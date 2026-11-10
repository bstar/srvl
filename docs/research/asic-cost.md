# Graphics ASIC prototype cost estimate

Reviewed: 2026-10-29. Status: preliminary planning estimate, not a quotation,
fabrication commitment, proven area fit or guarantee of functional samples.

The owner asked for the cost of producing ten graphics chips. Assume ten copies
of one design integrating the proposed graphics engines, external framebuffer/
asset RAM, a fabrication-ready layout prepared by this project, and no paid
engineering labor. Ten sets of several separately manufactured chips would have
additional design and fabrication costs. No area or pin-count result exists yet.

## Published manufacturing anchors

wafer.space Run 3 standard pricing lists quarter/half/full slots at
US$3,000/5,000/8,000, each delivering 1,000 dies. Its chip-on-board assembly add-on
is US$1,500 per slot. Thus published fabrication-plus-assembly totals are
US$4,500/6,500/9,500 respectively, before other project expenses. Chip-on-board
means dies bonded to little PCBs, not conventional standalone QFN packages.
September's early-bird prices are not used here.

The default quarter/half/full pad rings leave approximately 1.73/4.46–5.02/12.92
mm² of core area and 48/56/56 I/O pads. Whether our design fits any option, meets
timing, and supports the required external-memory interface remains unverified.
A custom pad ring changes available area/I/O and packaging requirements.

ChipFoundry's chipIgnite FAQ lists US$14,950 including fabrication and 100
QFN-packaged parts, with ten parts mounted on daughtercards and an evaluation
board. Its permitted design area and I/O differ from wafer.space. This is a
pricing comparison, not a validated implementation option for our graphics bus.

## Project planning estimate

Allow **US$10,000–20,000 for a first run** as a provisional cash envelope,
excluding engineering labor. This is an inference from published manufacturing
options plus allowance for prototype integration and test, not a vendor offer.
An implementation that fits a half/full wafer.space slot could have a lower
fabrication-plus-assembly bill of US$6,500–9,500; a small isolated effect circuit
could be smaller still. Neither possibility establishes that the complete
graphics proposal fits or that ten samples will work correctly.

Additional expenses include project test PCBs, external RAM, assembly/integration,
test fixtures, shipping/tax and any paid IP/tools/review. Reserve a separate
budget for another fabrication run if silicon requires correction. No guaranteed
ceiling or complete paid-development estimate can be given before sizing,
physical implementation, package selection and a test plan.

Buying only ten useful samples does not divide a minimum slot price by 100 or
1,000 at checkout. If only ten chips are used, a US$10,000–20,000 first run
effectively costs US$1,000–2,000 per used chip. This differs from the unit price
at full lot utilization or production volumes. A US$10 total manufacturing
budget cannot fund this route; existing software/MiSTer work needs no purchase.

## Sources

- [wafer.space pricing](https://wafer.space/price)
- [Run 3 fabrication, assembly and slot specifications](https://www.crowdsupply.com/wafer-space/gf180mcu-run-3/)
- [chipIgnite manufacturing inclusions and pricing](https://chipfoundry.io/faqs)
- [Graphics architecture proposal](../architecture/graphics-effects.md)
- [FPGA budget and development approach](fpga-and-custom-silicon.md)
