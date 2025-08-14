defmodule Flashwars.Policies.OrgAdminRead do
  @moduledoc """
  Authorizes when the actor is an admin of the resource's organization.

  This filter check should be used in Ash policies to allow org admins to perform actions
  on resources that belong to their organization.

  It expects the resource to have an `organization_id` field and a relationship
  `organization.memberships` with a `role` field.
  """

  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(
      not is_nil(organization_id) and
        exists(organization.memberships, user_id == actor(:id) and role == :admin)
    )
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is admin of resource organization"
end
