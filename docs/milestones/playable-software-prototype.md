# Playable software prototype

Date: 2026-10-28
Status: Complete for software acceptance. Physical MiSTer testing remains deferred.

## Goal and acceptance

Build and run an original playable ROM on a reused 65C02-compatible HDL CPU and
custom video/audio/input hardware, using an interactive Nix-managed simulator.
Physical MiSTer verification is deferred and is not an acceptance gate here.

| Requirement | Evidence/status |
| --- | --- |
| Licensed CPU source and reproducible pin | R65C02 GPL-3.0-or-later; exact revision in `flake.lock` |
| CPU functionality | Pinned 6502 and 65C02 functional ROMs pass; reports in `build/cpu-tests/` |
| Directed CPU checks | Reset vector, selected instruction bus cycles, RAM writes, and BRK status regression pass |
| Original ROM boots through CPU | Circuit Courier title booted in an HDL SoC probe |
| Prototype bus, video, audio, input checks | Nix peripheral check passed |
| Interactive desktop frontend | Nix-built SDL app launched from terminal 2; native Wayland window mapped, PipeWire audio opened |
| Full gameplay and UI event tests | Passed, including collection, win/loss/replay, keyboard/controller events, focus handling, pixel replication, and audio queue |
| Flat/hierarchical simulation agreement | Actual title/gameplay/win/loss pixel files and stereo WAV match byte for byte |
| Actual desktop launch and runtime benchmark | Bounded desktop run completed; maze first-circuit benchmark of 120 frames took 1.88181 seconds, approximately 63.77 unthrottled fps against the 60 Hz target |
| Documentation and final flake checks | `nix flake check -L` and Nix formatting validation passed |

The original game has four maze circuits with a courier drone, three data packets,
two-to-five guards, a jam pulse and a delivery dock. The CPU ROM performs movement,
collision, timed scoring, progression, win/loss, replay, and sound sequencing.
The custom chip logic performs millisecond timing, tile lookup, sprite
composition, palette conversion, audio oscillation, input sampling, frame IRQ,
and frame-wait. The host implements no gameplay rules.

See [the architecture](../architecture/software-prototype.md) and
[the current CPU/peripheral decision](../architecture/decisions/0006-maze-game-and-sprite-budget.md).

## Build and validation artifacts

- `build/game-rom/`: original ROM, assembly listing, symbol/map files, source, and
  memory data. The image is 32,768 bytes; code/data/vectors occupy 9,488 bytes
  before padding, including maze tables. The game reserves 151 zero-page bytes.
- `build/cpu-tests/`: independent 6502 suite passed after 96,241,421 clocks and
  65C02 suite after 66,547,187 clocks, plus directed CPU results.
- `build/game-check/`: title, gameplay, delivered, link-lost, jammed, circuits 2–4 and
  campaign-complete PNG/PPM images;
  actual digital stereo gameplay WAV; end-to-end test report.
- `build/simulator-equivalence/test.log`: flat versus hierarchical comparison.
- `build/desktop-frame.ppm`: frame captured by the initial milestone's bounded native desktop run, before the guarding revision.
- `build/simulator-benchmark.log`: unthrottled first-circuit benchmark of the initial maze revision, before manual controls.

Original ROM SHA-256:

```text
4f3d6f0478fa988558697718b334811bad4cfdaef653703547d33ecf304d4957
```

## Guarding revision (before the maze)

