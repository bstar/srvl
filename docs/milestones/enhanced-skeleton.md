# Enhanced console skeleton

Reviewed: **2026-11-24**. Status: **simulation, mapping and open-tool routing
pass; no compositor, audio, input, loader or physical test**. This is the first
real enhanced top: until now the enhanced engines existed only inside test fixtures.

## What exists

[cb_enhanced_system.sv](../../hardware/enhanced/system/cb_enhanced_system.sv)
connects the pinned R65C02, 8 KiB RAM and a 32 KiB ROM in block RAM, the
[graphics MMIO port](../architecture/native-graphics-mmio.md) with the scaled
blitter, a new video-control block, a new native scanout and the shared SDRAM
service. [cb_enhanced_tang_board.sv](../../hardware/enhanced/system/cb_enhanced_tang_board.sv)
adds the same clock, reset, pin and serializer blocks as the legacy bench top.

| Block | Role | Origin |
| --- | --- | --- |
| [cb_native_scanout.sv](../../hardware/enhanced/cb_native_scanout.sv) | Reads one 320 × 204 indexed surface, applies a 256-entry RGB444 palette and shows it at exact 2× (640 × 408) centered in 640 × 480 | Project HDL derived from our legacy scanout: same mailbox crossing and alternating line buffers |
| [cb_video_control.sv](../../hardware/enhanced/cb_video_control.sv) | CPU registers at `$4500`: enable, swap request, front surface, frame counter, palette port, underrun and ownership-fault status | New project HDL |
| [enhanced-demo.s](../../firmware/enhanced-demo.s) | ROM that loads a palette, uploads a sprite, then clears, draws four scaled sprites and swaps once per frame | New project ca65 |

The scanout is the third client of the one memory service, beside the blitter
and the CPU byte port. There is no reserved display priority yet; round-robin
service has been sufficient for this light scene and nothing more is claimed.

## Frame ownership

Two surfaces sit at `$100000` and `$140000`. The displayed one belongs to scanout.
The CPU draws into the other and requests a swap; the swap is taken only at the
scanout's frame boundary, before any row of the next transport frame is fetched,
and the frame's surface is then held for all 204 rows. `FRONT` and `SWAP_PENDING`
change together in the CPU's view.

A graphics write into the displayed surface, or into either surface while a swap
is pending, sets a sticky ownership fault visible to the CPU. This is detection,
not prevention: the write still happens. A row that is not ready in time is shown
black as a whole pair of output lines and counted as an underrun.

## Clocks

The CPU and its local memory use one real 8 MHz clock, produced by a divider
primitive from the 64 MHz system clock; the earlier prototype's gated clock is
not used. Block RAM offers only rising-edge clocks, so RAM, ROM and the palette
write port use the rising edge and every CPU-domain register uses the falling
edge of the same net. Memory therefore sees a settled address mid-cycle and the
CPU sees registered data half a cycle later. CPU `RDY` stays high and remains
unvalidated. A first attempt that read memory on a logic-inverted clock routed
with hold violations; the mapping check now rejects any clock pin driven by logic.

Graphics and video are treated as unrelated to the CPU clock and cross through
the existing toggle synchronizers. One known gap: the MMIO block's CPU-side
registers still take the graphics-domain reset directly. CPU writes are gated by
the separately synchronized CPU reset, but that release path needs a proper review.

## Evidence

The [test](../../sim/enhanced-system.cpp) supplies clocks and the unchanged SDRAM
pin model and draws nothing itself. It captures complete 640 × 480 transport
frames and requires each to be exactly one frame of an independently rendered
reference sequence: the previous frame again or the next one, never a mixture.

- **14 distinct frames, 0 repeats, 0 torn frames** across two clock configurations
  (25.2 MHz pixel clock with an 8 MHz CPU; a slower pixel clock with a 10.67 MHz CPU).
- Exact 2× replication, black bars, 800 × 525 vertical period, no underrun, no
  ownership or protocol fault, and the CPU-uploaded sprite bytes verified in memory.
- A second ROM that deliberately draws into the displayed surface: the fault is
  raised and the CPU reports it.

![Frame drawn by the demo ROM](../images/enhanced-demo.png)

The image is the reference rendering of the last frame the test matched pixel for
pixel against the captured output.

| Resource on GW2AR-18 | Used | Available |
| --- | --- | --- |
| LUT4 sites | 7,885 | 20,736 |
| Registers | 2,906 | 15,552 |
| Block RAM | 21 | 46 |

| Clock | Target | Open-tool estimate |
| --- | --- | --- |
| System / SDRAM | 64 MHz | 66.36 MHz |
| CPU and local memory | 8 MHz | 20.79 MHz |
| Pixel | 25.2 MHz | 83.85 MHz |

Nineteen of the block RAMs hold the CPU's ROM and RAM. The system
clock margin is thin and comes from one seed. These are frequency estimates for
three clock nets from tools with no serializer or I/O timing model and no
cross-domain analysis, the same limits as the
[legacy board build](tang-board-build.md). No bitstream is packaged and nothing
has run on a board.

```sh
nix --extra-experimental-features 'nix-command flakes' build \
  .#enhanced-system-check -o build/enhanced-system-check -L
nix --extra-experimental-features 'nix-command flakes' build \
  .#enhanced-board-check -o build/enhanced-board-check -L
```

The [dated evidence](../research/evidence/enhanced-system-2026-11-24.json) records
the results and source hashes.

## What this does not show

The scene is four small sprites and a clear, so sustaining 60 frames per second
here says nothing about the [dense renderer workloads](scaled-blitter.md) once a
real game, compositor and scanout share the memory service. Next: port Circuit
Courier or a comparable game onto this top, add input and audio, then the
compositor, and measure the combined workload and fit again.
