defmodule Flashwars.Games.ScoreboardTest do
  use ExUnit.Case, async: true

  alias Flashwars.Games.Scoreboard

  test "merge skips duplicate names" do
    users = [
      %{user_id: 1, user: nil, name: "Alice", score: 5},
      %{user_id: 2, user: nil, name: "Bob", score: 3}
    ]

    players = [
      %{user_id: nil, name: "Alice", score: 0},
      %{user_id: nil, name: "Charlie", score: 0}
    ]

    merged = Scoreboard.merge(users, players)
    assert Enum.any?(merged, &(&1.name == "Alice"))
    assert Enum.any?(merged, &(&1.name == "Bob"))
    assert Enum.any?(merged, &(&1.name == "Charlie"))
    # Only one Alice
    assert Enum.count(merged, &(&1.name == "Alice")) == 1
  end

  test "merge guests-only yields player entries" do
    users = []
    players = [%{user_id: nil, name: "Guest 1", score: 0}, %{user_id: nil, name: "Guest 2", score: 0}]

    merged = Scoreboard.merge(users, players)
    assert Enum.map(merged, & &1.name) == ["Guest 1", "Guest 2"]
  end

  test "merge maintains user ordering by score" do
    users = [
      %{user_id: 1, user: nil, name: "Top", score: 10},
      %{user_id: 2, user: nil, name: "Low", score: 1}
    ]

    players = [%{user_id: nil, name: "Mid", score: 0}]

    merged = Scoreboard.merge(users, players)
    assert Enum.map(merged, & &1.name) == ["Top", "Low", "Mid"]
  end
end

