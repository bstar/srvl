# First standalone development target

Date: 2026-10-30. Status: selected engineering target under
[ADR 0008](decisions/0008-standalone-development-target.md). Physical acceptance,
procurement and the complete enhanced graphics implementation remain ahead.

## Decisions to develop against

| Area | First standalone target |
| --- | --- |
| FPGA | Lattice ECP5 **LFE5U-12F-6BG256C**, 12K LUT class, CABGA256 |
| CPU | Existing pinned/patched R65C02 HDL core inside the FPGA |
| Native CPU clock | Target 20.1216 MHz; the current simulator remains at 6.288 MHz |
| Graphics/memory clocks | Target 50.304/100.608 MHz from a 25.152 MHz reference |
| Working/graphics storage | One **32 MiB, 16-bit SDR SDRAM**; reference part W9825G6KH-6 |
| Nonvolatile storage | **16 MiB QSPI NOR flash**, reference W25Q128JVSIQ |
| Display interface | 3.3 V parallel RGB with PCLK/DE/HS/VS, backlight control |
| Game rendering | 320×204, 60 Hz; 400×262 total raster at 6.288 MHz |
| Legacy output | Unmodified Lynx images, 160×102 rendered pixels replicated 2× |
| Audio/input | FPGA stereo sound logic, external filtering/amplifier, direct buttons |
| Tools | Nix, GHDL, Yosys, nextpnr-ecp5, Trellis; software acceptance first |

These choices define development constraints; they do not claim the PLL, SDRAM,
full core or LCD has passed hardware timing. Panel selection and exact PCB balls
remain electrical integration decisions. No board purchase or ASIC fabrication is
authorized by this record. The former US$275 development board is not required.

## Why the CPU stays in the FPGA initially

The owner explicitly allowed physical retro chips when they improve the design.
Compare checked component prices before memory, power, board and assembly:

| CPU/FPGA arrangement | One-off listed subtotal | Selection |
| --- | ---: | --- |
| Soft CPU in UP5K | US$11.11 | Too restrictive as the baseline: 39 I/Os and CPU uses about half its LUTs |
| Physical W65C02S + UP5K | US$22.15 | CPU saves LUTs but consumes bus pins; narrow/multiplexed interfaces need more glue and validation |
| Soft CPU in ECP5-12F | **US$16.78** | Selected development target: more logic and direct memory/display I/O |
| Physical W65C02S + ECP5-12F | US$27.82 | Adds CPU cost and bus integration without an established benefit for this prototype |

These are component comparisons, not complete board quotations or guaranteed
stock. The ECP5 listing shows no stock when checked. The FPGA is US$6.78 above
the roughly US$10 aspiration; it is not represented as meeting that aspiration.
This engineering choice favors lower total system cost over fitting the FPGA
line item alone. It does not approve spending or establish a new user budget.
If US$10 is a strict component ceiling, this baseline needs a deliberate revision;
do not silently order a different part or claim UP5K supports every feature.

At the checked prices, FPGA + reference SDRAM + flash have an indicative subtotal
of about **US$25–30**. Budget separately for regulators, clock source, PCB, assembly,
connectors, LCD, controls, audio, battery and charging. Stock and landed prices
must be rechecked before a board BOM is released. This is not a US$10 console.

Physical CPU, dedicated retro sound and 65C22-style I/O are not first-board
dependencies. Preserve a clean eight-bit CPU bus so an external CPU remains a
future option, but do not spend pins, PCB area or development time on it now.

## Resource contract

The machine-readable contract is
[hardware/targets/standalone.json](../../hardware/targets/standalone.json).
It uses published **12F** resources even if an implementation tool reports the
shared 25F die's larger fabric. Spare silicon is not permission to enlarge the
console without a recorded revision.

| Resource | Published capacity | Development limit | Allocated |
| --- | ---: | ---: | ---: |
| LUT sites | 12,000 | 9,600 | 9,600 |
| 18-Kbit block RAMs | 32 | 28 | 22 |
| 18×18 multipliers | 28 | 16 | 12 |
| User I/Os | 197 | 128 | 117, including reserve/debug allowance |

