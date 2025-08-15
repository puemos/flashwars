defmodule Flashwars.Content.Tag do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tags"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :organization_id]
    end

    update :update do
      accept [:name]
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Flashwars.Org.Organization

    many_to_many :study_sets, Flashwars.Content.StudySet do
      through Flashwars.Content.SetTag
      source_attribute_on_join_resource :tag_id
      destination_attribute_on_join_resource :study_set_id
    end
  end

  identities do
    identity :unique_name_per_org, [:organization_id, :name]
  end
end
