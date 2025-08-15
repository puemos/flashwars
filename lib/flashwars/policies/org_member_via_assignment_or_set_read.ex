defmodule Flashwars.Policies.OrgMemberViaAssignmentOrSetRead do
  @moduledoc """
  Authorizes read when actor is a member of the organization through either
  the related assignment or related study_set.
  """
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    Ash.Expr.expr(
      exists(study_set.organization.memberships, user_id == ^actor(:id)) or
        (not is_nil(assignment_id) and
           exists(assignment.organization.memberships, user_id == ^actor(:id)))
    )
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member via assignment or study_set organization"
end
