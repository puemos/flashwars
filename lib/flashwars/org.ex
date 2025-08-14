defmodule Flashwars.Org do
  use Ash.Domain, otp_app: :flashwars
  require Ash.Query

  resources do
    resource Flashwars.Org.Organization
    resource Flashwars.Org.OrgMembership
    resource Flashwars.Org.OrgDomain
  end

  alias Flashwars.Org.{Organization, OrgMembership, OrgDomain}

  # Organization
  def create_organization(params, opts \\ []) do
    Organization |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()
  end

  def add_org_domain(params, opts \\ []) do
    OrgDomain |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()
  end

  def add_member(params, opts \\ []) do
    OrgMembership |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()
  end
end
