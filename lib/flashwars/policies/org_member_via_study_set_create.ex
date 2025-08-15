defmodule Flashwars.Policies.OrgMemberViaStudySetCreate do
  @moduledoc "Authorizes create when actor is a member of the organization of the provided study_set."
  use Ash.Policy.SimpleCheck
  import Ash.Query
  alias Flashwars.Content.StudySet
  alias Flashwars.Org.OrgMembership

  @impl true
  def describe(_opts), do: "actor is member of organization via study_set"

  @impl true
  def match?(actor, %{changeset: changeset}, _opts) do
    set_id = Ash.Changeset.get_attribute(changeset, :study_set_id)

    if is_nil(set_id) or is_nil(actor) do
      false
    else
      with {:ok, set} <- Ash.get(StudySet, set_id, authorize?: false),
           org_id when not is_nil(org_id) <- set.organization_id do
        OrgMembership
        |> filter(organization_id == ^org_id and user_id == ^actor.id)
        |> Ash.exists?(authorize?: false)
      else
        _ -> false
      end
    end
  end

  def match?(_actor, _context, _opts), do: false
end
