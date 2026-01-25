# zigraph

[![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg)](LICENSE)

**Zero-dependency graph layout engine for Zig.** Visualize DAGs, dependency trees, and flow graphs in terminals, SVG, or JSON.

<table>
<tr>
<td><strong>Terminal (Unicode)</strong></td>
<td><strong>SVG (Direct)</strong></td>
<td><strong>SVG (Splines)</strong></td>
</tr>
<tr>
<td>

<img src="assets/readme_hero_tui_colored.png" width="280">

</td>
<td>

<img src="assets/hero_direct.svg" width="280">

</td>
<td>

<img src="assets/hero_spline.svg" width="280">

</td>
</tr>
</table>

## Features

- **Zero dependencies** — Pure Zig, no libc required
- **Three renderers** — Unicode (terminal), SVG (with splines), JSON (for tooling)
- **Pluggable algorithms** — Bring your own crossing reduction, positioning, routing
- **Comptime graphs** — Build diagrams at compile time, embed as string literals
- **Embedded-first** — Explicit allocators, ~40KB WASM target

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zigraph = .{
        .url = "https://github.com/AshutoshMahala/zigraph/archive/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

Then in `build.zig`:

```zig
const zigraph = b.dependency("zigraph", .{});
exe.root_module.addImport("zigraph", zigraph.module("zigraph"));
```

## API Usage

### 1. Unicode Renderer (Terminal)

```zig
const zigraph = @import("zigraph");

// Render with ANSI colors (optional)
const output = try zigraph.unicode.renderWithConfig(&ir, allocator, .{
    .edge_palette = &zigraph.colors.ansi_dark,
    .show_dummy_nodes = false, 
});
defer allocator.free(output);
std.debug.print("{s}\n", .{output});
```

### 2. SVG Renderer (Web/Vector)

```zig
// Render directly layout IR to SVG
const svg = try zigraph.svg.render(&ir, allocator, .{
    .edge_palette = &zigraph.colors.radix,
    .color_edges = true,
    .stitch_splines = true, // Smooth curves
});
defer allocator.free(svg);
```

### 3. JSON Renderer (Integration)

```zig
// Export layout data for external tools
const json = try zigraph.json.render(&ir, allocator);
defer allocator.free(json);
```

See [JSON_SCHEMA.md](JSON_SCHEMA.md) for data format details.

## Quick Start

```zig
const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build graph
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();
    
    try graph.addNode(1, "Parse");
    try graph.addNode(2, "Compile");
    try graph.addNode(3, "Link");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);

    // Layout and render
    const output = try zigraph.render(&graph, allocator, .{});
    defer allocator.free(output);
    
    std.debug.print("{s}\n", .{output});
}
```

Output:
```text
[Parse]
   │
   ↓
[Compile]
   │
   ↓
 [Link]
```

## Renderers

### Unicode (Terminal)

```zig
const output = try zigraph.render(&graph, allocator, .{});
```

### SVG

```zig
var ir = try zigraph.layout(&graph, allocator, .{ .routing = .spline });
defer ir.deinit();

const svg = try zigraph.svg.render(&ir, allocator, .{
    .edge_palette = &zigraph.colors.radix,  // Colored edges
    .show_control_points = true,             // Debug splines
});
```

### JSON

```zig
const json = try zigraph.exportJson(&graph, allocator, .{});
```

See [JSON_SCHEMA.md](JSON_SCHEMA.md) for the output format, or view [assets/hero.json](assets/hero.json) for an example.

## Configuration

```zig
const output = try zigraph.render(&graph, allocator, .{
    // Positioning
    .positioning = .brandes_kopf,  // or .simple

    // Crossing reduction
    .crossing_reducers = &zigraph.crossing.balanced,  // default
    // .crossing_reducers = &zigraph.crossing.fast,   // speed
    // .crossing_reducers = &zigraph.crossing.quality, // best

    // Edge routing
    .routing = .direct,  // or .spline

    // Spacing
    .node_spacing = 3,
    .level_spacing = 2,

    // Performance
    .skip_validation = false,
});
```

### Custom Crossing Reduction

Compose your own pipeline:

```zig
.crossing_reducers = &[_]zigraph.crossing.Reducer{
    zigraph.crossing.medianReducer(4),
    zigraph.crossing.adjacentExchangeReducer(2),
    zigraph.crossing.medianReducer(2),  // polish
},
```

Or bring your own algorithm:

```zig
fn myReducer(self: *const zigraph.crossing.Reducer, levels: *VirtualLevels, g: *const Graph, alloc: Allocator) !void {
    // Custom crossing reduction logic
}

.crossing_reducers = &[_]zigraph.crossing.Reducer{
    zigraph.crossing.medianReducer(2),
    .{ .runFn = myReducer, .passes = 5 },
},
```

## Comptime Graphs

Build diagrams at compile time with zero runtime allocation:

```zig
const ComptimeGraph = @import("zigraph").ComptimeGraph;

const diagram = comptime blk: {
    var g = ComptimeGraph.init();
    g.edge(1, 2);
    g.edge(2, 3);
    break :blk g.render();
};

pub fn main() void {
    // diagram is embedded in binary - no allocations!
    std.debug.print("{s}\n", .{diagram});
}
```

## Performance

Benchmarks on Apple M2 (zig build run-benchmark):

| Nodes | Edges | Layout | Render | Total |
|-------|-------|--------|--------|-------|
| 100 | 200 | 1.0 ms | 0.03 ms | 1.0 ms |
| 1,000 | 2,000 | 57 ms | 0.1 ms | 57 ms |
| 10,000 | 20,000 | 4.5 s | 1.4 ms | 4.5 s |

### Crossing Reduction Comparison (100 nodes)

| Preset | Time | Description |
|--------|------|-------------|
| `none` | 0.03 ms | No reduction |
| `fast` | 0.04 ms | median(2) |
| `balanced` | 0.6 ms | median(4) + exchange(2) |
| `quality` | 0.6 ms | median(8) + exchange(4) + median(2) |

### Complexity

- **Layout**: O(passes × (V + E)) dominated by crossing reduction (V=nodes, E=edges)
- **Render**: O(W × H) where W×H is output dimensions

### Recommendations

- **<100 nodes**: Use `crossing.quality` for best results
- **100-1000 nodes**: Use `crossing.balanced` (default)
- **>1000 nodes**: Use `crossing.fast` or `skip_validation = true`
- **Wide layers (>20 nodes)**: Adjacent exchange auto-skips for performance

## Architecture

zigraph implements the **Sugiyama algorithm** (hierarchical layout):

1. **Layering** — Assign nodes to horizontal layers (longest-path)
2. **Crossing reduction** — Reorder nodes to minimize edge crossings (median + adjacent exchange)
3. **Positioning** — Assign x-coordinates (Brandes-Köpf or simple)
4. **Routing** — Route edges between nodes (direct or spline)

```text
┌─────────────────────────────────────────────────────────────────┐
│                          User API                               │
│  zigraph.render() / zigraph.layout() / zigraph.exportJson()     │
├─────────────────────────────────────────────────────────────────┤
│                        LayoutConfig                             │
│  positioning, crossing_reducers, routing, spacing               │
├─────────────────────────────────────────────────────────────────┤
│                        Algorithms                               │
│  ┌─────────────┬──────────────────┬────────────────┬─────────┐  │
│  │  Layering   │ Crossing         │  Positioning   │ Routing │  │
│  │             │                  │                │         │  │
│  │ longest_path│ median           │ brandes_kopf   │ direct  │  │
│  │             │ adjacent_exchange│ simple         │ spline  │  │
│  │             │ (pluggable)      │                │         │  │
│  └─────────────┴──────────────────┴────────────────┴─────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                        Layout IR                                │
│  Intermediate representation with positions and paths           │
├─────────────────────────────────────────────────────────────────┤
│                        Renderers                                │
│  ┌──────────────┬──────────────────┬─────────────────────────┐  │
│  │   Unicode    │      SVG         │         JSON            │  │
│  │ (terminal)   │ (splines,colors) │ (for external tools)    │  │
│  └──────────────┴──────────────────┴─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed design decisions.

## Use Cases

- **CLI tools** — Error chain visualization, build graphs
- **Compilers** — AST/IR visualization
- **Documentation** — Embedded diagrams
- **Embedded systems** — Diagnostics on microcontrollers
- **WASM dashboards** — Browser-based visualization

## Examples

```bash
zig build run-example      # Basic usage
zig build run-hero         # README hero diagram
zig build run-svg          # SVG with splines
zig build run-json         # JSON export
zig build run-comptime     # Comptime graphs
zig build run-stress       # Stress test suite
zig build run-benchmark    # Performance benchmarks
```

## License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option.

---

Created by [Ash](https://github.com/AshutoshMahala) • Inspired by [ascii-dag](https://github.com/AshutoshMahala/ascii-dag) (Rust)
