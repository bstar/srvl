# Complete Tang bench build and timing coverage

Reviewed: **2026-11-17**. Status: **complete-board mapping, pin coverage,
placement/routing and fuse packing pass; complete timing qualification and
physical acceptance remain open**.
This is the actual bench-board top, including the original console, shared
memory services, buffered RGB, stereo audio, clocks, resets, serializer
primitives and I/O. It is distinct from the earlier registered core-only probe.

## What the board build contains

[lynx_tang_board.sv](../../hardware/boards/tang_nano20k/lynx_tang_board.sv)
uses host serial loading and controls. It sends fixed-mode RGB-only digital
video through the Tang display connector and I²S to the onboard mono-amplifier
interface. The core retains stereo; a final stereo analog circuit is still open.
There is no self-contained game browser, SD-card loader, multiboot controller or
handheld-panel driver in this image.

| Mapped resource | Count | Scope |
| --- | --- | --- |
| Block RAM | 35 of 46 | Original work RAM plus buffering; includes video and audio services |
| Registers | 6,234 of 15,552 | Complete bench top, including reset/control |
| LUT4 cells after normalization | 9,534 | Combinational LUT cells; ALU carry resources are additional |
| ALU cells before packing | 3,615 | Do not add this blindly to a final place/route utilization figure |
| System/video PLLs | 2 of 2 | Mapped and accepted by the packer; electrical clock quality untested |
| CLKDIV | 1 | Pixel clock derived from the serializer clock |
| OSER10 | 4 | Three data lanes and one forwarded clock lane |
| Differential output buffers | 4 | Device-specific bench output; physical signaling unqualified |

These are synthesis quantities, not a new graphics-engine budget. The
[dated build evidence](../research/evidence/tang-board-2026-11-17.json) records
the exact artifacts and distinguishes mapping, packing, routing and timing coverage.

## Current routed result and image

The corrected true-LVDS top places, routes and packs successfully. Final routed
utilization is **13,460 / 20,736 logic sites**, **6,234 / 15,552 registers** and
**35 / 46 block RAMs**. The pack-only figure is 13,754 logic sites;
keep the stages distinct when comparing resources. These **2026-11-24** results
use the [shared memory service](enhanced-memory.md); the last build with the
separate legacy controller and arbiter routed to 13,414 logic sites, 6,229
registers and 69.382 MHz, and is kept as a historical run in the evidence.

| Reported clock domain | Target | Tool-estimated maximum |
| --- | --- | --- |
| System | 64 MHz | 69.238 MHz |
| Pixel | 25.2 MHz | 79.586 MHz |
| Audio | 12.288 MHz | 194.818 MHz |

All eight explicit targets were applied. The three reported sequential clock
domains pass their scoped frequency checks. The 126 MHz serializer target does
not produce a timing-qualified serializer path because that primitive lacks a
model. These numbers are **partial-model tool results**, not measured clock
limits or complete-board signoff.

The Nix image output contains `lynx-tang-bench.fs` and a relative
`sha256.txt` checksum, plus exact build sources, upstream notices, checks and
route reports. The current image hash is in the dated evidence. No physical
board was programmed. A second identical place/route run has not yet established
bit-for-bit route reproducibility; the toolchain, sources, seed and thread count
are pinned for reproduction.

## Checked pins and clocks

The [pin manifest](../../hardware/boards/tang_nano20k/pins.json) records the
package, directions, pin assignments, polarity, clock requirements and source
references. The [generator](../../scripts/prepare-tang-board.py) compares it
with the actual mapped top, rather than accepting an unrelated pin table.
All **79 top-level signal bits** are covered, with no duplicate pad labels.
The nextpnr packer additionally checks placement legality against its device
database. Neither check measures actual board wiring or electrical behavior.

| Function | Assignment / requirement |
| --- | --- |
| System reference | FPGA pin 10, externally configured 64 MHz |
| Video reference | Pin 11, externally configured 25.2 MHz |
| Audio reference | Pin 13, externally configured 12.288 MHz |
| Reset button | Pin 88, active high, pull down |
| UART | RX 70, TX 69 |
| Six LEDs | Pins 15–20, active low |
| Display clock | Differential pair 33/34 |
| Display blue / green / red | Pairs 35/36, 37/38, 39/40 |
| Audio | Amplifier enable 51, data 54, word select 55, bit clock 56 |
| Embedded SDRAM | Named die pads in the manifest; these are **not** header/package pin numbers |

