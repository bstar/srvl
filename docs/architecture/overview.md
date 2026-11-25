# System architecture

Chipbuilder is a handheld console built in an FPGA: an imagined mid-1990s
successor to the Atari Lynx. It has to do two things. It runs original Lynx
software unchanged at 160 × 102, shown as exact 2 × 2 blocks. And it runs new
games at 320 × 204 on a faster 65C02 with graphics hardware of our own design:
a scaling blitter, scrolling tile planes and, later, flat-shaded triangles.

Everything currently targets one board, the Tang Nano 20K (GW2AR-18 with 8 MiB
of SDRAM in the package). Nothing has run on the board yet. All results quoted
in these pages come from simulation and from the open place-and-route tools.

## Two configurations, one board

The two jobs are separate FPGA images. They share the SDRAM controller, the
memory arbiter, the video output stage and the clock and reset blocks, and
nothing else.

| | Legacy | Enhanced |
| --- | --- | --- |
| CPU | Upstream Lynx core: its CPU, Suzy and Mikey | Pinned R65C02 core at 8 MHz |
| CPU memory | 64 KiB work RAM in block RAM | 8 KiB RAM and 32 KiB ROM in block RAM |
| Graphics | The original Lynx hardware, as translated upstream | Our blitter, tile planes and scanout |
| SDRAM holds | Cartridge image, three captured RGB frames | Sprite sources, two indexed surfaces |
| Top level | [lynx_tang_system.sv](../../hardware/tang/lynx_tang_system.sv) | [cb_enhanced_system.sv](../../hardware/enhanced/system/cb_enhanced_system.sv) |
| Detail | [Tang prototype](tang-prototype.md) | This page, then the [chip design handbook](../chip-design/overview.md) |

They are separate because they do not fit together. The legacy image uses 35 of
the 46 block RAMs and the enhanced one 29. They also use different CPU cores,
and the Lynx core's bus timing is part of what makes old games behave correctly.
A single image that switches modes would need a different FPGA or a different
memory plan; neither is being pursued now.

## The enhanced machine

```
            8 MHz                               64 MHz                         25.2 MHz
   ┌─────────────────────┐        ┌──────────────────────────────┐      ┌────────────────────┐
   │ R65C02              │        │ scaled blitter               │      │                    │
   │ RAM  $0000-$1FFF    │ $4400  │   draws into the back surface│      │                    │
   │ ROM  $8000-$FFFF    ├───────►│                              │      │                    │
   │                     │        │ tile planes (block RAM)      │      │                    │
   │                     │ $4500  │   two scrolling 8x8 maps     │      │                    │
   │                     ├───────►│          │                   │      │                    │
   └─────────────────────┘        │          ▼                   │      │                    │
                                  │ scanout line fill            │ line │ palette, 2x repeat │
                                  │   surface row + planes ──────┼─────►│ 640x480 timing     ├──► TMDS
                                  │          ▲                   │ bufs │                    │
                                  │ arbiter ─┴─ SDRAM controller │      │                    │
                                  └──────────────┬───────────────┘      └────────────────────┘
                                                 ▼
                                         8 MiB SDRAM, 32-bit
```

### Clocks

| Domain | Rate | What runs in it |
| --- | --- | --- |
| System | 64 MHz | SDRAM controller, arbiter, blitter, tile-plane fetch, scanout line fill |
| CPU | 8 MHz, divided from the system clock | CPU, its RAM and ROM, register files, palette and tile memory write ports |
| Pixel | 25.2 MHz, with a 5× serializer clock | Video timing, line-buffer read, palette lookup, TMDS |

The three are treated as unrelated. Single bits cross through two flops as
toggles; anything wider is held still by its sender until the toggle has been
acknowledged. There are no asynchronous FIFOs on the enhanced side.

Block RAM on this part has rising-edge clocks only, so the CPU's memories use
the rising edge of the 8 MHz clock and the CPU's own registers the falling edge
of the same net. An address settles for half a cycle, the RAM samples it, and
the CPU captures the data half a cycle later. The earlier software prototype
used a gated clock for the CPU; that cannot be built and is gone from this path.

### What the CPU sees

| Address | Size | Contents |
| --- | --- | --- |
| `$0000` | 8 KiB | Work RAM |
| `$4400` | one page | Graphics commands: a 36-byte descriptor, submit, status, counters |
| `$4500` | one page | Video: swap, palette, plane scroll, tile memory port |
| `$8000` | 32 KiB | ROM |

