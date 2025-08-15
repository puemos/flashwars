defmodule Flashwars.Policies.OrgMemberCreate do
  @moduledoc "Authorizes create actions when the actor is a member of the organization referenced by organization_id."
  use Ash.Policy.SimpleCheck
  import Ash.Query
  alias Flashwars.Org.OrgMembership

  @impl true
  def describe(_opts), do: "actor is member of organization"

  @impl true
  def match?(actor, %{changeset: changeset}, _opts) do
    org_id = Ash.Changeset.get_attribute(changeset, :organization_id)

    if is_nil(org_id) or is_nil(actor) do
      false
    else
      OrgMembership
      |> filter(organization_id == ^org_id and user_id == ^actor.id)
      |> Ash.exists?(authorize?: false)
    end
  end

  def match?(_actor, _context, _opts), do: false
end