Pin and display-standard references are the
[board vendor's pinned examples](https://github.com/sipeed/TangNano-20K-example/tree/e23949a0a77381b94960cbc4e97a7c5e5ba8d222)
and its [clock-generator guide](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/example/unbox.html).
The embedded-memory names follow the
[pinned SDRAM port example](https://github.com/Seyviour/sdram-tang-nano-20k-os-example/blob/9f787879f8d7d93e076f35d3123879241d6a5cec/src/sdram.nano20k.cst).
The manifest retains the exact individual source paths.

Eight explicit clock targets cover the three inputs, system/serializer/pixel/
shifted-SDRAM clocks, and the internal audio clock after its input buffer.
PLL ratios, reference connections, divide-by-five wiring and all four serializer
clock connections are checked against the mapped primitive graph. Parameter
agreement is not phase, jitter or setup/hold acceptance.

The display pairs use **TLVDS_OBUF with LVDS25 and 3.5 mA drive**, following
the board vendor's constraints. The bitstream packer rejected an earlier
ELVDS configuration because these sites are true-LVDS pins. The current build
corrects both the primitive and the I/O standard. A nextpnr packing pass alone
had not detected that mismatch; the final fuse packer is a separate check.

Two pinned-tool behaviors affected this integration. Differential pair shorthand
does not infer a vector's negative name correctly, so both sides of every pair
are assigned explicitly. An external input clock target also did not propagate
to the internal audio clock in the first route, so that internal net now has
its own 12.288 MHz target. The initial route is retained as historical evidence;
it is not the accepted timing result.

The [fault-injection check](../../scripts/check-tang-constraints.py) rejects
missing ports, duplicate pads, wrong bus widths, wrong direction, incomplete
differential buses, a wrong reference frequency and a wrong PLL ratio. The
normal component tests still cover the actual encoder, reset and audio logic.

## Timing coverage is a measured boundary

The pinned Himbaechel database contains a delay model for **LUT4**, but no
LUT1/LUT2/LUT3 variants. The first mapped netlist contained 4,793 such smaller
cells. Its reported maximum frequencies therefore did not establish timing
through those cells.

The [normalization pass](../../scripts/normalize-gowin-luts.py) represents each
small LUT as an equivalent physical LUT4, ties unused inputs low and replicates
its truth table. It checks **29,030 original input combinations** across all
converted cells. Registers, memories, DSPs, I/O and existing LUT4 cells are
unchanged. This closes the missing small-LUT model boundary for the new board
build; it does not retroactively change the historical core-only probe.

The [coverage report](../../scripts/report-gowin-timing-coverage.py) reads the
**actual binary chip database**, verifies its schema and constant IDs against
the pinned tool source, selects the device speed grade, and compares available
cell models with the netlist. Fabric-model presence is a narrower result than
complete path analysis. DSP multipliers, OSER10, clock primitives and I/O still
lack the models or budgets needed for full board timing qualification.

The pinned generic SDC parser supports frequency targets but does not apply
`set_false_path`; input/output delay commands are unsupported. This build uses
no ignored false-path or multicycle exceptions and no timing-allow-fail flag.
Cross-domain paths remain visible in the tool's report. Handshake tests do not
simulate metastability or establish reset recovery/removal margins.

Full timing acceptance still needs justified DSP and serializer timing,
clock phase/skew, SDRAM setup/hold/read-capture budgets, external I/O constraints,
hold/path coverage, and a reviewed CDC/reset implementation. A routed-and-packed
file remains an **untested bench image** while those requirements are open.

## Reproduce the build

```sh
nix --extra-experimental-features 'nix-command flakes' build \
  .#tang-board-check -o build/tang-board-check -L
nix --extra-experimental-features 'nix-command flakes' build \
  .#tang-board-route -o build/tang-board-route -L
```

The route package deliberately retains failed runs. Inspect `exit-code.txt`,
`route.log` and `timing.json`; successful creation of its Nix output alone does
not mean routing or timing passed. This avoids losing the evidence of a failure.

The separate image recipe requires a successful nextpnr exit before packing:

```sh
nix --extra-experimental-features 'nix-command flakes' build \
  .#tang-bench-bitstream -o build/tang-bench-bitstream -L
```

Build definitions are in [nix/tang-bitstream.nix](../../nix/tang-bitstream.nix).
The image bundle links the exact project RTL, translated console source,
upstream notices, constraints and route reports. It contains no commercial
BIOS/game images and runs no programmer or serial clock-configuration commands.

## Acceptance that remains

Keep [roadmap gate 4](../roadmap.md#4-complete-tang-build-next-implementation-gate)
open until required timing coverage is established. Physical board testing
remains deferred under ADR 0004. Begin that later gate with the original
diagnostic and recorded reference-clock configuration, then owner-supplied
BIOS/game cases. The final backlit panel, controls, storage, power, PCB and case
remain separate workstreams.
