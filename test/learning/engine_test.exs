defmodule Flashwars.Learning.EngineTest do
  use Flashwars.DataCase, async: true

  import Flashwars.Test.LearningFixtures, only: [build_set: 1]

  alias Flashwars.Learning.{Engine, CardState}

  setup [:build_set]

  describe "generate_item/2" do
    test "produces 4 choices with valid answer index and respects exclusions", %{set: set} do
      item1 = Engine.generate_item(set.id)
      term_id1 = item1.term_id
      assert length(item1.choices) == 4
      assert Enum.at(item1.choices, item1.answer_index)

      item2 = Engine.generate_item(set.id, exclude_term_ids: [term_id1])
      assert item2.term_id != term_id1
    end
  end

  describe "flashcards" do
    test "order strategies and exclusions", %{user: user, set: set, terms: terms} do
      apple_id = terms["apple"].id

      card =
        Engine.generate_flashcard(user, set.id,
          order: :alphabetical,
          exclude_term_ids: [apple_id]
        )

      assert card.front != "apple"

      card2 =
        Engine.generate_flashcard(user, set.id, order: :position, exclude_term_ids: [apple_id])

      assert card2.front == "book"
    end

    test "smart order uses scheduler", %{user: user, set: set, org: org, terms: terms} do
      now = DateTime.add(DateTime.utc_now(), -3600, :second)

      CardState
      |> Ash.Changeset.for_create(
        :create,
        %{
          term_id: terms["happy"].id,
          study_set_id: set.id,
          next_due_at: now,
          organization_id: org.id
        },
        actor: user
      )
      |> Ash.create!()

      card = Engine.generate_flashcard(user, set.id, order: :smart)
      assert card.front == "happy"
    end

    test "smart flag bypasses scheduler", %{user: user, set: set, org: org, terms: terms} do
      now = DateTime.add(DateTime.utc_now(), -3600, :second)

      CardState
      |> Ash.Changeset.for_create(
        :create,
        %{
          term_id: terms["happy"].id,
          study_set_id: set.id,
          next_due_at: now,
          organization_id: org.id
        },
        actor: user
      )
      |> Ash.create!()

      card =
        Engine.generate_flashcard(user, set.id,
          order: :smart,
          smart: false,
          exclude_term_ids: []
        )

      assert card.front != "happy"
    end
  end

  describe "learning flow" do
    test "sessions adapt based on prior reviews", %{user: user, set: set, org: org} do
      card1 = Engine.generate_flashcard(user, set.id, order: :smart, seed: 3)
      now = DateTime.utc_now()

      # simulate a failed review so the card is due immediately
      CardState
      |> Ash.Changeset.for_create(
        :upsert,
        %{
          term_id: card1.term_id,
          study_set_id: set.id,
          next_due_at: DateTime.add(now, -60, :second),
          organization_id: org.id
        },
        actor: user
      )
      |> Ash.create!()

      card2 = Engine.generate_flashcard(user, set.id, order: :smart)
      assert card2.term_id == card1.term_id

      # simulate a correct review pushing due date into future
      CardState
      |> Ash.Changeset.for_create(
        :upsert,
        %{
          term_id: card1.term_id,
          study_set_id: set.id,
          next_due_at: DateTime.add(now, 86_400, :second),
          organization_id: org.id
        },
        actor: user
      )
      |> Ash.create!()

      card3 = Engine.generate_flashcard(user, set.id, order: :smart)
      refute card3.term_id == card1.term_id
    end
  end

  describe "learn round" do
    test "mixed items obey rules", %{user: user, set: set, terms_by_id: terms_by_id} do
      items = Engine.generate_learn_round(user, set.id, size: 5, pair_count: 3, seed: 42)
      assert length(items) == 5

      term_ids =
        Enum.flat_map(items, fn
          %{kind: "matching", left: left} -> Enum.map(left, & &1.term_id)
          item -> [item.term_id]
        end)

      assert length(term_ids) == length(Enum.uniq(term_ids))

      for item <- items do
        case item.kind do
          "multiple_choice" ->
            assert length(item.choices) == 4

            assert Enum.at(item.choices, item.answer_index) ==
                     terms_by_id[item.term_id].definition

          "true_false" ->
            assert item.choices == ["True", "False"]

          "free_text" ->
            assert is_binary(item.answer_text)

          "matching" ->
            assert length(item.left) == 3
            assert length(item.right) == 3
            assert length(item.answer_pairs) == 3
        end
      end
    end

    test "smart flag bypasses scheduler", %{user: user, set: set, org: org, terms: terms} do
      now = DateTime.add(DateTime.utc_now(), -3600, :second)

      CardState
      |> Ash.Changeset.for_create(
        :create,
        %{
          term_id: terms["happy"].id,
          study_set_id: set.id,
          next_due_at: now,
          organization_id: org.id
        },
        actor: user
      )
      |> Ash.create!()

      [%{term_id: tid1}] =
        Engine.generate_learn_round(user, set.id,
          size: 1,
          types: [:multiple_choice],
          smart: true
        )

      assert tid1 == terms["happy"].id

      [%{term_id: tid2}] =
        Engine.generate_learn_round(user, set.id,
          size: 1,
          types: [:multiple_choice],
          smart: false
        )

      assert tid2 != terms["happy"].id
    end
  end

  describe "test mode" do
    test "fixed size and prioritizes due items", %{user: user, set: set, org: org, terms: terms} do
      now = DateTime.add(DateTime.utc_now(), -3600, :second)

      CardState
      |> Ash.Changeset.for_create(
        :create,
        %{
          term_id: terms["sun"].id,
          study_set_id: set.id,
          next_due_at: now,
          organization_id: org.id
        },
        actor: user
      )
      |> Ash.create!()

      states = Flashwars.Learning.Scheduler.build_daily_queue(user, set.id, 4)
      assert hd(states).term_id == terms["sun"].id

      items = Engine.generate_test(user, set.id, size: 1, types: [:multiple_choice], seed: 7)
      assert length(items) == 1
    end

    test "smart flag bypasses scheduler", %{user: user, set: set, org: org, terms: terms} do
      now = DateTime.add(DateTime.utc_now(), -3600, :second)

      CardState
      |> Ash.Changeset.for_create(
        :create,
        %{
          term_id: terms["sun"].id,
          study_set_id: set.id,
          next_due_at: now,
          organization_id: org.id
        },
        actor: user
      )
      |> Ash.create!()

      [%{term_id: tid1}] =
        Engine.generate_test(user, set.id,
          size: 1,
          types: [:multiple_choice],
          smart: true
        )

      assert tid1 == terms["sun"].id

      [%{term_id: tid2}] =
        Engine.generate_test(user, set.id,
          size: 1,
          types: [:multiple_choice],
          smart: false
        )

      assert tid2 == terms["apple"].id
    end
  end
end
