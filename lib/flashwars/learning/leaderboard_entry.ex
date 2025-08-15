defmodule Flashwars.Learning.LeaderboardEntry do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Learning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "leaderboard_entries"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      upsert? true
      upsert_identity :unique_scope_user
      upsert_fields [:score, :submitted_at, :study_set_id]
      accept [:scope, :mode, :score, :submitted_at, :study_set_id, :organization_id]
      change relate_actor(:user)

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

      validate present(:organization_id)
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

    # Org members can upsert leaderboard when associated to a set in their org; admins also allowed
    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgMemberViaStudySetCreate, []}
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :scope, :string

    attribute :mode, :atom,
      constraints: [one_of: [:flashcards, :learn, :test, :match, :game]],
      default: :game

    attribute :score, :integer, allow_nil?: false
    attribute :submitted_at, :utc_datetime
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet
    belongs_to :organization, Flashwars.Org.Organization
  end

  identities do
    identity :unique_scope_user, [:scope, :mode, :user_id]
  end
end
