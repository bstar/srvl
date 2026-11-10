# Circuit Courier software prototype

The 65C02 ROM is an original four-circuit maze game: collect three packets, avoid
the guards, and reach the delivery dock. The ROM executes on the pinned R65C02 HDL
core. Custom HDL draws tiles/sprites and generates audio; SDL transports the
pixels, input, and sample stream. Physical MiSTer verification is deferred.

Movement follows lanes while you hold a direction; release all directions to
stop immediately, even inside a corridor. Request a turn before an intersection
to buffer it while held; releasing it cancels that request. Reverse at any time. Walls
block exits and diagonal movement. X/B slows the courier for precise positioning.

Circuits have two, three, four and five guards, with different chasing,
interception, defense and patrol behavior. Guards follow the same maze, travel
at most half your normal speed, and cannot cross walls. Press Z/Space/A while
**JAM READY** to freeze them and pass through them harmlessly for one second.
The pulse recharges in 2.5–4 seconds, with longer waits on later circuits.

Boot Sector, Mirror Bus, Reverse Flow and Cross Circuit each generate a fresh
route on every attempt, including retries. Each has a distinct connected maze;
later circuits have fewer shortcuts. Spawn, cards and dock are randomized on
separated junctions. Press A (Z/Space/Enter)
after delivery to advance; after circuit four it replays the campaign.
`TIME` shows the current circuit split and `TOTAL` is your score: lower is better.
Both use `MM:SS.mmm`, including thousandths, from hardware millisecond counters.
Menus and pause are excluded; failed attempts remain in total when you retry.
A new campaign or reset clears the score.

Finish **before the BEAT time** to qualify for the next circuit. The target scales
with your actual route length, and gets stricter on each circuit. Taking too long
loses the attempt even if you avoid the guards. Targets use actual maze distances.
Plan turns, use alternate corridors and save a jam pulse for an interception.

## Run

From the project root:

```sh
nix --extra-experimental-features 'nix-command flakes' run .#sim
```

| Control | Keyboard |
| --- | --- |
| Move | Arrow keys or WASD |
| Jam guards while playing | Z or Space (controller A) |
| Connect, retry, next circuit, replay | Z, Space, or Enter |
| Slow movement | Hold X |
| Pause/resume simulation | P |
| Reset the HDL machine and reboot ROM | R |
| Fullscreen | F11 |
| Quit | Escape or close window |

SDL-recognized controllers support D-pad/left stick, A/B, Start, and Back.
Physical controller models have not been individually verified. Losing window
focus clears held input so the drone does not remain stuck moving.
The display uses integer nearest-neighbor scaling, preserving native pixels.

The desktop session supplies the display/audio services. Build dependencies and
runtime libraries are Nix-managed. No Quartus, FPGA, Atari ROM, installed SDL
development package, or global executable installation is needed.

## Checks and evidence

```sh
nix --extra-experimental-features 'nix-command flakes' flake check -L
nix --extra-experimental-features 'nix-command flakes' build .#checks.x86_64-linux.game -o build/game-check -L
nix --extra-experimental-features 'nix-command flakes' build .#cpu-functional -o build/cpu-tests -L
nix --extra-experimental-features 'nix-command flakes' build .#simulator-equivalence -o build/simulator-equivalence -L
nix --extra-experimental-features 'nix-command flakes' run .#sim -- --benchmark 120
```

Default checks include directed CPU tests, peripheral tests, original-ROM gameplay,
the prior bring-up tests, toolchain smoke checks, and documentation links/ADRs.
The longer CPU target runs the pinned independent functional ROM suites. Run it
after changing the CPU, its patch, or translation pipeline.

Game tests use SDL's dummy video/audio drivers and inject input through the same
SDL event handler as the desktop. They check ROM boot, CPU-executed RAM/ROM and
unmapped-bus diagnostics, rendered pixel replication, movement and slow mode,
guard contact and its speed limit, connected mazes, rail movement, blocked exits,
buffered turns and reversals, jam freeze, increasing guard counts, full qualifying
clears on all four circuits, graph-based deadlines, menu/pause freezes, retry
penalties, score accumulation and replay,
reset, pause, and digital audio. They export actual
HDL screenshots and a stereo WAV under `build/game-check/`. The equality target
compares snapshots and audio from flat and hierarchical versions of the same HDL.
Neither host test mode implements game rules or patches emulated RAM to force wins.

The native machine target is 60 Hz. The benchmark measures unthrottled emulation
speed on this host, separately from the frame pacing used by the desktop app.
`--frames N` runs a bounded interactive session; `--screenshot FILE.ppm` captures
the native frame on exit. `--no-audio` permits visual work without an audio device.

## Implementation boundaries

- [SoC](../hardware/rtl/chipbuilder_soc.sv): CPU, RAM, ROM, and bus decode.
- [CPU adapter](../hardware/rtl/chipbuilder_cpu.sv): pinned VHDL CPU boundary.
- [Custom peripherals](../hardware/rtl/chipbuilder_peripherals.sv): pipelined
  tiles/glyphs, four sprites, palette, oscillators, input, IRQ, and frame-wait.
- [Original ROM](../firmware/courier.s): all game behavior and hardware setup.
- [Memory map](../docs/architecture/software-prototype.md) and
  [architecture decision](../docs/architecture/decisions/0005-prototype-cpu-and-peripherals.md).

This is a software prototype, with no game-capable MiSTer adapter yet. The earlier
`prototype` RBF remains the separate display/input/audio bring-up circuit. The
prototype clock gate needs dedicated clock-control resources in a physical
adapter. Lynx games, full cycle compatibility, ASIC/PCB timing, and final hardware
budgets are not established by this milestone.

## CPU source and license

The generated CPU package retains the pinned VHDL source, local correction patch,
and upstream GPL-3.0-or-later license. The simulator references them under
`share/chipbuilder/cpu-source/`; its original ROM sources and assets are under
`share/chipbuilder/rom/`. The new project files retain their individual SPDX
notices. No project-wide relicensing claim is made here. See
[CPU research](../docs/research/cpu-selection.md) for choices and known limits.
