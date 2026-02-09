# Changelog

All notable changes to zigraph will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Network simplex layering** — Optimal layer assignment algorithm (Gansner et al. 1993) that minimizes total edge span, producing more compact layouts than longest-path for complex graphs
  - `.network_simplex` — Full simplex pivoting until optimal
  - `.network_simplex_fast` — Bounded iterations (`V × √E`) for predictable performance on large graphs
- **Edge labels** — `graph.addEdgeLabeled(from, to, "label")` to attach labels to edges
- **Edge labels in Unicode renderer** — Labels rendered inline alongside edges in terminal output
- **Edge labels in SVG renderer** — Two rendering modes:
  - **Fixed-position** (default) — Labels centered at the edge midpoint with `text-anchor="middle"`
  - **Text-on-path** (`labels_on_path: true`) — Labels follow the edge curve using SVG `<textPath>`
- **Smart text orientation** — Text paths are always left-to-right so labels are never rendered upside-down, even on edges that flow right-to-left
- **SVG edge label centering** — Labels are positioned at the true geometric midpoint of the rendered edge path (polyline walk), not the terminal grid position
- `run-labels` build step — `zig build run-labels` to run the edge labels demo
- `run-ns-compare` build step — `zig build run-ns-compare` to compare layering algorithms
- `edge_labels.zig` example — Demonstrates labeled edges with dependency, state machine, and mixed-label graphs
- `ns_compare.zig` example — Side-by-side comparison of longest-path vs network simplex layering

### Changed

- SVG edge labels use `dominant-baseline="auto"` with `dy="-4"` offset so text sits above the edge (edge underlines the label) instead of overlapping it
- SVG `<textPath>` labels use `startOffset="50%"` + `text-anchor="middle"` for centered placement along the path
- Visible edge elements (`<line>`/`<path>`) are now always separate from hidden text paths, so arrow markers render correctly regardless of text direction

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
