# CPU-driven software prototype

Status: software implementation and functional verification complete. This describes the first
original-ROM machine, not the Lynx compatibility specification or final hardware.
See [ADR 0006](decisions/0006-maze-game-and-sprite-budget.md), which carries
forward the CPU/system choices from ADR 0005 and expands the sprite budget.

The R65C02 CPU, memories, and custom peripherals are HDL. GHDL translates the
pinned VHDL CPU into Verilog, and Verilator compiles the machine for simulation.
The desktop frontend displays 320×204 HDL pixels and forwards input bits. An
original ca65 assembly ROM implements Circuit Courier's rules.

## Clock and video

The master clock is 6,288,000 Hz. The raster is 400×262 clocks, with a native
320×204 visible area, giving exactly 60 logical frames/second. No renderer exists
in the host frontend. Tile/attribute fetch and font lookup occupy two pipeline
stages; sync, display enable, and coordinates receive the same delay.

The tile map has 40 columns and 26 rows; the last tile row is only partly visible.
Each of its 1,040 active cells has an 8-bit tile/glyph ID and an 8-bit attribute:
foreground palette index in the upper nibble, background in the lower nibble.
The banks reserve 2,048 entries each. The original 256-glyph 8×8 mask ROM occupies
2 KiB. Eight sprites each select one of eight 16×16 two-bit masks, with transparent,
shadow (palette 1), body (selected palette), and highlight (palette 15) inks.
Slot 0 has highest priority. Sprite ROM occupies 512 bytes. Eight sprite slots
share those eight patterns; the game assigns slots 0/1 to courier/card, 2–6 to
guards and 7 to the delivery dock.

## Prototype memory map

| Range | Purpose |
| --- | --- |
| `$0000–$1FFF` | 8 KiB work RAM, including zero page and stack |
| `$2000–$27FF` | Tile/glyph IDs |
| `$2800–$2FFF` | Tile attributes |
| `$4000–$401F` | 16 palette entries, two bytes each |
| `$4020` | Display enable, bit 0 |
| `$4021–$4022` | Beam Y, low byte and bit 8 |
| `$4023` | Frame IRQ enable, bit 0 |
| `$4024` | Frame IRQ pending, bit 0; write 1 to acknowledge |
| `$4025–$4026` | Frame counter, low/high bytes |
| `$4027` | Frame-wait request/readback, bit 0 |
| `$4030` | Frame-latched controller bits |
| `$403F` | General software diagnostic latch |
| `$4040–$4043` | Level millisecond stopwatch: control, low byte, latched middle/high |
| `$4044–$4047` | Total millisecond stopwatch, same register layout |
| `$4100–$413F` | Eight sprites, eight registers each |
| `$4300–$4307` | Left voice |
| `$4308–$430F` | Right voice |
| `$8000–$FFFF` | 32 KiB ROM; writes ignored |

Unmapped reads return zero; unmapped writes have no effect. RAM/VRAM contents
are not cleared by reset. The ROM initializes its working state and VRAM before
enabling the display. Reset clears peripheral controls, palette, sprites, pending
IRQ, diagnostic latch, stopwatch state, and audio state. ROM reads are combinational; CPU data
is available on dummy cycles too.

Palette byte 0 contains `GGGGBBBB`; byte 1 contains `0000RRRR`. Reserved high
bits in byte 1 are masked. Each four-bit output component is expanded to eight
bits by repeating the nibble.

## Sprite registers

The offsets below are relative to `$4100 + slot×8`.

| Offset | Meaning |
| --- | --- |
| 0 | X low byte |
| 1 | X bit 8 in bit 0 |
| 2 | Y |
| 3 | Pattern index, bits 0–2 |
| 4 | Body palette index, bits 0–3 |
| 5 | Enable bit 0, horizontal flip bit 1, vertical flip bit 2 |
| 6–7 | Reserved, stored but not rendered |

## Input, IRQ, and frame-wait

Controller bits are Right, Left, Down, Up, A, B, Start, Select in bit order 0–7.
Input is sampled when blanking begins at beam `(0,204)`. That event also sets
pending IRQ and releases frame-wait. IRQ masking preserves pending status.
A new event wins over an acknowledgment on the same clock.

A frame-wait request is refused if a frame is already pending, avoiding the
check-then-sleep race. Firmware masks interrupts while checking its tick counter
and requesting sleep, then reenables them. The CPU clock stops on a low-clock
boundary and resumes when the next frame event arrives. Its state is retained;
the other peripherals keep running. The HDL prototype's gate must be adapted to
dedicated clock-control hardware before physical FPGA acceptance.

## Audio

Each voice has a 24-bit phase accumulator updated every master clock. Register
offsets 0–1 set a little-endian 16-bit phase increment, offset 2 sets a four-bit
volume, and offset 3 bit 0 gates output. Other voice offsets read zero.
Square-wave frequency is `6,288,000 × increment / 2²⁴` Hz; amplitude is ±128×volume.
The two voices feed independent signed 16-bit stereo channels.
Their phases are independent; sequential register writes do not promise
sample-identical channels at zero crossings.

The desktop frontend samples the actual outputs every 131 master clocks, giving
48,000 stereo pairs/second, exactly 800 pairs/frame. Firmware programs both
channels for its cues. Host audio playback and logical hardware clocks remain
distinct; benchmarks measure whether this host can keep up in real time.

## ROM maze gameplay

