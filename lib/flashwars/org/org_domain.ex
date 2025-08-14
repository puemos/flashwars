defmodule Flashwars.Org.OrgDomain do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Org,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "org_domains"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:organization_id, :domain]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end

    policy action_type([:read, :create, :destroy]) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :domain, :string, allow_nil?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Flashwars.Org.Organization, allow_nil?: false
  end

  identities do
    identity :unique_org_domain, [:organization_id, :domain]
  end
end
