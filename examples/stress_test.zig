//! Stress test suite for zigraph
//!
//! Tests various graph topologies to stress the layout engine.
//! Generates both terminal (Unicode) and SVG output.
//!
//! Run with: zig build run-stress

const std = @import("std");
const zigraph = @import("zigraph");

// Simple LCG random number generator (no dependencies)
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\=== zigraph Stress Test Suite ===
        \\
        \\
    , .{});

    const tests = [_]struct {
        name: []const u8,
        func: *const fn (std.mem.Allocator) anyerror!zigraph.Graph,
        show_output: bool,
        export_svg: bool,
    }{
        .{ .name = "The Double Helix", .func = testDoubleHelix, .show_output = true, .export_svg = true },
        .{ .name = "The Skyscraper (50 floors)", .func = testSkyscraper, .show_output = false, .export_svg = false },
        .{ .name = "The Wide Fan (50 workers)", .func = testWideFan, .show_output = true, .export_svg = true },
        .{ .name = "The Diamond Lattice (5x10)", .func = testDiamondLattice, .show_output = true, .export_svg = true },
        .{ .name = "The Skip-Level Nightmare", .func = testSkipLevel, .show_output = true, .export_svg = true },
        .{ .name = "Random Hairball (30 nodes)", .func = testHairball, .show_output = true, .export_svg = true },
        .{ .name = "Cross-Level Nightmare", .func = testCrossLevelNightmare, .show_output = true, .export_svg = true },
        .{ .name = "Binary Tree (depth 5)", .func = testBinaryTree, .show_output = true, .export_svg = true },
        .{ .name = "Random DAG (50 nodes)", .func = testRandomDag, .show_output = false, .export_svg = false },
        .{ .name = "Massive Diamond (1000 nodes)", .func = testMassiveDiamond, .show_output = false, .export_svg = false },
    };

    var total_time: u64 = 0;

    for (tests) |t| {
        std.debug.print("\n>>> RUNNING: {s} <<<\n\n", .{t.name});

        var graph = try t.func(allocator);
        defer graph.deinit();

        const node_count = graph.nodeCount();
        const edge_count = graph.edgeCount();
        std.debug.print("Graph: {d} nodes, {d} edges\n", .{ node_count, edge_count });

        // Time the layout and render
        const start = std.time.nanoTimestamp();

        const output = try zigraph.render(&graph, allocator, .{});
        defer allocator.free(output);

        const end = std.time.nanoTimestamp();
        const duration_us = @as(u64, @intCast(end - start)) / 1000;
        total_time += duration_us;

        if (t.show_output) {
            std.debug.print("{s}\n", .{output});
        } else {
            std.debug.print("(Output suppressed. Length: {d} bytes)\n", .{output.len});
        }

        // Export SVG for select tests
        if (t.export_svg) {
            // Layout with spline routing for nice curves
            // include_dummy_nodes = true makes dummy nodes visible in IR
            var ir_layout = try zigraph.layout(&graph, allocator, .{
                .routing = .spline,
                .crossing_reducers = &zigraph.crossing.quality, // High quality for SVG
                .include_dummy_nodes = true, // TEMP: make dummy nodes visible
            });
            defer ir_layout.deinit();

            const svg_output = try zigraph.svg.render(&ir_layout, allocator, .{
                .show_control_points = false,
                .show_dummy_nodes = true, // TEMP: show dummy nodes as orange circles
                .char_width = 12,
                .line_height = 24,
                .color_edges = true, // Use colored edges for visual clarity
            });
            defer allocator.free(svg_output);

            // Create filename from test name (replace spaces with underscores)
            var filename_buf: [128]u8 = undefined;
            var filename_len: usize = 0;
            for (t.name) |c| {
                if (filename_len >= filename_buf.len - 5) break;
                filename_buf[filename_len] = if (c == ' ' or c == '(' or c == ')') '_' else std.ascii.toLower(c);
                filename_len += 1;
            }
            const suffix = ".svg";
            @memcpy(filename_buf[filename_len..][0..suffix.len], suffix);
            const filename = filename_buf[0 .. filename_len + suffix.len];

            const file = std.fs.cwd().createFile(filename, .{}) catch |err| {
                std.debug.print("Failed to create SVG file: {}\n", .{err});
                continue;
            };
            defer file.close();
            file.writeAll(svg_output) catch |err| {
                std.debug.print("Failed to write SVG: {}\n", .{err});
                continue;
            };
            std.debug.print(">>> SVG exported to: {s}\n", .{filename});
        }

        std.debug.print(">>> Rendered in {d} µs <<<\n", .{duration_us});
        std.debug.print("------------------------------------------------------------\n", .{});
    }

    std.debug.print("\n=== TOTAL TIME: {d} µs ({d:.2} ms) ===\n", .{ total_time, @as(f64, @floatFromInt(total_time)) / 1000.0 });
}

