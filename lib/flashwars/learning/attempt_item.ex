defmodule Flashwars.Learning.AttemptItem do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Learning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "attempt_items"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
        :attempt_id,
        :term_id,
        :answer,
        :correct,
        :score,
        :evaluated_at,
        :grade,
        :response_time_ms,
        :confidence,
        :prev_interval_days,
        :next_interval_days,
        :s_before,
        :s_after,
        :d_before,
        :d_after,
        :queue_type,
        :app_version,
        :device,
        :ai_confidence,
        :ai_explanation,
        :organization_id
      ]

      change fn changeset, _ctx ->
        case Ash.Changeset.get_attribute(changeset, :organization_id) do
          nil ->
            case Ash.Changeset.get_attribute(changeset, :attempt_id) do
              nil ->
                changeset

              att_id ->
                with {:ok, att} <- Ash.get(Flashwars.Learning.Attempt, att_id, authorize?: false) do
                  Ash.Changeset.change_attribute(changeset, :organization_id, att.organization_id)
                else
                  _ -> changeset
                end
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
    policy action_type([:read, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # Owners (user) can do everything
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via([:attempt, :user])
    end

    # Attempt owners can create items for their attempt; org admins also allowed
    policy action_type(:create) do
      authorize_if {Flashwars.Policies.AttemptOwnerCreate, []}
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :answer, :string
    attribute :correct, :boolean, default: false
    attribute :score, :integer, default: 0
    attribute :evaluated_at, :utc_datetime
    attribute :grade, :atom, constraints: [one_of: [:again, :hard, :good, :easy]]
    attribute :response_time_ms, :integer
    attribute :confidence, :integer
    attribute :prev_interval_days, :float
    attribute :next_interval_days, :float
    attribute :s_before, :float
    attribute :s_after, :float
    attribute :d_before, :float
    attribute :d_after, :float
    attribute :queue_type, :atom, constraints: [one_of: [:learning, :review, :relearn, :cram]]
    attribute :app_version, :string
    attribute :device, :string
    attribute :ai_confidence, :float
    attribute :ai_explanation, :string
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :attempt, Flashwars.Learning.Attempt, allow_nil?: false
    belongs_to :term, Flashwars.Content.Term, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
  end
end