The original fixed horizontal patrol has been replaced with card defense on
both axes. The sentinel takes position beside the active card, pursues nearby
couriers for 18 frames, and exposes a bronze 48-frame recovery interval. Captures
redirect it immediately to the next card, then to the delivery dock. All steering
and state transitions execute in the ROM. Following play feedback, guard and
pursuit movement were halved to one pixel per axis per frame; recovery movement
was also halved to one pixel every other frame. Normal courier movement can now
outrun the guard. See the
[current guard behavior](../architecture/software-prototype.md#guards-and-jam-pulse).

The pre-maze game check verified an idle spawn remained safe, a slow first-card
approach is caught while normal movement escapes, the guard never moves more
than one pixel per axis per frame, a feint draws it on both axes, recovery is visibly signaled,
and the guard relocates to defend subsequent cards. A full input-only route baits
the guard and delivers all three cards without changing emulated RAM or disabling
the enemy. The previous independent CPU functional results remain applicable:
the CPU core and its translation pipeline are unchanged.

## Campaign and millisecond scoring revision

The initial campaign revision introduced four reflected
layouts with distinct border colors, starting corners, card routes and docks.
The full campaign is verified using controller events, including advancing
through all four circuits and replaying from the first. Enemy speed is unchanged
from the slower tuning above.

Two independent custom hardware stopwatches divide the master clock by 6,288 to
count exact milliseconds. The ROM renders `TIME MM:SS.mmm` and `TOTAL MM:SS.mmm`;
the lower total is the better score. Failed attempts count, while menus and pause
do not. Per-level time resets at each start or retry; campaign replay clears both.
The counters and decimal formatting run in the HDL and 65C02 respectively.
Live digits refresh at 30 Hz to reserve CPU time for gameplay, with an immediate
sample at the finish; timing resolution remains one millisecond.

Peripheral checks cover tick cadence, independent controls, pause/resume and
coherent reads through a byte rollover. Game checks cover HUD formatting and
one-second drift, frozen results, retry scoring, accumulated totals and all four
playable circuits. Flat/hierarchical comparison includes every circuit image,
the final campaign screen and stereo audio. See the
[timer registers and score rules](../architecture/software-prototype.md#circuits-and-timed-score).

## Randomized qualifying runs (2026-10-29, before the maze)

Every start and retry now shuffles and jitters five separated positions: courier,
three ordered cards and dock. This replaces the fixed reflections. A seeded
16-bit PRNG executes entirely on the 65C02; start timing varies campaigns while
identical input sequences remain reproducible for simulation comparisons.
All points remain in bounds and every pair is at least 48 pixels apart on one
axis, preventing overlapping pickups or an unsafe initial spawn.

The HUD displays a `BEAT MM:SS.mmm` target computed from the actual route.
The qualifying limit is `500 + route_length × coefficient` milliseconds, with
coefficients 12, 11, 10 and 9 for circuits 1–4. Route length is the sum of four
Chebyshev legs, matching diagonal movement. Delivery must finish strictly before
the target; expiry produces `TOO SLOW - A RETRY`. Failure time still counts in
the campaign total. Later guards pursue for longer and recover sooner, while
retaining the slower one-pixel movement speed.

Input-only game checks complete eight distinct randomized circuits across two
campaigns, validate separation and deadline calculations, check frozen menus
and retry penalties, and verify a stationary attempt times out. Tests also seek
guard contact to verify collision loss. The test driver only observes visible
sprite/HUD writes and sends SDL controls; it never edits RAM, disables hazards
or implements production game rules in the host.

## Rail maze and multiple guards (2026-10-29)

The initial maze revision added four connected mazes with automatic cardinal movement,
buffered junction turns, immediate reversals and wall blocking. Ordered cards,
delivery and millisecond scoring remain. A one-second jam pulse freezes guards
and makes them harmless; recharge increases from 2.5 to 4 seconds. Circuits add
guards from two to five, with chasing, ambush, defense and patrol roles. The
fastest guard remains capped at one pixel per frame versus the courier's two.

The sprite budget expands from four to eight slots, fitting courier, card, five
guards and dock. Peripheral tests verify upper-register isolation, slot-seven
rendering and sprite-zero priority. Maze topology, graphics and shortest-path
tables are generated reproducibly and stored in the ROM. Gameplay and junction
steering still execute entirely on the 65C02. See
[ADR 0006](../architecture/decisions/0006-maze-game-and-sprite-budget.md).

The input-only campaign check qualified all four maze circuits with no failed
attempts and nine jam pulses:

| Circuit | Guards | Clear / qualifying limit |
| --- | --- | --- |
| 1 | 2 | 7,742 / 15,824 ms |
| 2 | 3 | 8,475 / 15,056 ms |
| 3 | 4 | 11,408 / 15,824 ms |
| 4 | 5 | 13,409 / 15,920 ms |

Checks also reconstruct the rendered graph, prove every junction reachable,
verify reciprocal links and progressive obstruction counts, check all actor
positions against rails every frame, reject diagonal/wall motion, exercise
buffered turns, reversals, stopped exits, slow mode and jam freeze, and preserve
clock/retry/replay checks. Flat/hierarchical builds agree on all maze images,
jam and outcome screens, and stereo audio. These are successful software test
runs, not a guarantee that every human player or randomized attempt will win.

## Manual movement revision (2026-10-29)

The courier now moves only while a direction is held. Releasing directions stops
immediately, including between junctions, while enemies and the clock continue.
The edge position and heading are retained so resuming cannot snap to a node.
Held perpendicular requests still buffer turns; released requests are canceled.
Opposing directions cancel on their axis, and slow/jam buttons alone do not move
the courier. Tests explicitly check release-to-stop, mid-edge resume, opposing
directions and slow-mode release, while retaining all four qualifying maze clears.

## Scope and limits

This is an original playable enhanced-mode prototype, with temporary registers
and budgets. Software tests validate the HDL behavior, ROM, host input/rendering,
and digital audio transport. The desktop was observed running with Wayland and
PipeWire; no physical sound measurement or controller-model certification is
claimed. The benchmark excludes desktop presentation and is specific to this host.

Original Lynx ROMs, exact Lynx bus/interrupt timing, PCB/display integration,
physical clock-control mapping, manufacturing, and new MiSTer hardware acceptance
remain later work. The existing MiSTer RBF is still the earlier bring-up circuit;
the game has not been loaded onto that board.
