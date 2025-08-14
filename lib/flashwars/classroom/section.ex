defmodule Flashwars.Classroom.Section do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Classroom,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sections"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:name, :class_id]
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberViaClassRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :class, Flashwars.Classroom.Class, allow_nil?: false
    has_many :enrollments, Flashwars.Classroom.Enrollment
    has_many :assignments, Flashwars.Classroom.Assignment
  end
end
