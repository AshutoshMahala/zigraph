//! Benchmark: zigraph performance measurement
//!
//! Comprehensive benchmarks covering:
//! - Graph size scaling (10 to 10,000 nodes)
//! - Graph topology comparison (chain, tree, wide fan, lattice)
//! - Positioning algorithm comparison (simple vs Brandes-Köpf)
//! - Crossing reducer comparison (fast, balanced, quality, none)
//! - Routing comparison (direct vs spline)
//! - Renderer comparison (Unicode vs SVG vs JSON)
//! - Memory usage estimation
//!
//! Run with: zig build run-benchmark

const std = @import("std");
const zigraph = @import("zigraph");

const BenchmarkResult = struct {
    nodes: usize,
    edges: usize,
    layout_us: u64,
    render_us: u64,
    memory_bytes: usize = 0,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  zigraph Performance Benchmark Suite                                       ║\n", .{});
    std.debug.print("║  Run with: zig build run-benchmark                                         ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // Warm up
    std.debug.print("Warming up...\n\n", .{});
    _ = try benchmarkGraph(allocator, 10, 20, .{});

    // =========================================================================
    // 1. SIZE SCALING
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  1. SIZE SCALING (layered DAG, ~2 edges per node)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    var results: std.ArrayListUnmanaged(BenchmarkResult) = .{};
    defer results.deinit(allocator);

    const sizes = [_]struct { nodes: usize, edges_per_node: usize }{
        .{ .nodes = 10, .edges_per_node = 2 },
        .{ .nodes = 25, .edges_per_node = 2 },
        .{ .nodes = 50, .edges_per_node = 2 },
        .{ .nodes = 100, .edges_per_node = 2 },
        .{ .nodes = 250, .edges_per_node = 2 },
        .{ .nodes = 500, .edges_per_node = 2 },
        .{ .nodes = 1000, .edges_per_node = 2 },
        .{ .nodes = 2500, .edges_per_node = 2 },
        .{ .nodes = 5000, .edges_per_node = 2 },
        .{ .nodes = 10000, .edges_per_node = 2 },
    };

    for (sizes) |size| {
        const edge_count = size.nodes * size.edges_per_node;
        const result = try benchmarkGraph(allocator, size.nodes, edge_count, .{});
        try results.append(allocator, result);
    }

    std.debug.print("┌──────────┬──────────┬────────────────┬────────────────┬────────────────┐\n", .{});
    std.debug.print("│   Nodes  │   Edges  │   Layout (µs)  │   Render (µs)  │   Total (µs)   │\n", .{});
    std.debug.print("├──────────┼──────────┼────────────────┼────────────────┼────────────────┤\n", .{});

    for (results.items) |r| {
        const total_us = r.layout_us + r.render_us;
        std.debug.print("│ {d:>8} │ {d:>8} │ {d:>14} │ {d:>14} │ {d:>14} │\n", .{
            r.nodes,
            r.edges,
            r.layout_us,
            r.render_us,
            total_us,
        });
    }

    std.debug.print("└──────────┴──────────┴────────────────┴────────────────┴────────────────┘\n\n", .{});

    // =========================================================================
    // 2. TOPOLOGY COMPARISON
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  2. TOPOLOGY COMPARISON (100 nodes, default settings)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const topology_results = [_]struct { name: []const u8, result: BenchmarkResult }{
        .{ .name = "Linear chain       ", .result = try benchmarkLinear(allocator, 100) },
        .{ .name = "Binary tree        ", .result = try benchmarkBinaryTree(allocator, 100) },
        .{ .name = "Wide fan (1→99)    ", .result = try benchmarkWide(allocator, 100) },
        .{ .name = "Diamond lattice    ", .result = try benchmarkDiamond(allocator, 100) },
        .{ .name = "Random DAG         ", .result = try benchmarkRandomDAG(allocator, 100, 200) },
    };

    std.debug.print("┌─────────────────────┬──────────┬────────────────┬────────────────┐\n", .{});
    std.debug.print("│  Topology           │   Edges  │   Layout (µs)  │   Render (µs)  │\n", .{});
    std.debug.print("├─────────────────────┼──────────┼────────────────┼────────────────┤\n", .{});

    for (topology_results) |s| {
        std.debug.print("│ {s} │ {d:>8} │ {d:>14} │ {d:>14} │\n", .{
            s.name,
            s.result.edges,
            s.result.layout_us,
            s.result.render_us,
        });
    }

    std.debug.print("└─────────────────────┴──────────┴────────────────┴────────────────┘\n\n", .{});

    // =========================================================================
    // 3. POSITIONING ALGORITHM COMPARISON
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  3. POSITIONING ALGORITHM (100-node layered DAG)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const positioning_results = try benchmarkPositioning(allocator, 100);

    std.debug.print("┌─────────────────────┬────────────────┐\n", .{});
    std.debug.print("│  Algorithm          │   Layout (µs)  │\n", .{});
    std.debug.print("├─────────────────────┼────────────────┤\n", .{});
    std.debug.print("│ Barycentric          │ {d:>14} │\n", .{positioning_results.barycentric_us});
    std.debug.print("│ Brandes-Köpf        │ {d:>14} │\n", .{positioning_results.brandes_kopf_us});
    std.debug.print("└─────────────────────┴────────────────┘\n\n", .{});

    // =========================================================================
    // 4. CROSSING REDUCER COMPARISON
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  4. CROSSING REDUCTION (100-node layered DAG)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const crossing_results = try benchmarkCrossingReducers(allocator, 100);

    std.debug.print("┌─────────────────────┬────────────────┬─────────────────────────────────────┐\n", .{});
    std.debug.print("│  Preset             │   Layout (µs)  │  Description                        │\n", .{});
    std.debug.print("├─────────────────────┼────────────────┼─────────────────────────────────────┤\n", .{});
    std.debug.print("│ none                │ {d:>14} │ No crossing reduction               │\n", .{crossing_results.none_us});
    std.debug.print("│ fast                │ {d:>14} │ median(2)                           │\n", .{crossing_results.fast_us});
    std.debug.print("│ balanced (default)  │ {d:>14} │ median(4) + exchange(2)             │\n", .{crossing_results.balanced_us});
    std.debug.print("│ quality             │ {d:>14} │ median(8) + exchange(4) + median(2) │\n", .{crossing_results.quality_us});
    std.debug.print("└─────────────────────┴────────────────┴─────────────────────────────────────┘\n\n", .{});

    // =========================================================================
    // 5. ROUTING COMPARISON
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  5. EDGE ROUTING (100-node layered DAG)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const routing_results = try benchmarkRouting(allocator, 100);

    std.debug.print("┌─────────────────────┬────────────────┬─────────────────────────────────────┐\n", .{});
    std.debug.print("│  Routing            │   Layout (µs)  │  Description                        │\n", .{});
    std.debug.print("├─────────────────────┼────────────────┼─────────────────────────────────────┤\n", .{});
    std.debug.print("│ direct              │ {d:>14} │ Manhattan (grid-aligned segments)   │\n", .{routing_results.direct_us});
    std.debug.print("│ spline              │ {d:>14} │ Catmull-Rom spline curves           │\n", .{routing_results.spline_us});
    std.debug.print("└─────────────────────┴────────────────┴─────────────────────────────────────┘\n\n", .{});

    // =========================================================================
    // 6. RENDERER COMPARISON
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  6. RENDERER COMPARISON (100-node layered DAG, pre-computed layout)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const renderer_results = try benchmarkRenderers(allocator, 100);

    std.debug.print("┌─────────────────────┬────────────────┬────────────────┐\n", .{});
    std.debug.print("│  Renderer           │   Render (µs)  │  Output (bytes)│\n", .{});
    std.debug.print("├─────────────────────┼────────────────┼────────────────┤\n", .{});
    std.debug.print("│ Unicode (terminal)  │ {d:>14} │ {d:>14} │\n", .{ renderer_results.unicode_us, renderer_results.unicode_bytes });
    std.debug.print("│ SVG                 │ {d:>14} │ {d:>14} │\n", .{ renderer_results.svg_us, renderer_results.svg_bytes });
    std.debug.print("│ JSON                │ {d:>14} │ {d:>14} │\n", .{ renderer_results.json_us, renderer_results.json_bytes });
    std.debug.print("└─────────────────────┴────────────────┴────────────────┘\n\n", .{});

    // =========================================================================
    // 7. STRESS TESTS
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  7. STRESS TESTS (extreme topologies)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const stress_results = [_]struct { name: []const u8, result: BenchmarkResult }{
        .{ .name = "Diamond mesh (20K)      ", .result = try benchmarkDiamondMesh(allocator, 20000) },
        .{ .name = "Wide fan (20K)          ", .result = try benchmarkWideFan(allocator, 20000) },
        .{ .name = "Neural net (5×100 = 500)", .result = try benchmarkNeuralNet(allocator, 5, 100) },
        .{ .name = "Deep chain (1000)       ", .result = try benchmarkLinear(allocator, 1000) },
    };

    std.debug.print("┌───────────────────────────┬──────────┬─────────────┬────────────────┬────────────────┐\n", .{});
    std.debug.print("│  Topology                 │   Nodes  │    Edges    │   Layout (µs)  │   Render (µs)  │\n", .{});
    std.debug.print("├───────────────────────────┼──────────┼─────────────┼────────────────┼────────────────┤\n", .{});

    for (stress_results) |s| {
        std.debug.print("│ {s} │ {d:>8} │ {d:>11} │ {d:>14} │ {d:>14} │\n", .{
            s.name,
            s.result.nodes,
            s.result.edges,
            s.result.layout_us,
            s.result.render_us,
        });
    }

    std.debug.print("└───────────────────────────┴──────────┴─────────────┴────────────────┴────────────────┘\n\n", .{});

    // =========================================================================
    // SUMMARY
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  SUMMARY\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    std.debug.print("Complexity:\n", .{});
    std.debug.print("  • Layout: O(n·m) where n=nodes, m=edges (dominated by crossing reduction)\n", .{});
    std.debug.print("  • Render: O(W·H) where W=width, H=height of output grid\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Recommendations:\n", .{});
    std.debug.print("  • <100 nodes:  Use .quality for best results\n", .{});
    std.debug.print("  • 100-1000:    Use .balanced (default)\n", .{});
    std.debug.print("  • >1000 nodes: Use .fast or skip_validation=true\n", .{});
    std.debug.print("  • Wide layers: Adjacent exchange auto-skips layers >20 nodes\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("=== Benchmark Complete ===\n\n", .{});
}

// ============================================================================
// BENCHMARK IMPLEMENTATIONS
// ============================================================================

const BenchmarkConfig = struct {
    crossing_reducers: []const zigraph.crossing.Reducer = &zigraph.crossing.balanced,
    positioning: zigraph.Positioning = .brandes_kopf,
    routing: zigraph.Routing = .direct,
};

fn benchmarkGraph(allocator: std.mem.Allocator, node_count: usize, edge_count: usize, config: BenchmarkConfig) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    // Create layered graph structure
    const layers: usize = @max(1, node_count / 10);
    const nodes_per_layer = node_count / layers;

    var node_id: usize = 1;
    for (0..layers) |_| {
        for (0..nodes_per_layer) |_| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{node_id}) catch "?";
            try graph.addNode(node_id, label);
            node_id += 1;
        }
    }

    while (node_id <= node_count) : (node_id += 1) {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{node_id}) catch "?";
        try graph.addNode(node_id, label);
    }

    var edges_added: usize = 0;
    for (0..layers - 1) |layer| {
        const layer_start = layer * nodes_per_layer + 1;
        const next_layer_start = (layer + 1) * nodes_per_layer + 1;

        for (0..nodes_per_layer) |i| {
            if (edges_added >= edge_count) break;

            const from = layer_start + i;
            const to = next_layer_start + (i % nodes_per_layer);
            if (from <= node_count and to <= node_count) {
                try graph.addEdge(from, to);
                edges_added += 1;
            }

            if (edges_added >= edge_count) break;

            const to2 = next_layer_start + ((i + 1) % nodes_per_layer);
            if (from <= node_count and to2 <= node_count) {
                try graph.addEdge(from, to2);
                edges_added += 1;
            }
        }
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{
        .crossing_reducers = config.crossing_reducers,
        .positioning = config.positioning,
        .routing = config.routing,
    });
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

