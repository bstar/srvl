# Scaled sprite engine

Reviewed: **2026-11-17**. Status: **original v1 component implemented and
verified against pixel/memory models**. Experimental native MMIO and an actual
CPU diagnostic now pass; compositor, frame ownership and complete enhanced-system fit/timing remain open. Circuit
Courier still uses its eight fixed-size sprites; reused Suzy supplies legacy
behavior in the separate compatibility path.

## From a command to written pixels

The engine latches an object descriptor, walks the visible destination,
samples the source, suppresses transparent pixels and emits masked writes.
Rectangle fill emits one or two pixels per aligned word without fetching a
source or walking every pixel through the sampler.
Component/workload tests submit commands from harnesses. A separate
[actual CPU diagnostic](../architecture/native-graphics-mmio.md) now submits work
through implemented dual-clock MMIO and uploads its source data with CPU instructions.

{{chip-diagram:sprites}}

The implementation is [cb_scaled_blitter.sv](../../hardware/enhanced/cb_scaled_blitter.sv).
Its [acceptance record](../milestones/scaled-blitter.md) contains exact test,
resource and workload evidence, including workloads that miss 60 Hz.

## Experimental component contract v1

These are latched RTL fields, **not a frozen CPU register or binary descriptor
ABI**. The `$4400–$44FF` window now contains the separate
[experimental v1 serialized MMIO interface](../architecture/native-graphics-mmio.md#register-map);
it is concrete development code, not a frozen SDK.

| Field | Current rule |
| --- | --- |
| Operation | Scaled draw, or rectangle fill with a constant index/band |
| Source base | 23-bit byte address in 8 MiB physical memory; unaligned bases supported |
| Source dimensions | 1–256 pixels per axis for draws; ignored by fill |
| Source stride | Unsigned 16-bit bytes per row, at least the packed row length |
| Source format | 8-bit indices, or packed 4-bit indices with the low nibble first |
| Destination | Even byte base and even 16-bit row stride, at least 640 bytes; complete 320×204 surface must fit |
| Origin | Signed 12-bit X/Y, −2048 through 2047 |
| Destination dimensions | 1–1024 pixels per axis, intersected with surface and user clip |
| Clip | Unsigned 10-bit coordinates; half-open `[x0,x1) × [y0,y1)` |
| Flips | Independent X/Y reversal after exact source sampling |
| Transparency | Optional suppression of **raw source index zero**, before palette banking |
| Palette bank | Four bits prepended to a 4-bit index; ignored for 8-bit sources and fill |
| Insertion band | Four bits stored per pixel; composition ordering remains an integration contract |
| Fill value | Eight-bit index plus covered/clear flag; uncovered fill writes canonical zero and ignores index/band |
| Tag | Caller-supplied 16-bit value returned with completion |

The object-surface word is:

```text
15      13 12       11             8 7                          0
+---------+--------+----------------+----------------------------+
|  zero   |covered | insertion band |          index             |
+---------+--------+----------------+----------------------------+
```

This is indexed object data. RGB444 palette lookup, tile layers, equal-priority
rules and visible frame publication are not performed by this engine.
Coverage distinguishes an empty surface pixel from an opaque palette-index-zero
pixel. Suppressed source pixels leave the destination unchanged; an explicit
uncovered fill clears it to zero.

## Exact scaling and clipping

For a destination position relative to the **unclipped** object origin:

```text
source_x = floor(relative_x × source_width / destination_width)
flipped_source_x = source_width - 1 - source_x
```

Y follows the same rule. For each destination step, add the source dimension
to an integer remainder; while it is at least the destination dimension,
subtract that dimension and advance the source coordinate. This preserves the
exact quotient/remainder relationship. It uses additions, comparisons and
repeated subtraction, with no finite fixed-point approximation, multiplier or
divider. Unity scaling and enlargement need at most one carry, which is folded
into sampling/store advancement. Minification keeps the repeated-carry path.

Clipped-away steps establish the initial source phase once. The X phase is saved
and restored at each row. Minification can require multiple carry cycles; this
is not a claim of one output pixel per clock. Validation computes source and
surface extents with bounded row additions rather than a hardware multiplier.

## Memory, masks and completion

One 32-bit cache word supplies four 8-bit or eight 4-bit source samples. Sources
must remain unchanged until completion. Aligned fetches can include padding
bytes around the source; every requested word remains inside physical memory.

A one-word combiner holds two 16-bit destination pixels. Byte masks preserve
the other halfword and transparent pixels. Changing to another word flushes the
pending word. Cached samples enter the combiner in the sampling cycle; a sample
held behind a flush resumes on its ACK. Fill prepares paired values directly
and masks partial first/last words, including alternating row alignment.
No destination read is needed. The interface permits one
outstanding request: valid/address/data/mask remain coherent under backpressure,
and a response arrives at least one cycle after acceptance.

Completion appears only after the final write acknowledgment. Its tag, error
and counters stay stable until completion-ready. A new command is accepted only
in idle. There is no resident 256-descriptor table or command FIFO yet.

| Completion error | Meaning |
| --- | --- |
| 0 | Successful command, including a valid empty intersection |
| 1 | Invalid source/destination dimensions |
| 2 | Invalid stride or destination alignment |
| 3 | Source or complete destination-surface extent exceeds 8 MiB |
| 4 | Conservative source/surface byte intervals overlap |

Parameters are checked before an empty clip becomes a successful no-op.
Bounding intervals include stride holes: interleaved allocations can be rejected
even if their individual pixels would not overlap.

Unexpected responses set a sticky protocol fault. This interface has no memory
error response or automatic timeout. Joint reset must cancel the adapter's
outstanding work as well as the engine's token/cache/buffer state. Committed
writes are not rolled back. A frame owner must clear or discard partial back
surfaces after an abort.

## Counters and limits

Each command reports 32-bit cycle, sampled-pixel, written-pixel, accepted-read,
accepted-write and memory-stall counters. They wrap modulo 2³² and stop changing
while completion waits. Transparency suppresses writes but still costs sampling.

The independent model uses direct integer division per pixel. Tests cover
4/8-bit sources, flips, fractional ratios, extreme minification, negative origins,
odd packed rows, masks, stride padding, address limits, invalid commands,
input changes after acceptance, delayed writes, held completion and reset.
A second fixture uses the actual arbiter/controller plus an independent SDRAM
command model with synthetic front-surface reads and host traffic.

With the [enhanced elastic memory service](../milestones/enhanced-memory.md), at an
**assumed 64 MHz**, clear plus 64 small sprites takes **5.61 ms**; clear plus 256
takes **10.96 ms**, down from 22.53 ms with identical draw/pixel and engine-request
counts. The scaled scene with continuous host traffic takes **14.57 ms**, down
from 23.66 ms. All three renderer-only budgets are enforced; dense and scaled
scenes also repeat across front-read phases. The slowest scaled repeat leaves
**2.095 ms** in a 60 Hz frame. These exclude native CPU marshaling, tile
composition and actual scanout; complete-system throughput remains open.

The component maps to 887 registers, 1,366 LUT1–LUT4 cells and 1,018 ALU cells, with
no DSP, block RAM or unintended latch. These are synthesis quantities, not
integrated logic-site totals or a clock-speed guarantee.

## Integration still required

The native CPU command/status adapter and original diagnostic ROM now pass their
separate checks. Add bounded batch storage, front/back-surface ownership, palette/compositor consumption,
native-resolution scanout and frame-level completion/deadline handling.
Improve shared memory service and pipeline overlap against the dense/contended
benchmarks, then synthesize and route the complete enhanced configuration.
Row stretch/tilt, affine rotation, alpha blending and collision rules remain
separate extensions. Legacy Suzy compatibility is not inferred from these tests.
