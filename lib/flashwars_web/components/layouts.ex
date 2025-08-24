defmodule FlashwarsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FlashwarsWeb, :html
  import Ash.Query
  alias Flashwars.Org
  alias Flashwars.Org.Organization

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the current signed-in user, if any"
  # Optional: allow callers to provide preloaded orgs for efficiency
  attr :orgs, :any, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:orgs, fn ->
        case assigns[:current_user] do
          nil ->
            []

          user ->
            Org.list_org_memberships_for_user!(user.id, actor: user, authorize?: false)
            |> Enum.map(& &1.organization_id)
            |> then(fn ids ->
              if ids == [] do
                []
              else
                # Pass an Ash.Query struct to the code interface
                Org.list_organizations!(
                  actor: user,
                  authorize?: false,
                  query: Organization |> filter(id in ^ids)
                )
              end
            end)
        end
      end)
      |> assign_new(:orgs_count, fn -> length(assigns[:orgs] || []) end)

    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href={~p"/"} class="flex w-fit items-center gap-2">
          <img src={~p"/images/logo.webp"} width="120" />
        </a>
      </div>
      <div class="flex-none">
        <ul class="menu menu-horizontal px-1 items-center gap-1">
          <li :if={@current_user && @orgs_count > 1}>
            <details class="dropdown dropdown-end">
              <summary class="btn btn-ghost">
                <span class="mr-2">Org</span>
                <.icon name="hero-chevron-down" class="w-4 h-4" />
              </summary>
              <ul class="dropdown-content menu bg-base-200 rounded-box z-[1] w-56 p-2 shadow max-h-72 overflow-auto">
                <li :for={org <- @orgs}>
                  <.link navigate={~p"/orgs/#{org.id}"}>
                    <span class={[
                      "truncate",
                      @current_scope && @current_scope[:org_id] == org.id && "font-semibold"
                    ]}>
                      {org.name}
                    </span>
                  </.link>
                </li>
              </ul>
            </details>
          </li>
          <li :if={@current_user && @current_scope && @current_scope[:org_id]}>
            <.link navigate={~p"/orgs/#{@current_scope[:org_id]}"} class="btn btn-ghost">Play</.link>
          </li>
          <li :if={@current_user && @current_scope && @current_scope[:org_id]}>
            <.link
              navigate={~p"/orgs/#{@current_scope[:org_id]}/study_sets/new"}
              class="btn btn-ghost"
            >
              Build Set
            </.link>
          </li>
          <%!-- <li>
            <.theme_toggle />
          </li> --%>
          <li :if={@current_user}>
            <details class="dropdown dropdown-end">
              <summary class="btn">Account</summary>
              <ul class="dropdown-content menu bg-base-200 rounded-box z-[1] w-52 p-2 shadow">
                <li><a href={~p"/sign-out"}>Sign out</a></li>
              </ul>
            </details>
          </li>
          <li :if={!@current_user}>
            <a href={~p"/sign-in"} class="btn">Sign in</a>
          </li>
          <li :if={!@current_user}>
            <a href={~p"/register"} class="btn btn-primary">Play Now</a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
