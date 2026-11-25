"use strict";
(() => {
  const dialog = document.getElementById("search-dialog");
  const launch = document.getElementById("search-launch");
  const input = document.getElementById("search-input");
  const results = document.getElementById("search-results");
  const status = document.getElementById("search-status");
  const index = window.SRVL_SEARCH || [];

  function textElement(tag, value, className) {
    const element = document.createElement(tag);
    element.textContent = value;
    if (className) element.className = className;
    return element;
  }

  function search() {
    const query = input.value.trim().toLowerCase();
    const terms = query.split(/\s+/).filter(Boolean);
    results.replaceChildren();
    if (!terms.length) {
      status.textContent = `Search ${index.length} project documents, including research and decision history.`;
      return;
    }
    const ranked = index.map(doc => {
      const title = (doc.title + " " + doc.label).toLowerCase();
      const summary = doc.summary.toLowerCase();
      const body = doc.text.toLowerCase();
      const all = title + " " + summary + " " + body;
      if (!terms.every(term => all.includes(term))) return null;
      const score = terms.reduce((sum, term) => sum + (title.includes(term) ? 20 : 0) + (summary.includes(term) ? 6 : 0) + (body.includes(term) ? 1 : 0), 0);
      return { doc, score };
    }).filter(Boolean).sort((a, b) => b.score - a.score || a.doc.title.localeCompare(b.doc.title));
    status.textContent = ranked.length ? `${ranked.length} matching document${ranked.length === 1 ? "" : "s"}${ranked.length > 20 ? "; showing the first 20" : ""}. Tab to a result and press Enter to open it.` : "No matching documents. Try a broader term such as CPU, SDRAM, display or timing.";
    for (const { doc } of ranked.slice(0, 20)) {
      const item = document.createElement("li");
      const link = document.createElement("a");
      link.href = doc.url;
      link.append(textElement("span", doc.title));
      const first = doc.text.toLowerCase().indexOf(terms[0]);
      const start = Math.max(0, first - 55);
      const excerpt = first < 0 ? doc.summary : (start ? "…" : "") + doc.text.slice(start, start + 190) + (start + 190 < doc.text.length ? "…" : "");
      link.append(textElement("small", `${doc.group} · ${doc.state}`));
      link.append(textElement("small", excerpt));
      item.append(link);
      results.append(item);
    }
  }

  function openSearch() {
    if (dialog.open) return;
    dialog.showModal();
    search();
    input.focus();
  }
  if (typeof dialog.showModal === "function") {
    launch.hidden = false;
    launch.addEventListener("click", openSearch);
    input.addEventListener("input", search);
    input.addEventListener("keydown", event => {
      if (event.key === "ArrowDown") {
        results.querySelector("a")?.focus();
        event.preventDefault();
      }
    });
    dialog.addEventListener("click", event => { if (event.target === dialog) dialog.close(); });
    document.addEventListener("keydown", event => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        openSearch();
      }
    });
  }

  const menu = document.getElementById("menu-toggle");
  const sidebar = document.getElementById("sidebar");
  menu.hidden = false;
  function closeMenu() {
    sidebar.classList.remove("is-open");
    menu.setAttribute("aria-expanded", "false");
  }
  menu.addEventListener("click", () => {
    const open = !sidebar.classList.contains("is-open");
    sidebar.classList.toggle("is-open", open);
    menu.setAttribute("aria-expanded", String(open));
  });
  document.addEventListener("keydown", event => { if (event.key === "Escape") closeMenu(); });
  document.addEventListener("click", event => { if (!sidebar.contains(event.target) && !menu.contains(event.target)) closeMenu(); });

  const filters = document.querySelector(".record-tools");
  if (filters) {
    filters.hidden = false;
    filters.addEventListener("click", event => {
      const button = event.target.closest("[data-filter]");
      if (!button) return;
      const state = button.dataset.filter;
      filters.querySelectorAll("button").forEach(item => item.setAttribute("aria-pressed", String(item === button)));
      let visible = 0;
      document.querySelectorAll(".record-card").forEach(card => {
        card.hidden = state !== "All" && card.dataset.state !== state;
        if (!card.hidden) visible++;
      });
      document.getElementById("record-count").textContent = `${visible} ${state.toLowerCase()} decision records shown.`;
    });
  }

  const architecture = document.querySelector(".architecture");
  if (!architecture) return;
  const configs = {
    legacy: {
      boundary: "PORTABLE FPGA LOGIC · ORIGINAL DIAGNOSTICS VERIFIED IN SOFTWARE",
      caption: "Logical audiovisual integration passes. The complete board image, physical timing and commercial-game acceptance remain open.",
      blocks: {
        cpu: ["Lynx CPU", "Original instruction & bus behavior", "Reused from the pinned upstream Lynx implementation. Keep it inside the FPGA for the first Tang port, as accepted by the owner. Diagnostic execution and core-only routing passed; complete CPU/interrupt/timing equivalence and commercial-game tests remain ahead."],
        graphics: ["Suzy + Mikey", "Graphics, math, audio, timers & DMA", "Reused original-console logic: Suzy draws/scales sprites and performs arithmetic; Mikey handles display DMA, timers and sound. These blocks form compatibility mode. They are not our proposed enhanced graphics engines."],
        ram: ["64 KiB work RAM", "Local memory; audited RAM adapter", "The original work RAM stays on-chip to preserve its access behavior. Our adapter passed 23,931 defined observations against the Intel RAM model. Undefined mixed-port collisions were excluded. The full design still needs primitive and physical acceptance."],
        memory: ["8 MiB ×32 SDRAM", "Cartridge & RGB presentation storage", "Existing packaged memory, controlled by original project RTL. Command-model checks cover initialization, refresh, byte lanes and reset. The real console, capture, round-robin arbiter and line reader pass integration checks; physical memory timing and enhanced drawing workloads remain open."],
        display: ["Display + audio output", "RGB and I2S pass; physical output open", "Complete captured frames produce exact 2x RGB through independent-clock line buffers. Actual Mikey samples pass signed filtering, coherent stereo transfer and pin-decoded I2S. Video serialization, final filter fidelity, physical clocks and the backlit panel still need qualification."],
        input: ["Loading + controls", "USB UART bench interface", "The actual ASCII/CRC UART loader validates complete-image commit and drives held/released buttons. Original cold/warm audiovisual diagnostics pass through it. The board debugger transports data; games execute on the console CPU. Self-contained storage and direct handheld controls remain ahead."]
      }
    },
    native: {
      boundary: "SIMULATED HDL MACHINE · WORKING PROTOTYPE",
      caption: "This configuration is software verified. It is not the existing MiSTer bring-up RBF or a Tang board image.",
      blocks: {
        cpu: ["Patched R65C02", "Pinned Jens Gutschmidt CPU", "Reused CPU source translated through GHDL. Our corrections and independent functional/directed tests are documented. This is a different CPU implementation from the one inside the upstream Lynx core."],
        graphics: ["Project peripherals", "Tiles, 8 sprites, timers & 2 voices", "Original HDL implements the working game's tile graphics, eight fixed 16×16 sprite slots, palette, IRQ/input, frame wait, millisecond scoring and two audio voices. General sprite scaling, eight-plane parallax and 3D are not implemented here."],
        ram: ["8 KiB RAM + 32 KiB ROM", "Temporary native memory map", "The original assembly ROM contains all Circuit Courier gameplay. Local memories and MMIO use the documented temporary map. The simulator runs at 6.288 MHz with a 400×262 raster for 320×204 active pixels at 60 Hz."],
        memory: ["Simulation storage", "HDL memories; no SDRAM controller", "The current native prototype does not validate a real external SDRAM interface. Future memory latency and CPU stalling need explicit adapters and tests. Passing the game in simulation cannot establish their correctness."],
        display: ["SDL frontend", "Displays HDL pixels; plays samples", "The desktop frontend presents the hardware's 320×204 output and digital stereo samples. It contains no production game renderer or game rules. Functional/equivalence checks passed; physical panel or amplifier quality is outside those checks."],
        input: ["Original game + controls", "ca65 ROM and host input events", "Circuit Courier is an original CPU-executed manual-movement maze game with four circuits, two-to-five guards, cards, a jam pulse and millisecond scores. Host SDL events become console button bits."]
      }
    },
    enhanced: {
      boundary: "PROPOSED ENHANCED FPGA CONFIGURATION",
      caption: "Performance targets require a fresh Tang resource and bandwidth budget. No enhanced-engine fit or timing signoff exists.",
      blocks: {
        cpu: ["65C02 orchestrator", "Scene/game setup; bounded bus", "A 65C02-family CPU remains the intended game processor. Its final enhanced clock, cache/stall adapter and resource allocation need validation on the selected board. The earlier 20.1216 MHz ECP5 target is historical, not a verified Tang clock."],
        graphics: ["Original effects engines", "Scaled blitter, layers & flat triangles", "Planned project HDL offloads sprite scaling, parallax composition and basic 3D. Initial 3D uses fixed-point math assistance, CPU geometry setup/painter ordering and hardware screen-space flat triangles. Textures, Z buffering and alpha are later extensions."],
        ram: ["Local caches + buffers", "Resource budget still open", "Allocate block RAM for CPU data, scanout and bounded queues after full synthesis. Eight layers and 256 resident descriptors are earlier ambitions, not a simultaneous-scene performance guarantee on Tang."],
        memory: ["Shared graphics memory", "Measured service must define limits", "The scheduler must serve scanout, drawing and CPU traffic with explicit backpressure and complete-frame fences. The old x16 ECP5 64 MB/s useful target cannot be transplanted to the Tang x32 design without measurements."],
        display: ["320 × 204 / 60 fps", "Backlit color panel; exact legacy scaling", "The enhanced rendering target stays 320×204 with 60 fps under defined workloads. Choose a physical panel after motion, refresh, power, orientation and sourcing checks. Integer scaling and borders preserve the logical image."],
        input: ["Original SDK + game format", "Registers and command ABI pending", "Preserve existing regressions while defining a small bounded command/register interface for new engines. Self-contained boot/storage, direct controls and the product SDK remain decisions to settle before final handheld integration."]
      }
    }
  };
  let current = "legacy";
  const detail = document.getElementById("diagram-detail");
  architecture.querySelector(".mode-tabs").hidden = false;
  function selectComponent(key) {
    const block = configs[current].blocks[key];
    architecture.querySelectorAll("[data-component]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.component === key)));
    detail.replaceChildren(textElement("strong", block[0]), document.createTextNode(block[2]));
  }
  architecture.addEventListener("click", event => {
    const mode = event.target.closest("[data-mode]");
    if (mode) {
      current = mode.dataset.mode;
      architecture.querySelectorAll("[data-mode]").forEach(button => button.setAttribute("aria-pressed", String(button === mode)));
      document.getElementById("boundary-label").textContent = configs[current].boundary;
      document.getElementById("diagram-caption").textContent = configs[current].caption;
      architecture.querySelectorAll("[data-component]").forEach(button => {
        const block = configs[current].blocks[button.dataset.component];
        button.querySelector("span").textContent = block[0];
        button.querySelector("small").textContent = block[1];
      });
      selectComponent("cpu");
    }
    const component = event.target.closest("[data-component]");
    if (component) selectComponent(component.dataset.component);
  });
})();
