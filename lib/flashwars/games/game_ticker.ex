defmodule Flashwars.Games.GameTicker do
  use GenServer
  require Logger
  alias Phoenix.PubSub

  @tick 200

  def start_link(opts) do
    game_room_id = Keyword.fetch!(opts, :game_room_id)
    GenServer.start_link(__MODULE__, %{game_room_id: game_room_id}, name: via(game_room_id))
  end

  def via(game_room_id), do: {:via, Registry, {Flashwars.Registry, {:game_ticker, game_room_id}}}

  def init(state) do
    {:ok, Map.merge(%{phase: :lobby, round: 0, deadline: nil}, state)}
  end

  def handle_cast({:start}, %{game_room_id: _} = s) do
    s = transition(s, :countdown, 3000)
    {:noreply, s}
  end

  def handle_info(:tick, s) do
    now = System.monotonic_time(:millisecond)
    s = maybe_advance(now, s)
    schedule_tick()
    {:noreply, s}
  end

  defp schedule_tick(), do: Process.send_after(self(), :tick, @tick)

  defp maybe_advance(now, %{deadline: deadline} = s)
       when not is_nil(deadline) and now >= deadline do
    next_phase(s)
  end

  defp maybe_advance(_now, s), do: s

  defp next_phase(%{phase: :countdown} = s), do: transition(s, :question, 10000)
  defp next_phase(%{phase: :question} = s), do: transition(s, :lock, 250)
  defp next_phase(%{phase: :lock} = s), do: transition(s, :reveal, 2000)
  defp next_phase(%{phase: :reveal} = s), do: transition(s, :intermission, 3000)

  defp next_phase(%{phase: :intermission, round: r} = s),
    do: transition(%{s | round: r + 1}, :question, 10000)

  defp transition(%{game_room_id: id} = s, new_phase, after_ms) do
    now = System.monotonic_time(:millisecond)
    deadline = now + after_ms

    PubSub.broadcast(Flashwars.PubSub, topic(id), %{
      event: :phase,
      phase: new_phase,
      deadline: deadline
    })

    %{s | phase: new_phase, deadline: deadline}
  end

  defp topic(id), do: "flash_wars:room:" <> to_string(id)
end
