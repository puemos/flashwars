defmodule Flashwars.Classroom do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Classroom.Class do
      define :create_class, action: :create
    end

    resource Flashwars.Classroom.Section do
      define :create_section, action: :create
    end

    resource Flashwars.Classroom.Enrollment do
      define :enroll, action: :create
    end

    resource Flashwars.Classroom.Assignment do
      define :create_assignment, action: :create
    end
  end
end
