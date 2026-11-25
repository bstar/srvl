# FPGA development and custom silicon

Current update, 2026-11-15: [ADR 0009](../architecture/decisions/0009-tang-prototype.md)
selects Tang Nano 20K for the immediate prototype after its core feasibility audit.
ECP5 and pricing observations below remain dated research, not the current board
selection. The enhanced design still needs a Tang resource/bandwidth budget.

Reviewed: 2026-10-28. Status: development approach and later feasibility questions.

For the later request to investigate original Lynx support before selecting the
Tang Nano 20K, see the [pinned core compatibility audit](lynx-tang20k-compatibility.md).
It distinguishes console logic, MiSTer infrastructure and measured evidence.

Development-target update, 2026-10-30: [ADR 0008](../architecture/decisions/0008-standalone-development-target.md)
selects ECP5-12F with the soft CPU, x16 SDRAM and flash as the working engineering
target after comparing the physical CPU option. Earlier candidates and price
research below are retained as history. The FPGA's checked US$16.78 price exceeds
the US$10 aspiration; no purchase or spending increase is authorized. See the
[platform contract](../architecture/standalone-platform.md) for exact limits and
the reproducible Nix CPU sizing output.

## Agreed development path

Prototype circuits in HDL on the owner's existing MiSTer. Reuse a CPU core and
design the peripheral hardware. An FPGA implements configured digital circuits;
we can impose period-inspired clock, memory and bandwidth limits without using a
general-purpose processor to perform the console's rendering in software.

The MiSTer framework can supply menus, game loading, controllers and display
integration while the console logic remains a distinct subsystem. Its ARM/Linux
support infrastructure is a development convenience and should not become an
unexamined requirement of the eventual handheld.

Development loop: hardware description → simulation → Quartus synthesis/place and
route → load the core on MiSTer → run tests and original software. HDL simulation
is useful before hardware compilation; firmware and games are separate programs
executed by the modeled CPU. A working core is not a tested handheld board.

## Later implementation choices

| Route | Advantages | Costs and uncertainties |
|---|---|---|
| FPGA in final handheld | Reprogrammable, practical for correcting designs | Device selection, power, package/PCB complexity; modern physical silicon |
| Physical W65C02S plus FPGA peripherals | Tangible CPU bus and period-family hardware | Electrical adaptation, arbitration and timing; CPU behavior still needs validation |
| Manufactured ASIC peripherals | Fixed custom circuits and potential efficiency | Verification, physical design, process libraries, packaging, fabrication cost and revision risk |
| Discrete logic | Directly inspectable small logic blocks | Board size, component count and power make a full Lynx-class handheld challenging |

The final arrangement is undecided. Passing FPGA tests does not make an HDL
design fabrication-ready: clock/reset design, RAM implementation, constraints,
I/O cells, physical layout and test strategy need additional work. Vendor PLL,
RAM or other FPGA primitives require replacements or wrappers for ASIC use.

Tiny Tapeout can provide experience manufacturing a small audio/math/control
block. It is not an established route for the entire console: tile area, memory,
I/O count, packaging, shuttle-specific limits and costs must be checked. No ASIC
schedule or budget is committed.

For the owner's later request about ten manufactured graphics chips, see the
[ASIC cost estimate](asic-cost.md). Published fabrication minimums and ASIC
development expenses are separate from the roughly US$10 FPGA hardware target.

## Open preparation

Inventory the owner's MiSTer model, SDRAM and I/O board before hardware integration.
Choose a CPU only after behavioral and licensing review. Develop explicit bus and
memory budgets rather than allowing spare FPGA resources to dictate the console.
Game-image loading comes first; physical cartridge support remains a later scope.

## Standalone prototype budget

The owner rejected the US$275 ULX3S recommendation on 2026-10-29 and stated a
target of **around US$10**. Whether that covers the FPGA alone or the development
board remains to be clarified. Do not treat the ECP5 or its suggested board as
selected hardware. Continue software-first development and use the existing
MiSTer if needed; no new hardware purchase is required for current work.

Low-cost leads checked on the same date:

| Candidate | Listed board price, before shipping/tax | Assessment |
| --- | ---: | --- |
| Tang Nano 1K | US$5.90, listed in stock at Spotpear | Candidate for small independent effect circuits; not recommended as the complete console target |
| Tang Nano 9K | US$15.90, listed in stock at Spotpear | Above the stated target; candidate for fit/resource evaluation, not a selected purchase |

