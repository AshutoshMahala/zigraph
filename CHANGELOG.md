# Changelog

All notable changes to zigraph will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed (breaking)

- **Per-graph diagnostics** — the module-level error-capture state in
  `zigraph.errors` is removed; each `Graph` now owns its diagnostics, making
  independent graphs safe to use from independent threads.
  - Removed: `zigraph.errors.captureSrc()`, `captureError()`,
    `captureErrorWithDetail()`, `captureErrorFull()`, `lastDiagnostic()`,
    `clearDiagnostic()`. Migrate `zigraph.errors.lastDiagnostic()` →
    `graph.lastDiagnostic()`; explicit reset is `graph.clearDiagnostics()`.
  - `layout`, `layoutTyped`, `render`, `renderTyped`, `exportJson`,
    `exportJsonTyped`, `exportSvg`, `exportSvgTyped` now take `*Graph`
    instead of `*const Graph` (they clear, and on error write, the graph's
    diagnostics). Callers with a mutable graph (`var g = ...;
    zigraph.layout(&g, ...)`) compile unchanged.
  - `crossing.runPipeline` takes an additional `*Diagnostics` parameter so
    reducer-corruption errors are captured on the right graph.
- Diagnostics semantics: mutating builder operations and layout entry points
  clear the previous diagnostic on entry; read-only queries (`validate`,
  `hasCycle`, `findRoots`, `findLeaves`, getters) never modify it;
  allocation failures propagate without capture.
- **u32 internal indices** — internal dense node indices are now
  `NodeIndex` (`u32`); node IDs and the `LayoutIR` contract remain `usize`.
  - `getChildren`/`getParents` return `[]const NodeIndex` instead of
    `[]const usize`. u32 widens implicitly wherever a `usize` is expected
    (slice indexing, comparisons, appends), so most call sites compile
    unchanged; only explicit `[]const usize` element-type annotations need
    updating.
  - `validation.zig` adjacency parameters are `NodeIndex`-typed.
  - "Unlimited" caps (`max_nodes`/`max_edges` = 0, or configured above
    4,294,967,295) now clamp to the 32-bit index capacity.
  - Bug fix: nodes auto-created by `addEdgeAutoCreate` now respect
    `max_nodes` (previously they bypassed the DoS cap entirely).

### Added

- `Graph.lastDiagnostic()`, `Graph.clearDiagnostics()`, and a
  `zigraph.Diagnostics` re-export.
- `zigraph.NodeIndex` (u32), `zigraph.nil_index` sentinel,
  `Graph.index_capacity`, and `Graph.effectiveMaxNodes()`/
  `effectiveMaxEdges()`.
- Passive-parallelism contract tests (`src/parallel_contract_tests.zig`):
  diagnostics isolation across graphs, clear-on-entry semantics, accessor
  ordering, and byte-identical concurrent batch layouts.
- No-globals build gate (`tools/check_no_globals.zig`), a dependency of
  `zig build test` — module-level mutable state now fails the build.

## [0.3.0] — 2026-04-26

### Added

- **Color system** (`src/render/color/`) — Numeric `Color` struct with perceptually uniform operations
  - `Color` type: f32 RGBA, constructors `rgb()`, `rgba()`, `rgb8()`, `fromHex()`, `fromHsl()`, `fromOklab()`
  - Oklab color space: `toOklab()`, `lerp()` (perceptually smooth interpolation)
  - HSL color space: `toHsl()`, `fromHsl()`
  - Operations: `darken()`, `lighten()`, `desaturate()`, `saturate()`, `withAlpha()`
  - `toHex()` — comptime `[7]u8`, `toHexAlloc(arena)` — runtime `[]const u8`
  - `ColorMap` struct with 6 scientific colormaps: viridis, inferno, magma, plasma, turbo, coolwarm
  - `ColorMap.sample(t)` — continuous color from scalar, interpolated in Oklab space
  - `ColorMap.quantize(comptime n)` — pre-baked `[n][7]u8` hex palette at comptime
  - SVG gradient helpers: `linearGradient()`, `radialGradient()`, `glowGradient()`

