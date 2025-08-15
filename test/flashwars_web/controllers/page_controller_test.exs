defmodule FlashwarsWeb.PageControllerTest do
  use FlashwarsWeb.ConnCase

  alias Flashwars.Accounts.User
  alias Flashwars.Org
  alias Flashwars.Org.Organization

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session("user_token", token)
  end

  test "GET / shows new landing for logged out", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Study like a game."
    assert html_response(conn, 200) =~ "Play Now"
  end

  test "GET / redirects signed-in user with no orgs to /orgs", %{conn: conn} do
    user = Ash.Seed.seed!(User, %{email: "nav_root_no_orgs@example.com"})
    conn = conn |> sign_in(user)

    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/orgs"
  end

  test "GET / redirects signed-in user with one org to that org home", %{conn: conn} do
    user = Ash.Seed.seed!(User, %{email: "nav_root_one_org@example.com"})
    :ok = Org.ensure_default_org_for(user)

    # find that org id
    org =
      Organization
      |> Ash.read!(authorize?: false)
      |> Enum.find(fn o -> String.contains?(String.downcase(o.name), "nav_root_one_org") end)

    conn = conn |> sign_in(user)
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/orgs/" <> org.id
  end

  test "GET / redirects signed-in user with multiple orgs to /orgs", %{conn: conn} do
    user = Ash.Seed.seed!(User, %{email: "nav_root_multi@example.com"})
    :ok = Org.ensure_default_org_for(user)

    # create another org and add membership
    other = Ash.Seed.seed!(Organization, %{name: "Second Org - nav_root_multi"})

    {:ok, _mem} =
      Org.add_member(%{organization_id: other.id, user_id: user.id, role: :admin},
        authorize?: false
      )

    conn = conn |> sign_in(user)
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/orgs"
  end
end
