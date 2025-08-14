defmodule Flashwars.Classroom do
  use Ash.Domain, otp_app: :flashwars

  resources do
    resource Flashwars.Classroom.Class
    resource Flashwars.Classroom.Section
    resource Flashwars.Classroom.Enrollment
    resource Flashwars.Classroom.Assignment
  end

  alias Flashwars.Classroom.{Class, Section, Enrollment, Assignment}

  def create_class(params, opts \\ []),
    do: Class |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()

  def create_section(params, opts \\ []),
    do: Section |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()

  def enroll(params, opts \\ []),
    do: Enrollment |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()

  def create_assignment(params, opts \\ []),
    do: Assignment |> Ash.Changeset.for_create(:create, params, opts) |> Ash.create()
end
