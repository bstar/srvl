# Tang board services and serial loading

Date: **2026-11-17**. Status: **service-level and original-console integration
software checks pass**. No full board bitstream, display transport,
commercial game, or physical Tang acceptance is established by these checks.

## Completed implementation

The project now has original RTL for the 64 MHz / 460800-baud UART, ASCII/CRC
packet transport, guarded BIOS/image loader, cartridge byte bridge/cache and
single-word x32 SDRAM controller. A host utility validates owner-supplied images
and sends the same tested wire format. It never auto-selects or programs a board.

The loader holds the console in reset until complete-image commit. An upload
cannot modify a running game. Sequential writes and idempotent retries avoid
duplicated loader/header side effects. BIOS replacement invalidates the old BIOS
until all 512 bytes have arrived. Recovery/stop holds the game and invalidates
its committed state; it does not fabricate a new system BIOS or launcher.

## Reproduce the evidence

```sh
nix --extra-experimental-features 'nix-command flakes' build .#tang-services-check -o build/tang-services-check -L
nix --extra-experimental-features 'nix-command flakes' build .#lynx-link-check -o build/lynx-link-check -L
nix --extra-experimental-features 'nix-command flakes' run .#lynx-link -- inspect path/to/owned-game.lnx
```

`tang-services-check` retains the compilation/test logs, tool version, source and
machine-readable result. Its wire fixtures contain requests and replies captured
from the actual simulated UART/packet/loader. The Python client tests validate
those replies rather than relying on a separate firmware imitation.

The [checked-in evidence](../research/evidence/tang-services-2026-11-17.json)
records 12,455,777 simulated clocks, **618,859 accepted memory requests**,
**618,858 completions** and **one explicitly reset-cancelled request**. It records
**24,597 refreshes**, with a maximum runtime refresh gap of **512 SDRAM clocks**.
The seed is `0x1ac00217`. These counts are a reproducible test workload, not a
throughput benchmark or proof of all possible interleavings.

| Check | Coverage and boundary |
| --- | --- |
| UART | All 256 byte values in both directions; host bit periods 137–141 master clocks; false-start and invalid-stop rejection |
| Packet integrity | Independent CRC check vector, correct requests/replies, bad CRC, malformed hex, truncated/long line, bad stop, CRLF and recovery |
| SDRAM commands | Four banks, address-bit separation, row/column endpoints, all 16 byte-lane masks and 30,000 seeded write/read cases |
| SDRAM timing model | Initialization wait, precharge, two initialization refreshes, mode/CAS, activation/access/recovery, DQ ownership and continuous refresh under load/idle |
| Loader | Sequential addresses, bad ranges/lengths, complete BIOS, BS93/LNX/raw commit, idempotent word/BIOS/commit retries, random grant stalls and reset cancellation |
| Protection/input | No writes into a running game; commit cannot start a partial image; nine held control bits and explicit release |
| Cartridge bridge | Pulsed misses survive delayed grants; all four bytes share an aligned cached word; 1,000 seeded address cases; new image invalidates cache |
| Host tool | Nine checks cover real RTL reply fixtures, presentation status bits, CRC corruption, timeout without relaunch, all 65,536 payload words encoded as ASCII, image bounds/formats and BIOS preflight |

The independent [SDRAM model](../../sim/sdram-model.hpp) consumes physical command,
address, DQM and DQ pins at the modeled SDRAM clock edge. It reconstructs memory
geometry and CAS timing without inspecting controller state. Client-address/data
scoreboarding is separate from command decoding. It is not an electrical model,
vendor primitive model, analog retention test or manufacturing-corner signoff.

## Bench protocol

Every request is **16 ASCII bytes**: opcode, six address hex digits, four data hex
digits, four CRC digits and LF. CRC is CCITT polynomial `0x1021`, initial `0xffff`,
over the first eleven ASCII bytes. The response is `K` or `E`, eight status hex
digits, four CRC digits and LF; response CRC covers its first nine bytes. CR is
ignored by the receiver. Only one command may be outstanding.

