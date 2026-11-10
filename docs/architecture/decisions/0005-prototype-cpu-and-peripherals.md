# 0005: CPU-driven software prototype and dedicated peripherals

Date: 2026-10-28
Status: Superseded

Superseded by [ADR 0006](0006-maze-game-and-sprite-budget.md). The CPU, clock and
system design carry forward; the sprite budget expands for the maze game.

## Context

The display/input/audio bring-up milestone passed software acceptance. The next
goal is a playable original ROM using an HDL CPU and original peripheral logic,
with an interactive Nix-managed desktop simulator. Physical MiSTer testing remains
deferred under ADR 0004. No existing Lynx boot ROM or game assets are required.

## Decision

Use Jens Gutschmidt's R65C02 timing-oriented HDL core for this prototype, pinned
to `freecores/cpu65c02_true_cycle` revision
`acd38f0ec29facbf7a0d6c144b20a4757bfc0358`. Retain its GPL-3.0-or-later notices,
source, and license. Apply the explicit local correction patch before translating
VHDL through GHDL for Verilator. The core's Rockwell instruction family does not
establish WDC-specific STP/WAI support or Lynx compatibility.

The patch preserves the decimal flag in BRK's stacked status, supplies missing
next-state defaults on RDY paths, and factors identical branch-offset outputs
out of conditions that created a combinational scheduling loop. The BRK issue
was exposed by the independent Klaus Dormann functional ROMs. Those suites and
directed bus-cycle/BRK checks gate CPU acceptance. They do not prove every original
Lynx bus timing or interrupt corner case.

Use a temporary prototype memory map, 8 KiB work RAM, a 32 KiB original ROM,
4 KiB tile/attribute VRAM, a 16-entry RGB444 palette, four 16×16 two-bit sprites,
and two programmable square-wave voices. Generate a native 320×204 image in a
400×262 raster at 60 Hz using a 6.288 MHz master clock. The CPU runs at that
clock while awake and can request frame-wait through a register. Video/audio
continue while it sleeps. These are prototype budgets, not final console limits.

All gameplay belongs in the original 65C02 ROM. The SDL frontend transports
inputs, displays actual HDL pixels, and queues actual HDL audio samples. It
contains no game-rule implementation. Use a hierarchical Verilator compilation
boundary around the CPU for desktop performance, and compare against flat
simulation to check that compilation boundaries preserve observable behavior.

## Consequences

The custom renderer, rather than a CPU pixel loop, performs tile lookup, sprite
composition, and palette conversion. Frame-wait avoids wasting CPU work on
polling. A physical adapter must implement its clock control using appropriate
FPGA clock resources or an ASIC clock-gating cell; the software clock gate alone
is not board-level signoff.

The prototype map is separate from the eventual Lynx compatibility map. Keep
the earlier MiSTer bring-up target available. CPU, register, color-depth, memory,
and clock choices may be superseded as compatibility and bandwidth work develops.

## References

- Owner's request for a major playable software goal and direct execution of commands.
- [R65C02 source](https://github.com/freecores/cpu65c02_true_cycle)
- [Functional tests](https://github.com/Klaus2m5/6502_65C02_functional_tests)
- [Local CPU corrections](../../../patches/r65c02-corrections.patch)
- [Prototype memory map and interfaces](../software-prototype.md)
- [Software-first validation](0004-software-first-validation.md)
- [Verilator hierarchical compilation](https://verilator.org/guide/latest/verilating.html#hierarchical-verilation)
