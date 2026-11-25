# Tile planes and composition

Two scrolling tile planes are implemented and merged with the object surface
during scanout. The RTL is [cb_tile_planes.sv](../../hardware/enhanced/cb_tile_planes.sv)
and the merge is in [cb_native_scanout.sv](../../hardware/enhanced/cb_native_scanout.sv).
It passes the system test in simulation and routes on the Tang; it has not run
on hardware. Earlier notes talked about eight planes. Two is what exists, and
the section on [growing it](#growing-it) says what more would cost.

{{chip-diagram:compositor}}

## What a plane is

A plane is a 64 × 32 map of 8 × 8 tiles, 512 × 256 pixels, that wraps in both
directions. The screen is a 320 × 204 window onto it, placed by a 9-bit X and
an 8-bit Y scroll. Plane 0 is drawn behind the object surface and plane 1 in
front of it.

Both planes share one set of 256 patterns. A pattern row is one 32-bit word:
eight 4-bit pixels, leftmost in bits 3:0. Pixel value 0 is transparent.

A map entry is 16 bits:

| Bits | Field |
| --- | --- |
| 7:0 | Tile number |
| 9:8 | Unused, write zero |
| 10 | Flip horizontally |
| 11 | Flip vertically |
| 15:12 | Palette bank; the color index is bank × 16 + pixel |

Tile memory is addressed in words through the port at `$4510`:

| Word address | Contents |
| --- | --- |
| `$0000`–`$07FF` | Patterns: tile × 8 + row |
| `$1000`–`$17FF` | Plane 0 map: row × 64 + column |
| `$1800`–`$1FFF` | Plane 1 map |

## Why block RAM

The obvious home for maps and patterns is SDRAM, next to the sprite data. We
did not put them there because the memory bus is the scarce thing in this
machine. The blitter's dense scenes already use most of a frame's worth of
bus time, and scanout takes 160 reads per row on top. Two planes fetched from
SDRAM would add a map read and a pattern read per plane for every eight
pixels, about 80 more reads per row, all with a display deadline.

In block RAM the planes cost no bus time and their timing is fixed. The price
is eight of the 46 block RAMs and a hard ceiling: 256 tiles, two maps. A game
that wants more variety has to rewrite patterns between scenes.

## The fetch

Scanout asks for one row at a time. `start` latches the row number and both
scroll values. After that the plane logic offers one pixel from each plane and
advances when scanout takes it.

Per plane it keeps the current pattern row in a 32-bit register and selects a
nibble by the low three bits of the world X position. When X crosses a tile
boundary the row is stale and one small state machine refills it: read the map
entry, then read the pattern word, four clock cycles in all, one plane at a
time. Scanout waits if the pixel is not ready. In practice the refill overlaps
the SDRAM read scanout is waiting for anyway, so planes add very little to the
time a row takes.

Vertical flip inverts the row number before the pattern read. Horizontal flip
inverts the nibble select. A disabled plane reports ready and transparent.

## Priority

For each pixel, the first of these that applies wins:

1. Front plane pixel, unless the surface pixel is covered and its band is 8 or more
2. Covered surface pixel
3. Back plane pixel
4. Nothing: the pixel is black

So bands 0–7 put a sprite between the planes and bands 8–15 put it in front of
everything. Only the top band bit means anything today; the other three are
stored and ignored. Sprites are ordered among themselves by draw order: the
blitter overwrites, so the last one drawn is on top.

The winner is stored in the line buffer as a palette index. Color lookup
happens later, in the pixel clock domain, from the one 256-entry palette that
sprites and planes share.

## When changes take effect

Scroll values and plane enables are staged by the CPU and applied at the frame
boundary by the same request that swaps surfaces, so a frame's sprites and its
scroll always arrive together. See the
[video registers](../architecture/native-graphics-mmio.md#video-control-at-4500).

Tile memory is different: a write lands immediately. Changing a map or pattern
that is on screen shows partway down the frame. Load tiles while the plane is
disabled or off screen, or accept the tear.

There is no per-line scroll. Each row latches the scroll registers when its
fetch starts, so the hardware path for it exists, but the registers only
change at the frame boundary and there is no raster table.

## Tests

The [system test](../../sim/enhanced-system.cpp) runs the demo ROM, which loads
four tiles, fills both maps with every flip and palette-bank combination, and
scrolls the planes in different directions under four scaled sprites, two in
bands below the front plane and two above. Each captured frame must match a
separately written C++ model of the same rules.

To check that the test can fail, seven deliberate faults were put into the RTL
one at a time: each flip ignored, palette bank dropped, scroll bit 8 dropped,
the band rule removed, the tile-boundary refill skipped and the scroll latch
disconnected. All seven were caught.

Not tested: a plane disabled while the other is on, scroll values beyond the
first few frames of motion, tile writes during display, and any scene heavy
enough to make scanout wait for the bus.

## Growing it

- **More planes.** Each extra plane is another 4-cycle refill per tile and one
  more map. The pattern RAM can be shared. At four planes the refill no longer
  hides behind the SDRAM read and the row budget needs measuring.
- **More tiles.** 256 patterns is four block RAMs. Doubling it is four more.
- **Per-line scroll.** Needs a 204-entry table per plane and a rule for when
  the CPU may write it.
- **8 × 8 tiles only.** Larger tiles or 8-bit pixels change the pattern word
  and the refill, not the priority logic.
