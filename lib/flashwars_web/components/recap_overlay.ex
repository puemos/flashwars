defmodule FlashwarsWeb.Components.RecapOverlay do
  use FlashwarsWeb, :html

  import FlashwarsWeb.CoreComponents, only: [progress: 1, icon: 1, button: 1]

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, default: "Round recap"
  attr :subtitle, :string, default: nil
  attr :items, :list, default: []
  attr :continue_event, :string, required: true
  attr :continue_label, :string, default: "Next Round"
  attr :empty_text, :string, default: "No items to recap."
  # Gamify options
  # Optional gamification props (if nil, derived heuristically)
  attr :level, :integer, default: nil
  attr :level_progress, :float, default: nil, doc: "0..100"
  attr :xp_earned, :integer, default: nil
  attr :streak, :integer, default: nil

  def recap_overlay(assigns) do
    assigns =
      assigns
      |> assign_new(:counts, fn assigns -> counts(assigns[:items] || []) end)
      |> assign_new(:good_pct, fn assigns -> good_pct(assigns[:items] || []) end)
      |> assign_new(:derived, fn assigns -> derive(assigns[:items] || []) end)
      |> assign_new(:eff_level, fn assigns -> assigns[:level] || assigns.derived.level end)
      |> assign_new(:eff_level_progress, fn assigns ->
        lp = assigns[:level_progress]
        if is_number(lp), do: max(0.0, min(lp, 100.0)), else: assigns.derived.level_progress
      end)
      |> assign_new(:eff_xp, fn assigns -> assigns[:xp_earned] || assigns.derived.xp_earned end)
      |> assign_new(:eff_streak, fn assigns -> assigns[:streak] end)

    ~H"""
    <div
      id={@id}
      class={["fixed inset-0 z-50", @show && "block", !@show && "hidden"]}
      phx-hook="OverlayDismiss"
      data-push-event={@continue_event}
      data-on-escape="true"
    >
      <div
        id={@id <> "-scrim"}
        class="absolute inset-0 bg-base-300/60 backdrop-blur-sm"
        phx-hook="OverlayDismiss"
        data-push-event={@continue_event}
      >
      </div>
      <div class="relative h-full flex flex-col justify-end md:flex md:items-center md:justify-center md:h-auto md:mt-10 md:transform md:translate-y-1/4">
        <div
          id={@id <> "-card"}
          class="recap-card card bg-base-300/80 border-2 border-base-100 shadow-2xl h-full overflow-hidden md:rounded-2xl rounded-none mx-auto w-full max-w-3xl transition-all duration-300 opacity-0 translate-y-6"
          phx-hook="PopIn"
        >
          <!-- Gamified header -->
          <div class="relative">
            <div class="h-20 md:h-24 bg-base-400"></div>
            <div class="absolute inset-0 flex items-center gap-3 md:gap-4 px-5">
              <.icon name="hero-trophy" class="size-8 md:size-10 text-yellow-400 drop-shadow" />
              <div>
                <div class="uppercase text-xs opacity-80">{@title}</div>
                <div class="text-xl md:text-2xl font-extrabold">Round Clear!</div>
              </div>
            </div>
          </div>

          <div class="card-body">
            <%= if @subtitle do %>
              <div class="text-base-content/80">{@subtitle}</div>
            <% end %>
            
    <!-- Top row: level ring + rewards + stars -->
            <div class="grid grid-cols-3 gap-4 items-center mt-2">
              <div class="col-span-1 flex">
                <.level_ring level={@eff_level} pct={@eff_level_progress} />
              </div>
              <div class="col-span-2">
                <div class="flex items-center gap-2">
                  <span class="badge badge-warning">
                    <.icon name="hero-sparkles" class="size-4" />
                    <span class="ml-1">
                      <span
                        id={@id <> "-xp"}
                        phx-hook="CountTo"
                        data-count-to={@eff_xp || 0}
                        data-count-ms="900"
                      >
                        0
                      </span>
                      XP
                    </span>
                  </span>
                  <span :if={@eff_streak} class="badge badge-error">
                    <.icon name="hero-fire" class="size-4" />
                    <span class="ml-1">
                      Streak
                      <span id={@id <> "-streak"} phx-hook="CountTo" data-count-to={@eff_streak}>
                        0
                      </span>
                    </span>
                  </span>
                </div>
                <div class="mt-2">
                  <.stars pct={@good_pct} />
                </div>
              </div>
            </div>
            
    <!-- Progress toward mastery -->
            <div class="mt-3">
              <div class="flex items-center justify-between text-sm opacity-80 mb-1">
                <div>Mastery Progress</div>
                <div>
                  <span
                    id={@id <> "-pct"}
                    phx-hook="CountTo"
                    data-count-to={Float.round(@good_pct, 0)}
                    data-count-ms="800"
                  >0</span>%
                </div>
              </div>
              <.progress pct={@good_pct} />
            </div>
            
    <!-- Recap list -->
            <ul class="divide-y divide-base-300 mt-4 overflow-y-auto max-h-[58vh]">
              <li
                :for={rec <- @items}
                id={"recap-#{rec.term_id}"}
                class="py-3 flex items-center justify-between"
              >
                <div class="font-medium">{rec.term}</div>
                <span class={badge_class(rec.mastery)}>{rec.mastery}</span>
              </li>
            </ul>
            <div :if={@items == []} class="opacity-70">{@empty_text}</div>

            <div class="mt-5 flex gap-2">
              <.button class="btn w-full btn-neutral" phx-click={@continue_event}>
                {@continue_label}
              </.button>
            </div>
          </div>
        </div>
        
    <!-- No confetti (intentionally removed for lean mobile feel) -->
      </div>
    </div>
    """
  end

  # ——— Mini components ———
  attr :level, :integer, default: 1
  attr :pct, :float, default: 0.0

  def level_ring(assigns) do
    pct = assigns[:pct] || 0.0
    clamped = pct |> max(0.0) |> min(100.0)
    # 2*pi*r ; r = 26
    circ = 163.36281798666926
    dash = circ * clamped / 100.0
    gap = circ - dash
    assigns = assign(assigns, circ: circ, dash: dash, gap: gap, clamped: clamped)

    ~H"""
    <div class="relative w-24 h-24 md:w-28 md:h-28">
      <svg viewBox="0 0 64 64" class="w-full h-full -rotate-90">
        <circle cx="32" cy="32" r="26" fill="none" stroke="rgba(255,255,255,0.2)" stroke-width="8" />
        <circle
          cx="32"
          cy="32"
          r="26"
          fill="none"
          stroke="currentColor"
          stroke-width="8"
          class="text-emerald-400 transition-all duration-500"
          stroke-dasharray={"#{Float.round(@dash, 2)} #{Float.round(@gap, 2)}"}
          stroke-linecap="round"
        />
      </svg>
      <div class="absolute inset-0 flex flex-col items-center justify-center">
        <div class="text-xs opacity-70">Level</div>
        <div class="text-xl md:text-2xl font-extrabold win-glow">{@level || 1}</div>
      </div>
    </div>
    """
  end

  attr :pct, :float, default: 0.0

  def stars(assigns) do
    pct = assigns[:pct] || 0.0

    filled =
      cond do
        pct >= 90 -> 3
        pct >= 70 -> 2
        pct >= 40 -> 1
        true -> 0
      end

    assigns = assign(assigns, :filled, filled)

    ~H"""
    <div class="flex items-center gap-1">
      <%= for i <- 1..3 do %>
        <.icon
          name={if i <= @filled, do: "hero-star-solid", else: "hero-star"}
          class={
            if i <= @filled, do: "size-6 text-yellow-400 animate-pop", else: "size-6 text-base-300"
          }
        />
      <% end %>
    </div>
    """
  end

  defp counts(items) do
    Enum.reduce(items, %{total: 0, mastered: 0, practicing: 0, struggling: 0, unseen: 0}, fn rec,
                                                                                             acc ->
      acc
      |> Map.update!(:total, &(&1 + 1))
      |> increment(String.downcase(to_string(rec.mastery || "")))
    end)
  end

  defp increment(acc, "mastered"), do: Map.update!(acc, :mastered, &(&1 + 1))
  defp increment(acc, "practicing"), do: Map.update!(acc, :practicing, &(&1 + 1))
  defp increment(acc, "struggling"), do: Map.update!(acc, :struggling, &(&1 + 1))
  defp increment(acc, "unseen"), do: Map.update!(acc, :unseen, &(&1 + 1))
  defp increment(acc, _), do: acc

  # percent of items not struggling (Mastered + Practicing)
  defp good_pct(items) do
    c = counts(items)

    if c.total > 0 do
      (c.mastered + c.practicing) * 100.0 / c.total
    else
      0.0
    end
  end

  defp derive(items) do
    c = counts(items)
    pct = good_pct(items)
    # Heuristic XP: reward mastery and practice
    base =
      c.mastered * 12 + c.practicing * 6 +
        max(0, c.total - c.struggling - c.mastered - c.practicing) * 2

    bonus = if c.struggling == 0 and c.total > 0, do: 10, else: 0
    xp = base + bonus
    # Simple leveling: 0..999 = lvl 1, 1000..1999 = lvl 2, etc.; progress within level
    total_xp = xp
    level = div(total_xp, 1000) + 1
    level_progress = rem(total_xp, 1000) * 100.0 / 1000.0
    %{xp_earned: xp, level: level, level_progress: level_progress, mastery_pct: pct}
  end

  defp badge_class("Mastered"), do: "badge badge-success"
  defp badge_class("Practicing"), do: "badge badge-info"
  defp badge_class("Struggling"), do: "badge badge-warning"
  defp badge_class(_), do: "badge badge-ghost"
end
