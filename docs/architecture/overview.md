# Architecture overview

Status: requirements and exploration, with a CPU-driven software prototype and
a separate MiSTer display/input/audio bring-up circuit. Physical verification
and Lynx compatibility remain ahead.

## Agreed direction

- A plausible 1993–1995 Lynx successor, using modern development tools while
  keeping explicit limits on computation, memory, and bandwidth.
- Original graphics, audio, and system hardware designs with a reused CPU core.
  R65C02 is selected for the software prototype under ADR 0005; the eventual
  timing-faithful Lynx compatibility CPU still needs validation.
- Existing retro chips may accompany the FPGA where they improve the design.
  The [physical CPU option](hybrid-hardware.md) was evaluated; the first standalone
  development target retains the soft 65C02 in an ECP5-12F to reduce CPU/FPGA cost
  and external-bus complexity. See the [selected platform](standalone-platform.md).
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
- The standalone engineering target is LFE5U-12F-6BG256C, one x16 SDR SDRAM and
  QSPI flash under [ADR 0008](decisions/0008-standalone-development-target.md).
  Its checked US$16.78 FPGA price exceeds the roughly US$10 aspiration; that
  tradeoff does not authorize purchase or change the user's spending budget.
  The US$275 ULX3S option remains rejected.
- Software-first validation for current development. Physical MiSTer testing is
  deferred under [ADR 0004](decisions/0004-software-first-validation.md).
- A CPU-driven original-ROM prototype under
  [ADR 0005](decisions/0005-prototype-cpu-and-peripherals.md), with a documented
  [temporary memory map](software-prototype.md).
- The current maze revision carries those CPU/system choices forward under
  [ADR 0006](decisions/0006-maze-game-and-sprite-budget.md), expanding the fixed
  sprite budget to eight and implementing lane movement and multiple guards.
- The owner requested scaled sprites, many parallax layers, dense objects and
  basic 3D. The [standalone contract](standalone-platform.md) fixes development
  limits and workloads for the blitter, compositor and flat-triangle/math hardware.
  Measured acceptance remains ahead; [ADR 0007](decisions/0007-enhanced-graphics-effects.md)
  preserves the earlier exploration.

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
Enhanced mode uses the selected resource/memory contract. The native enhanced
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

Consult the [decision index](decisions/README.md) and selected platform contract
for development requirements. This is not a procurement-ready schematic or proof
that the target has passed physical acceptance. The exact LCD remains open.
