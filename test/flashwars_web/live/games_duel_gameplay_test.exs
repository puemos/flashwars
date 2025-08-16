defmodule FlashwarsWeb.GamesDuelGameplayTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Flashwars.{Content, Games, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization
  alias Flashwars.Games.GameRound

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  defp wait_for(fn_pred, attempts \\ 80)
  defp wait_for(_fun, 0), do: :timeout

  defp wait_for(fun, n) do
    case fun.() do
      true ->
        :ok

      _ ->
        :timer.sleep(25)
        wait_for(fun, n - 1)
    end
  end

  test "round closes on first answer, reveals, auto-advances", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Gameplay"})
    host = Ash.Seed.seed!(User, %{email: "hostA@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    guest = Ash.Seed.seed!(User, %{email: "guestA@example.com"})

    Org.add_member!(%{organization_id: org.id, user_id: guest.id, role: :member},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{name: "Set-Gameplay", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}, {"e", "5"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    room =
      Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private},
        actor: host
      )

    conn_host = sign_in(conn, host)
    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")

    # Set rounds: 2, disable timer
    _ =
      form(host_lv, "#duel-settings-form",
        settings: %{
          rounds: "2",
          privacy: "private",
          types: ["multiple_choice"],
          time_limit_ms: "",
          intermission_ms: "300"
        }
      )
      |> render_submit()

    _ = host_lv |> element("button", "Start Game") |> render_click()

    # Guest joins
    conn_guest = sign_in(conn, guest)
    {:ok, guest_lv, _} = live(conn_guest, ~p"/games/r/#{room.id}")

    # Fetch current round and pick first choice (may be wrong)
    GameRound
    |> Ash.Query.filter(game_room_id == ^room.id)
    |> Ash.Query.sort(number: :desc)
    |> Ash.read!(authorize?: false)
    |> List.first()

    # Click on guest (first option)
    _ = guest_lv |> element("#duel-round button[phx-value-index='0']") |> render_click()

    # Both should show reveal and disable buttons
    :ok = wait_for(fn -> render(host_lv) =~ "Correct answer:" end)
    :ok = wait_for(fn -> render(guest_lv) =~ "Correct answer:" end)
    assert render(guest_lv) =~ "selected"

    # After a short while, advance to next question (2)
    :ok = wait_for(fn -> render(host_lv) =~ "Question 2 of" end)
    :ok = wait_for(fn -> render(guest_lv) =~ "Question 2 of" end)
  end

  test "time limit shows countdown and auto-closes round", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Timer"})
    host = Ash.Seed.seed!(User, %{email: "hostTimer@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "Set-Timer", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    conn_host = sign_in(conn, host)

    {:ok, host_lv, _} =
      live(
        conn_host,
        ~p"/games/r/#{Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private}, actor: host).id}"
      )

    # Set a tiny timer and start
    _ =
      form(host_lv, "#duel-settings-form",
        settings: %{
          rounds: "2",
          privacy: "private",
          types: ["multiple_choice"],
          time_limit_ms: "400",
          intermission_ms: "300"
        }
      )
      |> render_submit()

    _ = host_lv |> element("button", "Start Game") |> render_click()

    # Countdown visible
    assert render(host_lv) =~ "Time left:"

    # Wait for auto close and reveal
    :ok = wait_for(fn -> render(host_lv) =~ "Correct answer:" end)
  end

  test "ready clicks start next round early when threshold met", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Ready"})
    host = Ash.Seed.seed!(User, %{email: "hostReady@example.com"})
    guest = Ash.Seed.seed!(User, %{email: "guestReady@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    Org.add_member!(%{organization_id: org.id, user_id: guest.id, role: :member},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{name: "Set-Ready", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}, {"e", "5"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    room =
      Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private},
        actor: host
      )

    # Host opens and configures long intermission to observe early start
    conn_host = sign_in(conn, host)
    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")

    _ =
      form(host_lv, "#duel-settings-form",
        settings: %{
          rounds: "2",
          privacy: "private",
          types: ["multiple_choice"],
          time_limit_ms: "",
          intermission_ms: "5000"
        }
      )
      |> render_submit()

    _ = host_lv |> element("button", "Start Game") |> render_click()

    # Guest joins
    conn_guest = sign_in(conn, guest)
    {:ok, guest_lv, _} = live(conn_guest, ~p"/games/r/#{room.id}")

    # Guest answers first to close round and trigger intermission
    _ = guest_lv |> element("#duel-round button[phx-value-index='0']") |> render_click()

    # Ensure intermission countdown visible
    :ok = wait_for(fn -> render(guest_lv) =~ "Next round in" end)

    # Both click Ready; since threshold is ceil(0.6*2)=2, both must be ready
    # Buttons are gated by @intermission_rid, wait until they appear
    :ok = wait_for(fn -> has_element?(host_lv, "button", "Ready") end)
    :ok = wait_for(fn -> has_element?(guest_lv, "button", "Ready") end)
    _ = host_lv |> element("button", "Ready") |> render_click()
    _ = guest_lv |> element("button", "Ready") |> render_click()

    # Should advance to Question 2 without waiting full 5s
    :ok = wait_for(fn -> render(host_lv) =~ "Question 2 of" end)
    :ok = wait_for(fn -> render(guest_lv) =~ "Question 2 of" end)
  end

  test "game over and restart allows new game", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Restart"})
    host = Ash.Seed.seed!(User, %{email: "hostRestart@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "Set-Restart", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    conn_host = sign_in(conn, host)

    room =
      Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private},
        actor: host
      )

    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")

    # One round only, short intermission for quick game over
    _ =
      form(host_lv, "#duel-settings-form",
        settings: %{
          rounds: "1",
          privacy: "private",
          types: ["multiple_choice"],
          time_limit_ms: "",
          intermission_ms: "300"
        }
      )
      |> render_submit()

    _ = host_lv |> element("button", "Start Game") |> render_click()

    # Answer to close the only round
    _ = host_lv |> element("#duel-round button[phx-value-index='0']") |> render_click()

    # Game over visible
    :ok = wait_for(fn -> render(host_lv) =~ "Game Over" end)

    # Restart
    _ = host_lv |> element("button", "Start New Game") |> render_click()
    assert render(host_lv) =~ "Waiting for host to start"
  end
end
