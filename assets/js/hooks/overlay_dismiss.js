// Generic hook: push an event when clicking the element (scrim),
// and optionally when pressing Escape.
// Usage:
//  <div phx-hook="OverlayDismiss" id="scrim" data-push-event="close_overlay"></div>
//  <div phx-hook="OverlayDismiss" id="overlay" data-push-event="close_overlay" data-on-escape="true"></div>
export const OverlayDismiss = {
  mounted() {
    this.pushEvt = this.el.getAttribute("data-push-event");
    this.onEscape = this.el.getAttribute("data-on-escape") === "true";
    this.onClick = (e) => {
      if (!this.pushEvt) return;
      // Only trigger for direct clicks on the element (avoid child clicks for scrims)
      if (e.target === this.el) this.pushEvent(this.pushEvt, {});
    };
    this.el.addEventListener("click", this.onClick);

    if (this.onEscape) {
      this.onKey = (e) => {
        const key = e.key || e.code;
        if (key && key.toLowerCase() === "escape") {
          if (this.pushEvt) this.pushEvent(this.pushEvt, {});
        }
      };
      window.addEventListener("keydown", this.onKey);
    }
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    if (this.onEscape) window.removeEventListener("keydown", this.onKey);
  },
};

