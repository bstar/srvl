# What we design and what we reuse

Reviewed: **2026-11-17**. Custom hardware means we author logic and interfaces;
the first prototype implements them in an existing FPGA. It does not yet contain
fabricated custom silicon.

| Component | Origin | Our work and limits |
| --- | --- | --- |
| Original game | Project ca65 assembly ROM | Circuit Courier rules, mazes, guards, scoring, input and sound sequencing execute on the simulated CPU |
| Native CPU | Jens Gutschmidt R65C02, pinned source | Local correction patch, GHDL conversion, directed tests and independent functional suites; not an original CPU design |
| Native peripherals | Project HDL | Tile/sprite composition, input, frame IRQ/wait, two audio voices and exact millisecond timers; current sprite engine is small and fixed-size |
| Desktop simulator | Verilator/SDL and project frontend | Runs generated hardware, displays its pixels and transports input/audio; host code does not implement production gameplay |
| Lynx CPU/Suzy/Mikey | Pinned MiSTer Lynx implementation | Adapt memory, loading and board support; documented reset-only strobe correction fixes warm boot; original algorithms are reused rather than claimed as new graphics chips |
| Lynx memory adapter | Project adapter around inferred RAM | Preserve defined upstream enable/output/write-forwarding behavior; tested against the Intel model with collision exclusions |
| Tang board integration | New project work around documented board interfaces | UART/protocol/loader/cart/SDRAM, buffered exact-2× RGB, stereo transport, TMDS encoding and reset/activity control pass software checks; complete mapping/pin packing passes; serializer, analog output and complete timing qualification remain open |
| Enhanced effects engines | Original project HDL; partial implementation | Scaled-blitter component, exact sampler, cache, masks/fences and dual-clock MMIO pass pixel/SDRAM and actual CPU-ROM tests; parallax, geometry, frame ownership and full-scene performance remain ahead |
| Enhanced diagnostic | Original project ca65 ROM | CPU uploads assets, submits tagged commands, validates results and handles IRQ; six cold/warm boots pass. This is separate from a shared boot monitor or game launcher |
| Shared memory service | Original project HDL; replaced our earlier legacy service on 2026-11-24 | Elastic round-robin arbiter and conservative auto-precharge controller pass independent model/fairness/reset checks and bounded renderer workloads; CPU/scanout/deadline integration and full enhanced timing remain open |
| FPGA/SDRAM/flash | Existing commercial silicon | The FPGA implements our logic; memory stores data. These parts are not chips fabricated by this project |
| Board/enclosure | Future project work | Custom PCB, power, controls and 3D case; no released schematic or manufactured handheld yet |
| Toolchain | Nixpkgs, GHDL, Verilator, Yosys, nextpnr, Apicula, cc65, SDL and optional Quartus | Pinned inputs and project build recipes; tool authors retain ownership |
| Design inspiration | Atari Lynx and Commander X16 | Hardware-offloaded graphics and readable interfaces; inspiration does not establish source reuse or compatibility |

## Two different CPU implementations

The native game's selected CPU is pinned to
`acd38f0ec29facbf7a0d6c144b20a4757bfc0358`, with the
[documented correction patch](../../patches/r65c02-corrections.patch). The Lynx
audit uses the CPU inside the pinned Lynx source revision
`3708e457e413aa7a33f8bec8fcd79eba45ce4702`.

Both run inside FPGA logic in the current direction. Passing the native CPU's
functional suites does not certify the separate Lynx implementation, and the
Lynx core's route result says nothing about the complete enhanced configuration.

## What is new about the intended console

The planned originality is the combination of a deliberately limited enhanced
graphics architecture, its register/command interface, original software and
physical handheld design. A scaled blitter, compositing rules, memory scheduler
and flat-triangle engine can be our designs even though the FPGA and CPU core
are reused. Recreating Lynx mode is a compatibility workstream, with separate
provenance and testing.

The working prototype currently proves a smaller original system: fixed-size
sprites, tile graphics, simple sound and a CPU-driven game. It does not yet
implement all the enhanced effects. Its exact
[temporary register map](software-prototype.md#prototype-memory-map) is documented.

## Source and image boundaries

Keep upstream notices, exact revisions, modifications and applicable source
alongside distributed builds. The native CPU source is GPL-3.0-or-later. The
Lynx tree contains different file-level GPL notices; preserve the actual notices
rather than assigning the whole tree one convenient label. The
[audit](../research/lynx-tang20k-compatibility.md#references) records these findings.

Upstream emulation HDL does not grant rights to Atari boot ROMs or commercial
game images. Original project diagnostics are the current test content. No
decompilation or recompilation of commercial games has been performed.
