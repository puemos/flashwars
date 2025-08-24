defmodule Flashwars.Content.StudySet do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Content,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "study_sets"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :privacy, :folder_id, :organization_id, :owner_id]
      change relate_actor(:owner)
      validate present(:organization_id)

      change fn changeset, _ctx ->
        privacy = Ash.Changeset.get_attribute(changeset, :privacy)

        if privacy == :link_only do
          Ash.Changeset.change_attribute(changeset, :link_token, __MODULE__.generate_link_token())
        else
          changeset
        end
      end
    end

    update :update do
      require_atomic? false
      accept [:name, :description, :privacy, :folder_id]

      change fn changeset, _ctx ->
        case {Ash.Changeset.get_attribute(changeset, :privacy),
              Ash.Changeset.get_attribute(changeset, :link_token)} do
          {:link_only, nil} ->
            Ash.Changeset.change_attribute(
              changeset,
              :link_token,
              __MODULE__.generate_link_token()
            )

          _ ->
            changeset
        end
      end
    end

    destroy :archive do
      primary? true
      require_atomic? false
      soft? true
    end

    read :public do
      filter expr(privacy == :public)
    end

    read :with_link_token do
      argument :token, :string, allow_nil?: false
      filter expr(privacy == :link_only and link_token == ^arg(:token))
    end

    read :for_org do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [updated_at: :desc])
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

    # Owners can do everything
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end

    # Org admins can create under their org
    policy action_type(:create) do
      authorize_if {Flashwars.Policies.OrgAdminCreate, []}
    end

    # Org members can read org resources
    policy action_type(:read) do
      authorize_if {Flashwars.Policies.OrgMemberRead, []}
    end

    # Members with link-token can read the resource
    policy action(:with_link_token) do
      authorize_if always()
    end

    # Public read access (if you want to keep public sets readable by anyone)
    policy action(:public) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false
    attribute :description, :string

    attribute :privacy, :atom,
      constraints: [one_of: [:private, :link_only, :public]],
      default: :private

    attribute :tags_cache, {:array, :string}, default: []
    attribute :link_token, :string

    attribute :owner_id, :uuid, public?: true
    # Multitenancy (org support). Relationship can be added later
    attribute :organization_id, :uuid

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, Flashwars.Accounts.User, allow_nil?: false
    belongs_to :organization, Flashwars.Org.Organization
    belongs_to :folder, Flashwars.Content.Folder

    has_many :terms, Flashwars.Content.Term do
      sort position: :asc
    end

    many_to_many :tags, Flashwars.Content.Tag do
      through Flashwars.Content.SetTag
      source_attribute_on_join_resource :study_set_id
      destination_attribute_on_join_resource :tag_id
    end
  end

  aggregates do
    count :terms_count, :terms
  end

  identities do
    identity :owner_name, [:owner_id, :name]
  end

  def generate_link_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
