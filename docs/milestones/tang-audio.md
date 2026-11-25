# Stereo audio acceptance

Date: **2026-11-17**. Status: **audio component and actual-console audiovisual
simulation pass**. This establishes signed filtering, coherent stereo transfer
and pin-decoded I²S. Physical audio, analog-filter fidelity, complete board
clocks/pins/timing and video serialization remain open.

## Reproduce

```sh
nix --extra-experimental-features 'nix-command flakes' build .#audio-output-check -o build/audio-output-check -L
nix --extra-experimental-features 'nix-command flakes' build .#lynx-tang-av-check -o build/lynx-tang-av-check -L
nix --extra-experimental-features 'nix-command flakes' build .#tang-av-sizing -o build/tang-av-sizing -L
```

Artifacts retain logs, exact source links, tool versions, mapping and evidence.
The console artifact also contains `lynx-stereo.wav`: 48 kHz, signed PCM16,
two channels, decoded from the simulated I²S pins. No Atari BIOS, commercial
game image or attached board is needed. See the
[dated snapshot](../research/evidence/tang-audio-2026-11-17.json).

## Listen to the observed diagnostic

<audio controls preload="none" src="../audio/lynx-stereo.wav">Download the stereo capture below.</audio>

[Download the pin-decoded stereo WAV](../audio/lynx-stereo.wav).

The original diagnostic programs separate Mikey timers and feedback taps for
approximately 2 kHz left and 2.5 kHz right square waves. A halves their volume.
This is a diagnostic tone, not game music. The capture includes loading/stop
silence and cold/warm operation. Playback is user-controlled.

## Component coverage

The component check passes **2,500 decoded stereo frames** across **3,334,192
system clocks**. A separate mathematical model checks every filtered system-clock
value and every captured pair. A decoder observing only BCLK, WS and SD checks
bit order, channel order, the one-bit delay, 32-bit slots and zero padding.

Directed cases cover both full-scale signs, reversal, unequal DC values, random
independent channels, disable/reenable, stopped system clock while audio continues,
underrun silence/recovery and joint reset. Two queued buffers are explicitly
discarded during reset. A second audio-clock ratio changes crossing phase.

Independent sinusoidal-response checks measure −0.174516 dB at 1 kHz,
−33.3406 dB at 24 kHz and −42.1845 dB at 32 kHz. They agree with the documented
four-pole transfer function. The first run exposed an unsigned-expression shift
in the negative arithmetic path; explicit signed intermediate steps corrected it,
and full-scale reversal plus the independent model now pass.

The filter/transmitter/mailbox component maps to **391 registers**, **122 LUT1–4
cells** and **596 ALU cells**, with **no multipliers, block RAM or unintended
latches**. Mapped primitive counts are not post-route logic-site counts.

## Actual console and simultaneous video

The combined check uses the real UART/CRC loader, original CPU/RAM/math/cart
diagnostic, SDRAM arbitration, exact-2× RGB path and Mikey sound generators.
The 298-byte BS93 image initializes channel masks and independent audio timers.
The host only uploads the image and held button states.

The run decodes **26,151 stereo frames**, matching the actual core's independently
filtered snapshots. **Six** input phases verify tone polarity, separate channel
frequencies and volume, including changes after warm reload. Stop is followed by
complete silent frames; no transport underrun occurs. Simultaneously, **23**
complete 320×204 canvases match complete emitted Lynx frames with exact 2× pixels.
The run covers **34,869,130 master clocks**, twelve cartridge requests/ACKs, two
external cartridge-cache misses and **69,547 SDRAM refreshes**.

These are original diagnostics, not a compatibility result for commercial games.
The earlier [video-only acceptance](tang-video.md) remains a separate test.

## Clock and reset contract

The model runs independent 64 MHz system, 25.2 MHz pixel and 12.288 MHz audio
clocks. I²S divides its audio reference by four for 3.072 MHz BCLK and uses
64 clocks per 48 kHz stereo frame. No fractional clock divider is used in this
transport. The board clock-generator setup and electrical quality are unverified.

System/audio reset must assert together; each must release synchronously to its
own clock in the board wrapper. Stereo metadata stays held until acknowledged;
individual PCM bits are not independently synchronized. The digital clock model
does not reproduce metastability or certify clock-domain constraints.

The host status query reports formatter readiness at bit 13 and sticky audio
underrun at bit 14. Both cross as synchronized registered flags. Readiness means
a coherent pair has started transmission; it does not certify a physical DAC.

The intended third reference can use the board's programmable generator output
on FPGA pin 13, subject to configuration/clock validation. Sipeed documents the
three outputs on pins 10/11/13 and its control interface in the
[board unboxing guide](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/example/unbox.html).
No hardware clock configuration was changed by these software checks.

## Remaining acceptance

The bench filter's upper-audible attenuation is a deliberate, documented open
tradeoff. Compare a reference capture/listening corpus before selecting the
final response. This filter is not an Atari analog-circuit reconstruction.
Stereo headphone circuitry, amplifier enable/reset sequencing, board I/O,
physical clock quality and listening measurements remain unqualified.

The portable audiovisual system maps to **35 block RAMs** and
**6,214 registers**, including synchronized audio status. Complete-board
placement/routing and timing are still the next gate. See the
[audio design diagram](../chip-design/audio.md),
[open choices](../tradeoffs.md) and [roadmap](../roadmap.md).
