# Lynx MiSTer core on Tang Nano 20K

**2026-11-17 integration update:** [UART/loader/cart/SDRAM service checks](../milestones/tang-board-services.md)
now pass, and the real console diagnostic cold-boots and warm-reloads through that
path. Warm reload exposed retained CPU bus strobes in the pinned upstream core;
the exported adaptation patch now clears CPU request/IRQ strobes, memory write/
completion enables and cart wait during reset. Normal execution logic is unchanged.
Both the standalone cold/input/warm diagnostic and ordered-frame serial integration
regressions pass. The corrected core also passes a fresh registered route probe:
**11,710/20,736 LUT sites**, **5,062/15,552 registers**, **33/46 BSRAMs**, and
**81.833 MHz** estimated maximum against the **64 MHz** requirement. The
[current snapshot](evidence/lynx-tang20k-2026-11-17.json) includes the adaptation
hash and artifact. Board services are not inside this routed harness. The tables
below preserve the **2026-10-30 historical baseline**, before the reset correction.

The subsequent [buffered-video milestone](../milestones/tang-video.md) now adds
simulated exact-2× RGB through capture, shared SDRAM and cross-clock line buffers,
plus a 35-block-RAM portable-system mapping. Those services are still outside the
registered core-only route probe; full board timing remains open.

The [stereo acceptance record](../milestones/tang-audio.md) subsequently adds
actual Mikey timers, signed filtering, coherent sample transfer and pin-decoded
I²S alongside video. Analog fidelity and full board timing remain separate gates.

Reviewed: 2026-10-30. Status: compatibility and resource investigation; not a
playable Tang port, board acceptance, or replacement of ADR 0008.

**Result:** the adapted baseline Lynx console passes Gowin resource mapping,
placement/routing and a 64 MHz registered-core timing test on the exact Tang
device. Post-route use is 11,616/20,736 logic sites, 5,062/15,552 registers and
33/46 BSRAMs, including the test harness. The tool estimates 103.295 MHz maximum
for this configuration. This establishes a viable core-only implementation
candidate; SDRAM, presentation, loading, controls and physical testing still
need integration. Enhanced graphics fit is not established.

The [dated evidence snapshot](evidence/lynx-tang20k-2026-10-30.json) records the
source revision, locked tools, measurements, passed checks and scope limits.

## Question and evidence boundary

Can the original Lynx console be implemented on a Tang Nano 20K, with original
game behavior and exact 2× output, before committing to enhanced graphics?
The correct target for this audit is the original console plus a small board
adapter, not the entire MiSTer platform and not the new enhanced console too.

Upstream is pinned in `flake.lock` at
`3708e457e413aa7a33f8bec8fcd79eba45ce4702`, also the local reference checkout
and upstream HEAD checked on the review date. It includes the ComLynx serial
fix merged July 14, 2026. The local vendor checkout was not modified. Nix fetches
the pinned source independently, retaining its license and a source SHA-256
manifest with generated audit outputs.

Synthesis and simulation are separate evidence. A mapped console netlist does
not establish SDRAM timing, pin constraints, physical operation, or original
game compatibility. The adapted console uses the upstream CPU, not this
project's separately selected R65C02 implementation.

## Board resources

