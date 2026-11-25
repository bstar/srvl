# Project documentation

Start with the [current project summary](project-status.md),
[work plan](roadmap.md), [tradeoffs](tradeoffs.md) and
[Tang architecture](architecture/tang-prototype.md). For a searchable HTML view of
all project documents, run `nix run .#docs` and open <http://127.0.0.1:8787>.
See the [documentation workflow](documentation.md) for rebuilding and upkeep.

Research reviewed on **2026-10-28**. Dates indicate when sources were examined,
not when the underlying products or documents were first published. Availability
and manufacturer lifecycle statements must be rechecked before procurement.

## Research

- [Lynx hardware and compatibility](research/lynx-hardware.md)
- [Lynx MiSTer core compatibility and Tang Nano 20K audit](research/lynx-tang20k-compatibility.md)
- [CPU selection, corrections, and functional tests](research/cpu-selection.md)
- [Display selection](research/display-selection.md)
- [Commander X16 inspiration](research/commander-x16.md)
- [FPGA development and custom silicon](research/fpga-and-custom-silicon.md)
- [Graphics ASIC prototype cost estimate](research/asic-cost.md)
- [Nix and Quartus tooling](research/tooling.md)

## Architecture

- [Chip design handbook with inspectable diagrams](chip-design/overview.md)
- [System control and boot ROM design](chip-design/system.md)
- [Clock, reset and display-output design](chip-design/board-output.md)
- [Current hardware choices and integration boundaries](hardware.md)
- [Current Tang prototype](architecture/tang-prototype.md)
- [Current enhanced graphics target and its limits](architecture/enhanced-target.md)
- [Original versus reused components](architecture/provenance.md)
- [System architecture: both configurations, clocks, memory and the path of a frame](architecture/overview.md)
- [Selected standalone development platform and hardware tradeoffs](architecture/standalone-platform.md)
- [Decision-record index and conventions](architecture/decisions/README.md)
- [Prototype simulation, controls, and optional MiSTer build](../hardware/README.md)
- [First prototype acceptance record](milestones/first-mister-prototype.md)
- [CPU-driven software architecture and memory map](architecture/software-prototype.md)
- [Enhanced graphics effects proposal and bandwidth targets](architecture/graphics-effects.md)
- [Physical retro CPU with FPGA graphics](architecture/hybrid-hardware.md)
- [Playable software prototype milestone](milestones/playable-software-prototype.md)
- [Tang board-service and serial-loading acceptance](milestones/tang-board-services.md)

Research notes preserve evidence, alternatives, and uncertainty. An accepted ADR
records a project decision, not a claim that the hardware already works. Revise
research as evidence improves; preserve decision history by superseding ADRs.
