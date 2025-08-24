defmodule Flashwars.Learning.Scheduler do
  @moduledoc """
  Neuroscience-informed scheduling engine.

  Implements exponential forgetting model with stability (S) and difficulty (D),
  relearning steps, growth caps, and queue building helpers.
  """

  alias Flashwars.Learning
  alias Flashwars.Learning.TermState

  @r_star 0.80
  @s_min 0.10
  @alpha 0.30
  @beta 0.05
  @gamma 0.02
  @delta 0.40
  @eta 0.60

  @type grade :: :again | :hard | :good | :easy

  def constants do
    %{
      r_star: @r_star,
      s_min: @s_min,
      alpha: @alpha,
      beta: @beta,
      gamma: @gamma,
      delta: @delta,
      eta: @eta
    }
  end

  @doc """
  Compute next schedule after a review and return updated fields for `TermState` and log info.
  """
  @spec schedule_after_review(TermState.t() | map, grade, integer | nil, DateTime.t()) ::
          {:ok, %{update: map, log: map}}
  def schedule_after_review(card, grade, rt_ms, now) do
    # allow passing in maps for convenience in tests
    card = Map.new(card)

    s = Map.get(card, :stability_days) || 0.3
    d = Map.get(card, :difficulty) || 6.0
    prev_i = Map.get(card, :prev_interval_days) || 0.0
    t_last = Map.get(card, :t_last) || now
    streak = Map.get(card, :streak) || 0
    lapses = Map.get(card, :lapses) || 0
    relearn_stage = Map.get(card, :relearn_stage) || 0

    dt_days = diff_days(t_last, now)
    r_now = :math.exp(-dt_days / max(s, @s_min))

    {success, g} =
      case grade do
        :again -> {0, 0}
        :hard -> {1, 1}
        :good -> {1, 2}
        :easy -> {1, 3}
      end

    {s_before, d_before} = {s, d}

    {s_new, d_new, streak_new, lapses_new, relearn_stage_new, i_next_days} =
      if success == 0 do
        s_new = max(@s_min, s * @delta)
        d_new = min(10.0, d + @eta)
        i_next = relearn_step_interval(relearn_stage)
        {s_new, d_new, 0, lapses + 1, next_relearn_stage(relearn_stage), i_next}
      else
        s_inc = 1.0 + @alpha * (1.0 - r_now) * f_g(g) * (1.0 / max(d, 1.0))
        s_new = max(@s_min, s * s_inc)
        drift = @beta * (k_g(g) - d) + @gamma * speed(rt_ms)
        d_new = clamp(d + drift, 1.0, 10.0)
        i_candidate = -s_new * :math.log(@r_star)
        growth_cap = 3.0 * max(prev_i, 1.0 / 24.0)
        # placeholder: 1 year cap; wire to per-user later
        user_cap = 365.0

        i_next =
          i_candidate |> min(growth_cap) |> min(user_cap) |> max(min_interval_by_grade(grade))

        {s_new, d_new, streak + 1, lapses, 0, i_next}
      end

    next_due_at = DateTime.add(now, days_to_seconds(i_next_days), :second)

    update = %{
      stability_days: s_new,
      difficulty: d_new,
      prev_interval_days: i_next_days,
      streak: streak_new,
      lapses: lapses_new,
      relearn_stage: relearn_stage_new,
      t_last: now,
      next_due_at: next_due_at,
      last_rt_ms: rt_ms
    }

    log = %{
      grade: grade,
      response_time_ms: rt_ms,
      prev_interval_days: prev_i,
      next_interval_days: i_next_days,
      s_before: s_before,
      s_after: s_new,
      d_before: d_before,
      d_after: d_new
    }

    {:ok, %{update: update, log: log}}
  end

  def build_daily_queue(user, study_set_id, capacity_cards) do
    now = DateTime.utc_now()

    # existing states due
    due_states =
      Learning.list_term_states_for_user_set!(
        %{study_set_id: study_set_id},
        actor: user
      )
      |> Enum.filter(fn cs ->
        is_nil(cs.next_due_at) or DateTime.compare(cs.next_due_at, now) != :gt
      end)

    # compute R_now and sort ascending (most at risk first)
    ranked_due =
      Enum.map(due_states, fn cs ->
        s = max(cs.stability_days || 0.3, @s_min)
        dt_days = diff_days(cs.t_last || now, now)
        r_now = :math.exp(-dt_days / s)
        {r_now, cs}
      end)
      |> Enum.sort_by(fn {r, _} -> r end, :asc)
      |> Enum.map(&elem(&1, 1))

    # add unseen cards if capacity remains
    unseen = unseen_cards(user, study_set_id)

    take_due = Enum.take(ranked_due, capacity_cards)
    remaining = capacity_cards - length(take_due)
    add_unseen = if remaining > 0, do: Enum.take(unseen, remaining), else: []

    take_due ++ add_unseen
  end

  defp unseen_cards(user, study_set_id) do
    # all terms in set
    terms =
      Flashwars.Content.list_terms_for_study_set!(
        %{study_set_id: study_set_id},
        actor: user
      )

    # existing states map
    states =
      Learning.list_term_states_for_user_set!(
        %{study_set_id: study_set_id},
        actor: user
      )
      |> Map.new(&{&1.term_id, true})

    terms
    |> Enum.reject(&Map.has_key?(states, &1.id))
    |> Enum.shuffle()
  end

  # Helpers
  defp f_g(1), do: 0.6
  defp f_g(2), do: 1.0
  defp f_g(3), do: 1.4
  defp f_g(_), do: 0.0

  defp k_g(1), do: 8.0
  defp k_g(2), do: 6.0
  defp k_g(3), do: 4.0
  defp k_g(_), do: 6.0

  defp speed(nil), do: 0.0
  defp speed(rt_ms) when is_integer(rt_ms) and rt_ms <= 1500, do: -0.1
  defp speed(rt_ms) when is_integer(rt_ms) and rt_ms >= 5000, do: 0.1
  defp speed(_), do: 0.0

  defp min_interval_by_grade(:hard), do: minutes_to_days(10)
  defp min_interval_by_grade(:good), do: 1.0
  defp min_interval_by_grade(:easy), do: 3.0
  defp min_interval_by_grade(_), do: 0.0

  defp relearn_step_interval(0), do: minutes_to_days(1)
  defp relearn_step_interval(1), do: minutes_to_days(10)
  defp relearn_step_interval(_), do: 1.0

  defp next_relearn_stage(0), do: 1
  defp next_relearn_stage(1), do: 2
  defp next_relearn_stage(_), do: 0

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v

  defp minutes_to_days(mins), do: mins / 1440.0
  defp days_to_seconds(days), do: trunc(days * 86_400)
  defp diff_days(t1, t2), do: DateTime.diff(t2, t1, :second) / 86_400
end
