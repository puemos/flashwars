defmodule Flashwars.Games.Scoring do
  @moduledoc "Scoring utilities for game submissions."

  # Simple scoring: base points + speed bonus; apply streak externally
  def score(correct?, ms_taken, opts \\ [])
  def score(false, _ms, _opts), do: 0

  def score(true, ms, opts) do
    base = Keyword.get(opts, :base, 100)
    max_bonus = Keyword.get(opts, :max_bonus, 100)
    limit = Keyword.get(opts, :limit_ms, 10_000)
    bonus = max(0, max_bonus - div(max_bonus * min(ms, limit), limit))
    base + bonus
  end
end
