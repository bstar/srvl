# Hardware choices and boundaries

Reviewed: **2026-11-15**. The immediate target is an existing Tang Nano 20K board.
The later handheld is a separate electronics and mechanical design. This page
records development choices; it is not a shopping list or released BOM.

## First prototype

| Function | Current choice | Why and remaining work |
| --- | --- | --- |
| FPGA board | Tang Nano 20K; GW2AR-LV18QN88C8/I7 | Audited baseline Lynx logic fits. Board integration, complete timing and physical acceptance remain ahead |
| CPU | Soft CPU inside the FPGA | Avoid external address/data/control wiring and bus timing for this phase; retain the upstream CPU in Lynx mode |
| Fast work RAM | FPGA block RAM | Preserve original 64 KiB Lynx RAM behavior; 33 of 46 blocks are used in the registered core probe |
| External working storage | Board's packaged 8 MiB ×32 SDRAM | Enough capacity for cartridge data and RGB presentation storage; needs a real controller and measured contention handling |
| Configuration storage | Existing board flash | Configuration/load flow remains to be integrated; a finished game's storage format is not chosen |
| Bench display | HDMI/DVI bring-up | Allows a visible console before committing to a handheld panel; includes serializers and a separate video clock domain |
| Loading/bench controls | Existing USB debugger UART bridge | Reduces initial external hardware; protocol, host tool, button hold/release and reset sequencing need tests |
| Clock references | Investigate onboard programmable generator | Exact legacy timing matters; PLL/phase legality and physical configuration must be verified |
| Sound | Actual Mikey stereo through fixed-point filtering, coherent transfer and I²S | Software audio/video integration passes; final filter response, amplification, speaker/headphone circuit and physical quality remain open |

The Tang audit's I/O availability is a die-model figure, not a count of accessible
header pins. Final connectors, GPIO allocation, bank voltage rules and dedicated
SDRAM/HDMI assignments require a checked board pin map. Do not add an external
CPU or wide peripheral bus on the assumption that the reported die I/O is free.

## What belongs inside the FPGA

Keep CPU execution, address decoding, graphics engines, raster timing, audio
generation, interrupt/timer behavior, memory scheduling and control registers in
logic we can simulate and constrain. These are the parts that define the machine.
Using the FPGA as custom logic does not require an ARM/Linux processor to render
or emulate games.

For compatibility mode, much of that logic is the reused upstream Lynx design.
For the enhanced configuration, the blitter, tile planes and scanout are project work, as the planned
flat-triangle engine will be. See [component provenance](architecture/provenance.md).

## What ordinary external parts should do

| External function | Good reason to use an existing part | Decision still needed |
| --- | --- | --- |
| Bulk memory / nonvolatile storage | Store bits efficiently without consuming logic as emulated memory | Final capacity, organization, loading format and memory layout |
| Audio conversion / amplification | Drive an analog load; avoid spending logic on functions an inexpensive mixed-signal part performs | Stereo DAC/transport, amplifier, speaker, headphones and noise/power budget |
| Power regulation / charging | Generate and sequence required rails, charge a battery and drive a backlight | Battery chemistry/capacity, rail currents, charger/protection and backlight topology |
| Clock source / reset support | Supply legal stable clocks and predictable reset behavior | Exact frequencies, tolerances, startup and routing |
| Physical controls / connectors | Provide real buttons, storage and programming connections | Layout, debounce, available pins and connector durability |

There is no demonstrated benefit yet to adding a physical 65C02, a retro sound
chip or a general-purpose I/O chip to the first Tang prototype. A later board can
revisit those options using actual pin, cost, resource and timing measurements.

## Display is a board-design dependency

The required screen is color with a **backlight**. The leading research direction
is a transflective TFT, with ordinary backlit IPS as a fallback. No part is
qualified. A 60 Hz input specification alone does not prove clean motion;
optical response, sample behavior and temperature also matter.

The native canvas is **320 × 204**. Legacy 160 × 102 pixels fill it at **exact
2×, with no added borders**. The owner confirmed this on 2026-11-17. The final
panel/interface must preserve the complete image and border-free visible area.
Common 320 × 240 and 640 × 480 panels have a different aspect ratio; their
letterboxed layouts are not accepted final choices. Resolve the active-area
mapping before qualification or enclosure design. Portrait panels also require
rotation-aware scanout and a different memory schedule.

See the [display research](research/display-selection.md) before interpreting a
historical candidate as available stock. Confirm panel voltage, flex position,
connector clearance, backlight current/boost voltage, motion and lifecycle before
freezing schematic or enclosure dimensions.

## Cost and manufacture

The owner rejected an expensive FPGA development board and suggested roughly
US$10 during early exploration. A complete BOM ceiling is still open. Earlier
bare-chip prices exclude memory, power, PCB, assembly, display, connectors,
controls and battery. They are dated observations, not current quotations.

The first version uses an existing FPGA development board. A custom carrier or
fully custom board comes after interfaces and power are known. A packaged FPGA
is still a commercial chip configured with our logic; manufacturing a custom
ASIC is a distinct, later project with design-rule, packaging, test and fixed-cost
requirements. An order of ten ASICs does not amortize those fixed costs well.

No new hardware has been ordered or programmed by this documentation work.
See [the tradeoff register](tradeoffs.md) and
[historical FPGA/ASIC research](research/fpga-and-custom-silicon.md) for context.
