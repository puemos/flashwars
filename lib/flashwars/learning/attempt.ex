defmodule Flashwars.Learning.Attempt do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Learning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "attempts"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:mode, :score, :started_at, :completed_at, :study_set_id, :assignment_id]
      change relate_actor(:user)
    end
  end

  policies do
    # 1. Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # 2. Org admin can do everything under their org (filter check)
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # 3. Owners (user) can do everything
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end

    # 4. Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberViaAssignmentOrSetRead, []}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mode, :atom,
      constraints: [one_of: [:flashcards, :learn, :test, :match, :game]],
      default: :test

    attribute :score, :integer, default: 0
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
    belongs_to :assignment, Flashwars.Classroom.Assignment
    has_many :items, Flashwars.Learning.AttemptItem
  end
end
