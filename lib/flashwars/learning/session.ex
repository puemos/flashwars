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
      accept [:study_set_id, :mode, :state, :last_saved_at]
      change relate_actor(:user)
    end

    read :for_user_set_mode do
      argument :study_set_id, :uuid, allow_nil?: false
      argument :mode, :atom, allow_nil?: false

      filter expr(
               user_id == ^actor(:id) and study_set_id == ^arg(:study_set_id) and
                 mode == ^arg(:mode)
             )

      prepare build(sort: [updated_at: :desc])
    end
  end

  policies do
    # 1. Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # 2. Org admin can do everything under their org
    policy action_type([:read, :create, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # 3. Owners (user) can do everything
    policy action_type([:read, :create, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end

    # 4. Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberViaStudySetRead, []}
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
