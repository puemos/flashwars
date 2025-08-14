defmodule Flashwars.Ops.Notification do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Ops,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notifications"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:type, :data, :read_at]
      change relate_actor(:user)
    end

    update :mark_read do
      change set_attribute(:read_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :type, :string, allow_nil?: false
    attribute :data, :map, default: %{}
    attribute :read_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
  end
end
