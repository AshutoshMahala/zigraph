//! Standalone Algorithm Usage
//!
//! Demonstrates using zigraph algorithms individually,
//! without the full layout pipeline.
//!
//! This is the "idiotically modular" philosophy in action:
//! grab just the algorithm you need for your own project.

const std = @import("std");
const zigraph = @import("zigraph");

const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print(
        \\╔════════════════════════════════════════════════════════════╗
        \\║  Standalone Algorithm Demo                                 ║
        \\╚════════════════════════════════════════════════════════════╝
        \\
        \\
    , .{});

    // First, build a simple graph for demonstration
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();

    // Diamond pattern: A -> B, A -> C, B -> D, C -> D
    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addNode(3, "C");
    try graph.addNode(4, "D");
    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(2, 4);
    try graph.addEdge(3, 4);

    // =========================================================================
    // STANDALONE: Layering Algorithm
    // =========================================================================
    print("=== Standalone: Longest-Path Layering ===\n\n", .{});

    // Use JUST the layering algorithm - no crossing, no positioning, no routing
    const LayerAssignment = zigraph.layering.longest_path.LayerAssignment;
    var layers: LayerAssignment = try zigraph.layering.longest_path.compute(&graph, allocator);
    defer layers.deinit();

    print("Max level: {d}\n", .{layers.max_level});
    print("Node levels:\n", .{});

    for (graph.nodes.items, 0..) |node, idx| {
        print("  Node {d} (\"{s}\"): level {d}\n", .{
            node.id,
            node.label,
            layers.getLevel(idx),
        });
    }

    // =========================================================================
    // STANDALONE: Build layer structure for crossing reduction
    // =========================================================================
    print("\n=== Standalone: Median Crossing Reduction ===\n\n", .{});

    // Build level arrays (nodes grouped by level)
    var level_arrays = try allocator.alloc(std.ArrayListUnmanaged(usize), layers.max_level + 1);
    defer {
        for (level_arrays) |*arr| arr.deinit(allocator);
        allocator.free(level_arrays);
    }
    for (level_arrays) |*arr| arr.* = .{};

    for (0..graph.nodeCount()) |node_idx| {
        const level = layers.getLevel(node_idx);
        try level_arrays[level].append(allocator, node_idx);
    }

    print("Before crossing reduction:\n", .{});
    for (level_arrays, 0..) |level, level_idx| {
        print("  Level {d}: ", .{level_idx});
        for (level.items) |node_idx| {
            const node = graph.nodes.items[node_idx];
            print("{s} ", .{node.label});
        }
        print("\n", .{});
    }

    // Apply crossing reduction (modifies level_arrays in place)
    try zigraph.crossing.median.reduce(&graph, level_arrays, 4, allocator);

    print("\nAfter crossing reduction (4 passes):\n", .{});
    for (level_arrays, 0..) |level, level_idx| {
        print("  Level {d}: ", .{level_idx});
        for (level.items) |node_idx| {
            const node = graph.nodes.items[node_idx];
            print("{s} ", .{node.label});
        }
        print("\n", .{});
    }

    // =========================================================================
    // STANDALONE: Positioning Algorithm
    // =========================================================================
    print("\n=== Standalone: Brandes-Köpf Positioning ===\n\n", .{});

    // Use positioning directly
    const bk = zigraph.positioning.brandes_kopf;
    var positions: bk.PositionAssignment = try bk.compute(
        &graph,
        level_arrays,
        .{ .node_spacing = 3 },
        allocator,
    );
    defer positions.deinit();

    print("Total width: {d}\n", .{positions.total_width});
    print("Node positions:\n", .{});
    for (graph.nodes.items, 0..) |node, idx| {
        print("  Node \"{s}\": x = {d}, center_x = {d}\n", .{
            node.label,
            positions.x[idx],
            positions.center_x[idx],
        });
    }

    // =========================================================================
    // Summary
    // =========================================================================
    print(
        \\
        \\=== Summary ===
        \\
        \\Each algorithm is fully standalone:
        \\
        \\  zigraph.layering.longest_path.compute()
        \\    → LayerAssignment (level per node)
        \\
        \\  zigraph.crossing.median.reduce()
        \\    → Reorders nodes in-place to minimize crossings
        \\
        \\  zigraph.positioning.brandes_kopf.compute()
        \\    → PositionAssignment (x-coordinate per node)
        \\
        \\Use them individually in your own pipeline!
        \\
        \\=== Done ===
        \\
    , .{});
}
