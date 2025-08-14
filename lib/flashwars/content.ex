defmodule Flashwars.Content do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Content.Folder do
      define :get_folder_by_id, action: :read, get_by: [:id]
      define :create_folder, action: :create
    end

    resource Flashwars.Content.StudySet do
      define :get_study_set_by_id, action: :read, get_by: [:id]
      define :create_study_set, action: :create
    end

    resource Flashwars.Content.Term do
      define :get_term_by_id, action: :read, get_by: [:id]
      define :create_term, action: :create
    end

    resource Flashwars.Content.Tag do
      define :create_tag, action: :create
      define :update_tag, action: :update
    end

    resource Flashwars.Content.SetTag do
      define :get_set_tag_by_id, action: :read, get_by: [:id]
      define :create_set_tag, action: :create
    end
  end
end
