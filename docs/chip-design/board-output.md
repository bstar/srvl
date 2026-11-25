# Clock, reset and display-output logic

Reviewed: **2026-11-17**. Status: **digital encoding/control checks and complete
bench build pass; full timing qualification and physical output remain open**. This chapter connects
the tested portable console to the proposed Tang Nano 20K board wrapper. It
does not select the handheld screen or establish full-board timing.

## Three clock domains, explicit boundaries

The console, memory and loader use a 64 MHz system clock. Video has a related
pixel/serializer pair; audio has its own reference. A frame or stereo pair
crosses between domains through a held-data request/acknowledgment handshake.
Independent clocks do not imply independent ownership of shared data.
The 64 MHz figure is the FPGA system clock; the reused core's clock enables
preserve original console timing. It is not a claim of a 64 MHz 65C02.

{{chip-diagram:clocks}}

| Clock | Proposed source or derivation | Consumer | Evidence boundary |
| --- | --- | --- | --- |
| System, 64 MHz | External reference through system rPLL | Console, memory controller, loader and capture | Portable RTL tests use ideal clocks; original core-only route meets 64 MHz |
| SDRAM, 64 MHz shifted 180° | System rPLL phase output | External memory clock | Independent command model assumes this relationship; physical I/O setup/hold open |
| Serializer, 126 MHz | Video reference ×5 through rPLL | Four DDR OSER10 primitives | Wrapper written; primitive alignment and timing open |
| Pixel, 25.2 MHz | Serializer clock ÷5 through CLKDIV | Scanout and registered TMDS encoders | Logical raster and encoding pass; clock-tree implementation open |
| Audio, 12.288 MHz | Separate external reference | Stereo mailbox receiver and formatter | Ideal-clock tests and pin decoding pass; board reference unmeasured |
| I²S BCLK, 3.072 MHz | Audio counter ÷4 | Serial audio output | Independent decoder verifies cadence |
| Stereo frames, 48 kHz | 64 BCLK periods | Frame latch and audio activity watchdog | Coherent stereo transport and stopped-stream recovery tested |

The required reference profile is **64 / 25.2 / 12.288 MHz**. The wrapper does
not configure the board's external clock generator. Configuration persistence,
startup frequencies, clock quality and the board revision must be checked before
bring-up. Primitive parameters are in
[gowin_board_clocks.sv](../../hardware/boards/tang_nano20k/gowin_board_clocks.sv).
They are an implementation candidate, not a PLL qualification report.

## Reset must work when a clock stops

The button or loss of either PLL lock asserts all three local resets
asynchronously. Each local reset releases only after **three rising edges of
its own clock**. A stopped audio clock therefore keeps its domain in reset.
The [reset synchronizer](../../hardware/boards/tang_nano20k/cb_reset_sync.sv)
also begins asserted at FPGA configuration.

The [board control logic](../../hardware/boards/tang_nano20k/cb_board_control.sv)
requires a running game, audio-ready status, no audio underrun, and recent frame
activity before amplifier enable. The frame toggle crosses into the system
domain through two registers. With no new event for approximately 4,096 system
cycles (**64 µs**), the watchdog drops activity. This is a digital enable policy;
it does not establish analog pop suppression or speaker safety under every
power fault.

The [control test](../../sim/board-control.cpp) exercises delayed lock, exact
local release, clocks stopping, formatter stopping while its clock continues,
restart, underrun mute, game stop, lost lock with stopped clocks, and button
reset. It drives ideal clocks and lock inputs; it does not model metastability
or a PLL's acquisition behavior.

## From exact pixels to serial words

The bench output retains the **320×204 logical canvas**, including the exact
2× representation of a **160×102** legacy frame. That canvas sits inside a
640×480 visible raster with black borders. The total raster is 800×525;
25.2 MHz gives exactly 60 transport frames/s by arithmetic. This is our chosen
bench timing, separate from source-game cadence and the eventual panel mode.

{{chip-diagram:tmds}}