Allocations are engineering ceilings, not predictions of implemented utilization.
The remaining 2,400 LUTs provide routing/integration headroom. The CPU allocation
is 4,000 LUT sites. A fresh Yosys ECP5 synthesis of the existing core used 3,122
`LUT4` and 48 `CCU2C` primitives: approximately **3,218 LUT sites**, counting two
sites per carry primitive. It also used 155 FFs and dedicated wide-mux primitives.
This fits the CPU allocation; only placement/routing can establish actual packing
and speed, and the rest of the enhanced console is not yet synthesized.

CPU block RAM allocation covers 8 KiB direct work RAM plus an approximately 8 KiB
instruction/data cache budget. External SDRAM holds additional CPU-visible memory,
program images and graphics. Keep CPU accesses separate from the graphics-local
address space through explicit mapping and arbitration. The existing prototype's
ROM/map remain the software regression target until the new adapter passes.

## Pins and memory buses

Use the **16-bit SDRAM interface**, not the earlier hypothetical 32-bit graphics
bus. Reserve 39 signals for DQ[15:0], A[12:0], BA[1:0], DQM[1:0], CLK, CKE, CS,
RAS, CAS and WE. Clock/data placement and board signal integrity need verification.

Reserve 28 signals for RGB888 plus four video timing signals; the palette remains
RGB444 and component bits may be repeated for panel transport. Additional budgets
are five LCD control pins, six QSPI flash pins, five SD/SPI/card-detect pins,
eight buttons, two audio pins, clock/reset, debug allowance and sixteen spare
pins. This totals 117 signals conservatively; some debug/configuration signals
may use dedicated pins. It is a feasibility count, not a checked package-bank
assignment. Keep console-side digital interfaces at 3.3 V; power rails, panel
voltages, amplifiers and any translators still need a schematic.

One x16 SDRAM avoids several parallel SRAM ICs and the corresponding PCB area.
It costs a refresh/burst controller and requires buffers. Do not emulate it as
unlimited, zero-latency memory in acceptance tests. QSPI flash is for configuration,
boot and loading assets/programs; the CPU must not depend on one serial flash
transaction per instruction fetch.

## Graphics contract and explicit limits

Retain eight configurable 4-bpp tile planes, 256 resident object descriptors,
256 palette entries selected from RGB444, independent X/Y sprite scaling, flips,
clipping and row stretch/tilt. Raster tables provide line scrolling/palette-bank
changes. Resident object count is not a guaranteed count of large draws per frame.

Keep **1 MiB game-visible graphics storage**, even though the physical memory is
larger. Two 320×204, 16-bit object surfaces occupy 261,120 bytes. Each pixel holds
an eight-bit color index, four insertion-band bits and four reserved bits. Draw
back-to-front by band, avoiding per-pixel destination reads. Maps, descriptors,
patterns and meshes share the remaining graphics space. Loading infrastructure
and CPU/cart storage are separately mapped; they do not enlarge the graphics ABI.

For the first 3D version, use a shared fixed-point multiply/accumulate/divide unit
and an autonomous **screen-space flat-triangle rasterizer**. The 65C02 initially
handles scene transforms, projection, clipping and painter ordering with hardware
math assistance. This establishes a smaller implementable graphics interface.
Autonomous indexed-mesh transforms, texture mapping, affine floor planes, Z
buffers and alpha blending are later extensions, outside the first resource
allocation. Basic 3D remains a required workload; it does not depend on these
extensions. Near-plane clipping and ordering limitations must be tested explicitly.

At 100.608 MHz and 16 bits/transfer, peak SDRAM bandwidth is 201.216 MB/s. Use
**64 MB/s useful bandwidth** as a controller acceptance target, leaving substantial
headroom for refresh, setup and turnaround. This throughput must be demonstrated.
Reserve 8 MB/s for CPU/cache fills, 4 MB/s for uploads and 4 MB/s for geometry.
The remaining 48 MB/s supports these candidate 60 Hz scenes using the conservative
line-fetch equations in the earlier graphics research:

