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
            case Ash.get(Flashwars.Content.StudySet, set_id) do
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

    attribute :config, :map, default: %{}
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
