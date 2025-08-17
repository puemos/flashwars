defmodule FlashwarsWeb.LearnLiveTest do
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

  # test "loads learn view and shows choices; answer then next", %{
  #   conn: conn,
  #   org: org,
  #   user: user,
  #   set: set
  # } do
  #   conn = sign_in(conn, user)

  #   {:ok, lv, html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/learn")
  #   assert html =~ "Learn: #{set.name}"

  #   # Should render 4 choice buttons
  #   assert html =~ "data-choice-index=\"0\""
  #   assert html =~ "data-choice-index=\"1\""
  #   assert html =~ "data-choice-index=\"2\""
  #   assert html =~ "data-choice-index=\"3\""

  #   # Click first choice, expect feedback and Next button
  #   _html = lv |> element("button[data-choice-index='0']") |> render_click()
  #   html = render(lv)
  #   assert html =~ "Next"

  #   # Advance to next item
  #   _html = lv |> element("#next-btn") |> render_click()
  #   html = render(lv)
  #   # not answered yet
  #   refute html =~ "Next"
  # end
end
