defmodule Flashwars.Org do
  use Ash.Domain, otp_app: :flashwars
  require Ash.Expr
  require Ash.Query

  resources do
    resource Flashwars.Org.Organization do
      define :create_organization, action: :create
    end

    resource Flashwars.Org.OrgMembership do
      define :add_member, action: :create
    end

    resource Flashwars.Org.OrgDomain do
      define :add_org_domain, action: :create
    end
  end

  @doc """
  Ensures the given user has a default organization and is an admin member.

  - If the user already has any organization membership, this is a no-op.
  - Otherwise creates a new organization and adds the user as :admin.
  """
  @spec ensure_default_org_for(struct()) :: :ok | {:error, term()}
  def ensure_default_org_for(%{id: user_id, email: email} = user) do
    alias Flashwars.Org.{Organization, OrgMembership}

    has_membership? =
      OrgMembership
      |> Ash.Query.filter(Ash.Expr.expr(user_id == ^user_id))
      |> Ash.exists?(actor: user, authorize?: false)

    if has_membership? do
      :ok
    else
      name = default_org_name(email)

      with {:ok, org} <-
             Ash.create(Organization, %{name: name}, action: :create, authorize?: false),
           {:ok, _mem} <-
             Ash.create(
               OrgMembership,
               %{organization_id: org.id, user_id: user_id, role: :admin},
               action: :create,
               authorize?: false
             ) do
        :ok
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :unknown}
      end
    end
  end

  defp default_org_name(nil), do: "My Organization"

  defp default_org_name(email) do
    email = to_string(email)
    local = email |> String.split("@", parts: 2) |> List.first()
    "#{local}'s Organization"
  end
end
