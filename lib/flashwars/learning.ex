defmodule Flashwars.Learning do
  use Ash.Domain, otp_app: :flashwars
  require Ash.Query

  resources do
    resource Flashwars.Learning.Attempt do
      define :create_attempt, action: :create
    end

    resource Flashwars.Learning.AttemptItem do
      define :create_attempt_item, action: :create
    end

    resource Flashwars.Learning.LeaderboardEntry do
      define :upsert_leaderboard, action: :upsert
    end

    resource Flashwars.Learning.Session do
      define :list_sessions, action: :read
      define :upsert_session, action: :upsert
      define :list_sessions_for_user_set_mode, action: :for_user_set_mode
    end

    resource Flashwars.Learning.TermState do
      define :upsert_term_state, action: :upsert
      define :list_term_states, action: :read
      define :list_term_states_for_user_set, action: :for_user_set
    end
  end

  @doc "Convenience wrapper to classify mastery per study set for a user."
  @spec mastery_for_set(%{id: any}, String.t(), keyword) :: map
  def mastery_for_set(user, study_set_id, opts \\ []) do
    Flashwars.Learning.Mastery.classify(user, study_set_id, opts)
  end

  @doc """
  Review a term, updating TermState and logging an AttemptItem with scheduler metadata.

  Options:
  - :attempt_id (optional) – attempts are required for items; if absent, a new one is created
  - :rt_ms, :confidence, :queue_type, :app_version, :device, :answer, :score
  - :evaluated_at (default now)
  """
  @spec review(%{id: any}, String.t(), atom, keyword) :: {:ok, map} | {:error, term}
  def review(user, term_id, grade, opts \\ []) when grade in [:again, :hard, :good, :easy] do
    now = DateTime.utc_now()

    # resolve term + set
    term = Flashwars.Content.get_term_by_id!(term_id, authorize?: false)
    set_id = term.study_set_id

    # load or init term state
    cs_existing =
      __MODULE__.list_term_states!(
        authorize?: false,
        query: [filter: [user_id: user.id, term_id: term_id], limit: 1]
      )
      |> List.first()

    cs_map =
      case cs_existing do
        nil ->
          %{
            stability_days: 0.3,
            difficulty: 6.0,
            prev_interval_days: 0.0,
            streak: 0,
            lapses: 0,
            relearn_stage: 0,
            t_last: now,
            next_due_at: now
          }

        cs ->
          Map.from_struct(cs)
      end

    rt_ms = Keyword.get(opts, :rt_ms)

    with {:ok, %{update: update, log: log}} <-
           Flashwars.Learning.Scheduler.schedule_after_review(cs_map, grade, rt_ms, now) do
      # upsert term state
      _cs =
        __MODULE__.upsert_term_state!(
          Map.merge(update, %{term_id: term_id, study_set_id: set_id}),
          actor: user
        )

      # ensure attempt
      attempt_id =
        case Keyword.get(opts, :attempt_id) do
          nil ->
            attempt =
              __MODULE__.create_attempt!(
                %{mode: :learn, study_set_id: set_id, started_at: now},
                actor: user
              )

            attempt.id

          id ->
            id
        end

      params = %{
        attempt_id: attempt_id,
        term_id: term_id,
        correct: grade != :again,
        score: Keyword.get(opts, :score, if(grade == :again, do: 0, else: 10)),
        answer: Keyword.get(opts, :answer),
        evaluated_at: Keyword.get(opts, :evaluated_at, now),
        grade: grade,
        response_time_ms: rt_ms,
        confidence: Keyword.get(opts, :confidence),
        prev_interval_days: log.prev_interval_days,
        next_interval_days: log.next_interval_days,
        s_before: log.s_before,
        s_after: log.s_after,
        d_before: log.d_before,
        d_after: log.d_after,
        queue_type: Keyword.get(opts, :queue_type, :review),
        app_version: Keyword.get(opts, :app_version),
        device: Keyword.get(opts, :device)
      }

      item = __MODULE__.create_attempt_item!(params, actor: user)

      {:ok, %{card_state: update, item: item}}
    end
  end
end
