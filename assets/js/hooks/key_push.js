// Pushes a LiveView event when specific keys are pressed.
// Attaches listener to window for broad reach.
// Usage:
// <div phx-hook="KeyPush" data-push-event="start_next_round" data-keys="Enter, Space"></div>
export const KeyPush = {
  mounted() {
    this.pushEvt = this.el.getAttribute("data-push-event");
    const keysAttr = this.el.getAttribute("data-keys") || "Enter, Space";
    this.keys = keysAttr
      .split(",")
      .map((k) => k.trim().toLowerCase())
      .filter((k) => k.length > 0);
    this.onKey = (e) => {
      if (!this.pushEvt) return;
      const key = (e.key || e.code || "").toLowerCase();
      if (this.keys.includes(key)) {
        e.preventDefault();
        this.pushEvent(this.pushEvt, {});
      }
    };
    window.addEventListener("keydown", this.onKey);
  },
  destroyed() {
    window.removeEventListener("keydown", this.onKey);
  },
};

