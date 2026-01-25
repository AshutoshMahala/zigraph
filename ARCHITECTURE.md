# Architecture

This document describes the internal architecture of `zigraph`, a zero-dependency graph layout engine for Zig.

## Overview

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                              USER API                                   │
│                                                                         │
│   var graph = Graph.init(allocator);                                    │
│   const ir = try zigraph.layout(&graph, allocator, .{});                │
│   const output = try zigraph.unicode.render(ir, allocator, .{});        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         LAYOUT CONFIG                                   │
│                                                                         │
│   LayoutConfig {                                                        │
│       .layering = .longest_path,                                        │
│       .crossing_reducers = &crossing.balanced,  // preset or custom     │
│       .positioning = .brandes_kopf,                                     │
│       .routing = .direct,                                               │
│   }                                                                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         ALGORITHM LAYER                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  Layering   │  │  Crossing   │  │ Positioning │  │   Routing   │     │
│  │             │  │  Reduction  │  │             │  │             │     │
│  │ longest_path│  │ median      │  │ simple      │  │ direct      │     │
│  │ virtual     │  │ adj_exchange│  │ brandes_kopf│  │ spline      │     │
│  │ (dummies)   │  │ reducers    │  │             │  │             │     │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    ★ INTERMEDIATE REPRESENTATION ★                      │
│                                                                         │
│   LayoutIR { nodes: []LayoutNode, edges: []LayoutEdge, width, height }  │
│                                                                         │
│   This is the STABLE CONTRACT between layout and rendering.             │
│   Supports both real and dummy nodes for multi-level edge routing.      │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          RENDER LAYER                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   Unicode   │  │     SVG     │  │    JSON     │  │   Colors    │     │
│  │ (terminal)  │  │  (vector)   │  │   (IR)      │  │ (palettes)  │     │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
zigraph/
├── src/
│   ├── root.zig              # Library entry point, re-exports, layout()
│   ├── comptime_graph.zig    # ComptimeGraph for zero-runtime-cost diagrams
│   ├── fuzz_tests.zig        # Property-based and security tests
│   │
│   ├── core/
│   │   ├── graph.zig         # Graph, Node, Edge, Options (with resource limits)
│   │   ├── ir.zig            # LayoutIR, LayoutNode, LayoutEdge, EdgePath
│   │   ├── validation.zig    # Cycle detection, graph validation
│   │   └── errors.zig        # WDP Level 0 error codes
│   │
│   ├── algorithms/
│   │   ├── layering/
│   │   │   ├── longest_path.zig   # O(V+E) layer assignment
│   │   │   └── virtual.zig        # Dummy node insertion for long edges
│   │   │
│   │   ├── crossing/
│   │   │   ├── median.zig         # Median heuristic crossing reduction
│   │   │   ├── adjacent_exchange.zig  # Local optimization refinement
│   │   │   └── reducers.zig       # Preset pipelines (fast, balanced, quality)
│   │   │
│   │   ├── positioning/
│   │   │   ├── simple.zig         # Left-to-right packing
│   │   │   ├── brandes_kopf.zig   # Centered parent/child alignment
│   │   │   └── common.zig         # Shared positioning utilities
│   │   │
│   │   └── routing/
│   │       ├── direct.zig         # Manhattan routing (straight + corners)
│   │       └── spline.zig         # Catmull-Rom spline generation
│   │
│   └── render/
│       ├── unicode.zig        # Terminal output with box drawing
│       ├── svg.zig            # SVG vector output with spline support
│       ├── json.zig           # JSON IR export (for external tools)
│       └── colors.zig         # Color palettes (Radix, vibrant, etc.)
│
├── examples/                  # Usage examples
├── build.zig                  # Zig build configuration
├── build.zig.zon              # Package manifest
├── README.md
├── ARCHITECTURE.md            # This file
└── LICENSE-*
```

## Design Principles

### 1. Zero Dependencies

zigraph has no dependencies beyond the Zig standard library. This ensures:
- Predictable build times
- No supply chain concerns
- Works in embedded/no_std environments

### 2. Explicit Allocator Passing (BYOA)

Every function that allocates takes an `std.mem.Allocator`:

```zig
pub const Graph = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(Node),
    edges: std.ArrayListUnmanaged(Edge),
    
    pub fn init(allocator: std.mem.Allocator) Graph { ... }
    pub fn deinit(self: *Graph) void { ... }
};
```

**Benefits:**
- Works with any allocator (GPA, Arena, FixedBuffer, page allocator)
- No hidden global state
- Easy to track memory ownership

### 3. Configurable Resource Limits

Security hardening with configurable limits:

```zig
// Default: 100K nodes, 500K edges
var graph = Graph.init(allocator);

// Custom limits for constrained environments
var graph = Graph.initWithOptions(allocator, .{
    .max_nodes = 10_000,
    .max_edges = 50_000,
});
```

### 4. Stable IR Contract

The `LayoutIR` is the stable interface between:
- **Above**: Layout algorithms (produce IR)
- **Below**: Renderers (consume IR)

```zig
pub const LayoutNode = struct {
    id: usize,
    label: []const u8,
    x: usize,
    y: usize,
    width: usize,
    center_x: usize,
    level: usize,
    level_position: usize,               // Position within level (0-indexed)
    kind: NodeKind = .explicit,          // .explicit, .implicit, or .dummy
    edge_index: ?usize = null,           // For dummy nodes: which edge
};

pub const EdgePath = union(enum) {
    direct: void,                                    // Straight vertical
    corner: struct { horizontal_y: usize },          // L-shaped with horizontal segment
    side_channel: struct {                           // For skip-level edges
        channel_x: usize,
        start_y: usize,
        end_y: usize,
    },
    multi_segment: struct {                          // Through dummy nodes
        waypoints: std.ArrayListUnmanaged(Waypoint),
        allocator: Allocator,
    },
    spline: struct {                                 // Bezier curve
        cp1_x: usize, cp1_y: usize,                  // Control point 1
        cp2_x: usize, cp2_y: usize,                  // Control point 2
    },
};

