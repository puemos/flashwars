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
      accept [:role, :organization_id, :user_id]
    end

    update :set_role do
      accept [:role]
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end

    read :for_org_and_user do
      argument :organization_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and user_id == ^arg(:user_id))
    end
  end

  policies do
    # Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # Org admin can read, update, destroy
    policy action_type([:read, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # Org members can read
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    # Org admins can create
    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Users can read their own memberships
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
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