/// Two intertwined chains with cross-connections
fn testDoubleHelix(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    for (0..10) |i| {
        try dag.addNode(i * 2, "A");
        try dag.addNode(i * 2 + 1, "B");

        if (i > 0) {
            try dag.addEdge((i - 1) * 2, i * 2); // A -> A
            try dag.addEdge((i - 1) * 2 + 1, i * 2 + 1); // B -> B

            // Cross connections
            if (i % 2 == 0) {
                try dag.addEdge((i - 1) * 2, i * 2 + 1); // A -> B
                try dag.addEdge((i - 1) * 2 + 1, i * 2); // B -> A
            }
        }
    }
    return dag;
}

/// Very deep, narrow graph (50 levels)
fn testSkyscraper(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    for (0..50) |i| {
        // Use simple single-char labels to avoid allocation
        try dag.addNode(i, "F");
        if (i > 0) {
            try dag.addEdge(i - 1, i);
        }
    }
    return dag;
}

/// Source -> 50 workers -> Sink
fn testWideFan(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    try dag.addNode(0, "Source");
    try dag.addNode(1000, "Sink");

    for (1..51) |i| {
        // Use simple labels
        try dag.addNode(i, "W");
        try dag.addEdge(0, i);
        try dag.addEdge(i, 1000);
    }
    return dag;
}

/// Grid-like diamond lattice (5 wide, 10 deep)
fn testDiamondLattice(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    const width: usize = 5;
    const height: usize = 10;

    for (0..height) |y| {
        for (0..width) |x| {
            const id = y * width + x;
            try dag.addNode(id, "*");

            if (y > 0) {
                // Connect to parent above
                try dag.addEdge((y - 1) * width + x, id);

                // Cross connection to left parent
                if (x > 0) {
                    try dag.addEdge((y - 1) * width + (x - 1), id);
                }
            }
        }
    }
    return dag;
}

/// Many skip-level edges
fn testSkipLevel(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    // Create levels
    try dag.addNode(0, "Root");

    // Level 1: 3 nodes
    try dag.addNode(1, "A1");
    try dag.addNode(2, "A2");
    try dag.addNode(3, "A3");
    try dag.addEdge(0, 1);
    try dag.addEdge(0, 2);
    try dag.addEdge(0, 3);

    // Level 2: 3 nodes
    try dag.addNode(4, "B1");
    try dag.addNode(5, "B2");
    try dag.addNode(6, "B3");
    try dag.addEdge(1, 4);
    try dag.addEdge(2, 5);
    try dag.addEdge(3, 6);

    // Level 3: sink
    try dag.addNode(7, "Sink");
    try dag.addEdge(4, 7);
    try dag.addEdge(5, 7);
    try dag.addEdge(6, 7);

    // Skip-level edges!
    try dag.addEdge(0, 7); // Root -> Sink (skip 2 levels)
    try dag.addEdge(1, 7); // A1 -> Sink (skip 1 level)
    try dag.addEdge(3, 7); // A3 -> Sink (skip 1 level)

    return dag;
}

/// Complete binary tree
fn testBinaryTree(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    const depth: usize = 5;
    const total_nodes = (@as(usize, 1) << depth) - 1; // 2^depth - 1

    for (0..total_nodes) |i| {
        // Use simple label
        try dag.addNode(i, "o");

        if (i > 0) {
            const parent = (i - 1) / 2;
            try dag.addEdge(parent, i);
        }
    }
    return dag;
}

