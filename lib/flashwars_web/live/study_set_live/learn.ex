defmodule FlashwarsWeb.StudySetLive.Learn do
  use FlashwarsWeb, :live_view

  import Phoenix.Component

  alias Flashwars.Content
  alias Flashwars.Learning
  alias Flashwars.Learning.SessionManager
  alias FlashwarsWeb.QuizComponents, as: QC

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  # Configuration constants
  @review_timeout 5_000
  @segment_window 3

  # Type definitions for better documentation
  @type question_kind :: :multiple_choice | :true_false | :free_text | :matching
  @type interaction_state :: :idle | :wrong_attempt | :wrong_closed | :correct

  # ————————————————————————————————————————————————————————————————
  # Components
  # ————————————————————————————————————————————————————————————————

  attr :current_round, :integer, required: true
  attr :badge_value, :integer, required: true
  attr :fill_pct, :float, required: true
  attr :window, :integer, default: @segment_window
  attr :score, :string, default: nil

  defp progress_segments(assigns) do
    ~H"""
    <div class="relative flex items-center gap-2 select-none">
      <div class="flex gap-2">
        <% left_count = if @current_round > 1, do: 1, else: 0 %>
        <% right_count = max(@window - 1 - left_count, 0) %>
        
    <!-- Completed rounds -->
        <div :for={_ <- 1..left_count//1} class="relative h-2 w-24 rounded-full bg-slate-600">
          <div class="absolute inset-0 rounded-full bg-green-500"></div>
        </div>
        
    <!-- Current round with progress -->
        <div class="relative h-2 w-24 rounded-full bg-slate-600 overflow-visible">
          <div
            class="absolute left-0 top-0 h-full rounded-full bg-green-500 transition-all duration-300"
            style={"width: #{@fill_pct}%"}
          >
          </div>
          <!-- Badge showing current question number -->
          <div class="absolute -top-3 left-1/2 -translate-x-1/2 w-8 h-8 rounded-full bg-green-500 text-slate-900 text-xs font-bold flex items-center justify-center">
            {@badge_value}
          </div>
        </div>
        
    <!-- Future rounds -->
        <div :for={_ <- 1..right_count} class="relative h-2 w-24 rounded-full bg-slate-600"></div>
      </div>

      <div :if={@score} class="ml-auto px-3 py-1 rounded-full bg-slate-700 text-slate-200 text-sm">
        {@score}
      </div>
    </div>
    """
  end

  # ————————————————————————————————————————————————————————————————
  # Main Render
  # ————————————————————————————————————————————————————————————————

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.async_result :let={set} assign={@study_set}>
        <:loading>
          <.header>Learn: Loading…</.header>
          <div class="flex justify-center py-8">
            <div class="loading loading-spinner loading-lg"></div>
          </div>
        </:loading>

        <:failed :let={reason}>
          <.header>Learn</.header>
          <div class="alert alert-error mt-4">Failed to load study set: {inspect(reason)}</div>
        </:failed>

        <.header>
          Learn: {set.name}
          <:subtitle>Mixed practice</:subtitle>
          <:actions>
            <.button phx-click="restart" class="btn-sm">New Round</.button>
          </:actions>
        </.header>
        
    <!-- While session is initializing -->
        <div :if={!@session_state} class="flex justify-center py-8">
          <div class="loading loading-spinner loading-lg"></div>
        </div>

        <div :if={@session_state} id="learn-panel" class="space-y-4" phx-window-keydown="any_key">
          <!-- Progress visualization -->
          <div class="mt-2">
            <.progress_segments
              current_round={@round_number}
              badge_value={@round_position}
              fill_pct={round_fill_percentage(assigns)}
              score={"#{calculate_session_accuracy(@session_stats)}%"}
            />
          </div>

          <div class="card bg-base-200">
            <div class="card-body">
              <!-- Question header -->
              <div class="flex items-center justify-between">
                <div class="text-sm opacity-70 flex items-center gap-2">
                  <span class="uppercase tracking-wide">{prompt_label(@current_item)}</span>
                  <button type="button" class="btn btn-ghost btn-xs" aria-label="Play audio">
                    🔊
                  </button>
                </div>
                <div class="text-sm opacity-70">
                  Question {@round_position} / {length(@round_items)}
                </div>
              </div>
              
    <!-- Question prompt -->
              <h3 :if={@current_item[:prompt]} class="mt-2 text-2xl font-semibold">
                {@current_item[:prompt]}
              </h3>
              
    <!-- Status messages -->
              <div class="mt-3 min-h-[28px]">
                <%= case interaction_state(assigns) do %>
                  <% :idle -> %>
                    <div class="text-sm opacity-70">Choose an answer</div>
                  <% :wrong_attempt -> %>
                    <div class="text-sm text-orange-300">
                      Not quite. Try again, or <button
                        class="link link-hover text-orange-200"
                        phx-click="next"
                      >
                          Skip
                        </button>.
                    </div>
                  <% :wrong_closed -> %>
                    <div class="text-sm text-orange-300">
                      Incorrect — press Continue or any key to move on.
                    </div>
                  <% :correct -> %>
                    <div class="inline-flex items-center gap-2 text-sm text-green-300">
                      <span>👋</span>
                      <span>You're really getting this!</span>
                    </div>
                <% end %>
              </div>
              
    <!-- Answer interface -->
              <%= case @current_item[:kind] do %>
                <% "multiple_choice" -> %>
                  <QC.choices
                    choices={@current_item[:choices] || []}
                    selected_index={get_in(assigns, [:reveal, :selected_index])}
                    correct_index={@current_item[:answer_index]}
                    immediate_response={true}
                    round_closed?={@answered?}
                    answered?={@answered?}
                  />
                <% "true_false" -> %>
                  <QC.true_false
                    definition={@current_item[:definition]}
                    selected_index={get_in(assigns, [:reveal, :selected_index])}
                    correct_index={@current_item[:answer_index]}
                    immediate_response={true}
                    round_closed?={@answered?}
                    answered?={@answered?}
                  />
                <% "free_text" -> %>
                  <QC.free_text
                    reveal={@reveal}
                    round_closed?={@answered?}
                    answered?={@answered?}
                  />
                <% "matching" -> %>
                  <QC.matching
                    left={@current_item[:left]}
                    right={@current_item[:right]}
                    pairs={@pairs}
                    selected_left={@selected_left}
                    selected_right={@selected_right}
                    reveal={@reveal}
                    round_closed?={@answered?}
                    answered?={@answered?}
                  />
                <% _ -> %>
                  <div class="h-28 rounded-xl bg-base-300/40 animate-pulse"></div>
              <% end %>
              
    <!-- Utility actions -->
              <div class="mt-3 flex items-center justify-end gap-3">
                <button
                  :if={
                    @current_item[:kind] in ["multiple_choice", "true_false"] and
                      interaction_state(assigns) in [:idle, :wrong_attempt]
                  }
                  phx-click="dont_know"
                  class="link link-hover text-sm opacity-80"
                >
                  Don't know?
                </button>
              </div>
              
    <!-- Feedback and continue section -->
              <div :if={@answered?} class="mt-4 space-y-3">
                <div :if={@correct?} class="alert alert-success">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="stroke-current shrink-0 h-6 w-6"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span>Correct!</span>
                </div>

                <div
                  :if={not @correct? and @current_item[:kind] in ["multiple_choice", "true_false"]}
                  class="alert alert-error"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="stroke-current shrink-0 h-6 w-6"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span>Incorrect.</span>
                </div>

                <div
                  :if={not @correct? and @current_item[:kind] == "free_text"}
                  class="alert alert-error"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="stroke-current shrink-0 h-6 w-6"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span>Incorrect. Answer: {@current_item[:answer_text]}</span>
                </div>

                <.button id="next-btn" class="btn-primary" phx-click="next">
                  Continue
                </.button>
              </div>
            </div>
          </div>
          
    <!-- Keyboard hint -->
          <div :if={@answered?} class="text-center text-sm opacity-70">
            Press any key or Continue to move on
          </div>
        </div>
      </.async_result>
    </Layouts.app>
    """
  end

  # ————————————————————————————————————————————————————
  # Lifecycle
  # ————————————————————————————————————————————————————————————————

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(60_000, self(), :heartbeat)
    end

    socket =
      socket
      |> assign(:page_title, "Learn")
      |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
      |> assign(:loading?, true)
      |> assign(:error, nil)
      |> assign(:session_state, nil)
      |> assign_empty_session_ui()

    {:ok, socket, temporary_assigns: [flash: %{}]}
  end

  @impl true
  def handle_params(%{"id" => set_id}, _uri, socket) when byte_size(set_id) > 0 do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:page_title, "Learn")
     # Load the study set as an AsyncResult
     |> assign_async(:study_set, fn ->
       case Content.get_study_set_by_id(set_id, actor: user) do
         {:ok, set} when not is_nil(set) -> {:ok, %{study_set: set}}
         {:ok, nil} -> {:error, :not_found}
         {:error, reason} -> {:error, reason}
       end
     end)
     # Initialize the session as a background task
     |> start_async(:init_session, fn ->
       case SessionManager.initialize_session(user, set_id, :learn) do
         {:ok, state} -> {:ok, state}
         {:error, :no_items} -> {:ok, create_empty_session()}
         {:error, reason} -> {:error, reason}
       end
     end)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:loading?, false)
     |> assign(:error, "Invalid study set ID")
     |> push_navigate(to: ~p"/")}
  end

  @impl true
  def handle_info(:heartbeat, socket) do
    if socket.assigns[:study_set] && socket.assigns[:session_state] do
      Task.start(fn ->
        SessionManager.save_session(
          socket.assigns.current_user,
          study_set_id(socket.assigns),
          :learn,
          socket.assigns.session_state
        )
      end)
    end

    {:noreply, socket}
  end

  # Keep this for backward-compat in case anything still sends this message
  def handle_info({:review_complete, term_id, result}, socket) do
    Phoenix.PubSub.broadcast(
      Flashwars.PubSub,
      "user:#{socket.assigns.current_user.id}",
      {:learning_progress, term_id, result}
    )

    {:noreply, socket}
  end

  # ————————————————————————————————————————————————————————————————
  # Async task handlers
  # ————————————————————————————————————————————————————————————————

  @impl true
  def handle_async(:init_session, {:ok, {:ok, session_state}}, socket) do
    socket =
      socket
      |> assign(:error, nil)
      |> assign(:page_title, page_title_with_name(socket.assigns[:study_set]))
      |> assign(:loading?, false)
      |> assign(:session_state, session_state)
      |> assign_session_ui_state(session_state)
      |> reset_interaction_state()

    {:noreply, socket}
  end

  def handle_async(:init_session, {:error, :not_found}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Study set not found")
     |> push_navigate(to: ~p"/")}
  end

  def handle_async(:init_session, {:error, _reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "An error occurred starting the session")
     |> push_navigate(to: ~p"/")}
  end

  # Review (shared tag for both sync/async answer paths)
  @impl true
  def handle_async({:review, term_id}, {:ok, result}, socket) do
    Phoenix.PubSub.broadcast(
      Flashwars.PubSub,
      "user:#{socket.assigns.current_user.id}",
      {:learning_progress, term_id, result}
    )

    {:noreply, socket}
  end

  def handle_async({:review, _term_id}, {:error, error}, socket) do
    require Logger
    Logger.error("Review failed: #{inspect(error)}")
    {:noreply, socket}
  end

  # ————————————————————————————————————————————————————————————————
  # Session Management
  # ————————————————————————————————————————————————————————————————

  defp assign_session_ui_state(socket, session_state) do
    socket
    |> assign(:round_items, session_state[:round_items])
    |> assign(:round_index, session_state[:round_index])
    |> assign(:round_number, session_state[:round_number])
    |> assign(:round_correct_count, session_state[:round_correct_count])
    |> assign(:round_position, session_state[:round_position])
    |> assign(:current_item, session_state[:current_item])
    |> assign(:session_stats, session_state[:session_stats])
  end

  defp assign_empty_session_ui(socket) do
    socket
    |> assign(:round_items, [])
    |> assign(:round_index, 0)
    |> assign(:round_number, 1)
    |> assign(:round_correct_count, 0)
    |> assign(:round_position, 1)
    |> assign(:current_item, SessionManager.create_empty_item())
    |> assign(:session_stats, %{total_correct: 0, total_questions: 0})
  end

  defp create_empty_session do
    %{
      round_items: [],
      round_index: 0,
      round_number: 1,
      round_correct_count: 0,
      round_position: 1,
      current_item: SessionManager.create_empty_item(),
      session_stats: %{total_correct: 0, total_questions: 0},
      mode: :learn
    }
  end

  # ————————————————————————————————————————————————————————————————
  # State Management
  # ————————————————————————————————————————————————————————————————

  defp reset_interaction_state(socket) do
    socket
    |> assign(:answered?, false)
    |> assign(:reveal, nil)
    |> assign(:correct?, nil)
    |> assign(:answer_text, nil)
    |> assign(:pairs, [])
    |> assign(:selected_left, nil)
    |> assign(:selected_right, nil)
    |> assign(:last_wrong_index, nil)
  end

  defp advance_question(socket) do
    session_state = socket.assigns.session_state

    case SessionManager.advance_session(session_state) do
      {:advance_in_round, new_state} ->
        socket
        |> assign(:session_state, new_state)
        |> assign_session_ui_state(new_state)
        |> reset_interaction_state()

      {:start_new_round, state} ->
        case SessionManager.start_new_round(
               state,
               socket.assigns.current_user,
               study_set_id(socket.assigns)
             ) do
          {:ok, new_state} ->
            socket
            |> assign(:session_state, new_state)
            |> assign_session_ui_state(new_state)
            |> reset_interaction_state()
            |> put_flash(:info, "New round started!")

          {:error, :no_items} ->
            socket
            |> put_flash(:error, "Unable to generate new round items")
        end
    end
  end

  # ————————————————————————————————————————————————————————————————
  # Event Handlers
  # ————————————————————————————————————————————————————————————————

  @impl true
  def handle_event("answer", %{"index" => idx_str}, socket) when is_binary(idx_str) do
    with {idx, ""} <- Integer.parse(idx_str),
         true <- idx >= 0,
         %{current_item: item} <- socket.assigns,
         true <- item.kind in ["multiple_choice", "true_false"],
         choices when is_list(choices) <- item[:choices],
         true <- idx < length(choices) do
      answer_text = Enum.at(choices, idx, "")
      correct? = idx == item.answer_index

      # Update session state
      session_state =
        socket.assigns.session_state
        |> SessionManager.update_session_stats(correct?)

      socket =
        socket
        |> assign(:session_state, session_state)
        |> assign(:session_stats, session_state.session_stats)
        |> handle_answer_result(item, correct?, answer_text, idx)

      {:noreply, socket}
    else
      _ ->
        require Logger
        Logger.warning("Invalid answer event: #{inspect(idx_str)}")
        {:noreply, socket}
    end
  end

  def handle_event("answer", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("answer_text", %{"answer" => %{"text" => text}}, socket)
      when is_binary(text) do
    %{current_item: item} = socket.assigns

    if item.kind == "free_text" do
      user_text = text |> to_string() |> String.trim()
      correct_text = item.answer_text |> to_string() |> String.trim()

      correct? =
        String.downcase(user_text) == String.downcase(correct_text) &&
          byte_size(correct_text) > 0

      socket = record_review_async(socket, item, correct?, user_text)

      # Update session state
      session_state =
        socket.assigns.session_state
        |> SessionManager.update_session_stats(correct?)

      socket =
        socket
        |> assign(:session_state, session_state)
        |> assign(:session_stats, session_state.session_stats)
        |> assign(:answered?, true)
        |> assign(:correct?, correct?)
        |> assign(:answer_text, user_text)
        |> assign(:reveal, %{user_text: user_text, correct_text: correct_text})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("answer_text", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("match_pick", %{"side" => side, "index" => idx_str}, socket) do
    with {idx, ""} <- Integer.parse(idx_str) do
      socket =
        case side do
          "left" -> assign(socket, :selected_left, idx)
          "right" -> assign(socket, :selected_right, idx)
          _ -> socket
        end

      socket = maybe_create_match_pair(socket)
      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_matches", _params, socket) do
    %{current_item: item, pairs: user_pairs} = socket.assigns

    if item.kind == "matching" do
      correct_pairs = item.answer_pairs || []
      user_pairs_reversed = Enum.reverse(user_pairs)
      correct? = MapSet.new(user_pairs_reversed) == MapSet.new(correct_pairs)

      socket = record_review(socket, item, correct?, inspect(user_pairs_reversed))

      # Update session state
      session_state =
        socket.assigns.session_state
        |> SessionManager.update_session_stats(correct?)

      socket =
        socket
        |> assign(:session_state, session_state)
        |> assign(:session_stats, session_state.session_stats)
        |> assign(:answered?, true)
        |> assign(:correct?, correct?)
        |> assign(:reveal, %{user_pairs: user_pairs_reversed, correct_pairs: correct_pairs})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next", _params, socket) do
    {:noreply, advance_question(socket)}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    user = socket.assigns.current_user
    set_id = study_set_id(socket.assigns)

    case set_id && SessionManager.create_new_session(user, set_id, :learn) do
      {:ok, session_state} ->
        socket =
          socket
          |> assign(:session_state, session_state)
          |> assign_session_ui_state(session_state)
          |> reset_interaction_state()
          |> put_flash(:info, "Starting new session!")

        {:noreply, socket}

      _ ->
        socket = put_flash(socket, :error, "Unable to start new session")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dont_know", _params, socket) do
    {:noreply, advance_question(socket)}
  end

  @impl true
  def handle_event("any_key", _params, socket) do
    if socket.assigns[:answered?] do
      {:noreply, advance_question(socket)}
    else
      {:noreply, socket}
    end
  end

  # ————————————————————————————————————————————————————————————————
  # Helper Functions
  # ————————————————————————————————————————————————————————————————

  @spec handle_answer_result(Phoenix.LiveView.Socket.t(), map(), boolean(), String.t(), integer()) ::
          Phoenix.LiveView.Socket.t()
  defp handle_answer_result(socket, item, correct?, answer_text, selected_idx) do
    socket = record_review_async(socket, item, correct?, answer_text)

    if correct? do
      # Update session state with correct answer
      session_state = SessionManager.mark_answer_correct(socket.assigns.session_state)

      socket =
        socket
        |> assign(:session_state, session_state)
        |> assign(:round_correct_count, session_state.round_correct_count)
        |> assign(:last_wrong_index, nil)

      advance_question(socket)
    else
      socket
      |> assign(:last_wrong_index, selected_idx)
      |> assign(:reveal, %{selected_index: selected_idx, correct_index: item.answer_index})
    end
  end

  # Start review as a LiveView async task (used for MC/TF + free text)
  @spec record_review_async(Phoenix.LiveView.Socket.t(), map(), boolean(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp record_review_async(socket, %{term_id: nil}, _correct?, _answer_text), do: socket

  defp record_review_async(socket, %{term_id: term_id}, correct?, answer_text) do
    grade = if correct?, do: :good, else: :again
    user = socket.assigns.current_user

    start_async(socket, {:review, term_id}, fn ->
      Learning.review(
        user,
        term_id,
        grade,
        answer: answer_text,
        queue_type: :review,
        timeout: @review_timeout
      )
    end)
  end

  # Matching submits can reuse the same async machinery
  defp record_review(socket, %{term_id: nil}, _correct?, _answer_text), do: socket

  defp record_review(socket, %{term_id: term_id}, correct?, answer_text) do
    grade = if correct?, do: :good, else: :again
    user = socket.assigns.current_user

    start_async(socket, {:review, term_id}, fn ->
      Learning.review(
        user,
        term_id,
        grade,
        answer: answer_text,
        queue_type: :review
      )
    end)
  end

  # ————————————————————————————————————————————————————————————————
  # View Helpers
  # ————————————————————————————————————————————————————————————————

  @spec round_fill_percentage(map()) :: float()
  defp round_fill_percentage(assigns) do
    SessionManager.calculate_round_progress(assigns.session_state)
  end

  @spec prompt_label(map()) :: String.t()
  defp prompt_label(%{kind: kind}) when kind in ["multiple_choice", "true_false"], do: "Term"
  defp prompt_label(_), do: "Definition"

  @spec interaction_state(map()) :: interaction_state()
  defp interaction_state(assigns) do
    answered? = Map.get(assigns, :answered?, false)
    correct? = Map.get(assigns, :correct?, false)
    wrong_idx = Map.get(assigns, :last_wrong_index)

    cond do
      answered? -> if correct?, do: :correct, else: :wrong_closed
      not is_nil(wrong_idx) -> :wrong_attempt
      true -> :idle
    end
  end

  defp calculate_session_accuracy(%{total_questions: 0}), do: 0

  defp calculate_session_accuracy(%{total_correct: correct, total_questions: total}) do
    SessionManager.calculate_session_accuracy(%{total_correct: correct, total_questions: total})
  end

  defp maybe_create_match_pair(socket) do
    with %{selected_left: l, selected_right: r, pairs: pairs} <- socket.assigns,
         true <- is_integer(l) && is_integer(r) do
      pair_exists? = Enum.any?(pairs, &(&1.left_index == l || &1.right_index == r))

      if pair_exists? do
        socket
      else
        new_pair = %{left_index: l, right_index: r}

        socket
        |> assign(:pairs, [new_pair | pairs])
        |> assign(:selected_left, nil)
        |> assign(:selected_right, nil)
      end
    else
      _ -> socket
    end
  end

  # ————————————————————————————————————————————————————————————————
  # Utilities for Async assigns
  # ————————————————————————————————————————————————————————————————

  defp page_title_with_name(%Phoenix.LiveView.AsyncResult{ok?: true, result: %{name: name}}),
    do: "Learn · #{name}"

  defp page_title_with_name(_), do: "Learn"

  defp study_set_id(assigns) do
    case assigns[:study_set] do
      %Phoenix.LiveView.AsyncResult{ok?: true, result: %{id: id}} -> id
      %Phoenix.LiveView.AsyncResult{} -> nil
      %{id: id} -> id
      _ -> nil
    end
  end
end
