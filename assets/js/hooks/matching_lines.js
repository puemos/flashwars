// hooks/matching_lines.js
const COLOR = {
  user: "#9ca3af",
  ok: "#22c55e",
  bad: "#ef4444",
  label: "#6b7280",
};

function isScrollable(el) {
  if (!el || el === document.body) return false;
  const s = getComputedStyle(el);
  return /(auto|scroll)/.test(s.overflow + s.overflowX + s.overflowY);
}
function scrollParents(el) {
  const out = [];
  let n = el?.parentElement;
  while (n && n !== document.body) {
    if (isScrollable(n)) out.push(n);
    n = n.parentElement;
  }
  out.push(window);
  return out;
}

export const MatchingLines = {
  mounted() {
    this.rootEl = document.getElementById(this.el.dataset.rootId);
    if (!this.rootEl) return;

    // debounced draw
    this._raf = null;
    this._drawing = false;
    this.scheduleDraw = () => {
      if (this._raf) return;
      this._raf = requestAnimationFrame(() => {
        this._raf = null;
        this.draw();
      });
    };

    // listeners
    this._onResize = () => this.scheduleDraw();
    this._onScroll = () => this.scheduleDraw();

    this.resizeObs = new ResizeObserver(this._onResize);
    this.resizeObs.observe(this.rootEl);

    this.scrollSubs = scrollParents(this.rootEl).map((t) => {
      t.addEventListener("scroll", this._onScroll, { passive: true });
      return t;
    });

    this.scheduleDraw();
  },

  updated() {
    this.scheduleDraw();
  },

  destroyed() {
    this.resizeObs?.disconnect();
    this.scrollSubs?.forEach((t) =>
      t.removeEventListener?.("scroll", this._onScroll),
    );
    if (this._raf) cancelAnimationFrame(this._raf);
  },

  parseLines() {
    try {
      return JSON.parse(this.el.dataset.lines || "[]");
    } catch {
      return [];
    }
  },

  ensureViewport(rect) {
    const w = Math.max(1, Math.round(rect.width));
    const h = Math.max(1, Math.round(rect.height));
    const vb = `0 0 ${w} ${h}`;
    if (
      this.el.getAttribute("viewBox") !== vb ||
      this.el.getAttribute("width") !== String(w) ||
      this.el.getAttribute("height") !== String(h)
    ) {
      this.el.setAttribute("viewBox", vb);
      this.el.setAttribute("preserveAspectRatio", "none");
      this.el.setAttribute("width", String(w));
      this.el.setAttribute("height", String(h));
      this.el.style.width = w + "px";
      this.el.style.height = h + "px";
      this.el.style.pointerEvents = "none";
    }
  },

  clear() {
    while (this.el.firstChild) this.el.removeChild(this.el.firstChild);
  },

  lineColor(s) {
    return s === "ok" ? COLOR.ok : s === "bad" ? COLOR.bad : COLOR.user;
  },

  draw() {
    if (this._drawing) return;
    this._drawing = true;
    try {
      if (!this.rootEl) return;

      const rect = this.rootEl.getBoundingClientRect();
      if (rect.width < 1 || rect.height < 1) {
        this.scheduleDraw();
        return;
      }

      this.ensureViewport(rect);
      this.clear();

      const toLocal = (x, y) => ({ x: x - rect.left, y: y - rect.top });
      const lines = this.parseLines();
      if (!lines.length) return;

      for (let idx = 0; idx < lines.length; idx++) {
        const p = lines[idx];
        const l = document.getElementById(`${this.rootEl.id}-l-${p.l}`);
        const r = document.getElementById(`${this.rootEl.id}-r-${p.r}`);
        if (!l || !r) continue;

        const lr = l.getBoundingClientRect();
        const rr = r.getBoundingClientRect();
        const { x: x1, y: y1 } = toLocal(lr.right, lr.top + lr.height / 2);
        const { x: x2, y: y2 } = toLocal(rr.left, rr.top + rr.height / 2);

        const dx = Math.max(24, Math.min(160, (x2 - x1) * 0.33));
        const d = `M ${x1},${y1} C ${x1 + dx},${y1} ${x2 - dx},${y2} ${x2},${y2}`;

        const path = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "path",
        );
        path.setAttribute("d", d);
        path.setAttribute("fill", "none");
        path.setAttribute("stroke", this.lineColor(p.status));
        path.setAttribute("stroke-width", "2");
        path.setAttribute("stroke-linecap", "round");
        path.setAttribute("vector-effect", "non-scaling-stroke");
        path.setAttribute("opacity", p.status === "user" ? "0.6" : "0.9");
        path.style.pointerEvents = "none";
        this.el.appendChild(path);
      }
    } finally {
      this._drawing = false;
    }
  },
};
