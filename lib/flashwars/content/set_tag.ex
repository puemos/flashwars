defmodule Flashwars.Content.SetTag do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "set_tags"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:study_set_id, :tag_id, :organization_id]

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
  end

  policies do
    # Site admin can do everything (bypass)
    bypass actor_attribute_equals(:site_admin, true) do
      authorize_if always()
    end

    # Org admin can do everything under their org
    policy action_type([:read, :destroy]) do
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

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :study_set, Flashwars.Content.StudySet, allow_nil?: false
    belongs_to :tag, Flashwars.Content.Tag, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
  end

  identities do
    identity :unique_pair, [:study_set_id, :tag_id]
  end
end
