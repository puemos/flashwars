defmodule Flashwars.Games.GameSubmission do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "game_submissions"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:answer, :correct, :score, :submitted_at, :game_round_id, :organization_id]
      change relate_actor(:user)

      change fn changeset, _ctx ->
        # Backfill game_room_id and organization_id from game_round if missing
        round_id = Ash.Changeset.get_attribute(changeset, :game_round_id)

        changeset =
          case {Ash.Changeset.get_attribute(changeset, :game_room_id), round_id} do
            {nil, round_id} when not is_nil(round_id) ->
              case Ash.get(Flashwars.Games.GameRound, round_id, authorize?: false) do
                {:ok, round} ->
                  changeset =
                    Ash.Changeset.change_attribute(changeset, :game_room_id, round.game_room_id)

                  case Ash.Changeset.get_attribute(changeset, :organization_id) do
                    nil ->
                      Ash.Changeset.change_attribute(
                        changeset,
                        :organization_id,
                        round.organization_id
                      )

                    _ ->
                      changeset
                  end

                _ ->
                  changeset
              end

            _ ->
              changeset
          end

        # If organization_id is still nil but game_room_id present, try to load room
        case {
          Ash.Changeset.get_attribute(changeset, :organization_id),
          Ash.Changeset.get_attribute(changeset, :game_room_id)
        } do
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

      # Business rule: scoring
      # If no explicit score provided, award points to the first correct submission
      # based on response time. Subsequent correct submissions for the same round get 0.
      change fn changeset, _ctx ->
        score = Ash.Changeset.get_attribute(changeset, :score)
        correct? = Ash.Changeset.get_attribute(changeset, :correct)
        round_id = Ash.Changeset.get_attribute(changeset, :game_round_id)
        submitted_at = Ash.Changeset.get_attribute(changeset, :submitted_at) || DateTime.utc_now()

        cond do
          not is_nil(score) ->
            changeset

          correct? == true and not is_nil(round_id) ->
            already_correct? =
              __MODULE__
              |> Ash.Query.filter(game_round_id == ^round_id and correct == true)
              |> Ash.Query.limit(1)
              |> Ash.read!(authorize?: false)
              |> case do
                [] -> false
                _ -> true
              end

            if already_correct? do
              Ash.Changeset.change_attribute(changeset, :score, 0)
            else
              # Compute time-based score using round start and config time limit
              ms_taken =
                case Ash.get(Flashwars.Games.GameRound, round_id, authorize?: false) do
                  {:ok, round} ->
                    start = round.started_at || submitted_at
                    seconds = max(0, DateTime.diff(submitted_at, start, :second))
                    seconds * 1000
                  _ ->
                    0
                end

              # Load time limit from room config if available
              limit_ms =
                case Ash.get(Flashwars.Games.GameRound, round_id, authorize?: false) do
                  {:ok, round} ->
                    case Ash.get(Flashwars.Games.GameRoom, round.game_room_id, authorize?: false) do
                      {:ok, room} -> room.config && room.config.time_limit_ms
                      _ -> nil
                    end
                  _ -> nil
                end

              points = Flashwars.Games.Scoring.score(true, ms_taken, limit_ms: limit_ms || 10_000)
              Ash.Changeset.change_attribute(changeset, :score, points)
            end

          true ->
            Ash.Changeset.change_attribute(changeset, :score, 0)
        end
      end
    end

    read :for_room do
      argument :game_room_id, :uuid, allow_nil?: false
      filter expr(game_room_id == ^arg(:game_room_id))
    end
  end

  policies do
    # Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # Org admin can do everything under their org
    policy action_type([:read, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # Owners (user) can do everything
    policy action_type([:read, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgMemberViaRoundCreate, []}
    end

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    # Participants can read all submissions in their game room
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.GameParticipantViaRoomRead, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :answer, :string
    attribute :correct, :boolean, default: false
    # No default so we can detect when a client did not provide a score
    # and compute it in the create change.
    attribute :score, :integer
    attribute :submitted_at, :utc_datetime
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :game_room, Flashwars.Games.GameRoom, allow_nil?: false
    belongs_to :game_round, Flashwars.Games.GameRound, allow_nil?: false
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
  end

  identities do
    identity :one_submission_per_round, [:game_round_id, :user_id]
  end
end
