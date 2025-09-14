defmodule Flashwars.Games.GameSubmissionScoringTest do
  use Flashwars.DataCase, async: true

  alias Flashwars.{Content, Games, Org}
  alias Flashwars.Games.GameSubmission
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  setup do
    org = Ash.Seed.seed!(Organization, %{name: "ScoringOrg"})
    host = Ash.Seed.seed!(User, %{email: "host-score@example.com"})
    p1 = Ash.Seed.seed!(User, %{email: "p1@example.com"})
    p2 = Ash.Seed.seed!(User, %{email: "p2@example.com"})

    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)
    Org.add_member!(%{organization_id: org.id, user_id: p1.id, role: :member}, authorize?: false)
    Org.add_member!(%{organization_id: org.id, user_id: p2.id, role: :member}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "ScoreSet", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    room = Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private}, actor: host)
    r1 = Games.generate_round!(%{game_room_id: room.id}, actor: host)

    {:ok, org: org, host: host, p1: p1, p2: p2, room: room, r1: r1}
  end

  test "computes positive score for first correct submission when score not provided", %{r1: r1, p1: p1} do
    now = DateTime.utc_now()

    s =
      GameSubmission
      |> Ash.Changeset.for_create(
        :create,
        %{answer: "x", correct: true, submitted_at: now, game_round_id: r1.id},
        actor: p1
      )
      |> Ash.create!()

    assert is_integer(s.score) and s.score > 0
  end

  test "keeps zero score for wrong submission when score not provided", %{r1: r1, p1: p1} do
    now = DateTime.utc_now()

    s =
      GameSubmission
      |> Ash.Changeset.for_create(
        :create,
        %{answer: "x", correct: false, submitted_at: now, game_round_id: r1.id},
        actor: p1
      )
      |> Ash.create!()

    assert s.score == 0
  end

  test "second correct submission in same round yields 0 (first correct gets points)", %{r1: r1, p1: p1, p2: p2} do
    now = DateTime.utc_now()

    s1 =
      GameSubmission
      |> Ash.Changeset.for_create(
        :create,
        %{answer: "x", correct: true, submitted_at: now, game_round_id: r1.id},
        actor: p1
      )
      |> Ash.create!()

    s2 =
      GameSubmission
      |> Ash.Changeset.for_create(
        :create,
        %{answer: "x", correct: true, submitted_at: DateTime.add(now, 1, :second), game_round_id: r1.id},
        actor: p2
      )
      |> Ash.create!()

    assert s1.score > 0
    assert s2.score == 0
  end
end
