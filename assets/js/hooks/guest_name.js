/**
 * @type {import("phoenix_live_view").Hook}
 */
export const GuestName = {
  mounted() {
    try {
      const stored = localStorage.getItem("fw_duel_name");
      if (stored && stored.trim().length > 0) {
        this.pushEvent("guest_name_loaded", { name: stored });
      }
    } catch (_e) {}

    // Also store on submit just in case
    this.el.addEventListener("submit", (e) => {
      const inp = this.el.querySelector("input[name='name[name]']");
      const val = inp && inp.value ? inp.value.trim() : "";
      try {
        if (val.length > 0) localStorage.setItem("fw_duel_name", val);
      } catch (_e) {}
    });

    this.handleEvent("store_guest_name", ({ name }) => {
      try {
        if (name && name.trim().length > 0)
          localStorage.setItem("fw_duel_name", name.trim());
      } catch (_e) {}
    });
  },
};
