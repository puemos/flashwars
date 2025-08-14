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
      accept [:name]
    end

    update :update do
      accept [:name]
    end

    destroy :destroy
  end

  policies do
    # 1. Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    many_to_many :study_sets, Flashwars.Content.StudySet do
      through Flashwars.Content.SetTag
      source_attribute_on_join_resource :tag_id
      destination_attribute_on_join_resource :study_set_id
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
