# System control and boot ROM

Reviewed: **2026-11-17**. Status: **proposed control/firmware architecture**.
The current native game has its own startup code and boots directly. There is
no shared project boot monitor, launcher or system BIOS yet. The separate HDL
serial loader now passes its [service checks](../milestones/tang-board-services.md);
the real console cold/warm diagnostic now boots through that path. A shared system ROM remains future work.

## Three different images

The **FPGA bitstream** configures circuits. A **system ROM** contains CPU-executed
startup and management code. A **game image** contains the application. ROM may
be implemented as initialized FPGA memory or loaded from nonvolatile storage;
the storage and boot mapping are still to be designed.

{{chip-diagram:boot}}

## Hardware must establish a safe starting point

Clock lock, reset sequencing, memory initialization and continuous refresh cannot
depend on game code already running correctly. Control logic holds consumers in
a safe state and exposes readiness/error status. A boot CPU may use local ROM/RAM
while external memory initializes, or wait in reset until the hardware is ready;
that exact sequence is an open implementation choice.

## CPU-driven graphics diagnostic

{{chip-diagram:native-commands}}

The original [enhanced diagnostic ROM](../../firmware/enhanced-diagnostic.s) now
boots on the actual native R65C02 and uses the experimental
[$4400 MMIO interface](../architecture/native-graphics-mmio.md). It uploads source
bytes, submits scaled/fill commands, checks errors/tags and handles a completion
IRQ. Six cold/warm boots across three clock configurations pass. Commands and
held results cross CPU/graphics clocks through acknowledged mailboxes; local
register accesses complete without an external-memory CPU stall.

This is diagnostic startup code, not a shared monitor or launcher. The fixture
uses local ROM/RAM; a general CPU external-memory adapter and the complete board
clock/timing contract remain open. Frame ownership must be added before native
display can safely consume rendered surfaces.

| Layer | Responsibilities | Still open |
| --- | --- | --- |
| System controller HDL | Safe reset, readiness/status, accepted load transactions and controlled handoff | Register map, timeout policy, recovery/reset domains |
| Boot monitor ROM | Diagnostics, serial load commands, hardware status and a recovery screen | ROM size/map, routines, diagnostic result format |
| Later launcher | Game browser, storage access and persistent settings | Storage format, filesystem, update/recovery and UI |
| Game runtime | Initialize its working state and use the selected hardware ABI | Stable enhanced ABI and SDK startup conventions |

## First monitor scope

Start with deterministic startup diagnostics, serial image loading, clear hardware
status and a reliable reset/recovery path. Validate lengths, destinations,
integrity and complete-image commit before releasing a game. Settings such as
brightness and volume follow once the physical interfaces are selected.

A command received twice or a transfer interrupted by reset must not accidentally
launch a partial game. The loader needs explicit ownership of memory while the
game is held. BIOS images and original project diagnostics are different payloads
and must follow their respective core interfaces.

## Legacy handoff is its own design gate

The reused Lynx core has its original BIOS interface. Its original-visible memory
map and timing must be restored for compatibility mode. Our larger native monitor
cannot remain mapped over original game addresses and be assumed transparent.

Separate enhanced/legacy bitstreams are acceptable initially, but runtime
configuration switching, persistent load state and recovery are **not implemented**.
The diagram's mode decision identifies that boundary; it does not claim a working
multiboot mechanism. Host-controlled loading/reset is sufficient for first bench
bring-up. A self-contained launcher is a later integration goal.

## Acceptance

Test power-on/reset ordering, delayed memory readiness, corrupt/truncated image,
bad destination, reset mid-load, failed commit, repeated commands and game reset.
Prove that launch occurs once, only after all required writes complete. Recovery
must remain reachable when a game hangs. Test a mode change only after its exact
configuration/reset mechanism is specified.
