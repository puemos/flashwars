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

  Always returns a list sorted by score (desc) across all participants,
  merging registered users (from DB submissions) and configured players
  (from the room config). Registered users are matched by user_id and not
  duplicated even if they also appear in the config players with a different
  nickname.
  """
  @spec final_for_room(%GameRoom{} | binary()) :: [entry()]
  def final_for_room(%GameRoom{id: room_id}), do: final_for_room(room_id)

  def final_for_room(room_id) when is_binary(room_id) do
    # Always fetch fresh room so all clients see up-to-date guest scores
    room =
      case Games.get_game_room_by_id(room_id, authorize?: false) do
        {:ok, r} -> r
        _ -> %GameRoom{config: %Flashwars.Games.GameRoomConfig{players: %{}}}
      end

    user_entries = for_room(room)
    player_entries = Players.player_entries(room)

    user_entries
    |> merge(player_entries)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Merge player entries into user entries.

  - Registered users (player.user_id present) are deduplicated by user_id.
  - Guests (no user_id) are deduplicated by name to avoid duplicates.
  - Merged list preserves the original user_entries ordering; player_entries
    are appended (caller may sort afterwards if desired).
  """
  @spec merge([entry()], [map()]) :: [entry()]
  def merge(user_entries, player_entries) do
    existing_user_ids =
      user_entries
      |> Enum.map(& &1.user_id)
      |> Enum.filter(& &1)
      |> MapSet.new()

    existing_names = MapSet.new(Enum.map(user_entries, & &1.name))

    new_entries =
      player_entries
      # Drop any player that corresponds to a registered user already present
      |> Enum.reject(fn p -> p[:user_id] && MapSet.member?(existing_user_ids, p[:user_id]) end)
      # For guests (no user_id), avoid duplicate names
      |> Enum.reject(fn p -> is_nil(p[:user_id]) and MapSet.member?(existing_names, p[:name]) end)
      |> Enum.map(fn p -> Map.put_new(p, :user, nil) end)

    user_entries ++ new_entries
  end

  defp display_name(nil), do: "Unknown"

  defp display_name(%{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp display_name(_), do: "Player"
end
