defmodule Flashwars.Learning.SessionManager do
  @moduledoc """
  Manages learning session state and persistence for study sessions.

  Handles session lifecycle, progression logic, and state persistence
  for different learning modes like flashcards, learn, and test.
  """

  alias Flashwars.Learning
  alias Flashwars.Learning.Engine
  require Ash.Query

  @recent_window :timer.hours(24)

  # Configuration constants
  @round_size 10
  @match_pairs 4

  # Type definitions
  @type session_state :: %{
          round_items: list(),
          round_index: integer(),
          round_number: integer(),
          round_correct_count: integer(),
          round_position: integer(),
          current_item: map() | nil,
          session_stats: map(),
          mode: atom()
        }

  @type progression_result ::
          {:advance_in_round, session_state()}
          | {:start_new_round, session_state()}
          | {:session_complete, session_state()}

  # ————————————————————————————————————————————————————————————————
  # Session Lifecycle
  # ————————————————————————————————————————————————————————————————

  @spec initialize_session(map(), String.t(), atom()) :: {:ok, session_state()} | {:error, atom()}
  def initialize_session(user, study_set_id, mode \\ :learn) do
    # Try to resume existing session first
    case resume_session(user, study_set_id, mode) do
      {:ok, state} -> {:ok, state}
      {:error, :no_session} -> create_new_session(user, study_set_id, mode)
    end
  end

  @spec create_new_session(map(), String.t(), atom()) :: {:ok, session_state()} | {:error, atom()}
  def create_new_session(user, study_set_id, mode) do
    case generate_learn_items(user, study_set_id) do
      [] ->
        {:error, :no_items}

      items ->
        state = %{
          round_items: items,
          round_index: 0,
          round_number: 1,
          round_correct_count: 0,
          round_position: 1,
          current_item: List.first(items),
          session_stats: %{total_correct: 0, total_questions: 0},
          mode: mode
        }

        {:ok, state}
    end
  end

  @spec advance_session(session_state()) :: progression_result()
  def advance_session(state) do
    %{round_items: items, round_index: idx, round_position: pos} = state
    new_idx = idx + 1

    if new_idx < length(items) do
      # Advance within current round
      new_state = %{
        state
        | round_index: new_idx,
          round_position: pos + 1,
          current_item: Enum.at(items, new_idx)
      }

      {:advance_in_round, new_state}
    else
      # Start new round
      {:start_new_round, state}
    end
  end

  @spec start_new_round(session_state(), map(), String.t()) ::
          {:ok, session_state()} | {:error, atom()}
  def start_new_round(state, user, study_set_id) do
    case generate_learn_items(user, study_set_id) do
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
            current_item: List.first(items)
        }

        {:ok, new_state}
    end
  end

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

  # ————————————————————————————————————————————————————————————————
  # Progress Calculations
  # ————————————————————————————————————————————————————————————————

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
  def is_round_complete?(state) do
    state.round_index >= length(state.round_items) - 1
  end

  # ————————————————————————————————————————————————————————————————
  # Item Generation
  # ————————————————————————————————————————————————————————————————

  @spec generate_learn_items(map(), String.t()) :: list()
  defp generate_learn_items(user, set_id) do
    try do
      Engine.generate_learn_round(user, set_id, size: @round_size, pair_count: @match_pairs)
    rescue
      error ->
        require Logger
        Logger.error("Failed to generate learn items: #{inspect(error)}")
        []
    end
  end

  @spec create_empty_item() :: map()
  def create_empty_item do
    %{
      kind: "multiple_choice",
      prompt: "No items",
      choices: ["—", "—", "—", "—"],
      answer_index: 0,
      term_id: nil
    }
  end

  # ————————————————————————————————————————————————————————————————
  # Session Persistence (existing functionality)
  # ————————————————————————————————————————————————————————————————

  @spec save_session(map(), String.t(), atom(), session_state()) ::
          {:ok, map()} | {:error, term()}
  def save_session(user, study_set_id, mode, state) do
    now = DateTime.utc_now()

    Learning.Session
    |> Ash.Changeset.for_create(
      :upsert,
      %{
        study_set_id: study_set_id,
        mode: mode,
        state: state,
        last_saved_at: now
      },
      actor: user
    )
    |> Ash.create(actor: user)
  end

  @spec resume_session(map(), String.t(), atom()) :: {:ok, session_state()} | {:error, atom()}
  def resume_session(user, study_set_id, mode) do
    with {:ok, sessions} <-
           Learning.Session
           |> Ash.Query.for_read(
             :for_user_set_mode,
             %{
               study_set_id: study_set_id,
               mode: mode
             },
             actor: user
           )
           |> Ash.read(limit: 1, actor: user),
         [session] <- sessions do
      if recent?(session) do
        # Validate and potentially fix session state
        case validate_session_state(session.state) do
          {:ok, valid_state} -> {:ok, valid_state}
          {:error, _} -> {:error, :invalid_session}
        end
      else
        {:error, :no_session}
      end
    else
      _ -> {:error, :no_session}
    end
  end

  @spec validate_session_state(map()) :: {:ok, session_state()} | {:error, atom()}
  defp validate_session_state(state) when is_map(state) do
    required_keys = [:round_items, :round_index, :round_number, :round_position, :session_stats]

    if Enum.all?(required_keys, &Map.has_key?(state, &1)) do
      # Ensure session_stats has required structure
      stats = Map.get(state, :session_stats, %{})

      valid_stats = %{
        total_correct: Map.get(stats, :total_correct, 0),
        total_questions: Map.get(stats, :total_questions, 0)
      }

      valid_state = %{state | session_stats: valid_stats}
      {:ok, valid_state}
    else
      {:error, :missing_required_keys}
    end
  end

  defp validate_session_state(_), do: {:error, :invalid_format}

  defp recent?(%{updated_at: updated_at}) when not is_nil(updated_at) do
    diff_ms = DateTime.diff(DateTime.utc_now(), updated_at, :millisecond)
    diff_ms < @recent_window
  end

  defp recent?(_), do: false
end
