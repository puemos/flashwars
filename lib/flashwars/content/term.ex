defmodule Flashwars.Content.Term do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "terms"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:term, :definition, :position, :study_set_id]
    end

    read :for_study_set do
      argument :study_set_id, :uuid, allow_nil?: false
      filter expr(study_set_id == ^arg(:study_set_id))
      prepare build(sort: [position: :asc])
    end
  end

  policies do
    policy always() do
      forbid_if always()
    end

    # Allow owners of the study set to read/write terms
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if relates_to_actor_via([:study_set, :owner])
    end

    # Org members can read terms via study set organization
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberViaStudySetRead, []}
    end

    policy always() do
      authorize_if actor_attribute_equals(:site_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :term, :string, allow_nil?: false
    attribute :definition, :string, allow_nil?: false
    attribute :position, :integer, default: 0
    attribute :distractors, {:array, :string}, default: []

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
  end
end
