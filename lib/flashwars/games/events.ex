defmodule Flashwars.Games.Events do
  @moduledoc """
  PubSub helpers and event names for game rooms.

  LiveViews and services should publish and subscribe using these helpers
  to keep topic naming consistent.
  """

  @topic_prefix "flash_wars:room:"

  @doc """
  Returns the PubSub topic for a given game room id.
  """
  def topic(room_id), do: @topic_prefix <> to_string(room_id)

  @doc """
  Subscribe current process to a room's topic.
  """
  def subscribe(room_id) do
    Phoenix.PubSub.subscribe(Flashwars.PubSub, topic(room_id))
  end

  @doc """
  Broadcast an event map to the room topic.
  """
  def broadcast(room_id, event) when is_map(event) do
    Phoenix.PubSub.broadcast(Flashwars.PubSub, topic(room_id), event)
  end
end

