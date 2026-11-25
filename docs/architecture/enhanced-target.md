# Enhanced graphics target

This page says what the enhanced console is meant to do and how far the
hardware has got. The [system architecture](overview.md) describes what is
built; the [chip design handbook](../chip-design/overview.md) covers each engine.

## What we want

New games render at 320 × 204 and hold 60 frames per second for scenes whose
size we can state. The CPU runs the game and hands drawing to hardware. The
speed comes from purpose-built graphics logic and careful use of one memory
bus, not from a fast processor.

| Capability | Hardware | State |
| --- | --- | --- |
| Lynx-style scaled objects | Command-driven blitter with independent X/Y scaling, clipping and flips | Built. [Results](../milestones/scaled-blitter.md) |
| Parallax layers | Scrolling tile planes merged during scanout | Two planes built. [Design](../chip-design/compositor.md) |
| Stable frames | Front/back surfaces, swap at the frame boundary, late-row and ownership flags | Built. [Skeleton](../milestones/enhanced-skeleton.md) |
| Raster and palette effects | Per-line scroll and palette changes at defined points | Not built |
| Dense sprites | Resident descriptor lists and batch submission | Not built; one command at a time today |
| Basic 3D | Fixed-point math help and flat-triangle filling | Not built. [Design](../chip-design/geometry.md) |
| Sound, input, loading | | Not on the enhanced top yet |

## What limits it

Memory bandwidth, before anything else. A 320 × 204 surface at 16 bits per
pixel is 130,560 bytes. Reading one 60 times a second for display is 7.8 MB/s
before any sprite source read, any drawing, CPU traffic or refresh.

The blitter has been measured alone on the real controller model at 64 MHz:
a 256-sprite scene takes 10.96 ms and a scaled scene with continuous CPU
traffic 14.57 ms of a 16.67 ms frame. Those figures leave out scanout, which
adds 32,640 reads a frame: about 3 ms of bus time at six cycles a read. The
first scene has room for that. The second, with 2.1 ms to spare, does not.
This is arithmetic, not a measurement; measuring it needs a real game on the
enhanced top. It is also why the tile planes went into block RAM.

Capacity is not the same as throughput. A list that can hold 256 sprites does
not mean 256 large sprites can be drawn every frame. Any limit we publish has
to name the scene.

The earlier ECP5 plan assumed eight tile planes, 256 resident descriptors and
1 MiB of game-visible graphics memory. Those were proposals for a different
board and are not commitments here.

## First 3D scope

Flat-shaded triangles in fixed point. The CPU does transforms, projection,
clipping and ordering with hardware help for multiply and divide; the
rasterizer fills screen-space triangles on its own. Textures, a depth buffer,
blending and hardware transforms are later, if at all. They should not take
resources before the 2D system holds its frame rate.

## Legacy mode

Old games keep their own register map, memory behavior and clock, in a separate
FPGA image. Their picture is the full 320 × 204 screen at exact 2×, with no
added borders. Nothing in the enhanced design may change how they run.

## Order of work

1. Shared memory service and CPU command interface. Done.
2. Scaled blitter with a CPU diagnostic. Done.
3. Whole-frame ownership and native scanout. Done.
4. Tile planes. Two done; more only if a measured scene has room.
5. Input and audio on the enhanced top, then a real game to measure with.
6. Fixed-point math and a small flat-triangle scene.
7. Combined workloads on the board.

The register interface is described in the [register reference](native-graphics-mmio.md).
It is a working interface that will change, not an SDK.
