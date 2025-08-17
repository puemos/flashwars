/**
 * @type {import("phoenix_live_view").Hook}
 */
export const MatchingDnD = {
  mounted() {
    this.install();
  },
  updated() {
    this.install();
  },
  install() {
    const root = this.el;
    const disabled = root.dataset.disabled === "true";

    const rebind = (el, fn) => {
      const clone = el.cloneNode(true);
      el.parentNode.replaceChild(clone, el);
      fn(clone);
      return clone;
    };

    // Draggable terms (left)
    root.querySelectorAll('[data-side="left"] [data-index]').forEach((node) => {
      const used = node.classList.contains("btn-ghost");
      if (disabled || used) return;
      rebind(node, (el) => {
        el.setAttribute("draggable", "true");
        el.addEventListener("dragstart", (e) => {
          e.dataTransfer.effectAllowed = "link";
          e.dataTransfer.setData(
            "application/json",
            JSON.stringify({
              side: "left",
              index: parseInt(el.dataset.index, 10),
            }),
          );
          el.classList.add("ring-2", "ring-offset-2");
          el.setAttribute("aria-grabbed", "true");
        });
        el.addEventListener("dragend", () => {
          el.classList.remove("ring-2", "ring-offset-2");
          el.setAttribute("aria-grabbed", "false");
        });
      });
    });

    // Droppable definitions (right)
    root
      .querySelectorAll('[data-side="right"] [data-index]')
      .forEach((node) => {
        const used = node.classList.contains("btn-ghost");
        if (disabled || used) return;
        rebind(node, (el) => {
          el.addEventListener("dragover", (e) => {
            e.preventDefault();
            e.dataTransfer.dropEffect = "link";
            el.classList.add("outline", "outline-2", "outline-dashed");
          });
          el.addEventListener("dragleave", () => {
            el.classList.remove("outline", "outline-2", "outline-dashed");
          });
          el.addEventListener("drop", (e) => {
            e.preventDefault();
            el.classList.remove("outline", "outline-2", "outline-dashed");
            let payload;
            try {
              payload = JSON.parse(e.dataTransfer.getData("application/json"));
            } catch (_) {
              return;
            }
            if (payload && payload.side === "left") {
              const left_index = parseInt(payload.index, 10);
              const right_index = parseInt(el.dataset.index, 10);
              this.pushEvent("match_drop", { left_index, right_index });
            }
          });
        });
      });
  },
};
