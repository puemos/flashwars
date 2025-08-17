/**
 * @type {import("phoenix_live_view").Hook}
 */
export const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", async (e) => {
      const text = this.el.dataset.text || "";
      try {
        await navigator.clipboard.writeText(text);
        this.pushEvent("copied", { ok: true });
      } catch (_e) {
        // no-op
      }
    });
  },
};
