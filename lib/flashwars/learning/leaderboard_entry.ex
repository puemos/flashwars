defmodule Flashwars.Learning.LeaderboardEntry do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Learning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "leaderboard_entries"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      upsert? true
      upsert_identity :unique_scope_user
      upsert_fields [:score, :submitted_at, :study_set_id]
      accept [:scope, :mode, :score, :submitted_at, :study_set_id]
      change relate_actor(:user)
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
    attribute :scope, :string

    attribute :mode, :atom,
      constraints: [one_of: [:flashcards, :learn, :test, :match, :game]],
      default: :game

    attribute :score, :integer, allow_nil?: false
    attribute :submitted_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet
  end

  identities do
    identity :unique_scope_user, [:scope, :mode, :user_id]
  end
end
