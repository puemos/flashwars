defmodule Flashwars.Policies.OrgMemberViaRoundCreate do
  @moduledoc "Authorizes create when actor is a member of the organization of the game round's room."
  use Ash.Policy.SimpleCheck
  import Ash.Query
  alias Flashwars.Games.GameRound
  alias Flashwars.Org.OrgMembership

  @impl true
  def describe(_opts), do: "actor is member of organization via game_round"

  @impl true
  def match?(actor, %{changeset: changeset}, _opts) do
    round_id = Ash.Changeset.get_attribute(changeset, :game_round_id)

    if is_nil(round_id) or is_nil(actor) do
      false
    else
      with {:ok, round} <- Ash.get(GameRound, round_id, authorize?: false),
           org_id when not is_nil(org_id) <- round.organization_id do
        OrgMembership
        |> filter(organization_id == ^org_id and user_id == ^actor.id)
        |> Ash.exists?(authorize?: false)
      else
        _ -> false
      end
    end
  end

  def match?(_actor, _context, _opts), do: false
end
