/**
 * Phoenix LiveView SwipeDeck Hook
 * Event-driven implementation
 */
export const SwipeDeckHook = {
  mounted() {
    // Parse initial configuration from data attributes
    const items = JSON.parse(this.el.dataset.items || "[]");
    const directions = JSON.parse(
      this.el.dataset.directions || '["left", "right"]',
    );
    const keyboard = this.el.dataset.keyboard !== "false";
    const haptics = this.el.dataset.haptics !== "false";
    const stackSize = parseInt(this.el.dataset.stackSize || "3");

    // Initialize deck state
    this.data = [...items];
    this.cards = [];
    this.currentIndex = 0;
    this.swipeCount = 0;
    this.stackSize = Math.max(1, stackSize);
    this.directions = directions;
    this.thresholds = { distance: 100, velocity: 0.5 };
    this.keyboard = keyboard;
    this.haptics = haptics;

    // Setup
    this.el.classList.add("swipe-deck");
    this.setupKeyboard();
    this.setupEventListeners();
    this.render();
    this.updateLayout();
  },

  destroyed() {
    if (this.keyboardHandler) {
      document.removeEventListener("keydown", this.keyboardHandler);
    }
    this.cards.forEach((card) => this.removeCardListeners(card));
  },

  // Setup event listeners for LiveView events
  setupEventListeners() {
    // Listen for programmatic swipes from LiveView
    this.el.addEventListener("swipe-deck:programmatic", (e) => {
      this.swipe(e.detail.direction);
    });

    // Listen for add card events from LiveView
    this.handleEvent("add_card", (payload) => {
      this.addCard(payload.card);
    });

    // Listen for add multiple cards events from LiveView
    this.handleEvent("add_cards", (payload) => {
      const cards = payload.cards || [];
      if (Array.isArray(cards)) this.addCards(cards);
    });

    // Listen for programmatic swipes from LiveView push_event
    this.handleEvent("programmatic_swipe", (payload) => {
      const direction = payload && payload.direction;
      if (direction) this.swipe(direction);
    });

    // Listen for update deck data events from LiveView
    this.handleEvent("update_deck_data", (payload) => {
      this.setData(payload.items);
    });
  },

  // Public methods
  setData(newData) {
    this.data = [...newData];
    this.currentIndex = 0;
    this.cards.forEach((card) => card.remove());
    this.cards = [];
    this.render();
    this.updateLayout();
  },

  addCard(cardData) {
    // Add new card to data
    this.data.push(cardData);

    // If we need more cards in the stack, render them
    const neededCards = Math.min(
      this.stackSize,
      this.data.length - this.currentIndex,
    );

    if (this.cards.length < neededCards) {
      const dataIndex = this.currentIndex + this.cards.length;
      if (dataIndex < this.data.length) {
        const item = this.data[dataIndex];
        const card = this.createCard(item, dataIndex);
        this.el.appendChild(card);
        this.cards.unshift(card); // Add to beginning (bottom of stack)
        this.updateLayout();
      }
    }
  },

  addCards(cards) {
    if (!Array.isArray(cards) || cards.length === 0) return;
    // Append cards to data in order
    for (const c of cards) this.data.push(c);
    // Ensure stack is topped up
    const neededCards = Math.min(
      this.stackSize,
      this.data.length - this.currentIndex,
    );
    while (this.cards.length < neededCards) {
      const dataIndex = this.currentIndex + this.cards.length;
      if (dataIndex >= this.data.length) break;
      const item = this.data[dataIndex];
      const card = this.createCard(item, dataIndex);
      this.el.appendChild(card);
      this.cards.unshift(card);
    }
    this.updateLayout();
  },

  swipe(direction) {
    if (!this.directions.includes(direction)) return;
    const topCard = this.getTopCard();
    if (!topCard) {
      // Request new card from LiveView
      const count = this.stackSize;
      this.pushEventTo(this.el, "request_new_card", { count });
      return;
    }
    this.animateSwipe(topCard, direction, true);
  },

  getState() {
    return {
      currentIndex: this.currentIndex,
      remainingCount: Math.max(0, this.data.length - this.currentIndex),
      swipeCount: this.swipeCount,
      totalCount: this.data.length,
    };
  },

  // Private methods
  setupKeyboard() {
    if (!this.keyboard) return;

    this.keyboardHandler = (e) => {
      const activeElement = document.activeElement;
      if (
        activeElement &&
        (activeElement.tagName === "INPUT" ||
          activeElement.tagName === "TEXTAREA" ||
          activeElement.isContentEditable)
      )
        return;

      const keyMap = {
        ArrowLeft: "left",
        ArrowRight: "right",
        ArrowUp: "up",
        ArrowDown: "down",
      };

      if (keyMap[e.key]) {
        e.preventDefault();
        this.swipe(keyMap[e.key]);
      } else if (e.code === "Space") {
        e.preventDefault();
        this.toggleTopCardAnswer();
      }
    };

    document.addEventListener("keydown", this.keyboardHandler);
  },

  render() {
    const neededCards = Math.min(
      this.stackSize,
      this.data.length - this.currentIndex,
    );

    // Remove excess cards
    while (this.cards.length > neededCards) {
      const card = this.cards.shift(); // Remove from beginning (bottom of stack)
      this.removeCardListeners(card);
      card.remove();
    }

    // Add missing cards
    for (let i = this.cards.length; i < neededCards; i++) {
      const dataIndex = this.currentIndex + i;
      if (dataIndex >= this.data.length) {
        // Request new card from LiveView
        const count = Math.max(1, this.stackSize - this.cards.length);
        this.pushEventTo(this.el, "request_new_card", { count });
        break;
      }

      const item = this.data[dataIndex];
      const card = this.createCard(item, dataIndex);
      this.el.appendChild(card);
      this.cards.unshift(card); // Add to beginning (bottom of stack)
    }
  },

  createCard(item, dataIndex) {
    // Find template
    const template = this.el.querySelector(
      `template[data-template="${item.type}"]`,
    );
    if (!template)
      throw new Error(`No template found for item type: ${item.type}`);

    // Clone template
    const card = document.createElement("div");
    card.classList.add("swipe-card", "group");
    card.dataset.index = dataIndex;

    const content = template.content.firstElementChild.cloneNode(true);
    card.appendChild(content);

    // Populate fields
    card.querySelectorAll("[data-field]").forEach((fieldEl) => {
      const fieldName = fieldEl.getAttribute("data-field");
      const fieldValue = item[fieldName];
      if (fieldValue !== undefined) {
        if (fieldEl.tagName === "IMG") {
          fieldEl.src = fieldValue;
          fieldEl.alt = item.name || fieldValue;
        } else {
          fieldEl.textContent = fieldValue;
        }
      }
    });

    // Setup reveal button
    const revealBtn = card.querySelector(".swipe-reveal-btn");
    if (revealBtn) {
      revealBtn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.toggleCardAnswer(card);
      });
      revealBtn.addEventListener("pointerdown", (e) => e.stopPropagation());
    }

    // Store data
    card._swipeData = { item, dataIndex };

    // Setup drag
    this.attachDragListeners(card);
    return card;
  },

  attachDragListeners(card) {
    let isDragging = false;
    let startX = 0,
      startY = 0;
    let currentX = 0,
      currentY = 0;
    let velocityTracker = [];

    const handlePointerDown = (e) => {
      if (card !== this.getTopCard() || e.button !== 0) return;

      // Skip interactive elements
      let target = e.target;
      while (target && target !== card) {
        if (
          (target.hasAttribute && target.hasAttribute("data-no-drag")) ||
          target.tagName === "BUTTON" ||
          target.classList.contains("btn")
        ) {
          return;
        }
        target = target.parentElement;
      }

      isDragging = true;
      startX = e.clientX;
      startY = e.clientY;
      velocityTracker = [{ x: startX, y: startY, time: performance.now() }];

      card.setPointerCapture(e.pointerId);
      card.style.transition = "none";
      document.body.style.userSelect = "none";
    };

    const handlePointerMove = (e) => {
      if (!isDragging) return;

      currentX = e.clientX - startX;
      currentY = e.clientY - startY;

      // Track velocity
      const now = performance.now();
      velocityTracker.push({ x: e.clientX, y: e.clientY, time: now });
      if (velocityTracker.length > 5) velocityTracker.shift();

      // Apply transform
      const rotation = this.calculateRotation(currentX, currentY);
      card.style.transform = `translate3d(${currentX}px, ${currentY}px, 0) rotate(${rotation}deg)`;

      // Update indicators
      this.updateDirectionIndicators(card, currentX, currentY);
    };

    const handlePointerEnd = (e) => {
      if (!isDragging) return;
      isDragging = false;

      document.body.style.userSelect = "";
      this.clearDirectionIndicators(card);

      const velocity = this.calculateVelocity(velocityTracker);
      const direction = this.getSwipeDirection(currentX, currentY);
      const distance = Math.sqrt(currentX * currentX + currentY * currentY);

      const shouldSwipe =
        distance > this.thresholds.distance ||
        velocity > this.thresholds.velocity;

      if (shouldSwipe && direction && this.directions.includes(direction)) {
        this.animateSwipe(card, direction, false);
      } else {
        this.snapBack(card);
      }
    };

    card.addEventListener("pointerdown", handlePointerDown);
    card.addEventListener("pointermove", handlePointerMove);
    card.addEventListener("lostpointercapture", handlePointerEnd);

    card._listeners = {
      handlePointerDown,
      handlePointerMove,
      handlePointerEnd,
    };
  },

  removeCardListeners(card) {
    if (card._listeners) {
      const { handlePointerDown, handlePointerMove, handlePointerEnd } =
        card._listeners;
      card.removeEventListener("pointerdown", handlePointerDown);
      card.removeEventListener("pointermove", handlePointerMove);
      card.removeEventListener("lostpointercapture", handlePointerEnd);
    }
  },

  calculateRotation(x, y) {
    const maxRotation = 15;
    const distance = Math.sqrt(x * x + y * y);
    const normalizedDistance = Math.min(distance / 200, 1);
    return (x / Math.abs(x || 1)) * normalizedDistance * maxRotation;
  },

  calculateVelocity(tracker) {
    if (tracker.length < 2) return 0;
    const recent = tracker.slice(-3);
    const first = recent[0];
    const last = recent[recent.length - 1];
    const deltaTime = Math.max(1, last.time - first.time);
    const deltaX = last.x - first.x;
    const deltaY = last.y - first.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY) / deltaTime;
  },

  getSwipeDirection(x, y) {
    const absX = Math.abs(x);
    const absY = Math.abs(y);
    if (absX > absY) {
      return x > 0 ? "right" : "left";
    } else {
      return y > 0 ? "down" : "up";
    }
  },

  updateDirectionIndicators(card, x, y) {
    const direction = this.getSwipeDirection(x, y);
    const distance = Math.sqrt(x * x + y * y);
    const active = distance > 20 && this.directions.includes(direction);

    this.clearDirectionIndicators(card);

    if (active) {
      this.updateContainerDragClasses(direction, true, card);
    }
  },

  clearDirectionIndicators(card) {
    this.updateContainerDragClasses(null, false, card);
  },

  updateContainerDragClasses(direction, active, card) {
    const dirs = ["left", "right", "up", "down"];
    card.classList.toggle("swipe-deck-dragging", !!active);
    for (const d of dirs) {
      const cls = `swipe-deck-${d}`;
      if (active && d === direction) {
        card.classList.add(cls);
      } else {
        card.classList.remove(cls);
      }
    }
  },

  animateSwipe(card, direction, programmatic) {
    const { item, dataIndex } = card._swipeData;

    // Calculate exit position
    const containerRect = this.el.getBoundingClientRect();
    const multiplier = 1.5;
    let targetX = 0,
      targetY = 0;

    switch (direction) {
      case "left":
        targetX = -containerRect.width * multiplier;
        break;
      case "right":
        targetX = containerRect.width * multiplier;
        break;
      case "up":
        targetY = -containerRect.height * multiplier;
        break;
      case "down":
        targetY = containerRect.height * multiplier;
        break;
    }

    // Animate out
    if (programmatic) {
      this.updateContainerDragClasses(direction, true, card);
    }

    card.style.transition =
      "transform 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94)";
    card.style.transform = `translate3d(${targetX}px, ${targetY}px, 0) rotate(${this.calculateRotation(targetX, targetY)}deg)`;

    // Haptic feedback
    if (this.haptics && !programmatic && "vibrate" in navigator) {
      try {
        navigator.vibrate(20);
      } catch (e) {}
    }

    // Handle completion
    const handleComplete = () => {
      this.currentIndex++;
      this.swipeCount++;

      // Remove card
      const cardIndex = this.cards.indexOf(card);
      if (cardIndex >= 0) {
        this.cards.splice(cardIndex, 1);
        this.removeCardListeners(card);
        card.remove();
      }

      // Render new cards and update layout
      this.render();
      this.updateLayout();
      this.updateContainerDragClasses(null, false, card);

      // Send to LiveView
      this.pushEventTo(this.el, "swipe", {
        direction: direction,
        item_id: item.id,
        programmatic: programmatic,
      });

      // Check if deck is empty (no more cards in stack)
      if (this.cards.length === 0) {
        this.pushEventTo(this.el, "deck_empty", {
          total_swiped: this.swipeCount,
        });
      }
    };

    card.addEventListener("transitionend", handleComplete, { once: true });
  },

  snapBack(card) {
    card.style.transition =
      "transform 0.2s cubic-bezier(0.25, 0.46, 0.45, 0.94)";
    card.style.transform = "translate3d(0, 0, 0) rotate(0deg)";
  },

  updateLayout() {
    this.cards.forEach((card, index) => {
      const stackIndex = this.cards.length - 1 - index; // 0 is top card
      const scale = 1 - stackIndex * 0.03;
      const translateY = stackIndex * 8;
      const opacity = stackIndex > 2 ? 0 : 1;

      card.style.transition = "transform 0.2s ease-out";
      card.style.transform = `translate3d(0, ${translateY}px, 0) scale(${scale})`;
      card.style.zIndex = 100 + index;
      card.style.opacity = opacity;
    });
  },

  getTopCard() {
    return this.cards[this.cards.length - 1] || null;
  },

  // Answer toggle methods
  toggleTopCardAnswer() {
    const topCard = this.getTopCard();
    if (topCard) this.toggleCardAnswer(topCard);
  },

  toggleCardAnswer(card) {
    const backElement = card.querySelector(".swipe-card-back");
    const button = card.querySelector(".swipe-reveal-btn");
    if (!backElement || !button) return;

    // Ensure a transition is present
    if (!backElement.style.transition) {
      backElement.style.transition =
        "opacity var(--swipe-duration-fast, 150ms) ease-out";
    }

    const isVisible =
      backElement.dataset.visible === "true" ||
      getComputedStyle(backElement).opacity === "1";

    if (isVisible) {
      backElement.style.opacity = "0";
      backElement.style.pointerEvents = "none";
      backElement.setAttribute("aria-hidden", "true");
      backElement.dataset.visible = "false";

      button.textContent = "Show Answer";
      button.classList.remove("btn-outline");
      button.classList.add("btn-primary");
    } else {
      backElement.style.opacity = "1";
      backElement.style.pointerEvents = "auto";
      backElement.setAttribute("aria-hidden", "false");
      backElement.dataset.visible = "true";

      button.textContent = "Hide Answer";
      button.classList.remove("btn-primary");
      button.classList.add("btn-outline");
    }
  },
};
