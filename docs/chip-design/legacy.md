# Lynx compatibility logic

Reviewed: **2026-11-17**. Status: **scoped core evidence exists; playable Tang
board integration remains incomplete**. This diagram separates reused console
behavior from our new presentation and board-support logic.

## Preserve behavior, replace the board services

The pinned upstream implementation supplies the Lynx CPU, Suzy and Mikey. Our
port keeps the core's clock and original-visible behavior while adapting storage,
loading, controls, sound transport and display. Original 64 KiB work RAM stays
local. The original CPU is not replaced by the native prototype's R65C02.

{{chip-diagram:legacy}}

## Compatibility boundary

| Reused or retained | Adapted by this project | Evidence still required |
| --- | --- | --- |
| Upstream CPU execution and original register map | Board reset/clock adapter | Full instruction/interrupt/peripheral cases and real game timing |
| Suzy sprites, math and collision behavior | Memory/core wrapper | Focused sprite RLE/scaling/collision and arithmetic cases |
| Mikey timers, audio and display DMA | Digital audio/output transport | Timer/IRQ/audio checks and physical output |
| Local work RAM behavior | Inferred RAM with explicit own-port forwarding | Existing model comparison covers defined cases; primitive/physical checks remain |
| Core cartridge/BIOS interfaces | Host loader and SDRAM-backed cartridge access | Length/header/bank/byte-order/reset/commit cases |
| Emitted RGB444 pixel values | Presentation storage, scaling and final display | Pixel-exact capture, frame ownership, cadence and real-board video |

## Capture colors when they happen

Palette changes can occur during a frame. Capture each emitted RGB444 sample,
not just the 4-bpp index plus one final palette. The latter would reconstruct the
wrong colors for raster effects. A padded 16-bit presentation format simplifies
storage; it does not reduce the original palette's fidelity.

The logical 2× mapping is exact: source `(x, y)` supplies destination
`(2x, 2y)`, `(2x+1, 2y)`, `(2x, 2y+1)` and `(2x+1, 2y+1)`. This fills the full
**320×204 logical screen with no added borders**. Final physical adaptation must
preserve the complete image and border-free visible area. Original game execution
speed is independent of the panel's refresh rate.

<figure class="logical-lynx-preview">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="160 138 320 204" width="320" height="204" role="img" aria-labelledby="logical-lynx-preview-title">
<title id="logical-lynx-preview-title">Exact two-times Lynx image filling the 320 by 204 logical screen</title>
<image href="../images/tang-video-pattern.png" x="0" y="0" width="640" height="480"></image>
</svg>
<figcaption>320×204 logical viewport from the real-core diagnostic: every original pixel occupies exactly 2×2 pixels, edge to edge. This view shows the logical image; the existing full bench transport is recorded below.</figcaption>
</figure>

## What the audit actually says

The 2026-11-17 registered core probe, including the warm-reset correction, fits
**11,710 / 20,736 LUT sites**, **33 / 46 block RAMs** and passes its **64 MHz**
constraint, with an estimated **81.833 MHz** maximum.
It omits the real board services shown outside the retained-console boundary.
Its historical maximum uses partial timing-model coverage: the later
[board review](../milestones/tang-board-build.md#timing-coverage-is-a-measured-boundary)
found missing small-LUT and DSP models. Do not treat it as complete path timing.
The original diagnostic and defined-behavior RAM-model comparison passed.

Serial cold/warm loading and held/released-input RGB checks now pass through the
actual core, loader, cartridge cache and modeled SDRAM. The separate frame-capture
component also passes its delayed-write checks. Their original checks exclude
physical display transport; [the service milestone](../milestones/tang-board-services.md)
records that scope. The buffered-output section below records the newer logical
RGB integration.

No commercial games have been tested on Tang, and there is no physical Tang
acceptance yet. Those numbers do not establish enhanced-engine fit or complete
board timing. The [full audit](../research/lynx-tang20k-compatibility.md) preserves
the exact source revision, methods, logs and exclusions.

## Scope beyond the first port

ComLynx and physical cartridges require separate electrical and compatibility
work. The first target is unmodified owner-supplied game images. Recompiling or
decompiling games remains deferred and is not a substitute for that goal.

## Buffered output and clock crossing

{{chip-diagram:scanout}}

The portable path now passes component contention/reset/deadline tests and an
actual serial-loaded console diagnostic. It emits a centered 320×204 logical
canvas within 640×480 RGB timing. Every pixel is compared against a complete
emitted source frame, with exact 2× replication and black borders. The line
buffers map to one block RAM; the integrated portable system uses 35 block RAMs.
These are software and mapping results. Serializers, clock/pin constraints,
full-board timing and physical output remain ahead. Digital stereo I²S now also
passes [actual-core audiovisual tests](../milestones/tang-audio.md). The
[video milestone](../milestones/tang-video.md) records the contract, previews,
reproduction commands and exclusions.

The next boundary is documented in [clocks and display output](board-output.md):
digital TMDS encoding and reset/activity-control checks pass, while the
primitive serializers and complete board timing remain unqualified.
