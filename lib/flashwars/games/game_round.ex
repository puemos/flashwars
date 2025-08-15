defmodule Flashwars.Games.GameRound do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "game_rounds"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
        :number,
        :state,
        :question_data,
        :started_at,
        :ended_at,
        :game_room_id,
        :organization_id
      ]

      change fn changeset, _ctx ->
        case {Ash.Changeset.get_attribute(changeset, :organization_id),
              Ash.Changeset.get_attribute(changeset, :game_room_id)} do
          {nil, room_id} when not is_nil(room_id) ->
            case Ash.get(Flashwars.Games.GameRoom, room_id, authorize?: false) do
              {:ok, room} ->
                Ash.Changeset.change_attribute(changeset, :organization_id, room.organization_id)

              _ ->
                changeset
            end

          _ ->
            changeset
        end
      end

      validate present(:organization_id)
    end

    # Generate a new round for a room with a 4-option MCQ from the room's study set
    create :generate_for_room do
      accept [:state, :started_at]
      argument :game_room_id, :uuid, allow_nil?: false
      argument :strategy, :atom, allow_nil?: true

      change fn changeset, _ctx ->
        room_id = Ash.Changeset.get_argument(changeset, :game_room_id)

        with {:ok, room} <- Ash.get(Flashwars.Games.GameRoom, room_id, authorize?: false) do
          last_round_number =
            __MODULE__
            |> Ash.Query.filter(game_room_id == ^room.id)
            |> Ash.Query.sort(number: :desc)
            |> Ash.Query.limit(1)
            |> Ash.read!(authorize?: false)
            |> case do
              [%{number: n}] -> n
              _ -> 0
            end

          prev_term_ids =
            __MODULE__
            |> Ash.Query.filter(game_room_id == ^room.id)
            |> Ash.read!(authorize?: false)
            |> Enum.flat_map(fn r ->
              case r.question_data do
                %{"term_id" => tid} when is_binary(tid) -> [tid]
                %{term_id: tid} when is_binary(tid) -> [tid]
                _ -> []
              end
            end)

          item =
            Flashwars.Learning.Engine.generate_item(room.study_set_id,
              exclude_term_ids: prev_term_ids,
              strategy: Ash.Changeset.get_argument(changeset, :strategy)
            )

          changeset
          |> Ash.Changeset.change_attributes(%{
            game_room_id: room.id,
            organization_id: room.organization_id,
            number: last_round_number + 1,
            state: :question,
            question_data: item,
            started_at: Ash.Changeset.get_attribute(changeset, :started_at) || DateTime.utc_now()
          })
        else
          _ ->
            changeset
        end
      end

      validate present(:organization_id)
      validate present(:game_room_id)
    end

    read :for_room_token do
      argument :token, :string, allow_nil?: false
      filter expr(game_room.privacy == :link_only and game_room.link_token == ^arg(:token))
      prepare build(sort: [number: :asc])
    end
  end

  policies do
    # Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # Org admin can do everything under their org
    policy action_type([:read, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # Host (owner) can do everything
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via([:game_room, :host])
    end

    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    # Game participants can read (if applicable)
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.GameParticipantViaRoomRead, []}
    end

    # Allow reading rounds when accessed via room link token
    policy action(:for_room_token) do
      authorize_if always()
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
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :game_room, Flashwars.Games.GameRoom, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
  end

  # Item generation now handled by Flashwars.Learning.Engine
end
