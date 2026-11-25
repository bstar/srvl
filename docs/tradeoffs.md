# Open decisions and compromises

Reviewed: **2026-11-17**. These are review items, not requests to stop development.
Continue work that does not depend on an open choice. Record accepted changes in
an ADR and link the evidence that caused the decision.

## Next decisions, ordered by dependency

| Decision | Working direction | Alternatives and compromise | Evidence / decision trigger |
| --- | --- | --- | --- |
| Handheld LCD | Backlit color; full 320×204 logical image with exact border-free 2× Lynx output | Panel aspect ratio/active area must satisfy the complete image; common 4:3 letterboxed layouts are not accepted final presentation. Optical technology remains a separate choice | Qualify active-area mapping, genuine 60 Hz input, motion, brightness, rotation, power, lifecycle and price before PCB/case freeze |
| Enhanced graphics budget on Tang | Scaled sprites, multiple planes, basic flat triangles; re-budget the full design | Fewer simultaneous layers/large sprites, lower scene complexity or separate configurations; preserve native resolution | Full engine synthesis, measured SDRAM service and representative worst-case scenes; review before promising counts |
| Dense-scene memory service | Preserve renderer benchmarks; use the enhanced elastic service and measure full-system traffic | Dense and host-contended scaled scenes pass their renderer-only 60 Hz budgets, with [about 2 ms left](milestones/enhanced-memory.md#same-rendering-work-faster-memory-service) in the slowest case before CPU/compositor costs. Faster blitter paths add LUTs/ALUs; the new service has no bursts or display reservation yet | Retain phase-tested renderer limits and both historical baselines; measure the [complete simultaneous workload](milestones/scaled-blitter.md#measured-workloads-including-missed-budgets) before claiming 60 fps system throughput |
| Legacy + enhanced configuration | Permit separate bitstreams initially | One combined machine eases switching but consumes more logic/RAM and complicates reset/compatibility isolation | Measure integrated resource and timing headroom; decide before final boot/storage UI |
| Complete prototype/handheld cost | Low-cost Tang development first; no complete BOM ceiling established | External CPU, expensive FPGA modules and custom silicon raise cost; bare chip price excludes the rest of the system | Agree a total BOM/assembly budget before procurement; refresh historical pricing rather than treating it as a quotation |
| First video output | HDMI bench bring-up while LCD is unresolved | Direct LCD reduces duplication once a panel is known, but binds pin and timing work to that selection | Integrated timing/build result, then panel interface qualification |
| Board timing qualification | Preserve the open-flow build and audit its actual model coverage | A vendor timing flow or validated additional device models are needed for uncovered DSP/serializer/I/O paths; a passing partial report cannot substitute for them | Close [documented timing gaps](milestones/tang-board-build.md#timing-coverage-is-a-measured-boundary) before claiming full-board timing acceptance |
| Audio path | Preserve Lynx stereo samples; choose output circuitry later | A mono board speaker can prove activity but cannot establish stereo fidelity; headphone/stereo amplification consumes pins, power and board area | Transport simulation, chosen output part/interface and measured physical output before schematic release |
| Audio filtering/resampling | A measured four-pole shift/add smoother is implemented for bench I²S | It suppresses near-Nyquist content but also attenuates upper audible frequencies (about −12 dB at 10 kHz); a flatter passband or reference analog model needs a different measured filter/resource budget | Compare reference recordings/listening cases and quantify aliasing/passband before accepting final fidelity; [current audio evidence](milestones/tang-audio.md) is transport acceptance |
| Game storage and boot | Host UART for initial loading | SD/flash storage makes a self-contained handheld; requires filesystem/boot/UI work and power-failure handling | Bench loader acceptance first; settle product format before the handheld board |
| Native game/register ABI | Retain existing prototype regressions; reserve enhanced command/register space | An expansive ABI may waste scarce implementation resources; a minimal ABI may constrain effects | First scaled-blitter diagnostic and stall/backpressure tests before SDK commitment |

## Choices already made for this phase

| Choice | Why | Cost or limitation | Revisit when |
| --- | --- | --- | --- |
| CPU inside the FPGA | Fits the audited console and avoids an external bus | Uses FPGA resources; a physical CPU is not in the first prototype | A later custom-board measurement shows a concrete cost, pin or timing benefit |
| Keep the upstream CPU in Lynx mode | Compatibility includes bus/interrupt/peripheral timing, beyond the instruction set | Two CPU implementations across current workstreams | Equivalence evidence justifies consolidation |
| Keep 64 KiB Lynx work RAM on-chip | Avoids adding arbitrary SDRAM latency to original-visible RAM | Most block RAM is already committed; presentation frames must be external | A behaviorally validated alternative improves the full resource/timing budget |
| Capture RGB444 presentation pixels | Preserves palette changes at their original emission time | Uses more storage and bandwidth than saving 4-bpp indices alone | Only if an equivalent palette-event/reconstruction design is proved |
| Exact legacy pixel replication | Preserves the full image and fills 320×204 edge to edge at exact 2× | Final panel active area must support the complete image without added borders or cropping; the padded bench raster is temporary | Qualify border-free final mapping and the selected panel/interface |
| Software-first verification | Progress without attached MiSTer/Tang hardware | Does not establish electrical correctness or actual game compatibility | Physical bring-up phase under the owner's chosen schedule |
| Defer custom ASICs | FPGA design is still changing and fabrication has fixed costs | Initial product uses an FPGA rather than fabricated project silicon | Stable RTL, timing/power estimates and a separately approved fabrication budget |

## Graphics limits to make explicit

The earlier ECP5 contract considered eight tile planes, 256 resident descriptors
and three bounded traffic scenes. Those numbers are **not a Tang performance
promise**. More layers, large scaled sprites, overlap and triangle filling compete
for memory service. A maximum descriptor count describes storage capacity;
draw throughput depends on touched pixels, fetch locality, source format and
composition rules.

Initial 3D means fixed-point math assistance and autonomous flat-triangle filling,
with CPU scene setup and painter ordering. Texture mapping, a Z buffer, alpha
blending and autonomous mesh transforms remain later extensions. The visible
compromises are limited scene complexity and ordering artifacts that must be
bounded through clipping, authoring constraints and tests.

## Compatibility limits to review

The audit is not a list of working commercial games. Before making that claim,
test boot images, header and bank handling, arithmetic, RLE sprites, collision,
interrupts, frame timings, audio and orientation. Original-game speed must remain
separate from display refresh. A frozen display frame must not freeze gameplay.

ComLynx voltage/connector behavior and physical cartridge access are separate
electrical and compatibility work. Recompiling/decompiling games is deferred; it
does not replace the initial unmodified-image compatibility goal.

## Sources for the next review

- [Display shortlist and sample acceptance checklist](research/display-selection.md)
- [Full Lynx audit and remaining integration work](research/lynx-tang20k-compatibility.md)
- [Current Tang architecture](architecture/tang-prototype.md)
- [Historical ECP5 budgets and simultaneous workloads](architecture/standalone-platform.md)
- [Physical CPU option and bus constraints](architecture/hybrid-hardware.md)
- [Historical custom-silicon cost research](research/asic-cost.md)
