# Project at a glance

Reviewed: **2026-11-24**. This is the current project summary and the one place
other pages point to for current figures. Historical research
and measurements retain their original review dates.

## The console we are building

An alternate-history Lynx successor: a handheld built around purpose-designed
graphics, audio and system logic, a 65C02-family CPU, physical controls, a backlit
color display and eventually a custom PCB in a 3D-printed enclosure. We use modern
FPGA development tools to design bounded hardware. Game logic runs on the console
CPU; host software is development infrastructure.

| Requirement | Target and current boundary |
| --- | --- |
| New games | **320 × 204**, aiming for **60 fps** under defined graphics workloads |
| Legacy Lynx games | Original **160 × 102** rendering, exact **2×** replication filling **320 × 204 edge to edge**, with **no added borders**; initial support requires no recompilation |
| CPU | **Inside the FPGA for the first Tang prototype**, accepted by the owner; an external CPU is a later option |
| First board port | **Tang Nano 20K**, following the successful core feasibility audit |
| Graphics ambitions | Scaled sprites, multiple independently scrolling layers, dense objects and basic flat-shaded 3D |
| Display | Color **with a backlight**; exact handheld panel still open |
| Software/tooling | Original ROM code and custom peripherals; tooling and builds managed by Nix |
| Custom chips | HDL modules first; custom silicon is a later, separately costed possibility |

The name is a creative direction, not an Atari product or branding agreement.
No PCB, complete handheld, commercial-game compatibility certification or
complete enhanced-graphics fit on Tang has been demonstrated.

## Separate implementation workstreams

| Workstream | What exists | What it proves | What comes next |
| --- | --- | --- | --- |
| Original enhanced-mode software prototype | Circuit Courier on an HDL 65C02, custom tile/sprite/audio/input hardware, desktop simulator | A real CPU executes the game and controls custom peripherals; software regressions pass | Retain as the regression baseline while developing the larger graphics engines |
| Original Lynx feasibility audit | Pinned upstream CPU/Suzy/Mikey, adapted memory, diagnostic simulation and a registered core-only routed design | Baseline console fits Tang resources and the core-only timing model passes 64 MHz | Add real clocks, SDRAM, loading, display, input and audio |
| Tang playable port | UART/CRC loader, cartridge bridge/cache, x32 SDRAM, frame capture, RGB scanout and stereo filter/mailbox/I²S | Serial cold/warm boot, patterned input-dependent video and actual Mikey audio pass; component contention/reset/overflow/deadline checks pass | Complete board pin/clock constraints, verify primitive serialization and timing, then physical acceptance and filter/analog qualification |
| Complete bench-board top | Original TMDS encoders, reset/activity control, clock/serializer wrappers and all pin assignments | Complete mapping and pin/clock packing checks pass; encoding/control tests pass | Complete timing-model and I/O coverage, then physical output |
| Custom scaled blitter | Original 4/8-bit scaler/fill, clipping, coverage/index/band surface, cache, masks and fences | Pixel reference, real-SDRAM model integration and standalone synthesis pass | Compositor integration and dense workloads on the [enhanced skeleton](milestones/enhanced-skeleton.md) |

The existing MiSTer RBF is an earlier display/input/audio bring-up circuit. It is
not the Circuit Courier game or a Tang Lynx port.

## Measured baseline, with its scope

The **2026-11-17** registered Lynx core probe, including the warm-reset correction,
uses **11,710 of 20,736 LUT sites**,
**5,062 of 15,552 registers** and **33 of 46 block RAMs**. Its estimated maximum
clock is **81.833 MHz** against a **64 MHz** requirement. These are final routed
core-plus-test-harness numbers, not a full board design.

A later timing-coverage review found that the pinned tool does not model
LUT1–LUT3 or DSP delays. The historical maximum above therefore describes
partial timing-model coverage. The new [complete-board build](milestones/tang-board-build.md)
normalizes the small LUTs to equivalent LUT4s and checks the actual binary
database; DSP, serializer and I/O timing remain unqualified.

The complete bench top currently packs to **13,754 / 20,736 logic sites**,
**6,234 / 15,552 registers** and **35 / 46 block RAMs**. These newer quantities
include board services and I/O; they are not enhanced-engine allocations or
complete timing signoff.

