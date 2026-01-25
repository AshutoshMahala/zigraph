//! Example: JSON IR Export
//!
//! Demonstrates exporting the layout as JSON for use by external tools.
//! The JSON IR contains all layout information needed to render the graph
//! in any format: SVG, Canvas, React components, etc.

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  JSON IR Export Demo                                       ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});

    // Build a graph
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "Process");
    try g.addNode(3, "End");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    // =========================================================================
    // Show Unicode render (for comparison)
    // =========================================================================
    std.debug.print("\n=== Unicode Render ===\n\n", .{});
    {
        const output = try zigraph.render(&g, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // =========================================================================
    // Export as JSON
    // =========================================================================
    std.debug.print("\n=== JSON IR Export ===\n\n", .{});
    {
        const json = try zigraph.exportJson(&g, allocator, .{});
        defer allocator.free(json);
        std.debug.print("{s}", .{json});
    }

    // =========================================================================
    // Or use the LayoutIR directly for more control
    // =========================================================================
    std.debug.print("\n=== Direct IR Access ===\n\n", .{});
    {
        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        std.debug.print("Dimensions: {d}x{d}\n", .{ ir.width, ir.height });
        std.debug.print("Levels: {d}\n", .{ir.level_count});
        std.debug.print("Nodes: {d}\n", .{ir.nodes.items.len});
        std.debug.print("Edges: {d}\n\n", .{ir.edges.items.len});

        for (ir.nodes.items) |node| {
            std.debug.print("  Node {d}: \"{s}\" at ({d}, {d}), level {d}\n", .{
                node.id,
                node.label,
                node.x,
                node.y,
                node.level,
            });
        }
    }

    std.debug.print("\n=== Done ===\n", .{});
}
