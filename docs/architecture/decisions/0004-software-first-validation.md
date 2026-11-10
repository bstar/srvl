# 0004: Software-first prototype validation

Date: 2026-10-28
Status: Accepted

## Context

The prototype has a reproducible Nix-managed Quartus build and portable RTL
simulation. Physical MiSTer verification was blocking the first milestone.
The owner explicitly requested skipping that verification for now and continuing
with software tooling.

## Decision

Accept the first prototype milestone using software evidence: HDL simulation of
video, controls, and audio, generated pixel previews, and the already completed
Quartus compile/timing and bitstream reproducibility checks. Defer physical
MiSTer acceptance to a later hardware session. Neither MiSTer availability nor
SSH credentials gate ongoing development.

Use Nix-managed Verilator regression tests as the normal development loop. Keep
the short checks fast and expose the full held-input traversal separately.
MiSTer remains the initial FPGA platform selected in ADR 0002.

## Consequences

CPU, memory-map, peripheral, and original-ROM development can proceed in
simulation. Preserve the hardware checklist and MiSTer adapter for later use.
Software acceptance does not establish physical PLL/HDMI operation, controller
transport, electrical timing, or audible output. Claims of running successfully
on MiSTer require actual device evidence.

## References

- Owner's request to skip MiSTer verification and use software tooling, 2026-10-28.
- [MiSTer platform decision](0002-mister-prototyping.md)
- [Prototype acceptance record](../../milestones/first-mister-prototype.md)
- [Software workflow and tests](../../../hardware/README.md)
