defmodule Flashwars.Policies.GameParticipantViaRoomRead do
  @moduledoc "Authorizes read when the actor has participated in the parent game room."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    Ash.Expr.expr(exists(game_room.submissions, user_id == ^actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is a participant in the parent game room"
end
