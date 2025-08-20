defmodule FlashwarsWeb.OrgHomeLive do
  use FlashwarsWeb, :live_view

  import Ash.Query
  alias Flashwars.Content.StudySet
  alias Flashwars.Learning.Session
  alias Flashwars.Learning.Mastery
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

    # Calculate mastery status for each study set
    sets_with_mastery =
      Enum.map(my_sets, fn set ->
        mastery = Mastery.classify(actor, set.id)
        mastered_count = length(mastery.mastered)
        struggling_count = length(mastery.struggling)
        practicing_count = length(mastery.practicing)
        unseen_count = length(mastery.unseen)
        total_terms = mastered_count + struggling_count + practicing_count + unseen_count

        mastery_percentage =
          if total_terms > 0, do: round(mastered_count / total_terms * 100), else: 0

        Map.put(set, :mastery_status, %{
          mastered: mastered_count,
          struggling: struggling_count,
          practicing: practicing_count,
          unseen: unseen_count,
          total: total_terms,
          percentage: mastery_percentage
        })
      end)

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
     |> assign(:my_sets, sets_with_mastery)
     |> assign(:recent_sessions, recent_sessions)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <!-- Hero Section with Welcome -->
      <div class="bg-base-200 rounded-2xl p-8 mb-8 border border-base-300/50">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-base-content mb-2">
              Welcome back!
            </h1>
            <p class="text-lg text-base-content/70 mb-6">
              Ready to learn something new today?
            </p>
          </div>
          <div class="hidden md:block">
            <div class="stats bg-base-100 shadow-sm border border-base-300/30">
              <div class="stat py-4 px-6">
                <div class="stat-value text-2xl text-base-content">{length(@my_sets)}</div>
                <div class="stat-title text-xs text-base-content/60">Study Sets</div>
              </div>
              <div class="stat py-4 px-6">
                <div class="stat-value text-2xl text-base-content">{length(@recent_sessions)}</div>
                <div class="stat-title text-xs text-base-content/60">Sessions</div>
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap gap-3">
          <.link
            navigate={~p"/orgs/#{@current_org.id}/study_sets/new"}
            class="btn btn-primary gap-2"
          >
            <.icon name="hero-plus" class="size-5" /> Create Study Set
          </.link>
          <.link
            navigate={~p"/orgs/#{@current_org.id}/study_sets"}
            class="btn btn-ghost gap-2"
          >
            <.icon name="hero-book-open" class="size-5" /> Browse All Sets
          </.link>
        </div>
      </div>
      
    <!-- Quick Actions Grid -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <div class="card bg-base-200 border border-base-300/50 hover:border-primary/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-primary/20 rounded-lg">
                <.icon name="hero-academic-cap" class="size-6 text-primary/80" />
              </div>
              <h3 class="font-semibold text-base-content">Learn Mode</h3>
            </div>
            <p class="text-sm text-base-content/70 mb-4">
              Interactive learning with immediate feedback
            </p>
            <div :if={@my_sets != []} class="card-actions">
              <.link
                navigate={~p"/orgs/#{@current_org.id}/study_sets/#{hd(@my_sets).id}/learn"}
                class="btn btn-sm"
              >
                Start Learning
              </.link>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300/50 hover:border-secondary/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-secondary/20 rounded-lg">
                <.icon name="hero-rectangle-stack" class="size-6 text-secondary/80" />
              </div>
              <h3 class="font-semibold text-base-content">Flashcards</h3>
            </div>
            <p class="text-sm text-base-content/70 mb-4">Classic flip-card study method</p>
            <div :if={@my_sets != []} class="card-actions">
              <.link
                navigate={~p"/orgs/#{@current_org.id}/study_sets/#{hd(@my_sets).id}/flashcards"}
                class="btn btn-sm"
              >
                Review Cards
              </.link>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300/50 hover:border-accent/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-accent/20 rounded-lg">
                <.icon name="hero-pencil-square" class="size-6 text-accent/80" />
              </div>
              <h3 class="font-semibold text-base-content">Test Mode</h3>
            </div>
            <p class="text-sm text-base-content/70 mb-4">Quiz yourself and track progress</p>
            <div :if={@my_sets != []} class="card-actions">
              <.link
                navigate={~p"/orgs/#{@current_org.id}/study_sets/#{hd(@my_sets).id}/test"}
                class="btn btn-sm"
              >
                Take Test
              </.link>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300/50 hover:border-warning/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-warning/20 rounded-lg">
                <.icon name="hero-bolt" class="size-6 text-warning/80" />
              </div>
              <h3 class="font-semibold text-base-content">Duel Mode</h3>
            </div>
            <p class="text-sm text-base-content/70 mb-4">Challenge others in real-time</p>
            <div :if={@my_sets != []} class="card-actions">
              <button
                type="button"
                class="btn btn-sm"
                phx-click="create_duel"
                phx-value-set-id={hd(@my_sets).id}
              >
                Create Duel
              </button>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Main Content Grid -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Study Sets - Takes more space -->
        <div class="lg:col-span-2">
          <div class="card bg-base-200 shadow-sm border border-base-300">
            <div class="card-body">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold flex items-center gap-2">
                  <.icon name="hero-book-open" class="size-5" /> My Study Sets
                </h2>
                <.link navigate={~p"/orgs/#{@current_org.id}/study_sets"} class="btn btn-ghost btn-sm">
                  View All
                </.link>
              </div>

              <div :if={@my_sets == []} class="text-center py-12">
                <div class="p-4 bg-base-200 rounded-full w-16 h-16 mx-auto mb-4 flex items-center justify-center">
                  <.icon name="hero-book-open" class="size-8 text-base-content/40" />
                </div>
                <h3 class="text-lg font-medium mb-2">No study sets yet</h3>
                <p class="text-base-content/60 mb-4">Create your first study set to get started</p>
                <.link navigate={~p"/orgs/#{@current_org.id}/study_sets/new"} class="btn btn-primary">
                  <.icon name="hero-plus" class="mr-2" /> Create Study Set
                </.link>
              </div>

              <div :if={@my_sets != []}>
                <.study_set_card
                  :for={set <- @my_sets}
                  set={set}
                  current_org={@current_org}
                  show_mastery={true}
                />
              </div>
            </div>
          </div>
        </div>
        
    <!-- Sidebar with Activity & Quick Info -->
        <div class="space-y-6">
          <!-- Recent Activity -->
          <div class="card bg-base-100 shadow-sm border border-base-300">
            <div class="card-body">
              <h3 class="text-lg font-semibold flex items-center gap-2 mb-4">
                <.icon name="hero-clock" class="size-5" /> Recent Activity
              </h3>

              <div :if={@recent_sessions == []} class="text-center py-8">
                <div class="p-3 bg-base-200 rounded-full w-12 h-12 mx-auto mb-3 flex items-center justify-center">
                  <.icon name="hero-clock" class="size-6 text-base-content/40" />
                </div>
                <p class="text-sm text-base-content/60">No recent activity</p>
              </div>

              <div :if={@recent_sessions != []} class="space-y-3">
                <div
                  :for={s <- @recent_sessions}
                  class="flex items-center gap-3 p-3 bg-base-200/50 rounded-lg"
                >
                  <div class="p-2 bg-primary/10 rounded-full">
                    <.icon name="hero-academic-cap" class="size-4 text-primary" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium truncate">
                      {(s.study_set && s.study_set.name) || "a set"}
                    </p>
                    <p class="text-xs text-base-content/60">
                      {Atom.to_string(s.mode) |> String.capitalize()} · {Calendar.strftime(
                        s.updated_at,
                        "%b %d"
                      )}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Organization Info -->
          <div class="card bg-base-100 shadow-sm border border-base-300">
            <div class="card-body">
              <h3 class="text-lg font-semibold flex items-center gap-2 mb-4">
                <.icon name="hero-building-office" class="size-5" /> Organization
              </h3>
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <span class="text-sm text-base-content/60">Name</span>
                  <span class="font-medium">{@current_org.name}</span>
                </div>
                <div class="flex items-center justify-between">
                  <span class="text-sm text-base-content/60">Study Sets</span>
                  <span class="font-medium">{length(@my_sets)}</span>
                </div>
              </div>
            </div>
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

  def handle_event("review_struggling", %{"set-id" => set_id}, socket) do
    org_id = socket.assigns.current_org.id

    {:noreply,
     push_navigate(socket, to: ~p"/orgs/#{org_id}/study_sets/#{set_id}/learn?mode=struggling")}
  end

  def handle_event("practice_next", %{"set-id" => set_id}, socket) do
    org_id = socket.assigns.current_org.id

    {:noreply,
     push_navigate(socket, to: ~p"/orgs/#{org_id}/study_sets/#{set_id}/learn?mode=practice")}
  end
end
