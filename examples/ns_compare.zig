const std = @import("std");
const zigraph = @import("zigraph");

/// Number of iterations for the benchmark section (median is reported).
const bench_iterations = 5;

/// Simple deterministic RNG (same as stress_test.zig)
const SimpleRng = struct {
    state: u64,

    fn init(seed: u64) SimpleRng {
        return .{ .state = seed };
    }

    fn next(self: *SimpleRng) u64 {
        self.state = self.state *% 6364136223846793005 +% 1;
        return self.state;
    }

    fn range(self: *SimpleRng, min: usize, max: usize) usize {
        const r = max - min;
        if (r == 0) return min;
        return min + @as(usize, @intCast(self.next() % @as(u64, @intCast(r))));
    }
};

/// A simple allocator wrapper that tracks peak memory usage.
const CountingAllocator = struct {
    parent: std.mem.Allocator,
    current_bytes: usize = 0,
    peak_bytes: usize = 0,
    total_allocations: usize = 0,

    const Alignment = std.mem.Alignment;

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    fn remap(ctx: *anyopaque, buf: []u8, log2_align: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawRemap(buf, log2_align, new_len, ret_addr);
        if (result != null) {
            if (new_len > buf.len) {
                self.current_bytes += (new_len - buf.len);
                self.peak_bytes = @max(self.peak_bytes, self.current_bytes);
            } else {
                self.current_bytes -|= (buf.len - new_len);
            }
        }
        return result;
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_align: Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawAlloc(len, log2_align, ret_addr);
        if (result != null) {
            self.current_bytes += len;
            self.peak_bytes = @max(self.peak_bytes, self.current_bytes);
            self.total_allocations += 1;
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_align: Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (self.parent.rawResize(buf, log2_align, new_len, ret_addr)) {
            if (new_len > buf.len) {
                self.current_bytes += (new_len - buf.len);
                self.peak_bytes = @max(self.peak_bytes, self.current_bytes);
            } else {
                self.current_bytes -= (buf.len - new_len);
            }
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_align: Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(buf, log2_align, ret_addr);
        self.current_bytes -|= buf.len;
    }

    fn reset(self: *CountingAllocator) void {
        self.current_bytes = 0;
        self.peak_bytes = 0;
        self.total_allocations = 0;
    }

    fn formatPeak(bytes: usize) struct { val: f64, unit: []const u8 } {
        if (bytes >= 1024 * 1024) {
            return .{ .val = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0), .unit = "MB" };
        } else if (bytes >= 1024) {
            return .{ .val = @as(f64, @floatFromInt(bytes)) / 1024.0, .unit = "KB" };
        } else {
            return .{ .val = @as(f64, @floatFromInt(bytes)), .unit = "B" };
        }
    }
};

/// Compute total edge span from the LayoutIR (sum of level differences).
fn totalEdgeSpan(ir: *const zigraph.LayoutIR) usize {
    var total: usize = 0;
    for (ir.edges.items) |edge| {
        var from_level: usize = 0;
        var to_level: usize = 0;
        for (ir.nodes.items) |node| {
            if (node.id == edge.from_id) from_level = node.level;
            if (node.id == edge.to_id) to_level = node.level;
        }
        if (to_level > from_level) {
            total += to_level - from_level;
        }
    }
    return total;
}

/// Count dummy nodes in the LayoutIR.
fn dummyNodeCount(ir: *const zigraph.LayoutIR) usize {
    var count: usize = 0;
    for (ir.nodes.items) |node| {
        if (node.kind == .dummy) count += 1;
    }
    return count;
}

/// Result from a single layering run
const LayeringResult = struct {
    width: usize,
    height: usize,
    levels: usize,
    edge_span: usize,
    dummies: usize,
    layout_us: u64,
    peak_mem: usize, // peak memory in bytes
};

/// Helper: build a graph, run all 3 layerings, print comparison
/// If show_render is true, prints the full rendering; otherwise just metrics.
fn compareLayerings(
    allocator: std.mem.Allocator,
    dag: *zigraph.Graph,
    title: []const u8,
    show_render: bool,
) !void {
    std.debug.print("\n============================================================\n", .{});
    std.debug.print("  {s}\n", .{title});
    std.debug.print("  ({d} nodes, {d} edges)\n", .{ dag.nodeCount(), dag.edges.items.len });
    std.debug.print("============================================================\n", .{});

    const layering_names = [_][]const u8{ "LONGEST PATH", "NETWORK SIMPLEX", "NS FAST" };
    const layering_vals = [_]zigraph.Layering{ .longest_path, .network_simplex, .network_simplex_fast };

    var results: [3]LayeringResult = undefined;

    for (0..3) |idx| {
        var counting = CountingAllocator{ .parent = allocator };
        const tracked = counting.allocator();
        const t_start = std.time.nanoTimestamp();
        var ir = try zigraph.layout(dag, tracked, .{
            .layering = layering_vals[idx],
            .crossing_reducers = &zigraph.crossing.quality,
            .node_spacing = 4,
        });
        const t_end = std.time.nanoTimestamp();
        defer ir.deinit();

        const layout_us = @as(u64, @intCast(t_end - t_start)) / 1000;
        const span = totalEdgeSpan(&ir);
        const dummies = dummyNodeCount(&ir);
        results[idx] = .{
            .width = ir.width,
            .height = ir.height,
            .levels = ir.level_count,
            .edge_span = span,
            .dummies = dummies,
            .layout_us = layout_us,
            .peak_mem = counting.peak_bytes,
        };

        if (show_render) {
            std.debug.print("\n--- {s} ---\n\n", .{layering_names[idx]});
            const output = try zigraph.unicode.renderWithConfig(&ir, allocator, .{
                .edge_palette = &zigraph.colors.ansi_dark,
            });
            defer allocator.free(output);
            std.debug.print("{s}\n", .{output});
        }
    }

    // Always print summary table
    std.debug.print("\n  {s:<20} {s:>6} {s:>6} {s:>7} {s:>10} {s:>8} {s:>12} {s:>10}\n", .{
        "Algorithm", "Width", "Height", "Levels", "Edge Span", "Dummies", "Layout (µs)", "Peak Mem",
    });
    std.debug.print("  -------------------- ------ ------ ------- ---------- -------- ------------ ----------\n", .{});
    for (0..3) |idx| {
        const r = results[idx];
        const mem = CountingAllocator.formatPeak(r.peak_mem);
        std.debug.print("  {s:<20} {d:>6} {d:>6} {d:>7} {d:>10} {d:>8} {d:>12} {d:>7.1}{s}\n", .{
            layering_names[idx], r.width, r.height, r.levels, r.edge_span, r.dummies, r.layout_us, mem.val, mem.unit,
        });
    }

    // Highlight differences
    if (results[0].edge_span != results[1].edge_span or results[0].levels != results[1].levels) {
        std.debug.print("\n  ⚡ Network simplex found a DIFFERENT layering!\n", .{});
        if (results[1].edge_span < results[0].edge_span) {
            const saved = results[0].edge_span - results[1].edge_span;
            std.debug.print("     NS saved {d} edge span ({d} → {d})\n", .{ saved, results[0].edge_span, results[1].edge_span });
        }
        if (results[1].dummies < results[0].dummies) {
            const saved = results[0].dummies - results[1].dummies;
            std.debug.print("     NS eliminated {d} dummy nodes ({d} → {d})\n", .{ saved, results[0].dummies, results[1].dummies });
        }
    } else {
        std.debug.print("\n  ✓ All algorithms agree (LP is already optimal)\n", .{});
    }

    // Timing comparison
    if (results[1].layout_us > 0 and results[0].layout_us > 0) {
        if (results[1].layout_us > results[0].layout_us) {
            const ratio = @as(f64, @floatFromInt(results[1].layout_us)) / @as(f64, @floatFromInt(results[0].layout_us));
            std.debug.print("  ⏱  NS is {d:.1}× slower than LP ({d} µs vs {d} µs)\n", .{ ratio, results[1].layout_us, results[0].layout_us });
        } else if (results[0].layout_us > results[1].layout_us) {
            const ratio = @as(f64, @floatFromInt(results[0].layout_us)) / @as(f64, @floatFromInt(results[1].layout_us));
            std.debug.print("  ⏱  NS is {d:.1}× faster than LP ({d} µs vs {d} µs)\n", .{ ratio, results[1].layout_us, results[0].layout_us });
        } else {
            std.debug.print("  ⏱  NS and LP took the same time ({d} µs)\n", .{results[0].layout_us});
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Graph 1: Chain + skip edge (small, show render) ──
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();
        try dag.addNode(1, "A");
        try dag.addNode(2, "B");
        try dag.addNode(3, "C");
        try dag.addNode(4, "D");
        try dag.addEdge(1, 2);
        try dag.addEdge(2, 3);
        try dag.addEdge(3, 4);
        try dag.addEdge(1, 4);
        try compareLayerings(allocator, &dag, "Graph 1: Chain + skip edge", true);
    }

    // ── Graph 2: Cross-level nightmare (skip edges galore) ──
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();
        try dag.addNode(0, "Root");
        try dag.addNode(1, "A1");
        try dag.addNode(2, "B1");
        try dag.addNode(3, "C1");
        try dag.addNode(4, "A2");
        try dag.addNode(5, "B2");
        try dag.addNode(6, "C2");
        try dag.addNode(7, "A3");
        try dag.addNode(8, "B3");
        try dag.addNode(9, "Sink");
        // Backbone edges
        try dag.addEdge(0, 1);
        try dag.addEdge(0, 2);
        try dag.addEdge(0, 3);
        try dag.addEdge(1, 4);
        try dag.addEdge(2, 5);
        try dag.addEdge(3, 6);
        try dag.addEdge(4, 7);
        try dag.addEdge(5, 8);
        try dag.addEdge(6, 8);
        try dag.addEdge(7, 9);
        try dag.addEdge(8, 9);
        // Skip edges
        try dag.addEdge(0, 5); // Root → B2 (skip 1)
        try dag.addEdge(0, 7); // Root → A3 (skip 2)
        try dag.addEdge(1, 8); // A1 → B3 (skip 1)
        try dag.addEdge(3, 7); // C1 → A3 (skip 1)
        try dag.addEdge(2, 9); // B1 → Sink (skip 2)
        try dag.addEdge(4, 9); // A2 → Sink (skip 1)
        try compareLayerings(allocator, &dag, "Graph 2: Cross-level nightmare (17 edges, many skips)", true);
    }

    // ── Graph 3: Random hairball (30 nodes) — metrics only ──
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();
        var rng = SimpleRng.init(42);
        const n: usize = 30;
        for (0..n) |i| {
            try dag.addNode(i, "H");
        }
        for (0..n) |i| {
            const edge_count = rng.range(1, 4);
            for (0..edge_count) |_| {
                if (i + 1 < n) {
                    const target = rng.range(i + 1, n);
                    if (target < n) {
                        dag.addEdge(i, target) catch {};
                    }
                }
            }
        }
        try compareLayerings(allocator, &dag, "Graph 3: Random Hairball (30 nodes, seed=42)", true);
    }

    // ── Graph 4: Bigger hairball (50 nodes) — metrics only ──
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();
        var rng = SimpleRng.init(137);
        const n: usize = 50;
        for (0..n) |i| {
            try dag.addNode(i, "N");
        }
        for (0..n) |i| {
            const edge_count = rng.range(1, 5); // 1-4 edges per node
            for (0..edge_count) |_| {
                if (i + 1 < n) {
                    const target = rng.range(i + 1, n);
                    if (target < n) {
                        dag.addEdge(i, target) catch {};
                    }
                }
            }
        }
        try compareLayerings(allocator, &dag, "Graph 4: Bigger Hairball (50 nodes, seed=137)", false);
    }

    // ── Graph 5: Sparse hairball (100 nodes, 1-2 edges each) ──
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();
        var rng = SimpleRng.init(256);
        const n: usize = 100;
        for (0..n) |i| {
            try dag.addNode(i, "X");
        }
        for (0..n) |i| {
            const edge_count = rng.range(1, 3); // 1-2 edges
            for (0..edge_count) |_| {
                if (i + 1 < n) {
                    const target = rng.range(i + 1, n);
                    if (target < n) {
                        dag.addEdge(i, target) catch {};
                    }
                }
            }
        }
        try compareLayerings(allocator, &dag, "Graph 5: Sparse Hairball (100 nodes, seed=256)", false);
    }

    // =====================================================================
    //  BENCHMARK: Multi-iteration timing for stable numbers
    // =====================================================================
    std.debug.print("\n\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Layering Algorithm Benchmark  (Sugiyama full pipeline)                 ║\n", .{});
    std.debug.print("║  Each entry = median of {d} iterations                                  ║\n", .{bench_iterations});
    std.debug.print("╚══════════════════════════════════════════════════════════════════════════╝\n", .{});

    const bench_configs = [_]struct { nodes: usize, edges_per_node: usize, seed: u64 }{
        .{ .nodes = 20, .edges_per_node = 2, .seed = 1 },
        .{ .nodes = 50, .edges_per_node = 2, .seed = 2 },
        .{ .nodes = 100, .edges_per_node = 2, .seed = 3 },
        .{ .nodes = 200, .edges_per_node = 3, .seed = 4 },
    };

    std.debug.print("\n  {s:<8} {s:>6} {s:>14} {s:>14} {s:>14} {s:>10} {s:>10} {s:>10} {s:>10}\n", .{
        "Nodes", "Edges", "LP (µs)", "NS (µs)", "NS_fast (µs)", "Ratio", "LP Mem", "NS Mem", "NSf Mem",
    });
    std.debug.print("  -------- ------ -------------- -------------- -------------- ---------- ---------- ---------- ----------\n", .{});

    for (bench_configs) |cfg| {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();
        var rng = SimpleRng.init(cfg.seed);
        for (0..cfg.nodes) |i| {
            try dag.addNode(i, "B");
        }
        for (0..cfg.nodes) |i| {
            for (0..cfg.edges_per_node) |_| {
                if (i + 1 < cfg.nodes) {
                    const target = rng.range(i + 1, cfg.nodes);
                    if (target < cfg.nodes) {
                        dag.addEdge(i, target) catch {};
                    }
                }
            }
        }

        const layerings = [_]zigraph.Layering{ .longest_path, .network_simplex, .network_simplex_fast };
        var medians: [3]u64 = undefined;
        var peak_mems: [3]usize = undefined;

        for (layerings, 0..) |lay, li| {
            var timings: [bench_iterations]u64 = undefined;
            var max_peak: usize = 0;
            for (0..bench_iterations) |it| {
                var counting = CountingAllocator{ .parent = allocator };
                const tracked = counting.allocator();
                const t0 = std.time.nanoTimestamp();
                var ir = try zigraph.layout(&dag, tracked, .{
                    .layering = lay,
                    .crossing_reducers = &zigraph.crossing.quality,
                    .node_spacing = 4,
                });
                const t1 = std.time.nanoTimestamp();
                ir.deinit();
                timings[it] = @as(u64, @intCast(t1 - t0)) / 1000;
                max_peak = @max(max_peak, counting.peak_bytes);
            }
            // Sort and take median
            std.mem.sort(u64, &timings, {}, std.sort.asc(u64));
            medians[li] = timings[bench_iterations / 2];
            peak_mems[li] = max_peak;
        }

        const ratio = if (medians[0] > 0)
            @as(f64, @floatFromInt(medians[1])) / @as(f64, @floatFromInt(medians[0]))
        else
            0.0;

        const lp_mem = CountingAllocator.formatPeak(peak_mems[0]);
        const ns_mem = CountingAllocator.formatPeak(peak_mems[1]);
        const nsf_mem = CountingAllocator.formatPeak(peak_mems[2]);

        std.debug.print("  {d:<8} {d:>6} {d:>14} {d:>14} {d:>14} {d:>9.1}× {d:>7.1}{s} {d:>7.1}{s} {d:>7.1}{s}\n", .{
            cfg.nodes,
            dag.edgeCount(),
            medians[0],
            medians[1],
            medians[2],
            ratio,
            lp_mem.val,
            lp_mem.unit,
            ns_mem.val,
            ns_mem.unit,
            nsf_mem.val,
            nsf_mem.unit,
        });
    }

    std.debug.print("\n  LP = Longest Path, NS = Network Simplex, NS_fast = NS (fast variant)\n", .{});
    std.debug.print("  Ratio > 1.0 means NS is slower; < 1.0 means NS is faster.\n", .{});
    std.debug.print("  NS typically produces fewer levels & dummies at the cost of more time.\n\n", .{});
}
