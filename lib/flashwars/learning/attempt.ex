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
      accept [
        :mode,
        :score,
        :started_at,
        :completed_at,
        :study_set_id,
        :assignment_id,
        :organization_id
      ]

      change relate_actor(:user)

      change fn changeset, _ctx ->
        # Prefer study_set.organization; if absent, use assignment.organization
        case Ash.Changeset.get_attribute(changeset, :organization_id) do
          nil ->
            org_from_set =
              case Ash.Changeset.get_attribute(changeset, :study_set_id) do
                nil ->
                  nil

                set_id ->
                  case Ash.get(Flashwars.Content.StudySet, set_id, authorize?: false) do
                    {:ok, set} -> set.organization_id
                    _ -> nil
                  end
              end

            org_id =
              if is_nil(org_from_set) do
                case Ash.Changeset.get_attribute(changeset, :assignment_id) do
                  nil ->
                    nil

                  asg_id ->
                    case Ash.get(Flashwars.Classroom.Assignment, asg_id, authorize?: false) do
                      {:ok, asg} -> asg.organization_id
                      _ -> nil
                    end
                end
              else
                org_from_set
              end

            if is_nil(org_id) do
              changeset
            else
              Ash.Changeset.change_attribute(changeset, :organization_id, org_id)
            end

          _ ->
            changeset
        end
      end

      validate present(:study_set_id)
      validate present(:organization_id)
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

    # Owners (user) can do everything
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end

    # Org members (students) can create attempts under their org via assignment or set
    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgMemberViaAssignmentOrSetCreate, []}
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mode, :atom,
      constraints: [one_of: [:flashcards, :learn, :test, :game]],
      default: :test

    attribute :score, :integer, default: 0
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
    attribute :organization_id, :uuid

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
    belongs_to :assignment, Flashwars.Classroom.Assignment
    belongs_to :organization, Flashwars.Org.Organization
    has_many :items, Flashwars.Learning.AttemptItem
  end
end
