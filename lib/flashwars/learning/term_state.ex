defmodule Flashwars.Learning.TermState do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Learning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Persistent per-user, per-term learning state used for scheduling.

  Fields mirror the neuroscience-informed model:
  - stability_days (S)
  - difficulty (D)
  - prev_interval_days
  - streak, lapses, relearn_stage
  - t_last (timestamp of last review)
  - next_due_at (when to show next)
  - optional last response signals (rt_ms, conf)
  """

  postgres do
    table "term_states"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
        :stability_days,
        :difficulty,
        :prev_interval_days,
        :streak,
        :lapses,
        :relearn_stage,
        :t_last,
        :next_due_at,
        :last_rt_ms,
        :last_conf,
        :term_id,
        :study_set_id,
        :organization_id
      ]

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

    # Upsert by user/term to simplify review updates
    create :upsert do
      upsert? true
      upsert_identity :by_user_term

      upsert_fields [
        :stability_days,
        :difficulty,
        :prev_interval_days,
        :streak,
        :lapses,
        :relearn_stage,
        :t_last,
        :next_due_at,
        :last_rt_ms,
        :last_conf,
        :term_id,
        :study_set_id,
        :organization_id
      ]

      accept [
        :stability_days,
        :difficulty,
        :prev_interval_days,
        :streak,
        :lapses,
        :relearn_stage,
        :t_last,
        :next_due_at,
        :last_rt_ms,
        :last_conf,
        :term_id,
        :study_set_id,
        :organization_id
      ]

      change relate_actor(:user)

      change fn changeset, _ctx ->
        # ensure org from study set if missing
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

    read :for_user_set do
      argument :study_set_id, :uuid, allow_nil?: false
      filter expr(user_id == ^actor(:id) and study_set_id == ^arg(:study_set_id))
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

    # Owners (user)
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end

    # Org members can create under their org via the set; admins also allowed
    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgMemberViaStudySetCreate, []}
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :stability_days, :float, default: 0.3
    attribute :difficulty, :float, default: 6.0
    attribute :prev_interval_days, :float, default: 0.0
    attribute :streak, :integer, default: 0
    attribute :lapses, :integer, default: 0
    attribute :relearn_stage, :integer, default: 0
    attribute :t_last, :utc_datetime
    attribute :next_due_at, :utc_datetime
    attribute :last_rt_ms, :integer
    attribute :last_conf, :integer
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :term, Flashwars.Content.Term, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
  end

  identities do
    identity :by_user_term, [:user_id, :term_id]
  end
end
