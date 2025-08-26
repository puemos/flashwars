// Generic hook: apply a brief pop-in entrance animation
// Usage: <div phx-hook="PopIn" class="opacity-0 translate-y-6"> ... </div>
export const PopIn = {
  mounted() { this.pop(); },
  updated() { this.pop(); },
  pop() {
    const el = this.el;
    el.classList.remove("opacity-0", "translate-y-6");
    el.classList.add("animate-pop");
    // Remove the class after animation so it can re-trigger later if needed
    setTimeout(() => el.classList.remove("animate-pop"), 600);
  },
};

