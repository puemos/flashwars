defmodule Flashwars.Classroom.Assignment do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Classroom,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "assignments"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:mode, :due_at, :section_id, :study_set_id]
    end
  end

  policies do
    policy always(), do: forbid_if(always())

    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberViaSectionClassRead, []}
      authorize_if actor_attribute_equals(:site_admin, true)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mode, :atom,
      constraints: [one_of: [:flashcards, :learn, :test, :match, :game]],
      default: :test

    attribute :due_at, :utc_datetime
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :section, Flashwars.Classroom.Section, allow_nil?: false
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
  end
end
