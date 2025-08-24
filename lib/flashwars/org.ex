defmodule Flashwars.Org do
  use Ash.Domain, otp_app: :flashwars
  require Ash.Expr

  resources do
    resource Flashwars.Org.Organization do
      define :create_organization, action: :create
      define :get_organization_by_id, action: :read, get_by: [:id]
      define :list_organizations, action: :read
    end

    resource Flashwars.Org.OrgMembership do
      define :add_member, action: :create
      define :list_org_memberships, action: :read
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
    has_membership? =
      list_org_memberships!(
        actor: user,
        authorize?: false,
        query: [filter: [user_id: user_id], limit: 1]
      )
      |> Enum.any?()

    if has_membership? do
      :ok
    else
      name = default_org_name(email)

      with {:ok, org} <- create_organization(%{name: name}, authorize?: false),
           {:ok, _mem} <-
             add_member(%{organization_id: org.id, user_id: user_id, role: :admin},
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

  @doc "Returns true if user_id is a member of org_id."
  @spec member?(String.t(), String.t(), keyword) :: boolean
  def member?(org_id, user_id, opts \\ []) do
    list_org_memberships!(
      Keyword.merge(
        [
          authorize?: false,
          query: [filter: [organization_id: org_id, user_id: user_id], limit: 1]
        ],
        opts
      )
    )
    |> Enum.any?()
  end

  @doc "Returns true if user_id is an admin member of org_id."
  @spec admin_member?(String.t(), String.t(), keyword) :: boolean
  def admin_member?(org_id, user_id, opts \\ []) do
    list_org_memberships!(
      Keyword.merge(
        [
          authorize?: false,
          query: [filter: [organization_id: org_id, user_id: user_id, role: :admin], limit: 1]
        ],
        opts
      )
    )
    |> Enum.any?()
  end
end
