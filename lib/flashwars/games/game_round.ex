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
    # 1. Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # 2. Org admin can do everything under their org
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # 3. Host (owner) can do everything
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if relates_to_actor_via([:game_room, :host])
    end

    # 4. Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberViaGameRoomOrgRead, []}
    end

    # 5. Game participants can read (if applicable)
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.GameParticipantViaRoomRead, []}
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
