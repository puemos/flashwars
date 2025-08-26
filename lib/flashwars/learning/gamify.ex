defmodule Flashwars.Learning.Gamify do
  @moduledoc "Helpers for XP/level/streak updates and computation."
  alias Flashwars.Learning

  @level_size 1000

  @doc "Compute XP gain from recap items."
  def xp_from_items(items) when is_list(items) do
    {m, p, s, t} =
      Enum.reduce(items, {0, 0, 0, 0}, fn rec, {m, p, s, t} ->
        case to_string(rec.mastery || "") do
          "Mastered" -> {m + 1, p, s, t + 1}
          "Practicing" -> {m, p + 1, s, t + 1}
          "Struggling" -> {m, p, s + 1, t + 1}
          _ -> {m, p, s, t + 1}
        end
      end)

    base = m * 12 + p * 6 + max(0, t - m - p - s) * 2
    bonus = if s == 0 and t > 0, do: 10, else: 0
    base + bonus
  end

  @doc "Grant round rewards and persist to UserStats. Returns display map."
  def grant_round_rewards(user, org_id, items) do
    xp_gain = xp_from_items(items)
    now = DateTime.utc_now()

    try do
      stats =
        case Learning.list_user_stats_for_user_org!(%{organization_id: org_id}, actor: user)
             |> List.first() do
          nil ->
            Learning.upsert_user_stats!(
              %{
                user_id: user.id,
                organization_id: org_id,
                xp: 0,
                level: 1,
                streak: 0,
                longest_streak: 0
              },
              actor: user
            )

          s ->
            s
        end

      new_xp = stats.xp + xp_gain
      new_level = div(new_xp, @level_size) + 1
      level_progress = rem(new_xp, @level_size) * 100.0 / @level_size

      new_streak =
        case stats.last_round_at do
          nil ->
            1

          last ->
            days = Date.diff(DateTime.to_date(now), DateTime.to_date(last))

            cond do
              # same day
              days <= 0 -> stats.streak
              days == 1 -> stats.streak + 1
              true -> 1
            end
        end

      longest = max(stats.longest_streak || 0, new_streak)

      _ =
        Learning.upsert_user_stats!(
          %{
            user_id: user.id,
            organization_id: org_id,
            xp: new_xp,
            level: new_level,
            streak: new_streak,
            longest_streak: longest,
            last_round_at: now
          },
          actor: user
        )

      %{xp_earned: xp_gain, level: new_level, level_progress: level_progress, streak: new_streak}
    rescue
      _ ->
        # Database table may not exist in some environments. Fall back to heuristics only.
        %{xp_earned: xp_gain, level: 1, level_progress: 0.0, streak: nil}
    end
  end
end
