defmodule FlashwarsWeb.FlashcardsRoundRecapTest do
  use FlashwarsWeb.ConnCase, async: true

  alias Flashwars.Test.LearningFixtures

  setup do
    {:ok, LearningFixtures.build_set(nil)}
  end

  test "shows recap after a round of swipes", %{user: user, set: set} do
    # Build a socket with required assigns
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        current_user: user,
        study_set: set,
        flash: %{},
        exclude_term_ids: MapSet.new(),
        cards: [],
        cards_completed: 0,
        round_number: 1,
        round_terms: [],
        show_recap?: false,
        round_recap: [],
        __changed__: %{}
      }
    }

    # Simulate 10 swipes with different term ids from the set
    term_ids =
      Flashwars.Content.list_terms_for_study_set!(%{study_set_id: set.id}, actor: user)
      |> Enum.take(10)
      |> Enum.map(& &1.id)

    swipe = fn sock, tid ->
      card = %{term_id: tid, front: "t", back: "d"}
      msg = {:swipe_event, %{direction: "right", item: card, component_id: "flashcard-deck"}}
      {:noreply, ns} = FlashwarsWeb.StudySetLive.Flashcards.handle_info(msg, sock)
      ns
    end

    socket = Enum.reduce(term_ids, socket, fn tid, acc -> swipe.(acc, tid) end)

    assert socket.assigns.show_recap? == true
    assert socket.assigns.round_number == 2
    assert length(socket.assigns.round_recap) == 10
  end
end
