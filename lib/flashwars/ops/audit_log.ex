defmodule Flashwars.Ops.AuditLog do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Ops,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "audit_logs"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:action, :resource, :resource_id, :metadata, :actor_id]
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :action, :string, allow_nil?: false
    attribute :resource, :string, allow_nil?: false
    attribute :resource_id, :string
    attribute :metadata, :map, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :actor, Flashwars.Accounts.User
  end
end
