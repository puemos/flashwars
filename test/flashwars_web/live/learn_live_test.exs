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
    # Wait for header actions to render
    try do
      for _ <- 1..40 do
        _ = render(lv)
        if has_element?(lv, "[phx-click='toggle_settings']"), do: throw(:ready)
        Process.sleep(50)
      end
    catch
      :ready -> :ok
    end

    refute has_element?(lv, "#learn-settings-card")
    _ = lv |> element("[phx-click='toggle_settings']") |> render_click()
    # wait for panel to appear
    try do
      for _ <- 1..40 do
        if has_element?(lv, "#learn-settings-card"), do: throw(:ok)
        _ = render(lv)
        Process.sleep(25)
      end
    catch
      :ok -> :ok
    end

    assert has_element?(lv, "#learn-settings-card")
  end
end
