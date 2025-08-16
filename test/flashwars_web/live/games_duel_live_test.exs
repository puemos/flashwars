defmodule FlashwarsWeb.GamesDuelLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Flashwars.{Content, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  test "create duel from study set listing and start game", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Game"})
    user = Ash.Seed.seed!(User, %{email: "admin@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: user.id, role: :admin}, authorize?: false)

    # Create a study set with terms
    set =
      Content.create_study_set!(
        %{name: "SetOne", organization_id: org.id, owner_id: user.id, privacy: :private},
        actor: user
      )

    # seed min 4 terms for MCQ
    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    conn = sign_in(conn, user)

    # Go to study set terms page and click Create Duel
    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/terms")
    assert has_element?(lv, "button", "Create Duel")
    _html = lv |> element("button", "Create Duel") |> render_click()

    # Should navigate to the room page
    {path, _} = assert_redirect(lv, 500)
    assert String.starts_with?(path, "/games/r/")

    # Load the room liveview
    {:ok, room_lv, room_html} = live(conn, path)
    assert room_html =~ "Duel Room"

    # Host starts the game
    _html = room_lv |> element("button", "Start Game") |> render_click()
    html = render(room_lv)
    assert html =~ "Question"
  end

  test "host can configure settings and copy link when link-only", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Game2"})
    user = Ash.Seed.seed!(User, %{email: "admin2@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: user.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "SetTwo", organization_id: org.id, owner_id: user.id, privacy: :private},
        actor: user
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    conn = sign_in(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/terms")
    _ = lv |> element("button", "Create Duel") |> render_click()
    {path, _} = assert_redirect(lv, 500)

    {:ok, room_lv, _} = live(conn, path)
    # Change privacy to link_only and save
    form(room_lv, "#duel-settings-form",
      settings: %{rounds: "2", privacy: "link_only", types: ["multiple_choice"]}
    )
    |> render_submit()

    html = render(room_lv)
    assert html =~ "Settings saved"
    assert html =~ "Copy Invitation Link"
    assert html =~ "/games/t/"

    # Verify persisted values in DB
    room_id = path |> String.split("/") |> List.last()
    room = Ash.get!(Flashwars.Games.GameRoom, room_id, authorize?: false)
    assert room.privacy == :link_only
    assert is_binary(room.link_token) and byte_size(room.link_token) > 10
    assert (room.config["rounds"] || room.config[:rounds]) == 2
  end

  test "default playful names are unique and used in lobby and final scores", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Names"})
    host = Ash.Seed.seed!(User, %{email: "names-host@example.com"})
    guest = Ash.Seed.seed!(User, %{email: "names-guest@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    Org.add_member!(%{organization_id: org.id, user_id: guest.id, role: :member},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{name: "Set-Names", organization_id: org.id, owner_id: host.id, privacy: :private},
        actor: host
      )

    for {t, d} <- [{"a", "1"}, {"b", "2"}, {"c", "3"}, {"d", "4"}] do
      Content.create_term!(%{study_set_id: set.id, term: t, definition: d}, authorize?: false)
    end

    room =
      Flashwars.Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :private},
        actor: host
      )

    conn_host = sign_in(conn, host)
    {:ok, host_lv, _} = live(conn_host, ~p"/games/r/#{room.id}")

    conn_guest = sign_in(conn, guest)
    {:ok, _guest_lv, _} = live(conn_guest, ~p"/games/r/#{room.id}")

    # In lobby, grab player names from the list
    lobby_html = render(host_lv)
    # Extract the second <span> text within each lobby <li>
    items =
      Regex.scan(~r/<li[^>]*>\s*<span[^>]*><\/span>\s*<span>([^<]+)<\/span>/, lobby_html)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.filter(&(&1 != ""))

    # Should have at least two names, unique and not email local-parts
    [n1, n2 | _] = items
    refute n1 == n2
    refute String.contains?(String.downcase(n1), "names-host")
    refute String.contains?(String.downcase(n2), "names-guest")

    # Start a 1-round game and answer to finish quickly
    _ =
      form(host_lv, "#duel-settings-form",
        settings: %{
          rounds: "1",
          privacy: "private",
          types: ["multiple_choice"],
          time_limit_ms: ""
        }
      )
      |> render_submit()

    _ = host_lv |> element("button", "Start Game") |> render_click()
    _ = host_lv |> element("#duel-round button[phx-value-index='0']") |> render_click()

    # Final scores should use names (not email local-parts)
    html = render(host_lv)

    scores =
      Regex.scan(~r/<li[^>]*>\s*<span>\s*([^<]+)<\/span>\s*<span class=\"font-semibold\">/m, html)
      |> Enum.map(fn [_, text] -> text end)

    assert Enum.any?(scores, fn t -> String.contains?(t, n1) or String.contains?(t, n2) end)

    refute Enum.any?(scores, fn t ->
             low = String.downcase(t)
             String.contains?(low, "names-host") or String.contains?(low, "names-guest")
           end)
  end
end
