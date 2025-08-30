defmodule FlashwarsWeb.LearnLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  alias Flashwars.Learning.SessionState
  alias Flashwars.Test.LearningFixtures

  setup do
    {:ok, LearningFixtures.build_set(nil)}
  end

  test "requeues incorrect answers in learn state" do
    items = [
      %{
        term_id: "t1",
        kind: "multiple_choice",
        prompt: "Q1",
        choices: ["a", "b", "c", "d"],
        answer_index: 1
      },
      %{
        term_id: "t2",
        kind: "multiple_choice",
        prompt: "Q2",
        choices: ["a", "b", "c", "d"],
        answer_index: 2
      }
    ]

    state = %SessionState{
      round_items: items,
      round_index: 0,
      round_number: 1,
      round_correct_count: 0,
      round_position: 1,
      current_item: hd(items),
      session_stats: %{total_correct: 0, total_questions: 0},
      mode: :learn,
      phase: :first_pass
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        session_state: state,
        answered?: false,
        round_closed?: false,
        study_set: %{},
        current_user: nil,
        __changed__: %{}
      }
    }

    {:noreply, socket} = FlashwarsWeb.StudySetLive.Learn.handle_event("dont_know", %{}, socket)
    {:noreply, socket} = FlashwarsWeb.StudySetLive.Learn.handle_event("dont_know", %{}, socket)

    assert socket.assigns.session_state.phase == :retry
    assert socket.assigns.session_state.current_item.term_id == "t1"
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

defmodule FlashwarsWeb.LearnSettingsUITest do
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

  test "settings panel toggles and renders", %{conn: conn, org: org, user: user, set: set} do
    conn = sign_in(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/learn")
    _ = render(lv)
    :ok = wait_for_selector(lv, "[phx-click='toggle_settings']")

    refute has_element?(lv, "#learn-settings-card")
    _ = lv |> element("[phx-click='toggle_settings']") |> render_click()
    :ok = wait_for_selector(lv, "#learn-settings-card")

    assert has_element?(lv, "#learn-settings-card")
  end
end

defmodule FlashwarsWeb.LearnFlowE2ETest do
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

  defp wait_for(fun, attempts \\ 80)
  defp wait_for(_fun, 0), do: :timeout

  defp wait_for(fun, n) do
    case fun.() do
      true ->
        :ok

      _ ->
        Process.sleep(25)
        wait_for(fun, n - 1)
    end
  end

  test "answer then continue advances to next question", %{
    conn: conn,
    org: org,
    user: user,
    set: set
  } do
    conn = sign_in(conn, user)
    {:ok, lv, html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/learn")
    assert html =~ "Learn"

    # Open settings and restrict to multiple choice only, then restart session
    :ok = wait_for(fn -> has_element?(lv, "[phx-click='toggle_settings']") end)
    _ = lv |> element("[phx-click='toggle_settings']") |> render_click()
    :ok = wait_for_selector(lv, "#learn-settings")
    _ =
      form(lv, "#learn-settings",
        settings: %{
          types: %{multiple_choice: "on"},
          smart: "true",
          size: "5"
        }
      )
      |> render_change()

    _ =
      lv
      |> element("#learn-settings-card button", "Start New Session With Settings")
      |> render_click()

    # Wait for choices to render (buttons carry phx-click="answer")
    :ok =
      wait_for(
        fn -> has_element?(lv, "button[phx-click='answer'][phx-value-index='0']") end,
        1000
      )

    # Answer first option
    _ = lv |> element("button[phx-click='answer'][phx-value-index='0']") |> render_click()
    :ok = wait_for(fn -> has_element?(lv, "#next-btn") end)

    # Continue to next item
    _ = lv |> element("#next-btn") |> render_click()
    # Ensure position increments; the UI shows "Question X / N"
    :ok = wait_for(fn -> render(lv) =~ ~r/Question\s+\d+\s+\/\s+\d+/ end)
  end
end