fn benchmarkLinear(allocator: std.mem.Allocator, node_count: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    for (1..node_count) |i| {
        try graph.addEdge(i, i + 1);
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{});
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

fn benchmarkBinaryTree(allocator: std.mem.Allocator, node_count: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    for (1..node_count / 2 + 1) |i| {
        const left = i * 2;
        const right = i * 2 + 1;
        if (left <= node_count) try graph.addEdge(i, left);
        if (right <= node_count) try graph.addEdge(i, right);
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{});
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

fn benchmarkWide(allocator: std.mem.Allocator, node_count: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    for (2..node_count + 1) |i| {
        try graph.addEdge(1, i);
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{});
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

fn benchmarkDiamond(allocator: std.mem.Allocator, node_count: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    const layer_size = 10;
    for (1..node_count - layer_size + 1) |i| {
        if (i + layer_size <= node_count) try graph.addEdge(i, i + layer_size);
        if (i + layer_size + 1 <= node_count) try graph.addEdge(i, i + layer_size + 1);
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{});
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

fn benchmarkRandomDAG(allocator: std.mem.Allocator, node_count: usize, edge_count: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    // Random edges (from lower to higher ID to ensure DAG)
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    var edges_added: usize = 0;
    while (edges_added < edge_count) {
        const from = random.intRangeAtMost(usize, 1, node_count - 1);
        const to = random.intRangeAtMost(usize, from + 1, node_count);
        graph.addEdge(from, to) catch continue;
        edges_added += 1;
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{});
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

const PositioningResults = struct {
    barycentric_us: u64,
    brandes_kopf_us: u64,
};

fn benchmarkPositioning(allocator: std.mem.Allocator, node_count: usize) !PositioningResults {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Build graph
    var graph = zigraph.Graph.init(alloc);
    const layers = 10;
    const nodes_per_layer = node_count / layers;

    var node_id: usize = 1;
    for (0..layers) |_| {
        for (0..nodes_per_layer) |_| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{node_id}) catch "?";
            try graph.addNode(node_id, label);
            node_id += 1;
        }
    }

    for (0..layers - 1) |layer| {
        const layer_start = layer * nodes_per_layer + 1;
        const next_start = (layer + 1) * nodes_per_layer + 1;
        for (0..nodes_per_layer) |i| {
            try graph.addEdge(layer_start + i, next_start + (i % nodes_per_layer));
        }
    }

    // Benchmark barycentric
    const simple_start = std.time.nanoTimestamp();
    var ir1 = try zigraph.layout(&graph, alloc, .{ .positioning = .barycentric });
    _ = &ir1;
    const simple_end = std.time.nanoTimestamp();

    // Benchmark brandes_kopf
    const bk_start = std.time.nanoTimestamp();
    var ir2 = try zigraph.layout(&graph, alloc, .{ .positioning = .brandes_kopf });
    _ = &ir2;
    const bk_end = std.time.nanoTimestamp();

    return .{
        .barycentric_us = @as(u64, @intCast(@divFloor(simple_end - simple_start, 1000))),
        .brandes_kopf_us = @as(u64, @intCast(@divFloor(bk_end - bk_start, 1000))),
    };
}

const CrossingResults = struct {
    none_us: u64,
    fast_us: u64,
    balanced_us: u64,
    quality_us: u64,
};

fn benchmarkCrossingReducers(allocator: std.mem.Allocator, node_count: usize) !CrossingResults {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Build graph
    var graph = zigraph.Graph.init(alloc);
    const layers = 10;
    const nodes_per_layer = node_count / layers;

    var node_id: usize = 1;
    for (0..layers) |_| {
        for (0..nodes_per_layer) |_| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{node_id}) catch "?";
            try graph.addNode(node_id, label);
            node_id += 1;
        }
    }

    for (0..layers - 1) |layer| {
        const layer_start = layer * nodes_per_layer + 1;
        const next_start = (layer + 1) * nodes_per_layer + 1;
        for (0..nodes_per_layer) |i| {
            try graph.addEdge(layer_start + i, next_start + (i % nodes_per_layer));
            try graph.addEdge(layer_start + i, next_start + ((i + 1) % nodes_per_layer));
        }
    }

    // None
    const none_start = std.time.nanoTimestamp();
    var ir1 = try zigraph.layout(&graph, alloc, .{ .crossing_reducers = &zigraph.crossing.none });
    _ = &ir1;
    const none_end = std.time.nanoTimestamp();

    // Fast
    const fast_start = std.time.nanoTimestamp();
    var ir2 = try zigraph.layout(&graph, alloc, .{ .crossing_reducers = &zigraph.crossing.fast });
    _ = &ir2;
    const fast_end = std.time.nanoTimestamp();

    // Balanced
    const balanced_start = std.time.nanoTimestamp();
    var ir3 = try zigraph.layout(&graph, alloc, .{ .crossing_reducers = &zigraph.crossing.balanced });
    _ = &ir3;
    const balanced_end = std.time.nanoTimestamp();

    // Quality
    const quality_start = std.time.nanoTimestamp();
    var ir4 = try zigraph.layout(&graph, alloc, .{ .crossing_reducers = &zigraph.crossing.quality });
    _ = &ir4;
    const quality_end = std.time.nanoTimestamp();

    return .{
        .none_us = @as(u64, @intCast(@divFloor(none_end - none_start, 1000))),
        .fast_us = @as(u64, @intCast(@divFloor(fast_end - fast_start, 1000))),
        .balanced_us = @as(u64, @intCast(@divFloor(balanced_end - balanced_start, 1000))),
        .quality_us = @as(u64, @intCast(@divFloor(quality_end - quality_start, 1000))),
    };
}

const RoutingResults = struct {
    direct_us: u64,
    spline_us: u64,
};

fn benchmarkRouting(allocator: std.mem.Allocator, node_count: usize) !RoutingResults {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Build graph
    var graph = zigraph.Graph.init(alloc);
    const layers = 10;
    const nodes_per_layer = node_count / layers;

    var node_id: usize = 1;
    for (0..layers) |_| {
        for (0..nodes_per_layer) |_| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{node_id}) catch "?";
            try graph.addNode(node_id, label);
            node_id += 1;
        }
    }

    for (0..layers - 1) |layer| {
        const layer_start = layer * nodes_per_layer + 1;
        const next_start = (layer + 1) * nodes_per_layer + 1;
        for (0..nodes_per_layer) |i| {
            try graph.addEdge(layer_start + i, next_start + (i % nodes_per_layer));
        }
    }

    // Direct
    const direct_start = std.time.nanoTimestamp();
    var ir1 = try zigraph.layout(&graph, alloc, .{ .routing = .direct });
    _ = &ir1;
    const direct_end = std.time.nanoTimestamp();

    // Spline
    const spline_start = std.time.nanoTimestamp();
    var ir2 = try zigraph.layout(&graph, alloc, .{ .routing = .spline });
    _ = &ir2;
    const spline_end = std.time.nanoTimestamp();

    return .{
        .direct_us = @as(u64, @intCast(@divFloor(direct_end - direct_start, 1000))),
        .spline_us = @as(u64, @intCast(@divFloor(spline_end - spline_start, 1000))),
    };
}

