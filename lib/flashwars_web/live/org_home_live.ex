defmodule FlashwarsWeb.OrgHomeLive do
  use FlashwarsWeb, :live_view

  alias Flashwars.Content
  alias Flashwars.Learning
  alias Flashwars.Learning.Mastery
  alias Flashwars.Games
  require Ash.Query

  on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
  on_mount {FlashwarsWeb.OnMount.CurrentOrg, :require_member}

  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    org = socket.assigns.current_org

    my_sets =
      Content.list_study_sets_for_org!(org.id,
        actor: actor,
        query: [filter: [owner_id: actor.id], limit: 6]
      )

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

    # Recent activity from learning attempts (learn, test, flashcards)
    recent_attempts =
      Learning.list_attempts!(
        actor: actor,
        query: [
          filter: [user_id: actor.id, organization_id: org.id],
          sort: [updated_at: :desc],
          limit: 6
        ],
        load: [:study_set, :items]
      )
      |> Enum.map(fn a ->
        items_count = length(a.items || [])
        correct_count = Enum.count(a.items || [], &(&1.correct))
        acc_pct = if items_count > 0, do: round(correct_count * 100 / items_count), else: 0
        details =
          case a.mode do
            :learn -> "Rounds: " <> Integer.to_string(rounds_from_items(items_count, 10))
            :flashcards -> "Rounds: " <> Integer.to_string(rounds_from_items(items_count, 10))
            :test -> "Questions: " <> Integer.to_string(items_count)
            _ -> nil
          end

        href =
          case a.mode do
            :learn -> ~p"/orgs/#{org.id}/study_sets/#{a.study_set_id}/learn"
            :flashcards -> ~p"/orgs/#{org.id}/study_sets/#{a.study_set_id}/flashcards"
            :test -> ~p"/orgs/#{org.id}/study_sets/#{a.study_set_id}/test"
            _ -> "#"
          end

        %{
          type: :attempt,
          id: a.id,
          mode: a.mode,
          updated_at: a.updated_at || a.inserted_at,
          study_set: a.study_set,
          details: details,
          href: href,
          total: items_count,
          accuracy: acc_pct
        }
      end)

    # Include recent duel activity based on latest submissions
    recent_duels =
      Games.list_submissions!(
        actor: actor,
        query: [
          filter: [user_id: actor.id, organization_id: org.id],
          sort: [inserted_at: :desc],
          limit: 30
        ],
        load: [:game_room]
      )
      |> Enum.group_by(& &1.game_room_id)
      |> Enum.map(fn {_rid, subs} ->
        s = List.first(subs)
        room_loaded =
          case s.game_room do
            nil -> nil
            r -> Ash.load!(r, [:study_set, :rounds], actor: actor)
          end

        set = room_loaded && room_loaded.study_set
        rounds_count = room_loaded && length(room_loaded.rounds || [])
        href = if room_loaded, do: ~p"/games/r/#{room_loaded.id}", else: "#"
        %{
          type: :game_room,
          id: room_loaded && room_loaded.id,
          mode: :game,
          updated_at: s.inserted_at,
          study_set: set,
          details: rounds_count && ("Rounds: " <> Integer.to_string(rounds_count)),
          href: href,
          rounds: rounds_count
        }
      end)

    # Merge and keep the 6 most recent across all modes
    recent_merged =
      (recent_attempts ++ recent_duels)
      |> Enum.sort_by(
        fn s ->
          case s.updated_at do
            %DateTime{} = dt -> DateTime.to_unix(dt, :second)
            _ -> 0
          end
        end,
        :desc
      )
      |> Enum.take(6)

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign_new(:current_scope, fn -> %{org_id: org.id} end)
     |> assign(:my_sets, sets_with_mastery)
     |> assign(:recent_sessions, recent_merged)
     |> assign(:recap_open?, false)
     |> assign(:recap_kind, nil)
     |> assign(:recap_title, nil)
     |> assign(:recap_meta, %{})
     |> assign(:recap_items, [])}
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
            <div class="stats bg-base-300 shadow-sm border border-base-100/30">
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
        <div class="card bg-base-200 border-3 border-base-300/50 hover:border-blue-200/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-blue-200/20 rounded-lg">
                <.icon name="hero-academic-cap" class="size-6 text-blue-200/80" />
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

        <div class="card bg-base-200 border-3 border-base-300/50 hover:border-fuchsia-200/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-fuchsia-200/20 rounded-lg">
                <.icon name="hero-rectangle-stack" class="size-6 text-fuchsia-200/80" />
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

        <div class="card bg-base-200 border-3 border-base-300/50 hover:border-emerald-200/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-emerald-200/20 rounded-lg">
                <.icon name="hero-pencil-square" class="size-6 text-emerald-200/80" />
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

        <div class="card bg-base-200 border-3 border-base-300/50 hover:border-amber-200/30 transition-colors">
          <div class="card-body p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="p-2 bg-amber-200/20 rounded-lg">
                <.icon name="hero-bolt" class="size-6 text-amber-200/80" />
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
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 divide-x divide-base-200">
        <!-- Study Sets - Takes more space -->
        <div class="lg:col-span-2">
          <div class="px-2">
            <div class="">
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

              <div :if={@my_sets != []} class="divide-y divide-base-200">
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
          <div class="">
            <div class="">
              <h3 class="text-lg font-semibold flex items-center gap-2 mb-4">
                <.icon name="hero-clock" class="size-5" /> Recent Activity
              </h3>

              <div :if={@recent_sessions == []} class="text-center py-8">
                <div class="p-3 bg-base-200 rounded-full w-12 h-12 mx-auto mb-3 flex items-center justify-center">
                  <.icon name="hero-clock" class="size-6 text-base-content/40" />
                </div>
                <p class="text-sm text-base-content/60">No recent activity</p>
              </div>

              <div :if={@recent_sessions != []} class="space-y-2">
                <div
                  :for={s <- @recent_sessions}
                  class="group flex items-center gap-3 p-3 rounded-lg border border-base-300/60 hover:bg-base-200/70 transition-colors"
                >
                  <!-- Leading icon by mode -->
                  <div class="p-2 rounded-lg bg-base-200/70">
                    <.icon name={mode_icon(s.mode)} class="size-5 text-base-content/70" />
                  </div>
                  
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2">
                      <button
                        class="text-sm font-medium truncate hover:underline text-left"
                        phx-click="show_recap"
                        phx-value-kind={s[:type]}
                        phx-value-id={s[:id]}
                      >
                        {(s.study_set && s.study_set.name) || "a set"}
                      </button>
                      <span class={mode_badge_class(s.mode)}>{String.capitalize(Atom.to_string(s.mode))}</span>
                    </div>
                    <div class="text-xs text-base-content/60 mt-0.5 flex items-center gap-2">
                      <span>{Calendar.strftime(s.updated_at, "%b %d")}</span>
                      <span :if={s[:details]}>• {s.details}</span>
                      <span :if={s[:accuracy]} class="ml-1">• Accuracy {s.accuracy}%</span>
                      <span :if={s[:rounds]} class="ml-1">• Rounds {s.rounds}</span>
                    </div>
                  </div>

                  <.link navigate={s.href} class="btn btn-ghost btn-sm opacity-0 group-hover:opacity-100 transition-opacity">Open</.link>
                </div>
              </div>
          </div>
        </div>
      
      <div
        :if={@recap_open?}
        id="activity-recap"
        class="fixed inset-0 z-50"
        phx-hook="OverlayDismiss"
        data-push-event="close_recap"
        data-on-escape="true"
        role="dialog"
        aria-modal="true"
        aria-labelledby="activity-recap-title"
      >
        <div
          id="activity-recap-scrim"
          class="absolute inset-0 bg-base-300/60 backdrop-blur-sm"
          phx-hook="OverlayDismiss"
          data-push-event="close_recap"
        ></div>
        <div class="relative z-10 w-full max-w-3xl mx-auto p-4 md:pt-24">
          <div class="card bg-base-100 shadow-2xl border border-base-300/50 md:rounded-2xl">
            <!-- Header -->
            <div class="relative">
              <div class="h-16 md:h-20 bg-base-200/80 rounded-t-2xl"></div>
              <div class="absolute inset-0 flex items-center justify-between px-6">
                <div class="flex items-center gap-3">
                  <.icon name="hero-trophy" class="size-7 md:size-8 text-yellow-400" />
                  <div>
                    <div id="activity-recap-title" class="font-bold text-lg md:text-xl">{@recap_title}</div>
                    <div class="text-xs opacity-70">{@recap_meta[:subtitle]}</div>
                  </div>
                </div>
                <button class="btn btn-ghost" phx-click="close_recap" aria-label="Close recap">✕</button>
              </div>
            </div>

            <div class="card-body">
              <!-- Summary chips + accuracy progress -->
              <div :if={@recap_meta[:summary]} class="space-y-3">
                <div class="flex flex-wrap gap-2">
                  <span class="badge badge-ghost"><.icon name="hero-queue-list" class="size-4" /><span class="ml-1">Total {@recap_meta[:summary][:total]}</span></span>
                  <span class="badge badge-success"><.icon name="hero-check" class="size-4" /><span class="ml-1">Correct {@recap_meta[:summary][:correct]}</span></span>
                  <span class="badge badge-info"><.icon name="hero-sparkles" class="size-4" /><span class="ml-1">Accuracy {@recap_meta[:summary][:accuracy]}%</span></span>
                </div>
                <div>
                  <div class="flex items-center justify-between text-sm opacity-70 mb-1">
                    <div>Accuracy</div>
                    <div class="tabular-nums">{@recap_meta[:summary][:accuracy]}%</div>
                  </div>
                  <.progress pct={@recap_meta[:summary][:accuracy] || 0.0} />
                </div>
              </div>

              <!-- Actions -->
              <div class="mt-3 flex flex-wrap gap-2">
                <.link :if={@recap_meta[:open_href]} navigate={@recap_meta[:open_href]} class="btn btn-primary">Open</.link>
                <button
                  :if={@recap_meta[:study_set_id]}
                  phx-click="review_struggling"
                  phx-value-set-id={@recap_meta[:study_set_id]}
                  class="btn btn-outline"
                >
                  Review Struggling
                </button>
                <button
                  :if={@recap_meta[:study_set_id]}
                  phx-click="practice_next"
                  phx-value-set-id={@recap_meta[:study_set_id]}
                  class="btn btn-ghost"
                >
                  Practice Next
                </button>
              </div>

              <!-- Details list -->
              <details class="mt-4" {if length(@recap_items) <= 10, do: [open: true], else: []}>
                <summary class="cursor-pointer text-sm opacity-80 list-none flex items-center gap-2">
                  <.icon name="hero-list-bullet" class="size-4" />
                  <span>Recent items ({length(@recap_items)})</span>
                </summary>
                <ul class="mt-2 max-h-[50vh] overflow-y-auto divide-y divide-base-300 rounded-lg border border-base-300/60">
                  <li :for={{row, idx} <- Enum.with_index(@recap_items, 1)} class="p-3 flex items-center gap-3">
                    <!-- Status icon -->
                    <div class={"shrink-0 rounded-full p-1 " <> (if row[:correct] == true, do: "bg-success/20", else: (if row[:correct] == false, do: "bg-error/20", else: "bg-base-200"))}>
                      <.icon name={if row[:correct] == true, do: "hero-check", else: (if row[:correct] == false, do: "hero-x-mark", else: "hero-question-mark-circle") } class={"size-4 "<> if(row[:correct] == true, do: "text-success", else: (if row[:correct] == false, do: "text-error", else: "text-base-content/60"))} />
                    </div>
                    
                    <!-- Texts -->
                    <div class="min-w-0 flex-1">
                      <div class="font-medium truncate">{row[:label] || row[:name] || row[:term] || row[:user]}</div>
                      <div :if={row[:definition]} class="text-xs opacity-70 truncate">{row[:definition]}</div>
                    </div>

                    <!-- Tags / score -->
                    <div class="flex items-center gap-2">
                      <span :if={row[:grade]} class={grade_badge_class(row[:grade])}>{row[:grade] |> to_string() |> String.capitalize()}</span>
                      <span :if={row[:score]} class="badge badge-ghost">Score {row[:score]}</span>
                    </div>
                  </li>
                </ul>
              </details>
            </div>
          </div>
        </div>
      </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ========================================
  # UI helpers
  # ========================================

  defp mode_icon(:learn), do: "hero-academic-cap"
  defp mode_icon(:flashcards), do: "hero-rectangle-stack"
  defp mode_icon(:test), do: "hero-pencil-square"
  defp mode_icon(:game), do: "hero-bolt"
  defp mode_icon(_), do: "hero-clock"

  defp mode_badge_class(:learn), do: "badge badge-info badge-sm"
  defp mode_badge_class(:flashcards), do: "badge badge-primary badge-sm"
  defp mode_badge_class(:test), do: "badge badge-warning badge-sm"
  defp mode_badge_class(:game), do: "badge badge-accent badge-sm"
  defp mode_badge_class(_), do: "badge badge-ghost badge-sm"

  defp grade_badge_class(:again), do: "badge badge-error"
  defp grade_badge_class(:hard), do: "badge badge-warning"
  defp grade_badge_class(:good), do: "badge badge-success"
  defp grade_badge_class(:easy), do: "badge badge-success"
  defp grade_badge_class(_), do: "badge badge-ghost"

  defp rounds_from_items(count, chunk) when is_integer(count) and is_integer(chunk) and chunk > 0 do
    if count <= 0, do: 0, else: div(count + chunk - 1, chunk)
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

  def handle_event("show_recap", %{"kind" => "attempt", "id" => attempt_id}, socket) do
    actor = socket.assigns.current_user

    attempt =
      Flashwars.Learning.Attempt
      |> Ash.get!(attempt_id, actor: actor)
      |> Ash.load!([:study_set, items: [:term]], actor: actor)

    total = length(attempt.items || [])
    correct = Enum.count(attempt.items || [], &(&1.correct))
    acc = if total == 0, do: 0, else: Float.round(correct * 100.0 / total, 1)

    rows =
      (attempt.items || [])
      |> Enum.sort_by(&(&1.evaluated_at || &1.inserted_at), :desc)
      |> Enum.take(100)
      |> Enum.map(fn it ->
        {term_text, definition} =
          case it.term do
            %Flashwars.Content.Term{term: t, definition: d} -> {t, d}
            _ -> {nil, nil}
          end

        %{label: term_text || "—", definition: definition, correct: it.correct, score: it.score, grade: it.grade, answer: it.answer}
      end)

    title =
      case attempt.mode do
        :learn -> "Learn Recap: #{attempt.study_set && attempt.study_set.name}"
        :flashcards -> "Flashcards Recap: #{attempt.study_set && attempt.study_set.name}"
        :test -> "Test Recap: #{attempt.study_set && attempt.study_set.name}"
        _ -> "Activity Recap"
      end

    org_id = socket.assigns.current_org.id

    open_href =
      case attempt.mode do
        :learn -> ~p"/orgs/#{org_id}/study_sets/#{attempt.study_set_id}/learn"
        :flashcards -> ~p"/orgs/#{org_id}/study_sets/#{attempt.study_set_id}/flashcards"
        :test -> ~p"/orgs/#{org_id}/study_sets/#{attempt.study_set_id}/test"
        _ -> nil
      end

    meta = %{
      subtitle: Calendar.strftime((attempt.updated_at || attempt.inserted_at), "%b %d, %Y"),
      summary: %{total: total, correct: correct, accuracy: acc},
      open_href: open_href,
      study_set_id: attempt.study_set_id
    }

    {:noreply,
     socket
     |> assign(:recap_open?, true)
     |> assign(:recap_kind, :attempt)
     |> assign(:recap_title, title)
     |> assign(:recap_meta, meta)
     |> assign(:recap_items, rows)}
  end

  def handle_event("show_recap", %{"kind" => "game_room", "id" => room_id}, socket) do
    actor = socket.assigns.current_user

    room =
      Flashwars.Games.GameRoom
      |> Ash.get!(room_id, actor: actor)
      |> Ash.load!([:study_set, :rounds], actor: actor)

    scoreboard = Flashwars.Games.Scoreboard.final_for_room(room.id)

    rows =
      scoreboard
      |> Enum.map(fn e -> %{name: e.name, score: e.score, correct: nil, result: "score"} end)

    title = "Game Recap: #{room.study_set && room.study_set.name}"
    meta = %{
      subtitle: Calendar.strftime((room.updated_at || room.inserted_at), "%b %d, %Y"),
      summary: %{total: length(room.rounds || []), correct: "-", accuracy: "-"},
      open_href: ~p"/games/r/#{room.id}",
      study_set_id: room.study_set_id
    }

    {:noreply,
     socket
     |> assign(:recap_open?, true)
     |> assign(:recap_kind, :game)
     |> assign(:recap_title, title)
     |> assign(:recap_meta, meta)
     |> assign(:recap_items, rows)}
  end

  def handle_event("close_recap", _params, socket) do
    {:noreply,
     socket
     |> assign(:recap_open?, false)
     |> assign(:recap_kind, nil)
     |> assign(:recap_title, nil)
     |> assign(:recap_meta, %{})
     |> assign(:recap_items, [])}
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
