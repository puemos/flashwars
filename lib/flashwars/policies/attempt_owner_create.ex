defmodule Flashwars.Policies.AttemptOwnerCreate do
  @moduledoc "Authorizes create when actor owns the referenced attempt."
  use Ash.Policy.SimpleCheck
  alias Flashwars.Learning.Attempt

  @impl true
  def describe(_opts), do: "actor owns the attempt"

  @impl true
  def match?(actor, %{changeset: changeset}, _opts) do
    att_id = Ash.Changeset.get_attribute(changeset, :attempt_id)

    if is_nil(att_id) or is_nil(actor) do
      false
    else
      case Ash.get(Attempt, att_id, authorize?: false) do
        {:ok, att} -> att.user_id == actor.id
        _ -> false
      end
    end
  end

  def match?(_actor, _context, _opts), do: false
end
