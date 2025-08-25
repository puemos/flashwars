defmodule FlashwarsWeb.Components.SwipeDeckComponent do
  use FlashwarsWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:deck_id, fn -> "swipe-deck-#{System.unique_integer()}" end)
     |> assign_new(:directions, fn -> ["left", "right", "up", "down"] end)
     |> assign_new(:stack_size, fn -> 3 end)
     |> assign_new(:keyboard, fn -> true end)
     |> assign_new(:haptics, fn -> true end)}
  end

  @impl true
  def handle_event(
        "swipe",
        %{"direction" => direction, "item_id" => item_id, "programmatic" => programmatic},
        socket
      ) do
    # Find the swiped item
    item = Enum.find(socket.assigns.items, &(to_string(&1.id) == item_id))

    # Send event to parent LiveView
    send(
      self(),
      {:swipe_event,
       %{
         direction: direction,
         item: item,
         item_id: item_id,
         programmatic: programmatic,
         component_id: socket.assigns.id
       }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("deck_empty", %{"total_swiped" => total}, socket) do
    # Send event to parent LiveView
    send(
      self(),
      {:deck_empty,
       %{
         total_swiped: total,
         component_id: socket.assigns.id
       }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("request_new_card", params, socket) do
    # Send event to parent LiveView requesting a new card
    send(
      self(),
      {:request_new_card,
       %{
         component_id: socket.assigns.id,
         count: Map.get(params, "count")
       }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_answer", %{"item_id" => item_id}, socket) do
    # Toggle the answer visibility for the specific card using JavaScript
    {:noreply,
     push_event(socket, "toggle_answer", %{
       deck_id: socket.assigns.deck_id,
       item_id: item_id
     })}
  end

  @impl true
  def handle_event("show_answer", _params, socket) do
    # Fallback for when item_id is not provided - show answer for top card
    {:noreply,
     push_event(socket, "toggle_top_card_answer", %{
       deck_id: socket.assigns.deck_id
     })}
  end

  @impl true
  def handle_event("programmatic_swipe", %{"direction" => direction}, socket) do
    # Allow server-driven programmatic swipes (useful for tests and a11y)
    {:noreply,
     push_event(socket, "programmatic_swipe", %{
       deck_id: socket.assigns.deck_id,
       direction: direction
     })}
  end

  # New function to add a card via push_event
  def add_card(socket, new_card) do
    push_event(socket, "add_card", %{
      deck_id: socket.assigns.deck_id,
      card: new_card
    })
  end

  # New function to update deck data via push_event
  def update_deck_data(socket, new_items) do
    push_event(socket, "update_deck_data", %{
      deck_id: socket.assigns.deck_id,
      items: new_items
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="swipe-deck-container">
      <!-- Swipe Deck -->
      <div
        id={@deck_id}
        phx-hook="SwipeDeck"
        phx-target={@myself}
        data-items={Jason.encode!(@items)}
        data-directions={Jason.encode!(@directions)}
        data-keyboard={to_string(@keyboard)}
        data-haptics={to_string(@haptics)}
        data-stack-size={to_string(@stack_size)}
        class="relative w-full h-96 mb-10 max-w-md mx-auto"
      >
        <!-- Flashcard Template -->
        <template data-template="flashcard" class="group">
          <div class="absolute inset-0 card bg-base-200 shadow-xl">
            <!-- Swipe direction indicators -->
            <div class="swipe-indicators z-index-10">
              <div class="swipe-indicator group-[.swipe-deck-left]:opacity-100 absolute left-4 top-1/2 -translate-y-1/2 opacity-0 transition-opacity">
                <div class="bg-error text-error-content px-3 py-2 rounded-lg font-bold text-sm rotate-12">
                  AGAIN
                </div>
              </div>
              <div class="swipe-indicator group-[.swipe-deck-right]:opacity-100 absolute right-4 top-1/2 -translate-y-1/2 opacity-0 transition-opacity">
                <div class="bg-success text-success-content px-3 py-2 rounded-lg font-bold text-sm -rotate-12">
                  GOOD
                </div>
              </div>
              <div class="swipe-indicator group-[.swipe-deck-up]:opacity-100 absolute top-4 left-1/2 -translate-x-1/2 opacity-0 transition-opacity">
                <div class="bg-info text-info-content px-3 py-2 rounded-lg font-bold text-sm">
                  EASY
                </div>
              </div>
              <div class="swipe-indicator group-[.swipe-deck-down]:opacity-100 absolute bottom-4 left-1/2 -translate-x-1/2 opacity-0 transition-opacity">
                <div class="bg-warning text-warning-content px-3 py-2 rounded-lg font-bold text-sm">
                  HARD
                </div>
              </div>
            </div>
            <div class="card-body h-full flex flex-col">
              
    <!-- Front side -->
              <div class="flex-1 flex flex-col justify-center">
                <div class="text-sm opacity-70 mb-2">Term</div>
                <h3 class="text-2xl font-semibold mb-4" data-field="front"></h3>
                
    <!-- Back side (initially hidden) -->
                <div class="swipe-card-back" style="opacity: 0;">
                  <div class="text-sm opacity-70 mb-2">Definition</div>
                  <div class="" data-field="back"></div>
                </div>
              </div>
              
    <!-- Reveal button -->
              <div class="mt-auto">
                <button
                  class="btn btn-primary btn-sm swipe-reveal-btn"
                  phx-click="show_answer"
                  phx-target={@myself}
                  phx-value-item_id=""
                >
                  Show Answer
                </button>
              </div>
            </div>
          </div>
        </template>
      </div>
      
    <!-- Instructions -->
      <div class="text-center text-sm opacity-70 mb-4">
        <div class="flex justify-center gap-4 mb-2">
          <span>← Again</span>
          <span>↓ Hard</span>
          <span>↑ Easy</span>
          <span>→ Good</span>
        </div>
        <div>Swipe or use arrow keys to grade • Space to reveal answer</div>
      </div>
      
    <!-- Action buttons (fallback for non-swipe users) -->
      <div class="flex justify-center gap-2">
        <button
          class="btn btn-sm"
          phx-click="programmatic_swipe"
          phx-value-direction="left"
          phx-target={@myself}
        >
          Again
        </button>
        <button
          class="btn btn-sm"
          phx-click="programmatic_swipe"
          phx-value-direction="down"
          phx-target={@myself}
        >
          Hard
        </button>
        <button
          class="btn btn-sm btn-primary"
          phx-click="programmatic_swipe"
          phx-value-direction="right"
          phx-target={@myself}
        >
          Good
        </button>
        <button
          class="btn btn-sm"
          phx-click="programmatic_swipe"
          phx-value-direction="up"
          phx-target={@myself}
        >
          Easy
        </button>
      </div>
    </div>
    """
  end
end
