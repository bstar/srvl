# Enhanced graphics target

Reviewed: **2026-11-17**. Status: **design target; full implementation and Tang
resource/bandwidth qualification remain ahead**. Keep the working software
prototype as a regression baseline while building these engines.

The [chip design handbook](../chip-design/overview.md) expands this target into
inspectable engine diagrams, interface contracts and per-engine acceptance work.

## The experience we want

New games should render at **320 × 204** and reach **60 fps** under explicitly
bounded workloads. The CPU handles gameplay and submits work to specialized
engines. Performance comes from parallel, purpose-designed graphics logic and
memory scheduling, rather than a modern host CPU doing all rendering.

| Capability | Intended hardware | Limits to make visible |
| --- | --- | --- |
| Lynx-style scaled objects | A command-driven sprite blitter with independent X/Y scaling, clipping and flips | Source format, minification locality, overlap and destination area affect throughput |
| Many parallax layers | Tile-plane compositor with independent offsets and raster control | Layer capacity competes for fetch bandwidth and buffers; simultaneous workload needs a measured limit |
| Dense sprites | Resident descriptors, queues and scheduled drawing | A descriptor count is storage capacity, not a guaranteed number of large visible draws |
| Basic 3D | Shared fixed-point math assistance and screen-space flat-triangle filling | CPU scene setup/geometry and painter ordering initially; clipping and ordering constraints must be tested |
| Raster/palette effects | Deliberate scanline and palette-bank controls | Define when updates latch and how software synchronizes; no accidental timing semantics |
| Stable frame presentation | Completion fences, reserved scanout service and explicit late/overflow status | Swap complete frames only; avoid hiding missed work with partly rendered images |

## What the existing game proves

The current prototype already renders native-resolution tile graphics and eight
fixed-size sprites, runs two audio voices and handles timing/input in HDL. The
CPU runs the original maze game and enemy logic. This provides a working system
and regression target. It does **not** implement the general scaled blitter,
many-plane compositor or 3D hardware described here.

See the [working memory map and peripheral details](software-prototype.md).

An original [scaled-blitter component](../milestones/scaled-blitter.md) is now
implemented separately: exact 4/8-bit scaling, coverage/index/band output, fills,
clipping, masked writes and completion fences pass independent tests and real
SDRAM-controller integration. A separate [native MMIO/CPU diagnostic](native-graphics-mmio.md)
now uploads sources and submits draws on the actual CPU, and a first
[enhanced top](../milestones/enhanced-skeleton.md) adds native scanout and frame
ownership; a playable enhanced game and the compositor remain ahead. With the
[enhanced elastic memory service](../milestones/enhanced-memory.md), all bounded
renderer-only 60 Hz checks pass, including front-read phase repeats. Full-system budgets and
enhanced clock qualification remain open.

## Planning numbers versus promises

The earlier ECP5 contract explored **eight tile planes**, **256 resident object
descriptors**, **1 MiB game-visible graphics storage**, an RGB444 palette and
bounded example scenes. Those remain useful starting proposals. They need a
fresh full-system allocation for Tang; its different fabric, RAM, memory width
and board interfaces change the available headroom.

A 320 × 204 frame contains **65,280 pixels**. At 16 bits per stored pixel, one
surface occupies **130,560 bytes** and two occupy **261,120 bytes**. Merely reading
one such surface 60 times per second consumes **7.8336 MB/s**, before sprite
source reads, drawing, tile layers, CPU traffic, refresh and turnaround. This is
a storage/traffic calculation, not a measured controller result.

Measure useful scheduled traffic and worst-case service latency, not just
clock × bus width. Freeze a simultaneous-scene contract after the new memory
controller and engine synthesis provide real evidence.

## First 3D scope

Start with flat-shaded triangles and fixed-point arithmetic. The CPU initially
handles transforms, projection, clipping and ordering with hardware math help;
the rasterizer fills screen-space triangles autonomously. This deliberately
limits geometry complexity and requires clear near-plane and ordering rules.

Textures, a depth buffer, alpha blending and autonomous indexed-mesh transforms
are later extensions. They should not consume the first resource budget before
the basic system passes. We can still build distinct original games around
flat-shaded scenes and mixed 2D/3D presentation.

## Interface work still ahead

The `$4400–$44FF` window now has a concrete experimental v1 MMIO implementation:
36-byte staging, atomic submission, held result/counters, byte access and IRQ.
Its [encoding and CPU diagnostic](native-graphics-mmio.md) are tested; it is not a
frozen SDK. Batch commands, general CPU external-memory access and frame ownership
remain open. Local nonblocking registers keep the current CPU bus cycles independent
of graphics-memory stalls; a general stall/cache adapter still needs its own tests.

Legacy mode must retain its own visible register map, memory behavior and clock.
Its exact 2× image fills the full 320×204 logical screen with no added borders.
Enhanced-mode speed must not alter old-game execution. Separate FPGA images are
acceptable initially; a unified mode-switching architecture needs its own fit,
reset and compatibility evidence.

## Build sequence

1. Qualify the shared memory and CPU request/stall interfaces.
2. Implement the scaled blitter and an original native diagnostic.
3. Add complete-frame fences and traffic/error counters.
4. Grow the compositor from a small layer count to the measured useful limit.
5. Add fixed-point math and a small flat-triangle scene.
6. Test bounded combined workloads, synthesize and route the complete design.

See [the roadmap](../roadmap.md), [current Tang architecture](tang-prototype.md)
and [earlier ECP5 calculations](standalone-platform.md) for dependencies and history.
