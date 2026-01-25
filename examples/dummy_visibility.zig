const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a graph with edges that span multiple levels
    // This will create dummy nodes for routing
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    // Add nodes with explicit IDs
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");

    // A simple chain that skips levels
    // A -> D means we need dummy nodes at levels 1 and 2
    try g.addEdge(1, 2); // A at level 0, B at level 1
    try g.addEdge(2, 3); // C at level 2
    try g.addEdge(3, 4); // D at level 3
    try g.addEdge(1, 4); // Long edge: A(0) -> D(3), needs 2 dummies

    // Layout is now unified - always uses dummy nodes internally
    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    std.debug.print("Nodes in IR: {d} (including dummy nodes)\n\n", .{ir.nodes.items.len});

    // Normal rendering: dummy nodes are invisible (edges draw through)
    std.debug.print("=== Normal Rendering (dummies invisible) ===\n\n", .{});
    {
        const output = try zigraph.unicode.render(&ir, allocator);
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // Debug rendering: show dummy nodes as 'O'
    std.debug.print("=== Debug Rendering (dummies visible as O) ===\n\n", .{});
    {
        const output = try zigraph.unicode.renderWithConfig(&ir, allocator, .{
            .show_dummy_nodes = true,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // Show node details
    std.debug.print("Node details:\n", .{});
    for (ir.nodes.items) |node| {
        const kind_str: []const u8 = switch (node.kind) {
            .explicit => "explicit",
            .implicit => "implicit",
            .dummy => "DUMMY  ",
        };
        if (node.edge_index) |ei| {
            std.debug.print("  {s}: {s} (level={d}, x={d}, edge_idx={d})\n", .{
                node.label,
                kind_str,
                node.level,
                node.x,
                ei,
            });
        } else {
            std.debug.print("  {s}: {s} (level={d}, x={d})\n", .{
                node.label,
                kind_str,
                node.level,
                node.x,
            });
        }
    }
}
