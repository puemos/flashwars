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
    defaults [:read, :create, :update, :destroy]
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:attempt, :user])
      authorize_if {Flashwars.Policies.OrgMemberViaAssignmentOrSetRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if relates_to_actor_via([:attempt, :user])
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :answer, :string
    attribute :correct, :boolean, default: false
    attribute :score, :integer, default: 0
    attribute :evaluated_at, :utc_datetime
    attribute :ai_confidence, :float
    attribute :ai_explanation, :string
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :attempt, Flashwars.Learning.Attempt, allow_nil?: false
    belongs_to :term, Flashwars.Content.Term, allow_nil?: false
  end
end
