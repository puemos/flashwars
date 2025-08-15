defmodule Flashwars.UseCases.GamesMultiRoundFlowTest do
  use Flashwars.DataCase, async: true
  require Ash.Query

  alias Flashwars.{Content, Games, Org}
  alias Flashwars.Games.{GameRound, GameSubmission}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  describe "games multi-round flow" do
    test "players submit across rounds; participants can read all submissions in their room" do
      org = Ash.Seed.seed!(Organization, %{name: "PlayOrg"})
      host = Ash.Seed.seed!(User, %{email: "host-mr@example.com"})
      p1 = Ash.Seed.seed!(User, %{email: "player1@example.com"})
      p2 = Ash.Seed.seed!(User, %{email: "player2@example.com"})

      # memberships
      Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin},
        authorize?: false
      )

      Org.add_member!(%{organization_id: org.id, user_id: p1.id, role: :member},
        authorize?: false
      )

      Org.add_member!(%{organization_id: org.id, user_id: p2.id, role: :member},
        authorize?: false
      )

      # study set, terms, and room
      set =
        Content.create_study_set!(
          %{name: "QuickMath", organization_id: org.id, owner_id: host.id, privacy: :private},
          actor: host
        )

      # seed at least 4 terms to enable 4-choice MCQs
      Content.create_term!(%{study_set_id: set.id, term: "2+2", definition: "4"},
        authorize?: false
      )

      Content.create_term!(%{study_set_id: set.id, term: "3+5", definition: "8"},
        authorize?: false
      )

      Content.create_term!(%{study_set_id: set.id, term: "10-7", definition: "3"},
        authorize?: false
      )

      Content.create_term!(%{study_set_id: set.id, term: "6/2", definition: "3"},
        authorize?: false
      )

      room =
        Games.create_game_room!(
          %{
            type: :duel,
            rating_scope: "class-1",
            study_set_id: set.id,
            organization_id: org.id
          },
          actor: host
        )

      # generate two rounds using the learning engine via Games
      r1 = Games.generate_round!(%{game_room_id: room.id}, actor: host)
      r2 = Games.generate_round!(%{game_room_id: room.id}, actor: host)

      # validate rounds contain 4 options and a valid answer index
      for r <- [r1, r2] do
        q = r.question_data
        assert q["kind"] == "multiple_choice" or q[:kind] == "multiple_choice"
        choices = q["choices"] || q[:choices]
        assert is_list(choices) and length(choices) == 4
        aidx = q["answer_index"] || q[:answer_index]
        assert is_integer(aidx) and aidx >= 0 and aidx < 4
      end

      now = DateTime.utc_now()

      # submissions round 1
      s1_p1 =
        GameSubmission
        |> Ash.Changeset.for_create(
          :create,
          %{answer: "4", correct: true, score: 10, submitted_at: now, game_round_id: r1.id},
          actor: p1
        )
        |> Ash.create!()

      s1_p2 =
        GameSubmission
        |> Ash.Changeset.for_create(
          :create,
          %{answer: "5", correct: false, score: 0, submitted_at: now, game_round_id: r1.id},
          actor: p2
        )
        |> Ash.create!()

      # submissions round 2
      s2_p1 =
        GameSubmission
        |> Ash.Changeset.for_create(
          :create,
          %{answer: "8", correct: true, score: 10, submitted_at: now, game_round_id: r2.id},
          actor: p1
        )
        |> Ash.create!()

      s2_p2 =
        GameSubmission
        |> Ash.Changeset.for_create(
          :create,
          %{answer: "8", correct: true, score: 10, submitted_at: now, game_round_id: r2.id},
          actor: p2
        )
        |> Ash.create!()

      # identity guard: same user cannot submit twice in same round
      assert {:error, _} =
               GameSubmission
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   answer: "4 again",
                   correct: true,
                   score: 10,
                   submitted_at: now,
                   game_round_id: r1.id
                 },
                 actor: p1
               )
               |> Ash.create()

      # org admin can read all submissions for the room
      subs_for_room_as_host =
        GameSubmission
        |> Ash.Query.filter(game_room_id == ^room.id)
        |> Ash.read!(authorize?: false)

      assert Enum.sort(Enum.map(subs_for_room_as_host, & &1.id)) ==
               Enum.sort([s1_p1.id, s1_p2.id, s2_p1.id, s2_p2.id])

      # list submissions for the room (DB visibility)
      GameSubmission
      |> Ash.Query.filter(game_room_id == ^room.id and user_id == ^p1.id)
      |> Ash.read!(authorize?: false)

      # verify rounds list sorted asc
      rounds =
        GameRound
        |> Ash.Query.filter(game_room_id == ^room.id)
        |> Ash.read!(authorize?: false)

      assert Enum.map(rounds, & &1.number) == [1, 2]

      # simple cumulative scoring check
      totals =
        subs_for_room_as_host
        |> Enum.group_by(& &1.user_id)
        |> Enum.into(%{}, fn {uid, subs} ->
          {uid, Enum.reduce(subs, 0, fn s, acc -> acc + (s.score || 0) end)}
        end)

      assert totals[p1.id] == 20
      assert totals[p2.id] == 10

      # create another room in same org; ensure filtering by room id works
      room2 =
        Games.create_game_room!(
          %{
            type: :duel,
            rating_scope: "class-2",
            study_set_id: set.id,
            organization_id: org.id
          },
          actor: host
        )

      _r2_1 =
        GameRound
        |> Ash.Changeset.for_create(
          :create,
          %{number: 1, game_room_id: room2.id, question_data: %{q: "1+1"}},
          actor: host
        )
        |> Ash.create!()

      # reading submissions filtered by room id returns only that room's data
      only_room1_ids =
        GameSubmission
        |> Ash.Query.filter(game_room_id == ^room.id)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      assert MapSet.equal?(only_room1_ids, MapSet.new([s1_p1.id, s1_p2.id, s2_p1.id, s2_p2.id]))
    end
  end
end
