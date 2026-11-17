(() => {
  "use strict";
  if (window.researchWorkbenchInstalled) return;
  window.researchWorkbenchInstalled = true;
  const send = (name, value) => {
    if (window.Shiny) window.Shiny.setInputValue(name, value, { priority: "event" });
  };
  document.addEventListener("click", (event) => {
    if (!event.target.closest("#start_presentation")) return;
    const stage = document.getElementById("presentationStage");
    if (!stage) return;
    send("presentation_started", Date.now());
    stage.focus();
    if (stage.requestFullscreen) stage.requestFullscreen().catch(() => {
      // Projection still works in the page when the browser denies fullscreen.
    });
  });
  document.addEventListener("keydown", (event) => {
    if (event.target.closest("input,textarea,select,[contenteditable='true']")) return;
    const stage = document.getElementById("presentationStage");
    if (!stage || !stage.getClientRects().length) return;
    const keys = { ArrowRight: 1, PageDown: 1, ArrowLeft: -1, PageUp: -1 };
    if (Object.hasOwn(keys, event.key)) {
      event.preventDefault();
      send("slide_key", { direction: keys[event.key], at: Date.now() });
    }
    if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      send("slide_jump", { slide: event.key === "Home" ? 1 : 12, at: Date.now() });
    }
  });
  document.addEventListener("fullscreenchange", () => {
    if (!document.fullscreenElement) send("presentation_exited", Date.now());
  });
  document.addEventListener("shiny:connected", () => {
    window.Shiny.addCustomMessageHandler("teacher-controls", (state) => {
      for (const [id, enabled] of Object.entries(state)) {
        const control = document.getElementById(id);
        if (control) control.disabled = !enabled;
      }
    });
    window.Shiny.addCustomMessageHandler("teacher-exit-fullscreen", () => {
      if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    });
  });
})();
