# 0002: MiSTer as the initial FPGA platform

Date: 2026-10-28
Status: Accepted

## Context

The owner already has a MiSTer and primarily has software experience. The first
major deliverable is a playable bench prototype, before custom PCB/enclosure work.

## Decision

Use the existing MiSTer to prototype custom digital hardware and games. Reuse a
CPU core while designing the project's peripheral hardware. Separate console
logic from the MiSTer framework. Existing Lynx implementations are comparison
references; this does not authorize or select wholesale adoption of one.

## Consequences

No additional FPGA board is needed to begin. The hardware's exact configuration,
including SDRAM expansion, still needs inventory before running the existing
Lynx core. Custom PCB work will require new display, power, controls, and electrical
integration. A physical CPU and ASIC fabrication remain later possibilities.

## References

- User selections and approved implementation plan, 2026-10-28.
- [MiSTer developer template](https://github.com/MiSTer-devel/Template_MiSTer)
- [Lynx FPGA reference](https://github.com/MiSTer-devel/AtariLynx_MiSTer)
- [FPGA and silicon research](../../research/fpga-and-custom-silicon.md)
