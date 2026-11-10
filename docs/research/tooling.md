# Nix and Quartus tooling

Reviewed: 2026-10-28. Status: default tools, prototype simulation, Quartus
17.0.2 Cyclone V smoke compile, and full MiSTer build validated. Device acceptance
is deferred at the owner's request under
[ADR 0004](../architecture/decisions/0004-software-first-validation.md).

## Environment

Standalone update, 2026-10-30: `nix develop .#ecp5` provides the locked Nixpkgs
nextpnr/Trellis/programming tools alongside the existing HDL tools. The
`standalone-cpu-sizing` output maps the pinned CPU to ECP5 and validates the
[platform allocation/traffic budget](../architecture/standalone-platform.md).
This is independent of the Quartus/MiSTer bring-up build and does not program
hardware. Full graphics synthesis and physical timing acceptance remain ahead.

The development host is x86_64 Arch Linux with Nix 2.35.2. The repository uses a
locked Nixpkgs input and project shells; no Arch/AUR packages are needed. Pass
`--extra-experimental-features 'nix-command flakes'` if these are not enabled in
the invoking environment. No host configuration was changed.

The default shell includes HDL simulation and generic synthesis, waveform viewing,
65C02 compilation, Python, Make, Git and native C/C++ tools. Its checks exercise
Verilog in Icarus/Verilator, VHDL in GHDL, Yosys synthesis, cc65/ca65 object creation,
and local documentation links/ADR metadata.

The shell does not implement an interactive access-control sandbox. Dependencies
live in the Nix store and checks use Nix derivations. Host graphics services and
device permissions remain host concerns. No USB rules or JTAG daemon are installed.

## Quartus version and input

MiSTer's template recommends Quartus 17.0.x, preferably 17.0.2. The project pins
**Lite 17.0.2 Build 602** with **Cyclone V** data. The current Nixpkgs Quartus
package is a substantially newer release, so it cannot be used unchanged.

The optional local expression accepts the official combined Linux archive:

```text
Filename: Quartus-lite-17.0.2.602-linux.tar
Vendor-published SHA-1: 02aebab728d54e3ca8660d2646fdf93bc669b0ac
Vendor-listed size: approximately 8.2 GB
```

The SHA-1 is the publisher's integrity pin, not a locally computed SHA-256 or a
claim that SHA-1 provides modern collision resistance. Keep the vendor origin and
filename intact. Do not import an HTML login/download page as the archive.

Expected archive contents used by the packaging:

```text
QuartusLiteSetup-17.0.0.595-linux.run
cyclonev-17.0.0.595.qdz
QuartusSetup-17.0.2.602-linux.run
```

The expression isolates the base Lite installer and Cyclone V device data, then
applies Update 2. Other device families and ModelSim are not intentionally
installed. The archive layout and static installer format were inspected. These
installers do not support the newer `--accept_eula` option; they run in unattended
mode. Review the vendor terms before building. Binaries are installed in the Nix
store, not `/opt` or Arch.

## Observed upstream blocker and recovery

On 2026-10-28 the legacy MiSTer-linked `downloads.intel.com` archive URL redirected
to Intel's download-center HTML. Direct `download.altera.com` installer URLs
returned HTTP 403. The current vendor download page routes through its customer
login service. No authenticated account was used and no unofficial mirror was
substituted. Subsequently, the official archive URL returned the complete archive
when requested with `User-Agent: Alterabot/1.0`; Nix fetched it and verified the
published SHA-1 successfully. This client header also appears in current Nixpkgs'
Quartus downloader. The initial missing-archive blocker is resolved.

The optional package now uses `fetchurl` with that header. If the vendor becomes
unreachable again, the same exact archive can be imported after obtaining it from
the vendor:

```sh
sha1sum /absolute/path/Quartus-lite-17.0.2.602-linux.tar
# Expected: 02aebab728d54e3ca8660d2646fdf93bc669b0ac
nix-store --add-fixed sha1 /absolute/path/Quartus-lite-17.0.2.602-linux.tar
nix --extra-experimental-features 'nix-command flakes' develop .#quartus
bash scripts/check-quartus.sh
```

The hash-enforced Nix input rejects different archive contents. The runtime uses
Nix's FHS environment support and pinned libraries to run legacy binaries on the
host. The static installer hung during shutdown after recording completion.
The packaging requires both explicit completion markers before terminating that
hang; early failures and timeouts without completion still fail the build. Both
the base and Update 2 installations completed, and the installed version executed
and compiled a Cyclone V design. GUI behavior remains untested.

## Validation record

- Default toolchain: compiled and simulated Verilog with Icarus and Verilator,
  analyzed/elaborated/ran VHDL with GHDL, synthesized with Yosys, compiled/assembled
  a 65C02 object with cc65/ca65.
- Default flake checks also verify repository-local Markdown links and ADR fields.
- Prototype RTL: Verilator checks raster timing, exact doubled pixels, input,
  clamps, resets and tone generation; the full held-input traversal also passed.
  The normal check exports a PNG from actual simulated pixel output.
- Quartus: exact vendor archive downloaded and hash verified. Version reports
  `17.0.2 Build 602`; analysis, fitting, assembly, and timing analysis of a minimal
  Cyclone V register design passed. The smoke design has no board pin assignments
  and is never loaded on hardware.
- Full MiSTer prototype: synthesis, fitting, assembly/RBF generation, and fitted
  clock/setup/hold checks passed. Worst setup slack is +0.246 ns and hold slack
  +0.247 ns in the slow 1100 mV/100 °C model. The framework retains warnings and
  incomplete external-I/O constraints; see the
  [acceptance record](../milestones/first-mister-prototype.md) for scope, hash,
  resource use, and limitations. Other timing corners remain unverified.
- Bitstream reproducibility: two independent clean Nix/Quartus builds on this
  host produced byte-identical 2,424,312-byte RBFs. The second build also passed
  its timing checks with the same slack. Reports have timestamps and are not
  byte-identical; cross-host reproducibility remains untested.
- CPU-driven software prototype: a pinned, locally corrected R65C02 is translated
  by GHDL and tested with Verilator. Its independent functional ROM suites pass.
  The Nix-managed SDL simulator runs an original ROM against custom tile/sprite,
  audio, and input hardware. Peripheral, gameplay, and host-event checks pass;
  flat and hierarchical simulation yield identical images/audio. See the
  [playable prototype record](../milestones/playable-software-prototype.md) and
  [software workflow](../../sim/README.md).
- An attached MiSTer SD card was identified, the RBF added under `_Other/` with a
  distinct filename, its checksum verified, and the card unmounted. FPGA loading,
  graphical waveform viewing, and USB/JTAG programming have not been tested.
  The running device's image, controls, and sound remain unverified.

## Sources

- [Nix development shells](https://nix.dev/manual/nix/2.20/command-ref/new-cli/nix3-develop)
- [MiSTer template version guidance](https://github.com/MiSTer-devel/Template_MiSTer)
- [MiSTer historical download links](https://mister-devel.github.io/MkDocs_MiSTer/developer/links/)
- [Altera 17.0 Linux downloads and Update 2 checksum](https://www.altera.com/downloads/fpga-development-tools/quartus-prime-lite-edition-design-software-version-17-0-linux)
- [Nixpkgs Quartus packaging reference](https://github.com/NixOS/nixpkgs/tree/31ecbaca1bdefa45dffc409f0250bd8039ea0010/pkgs/by-name/qu/quartus-prime-lite)
