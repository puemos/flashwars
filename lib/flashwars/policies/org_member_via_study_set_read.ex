defmodule Flashwars.Policies.OrgMemberViaStudySetRead do
  @moduledoc "Authorizes read when actor is a member via related study_set.organization."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(
      not is_nil(study_set.organization_id) and
        exists(study_set.organization.memberships, user_id == actor(:id))
    )
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member via study_set.organization"
end