- **SVG Renderer Refinements** — Full style customization via function pointers
  - `edge_style_fn` — per-edge stroke, markers (7 shapes), `<defs>`, `extra_attrs`
  - `node_style_fn` — per-node shape via raw SVG (`shape_svg`), fill, stroke, defs
  - `edge_label_style_fn` — per-label color, font, size, position (0–100%), on-path toggle
  - `subgraph_style_fn` — per-subgraph box via raw SVG (`box_svg`), fill, stroke, defs
  - `global_style` / `global_script` — inject CSS `<style>` and `<script>` into SVG
  - 6 built-in node shape presets: `shapes.rounded_rectangle`, `.rectangle`, `.ellipse`, `.diamond`, `.hexagon`, `.circle`
  - `subgraph_presets.default` — default subgraph styling with depth-aware opacity
  - `defaultEdgeStyle` — Radix palette cycling with directional arrows
  - `monoEdgeStyle` — monochrome edge styling
  - **Zero hardcoded visual styling** — all styling flows through function pointers; `SvgConfig` retains only structural/layout fields

- **Type-erased Renderer interface** — `Renderer` struct following `std.mem.Allocator` vtable pattern
  - `Renderer.initSvg(config)` / `Renderer.initUnicode(config)` / `Renderer.initJson()`
  - `Renderer.init(anytype)` — wrap custom renderer backends
  - Uniform `renderer.render(layout, allocator) ![]u8` API across all backends

- **Subgraphs (Clusters)** — Hierarchical node grouping with visual boundaries
  - `graph.addSubgraph("label")` creates named clusters
  - `graph.putNodes(&.{id1, id2}).inside(sg_id)` — fluent API for node membership
  - `graph.putSubgraphs(&.{child}).inside(parent)` — nested subgraph hierarchies with cycle detection
  - Subgraph-aware Sugiyama pipeline: contiguous levels, block-based crossing reduction, padding, bounding boxes
  - FDG cohesion force pulls subgraph members toward group centroid
  - **Unicode**: double-line boxes (`╔═╗║╚╝`) with labels; edges cross borders cleanly (`╫╪╤╧`)
  - **SVG**: dashed rounded rectangles with configurable fill/stroke/opacity
  - **JSON schema v1.2**: optional `subgraphs` array with bounding box data (backward compatible)

- **FDG edge label placement** — Labels positioned at geometric midpoint of each edge

- **FDG inter-cluster separation force** — `applySeparation()` in `forces/cohesion.zig` applies Coulomb-like repulsion between sibling subgraph centroids (same `parent_id`), preventing clusters from overlapping
  - New `cluster_separation: FP` config param on `fruchterman_reingold.Config` (default `1.0`; `0` disables)
  - Applied every iteration in both `compute()` (O(N²)) and `computeFast()` (Barnes-Hut)
  - Re-exported as `forces.applySeparation` from `forces/mod.zig`
  - `fdg_subgraph_stress` example (`examples/fdg_subgraph_stress.zig`) exercises all tiers, cyclic clusters, cohesion sweep, and large-scale (500-node) graphs

- **Sugiyama subgraph overlap repair** (`sugiyama/subgraph/overlap.zig`) — new post-positioning pass that detects and fixes overlapping sibling subgraph bounding boxes by shifting node x-coordinates outward; bounded iterations prevent infinite loops
  - `fixSubgraphOverlaps()` — iterative repair with configurable minimum gap between sibling cluster borders
  - `refineAndCompact()` — 3-round refine+compact sweep matching the ascii-dag pipeline quality level
  - `asciidag_stress` example added for regression coverage

