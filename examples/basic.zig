//! Basic example - demonstrates simple graph layout
//!
//! Run with: zig build run-example

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\zigraph - Basic Example
        \\========================
        \\
        \\
    , .{});

    // Example 1: Simple chain
    {
        std.debug.print("Example 1: Simple Chain\n", .{});
        std.debug.print("-----------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "Parse");
        try graph.addNode(2, "Compile");
        try graph.addNode(3, "Link");
        try graph.addEdge(1, 2);
        try graph.addEdge(2, 3);

        const output = try zigraph.render(&graph, allocator, .{});
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});
    }

    // Example 2: Diamond graph
    {
        std.debug.print("Example 2: Diamond Graph\n", .{});
        std.debug.print("------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "Root");
        try graph.addNode(2, "Left");
        try graph.addNode(3, "Right");
        try graph.addNode(4, "Merge");
        try graph.addEdge(1, 2);
        try graph.addEdge(1, 3);
        try graph.addEdge(2, 4);
        try graph.addEdge(3, 4);

        const output = try zigraph.render(&graph, allocator, .{});
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});
    }

    // Example 3: Wide graph
    {
        std.debug.print("Example 3: Wide Graph\n", .{});
        std.debug.print("---------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "Start");
        try graph.addNode(2, "A");
        try graph.addNode(3, "B");
        try graph.addNode(4, "C");
        try graph.addNode(5, "D");
        try graph.addNode(6, "End");
        try graph.addEdge(1, 2);
        try graph.addEdge(1, 3);
        try graph.addEdge(1, 4);
        try graph.addEdge(1, 5);
        try graph.addEdge(2, 6);
        try graph.addEdge(3, 6);
        try graph.addEdge(4, 6);
        try graph.addEdge(5, 6);

        const output = try zigraph.render(&graph, allocator, .{});
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});
    }

    // Example 4: Implicit nodes (auto-created from edges)
    {
        std.debug.print("Example 4: Explicit vs Implicit Nodes\n", .{});
        std.debug.print("--------------------------------------\n", .{});
        std.debug.print("Explicit nodes use [], implicit use <>\n\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        // Explicit node with custom label
        try graph.addNode(1, "Start");
        try graph.addNode(5, "End");

        // Edges to implicit nodes (auto-created with ID as label)
        try graph.addEdgeAutoCreate(1, 2); // Node 2 is implicit
        try graph.addEdgeAutoCreate(1, 3); // Node 3 is implicit
        try graph.addEdgeAutoCreate(2, 4); // Node 4 is implicit
        try graph.addEdgeAutoCreate(3, 4);
        try graph.addEdgeAutoCreate(4, 5);

        const output = try zigraph.render(&graph, allocator, .{});
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});
    }

    std.debug.print("Done!\n", .{});
}
