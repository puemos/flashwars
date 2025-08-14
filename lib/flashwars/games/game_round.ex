defmodule Flashwars.Games.GameRound do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "game_rounds"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:number, :state, :question_data, :started_at, :ended_at, :game_room_id]
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:game_room, :host])
      authorize_if {Flashwars.Policies.GameParticipantViaRoomRead, []}
      authorize_if {Flashwars.Policies.OrgMemberViaGameRoomOrgRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:site_admin, true)
      authorize_if relates_to_actor_via([:game_room, :host])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :number, :integer, allow_nil?: false

    attribute :state, :atom,
      constraints: [one_of: [:question, :lock, :reveal, :intermission]],
      default: :question

    attribute :question_data, :map, default: %{}
    attribute :started_at, :utc_datetime
    attribute :ended_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :game_room, Flashwars.Games.GameRoom, allow_nil?: false
  end
end
