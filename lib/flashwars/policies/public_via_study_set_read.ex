defmodule Flashwars.Policies.PublicViaStudySetRead do
  @moduledoc "Authorizes read when the related study_set is public."
  use Ash.Policy.FilterCheck

  @impl true
  def filter(_actor, _context, _opts) do
    Ash.Expr.expr(study_set.privacy == :public)
  end

  @impl Ash.Policy.Check
  def describe(_opts), do: "public via related study_set"
end
