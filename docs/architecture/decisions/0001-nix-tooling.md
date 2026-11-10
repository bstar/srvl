# 0001: Project-local Nix tooling

Date: 2026-10-28
Status: Accepted

## Context

The host runs Arch Linux. The user requires project tools and dependencies in a
Nix shell, without installing them into Arch. This is dependency management, not
a request for additional interactive filesystem or network restrictions.

## Decision

Use a flake and committed lock file for x86_64 Linux. Keep open-source HDL and
65C02 tools in the default shell. Provide optional Quartus Lite 17.0.2.602 plus
Cyclone V support in a separate shell with narrowly scoped unfree allowance.
Do not edit global Nix configuration or install project tools into a user profile.

## Consequences

Tool versions follow the lock file. Updates are explicit and require checks.
Quartus's vendor archive and runtime are a separate dependency; its absence must
not block the default toolchain. Proprietary packaging remains unverified until
the exact archive can be built and tested. Nix's store and downloads use host disk
space; a dev shell does not provide security isolation.

## References

- User requirements and approved implementation plan, 2026-10-28.
- [Nix development shells](https://nix.dev/manual/nix/2.20/command-ref/new-cli/nix3-develop)
- [Tooling research](../../research/tooling.md)
