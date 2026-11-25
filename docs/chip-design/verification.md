# Chip verification and implementation gates

Reviewed: **2026-11-17**. A diagram defines intent. Evidence establishes behavior,
cost and timing. Each engine must close its own tests and then pass again as
part of the integrated machine.

## From a design contract to working hardware

{{chip-diagram:verification}}

## What each gate answers

| Gate | Question | Useful evidence |
| --- | --- | --- |
| Interface contract | What must happen, including stalls/reset/errors? | Defined commands, invariants, ownership and completion rules |
| Independent reference | Is our intended arithmetic/pixel behavior correct? | Small model with explicit integer/rounding/coverage rules |
| RTL simulation | Does the circuit implement that behavior under stress? | Directed corner cases, randomized latency, assertions and reproducible seeds |
| Synthesis | What resources does the implementation actually infer? | Mapped primitives, RAM inference, no unintended latches, source/tool pins |
| Integrated place and route | Does the complete configuration fit and meet clock/I/O requirements? | Resource/timing reports, timing-model coverage, pin/I/O budgets and reviewed clock/CDC boundaries |
| Physical acceptance | Does the real board behave correctly? | Original diagnostics, signal/power/display observations and named compatibility cases |

## Cross-cutting invariants

- An accepted memory request is executed exactly once.
- A producer under backpressure retains a coherent request.
- A completion fence includes writes still queued or in flight.
- Display never consumes an unowned or partly filled frame/line buffer.
- Reset cannot leak a stale command, response, ownership token or interrupt.
- Signed coordinates and arithmetic cannot wrap into an unrelated memory region.
- Queue pressure and missed deadlines are visible in status/counters.

## Budget the whole configuration

The completed Lynx audit is a **core-only** result with a registered test harness.
Its nominal remaining 9,026 logic sites and 13 block RAMs are not a guaranteed
allocation for new effects: real SDRAM, loading, video, audio and control logic
must fit too. The enhanced configuration has different logic and workload costs.

For every reported limit record clock, source format, object sizes, overlap,
active layers, traffic, queue sizes, memory latency, tool revision and timing
coverage. Descriptor capacity and raw memory bus bandwidth must not stand in for
frame throughput. Keep the old native game checks while developing new engines.

## Existing evidence to retain

- [Native CPU/peripheral/game acceptance](../milestones/playable-software-prototype.md)
- [Lynx diagnostic, RAM comparison, mapping and registered route probe](../research/lynx-tang20k-compatibility.md)
- [Current machine-readable audit snapshot](../research/evidence/lynx-tang20k-2026-11-17.json)
- [Serial loading, SDRAM and real-console integration](../milestones/tang-board-services.md)
- [Buffered RGB, ownership, clock crossing and portable-system mapping](../milestones/tang-video.md)
- [Stereo filtering, coherent I²S, actual Mikey tones and audiovisual mapping](../milestones/tang-audio.md)
- [TMDS encoding, board reset and audio-activity control](board-output.md)
- [Original scaled blitter, pixel equality, SDRAM integration and missed workload budgets](../milestones/scaled-blitter.md)
- [Enhanced elastic memory service, physical-command checks, fairness and bounded renderer budgets](../milestones/enhanced-memory.md)
- [Native MMIO, clock-crossing commands, CPU-driven uploads/draws, held results and completion IRQs](../architecture/native-graphics-mmio.md)
- [Workstream gates and physical deferral](../roadmap.md)

The current core-only probe includes the warm-reset correction and still meets
its tool's 64 MHz target. A later [board timing-coverage review](../milestones/tang-board-build.md)
found missing small-LUT and DSP models in that historical result. The new board
mapping normalizes small LUTs and verifies fabric-model presence; DSP, serializer
and external I/O timing remain open. Service simulation and the FIFO's separate block-RAM mapping are narrower
checks; neither the portable system nor its scanout is included in that routed
design. Both video-only and audiovisual portable systems map to 35 block RAMs;
the audiovisual system uses 6,209 registers. The new scaled-blitter component
passes pixel/SDRAM-model checks and standalone synthesis; its complete enhanced
configuration has not completed place/route or physical acceptance.
