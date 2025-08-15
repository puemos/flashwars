defmodule FlashwarsWeb.StudySetLive.Flashcards do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  alias Flashwars.Learning
  alias Flashwars.Learning.Engine

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(%{"id" => set_id}, _session, socket) do
    actor = socket.assigns.current_user

    with {:ok, set} <- Content.get_study_set_by_id(set_id, actor: actor) do
      card = Engine.generate_flashcard(actor, set.id, order: :smart)

      {:ok,
       socket
       |> assign(:page_title, "Flashcards · #{set.name}")
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:exclude_term_ids, MapSet.new())
       |> assign(:card, card)
       |> assign(:revealed?, false)}
    else
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def handle_event("reveal", _params, socket) do
    {:noreply, assign(socket, :revealed?, true)}
  end

  def handle_event("grade", %{"grade" => grade}, socket) do
    card = socket.assigns.card

    _ =
      if card.term_id do
        grade_atom = String.to_existing_atom(grade)

        {:ok, _} =
          Learning.review(socket.assigns.current_user, card.term_id, grade_atom,
            queue_type: :review
          )
      end

    exclude =
      if card.term_id,
        do: MapSet.put(socket.assigns.exclude_term_ids, card.term_id),
        else: socket.assigns.exclude_term_ids

    set = socket.assigns.study_set
    actor = socket.assigns.current_user

    next =
      Engine.generate_flashcard(actor, set.id,
        order: :smart,
        exclude_term_ids: MapSet.to_list(exclude)
      )

    {:noreply,
     socket
     |> assign(:card, next)
     |> assign(:revealed?, false)
     |> assign(:exclude_term_ids, exclude)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        Flashcards: {@study_set.name}
        <:subtitle>Reveal the answer, then grade yourself</:subtitle>
      </.header>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="text-sm opacity-70">Term</div>
          <h3 class="text-2xl font-semibold">{@card.front}</h3>

          <div :if={@revealed?} class="mt-4">
            <div class="text-sm opacity-70">Definition</div>
            <div class="p-3 rounded bg-base-100">{@card.back}</div>
          </div>

          <div class="mt-6 flex gap-2">
            <button :if={!@revealed?} class="btn btn-primary" phx-click="reveal">Show Answer</button>
            <div :if={@revealed?} class="flex gap-2">
              <button class="btn" phx-click="grade" phx-value-grade="again">Again</button>
              <button class="btn" phx-click="grade" phx-value-grade="hard">Hard</button>
              <button class="btn" phx-click="grade" phx-value-grade="good">Good</button>
              <button class="btn" phx-click="grade" phx-value-grade="easy">Easy</button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
