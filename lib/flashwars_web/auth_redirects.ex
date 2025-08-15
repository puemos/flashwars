defmodule FlashwarsWeb.AuthRedirects do
  @moduledoc """
  Determines post-login redirect destinations based on org membership.
  """
  import Ash.Query
  alias Flashwars.Org.OrgMembership

  @spec path_for_user(struct()) :: String.t()
  def path_for_user(%{id: user_id} = actor) do
    org_ids =
      OrgMembership
      |> filter(user_id == ^user_id)
      |> Ash.read!(actor: actor, authorize?: false)
      |> Enum.map(& &1.organization_id)

    case org_ids do
      [only] -> "/orgs/" <> only
      _many_or_zero -> "/orgs"
    end
  end
end

