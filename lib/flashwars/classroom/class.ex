defmodule Flashwars.Classroom.Class do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Classroom,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "classes"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:name, :description, :organization_id]
      validate present(:organization_id)
    end
  end

  policies do
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Flashwars.Org.Organization
    has_many :sections, Flashwars.Classroom.Section
  end
end
