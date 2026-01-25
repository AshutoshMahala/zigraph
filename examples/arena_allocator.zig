//! Example: Arena allocator for efficient graph processing
//!
//! This example demonstrates using an arena allocator for batch graph operations.
//! Arena allocation is ideal for zigraph because:
//!
//! 1. Graph + layout is a batch operation (create → layout → render → done)
//! 2. All allocations can be freed at once (no individual frees needed)
//! 3. Much faster than general-purpose allocators for many small allocations
//!
//! Pattern:
//!   arena.reset() or arena.deinit()  ← Frees everything instantly
//!   ├── Graph allocations
//!   ├── Layout IR allocations
//!   └── Render buffer allocation
//!
//! Memory: O(nodes + edges + output) - all freed in one operation

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    // Backing allocator for the arena (page allocator is fine here)
    const backing = std.heap.page_allocator;

    // =========================================================================
    // Example 1: Single graph with arena
    // =========================================================================
    std.debug.print("\n=== Example 1: Single Graph with Arena ===\n\n", .{});
    {
        // Create arena - all allocations go here
        var arena = std.heap.ArenaAllocator.init(backing);
        defer arena.deinit(); // Frees EVERYTHING at once

        const allocator = arena.allocator();

        // Build graph (allocations go to arena)
        var g = zigraph.Graph.init(allocator);
        // No defer g.deinit() needed - arena handles it

        // Use implicit nodes for quick construction
        try g.addEdgeAutoCreate(1, 2);
        try g.addEdgeAutoCreate(1, 3);
        try g.addEdgeAutoCreate(2, 4);
        try g.addEdgeAutoCreate(3, 4);

        // Layout and render (all allocations go to same arena)
        const output = try zigraph.render(&g, allocator, .{});
        // No defer allocator.free(output) needed - arena handles it

        std.debug.print("{s}\n", .{output});

        // When arena.deinit() runs, everything is freed at once
        // No per-object cleanup, no fragmentation
    }

    // =========================================================================
    // Example 2: Multiple graphs with arena reset
    // =========================================================================
    std.debug.print("\n=== Example 2: Processing Multiple Graphs ===\n\n", .{});
    {
        var arena = std.heap.ArenaAllocator.init(backing);
        defer arena.deinit();

        const allocator = arena.allocator();

        // Process multiple graphs, reusing the arena
        const graphs = [_]struct { edges: []const [2]usize, name: []const u8 }{
            .{ .edges = &.{ .{ 1, 2 }, .{ 2, 3 } }, .name = "Linear" },
            .{ .edges = &.{ .{ 1, 2 }, .{ 1, 3 }, .{ 2, 4 }, .{ 3, 4 } }, .name = "Diamond" },
            .{ .edges = &.{ .{ 1, 2 }, .{ 1, 3 }, .{ 1, 4 } }, .name = "Star" },
        };

        for (graphs) |graph_def| {
            std.debug.print("--- {s} ---\n", .{graph_def.name});

            var g = zigraph.Graph.init(allocator);
            for (graph_def.edges) |edge| {
                try g.addEdgeAutoCreate(edge[0], edge[1]);
            }

            const output = try zigraph.render(&g, allocator, .{});
            std.debug.print("{s}\n", .{output});

            // Reset arena for next graph - instant, O(1) "free"
            // This keeps memory allocated but marks it as reusable
            _ = arena.reset(.retain_capacity);
        }
    }

    // =========================================================================
    // Example 3: Larger graph - showing scaling
    // =========================================================================
    std.debug.print("\n=== Example 3: Larger Graph (100 nodes) ===\n\n", .{});
    {
        var arena = std.heap.ArenaAllocator.init(backing);
        defer arena.deinit();

        const allocator = arena.allocator();

        var g = zigraph.Graph.init(allocator);

        // Create a 10-layer graph with 10 nodes per layer
        const layers: usize = 10;
        const nodes_per_layer: usize = 10;

        var node_id: usize = 1;
        for (0..layers) |layer| {
            for (0..nodes_per_layer) |_| {
                // Connect to ~2 random nodes in next layer
                if (layer + 1 < layers) {
                    const next_layer_start = (layer + 1) * nodes_per_layer + 1;
                    try g.addEdgeAutoCreate(node_id, next_layer_start + (node_id % nodes_per_layer));
                    try g.addEdgeAutoCreate(node_id, next_layer_start + ((node_id + 1) % nodes_per_layer));
                }
                node_id += 1;
            }
        }

        std.debug.print("Graph: {d} nodes, {d} edges\n", .{ g.nodeCount(), g.edges.items.len });

        // Time the layout
        const start = std.time.nanoTimestamp();
        var ir = try zigraph.layout(&g, allocator, .{});
        const layout_time = std.time.nanoTimestamp() - start;

        std.debug.print("Layout time: {d}µs\n", .{@divFloor(layout_time, 1000)});
        std.debug.print("Levels: {d}\n", .{ir.level_count});

        // Skip rendering the huge graph, just show stats
        ir.deinit();
    }

    std.debug.print("\n=== Done ===\n", .{});
}
