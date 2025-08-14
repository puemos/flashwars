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
    # 1. Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # 2. Org admin can do everything under their org
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if {Flashwars.Policies.OrgAdminRead, []}
    end

    # 3. Owners can do everything
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if relates_to_actor_via([:study_set, :owner])
    end

    # 4. Org members can read terms via study set organization
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberViaStudySetRead, []}
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
