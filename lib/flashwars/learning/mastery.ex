defmodule Flashwars.Learning.Mastery do
  @moduledoc """
  Computes per-term mastery status for a user within a study set.

  Categories:
  - mastered: accuracy >= mastered_accuracy and attempts >= min_attempts
  - struggling: accuracy <= struggling_accuracy or last answer incorrect
  - unseen: no attempts for the term
  - practicing: attempted but neither mastered nor struggling
  """

  require Ash.Query

  @type summary :: %{
          term_id: String.t(),
          term: String.t(),
          definition: String.t(),
          attempts: non_neg_integer(),
          correct: non_neg_integer(),
          accuracy: float()
        }

  @type result :: %{
          mastered: [summary],
          struggling: [summary],
          practicing: [summary],
          unseen: [summary]
        }

  @defaults [min_attempts: 2, mastered_accuracy: 0.9, struggling_accuracy: 0.5]

  @spec classify(%{id: any}, String.t(), keyword) :: result
  def classify(user, study_set_id, opts \\ []) do
    thresholds = Keyword.merge(@defaults, opts)

    terms =
      Flashwars.Content.Term
      |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, authorize?: false)
      |> Ash.read!(authorize?: false)

    _term_by_id = Map.new(terms, &{&1.id, &1})

    # collect attempt items for this user + set (via attempts -> items)
    attempts =
      Flashwars.Learning.Attempt
      |> Ash.Query.filter(user_id == ^user.id and study_set_id == ^study_set_id)
      |> Ash.read!(authorize?: false)

    attempt_ids = Enum.map(attempts, & &1.id)

    items =
      if attempt_ids == [] do
        []
      else
        Flashwars.Learning.AttemptItem
        |> Ash.Query.filter(attempt_id in ^attempt_ids)
        |> Ash.read!(authorize?: false)
      end

    by_term = Enum.group_by(items, & &1.term_id)

    summaries =
      Enum.map(terms, fn term ->
        stats = stats_for_term(by_term[term.id] || [])
        Map.merge(stats, %{term_id: term.id, term: term.term, definition: term.definition})
      end)

    partition(summaries, thresholds)
  end

  defp stats_for_term([]) do
    %{attempts: 0, correct: 0, accuracy: 0.0, last_correct?: false}
  end

  defp stats_for_term(items) do
    attempts = length(items)
    correct = Enum.count(items, &(&1.correct == true))
    accuracy = if attempts > 0, do: correct / attempts, else: 0.0

    last_correct? =
      items
      |> Enum.sort_by(&(&1.evaluated_at || &1.inserted_at), {:desc, DateTime})
      |> List.first()
      |> case do
        nil -> false
        i -> i.correct == true
      end

    %{attempts: attempts, correct: correct, accuracy: accuracy, last_correct?: last_correct?}
  end

  defp partition(summaries, opts) do
    min_attempts = Keyword.fetch!(opts, :min_attempts)
    mastered_acc = Keyword.fetch!(opts, :mastered_accuracy)
    struggling_acc = Keyword.fetch!(opts, :struggling_accuracy)

    {seen, unseen} = Enum.split_with(summaries, &(&1.attempts > 0))

    mastered =
      Enum.filter(seen, fn s ->
        s.attempts >= min_attempts and (s.accuracy >= mastered_acc or s.last_correct?)
      end)

    struggling =
      Enum.filter(seen, fn s -> s.accuracy <= struggling_acc or s.last_correct? == false end)

    practicing =
      seen
      |> MapSet.new()
      |> MapSet.difference(MapSet.new(mastered))
      |> MapSet.difference(MapSet.new(struggling))
      |> MapSet.to_list()

    %{
      mastered: mastered,
      struggling: struggling,
      practicing: practicing,
      unseen: unseen
    }
  end
end
