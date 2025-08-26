defmodule FlashwarsWeb.LearnRoundMatchingRecapTest do
  use FlashwarsWeb.ConnCase, async: true

  alias Flashwars.Learning.SessionState
  alias Flashwars.Test.LearningFixtures
  alias Flashwars.Learning.Engine

  setup do
    {:ok, LearningFixtures.build_set(nil)}
  end

  test "recap includes terms from matching items", %{user: user, set: set} do
    # Force a matching-only round with a single matching item
    [matching_item | _] =
      Engine.generate_learn_round(user, set.id, size: 1, types: [:matching], pair_count: 4)

    # Sanity: matching item has left list
    assert matching_item.kind == "matching"
    assert is_list(matching_item.left)

    state = %SessionState{
      round_items: [matching_item],
      round_index: 0,
      round_number: 1,
      round_correct_count: 0,
      round_position: 1,
      current_item: matching_item,
      session_stats: %{total_correct: 0, total_questions: 0},
      mode: :learn,
      phase: :first_pass
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        session_state: state,
        answered?: true,
        correct?: true,
        round_closed?: false,
        study_set: %{id: set.id},
        current_user: user,
        __changed__: %{}
      }
    }

    {:noreply, socket} = FlashwarsWeb.StudySetLive.Learn.handle_event("next", %{}, socket)

    assert socket.assigns.show_recap? == true

    left_ids = Enum.map(matching_item.left, & &1.term_id) |> Enum.sort()
    recap_ids = Enum.map(socket.assigns.round_recap, & &1.term_id) |> Enum.sort()
    assert recap_ids == left_ids
  end
end
