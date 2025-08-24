defmodule FlashwarsWeb.OrgSelectLive do
  use FlashwarsWeb, :live_view

  import Ash.Query
  alias Flashwars.Org
  alias Flashwars.Org.Organization

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user

    orgs =
      Org.list_org_memberships_for_user!(actor.id, actor: actor, authorize?: false)
      |> Enum.map(& &1.organization_id)
      |> then(fn ids ->
        if ids == [] do
          []
        else
          # use code interface with an Ash.Query to apply `id in ^ids`
          Org.list_organizations!(
            actor: actor,
            authorize?: false,
            query: Organization |> filter(id in ^ids)
          )
        end
      end)

    {:ok,
     socket
     |> assign(:page_title, "Select Organization")
     |> assign_new(:current_scope, fn -> nil end)
     |> assign(:orgs, orgs)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
      orgs={@orgs}
    >
      <.header>
        Choose an organization
        <:subtitle>Select where to work</:subtitle>
      </.header>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div :for={org <- @orgs} class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title">{org.name}</h3>
            <div class="card-actions justify-end">
              <.link navigate={~p"/orgs/#{org.id}"} class="btn btn-primary">Open</.link>
            </div>
          </div>
        </div>
        <div :if={@orgs == []} class="text-sm opacity-70">
          You are not a member of any organizations.
        </div>
      </div>
    </Layouts.app>
    """
  end
end