- **Terminal renderer: custom node paint functions** — `TerminalNodeStyle` gains a `paint_fn` field (`NodePaintContext → void`)
  - `NodePaintContext` provides bounding box dimensions and node label to the callback
  - `RenderPlan` respects custom node heights declared via `paint_fn` dimensions
  - `NodePaintContext` re-exported from `root.zig`

### Changed

- **`zigraph.colors` → `zigraph.color`** — Palette module renamed and expanded into `src/render/color/` sub-module.
  Palettes (`radix`, `ansi_dark`, etc.) and utilities (`get()`, `getAnsi()`) remain at the top level:
  `zigraph.color.get(&zigraph.color.radix, i)`. The old `colors.zig` shim has been removed.

- **SVG renderer modularized** — old monolithic `svg.zig` removed; replaced by 9 focused files under `src/render/svg/`:
  `mod.zig` (400 lines, entry point), `config.zig`, `nodes.zig`, `edges.zig`, `splines.zig`,
  `subgraphs.zig`, `defs.zig`, `helpers.zig`, `render_tests.zig`
- **SVG SvgConfig** — removed all hardcoded visual fields (`node_radius`, `node_fill`, `node_stroke`,
  `font_family`, `font_size`, `subgraph_fill`, etc.); styling now fully delegated to function pointers

- **Vertical spacing** — Sub-linear formula `2 + sqrt(max_fan)` (cap 8) produces more compact layouts
- **SVG horizontal edges** — Dome-shaped cubic Bézier curves for near-horizontal edges
- **FDG horizontal edge routing** — Edges routed from box edges instead of node centers
- **Sugiyama subgraph group centroid** — `reorderByGroup()` in `subgraph/compact.zig` now uses a neighbor-weighted centroid for "bridge" subgroups (few members, many external edges): these groups are positioned where their cross-cluster edges pull them, reducing crossings; large self-contained groups continue to use their own centroid
- **Sugiyama horizontal edge routing** — `findSafeHorizontalY()` in `routing/direct.zig` searches outward from the initial h_y to find a row that does not visually collide with any intermediate node, eliminating edge-through-node artifacts on long skip-level connections

## [0.2.1] — 2026-02-21

### Fixed

- **Adjacent exchange crossing reduction** — replaced fixed-size stack buffers (`[64]usize`, `[256]usize`) with dynamically allocated buffers sized to the fixed layer length, eliminating silent data truncation on graphs with high-degree nodes
- `refine()` and `refineLayer()` now take an `Allocator` and return errors properly (`!void`), propagated through the reducer pipeline

### Changed

- **`compactLevel` deduplicated** — extracted identical implementations from `brandes_kopf.zig` and `simple.zig` into `positioning/common.zig`
- **Dummy node ID constants** — replaced magic numbers (`0x80000000`, `1000`, `10000`) with named constants (`dummy_id_base`, `dummy_id_edge_stride`, `dummy_key_stride`) in `root.zig`
- **Quality preset** — `presets.sugiyama.quality()` now uses `.brandes_kopf` positioning instead of `.compact`
- **`crossing_passes` removed from `Graph`** — crossing reduction pass count is a layout concern, not a graph property; removed field, `Options` entry, and `setCrossingPasses()` method

## [0.2.0] — 2026-02-12

### Added

- **Layout Presets** — Curated configurations for common use cases
  - `presets.sugiyama.standard()` — Balanced quality/speed (default)
  - `presets.sugiyama.fast()` — Optimized for speed
  - `presets.sugiyama.quality()` — Best visual quality (network simplex + splines)
  - `presets.fdg_presets.standard()` — Fruchterman-Reingold O(N²)
  - `presets.fdg_presets.fast()` — Barnes-Hut O(N log N)
  - Each preset includes `.requirements` metadata for validation

- **Bitset-based Validation** — Report multiple graph issues at once
  - `ValidationFailures` packed struct with `empty`, `has_cycle`, `has_undirected_edges`, `has_directed_edges`, `disconnected` flags
  - `Requirements` struct for algorithm preconditions (non_empty, acyclic, all_directed, etc.)
  - `GraphProperties` computed properties (node_count, edge_counts, has_cycle, component_count)
  - `validation.checkRequirements()` convenience function
  - `validation.countComponents()` for connectivity checking

