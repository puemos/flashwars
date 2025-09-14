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
      accept [:type, :config, :rating_scope, :organization_id, :privacy]
      argument :study_set_id, :uuid, allow_nil?: false
      change relate_actor(:host)
      change set_attribute(:study_set_id, arg(:study_set_id))

      change fn changeset, _ctx ->
        case {Ash.Changeset.get_attribute(changeset, :organization_id),
              Ash.Changeset.get_attribute(changeset, :study_set_id)} do
          {nil, set_id} when not is_nil(set_id) ->
            case Ash.get(Flashwars.Content.StudySet, set_id, authorize?: false) do
              {:ok, set} ->
                Ash.Changeset.change_attribute(changeset, :organization_id, set.organization_id)

              _ ->
                changeset
            end

          _ ->
            changeset
        end
      end

      change fn changeset, _ctx ->
        case Ash.Changeset.get_attribute(changeset, :privacy) do
          :link_only ->
            Ash.Changeset.change_attribute(
              changeset,
              :link_token,
              __MODULE__.generate_link_token()
            )

          _ ->
            changeset
        end
      end

      validate present(:organization_id)
    end

    read :with_link_token do
      argument :token, :string, allow_nil?: false
      filter expr(privacy == :link_only and link_token == ^arg(:token))
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

    update :update_config do
      require_atomic? false
      accept [:config, :privacy]

      change fn changeset, _ctx ->
        case {Ash.Changeset.get_attribute(changeset, :privacy),
              Ash.Changeset.get_attribute(changeset, :link_token)} do
          {:link_only, nil} ->
            Ash.Changeset.change_attribute(
              changeset,
              :link_token,
              __MODULE__.generate_link_token()
            )

          _ ->
            changeset
        end
      end
    end

    # Update or insert an entry in config.players with validation
    update :set_player_info do
      require_atomic? false
      argument :player_key, :string, allow_nil?: false
      argument :player_info, :map, allow_nil?: false

      change fn changeset, _ctx ->
        key = Ash.Changeset.get_argument(changeset, :player_key)
        info = Ash.Changeset.get_argument(changeset, :player_info)

        cfg = changeset.data.config || %Flashwars.Games.GameRoomConfig{}
        players = cfg.players || %{}
        existing = Map.get(players, key)

        # resolve nickname: prefer provided, fallback to existing
        nickname =
          case info do
            %Flashwars.Games.PlayerInfo{nickname: n} -> n
            %{} = m -> m[:nickname] || m["nickname"]
          end

        trimmed =
          case (is_binary(nickname) && String.trim(nickname)) || nil do
            nil ->
              case existing do
                %Flashwars.Games.PlayerInfo{nickname: n} -> n
                _ -> nil
              end
            v -> v
          end

        cond do
          is_nil(trimmed) or byte_size(trimmed) < 1 or byte_size(trimmed) > 24 ->
            Ash.Changeset.add_error(changeset,
              field: :player_info,
              message: "invalid nickname"
            )

          true ->
            new_info =
              case info do
                %Flashwars.Games.PlayerInfo{} = s ->
                  # Keep other fields, override nickname
                  %{s | nickname: trimmed}

                %{} = m ->
                  %Flashwars.Games.PlayerInfo{
                    nickname: trimmed,
                    user_id: m[:user_id] || m["user_id"],
                    guest_id: m[:guest_id] || m["guest_id"],
                    score: m[:score] || m["score"] ||
                      (case existing do
                         %Flashwars.Games.PlayerInfo{score: sc} -> sc
                         _ -> 0
                       end),
                    joined_at: m[:joined_at] || m["joined_at"] || DateTime.utc_now(),
                    last_seen: m[:last_seen] || m["last_seen"] || DateTime.utc_now()
                  }
              end

            # Merge score increment if info.score is provided as delta
            new_info =
              case {existing, info} do
                {%Flashwars.Games.PlayerInfo{score: sc} = ex, %Flashwars.Games.PlayerInfo{score: inc}} when is_integer(inc) ->
                  %{ex | nickname: trimmed, score: sc + inc, last_seen: DateTime.utc_now()}
                {_ex, _} -> new_info
              end

            new_cfg = %Flashwars.Games.GameRoomConfig{cfg | players: Map.put(players, key, new_info)}

            Ash.Changeset.change_attribute(changeset, :config, new_cfg)
        end
      end
    end
  end

  policies do
    # Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # Org admin can do everything under their org (filter check)
    policy action_type([:read, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # Host (owner) can do everything
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:host)
    end

    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    # Public rooms are readable by anyone
    policy action_type(:read) do
      authorize_if expr(privacy == :public)
    end

    # Game participants can read (if applicable)
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.GameParticipantRead, []}
    end

    # Link-token based read is allowed when enabled
    policy action(:with_link_token) do
      authorize_if always()
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

    attribute :config, Flashwars.Games.GameRoomConfig,
      default: %{
        rounds: 10,
        types: ["multiple_choice"],
        time_limit_ms: nil,
        intermission_ms: 10000,
        players: %{}
      }

    attribute :rating_scope, :string

    attribute :privacy, :atom,
      constraints: [one_of: [:private, :link_only, :public]],
      default: :private

    attribute :link_token, :string
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

  def generate_link_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
