defmodule Flashwars.UseCases.AttemptFlowTest do
  use Flashwars.DataCase, async: true

  alias Flashwars.{Content, Org}
  alias Flashwars.Learning.{Attempt, AttemptItem, LeaderboardEntry}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  @doc """
  This test verifies the complete flow of a student taking a test:
  1. Setup of organization with admin and student users
  2. Creation of a private study set with terms by the admin
  3. Student creates an attempt to take the test
  4. Student records their answer to a test question
  5. Student's score is recorded on the leaderboard

  The test ensures proper user associations and data integrity throughout the flow.
  """
  test "student creates attempt, items, and leaderboard upsert" do
    org = Ash.Seed.seed!(Organization, %{name: "Org"})
    admin = Ash.Seed.seed!(User, %{email: "admin@ex.com"})
    student = Ash.Seed.seed!(User, %{email: "student@ex.com"})

    Org.add_member!(%{organization_id: org.id, user_id: admin.id, role: :admin},
      authorize?: false
    )

    Org.add_member!(%{organization_id: org.id, user_id: student.id, role: :member},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{name: "Algebra", organization_id: org.id, owner_id: admin.id, privacy: :private},
        actor: admin
      )

    term =
      Content.create_term!(%{term: "2+2", definition: "4", study_set_id: set.id}, actor: admin)

    # Student creates attempt
    attempt =
      Attempt
      |> Ash.Changeset.for_create(:create, %{study_set_id: set.id, mode: :test}, actor: student)
      |> Ash.create!()

    assert attempt.user_id == student.id

    # Student records an item
    item =
      AttemptItem
      |> Ash.Changeset.for_create(
        :create,
        %{attempt_id: attempt.id, term_id: term.id, answer: "4", correct: true, score: 10},
        actor: student
      )
      |> Ash.create!()

    assert item.correct

    # Student upserts leaderboard entry for the set
    lb =
      LeaderboardEntry
      |> Ash.Changeset.for_create(
        :upsert,
        %{scope: "class", mode: :test, score: 10, study_set_id: set.id},
        actor: student
      )
      |> Ash.create!()

    assert lb.user_id == student.id
  end
end
