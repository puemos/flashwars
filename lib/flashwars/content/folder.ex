defmodule Flashwars.Content.Folder do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "folders"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  policies do
    policy always() do
      forbid_if always()
    end

    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end

    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    policy always() do
      authorize_if actor_attribute_equals(:site_admin, true)
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
    belongs_to :owner, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
    has_many :study_sets, Flashwars.Content.StudySet, destination_attribute: :folder_id
  end
end