/// Random DAG with controlled density
fn testRandomDag(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    var rng = SimpleRng.init(42); // Deterministic seed

    const n: usize = 50;

    // Add nodes
    for (0..n) |i| {
        // Use simple label
        try dag.addNode(i, "N");
    }

    // Add random edges (only forward to ensure DAG)
    for (0..n) |i| {
        const num_edges = rng.range(1, 4); // 1-3 edges per node
        for (0..num_edges) |_| {
            const target = rng.range(i + 1, n);
            if (target < n) {
                dag.addEdge(i, target) catch {}; // Ignore duplicates
            }
        }
    }

    return dag;
}

/// Large diamond pattern for performance testing
fn testMassiveDiamond(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    const width: usize = 50;
    const height: usize = 20;

    // Source
    try dag.addNode(0, "S");

    // Middle layers
    for (1..height - 1) |y| {
        for (0..width) |x| {
            const id = 1 + (y - 1) * width + x;
            try dag.addNode(id, "*");

            if (y == 1) {
                // Connect from source
                try dag.addEdge(0, id);
            } else {
                // Connect from previous row
                const prev_row_start = 1 + (y - 2) * width;
                if (x < width) {
                    try dag.addEdge(prev_row_start + x, id);
                }
                if (x > 0) {
                    try dag.addEdge(prev_row_start + x - 1, id);
                }
            }
        }
    }

    // Sink
    const sink_id = 1 + (height - 2) * width;
    try dag.addNode(sink_id + width, "T");
    const last_row_start = 1 + (height - 3) * width;
    for (0..width) |x| {
        try dag.addEdge(last_row_start + x, sink_id + width);
    }

    return dag;
}

/// Random hairball: chaotic connections with many cross-edges
/// Similar to ascii-dag's random_hairball test
fn testHairball(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    var rng = SimpleRng.init(42);
    const n: usize = 30;

    // Add nodes
    for (0..n) |i| {
        try dag.addNode(i, "H");
    }

    // Each node gets 1-3 random edges to higher-numbered nodes (DAG constraint)
    for (0..n) |i| {
        const edge_count = rng.range(1, 4);
        for (0..edge_count) |_| {
            if (i + 1 < n) {
                // Pick random target with i < j (ensures DAG)
                const target = rng.range(i + 1, n);
                if (target < n) {
                    dag.addEdge(i, target) catch {};
                }
            }
        }
    }

    return dag;
}

/// Cross-level nightmare: multiple nodes per level with skip edges
/// Enhanced version of ascii-dag's skip_level_nightmare
fn testCrossLevelNightmare(allocator: std.mem.Allocator) !zigraph.Graph {
    var dag = zigraph.Graph.init(allocator);
    errdefer dag.deinit();

    // Level 0: Root
    try dag.addNode(0, "Root");

    // Level 1: A, B, C
    try dag.addNode(1, "A1");
    try dag.addNode(2, "B1");
    try dag.addNode(3, "C1");
    try dag.addEdge(0, 1);
    try dag.addEdge(0, 2);
    try dag.addEdge(0, 3);

    // Level 2: A2, B2, C2
    try dag.addNode(4, "A2");
    try dag.addNode(5, "B2");
    try dag.addNode(6, "C2");
    try dag.addEdge(1, 4);
    try dag.addEdge(2, 5);
    try dag.addEdge(3, 6);

    // Level 3: A3, B3
    try dag.addNode(7, "A3");
    try dag.addNode(8, "B3");
    try dag.addEdge(4, 7);
    try dag.addEdge(5, 8);
    try dag.addEdge(6, 8);

    // Level 4: Sink
    try dag.addNode(9, "Sink");
    try dag.addEdge(7, 9);
    try dag.addEdge(8, 9);

    // SKIP EDGES (the nightmare part!)
    // Root skips to level 2
    try dag.addEdge(0, 5); // Root → B2 (skip level 1)

    // Root skips to level 3
    try dag.addEdge(0, 7); // Root → A3 (skip levels 1,2)

    // Level 1 skips to level 3
    try dag.addEdge(1, 8); // A1 → B3 (skip level 2)
    try dag.addEdge(3, 7); // C1 → A3 (skip level 2)

    // Level 1 skips to level 4 (sink)
    try dag.addEdge(2, 9); // B1 → Sink (skip levels 2,3)

    // Level 2 skips to level 4
    try dag.addEdge(4, 9); // A2 → Sink (skip level 3)

    return dag;
}
