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
  // Shiny's lifecycle events are jQuery events, not native DOM events.
  // Keep controls closed until an authenticated server message enables them.
  const controlState = {
    update_publish: false, refresh_latest: false,
    load_demo: false, cancel_operation: false
  };
  let handlersInstalled = false;
  let lifecycleInstalled = false;
  const applyControls = () => {
    for (const [id, enabled] of Object.entries(controlState)) {
      const control = document.getElementById(id);
      if (control) control.disabled = enabled !== true;
    }
  };
  const resetControls = () => {
    for (const id of Object.keys(controlState)) controlState[id] = false;
    applyControls();
  };
  const installHandlers = () => {
    if (handlersInstalled || !window.Shiny ||
        typeof window.Shiny.addCustomMessageHandler !== "function") return;
    window.Shiny.addCustomMessageHandler("teacher-controls", (state) => {
      for (const id of Object.keys(controlState)) controlState[id] = state?.[id] === true;
      applyControls();
    });
    window.Shiny.addCustomMessageHandler("teacher-exit-fullscreen", () => {
      if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    });
    handlersInstalled = true;
  };
  const initialiseControls = () => {
    installHandlers();
    if (!lifecycleInstalled && window.jQuery) {
      const events = window.jQuery(document);
      events.on("shiny:connected.researchWorkbench", () => {
        resetControls();
        installHandlers();
      });
      events.on("shiny:disconnected.researchWorkbench", resetControls);
      events.on("shiny:bound.researchWorkbench", (event) => {
        if (event.target?.id === "teacher_login-user_id") resetControls();
        // The authenticated UI is inserted after the initial connection.
        if (Object.hasOwn(controlState, event.target?.id)) applyControls();
      });
      lifecycleInstalled = true;
    }
    applyControls();
  };
  initialiseControls();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialiseControls, { once: true });
  }
})();