Sipeed lists 1,152 LUT4s for the Nano 1K and 8,640 for the Nano 9K. The 9K lists
468 Kbits of block RAM, 64 Mbits of PSRAM and 20 18×18 multipliers. Memory capacity
is not proof of graphics throughput. Neither our current prototype nor the full
enhanced design has been fitted to either device. Existing research capacities
such as 256 object descriptors/eight planes are provisional, not promises of fit
on a roughly US$10 device. Measure synthesis resources, timing and external-memory
traffic before recommending a part. A low-cost board listing also does not
establish the unit cost of that bare FPGA on a custom PCB.

## Bare-chip candidates and CPU sizing

Reviewed: 2026-10-30. The owner's latest request specifically asks for a bare
FPGA chip. Prices below are USD for that component, before shipping/tax, not
assembled board prices. No device is accepted or proven to fit the full console.

The **Lattice iCE40UP5K-SG48I** is the first near-US$10 graphics candidate to
evaluate. DigiKey lists US$11.11 for one or US$9.9448 each for 25 (US$248.62
total), but shows no stock when the product page is opened. Search snippets
reported different inventory; do not use those as proof of immediate availability.
The **ECP5 LFE5U-12F-6BG256C** is a larger comparison at US$16.78 for one,
also shown out of stock. These are checked candidates, not an exhaustive global
minimum-price claim. The cheap Gowin board prices above do not establish their
bare-chip prices.

Lattice lists 5,280 LUTs, 1,024 Kbits single-port RAM, 120 Kbits block RAM and
eight 16×16 multiply/accumulate blocks for UP5K. The SG48 package provides 39
I/Os. The X16 community's VERA FPGA project selects `iCE40UP5K-SG48I`; that is
evidence of a compact graphics implementation, not proof that our CPU, legacy
hardware and enhanced engines all fit together.

A Nix-managed Yosys `synth_ice40` estimate of our existing pinned, patched CPU
on 2026-10-30 produced:

| Primitive | Count |
| --- | ---: |
| `SB_LUT4` | 2,759 |
| `SB_CARRY` | 87 |
| Flip-flops, across four reset/enable types | 155 |

CPU LUT usage alone is about 52% of UP5K's LUT capacity, nominally leaving 2,521
LUTs before graphics, bus control and board integration. Carry/FF packing and
routing are not represented by simply subtracting LUT counts. This is synthesis
only: no placement, route, speed, power or complete-system fit has been measured.
It does not justify a 20 MHz CPU claim. The CPU was not changed for this probe.

Reproduce the estimate from the project root:

```sh
nix --extra-experimental-features 'nix-command flakes' build .#cpu-hdl --out-link build/cpu-hdl
mkdir -p build/fpga-sizing
nix --extra-experimental-features 'nix-command flakes' develop --command \
  yosys -Q -T -p 'read_verilog build/cpu-hdl/cpu.v; synth_ice40 -top core -json build/fpga-sizing/cpu-ice40.json; stat' \
  > build/fpga-sizing/cpu-ice40.log 2>&1
```

The provisional enhanced design's two 16-bit 320×204 surfaces alone occupy
261,120 bytes, more than UP5K's 128 KiB SPRAM plus 15 KiB block RAM. External
memory or a redesigned surface format is required, alongside sufficient I/O and
bandwidth. A physical external CPU can save FPGA logic but adds a CPU chip, bus
pins and board cost. Neither that route nor a reduced graphics profile is selected.

UP5K was the near-US$10 evaluation candidate, not a promise of the full graphics
specification. The subsequent pin/cost comparison selected ECP5-12F as the
development target. Full graphics resource usage, external-memory service and
timing still require implementation and acceptance before board release.

## Earlier ECP5 option — outside the owner's budget

Reviewed: 2026-10-29. Status: prior recommendation withdrawn following budget
clarification; retained as a technical comparison, not a purchase target.

The earlier option was the **Lattice ECP5 LFE5U-85F**, using the **ULX3S
85F** development board. Its listed FPGA is **LFE5U-85F-6BG381C**, in a 381-ball
BGA package. The intended console CPU is the HDL 65C02 inside the FPGA, alongside
our custom peripherals. A separate physical 65C02 is not required for this route.