The [Sipeed specification](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
lists GW2AR-LV18QN88C8/I7, 20,736 LUT4s, 15,552 flip-flops, 46 blocks of 18,432
bits BSRAM (105,984 bytes, 103.5 KiB), 48 18×18 multipliers, two PLLs, 8 MiB
32-bit SDR SDRAM, and 8 MiB flash. SDRAM is packaged with the FPGA; it still
requires a controller. It is not interchangeable with synchronous internal RAM.
The board also has HDMI, RGB LCD, microSD, a MAX98357A speaker amplifier, BL616
programming/UART support, and an MS5351 clock generator.

Gowin and Intel logic metrics cannot be converted by dividing MiSTer ALMs by
a constant. Measure a Gowin-mapped design and then pack/place/route it.

## Partition and required changes

| Subsystem | Upstream implementation | Tang implications |
| --- | --- | --- |
| CPU | `rtl/cpu.vhd`, Lynx-specific execution and bus requests | Retain for the compatibility audit; changing CPU needs a separate behavioral comparison |
| Suzy | `gpu.vhd`, `math.vhd`, `joypad.vhd` | Portable VHDL; retain sprite decoding, collision, arithmetic, input and timing behavior |
| Mikey | timers, audio, DMA, serial, cart and register modules | Portable VHDL; preserve clocks, interrupts and bus arbitration |
| System RAM | 64 KiB Intel `altsyncram` through `dpram.vhd` | Replace primitive with verified Gowin RAM; retain low-latency access initially |
| Boot ROM | Writable 512-byte internal memory | Load a separately supplied boot image; no Atari BIOS is included |
| Cartridge data | External x16 SDRAM through `sdram.sv` | Adapt to Tang's x32 SDRAM geometry, timing and arbitration |
| Presentation | Three RGB444 frames, rotation, blending, `video_mixer` and MiSTer scaler | Replace with a small display adapter; place framebuffers in SDRAM if needed |
| Menus, loading, controllers | MiSTer `hps_io` plus ARM/Linux platform services | Provide Tang-specific loading and controls; these services do not transfer automatically |
| Audio output | Signed 16-bit stereo samples into MiSTer | Add I²S transport; onboard mono speaker amplifier does not provide stereo headphone output |
| Rewind / save states | State bus and MiSTer DDR3-backed storage | Disable initially; removing convenience features does not remove Suzy/Mikey behavior |
| ComLynx | Open-drain shared line in the platform wrapper | Requires an electrically correct external interface and real-device tests |

The upstream SDRAM controller uses a 16-bit bus, CAS latency 2 at 64 MHz and
device-specific row/column/mask handling. Connecting its pins to a 32-bit
controller without adapting the transaction interface is insufficient. Its
cartridge interface already has request/acknowledge flow control, making it a
reasonable boundary for a replacement controller. Validate variable latency and
arbitration; do not assume capacity means deadlines are met.

The board's BL616 may handle support functions if an appropriate firmware is
chosen. It is not needed to execute the Lynx CPU or draw graphics. No companion
firmware or USB host implementation is selected by this audit.

## Memory constraint and presentation design

The stock `AtariLynx.sv` declares three arrays of 16,320 × 12-bit RGB pixels.
They require 73,440 bytes, and the system RAM another 65,536 bytes: a minimum
138,976 bytes (135.72 KiB), before BIOS, FIFOs, register shadow storage and RAM
packing inefficiency. This exceeds Tang's 105,984 bytes of BSRAM. Even ignoring
MiSTer's much larger scaler/framework, the stock arrangement cannot fit in
internal memory. Merely turning off a runtime option does not remove its arrays.

The original game-visible packed 4bpp framebuffer is 8,160 bytes **inside** the
64 KiB system RAM. The separate RGB presentation frames above contain palette
changes captured during display DMA; replacing them with a simple 4bpp buffer
and one final palette can change raster palette effects.

Prefer keeping the 64 KiB system RAM internal and storing two RGB444 presentation
frames in SDRAM as 16-bit words. Two frames occupy 65,280 bytes. Keep small
write FIFOs and scanout line buffers in BSRAM. An original 160×102 pixel is
repeated into a 2×2 block for 320×204 output; this does not make Suzy render four
times as many pixels and does not require a 320×204 legacy framebuffer.

At 79 source frames/s, RGB16 presentation writes average 2.579 MB/s. Reading one
source frame at 60 Hz is 1.958 MB/s; re-reading each row twice without a row-reuse
buffer is 3.917 MB/s. These are payload estimates, excluding cartridge traffic,
refresh, row changes and burst inefficiency. Buffering must cover the pixel
bursts and scanout deadlines, not only average throughput.

## Clocks and compatibility hazards

**2026-11-17 timing-coverage clarification:** the historical registered core
probe's 81.833 MHz result uses the pinned tool's partial timing models. A later
[complete-board review](../milestones/tang-board-build.md#timing-coverage-is-a-measured-boundary)
found missing LUT1–LUT3 and DSP timing variants in the actual database. The new
board build normalizes small LUTs to equivalent LUT4s; it does not retroactively
qualify this older probe or close DSP/serializer/external I/O timing.

The upstream console input is 64 MHz. Normal system enable is every fourth
clock, giving a 16 MHz system timing basis; this is not a 16 MHz instruction
rate. `rtl/pll/pll_0002.v` creates two 64 MHz outputs. A Tang adapter needs
explicit clocks, reset synchronization, memory clock relationships and physical
timing constraints. Our enhanced console's existing 6.288 MHz simulator clock
cannot replace the Lynx clock without changing behavior.

Lynx software controls display timing, with upstream documenting approximately
50–79 Hz. Preserve console speed and decouple display presentation from a fixed
60 Hz panel by repeating/dropping complete frames. There will be cadence effects
when rates differ. Making every game run at exactly 60 Hz by pausing the core
can affect game speed and audio. Upstream [issue 22](https://github.com/MiSTer-devel/AtariLynx_MiSTer/issues/22)
reports a video/core speed mismatch and audio problems with the 60 Hz sync
option. Exact 2× pixel geometry does not imply exact temporal reproduction.

The upstream README says official games should be playable and most homebrew
works; this is its author's claim, not a result of this audit. External EEPROM
is explicitly unsupported. Open [issue 24](https://github.com/MiSTer-devel/AtariLynx_MiSTer/issues/24)
reports unexpected Suzy behavior in a timing test, and [issue 23](https://github.com/MiSTer-devel/AtariLynx_MiSTer/issues/23)
reports a Joust visual glitch. Preserve these as baseline limitations and compare
changes against the pinned upstream build and real Lynx evidence where available.

The ROM/header loader accepts raw images and LYNX/BS93 forms. Preserve its byte
ordering, 64-byte LYNX header handling, bank-size detection and boot-image upload.
Physical cartridge support is a separate electrical/media project. A physical
W65C02 does not eliminate the Suzy/Mikey work or automatically match this CPU.

## Reproducible audit implementation

`scripts/prepare-lynx-audit.py` copies only the upstream VHDL dependency list,
replaces the Intel RAM with an **audit-only same-clock inferred RAM**, narrows
the overlay's X/Y integer formals to their callers' existing ranges and narrows
the state-manager slot formal to 0–3 for GHDL. It records the exact changes as
`audit-adaptations.patch`. No CPU/GPU algorithm is changed. The adapter preserves
own-port write-through with explicit registered bypasses. Mixed-port read/write
collisions are marked unspecified (`no_rw_check`), matching the original Intel
model's default `DONT_CARE`; same-address dual writes are also outside the defined
comparison. `ram_style=block` prevents silent conversion of the 64 KiB memory to
hundreds of thousands of flip-flops. A generic first attempt without these
semantics did not map to BSRAM and was rejected; it is not the reported sizing
result. Actual Gowin RAM and board behavior still require tests. GHDL warns about
upstream signed constant truncation and unhandled RAM attributes; the latter are
preserved in generated Verilog and used by Yosys. The FIFO's Intel
`ramstyle=logic` is also retained.

The original GHDL Verilog is retained as `lynx.v`. Equivalent complete RAM/ROM
initializers are compacted into checked hexadecimal files and `lynx-compact.v`
for synthesis. The integration diagnostic passed with both forms; no memory
values are discarded.

A generated `lynx_audit` wrapper disables fast-forward, turbo, cheats, FPS
overlay, rewind and save/load requests, preserving normal console functionality.
It exposes pixel writes, stereo samples, ROM transactions, BIOS upload and Lynx
buttons. It omits the platform, display buffers and physical memory controller.

Nix packages and commands:

```sh
nix --extra-experimental-features 'nix-command flakes' develop .#tang
nix --extra-experimental-features 'nix-command flakes' build .#lynx-compatibility-audit -o build/lynx-compatibility-audit -L
nix --extra-experimental-features 'nix-command flakes' build .#lynx-audit-hdl -o build/lynx-audit-hdl -L
nix --extra-experimental-features 'nix-command flakes' build .#lynx-audit-smoke -o build/lynx-audit-smoke -L
nix --extra-experimental-features 'nix-command flakes' build .#lynx-audit-report -o build/lynx-audit-report -L
nix --extra-experimental-features 'nix-command flakes' build .#lynx-audit-route-probe -o build/lynx-audit-route-probe -L
nix --extra-experimental-features 'nix-command flakes' build .#lynx-audit-ram-check -o build/lynx-audit-ram-check -L
```

Tools are pinned through the existing Nixpkgs input: GHDL 6.0.0, Yosys
0.70+post, nextpnr 0.11.1, Apicula 0.34. The Tang uses device
`GW2AR-LV18QN88C8/I7` and nextpnr family `GW2A-18C`, per the
[Apicula tool documentation](https://github.com/YosysHQ/apicula/wiki/Nextpnr%E2%80%90Himbaechel-Gowin).
`gowin_pack` and openFPGALoader are available in the shell. No board is programmed
and no commercial ROM is fetched by these commands.

The optional `lynx-audit-ram-check` additionally uses the project's existing
Quartus 17.0.2.602 simulation library. The Tang shell and synthesis flow use the
open tools and do not require that unfree package.

`lynx-compatibility-audit` aggregates all stages, including that RAM-model
comparison, and **fails** unless the diagnostic, RAM comparison, resource limits
and 64 MHz route result pass. Its `evidence.json` summarizes the results, with
the supporting outputs alongside it.
The default `nix flake check` also runs the original Lynx diagnostic, alongside
the existing console/game checks; it does not fetch Quartus for the RAM test.

## Measured Gowin synthesis

`lynx-audit-report` completed with the corrected block-RAM adapter:

| Resource | Measured baseline | Tang capacity | Assessment |
| --- | ---: | ---: | --- |
| LUT1–LUT4 cells | 8,159 | 20,736 LUT4 sites | Before packing with ALUs/wide-mux constraints |
| ALU/carry cells | 2,327 | Share logic-site resources | LUT plus ALU estimate: 10,486 sites, 50.6% |
| Flip-flops | 4,886 | 15,552 | 31.4% before the route harness |
| Block RAM | 32 DPB + 1 DPX9B | 46 blocks | 71.7%; 13 blocks remain |
| Multipliers | 3 MULT18X18 + 9 MULT9X9 | 48 18×18 units | Smaller units have packing rules; use the pack report for physical use |
| Latches | 0 | — | None inferred |

Yosys reports no remaining design-check problems. BRAM mapper warnings concern
padding of unused lanes: work RAM is mapped as 32 one-bit-wide DPBs with only
the active data bit connected. Undefined padding bits are not game RAM data.
The mapping also includes wide LUT muxes; the site estimate is not a replacement
for physical packing. Approximately half the nominal logic is available for
board support, but RAM, control sets, routing and timing must all fit together.

This is evidence that the original console is a credible resource fit. It does
not establish that every MiSTer feature or the enhanced graphics engines fit.

## Registered route probe

`scripts/prepare-lynx-route-probe.py` preserves every mapped console cell and
replaces its wide virtual input/output boundary with serial input registers and
registered output capture. Four physical I/O buffers avoid pretending that all
177 console interface bits are external board pins. The extra registers and
capture LUTs are counted separately in `scope.json`.

The probe targets the exact Tang part/family at 64 MHz, seed 1, with no false-path
or multicycle exceptions. Pin locations are checked against Sipeed's
[HDMI constraints](https://github.com/sipeed/TangNano-20K-example/blob/main/hdmi/src/hdmi.cst)
and [LED constraints](https://github.com/sipeed/TangNano-20K-example/blob/main/led/flow_led/src/flow_led.cst).
It is a tool harness, not a handheld pin map. In particular, constraining the
clock input to 64 MHz does not reconfigure the board's physical 27 MHz source.
The actual port needs a suitable clock source and its own constraints.

The Nix target retains `exit-code.txt`, `route.log`, and timing/routed JSON when
available, including failed results. A successful Nix artifact build alone is
not a successful timing result: inspect the recorded exit code and timing.
SDRAM/display/controller/loader timing and I/O paths remain outside this probe.

The completed route probe returned exit code **0**, with no nextpnr warnings or
errors in the recorded log:

| Post-route result, including the harness | Used | Capacity / target |
| --- | ---: | ---: |
| LUT4 sites, including ALU packing and route overhead | 11,616 | 20,736 (56.0%) |
| Registers | 5,062 | 15,552 (32.5%) |
| BSRAM blocks | 33 | 46 (71.7%) |
| 18×18 / 9×9 multipliers | 3 / 9 | 48 / 96; shared packing constraints |
| Core clock | 64 MHz required | 103.295 MHz estimated maximum |
| Worst reported setup slack at 64 MHz | About +5.94 ns | Positive |

The critical path is in the upstream CPU, with 5.21 ns logic and 4.47 ns routing
in the report. This is one seed and the open tool's device/timing model, not a
measurement on a physical board or proof over all manufacturing/voltage/thermal
conditions. No multicycle or false-path exceptions were introduced. The harness
adds 95 input registers, 81 output registers, 81 capture LUTs and four I/O buffers;
every mapped console cell is retained. Packing initially reports 10,964 logic
sites, while the final routed JSON reports 11,616; use the latter for headroom.
9,120 logic sites and 13 BSRAMs remain before real board integration. The report's
384 IOB availability describes the die model, not externally accessible QN88 or
board-header pins; it is not a board pin budget.

## Completed behavioral evidence

The original `hardware/tests/lynx-audit.s` diagnostic loads through BS93 and
executes on the upstream CPU in Verilator. It checks a RAM store/increment/read,
Suzy unsigned `$1234 × 3 = $0000369c`, initializes a packed framebuffer, sets
Mikey line/frame timers and display DMA, and changes palette index 1 according
to button A. `sim/lynx-audit.cpp` checks every one of the 16,320 pixel addresses
for green, red while A is held, then green after release.

The Nix `lynx-audit-smoke` target passed:

| Phase | Master cycles until all pixel addresses observed with expected color |
| --- | ---: |
| Initial green frame | 3,404,729 |
| A held: red | 1,068,444 |
| A released: green | 1,068,480 |

This tests the translated HDL and audit RAM adapter in simulation. It does not
exercise sprite decoding/collision, the full CPU instruction set, audio, serial,
commercial cartridge/BIOS loading, save states, cross-port RAM corner cases or
physical FPGA behavior. Zero commercial games have been tested on the Tang.

The independent `lynx-audit-ram-check` compares the generated adapter against
the actual Quartus `altsyncram` behavioral model, with the same parameters as
the upstream primitive and independent port enables/read/write patterns. It
passed **23,931 defined port observations across 12,000 deterministic cycles**,
including own-port write-through and output holds during disabled clocks.
It excludes mixed-port same-address read/write collisions and simultaneous
same-address writes, whose values are unspecified upstream. This is RTL/model
comparison, not simulation of physical Gowin primitives or an exhaustive proof.

## Decision gate

Do not treat board price or another retro core running on this board as proof of
Lynx fit. Record Gowin mapping, pack/place/route results and limitations here.
After a successful console fit, a playable port must still integrate the Tang
SDRAM/display/input/loader/clock interfaces and pass simulation and hardware
tests. Native 320×204 enhanced engines need a separate budget; optionally loading
legacy and enhanced configurations avoids paying for both at once.

The next port's acceptance matrix is explicit:

| Work | Evidence required before claiming support |
| --- | --- |
| Gowin memory | Primitive-level or hardware checks for initialization, enable holds, own-port forwarding and loader access; preserve the defined Intel behavior |
| SDRAM/controller | Correct x32 geometry, refresh and byte lanes; randomized request latency; no scanout FIFO underruns or dropped writes under cartridge reads |
| Image loading | BIOS upload and raw/LYNX/BS93 files, byte order, headers, bank sizes and reset sequencing; no MiSTer HPS dependency |
| Video | Every 160×102 RGB sample becomes the correct 2×2 block, including palette changes; bounded frame repeats/drops at different game rates |
| Console behavior | Focused sprite scaling/RLE/collision, math, CPU interrupts/decimal mode, timers and stereo audio tests; compare to pinned upstream and hardware evidence |
| Complete board build | Exact clocks and pins, all required I/O constraints, full controller/display/loader logic included, timing pass with reviewed coverage |
| Physical games | Owner-supplied BIOS/game images exercised on the actual Tang, including vertical orientation and timing-sensitive cases; record hashes and failures |

ComLynx with an original Lynx and physical cartridge support remain separate
hardware acceptance items. Neither is inferred from the console's resource fit.

The existing enhanced console, game ROM and accepted ECP5 target are unchanged.
The Tang passes this baseline feasibility gate. A playable port, actual hardware
acceptance and separate enhanced-console sizing remain open.

## References

- [Pinned upstream source and README](https://github.com/MiSTer-devel/AtariLynx_MiSTer/tree/3708e457e413aa7a33f8bec8fcd79eba45ce4702)
- [Sipeed board specifications and hardware files](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
- [Apicula flow and supported primitives](https://github.com/YosysHQ/apicula/wiki)
- [Existing Lynx compatibility research](lynx-hardware.md)
- [Current standalone target](../architecture/standalone-platform.md)

The upstream root license is GPL v2, its MiSTer wrapper states GPL v2-or-later,
and `rtl/sdram.sv` explicitly states GPL v3-or-later. Preserve the actual notices,
source and modifications when reusing/distributing components. The audit retains
the source and license; it supplies no rights to Atari BIOS/game images.
