defmodule Flashwars.Policies.GameParticipantViaRoomRead do
  @moduledoc "Authorizes read when actor has submissions via game_room relationship."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(exists(game_room.submissions, user_id == actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor has submissions via game_room"
end
