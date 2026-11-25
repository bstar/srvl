# Work plan and acceptance gates

Reviewed: **2026-11-24**. Ordered gates, not delivery dates. Progress comes from
recorded evidence; writing RTL or accepting a direction does not close a gate.
Current work is the Tang integration path; the original software game remains
the regression baseline.

## 1. Keep the working foundation — verified in software

Gate: Foundation · Done

Nix development shells, original-ROM simulator, native CPU tests, peripheral/game
checks and the legacy feasibility audit exist. Preserve reproducible pins,
licenses, logs and evidence. The [software milestone](milestones/playable-software-prototype.md)
and [Lynx audit](research/lynx-tang20k-compatibility.md) state their exact scope.

Acceptance: existing applicable Nix checks continue to pass. Physical MiSTer
testing remains deferred under ADR 0004.

## 2. Board services — service-level software checks pass

Gate: Board services · Done

Implement and independently verify the UART, CRC protocol, loader/reset path and
the Tang's x32 SDRAM controller. These service checks now pass, including guarded
image commit, cartridge cache, reset/backpressure and continuous refresh. The
[service milestone](milestones/tang-board-services.md) and
[evidence snapshot](research/evidence/tang-services-2026-11-17.json) record the
test scope. Real-console integration remains a separate gate.

Acceptance: corrupted/truncated requests cannot mutate a committed game; byte
lanes and bank/row/column boundaries are correct; refresh continues under load;
controller reads/writes match an independent memory model.

## 3. Legacy presentation and controls — original diagnostics verified in software

Gate: Presentation · Done

Integrate the original console with cartridge reads, RGB capture, completed-frame
handoff, line buffers, exact pixel replication, controls and audio transport.
The new UART/loader/cart/SDRAM path boots the original console diagnostic and
produces full RGB frames with held/released controls. A reset-only upstream strobe correction now passes cold/warm boot and input
regressions. The original source-only checks are recorded in the
[console integration evidence](research/evidence/tang-core-integration-2026-11-17.json).
Capture, shared SDRAM arbitration, line reads and cross-clock ownership now pass
the [buffered RGB acceptance](milestones/tang-video.md), including patterned
real-console input/reload and exact 2× pixels. The
[stereo audio acceptance](milestones/tang-audio.md) now adds actual Mikey tones,
coherent filtered pairs and pin-decoded I²S during video, including mute and six
cold/warm input phases. Filter fidelity and physical output remain open.
Video serialization and full-board timing are the next gate, not established
by the component tests or the portable system's 35-block-RAM synthesis result.
Preserve source frame cadence and live palette changes. Use an original
diagnostic to exercise button hold/release and output samples.

Acceptance: every source pixel has the correct scaled destination; no mixed or
partially written frames; bounded whole-frame repeat/drop; overload is visible
through status; input and memory contention cannot silently corrupt output.

## 4. Complete Tang build — next implementation gate

Gate: Complete build · Active

Add the real board top, verified pin constraints, clock-generator configuration,
PLLs, SDRAM clock phase, video serializers and reset sequencing. Synthesize,
place, route and pack the **complete** design through Nix.

The [clock and display-output design](chip-design/board-output.md) now includes
original TMDS encoders and digital reset/activity-control tests. Both component
checks pass. The complete board top now maps, places/routes and fuse-packs,
with all 79 signal bits
assigned and eight explicit clock targets. Small LUTs are normalized with
exhaustive local equivalence checks. The [board-build record](milestones/tang-board-build.md)
documents these results and uncovered timing models. Complete timing coverage
and physical output remain unqualified.

Acceptance: all required board I/O is constrained; timing coverage and clock
crossings are reviewed; resource use and timing pass; the output bitstream and
source/license bundle are reproducible. The existing registered core probe does
not satisfy this gate.

## 5. Physical bring-up and compatibility — deferred physical work

Gate: Physical tests · Pending

Run the original diagnostic on the actual Tang first. Then use owner-supplied
BIOS/game images to test loading, original features, orientation and timing-sensitive
behavior. Record image hashes, board revisions, display setup and failures.
Sprite RLE/scaling/collision, arithmetic, timers, interrupts, audio and loader
corners need focused tests before broad claims of compatibility.

Acceptance: repeatable real-board boots and a named compatibility matrix.
ComLynx and physical cartridges are additional gates, not implied capabilities.

## 6. Enhanced graphics configuration — skeleton routes; engines and budget open

Gate: Enhanced engines · Active

Re-budget the native CPU, memory and new engines on Tang. Specify request/stall
interfaces and a bounded register/command ABI. Implement scaled drawing first,
then parallax composition, then fixed-point math and screen-space flat triangles.
Keep separate FPGA images if the combined design would crowd out useful engines.

The [first scaled-blitter component](milestones/scaled-blitter.md) now passes
independent pixel/memory tests, real-controller contention/reset checks and
standalone synthesis. The [native MMIO and CPU diagnostic](architecture/native-graphics-mmio.md)
now pass six cold/warm boots, CPU asset uploads, completion IRQs and three clock
configurations. A first [enhanced top](milestones/enhanced-skeleton.md) now adds
native scanout and front/back ownership, runs a CPU-drawn demo in simulation and
routes on Tang with open tools; the compositor, input, audio and a game remain
open. With the [enhanced elastic memory service](milestones/enhanced-memory.md),
the renderer-only frame budgets pass across front-read phases and are regression
limits; [project status](project-status.md) carries the current figures. Complete-system throughput and enhanced timing remain unqualified;
preserve both baselines and measure the new CPU/compositor/scanout workload.

Acceptance: native 320 × 204 scenes meet the stated 60 fps workloads with measured
memory service and resource/timing reports. Descriptor count is not a guarantee
that every large object can be drawn each frame. Stress scaling, overlap,
minification, clipping, memory stalls and incomplete-frame handling.

## 7. Display qualification and handheld electronics — open dependencies

Gate: LCD & power · Pending

Select a backlit color panel after motion, refresh, brightness, orientation,
interface, lifecycle, cost and power checks. Set stereo output, controls,
storage and charging interfaces. Measure a full power budget before selecting
battery capacity and enclosure geometry. Display research can run alongside the
FPGA work, but PCB and case dimensions depend on its result.

Acceptance: tested panel and interface; reviewed schematic/BOM/pin-bank assignment;
complete current/voltage budget; connector and thermal clearance in the mechanical
model. Do not freeze a case around an unqualified panel.

## 8. Custom PCB and enclosure — later

Gate: PCB & case · Pending

Build and bring up the carrier/custom board, integrate a screen and gamepad,
print the case, then measure power, sound, temperature and usability. Iterate
with a documented revision history.

Acceptance: a self-contained portable console running original games and the
explicitly tested subset of legacy games. Manufacturing and custom-ASIC work
require their own budget and validation plan after the architecture stabilizes.

## Decisions that can change the sequence

The [tradeoff register](tradeoffs.md) defines triggers for narrowing graphics
workloads, using separate configurations, changing the display or reconsidering
a custom-board FPGA. A failed measurement should update a proposal or ADR; it
should not silently change the agreed resolution or compatibility goal.
