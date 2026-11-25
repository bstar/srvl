# Architecture overview

**Current direction, 2026-11-15:** the next standalone prototype uses Tang Nano
20K with the upstream Lynx CPU inside the FPGA under
[ADR 0009](decisions/0009-tang-prototype.md). See the
[current architecture](tang-prototype.md) and [project summary](../project-status.md).
The earlier ECP5 requirements below preserve design history; their resource and
throughput figures require a fresh Tang budget.

Status: requirements and exploration, with a CPU-driven software prototype and
a separate MiSTer display/input/audio bring-up circuit. Physical verification
and Lynx compatibility remain ahead.

## Agreed direction

- A plausible 1993–1995 Lynx successor, using modern development tools while
  keeping explicit limits on computation, memory, and bandwidth.
- Original graphics, audio, and system hardware designs with a reused CPU core.
  R65C02 is selected for the software prototype under ADRs 0005/0006; the Tang
  legacy configuration retains the separate upstream Lynx CPU implementation.
- Existing retro chips may accompany the FPGA where they improve the design.
  The [physical CPU option](hybrid-hardware.md) was evaluated; the first standalone
  development target retains the CPU inside the Tang FPGA to avoid external-bus
  complexity. See the [current hardware choices](../hardware.md).
- FPGA development first, using the owner's existing MiSTer. First major outcome:
  a playable bench prototype, before custom handheld integration.
- Native enhanced-game resolution of 320 × 204. Legacy software renders at
  160 × 102 and receives exact 2× visual scaling, with each pixel becoming a
  2×2 block. Initial Lynx support targets unmodified game images;
  decompilation/recompilation and enhanced ports are deferred possibilities.
- Lynx software compatibility is a goal; game images precede physical cartridges.
  Compatibility milestones, completeness, and implementation order remain open.
- A color LCD with a backlight. Transflective LCDs are the leading research
  direction; no exact display panel is approved.
- Eventual custom PCB, controls, screen, and 3D-printed enclosure. Custom silicon
  is a possible later stage, not a prerequisite for the first playable prototype.
- Development tools and dependencies managed through project Nix shells.
- The current standalone prototype is Tang Nano 20K under
  [ADR 0009](decisions/0009-tang-prototype.md), with 64 KiB local Lynx work RAM and
  proposed SDRAM-backed cartridge/presentation storage. The earlier ECP5/x16
  contract is [preserved as history](standalone-platform.md). A complete BOM
  budget is open; the US$275 ULX3S option remains rejected.
- Software-first validation for current development. Physical MiSTer testing is
  deferred under [ADR 0004](decisions/0004-software-first-validation.md).
- A CPU-driven original-ROM prototype under
  [ADR 0005](decisions/0005-prototype-cpu-and-peripherals.md), with a documented
  [temporary memory map](software-prototype.md).
- The current maze revision carries those CPU/system choices forward under
  [ADR 0006](decisions/0006-maze-game-and-sprite-budget.md), expanding the fixed
  sprite budget to eight and implementing lane movement and multiple guards.
- The owner requested scaled sprites, many parallax layers, dense objects and
  basic 3D. The [current enhanced target](enhanced-target.md) explains those
  engines and their limits. The ECP5 workload calculations need a fresh Tang
  budget; full implementation and measured acceptance remain ahead.

## Proposed functional boundaries

The console logic should expose video pixels/timing, audio samples, controls,
reset/clock enables, and game-loading interfaces through an adapter for MiSTer.
MiSTer's menus, file loading, controller integration, and video output are
development infrastructure. Keep console behavior independent of those services
where practical so it can move to a custom board.

The first circuit follows this boundary: [portable demo RTL](../../hardware/rtl/chipbuilder_demo.sv)
and a [MiSTer adapter](../../hardware/mister/Chipbuilder.sv). Its 50.4 MHz clock
and 640 × 480 transport raster are bring-up choices, not a console CPU frequency
or a requirement for the eventual LCD. See the
[acceptance record](../milestones/first-mister-prototype.md) for actual validation.

Legacy mode must reproduce relevant timing and behavior, not merely CPU opcodes.
Enhanced mode requires a new Tang resource/memory contract. The native enhanced
register window is reserved at `$4400–$44FF`; bit fields and legacy activation
will be specified with the respective engines.

## Open decisions

- Legacy CPU instruction/bus equivalence, arbitrary memory stalls and IRQ corners.
- Legacy compatibility test corpus, hardware oracle, milestones, and acceptance.
- SDRAM arbiter implementation and measured throughput; selected clocks need timing closure.
- Full graphics resource fit and legacy collision/storage behavior.
- Exact display, verified 60 Hz operation, motion quality, orientation/scanout,
  availability, backlight driver, and power budget.
- Audio design, game format, boot code, SDK, and eventual cartridge interface.
- Handheld size, battery, electrical interfaces, and ASIC feasibility/budget.

Consult the [decision index](decisions/README.md) and current Tang architecture
for development requirements. This is not a procurement-ready schematic or proof
that the target has passed physical acceptance. The exact LCD remains open.
