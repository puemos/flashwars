defmodule Flashwars.Games.OrchestratorStateTest do
  use ExUnit.Case, async: true

  alias Flashwars.Games.Orchestrator.State

  test "begin sets strategy and timers" do
    st = State.new(123)
    {st2, eff} = State.reduce(st, {:begin, :multiple_choice, %{time_limit_ms: 400, intermission_ms: 3000}})
    assert st2.strategy == :multiple_choice
    assert st2.time_limit_ms == 400
    assert st2.intermission_ms == 3000
    assert eff == []
  end

  test "new_round schedules time_up when time_limit_ms set" do
    st = State.new(1, time_limit_ms: 250)
    round = %{id: 42, number: 1, question_data: %{answer_index: 0}}
    {st2, eff} = State.reduce(st, {:new_round, round})
    assert st2.current_round == round
    assert st2.mode == :question
    assert {:schedule_in, 250, {:time_up, 42}} in eff
  end

  test "time_up broadcasts round_closed and schedules intermission" do
    st = State.new(1, time_limit_ms: 250, intermission_ms: 500)
    round = %{id: 7, number: 1, question_data: %{answer_index: 2}}
    {st1, _} = State.reduce(st, {:new_round, round})
    {st2, eff} = State.reduce(st1, {:time_up, 7})
    assert st2.mode == :intermission
    assert {:broadcast, %{event: :round_closed, round_id: 7, correct_index: 2}} = Enum.find(eff, fn {k, v} -> k == :broadcast and v[:event] == :round_closed end)
    assert {:schedule_in, 500, :intermission_over} in eff
  end

  test "round_closed schedules intermission once" do
    st = State.new(1, intermission_ms: 800)
    round = %{id: 9, number: 1, question_data: %{answer_index: 1}}
    {st1, _} = State.reduce(st, {:new_round, round})
    {st2, eff1} = State.reduce(st1, {:round_closed, 9})
    assert st2.mode == :intermission
    assert {:schedule_in, 800, :intermission_over} in eff1
    # Duplicate close does not reschedule
    {st3, eff2} = State.reduce(st2, {:round_closed, 9})
    assert st3.mode == :intermission
    assert eff2 == []
  end

  test "intermission_over broadcasts and returns to idle" do
    st = State.new(1)
    round = %{id: 3, number: 1, question_data: %{answer_index: 0}}
    {st1, _} = State.reduce(st, {:new_round, round})
    {st2, _} = State.reduce(st1, {:round_closed, 3})
    {st3, eff} = State.reduce(st2, :intermission_over)
    assert st3.mode == :idle
    assert {:broadcast, %{event: :intermission_over, rid: 3}} in eff
  end
end