pub const LayoutEdge = struct {
    from_id: usize,
    to_id: usize,
    from_x: usize,
    from_y: usize,
    to_x: usize,
    to_y: usize,
    path: EdgePath,
    edge_index: usize,                    // For consistent coloring
};

pub const LayoutIR = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(LayoutNode),
    edges: std.ArrayListUnmanaged(LayoutEdge),
    width: usize,
    height: usize,
    level_count: usize,
    levels: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)),
    id_to_index: std.AutoHashMapUnmanaged(usize, usize),
    
    pub fn deinit(self: *LayoutIR) void { ... }
};
```

### 5. Crossing Reducer Pipelines

Crossing reduction uses composable reducer pipelines:

```zig
// Use a preset
const ir = try zigraph.layout(&graph, allocator, .{
    .crossing_reducers = &zigraph.crossing.quality,
});

// Or build custom pipeline
const custom = &[_]zigraph.crossing.Reducer{
    zigraph.crossing.medianReducer(6),
    zigraph.crossing.adjacentExchangeReducer(3),
};
const ir = try zigraph.layout(&graph, allocator, .{
    .crossing_reducers = custom,
});
```

**Presets:**
- `fast`: 2 median passes (quick, decent quality)
- `balanced`: 4 median + 2 adjacent exchange (default)
- `quality`: 8 median + 4 adjacent exchange + 2 polish passes (best results)
- `none`: No reduction (for debugging)

---

## Sugiyama Algorithm Implementation

The library implements the Sugiyama layered graph layout:

### Phase 1: Cycle Detection
- DFS-based cycle detection in `validation.zig`
- Returns `CycleInfo` with participating nodes
- Cycles are rejected (DAGs only)

### Phase 2: Layer Assignment
- **Longest Path**: O(V+E), assigns each node to deepest possible layer
- Virtual nodes inserted for edges spanning multiple layers

### Phase 3: Crossing Reduction
- **Median Heuristic**: Orders nodes by median position of neighbors
- **Adjacent Exchange**: Local swaps to reduce crossings further
- Multiple passes with alternating down-sweep/up-sweep

### Phase 4: X-Coordinate Assignment
- **Simple**: Left-to-right packing with minimum spacing
- **Brandes-Kopf**: Centers parents over children for tree-like structures

### Phase 5: Edge Routing
- **Direct**: Manhattan routing with corner detection
- **Spline**: Catmull-Rom/Bezier curves through waypoints

---

## Memory Model

### Ownership Rules

1. **Graph** owns its nodes and edges
2. **LayoutIR** owns the computed layout (separate allocation)
3. **Rendered output** is a new allocation (caller owns)

```zig
var graph = Graph.init(allocator);  // graph owns nodes/edges
defer graph.deinit();

const ir = try layout(&graph, allocator, .{});  // ir owns layout data
defer ir.deinit();

const output = try unicode.render(ir, allocator);  // caller owns output
defer allocator.free(output);
```

### Arena Support

For embedded/no_std, use a fixed buffer arena:

```zig
var buffer: [65536]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);

var graph = Graph.init(fba.allocator());
// ... build graph, layout, render - all in fixed buffer
```

---

## Security Hardening

zigraph includes protections against resource exhaustion:

| Protection | Location | Limit |
|------------|----------|-------|
| Max nodes | graph.zig | 100,000 (configurable) |
| Max edges | graph.zig | 500,000 (configurable) |
| Buffer overflow | unicode.zig | Checked w*h multiplication |
| SVG dimensions | svg.zig | Checked arithmetic |
| Connection buffer | adjacent_exchange.zig | 256 per node pair |

All limits return `error.OutOfMemory` when exceeded.

---

## Testing Strategy

- **Unit tests**: In each module (`test "..."` blocks)
- **Property-based tests**: Layout invariants verified in `fuzz_tests.zig`
- **Cycle detection tests**: Edge cases including disjoint components
- **Security tests**: Resource limit verification
- **88 tests total** as of v0.1.0

---

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Longest path layering | O(V + E) | Single DFS pass |
| Median crossing | O(passes * (V + E)) | Default 4 passes, optimized with position maps |
| Adjacent exchange | O(L * N^2 * passes) | L=layers, N=nodes/layer |
| Simple positioning | O(V) | Linear scan |
| Brandes-Kopf | O(V + E) | Two passes |
| Unicode render | O(W * H) | Grid-based |
| SVG render | O(V + E) | Path generation |

---

## Error Codes (WDP Level 0)

zigraph uses Waddling Diagnostic Protocol compliant error codes:

| Code | Meaning |
|------|---------|
| E.Graph.Node.001 | Empty graph (MISSING) |
| E.Graph.Node.021 | Node not found (NOT_FOUND) |
| E.Graph.Edge.003 | Self-loop invalid (INVALID) |
| E.Graph.Edge.007 | Duplicate edge (DUPLICATE) |
| E.Graph.Dag.003 | Cycle detected (INVALID) |
| E.Layout.Algo.003 | Layout failed (INVALID) |
| E.Layout.Algo.026 | Out of memory (EXHAUSTED) |
| E.Layout.Reducer.001 | Reducer lost node (MISSING) |
| E.Layout.Reducer.002 | Reducer node count mismatch (MISMATCH) |
| E.Layout.Reducer.003 | Reducer corrupted levels (INVALID) |
| E.Layout.Reducer.007 | Reducer duplicate node (DUPLICATE) |
