defmodule FlashwarsWeb.OrgHomeLive do
  use FlashwarsWeb, :live_view

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign_new(:current_scope, fn -> %{org_id: socket.assigns.current_org.id} end)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@current_org.name}
        <:subtitle>Welcome back!</:subtitle>
        <:actions>
          <.link navigate={~p"/orgs/#{@current_org.id}/study_sets/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="mr-1" /> New Study Set
          </.link>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title">Quick Start</h3>
            <p>Create a study set and start adding terms.</p>
            <div class="card-actions justify-end">
              <.link navigate={~p"/orgs/#{@current_org.id}/study_sets/new"} class="btn">
                Create Study Set
              </.link>
            </div>
          </div>
        </div>
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title">Your Organization</h3>
            <p>Name: {@current_org.name}</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

