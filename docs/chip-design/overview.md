# Chip design handbook

Reviewed: **2026-11-17**. Status: **first scaled-blitter component implemented;
complete enhanced system remains in development**. The first hardware realization is a set of logic modules inside
one FPGA. Logical chip boundaries do not mean separate IC packages or a
manufactured custom die.

{{chip-diagram:system}}

## The machine at the logic level

The defining idea is a 65C02-family CPU orchestrating specialized circuits. Games
submit work; graphics engines fetch and draw through a memory scheduler; display
hardware consumes complete results. The CPU does not have to touch every output
pixel. The following map is the **proposed enhanced configuration**. Legacy Lynx
mode has its own [separate diagram and timing boundary](legacy.md).

## Explore the designs

| Design area | What you can inspect | Implementation state |
| --- | --- | --- |
| [Scaled sprite engine](sprites.md) | Exact sampling, clipping, packed source cache, transparency, masked writes and fences | Component, memory workload and native CPU/MMIO diagnostic tests pass; it draws the sprites on the [enhanced top](../milestones/enhanced-skeleton.md) |
| [Tile planes and composition](compositor.md) | Two scrolling tile planes in block RAM, priority against the object surface, line buffering | Implemented with two planes; passes the system test and routes; per-line scroll and more planes are not built |
| [Geometry and triangles](geometry.md) | CPU scene preparation, fixed-point assistance, edge setup, coverage and flat filling | Proposed; no new 3D engine implemented |
| [Memory and timing](memory.md) | CPU stalls, queues, arbitration, refresh, complete-frame ownership and clock crossings | Legacy service/video tests pass; enhanced elastic arbiter/SDRAM and bounded blitter workloads pass models; full native scheduler/ownership integration remains open |
| [System and boot control](system.md) | Bitstream configuration, safe reset, boot monitor, loading, game handoff and recovery | HDL loader and original CPU-driven graphics diagnostic pass; shared monitor/launcher and frame handoff proposed |
| [Stereo audio](audio.md) | Signed filtering, coherent stereo pairs, independent audio clocks and I²S | Component and real-core audiovisual tests pass; final response/analog circuit and board timing open |
| [Clock, reset and display output](board-output.md) | Clock islands, reset release, TMDS encoding, serialization and board I/O boundaries | Encoder/control checks and complete bench route/fuse pack pass; DSP/serializer/I/O timing and physical output remain unqualified |
| [Lynx compatibility path](legacy.md) | Reused CPU/Suzy/Mikey, local RAM, emitted RGB capture and exact scaling | Patterned serial diagnostic, exact 2× RGB and stereo I²S pass; video serializer/full board timing remain open |
| [Verification and budgets](verification.md) | Reference models, tests, synthesis, timing and physical acceptance | Existing evidence is scoped; enhanced fit remains open |

## Read the diagrams

**Green**, with a solid outline, identifies original project logic or a
proposed project interface. **Blue**, with long dashes, identifies reused
implementation. **Amber**, dotted, identifies integration work or a boundary
that still needs qualification. Every selectable block has a state, inputs,
outputs and an acceptance requirement. The colors describe ownership and design
role; they are not a pass/fail test report.

Select a block for its details. Use zoom and horizontal scrolling for larger
views; **Open drawing** and **Save drawing** give the figure as a file for review and
printing. The diagrams work offline and their source is kept with the generator.
They are logical diagrams, not physical floorplans, routed nets or schematics.

## What is established

- Native rendering is **320×204**, with a **60 fps workload goal**.
- Original Lynx output remains **160×102**, replicated exactly onto the logical
  **320×204 canvas, edge to edge with no added borders**. Physical panel
  adaptation must preserve that requirement.
- CPU logic stays inside the FPGA for the first Tang prototype.
- Legacy work RAM stays local; presentation/cartridge storage now passes modeled
  external-memory integration with exact 2× RGB output.
- The larger enhanced engines need a **fresh Tang resource and bandwidth budget**.
  The earlier ECP5 figures are historical planning work.

The [project status](../project-status.md), [decision records](../architecture/decisions/README.md)
and [provenance record](../architecture/provenance.md) are the evidence and decision
context for these designs.

## Interfaces before gate counts

Each engine needs a bounded command format, reset state, accepted-request rule,
backpressure behavior, completion/fence semantics and error counters. Only after
those are simulated can synthesis establish its cost. A maximum sprite count or
layer count is not useful without the scene size, source format and memory-service
conditions that make the count achievable.

The complete legacy bench top now routes and fuse-packs; its remaining timing
coverage and physical output still need qualification. The enhanced top has the blitter, two tile planes, whole-frame ownership and
native scanout working together in simulation; its next steps are input, audio
and a real game to measure the combined load.

## Source and upkeep

Diagram definitions and rendering live in
[chip_diagrams.py](../../scripts/chip_diagrams.py). The HTML build exports the same
definitions as SVG and as block-description data, keeping the labels and block details
together. Update the relevant page, diagram and verification evidence when an
interface or implementation state changes. See the
[documentation workflow](../documentation.md).
