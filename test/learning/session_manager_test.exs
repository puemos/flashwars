defmodule Flashwars.Learning.SessionManagerTest do
  use Flashwars.DataCase, async: true

  alias Flashwars.Learning.SessionManager

  describe "retrying incorrect answers" do
    @doc """
    Ensures a round does not complete until the question is answered correctly.
    Incorrect answers in the retry phase requeue the item so it appears again
    at the end of the round.
    """
    test "incorrect retry requeues item until answered correctly" do
      item = %{id: 1}

      state = %{
        phase: :first_pass,
        round_items: [item],
        round_index: 0,
        round_number: 1,
        round_correct_count: 0,
        round_position: 1,
        current_item: item,
        session_stats: %{total_correct: 0, total_questions: 0}
      }

      # initial incorrect answer moves item to retry phase
      state = SessionManager.defer_current_item(state)
      {:advance_in_round, state} = SessionManager.advance_session(state)
      assert state.phase == :retry

      # incorrect answer during retry puts item back into queue
      state = SessionManager.defer_current_item(state)
      {:advance_in_round, state} = SessionManager.advance_session(state)
      assert state.phase == :retry
      assert state.current_item == item

      # correct answer now finishes the round
      state = SessionManager.mark_answer_correct(state)
      assert {:start_new_round, _clean} = SessionManager.advance_session(state)
    end
  end
end
