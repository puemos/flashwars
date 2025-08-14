defmodule Flashwars.Content.SetTag do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "set_tags"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :create, :destroy]
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :destroy]) do
      authorize_if relates_to_actor_via([:study_set, :owner])
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
    belongs_to :tag, Flashwars.Content.Tag, allow_nil?: false
  end

  identities do
    identity :unique_pair, [:study_set_id, :tag_id]
  end
end
