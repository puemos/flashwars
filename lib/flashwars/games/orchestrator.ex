defmodule Flashwars.Games.Orchestrator do
  use GenServer
  require Logger

  alias Flashwars.Games.Events
  alias Flashwars.Games.Orchestrator.State

  @registry Flashwars.Registry
  @sup Flashwars.GameOrchestratorSupervisor

  # Public API

  def via(room_id), do: {:via, Registry, {@registry, {:game_orchestrator, room_id}}}

  def whereis(room_id) do
    case Registry.lookup(@registry, {:game_orchestrator, room_id}) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  def ensure_started(room_id) do
    case whereis(room_id) do
      nil ->
        spec = {__MODULE__, [game_room_id: room_id]}
        DynamicSupervisor.start_child(@sup, spec)

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  def begin(room_id, _actor, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :multiple_choice)
    time_limit_ms = Keyword.get(opts, :time_limit_ms)
    intermission_ms = Keyword.get(opts, :intermission_ms, 10_000)

    with {:ok, _pid} <- ensure_started(room_id) do
      GenServer.cast(
        via(room_id),
        {:begin, strategy, %{time_limit_ms: time_limit_ms, intermission_ms: intermission_ms}}
      )

      :ok
    end
  end

  def force_next(room_id, _opts \\ []) do
    with {:ok, _pid} <- ensure_started(room_id) do
      GenServer.cast(via(room_id), :force_next)
      :ok
    end
  end

  # GenServer

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :game_room_id)
    GenServer.start_link(__MODULE__, %{room_id: room_id}, name: via(room_id))
  end

  @impl true
  def init(%{room_id: room_id}) do
    _ = Events.subscribe(room_id)
    {:ok, %{st: State.new(room_id)}}
  end

  @impl true
  def handle_cast({:begin, strategy, %{time_limit_ms: tl, intermission_ms: im}}, %{st: st} = s) do
    {st2, effects} =
      State.reduce(st, {:begin, strategy, %{time_limit_ms: tl, intermission_ms: im}})

    interpret_effects(effects, st2.room_id)
    {:noreply, %{s | st: st2}}
  end

  @impl true
  def handle_cast(:force_next, %{st: st} = s) do
    {st2, effects} = State.reduce(st, :force_next)
    interpret_effects(effects, st2.room_id)
    {:noreply, %{s | st: st2}}
  end

  @impl true
  def handle_info({:time_up, rid}, %{st: st} = s) do
    {st2, effects} = State.reduce(st, {:time_up, rid})
    interpret_effects(effects, st2.room_id)
    {:noreply, %{s | st: st2}}
  end

  # React to LiveView broadcasts
  @impl true
  def handle_info(%{event: :round_closed, round_id: rid}, %{st: st} = s) do
    {st2, effects} = State.reduce(st, {:round_closed, rid})
    interpret_effects(effects, st2.room_id)
    {:noreply, %{s | st: st2}}
  end

  def handle_info(%{event: :ready}, s), do: {:noreply, s}

  def handle_info(%{event: :new_round, round: round}, %{st: st} = s) do
    {st2, effects} = State.reduce(st, {:new_round, round})
    interpret_effects(effects, st2.room_id)
    {:noreply, %{s | st: st2}}
  end

  def handle_info(%{event: :game_over}, %{st: st} = s),
    do: {:noreply, %{s | st: %{st | mode: :ended}}}

  @impl true
  def handle_info(:intermission_over, %{st: st} = s) do
    {st2, effects} = State.reduce(st, :intermission_over)
    interpret_effects(effects, st2.room_id)
    {:noreply, %{s | st: st2}}
  end

  @impl true
  def handle_info(_msg, s), do: {:noreply, s}

  # Effect interpreter
  defp interpret_effects(effects, room_id) when is_list(effects) do
    Enum.each(effects, fn
      {:broadcast, event} -> Events.broadcast(room_id, event)
      {:schedule_in, ms, msg} -> Process.send_after(self(), msg, ms)
      _ -> :ok
    end)
  end
end
