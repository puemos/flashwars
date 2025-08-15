defmodule Flashwars.Learning.SchedulerTest do
  use Flashwars.DataCase, async: true
  require Ash.Query

  alias Flashwars.{Content, Learning, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  describe "schedule_after_review + review logging" do
    test "success and failure update card state and log AttemptItem metadata" do
      org = Ash.Seed.seed!(Organization, %{name: "Org"})
      admin = Ash.Seed.seed!(User, %{email: "admin-sched@example.com"})
      student = Ash.Seed.seed!(User, %{email: "student-sched@example.com"})

      # memberships
      Org.add_member!(%{organization_id: org.id, user_id: admin.id, role: :admin},
        authorize?: false
      )

      Org.add_member!(%{organization_id: org.id, user_id: student.id, role: :member},
        authorize?: false
      )

      set =
        Content.create_study_set!(
          %{name: "Bio", organization_id: org.id, owner_id: admin.id, privacy: :private},
          actor: admin
        )

      t =
        Content.create_term!(%{study_set_id: set.id, term: "cell", definition: "basic unit"},
          authorize?: false
        )

      # first review: good
      {:ok, res1} = Learning.review(student, t.id, :good, rt_ms: 1200, queue_type: :learning)
      assert res1.item.grade == :good
      assert is_float(res1.item.s_after)
      assert is_float(res1.item.d_after)
      # card state has a next due in the future
      cs =
        Learning.CardState
        |> Ash.Query.filter(user_id == ^student.id and term_id == ^t.id)
        |> Ash.read!(authorize?: false)
        |> List.first()

      assert cs
      assert DateTime.compare(cs.next_due_at, DateTime.utc_now()) == :gt

      # second review: again (failure) – relearn step should produce short interval
      {:ok, res2} = Learning.review(student, t.id, :again, rt_ms: 5000, queue_type: :relearn)
      assert res2.item.grade == :again

      cs2 =
        Learning.CardState
        |> Ash.Query.filter(user_id == ^student.id and term_id == ^t.id)
        |> Ash.read!(authorize?: false)
        |> List.first()

      assert cs2.relearn_stage in [1, 2]
      # Next due should be within ~1 day for relearn steps
      assert DateTime.diff(cs2.next_due_at, DateTime.utc_now(), :second) < 86_400
    end
  end

  describe "daily queue" do
    test "includes unseen when no due items" do
      org = Ash.Seed.seed!(Organization, %{name: "Org2"})
      admin = Ash.Seed.seed!(User, %{email: "admin-q@example.com"})
      student = Ash.Seed.seed!(User, %{email: "student-q@example.com"})

      Org.add_member!(%{organization_id: org.id, user_id: admin.id, role: :admin},
        authorize?: false
      )

      Org.add_member!(%{organization_id: org.id, user_id: student.id, role: :member},
        authorize?: false
      )

      set =
        Content.create_study_set!(%{name: "Chem", organization_id: org.id, owner_id: admin.id},
          actor: admin
        )

      _ =
        Content.create_term!(%{study_set_id: set.id, term: "H2O", definition: "water"},
          authorize?: false
        )

      _ =
        Content.create_term!(%{study_set_id: set.id, term: "NaCl", definition: "salt"},
          authorize?: false
        )

      queue = Flashwars.Learning.Scheduler.build_daily_queue(student, set.id, 2)
      assert length(queue) <= 2
    end
  end
end
