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
      accept [:mode, :score, :started_at, :completed_at, :user_id, :study_set_id, :assignment_id]
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if {Flashwars.Policies.OrgMemberViaAssignmentOrSetRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
      authorize_if actor_attribute_equals(:site_admin, true)
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
