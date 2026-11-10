# CPU selection for the software prototype

Reviewed: 2026-10-28. Prototype choice accepted in
[ADR 0005](../architecture/decisions/0005-prototype-cpu-and-peripherals.md).
This is not a claim of verified Lynx timing or WDC-specific opcode coverage.

## Candidates examined

| Core | Relevant evidence | Outcome |
| --- | --- | --- |
| `mist-devel/T65` | Upstream README explicitly calls 65C02/65C816 modes incomplete, lists missing CMOS instructions, and notes interrupt/interface issues | Not selected for this 65C02 milestone |
| `hoglet67/verilog-6502` and `spectrumero/verilog-65C02` | Upstream documents CMOS additions, optional decimal/NOP behavior, missing Rockwell/WDC instructions, and wait-state caveats | Retained as comparison references |
| Arlet's microcoded core | Deliberately reduces instruction cycle counts | Not selected as a timing-oriented basis |
| `MJoergen/65c02` | MIT license, Rockwell instruction set, functional-test support; explicitly not cycle exact and excludes STP/WAI | Useful reference, not selected for this timing-oriented prototype |
| Jens Gutschmidt's `cpu65c02_true_cycle` | Timing-oriented Rockwell core, GPL-3.0-or-later source, original cycle specification and functional-test history | Selected with an explicit local correction patch and independent tests |

The selected source is pinned to revision
`acd38f0ec29facbf7a0d6c144b20a4757bfc0358`. GHDL analyzes its six leaf source
files in the `r65c02_tc` library and synthesizes the `core` entity to Verilog. The
redundant upstream wrapper is not needed, avoiding its entity/library name clash
in GHDL. The generated package preserves source, license, and the applied patch.

## Issues found and tests

The first unmodified-core runs trapped in both current functional test binaries
when BRK incorrectly cleared D in the stacked status byte. The CPU should retain
the old flag in the stack copy while clearing it in the handler's live status.
The local patch corrects the stacked value, supplies default hold states on
otherwise unassigned RDY paths, and factors duplicated branch-offset outputs to
remove a combinational scheduling feedback path without changing those outputs.

The pinned Klaus Dormann tests are revision
`7954e2dbb49c469ea286070bf46cdd71aeb29e4b`, including preassembled binaries and
their listings. The harness loads all 64 KiB and sets only the reset vector to
the suite's documented `$0400` entry. It does not force CPU registers or skip
failing tests. Success requires the documented terminal loops (`$3469` and
`$24F1`), with trap detection and a bounded clock count.

Both suites passed after the corrections. Directed tests independently check
reset-vector fetching, selected instruction bus-cycle counts, RAM writes, and
the BRK stacked/live flag regression. This is instruction-level and selected
cycle evidence, not complete proof of bus equivalence, arbitrary RDY stalls,
all IRQ/NMI corners, or original Lynx behavior. The prototype currently ties
RDY active and uses frame-wait clock control separately.

## Sources

- [Selected core and GPL license](https://github.com/freecores/cpu65c02_true_cycle)
- [T65 limitations](https://github.com/mist-devel/T65/blob/master/README)
- [Arlet microcoded core](https://github.com/Arlet/verilog-65C02-microcode)
- [Hoglet CMOS extensions](https://github.com/hoglet67/verilog-6502)
- [Spectrumero variant and caveats](https://github.com/spectrumero/verilog-65C02)
- [MJoergen core and stated cycle limitations](https://github.com/MJoergen/65c02)
- [Klaus Dormann functional tests](https://github.com/Klaus2m5/6502_65C02_functional_tests)
- [GHDL synthesis](https://ghdl.github.io/ghdl/using/Synthesis.html)
- [Verilator hierarchy boundaries](https://verilator.org/guide/latest/verilating.html#hierarchical-verilation)
