defmodule Flashwars.Games.GameSubmission do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "game_submissions"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:answer, :correct, :score, :submitted_at, :game_round_id, :user_id]
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if {Flashwars.Policies.OrgMemberViaGameRoomOrgRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :destroy]) do
      authorize_if relates_to_actor_via(:user)
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :answer, :string
    attribute :correct, :boolean, default: false
    attribute :score, :integer, default: 0
    attribute :submitted_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :game_room, Flashwars.Games.GameRoom, allow_nil?: false
    belongs_to :game_round, Flashwars.Games.GameRound, allow_nil?: false
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
  end

  identities do
    identity :one_submission_per_round, [:game_round_id, :user_id]
  end
end
