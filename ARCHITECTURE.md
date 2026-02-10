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
│                       ALGORITHM DISPATCH                                │
│                                                                         │
│   Algorithm = union(enum) {                                             │
│       sugiyama,                    // DAG hierarchical layout           │
│       fruchterman_reingold,        // Force-directed O(V²)              │
│       fruchterman_reingold_fast,   // Barnes-Hut O(V log V)             │
│   }                                                                     │
└─────────────────────────────────────────────────────────────────────────┘
                        ┌───────────┴───────────┐
                        ▼                       ▼
┌──────────────────────────────────┐ ┌────────────────────────────────────┐
│      SUGIYAMA PIPELINE           │ │     FORCE-DIRECTED (FDG)           │
│  ┌──────────┐  ┌──────────────┐  │ │                                    │
│  │ Layering │  │  Crossing    │  │ │  Q16.16 fixed-point arithmetic     │
│  │  lp / ns │  │  med / ae    │  │ │  Quadtree (Barnes-Hut θ=0.8)       │
│  ├──────────┤  ├──────────────┤  │ │  Fruchterman-Reingold simulation   │
│  │Positioning│ │  Routing     │  │ │  300 iterations → grid coords      │
│  │  bk / s  │  │ direct / sp  │  │ │                                    │
│  └──────────┘  └──────────────┘  │ └────────────────────────────────────┘
└──────────────────────────────────┘
                        ┌───────────┴───────────┐
                        ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    ★ INTERMEDIATE REPRESENTATION ★                      │
│                                                                         │
│   LayoutIR { nodes: []LayoutNode, edges: []LayoutEdge, width, height }  │
│                                                                         │
│   This is the STABLE CONTRACT between layout and rendering.             │
│   Supports both real and dummy nodes for multi-level edge routing.      │
│   Edges carry a `directed` flag for per-edge arrow control.             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          RENDER LAYER                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   Unicode   │  │     SVG     │  │    JSON     │  │   Colors    │     │
│  │ (terminal)  │  │  (vector)   │  │ (IR ⇄ JSON) │  │ (palettes)  │     │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
zigraph/
├── src/
│   ├── root.zig              # Library entry point, re-exports, layout()
│   ├── presets.zig           # Curated layout configurations (sugiyama.*, fdg.*)
│   ├── comptime_graph.zig    # ComptimeGraph for zero-runtime-cost diagrams
│   ├── fuzz_tests.zig        # Property-based and security tests
│   │
│   ├── core/
│   │   ├── graph.zig         # Graph, Node, Edge, Options (with resource limits)
│   │   ├── ir.zig            # LayoutIR, LayoutNode, LayoutEdge, EdgePath
│   │   ├── validation.zig    # Cycle detection, graph validation, Requirements
│   │   └── errors.zig        # WDP Level 0 error codes, ValidationFailures
│   │
│   ├── algorithms/
│   │   ├── interface.zig              # LayoutAlgorithm contract for BYOA
│   │   │
│   │   ├── sugiyama/                  # Hierarchical DAG layout
│   │   │   ├── layering/
│   │   │   │   ├── longest_path.zig      # O(V+E) layer assignment
│   │   │   │   ├── network_simplex.zig   # Optimal layering (Gansner et al. 1993)
│   │   │   │   └── virtual.zig           # Dummy node insertion for long edges
│   │   │   │
│   │   │   ├── crossing/
│   │   │   │   ├── median.zig         # Median heuristic crossing reduction
│   │   │   │   ├── adjacent_exchange.zig  # Local optimization refinement
│   │   │   │   └── reducers.zig       # Preset pipelines (fast, balanced, quality)
│   │   │   │
│   │   │   ├── positioning/
│   │   │   │   ├── simple.zig         # Left-to-right packing
│   │   │   │   ├── brandes_kopf.zig   # Centered parent/child alignment
│   │   │   │   └── common.zig         # Shared positioning utilities
│   │   │   │
│   │   │   └── routing/
│   │   │       ├── direct.zig         # Manhattan routing (straight + corners)
│   │   │       └── spline.zig         # Catmull-Rom spline generation
│   │   │
│   │   ├── shared/                    # Reusable components for all algorithms
│   │   │   ├── fixed_point.zig        # Q16.16 fixed-point arithmetic
│   │   │   ├── quadtree.zig           # Barnes-Hut spatial acceleration
│   │   │   ├── common.zig             # PositionResult, Convergence, Initializer
│   │   │   └── forces/                # Composable force primitives
│   │   │       ├── mod.zig            # Force re-exports
│   │   │       ├── repulsion.zig      # Coulomb-like: k²/d
│   │   │       ├── attraction.zig     # Spring-like: d/k
│   │   │       └── gravity.zig        # Center pull (for FA2)
│   │   │
│   │   └── fruchterman_reingold/      # FR force-directed layout
│   │       └── mod.zig                # Standard O(N²) + Fast O(N log N)
│   │
│   └── render/
│       ├── unicode.zig        # Terminal output with box drawing
│       ├── svg.zig            # SVG vector output with spline support
│       ├── json.zig           # JSON IR export/import (for external tools)
│       └── colors.zig         # Color palettes (Radix, vibrant, etc.)
│
├── examples/                  # Usage examples
├── docs/                      # Design documents and roadmaps
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
    directed: bool = true,                // Arrow at target (false = undirected)
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

