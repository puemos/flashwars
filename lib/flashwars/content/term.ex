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
    defaults [:read, :destroy, update: [:term, :definition]]

    create :create do
      accept [:term, :definition, :position, :study_set_id, :organization_id]

      change fn changeset, _ctx ->
        case Ash.Changeset.get_attribute(changeset, :organization_id) do
          nil ->
            case Ash.Changeset.get_attribute(changeset, :study_set_id) do
              nil ->
                changeset

              set_id ->
                with {:ok, set} <- Ash.get(Flashwars.Content.StudySet, set_id, authorize?: false) do
                  Ash.Changeset.change_attribute(changeset, :organization_id, set.organization_id)
                else
                  _ -> changeset
                end
            end

          _ ->
            changeset
        end
      end

      validate present(:organization_id)
    end

    read :for_study_set do
      argument :study_set_id, :uuid, allow_nil?: false
      filter expr(study_set_id == ^arg(:study_set_id))
      prepare build(sort: [position: :asc])
    end

    read :with_link_token do
      argument :token, :string, allow_nil?: false
      filter expr(study_set.privacy == :link_only and study_set.link_token == ^arg(:token))
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

    # Owners can update/destroy via study set owner
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via([:study_set, :owner])
    end

    # Org admins can create under their org
    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Org members can read terms via study set organization
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.PublicViaStudySetRead, []}
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    policy action(:with_link_token) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :term, :string, allow_nil?: false
    attribute :definition, :string, allow_nil?: false
    attribute :position, :integer, default: 0
    attribute :distractors, {:array, :string}, default: []
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
  end
end
