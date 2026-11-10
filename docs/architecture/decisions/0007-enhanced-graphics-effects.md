# 0007: Enhanced graphics effects engines

Date: 2026-10-29
Status: Superseded

Superseded by [ADR 0008](0008-standalone-development-target.md), which selects
the standalone development contract after the owner's request for firm tradeoffs.

## Context

The owner requested custom graphics hardware for Lynx-style sprite scaling,
many parallax layers, dense sprites and basic 3D. The current eight fixed 16×16
sprites and single glyph plane demonstrate the console's software/hardware
boundary but do not provide these features.

## Decision

Propose a framebuffer object blitter, a multi-plane tile/raster compositor and a
fixed-function geometry engine sharing local graphics memory. Keep the 65C02
responsible for game code and command submission. Develop the engines as original
HDL modules on one FPGA before choosing physical IC boundaries.

The [design and bandwidth proposal](../graphics-effects.md) explores eight tile
planes, 256 persistent object descriptors, 256 palette entries, 1 MiB graphics
memory and a 25.152 MHz graphics clock with a 32-bit aggregate memory path. These
are provisional targets, not accepted final capacities or measured throughput.
Start 3D with flat shading, painter ordering and constrained scenes; add transforms
and projection after screen-space triangle filling works.

## Consequences

Implement incrementally under Nix with CPU-driven diagnostic ROMs and cycle-based
software acceptance. Retain the existing game/prototype until integration passes.
Memory arbitration and fill rate bound simultaneous effects, regardless of object
descriptor count. Physical timing, resources, power and separate-chip feasibility
remain unverified. Legacy Lynx behavior still requires a separate specification
and compatibility tests; these enhancements do not supply it automatically.

This proposed record does not supersede ADR 0006's implemented prototype.

## References

- [Detailed proposal, calculations and primary sources](../graphics-effects.md)
- [Current prototype decision](0006-maze-game-and-sprite-budget.md)
- [Software-first validation](0004-software-first-validation.md)
- [Native and legacy resolutions](0003-display-resolution.md)