- **New WDP Error Codes** — Graph validation errors
  - `E.Graph.Edge.002` — GRAPH_HAS_UNDIRECTED / GRAPH_HAS_DIRECTED (mismatch)
  - `E.Graph.Component.003` — GRAPH_DISCONNECTED (invalid)

- **JSON Bidirectional** — `json.deserialize()` and `json.deserializeGeneric()` to parse JSON back into `LayoutIR`
  - Backward compatible: accepts both v1.0 and v1.1 schema inputs
  - `json.deinitDeserialized()` for proper cleanup of deserialized IRs

- **JSON schema v1.1** — New fields in serialized output:
  - Nodes: `kind` ("explicit", "implicit", "dummy"), `edge_index` (for dummy nodes)
  - Edges: `edge_index`, `directed`, `label` (optional)

- **Cycle Breaking** — Automatic handling of cyclic graphs in the Sugiyama pipeline
  - DFS-based back edge detection (O(V + E)) — `.cycle_breaking = .depth_first`
  - Back edges virtually reversed (original graph not mutated)
  - **SVG**: reversed edges rendered as dashed lines; two-node cycles use bezier curves to avoid overlap; self-loops rendered as arcs above the node with arrowhead
  - **Unicode**: reversed edges rendered with dashed arrows (`⇡`); self-loops shown inline with `↺` symbol (e.g. `[A]↺"self"`)
  - Self-loop handling in layering algorithms (longest path + network simplex)
  - `examples/cycle_breaking.zig` — Five demo graphs (feedback loop, build system, state machine, two-node cycle, self-loop)

- **Network Simplex Layering** — Optimal layer assignment algorithm (Gansner et al. 1993)
  - `.network_simplex` — Full simplex pivoting until optimal
  - `.network_simplex_fast` — Bounded iterations (V × √E) for predictable performance

- **Edge Labels** — `graph.addEdgeLabeled(from, to, "label")` with support in all renderers

### Changed

- **Positioning algorithms renamed and fixed**
  - `.compact` (was `.none`) — left-to-right packing (fast, default)
  - `.barycentric` (was `.simple`) — single-pass barycentric nudge (graph-aware)
  - `.brandes_kopf` — multi-pass parent/child centering (best quality)
  - All three produce correct, collision-free output

- **WDP Error Codes** now use comptime composition for consistency:
  ```zig
  pub const EMPTY_GRAPH = code(E, Graph, Node, MISSING); // → "E.Graph.Node.001"
  ```

- **Algorithm folder restructure** for scalability:
  - `algorithms/sugiyama/` — Hierarchical layout (layering, crossing, positioning, routing)
  - `algorithms/shared/` — Reusable components (fixed_point, quadtree, forces)
  - `algorithms/fruchterman_reingold/` — Force-directed layout

- JSON serializer now properly escapes special characters in labels

### Fixed

- JSON labels containing quotes no longer produce invalid JSON output
- Memory leak: `errdefer` for edge label allocation moved outside conditional block
- Dummy-node collisions in `.barycentric` and `.brandes_kopf` positioning (per-level compaction)
- Symmetric bidirectional compaction eliminates left-bias in positioned layouts

## [0.1.0] — 2026-01-25

### Added

- Initial release
- Core graph data structure with explicit allocators
- Sugiyama hierarchical layout algorithm:
  - Longest-path layering
  - Median + adjacent exchange crossing reduction (pluggable)
  - Brandes-Köpf and simple positioning
  - Direct and spline edge routing
- Three renderers: Unicode (terminal), SVG (with Catmull-Rom splines), JSON
- Color palettes: Radix UI, ANSI dark/light
- Layout IR intermediate representation
- Graph validation
- Comprehensive examples and benchmarks
