defmodule Flashwars.Learning.Session do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Learning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sessions"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      upsert? true
      upsert_identity :by_user_set_mode
      upsert_fields [:state, :last_saved_at]
      accept [:user_id, :study_set_id, :mode, :state, :last_saved_at]
    end

    read :for_user_set_mode do
      argument :user_id, :uuid, allow_nil?: false
      argument :study_set_id, :uuid, allow_nil?: false
      argument :mode, :atom, allow_nil?: false

      filter expr(
               user_id == ^arg(:user_id) and study_set_id == ^arg(:study_set_id) and
                 mode == ^arg(:mode)
             )

      prepare build(sort: [updated_at: :desc])
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if {Flashwars.Policies.OrgMemberViaStudySetRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :destroy]) do
      authorize_if relates_to_actor_via(:user)
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mode, :atom,
      constraints: [one_of: [:flashcards, :learn, :test, :match]],
      allow_nil?: false

    attribute :state, :map, default: %{}
    attribute :last_saved_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
  end

  identities do
    identity :by_user_set_mode, [:user_id, :study_set_id, :mode]
  end
end
