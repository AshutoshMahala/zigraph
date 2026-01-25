//! Example: Algorithm selection via config
//!
//! Demonstrates how to choose different algorithms for each stage
//! of the Sugiyama layout pipeline.

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Build a sample graph
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    // Binary tree
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addNode(5, "E");
    try g.addNode(6, "F");
    try g.addNode(7, "G");

    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(2, 5);
    try g.addEdge(3, 6);
    try g.addEdge(3, 7);

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Algorithm Selection Demo                                  ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});

    // =========================================================================
    // Example 1: Default settings (Brandes-Köpf positioning)
    // =========================================================================
    std.debug.print("\n=== Default: Brandes-Köpf positioning ===\n\n", .{});
    {
        const output = try zigraph.render(&g, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // =========================================================================
    // Example 2: Simple positioning (left-to-right, no centering)
    // =========================================================================
    std.debug.print("\n=== Simple positioning ===\n\n", .{});
    {
        const output = try zigraph.render(&g, allocator, .{
            .positioning = .simple,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // =========================================================================
    // Example 3: Custom spacing
    // =========================================================================
    std.debug.print("\n=== Compact (spacing = 1) ===\n\n", .{});
    {
        const output = try zigraph.render(&g, allocator, .{
            .node_spacing = 1,
            .level_spacing = 1,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // =========================================================================
    // Example 4: Wide spacing
    // =========================================================================
    std.debug.print("\n=== Wide (spacing = 6) ===\n\n", .{});
    {
        const output = try zigraph.render(&g, allocator, .{
            .node_spacing = 6,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // =========================================================================
    // Show available options
    // =========================================================================
    std.debug.print("\n=== Available Options ===\n\n", .{});
    std.debug.print("Layering:    .longest_path (default)\n", .{});
    std.debug.print("Crossing:    crossing.balanced (default), crossing.fast, crossing.quality, crossing.none\n", .{});
    std.debug.print("Positioning: .brandes_kopf (default), .simple\n", .{});
    std.debug.print("Routing:     .direct (default), .spline\n", .{});
    std.debug.print("\nTuning:\n", .{});
    std.debug.print("  .node_spacing   = 3 (default)\n", .{});
    std.debug.print("  .level_spacing  = 2 (default)\n", .{});
    std.debug.print("\nCrossing Reducers (composable pipeline):\n", .{});
    std.debug.print("  .crossing_reducers = &crossing.balanced (default)\n", .{});
    std.debug.print("  Custom: &[_]crossing.Reducer{{ crossing.medianReducer(4), crossing.adjacentExchangeReducer(2) }}\n", .{});
    std.debug.print("\nPerformance:\n", .{});
    std.debug.print("  .skip_validation = false (default)\n", .{});

    std.debug.print("\n=== Done ===\n", .{});
}
