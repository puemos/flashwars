defmodule Flashwars.Accounts.User do
  use Ash.Resource,
    otp_app: :flashwars,
    domain: Flashwars.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Flashwars.Accounts.Token
      signing_secret Flashwars.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true

        sender Flashwars.Accounts.User.Senders.SendMagicLinkEmailImpl
      end

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
      end
    end
  end

  postgres do
    table "users"
    repo Flashwars.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get? true

      argument :email, :ci_string do
        allow_nil? false
      end

      filter expr(email == ^arg(:email))
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end
  end

  # Custom update actions to evolve user profile without impacting auth
  actions do
    # Existing actions preserved above; add safe updates
    update :update_last_login do
      accept [:last_login_at]
      change set_attribute(:last_login_at, &DateTime.utc_now/0)
    end

    update :update_settings do
      accept [:settings]
      validate present(:settings)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    # Extended attributes (preserve existing auth fields)
    attribute :site_admin, :boolean, default: false
    attribute :settings, :map, default: %{}
    attribute :last_login_at, :utc_datetime
  end

  relationships do
    has_many :valid_api_keys, Flashwars.Accounts.ApiKey do
      filter expr(valid)
    end

    # Ownership relationships for content (resources will be added in Content domain)
    has_many :study_sets, Flashwars.Content.StudySet, destination_attribute: :owner_id

    has_many :folders, Flashwars.Content.Folder, destination_attribute: :owner_id

    has_many :org_memberships, Flashwars.Org.OrgMembership
    has_many :enrollments, Flashwars.Classroom.Enrollment
    has_many :attempts, Flashwars.Learning.Attempt
    has_many :notifications, Flashwars.Ops.Notification
  end

  identities do
    identity :unique_email, [:email]
  end
end
