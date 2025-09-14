defmodule FlashwarsWeb.StudySetLive.Test do
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
      # Group this test session under a single attempt
      now = DateTime.utc_now()
      attempt =
        Learning.create_attempt!(
          %{mode: :test, study_set_id: set.id, started_at: now},
          actor: actor
        )

      items =
        Engine.generate_test(actor, set.id,
          size: 8,
          types: [:multiple_choice, :true_false],
          smart: true
        )

      {:ok,
       socket
       |> assign(:page_title, "Test · #{set.name}")
       |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
       |> assign(:study_set, set)
       |> assign(:attempt_id, attempt.id)
        |> assign(:items, items)
        |> assign(:index, 0)
        |> assign(:score, 0)
        |> assign(:answered?, false)
        |> assign(:correct?, nil)}
    else
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def handle_event("answer", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    item = current_item(socket)

    correct? = idx == item.answer_index
    answer_text = Enum.at(item.choices, idx)

    _ =
      if item[:term_id] do
        grade = if correct?, do: :good, else: :again

        {:ok, _} =
          Learning.review(socket.assigns.current_user, item.term_id, grade,
            answer: answer_text,
            queue_type: :review,
            attempt_id: socket.assigns[:attempt_id]
          )
      end

    # Update score locally
    new_score = socket.assigns.score + if(correct?, do: 10, else: 0)

    {:noreply,
     socket
     |> assign(:answered?, true)
     |> assign(:correct?, correct?)
     |> assign(:score, new_score)}
  end

  def handle_event("next", _params, socket) do
    new_index = socket.assigns.index + 1

    # Advance to next question

    {:noreply,
     socket
     |> assign(:index, new_index)
     |> assign(:answered?, false)
     |> assign(:correct?, nil)}
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

  defp current_item(socket) do
    Enum.at(socket.assigns.items, socket.assigns.index)
  end

  # Minimal session state persisted via default_state(:test)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        Test: {@study_set.name}
        <:subtitle>Answer mixed questions</:subtitle>
        <:actions>
          <.button phx-click="create_duel" variant="primary">Create Duel</.button>
        </:actions>
      </.header>

      <div class="flex items-center justify-between mb-2">
        <div class="badge">Score: {@score}</div>
        <div class="text-sm opacity-70">
          Q {@index + 1} / {length(@items)}
        </div>
      </div>

      <%= if @index >= length(@items) do %>
        <div class="card bg-base-200">
          <div class="card-body items-center">
            <h3 class="card-title">Test Complete</h3>
            <p>Final Score: {@score}</p>
          </div>
        </div>
      <% else %>
        <% item = Enum.at(@items, @index) %>
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="text-sm opacity-70">Question</div>
            <h3 class="text-xl font-semibold">{item.prompt}</h3>

            <div class="mt-4 grid grid-cols-1 gap-2">
              <button
                :for={{choice, idx} <- Enum.with_index(item.choices)}
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
                Incorrect. Answer: {Enum.at(item.choices, item.answer_index)}
              </div>
              <button class="btn btn-primary mt-3" phx-click="next">Next</button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