const RendererResults = struct {
    unicode_us: u64,
    unicode_bytes: usize,
    svg_us: u64,
    svg_bytes: usize,
    json_us: u64,
    json_bytes: usize,
};

fn benchmarkRenderers(allocator: std.mem.Allocator, node_count: usize) !RendererResults {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Build graph and layout once
    var graph = zigraph.Graph.init(alloc);
    const layers = 10;
    const nodes_per_layer = node_count / layers;

    var node_id: usize = 1;
    for (0..layers) |_| {
        for (0..nodes_per_layer) |_| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{node_id}) catch "?";
            try graph.addNode(node_id, label);
            node_id += 1;
        }
    }

    for (0..layers - 1) |layer| {
        const layer_start = layer * nodes_per_layer + 1;
        const next_start = (layer + 1) * nodes_per_layer + 1;
        for (0..nodes_per_layer) |i| {
            try graph.addEdge(layer_start + i, next_start + (i % nodes_per_layer));
        }
    }

    var ir = try zigraph.layout(&graph, alloc, .{});

    // Unicode
    const unicode_start = std.time.nanoTimestamp();
    const unicode_out = try zigraph.unicode.render(&ir, alloc);
    const unicode_end = std.time.nanoTimestamp();

    // SVG
    const svg_start = std.time.nanoTimestamp();
    const svg_out = try zigraph.svg.render(&ir, alloc, .{});
    const svg_end = std.time.nanoTimestamp();

    // JSON
    const json_start = std.time.nanoTimestamp();
    const json_out = try zigraph.json.render(&ir, alloc);
    const json_end = std.time.nanoTimestamp();

    return .{
        .unicode_us = @as(u64, @intCast(@divFloor(unicode_end - unicode_start, 1000))),
        .unicode_bytes = unicode_out.len,
        .svg_us = @as(u64, @intCast(@divFloor(svg_end - svg_start, 1000))),
        .svg_bytes = svg_out.len,
        .json_us = @as(u64, @intCast(@divFloor(json_end - json_start, 1000))),
        .json_bytes = json_out.len,
    };
}

