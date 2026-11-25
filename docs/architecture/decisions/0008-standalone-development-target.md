# 0008: Standalone development target and hardware tradeoffs

Date: 2026-10-30
Status: Superseded

Superseded for the immediate standalone prototype by
[ADR 0009](0009-tang-prototype.md). The following ECP5 contract preserves the
earlier decision and its calculations; enhanced graphics must be re-budgeted
for Tang rather than treating these numbers as verified Tang performance.

## Context

The owner asked for concrete tradeoffs now so development has a target. Existing
retro chips are allowed alongside an FPGA, and approximately US$10 was suggested
for the FPGA. The US$275 board was rejected. UP5K is near that chip-price target,
but its 39 I/Os constrain parallel RAM/display and an external CPU bus. A physical
W65C02 adds approximately US$11 at checked one-off pricing and does not automatically
reduce the complete system cost. Full enhanced graphics fit is unverified.

## Decision

Set the **ECP5 LFE5U-12F-6BG256C with the existing soft R65C02** as the working
standalone engineering target. Use one 32 MiB x16 SDR SDRAM and 16 MiB QSPI flash,
3.3 V digital interfaces, parallel RGB LCD transport and FPGA audio/input/timers.
Keep physical CPU and separate retro sound/I/O chips outside the first-board
dependencies. Preserve module boundaries for later reuse.

The FPGA's checked US$16.78 price exceeds the roughly US$10 aspiration. This is
an explicit engineering tradeoff for a lower CPU/FPGA subtotal and a simpler
interface budget. It is **not approval to purchase hardware or an assertion that
the user's spending budget increased**. A firm US$10 ceiling requires revisiting
the design before procurement. Existing simulation/MiSTer work requires no purchase.

Adopt the [standalone platform contract](../standalone-platform.md) and its
[machine-readable budget](../../../hardware/targets/standalone.json): 9,600 LUT
sites, 28 block RAMs, 16 multipliers and 128 I/O maximums within the published
12F capacities. Target 20.1216 MHz native CPU, 50.304 MHz graphics and 100.608 MHz
x16 memory, with 64 MB/s useful controller service to be demonstrated.

Retain eight tile planes, 256 resident object descriptors, scaled/tilted sprites,
raster effects, native 320×204/60 Hz and 1 MiB graphics-visible storage. First 3D
uses hardware math and autonomous flat-triangle filling; CPU handles geometry
setup. Autonomous mesh transforms and textured/depth-buffered rendering are later
extensions. Unmodified Lynx compatibility and exact 2× legacy output remain goals;
recompilation stays deferred.

## Consequences

Firmware/HDL can now target explicit memory width, resources, engine interfaces
and workloads. Existing game/prototype behavior is retained for regression.
Synthesis/resource checks become Nix outputs. Fitting the CPU is not evidence
that the complete graphics/legacy implementation fits or that clocks meet timing.
Full-system placement/routing, SDRAM service, pin-bank assignment, LCD selection,
power, sourcing and physical testing remain required gates before board release.
The contract must change explicitly if those gates reveal a limit.

This supersedes ADR 0007's open graphics-platform proposal and its hypothetical
32-bit graphics memory budget. ADR 0006 remains the implemented software-game
baseline, and software-first development under ADR 0004 continues.

## References

- [Platform choice, cost/pin/resource budgets and acceptance gates](../standalone-platform.md)
- [Prior enhanced graphics proposal](0007-enhanced-graphics-effects.md)
- [Physical CPU option evaluated](../hybrid-hardware.md)
- [FPGA research and CPU sizing](../../research/fpga-and-custom-silicon.md)
