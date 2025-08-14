defmodule Flashwars.Content do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Content.Folder

    resource Flashwars.Content.StudySet do
      define :create_study_set, action: :create
      define :update_study_set, action: :update
      define :archive_study_set, action: :archive
      define :list_study_sets, action: :read
      define :get_study_set, action: :read, args: [:id], get?: true
    end

    resource Flashwars.Content.Term do
      define :create_term, action: :create
      define :update_term, action: :update
      define :delete_term, action: :destroy
      define :list_terms, action: :for_study_set, args: [:study_set_id]
    end

    resource Flashwars.Content.Tag do
      define :create_tag, action: :create
      define :update_tag, action: :update
      define :destroy_tag, action: :destroy
      define :list_tags, action: :read
    end

    resource Flashwars.Content.SetTag
  end
end
