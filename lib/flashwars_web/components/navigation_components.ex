defmodule FlashwarsWeb.NavigationComponents do
  @moduledoc """
  Navigation building blocks: primary desktop nav, breadcrumbs, create menu,
  and a minimal mobile bottom nav. These are additive and not yet wired into
  `Layouts.app`, so they can be adopted incrementally by LiveViews/templates.

  Usage examples (in a LiveView template):

      <FlashwarsWeb.NavigationComponents.main_nav
        current_user={@current_user}
        current_scope={@current_scope}
        orgs_count={@orgs_count}
      />

      <FlashwarsWeb.NavigationComponents.breadcrumbs items={[
        %{label: @current_org.name, href: ~p"/orgs/#/{@current_org.id}"},
        %{label: "Study Sets", href: ~p"/orgs/#/{@current_org.id}/study_sets"},
        %{label: @page_title}
      ]} />

  """
  use FlashwarsWeb, :html

  # =============
  # Primary Nav
  # =============

  attr :current_user, :map, default: nil
  attr :current_scope, :map, default: nil
  attr :orgs_count, :integer, default: 0
  attr :orgs, :any, default: []

  def main_nav(assigns) do
    assigns =
      assign_new(assigns, :orgs_count, fn ->
        case assigns[:orgs] do
          list when is_list(list) -> length(list)
          _ -> assigns[:orgs_count] || 0
        end
      end)

    ~H"""
    <nav class="hidden md:flex items-center gap-1">
      <.link
        :if={@current_user && @current_scope && @current_scope[:org_id]}
        navigate={~p"/orgs/#{@current_scope[:org_id]}"}
        class="btn btn-ghost"
      >
        Play
      </.link>

      <.link
        :if={@current_user && @current_scope && @current_scope[:org_id]}
        navigate={~p"/orgs/#{@current_scope[:org_id]}/study_sets"}
        class="btn btn-ghost"
      >
        Study Sets
      </.link>

      <.link
        :if={@current_user && @current_scope && @current_scope[:org_id]}
        navigate={~p"/games/r/#{"new"}"}
        class="btn btn-ghost"
        aria-disabled="true"
        data-tooltip="Coming soon: Games index"
      >
        Games
      </.link>

      <div
        :if={@current_user && @current_scope && @current_scope[:org_id]}
        class="divider divider-horizontal"
      />

      <.create_menu
        :if={@current_user && @current_scope && @current_scope[:org_id]}
        org_id={@current_scope[:org_id]}
      />

      <div :if={@current_user && @orgs_count > 1} class="divider divider-horizontal" />

      <.org_switcher
        :if={@current_user && @orgs_count > 1}
        orgs={@orgs}
        current_scope={@current_scope}
      />
    </nav>
    """
  end

  # Split Create menu. Caller passes org_id for scoped targets.
  attr :org_id, :any, required: true

  def create_menu(assigns) do
    ~H"""
    <details class="dropdown dropdown-end">
      <summary class="btn btn-primary">
        <.icon name="hero-plus" class="mr-1 size-4" /> Create
      </summary>
      <ul class="dropdown-content menu bg-base-200 rounded-box z-[1] w-56 p-2 shadow">
        <li>
          <.link navigate={~p"/orgs/#{@org_id}/study_sets/new"}>
            <.icon name="hero-rectangle-stack" class="size-4" /> Study Set
          </.link>
        </li>
        <li>
          <a aria-disabled="true" class="disabled opacity-50">
            <.icon name="hero-user-group" class="size-4" /> Class (soon)
          </a>
        </li>
        <li>
          <a aria-disabled="true" class="disabled opacity-50">
            <.icon name="hero-bolt" class="size-4" /> Duel (quick start)
          </a>
        </li>
      </ul>
    </details>
    """
  end

  # Org switcher trigger only. The existing Layouts.app already renders the full dropdown
  # list with organizations; this is a compact version for reuse where needed.
  attr :orgs, :any, default: []
  attr :current_scope, :map, default: nil

  def org_switcher(assigns) do
    ~H"""
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
    """
  end

  # =============
  # Breadcrumbs
  # =============
  attr :items, :list, default: []
  attr :class, :string, default: nil

  def breadcrumbs(assigns) do
    ~H"""
    <nav
      :if={@items != []}
      class={[@class || "breadcrumbs text-sm text-base-content/70"]}
      aria-label="Breadcrumb"
    >
      <ul>
        <li :for={{item, idx} <- Enum.with_index(@items)}>
          <.link :if={item[:href] && idx < length(@items) - 1} navigate={item[:href]}>
            {item[:label]}
          </.link>
          <span :if={!item[:href] || idx == length(@items) - 1} class="font-medium text-base-content">
            {item[:label]}
          </span>
        </li>
      </ul>
    </nav>
    """
  end

  # =====================
  # Mobile bottom nav (v1)
  # =====================
  attr :current_scope, :map, default: nil
  attr :current_user, :map, default: nil

  def mobile_bottom_nav(assigns) do
    ~H"""
    <nav
      :if={@current_user}
      class="md:hidden fixed z-40 bottom-0 left-0 right-0 border-t border-base-300 bg-base-100/95 backdrop-blur"
    >
      <ul class="grid grid-cols-4">
        <li>
          <.link
            :if={@current_scope && @current_scope[:org_id]}
            navigate={~p"/orgs/#{@current_scope[:org_id]}"}
            class="flex flex-col items-center py-2"
          >
            <.icon name="hero-home" class="size-5" />
            <span class="text-[10px]">Home</span>
          </.link>
        </li>
        <li>
          <.link
            :if={@current_scope && @current_scope[:org_id]}
            navigate={~p"/orgs/#{@current_scope[:org_id]}/study_sets"}
            class="flex flex-col items-center py-2"
          >
            <.icon name="hero-rectangle-stack" class="size-5" />
            <span class="text-[10px]">Sets</span>
          </.link>
        </li>
        <li>
          <a class="flex flex-col items-center py-2 opacity-60" aria-disabled="true">
            <.icon name="hero-bolt" class="size-5" />
            <span class="text-[10px]">Games</span>
          </a>
        </li>
        <li>
          <.link href={~p"/sign-out"} class="flex flex-col items-center py-2">
            <.icon name="hero-user-circle" class="size-5" />
            <span class="text-[10px]">Account</span>
          </.link>
        </li>
      </ul>
    </nav>
    """
  end
end
