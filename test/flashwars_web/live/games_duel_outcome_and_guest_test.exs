defmodule FlashwarsWeb.GamesDuelOutcomeAndGuestTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Flashwars.{Content, Games, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization
  alias Flashwars.Games.GameRound

  defp sign_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  defp wait_for(fun, attempts \\ 200)
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

  setup do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Outcome"})
    host = Ash.Seed.seed!(User, %{email: "host-outcome@example.com"})
    guest = Ash.Seed.seed!(User, %{email: "guest-outcome@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    Org.add_member!(%{organization_id: org.id, user_id: guest.id, role: :member},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{name: "Set-Outcome", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    {:ok, host: host, guest: guest, set: set}
  end

  test "correct answer shows YOU WIN for answerer, YOU LOSE for others", %{
    conn: conn,
    host: host,
    guest: guest,
    set: set
  } do
    room =
      Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private},
        actor: host
      )

    conn_host = sign_in(conn, host)
    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")

    # Short intermission, no round timer
    _ =
      form(host_lv, "#duel-settings-form",
        settings: %{
          rounds: "2",
          privacy: "private",
          types: ["multiple_choice"],
          time_limit_ms: "",
          intermission_ms: "400"
        }
      )
      |> render_submit()

    _ = host_lv |> element("button", "Start Game") |> render_click()

    conn_guest = sign_in(conn, guest)
    {:ok, guest_lv, _} = live(conn_guest, ~p"/games/r/#{room.id}")

    # Get current round answer index
    r1 =
      GameRound
      |> Ash.Query.filter(game_room_id == ^room.id)
      |> Ash.Query.sort(number: :desc)
      |> Ash.read!(authorize?: false)
      |> List.first()

    aidx = r1.question_data["answer_index"] || r1.question_data[:answer_index]

    _ = guest_lv |> element("#duel-round button[phx-value-index='#{aidx}']") |> render_click()

    :ok = wait_for(fn -> has_element?(guest_lv, "#result-overlay") end)
    :ok = wait_for(fn -> has_element?(host_lv, "#result-overlay") end)

    assert render(guest_lv) =~ "YOU WIN!"
    assert render(host_lv) =~ "YOU LOSE"
  end

  test "first wrong answer results in NO WINNER (draw) for all viewers", %{
    conn: conn,
    host: host,
    guest: guest,
    set: set
  } do
    room =
      Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private},
        actor: host
      )

    conn_host = sign_in(conn, host)
    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")
    _ = host_lv |> element("button", "Start Game") |> render_click()

    conn_guest = sign_in(conn, guest)
    {:ok, guest_lv, _} = live(conn_guest, ~p"/games/r/#{room.id}")

    # Get current round and choose a wrong index
    r1 =
      GameRound
      |> Ash.Query.filter(game_room_id == ^room.id)
      |> Ash.Query.sort(number: :desc)
      |> Ash.read!(authorize?: false)
      |> List.first()

    aidx = r1.question_data["answer_index"] || r1.question_data[:answer_index]
    wrong_idx = if aidx == 0, do: 1, else: 0

    _ =
      guest_lv |> element("#duel-round button[phx-value-index='#{wrong_idx}']") |> render_click()

    :ok = wait_for(fn -> has_element?(guest_lv, "#result-overlay") end)
    :ok = wait_for(fn -> has_element?(host_lv, "#result-overlay") end)

    assert render(guest_lv) =~ "NO WINNER"
    assert render(host_lv) =~ "NO WINNER"
  end

  test "anonymous guest via link can answer and see overlay; scoreboard hidden", %{
    conn: conn,
    host: host,
    set: set
  } do
    room =
      Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :link_only},
        actor: host
      )

    # Host starts game
    conn_host = sign_in(conn, host)
    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")
    _ = host_lv |> element("button", "Start Game") |> render_click()

    # Anonymous guest joins via token (no sign_in)
    {:ok, anon_lv, _} = live(conn, ~p"/games/t/#{room.link_token}")

    # Click first choice
    _ = anon_lv |> element("#duel-round button[phx-value-index='0']") |> render_click()

    :ok = wait_for(fn -> has_element?(anon_lv, "#result-overlay") end)
    # Scoreboard prompt visible to anonymous users
    assert render(anon_lv) =~ "Sign in to play and see your score"
  end
end
