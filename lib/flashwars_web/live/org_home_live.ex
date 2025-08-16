defmodule FlashwarsWeb.OrgHomeLive do
  use FlashwarsWeb, :live_view

  import Ash.Query
  alias Flashwars.Content.StudySet
  alias Flashwars.Learning.Session
  alias Flashwars.Games

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    org = socket.assigns.current_org

    my_sets =
      StudySet
      |> filter(owner_id == ^actor.id and organization_id == ^org.id)
      |> sort(updated_at: :desc)
      |> limit(6)
      |> Ash.read!(actor: actor)

    recent_sessions =
      Session
      |> filter(user_id == ^actor.id and organization_id == ^org.id)
      |> sort(updated_at: :desc)
      |> limit(6)
      |> Ash.read!(actor: actor, load: [:study_set])

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign_new(:current_scope, fn -> %{org_id: org.id} end)
     |> assign(:my_sets, my_sets)
     |> assign(:recent_sessions, recent_sessions)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
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

      <div class="mt-8 grid grid-cols-1 gap-4 md:grid-cols-2">
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title">My Study Sets</h3>
            <div :if={@my_sets == []} class="text-sm opacity-70">No sets yet.</div>
            <ul :if={@my_sets != []} class="menu">
              <li :for={set <- @my_sets} class="flex items-center justify-between">
                <div>
                  <.link navigate={~p"/orgs/#{@current_org.id}/study_sets/#{set.id}/terms"}>
                    <span class="font-medium">{set.name}</span>
                    <span class="opacity-60">
                      · updated {Calendar.strftime(set.updated_at, "%b %d")}
                    </span>
                  </.link>
                </div>
                <div class="flex gap-2">
                  <.link
                    navigate={~p"/orgs/#{@current_org.id}/study_sets/#{set.id}/learn"}
                    class="btn btn-sm"
                  >
                    Learn
                  </.link>
                  <.link
                    navigate={~p"/orgs/#{@current_org.id}/study_sets/#{set.id}/flashcards"}
                    class="btn btn-sm"
                  >
                    Flashcards
                  </.link>
                  <.link
                    navigate={~p"/orgs/#{@current_org.id}/study_sets/#{set.id}/test"}
                    class="btn btn-sm"
                  >
                    Test
                  </.link>
                  <button
                    type="button"
                    class="btn btn-sm btn-primary"
                    phx-click="create_duel"
                    phx-value-set-id={set.id}
                  >
                    Create Duel
                  </button>
                </div>
              </li>
            </ul>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title">Recent Activity</h3>
            <div :if={@recent_sessions == []} class="text-sm opacity-70">None yet.</div>
            <ul :if={@recent_sessions != []} class="menu">
              <li :for={s <- @recent_sessions}>
                <span>
                  Studied <strong>{(s.study_set && s.study_set.name) || "a set"}</strong>
                  in {Atom.to_string(s.mode) |> String.capitalize()} · {Calendar.strftime(
                    s.updated_at,
                    "%b %d"
                  )}
                </span>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("create_duel", %{"set-id" => set_id}, socket) do
    actor = socket.assigns.current_user

    case Games.create_game_room(%{type: :duel, study_set_id: set_id, privacy: :private},
           actor: actor
         ) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/games/r/#{room.id}")}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, "Could not create duel: #{inspect(err)}")}
    end
  end
end
