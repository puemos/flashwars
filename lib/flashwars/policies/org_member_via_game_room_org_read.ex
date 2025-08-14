defmodule Flashwars.Policies.OrgMemberViaGameRoomOrgRead do
  @moduledoc "Authorizes read when actor is a member via game_room.organization."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    expr(
      not is_nil(game_room.organization_id) and
        exists(game_room.organization.memberships, user_id == actor(:id))
    )
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is member via game_room.organization"
end
