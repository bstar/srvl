# Geometry and flat triangles

Reviewed: **2026-11-16**. Status: **proposed enhanced hardware**. No project 3D
pipeline is implemented yet. The first target is fixed-point math assistance and
autonomous screen-space flat-triangle filling.

## Split the work deliberately

The CPU owns the scene and prepares geometry. A math unit assists with arithmetic.
The rasterizer receives clipped, ordered screen-space triangles and produces
covered pixels. This creates a small, useful graphics interface without assuming
the FPGA can implement every stage of a modern GPU.

{{chip-diagram:geometry}}

## First responsibility split

| Owner | Work | Acceptance requirement |
| --- | --- | --- |
| CPU/firmware | Scene traversal, transforms, projection, clipping and painter ordering, with math assistance | Bounded scene cost and correct near-plane behavior |
| Math unit | Fixed-point multiply/accumulate and a defined divide operation | Signedness, rounding, saturation/overflow and divide-by-zero behavior |
| Triangle setup | Bounding box, edge coefficients, orientation and degeneracy handling | Shared-edge agreement and explicit winding/degenerate rules |
| Coverage walker | Evaluate edges across the bounded screen rectangle | Every intended pixel exactly once, no writes outside the surface |
| Flat fill/write queue | Emit the selected color/priority for covered pixels | Backpressure and fence semantics match the sprite path |

Fixed-point formats and multiplier sharing remain resource decisions. Different
pipeline depths affect latency; software must wait for completion rather than
assume a guessed cycle count.

## Coverage rules must be specified

An edge function can determine whether a sample lies inside a triangle:

```text
edge(x, y) = A × x + B × y + C
edge(x + 1, y) = edge(x, y) + A
edge(x, y + 1) = edge(x, y) + B
```

The sample position, winding convention and boundary inclusion rule must be
chosen together. A top-left-style rule is a candidate for preventing gaps or
double-covered shared edges; it is not yet an accepted raster specification.
Intermediate width must cover worst-case clipped coordinates without overflow.

## What the first version leaves to software and authoring

Without a depth buffer, painter ordering can fail for intersecting geometry or
cyclic overlap. Near-plane clipping must happen before unstable projection.
Initial games should use bounded, testable scene structures and explicit ordering
constraints. Flat shading avoids texture fetch and interpolation costs.

Textures, a Z buffer, alpha blending and autonomous indexed-mesh transforms are
later extensions. Their absence is a visible scope choice, not an unexplained
performance shortfall. Triangles and sprite drawing still compete for the same
memory-service budget.

## Acceptance and useful measurements

Compare coverage against an independent integer reference over tiny triangles,
both windings, flat-top/flat-bottom cases, shared edges, zero-area inputs, screen
edges and negative/off-screen coordinates. Verify clipping and arithmetic extrema.
Inject queue stalls between any two covered pixels without changing coverage.

Measure setup cycles, covered pixels, rejected bounding-box samples, write stalls
and frame completion for representative scenes. Report geometry preparation cost
separately from raster throughput; a fast fill unit does not make CPU transforms
free. Then synthesize and route the complete configuration.
