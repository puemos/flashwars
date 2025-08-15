defmodule Flashwars.Policies.OrgMemberViaStudySetRead do
  @moduledoc "Authorizes read when actor is a member of the organization through the related study_set."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    Ash.Expr.expr(exists(study_set.organization.memberships, user_id == ^actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member via study_set.organization"
end