### 6. Layout Presets

Curated configurations for common use cases:

```zig
// Use a preset (recommended)
const ir = try zigraph.layout(&graph, allocator, zigraph.presets.sugiyama.standard());

// Presets include validation requirements
const preset = zigraph.presets.sugiyama.preset(.quality);
// preset.requirements = { .non_empty = true, .acyclic = true, .all_directed = true }
```

| Preset | Layering | Crossing | Positioning | Routing | Requirements |
|--------|----------|----------|-------------|---------|---------------|
| `sugiyama.standard()` | longest_path | balanced | none | direct | non_empty, acyclic, all_directed |
| `sugiyama.fast()` | longest_path | fast | none | direct | non_empty, acyclic, all_directed |
| `sugiyama.quality()` | network_simplex_fast | quality | none | spline | non_empty, acyclic, all_directed |
| `fdg_presets.standard()` | — | — | — | direct | non_empty |
| `fdg_presets.fast()` | — | — | — | direct | non_empty |

### 7. Validation System

Bitset-based validation for reporting multiple failures:

```zig
// ValidationFailures is a packed struct(u8)
const failures = try zigraph.validation.checkRequirements(
    graph.nodeCount(), 
    graph.children, 
    graph.parents, 
    zigraph.Requirements.sugiyama, 
    allocator
);

if (!failures.isOk()) {
    // Check individual failures
    if (failures.empty) { /* graph has no nodes */ }
    if (failures.has_cycle) { /* graph contains cycles */ }
    if (failures.has_undirected_edges) { /* graph has undirected edges */ }
    
    // Get all WDP error codes
    var codes_buf: [5][]const u8 = undefined;
    const codes = failures.codes(&codes_buf);
    // codes = ["E.Graph.Node.001", "E.Graph.Dag.003", ...]
}
```

---

## Sugiyama Algorithm Implementation

The library implements the Sugiyama layered graph layout for DAGs:

### Phase 1: Cycle Detection
- DFS-based cycle detection in `validation.zig`
- Returns `CycleInfo` with participating nodes
- Cycles are rejected (DAGs only)

### Phase 2: Layer Assignment
- **Longest Path** (`.longest_path`): O(V+E), assigns each node to deepest possible layer
- **Network Simplex** (`.network_simplex`): Optimal layering via simplex pivoting (Gansner et al. 1993). Minimizes total edge span → fewer dummy nodes → more compact layouts. Typical O(V·E), worst case O(V²·E)
- **Network Simplex Fast** (`.network_simplex_fast`): Same algorithm with bounded iterations (V×√E). Trades optimality for predictable O(V+E + iters·E) runtime on large graphs
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

