defmodule FlashwarsWeb.LayoutsNavTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flashwars.Accounts.User
  alias Flashwars.Org
  alias Flashwars.Org.Organization

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  test "navbar hides Organizations link and org switcher when exactly 1 org", %{conn: conn} do
    user = Ash.Seed.seed!(User, %{email: "nav_1_org@example.com"})
    :ok = Org.ensure_default_org_for(user)
    conn = sign_in(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orgs")

    refute has_element?(lv, "header a", "Organizations")
    refute render(lv) =~ ">Org<"
  end

  test "navbar shows org switcher when user has multiple orgs", %{conn: conn} do
    user = Ash.Seed.seed!(User, %{email: "nav_multi_orgs@example.com"})
    :ok = Org.ensure_default_org_for(user)

    # create a second org and add membership
    second = Ash.Seed.seed!(Organization, %{name: "Second Org - nav_multi_orgs"})

    {:ok, _mem} =
      Org.add_member(%{organization_id: second.id, user_id: user.id, role: :admin},
        authorize?: false
      )

    conn = sign_in(conn, user)
    {:ok, _lv, html} = live(conn, ~p"/orgs")

    assert html =~ ">Org<"
    # Dropdown should list org names; at least the known second org
    assert html =~ "Second Org - nav_multi_orgs"
  end
end
