defmodule Flashwars.Policies.OrgMemberRead do
  @moduledoc "Authorizes read when actor is a member of the resource's organization."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(not is_nil(organization_id) and exists(organization.memberships, user_id == ^actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member of resource organization"
end
