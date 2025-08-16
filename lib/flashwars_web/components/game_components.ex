defmodule FlashwarsWeb.GameComponents do
  @moduledoc """
  Small, focused components that match the existing 'peak' design.
  No extra CSS beyond the classes you already have in app.css.
  """
  use Phoenix.Component

  # -- Lobby players ----------------------------------------------------------

  attr :presences, :map, required: true

  def lobby_players(assigns) do
    ~H"""
    <ul>
      <li
        :for={{key, %{metas: metas}} <- @presences}
        class="flex items-center gap-2 py-1"
      >
        <span class="badge badge-success"></span>
        <span>{List.first(metas)[:name] || String.slice(key, 0, 6)}</span>
      </li>
    </ul>
    """
  end

  # -- Choices ---------------------------------------------------------------

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
        <button
          type="button"
          class={[
            "btn",
            is_correct && "btn-success",
            is_wrong && "btn-error"
          ]}
          phx-click="answer"
          phx-value-index={idx}
          disabled={@answered? || @round_closed?}
        >
          {choice}
        </button>
      <% end %>
    </div>
    """
  end

  # -- Scoreboard ------------------------------------------------------------

  attr :entries, :list, required: true
  attr :nicknames, :map, default: %{}

  def scoreboard(assigns) do
    ~H"""
    <ul>
      <li :for={entry <- @entries} class="flex justify-between">
        <span>{Map.get(@nicknames, entry.user_id) || entry.name}</span>
        <span class="font-semibold">{entry.score}</span>
      </li>
    </ul>
    """
  end

  # -- Result overlay (win/lose + next-round) --------------------------------

  attr :won, :boolean, required: true
  attr :seconds_left, :integer, required: true
  attr :pct, :float, required: true

  attr :current_user, :any, default: nil
  attr :intermission_rid, :any, default: nil
  attr :ready_user_ids, :any, default: MapSet.new()
  attr :presences, :map, default: %{}
  attr :host?, :boolean, default: false

  def result_overlay(assigns) do
    ~H"""
    <div
      id="result-overlay"
      phx-hook="RoundOverlay"
      class="fixed inset-0 z-50 flex items-center justify-center select-none"
    >
      <!-- Animated gradient background -->
      <div class="absolute inset-0 opacity-70 game-gradient bg-pan"></div>
      
    <!-- Content -->
      <div class="relative z-10 mx-4 w-full max-w-4xl">
        <div class={[
          "text-center text-white text-6xl md:text-7xl font-extrabold animate-pop",
          @won && "win-glow",
          !@won && "lose-glow"
        ]}>
          {if @won, do: "YOU WIN! 🏆", else: "YOU LOSE"}
        </div>

        <div class="mt-6 text-center">
          <div class="text-white/90 text-2xl md:text-4xl font-black animate-float">
            Next round in <span class="tabular-nums"><%= @seconds_left %></span>s
          </div>
          
    <!-- Big progress bar driven by --pct -->
          <div
            class="mt-4 h-6 md:h-8 w-full rounded-full overflow-hidden overlay-progress"
            style={"--pct: #{@pct}%"}
          >
            <div class="bar"></div>
          </div>
          
    <!-- Ready row -->
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
      
    <!-- Confetti on win -->
      <div :if={@won} aria-hidden class="pointer-events-none absolute inset-0">
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

  defp ms_remaining(nil, _now), do: nil

  defp ms_remaining(deadline, nil) when is_integer(deadline) do
    now = System.monotonic_time(:millisecond)
    max(deadline - now, 0)
  end

  defp ms_remaining(deadline, now) when is_integer(deadline) and is_integer(now) do
    max(deadline - now, 0)
  end
end
