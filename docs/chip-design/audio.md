# Stereo audio and output logic

Reviewed: **2026-11-17**. Status: **component and real-console software checks
pass**. Mikey generates the sound; original project logic filters its signed
PCM, transfers coherent stereo pairs and serializes them. Analog quality and
complete board timing remain open.

{{chip-diagram:audio}}

## Preserve the source, define the transport

The reused console exposes signed 16-bit left/right values in the 64 MHz system
domain. Its four sound channels, timer/LFSR behavior, stereo masks and attenuation
remain in the pinned upstream implementation. The host does not synthesize the
test tone. An original 65C02 diagnostic configures Mikey itself.

The new output path uses a separate **12.288 MHz reference**, divided by four
for **3.072 MHz BCLK**, then 64 bit clocks per **48 kHz stereo frame**. The
reference is a board-clock requirement, not a programmed or physically measured
clock yet. It uses no fractional divider in the audio transport.

## The first fixed-point filter

Four cascaded poles update on each system clock. Each has signed 32-bit Q16 state:

```text
state_next = state + floor((previous_input - state) / 1024)
output = floor((last_state + 32768) / 65536)
```

Each pole reads the preceding pole's old registered state. A 33-bit difference
covers opposite full-scale inputs. The shifted step has an explicit signed type;
an unsigned expression must not turn the right shift into a logical shift.
Clearing `enable` clears filter state and gates its output to zero.

| Frequency | Measured gain in the component test |
| --- | ---: |
| 1 kHz | −0.174516 dB |
| 24 kHz | −33.3406 dB |
| 32 kHz | −42.1845 dB |

This is a **provisional bench smoother**, not a reconstruction of the Lynx's
analog output. Four identical poles also attenuate upper audible frequencies;
the response is about −12 dB at 10 kHz. Listening/reference comparisons and a
final resampling/filter design remain an explicit decision. Replacing this
filter does not require changing the serial wiring or game-visible sound logic.
The current shift/add implementation uses no multipliers or block RAM.

## One pair, one owner

A pull request crosses into the system domain through a two-register toggle
synchronizer. The system latches both filtered channels on the same edge, holds
them, and acknowledges. After the acknowledgment crosses back, the audio domain
owns one complete pair. Data remains stable until the next request.

The transmitter latches the pair once at a stereo-frame boundary. Changing source
values during the right slot cannot combine a new right sample with an old left
sample. If no new pair is available, a started transmitter emits a complete
silent frame and increments a saturating underrun counter. Initial waiting is
silent. Joint reset flushes ownership; unilateral clock-domain reset is unsupported.

## Serial contract

WS low selects left and high selects right. WS changes one bit clock before the
new word's MSB. The implementation changes SD/WS on BCLK falling edges and the
receiver samples rising edges. Each 32-bit slot carries 16 signed PCM bits followed
by zero padding, with the standard one-bit offset. See the
[NXP I²S specification](https://www.nxp.com/docs/en/user-manual/UM11732.pdf).

Game stop holds the core and clears the filter. A previously prefetched sample
may finish; silence follows within the bounded pipeline. Serial clocks continue.
Physical amplifier shutdown, startup transients and output-clock electrical
timing still need the board wrapper and measurements.

## What the tests establish

The [component test](../../sim/audio-output.cpp) uses an independent wide-integer
filter model, a transfer-function check and a
[pin-only I²S decoder](../../sim/i2s-decoder.hpp). It checks full signed scale,
channel independence, random data, mute, two clock ratios, source-clock stop,
reported whole-frame silence and joint-reset recovery.

The [real-console monitor](../../sim/lynx-audio-monitor.hpp) derives expected
filtered samples from actual core outputs. It matches every decoded stereo pair
to its coherent snapshot, then checks distinct 2/2.5 kHz tones, button-controlled
volume, stop silence and cold/warm reload while exact-2× video also runs.
The [audio acceptance record](../milestones/tang-audio.md) contains commands,
evidence, a playable capture and resource results.

## Physical choices still ahead

The Tang's onboard MAX98357A is a mono amplifier that accepts a stereo serial
stream and can select a channel or combine them. A true stereo headphone/line
path needs a separate circuit choice; the digital pair is kept intact for that
purpose. Its interface and channel modes are described by the
[Analog Devices datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/MAX98357A-MAX98357B.pdf).
Neither a decoded WAV nor a mapped FPGA netlist qualifies an analog output.
