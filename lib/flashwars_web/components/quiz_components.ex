defmodule FlashwarsWeb.QuizComponents do
  @moduledoc """
  Game UI components that match the overlay look & feel.
  Uses Tailwind + daisyUI + your helper classes only:
  game-gradient, bg-pan, animate-pop, animate-float, win-glow, lose-glow,
  overlay-progress (.bar), confetti-[0..4].
  """
  use Phoenix.Component

  import FlashwarsWeb.CoreComponents

  # ————————————————————————————————————————————————————————————————
  # Components
  # ————————————————————————————————————————————————————————————————

  # Inputs
  # total segments
  attr :chunks, :integer, required: true
  # units per segment
  attr :chunk_size, :integer, required: true
  # active segment index (1..chunks)
  attr :chunk, :integer, required: true
  # position within active segment
  attr :offset, :integer, required: true

  attr :label, :any
  attr :id, :string, default: nil

  def segment_track(assigns) do
    assigns =
      assigns
      |> assign_new(:label, fn -> nil end)

    chunks = max(assigns[:chunks] || 1, 1)
    chunk_size = assigns[:chunk_size] || 0
    chunk = assigns[:chunk] |> max(1) |> min(chunks)
    offset = assigns[:offset] |> max(0) |> min(chunk_size)

    pct = if chunk_size > 0, do: offset / chunk_size * 100.0, else: 0.0
    done = max(chunk - 1, 0)
    todo = max(chunks - chunk, 0)
    badge_left = if chunks > 0, do: (chunk - 1 + pct / 100.0) / chunks * 100.0, else: 0.0

    base_id = assigns[:id] || "segtrack-#{chunks}-#{chunk_size}"

    assigns =
      assign(assigns,
        chunks: chunks,
        chunk_size: chunk_size,
        chunk: chunk,
        offset: offset,
        pct: Float.round(pct, 2),
        done: done,
        todo: todo,
        badge_left: Float.round(badge_left, 2),
        base_id: base_id,
        # Roll when THIS value changes. Use label by default:
        label_key: :erlang.phash2(assigns[:label])
        # If you prefer roll on progress instead, use:
        # label_key: :erlang.phash2({chunk, offset})
      )

    ~H"""
    <div class="relative flex w-full items-center gap-2 select-none">
      <div class="relative flex gap-2 w-full">
        <!-- completed -->
        <div
          :for={_ <- 1..@done}
          :if={@done > 0}
          class="relative h-4 flex-1 rounded-full bg-slate-600"
        >
          <div class="absolute inset-0 rounded-full bg-emerald-500"></div>
        </div>
        
    <!-- current -->
        <div class="relative h-4 flex-1 rounded-full bg-slate-600 overflow-visible">
          <div
            class="absolute left-0 top-0 h-full rounded-full bg-emerald-500 transition-all duration-300"
            style={"width: #{@pct}%"}
          />
        </div>
        
    <!-- upcoming -->
        <div :for={_ <- 1..@todo} class="relative h-4 flex-1 rounded-full bg-slate-600"></div>
        
    <!-- badge across full track -->
        <div
          :if={not is_nil(@label)}
          id={"#{@base_id}-badge"}
          class="transition-all absolute -top-2 w-8 h-8 rounded-full bg-emerald-500 text-white text-base font-bold flex items-center justify-center pointer-events-none overflow-hidden"
          style={"left: #{@badge_left}%; transform: translateX(-50%);"}
          phx-update="replace"
        >
          <!-- Replace this child ONLY when the watched value changes -->
          <span
            id={"#{@base_id}-label-#{@label_key}"}
            class="block leading-none animate-roll-up"
          >
            {@label}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ========== LOBBY ==========
  attr :presences, :map, required: true

  def lobby_players(assigns) do
    ~H"""
    <ul>
      <li :for={{key, %{metas: metas}} <- @presences} class="flex items-center gap-2 py-1">
        <span class="badge badge-success h-3 w-4"></span>
        <span>{List.first(metas)[:name] || String.slice(key, 0, 6)}</span>
      </li>
    </ul>
    """
  end

  # ========== HUD (sticky bar) ==========
  attr :round, :integer, required: true
  attr :rounds, :integer, required: true
  attr :seconds_left, :integer, default: nil
  attr :pct, :float, default: nil
  attr :players_count, :integer, required: true

  def hud(assigns) do
    ~H"""
    <.sticky_top>
      <div class="grid grid-cols-3 items-center">
        <div>
          <.stat label="Round" value={"#{@round}/#{@rounds}"} />
        </div>

        <div class="text-center">
          <div class="uppercase text-xs opacity-90">Time left</div>
          <div :if={@seconds_left != nil} class="font-extrabold tabular-nums animate-pop">
            {@seconds_left}s
          </div>
          <div :if={@seconds_left == nil} class="font-extrabold">-</div>
          <div :if={@pct != nil} class="mt-1">
            <.progress pct={@pct} />
          </div>
        </div>

        <div>
          <.stat label="Players" value={@players_count} align="right" />
        </div>
      </div>
    </.sticky_top>
    """
  end

  # ========== READY ROW ==========
  attr :current_user, :any, default: nil
  attr :intermission_rid, :any, default: nil
  attr :ready_user_ids, :any, default: MapSet.new()
  attr :presences, :map, default: %{}
  attr :host?, :boolean, default: false

  def ready_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <div :if={@current_user && @intermission_rid}>
        <button
          :if={!MapSet.member?(@ready_user_ids, @current_user.id)}
          class="btn btn-primary"
          phx-click="ready"
          phx-value-rid={@intermission_rid}
        >
          Ready
        </button>
        <button :if={MapSet.member?(@ready_user_ids, @current_user.id)} class="btn btn-ghost" disabled>
          Ready ✔️
        </button>
      </div>

      <div class="text-sm opacity-80">
        Players ready: {MapSet.size(@ready_user_ids)} / {map_size(@presences)}
      </div>

      <button
        :if={@host? && @intermission_rid}
        class="btn btn-outline"
        phx-click="override_next"
        phx-value-rid={@intermission_rid}
      >
        Start Next Now
      </button>
    </div>
    """
  end

  # ========== COUNTDOWN ==========
  attr :label, :string, required: true
  attr :seconds_left, :integer, required: true
  attr :pct, :float, required: true

  def countdown(assigns) do
    ~H"""
    <div>
      <div class="text-sm">
        {@label} <span class="tabular-nums font-semibold"><%= @seconds_left %></span>s
      </div>
      <div class="mt-1">
        <.progress pct={@pct} />
      </div>
    </div>
    """
  end

  # ========== RANKED SCOREBOARD ==========
  attr :entries, :list, required: true
  attr :nicknames, :map, default: %{}

  def scoreboard(assigns) do
    ~H"""
    <ul>
      <li
        :for={{entry, idx} <- Enum.with_index(@entries, 1)}
        class="flex justify-between items-center py-2"
      >
        <span class="flex items-center gap-2">
          <.rank_badge index={idx} />
          {Map.get(@nicknames, entry.user_id) || entry.name}
          <span :if={idx == 1} class="badge badge-success ml-1">Winner</span>
        </span>
        <span
          data-test-id={"score-#{Slug.slugify(Map.get(@nicknames, entry.user_id))}"}
          class="font-semibold tabular-nums"
        >
          {entry.score}
        </span>
      </li>
    </ul>
    """
  end

  # ========== RESULT OVERLAY ==========
  # Prefer :outcome (:win | :lose | :draw). :won kept for backward compat.
  attr :outcome, :atom, default: nil
  attr :won, :boolean, default: nil
  attr :seconds_left, :integer, required: true
  attr :pct, :float, required: true
  attr :current_user, :any, default: nil
  attr :intermission_rid, :any, default: nil
  attr :ready_user_ids, :any, default: MapSet.new()
  attr :presences, :map, default: %{}
  attr :host?, :boolean, default: false

  def result_overlay(assigns) do
    assigns =
      assign_new(assigns, :resolved_outcome, fn ->
        cond do
          is_atom(assigns.outcome) -> assigns.outcome
          is_boolean(assigns.won) -> if assigns.won, do: :win, else: :lose
          true -> :lose
        end
      end)

    ~H"""
    <div
      id="result-overlay"
      phx-hook="RoundOverlay"
      class="fixed inset-0 z-50 flex items-center justify-center select-none"
    >
      <div class="absolute inset-0 opacity-70 game-gradient bg-pan"></div>

      <div class="relative z-10 mx-4 w-full max-w-4xl">
        <div class={[
          "text-center text-white text-6xl md:text-7xl font-extrabold animate-pop",
          @resolved_outcome == :win && "win-glow",
          @resolved_outcome == :lose && "lose-glow",
          @resolved_outcome == :draw && ""
        ]}>
          {case @resolved_outcome do
            :win -> "YOU WIN! 🏆"
            :lose -> "YOU LOSE"
            :draw -> "NO WINNER"
          end}
        </div>

        <div class="mt-6 text-center">
          <div class="text-white/90 text-2xl md:text-4xl font-black animate-float">
            Next round in <span class="tabular-nums"><%= @seconds_left %></span>s
          </div>

          <div class="mt-4">
            <.progress pct={@pct} height="h-6 md:h-8" />
          </div>

          <div class="mt-6 flex items-center justify-center gap-3">
            <%= if @current_user && @intermission_rid do %>
              <button
                :if={!MapSet.member?(@ready_user_ids, @current_user.id)}
                class="btn btn-primary btn-lg"
                phx-click="ready"
                phx-value-rid={@intermission_rid}
              >
                I’m Ready
              </button>
              <button
                :if={MapSet.member?(@ready_user_ids, @current_user.id)}
                class="btn btn-ghost btn-lg"
                disabled
              >
                Ready ✔️
              </button>
            <% end %>

            <div class="text-white/90 text-sm md:text-base">
              Players ready: {MapSet.size(@ready_user_ids)} / {map_size(@presences)}
            </div>

            <button
              :if={@host? && @intermission_rid}
              class="btn btn-outline btn-sm md:btn-md"
              phx-click="override_next"
              phx-value-rid={@intermission_rid}
            >
              Start Next Now
            </button>
          </div>
        </div>
      </div>

      <div :if={@resolved_outcome == :win} aria-hidden class="pointer-events-none absolute inset-0">
        <div
          :for={i <- 1..36}
          class={"confetti confetti-#{rem(i,5)}"}
          style={"left: #{rem(i*17,100)}%; animation-delay: #{rem(i*137,900)/100.0}s;"}
        >
        </div>
      </div>
    </div>
    """
  end

  # ========== CHOICES (quiz only) ==========
  attr :choices, :list, default: []
  attr :reveal, :map, default: nil
  attr :round_closed?, :boolean, default: false
  attr :answered?, :boolean, default: false
  # New API
  attr :correct_index, :integer, default: nil
  attr :selected_index, :integer, default: nil
  attr :immediate_response, :boolean, default: false

  def choices(assigns) do
    assigns =
      assigns
      |> assign_new(:eff_correct, fn ->
        if is_integer(assigns.correct_index),
          do: assigns.correct_index,
          else: assigns.reveal && assigns.reveal[:correct_index]
      end)
      |> assign_new(:eff_selected, fn ->
        if is_integer(assigns.selected_index),
          do: assigns.selected_index,
          else: assigns.reveal && assigns.reveal[:selected_index]
      end)
      |> assign(
        :show_feedback,
        assigns.round_closed? or
          (assigns.immediate_response and not is_nil(assigns[:eff_selected]))
      )
      |> assign(:locked?, assigns.answered? || assigns.round_closed?)

    choice_data =
      Enum.with_index(assigns.choices)
      |> Enum.map(fn {choice, idx} ->
        %{
          choice: choice,
          idx: idx,
          is_correct:
            assigns.show_feedback && not is_nil(assigns.eff_correct) && idx == assigns.eff_correct,
          is_wrong:
            assigns.show_feedback && not is_nil(assigns.eff_selected) &&
              assigns.eff_selected == idx && assigns.eff_selected != assigns.eff_correct,
          letter: idx + 1
        }
      end)

    assigns = assign(assigns, :choice_data, choice_data)

    ~H"""
    <div class="mt-4 grid grid-cols-2 gap-2">
      <%= for choice_item <- @choice_data do %>
        <button
          type="button"
          class={[
            "btn btn-lg w-full py-8 justify-start items-center gap-3 whitespace-normal shadow-lg transition-transform hover:-translate-y-0.5 bg-base-300",
            choice_item.is_correct && "border-success border-2",
            choice_item.is_wrong && "border-error border-2",
            @locked? && "pointer-events-none cursor-default"
          ]}
          aria-disabled={@locked?}
          tabindex={if @locked?, do: "-1"}
          phx-click={if @locked?, do: nil, else: "answer"}
          phx-value-index={if @locked?, do: nil, else: choice_item.idx}
          phx-window-keyup={
            unless @locked?,
              do: "answer"
          }
          phx-key={choice_item.idx + 1}
        >
          <.kbd text={choice_item.letter} />
          <span class="font-semibold flex-1 text-left">{choice_item.choice}</span>
          <span class={[
            "ml-2",
            choice_item.is_correct && "text-success",
            choice_item.is_wrong && "text-error"
          ]}>
            <span :if={choice_item.is_correct}>✓</span>
            <span :if={choice_item.is_wrong}>✗</span>
          </span>
        </button>
      <% end %>
    </div>
    """
  end

  # ========== TRUE / FALSE ==========
  @doc """
  Renders a True/False question. Expects the caller to show the prompt separately.
  Pass the definition to verify and an optional `reveal` map like `%{selected_index: 1, correct_index: 0}`.
  Reuses the existing `<.choices>` component for buttons.
  """
  attr :definition, :string, required: true
  attr :choices, :list, default: ["True", "False"]
  attr :reveal, :map, default: nil
  attr :round_closed?, :boolean, default: false
  attr :answered?, :boolean, default: false
  # New passthrough API
  attr :correct_index, :integer, default: nil
  attr :selected_index, :integer, default: nil
  attr :immediate_response, :boolean, default: false

  attr :rest, :global, default: %{}

  def true_false(assigns) do
    ~H"""
    <div {@rest}>
      <div class="mb-4 p-4 rounded-lg bg-base-200 border border-base-300">{@definition}</div>

      <.choices
        choices={@choices}
        reveal={@reveal}
        round_closed?={@round_closed?}
        answered?={@answered?}
        correct_index={@correct_index}
        selected_index={@selected_index}
        immediate_response={@immediate_response}
      />
    </div>
    """
  end

  # ========== FREE TEXT ==========
  @doc """
  Renders a free-text answer input.
  Events expected in the LiveView:
  - `phx-submit=\"answer_text\"` receives params under `"answer" => %{ "text" => ... }`
  Optional `reveal` may include `%{user_text: binary(), correct_text: binary()}` for post-round display.
  """
  attr :placeholder, :string, default: "Type your answer…"
  attr :reveal, :map, default: nil
  attr :round_closed?, :boolean, default: false
  attr :answered?, :boolean, default: false
  attr :rest, :global, default: %{}

  def free_text(assigns) do
    assigns =
      assign_new(assigns, :user_text, fn -> assigns.reveal && assigns.reveal[:user_text] end)

    ~H"""
    <div {@rest}>
      <form phx-submit="answer_text" class="flex items-center gap-2">
        <input
          type="text"
          name="answer[text]"
          value={@user_text}
          placeholder={@placeholder}
          class="input input-bordered w-full y-2"
          disabled={@answered? || @round_closed?}
          autocomplete="off"
        />
        <button type="submit" class="btn btn-primary" disabled={@answered? || @round_closed?}>
          Submit
        </button>
      </form>

      <%= if @round_closed? && @reveal do %>
        <% user = String.trim(@reveal[:user_text] || "") %>
        <% correct = String.trim(@reveal[:correct_text] || "") %>
        <% ok? = String.downcase(user) == String.downcase(correct) and byte_size(correct) > 0 %>
        <div class={["mt-4 alert", ok? && "alert-success", !ok? && "alert-error"]}>
          <div class="font-semibold">Correct answer</div>
          <div class="opacity-90 break-words">{correct}</div>
          <div class="mt-2 text-sm">Your answer: <span class="font-medium">{user}</span></div>
        </div>
      <% end %>
    </div>
    """
  end

  # inside your Phoenix Component module (use Phoenix.Component)

  attr :id, :string, required: true
  attr :left, :list, required: true
  attr :right, :list, required: true
  attr :pairs, :list, default: []
  attr :selected_left, :integer, default: nil
  attr :selected_right, :integer, default: nil
  attr :reveal, :map, default: nil
  attr :round_closed?, :boolean, default: false
  attr :answered?, :boolean, default: false
  attr :rest, :global, default: %{}

  def matching(assigns) do
    assigns =
      prepare_matching(assigns)

    ~H"""
    <div
      id={@id}
      phx-hook="MatchingDnD"
      data-disabled={@answered? || @round_closed?}
      {@rest}
      class="relative grid grid-cols-1 md:grid-cols-2 gap-20"
    >
      <!-- Lines layer -->
      <svg
        id={"#{@id}-lines"}
        phx-hook="MatchingLines"
        data-root-id={@id}
        data-lines={Jason.encode!(@line_data)}
        class="pointer-events-none absolute inset-0 z-0"
      />
      
    <!-- Columns (raised above the lines) -->
      <div class="relative z-10">
        <.left_column
          id_prefix={@id}
          left={@left}
          user_pairs={@user_pairs}
          selected_left={@selected_left}
          left_used={@left_used}
          correct_lookup={@correct_lookup}
          answered?={@answered?}
          round_closed?={@round_closed?}
        />
      </div>

      <div class="relative z-10">
        <.right_column
          id_prefix={@id}
          right={@right}
          user_pairs={@user_pairs}
          selected_right={@selected_right}
          right_used={@right_used}
          answered?={@answered?}
          round_closed?={@round_closed?}
        />
      </div>
    </div>

    <!-- Progress + actions -->
    <div class="mt-4">
      <div class="flex flex-row-reverse items-center justify-between mb-2">
        <button
          type="button"
          class="btn btn-primary"
          phx-click="submit_matches"
          disabled={@answered? || @round_closed? || length(@user_pairs) == 0}
        >
          Submit Matches
        </button>
      </div>
    </div>
    """
  end

  defp prepare_matching(assigns) do
    reveal = assigns.reveal || %{}
    user_pairs = Map.get(reveal, :user_pairs, assigns.pairs || [])
    correct_pairs = Map.get(reveal, :correct_pairs, [])

    max_possible_pairs = min(length(assigns.left), length(assigns.right))
    correct_lookup = MapSet.new(for %{left_index: l, right_index: r} <- correct_pairs, do: {l, r})
    right_used = MapSet.new(for %{right_index: r} <- user_pairs, do: r)
    left_used = MapSet.new(for %{left_index: l} <- user_pairs, do: l)

    progress_pct =
      if max_possible_pairs > 0 do
        Integer.floor_div(length(user_pairs) * 100, max_possible_pairs)
      else
        0
      end

    line_data =
      Enum.map(user_pairs, fn p ->
        status =
          if assigns.round_closed? do
            if MapSet.member?(correct_lookup, {p.left_index, p.right_index}),
              do: "ok",
              else: "bad"
          else
            "user"
          end

        %{l: p.left_index, r: p.right_index, status: status}
      end)

    assign(assigns,
      user_pairs: user_pairs,
      correct_pairs: correct_pairs,
      max_possible_pairs: max_possible_pairs,
      right_used: right_used,
      left_used: left_used,
      correct_lookup: correct_lookup,
      progress_pct: progress_pct,
      line_data: line_data
    )
  end

  # ---------- Private subcomponents ----------

  # Left column
  attr :id_prefix, :string, required: true
  attr :left, :list, required: true
  attr :user_pairs, :list, required: true
  attr :selected_left, :integer, default: nil
  attr :left_used, :any, required: true
  attr :correct_lookup, :any, required: true
  attr :answered?, :boolean, default: false
  attr :round_closed?, :boolean, default: false

  defp left_column(assigns) do
    ~H"""
    <div data-side="left" class="space-y-2">
      <div class="uppercase text-xs opacity-70 mb-2">Terms</div>
      <ul class="space-y-2">
        <li :for={{item, index} <- Enum.with_index(@left)}>
          <.left_item
            id_prefix={@id_prefix}
            item={item}
            index={index}
            user_pairs={@user_pairs}
            selected_left={@selected_left}
            left_used={@left_used}
            correct_lookup={@correct_lookup}
            answered?={@answered?}
            round_closed?={@round_closed?}
          />
        </li>
      </ul>
    </div>
    """
  end

  # A single left row
  attr :id_prefix, :string, required: true
  attr :item, :map, required: true
  attr :index, :integer, required: true
  attr :user_pairs, :list, required: true
  attr :selected_left, :integer, default: nil
  attr :left_used, :any, required: true
  attr :correct_lookup, :any, required: true
  attr :answered?, :boolean, default: false
  attr :round_closed?, :boolean, default: false

  defp left_item(assigns) do
    ~H"""
    <% matched_right =
      Enum.find_value(@user_pairs, fn p -> if p.left_index == @index, do: p.right_index end) %>
    <% is_selected = @selected_left == @index %>
    <% is_used = MapSet.member?(@left_used, @index) %>
    <% order_idx = Enum.find_index(@user_pairs, &(&1.left_index == @index)) %>
    <% result_badge =
      if @round_closed? && !is_nil(matched_right) do
        if MapSet.member?(@correct_lookup, {@index, matched_right}),
          do: "badge-success",
          else: "badge-error"
      else
        nil
      end %>

    <button
      id={"#{@id_prefix}-l-#{@index}"}
      type="button"
      data-index={@index}
      data-draggable={!(@answered? || @round_closed? || is_used)}
      class={[
        "btn w-full border-2 border-dashed border-neutral-content/30 justify-between",
        is_selected && "btn-primary",
        is_used && "border-solid border-neutral-content/60",
        !is_used && !(@answered? || @round_closed?) && "cursor-grab"
      ]}
      phx-value-side="left"
      phx-value-index={@index}
      disabled={@answered? || @round_closed?}
      aria-grabbed="false"
    >
      <span class="truncate text-left">{@item.term}</span>

      <span
        :if={!is_nil(order_idx)}
        class={[
          "badge ml-2",
          is_nil(result_badge) && "badge-ghost",
          result_badge
        ]}
      >
        {order_idx + 1}
      </span>
    </button>
    """
  end

  # Right column
  attr :id_prefix, :string, required: true
  attr :right, :list, required: true
  attr :user_pairs, :list, required: true
  attr :selected_right, :integer, default: nil
  attr :right_used, :any, required: true
  attr :answered?, :boolean, default: false
  attr :round_closed?, :boolean, default: false

  defp right_column(assigns) do
    ~H"""
    <div data-side="right" class="space-y-2">
      <div class="uppercase text-xs opacity-70 mb-2">Definitions</div>
      <ul class="space-y-2">
        <li :for={{defn, index} <- Enum.with_index(@right)}>
          <.right_item
            id_prefix={@id_prefix}
            defn={defn}
            index={index}
            user_pairs={@user_pairs}
            selected_right={@selected_right}
            right_used={@right_used}
            answered?={@answered?}
            round_closed?={@round_closed?}
          />
        </li>
      </ul>
    </div>
    """
  end

  # A single right row
  attr :id_prefix, :string, required: true
  attr :defn, :any, required: true
  attr :index, :integer, required: true
  attr :user_pairs, :list, required: true
  attr :selected_right, :integer, default: nil
  attr :right_used, :any, required: true
  attr :answered?, :boolean, default: false
  attr :round_closed?, :boolean, default: false

  defp right_item(assigns) do
    ~H"""
    <% is_selected = @selected_right == @index %>
    <% is_used = MapSet.member?(@right_used, @index) %>
    <% order_idx = Enum.find_index(@user_pairs, &(&1.right_index == @index)) %>

    <button
      id={"#{@id_prefix}-r-#{@index}"}
      type="button"
      data-index={@index}
      data-droppable={!(@answered? || @round_closed? || is_used)}
      class={[
        "btn w-full border-2 border-dashed border-neutral-content/30 justify-start whitespace-normal align-top",
        is_selected && "btn-primary",
        is_used && "border-solid border-neutral-content/60"
      ]}
      phx-value-side="right"
      phx-value-index={@index}
      disabled={@answered? || @round_closed?}
      aria-dropeffect="link"
    >
      <span class="text-left flex-1">{@defn}</span>
      <span :if={!is_nil(order_idx)} class="badge ml-2 badge-ghost">{order_idx + 1}</span>
    </button>
    """
  end
end
