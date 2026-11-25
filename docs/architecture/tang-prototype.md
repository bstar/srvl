# Tang prototype architecture

Date: **2026-11-17**. Status: **integration in progress** under
[ADR 0009](decisions/0009-tang-prototype.md). The architecture below describes the
next board port, not a completed bitstream.

## The first configuration

Keep the original Lynx CPU, Suzy graphics/math and Mikey audio/timer/display logic
inside the Tang Nano 20K FPGA. Reuse the pinned upstream console implementation;
replace MiSTer-specific loading, memory and presentation infrastructure with
portable interfaces and board adapters. Preserve the original game clock and
pixel behavior rather than speeding games up to match a display.

| Boundary | Responsibility | Current status |
| --- | --- | --- |
| Upstream Lynx console | CPU execution, original graphics, collision/math, timers, audio and cartridge requests | Diagnostic simulation and core-only route passed; broad compatibility untested |
| Work RAM | Original 64 KiB, local dual-port RAM with explicit write forwarding | Audit adapter passes defined-behavior model comparison |
| Cartridge storage | SDRAM-backed reads and loader writes with aligned-word byte cache | Service tests pass, including supported raw/LNX/BS93 boundaries, cached bytes and invalidation; broad game cases untested |
| Presentation memory | Capture emitted RGB444 into three banks; publish only complete frames | Integrated patterned console output passes; physical timing remains open |
| Memory controller | On-package 8 MiB ×32 SDRAM access, refresh and byte lanes | Independent command-level model, service and video-contention tests pass; physical timing remains open |
| Loading/input | USB UART with ASCII/CRC, guarded BIOS/image commit, held/released input and host tool | Cold/warm audiovisual diagnostics and host/service checks pass; physical acceptance remains open |
| Display | Independent-clock 640×480 RGB timing, exact legacy 2× canvas, TMDS encoding and true-LVDS serializer wrapper | Logical checks and complete bench route/fuse pack pass; serializer/I/O timing, physical output and handheld LCD remain open |
| Audio transport | Signed four-pole filter, coherent stereo mailbox and 48 kHz I²S | Component and actual Mikey tone/input/reload checks pass; final response, analog circuit and board timing unqualified |
| Clocks/reset | Faithful 64 MHz console master, related pixel/serializer clocks, independent audio and local reset release | Reference/PLL/divider graph and explicit targets checked; clock quality, phase and physical validation pending |

The board's debugger can configure clocks, program the FPGA and bridge serial.
It is support infrastructure. It does not execute game logic or render graphics.

The audio implementation expects a third **12.288 MHz** reference and derives
3.072 MHz BCLK / 48 kHz stereo by integer division. No board clocks have been
programmed or measured yet. The provisional four-pole filter's response is
documented and remains an open fidelity choice. See
[audio architecture and clock ownership](../chip-design/audio.md) and
[combined audiovisual evidence](../milestones/tang-audio.md).

## Why memory is split

The Tang has 103.5 KiB of block RAM. Original Lynx work RAM is 64 KiB. Three
160 × 102 RGB444 presentation frames alone need 73,440 bytes when tightly packed;
together they exceed the available internal storage. Work RAM stays local for
console timing, while cartridge data and presentation frames move to SDRAM.

For simpler memory transactions the implemented legacy presentation format uses **16 bits
per pixel**, keeping the 12 RGB bits and padding four bits. One frame is 32,640
bytes; three are 97,920 bytes. Reserve distinct 64 KiB-aligned banks. Line buffers
and a bounded pixel-write queue decouple display reads from emitted game pixels.
The tested legacy banks begin at `0x100000`, `0x110000` and `0x120000`; cartridge
addresses remain below `0x100000`. This internal storage layout is not an enhanced
SDK ABI. Capture preserves the last displayed complete frame during loading.

The implemented three-client round-robin arbiter absorbs short bursts through
the capture queue and tags single-outstanding completions. The SDRAM controller
performs refresh independently. Model tests exercise latency, contention and
deadline failure/recovery; raw bus rate is not useful application throughput.
The enhanced scheduler still needs its own workload budget.

## Video and frame cadence

The logical enhanced display is **320 × 204**. Legacy rendering remains
**160 × 102**, with each source pixel replicated into a 2 × 2 block, filling the
entire logical screen **without added borders**. Physical adaptation must preserve
that requirement and the complete image.

The current bench implementation centers the logical image in a 640 × 480
transport. Those test-harness borders are not the accepted handheld presentation.
A bench presentation choice is pending because 640 × 480 does not match the
logical aspect ratio; keep that transport evidence distinct from final policy.

Keep RGB samples from the moment the Lynx display DMA emits them. Reapplying one
final palette to a 4-bpp frame would lose mid-frame palette effects. Present only
complete frames, with controlled whole-frame repeat/drop when the game's frame
cadence differs from the display's 60 Hz. Report queue overflow and scanout
underrun; do not silently display partly written frames.

The proposed bench path uses 640 × 480 video with a 25.2 MHz pixel clock. The
onboard programmable clock generator is the route being investigated for an
exact 64 MHz console reference and a separate video reference. Programming the
clock generator, PLL legality, clock-domain crossings, SDRAM phase and all board
pins still need full-system constraints and acceptance.

## Loading and controls

First bring-up uses a host loader over the board's existing USB UART. A host is
acceptable for development; a finished handheld needs its own boot/game-storage
experience. BIOS and cartridge loading must hold/reset the core correctly and
validate lengths, byte order, headers and commit state.

The implemented packet transport uses ASCII hexadecimal with a CRC. This avoids binary
payloads accidentally invoking debugger console escapes. Protocol correctness,
incomplete loads, corrupt packets, reset during transfer and button release all
have directed service tests recorded in the [service milestone](../milestones/tang-board-services.md). Integrated console recovery/reload now passes the original diagnostic; broader game behavior remains untested. ROM and BIOS images must be supplied by their owner; no
commercial images are included or downloaded by the project.

## Enhanced configuration

The original native prototype and Lynx configuration use different CPU sources
and peripheral maps. Do not replace the validated Lynx CPU with the native R65C02
and assume equivalence. An eventual unified configuration is possible, but
separate legacy and enhanced FPGA images are a reasonable first implementation.

Retain the desired effects: independent sprite scaling, multiple parallax
planes, dense objects and basic hardware-assisted flat-triangle rendering.
The old ECP5 resource and x16 bandwidth estimates are **historical design
constraints**, not verified Tang capacities. Re-budget the complete enhanced
machine on Tang before promising simultaneous layer, sprite or triangle counts.

See [provenance](provenance.md), [tradeoffs](../tradeoffs.md) and the
[roadmap](../roadmap.md) for implementation ownership and acceptance gates.

## References

- [Pinned Lynx audit and memory behavior](../research/lynx-tang20k-compatibility.md)
- [Sipeed clock-generator and serial-console documentation](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/example/unbox.html)
- [Original native software architecture](software-prototype.md)
- [Earlier standalone contract](standalone-platform.md)
- [Shared SDRAM controller RTL](../../hardware/memory/cb_graphics_sdram.sv)
- [Current initial UART RTL](../../hardware/tang/lynx_uart.sv)
- [Current initial packet RTL](../../hardware/tang/lynx_packet.sv)
