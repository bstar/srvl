# Commander X16 inspiration

Reviewed: 2026-10-28. Status: architectural inspiration; no X16 compatibility goal.

## Relevant evidence

The X16 combines an 8 MHz 65xx CPU with VERA, a specialized FPGA-based video/audio
adapter. Its current overview lists 128 KB dedicated video RAM, output up to
640 × 480, 256 palette colors from 4096, two tile/bitmap layers, and 128 sprites
up to 64 × 64 pixels. VERA also provides programmable sound and PCM facilities.
Board revisions differ; consult the appropriate hardware revision before copying
electrical details.

VERA exposes a small memory-mapped register interface. Video RAM is accessed
indirectly through address/data ports rather than occupying the whole CPU address
space. Address-increment facilities reduce CPU work for transfers. Sprite output
uses scanline buffering. These are useful examples of organizing bandwidth around
an inexpensive CPU.

VERA FX extends addressing and data operations with line, polygon and affine
helpers, cache writes, and arithmetic support. Its own documentation emphasizes
that these assist the CPU's inner loops rather than act as a complete autonomous
3D renderer.

## Possible applications here

- Dedicated graphics memory, efficient data ports, and explicit DMA/bus arbitration.
- Tile backgrounds for enhanced mode to avoid redrawing static scenery each frame.
- Packed-pixel operations, span filling, fixed-point address generation and math
  acceleration where measured workloads justify the circuit.
- Thorough register documentation and a small understandable programming model.

These are proposals, not accepted features. VERA's layered scanline composition
differs from Suzy drawing scaled sprites into a framebuffer. Wholesale replacement
would not supply Lynx compatibility. Any new memory organization must preserve
legacy visibility, contention, display timing, and collision behavior where needed.

The original VERA repository is MIT-licensed; the X16 implementation has diverged
and includes FX changes. Check the exact source revision and license before reuse.
We have not imported VERA or adopted its register map, capacities, or clocks.

## Sources

- [Official X16 overview](https://github.com/X16Community/x16-docs/blob/master/X16%20Reference%20-%2001%20-%20Overview.md)
- [VERA programmer reference](https://github.com/X16Community/x16-docs/blob/master/X16%20Reference%20-%2009%20-%20VERA%20Programmer%27s%20Reference.md)
- [VERA FX reference](https://github.com/X16Community/x16-docs/blob/master/X16%20Reference%20-%2010%20-%20VERA%20FX%20Reference.md)
- [Original VERA hardware and HDL repository](https://github.com/fvdhoef/vera-module)