fn benchmarkDiamondMesh(allocator: std.mem.Allocator, node_count: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    const layer_size: usize = 50;
    const num_layers = node_count / layer_size;

    for (0..num_layers - 1) |layer| {
        const layer_start = layer * layer_size + 1;
        const next_start = (layer + 1) * layer_size + 1;

        for (0..layer_size) |i| {
            const from = layer_start + i;
            if (from > node_count) break;

            const to1 = next_start + i;
            const to2 = next_start + ((i + 1) % layer_size);
            if (to1 <= node_count) try graph.addEdge(from, to1);
            if (to2 <= node_count and to2 != to1) try graph.addEdge(from, to2);
        }
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{ .crossing_reducers = &zigraph.crossing.fast });
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

fn benchmarkWideFan(allocator: std.mem.Allocator, node_count: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    for (2..node_count + 1) |i| {
        try graph.addEdge(1, i);
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{ .crossing_reducers = &zigraph.crossing.fast });
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}

fn benchmarkNeuralNet(allocator: std.mem.Allocator, num_layers: usize, nodes_per_layer: usize) !BenchmarkResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = zigraph.Graph.init(alloc);

    const total_nodes = num_layers * nodes_per_layer;

    for (1..total_nodes + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    // Fully connected layers
    for (0..num_layers - 1) |layer| {
        const layer_start = layer * nodes_per_layer + 1;
        const next_start = (layer + 1) * nodes_per_layer + 1;

        for (0..nodes_per_layer) |i| {
            for (0..nodes_per_layer) |j| {
                const from = layer_start + i;
                const to = next_start + j;
                try graph.addEdge(from, to);
            }
        }
    }

    const layout_start = std.time.nanoTimestamp();
    var ir = try zigraph.layout(&graph, alloc, .{ .crossing_reducers = &zigraph.crossing.fast });
    const layout_end = std.time.nanoTimestamp();

    const render_start = std.time.nanoTimestamp();
    _ = try zigraph.unicode.render(&ir, alloc);
    const render_end = std.time.nanoTimestamp();

    return .{
        .nodes = graph.nodeCount(),
        .edges = graph.edges.items.len,
        .layout_us = @as(u64, @intCast(@divFloor(layout_end - layout_start, 1000))),
        .render_us = @as(u64, @intCast(@divFloor(render_end - render_start, 1000))),
    };
}
