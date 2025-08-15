defmodule Flashwars.Org.ProvisioningTest do
  use Flashwars.DataCase, async: true

  alias Flashwars.Org
  alias Flashwars.Accounts.User
  alias Flashwars.Org.{Organization, OrgMembership}
  import Ash.Query

  test "ensure_default_org_for creates org and admin membership for new user" do
    user = Ash.Seed.seed!(User, %{email: "provision@example.com"})

    assert :ok = Org.ensure_default_org_for(user)

    mems =
      OrgMembership
      |> filter(user_id == ^user.id)
      |> Ash.read!(authorize?: false)

    assert length(mems) == 1
    [mem] = mems
    assert mem.role == :admin

    org = Ash.get!(Organization, mem.organization_id, authorize?: false)
    assert is_binary(org.name)
  end

  test "ensure_default_org_for is idempotent if membership exists" do
    user = Ash.Seed.seed!(User, %{email: "provision2@example.com"})
    assert :ok = Org.ensure_default_org_for(user)
    assert :ok = Org.ensure_default_org_for(user)

    mems =
      OrgMembership
      |> filter(user_id == ^user.id)
      |> Ash.read!(authorize?: false)

    assert length(mems) == 1
  end
end

