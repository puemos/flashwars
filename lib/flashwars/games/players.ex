defmodule Flashwars.Games.Players do
  @moduledoc """
  Helpers for working with GameRoomConfig players.

  Normalizes player info, provides typed reads, and utilities for
  extracting nicknames and entries suitable for scoreboards.
  """

  alias Flashwars.Games.{GameRoom, GameRoomConfig, PlayerInfo}

  @type entry :: %{
          optional(:user_id) => integer() | nil,
          name: String.t(),
          score: non_neg_integer()
        }

  @doc """
  Returns a list of player entries (guests and users with zero score) from a room struct.
  """
  @spec player_entries(%GameRoom{}) :: [entry()]
  def player_entries(%{config: %GameRoomConfig{players: players}}) when is_map(players) do
    players
    |> Map.values()
    |> Enum.map(&normalize_entry/1)
    |> Enum.filter(& &1)
  rescue
    _ -> []
  end

  def player_entries(_), do: []

  defp normalize_entry(%PlayerInfo{} = pi) do
    %{
      user_id: normalize_user_id(pi.user_id),
      name: pi.nickname,
      score: 0
    }
  end

  defp normalize_entry(%{} = m) do
    nickname = m[:nickname] || m["nickname"]
    uid = m[:user_id] || m["user_id"]

    if is_binary(nickname) do
      %{
        user_id: normalize_user_id(uid),
        name: nickname,
        score: 0
      }
    else
      nil
    end
  end

  defp normalize_entry(_), do: nil

  defp normalize_user_id(nil), do: nil
  defp normalize_user_id(uid) when is_binary(uid) do
    case Integer.parse(uid) do
      {i, _} -> i
      _ -> nil
    end
  end
  defp normalize_user_id(_), do: nil
end

