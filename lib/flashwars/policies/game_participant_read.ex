defmodule Flashwars.Policies.GameParticipantRead do
  @moduledoc "Authorizes read when the actor has participated in the game room (e.g., submitted an answer)."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    Ash.Expr.expr(exists(submissions, user_id == ^actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is a participant in the game room"
end
