defmodule Flashwars.Policies.OrgMemberViaAssignmentOrSetCreate do
  @moduledoc "Authorizes create when actor is a member of the organization via assignment or study_set."
  use Ash.Policy.SimpleCheck
  import Ash.Query
  alias Flashwars.Content.StudySet
  alias Flashwars.Classroom.Assignment
  alias Flashwars.Org.OrgMembership

  @impl true
  def describe(_opts), do: "actor is member via assignment or study_set organization"

  @impl true
  def match?(actor, %{changeset: changeset}, _opts) do
    set_id = Ash.Changeset.get_attribute(changeset, :study_set_id)
    asg_id = Ash.Changeset.get_attribute(changeset, :assignment_id)

    org_id =
      cond do
        not is_nil(set_id) ->
          case Ash.get(StudySet, set_id, authorize?: false) do
            {:ok, set} -> set.organization_id
            _ -> nil
          end

        not is_nil(asg_id) ->
          case Ash.get(Assignment, asg_id, authorize?: false) do
            {:ok, asg} -> asg.organization_id
            _ -> nil
          end

        true ->
          nil
      end

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
