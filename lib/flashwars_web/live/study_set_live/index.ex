defmodule FlashwarsWeb.StudySetLive.Index do
  use FlashwarsWeb, :live_view

  import Ash.Query
  alias Flashwars.Content.StudySet

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    org = socket.assigns.current_org

    study_sets =
      StudySet
      |> filter(organization_id == ^org.id)
      |> sort(updated_at: :desc)
      |> Ash.read!(actor: actor, load: [:owner])

    # Add mastery status to study sets
    sets_with_mastery =
      Enum.map(study_sets, fn set ->
        mastery = Flashwars.Learning.Mastery.classify(actor, set.id)
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

    {:ok,
     socket
     |> assign(:page_title, "Study Sets")
     |> assign_new(:current_scope, fn -> %{org_id: org.id} end)
     |> assign(:study_sets, sets_with_mastery)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_user={@current_user}>
      <.header>
        Study Sets
        <:subtitle>All study sets in your organization</:subtitle>
        <:actions>
          <.link navigate={~p"/orgs/#{@current_org.id}/study_sets/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="mr-1" /> New Study Set
          </.link>
        </:actions>
      </.header>
      <div class="">
        <div :if={@study_sets == []} class="text-center py-12">
          <div class="p-4 bg-base-200 rounded-full w-16 h-16 mx-auto mb-4 flex items-center justify-center">
            <.icon name="hero-book-open" class="size-8 text-base-content/40" />
          </div>
          <h3 class="text-lg font-medium mb-2">No study sets yet</h3>
          <p class="text-base-content/60 mb-4">Create your first study set to get started</p>
          <.link navigate={~p"/orgs/#{@current_org.id}/study_sets/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="mr-2" /> Create Study Set
          </.link>
        </div>

        <div :if={@study_sets != []} class="grid divide-y divide-base-200">
          <.study_set_card
            :for={set <- @study_sets}
            set={set}
            current_org={@current_org}
            show_mastery={true}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("create_duel", %{"set-id" => set_id}, socket) do
    actor = socket.assigns.current_user

    case Flashwars.Games.create_game_room(%{type: :duel, study_set_id: set_id, privacy: :private},
           actor: actor
         ) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/games/r/#{room.id}")}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, "Could not create duel: #{inspect(err)}")}
    end
  end
end
