# First MiSTer prototype

This is a display/input/audio bring-up circuit, not a CPU-based console or game.
It generates its pattern directly in logic. No Lynx boot ROM, games, or external
SDRAM expansion are needed. The target is MiSTer's DE10-Nano/Cyclone V framework;
other FPGA boards are not supported by these pin assignments.

Simulation and the full Quartus build pass. Physical testing is deferred at the
owner's request and does not block software development; see
[ADR 0004](../docs/architecture/decisions/0004-software-first-validation.md) and the
[acceptance record](../docs/milestones/first-mister-prototype.md) for the artifact
hash, fitted timing, resource use, and inherited constraint limitations.

## Behavior

- 50.4 MHz system clock, 25.2 MHz pixel enable, 800 × 525 total raster: 60 Hz.
- Standard 640 × 480 visible raster. A 320 × 204 logical image is doubled exactly
  in both directions, with 36 black lines above and below the 640 × 408 image.
- Eight color bars, one-logical-pixel checkerboard, white extent border, and a
  32-bit binary frame indicator across the first 256 logical pixels near the top.
- Directional input moves a 16 × 16 marker by one logical pixel per frame, clamped
  to the image. Opposing directions cancel. Button B changes its color while held.
- Button A plays a 440 Hz square wave in both channels at modest digital amplitude.
  The OSD can enable a continuous tone or a 16-pixel grid.
- User reset restores state/mutes sound without stopping video sync. LED_USER
  follows frame-counter bit 5. The PLL startup reset releases synchronously.

Controller bit mapping follows MiSTer's standard Right/Left/Down/Up/A/B positions.
Define the core's buttons using the OSD if the gamepad is not already mapped.
The full 4:3 raster includes letterboxing; HDMI aspect is therefore 4:3, preserving
square pixels within the narrower game image. This does not change the console's
agreed logical resolution.

## Build and simulate

Run from the repository root. Add `--extra-experimental-features 'nix-command flakes'`
after `nix` if needed on your host.

```sh
nix flake check -L
nix build .#checks.x86_64-linux.prototype -o build/prototype-simulation -L
nix build .#simulation-full -o build/prototype-simulation-full -L
```

Normal software work needs only the checks and simulation targets. Both targets
export `preview.png`, `compile.log`, and `simulation.log`. The image comes from
the RTL's pixel output.
Tests check sync/blanking, image size, 2× replication, movement, opposing controls,
clamps, reset, and audio edge intervals. Normal checks use directed boundary-state
injection to keep them fast; `simulation-full` runs the testbench's `+long` mode
and also traverses the full range through held controller input. This takes a few
minutes and requires no MiSTer, Quartus, or vendor binaries.
Simulation checks the circuit at clock edges;
it does not prove the physical PLL, HDMI, HPS controller transport, or analog audio.

Quartus is needed only when producing an FPGA bitstream:

```sh
nix build .#prototype -o build/mister -L
```

The hardware build pins the upstream template in `flake.lock`, stages it in a
temporary build directory, and leaves `sys/` unchanged. It replaces the template's
demo, changes its PLL from 20 to 50.4 MHz, bounds Quartus to four workers, and fixes
the displayed build date. Reports and the `.rbf` are exported under `build/mister`.
Two clean builds on the development host produced byte-for-byte identical RBFs;
see the acceptance record for the comparison. Compiler reports contain timestamps,
and builds on different hosts have not been compared.
The adapter preserves the template's `pll` instance name: the framework's clock
constraints depend on that hierarchy. The build checks the fitted 50.4 MHz clock
and rejects negative setup or hold slack under the loaded template constraints.
Detailed paths and clock reports are included with the RBF.

## Loading on hardware

With SSH key access and the device's hostname/IP:

```sh
nix develop
python scripts/deploy-mister.py --host root@MISTER_IP --load
```

The script copies a content-addressed RBF to `/tmp`, verifies its checksum, and
optionally sends `load_core` to `/dev/MiSTer_cmd`. It does not overwrite the menu,
installed cores, or SD-card configuration. Loading switches the running core;
return to MiSTer's menu normally afterward. For a permanent manual installation,
copy `Chipbuilder.rbf` to a new file under `_Other/` and select it in the menu.

## Hardware acceptance

Deferred under ADR 0004. These checks remain required before claiming the core
works on a physical MiSTer; they are not a gate for the current software milestone.

1. Confirm an intact border, eight color bars, exact checkerboard pixels and black
   bands. Check the monitor/scaler reports approximately 60 Hz; input timing is
   60 Hz but output also depends on MiSTer's video configuration.
2. Move the marker in all directions and to the limits; hold B to change color.
3. Hold A and hear the same tone in both channels. Release to mute; test continuous
   tone and grid in the OSD. Verify reset restores the marker while sync remains.
4. Record the MiSTer model/Main version, display connection, controller, RBF hash,
   and observed result in the milestone record.

Do not record hardware acceptance from a successful compile or simulation alone.
Network reachability or a successful `load_core` write alone is also insufficient.

## Source and licenses

The adapter derives from MiSTer's GPL-2.0-or-later template. New prototype RTL is
marked GPL-2.0-or-later. The pinned template includes its license, retained in the
hardware build output. Vendor-generated Altera PLL source has additional vendor
notices and remains confined to the MiSTer adapter; it is not an ASIC implementation.
See the [upstream template](https://github.com/MiSTer-devel/Template_MiSTer) and
[MiSTer load command usage](https://github.com/MiSTer-devel/SGIIndy_MiSTer/blob/master/docs/reference/deploy-and-debug.md).
