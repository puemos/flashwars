// Pushes a LiveView event after a delay
// Usage:
// <div phx-hook="AutoPush" data-push-event="start_next_round" data-delay-ms="2000"></div>
export const AutoPush = {
  mounted() {
    this.pushEvt = this.el.getAttribute("data-push-event");
    const ms = parseInt(this.el.getAttribute("data-delay-ms"), 10);
    this.delay = Number.isFinite(ms) && ms > 0 ? ms : 0;
    if (this.pushEvt && this.delay > 0) {
      this.timer = setTimeout(() => this.pushEvent(this.pushEvt, {}), this.delay);
    }
  },
  destroyed() {
    if (this.timer) clearTimeout(this.timer);
  },
};

