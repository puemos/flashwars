defmodule FlashwarsWeb.StudySetTokenLiveTest do
  use FlashwarsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Flashwars.{Content, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.Organization

  test "anonymous can view link-shared set with terms", %{conn: conn} do
    org = Ash.Seed.seed!(Organization, %{name: "TokenOrg"})
    owner = Ash.Seed.seed!(User, %{email: "owner-token@example.com"})

    Org.add_member!(%{organization_id: org.id, user_id: owner.id, role: :admin},
      authorize?: false
    )

    set =
      Content.create_study_set!(
        %{
          name: "Shared Biology",
          organization_id: org.id,
          owner_id: owner.id,
          privacy: :link_only
        },
        actor: owner
      )

    # Ensure a few terms exist
    Content.create_term!(%{study_set_id: set.id, term: "Cell", definition: "Basic unit"},
      authorize?: false
    )

    Content.create_term!(%{study_set_id: set.id, term: "DNA", definition: "Genetic material"},
      authorize?: false
    )

    assert is_binary(set.link_token)

    {:ok, _lv, html} = live(conn, ~p"/s/t/#{set.link_token}")
    assert html =~ "Shared Biology"
    assert html =~ "Cell"
    assert html =~ "Basic unit"
  end
end
