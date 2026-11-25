# 0009: Tang prototype with an internal Lynx CPU

Date: 2026-11-15
Status: Accepted

## Context

The owner selected Tang Nano 20K for investigation, asked us to establish whether
the MiSTer Lynx core fits, then authorized proceeding after the feasibility audit.
The owner subsequently accepted keeping the CPU inside the FPGA for this phase.
The core-only diagnostic, RAM-model comparison and registered route probe passed.
The real SDRAM, display, loader and clock interfaces are not integrated yet.

## Decision

Use **Tang Nano 20K** for the next standalone playable legacy-console prototype.
Keep the pinned upstream Lynx CPU, Suzy and Mikey inside the FPGA. Keep original
64 KiB work RAM on-chip and design SDRAM-backed cartridge/presentation storage.
Implement loading, controls, complete-frame presentation and board clock/output
adapters. Begin with host UART loading and HDMI bench output while handheld
panel qualification remains open.

Retain original Lynx execution timing and exact 2× logical pixel replication.
Keep the working native software game and its CPU/peripheral regressions.
Permit separate legacy and enhanced FPGA configurations initially; a combined
configuration has no established fit. Re-budget enhanced graphics for Tang.
The native 320×204 target, 60 fps workload goal and backlit-color requirement stay
in force. An external CPU remains a later design option.

## Consequences

This supersedes ADR 0008's **immediate standalone development-platform choice**.
Its ECP5/x16 resource and bandwidth tables remain historical engineering work;
they are not copied into a Tang performance promise. It does not discard the
desired effects or establish a final production PCB/BOM.

Core feasibility is not full-board acceptance. Require independent memory/loader
tests, complete integration, pin/clock review and full-system timing before
claiming a playable board build. Physical tests and owner-supplied game-image
checks remain separate gates. No hardware is purchased or programmed by this
decision. Software-first development under ADR 0004 continues.

## References

- [Current Tang integration architecture](../tang-prototype.md)
- [Audit, exact source pin and evidence](../../research/lynx-tang20k-compatibility.md)
- [Prior platform choice](0008-standalone-development-target.md)
- [Work plan and gates](../../roadmap.md)
