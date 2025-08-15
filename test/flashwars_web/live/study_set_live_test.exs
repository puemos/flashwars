defmodule FlashwarsWeb.StudySetLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flashwars.{Content, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  defp sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("user_token", token)
  end

  test "create study set navigates to terms", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-LV"})
    user = Ash.Seed.seed!(User, %{email: "lv-user@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: user.id, role: :admin}, authorize?: false)

    conn = sign_in(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/new")

    form(lv, "#new-study-set",
      study_set: %{
        name: "Biology 101",
        description: "Intro",
        privacy: "private"
      }
    )
    |> render_submit()
    {path, _opts} = assert_redirect(lv, 500)
    assert path =~ ~r{/orgs/#{org.id}/study_sets/.+/terms$}
  end

  test "add term shows in the list", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-LV-2"})
    user = Ash.Seed.seed!(User, %{email: "lv-user2@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: user.id, role: :admin}, authorize?: false)

    # Pre-create a set to navigate directly to terms page
    set =
      Content.create_study_set!(
        %{name: "Chemistry", organization_id: org.id, owner_id: user.id, privacy: :private},
        actor: user
      )

    conn = sign_in(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}/terms")

    form(lv, "#term-form",
      term: %{
        term: "Atom",
        definition: "Smallest unit of matter"
      }
    )
    |> render_submit()

    assert has_element?(lv, "#terms-table td", "Atom")
    assert has_element?(lv, "#terms-table td", "Smallest unit of matter")
  end
end
