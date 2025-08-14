defmodule Flashwars.Org.Organization do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Org,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:name, :support_contact]
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end

    # org admins and site admins can manage, members can read
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:site_admin, true)
      authorize_if relates_to_actor_via([:memberships, :user])
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :support_contact, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :memberships, Flashwars.Org.OrgMembership
    has_many :domains, Flashwars.Org.OrgDomain
  end
end