Both register pages are generated from
[graphics-abi.json](../../hardware/enhanced/graphics-abi.json) into the assembler
include and the SystemVerilog package, and the build fails if the checked-in
copies drift. The [register reference](native-graphics-mmio.md) has the bit
fields. The CPU has no direct view of SDRAM. It uploads bytes through a command
and never waits on memory: registers answer in the same cycle and commands
complete in the background.

### Where pixels live

SDRAM holds two 320 × 204 surfaces at `$100000` and `$140000`. A surface pixel
is 16 bits, two to a memory word:

```
 15      13   12     11       8   7            0
 ┌─────────┬───────┬───────────┬───────────────┐
 │    0    │covered│   band    │ palette index │
 └─────────┴───────┴───────────┴───────────────┘
```

The blitter writes whole pixels and never reads the destination. A fill can
write uncovered pixels, which is how a frame is cleared so the planes show.

Tile planes do not touch SDRAM at all. Patterns (256 tiles of 8 × 8 pixels at
4 bits) and two 64 × 32 maps sit in eight block RAMs. That costs block RAM we
could have spent elsewhere, but it means adding planes took nothing from the
memory bandwidth the blitter needs, and a plane fetch can never be late.

### One frame

1. The CPU reads which surface is in front and draws into the other one:
   a clear, then sprites, each a descriptor written to `$4400` and submitted.
2. It writes the plane scroll values for this frame, then one control write
   that asks for a swap and a latch of the plane settings together.
3. At the end of the visible raster the scanout takes the request. Front
   surface and plane settings change in the same cycle and then hold for all
   204 rows. The CPU sees `SWAP_PENDING` clear and `FRONT` flip together.
4. For each row, the line fill reads 160 words of the front surface. For each
   pixel it picks, in order: the front plane unless the surface pixel is
   covered with band 8 or above; the covered surface pixel; the back plane;
   otherwise black. The winning palette index goes into a line buffer.
5. The pixel domain reads the line buffer, looks up RGB444 in the palette and
   shows each row twice and each pixel twice: 640 × 408, centered in 640 × 480.

A row is fetched while the one before it is on screen, so the fill has two
output lines to finish: about 4,060 system clock cycles. A memory read takes
roughly 6 cycles when the bus is free and 12 when the blitter is also working,
which puts a row between 1,300 and 2,300 cycles. That figure is an estimate
from the controller's timing, not a measurement under heavy drawing. If a row
is late it is shown black, both copies, and an underrun flag is set.

### Rules the design holds to

- **Whole frames only.** Nothing the CPU does mid-frame reaches the screen
  until the next swap. Drawing into the surface that is on screen sets a sticky
  fault the program can read. It is detected, not prevented.
- **One owner of the SDRAM pins.** The CPU byte port, the blitter and scanout
  are equal clients of one round-robin arbiter. Scanout has no priority yet.
- **No clock made from logic.** The mapping check fails if any clock pin is
  driven by anything but a PLL or a clock divider.
- **Tests draw nothing.** The system test only supplies clocks and an SDRAM pin
  model. The CPU runs a ROM, and every captured frame must equal one frame of a
  separately written model of what that ROM draws.

## The legacy machine

The Lynx core is taken from upstream at a pinned revision and used as it is.
Around it we replaced what was MiSTer-specific: work RAM is a local 64 KiB
block RAM, the cartridge is read from SDRAM through a small byte cache, and a
loader on the board's USB serial port writes images in.

Video is captured, not re-rendered. Lynx games change palettes mid-frame, so
the RGB that the core emits is written to SDRAM as it appears, into one of
three frame banks, and only complete frames are handed to the scanout. Audio
goes through a low-pass filter to 48 kHz I²S on a third clock. The
[Tang prototype](tang-prototype.md) page covers this in detail.

## Not built

- Input, audio and a game loader on the enhanced side. Its only program is a
  demo ROM compiled into the image.
- Triangles and fixed-point math. See [geometry](../chip-design/geometry.md).
- Per-line scroll, more than two planes, tile maps larger than 64 × 32.
- Display priority at the memory arbiter, and any measurement of the scanout
  deadline under a dense scene.
- Everything physical: board bring-up, the LCD, power, the PCB and the case.
  The [roadmap](../roadmap.md) orders that work and
  [open decisions](../tradeoffs.md) lists what is waiting on a choice.

## Earlier designs

The project began on MiSTer and then planned an ECP5 board before settling on
the Tang. The [software prototype](software-prototype.md), a playable maze game
with fixed-size sprites, still runs in simulation and is kept as a regression.
The [ECP5 contract](standalone-platform.md) and the
[external CPU study](hybrid-hardware.md) are history. Their numbers do not
describe this machine. The [decision records](decisions/README.md) say why each
turn was taken.
