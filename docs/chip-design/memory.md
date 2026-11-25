# Memory, timing and frame ownership

Reviewed: **2026-11-17**. Status: **integration design**. Tang SDRAM, UART/loader
and cartridge service checks now pass an independent command-level memory model.
Integrated console cold/warm boot and buffered exact-2× RGB output also pass.
Display contention is covered by a separate component test; board timing remains open.
The elastic arbiter/controller passes standalone and scaled-blitter contention
checks, and since 2026-11-24 also serves the legacy system. A separate native CPU/MMIO diagnostic now uses
the same service, and the [enhanced skeleton](../milestones/enhanced-skeleton.md)
adds native scanout with front/back ownership as its third client. Deadline
reservations, cache sizes and the game-visible bus ABI remain open.

## Memory service defines the machine

Every client needs a bounded queue and an explicit accepted-request rule. The
scheduler must reserve service for display, preserve CPU-visible behavior and
continue refresh under load. Throughput and worst-case latency matter together.

{{chip-diagram:memory}}

## Implemented enhanced service

{{chip-diagram:graphics-memory}}

The current enhanced fixture uses an original three-client round-robin arbiter
with one elastic request slot and an auto-precharge x32 SDRAM controller. It
bypasses the slot when ready, retains accepted work when blocked, and can retire
an old response while accepting the next owner on the same edge. A write ACK
follows the physical WRITE; bank recovery independently delays the next ACTIVATE.
The conservative 64 MHz command timings and independent pin model are retained.

The [standalone acceptance](../milestones/enhanced-memory.md) checks
all masks/bank boundaries, strict fairness, refresh, stalls, resets and fault
recovery, and records the measured renderer workloads on this service. Both
60 Hz renderer budgets are checked across front-read phases. Those workload timings exclude CPU staging;
the separate [CPU diagnostic](../architecture/native-graphics-mmio.md) proves
functional command integration. Layer composition, scanout under dense
workloads and physical board timing remain ahead.

This one service now serves both the legacy system and the enhanced engines;
the earlier legacy controller/arbiter were removed. It has no
per-client request queues, bursts, open rows or reserved scanout priority yet.
The broader scheduler diagram above remains a proposal for complete-system
service, rather than a claim that all of its policy blocks are implemented.

## Request and completion are different events

A proposed request interface uses **valid + ready**: a request is accepted on a
clock edge where both are asserted. Its address, write data and byte lanes must
remain stable while waiting. A later response reports read data or committed
write completion. A fence waits for outstanding work as well as queued commands.

This is an interface design requirement, not a signal-level ABI already wired to
every module. The CPU's stall/clock-enable adapter must avoid repeating MMIO writes
or losing interrupts. Native CPU instruction tests do not prove arbitrary memory
stall behavior. Legacy work RAM keeps the separately audited local path.

## Storage and traffic baseline

| Storage item | Calculation | Size / read traffic |
| --- | --- | --- |
| Enhanced 16-bit surface | 320 × 204 × 2 bytes | 130,560 bytes |
| Two enhanced surfaces | Two complete frame stores | 261,120 bytes |
| One enhanced surface at 60 scans/s | 130,560 × 60 | 7.8336 MB/s, before all other work |
| Legacy presentation frame, padded RGB444 | 160 × 102 × 2 bytes | 32,640 bytes |
| Three padded legacy frames | Three complete frame stores | 97,920 bytes |
| Original Lynx work RAM | Local compatibility memory | 65,536 bytes; kept on-chip |

MB/s above uses decimal bytes. These are arithmetic baselines, not measured
controller throughput. Tile maps/patterns, sprite sources/writes, CPU/cache,
cartridge requests, geometry, refresh and turnaround consume additional service.
Do not import the old ECP5 x16 throughput target as a Tang result.

## A frame cannot have two writers

The ownership model below illustrates three presentation banks. The current
source frame, latest completed frame and displayed frame have distinct ownership.
A bank becomes publishable only after all its accepted writes complete. Display
handoff occurs at a safe frame boundary. Repeating or dropping complete frames is
allowed when source and display cadence differ.

{{chip-diagram:frames}}

A queue overflow or truncated source frame invalidates that candidate. Drain or
cancel its work safely before freeing its bank. Do not publish a partial image.
Line-buffer ownership also requires a completed-fill acknowledgment before scanout
switches banks. The native drawing configuration may use a different number of
surfaces, but it needs the same ownership invariants.

The original [three-bank capture RTL](../../hardware/video/lynx_frame_capture.sv)
now passes a same-clock delayed-write model: ordered RGB444 capture, final-write
acknowledgment, simultaneous completion/presentation, overflow, truncated and
out-of-order input, disable/drain and bank reuse. Its
[test](../../sim/frame-capture.cpp) checks all pixels in each presented bank and
rejects writes into the displayed bank. The caller must provide a safe
presentation boundary after old reads drain. The real SDRAM arbiter, display
reader, line buffers and clock-domain handoff now pass their
[integrated video checks](../milestones/tang-video.md). Physical timing and the
serializer remain separate gates.

The capture queue has its own reset/backpressure/pointer-wrap checks and maps to
one Gowin block RAM. These two component checks do not establish a full video
path's resource use or timing. The separate complete portable system maps to
35 block RAMs. The newer [complete-board build](../milestones/tang-board-build.md)
includes this path; its remaining timing-model and I/O gaps are documented there.
Reproduce the component checks
with `nix build .#video-fifo-check
.#frame-capture-check`; see [the milestone](../milestones/tang-board-services.md).

## Clock-domain crossings

Keep the faithful legacy master clock independent from display transport. Transfer
coherent metadata using an acknowledged toggle/mailbox or an appropriately designed
asynchronous FIFO, with dual-clock memory where needed. Synchronizing each bit of
a changing bus separately does not guarantee a coherent address or frame token.

Reset must establish matching ownership/toggle state on both sides. Review clock
constraints and CDC structure; only genuine asynchronous paths receive justified
exceptions. The 64 MHz core-only route probe does not close memory-I/O, serializer
or cross-domain timing for a complete board.

The implemented legacy reader uses one held request/acknowledgment mailbox and
two alternating 80-word line buffers. Both reset domains must assert together.
Digital tests cover different clock ratios, withheld memory service and joint
reset with outstanding work; they do not simulate metastability. See the
[clock/ownership diagram](legacy.md#buffered-output-and-clock-crossing).

## Acceptance

Use an independent SDRAM model for geometry, bank/row/column boundaries, byte
lanes, initialization, refresh, read latency and bus drive direction. Contend
display reads, cartridge requests, drawing and uploads. Verify no accepted request
is duplicated or lost and no display line reads an unowned buffer.

Log maximum service delay, queue high-water marks, refresh delay, underruns,
overflow invalidations and completed-frame age. Physical clock phase, signal
integrity and real memory behavior remain a later board acceptance stage.
