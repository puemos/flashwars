defmodule FlashwarsWeb.StudySetLive.Learn do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  alias Flashwars.Learning
  alias Flashwars.Learning.Engine
  alias Flashwars.Games

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(%{"id" => set_id}, _session, socket) do
    actor = socket.assigns.current_user

    with {:ok, set} <- Content.get_study_set_by_id(set_id, actor: actor) do
      item = Engine.generate_item(set.id, exclude_term_ids: [])

      {:ok,
       socket
       |> assign(:page_title, "Learn · #{set.name}")
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:exclude_term_ids, MapSet.new())
       |> assign(:item, item)
       |> assign(:answered?, false)
       |> assign(:correct?, nil)
       |> assign(:answer_text, nil)}
    else
      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def handle_event("answer", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    item = socket.assigns.item

    correct? = idx == item.answer_index
    answer_text = Enum.at(item.choices, idx)

    # Log review and attempt item via Learning.review/4
    _ =
      if item.term_id do
        grade = if correct?, do: :good, else: :again

        {:ok, _} =
          Learning.review(socket.assigns.current_user, item.term_id, grade,
            answer: answer_text,
            queue_type: :review
          )
      end

    exclude =
      case item.term_id do
        nil -> socket.assigns.exclude_term_ids
        id -> MapSet.put(socket.assigns.exclude_term_ids, id)
      end

    {:noreply,
     socket
     |> assign(:answered?, true)
     |> assign(:correct?, correct?)
     |> assign(:answer_text, answer_text)
     |> assign(:exclude_term_ids, exclude)}
  end

  def handle_event("next", _params, socket) do
    set = socket.assigns.study_set
    exclude_ids = MapSet.to_list(socket.assigns.exclude_term_ids)
    item = Engine.generate_item(set.id, exclude_term_ids: exclude_ids)

    {:noreply,
     socket
     |> assign(:item, item)
     |> assign(:answered?, false)
     |> assign(:correct?, nil)
     |> assign(:answer_text, nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        Learn: {@study_set.name}
        <:subtitle>Multiple choice practice</:subtitle>
      </.header>

      <div class="space-y-4" id="learn-panel">
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="text-sm opacity-70">Question</div>
            <h3 class="text-xl font-semibold">{@item.prompt}</h3>

            <div class="mt-4 grid grid-cols-1 gap-2">
              <button
                :for={{choice, idx} <- Enum.with_index(@item.choices)}
                type="button"
                class="btn"
                data-choice-index={idx}
                phx-click="answer"
                phx-value-index={idx}
                disabled={@answered?}
              >
                {choice}
              </button>
            </div>

            <div :if={@answered?} class="mt-4">
              <div :if={@correct?} class="alert alert-success">Correct!</div>
              <div :if={!@correct?} class="alert alert-error">
                Incorrect. Answer: {Enum.at(@item.choices, @item.answer_index)}
              </div>
              <button id="next-btn" class="btn btn-primary mt-3" phx-click="next">Next</button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Duel creation moved to study set page (Org Home / Terms)
end
