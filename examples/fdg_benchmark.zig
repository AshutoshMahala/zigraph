//! Benchmark: Force-Directed Graph (FDG) layout performance
//!
//! Measures FR standard (O(N²)) and FR-fast/Barnes-Hut (O(N log N))
//! across various graph sizes and topologies.
//!
//! Sections:
//! 1. Size scaling — FR vs FR-Fast at 10 to 5000 nodes
//! 2. Topology comparison — ring, star, grid, random
//! 3. Convergence — iterations to reach equilibrium
//! 4. Memory estimation — peak allocator usage via arena high-water mark
//!
//! Run with: zig build run-fdg-bench

const std = @import("std");
const zigraph = @import("zigraph");

const fr = zigraph.fdg.fruchterman_reingold;
const fp = zigraph.fdg.fixed_point;
const FP = fp.FP;

const FdgBenchResult = struct {
    nodes: usize,
    edges: usize,
    fr_us: u64,
    fr_fast_us: u64,
    fr_iters: u32,
    fr_fast_iters: u32,
    fr_mem_bytes: usize,
    fr_fast_mem_bytes: usize,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  zigraph FDG Performance Benchmark                                        ║\n", .{});
    std.debug.print("║  FR = Fruchterman-Reingold O(N²) · FR-Fast = Barnes-Hut O(N log N)        ║\n", .{});
    std.debug.print("║  Run with: zig build run-fdg-bench                                        ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // Warm up
    std.debug.print("Warming up...\n\n", .{});
    _ = try benchmarkRing(allocator, 10);

    // =========================================================================
    // 1. SIZE SCALING
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  1. SIZE SCALING (ring graph, ~2 edges per node)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const sizes = [_]usize{ 10, 25, 50, 100, 250, 500, 1000, 2500, 5000 };
    var scale_results: [sizes.len]FdgBenchResult = undefined;

    for (sizes, 0..) |n, i| {
        scale_results[i] = try benchmarkRing(allocator, n);
    }

    printSizeTable(&scale_results);

    // =========================================================================
    // 2. TOPOLOGY COMPARISON
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  2. TOPOLOGY COMPARISON (200 nodes)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const topo_n: usize = 200;
    const topo_results = [_]struct { name: []const u8, result: FdgBenchResult }{
        .{ .name = "Ring (cycle)        ", .result = try benchmarkRing(allocator, topo_n) },
        .{ .name = "Star (hub → N)      ", .result = try benchmarkStar(allocator, topo_n) },
        .{ .name = "Grid (√N × √N mesh) ", .result = try benchmarkGrid(allocator, topo_n) },
        .{ .name = "Random (3 edges/node)", .result = try benchmarkRandom(allocator, topo_n, 3) },
        .{ .name = "Complete bipartite   ", .result = try benchmarkBipartite(allocator, topo_n) },
        .{ .name = "Disconnected clusters", .result = try benchmarkClusters(allocator, topo_n) },
    };

    std.debug.print("┌───────────────────────┬────────┬──────────────┬──────────────┬───────┬───────┐\n", .{});
    std.debug.print("│  Topology             │  Edges │  FR (µs)     │  FR-Fast(µs) │  FR i │  FF i │\n", .{});
    std.debug.print("├───────────────────────┼────────┼──────────────┼──────────────┼───────┼───────┤\n", .{});

    for (topo_results) |t| {
        std.debug.print("│ {s} │ {d:>6} │ {d:>12} │ {d:>12} │ {d:>5} │ {d:>5} │\n", .{
            t.name,
            t.result.edges,
            t.result.fr_us,
            t.result.fr_fast_us,
            t.result.fr_iters,
            t.result.fr_fast_iters,
        });
    }

    std.debug.print("└───────────────────────┴────────┴──────────────┴──────────────┴───────┴───────┘\n\n", .{});

    // =========================================================================
    // 3. CONVERGENCE (iteration count vs node count)
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  3. CONVERGENCE (iterations to equilibrium, ring graph)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    std.debug.print("┌──────────┬──────────────┬──────────────┬──────────────┬──────────────┐\n", .{});
    std.debug.print("│   Nodes  │  FR iters    │  FR-Fast it  │  FR µs/iter  │  FF µs/iter  │\n", .{});
    std.debug.print("├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤\n", .{});

    for (sizes) |n| {
        // We already have these results from section 1
        const r = try benchmarkRing(allocator, n);
        const fr_per = if (r.fr_iters > 0) r.fr_us / @as(u64, r.fr_iters) else 0;
        const ff_per = if (r.fr_fast_iters > 0) r.fr_fast_us / @as(u64, r.fr_fast_iters) else 0;

        std.debug.print("│ {d:>8} │ {d:>12} │ {d:>12} │ {d:>12} │ {d:>12} │\n", .{
            n, r.fr_iters, r.fr_fast_iters, fr_per, ff_per,
        });
    }

    std.debug.print("└──────────┴──────────────┴──────────────┴──────────────┴──────────────┘\n\n", .{});

    // =========================================================================
    // 4. MEMORY USAGE
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  4. MEMORY USAGE (ring graph, arena high-water mark)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    std.debug.print("┌──────────┬──────────────┬──────────────┬──────────────┬──────────────┐\n", .{});
    std.debug.print("│   Nodes  │  FR (bytes)  │  FR-F(bytes) │  FR bytes/N  │  FF bytes/N  │\n", .{});
    std.debug.print("├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤\n", .{});

    for (sizes) |n| {
        const r = try benchmarkRingWithMemory(allocator, n);
        const fr_per_n = if (n > 0) r.fr_mem_bytes / n else 0;
        const ff_per_n = if (n > 0) r.fr_fast_mem_bytes / n else 0;

        std.debug.print("│ {d:>8} │ {d:>12} │ {d:>12} │ {d:>12} │ {d:>12} │\n", .{
            n, r.fr_mem_bytes, r.fr_fast_mem_bytes, fr_per_n, ff_per_n,
        });
    }

    std.debug.print("└──────────┴──────────────┴──────────────┴──────────────┴──────────────┘\n\n", .{});

    // =========================================================================
    // 5. FR vs FR-FAST SPEEDUP
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  5. SPEEDUP: FR-Fast / FR (ring graph)\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    std.debug.print("┌──────────┬──────────────┬──────────────┬────────────┐\n", .{});
    std.debug.print("│   Nodes  │  FR (µs)     │  FR-Fast(µs) │  Speedup   │\n", .{});
    std.debug.print("├──────────┼──────────────┼──────────────┼────────────┤\n", .{});

    for (sizes) |n| {
        const r = try benchmarkRing(allocator, n);
        const speedup_10x = if (r.fr_fast_us > 0) (r.fr_us * 10) / r.fr_fast_us else 0;

        std.debug.print("│ {d:>8} │ {d:>12} │ {d:>12} │ {d:>7}.{d}×  │\n", .{
            n, r.fr_us, r.fr_fast_us, speedup_10x / 10, speedup_10x % 10,
        });
    }

    std.debug.print("└──────────┴──────────────┴──────────────┴────────────┘\n\n", .{});

    // =========================================================================
    // SUMMARY
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("  SUMMARY\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    std.debug.print("Complexity:\n", .{});
    std.debug.print("  • FR standard:   O(N² × iters)  — exact pairwise repulsion\n", .{});
    std.debug.print("  • FR-Fast (BH):  O(N log N × iters) — Barnes-Hut approximation (θ=0.8)\n", .{});
    std.debug.print("  • Memory:        O(N) for positions + O(N) for quadtree (FR-Fast only)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Recommendations:\n", .{});
    std.debug.print("  • ≤500 nodes:   FR standard gives highest quality\n", .{});
    std.debug.print("  • 500-5000:     FR-Fast (Barnes-Hut) for practical speed\n", .{});
    std.debug.print("  • >5000:        FR-Fast with reduced iterations or cooling\n", .{});
    std.debug.print("  • Dense graphs: More edges → more attractive forces → faster convergence\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("=== FDG Benchmark Complete ===\n\n", .{});
}

// ============================================================================
// SIZE TABLE PRINTER
// ============================================================================

fn printSizeTable(results: []const FdgBenchResult) void {
    std.debug.print("┌──────────┬──────────┬──────────────┬──────────────┬──────────────┬──────────────┐\n", .{});
    std.debug.print("│   Nodes  │   Edges  │  FR (µs)     │  FR-Fast(µs) │  FR iters    │  FF iters    │\n", .{});
    std.debug.print("├──────────┼──────────┼──────────────┼──────────────┼──────────────┼──────────────┤\n", .{});

    for (results) |r| {
        std.debug.print("│ {d:>8} │ {d:>8} │ {d:>12} │ {d:>12} │ {d:>12} │ {d:>12} │\n", .{
            r.nodes, r.edges, r.fr_us, r.fr_fast_us, r.fr_iters, r.fr_fast_iters,
        });
    }

    std.debug.print("└──────────┴──────────┴──────────────┴──────────────┴──────────────┴──────────────┘\n\n", .{});
}

// ============================================================================
// GRAPH GENERATORS
// ============================================================================

/// Build a ring (cycle) graph: 1→2→3→...→N→1
fn buildRing(alloc: std.mem.Allocator, n: usize) !zigraph.Graph {
    var graph = zigraph.Graph.init(alloc);
    for (1..n + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    for (1..n) |i| {
        try graph.addEdge(i, i + 1);
    }
    try graph.addEdge(n, 1); // close the ring
    return graph;
}

/// Build a star graph: hub (1) → 2, 3, ..., N
fn buildStar(alloc: std.mem.Allocator, n: usize) !zigraph.Graph {
    var graph = zigraph.Graph.init(alloc);
    for (1..n + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    for (2..n + 1) |i| {
        try graph.addEdge(1, i);
    }
    return graph;
}

/// Build a 2D grid mesh: approximately √N × √N with 4-connectivity
fn buildGrid(alloc: std.mem.Allocator, n: usize) !zigraph.Graph {
    var graph = zigraph.Graph.init(alloc);
    const side = @as(usize, @intFromFloat(@ceil(@sqrt(@as(f64, @floatFromInt(n))))));

    // First pass: add all nodes
    for (1..n + 1) |id| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{id}) catch "?";
        try graph.addNode(id, label);
    }

    // Second pass: add grid edges
    for (0..side) |row| {
        for (0..side) |col| {
            const id = row * side + col + 1;
            if (id > n) break;

            // Connect to right neighbor
            const right = id + 1;
            if (col + 1 < side and right <= n) {
                try graph.addEdge(id, right);
            }
            // Connect to bottom neighbor
            const below = id + side;
            if (row + 1 < side and below <= n) {
                try graph.addEdge(id, below);
            }
        }
    }
    return graph;
}

/// Build a random graph with `edges_per_node` edges per node (deterministic via LCG)
fn buildRandom(alloc: std.mem.Allocator, n: usize, edges_per_node: usize) !zigraph.Graph {
    var graph = zigraph.Graph.init(alloc);
    for (1..n + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    // Deterministic pseudo-random (LCG)
    var rng: u64 = 12345;
    for (1..n + 1) |from| {
        for (0..edges_per_node) |_| {
            rng = rng *% 6364136223846793005 +% 1442695040888963407;
            const to = (rng >> 33) % n + 1;
            if (to != from) {
                graph.addEdge(from, to) catch {}; // ignore duplicates
            }
        }
    }
    return graph;
}

/// Build a complete bipartite graph: K(N/2, N/2)
fn buildBipartite(alloc: std.mem.Allocator, n: usize) !zigraph.Graph {
    var graph = zigraph.Graph.init(alloc);
    const half = n / 2;
    for (1..n + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    // Edges from partition A [1..half] to partition B [half+1..n]
    for (1..half + 1) |a| {
        for (half + 1..n + 1) |b| {
            try graph.addEdge(a, b);
        }
    }
    return graph;
}

/// Build disconnected clusters: 4 clusters of N/4 nodes each (ring inside each)
fn buildClusters(alloc: std.mem.Allocator, n: usize) !zigraph.Graph {
    var graph = zigraph.Graph.init(alloc);
    const cluster_size = @max(2, n / 4);
    var id: usize = 1;

    for (0..4) |_| {
        const cluster_start = id;
        for (0..cluster_size) |_| {
            if (id > n) break;
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{id}) catch "?";
            try graph.addNode(id, label);
            if (id > cluster_start) {
                try graph.addEdge(id - 1, id);
            }
            id += 1;
        }
        // Close the cluster ring
        if (id - 1 > cluster_start) {
            graph.addEdge(id - 1, cluster_start) catch {};
        }
    }
    return graph;
}

// ============================================================================
// BENCHMARK RUNNERS
// ============================================================================

const bench_config: fr.Config = .{ .seed = 42 };

fn benchmarkRing(allocator: std.mem.Allocator, n: usize) !FdgBenchResult {
    return benchmarkWithTopology(allocator, n, .ring);
}

fn benchmarkStar(allocator: std.mem.Allocator, n: usize) !FdgBenchResult {
    return benchmarkWithTopology(allocator, n, .star);
}

fn benchmarkGrid(allocator: std.mem.Allocator, n: usize) !FdgBenchResult {
    return benchmarkWithTopology(allocator, n, .grid);
}

fn benchmarkBipartite(allocator: std.mem.Allocator, n: usize) !FdgBenchResult {
    return benchmarkWithTopology(allocator, n, .bipartite);
}

fn benchmarkClusters(allocator: std.mem.Allocator, n: usize) !FdgBenchResult {
    return benchmarkWithTopology(allocator, n, .clusters);
}

fn benchmarkRandom(allocator: std.mem.Allocator, n: usize, epn: usize) !FdgBenchResult {
    _ = epn;
    return benchmarkWithTopology(allocator, n, .random);
}

const Topology = enum { ring, star, grid, random, bipartite, clusters };

fn benchmarkWithTopology(allocator: std.mem.Allocator, n: usize, topo: Topology) !FdgBenchResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = switch (topo) {
        .ring => try buildRing(alloc, n),
        .star => try buildStar(alloc, n),
        .grid => try buildGrid(alloc, n),
        .random => try buildRandom(alloc, n, 3),
        .bipartite => try buildBipartite(alloc, n),
        .clusters => try buildClusters(alloc, n),
    };

    const edge_count = graph.edges.items.len;

    // --- FR standard ---
    const fr_start = std.time.nanoTimestamp();
    var r1 = try fr.compute(&graph, alloc, bench_config);
    const fr_end = std.time.nanoTimestamp();
    const fr_iters = r1.iterations;
    r1.deinit();

    // --- FR fast (Barnes-Hut) ---
    const ff_start = std.time.nanoTimestamp();
    var r2 = try fr.computeFast(&graph, alloc, bench_config);
    const ff_end = std.time.nanoTimestamp();
    const ff_iters = r2.iterations;
    r2.deinit();

    return .{
        .nodes = n,
        .edges = edge_count,
        .fr_us = @intCast(@divFloor(fr_end - fr_start, 1000)),
        .fr_fast_us = @intCast(@divFloor(ff_end - ff_start, 1000)),
        .fr_iters = fr_iters,
        .fr_fast_iters = ff_iters,
        .fr_mem_bytes = 0,
        .fr_fast_mem_bytes = 0,
    };
}

/// Benchmark with memory tracking using separate arenas for FR and FR-Fast
fn benchmarkRingWithMemory(allocator: std.mem.Allocator, n: usize) !FdgBenchResult {
    // --- Build graph in its own arena ---
    var graph_arena = std.heap.ArenaAllocator.init(allocator);
    defer graph_arena.deinit();
    var graph = try buildRing(graph_arena.allocator(), n);
    const edge_count = graph.edges.items.len;

    // --- FR standard: measure memory via counting wrapper ---
    const fr_mem = blk: {
        var counting = CountingAllocator.init(allocator);
        var fr_arena = std.heap.ArenaAllocator.init(counting.allocator());
        var r1 = try fr.compute(&graph, fr_arena.allocator(), bench_config);
        const peak = counting.peak_bytes;
        r1.deinit();
        fr_arena.deinit();
        break :blk peak;
    };

    const fr_start = std.time.nanoTimestamp();
    var r1 = blk: {
        var tmp_arena = std.heap.ArenaAllocator.init(allocator);
        break :blk .{ try fr.compute(&graph, tmp_arena.allocator(), bench_config), tmp_arena };
    };
    const fr_end = std.time.nanoTimestamp();
    const fr_iters = r1[0].iterations;
    r1[0].deinit();
    r1[1].deinit();

    // --- FR fast: measure memory via counting wrapper ---
    const ff_mem = blk: {
        var counting = CountingAllocator.init(allocator);
        var ff_arena = std.heap.ArenaAllocator.init(counting.allocator());
        var r2 = try fr.computeFast(&graph, ff_arena.allocator(), bench_config);
        const peak = counting.peak_bytes;
        r2.deinit();
        ff_arena.deinit();
        break :blk peak;
    };

    const ff_start = std.time.nanoTimestamp();
    var r2 = blk: {
        var tmp_arena = std.heap.ArenaAllocator.init(allocator);
        break :blk .{ try fr.computeFast(&graph, tmp_arena.allocator(), bench_config), tmp_arena };
    };
    const ff_end = std.time.nanoTimestamp();
    const ff_iters = r2[0].iterations;
    r2[0].deinit();
    r2[1].deinit();

    return .{
        .nodes = n,
        .edges = edge_count,
        .fr_us = @intCast(@divFloor(fr_end - fr_start, 1000)),
        .fr_fast_us = @intCast(@divFloor(ff_end - ff_start, 1000)),
        .fr_iters = fr_iters,
        .fr_fast_iters = ff_iters,
        .fr_mem_bytes = fr_mem,
        .fr_fast_mem_bytes = ff_mem,
    };
}

/// Simple allocator wrapper that tracks peak memory usage.
const CountingAllocator = struct {
    backing: std.mem.Allocator,
    current_bytes: usize,
    peak_bytes: usize,

    fn init(backing: std.mem.Allocator) CountingAllocator {
        return .{ .backing = backing, .current_bytes = 0, .peak_bytes = 0 };
    }

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = cAlloc,
        .resize = cResize,
        .free = cFree,
        .remap = cRemap,
    };

    fn cAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.backing.rawAlloc(len, alignment, ret_addr);
        if (result != null) {
            self.current_bytes += len;
            if (self.current_bytes > self.peak_bytes) {
                self.peak_bytes = self.current_bytes;
            }
        }
        return result;
    }

    fn cResize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const old_len = memory.len;
        if (self.backing.rawResize(memory, alignment, new_len, ret_addr)) {
            if (new_len > old_len) {
                self.current_bytes += (new_len - old_len);
            } else {
                self.current_bytes -= (old_len - new_len);
            }
            if (self.current_bytes > self.peak_bytes) {
                self.peak_bytes = self.current_bytes;
            }
            return true;
        }
        return false;
    }

    fn cFree(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.current_bytes -= memory.len;
        self.backing.rawFree(memory, alignment, ret_addr);
    }

    fn cRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const old_len = memory.len;
        const result = self.backing.rawRemap(memory, alignment, new_len, ret_addr);
        if (result != null) {
            if (new_len > old_len) {
                self.current_bytes += (new_len - old_len);
            } else {
                self.current_bytes -= (old_len - new_len);
            }
            if (self.current_bytes > self.peak_bytes) {
                self.peak_bytes = self.current_bytes;
            }
        }
        return result;
    }
};
