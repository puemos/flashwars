// Generic hook: attach to any element to animate numeric content to a target value
// Usage: <span phx-hook="CountTo" data-count-to="150" data-count-ms="800" data-from="0"></span>
export const CountTo = {
  mounted() { this.run(); },
  updated() { this.run(); },
  run() {
    const el = this.el;
    const target = Number(el.getAttribute("data-count-to")) || 0;
    const duration = Number(el.getAttribute("data-count-ms")) || 700;
    const fromAttr = el.getAttribute("data-from");
    const from = fromAttr != null ? Number(fromAttr) : (Number(el.textContent) || 0);
    const diff = target - from;
    if (diff === 0) return;
    const start = performance.now();

    const step = (now) => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
      const val = Math.round(from + diff * eased);
      el.textContent = val;
      if (t < 1) requestAnimationFrame(step);
    };

    requestAnimationFrame(step);
  },
};

