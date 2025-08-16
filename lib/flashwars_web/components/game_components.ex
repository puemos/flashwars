defmodule FlashwarsWeb.GameComponents do
  @moduledoc """
  Game UI components that match the overlay look & feel.
  Uses Tailwind + daisyUI + your helper classes only:
  game-gradient, bg-pan, animate-pop, animate-float, win-glow, lose-glow,
  overlay-progress (.bar), confetti-[0..4].
  """
  use Phoenix.Component

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

  # ========== HUD (sticky bar with gentle gradient + overlay-style progress) ==========
  attr :round, :integer, required: true
  attr :rounds, :integer, required: true
  attr :seconds_left, :integer, default: nil
  attr :pct, :float, default: nil
  attr :players_count, :integer, required: true

  def hud(assigns) do
    ~H"""
    <div class="sticky top-0 z-30">
      <div class="relative border-b border-base-300">
        <div class="relative mx-auto max-w-6xl px-4 py-3 grid grid-cols-3 items-center">
          <div class="text-sm opacity-90">
            <div class="uppercase text-xs">Round</div>
            <div class="font-extrabold tabular-nums">{@round}/{@rounds}</div>
          </div>

          <div class="text-center">
            <div class="uppercase text-xs opacity-90">Time left</div>
            <div :if={@seconds_left != nil} class="font-extrabold tabular-nums animate-pop">
              {@seconds_left}s
            </div>
            <div :if={@seconds_left == nil} class="font-extrabold">—</div>
            <div
              :if={@pct != nil}
              class="mt-1 h-3 rounded-full overflow-hidden overlay-progress"
              style={"--pct: #{@pct}%"}
            >
              <div class="bar"></div>
            </div>
          </div>

          <div class="text-right text-sm opacity-90">
            <div class="uppercase text-xs">Players</div>
            <div class="font-extrabold tabular-nums">{@players_count}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ========== CHOICES (default to purple instead of gray; keep success/error reveal) ==========
  attr :choices, :list, default: []
  attr :reveal, :map, default: nil
  attr :round_closed?, :boolean, default: false
  attr :answered?, :boolean, default: false

  def choices(assigns) do
    ~H"""
    <div class="mt-4 grid grid-cols-1 gap-2">
      <%= for {choice, idx} <- Enum.with_index(@choices) do %>
        <% is_correct = @round_closed? && idx == (@reveal && @reveal.correct_index) %>
        <% is_wrong =
          @round_closed? && @reveal && idx == @reveal.selected_index &&
            @reveal.selected_index != @reveal.correct_index %>
        <% letter = <<?A + idx>> %>
        <button
          type="button"
          class={
            [
              # Default now purple (btn-secondary), not gray neutral
              "btn btn-lg w-full py-10 justify-start items-center gap-3 whitespace-normal shadow-lg transition-transform hover:-translate-y-0.5",
              is_correct && "btn-success",
              is_wrong && "btn-error",
              !is_correct && !is_wrong && "bg-base-100"
            ]
          }
          phx-click="answer"
          phx-value-index={idx}
          disabled={@answered? || @round_closed?}
        >
          <kbd class="kbd kbd-lg">{letter}</kbd>
          <span class="font-semibold">{choice}</span>
        </button>
      <% end %>
    </div>
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

  # ========== COUNTDOWN (overlay-style) ==========
  attr :label, :string, required: true
  attr :seconds_left, :integer, required: true
  attr :pct, :float, required: true

  def countdown(assigns) do
    ~H"""
    <div>
      <div class="text-sm">
        {@label} <span class="tabular-nums font-semibold"><%= @seconds_left %></span>s
      </div>
      <div class="mt-1 h-3 rounded-full overflow-hidden overlay-progress" style={"--pct: #{@pct}%"}>
        <div class="bar"></div>
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
          <span class={[
            "badge",
            idx == 1 && "badge-warning",
            idx == 2 && "badge-info",
            idx == 3 && "badge-secondary",
            idx > 3 && "badge-ghost"
          ]}>
            {idx}
          </span>
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
  # Prefer `:outcome` (:win | :lose | :draw). `:won` is kept for backward-compat.
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

          <div
            class="mt-4 h-6 md:h-8 w-full rounded-full overflow-hidden overlay-progress"
            style={"--pct: #{@pct}%"}
          >
            <div class="bar"></div>
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
end
