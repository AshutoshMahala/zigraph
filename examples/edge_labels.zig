//! Edge Labels Demo
//!
//! Demonstrates labeled edges with smart positioning.
//!
//! Run with: zig build run-labels

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\zigraph - Edge Labels Demo
        \\===========================
        \\
        \\
    , .{});

    // --- Example 1: Simple dependency graph ---
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();

        try dag.addNode(1, "App");
        try dag.addNode(2, "Auth");
        try dag.addNode(3, "DB");
        try dag.addNode(4, "Cache");

        try dag.addEdgeLabeled(1, 2, "requires");
        try dag.addEdgeLabeled(1, 3, "reads");
        try dag.addEdgeLabeled(2, 3, "queries");
        try dag.addEdgeLabeled(1, 4, "uses");

        var ir = try zigraph.layout(&dag, allocator, .{
            .node_spacing = 4,
        });
        defer ir.deinit();

        const output = try zigraph.unicode.renderWithConfig(&ir, allocator, .{
            .edge_palette = &zigraph.colors.ansi_dark,
        });
        defer allocator.free(output);

        std.debug.print("Example 1: Dependencies\n", .{});
        std.debug.print("-----------------------\n{s}\n\n", .{output});

        // Export SVG to test label rendering (fixed-position labels)
        const svg_output = try zigraph.svg.render(&ir, allocator, .{
            .color_edges = true,
        });
        defer allocator.free(svg_output);

        const svg_file = try std.fs.cwd().createFile("edge_labels.svg", .{});
        defer svg_file.close();
        try svg_file.writeAll(svg_output);
        std.debug.print(">>> SVG exported to: edge_labels.svg\n", .{});

        // Export SVG with labels-on-path mode
        const svg_path_output = try zigraph.svg.render(&ir, allocator, .{
            .color_edges = true,
            .labels_on_path = true,
        });
        defer allocator.free(svg_path_output);

        const svg_path_file = try std.fs.cwd().createFile("edge_labels_on_path.svg", .{});
        defer svg_path_file.close();
        try svg_path_file.writeAll(svg_path_output);
        std.debug.print(">>> SVG exported to: edge_labels_on_path.svg\n\n", .{});
    }

    // --- Example 2: State machine ---
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();

        try dag.addNode(1, "Idle");
        try dag.addNode(2, "Running");
        try dag.addNode(3, "Done");

        try dag.addEdgeLabeled(1, 2, "start");
        try dag.addEdgeLabeled(2, 3, "finish");

        var ir = try zigraph.layout(&dag, allocator, .{
            .node_spacing = 4,
        });
        defer ir.deinit();

        const output = try zigraph.unicode.renderWithConfig(&ir, allocator, .{
            .edge_palette = &zigraph.colors.ansi_dark,
        });
        defer allocator.free(output);

        std.debug.print("Example 2: State Machine\n", .{});
        std.debug.print("------------------------\n{s}\n\n", .{output});
    }

    // --- Example 3: Mixed labeled and unlabeled ---
    {
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();

        try dag.addNode(1, "Client");
        try dag.addNode(2, "API");
        try dag.addNode(3, "Worker");
        try dag.addNode(4, "Queue");
        try dag.addNode(5, "Storage");

        try dag.addEdgeLabeled(1, 2, "HTTP");
        try dag.addEdge(2, 3); // no label
        try dag.addEdgeLabeled(2, 4, "enqueue");
        try dag.addEdgeLabeled(3, 5, "write");
        try dag.addEdgeLabeled(4, 5, "flush");

        var ir = try zigraph.layout(&dag, allocator, .{
            .node_spacing = 5,
        });
        defer ir.deinit();

        const output = try zigraph.unicode.renderWithConfig(&ir, allocator, .{
            .edge_palette = &zigraph.colors.ansi_dark,
        });
        defer allocator.free(output);

        std.debug.print("Example 3: Mixed Labels\n", .{});
        std.debug.print("-----------------------\n{s}\n", .{output});
    }

    std.debug.print("Done!\n", .{});
}
