defmodule Flashwars.AI.DistractorGenerationWorker do
  use Oban.Worker, queue: :ai, max_attempts: 3
  alias Flashwars.Content

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"study_set_id" => study_set_id}}) do
    with {:ok, _} <- Content.get_study_set(study_set_id),
         {:ok, terms} <- Content.list_terms(study_set_id) do
      other_terms = Enum.map(terms, & &1.term)

      _updates =
        Enum.map(terms, fn t ->
          distractors = generate_distractors(t.term, t.definition, other_terms)
          {:ok, _} = Content.update_term(t, %{distractors: distractors})
          :ok
        end)

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_distractors(term, _definition, other_terms) do
    candidates =
      other_terms
      |> Enum.reject(&(&1 == term))
      |> Enum.take_random(4)

    # Placeholder heuristic; swap with Req-powered API call when wired
    candidates
  end
end
