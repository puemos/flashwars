defmodule FlashwarsWeb.StudySetLive.Flashcards do
  use FlashwarsWeb, :live_view
  alias Flashwars.Content
  alias Flashwars.Learning
  alias Flashwars.Learning.Engine
  alias Flashwars.Games
  alias FlashwarsWeb.Components.SwipeDeckComponent

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(%{"id" => set_id}, _session, socket) do
    actor = socket.assigns.current_user

    with {:ok, set} <- Content.get_study_set_by_id(set_id, actor: actor) do
      # Generate initial small batch of flashcards (just 3 to fill the stack)
      cards = generate_initial_cards(actor, set.id, 10)

      {:ok,
       socket
       |> assign(:page_title, "Flashcards · #{set.name}")
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:exclude_term_ids, MapSet.new())
       |> assign(:cards, cards)
       |> assign(:cards_completed, 0)}
    else
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  # Handle swipe events from the SwipeDeckComponent
  def handle_info(
        {:swipe_event, %{direction: direction, item: card, component_id: "flashcard-deck"}},
        socket
      ) do
    # Map swipe directions to grades
    grade =
      case direction do
        "left" -> :again
        "down" -> :hard
        "right" -> :good
        "up" -> :easy
        _ -> :good
      end

    # Process the grade
    _ =
      if card.term_id do
        {:ok, _} =
          Learning.review(socket.assigns.current_user, card.term_id, grade, queue_type: :review)
      end

    # Update exclude list
    exclude =
      if card.term_id do
        MapSet.put(socket.assigns.exclude_term_ids, card.term_id)
      else
        socket.assigns.exclude_term_ids
      end

    # Update cards completed counter
    cards_completed = socket.assigns.cards_completed + 1

    {:noreply,
     socket
     |> assign(:exclude_term_ids, exclude)
     |> assign(:cards_completed, cards_completed)
     |> put_flash(:info, "Graded as #{format_grade(grade)}")}
  end

  # Handle request for new card from the SwipeDeckComponent
  def handle_info({:request_new_card, %{component_id: "flashcard-deck", count: count}}, socket) do
    actor = socket.assigns.current_user
    set = socket.assigns.study_set

    base_exclude =
      socket.assigns.exclude_term_ids
      |> MapSet.to_list()
      |> Kernel.++(socket.assigns.cards |> Enum.map(& &1.term_id) |> Enum.reject(&is_nil/1))

    requested =
      case count do
        nil -> 1
        c when is_integer(c) and c > 0 -> c
        _ -> 1
      end

    # Generate a batch of new cards (may be fewer if exhausted)
    new_cards = generate_initial_cards(actor, set.id, requested, exclude_term_ids: base_exclude)

    cond do
      new_cards == [] ->
        {:noreply, put_flash(socket, :info, "No more cards available!")}

      true ->
        formatted = Enum.map(new_cards, &format_card_for_deck/1)

        {:noreply,
         socket
         |> push_event("add_cards", %{cards: formatted})
         |> assign(:cards, socket.assigns.cards ++ new_cards)}
    end
  end

  def handle_info({:deck_empty, %{total_swiped: _total, component_id: "flashcard-deck"}}, socket) do
    actor = socket.assigns.current_user
    set = socket.assigns.study_set
    # Try to load a fresh batch automatically
    base_exclude =
      socket.assigns.exclude_term_ids
      |> MapSet.to_list()
      |> Kernel.++(socket.assigns.cards |> Enum.map(& &1.term_id) |> Enum.reject(&is_nil/1))

    new_cards = generate_initial_cards(actor, set.id, 10, exclude_term_ids: base_exclude)

    cond do
      new_cards == [] ->
        {:noreply, put_flash(socket, :info, "Deck completed! Great job studying.")}

      true ->
        formatted = Enum.map(new_cards, &format_card_for_deck/1)

        {:noreply,
         socket
         |> push_event("add_cards", %{cards: formatted})
         |> assign(:cards, socket.assigns.cards ++ new_cards)}
    end
  end

  def handle_event("create_duel", _params, socket) do
    actor = socket.assigns.current_user
    set = socket.assigns.study_set

    case Games.create_game_room(%{type: :duel, study_set_id: set.id, privacy: :private},
           actor: actor
         ) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/games/r/#{room.id}")}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, "Could not create duel: #{inspect(err)}")}
    end
  end

  def handle_event("toggle_swipe_mode", _params, socket) do
    # Allow users to toggle between swipe and traditional mode
    current_mode = socket.assigns[:swipe_mode] || true
    {:noreply, assign(socket, :swipe_mode, !current_mode)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        Flashcards: {@study_set.name}
        <:subtitle>
          Swipe or use arrow keys to grade yourself • {@cards_completed} cards completed
        </:subtitle>
        <:actions>
          <.button phx-click="create_duel" variant="primary">Create Duel</.button>
        </:actions>
      </.header>
      
    <!-- Study Progress -->
      <div class="stats shadow mb-6">
        <div class="stat">
          <div class="stat-title">Cards Studied</div>
          <div class="stat-value text-primary">{@cards_completed}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Remaining</div>
          <div class="stat-value">{length(@cards)}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Study Set</div>
          <div class="stat-value text-sm">{@study_set.name}</div>
        </div>
      </div>
      
    <!-- SwipeDeck Component -->
      <.live_component
        module={SwipeDeckComponent}
        id="flashcard-deck"
        items={format_cards_for_deck(@cards)}
        directions={["left", "right", "up", "down"]}
        stack_size={3}
        keyboard={true}
        haptics={true}
      />
    </Layouts.app>
    """
  end

  # Helper functions

  defp generate_initial_cards(actor, set_id, count, opts \\ []) do
    generate_initial_cards_acc(actor, set_id, count, opts, [])
  end

  defp generate_initial_cards_acc(_actor, _set_id, 0, _opts, acc), do: Enum.reverse(acc)

  defp generate_initial_cards_acc(actor, set_id, count, opts, acc) do
    # Get existing exclude list and add previously generated card term_ids
    base_exclude = Keyword.get(opts, :exclude_term_ids, [])
    used_term_ids = Enum.map(acc, & &1.term_id) |> Enum.reject(&is_nil/1)
    current_exclude = base_exclude ++ used_term_ids

    card =
      Engine.generate_flashcard(actor, set_id,
        order: :smart,
        exclude_term_ids: current_exclude
      )

    if card && card.term_id do
      generate_initial_cards_acc(actor, set_id, count - 1, opts, [card | acc])
    else
      # No more unique cards available
      Enum.reverse(acc)
    end
  end

  defp format_cards_for_deck(cards) do
    Enum.with_index(cards, fn card, index ->
      format_card_for_deck(card, index)
    end)
  end

  defp format_card_for_deck(card, index \\ 0) do
    %{
      id: card.term_id || "card-#{index}",
      front: card.front,
      back: card.back,
      card_type: "flashcard",
      term_id: card.term_id,
      type: "flashcard"
    }
  end

  defp format_grade(:again), do: "Again"
  defp format_grade(:hard), do: "Hard"
  defp format_grade(:good), do: "Good"
  defp format_grade(:easy), do: "Easy"
end
