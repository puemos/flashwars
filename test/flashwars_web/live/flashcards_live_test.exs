defmodule FlashwarsWeb.FlashcardsLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Flashwars.Test.LearningFixtures

  setup do
    {:ok, LearningFixtures.build_set(nil)}
  end

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  test "loads and swipes increment count", %{conn: conn, org: org, user: user, set: set} do
    conn = sign_in(conn, user)
    {:ok, lv, html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/flashcards")
    assert html =~ "Flashcards: #{set.name}"
    assert html =~ "Cards Studied"

    # Simulate a swipe event from the deck (right = :good)
    term_id =
      Flashwars.Content.list_terms_for_study_set!(%{study_set_id: set.id}, actor: user)
      |> Enum.at(0)
      |> Map.get(:id)

    send(
      lv.pid,
      {:swipe_event,
       %{
         direction: "right",
         item: %{term_id: term_id, front: "A", back: "B"},
         component_id: "flashcard-deck"
       }}
    )

    _ = render(lv)

    # Stat has a dynamic id keyed by cards_completed; ensure it increments to 1
    assert has_element?(lv, ~s/[id^="cards-completed-1"]/)
  end

  test "shows recap after 10 swipes and continues to next round", %{
    conn: conn,
    org: org,
    user: user,
    set: set
  } do
    conn = sign_in(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/flashcards")

    # Perform 10 swipes to trigger end-of-round recap
    term_ids =
      Flashwars.Content.list_terms_for_study_set!(%{study_set_id: set.id}, actor: user)
      |> Enum.take(10)
      |> Enum.map(& &1.id)

    Enum.each(term_ids, fn tid ->
      send(
        lv.pid,
        {:swipe_event,
         %{
           direction: "right",
           item: %{term_id: tid, front: "F", back: "B"},
           component_id: "flashcard-deck"
         }}
      )

      _ = render(lv)
    end)

    # Recap overlay visible
    html = render(lv)
    assert html =~ "Round 1 recap"

    # Continue to next round
    _ = lv |> element("#flashcards-recap-overlay button", "Next Round") |> render_click()

    # Overlay remains in DOM but should be hidden now; check for hidden class on root overlay
    html = render(lv)
    assert html =~ ~r/<div id=\"flashcards-recap-overlay\"[^>]*class=\"[^"]*hidden/
  end
end
