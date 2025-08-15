defmodule Flashwars.Learning.EngineTest do
  use Flashwars.DataCase, async: true

  alias Flashwars.{Content, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization
  alias Flashwars.Learning.Engine

  describe "Learning.Engine.generate_item/2" do
    test "produces 4 choices with valid answer index and avoids repeats until exhaustion" do
      org = Ash.Seed.seed!(Organization, %{name: "LearnOrg"})
      host = Ash.Seed.seed!(User, %{email: "host-eng@example.com"})

      # membership so host can own/create the set
      Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin},
        authorize?: false
      )

      # Create a private set with 3 terms
      set =
        Content.create_study_set!(
          %{name: "Basic", organization_id: org.id, owner_id: host.id, privacy: :private},
          actor: host
        )

      _ =
        Content.create_term!(%{study_set_id: set.id, term: "2+2", definition: "4"},
          authorize?: false
        )

      _ =
        Content.create_term!(%{study_set_id: set.id, term: "3+5", definition: "8"},
          authorize?: false
        )

      _ =
        Content.create_term!(%{study_set_id: set.id, term: "10-7", definition: "3"},
          authorize?: false
        )

      # 1st item
      item1 = Engine.generate_item(set.id)
      choices1 = item1[:choices] || item1["choices"]
      aidx1 = item1[:answer_index] || item1["answer_index"]
      term_id1 = item1[:term_id] || item1["term_id"]
      assert is_list(choices1) and length(choices1) == 4
      assert is_integer(aidx1) and aidx1 >= 0 and aidx1 < 4
      term1 = Ash.get!(Flashwars.Content.Term, term_id1, authorize?: false)
      assert Enum.at(choices1, aidx1) == term1.definition

      # 2nd item, exclude previous term id
      item2 = Engine.generate_item(set.id, exclude_term_ids: [term_id1])
      term_id2 = item2[:term_id] || item2["term_id"]
      assert term_id2 != term_id1

      # 3rd item, exclude previous two term ids
      item3 = Engine.generate_item(set.id, exclude_term_ids: [term_id1, term_id2])
      term_id3 = item3[:term_id] || item3["term_id"]
      assert term_id3 not in [term_id1, term_id2]

      # 4th item, all terms exhausted, allowed to repeat
      item4 = Engine.generate_item(set.id, exclude_term_ids: [term_id1, term_id2, term_id3])
      term_id4 = item4[:term_id] || item4["term_id"]
      assert term_id4 in [term_id1, term_id2, term_id3]

      # ensure choice/answer validity for later items as well
      for item <- [item2, item3, item4] do
        choices = item[:choices] || item["choices"]
        aidx = item[:answer_index] || item["answer_index"]
        tid = item[:term_id] || item["term_id"]
        term = Ash.get!(Flashwars.Content.Term, tid, authorize?: false)
        assert is_list(choices) and length(choices) == 4
        assert is_integer(aidx) and aidx >= 0 and aidx < 4
        assert Enum.at(choices, aidx) == term.definition
      end
    end
  end
end
