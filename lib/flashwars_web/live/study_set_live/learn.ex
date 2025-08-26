defmodule FlashwarsWeb.StudySetLive.Learn do
  alias Flashwars.Learning.SessionState
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
  @heartbeat_interval 60_000

  # ========================================
  # Lifecycle
  # ========================================

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@heartbeat_interval, self(), :heartbeat)
    end

    socket =
      socket
      |> assign(:page_title, "Learn")
      |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)
      |> assign(:session_state, nil)
      |> assign_ui_state()

    {:ok, socket, temporary_assigns: [flash: %{}]}
  end

  @impl true
  def handle_params(%{"id" => set_id}, _uri, socket) when byte_size(set_id) > 0 do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign_async(:study_set, fn ->
       case Content.get_study_set_by_id(set_id, actor: user) do
         {:ok, set} -> {:ok, %{study_set: set}}
         {:error, reason} -> {:error, reason}
       end
     end)
     |> start_async(:init_session, fn ->
       SessionManager.load_or_create_session(user, set_id, :learn)
     end)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # ========================================
  # Async Handlers
  # ========================================

  @impl true
  def handle_async(:init_session, {:ok, {:ok, session_state}}, socket) do
    socket =
      socket
      |> assign(:session_state, session_state)
      |> sync_ui_with_session_state(session_state)
      |> assign_ui_state()

    {:noreply, socket}
  end

  def handle_async(:init_session, {:error, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Failed to initialize session: #{inspect(reason)}")
     |> push_navigate(to: ~p"/")}
  end

  def handle_async({:review, term_id}, {:ok, result}, socket) do
    # Broadcast learning progress for real-time updates
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

  # ========================================
  # Event Handlers
  # ========================================

  @impl true
  def handle_event("answer", %{"index" => idx_str}, socket) do
    with {idx, ""} <- Integer.parse(idx_str),
         true <- idx >= 0,
         %{current_item: item} <- socket.assigns,
         true <- item.kind in ["multiple_choice", "true_false"],
         choices when is_list(choices) <- item.choices,
         true <- idx < length(choices) do
      answer_text = Enum.at(choices, idx, "")
      correct? = idx == item.answer_index

      socket = handle_answer(socket, item, correct?, answer_text, idx)
      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("answer_text", %{"answer" => %{"text" => text}}, socket) do
    %{current_item: item} = socket.assigns

    if item.kind == "free_text" do
      user_text = String.trim(text)
      correct_text = String.trim(item.answer_text || "")

      correct? =
        String.downcase(user_text) == String.downcase(correct_text) &&
          byte_size(correct_text) > 0

      socket = handle_text_answer(socket, item, correct?, user_text, correct_text)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_matches", _params, socket) do
    %{current_item: item, pairs: user_pairs} = socket.assigns

    if item.kind == "matching" do
      correct_pairs = item[:answer_pairs] || []
      correct? = MapSet.new(user_pairs) == MapSet.new(correct_pairs)

      socket = handle_matching_answer(socket, item, correct?, user_pairs, correct_pairs)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next", _params, socket) do
    {:noreply, advance_to_next_question(socket)}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    user = socket.assigns.current_user
    set_id = get_study_set_id(socket.assigns)

    case SessionManager.create_session(user, set_id, :learn) do
      {:ok, session_state} ->
        socket =
          socket
          |> assign(:session_state, session_state)
          |> sync_ui_with_session_state(session_state)
          |> assign_ui_state()
          |> put_flash(:info, "Starting new session!")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to start new session")}
    end
  end

  @impl true
  def handle_event("start_next_round", _params, socket) do
    user = socket.assigns.current_user
    set_id = get_study_set_id(socket.assigns)

    case SessionManager.start_new_round(socket.assigns.session_state, user, set_id) do
      {:ok, new_state} ->
        {:noreply,
         socket
         |> assign(:session_state, new_state)
         |> assign(:show_recap?, false)
         |> assign(:round_recap, [])
         |> assign(:just_completed_round, nil)
         |> sync_ui_with_session_state(new_state)
         |> assign_ui_state()
         |> put_flash(:info, "New round started!")}

      {:error, :no_items} ->
        {:noreply, put_flash(socket, :error, "Unable to generate new round items")}
    end
  end

  @impl true
  def handle_event("dont_know", _params, socket) do
    session_state = SessionManager.defer_current_item(socket.assigns.session_state)

    socket =
      socket
      |> assign(:session_state, session_state)
      |> advance_to_next_question()

    {:noreply, socket}
  end

  @impl true
  def handle_event("any_key", _params, socket) do
    if socket.assigns[:answered?] do
      {:noreply, advance_to_next_question(socket)}
    else
      {:noreply, socket}
    end
  end

  # Matching-specific events
  @impl true
  def handle_event("match_pick", %{"side" => side, "index" => idx_str}, socket) do
    with {idx, ""} <- Integer.parse(idx_str) do
      socket =
        case side do
          "left" -> assign(socket, :selected_left, idx)
          "right" -> assign(socket, :selected_right, idx)
          _ -> socket
        end

      {:noreply, maybe_create_match_pair(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("match_drop", %{"left_index" => left_idx, "right_index" => right_idx}, socket)
      when is_integer(left_idx) and is_integer(right_idx) do
    pairs = socket.assigns.pairs
    pair_exists? = Enum.any?(pairs, &(&1.left_index == left_idx || &1.right_index == right_idx))

    socket =
      if pair_exists? do
        socket
      else
        new_pair = %{left_index: left_idx, right_index: right_idx}
        assign(socket, :pairs, [new_pair | pairs])
      end

    {:noreply, socket}
  end

  # ========================================
  # Info Handlers
  # ========================================

  @impl true
  def handle_info(:heartbeat, socket) do
    if socket.assigns[:session_state] do
      Task.start(fn ->
        SessionManager.save_session(
          socket.assigns.current_user,
          get_study_set_id(socket.assigns),
          :learn,
          socket.assigns.session_state
        )
      end)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:auto_next, round_no, round_pos}, socket) do
    same_question? =
      socket.assigns[:round_number] == round_no and
        socket.assigns[:round_position] == round_pos

    if same_question? and socket.assigns[:answered?] and socket.assigns[:correct?] do
      {:noreply, advance_to_next_question(socket)}
    else
      {:noreply, socket}
    end
  end

  # ========================================
  # Private Functions - Answer Handling
  # ========================================

  defp handle_answer(socket, item, correct?, answer_text, selected_idx) do
    socket = record_review_async(socket, item, correct?, answer_text)

    # Update session stats
    session_state = SessionManager.update_session_stats(socket.assigns.session_state, correct?)

    # Handle defer if wrong on first pass
    session_state =
      if correct?, do: session_state, else: SessionManager.defer_current_item(session_state)

    socket =
      socket
      |> assign(:session_state, session_state)
      |> assign(:answered?, true)
      |> assign(:correct?, correct?)
      |> assign(:reveal, %{selected_index: selected_idx, correct_index: item.answer_index})

    # Auto-advance for correct answers
    if correct? and is_nil(socket.assigns[:last_wrong_index]) do
      Process.send_after(
        self(),
        {:auto_next, socket.assigns[:round_number], socket.assigns[:round_position]},
        5_000
      )
    end

    socket
  end

  defp handle_text_answer(socket, item, correct?, user_text, correct_text) do
    socket = record_review_async(socket, item, correct?, user_text)

    session_state = SessionManager.update_session_stats(socket.assigns.session_state, correct?)

    session_state =
      if correct?, do: session_state, else: SessionManager.defer_current_item(session_state)

    socket
    |> assign(:session_state, session_state)
    |> assign(:answered?, true)
    |> assign(:correct?, correct?)
    |> assign(:reveal, %{user_text: user_text, correct_text: correct_text})
  end

  defp handle_matching_answer(socket, item, correct?, user_pairs, correct_pairs) do
    socket = record_matching_review_async(socket, item, correct?, user_pairs)

    session_state = SessionManager.update_session_stats(socket.assigns.session_state, correct?)

    session_state =
      if correct?, do: session_state, else: SessionManager.defer_current_item(session_state)

    socket
    |> assign(:session_state, session_state)
    |> assign(:answered?, true)
    |> assign(:correct?, correct?)
    |> assign(:reveal, %{user_pairs: user_pairs, correct_pairs: correct_pairs})
  end

  # ========================================
  # Private Functions - Session Management
  # ========================================

  defp advance_to_next_question(socket) do
    session_state = socket.assigns.session_state

    # Mark correct if answered correctly
    session_state =
      if socket.assigns[:answered?] and socket.assigns[:correct?] do
        SessionManager.mark_answer_correct(session_state)
      else
        session_state
      end

    case SessionManager.advance_session(session_state) do
      {:advance_in_round, new_state} ->
        socket
        |> assign(:session_state, new_state)
        |> sync_ui_with_session_state(new_state)
        |> assign_ui_state()

      {:start_new_round, state} ->
        # end-of-round: show recap for the just-completed round
        user = socket.assigns.current_user
        set_id = get_study_set_id(socket.assigns)
        recap = build_round_recap(user, set_id, state)

        socket
        |> assign(:session_state, state)
        |> assign(:show_recap?, true)
        |> assign(:round_recap, recap)
        |> assign(:just_completed_round, state.round_number)
    end
  end

  defp sync_ui_with_session_state(socket, state = %SessionState{}) do
    socket
    |> assign(:round_items, state.round_items || [])
    |> assign(:round_index, state.round_index || 0)
    |> assign(:round_number, state.round_number || 1)
    |> assign(:round_correct_count, state.round_correct_count || 0)
    |> assign(:round_position, calculate_ui_position(state))
    |> assign(:current_item, state.current_item)
    |> assign(:session_stats, state.session_stats || %{})
  end

  defp calculate_ui_position(state = %SessionState{}) do
    items_count = length(state.round_items || [])
    correct_count = state.round_correct_count || 0
    pos = correct_count + 1

    cond do
      items_count <= 0 -> 0
      pos > items_count -> items_count
      pos < 1 -> 1
      true -> pos
    end
  end

  # ========================================
  # Private Functions - UI State
  # ========================================

  defp assign_ui_state(socket) do
    socket
    |> assign(:answered?, false)
    |> assign(:reveal, nil)
    |> assign(:correct?, nil)
    |> assign(:answer_text, nil)
    |> assign(:pairs, [])
    |> assign(:selected_left, nil)
    |> assign(:selected_right, nil)
    |> assign(:last_wrong_index, nil)
    |> assign_new(:show_recap?, fn -> false end)
    |> assign_new(:round_recap, fn -> [] end)
    |> assign_new(:just_completed_round, fn -> nil end)
  end

  # ========================================
  # Private Functions - Review Operations
  # ========================================

  defp record_review_async(socket, %{"term_id" => nil}, _correct?, _answer_text), do: socket

  defp record_review_async(socket, item, _correct?, _answer_text)
       when not is_map_key(item, "term_id"),
       do: socket

  defp record_review_async(socket, %{"term_id" => term_id}, correct?, answer_text) do
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

  defp record_matching_review_async(socket, %{"left" => terms}, correct?, user_pairs)
       when is_list(terms) do
    grade = if correct?, do: :good, else: :again
    user = socket.assigns.current_user
    answer_text = inspect(user_pairs)

    Enum.reduce(terms, socket, fn term, acc_socket ->
      if term_id = term["term_id"] do
        start_async(acc_socket, {:review, term_id}, fn ->
          Learning.review(
            user,
            term_id,
            grade,
            answer: answer_text,
            queue_type: :review,
            timeout: @review_timeout
          )
        end)
      else
        acc_socket
      end
    end)
  end

  defp record_matching_review_async(socket, _item, _correct?, _user_pairs), do: socket

  # ========================================
  # Private Functions - Matching UI Logic
  # ========================================

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

  # ========================================
  # View Helpers
  # ========================================

  defp prompt_label(%{kind: kind}) when kind in ["multiple_choice", "true_false"], do: "Term"
  defp prompt_label(_), do: "Definition"

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

  # ========================================
  # Utilities
  # ========================================

  defp get_study_set_id(assigns) do
    case assigns[:study_set] do
      %Phoenix.LiveView.AsyncResult{ok?: true, result: %{id: id}} -> id
      %{id: id} -> id
      _ -> nil
    end
  end

  # ========================================
  # Render Function
  # ========================================

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
        
    <!-- Session loading state -->
        <div :if={!@session_state} class="flex justify-center py-8">
          <div class="loading loading-spinner loading-lg"></div>
        </div>
        
    <!-- Round recap -->
        <div :if={@session_state && @show_recap?} class="space-y-6">
          <div class="card bg-base-200">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <div class="text-sm opacity-70">Round {@just_completed_round} recap</div>
              </div>
              <h3 class="mt-2 text-2xl font-semibold">Great work! Here's what you covered:</h3>
              <div class="mt-4">
                <ul class="divide-y divide-base-300">
                  <li
                    :for={rec <- @round_recap}
                    id={"recap-#{rec.term_id}"}
                    class="py-3 flex items-center justify-between"
                  >
                    <div class="font-medium">{rec.term}</div>
                    <span class="badge badge-outline">{rec.mastery}</span>
                  </li>
                </ul>
                <div :if={@round_recap == []} class="opacity-70">No terms to recap.</div>
              </div>
              <div class="mt-4">
                <.button id="next-round-btn" phx-click="start_next_round">Next Round</.button>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Main learning interface -->
        <div
          :if={@session_state && !@show_recap?}
          id="learn-panel"
          class="space-y-6"
          phx-window-keydown={if @answered?, do: "any_key"}
        >
          <!-- Progress visualization -->
          <div class="mt-2 px-4 pb-2">
            <QC.segment_track
              chunks={3}
              chunk_size={length(@round_items)}
              chunk={if @round_number > 0, do: 1, else: 0}
              offset={@round_correct_count}
              label={@round_position}
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
                {@current_item.prompt}
              </h3>
              
    <!-- Status messages -->
              <div class="mt-3 min-h-[28px]">
                <%= case interaction_state(assigns) do %>
                  <% :idle -> %>
                    <%= case @current_item.kind do %>
                      <% "multiple_choice" -> %>
                        <div class="text-sm opacity-70">Select one of the options</div>
                      <% "true_false" -> %>
                        <div class="text-sm opacity-70">Choose True or False</div>
                      <% "free_text" -> %>
                        <div class="text-sm opacity-70">Type your answer</div>
                      <% "matching" -> %>
                        <div class="text-sm opacity-70">Match each item to its pair</div>
                      <% _ -> %>
                        <div class="h-28 rounded-xl bg-base-300/40 animate-pulse">
                          {@current_item.kind}
                        </div>
                    <% end %>
                  <% :wrong_attempt -> %>
                    <div class="text-sm text-orange-300">
                      Not quite. Try again, or <button
                        class="link link-hover text-orange-200"
                        phx-click="next"
                      >Skip</button>.
                    </div>
                  <% :wrong_closed -> %>
                    <div class="inline-flex items-center gap-2 text-sm text-orange-300">
                      <span>🙅</span>
                      <span>Incorrect — press Continue or any key to move on.</span>
                    </div>
                  <% :correct -> %>
                    <div class="inline-flex items-center gap-2 text-sm text-green-300">
                      <span>🏆</span>
                      <span>You're really getting this!</span>
                    </div>
                <% end %>
              </div>
              
    <!-- Answer interface -->
              <%= case @current_item.kind do %>
                <% "multiple_choice" -> %>
                  <QC.choices
                    choices={@current_item.choices || []}
                    selected_index={get_in(assigns, [:reveal, :selected_index])}
                    correct_index={@current_item.answer_index}
                    immediate_response={true}
                    round_closed?={@answered?}
                    answered?={@answered?}
                  />
                <% "true_false" -> %>
                  <QC.true_false
                    definition={@current_item.definition}
                    selected_index={get_in(assigns, [:reveal, :selected_index])}
                    correct_index={@current_item.answer_index}
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
                    id={"matching-#{@round_number}-#{@round_position}"}
                    left={@current_item.left}
                    right={@current_item.right}
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
                    @current_item.kind in ["multiple_choice", "true_false"] and
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
                <.button id="next-btn" phx-click="next">
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

  # ========================================
  # Private Functions - Round Recap
  # ========================================

  defp build_round_recap(user, study_set_id, %SessionState{} = state) do
    term_ids = extract_term_ids_from_round(state.round_items || [])

    # Classify mastery across the set, then filter for the round's terms
    mastery = Learning.mastery_for_set(user, study_set_id)

    by_id =
      mastery.mastered
      |> Enum.map(&{&1.term_id, {&1.term, "Mastered"}})
      |> Kernel.++(Enum.map(mastery.practicing, &{&1.term_id, {&1.term, "Practicing"}}))
      |> Kernel.++(Enum.map(mastery.struggling, &{&1.term_id, {&1.term, "Struggling"}}))
      |> Kernel.++(Enum.map(mastery.unseen, &{&1.term_id, {&1.term, "Unseen"}}))
      |> Map.new()

    term_ids
    |> Enum.uniq()
    |> Enum.map(fn id ->
      case Map.get(by_id, id) do
        {term, label} -> %{term_id: id, term: term, mastery: label}
        nil -> %{term_id: id, term: id, mastery: "—"}
      end
    end)
  end

  defp extract_term_ids_from_round(items) when is_list(items) do
    items
    |> Enum.flat_map(fn item ->
      cond do
        is_map(item) and Map.has_key?(item, :term_id) ->
          [item.term_id]

        is_map(item) and is_binary(Map.get(item, "term_id")) ->
          [Map.get(item, "term_id")]

        is_map(item) and is_list(Map.get(item, :left)) ->
          Enum.map(Map.get(item, :left), fn t -> t[:term_id] || t["term_id"] end)

        is_map(item) and is_list(Map.get(item, "left")) ->
          Enum.map(Map.get(item, "left"), fn t -> t["term_id"] || t[:term_id] end)

        true ->
          []
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
