defmodule Flashwars.Policies.OrgMemberViaSectionClassRead do
  @moduledoc "Authorizes read when actor is a member via section.class.organization."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(exists(section.class.organization.memberships, user_id == actor(:id)))
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member via section.class.organization"
end
