defmodule FlashwarsWeb.StudySetLive.Show do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  alias Flashwars.Content.StudySet
  alias Flashwars.Learning
  alias Flashwars.Learning.Engine
  alias Flashwars.Games
  import Phoenix.Component
  alias FlashwarsWeb.Components.SwipeDeckComponent

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_admin}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    with {:ok, set} <- Content.get_study_set_by_id(id, actor: socket.assigns.current_user),
         {:ok, terms} <- read_terms(set, socket.assigns.current_user) do
      # Compact study preview uses the same generator as Flashcards
      cards =
        generate_initial_cards(socket.assigns.current_user, set.id, 10)

      form = to_form(%{"term" => "", "definition" => ""}, as: :term)
      bulk_form = to_form(%{"csv" => ""}, as: :bulk)
      mastery_map = mastery_map(socket.assigns.current_user, set.id)

      # Pre-calculate mastery counts to avoid stream enumeration
      mastery_counts =
        terms
        |> Enum.group_by(fn term -> mastery_map[term.id] || :unseen end)
        |> Map.new(fn {status, terms} -> {status, length(terms)} end)

      {:ok,
       socket
       |> assign(:page_title, set.name)
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:terms_count, length(terms))
       |> assign(:form, form)
       |> assign(:bulk_form, bulk_form)
       |> assign(:editing_id, nil)
       |> assign(:edit_form, nil)
       |> assign(:mastery_map, mastery_map)
       |> assign(:mastery_counts, mastery_counts)
       |> assign(:next_position, length(terms) + 1)
       |> assign(:cards, cards)
       |> assign(:cards_completed, 0)
       |> assign(:exclude_term_ids, MapSet.new())
       |> assign(:share_open, false)
       |> assign(:status_filter, :all)
       |> stream(:terms, terms)}
    else
      _ -> {:ok, redirect(socket, to: ~p"/")}
    end
  end

  # =============================
  # Study preview interactions
  # =============================
  @impl true
  def handle_info(
        {:swipe_event, %{direction: direction, item: card, component_id: "preview-deck"}},
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
     |> assign(:cards_completed, cards_completed)}
  end

  # Handle request for new card from the SwipeDeckComponent
  def handle_info({:request_new_card, %{component_id: "preview-deck", count: count}}, socket) do
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

  def handle_info({:deck_empty, %{total_swiped: _total, component_id: "preview-deck"}}, socket) do
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

  # =============================
  # Existing term management & settings (inline editing + filter)
  # =============================
  @impl true
  def handle_event("add", %{"term" => params}, socket) do
    params =
      params
      |> Map.put_new("study_set_id", socket.assigns.study_set.id)
      |> Map.put_new("position", socket.assigns.next_position)

    case Content.create_term(params, actor: socket.assigns.current_user) do
      {:ok, term} ->
        {:noreply,
         socket
         |> stream_insert(:terms, term)
         |> assign(:next_position, socket.assigns.next_position + 1)
         |> assign(:terms_count, socket.assigns.terms_count + 1)
         |> assign(:form, to_form(%{"term" => "", "definition" => ""}, as: :term))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not add term")}
    end
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    case Content.get_term_by_id(id, actor: socket.assigns.current_user) do
      {:ok, term} ->
        edit_form = to_form(%{"term" => term.term, "definition" => term.definition}, as: :edit)

        {:noreply,
         socket
         |> assign(:editing_id, id)
         |> assign(:edit_form, edit_form)
         |> stream_insert(:terms, term)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", params, socket) do
    socket = socket |> assign(:editing_id, nil) |> assign(:edit_form, nil)

    case params do
      %{"id" => id} ->
        case Content.get_term_by_id(id, actor: socket.assigns.current_user) do
          {:ok, term} -> {:noreply, stream_insert(socket, :terms, term)}
          _ -> {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_edit", %{"edit" => params, "_row_id" => id}, socket) do
    with {:ok, term} <- Content.get_term_by_id(id, actor: socket.assigns.current_user),
         {:ok, _updated} <-
           Content.update_term(
             term,
             %{term: params["term"], definition: params["definition"]},
             actor: socket.assigns.current_user
           ),
         {:ok, refreshed} <- read_terms(socket.assigns.study_set, socket.assigns.current_user) do
      {:noreply,
       socket
       |> stream(:terms, refreshed, reset: true)
       |> assign(:editing_id, nil)
       |> assign(:edit_form, nil)
       |> put_flash(:info, "Updated")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update term")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, term} <- Content.get_term_by_id(id, actor: socket.assigns.current_user),
         {:ok, _} <- Content.destroy_term(term, actor: socket.assigns.current_user),
         {:ok, refreshed} <- read_terms(socket.assigns.study_set, socket.assigns.current_user) do
      {:noreply,
       socket
       |> stream(:terms, refreshed, reset: true)
       |> assign(:next_position, max(socket.assigns.next_position - 1, 1))
       |> assign(:terms_count, max(socket.assigns.terms_count - 1, 0))
       |> put_flash(:info, "Deleted")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete term")}
    end
  end

  @impl true
  def handle_event("bulk_add", %{"bulk" => %{"csv" => csv}}, socket) do
    # Use real newline characters; accept CRLF/CR/LF
    lines =
      csv
      |> String.split(~r/\r\n|\n|\r/, trim: true)

    {created, _errors} =
      Enum.reduce(lines, {[], []}, fn line, {acc, errs} ->
        case parse_csv_line(line) do
          {t0, d0} ->
            t = String.trim(t0 || "")
            d = String.trim(d0 || "")

            if t != "" and d != "" do
              params = %{
                "term" => t,
                "definition" => d,
                "study_set_id" => socket.assigns.study_set.id,
                "position" => socket.assigns.next_position + length(acc)
              }

              case Content.create_term(params, actor: socket.assigns.current_user) do
                {:ok, term} -> {[term | acc], errs}
                {:error, e} -> {acc, [e | errs]}
              end
            else
              {acc, errs}
            end
        end
      end)

    terms = Enum.reverse(created)

    {:noreply,
     socket
     |> stream(:terms, terms)
     |> assign(:next_position, socket.assigns.next_position + length(terms))
     |> assign(:terms_count, socket.assigns.terms_count + length(terms))
     |> assign(:bulk_form, to_form(%{"csv" => ""}, as: :bulk))
     |> put_flash(:info, "Added #{length(terms)} terms")}
  end

  @impl true
  def handle_event("refresh_mastery", _params, socket) do
    mm = mastery_map(socket.assigns.current_user, socket.assigns.study_set.id)
    {:noreply, assign(socket, :mastery_map, mm)}
  end

  @impl true
  def handle_event("save_privacy", %{"set" => %{"privacy" => priv}}, socket) do
    with {:ok, set} <-
           Content.get_study_set_by_id(socket.assigns.study_set.id,
             actor: socket.assigns.current_user
           ),
         {:ok, updated} <-
           Content.update_study_set(
             set,
             %{privacy: String.to_existing_atom(priv)},
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign(:study_set, updated)
       |> put_flash(:info, "Settings saved")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not save settings")}
    end
  end

  @impl true
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

  # Modal open/close
  @impl true
  def handle_event("open_share", _params, socket) do
    {:noreply, assign(socket, :share_open, true)}
  end

  @impl true
  def handle_event("close_share", _params, socket) do
    {:noreply, assign(socket, :share_open, false)}
  end

  # Filter by mastery status
  @impl true
  def handle_event("set_filter", %{"status" => status}, socket) do
    status_atom = if(status == "all", do: :all, else: String.to_existing_atom(status))
    {:noreply, assign(socket, :status_filter, status_atom)}
  end

  # Silence phx-change="noop" events from the inline edit form
  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("copied", _params, socket), do: {:noreply, put_flash(socket, :info, "Copied!")}

  # =============================
  # Helpers
  # =============================
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

  defp format_privacy(:public), do: "Public"
  defp format_privacy(:private), do: "Private"
  defp format_privacy(:link_only), do: "Private"

  defp status_match?(:all, _), do: true
  defp status_match?(status, status), do: true
  defp status_match?(_needed, _actual), do: false

  defp read_terms(%StudySet{id: id}, actor) do
    Content.list_terms_for_study_set(%{study_set_id: id}, actor: actor)
  end

  defp mastery_map(nil, _set_id), do: %{}
  defp mastery_map(_user, nil), do: %{}

  defp mastery_map(user, set_id) do
    res = Learning.mastery_for_set(user, set_id)

    %{}
    |> Map.merge(Map.new(res.mastered, &{&1.term_id, :mastered}))
    |> Map.merge(Map.new(res.struggling, &{&1.term_id, :struggling}))
    |> Map.merge(Map.new(res.practicing, &{&1.term_id, :practicing}))
    |> Map.merge(Map.new(res.unseen, &{&1.term_id, :unseen}))
  end

  # Accepts: term,definition
  #          "term",definition
  #          term,"definition, with, commas"
  defp parse_csv_line(line) do
    trimmed = String.trim(line)

    # Optional quotes around fields; greedy-ish second field to keep commas
    case Regex.run(~r/^\s*"?([^"]*)"?\s*,\s*"?(.+?)"?\s*$/, trimmed) do
      [_, term, defn] ->
        {term, defn}

      _ ->
        case String.split(trimmed, ",", parts: 2) do
          [t, d] -> {t, d}
          _ -> {"", ""}
        end
    end
  end

  # =============================
  # Render
  # =============================
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <!-- Header with privacy + count -->
      <.header>
        <span class="inline-flex items-center gap-2">
          {@study_set.name}
          <span class="opacity-70 text-xs">• {@terms_count} terms</span>
          <span class="badge">{format_privacy(@study_set.privacy)}</span>
        </span>
        <:actions>
          <div class="flex gap-2">
            <.button phx-click="open_share" class="btn">Share</.button>
          </div>
        </:actions>
      </.header>
      
    <!-- Share Modal -->
      <div
        :if={@share_open}
        id="share-modal"
        class="fixed inset-0 z-50 flex items-center justify-center"
        phx-window-keydown="close_share"
        phx-key="escape"
      >
        <!-- Backdrop -->
        <div class="absolute inset-0 bg-black/60" phx-click="close_share"></div>
        
    <!-- Dialog -->
        <div class="relative w-full max-w-xl rounded-2xl bg-base-100 p-6 shadow-xl">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold">Share settings</h3>
            <button class="btn btn-sm btn-ghost" phx-click="close_share">✕</button>
          </div>

          <div class="space-y-4">
            <.form
              for={to_form(%{}, as: :set)}
              id="set-privacy-form"
              phx-submit="save_privacy"
              class="flex items-center gap-2"
            >
              <.input
                name="set[privacy]"
                type="select"
                value={Atom.to_string(@study_set.privacy)}
                options={[
                  {"Private", "private"},
                  {"Link only", "link_only"},
                  {"Public", "public"}
                ]}
                class="select min-w-[160px]"
              />
              <.button class="btn mb-2">Save</.button>
            </.form>

            <div :if={@study_set.privacy == :link_only} class="">
              <label class="text-sm font-medium mb-2 block">Shareable link</label>
              <% share_link =
                FlashwarsWeb.Endpoint.url() <>
                  "/s/t/" <> to_string(@study_set.link_token || "") %>
              <div class="flex items-center gap-2">
                <input class="input w-full" readonly value={share_link} />
                <button
                  type="button"
                  class="btn"
                  id="copy-set-link"
                  phx-hook="CopyToClipboard"
                  data-text={share_link}
                >
                  Copy
                </button>
              </div>
              <p class="text-xs opacity-70 mt-2">
                Anyone with the link can view this set.
              </p>
            </div>

            <div :if={@study_set.privacy == :public} class="rounded-lg bg-base-200 p-4">
              <p class="text-sm">
                This set is public. It may be discoverable by others in your org.
              </p>
            </div>
          </div>

          <div class="flex justify-end mt-6">
            <button class="btn" phx-click="close_share">Close</button>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-12 gap-6">
        <!-- Sidebar -->


    <!-- Main content -->
        <main class="col-span-12 space-y-6">
          <div class="grid grid-cols-12 gap-6">
            <div class="col-span-full">
              <!-- Add Terms Forms -->
              <div class="grid grid-cols-2 gap-6">
                <!-- Compact study preview -->
                <div class="card bg-base-200/30 col-span-full">
                  <div class="card-body">
                    <h4 class="card-title">Study Preview</h4>
                    <p class="text-sm text-base-content/70 mb-4">
                      Quickly review a few cards. For the full experience, try one of the study modes below.
                    </p>
                    <.live_component
                      module={SwipeDeckComponent}
                      id="preview-deck"
                      items={format_cards_for_deck(@cards)}
                      directions={["left", "right", "up", "down"]}
                      stack_size={3}
                      keyboard={true}
                      haptics={true}
                    />
                  </div>
                </div>

                <div class="col-span-full grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                  <div class="card bg-base-200 border-3 border-base-300/50 hover:border-blue-200/30 transition-colors">
                    <div class="card-body p-6">
                      <div class="flex items-center gap-3 mb-3">
                        <div class="p-2 bg-blue-200/20 rounded-lg">
                          <.icon name="hero-academic-cap" class="size-6 text-blue-200/80" />
                        </div>
                        <h3 class="font-semibold text-base-content">Learn Mode</h3>
                      </div>
                      <p class="text-sm text-base-content/70 mb-4">
                        Interactive learning with immediate feedback
                      </p>
                      <div :if={@terms_count > 0} class="card-actions">
                        <.link
                          navigate={
                            ~p"/orgs/#{@current_scope.org_id}/study_sets/#{@study_set.id}/learn"
                          }
                          class="btn btn-sm"
                        >
                          Start Learning
                        </.link>
                      </div>
                    </div>
                  </div>

                  <div class="card bg-base-200 border-3 border-base-300/50 hover:border-fuchsia-200/30 transition-colors">
                    <div class="card-body p-6">
                      <div class="flex items-center gap-3 mb-3">
                        <div class="p-2 bg-fuchsia-200/20 rounded-lg">
                          <.icon name="hero-rectangle-stack" class="size-6 text-fuchsia-200/80" />
                        </div>
                        <h3 class="font-semibold text-base-content">Flashcards</h3>
                      </div>
                      <p class="text-sm text-base-content/70 mb-4">Classic flip-card study method</p>
                      <div :if={@terms_count > 0} class="card-actions">
                        <.link
                          navigate={
                            ~p"/orgs/#{@current_scope.org_id}/study_sets/#{@study_set.id}/flashcards"
                          }
                          class="btn btn-sm"
                        >
                          Review Cards
                        </.link>
                      </div>
                    </div>
                  </div>

                  <div class="card bg-base-200 border-3 border-base-300/50 hover:border-emerald-200/30 transition-colors">
                    <div class="card-body p-6">
                      <div class="flex items-center gap-3 mb-3">
                        <div class="p-2 bg-emerald-200/20 rounded-lg">
                          <.icon name="hero-pencil-square" class="size-6 text-emerald-200/80" />
                        </div>
                        <h3 class="font-semibold text-base-content">Test Mode</h3>
                      </div>
                      <p class="text-sm text-base-content/70 mb-4">
                        Quiz yourself and track progress
                      </p>
                      <div :if={@terms_count > 0} class="card-actions">
                        <.link
                          navigate={
                            ~p"/orgs/#{@current_scope.org_id}/study_sets/#{@study_set.id}/test"
                          }
                          class="btn btn-sm"
                        >
                          Take Test
                        </.link>
                      </div>
                    </div>
                  </div>

                  <div class="card bg-base-200 border-3 border-base-300/50 hover:border-amber-200/30 transition-colors">
                    <div class="card-body p-6">
                      <div class="flex items-center gap-3 mb-3">
                        <div class="p-2 bg-amber-200/20 rounded-lg">
                          <.icon name="hero-bolt" class="size-6 text-amber-200/80" />
                        </div>
                        <h3 class="font-semibold text-base-content">Duel Mode</h3>
                      </div>
                      <p class="text-sm text-base-content/70 mb-4">Challenge others in real-time</p>
                      <div :if={@terms_count > 0} class="card-actions">
                        <button
                          type="button"
                          class="btn btn-sm"
                          phx-click="create_duel"
                        >
                          Create Duel
                        </button>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="card bg-base-200">
                  <div class="card-body">
                    <h4 class="font-semibold">Add Single</h4>
                    <.form for={@form} id="term-form" phx-submit="add">
                      <.input field={@form[:term]} type="text" label="Term" required />
                      <.input field={@form[:definition]} type="textarea" label="Definition" required />
                      <div class="flex justify-end">
                        <.button class="btn btn-primary">Add</.button>
                      </div>
                    </.form>
                  </div>
                </div>

                <div class="card bg-base-200">
                  <div class="card-body">
                    <h4 class="font-semibold">Bulk Add (CSV)</h4>
                    <h5 class="text-xs opacity-70">One per line, format: term,definition</h5>
                    <.form for={@bulk_form} id="bulk-form" phx-submit="bulk_add" class="flex-grow">
                      <.input field={@bulk_form[:csv]} type="textarea" />
                      <div class="flex justify-end">
                        <.button class="btn">Add CSV</.button>
                      </div>
                    </.form>
                  </div>
                </div>
                <!-- Terms Management -->
                <div id="terms" class="card bg-base-200 col-span-full">
                  <div class="card-body">
                    <div class="flex items-center justify-between mb-6">
                      <div class="flex items-center gap-4">
                        <h4 class="font-semibold">Terms</h4>
                        <div class="flex items-center gap-2 text-sm">
                          <% statuses = [:mastered, :practicing, :struggling, :unseen] %>
                          <span :for={status <- statuses} class="flex items-center gap-1">
                            <%= if (@mastery_counts[status] || 0) > 0 do %>
                              <span class={[
                                "inline-block w-2 h-2 rounded-full",
                                status == :mastered && "bg-success",
                                status == :struggling && "bg-error",
                                status == :practicing && "bg-warning",
                                status == :unseen && "bg-base-content opacity-50"
                              ]}>
                              </span>
                              <span class="opacity-70">{@mastery_counts[status]} {status}</span>
                            <% end %>
                          </span>
                        </div>
                      </div>
                      <div class="flex items-center gap-2">
                        <label class="text-sm opacity-70">Filter</label>
                        <.form for={to_form(%{}, as: :f)} phx-change="set_filter">
                          <select name="status" class="select select-sm">
                            <option value="all" selected={@status_filter == :all}>All</option>
                            <option value="mastered" selected={@status_filter == :mastered}>
                              Mastered
                            </option>
                            <option value="practicing" selected={@status_filter == :practicing}>
                              Practicing
                            </option>
                            <option value="struggling" selected={@status_filter == :struggling}>
                              Struggling
                            </option>
                            <option value="unseen" selected={@status_filter == :unseen}>
                              Unseen
                            </option>
                          </select>
                        </.form>
                        <button class="btn btn-ghost btn-sm" phx-click="refresh_mastery">
                          Refresh Expertise
                        </button>
                      </div>
                    </div>

                    <div class="overflow-x-auto">
                      <table class="table table-hover mb-2 w-full">
                        <thead>
                          <tr>
                            <th>Term</th>
                            <th>Definition</th>
                            <th class="w-48 text-right">Actions</th>
                          </tr>
                        </thead>
                        <tbody id="term-rows" phx-update="stream">
                          <tr
                            :for={{dom_id, t} <- @streams.terms}
                            :if={status_match?(@status_filter, @mastery_map[t.id] || :unseen)}
                            id={dom_id}
                          >
                            <td>
                              <div :if={@editing_id != t.id}>{t.term}</div>
                              <.input
                                :if={@editing_id == t.id}
                                field={@edit_form[:term]}
                                type="textarea"
                                form={"edit-row-#{t.id}-form"}
                              />
                            </td>

                            <td>
                              <div :if={@editing_id != t.id}>{t.definition}</div>
                              <.input
                                :if={@editing_id == t.id}
                                field={@edit_form[:definition]}
                                type="textarea"
                                form={"edit-row-#{t.id}-form"}
                              />
                            </td>

                            <td class="text-right">
                              <div :if={@editing_id != t.id} class="flex gap-2 justify-end">
                                <button
                                  class="btn btn-sm btn-ghost min-w-[80px]"
                                  phx-click="edit"
                                  phx-value-id={t.id}
                                >
                                  Edit
                                </button>
                                <button
                                  class="btn btn-sm btn-error min-w-[80px]"
                                  phx-click="delete"
                                  phx-value-id={t.id}
                                >
                                  Delete
                                </button>
                              </div>

                              <div :if={@editing_id == t.id} class="flex gap-2 justify-end">
                                <.form
                                  for={@edit_form}
                                  id={"edit-row-#{t.id}-form"}
                                  phx-submit="save_edit"
                                  phx-change="noop"
                                >
                                  <input type="hidden" name="_row_id" value={t.id} />
                                  <.button class="btn btn-primary btn-sm min-w-[80px]">Save</.button>
                                  <button
                                    type="button"
                                    class="btn btn-ghost btn-sm min-w-[80px]"
                                    phx-click="cancel_edit"
                                    phx-value-id={t.id}
                                  >
                                    Cancel
                                  </button>
                                </.form>
                              </div>
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end
end
