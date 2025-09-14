defmodule Flashwars.Learning.Engine do
  @moduledoc """
  Item generation logic for learning/assessment flows.

  This module provides functions for generating various types of learning and assessment items
  for study sets. It handles multiple question types including:

  - Multiple choice questions
  - True/false questions
  - Free text responses
  - Matching exercises

  The generated items are used by games and other learning modes. All item generation should
  go through this module rather than implementing generation logic directly in game layers.

  Key features:
  - Smart scheduling based on user learning progress
  - Configurable difficulty and question types
  - Seeded random generation for reproducible sequences
  - Telemetry for monitoring item generation performance
  """

  require Ash.Query
  require Logger

  alias Flashwars.Content
  alias Flashwars.Content.Term
  alias Flashwars.Learning.Scheduler

  @telemetry_prefix [:flashwars, :learning]
  @default_matching_pairs 4
  @default_learn_size 10
  @default_test_size 20
  @default_queue_multiplier 4

  @type user :: %{id: any()}
  @type study_set_id :: String.t()
  @type term_id :: String.t()

  @type item :: %{
          kind: String.t(),
          prompt: String.t(),
          choices: [String.t()],
          answer_index: non_neg_integer(),
          term_id: term_id() | nil
        }

  @type flashcard :: %{
          kind: String.t(),
          front: String.t(),
          back: String.t(),
          term_id: term_id() | nil
        }

  @type generation_opts :: [
          seed: integer() | nil,
          exclude_term_ids: [term_id()],
          size: pos_integer(),
          types: [atom()],
          pair_count: pos_integer(),
          smart: boolean(),
          order: :smart | :alphabetical | :position
        ]

  # Public API
  @doc """
  Generate a single game item based on allowed types.

  Currently supports:
  - "multiple_choice"
  - "true_false"

  Unknown types are ignored; falls back to multiple choice.
  """
  @spec generate_game_item(study_set_id(), keyword()) :: map()
  def generate_game_item(study_set_id, opts \\ []) when is_binary(study_set_id) do
    with_seeded_random(opts, fn ->
      # normalize allowed types to strings
      types =
        opts
        |> Keyword.get(:types, ["multiple_choice"])
        |> Enum.map(fn t ->
          cond do
            is_atom(t) -> Atom.to_string(t)
            is_binary(t) -> t
            true -> "multiple_choice"
          end
        end)

      # default to MCQ if none provided
      allowed = if types == [], do: ["multiple_choice"], else: types

      used_ids =
        opts
        |> Keyword.get(:exclude_term_ids, [])
        |> MapSet.new()

      terms = fetch_study_set_terms(study_set_id)

      # pick a supported type
      pick =
        cond do
          Enum.member?(allowed, "true_false") and Enum.random([true, false]) -> "true_false"
          true -> "multiple_choice"
        end

      case pick do
        "true_false" ->
          {item, _} = build_true_false_item(terms, used_ids)
          item

        _ ->
          {item, _} = build_multiple_choice_item_from_pool(terms, used_ids)
          item
      end
    end)
  end

  @doc """
  Generates a single multiple choice question from a study set.

  ## Parameters
  - `study_set_id` - ID of the study set to generate from
  - `opts` - Keyword list of options

  ## Options
  - `:exclude_term_ids` - List of term IDs to exclude
  - `:seed` - Integer seed for random generation

  ## Returns
  Map with:
  - `:kind` - "multiple_choice"
  - `:prompt` - Question text
  - `:choices` - List of 4 possible answers
  - `:answer_index` - Index of correct answer (0-3)
  - `:term_id` - ID of source term
  """
  @spec generate_item(study_set_id(), generation_opts()) :: item()
  def generate_item(study_set_id, opts \\ []) when is_binary(study_set_id) do
    with_seeded_random(opts, fn ->
      exclude_ids = get_exclude_set(opts)
      terms = fetch_study_set_terms(study_set_id)

      build_multiple_choice_item(terms, exclude_ids)
    end)
  end

  @doc """
  Generate a learn-mode item for a specific user, picking the next due or unseen term.

  Uses the spaced repetition scheduler to select terms that are due for review or have not yet
  been seen by the user. Generates a multiple choice question using that term.

  ## Parameters
  - `user` - User map with :id field
  - `study_set_id` - ID of study set to generate from
  - `opts` - Keyword list of options (see `generate_item/2`)

  Falls back to generic term picking via `generate_item/2` when no TermState exists for the user.
  """
  @spec generate_item_for_user(user(), study_set_id(), generation_opts()) :: item()
  def generate_item_for_user(user, study_set_id, opts \\ []) do
    with_seeded_random(opts, fn ->
      exclude_ids = get_exclude_set(opts)

      case select_scheduled_term(user, study_set_id, exclude_ids) do
        {:ok, term} ->
          terms = fetch_study_set_terms(study_set_id)
          build_targeted_mcq(term, terms)

        :no_term_available ->
          generate_item(study_set_id, opts)
      end
    end)
  end

  @doc """
  Flashcards mode: generate the next card for a user.

  Generates a flashcard item using term/definition pairs. Can use different ordering strategies
  including spaced repetition scheduling.

  ## Parameters
  - `user` - User map with :id field
  - `study_set_id` - ID of study set
  - `opts` - Keyword list of options

  ## Options
  - `:order` - One of:
    - `:smart` - Use spaced repetition scheduler (default)
    - `:alphabetical` - Sort by term text
    - `:position` - Use original term order
  - `:smart` - Boolean to enable scheduler based ordering (default true)
  - `:exclude_term_ids` - List of term IDs to skip

  ## Returns
  Map with:
  - `:kind` - "flashcard"
  - `:front` - Term text
  - `:back` - Definition text
  - `:term_id` - Source term ID
  """
  @spec generate_flashcard(user(), study_set_id(), generation_opts()) :: flashcard()
  def generate_flashcard(user, study_set_id, opts \\ []) do
    start_time = System.monotonic_time()

    result =
      with_seeded_random(opts, fn ->
        exclude_ids = get_exclude_set(opts)
        order = determine_flashcard_order(opts)

        case select_flashcard_term(user, study_set_id, exclude_ids, order) do
          {:ok, term} ->
            %{
              kind: "flashcard",
              front: term.term,
              back: term.definition,
              term_id: term.id
            }

          :no_term_available ->
            Logger.error("No term available for flashcard", study_set_id: study_set_id)

            %{
              kind: "flashcard",
              front: "No terms",
              back: "",
              term_id: nil
            }
        end
      end)

    emit_telemetry(:flashcard, start_time, 1, %{mode: :flashcards, user_present: true})
    result
  end

  @doc """
  Learn mode: generate a round of items.

  Generates a sequence of mixed question types for a learning session. Can use spaced
  repetition scheduling to prioritize terms that are due for review.

  ## Parameters
  - `user` - User map with :id field
  - `study_set_id` - ID of study set
  - `opts` - Keyword list of options

  ## Options
  - `:size` - Number of items (default 10). Note: matching consumes multiple terms
  - `:types` - List of allowed types:
    - `:multiple_choice` - Multiple choice questions
    - `:true_false` - True/false questions
    - `:free_text` - Free text response
    - `:matching` - Term/definition matching groups
  - `:pair_count` - For :matching type, number of pairs to match (default 4)
  - `:smart` - Enable scheduler driven selection (default true)
  - `:exclude_term_ids` - Terms to avoid in this round
  """
  @spec generate_learn_round(user(), study_set_id(), generation_opts()) :: [map()]
  def generate_learn_round(user, study_set_id, opts \\ []) do
    start_time = System.monotonic_time()

    items =
      with_seeded_random(opts, fn ->
        config = parse_learn_round_config(opts)
        terms = get_prioritized_terms(user, study_set_id, config)

        generate_mixed_items(terms, config)
      end)

    log_generation_result(
      "learn round",
      study_set_id,
      opts[:size] || @default_learn_size,
      length(items)
    )

    emit_telemetry(:learn_round, start_time, length(items), %{mode: :learn, user_present: true})

    items
  end

  @doc """
  Test mode: generate an N-length test of mixed question types.

  Generates a sequence of mixed question types suitable for assessment. Can optionally
  use spaced repetition scheduling when a user is present.

  ## Parameters
  - `user_or_nil` - Optional user map with :id field
  - `study_set_id` - ID of study set
  - `opts` - Keyword list of options

  ## Options
  - `:size` - Number of items (required)
  - `:types` - List of allowed types (see generate_learn_round/3)
  - `:pair_count` - For matching type, number of pairs to match
  - `:smart` - Enable scheduler priority when user present (default true)
  - `:exclude_term_ids` - Terms to avoid
  """
  @spec generate_test(user() | nil, study_set_id(), generation_opts()) :: [map()]
  def generate_test(user_or_nil, study_set_id, opts) do
    start_time = System.monotonic_time()

    items =
      with_seeded_random(opts, fn ->
        config = parse_test_config(opts)
        terms = get_test_terms(user_or_nil, study_set_id, config)

        generate_mixed_items(terms, config)
      end)

    size = opts[:size] || @default_test_size
    log_generation_result("test", study_set_id, size, length(items), user_or_nil)

    emit_telemetry(:test, start_time, length(items), %{
      mode: :test,
      user_present: not is_nil(user_or_nil)
    })

    items
  end

  # Private functions

  defp with_seeded_random(opts, fun) do
    maybe_seed_random(opts)
    fun.()
  end

  defp maybe_seed_random(opts) do
    case Keyword.get(opts, :seed) do
      nil -> :ok
      seed when is_integer(seed) -> :rand.seed(:exsplus, {seed, seed, seed})
    end
  end

  defp get_exclude_set(opts) do
    opts
    |> Keyword.get(:exclude_term_ids, [])
    |> MapSet.new()
  end

  defp fetch_study_set_terms(study_set_id) do
    Content.list_terms_for_study_set!(
      %{study_set_id: study_set_id},
      authorize?: false
    )
  end

  defp fetch_study_set_terms(study_set_id, actor) do
    Content.list_terms_for_study_set!(
      %{study_set_id: study_set_id},
      actor: actor
    )
  end

  defp select_scheduled_term(user, study_set_id, exclude_ids) do
    user
    |> Scheduler.build_daily_queue(study_set_id, @default_learn_size)
    |> Enum.find(fn entry ->
      tid = extract_term_id(entry)
      tid && not MapSet.member?(exclude_ids, tid)
    end)
    |> case do
      # TermState or mastery summary map
      %{term_id: term_id} when is_binary(term_id) or is_integer(term_id) ->
        term = Content.get_term_by_id!(term_id, authorize?: false)
        {:ok, term}

      # Direct Term struct
      %Term{} = term ->
        {:ok, term}

      nil ->
        :no_term_available
    end
  end

  defp build_multiple_choice_item(terms, exclude_ids) do
    case terms do
      [] ->
        build_empty_mcq()

      terms when is_list(terms) ->
        {prompt, choices, answer_idx, term_id} = build_mcq_from_terms(terms, exclude_ids)

        %{
          kind: "multiple_choice",
          prompt: prompt,
          choices: choices,
          answer_index: answer_idx,
          term_id: term_id
        }
    end
  end

  defp build_empty_mcq do
    %{
      kind: "multiple_choice",
      prompt: "No terms in study set",
      choices: ["—", "—", "—", "—"],
      answer_index: 0,
      term_id: nil
    }
  end

  defp build_targeted_mcq(target_term, all_terms) do
    correct_def = target_term.definition
    other_defs = extract_other_definitions(all_terms, target_term.id)

    distractors = build_distractors(other_defs, target_term.distractors, correct_def, 3)
    choices = build_shuffled_choices(correct_def, distractors)
    answer_index = find_answer_index(choices, correct_def)

    %{
      kind: "multiple_choice",
      prompt: target_term.term,
      choices: choices,
      answer_index: answer_index,
      term_id: target_term.id
    }
  end

  defp extract_other_definitions(terms, exclude_id) do
    terms
    |> Enum.reject(&(&1.id == exclude_id))
    |> Enum.map(& &1.definition)
  end

  defp build_distractors(other_definitions, term_distractors, correct_def, needed_count) do
    from_terms =
      other_definitions
      |> Enum.uniq()
      |> Enum.shuffle()
      |> Enum.take(needed_count)

    remaining_needed = needed_count - length(from_terms)

    from_metadata =
      if remaining_needed > 0 do
        (term_distractors || [])
        |> Enum.reject(&(&1 == correct_def))
        |> Enum.uniq()
        |> Enum.shuffle()
        |> Enum.take(remaining_needed)
      else
        []
      end

    from_terms ++ from_metadata
  end

  defp build_shuffled_choices(correct_answer, distractors) do
    [correct_answer | distractors]
    |> Enum.uniq()
    |> pad_choices_to_four(correct_answer)
    |> Enum.shuffle()
  end

  defp pad_choices_to_four(choices, correct_answer) do
    case length(choices) do
      4 ->
        choices

      n when n < 4 ->
        padding = generate_padding(4 - n, correct_answer)
        choices ++ padding

      _ ->
        Enum.take(choices, 4)
    end
  end

  defp generate_padding(count, correct_answer) do
    1..count
    |> Enum.map(fn i -> "Not #{correct_answer} (#{i})" end)
  end

  defp find_answer_index(choices, correct_answer) do
    Enum.find_index(choices, &(&1 == correct_answer)) || 0
  end

  defp build_mcq_from_terms(terms, exclude_ids) do
    shuffled_terms = Enum.shuffle(terms)
    available_terms = Enum.reject(shuffled_terms, &MapSet.member?(exclude_ids, &1.id))

    target = select_target_term(available_terms, shuffled_terms)
    correct_def = target.definition
    other_defs = extract_other_definitions(terms, target.id)

    distractors = build_distractors(other_defs, target.distractors, correct_def, 3)
    final_distractors = ensure_sufficient_distractors(distractors, correct_def)

    choices = [correct_def | final_distractors] |> Enum.shuffle()
    answer_index = find_answer_index(choices, correct_def)

    {target.term, choices, answer_index, target.id}
  end

  defp select_target_term([], fallback_terms), do: Enum.random(fallback_terms)
  defp select_target_term(available_terms, _), do: Enum.random(available_terms)

  defp ensure_sufficient_distractors(distractors, correct_def) do
    case length(distractors) do
      n when n >= 3 ->
        Enum.take(distractors, 3)

      n ->
        padding = generate_padding(3 - n, correct_def)
        distractors ++ padding
    end
  end

  defp determine_flashcard_order(opts) do
    smart? = Keyword.get(opts, :smart, true)
    order = Keyword.get(opts, :order, :smart)

    if order == :smart and not smart?, do: :alphabetical, else: order
  end

  defp select_flashcard_term(user, study_set_id, exclude_ids, order) do
    exclude_list = MapSet.to_list(exclude_ids)

    case order do
      :smart ->
        select_smart_flashcard_term(user, study_set_id, exclude_ids)

      :alphabetical ->
        query_flashcard_term(study_set_id, user, exclude_list, term: :asc)

      :position ->
        query_flashcard_term(study_set_id, user, exclude_list, position: :asc)
    end
  end

  defp select_smart_flashcard_term(user, study_set_id, exclude_ids) do
    user
    |> Scheduler.build_daily_queue(study_set_id, 20)
    |> Enum.find(&(not MapSet.member?(exclude_ids, extract_term_id(&1))))
    |> case do
      %{term_id: term_id} ->
        term = Ash.get!(Term, term_id, authorize?: false)
        {:ok, term}

      %Term{} = term ->
        {:ok, term}

      nil ->
        :no_term_available
    end
  end

  defp extract_term_id(%{term_id: id}), do: id
  defp extract_term_id(%Term{id: id}), do: id
  defp extract_term_id(_), do: nil

  defp query_flashcard_term(study_set_id, user, exclude_list, sort_order) do
    case Content.list_terms_for_study_set!(
           %{study_set_id: study_set_id},
           actor: user,
           query:
             Term
             |> Ash.Query.filter(id not in ^exclude_list)
             |> Ash.Query.sort(sort_order)
             |> Ash.Query.limit(1)
         )
         |> List.first() do
      nil -> :no_term_available
      term -> {:ok, term}
    end
  end

  defp parse_learn_round_config(opts) do
    %{
      size: Keyword.get(opts, :size, @default_learn_size),
      types: Keyword.get(opts, :types, [:multiple_choice, :true_false, :free_text, :matching]),
      pair_count: Keyword.get(opts, :pair_count, @default_matching_pairs),
      smart: Keyword.get(opts, :smart, true),
      exclude_ids: get_exclude_set(opts)
    }
  end

  defp parse_test_config(opts) do
    %{
      size: Keyword.get(opts, :size, @default_test_size),
      types: Keyword.get(opts, :types, [:multiple_choice, :true_false, :free_text, :matching]),
      pair_count: Keyword.get(opts, :pair_count, @default_matching_pairs),
      smart: Keyword.get(opts, :smart, true),
      exclude_ids: get_exclude_set(opts)
    }
  end

  defp get_prioritized_terms(
         user,
         study_set_id,
         %{smart: true, exclude_ids: exclude_ids} = config
       ) do
    queue_states =
      Scheduler.build_daily_queue(user, study_set_id, config.size * @default_queue_multiplier)

    all_terms = fetch_study_set_terms(study_set_id, user)

    exclude_list = MapSet.to_list(exclude_ids)

    filtered_terms =
      all_terms
      |> Enum.reject(&(&1.id in exclude_list))
      |> Map.new(&{&1.id, &1})

    candidates = extract_candidate_terms(queue_states, filtered_terms)

    (candidates ++ Map.values(filtered_terms))
    |> Enum.uniq_by(& &1.id)
  end

  defp get_prioritized_terms(_user, study_set_id, %{exclude_ids: exclude_ids}) do
    exclude_list = MapSet.to_list(exclude_ids)

    Content.list_terms_for_study_set!(
      %{study_set_id: study_set_id},
      authorize?: false,
      query:
        Term
        |> Ash.Query.filter(id not in ^exclude_list)
    )
  end

  defp get_test_terms(nil, study_set_id, %{exclude_ids: exclude_ids}) do
    exclude_list = MapSet.to_list(exclude_ids)

    Term
    |> Ash.Query.for_read(:for_study_set, %{study_set_id: study_set_id}, authorize?: false)
    |> Ash.Query.filter(id not in ^exclude_list)
    |> Ash.read!(authorize?: false)
  end

  defp get_test_terms(_user, study_set_id, %{smart: false} = config) do
    get_test_terms(nil, study_set_id, config)
  end

  defp get_test_terms(user, study_set_id, %{smart: true} = config) do
    exclude_list = MapSet.to_list(config.exclude_ids)

    all_terms =
      Content.list_terms_for_study_set!(
        %{study_set_id: study_set_id},
        authorize?: false,
        query:
          Term
          |> Ash.Query.filter(id not in ^exclude_list)
      )

    queue_states =
      Scheduler.build_daily_queue(user, study_set_id, config.size * @default_queue_multiplier)

    prioritized = extract_candidate_terms(queue_states, Map.new(all_terms, &{&1.id, &1}))

    Enum.uniq_by(prioritized ++ all_terms, & &1.id)
  end

  defp extract_candidate_terms(queue_states, terms_map) do
    Enum.flat_map(queue_states, fn
      %{term_id: term_id} ->
        case Map.fetch(terms_map, term_id) do
          {:ok, term} -> [term]
          :error -> []
        end

      %Term{} = term ->
        [term]

      _ ->
        []
    end)
  end

  defp generate_mixed_items(terms, config) do
    {items, _used_ids} = build_mixed_items(terms, MapSet.new(), config)
    items
  end

  defp build_mixed_items(_terms, used_ids, %{size: 0}), do: {[], used_ids}
  defp build_mixed_items([], used_ids, _config), do: {[], used_ids}

  defp build_mixed_items(terms, used_ids, config) do
    item_type = Enum.random(config.types)

    {item, new_used_ids} =
      case item_type do
        :matching ->
          build_matching_item_or_fallback(terms, used_ids, config)

        :true_false ->
          build_true_false_item(terms, used_ids)

        :free_text ->
          build_free_text_item(terms, used_ids)

        _ ->
          build_multiple_choice_item_from_pool(terms, used_ids)
      end

    {remaining_items, final_used_ids} =
      build_mixed_items(terms, new_used_ids, %{config | size: config.size - 1})

    {[item | remaining_items], final_used_ids}
  end

  defp build_matching_item_or_fallback(terms, used_ids, %{pair_count: pair_count}) do
    available_terms = Enum.reject(terms, &MapSet.member?(used_ids, &1.id))
    selected_terms = Enum.take(available_terms, pair_count)

    min_required = max(3, div(pair_count, 2))

    if length(selected_terms) < min_required do
      build_multiple_choice_item_from_pool(terms, used_ids)
    else
      item = build_matching_item(selected_terms)
      new_used_ids = Enum.reduce(selected_terms, used_ids, &MapSet.put(&2, &1.id))
      {item, new_used_ids}
    end
  end

  defp build_multiple_choice_item_from_pool(terms, used_ids) do
    target_term = select_unused_term(terms, used_ids)
    other_definitions = extract_other_definitions(terms, target_term.id)

    distractors =
      build_distractors(other_definitions, target_term.distractors, target_term.definition, 3)

    choices = build_shuffled_choices(target_term.definition, distractors)
    answer_index = find_answer_index(choices, target_term.definition)

    item = %{
      kind: "multiple_choice",
      prompt: target_term.term,
      choices: choices,
      answer_index: answer_index,
      term_id: target_term.id
    }

    {item, MapSet.put(used_ids, target_term.id)}
  end

  defp build_true_false_item(terms, used_ids) do
    target_term = select_unused_term(terms, used_ids)
    other_definitions = extract_other_definitions(terms, target_term.id)

    show_correct? = Enum.random([true, false])
    definition = select_definition_for_tf(target_term, other_definitions, show_correct?)
    is_correct? = definition == target_term.definition

    answer_index = if is_correct?, do: 0, else: 1

    item = %{
      kind: "true_false",
      prompt: "#{target_term.term}",
      definition: definition,
      choices: ["True", "False"],
      answer_index: answer_index,
      term_id: target_term.id
    }

    {item, MapSet.put(used_ids, target_term.id)}
  end

  defp select_definition_for_tf(target_term, _other_definitions, true), do: target_term.definition

  defp select_definition_for_tf(target_term, other_definitions, false) do
    candidates = other_definitions ++ (target_term.distractors || [])
    # fallback to correct if no alternatives
    Enum.random(candidates ++ [target_term.definition])
  end

  defp build_free_text_item(terms, used_ids) do
    target_term = select_unused_term(terms, used_ids)

    item = %{
      kind: "free_text",
      prompt: target_term.term,
      answer_text: target_term.definition,
      term_id: target_term.id
    }

    {item, MapSet.put(used_ids, target_term.id)}
  end

  defp build_matching_item(terms) do
    left_items = Enum.map(terms, &%{term_id: &1.id, term: &1.term})

    right_items =
      terms
      |> Enum.map(&%{definition: &1.definition, term_id: &1.id})
      |> Enum.shuffle()

    answer_pairs = build_matching_answer_key(left_items, right_items)

    %{
      kind: "matching",
      left: left_items,
      right: Enum.map(right_items, & &1.definition),
      answer_pairs: answer_pairs
    }
  end

  defp build_matching_answer_key(left_items, right_items) do
    left_items
    |> Enum.with_index()
    |> Enum.map(fn {%{term_id: term_id}, left_index} ->
      right_index = Enum.find_index(right_items, &(&1.term_id == term_id)) || left_index
      %{left_index: left_index, right_index: right_index}
    end)
  end

  defp select_unused_term(terms, used_ids) do
    Enum.find(terms, &(not MapSet.member?(used_ids, &1.id))) || List.first(terms)
  end

  defp log_generation_result(type, study_set_id, requested, returned, user \\ nil) do
    cond do
      returned == 0 ->
        Logger.error("No items generated for #{type}",
          study_set_id: study_set_id,
          requested: requested,
          user_present: not is_nil(user)
        )

      returned < requested ->
        Logger.warning("Undersupplied #{type}",
          study_set_id: study_set_id,
          requested: requested,
          returned: returned
        )

      true ->
        :ok
    end
  end

  defp emit_telemetry(event_name, start_time, count, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [event_name],
      %{duration: duration, count: count},
      metadata
    )
  end
end
