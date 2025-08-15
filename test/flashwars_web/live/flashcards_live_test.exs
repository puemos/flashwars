defmodule FlashwarsWeb.FlashcardsLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Flashwars.Test.LearningFixtures

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  setup do
    {:ok, LearningFixtures.build_set(nil)}
  end

  test "flashcards reveal and grade cycle", %{conn: conn, org: org, user: user, set: set} do
    conn = sign_in(conn, user)
    {:ok, lv, html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/flashcards")
    assert html =~ "Flashcards: #{set.name}"
    assert html =~ "Show Answer"

    _ = lv |> element("button", "Show Answer") |> render_click()
    html = render(lv)
    assert html =~ "Again"
    assert html =~ "Good"

    _ = lv |> element("button", "Good") |> render_click()
    html = render(lv)
    # After grading, we should be back to unrevealed state
    assert html =~ "Show Answer"
  end
end
