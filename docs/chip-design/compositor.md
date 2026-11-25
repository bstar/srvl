# Parallax and composition

Reviewed: **2026-11-16**. Status: **proposed enhanced compositor**. Eight planes
are an earlier ambition, not a demonstrated Tang performance limit. The useful
simultaneous layer count must come from memory and resource measurements.

## Independent worlds, one scanline

Each tile plane has its own map, scroll position and palette selection. A
scanline fetch stage turns those maps into pixel candidates. Composition resolves
transparent samples and priority, combines object-surface candidates, and writes
a buffered line for display.

{{chip-diagram:compositor}}

## What makes parallax

Moving the near plane farther than the distant plane creates depth without
transforming every background pixel on the CPU. The CPU updates offsets or a
raster table; the compositor performs repeated tile lookup and pixel selection.
Independent horizontal and vertical offsets support different scene layouts.

Per-line scrolling is a possible interface for curved roads, waves and raster
effects. Its table-latch time and memory traffic must be defined before software
can rely on it. The diagram's three visual planes illustrate independent scroll;
they do not set a three-layer cap or prove eight layers fit.

## Candidate and priority contract

| Stage | Responsibility | Open specification |
| --- | --- | --- |
| Line state latch | Take a coherent snapshot of scroll, map and palette controls | Frame/line boundary, CPU update races and raster-table format |
| Tile/map fetch | Resolve map entry, pattern row, flip and palette bank | First tile format, wrap mode, map sizes and caching |
| Object candidate | Supply a completed object surface or a defined buffered stream | Surface pixel format, insertion bands and ownership |
| Priority resolver | Select the visible nontransparent sample deterministically | Equal-priority ties, insertion order and transparent sentinel |
| Palette expansion | Convert the selected color index to RGB | RGB444 selection/latching; no implicit legacy palette equivalence |
| Line buffer | Absorb memory timing variation while scanout advances | Queue depth, underflow indication and clock-domain ownership |

Avoid an expensive per-pixel read of destination data unless the composition
semantics require it. The earlier proposal used back-to-front object drawing and
insertion bands; that representation still needs a complete Tang implementation
budget and a stable interface.

## Deadline-driven fetching

The display cannot stop midway through a line to wait for a tile. Fetch ahead
and reserve memory service for scanout, including refresh and bursts of object
drawing. A buffer must become visible only after its data is complete. If a
deadline is missed, signal it and use a defined blank/repeat policy; do not read
an unrelated or partly refilled row.

Increasing plane count raises map/pattern traffic and local-buffer demand.
Different source formats, scroll positions and cache hits change actual traffic.
See the [traffic baseline](memory.md#storage-and-traffic-baseline) before treating
a bus's raw transfer rate as available graphics throughput.

## Acceptance scenes

Use uniquely colored planes and object bands so every overlap can be identified.
Test transparency, same-priority ties, tile boundaries, wrap, signed scroll,
independent X/Y motion, per-line control changes and edge cropping. Stress the
line buffers with randomized memory stalls and scanout deadline checks.

Build from a small layer count and measure combined scenes with scaled sprites.
The final limit must name the workload rather than imply that every maximum can
be used simultaneously.
