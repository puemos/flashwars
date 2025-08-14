defmodule Flashwars.Org.OrgMembership do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Org,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "org_memberships"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:role, :organization_id]
      change relate_actor(:user)
    end

    update :set_role do
      accept [:role]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :role, :atom, constraints: [one_of: [:member, :admin]], default: :member

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Flashwars.Org.Organization, allow_nil?: false
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_member, [:organization_id, :user_id]
  end
end
