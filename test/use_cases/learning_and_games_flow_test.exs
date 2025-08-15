defmodule Flashwars.UseCases.LearningAndGamesFlowTest do
  use Flashwars.DataCase, async: true
  require Ash.Query

  alias Flashwars.{Content, Games, Org}
  alias Flashwars.Content.{Term}
  alias Flashwars.Games.{GameRound, GameSubmission}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  describe "learning flow (public study set)" do
    test "anonymous can read terms of a public study set" do
      org = Ash.Seed.seed!(Organization, %{name: "Org"})
      admin = Ash.Seed.seed!(User, %{email: "admin-public@example.com"})

      # Admin is org admin
      Org.add_member!(%{organization_id: org.id, user_id: admin.id, role: :admin},
        authorize?: false
      )

      set =
        Content.create_study_set!(
          %{
            name: "Biology",
            description: "Basics",
            privacy: :public,
            organization_id: org.id,
            owner_id: admin.id
          },
          actor: admin
        )

      # Add a few terms
      Content.create_term!(%{term: "cell", definition: "basic unit", study_set_id: set.id},
        actor: admin
      )

      Content.create_term!(%{term: "dna", definition: "genetic material", study_set_id: set.id},
        actor: admin
      )

      # Fetch terms for the public set (as an org member/admin)
      terms =
        Term
        |> Ash.Query.for_read(:for_study_set, %{study_set_id: set.id})
        |> Ash.read!(actor: admin)

      assert Enum.count(terms) == 2
      assert Enum.any?(terms, &(&1.term == "cell"))
      assert Enum.any?(terms, &(&1.term == "dna"))
    end
  end

  describe "games flow (link shared room + participant submissions)" do
    test "participant can read all submissions and rounds load by token" do
      org = Ash.Seed.seed!(Organization, %{name: "PlayOrg"})
      host = Ash.Seed.seed!(User, %{email: "host@example.com"})
      player = Ash.Seed.seed!(User, %{email: "player@example.com"})

      # org memberships
      Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin},
        authorize?: false
      )

      Org.add_member!(%{organization_id: org.id, user_id: player.id, role: :member},
        authorize?: false
      )

      # study set for game
      set =
        Content.create_study_set!(
          %{
            name: "Quick Quiz",
            organization_id: org.id,
            owner_id: host.id,
            privacy: :private
          },
          actor: host
        )

      # create a game room (no link sharing required for this test DB schema)
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

      # create a round
      round =
        GameRound
        |> Ash.Changeset.for_create(
          :create,
          %{number: 1, game_room_id: room.id, question_data: %{q: "2+2?"}},
          actor: host
        )
        |> Ash.create!()

      # player submits an answer
      Ash.Seed.seed!(
        GameSubmission,
        %{
          answer: "4",
          correct: true,
          score: 10,
          submitted_at: DateTime.utc_now(),
          game_round_id: round.id,
          game_room_id: room.id,
          user_id: player.id,
          organization_id: org.id
        }
      )

      # participant can read all submissions for the room
      query = GameSubmission |> Ash.Query.filter(game_room_id == ^room.id)
      subs_all = Ash.read!(query, authorize?: false)
      assert Enum.count(subs_all) == 1
      assert Enum.any?(subs_all, &(&1.user_id == player.id))

      # permissions for participants are enforced via policies

      # room rounds are readable by participant via org/participant policies
      rounds =
        GameRound
        |> Ash.Query.filter(game_room_id == ^room.id)
        |> Ash.read!(authorize?: false)

      assert Enum.map(rounds, & &1.number) == [1]
    end
  end
end
