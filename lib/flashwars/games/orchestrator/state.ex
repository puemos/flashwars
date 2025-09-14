defmodule Flashwars.Games.Orchestrator.State do
  @moduledoc """
  Pure state machine for game orchestration.

  Reduces events to a new state and a list of side-effect intents (effects).

  Effects are data and interpreted by the GenServer runtime:
  - {:broadcast, event_map}
  - {:schedule_in, ms, message}
  """

  defstruct room_id: nil,
            strategy: :multiple_choice,
            time_limit_ms: nil,
            intermission_ms: 10_000,
            current_round: nil,
            mode: :idle

  @type t :: %__MODULE__{
          room_id: any(),
          strategy: atom(),
          time_limit_ms: nil | non_neg_integer(),
          intermission_ms: non_neg_integer(),
          current_round: nil | map(),
          mode: :idle | :question | :intermission | :ended
        }

  @type effect :: {:broadcast, map()} | {:schedule_in, non_neg_integer(), term()}

  @spec new(any(), keyword()) :: t()
  def new(room_id, opts \\ []) do
    %__MODULE__{
      room_id: room_id,
      strategy: Keyword.get(opts, :strategy, :multiple_choice),
      time_limit_ms: Keyword.get(opts, :time_limit_ms),
      intermission_ms: Keyword.get(opts, :intermission_ms, 10_000)
    }
  end

  @spec reduce(t(), term()) :: {t(), [effect()]}
  def reduce(%__MODULE__{} = s, {:begin, strategy, %{time_limit_ms: tl, intermission_ms: im}}) do
    s = %{s | strategy: strategy, time_limit_ms: tl, intermission_ms: im || 10_000, mode: :idle}
    {s, []}
  end

  def reduce(%__MODULE__{} = s, {:new_round, round}) do
    s = %{s | current_round: round, mode: :question}

    effects =
      case s.time_limit_ms do
        i when is_integer(i) and i > 0 -> [{:schedule_in, i, {:time_up, round.id}}]
        _ -> []
      end

    {s, effects}
  end

  def reduce(%__MODULE__{current_round: %{id: rid}} = s, {:round_closed, rid}) do
    # Schedule intermission end if not already in intermission
    effects =
      case s.mode do
        :intermission -> []
        _ -> [{:schedule_in, s.intermission_ms, :intermission_over}]
      end

    {%{s | mode: :intermission}, effects}
  end

  def reduce(%__MODULE__{current_round: %{id: rid}, mode: :question} = s, {:time_up, rid}) do
    qd = question_data(s.current_round)
    answer_index = qd[:answer_index] || qd["answer_index"] || 0

    effects = [
      {:broadcast,
       %{
         event: :round_closed,
         round_id: rid,
         user_id: nil,
         selected_index: nil,
         correct_index: answer_index,
         correct?: false
       }},
      {:schedule_in, s.intermission_ms, :intermission_over}
    ]

    {%{s | mode: :intermission}, effects}
  end

  def reduce(%__MODULE__{} = s, {:time_up, _other}), do: {s, []}
  def reduce(%__MODULE__{} = s, {:round_closed, _other}), do: {s, []}

  def reduce(%__MODULE__{current_round: %{id: rid}} = s, :intermission_over) do
    {%{s | mode: :idle}, [{:broadcast, %{event: :intermission_over, rid: rid}}]}
  end

  def reduce(%__MODULE__{} = s, :intermission_over), do: {s, []}

  def reduce(%__MODULE__{current_round: %{id: rid}} = s, :force_next) do
    {%{s | mode: :idle}, [{:broadcast, %{event: :intermission_over, rid: rid}}]}
  end

  def reduce(%__MODULE__{} = s, :force_next), do: {s, []}

  def reduce(%__MODULE__{} = s, _), do: {s, []}

  defp question_data(%{question_data: qd}) when is_map(qd), do: qd
  defp question_data(%{} = m), do: Map.get(m, :question_data) || Map.get(m, "question_data") || %{}
  defp question_data(_), do: %{}
end
