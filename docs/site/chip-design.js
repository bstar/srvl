"use strict";
(() => {
  const definitions = window.CHIPBUILDER_CHIPS || {};
  document.querySelectorAll("[data-chip-diagram]").forEach(figure => {
    const diagram = definitions[figure.dataset.chipDiagram];
    if (!diagram) return;
    const svg = figure.querySelector("svg");
    const canvas = figure.querySelector(".chip-canvas");
    const controls = figure.querySelector(".chip-zoom");
    const inspector = figure.querySelector(".chip-inspector");
    let zoom = 1;
    let baseWidth = Math.max(720, canvas.clientWidth);
    controls.hidden = false;

    function inspect(node) {
      const block = diagram.nodes[node.dataset.chipNode];
      if (!block) return;
      svg.querySelectorAll("[data-chip-node]").forEach(item => item.setAttribute("aria-pressed", String(item === node)));
      inspector.querySelector("strong").textContent = block.title;
      const badge = inspector.querySelector(".badge");
      badge.textContent = block.state;
      badge.className = "badge " + block.kind;
      inspector.querySelector(".chip-detail").textContent = block.detail;
      for (const port of ["inputs", "outputs", "gate"]) inspector.querySelector(`[data-port=${port}]`).textContent = block[port];
    }
    svg.addEventListener("click", event => {
      const node = event.target.closest("[data-chip-node]");
      if (node) inspect(node);
    });
    svg.addEventListener("keydown", event => {
      const node = event.target.closest("[data-chip-node]");
      if (node && ["Enter", " "].includes(event.key)) {
        event.preventDefault();
        inspect(node);
      }
    });
    controls.addEventListener("click", event => {
      const button = event.target.closest("[data-zoom]");
      if (!button) return;
      if (button.dataset.zoom === "fit") {
        baseWidth = canvas.clientWidth;
        zoom = 1;
      } else {
        zoom = Math.min(3, Math.max(0.5, zoom + (button.dataset.zoom === "in" ? 0.25 : -0.25)));
      }
      svg.style.minWidth = "0";
      svg.style.width = `${Math.round(baseWidth * zoom)}px`;
      controls.querySelector("output").textContent = `${Math.round(zoom * 100)}%`;
    });
  });
})();
