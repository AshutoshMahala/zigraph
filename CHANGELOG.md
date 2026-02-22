# Changelog

All notable changes to zigraph will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

### Internal

- 179 tests (up from 88 in v0.1.0)
- `computeVirtualPositionsWithHints()` for positioning algorithm integration
- `examples/presets_demo.zig` — All presets side-by-side comparison
- `examples/cycle_breaking.zig` — Cycle breaking demo with SVG export
- `run-presets`, `run-cycle` build steps

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
