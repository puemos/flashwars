defmodule Flashwars.Learning.ModeSeedTest do
  use Flashwars.DataCase, async: true

  import Flashwars.Test.LearningFixtures, only: [build_set: 1]

  alias Flashwars.Learning.{Session, Engine}
  alias Flashwars.Classroom.{Assignment, Class, Section}

  describe "mode constraints" do
    setup [:build_set]

    test "session rejects match mode", %{user: user, set: set} do
      {:error, error} =
        Session
        |> Ash.Changeset.for_create(
          :upsert,
          %{user_id: user.id, study_set_id: set.id, mode: :match},
          actor: user
        )
        |> Ash.create()

      assert %Ash.Error.Invalid{} = error
    end

    test "assignment rejects match mode", %{org: org, set: set} do
      class = Ash.Seed.seed!(Class, %{name: "C1", organization_id: org.id})

      section =
        Ash.Seed.seed!(Section, %{name: "S1", class_id: class.id, organization_id: org.id})

      {:error, error} =
        Assignment
        |> Ash.Changeset.for_create(:create, %{
          mode: :match,
          section_id: section.id,
          study_set_id: set.id,
          organization_id: org.id
        })
        |> Ash.create()

      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "deterministic test generation" do
    setup [:build_set]

    test "seed produces stable test", %{set: set} do
      items1 = Engine.generate_test(nil, set.id, size: 5, seed: 123)
      items2 = Engine.generate_test(nil, set.id, size: 5, seed: 123)
      items3 = Engine.generate_test(nil, set.id, size: 5, seed: 456)

      assert items1 == items2
      refute items1 == items3
    end
  end
end
