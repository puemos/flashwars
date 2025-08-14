defmodule Flashwars.Policies.OrgMemberViaClassRead do
  @moduledoc "Authorizes read when actor is a member via the resource's class.organization."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(exists(class.organization.memberships, user_id == actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member via class.organization"
end
