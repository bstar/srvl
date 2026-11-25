# Enhanced memory-service acceptance

Reviewed: **2026-11-17**. Status: **standalone and scaled-blitter model checks
pass; separate CPU/MMIO diagnostics also pass, while compositor/scanout integration, timing and physical acceptance
remain open**. This is original project logic derived from our earlier conservative
memory service, which it has now replaced in the legacy system as well.

## What changed

The enhanced fixture uses [cb_graphics_arbiter.sv](../../hardware/memory/cb_graphics_arbiter.sv)
and [cb_graphics_sdram.sv](../../hardware/memory/cb_graphics_sdram.sv).
Since **2026-11-24** the legacy Lynx system and board build use the same two
modules; the earlier legacy arbiter/controller were removed after every Tang
service, video, audio and board-route check passed on the shared service.
The [memory chapter](../chip-design/memory.md#implemented-enhanced-service)
provides an inspectable circuit diagram.

The arbiter has three round-robin clients and one elastic request slot. If the
controller is ready, a request passes straight through on its acceptance edge.
If initialization, recovery or refresh blocks it, the slot retains the accepted
address, data, byte mask and owner. An old response can retire while the next
request is accepted on the same clock edge. This avoids two register-stage gaps
without discarding requests or changing ownership before an old response is consumed.

The controller acknowledges a write after its physical WRITE command, while
separately blocking the next ACTIVATE until bank recovery is safe. A read returns
registered CAS-delayed data. The old controller waited longer before releasing
write ownership and returning to service; the enhanced path removes that delay.

## Timing and protocol contract

| Property | Implemented rule |
| --- | --- |
| Clock assumption | 64 MHz; these fixed command delays are not qualified for another clock |
| Geometry | 8 MiB, four banks, 2048 rows, 256 x32 columns |
| Transfer mode | Sequential burst length one, CAS two, auto-precharge after every access |
| Initialization | At least 200 μs, PRECHARGE ALL, two refreshes, mode setup and recovery |
| tRCD / tRP / tWR | At least two clock edges each under the unchanged independent model |
| Refresh recovery | At least five edges; refresh takes priority at idle when age reaches 500 |
| Client acceptance | Valid and ready on an edge; fields remain coherent until acceptance |
| Accepted depth | One global slot, pending issue or awaiting response; retirement can replace it on the same edge |
| Read response | Data belongs to the saved request owner |
| Write response | Physical WRITE has occurred; subsequent bank readiness remains separate |
| Byte masks | All 16 patterns, including zero; a zero-mask write still completes a physical transaction |
| Fault | Unexpected response sets a sticky protocol fault; no automatic rollback or timeout |
| Reset | Joint arbiter/controller reset cancels outstanding logic work; committed SDRAM data survives |

This implementation does not add bursts, open rows, command reordering,
per-client queues or a display-priority/deadline reservation. Round-robin fairness
and passing synthetic front-read deadlines are narrower than a full native
scanout guarantee. Physical clock phase and I/O setup/hold are still unqualified.

## Independent standalone evidence

The [test](../../sim/graphics-memory.cpp) drives the real modules through a
[pin/stall/fault fixture](../../hardware/tests/graphics-memory-top.sv). The
existing [SDRAM model](../../sim/sdram-model.hpp) is unchanged: geometry,
initialization, CAS, precharge/recovery, refresh and DQ drive-direction checks
were not relaxed. A separate byte-lane oracle compares the entire 8 MiB storage.
Each response must follow exactly one physical operation of the correct type.

The current run records:

- **9,394 accepted transactions**, **9,390 completed**, **four reset cancellations**.
- All 16 masks at column/row boundaries, every bank boundary and the last word.
- A request accepted before initialization and completed only after safe startup.
- **6,000 continuously offered requests in 36,433 cycles**, strict `0,1,2` grant
  rotation, maximum **14 cycles from acceptance to response**, and **25 cycles
  from offer to response**, including refresh.
- Another 3,000 requests with randomized addresses, arrivals and controller stalls.
- **4,465 bypass launches** and **8,990 simultaneous retire/accept edges**.
- **132 refreshes**, maximum observed gap **509 cycles**, including a 900-cycle
  accepted-request stall during which refresh continues.
- Reset during a pending request, physical READ, and committed WRITE before ACK;
  plus unexpected responses in idle and with an unissued slot. Fresh reads after
  reinitialization must complete with no stale owner or token.

At an assumed 64 MHz the continuous run carries approximately **42.2 MB/s** of
x32 payload. This includes the test's mix of reads/writes and refresh; it is not
a maximum bandwidth specification for arbitrary workloads or a board measurement.

## Same rendering work, faster memory service

The [scaled-blitter integration](scaled-blitter.md#measured-workloads-including-missed-budgets)
retains its original commands, source sampling, engine read/write counts,
one-front-word-per-32-cycles traffic and continuously enabled host traffic in the
scaled scene. All physical storage comparisons pass, and the diagnostic preview
is byte-for-byte identical.

| Workload including clear | Optimized blitter on legacy service | Enhanced service | Time at assumed 64 MHz |
| --- | --- | --- | --- |
| 64 small sprites | 560,723 cycles | 358,851 cycles | 5.607 ms |
| 256 small sprites | 1,049,970 cycles | 701,452 cycles | 10.960 ms |
| 32 scaled sprites with host traffic | 1,447,516 cycles | 932,576 cycles | 14.572 ms |

All three renderer-only frame budgets are enforced by the integration test.
Dense and host-contended scaled scenes also repeat with front-read release
offsets of 1, 7, 15 and 31 cycles. The slowest scaled repeat is **932,591 cycles /
14.572 ms**, leaving approximately **2.095 ms** of a 60 Hz frame before adding
other system work. Native CPU marshaling, tile composition, real native scanout
and game execution are still excluded. These results do not establish a complete
60 fps game or a qualified 64 MHz enhanced configuration.

## Resource scope and reproduction

Separate synthesis maps the arbiter to **67 registers, 262 LUT1–LUT4 cells and
two ALU cells**, and the controller to **171 registers, 166 LUT1–LUT4 cells and
38 ALU cells**, plus mux primitives. Neither uses DSP, block RAM or unintended
latches. These primitive counts cannot be summed into a reliable placed-site
budget or a complete enhanced timing result.

```sh
nix --extra-experimental-features 'nix-command flakes' build \
  .#graphics-memory-check -o build/graphics-memory-check -L
nix --extra-experimental-features 'nix-command flakes' build \
  .#scaled-blitter-memory-check -o build/scaled-blitter-memory-check -L
```

[nix/enhanced.nix](../../nix/enhanced.nix) captures builds, logs, source snapshots,
tool versions, test JSON and separate synthesis netlists. The
[service evidence](../research/evidence/graphics-memory-2026-11-17.json) and
[renderer evidence](../research/evidence/scaled-blitter-2026-11-17.json) record
current source hashes. The [original baseline](../research/evidence/scaled-blitter-baseline-2026-11-17.json)
and [optimized blitter on legacy memory](../research/evidence/scaled-blitter-legacy-memory-2026-11-17.json)
remain available for comparison.

The separate [native MMIO/CPU diagnostic](../architecture/native-graphics-mmio.md)
now uses this service. Next add complete-frame ownership and compositor/scanout
clients, then measure their simultaneous scene and resource/timing cost. Bursts,
open-row scheduling or display reservations need their own evidence if that
combined workload cannot meet its deadlines.
