defmodule Flashwars.Learning.UserStats do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Learning,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @moduledoc """
  Per-user/per-organization learning stats for gamification.

  Tracks XP, level, streaks, and last round timestamp.
  """

  postgres do
    table "user_stats"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:user_id, :organization_id, :xp, :level, :streak, :longest_streak, :last_round_at]
      change relate_actor(:user)
      validate present([:user_id])
    end

    create :upsert do
      upsert? true
      upsert_identity :by_user_org
      accept [:user_id, :organization_id, :xp, :level, :streak, :longest_streak, :last_round_at]
      upsert_fields [:xp, :level, :streak, :longest_streak, :last_round_at]
      change relate_actor(:user)
      validate present([:user_id])
    end

    read :for_user_org do
      argument :organization_id, :uuid, allow_nil?: true
      filter expr(user_id == ^actor(:id) and organization_id == ^arg(:organization_id))
    end
  end

  policies do
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if relates_to_actor_via(:user)
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :xp, :integer, default: 0
    attribute :level, :integer, default: 1
    attribute :streak, :integer, default: 0
    attribute :longest_streak, :integer, default: 0
    attribute :last_round_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
  end

  identities do
    identity :by_user_org, [:user_id, :organization_id]
  end
end

