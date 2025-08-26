defmodule FlashwarsWeb.LearnRoundRecapTest do
  use FlashwarsWeb.ConnCase, async: true

  alias Flashwars.Learning.SessionState
  alias Flashwars.Test.LearningFixtures

  setup do
    {:ok, LearningFixtures.build_set(nil)}
  end

  test "shows recap at end of round and waits for next round", %{user: user, set: set} do
    [t1, t2 | _] =
      Flashwars.Content.list_terms_for_study_set!(%{study_set_id: set.id}, actor: user)

    items = [
      %{
        term_id: t1.id,
        kind: "multiple_choice",
        prompt: "Q1",
        choices: ["a", "b", "c", "d"],
        answer_index: 1
      },
      %{
        term_id: t2.id,
        kind: "multiple_choice",
        prompt: "Q2",
        choices: ["a", "b", "c", "d"],
        answer_index: 2
      }
    ]

    state = %SessionState{
      round_items: items,
      round_index: 1,
      round_number: 1,
      round_correct_count: 1,
      round_position: 2,
      current_item: List.last(items),
      session_stats: %{total_correct: 1, total_questions: 1},
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
    assert is_list(socket.assigns.round_recap)
    # contains the two items' term_ids (labels may be unknown in this unit test)
    ids = Enum.map(socket.assigns.round_recap, & &1.term_id) |> Enum.sort()
    assert Enum.sort(ids) == Enum.sort(Enum.map(items, & &1.term_id))
  end
end