After placement/routing, the corrected true-LVDS build uses **13,460 logic
sites**, the same **6,234 registers** and **35 block RAMs**, and produces a
bench bitstream. Its modeled system paths report **69.238 MHz** against 64 MHz.
Since **2026-11-24** the legacy system uses the same SDRAM controller and arbiter
as the enhanced engines, so one memory service needs hardware qualification.
See the [board-build result](milestones/tang-board-build.md#current-routed-result-and-image)
for all clock targets, image checksum and exclusions.

That leaves 9,026 nominal logic sites and 13 block RAMs before integrating board
services. It does not reserve space for the enhanced engines or prove their fit.
The original diagnostic and the independent Intel RAM-model comparison passed.
**Zero commercial games and zero physical Tang runs have been tested.**

Read the [complete audit](research/lynx-tang20k-compatibility.md) and its
[machine-readable snapshot](research/evidence/lynx-tang20k-2026-11-17.json) for the
methods, exclusions, pins, source revision and reproducible commands.

The **video-only portable system** maps to **35 block RAMs** and **5,819
registers**, including serial loading, SDRAM services, capture and RGB scanout.
The combined **stereo audiovisual system** maps to **35 block RAMs** and
**6,214 registers**. Audio adds no block RAM or multipliers. Its 9,563 LUT1–4
cells and 3,504 ALU cells are mapped primitive counts, not routed logic-site use.
See the [audio milestone](milestones/tang-audio.md). The separate complete bench
top has the routed/fuse-packed result above; complete board timing coverage and
physical audiovisual output remain unqualified.

The original enhanced [scaled-blitter component](milestones/scaled-blitter.md)
now passes 513 pixel/reference commands and 1,521 real-controller-model commands.
With the [enhanced memory service](milestones/enhanced-memory.md), its 256-sprite
renderer workload falls from 22.531 ms to **10.960 ms** at an assumed 64 MHz.
The scaled scene with continuous host traffic falls from 23.656 ms to **14.572 ms**.
Both frame limits are enforced across front-read phases. The service separately
passes 9,390 responses with strict fairness and unchanged memory timing checks.
The [native CPU/MMIO diagnostic](architecture/native-graphics-mmio.md) separately
passes six cold/warm boots and 654 CPU submissions, with CPU-uploaded source data
and real completion IRQ handling. The register-driver suite checks another 399
results. The [enhanced skeleton](milestones/enhanced-skeleton.md) is the first
real enhanced top: CPU, block-RAM memory, MMIO blitter, native scanout and
front/back ownership on the shared memory service. Its demo ROM presents whole
frames in simulation, and the board top routes with open tools at 7,885 of 20,736
logic sites and 21 of 46 block RAMs, with a 66.36 MHz estimate against 64 MHz.
The compositor, input, audio and physical timing remain open; renderer-only
budgets and this light demo do not prove a complete 60 fps game.

## What is settled and what needs a decision

Accepted: rendering resolutions, backlight requirement, software-first progress,
Nix tooling, a Tang prototype with an internal CPU, and retaining the working
software game. See [ADR 0009](architecture/decisions/0009-tang-prototype.md).

Still open: handheld panel, complete BOM ceiling, enhanced resource/throughput
budget on Tang, exact register ABI, boot/game-storage product format, stereo
output circuitry, power/battery and enclosure dimensions. The
[tradeoff register](tradeoffs.md) explains alternatives and decision triggers;
the [roadmap](roadmap.md) defines the evidence required at each gate.

## How to read this documentation

- **Accepted** means we have chosen a direction. It does not mean it is built.
- **Verified in software** means the named simulation or tool check passed.
- **In progress** means code or integration work exists but acceptance is incomplete.
- **Proposed** means a design option or implementation plan remains to be validated.
- **Open** means the decision and its acceptance evidence are still ahead.
- **Historical** means useful context whose platform assumptions may have changed.

The HTML area is generated from these repository documents, the ADRs and the
checked-in evidence. It is a review snapshot, not an automatically updating task
tracker. Update the source documents when work or decisions change and rebuild
the site. [Documentation workflow](documentation.md) covers commands and upkeep.
