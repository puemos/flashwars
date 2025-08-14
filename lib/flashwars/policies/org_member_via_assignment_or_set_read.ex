defmodule Flashwars.Policies.OrgMemberViaAssignmentOrSetRead do
  @moduledoc "Authorizes read when actor is a member via attempt.assignment.section.class.organization or via attempt.study_set.organization."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(
      exists(assignment.section.class.organization.memberships, user_id == actor(:id)) or
        (not is_nil(study_set.organization_id) and
           exists(study_set.organization.memberships, user_id == actor(:id)))
    )
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member via assignment.section.class.org or study_set.org"
end
