# 0003: Enhanced and legacy rendering resolutions

Date: 2026-10-28
Status: Accepted

## Context

The user wants new games to render at twice the original Lynx's width and height,
with existing games simply doubled visually. A backlight is required.

## Decision

Enhanced games render natively at 320 × 204. Legacy games retain 160 × 102 rendering
and use exact 2× pixel replication into the enhanced logical display area.
Keep physical LCD adaptation separate from game rendering. Require a color LCD
with backlighting; leave the panel and interface selection open.

## Consequences

Scope clarification, 2026-10-29: the initial Lynx path runs unmodified game images
at their original logical resolution and replicates each output pixel into a
2×2 block. Native-resolution patches, decompilation/recompilation and enhanced
ports are deferred possibilities, not requirements for initial compatibility.
The custom enhanced graphics engines serve new native games independently.

Enhanced mode has four times the pixels. At 4 bits per pixel, a framebuffer grows
from 8,160 to 32,640 bytes; two enhanced buffers require 65,280 bytes before
collision data or game memory. Enhanced color depth and buffering policy are not
selected by these calculations. Legacy scaling belongs in output hardware and
must preserve game-visible timing. A 60 fps enhanced target guides display
evaluation, but a 60 Hz input specification alone does not establish motion quality.

## References

- User resolution and backlight requirements, 2026-10-28.
- [Display research](../../research/display-selection.md)
- [Lynx hardware research](../../research/lynx-hardware.md)
