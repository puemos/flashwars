defmodule Flashwars.Learning.SessionManager do
  @moduledoc """
  Core session business logic for learning modes.

  This module focuses purely on session state transitions and logic,
  without UI concerns or LiveView-specific functionality.
  """

  alias Flashwars.Learning.SessionState
  alias Flashwars.Learning
  alias Flashwars.Learning.Engine
  require Ash.Query

  # Type definitions
  @type session_state :: Flashwars.Learning.SessionState

  @type progression_result ::
          {:advance_in_round, session_state()}
          | {:start_new_round, session_state()}
          | {:session_complete, session_state()}

  # Configuration
  @recent_window_hours 24
  @default_round_size 10
  @default_match_pairs 4
  @default_types [:multiple_choice, :true_false, :free_text, :matching]

  # ========================================
  # Session Lifecycle - Core Logic Only
  # ========================================

  @spec create_session(map(), String.t(), atom(), keyword()) ::
          {:ok, session_state()} | {:error, atom()}
  def create_session(user, study_set_id, mode, opts \\ []) do
    size = Keyword.get(opts, :size, @default_round_size)
    pair_count = Keyword.get(opts, :pair_count, @default_match_pairs)
    types = Keyword.get(opts, :types, @default_types)
    smart = Keyword.get(opts, :smart, true)

    case generate_items_for_mode(user, study_set_id, mode,
           size: size,
           pair_count: pair_count,
           types: types,
           smart: smart
         ) do
      [] ->
        {:error, :no_items}

      items ->
        state = %SessionState{
          round_items: items,
          round_index: 0,
          round_number: 1,
          round_correct_count: 0,
          round_position: 1,
          current_item: List.first(items),
          session_stats: %{total_correct: 0, total_questions: 0},
          mode: mode,
          phase: :first_pass
        }

        {:ok, state}
    end
  end

  @spec load_or_create_session(map(), String.t(), atom(), keyword()) ::
          {:ok, session_state()} | {:error, atom()}
  def load_or_create_session(user, study_set_id, mode, opts \\ []) do
    case load_recent_session(user, study_set_id, mode) do
      {:ok, state} -> {:ok, state}
      {:error, _} -> create_session(user, study_set_id, mode, opts)
    end
  end

  # ========================================
  # State Transitions
  # ========================================

  @spec advance_session(session_state()) :: progression_result()
  def advance_session(%{phase: :first_pass} = state) do
    %{round_index: idx, round_items: items} = state

    cond do
      idx + 1 < length(items) ->
        {:advance_in_round, advance_to_next_item(state)}

      Map.get(state, :round_deferred, []) == [] ->
        {:start_new_round, state}

      true ->
        {:advance_in_round, enter_retry_phase(state)}
    end
  end

  def advance_session(%{phase: :retry} = state) do
    %{retry_index: i, retry_queue: queue} = state

    if i + 1 < length(queue) do
      new_state = %{
        state
        | retry_index: i + 1,
          current_item: Enum.at(queue, i + 1)
      }

      {:advance_in_round, new_state}
    else
      clean_state =
        %{
          state
          | phase: :first_pass,
            retry_queue: [],
            retry_index: 0
        }

      {:start_new_round, clean_state}
    end
  end

  @spec start_new_round(session_state(), map(), String.t(), keyword()) ::
          {:ok, session_state()} | {:error, atom()}
  def start_new_round(state, user, study_set_id, opts \\ []) do
    mode = state.mode
    size = Keyword.get(opts, :size, @default_round_size)
    pair_count = Keyword.get(opts, :pair_count, @default_match_pairs)
    types = Keyword.get(opts, :types, @default_types)
    smart = Keyword.get(opts, :smart, true)

    case generate_items_for_mode(user, study_set_id, mode,
           size: size,
           pair_count: pair_count,
           types: types,
           smart: smart
         ) do
      [] ->
        {:error, :no_items}

      items ->
        new_state = %{
          state
          | round_items: items,
            round_index: 0,
            round_number: state.round_number + 1,
            round_correct_count: 0,
            round_position: 1,
            current_item: List.first(items),
            phase: :first_pass
        }

        {:ok, new_state}
    end
  end

  # ========================================
  # State Updates
  # ========================================

  @spec update_session_stats(session_state(), boolean()) :: session_state()
  def update_session_stats(state, correct?) do
    stats = state.session_stats

    new_stats = %{
      total_questions: stats.total_questions + 1,
      total_correct: stats.total_correct + if(correct?, do: 1, else: 0)
    }

    %{state | session_stats: new_stats}
  end

  @spec mark_answer_correct(session_state()) :: session_state()
  def mark_answer_correct(state) do
    %{state | round_correct_count: state.round_correct_count + 1}
  end

  @spec defer_current_item(session_state()) :: session_state()
  def defer_current_item(%{phase: :first_pass, current_item: item} = state) do
    Map.update(state, :round_deferred, [item], &(&1 ++ [item]))
  end

  def defer_current_item(%{phase: :retry, current_item: item} = state) do
    Map.update(state, :retry_queue, [item], &(&1 ++ [item]))
  end

  def defer_current_item(state), do: state

  # ========================================
  # Progress Calculations
  # ========================================

  @spec calculate_round_progress(session_state()) :: float()
  def calculate_round_progress(state) do
    items_count = length(Map.get(state, :round_items, []))
    correct_count = Map.get(state, :round_correct_count, 0)
    total = max(items_count, 1)
    Float.round(min(correct_count * 100.0 / total, 100.0), 1)
  end

  @spec calculate_session_accuracy(map()) :: float()
  def calculate_session_accuracy(%{total_questions: 0}), do: 0.0

  def calculate_session_accuracy(%{total_correct: correct, total_questions: total}) do
    Float.round(correct * 100.0 / total, 1)
  end

  @spec is_round_complete?(session_state()) :: boolean()
  def is_round_complete?(%{round_index: idx, round_items: items}) do
    idx >= length(items) - 1
  end

  # ========================================
  # Persistence Operations
  # ========================================

  @spec save_session(map(), String.t(), atom(), session_state()) ::
          {:ok, map()} | {:error, term()}
  def save_session(user, study_set_id, mode, state) do
    now = DateTime.utc_now()

    Learning.upsert_session(
      %{
        study_set_id: study_set_id,
        mode: mode,
        state: state,
        last_saved_at: now
      },
      actor: user
    )
  end

  @spec load_recent_session(map(), String.t(), atom()) ::
          {:ok, session_state()} | {:error, atom()}
  def load_recent_session(user, study_set_id, mode) do
    cutoff = DateTime.add(DateTime.utc_now(), -@recent_window_hours, :hour)

    with {:ok, [session]} <-
           Learning.list_sessions_for_user_set_mode(
             %{study_set_id: study_set_id, mode: mode},
             actor: user,
             query:
               Learning.Session
               |> Ash.Query.filter(last_saved_at >= ^cutoff)
               |> Ash.Query.limit(1)
           ) do
      case session.state do
        %SessionState{} = st ->
          {:ok, st}
      end
    else
      _ -> {:error, :no_session}
    end
  end

  # ========================================
  # Private Functions
  # ========================================

  defp generate_items_for_mode(user, study_set_id, :learn, opts) do
    size = Keyword.get(opts, :size, @default_round_size)
    pair_count = Keyword.get(opts, :pair_count, @default_match_pairs)
    types = Keyword.get(opts, :types, @default_types)
    smart = Keyword.get(opts, :smart, true)

    try do
      Engine.generate_learn_round(user, study_set_id,
        size: size,
        pair_count: pair_count,
        types: types,
        smart: smart
      )
    rescue
      error ->
        require Logger
        Logger.error("Failed to generate learn items: #{inspect(error)}")
        []
    end
  end

  defp generate_items_for_mode(user, study_set_id, :test, opts) do
    size = Keyword.get(opts, :size, 20)
    pair_count = Keyword.get(opts, :pair_count, @default_match_pairs)

    try do
      Engine.generate_test(user, study_set_id, size: size, pair_count: pair_count)
    rescue
      error ->
        require Logger
        Logger.error("Failed to generate test items: #{inspect(error)}")
        []
    end
  end

  defp generate_items_for_mode(_user, _study_set_id, _mode, _opts), do: []

  defp advance_to_next_item(state) do
    %{round_index: idx, round_items: items, round_position: pos} = state
    new_idx = idx + 1

    %{
      state
      | round_index: new_idx,
        round_position: pos + 1,
        current_item: Enum.at(items, new_idx)
    }
  end

  defp enter_retry_phase(state) do
    retry_items = Map.get(state, :round_deferred, [])

    %{
      state
      | phase: :retry,
        retry_queue: retry_items,
        retry_index: 0,
        round_deferred: [],
        round_position: length(state.round_items),
        current_item: List.first(retry_items)
    }
  end
end
