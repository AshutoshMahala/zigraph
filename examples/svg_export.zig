//! SVG Export Example
//!
//! Demonstrates SVG rendering with spline curves and control point visualization.
//! Run with: zig build run-svg

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== zigraph SVG Export Example ===\n\n", .{});

    // Create a sample graph
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "Input");
    try graph.addNode(2, "Process A");
    try graph.addNode(3, "Process B");
    try graph.addNode(4, "Merge");
    try graph.addNode(5, "Output");

    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(2, 4);
    try graph.addEdge(3, 4);
    try graph.addEdge(4, 5);

    // ========================================
    // Direct routing (Manhattan)
    // ========================================
    std.debug.print("1. Direct Routing (Manhattan):\n", .{});
    std.debug.print("─────────────────────────────────────────\n", .{});

    var ir_direct = try zigraph.layout(&graph, allocator, .{ .routing = .direct });
    defer ir_direct.deinit();

    const svg_direct = try zigraph.svg.render(&ir_direct, allocator, .{});
    defer allocator.free(svg_direct);

    std.debug.print("Generated SVG with direct routing ({d} bytes)\n", .{svg_direct.len});

    // Write to file
    {
        const file = try std.fs.cwd().createFile("graph_direct.svg", .{});
        defer file.close();
        try file.writeAll(svg_direct);
        std.debug.print("Written to: graph_direct.svg\n\n", .{});
    }

    // ========================================
    // Spline routing (Bezier curves)
    // ========================================
    std.debug.print("2. Spline Routing (Bezier Curves):\n", .{});
    std.debug.print("─────────────────────────────────────────\n", .{});

    var ir_spline = try zigraph.layout(&graph, allocator, .{ .routing = .spline });
    defer ir_spline.deinit();

    const svg_spline = try zigraph.svg.render(&ir_spline, allocator, .{});
    defer allocator.free(svg_spline);

    std.debug.print("Generated SVG with spline routing ({d} bytes)\n", .{svg_spline.len});

    {
        const file = try std.fs.cwd().createFile("graph_spline.svg", .{});
        defer file.close();
        try file.writeAll(svg_spline);
        std.debug.print("Written to: graph_spline.svg\n\n", .{});
    }

    // ========================================
    // Spline with control points visible
    // ========================================
    std.debug.print("3. Spline with Control Points (Debug Mode):\n", .{});
    std.debug.print("─────────────────────────────────────────\n", .{});

    const svg_debug = try zigraph.svg.render(&ir_spline, allocator, .{
        .show_control_points = true,
        .control_point_color = "#ff0000",
    });
    defer allocator.free(svg_debug);

    std.debug.print("Generated debug SVG ({d} bytes)\n", .{svg_debug.len});

    {
        const file = try std.fs.cwd().createFile("graph_spline_debug.svg", .{});
        defer file.close();
        try file.writeAll(svg_debug);
        std.debug.print("Written to: graph_spline_debug.svg\n\n", .{});
    }

    // Show comparison
    std.debug.print("=== Unicode Comparison ===\n\n", .{});

    const unicode_direct = try zigraph.unicode.render(&ir_direct, allocator);
    defer allocator.free(unicode_direct);

    const unicode_spline = try zigraph.unicode.render(&ir_spline, allocator);
    defer allocator.free(unicode_spline);

    std.debug.print("Direct routing (Unicode):\n{s}\n", .{unicode_direct});
    std.debug.print("Spline routing (Unicode fallback):\n{s}\n", .{unicode_spline});

    std.debug.print("=== Done ===\n", .{});
    std.debug.print("Open graph_spline_debug.svg in a browser to see bezier curves with control points!\n", .{});
}
