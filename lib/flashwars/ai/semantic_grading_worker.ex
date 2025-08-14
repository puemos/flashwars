defmodule Flashwars.AI.SemanticGradingWorker do
  use Oban.Worker, queue: :ai, max_attempts: 3
  alias Flashwars.Learning

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_item_id" => item_id}}) do
    with {:ok, item} <- Ash.get(Learning.AttemptItem, item_id) do
      {confidence, explanation} = grade(item)
      score = credit(confidence)

      item
      |> Ash.Changeset.for_update(:update, %{
        ai_confidence: confidence,
        ai_explanation: explanation,
        score: score,
        evaluated_at: DateTime.utc_now()
      })
      |> Ash.update()
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp grade(item) do
    # Placeholder heuristic grading: lexical similarity
    expected = String.downcase(item.term.term)
    answer = String.downcase(to_string(item.answer || ""))
    confidence = jaccard(expected, answer)
    explanation = "Heuristic similarity based on token overlap"
    {Float.round(confidence, 2), explanation}
  end

  defp jaccard(a, b) do
    sa = MapSet.new(String.split(a))
    sb = MapSet.new(String.split(b))
    inter = MapSet.size(MapSet.intersection(sa, sb))
    union = MapSet.size(MapSet.union(sa, sb))
    if union == 0, do: 0.0, else: inter / union
  end

  defp credit(conf) when conf >= 0.85, do: 100
  defp credit(conf) when conf >= 0.60, do: 50
  defp credit(_), do: 0
end
