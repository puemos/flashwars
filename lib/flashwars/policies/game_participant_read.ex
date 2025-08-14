defmodule Flashwars.Policies.GameParticipantRead do
  @moduledoc "Authorizes read when actor has submitted to the game (participant)."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(exists(submissions, user_id == actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor has submissions in this game"
end
