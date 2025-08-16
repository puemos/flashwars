defmodule FlashwarsWeb.GamesDuelLinkAccessTest do
  use FlashwarsWeb.ConnCase, async: true
  require Ash.Query

  import Phoenix.LiveViewTest
  alias Flashwars.{Content, Games, Org}
  alias Flashwars.Games.{GameRound}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  defp wait_for(fn_pred, attempts \\ 40)
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

  test "user from other org joins via link token and both can play rounds", %{conn: conn} do
    # Org A + host
    org_a = Ash.Seed.seed!(Organization, %{name: "OrgA"})
    host = Ash.Seed.seed!(User, %{email: "hostA@example.com"})

    Org.add_member!(%{organization_id: org_a.id, user_id: host.id, role: :admin},
      authorize?: false
    )

    # Org B + guest
    org_b = Ash.Seed.seed!(Organization, %{name: "OrgB"})
    guest = Ash.Seed.seed!(User, %{email: "guestB@example.com"})

    Org.add_member!(%{organization_id: org_b.id, user_id: guest.id, role: :admin},
      authorize?: false
    )

    # Study set in org A
    set =
      Content.create_study_set!(
        %{name: "SharedSet", organization_id: org_a.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    # Host creates link-only duel room
    room =
      Games.create_game_room!(
        %{type: :duel, study_set_id: set.id, privacy: :link_only},
        actor: host
      )

    assert room.link_token

    # Host opens room and starts game
    conn_host = sign_in(conn, host)
    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")
    _ = host_lv |> element("button", "Start Game") |> render_click()

    # Host answers correctly for round 1
    r1 =
      GameRound
      |> Ash.Query.filter(game_room_id == ^room.id)
      |> Ash.Query.sort(number: :asc)
      |> Ash.read!(authorize?: false)
      |> List.last()

    qd1 = r1.question_data
    aidx1 = qd1["answer_index"] || qd1[:answer_index]
    _ = host_lv |> element("button[phx-value-index='#{aidx1}']") |> render_click()

    # Guest joins via token and answers correctly for round 2
    conn_guest = sign_in(conn, guest)
    {:ok, guest_lv, _} = live(conn_guest, ~p"/games/t/#{room.link_token}")

    # Wait for the next round to be generated
    r2 =
      GameRound
      |> Ash.Query.filter(game_room_id == ^room.id)
      |> Ash.Query.sort(number: :desc)
      |> Ash.read!(authorize?: false)
      |> List.first()

    qd2 = r2.question_data
    aidx2 = qd2["answer_index"] || qd2[:answer_index]
    :ok = wait_for(fn -> has_element?(guest_lv, "button[phx-value-index='#{aidx2}']") end)
    _ = guest_lv |> element("button[phx-value-index='#{aidx2}']") |> render_click()

    # Ensure both liveviews still render and show scoreboard section
    assert render(host_lv) =~ "Scoreboard"
    assert render(guest_lv) =~ "Scoreboard"
  end
end