| Opcode | Action | Preconditions |
| --- | --- | --- |
| `Q` | Read status | Address/data zero |
| `L` | Stop game, begin new image and clear candidate/input | Address/data zero; retains a previously completed BIOS |
| `B` | Write one BIOS byte | Loading, stopped, address 0–511, upper data byte zero, sequential; address zero can restart BIOS |
| `W` | Write a little-endian image word | Loading, stopped, SDRAM ready, even sequential address; preserve source container/header |
| `C` | Commit/start once | Address is the final image byte address, not byte count; data zero; exact full image and required BIOS/format validated |
| `K` | Set held buttons | Running, address zero; data bits 0–8 only |
| `R` | Hold reset/stop and invalidate committed image | Address/data zero |

Status bits 31–16 contain `0x4c59`. Bits 0–5 are memory ready, BIOS valid, running,
image valid, loading and sticky protocol error. The source-only configuration
leaves bits 8–11 zero. In the buffered RGB configuration they report a valid
display bank, sticky capture overflow, sticky display underrun and video protocol
fault respectively. Bit 12 reports cartridge-bridge or arbiter protocol fault.
The underrun flag is synchronized into the system clock. These bits do not
establish physical display acceptance; see [buffered-video evidence](tang-video.md).
Bits 13 and 14 now report audio formatter readiness and sticky audio underrun
when stereo output is included; both are synchronized registered flags. Readiness
means a coherent pair has started transmission. It does not certify the DAC or
amplifier. See [audio acceptance](tang-audio.md).

Button bits 0–8 are Right, Left, Down, Up, A, B, Pause, Option 1, Option 2.
The host does not retry an uncertain ACK or launch automatically after a timeout.
The hardware accepts an identical immediately previous word/BIOS write and a
repeated committed launch without performing the side effect twice.

## Image boundaries

- **Raw:** exactly 64, 128, 256 or 512 KiB and a complete 512-byte BIOS.
- **LNX:** retain all 64 header bytes; supported version 1 / bank-0 page geometry
  only. The pinned core's second cartridge bank is unimplemented and rejected.
- **BS93:** valid nonzero RAM entry and declared payload size; no RAM wrap. The
  host pads an odd payload with one trailing NOP and updates the container length
  because the pinned core consumes complete words. It reports input/wire hashes
  separately; the user's input file is not modified. No BIOS is required for this
  path.

Serial loading is a bench interface with per-word acknowledgments. It is not the
final self-contained game storage/boot experience. Image format validation does
not prove a particular game's compatibility or grant rights to game/BIOS content.

## Remaining acceptance

The real-console integration now passes through these services. Implement RGB
capture, completed-frame ownership, line buffering, exact scaling, display/audio
transport and the full board clock/pin adapter. Keep physical acceptance separate.

The present SDRAM controller uses individual auto-precharged words. It is a
compatibility bring-up implementation. Enhanced graphics still needs a measured
service budget and likely burst/locality improvements; these tests do not establish
the earlier enhanced scene throughput targets.

## Real-console integration

```sh
nix --extra-experimental-features 'nix-command flakes' build .#lynx-tang-core-check -o build/lynx-tang-core-check -L
```

This test runs the actual translated CPU, Suzy and Mikey. It sends an original
198-byte BS93 diagnostic through the real UART/CRC parser and loader into the
controller-backed SDRAM path and the original local RAM/header interface. It
does not reconstruct the FPGA instance or replace console behavior between boots.

| Phase | Complete ordered frame | Master clocks until observed |
| --- | --- | ---: |
| Initial serial boot, input released | 16,320 pixels, RGB444 `0x0f0` | 3,429,308 |
| Serial A held | 16,320 pixels, RGB444 `0xf00` | 2,095,203 |
| Serial A released | 16,320 pixels, RGB444 `0x0f0` | 2,095,275 |
| Recovery/stop, reupload and warm boot | 16,320 pixels, RGB444 `0x0f0` | 3,429,304 |

The CPU also forces cartridge fetches and verifies their data before enabling
display. Twelve requests receive twelve correct acknowledgments; two external
SDRAM reads serve them through the aligned-word cache, one miss per boot. The
second miss checks cache invalidation across reload. There are 39,301 refreshes
across the full 19,701,726-clock integration run. The
[integration snapshot](../research/evidence/tang-core-integration-2026-11-17.json)
records artifact/source hashes and explicit exclusions.

