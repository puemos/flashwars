defmodule FlashwarsWeb.QuizComponents do
  @moduledoc """
  Game UI components that match the overlay look & feel.
  Uses Tailwind + daisyUI + your helper classes only:
  game-gradient, bg-pan, animate-pop, animate-float, win-glow, lose-glow,
  overlay-progress (.bar), confetti-[0..4].
  """
  use Phoenix.Component

  import FlashwarsWeb.CoreComponents

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
          class="input input-bordered w-full"
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

  # ========== MATCHING ==========
  @doc """
  Renders a two-column matching UI.
  Inputs mirror Engine output shape:
  - `left`: list of `%{term_id, term}`
  - `right`: list of definition strings
  State from the LiveView:
  - `pairs`: list of `%{left_index, right_index}` already matched by the user
  - `selected_left` / `selected_right`: index currently highlighted (optional)
  Events expected in the LiveView:
  - `phx-click=\"match_pick\"` with `phx-value-side` ("left"|"right") and `phx-value-index`
  - `phx-click=\"submit_matches\"` to finalize the answer
  `reveal` may include `%{correct_pairs: [...], user_pairs: [...]}` using the same pair shape.
  """
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
    ~H"""
    <% user_pairs = (@reveal && (@reveal[:user_pairs] || @pairs)) || @pairs %>
    <% correct_pairs = (@reveal && (@reveal[:correct_pairs] || [])) || [] %>

    <% right_used = MapSet.new(Enum.map(user_pairs, & &1.right_index)) %>
    <% left_used = MapSet.new(Enum.map(user_pairs, & &1.left_index)) %>
    <% correct_lookup = MapSet.new(Enum.map(correct_pairs, fn p -> {p.left_index, p.right_index} end)) %>

    <div {@rest} class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <div class="uppercase text-xs opacity-70 mb-2">Terms</div>
        <ul class="space-y-2">
          <li :for={{item, li} <- Enum.with_index(@left)}>
            <% matched_right =
              Enum.find_value(user_pairs, fn p -> if p.left_index == li, do: p.right_index end) %>
            <% is_selected = @selected_left == li %>
            <% is_used = MapSet.member?(left_used, li) %>
            <% result_badge =
              if @round_closed? && matched_right != nil do
                if MapSet.member?(correct_lookup, {li, matched_right}),
                  do: "badge-success",
                  else: "badge-error"
              else
                nil
              end %>
            <button
              type="button"
              class={[
                "btn w-full justify-between",
                is_selected && "btn-primary",
                is_used && "btn-ghost"
              ]}
              phx-click="match_pick"
              phx-value-side="left"
              phx-value-index={li}
              disabled={@answered? || @round_closed?}
            >
              <span class="truncate text-left">{item.term}</span>
              <span :if={not is_nil(result_badge)} class={"badge ml-2 #{result_badge}"}>
                {if result_badge == "badge-success", do: "✓", else: "✗"}
              </span>
            </button>
          </li>
        </ul>
      </div>

      <div>
        <div class="uppercase text-xs opacity-70 mb-2">Definitions</div>
        <ul class="space-y-2">
          <li :for={{defn, ri} <- Enum.with_index(@right)}>
            <% is_selected = @selected_right == ri %>
            <% is_used = MapSet.member?(right_used, ri) %>
            <button
              type="button"
              class={[
                "btn w-full justify-start whitespace-normal",
                is_selected && "btn-primary",
                is_used && "btn-ghost"
              ]}
              phx-click="match_pick"
              phx-value-side="right"
              phx-value-index={ri}
              disabled={@answered? || @round_closed?}
            >
              <span class="text-left">{defn}</span>
            </button>
          </li>
        </ul>
      </div>
    </div>

    <div class="mt-4 flex items-center justify-between">
      <div class="text-sm opacity-80">
        Selected pairs: <span class="tabular-nums font-semibold">{length(user_pairs)}</span>
      </div>

      <button
        type="button"
        class="btn btn-primary"
        phx-click="submit_matches"
        disabled={@answered? || @round_closed? || length(user_pairs) == 0}
      >
        Submit Matches
      </button>
    </div>
    """
  end
end
