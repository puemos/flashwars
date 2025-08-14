defmodule Flashwars.Games.GameRoom do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "game_rooms"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:type, :config, :rating_scope, :organization_id]
      argument :study_set_id, :uuid, allow_nil?: false
      change relate_actor(:host)
      change set_attribute(:study_set_id, arg(:study_set_id))
    end

    update :start_game do
      accept []
      change set_attribute(:state, :countdown)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :advance_state do
      argument :new_state, :atom, allow_nil?: false
      change set_attribute(:state, arg(:new_state))
    end

    update :end_game do
      accept []
      change set_attribute(:state, :ended)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    # Host controls the game
    policy action_type([:create, :update]) do
      authorize_if relates_to_actor_via(:host)
    end

    # Players and org members can read
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:host)
      authorize_if {Flashwars.Policies.GameParticipantRead, []}
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :type, :atom, constraints: [one_of: [:duel, :party, :class_host]]

    attribute :state, :atom,
      constraints: [
        one_of: [:lobby, :countdown, :question, :lock, :reveal, :intermission, :ended]
      ],
      default: :lobby

    attribute :config, :map, default: %{}
    attribute :rating_scope, :string
    attribute :organization_id, :uuid

    attribute :started_at, :utc_datetime
    attribute :ended_at, :utc_datetime

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :host, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization

    has_many :rounds, Flashwars.Games.GameRound do
      sort number: :asc
    end

    has_many :submissions, Flashwars.Games.GameSubmission
  end
end