| Scene | Graphics traffic | With 16 MB/s reserved traffic |
| --- | ---: | ---: |
| Four planes + 256 objects, 16×16 | 37.542 MB/s | 53.542 MB/s |
| Two planes + 128 objects, 32×32 | 41.350 MB/s | 57.350 MB/s |
| Eight planes + 64 objects, 16×16 | 42.213 MB/s | 58.213 MB/s |

These are acceptance goals, not measured performance. They assume contiguous
4-bpp 1:1 sprite sampling and 16-bit writes; scale/minification, 8-bpp sources,
overlap, command setup and clipping must be measured separately. Eight planes
plus 256 32×32 draws exceed the traffic allowance and are not a guaranteed scene.
Keep scanout service reserved, stall producers safely, report lateness, and swap
only completed frames at vblank.

## Interfaces and compatibility

Develop CPU memory interfaces with explicit request/accept/read-valid semantics.
The CPU must be able to stall on memory/controller latency without repeating
MMIO effects or writes. Validate RDY/clock-control behavior before integration;
do not assume the CPU's existing instruction tests prove arbitrary stalls.

Keep current prototype registers working for regression. Reserve `$4400–$44FF`
for the first enhanced native graphics interface: auto-increment 20-bit VRAM
ports, a bounded command submission path, completion/fence/status and counters.
Finalize individual bit fields with the first blitter implementation. The engine
interfaces are reusable irrespective of the later physical CPU option.

Lynx mode needs its own original-visible memory, cartridge, graphics/collision,
audio, interrupt and timing behavior. The enhanced CPU rate must not drive legacy
software faster. Original frame cadence and the LCD's transport cadence stay
separate; exact pixel doubling does not require a game to execute at 60 Hz.
Original hardware and targeted tests remain the compatibility oracle; compatibility
is a required future acceptance stage, not established by this platform decision.

## Development sequence and gates

1. Nix CPU synthesis/resource check and the fixed platform budget. This is the
   current completed tooling step, not a physical core acceptance.
2. Memory/CPU request adapter and a latency/refresh-aware SDRAM model. Verify
   coherent reads, byte writes, arbitration, backpressure, reset and stalls.
3. Scaled blitter and diagnostic ROM at native resolution, then frame fences.
4. Tile compositor from two to eight planes and the three traffic workloads.
5. Math and flat-triangle drawing with a small original 3D diagnostic scene.
6. Full-system synthesis, package constraints and timing/resource acceptance
   within this contract before layout/purchasing. Keep current game regressions.
7. Physical board bring-up and Lynx compatibility are separate validation stages.

If a gate exceeds the limits, first improve scheduling/caching or reduce a
documented simultaneous workload. Do not quietly change the FPGA, memory limits,
clocks or game requirements. Bring the measured tradeoff back to a new decision.

## Reproduce current checks

```sh
nix --extra-experimental-features 'nix-command flakes' develop .#ecp5
nix --extra-experimental-features 'nix-command flakes' build .#standalone-cpu-sizing -o build/standalone-cpu-sizing -L
nix --extra-experimental-features 'nix-command flakes' flake check -L
```

The sizing result includes a mapped CPU netlist, tool version, synthesis log and
JSON report. It checks the platform's published resource caps, clock/raster ratios,
storage, pin totals and estimated traffic. No check programs a device.

## Sources

- [Lattice ECP5 family resources](https://www.latticesemi.com/Products/FPGAandCPLD/ECP5)
- [ECP5-12F listing and price](https://www.digikey.com/en/products/detail/lattice-semiconductor-corporation/LFE5U-12F-6BG256C/9553915)
- [UP5K listing and price](https://www.digikey.com/en/products/detail/lattice-semiconductor-corporation/ICE40UP5K-SG48I/7785190)
- [W65C02S price comparison](https://www.mouser.com/en/ProductDetail/Western-Design-Center-WDC/W65C02S6TQG-14?qs=opBjA1TV900Cx5CoX8hQeQ%3D%3D)
- [Reference SDRAM specifications](https://www.lcsc.com/product-detail/C62246.html)
- [Reference flash specifications](https://www.lcsc.com/product-detail/C97521.html)
- [Existing CPU and independent tests](../research/cpu-selection.md)
- [Earlier graphics exploration and sampling equations](graphics-effects.md)
