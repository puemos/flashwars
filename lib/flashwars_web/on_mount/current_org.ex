defmodule FlashwarsWeb.OnMount.CurrentOrg do
  @moduledoc """
  On-mount helpers to load and authorize the current organization context.
  """
  import Phoenix.Component
  use FlashwarsWeb, :verified_routes
  import Ash.Query

  alias Flashwars.Org.{Organization, OrgMembership}

  # Ensures the current user is a member of the given org id param
  def on_mount(:require_member, %{"org_id" => org_id}, _session, socket) do
    actor = socket.assigns[:current_user]

    if authorized_member?(actor, org_id) do
      {:ok, org} = Ash.get(Organization, org_id, actor: actor, authorize?: false)

      {:cont,
       socket
       |> assign(:current_org, org)
       |> assign(:current_scope, %{org_id: org.id})}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  # Ensures the current user is an admin of the given org id param
  def on_mount(:require_admin, %{"org_id" => org_id}, _session, socket) do
    actor = socket.assigns[:current_user]

    if authorized_admin?(actor, org_id) do
      {:ok, org} = Ash.get(Organization, org_id, actor: actor, authorize?: false)

      {:cont,
       socket
       |> assign(:current_org, org)
       |> assign(:current_scope, %{org_id: org.id})}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  defp authorized_member?(nil, _), do: false
  defp authorized_member?(actor, org_id) do
    OrgMembership
    |> filter(organization_id == ^org_id and user_id == ^actor.id)
    |> Ash.exists?(actor: actor, authorize?: false)
  end

  defp authorized_admin?(nil, _), do: false
  defp authorized_admin?(actor, org_id) do
    OrgMembership
    |> filter(organization_id == ^org_id and user_id == ^actor.id and role == :admin)
    |> Ash.exists?(actor: actor, authorize?: false)
  end
end