### Warm-reset defect and correction

The first integrated run passed cold boot and input changes but failed warm
reload. Direct observation confirmed that all uploaded RAM bytes matched the
image and the header still selected `$0200`. The upstream CPU retained
`bus_request=1` at an old address (`$02a5`) during reset. At the first resumed
clock-enable, the memory mux serviced that stale request while the CPU began
the new fetch. It returned zero instead of the initial SEI opcode, leading into
BRK/zero-page execution.

The exported source adaptation now clears CPU request/IRQ strobes, memory
completion/write enables and cart wait **during reset only**. Normal execution
algorithms and timing are unchanged. Both the standalone core diagnostic and the
full UART/loader/controller integration now include passing warm-reset/reload
regressions. The corrected core also passes a fresh
[registered route audit](../research/evidence/lynx-tang20k-2026-11-17.json):
11,710 LUT sites, 5,062 registers, 33 BSRAMs and 81.833 MHz estimated maximum
against 64 MHz. This remains a core-only harness; the board services tested here
are not included in its timing result.

## First video-path primitive

```sh
nix --extra-experimental-features 'nix-command flakes' build .#video-fifo-check -o build/video-fifo-check -L
```

The portable [same-clock queue](../../hardware/video/cb_sync_fifo.sv) stores 256
32-bit RAM entries plus one registered output. Its independent sequence model
checks full/empty behavior, wrap, producer/consumer backpressure, stable stalled
output and resets with queued data. It passes 75,105 accepted values, 66,799
consumed values and 8,306 explicitly reset-cancelled values across 51 resets.
Gowin synthesis maps the queue into **one block RAM**, with no unintended latches.
This is a verified building block, not a completed framebuffer or scanout engine.

## Complete-frame capture component

```sh
nix --extra-experimental-features 'nix-command flakes' build .#frame-capture-check -o build/frame-capture-check -L
```

The original [capture module](../../hardware/video/lynx_frame_capture.sv) uses
three presentation banks. It stores emitted RGB444 samples as padded 16-bit
values, keeps accepted writes pending until acknowledgment, and publishes only
an entire ordered 160×102 frame. Overflow, truncation and discontinuous source
addresses invalidate the candidate; its writes drain before the bank is reused.
Display ownership prevents that bank from being written.

The [independent delayed-write test](../../sim/frame-capture.cpp) passes **82,038
committed pixel writes** and **five valid presentations**. It compares every
pixel in each presented bank with a source-frame pattern and exercises
simultaneous final completion/presentation, randomized write acceptance/latency,
overflow, truncation, out-of-order input, disable/drain and bank reuse.

This component check shares one clock with its modeled write sink. `present` is
a caller-supplied safe boundary after old display reads drain. The subsequent
[buffered-video milestone](tang-video.md) now connects it to the actual console,
SDRAM arbiter, line reads and pixel-clock crossing. Serialization, audio and
full-board timing remain separate work. See
[the ownership diagram](../chip-design/memory.md#a-frame-cannot-have-two-writers).

## References

- [Original RTL and system boundary](../../hardware/tang/lynx_tang_system.sv)
- [Service testbench](../../sim/tang-services.cpp)
- [Host tool](../../tools/lynx_link.py)
- [Prior core-only audit](../research/lynx-tang20k-compatibility.md)
- [Sipeed's original SDRAM controller reference](https://github.com/sipeed/TangNano-20K-example/blob/e23949a0a77381b94960cbc4e97a7c5e5ba8d222/nestang/src/sdram.v)
- [Gowin GW2AR datasheet, geometry/CAS characteristics](https://cdn.gowinsemi.com.cn/DS226E.pdf)
- [Gowin controller guide, command structure and phase/timing requirements](https://www.gowinsemi.com/upload/database_doc/2265/document/68f697b42e222.pdf)

Controller/model recovery intervals are conservative engineering checks for this
64 MHz configuration, informed by the board reference. Neither the guide's
example cycle counts nor this software model replace part-specific electrical
timing review and physical testing.