## Fruchterman-Reingold (Force-Directed) Implementation

For general (non-DAG) graphs, zigraph provides the Fruchterman-Reingold
force-directed layout algorithm:

### Arithmetic
- All computation uses **Q16.16 fixed-point** (`i32`) for bit-exact determinism
  across platforms.  See `src/algorithms/shared/fixed_point.zig`.

### FR Standard (`fruchterman_reingold`)
- O(V²) per iteration — computes all-pairs repulsion
- Good for graphs up to ~500 nodes

### FR-Fast (`fruchterman_reingold_fast`)
- Uses a **Barnes-Hut quadtree** (θ = 0.8) for O(V log V) repulsion
- Scales to 5000+ nodes with 37× speedup over standard at that size
- See `src/algorithms/shared/quadtree.zig`

### Integration
- Selected via `Algorithm.fruchterman_reingold` / `.fruchterman_reingold_fast`
  in `LayoutConfig`
- FDG positions are scaled to integer grid coordinates and routed through
  the same `LayoutIR` / renderer pipeline as Sugiyama

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
- **168 tests total** as of v0.2.0 (presets, validation, FDG, directed/undirected)

---

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Longest path layering | O(V + E) | Single DFS pass |
| Network simplex layering | O(V · E) typical | Simplex pivoting until optimal |
| Network simplex fast | O(V + E + iters·E) | Bounded V×√E iterations |
| Median crossing | O(passes * (V + E)) | Default 4 passes, optimized with position maps |
| Adjacent exchange | O(L * N^2 * passes) | L=layers, N=nodes/layer |
| Simple positioning | O(V) | Linear scan |
| Brandes-Kopf | O(V + E) | Two passes |
| FR Standard | O(V² · iters) | 300 iterations default |
| FR-Fast (Barnes-Hut) | O(V log V · iters) | θ=0.8, 300 iterations |
| Unicode render | O(W * H) | Grid-based |
| SVG render | O(V + E) | Path generation |

---

## Error Codes (WDP Level 0)

zigraph uses Waddling Diagnostic Protocol compliant error codes.
Codes are composed at comptime from semantic building blocks:

```zig
// Building blocks
const E = "E";           // Severity: Error
const Graph = "Graph";   // Component
const Node = "Node";     // Primary
const MISSING = "001";   // Sequence (WDP Part 6)

// Composed at comptime
pub const EMPTY_GRAPH = code(E, Graph, Node, MISSING); // → "E.Graph.Node.001"
```

### Error Code Reference

| Code | Meaning |
|------|---------||
| E.Graph.Node.001 | Empty graph (MISSING) |
| E.Graph.Node.021 | Node not found (NOT_FOUND) |
| E.Graph.Edge.002 | Graph has undirected/directed edges (MISMATCH) |
| E.Graph.Edge.003 | Self-loop invalid (INVALID) |
| E.Graph.Edge.007 | Duplicate edge (DUPLICATE) |
| E.Graph.Dag.003 | Cycle detected (INVALID) |
| E.Graph.Component.003 | Graph disconnected (INVALID) |
| E.Layout.Algo.003 | Layout failed (INVALID) |
| E.Layout.Algo.026 | Out of memory (EXHAUSTED) |
| E.Layout.Reducer.001 | Reducer lost node (MISSING) |
| E.Layout.Reducer.002 | Reducer node count mismatch (MISMATCH) |
| E.Layout.Reducer.003 | Reducer corrupted levels (INVALID) |
| E.Layout.Reducer.007 | Reducer duplicate node (DUPLICATE) |
| E.Json.*.001 | JSON field missing (MISSING) |
| E.Json.*.002 | JSON field type mismatch (MISMATCH) |
| E.Json.*.003 | JSON field invalid (INVALID) |
| E.Json.*.009 | JSON version unsupported (UNSUPPORTED) |
