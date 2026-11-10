# First MiSTer prototype acceptance record

Date: 2026-10-28.
Status: software acceptance complete; physical MiSTer acceptance deferred by owner.

## Scope

A 320 × 204 pattern, exact 2× display scaling within a 640 × 480 raster,
controller-driven marker, and 440 Hz tone. Software acceptance verifies the
portable RTL behavior and build pipeline before adding a CPU, memory bus,
graphics registers, or Lynx compatibility.
See [build instructions and controls](../../hardware/README.md).

The owner requested software-only validation for now. Under
[ADR 0004](../architecture/decisions/0004-software-first-validation.md), physical
testing is deferred and no longer blocks this milestone or ongoing development.

## Completed checks

- Nix-managed HDL/65C02 toolchain and documentation checks passed.
- Verilator checked raster timing, blanking, doubled pixels, controller movement,
  opposing directions, clamps, reset, and tone levels/edge intervals. A separate
  long run traversed the full movement range using held input. The Nix target
  `simulation-full` passed with the current testbench in approximately 166 seconds;
  `build/prototype-simulation-full/` contains its preview and compile/test logs.
- The simulation produced a 640 × 480 PNG from the circuit's actual pixel output.
- The official Quartus archive passed its published checksum. The installed
  `quartus_sh` reports Lite 17.0.2 Build 602. A minimal Cyclone V design completed
  synthesis, fitting, assembly, and timing analysis without errors.

## Hardware build

`nix build .#prototype -o build/mister -L` completed successfully using Quartus
Lite 17.0.2 Build 602 and template revision
`5dda37366d02b04b8448da7b322235c1831af811` from `flake.lock`.

| Build evidence | Result |
| --- | --- |
| Target | DE10-Nano, Cyclone V 5CSEBA6U23I7 |
| Output | `build/mister/Chipbuilder.rbf`, 2,424,312 bytes |
| Fitted demo clock | 50.4 MHz, 19.841 ns period |
| Worst setup slack | +0.246 ns |
| Worst hold slack | +0.247 ns |
| Timing model checked | Slow 1100 mV, 100 °C |
| ALMs, including MiSTer framework | 7,235 / 41,910 (17%) |
| Registers, including framework | 11,221 |
| Block memory bits, including framework | 384,257 / 5,662,720 (7%) |
| DSP blocks, including framework | 33 / 112 (29%) |
| PLLs, including framework | 3 / 6 |

RBF SHA-256:

```text
9e0f461b14599b1d76c050d8f16e25cf01a26d54389465a0e58f8fd489865543
```

The output contains `sha256.txt` and `reports/`, including full Quartus reports,
clock definitions, and detailed setup/hold paths. The small demo's cost must not
be inferred from whole-build resource totals: these include HDMI/scaler, audio,
HPS interfaces, and other MiSTer infrastructure.

The full compile reports zero errors and 53 warnings. Reviewed warning groups
include vendor PLL/unused ports, dual-clock RAM semantics in the framework,
unused peripherals, Lite-only LogicLock limitations, inherited I/O electrical
defaults, and constraints for signals optimized away. No critical warning was
reported. The template also leaves 4 input ports and 50 output ports unconstrained
or partially constrained, including HDMI pins. Thus the positive slack covers
timed paths under the template constraints, not complete board-interface signoff.
Other process/voltage/temperature corners have not been independently verified.
Physical acceptance remains necessary before claiming successful operation on
the actual device, and is deferred from the current software milestone.

## Reproducibility

A second clean Nix build on the same host completed independently, including
synthesis, fitting, assembly, and timing checks. It used the same pinned inputs
and builder with a distinct derivation name to avoid reusing the first output:

```sh
nix build --impure --expr \
  'let project = builtins.getFlake (toString ./.); in project.packages.x86_64-linux.prototype.overrideAttrs (_: { name = "chipbuilder-mister-reproducibility"; })' \
  -o build/mister-repro -L
```

For another clean run, choose an unused derivation name; an existing name may
return the cached output. `--impure` here permits resolving the current workspace;
the inputs and Quartus build dependencies remain pinned and Nix-managed.

The second build's RBF was compared directly with the first as byte strings,
not just by size or filename. Both files contain 2,424,312 bytes and are identical,
with the SHA-256 above. Both fitted timing checks give setup +0.246 ns and hold
+0.247 ns. The comparison is recorded locally in `build/reproducibility.json`.
`build/mister-repro/reports/` retains the second run's compiler evidence.

This verifies bitstream reproducibility for these two builds on this host.
Reports include timestamps and are not byte-identical artifacts. Builds across
different hosts and CPU architectures have not been compared.

## Deferred device acceptance

The owner has a MiSTer. No working SSH destination or attached USB-Blaster was
available during implementation. A subsequently checked USB SD card labeled
`MiSTer_Data` had the expected `MiSTer`, `menu.rbf`, `linux/`, and `_Other/` layout.
It was inspected read-only, then mounted writable to add the prototype as a new
file without replacing existing cores:

```text
_Other/Chipbuilder_9e0f461b1459.rbf
```

The copied file's SHA-256 matched the accepted build above. The file was flushed
and the card successfully unmounted. It is ready to move back to the MiSTer and
select in the menu. No core has been loaded on or physically observed from the
running device. Physical observations and remote access are deferred; they are
not currently required from the owner.

| Evidence | Result |
| --- | --- |
| MiSTer board/Main version | Deferred; unverified |
| SD-card copy of the accepted RBF | Checksum verified; card unmounted |
| RBF SHA-256 loaded | Deferred; unverified |
| Display and HDMI/analog connection | Deferred; unverified |
| Border, bars, checkerboard, aspect, refresh | Deferred; unverified |
| Controller model and all movement directions/clamps | Deferred; unverified |
| Button B marker color | Deferred; unverified |
| Button A stereo tone and release-to-mute | Deferred; unverified |
| OSD continuous tone, grid, and reset | Deferred; unverified |

The [deployment helper](../../scripts/deploy-mister.py) can copy a verified RBF
to MiSTer's RAM filesystem and load it using existing SSH access. A successful
transfer or load command must be followed by the observations above.

## Next milestone

Choose and license-review a 65C02-compatible CPU core, define a small prototype
memory map, and run an original ROM that writes display state and reads controls.
That is a separate milestone; this circuit contains no CPU or commercial ROM.
