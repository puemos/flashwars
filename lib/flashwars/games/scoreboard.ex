defmodule Flashwars.Games.Scoreboard do
  @moduledoc """
  Build scoreboards from submissions and configured players.
  """

  alias Flashwars.Games
  alias Flashwars.Games.{Players, GameRoom}

  @type entry :: %{
          user_id: integer() | nil,
          user: map() | nil,
          name: String.t(),
          score: non_neg_integer()
        }

  @doc """
  Scoreboard for a room based on user submissions only.
  """
  @spec for_room(%GameRoom{}) :: [entry()]
  def for_room(%{id: room_id}) do
    Games.list_submissions_for_room!(room_id, authorize?: false)
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, subs} ->
      total = Enum.reduce(subs, 0, fn s, acc -> acc + (s.score || 0) end)
      user = subs |> List.first() |> Map.get(:user)
      %{user_id: user_id, user: user, name: display_name(user), score: total}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Scoreboard including guests/configured players not present in submissions.
  """
  @spec final_for_room(%GameRoom{}) :: [entry()]
  def final_for_room(room) do
    merge(for_room(room), Players.player_entries(room))
  end

  @doc """
  Merge player entries into user entries, skipping duplicate names.
  """
  @spec merge([entry()], [map()]) :: [entry()]
  def merge(user_entries, player_entries) do
    existing = MapSet.new(Enum.map(user_entries, & &1.name))

    new_entries =
      player_entries
      |> Enum.reject(fn p -> MapSet.member?(existing, p.name) end)
      |> Enum.map(fn p -> Map.put_new(p, :user, nil) end)

    user_entries ++ new_entries
  end

  defp display_name(nil), do: "Unknown"

  defp display_name(%{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp display_name(_), do: "Player"
end

