defmodule Flashwars.Learning do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Learning.Attempt
    resource Flashwars.Learning.AttemptItem
    resource Flashwars.Learning.LeaderboardEntry
    resource Flashwars.Learning.Session
  end

  alias Flashwars.Learning.{Attempt, AttemptItem, LeaderboardEntry}

  def create_attempt(params, opts \\ []),
    do: Attempt |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()

  def create_attempt_item(params, opts \\ []),
    do: AttemptItem |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()

  def upsert_leaderboard(params, opts \\ []),
    do: LeaderboardEntry |> Ash.Changeset.for_create(:upsert, params, opts) |> Ash.create()
end
