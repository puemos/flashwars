defmodule Flashwars.Classroom.Enrollment do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Classroom,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "enrollments"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:section_id, :role]
      change relate_actor(:user)
    end

    update :set_role do
      accept [:role]
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if {Flashwars.Policies.OrgMemberViaSectionClassRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :role, :atom, constraints: [one_of: [:student, :teacher]], default: :student
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :section, Flashwars.Classroom.Section, allow_nil?: false
    belongs_to :user, Flashwars.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_enrollment, [:section_id, :user_id]
  end
end
