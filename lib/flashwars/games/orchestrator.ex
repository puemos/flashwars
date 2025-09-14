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
    {:ok, %{st: State.new(room_id), timers: %{time_up: nil, intermission: nil}}}
  end

  @impl true
  def handle_cast({:begin, strategy, %{time_limit_ms: tl, intermission_ms: im}}, %{st: st} = s) do
    {st2, effects} =
      State.reduce(st, {:begin, strategy, %{time_limit_ms: tl, intermission_ms: im}})

    {:noreply, apply_effects(%{s | st: st2}, effects)}
  end

  @impl true
  def handle_cast(:force_next, %{st: st} = s) do
    {st2, effects} = State.reduce(st, :force_next)
    {:noreply, apply_effects(%{s | st: st2}, effects)}
  end

  @impl true
  def handle_info({:time_up, rid}, %{st: st} = s) do
    {st2, effects} = State.reduce(st, {:time_up, rid})
    {:noreply, apply_effects(%{s | st: st2}, effects)}
  end

  # React to LiveView broadcasts
  @impl true
  def handle_info(%{event: :round_closed, round_id: rid}, %{st: st} = s) do
    {st2, effects} = State.reduce(st, {:round_closed, rid})
    {:noreply, apply_effects(%{s | st: st2}, effects)}
  end

  def handle_info(%{event: :ready}, s), do: {:noreply, s}

  def handle_info(%{event: :new_round, round: round}, %{st: st} = s) do
    {st2, effects} = State.reduce(st, {:new_round, round})
    {:noreply, apply_effects(%{s | st: st2}, effects)}
  end

  def handle_info(%{event: :game_over}, %{st: st} = s),
    do: {:noreply, %{s | st: %{st | mode: :ended}}}

  @impl true
  def handle_info(:intermission_over, %{st: st} = s) do
    {st2, effects} = State.reduce(st, :intermission_over)
    {:noreply, apply_effects(%{s | st: st2}, effects)}
  end

  @impl true
  def handle_info(_msg, s), do: {:noreply, s}

  # Effect interpreter with robust timer management. Ensures only one active timer per kind.
  defp apply_effects(%{st: %{room_id: room_id}} = s, effects) when is_list(effects) do
    timers = s[:timers] || %{time_up: nil, intermission: nil}

    new_timers =
      Enum.reduce(effects, timers, fn
        {:broadcast, event}, acc ->
          Events.broadcast(room_id, event)
          acc

        {:schedule_in, ms, msg}, acc when is_integer(ms) and ms > 0 ->
          case msg do
            {:time_up, _rid} ->
              cancel_timer(acc.time_up)
              ref = Process.send_after(self(), msg, ms)
              %{acc | time_up: ref}

            :intermission_over ->
              cancel_timer(acc.intermission)
              ref = Process.send_after(self(), msg, ms)
              %{acc | intermission: ref}

            _ ->
              _ = Process.send_after(self(), msg, ms)
              acc
          end

        _other, acc ->
          acc
      end)

    %{s | timers: new_timers}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref) do
    # best-effort cancel; avoid sending message if already in queue
    _ = Process.cancel_timer(ref, async: true, info: false)
    :ok
  end
end
