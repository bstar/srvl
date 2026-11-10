# Lynx hardware and compatibility

Reviewed: 2026-10-28. Status: reference research, not a compatibility specification.

## Established baseline

The Lynx combines a 65C02-family CPU integrated into Mikey with the custom Suzy
graphics/math hardware, 64 KiB RAM, and a logical 160 × 102 display. Mikey covers
timers, display transfer, audio, serial communication, and other system functions.
Suzy provides sprite drawing/scaling, collision facilities, and arithmetic.
The CPU operates at up to roughly 4 MHz; the system uses a 16 MHz timing source.
These clock numbers must not be mistaken for instructions per second.

Normal graphics use 4 bits per pixel with 16 palette entries selected from 4096
colors. A 160 × 102 framebuffer occupies 8,160 bytes. The machine's register map,
bus access rules, interrupt timing, sprite decoding, and quirks all matter to
compatibility. Matching a generic 65C02 instruction set is insufficient.

The original Lynx II was a released revision. Our concept is a subsequent
generation or alternate-history successor, not a reconstruction of an unreleased
product called Lynx II.

## CPU candidates

- **65C02-family soft core:** leading direction for instruction-level continuity.
  Select against Lynx-specific instruction and bus-cycle requirements, not merely
  performance or FPGA size. Audit license and tests before incorporation.
- **Physical WDC W65C02S:** a currently listed commercial part; could accompany
  custom peripherals on a later board. It does not replace Mikey, and differences
  from the original embedded CPU require investigation.
- **W65C816S:** a currently listed 16-bit extension of the family. A plausible
  period-inspired enhancement, but its emulation mode is not a guarantee of
  Lynx compatibility. Not selected.

Arlet's `verilog-65C02-microcode` explicitly removes original instruction cycles.
It must not be treated as a timing-faithful legacy CPU without substantial work.
Other implementations also require checking decimal flags, undefined opcodes,
wait/stall behavior, reset, and interrupt timing.

The later software prototype selects a pinned R65C02 with an explicit correction
patch and independent functional tests. See [CPU selection](cpu-selection.md).
That decision does not establish original Lynx bus/interrupt equivalence.

## Compatibility evidence and limitations

The [Tang Nano 20K core audit](lynx-tang20k-compatibility.md) records the later
source, memory, toolchain and behavioral investigation. It is separate from
the current original-console implementation and does not certify game support.

The MiSTer Lynx core's README says all official games should be playable and most
homebrew works. It requires external SDRAM and a separately supplied boot ROM.
It documents limitations, including external EEPROM support. Treat it as a
behavioral comparison, not an infallible oracle. Original hardware and targeted
test programs would resolve disputed behavior more strongly.

Game images are the initial media goal. Physical cartridges, multiplayer with an
original console, and exhaustive compatibility are separate unresolved milestones.
The prototype builds include no Atari boot ROM or commercial game ROM. They reuse
a separately licensed CPU and execute an original game ROM; an existing Lynx
machine core has not been adopted wholesale.

## Implications

Preserve legacy-visible behavior while adding explicitly activated enhanced
facilities. Legacy output scaling must not increase the game-visible framebuffer
or sprite coordinates. Enhanced rendering at 320 × 204 has four times the pixels;
CPU speed alone cannot establish a viable graphics bandwidth budget.

## Sources

- [Atari's contemporary technical material](https://www.digitpress.com/library/books/book_atari_lynx_hint_book.pdf)
- [Original developer documentation archive](https://atariage.com/Lynx/archives/developer_docs/index.html?SystemID=LYNX)
- [Contemporary memory-map article](https://www.atarimania.com/mags/pdf/Atari_Explorer_January_February_1991.pdf)
- [MiSTer Lynx core](https://github.com/MiSTer-devel/AtariLynx_MiSTer)
- [WDC current CPU family](https://wdc65xx.com/integrated-circuit)
- [Arlet microcoded 65C02 and its cycle-count differences](https://github.com/Arlet/verilog-65C02-microcode)
- [Alternative 65C02 implementation and documented limitations](https://github.com/spectrumero/verilog-65C02)
