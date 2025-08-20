defmodule FlashwarsWeb.OrgLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flashwars.Org
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  test "org selector lists orgs and links", %{conn: conn} do
    user = Ash.Seed.seed!(User, %{email: "orgsel@example.com"})
    :ok = Org.ensure_default_org_for(user)

    conn = sign_in(conn, user)
    {:ok, lv, html} = live(conn, ~p"/orgs")
    assert html =~ "Choose an organization"
    assert render(lv) =~ "Open"
  end

  test "org home renders for member", %{conn: conn} do
    user = Ash.Seed.seed!(User, %{email: "orghome@example.com"})
    :ok = Org.ensure_default_org_for(user)

    # find org
    org =
      Organization
      |> Ash.read!(authorize?: false)
      |> Enum.find(fn o -> String.contains?(String.downcase(o.name), "orghome") end)

    conn = sign_in(conn, user)
    {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.id}")
    assert html =~ "Create Study Set"
    assert html =~ "My Study Sets"
    assert html =~ "Recent Activity"
  end
end