Circuit Courier now runs on four connected 8×4 junction graphs. Junctions are
32 pixels apart; corridors and wall cells are 16 pixels wide. The courier moves
at two pixels per frame (one while holding X/B) while a direction is held.
Releasing the directions stops it immediately without changing its edge position.
Held turn requests buffer until a junction; released requests are discarded.
Blocked exits stop motion, and reversals are allowed immediately inside a corridor.
Diagonal shortcuts and wall
crossings are impossible for both courier and guards.

Collect three ordered data cards and reach the delivery dock before the BEAT
time. This retains the original delivery objective rather than clearing pellets.
Every retry shuffles object positions on the maze. All movement, AI, collision,
jam controls, randomization and scoring execute in the 65C02 ROM.

Maze authoring uses a deterministic spanning tree plus extra links to create
loops. Circuits 1–4 contain 46, 43, 40 and 38 undirected links respectively, so
later layouts have more obstructions. `scripts/make-mazes.py` emits graph masks,
tile layouts and all-pairs shortest-path distances. Nix regenerates and compares
`firmware/maze-data.inc` before assembling. Every node is verified reachable and
all edges reciprocal. The tables occupy ROM; no host pathfinding runs during
interactive play. Junction steering is a small distance-table lookup on the CPU.

## Guards and jam pulse

Circuits contain two, three, four and five guards. Each travels along the same
rails, moves at most one pixel per frame, and avoids reversing except at dead
ends. First-circuit guards move on three of four frames; later guards move on
every frame. Even the fastest guard moves at half the normal courier speed.

The red chaser targets the current courier junction; the purple ambusher targets
its next junction. The orange warden defends the active card/dock until the
courier is nearby, then pursues. The blue patroller heads between circuit corners;
the final gold hunter adds another interception threat. Different body colors
make these roles visible. Contact within ten pixels on both axes loses the
attempt unless the guards are jammed.

Pressing Z/Space/controller A while JAM READY freezes all guards and makes them
harmless for 60 frames (one second). Their body color changes during the jam;
the courier can pass through them to escape a blocked corridor. Recharge takes
150, 180, 210 or 240 frames (2.5–4 seconds) from activation as difficulty rises.
The HUD distinguishes ready, active and recharging states. Card pickups do not
reset the jam cooldown. Pause and results screens freeze gameplay counters.

## Circuits and timed score

The campaign retains four named circuits and distinct border colors. A advances
after a qualified delivery; after the fourth it starts a new campaign. Losing
retries the same difficulty with a fresh route. Enemy pressure rises through
numbers, roles, topology and jam recharge, with a fixed one-pixel speed ceiling.

A 16-bit Galois LFSR (mask `$B400`, eight steps per output byte) supplies ROM
random choices. Campaign start mixes in the frame counter; identical input
sequences remain reproducible. Fisher–Yates shuffles 32 junctions. Greedy placement
selects five unique object nodes at least two links apart, then distinct guard
spawns at least three links from the courier and away from object nodes. This
provides reachable pickups and initial reaction distance without host randomness.

The HUD's `BEAT MM:SS.mmm` is a strict qualifying deadline. Let D be the sum of
the shortest graph-path lengths along spawn → card 1 → card 2 → card 3 → dock,
in pixels (32 per link). Limits are `2000 + D × C` milliseconds, with C equal to
18, 17, 16 and 15 for circuits 1–4. This accounts for walls instead of using the
old straight-line distance. Checks run every game update and again on the frozen
delivery sample. Reaching the limit produces `TOO SLOW - A RETRY` and prevents
progression.

`TIME MM:SS.mmm` shows the circuit split; `TOTAL MM:SS.mmm` is the campaign score,
with lower totals better. Failed attempts count. Retry resets the split, while
campaign replay/reset clears both clocks. Loss, delivery, menus and simulation
pause freeze the relevant clocks.

Two custom hardware stopwatches count milliseconds independently of the frame
IRQ and CPU sleep. Each uses a 13-bit divider (6,288 master clocks per tick), a
24-bit millisecond counter and a latched upper 16 bits. At offsets 0–3:

| Offset | Meaning |
| --- | --- |
| 0 | Bit 0 run/stop; writing bit 1 resets elapsed count, divider and snapshot. Readback returns run only. |
| 1 | Current low byte; a clocked read snapshots the upper two bytes. |
| 2 | Snapshotted middle byte. |
| 3 | Snapshotted high byte. |

Read low, then middle, then high to obtain a coherent sample across carries.
Stop/resume preserves the fractional millisecond divider; reset clears it.
Counters saturate at 5,999,999 ms (`99:59.999`) instead of wrapping. Reset wins
over a coincident increment. Counter data bytes are read-only.

The ROM converts each 24-bit sample to minutes, seconds and three fractional
digits using bounded decimal-place subtraction. Timing resolution is 1 ms;
live timer digits refresh at 30 Hz, with an immediate final sample when a circuit
ends; gameplay and controller updates remain at 60 Hz. No host wall clock or rounded
16-ms-per-frame approximation contributes to scores. Peripheral checks verify
exact tick cadence, independent control, pause/resume and coherent rollover;
game checks verify formatted times, one-second drift, frozen menus, retries,
accumulation, connected layouts, rail/wall/turn invariants, jam freeze, increasing
guard counts, randomized placements, graph-based qualification, all four clears
and campaign replay.
