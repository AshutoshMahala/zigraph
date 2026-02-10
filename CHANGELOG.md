# Changelog

All notable changes to zigraph will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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

- **Network Simplex Layering** — Optimal layer assignment algorithm (Gansner et al. 1993)
  - `.network_simplex` — Full simplex pivoting until optimal
  - `.network_simplex_fast` — Bounded iterations (V × √E) for predictable performance

- **Edge Labels** — `graph.addEdgeLabeled(from, to, "label")` with support in all renderers

### Changed

- **Positioning default changed** to `.none` (left-to-right packing)
  - `.simple` and `.brandes_kopf` currently have collision issues with dummy nodes
  - Use `.none` for reliable layouts without overlaps

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
- Collision fix: Default positioning reverted to avoid dummy node overlaps

### Internal

- 168 tests (up from 88 in v0.1.0)
- `computeVirtualPositionsWithHints()` for positioning algorithm integration
- `examples/presets_demo.zig` — All presets side-by-side comparison
- `run-presets` build step

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
- Comptime graph support — build diagrams at compile time with zero runtime allocation
- Color palettes: Radix UI, ANSI dark/light
- Layout IR intermediate representation
- Graph validation
- Comprehensive examples and benchmarks
