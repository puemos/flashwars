defmodule FlashwarsWeb.TestModeLiveTest do
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

  test "test mode answers and advances", %{conn: conn, org: org, user: user, set: set} do
    conn = sign_in(conn, user)
    {:ok, lv, html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/test")
    assert html =~ "Test: #{set.name}"
    assert html =~ "Q 1 /"

    # answer first item
    _ = lv |> element("button[data-choice-index='0']") |> render_click()
    html = render(lv)
    assert html =~ "Next"

    _ = lv |> element("button", "Next") |> render_click()
    html = render(lv)
    assert html =~ "Q 2 /"
  end
end
