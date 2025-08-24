defmodule FlashwarsWeb.AuthRedirects do
  @moduledoc """
  Determines post-login redirect destinations based on org membership.
  """
  alias Flashwars.Org

  @spec path_for_user(struct()) :: String.t()
  def path_for_user(%{id: user_id} = actor) do
    org_ids =
      Org.list_org_memberships!(
        actor: actor,
        authorize?: false,
        query: [filter: [user_id: user_id]]
      )
      |> Enum.map(& &1.organization_id)

    case org_ids do
      [only] -> "/orgs/" <> only
      _many_or_zero -> "/orgs"
    end
  end
end
