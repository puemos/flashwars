defmodule Flashwars.Learning.Engine do
  @moduledoc """
  Item generation logic for learning/assessment flows.

  Games and other modes should call into this module to generate the
  next item/question instead of baking logic into their layers.
  """

  require Ash.Query
  require Logger

  @telemetry_prefix [:flashwars, :learning]

  @type item :: %{
          kind: String.t(),
          prompt: String.t(),
          choices: [String.t()],
          answer_index: non_neg_integer(),
          term_id: String.t() | nil
        }

  defp maybe_seed(opts) do
    case Keyword.get(opts, :seed) do
      nil -> :ok
      seed when is_integer(seed) -> :rand.seed(:exsplus, {seed, seed, seed})
    end
  end

  @spec generate_item(String.t(), keyword()) :: item
  def generate_item(study_set_id, opts \\ []) when is_binary(study_set_id) do
    maybe_seed(opts)
    prev_term_ids = Keyword.get(opts, :exclude_term_ids, []) |> MapSet.new()

    terms =
      Flashwars.Content.Term
      |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, authorize?: false)
      |> Ash.read!(authorize?: false)

    {prompt, choices, answer_idx, term_id} =
      case terms do
        [] ->
          {"No terms in study set", ["—", "—", "—", "—"], 0, nil}

        [_ | _] ->
          build_mcq_from_terms(terms, prev_term_ids)
      end

    %{
      kind: "multiple_choice",
      prompt: prompt,
      choices: choices,
      answer_index: answer_idx,
      term_id: term_id
    }
  end

  @doc """
  Generate a learn-mode item for a specific user, picking the next due or unseen term.

  Falls back to generic term picking when no CardState exists.
  """
  @spec generate_item_for_user(%{id: any}, String.t(), keyword) :: item
  def generate_item_for_user(user, study_set_id, opts \\ []) do
    maybe_seed(opts)
    exclude = Keyword.get(opts, :exclude_term_ids, []) |> MapSet.new()

    queue = Flashwars.Learning.Scheduler.build_daily_queue(user, study_set_id, 10)

    term =
      case Enum.find(queue, fn cs -> not MapSet.member?(exclude, cs.term_id) end) do
        %{} = cs -> Ash.get!(Flashwars.Content.Term, cs.term_id, authorize?: false)
        nil -> nil
      end

    if is_nil(term) do
      generate_item(study_set_id, opts)
    else
      # Build MCQ using chosen term as target
      terms =
        Flashwars.Content.Term
        |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, authorize?: false)
        |> Ash.read!(authorize?: false)

      correct_def = term.definition
      other_defs = terms |> Enum.reject(&(&1.id == term.id)) |> Enum.map(& &1.definition)

      distractors_from_terms =
        other_defs
        |> Enum.uniq()
        |> Enum.shuffle()
        |> Enum.take(3)

      needed = 3 - length(distractors_from_terms)

      more_distractors =
        if needed > 0 do
          (term.distractors || [])
          |> Enum.reject(&(&1 == correct_def))
          |> Enum.uniq()
          |> Enum.shuffle()
          |> Enum.take(needed)
        else
          []
        end

      options =
        [correct_def | distractors_from_terms ++ more_distractors]
        |> Enum.uniq()
        |> Enum.shuffle()
        |> pad_to_four(correct_def)

      answer_idx = Enum.find_index(options, &(&1 == correct_def)) || 0

      %{
        kind: "multiple_choice",
        prompt: term.term,
        choices: options,
        answer_index: answer_idx,
        term_id: term.id
      }
    end
  end

  @doc """
  Flashcards mode: generate the next card for a user.

  Options:
  - :order – one of :smart | :alphabetical | :position (default :smart)
  - :smart – boolean to enable scheduler based ordering (default true)
  - :exclude_term_ids – list of term ids to skip
  Returns a map with kind: "flashcard", front, back, term_id
  """
  @spec generate_flashcard(%{id: any}, String.t(), keyword) :: map
  def generate_flashcard(user, study_set_id, opts \\ []) do
    maybe_seed(opts)
    start = System.monotonic_time()
    exclude = Keyword.get(opts, :exclude_term_ids, []) |> MapSet.new()
    smart? = Keyword.get(opts, :smart, true)
    order = Keyword.get(opts, :order, :smart)
    order = if order == :smart and not smart?, do: :alphabetical, else: order
    exclude_list = MapSet.to_list(exclude)

    term =
      case order do
        :smart ->
          queue = Flashwars.Learning.Scheduler.build_daily_queue(user, study_set_id, 20)

          case Enum.find(queue, fn
                 %{term_id: tid} -> not MapSet.member?(exclude, tid)
                 %Flashwars.Content.Term{id: id} -> not MapSet.member?(exclude, id)
                 _ -> false
               end) do
            %{term_id: tid} -> Ash.get!(Flashwars.Content.Term, tid, authorize?: false)
            %Flashwars.Content.Term{} = term -> term
            _ -> nil
          end

        :alphabetical ->
          Flashwars.Content.Term
          |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, actor: user)
          |> Ash.Query.filter(id not in ^exclude_list)
          |> Ash.Query.sort(term: :asc)
          |> Ash.Query.limit(1)
          |> Ash.read!(actor: user)
          |> List.first()

        :position ->
          Flashwars.Content.Term
          |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, actor: user)
          |> Ash.Query.filter(id not in ^exclude_list)
          |> Ash.Query.sort(position: :asc)
          |> Ash.Query.limit(1)
          |> Ash.read!(actor: user)
          |> List.first()
      end

    result =
      case term do
        nil ->
          Logger.error("no term for flashcard", study_set_id: study_set_id)

          %{
            kind: "flashcard",
            front: "No terms",
            back: "",
            term_id: nil
          }

        t ->
          %{
            kind: "flashcard",
            front: t.term,
            back: t.definition,
            term_id: t.id
          }
      end

    duration = System.monotonic_time() - start

    :telemetry.execute(@telemetry_prefix ++ [:flashcard], %{duration: duration, count: 1}, %{
      mode: :flashcards,
      user_present: true
    })

    result
  end

  @doc """
  Learn mode: generate a round of items.

  Options:
  - :size – number of items (default 10). Matching consumes multiple terms.
  - :types – list of types: [:multiple_choice, :true_false, :free_text, :matching]
  - :pair_count – for :matching, number of pairs (default 4)
  - :smart – enable scheduler driven selection (default true)
  - :exclude_term_ids – terms to avoid in this round
  """
  @spec generate_learn_round(%{id: any}, String.t(), keyword) :: [map]
  def generate_learn_round(user, study_set_id, opts \\ []) do
    maybe_seed(opts)
    start = System.monotonic_time()
    size = Keyword.get(opts, :size, 10)
    types = Keyword.get(opts, :types, [:multiple_choice, :true_false, :free_text, :matching])
    pair_count = Keyword.get(opts, :pair_count, 4)
    smart? = Keyword.get(opts, :smart, true)
    exclude = Keyword.get(opts, :exclude_term_ids, []) |> MapSet.new()
    exclude_list = MapSet.to_list(exclude)

    queue_states =
      if smart?,
        do: Flashwars.Learning.Scheduler.build_daily_queue(user, study_set_id, size * 4),
        else: []

    all_terms =
      Flashwars.Content.Term
      |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, actor: user)
      |> Ash.Query.filter(id not in ^exclude_list)
      |> Ash.read!(actor: user)
      |> Map.new(&{&1.id, &1})

    candidates =
      Enum.flat_map(queue_states, fn
        %{term_id: tid} ->
          case Map.fetch(all_terms, tid) do
            {:ok, t} -> [t]
            :error -> []
          end

        %Flashwars.Content.Term{} = t ->
          [t]

        _ ->
          []
      end)

    pool =
      (candidates ++ Map.values(all_terms))
      |> Enum.uniq_by(& &1.id)

    {items, _used} =
      build_mixed_items(pool, MapSet.new(), size, types, pair_count, Map.values(all_terms))

    count = length(items)

    cond do
      count == 0 ->
        Logger.error("no items for learn round", study_set_id: study_set_id, requested: size)

      count < size ->
        Logger.warning("undersupplied learn round",
          study_set_id: study_set_id,
          requested: size,
          returned: count
        )

      true ->
        :ok
    end

    duration = System.monotonic_time() - start

    :telemetry.execute(
      @telemetry_prefix ++ [:learn_round],
      %{duration: duration, count: count},
      %{mode: :learn, user_present: true}
    )

    items
  end

  @doc """
  Test mode: generate an N-length test of mixed question types.

  Options:
  - :size – number of items (required)
  - :types – list of allowed types
  - :pair_count – pairs in matching
  - :smart – enable scheduler priority when user present (default true)
  - :exclude_term_ids – terms to avoid
  If `user` is provided and `smart` is true, prioritizes due/unseen via the scheduler.
  """
  @spec generate_test(%{id: any} | nil, String.t(), keyword) :: [map]
  def generate_test(user_or_nil, study_set_id, opts) do
    maybe_seed(opts)
    start = System.monotonic_time()
    size = Keyword.get(opts, :size, 20)
    types = Keyword.get(opts, :types, [:multiple_choice, :true_false, :free_text, :matching])
    pair_count = Keyword.get(opts, :pair_count, 4)
    smart? = Keyword.get(opts, :smart, true)
    exclude = Keyword.get(opts, :exclude_term_ids, []) |> MapSet.new()
    exclude_list = MapSet.to_list(exclude)

    all_terms =
      Flashwars.Content.Term
      |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, authorize?: false)
      |> Ash.Query.filter(id not in ^exclude_list)
      |> Ash.read!(authorize?: false)

    pool =
      case {user_or_nil, smart?} do
        {nil, _} ->
          all_terms

        {user, true} ->
          states = Flashwars.Learning.Scheduler.build_daily_queue(user, study_set_id, size * 4)

          pri =
            Enum.map(states, fn
              %{term_id: tid} -> Enum.find(all_terms, &(&1.id == tid))
              %Flashwars.Content.Term{id: id} -> Enum.find(all_terms, &(&1.id == id))
              _ -> nil
            end)
            |> Enum.reject(&is_nil/1)

          Enum.uniq_by(pri ++ all_terms, & &1.id)

        {_user, false} ->
          all_terms
      end

    {items, _used} = build_mixed_items(pool, MapSet.new(), size, types, pair_count, all_terms)
    count = length(items)

    cond do
      count == 0 ->
        Logger.error("no items for test",
          study_set_id: study_set_id,
          requested: size,
          user?: not is_nil(user_or_nil)
        )

      count < size ->
        Logger.warning("undersupplied test",
          study_set_id: study_set_id,
          requested: size,
          returned: count
        )

      true ->
        :ok
    end

    duration = System.monotonic_time() - start

    :telemetry.execute(@telemetry_prefix ++ [:test], %{duration: duration, count: count}, %{
      mode: :test,
      user_present: not is_nil(user_or_nil)
    })

    items
  end

  defp pad_to_four(options, correct) do
    opts =
      case length(options) do
        4 ->
          options

        n when n < 4 ->
          pads = 1..(4 - n) |> Enum.map(fn i -> "Not #{correct} (#{i})" end)
          options ++ pads

        _ ->
          Enum.take(options, 4)
      end

    # ensure shuffle mixes in pads
    Enum.shuffle(opts)
  end

  defp build_mcq_from_terms(terms, prev_term_ids) do
    all_terms = Enum.shuffle(terms)

    candidate_terms =
      all_terms
      |> Enum.reject(&MapSet.member?(prev_term_ids, &1.id))

    pick_from = if candidate_terms == [], do: all_terms, else: candidate_terms
    target = Enum.random(pick_from)

    correct_def = target.definition

    other_defs =
      terms
      |> Enum.reject(&(&1.id == target.id))
      |> Enum.map(& &1.definition)

    distractors_from_terms =
      other_defs
      |> Enum.uniq()
      |> Enum.shuffle()
      |> Enum.take(3)

    needed = 3 - length(distractors_from_terms)

    more_distractors =
      if needed > 0 do
        (target.distractors || [])
        |> Enum.reject(&(&1 == correct_def))
        |> Enum.uniq()
        |> Enum.shuffle()
        |> Enum.take(needed)
      else
        []
      end

    final_distractors =
      (distractors_from_terms ++ more_distractors)
      |> Enum.uniq()
      |> case do
        list when length(list) >= 3 ->
          Enum.take(list, 3)

        list ->
          pad_needed = 3 - length(list)
          pads = 1..pad_needed |> Enum.map(fn i -> "Not #{correct_def} (#{i})" end)
          list ++ pads
      end

    options = [correct_def | final_distractors] |> Enum.shuffle()
    answer_idx = Enum.find_index(options, &(&1 == correct_def)) || 0

    {target.term, options, answer_idx, target.id}
  end

  # Internal: build a batch of mixed-type items without reusing terms (except matching groups).
  defp build_mixed_items(pool, used_ids, remaining, types, pair_count, all_terms) do
    if remaining <= 0 or pool == [] do
      {[], used_ids}
    else
      {next_item, newly_used} =
        case pick_type(types) do
          :matching ->
            # Need multiple unused terms; if insufficient, fall back to MCQ
            available = Enum.reject(pool, &MapSet.member?(used_ids, &1.id))
            group = Enum.take(available, pair_count)

            if length(group) < max(3, div(pair_count, 2)) do
              build_mcq_item(pool, used_ids, all_terms)
            else
              item = build_matching(group)
              used = Enum.reduce(group, used_ids, fn t, acc -> MapSet.put(acc, t.id) end)
              {item, used}
            end

          :true_false ->
            build_true_false_item(pool, used_ids, all_terms)

          :free_text ->
            build_free_text_item(pool, used_ids)

          _ ->
            build_mcq_item(pool, used_ids, all_terms)
        end

      {rest, final_used} =
        build_mixed_items(pool, newly_used, remaining - 1, types, pair_count, all_terms)

      {[next_item | rest], final_used}
    end
  end

  defp pick_type(types) when is_list(types) and types != [] do
    Enum.random(types)
  end

  defp build_mcq_item(pool, used_ids, all_terms) do
    candidate = Enum.find(pool, &(!MapSet.member?(used_ids, &1.id))) || List.first(pool)

    other_defs =
      all_terms
      |> Enum.reject(&(&1.id == candidate.id))
      |> Enum.map(& &1.definition)

    distractors_from_terms =
      other_defs
      |> Enum.uniq()
      |> Enum.shuffle()
      |> Enum.take(3)

    needed = 3 - length(distractors_from_terms)

    more =
      if needed > 0 do
        (candidate.distractors || [])
        |> Enum.reject(&(&1 == candidate.definition))
        |> Enum.uniq()
        |> Enum.shuffle()
        |> Enum.take(needed)
      else
        []
      end

    options =
      [candidate.definition | distractors_from_terms ++ more] |> Enum.uniq() |> Enum.shuffle()

    options = pad_to_four(options, candidate.definition)
    answer_idx = Enum.find_index(options, &(&1 == candidate.definition)) || 0

    item = %{
      kind: "multiple_choice",
      prompt: candidate.term,
      choices: options,
      answer_index: answer_idx,
      term_id: candidate.id
    }

    {item, MapSet.put(used_ids, candidate.id)}
  end

  defp build_true_false_item(pool, used_ids, all_terms) do
    candidate = Enum.find(pool, &(!MapSet.member?(used_ids, &1.id))) || List.first(pool)

    # 50/50 chance to present correct or incorrect pairing
    incorrect_defs =
      all_terms
      |> Enum.reject(&(&1.id == candidate.id))
      |> Enum.map(& &1.definition)

    incorrect =
      Enum.random(incorrect_defs ++ (candidate.distractors || []) ++ [candidate.definition])

    show_correct = Enum.random([true, false])
    definition = if show_correct, do: candidate.definition, else: incorrect
    is_correct = definition == candidate.definition

    choices = ["True", "False"]
    answer_index = if is_correct, do: 0, else: 1

    item = %{
      kind: "true_false",
      prompt: candidate.term <> " — matches definition?",
      definition: definition,
      choices: choices,
      answer_index: answer_index,
      term_id: candidate.id
    }

    {item, MapSet.put(used_ids, candidate.id)}
  end

  defp build_free_text_item(pool, used_ids) do
    candidate = Enum.find(pool, &(!MapSet.member?(used_ids, &1.id))) || List.first(pool)

    item = %{
      kind: "free_text",
      prompt: candidate.term,
      answer_text: candidate.definition,
      term_id: candidate.id
    }

    {item, MapSet.put(used_ids, candidate.id)}
  end

  defp build_matching(group) do
    left = Enum.map(group, &%{term_id: &1.id, term: &1.term})
    rights = group |> Enum.map(&%{definition: &1.definition, term_id: &1.id}) |> Enum.shuffle()

    # answer is index mapping: left[i] -> position in rights
    answer =
      left
      |> Enum.with_index()
      |> Enum.map(fn {%{term_id: tid}, i} ->
        j = Enum.find_index(rights, &(&1.term_id == tid)) || i
        %{left_index: i, right_index: j}
      end)

    %{
      kind: "matching",
      left: left,
      right: Enum.map(rights, & &1.definition),
      answer_pairs: answer
    }
  end
end
