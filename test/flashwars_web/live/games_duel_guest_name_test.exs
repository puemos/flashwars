defmodule FlashwarsWeb.GamesDuelGuestNameTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Flashwars.{Content, Games, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  defp sign_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  test "anonymous can set name and it reflects in input", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-GuestName"})
    host = Ash.Seed.seed!(User, %{email: "host-guest-name@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: host.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "Set-GuestName", organization_id: org.id, owner_id: host.id, privacy: :link_only},
        actor: host
      )

    room =
      Games.create_game_room!(%{type: :duel, study_set_id: set.id, privacy: :link_only},
        actor: host
      )

    # Anonymous visits token link
    {:ok, lv, _} = live(conn, ~p"/games/t/#{room.link_token}")

    # Submit name form as anonymous
    _ =
      form(lv, "#duel-name-form", name: %{name: "Speedy Panda"})
      |> render_submit()

    # The input reflects the chosen name
    html = render(lv)
    assert html =~ "value=\"Speedy Panda\""
  end
end
