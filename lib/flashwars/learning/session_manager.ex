defmodule Flashwars.Learning.SessionManager do
  @moduledoc "Persistence utilities for study sessions."
  alias Flashwars.Learning
  require Ash.Query

  @recent_window :timer.hours(24)

  def save_session(user, study_set_id, mode, state) do
    now = DateTime.utc_now()

    Learning.Session
    |> Ash.Changeset.for_create(
      :upsert,
      %{
        study_set_id: study_set_id,
        mode: mode,
        state: state,
        last_saved_at: now
      },
      actor: user
    )
    |> Ash.create(actor: user)
  end

  def resume_session(user, study_set_id, mode) do
    with {:ok, session} <-
           Learning.Session
           |> Ash.Query.for_read(
             :for_user_set_mode,
             %{
               study_set_id: study_set_id,
               mode: mode
             },
             actor: user
           )
           |> Ash.read(limit: 1, actor: user),
         [session] <- session do
      if recent?(session) do
        {:ok, session.state}
      else
        {:error, :no_session}
      end
    else
      _ -> {:error, :no_session}
    end
  end

  defp recent?(%{updated_at: updated_at}) when not is_nil(updated_at) do
    diff_ms = DateTime.diff(DateTime.utc_now(), updated_at, :millisecond)
    diff_ms < @recent_window
  end

  defp recent?(_), do: false
end
