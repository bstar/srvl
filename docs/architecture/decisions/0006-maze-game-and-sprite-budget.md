# 0006: Maze game and eight-sprite prototype budget

Date: 2026-10-29
Status: Accepted

## Context

The owner requested a loosely Pac-Man-inspired Circuit Courier: movement on
rails, obstructed routes, multiple enemies and progressive difficulty. The prior
four-sprite budget could display only one guard alongside courier, card and dock.

## Decision

Carry forward ADR 0005's pinned R65C02, 6.288 MHz master clock, 320×204/60 Hz
raster, RAM/ROM map, tile graphics, audio, input and frame-wait design. Retain
the two millisecond stopwatches. Expand the fixed sprite compositor to eight
16×16 sprites and its register window to `$4100–$413F`. Keep the existing eight
sprite patterns and 512-byte sprite ROM. Skip sprite sampling during blanking.

Use four connected 8×4 junction graphs, each with loops and progressively fewer
extra links. Junctions are 32 pixels apart; corridors and wall cells are 16 pixels
wide. The ROM implements buffered cardinal turns, continuous movement, immediate
reversals, wall blocking, randomized object placement and two-to-five guards.
Give the player a rechargeable jam pulse: guards freeze and become harmless for
one second, with progressively longer recharge intervals.

Keep maze graph masks, tile layouts and all-pairs shortest-path distances in ROM.
Generate these deterministic assets at build-authoring time and verify their
reproducibility in Nix. Guard junction steering and route-based qualifying times
use table lookups on the 65C02; the interactive frontend contains no game rules.
Retain ordered card deliveries and millisecond scoring to distinguish this game
from a pellet-clearing game.

## Consequences

Control revision, 2026-10-29: following owner feedback, the courier now requires
a held direction and stops immediately on release, including mid-corridor.
Held requests still buffer turns and reversals remain immediate. This replaces
the initial automatic-motion behavior; the hardware and maze decisions remain.

The final circuit fits courier, active card, five guards and dock without sprite
multiplexing. The expanded budget has explicit hardware cost; it does not imply
unlimited sprites or Lynx compatibility. Software tests reconstruct the visible
maze, check connectivity and rail motion, exercise jam/retry controls and qualify
all four circuits using ordinary SDL inputs. Peripheral tests cover upper sprite
register isolation and priority. Flat/hierarchical simulation must still agree.

Physical adapter work and FPGA/ASIC timing acceptance remain deferred under
ADR 0004. This supersedes ADR 0005's four-sprite budget and retains its CPU choice.

## References

- [Prior prototype decision](0005-prototype-cpu-and-peripherals.md)
- [Software-first acceptance](0004-software-first-validation.md)
- [Current architecture and memory map](../software-prototype.md)
- [Game ROM](../../../firmware/courier.s)
- [Maze asset authoring](../../../scripts/make-mazes.py)
- [Custom peripherals](../../../hardware/rtl/srvl_peripherals.sv)
