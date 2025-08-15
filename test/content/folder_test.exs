defmodule Flashwars.Content.FolderTest do
  use Flashwars.DataCase, async: true

  alias Flashwars.{Content, Org}
  alias Flashwars.Accounts.User
  alias Flashwars.Org.{Organization}

  test "org admins can create folders in their org" do
    org = Ash.Seed.seed!(Organization, %{name: "Org"})
    admin = Ash.Seed.seed!(User, %{email: "admin@example.com"})

    Org.add_member!(
      %{
        organization_id: org.id,
        user_id: admin.id,
        role: :admin
      },
      authorize?: false
    )

    assert Content.can_create_folder?(admin, %{
             name: "Folder",
             organization_id: org.id,
             owner_id: admin.id
           })
  end

  test "non org admins cannot create folders in org" do
    org = Ash.Seed.seed!(Organization, %{name: "Org"})
    user = Ash.Seed.seed!(User, %{email: "user@example.com"})

    refute Content.can_create_folder?(user, %{
             name: "Folder",
             organization_id: org.id,
             owner_id: user.id
           })
  end
end
