defmodule Flashwars.Learning do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Learning.Attempt do
      define :create_attempt, action: :create
    end

    resource Flashwars.Learning.AttemptItem do
      define :create_attempt_item, action: :create
    end

    resource Flashwars.Learning.LeaderboardEntry do
      define :upsert_leaderboard, action: :upsert
    end

    resource Flashwars.Learning.Session
  end
end