The original [symbol mapper](../../hardware/display/cb_dvi_symbols.sv) repeats
each RGB444 nibble to form RGB888. For example, channel value `0xA` becomes
`0xAA`; this preserves the source values without adding color precision.
The blue, green and red encoders have independent running-disparity state.
During blanking, blue carries horizontal/vertical control and the other two
lanes carry control 00.

The original [TMDS encoder](../../hardware/display/cb_tmds_encoder.sv) follows
the encoding and serialization rules in sections 3.2.2–3.2.3 of the
[DDWG DVI 1.0 specification](https://ez.analog.com/cfs-file/__key/communityserver-discussions-components-files/331/DVI_2D00_1.0_5F00_specs.pdf).
The separate [reference model](../../sim/tmds-model.hpp) tracks disparity by
counting the bits actually emitted and reconstructs bytes independently.
Its [test](../../sim/dvi-encoder.cpp) reaches every valid state through input
sequences, rather than forcing internal registers. It checks all **nine
reachable disparity states × 256 byte values**, the **460 active codewords**,
all four controls, reset and randomized transitions, every RGB444 color, and a
complete raster. The [dated evidence](../research/evidence/tang-output-2026-11-17.json)
records the passed scope and source hashes.

## The FPGA primitive boundary remains a separate gate

[gowin_dvi_tx.sv](../../hardware/boards/tang_nano20k/gowin_dvi_tx.sv) connects
four ten-bit words to four OSER10 primitives, followed by true LVDS output
buffers. One lane sends the clock pattern; the others send RGB symbols. The
intended data rate is **25.2 million words/s × 10 bits = 252 Mb/s per lane**,
using both edges of a 126 MHz serializer clock.

Encoding tests end at the ten-bit words. They do not establish a serializer's
load edge, reset alignment, pin mapping, I/O standard, signal amplitude, jitter,+cable behavior, receiver lock or real pixels. A project-written serializer
model would establish only its modeled contract, not device behavior.

This first bench path is **RGB-only DVI-style transport** through the board's
display connector. It generates no HDMI audio packets or data islands and has
no implemented EDID/hot-plug negotiation. Audio uses the separate I²S pins.
It is not a claim of full DVI/HDMI compliance or compatibility with every monitor.
The [backlit handheld display](../research/display-selection.md) remains open.

## What must close before a complete-board pass

The [complete bench build](../milestones/tang-board-build.md) now maps, routes
and fuse-packs the corrected true-LVDS design. It records all 79 pin assignments,
eight clock targets and partial-model frequency results. The remaining rows
below are qualification requirements; successful packing does not close them.

| Area | Required next evidence |
| --- | --- |
| Actual top-level I/O | Review [lynx_tang_board.sv](../../hardware/boards/tang_nano20k/lynx_tang_board.sv); constrain every port using the correct package and embedded-memory pads |
| Clock generation | Verify input profile, legal PLL parameters, generated clock relationships, routing and reset recovery |
| SDRAM boundary | Check shifted-clock command/data setup and hold, read sampling, turnaround and electrical behavior |
| Video output | Establish OSER10 word alignment, lane/bit ordering, differential buffer/pin legality and clock/data relationship |
| Timing coverage | Name each analyzed clock and I/O path; document cross-domain structure and any tool limitations or exceptions |
| Reproducibility | Nix synthesis, placement, routing and packing; preserve resource/timing reports and source/license bundle |
| Real board | Original diagnostic, observed video/audio and memory checks under the deferred physical acceptance gate |

A successful route or pack alone is insufficient if required clocks or I/O
paths were not analyzed. Timing exceptions require review of what the pinned
tool actually applies. Keep the [complete-build gate](../roadmap.md#4-complete-tang-build-next-implementation-gate)
open until these requirements are satisfied.

## Reproduce the current digital checks

```sh
nix --extra-experimental-features 'nix-command flakes' build \
  .#dvi-encoder-check .#board-control-check --no-link -L
```

Both recipes live in [nix/tang-board.nix](../../nix/tang-board.nix). Their
artifacts contain compilation/test logs, tool version, scoped JSON and a
reference to the exact source snapshot. No FPGA is programmed by these checks.