Lattice lists approximately 84K LUTs, 3,744 Kbits of embedded block memory
(468 KiB) and 156 18×18 multipliers for the 85F. These give useful development
headroom for graphics caches, arithmetic and debugging, but full-system synthesis
and place-and-route must establish actual usage and timing. Our proposed 1 MiB
graphics store exceeds that block memory before other console storage, so plan
external RAM. The 45F is a possible later reduction after measuring the design;
do not select it solely from CPU size.

The ULX3S campaign lists 32 MB SDRAM, microSD, USB programming, digital video,
analog audio, 56 expansion GPIO and a 94×51 mm board. Its hardware repository
documents a **16-bit SDRAM interface**. The controller/arbiter must account for
refresh, row changes, turnaround, burst efficiency and scanout deadlines. This
board does not directly implement the provisional 32-bit graphics-memory path
in the [enhanced graphics proposal](../architecture/graphics-effects.md). Faster
physical memory transfers and buffering might provide the required useful rate;
that must be measured rather than inferred from capacity or memory-chip rating.

The board also lists an ESP32 for Wi-Fi/programming. Console execution and
rendering must reside in FPGA logic; USB programming permits a development path
without using that processor for console functions. The onboard optional OLED
connection is not the selected backlit game display. An external LCD still needs
pin, voltage, timing, connector and power design.

ECP5 has an open Yosys → nextpnr-ecp5 → Project Trellis bitstream flow. Extend
the project Nix configuration with pinned device tools and a programming utility
when implementing this target; they are not yet wired into the existing flake.
Retain the GHDL CPU translation and software tests, and add a board adapter for
PLLs, resets, memory and I/O. The current MiSTer bitstream cannot be loaded on an
ECP5 unchanged. Legacy timing and the 20 MHz enhanced CPU target each need
their own validation; neither follows from the FPGA's capacity.

Crowd Supply's 85F purchasing option listed **US$275 before shipping/tax, in
stock** when checked on 2026-10-29. Use that purchasing option, not the historical
price comparison table elsewhere on the campaign page. Recheck before ordering.
For a custom handheld PCB, evaluate the same FPGA family after the board proves
the circuit; BGA assembly, regulators, configuration flash, RAM, display, controls,
audio and power consumption remain board engineering tasks. Limit game-visible
memory and clocks explicitly even if the development board offers more resources.

## Sources

- [DigiKey UP5K bare-chip price and inventory](https://www.digikey.com/en/products/detail/lattice-semiconductor-corporation/ICE40UP5K-SG48I/7785190)
- [DigiKey ECP5-12F bare-chip price and inventory](https://www.digikey.com/en/products/detail/lattice-semiconductor-corporation/LFE5U-12F-6BG256C/9553915)
- [Lattice UltraPlus resources](https://www.latticesemi.com/Products/FPGAandCPLD/iCE40UltraPlus)
- [X16 VERA FPGA device selection](https://github.com/X16Community/vera-module/blob/main/fpga/vera_module.rdf)
- [Spotpear Tang Nano 1K board pricing](https://spotpear.com/shop/Sipeed-Lichee-Tang-Nano1K-FPGA-GW1NZ-1.html)
- [Spotpear Tang Nano 9K board pricing](https://spotpear.com/shop/Sipeed-Lichee-Tang-Nano-9K-FPGA-GW1NR-9-GOAI-Gowin-HDMI.html)
- [Sipeed Nano comparison and 9K resources](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html)
- [Lattice ECP5 device resources and package options](https://www.latticesemi.com/Products/FPGAandCPLD/ECP5)
- [ULX3S specifications and purchasing options](https://www.crowdsupply.com/radiona/ulx3s)
- [ULX3S hardware, SDRAM interface and schematics](https://github.com/emard/ulx3s)
- [nextpnr ECP5 support](https://github.com/YosysHQ/nextpnr)
- [Project Trellis](https://github.com/YosysHQ/prjtrellis)
- [MiSTer template and project organization](https://github.com/MiSTer-devel/Template_MiSTer)
- [Existing Lynx core and its hardware requirements](https://github.com/MiSTer-devel/AtariLynx_MiSTer)
- [Intel FPGA hardware guide](https://cdrdv2-public.intel.com/785442/oneapi-fpga-add-on_developer-guide_2024.0-785441-785442.pdf)
- [Tiny Tapeout FAQ](https://tinytapeout.com/faq/)
- [Tiny Tapeout memory considerations](https://www.tinytapeout.com/specs/memory/)
