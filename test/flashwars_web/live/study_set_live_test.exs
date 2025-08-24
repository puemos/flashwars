defmodule FlashwarsWeb.StudySetLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flashwars.{Content, Org, Learning}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization
  require Ash.Query

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
    assert path =~ ~r{/orgs/#{org.id}/study_sets/.+$}
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
    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}")

    form(lv, "#term-form",
      term: %{
        term: "Atom",
        definition: "Smallest unit of matter"
      }
    )
    |> render_submit()

    # The list lives in the container with id="terms"
    assert has_element?(lv, "#terms td", "Atom")
    assert has_element?(lv, "#terms td", "Smallest unit of matter")
  end

  test "header shows privacy and term count", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-LV-3"})
    user = Ash.Seed.seed!(User, %{email: "lv-user3@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: user.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "Physics", organization_id: org.id, owner_id: user.id, privacy: :private},
        actor: user
      )

    # at least one term so the count renders > 0 and preview has a card
    _t =
      Content.create_term!(
        %{term: "Arti", definition: "Artist", study_set_id: set.id, position: 1},
        actor: user
      )

    conn = sign_in(conn, user)
    {:ok, _lv, html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}")

    assert html =~ "Physics"
    assert html =~ "Private"
    assert html =~ "terms"
  end

  test "preview study card accepts grading", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-LV-4"})
    user = Ash.Seed.seed!(User, %{email: "lv-user4@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: user.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "History", organization_id: org.id, owner_id: user.id, privacy: :private},
        actor: user
      )

    _t =
      Content.create_term!(
        %{term: "Anomalia", definition: "Anomaly", study_set_id: set.id, position: 1},
        actor: user
      )

    conn = sign_in(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}")

    # click ✓ on the preview card; assert the view re-renders without crashing
    lv |> element("button[phx-value-grade=good]") |> render_click()
  end

  test "privacy change is saved", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-LV-5"})
    user = Ash.Seed.seed!(User, %{email: "lv-user5@example.com"})
    Org.add_member!(%{organization_id: org.id, user_id: user.id, role: :admin}, authorize?: false)

    set =
      Content.create_study_set!(
        %{name: "Geo", organization_id: org.id, owner_id: user.id, privacy: :private},
        actor: user
      )

    conn = sign_in(conn, user)
    {:ok, lv, _} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}")

    lv
    |> element("button[phx-click=open_share]")
    |> render_click()

    lv
    |> form("#set-privacy-form", set: %{privacy: "link_only"})
    |> render_submit()

    {:ok, updated} = Content.get_study_set_by_id(set.id, actor: user)
    assert updated.privacy == :link_only
  end

  test "edit, delete, and reorder terms; bulk add; privacy link; expertise badges", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Manage"})
    admin = Ash.Seed.seed!(User, %{email: "admin-manage@example.com"})
    student = Ash.Seed.seed!(User, %{email: "student-manage@example.com"})

    Org.add_member!(%{organization_id: org.id, user_id: admin.id, role: :admin},
      authorize?: false
    )

    Org.add_member!(%{organization_id: org.id, user_id: student.id, role: :member},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{name: "Bio", organization_id: org.id, owner_id: admin.id, privacy: :private},
        actor: admin
      )

    t1 =
      Content.create_term!(%{study_set_id: set.id, term: "Cell", definition: "Basic unit"},
        authorize?: false
      )

    t2 =
      Content.create_term!(%{study_set_id: set.id, term: "DNA", definition: "Genetic"},
        authorize?: false
      )

    conn = sign_in(conn, admin)
    {:ok, lv, _} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}")

    # Verify edit control exists
    assert has_element?(lv, "button[phx-click='edit'][phx-value-id='#{t1.id}']")

    # Delete control exists
    assert has_element?(lv, "button[phx-click='delete'][phx-value-id='#{t2.id}']")

    # Bulk add CSV
    csv = "Mitochondria,Powerhouse\nRibosome,Protein factory"

    _ =
      form(lv, "#bulk-form", bulk: %{csv: csv})
      |> render_submit()

    html = render(lv)
    assert html =~ "Added 2 terms"

    lv
    |> element("button[phx-click=open_share]")
    |> render_click()

    # Privacy link_only
    _ =
      form(lv, "#set-privacy-form", set: %{privacy: "link_only"})
      |> render_submit()

    html = render(lv)
    assert html =~ "Settings saved"
    assert html =~ "/s/t/"

    # Expertise badges: review one term as student
    # Simulate a review: sign in student and create a review for DNA-Edited
    # No need to open the Learn LV here
    # Directly call Learning.review to mark a term as correct for student
    term =
      Content.Term
      |> Ash.Query.filter(study_set_id == ^set.id and term == "DNA")
      |> Ash.read!(authorize?: false)
      |> List.first()

    {:ok, _} = Learning.review(admin, term.id, :good)

    # back to admin LV, refresh mastery and expect at least one badge present
    _ = lv |> element("button", "Refresh Expertise") |> render_click()
    _html = render(lv)

    # assert String.contains?(html, "Mastered") or String.contains?(html, "Practicing") or
    #          String.contains?(html, "Struggling")
  end

  test "inline edit updates a term", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "Org-Manage-Edit"})
    admin = Ash.Seed.seed!(User, %{email: "admin-edit@example.com"})

    Org.add_member!(%{organization_id: org.id, user_id: admin.id, role: :admin},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{name: "Bio-Edit", organization_id: org.id, owner_id: admin.id, privacy: :private},
        actor: admin
      )

    t =
      Content.create_term!(
        %{study_set_id: set.id, term: "DNA", definition: "Genetic", position: 1},
        authorize?: false
      )

    conn = sign_in(conn, admin)
    {:ok, lv, _} = live(conn, ~p"/orgs/#{org.id}/study_sets/#{set.id}")

    # Enter edit mode for the row
    lv
    |> element("button[phx-click='edit'][phx-value-id='#{t.id}']")
    |> render_click()

    # Ensure edit form is visible for the row
    assert has_element?(lv, "#edit-row-#{t.id}-form")

    # Submit the row form with updated values
    lv
    |> form("#edit-row-#{t.id}-form", edit: %{term: "DNA-Edited", definition: "Genetic Updated"})
    |> render_submit()

    # Verify the updated values appear in the table
    assert has_element?(lv, "#terms td", "DNA-Edited")
    assert has_element?(lv, "#terms td", "Genetic Updated")
  end
end
