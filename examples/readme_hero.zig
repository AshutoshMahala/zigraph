//! README Hero - Showcase example for zigraph
//!
//! A complex graph demonstrating fan-out, fan-in, and skip-level edges.
//!
//! Run with: zig build run-hero

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var dag = zigraph.Graph.init(allocator);
    defer dag.deinit();

    // Build the hero graph
    // Task E is placed first (leftmost) since it has the skip-level edge to Output
    try dag.addNode(1, "Root");
    try dag.addNode(6, "Task E"); // Skip-level edge - leftmost
    try dag.addNode(2, "Task A");
    try dag.addNode(3, "Task B");
    try dag.addNode(4, "Task C");
    try dag.addNode(5, "Task D");
    try dag.addNode(7, "Task F");
    try dag.addNode(8, "Output");

    // Level 1 connections (Root fans out) - order matters for layout
    try dag.addEdgeLabeled(1, 6, "spawn"); // Root -> Task E (leftmost due to skip-level)
    try dag.addEdge(1, 2);
    try dag.addEdge(1, 3);
    try dag.addEdge(1, 4);
    try dag.addEdge(1, 5);

    // Converge on Task F (A, B, C, D -> F)
    try dag.addEdge(2, 7);
    try dag.addEdge(3, 7);
    try dag.addEdge(4, 7);
    try dag.addEdge(5, 7);

    // Final Output
    try dag.addEdgeLabeled(6, 8, "skip"); // E -> Output (skip-level edge, now on left)
    try dag.addEdgeLabeled(7, 8, "merge"); // F -> Output

    // Feedback loop (creates a cycle!)
    try dag.addEdgeLabeled(8, 1, "retry"); // Output -> Root (back edge)

    // Layout with quality settings to minimize edge crossings
    var ir = try zigraph.layout(&dag, allocator, .{
        .crossing_reducers = &zigraph.crossing.quality,
        .positioning = .brandes_kopf,
        .node_spacing = 4,
        .level_spacing = 3,
        .cycle_breaking = .depth_first,
    });
    defer ir.deinit();

    // Render (dummy nodes hidden for clean output)
    const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
        .show_dummy_nodes = false,
        .edge_palette = &zigraph.color.ansi_dark,
    });
    defer allocator.free(output);

    std.debug.print(
        \\
        \\zigraph - README Hero Example
        \\==============================
        \\
        \\{s}
        \\
    , .{output});

    // Export SVG assets for README
    // Direct mode: no colors, show dummy nodes for debugging showcase
    const svg_direct = try zigraph.svg.render(&ir, allocator, .{
        .edge_style_fn = &zigraph.svg.monoEdgeStyle,
        .stitch_splines = false,
        .show_dummy_nodes = true,
    });
    defer allocator.free(svg_direct);
    {
        var f = try std.Io.Dir.cwd().createFile(io, "assets/hero_direct.svg", .{});
        defer f.close(io);
        var wbuf1: [4096]u8 = undefined;
        var fw1 = std.Io.File.writer(f, io, &wbuf1);
        try fw1.interface.writeAll(svg_direct);
    }

    const svg_spline = try zigraph.svg.render(&ir, allocator, .{
        .stitch_splines = true,
    });
    defer allocator.free(svg_spline);
    {
        var f = try std.Io.Dir.cwd().createFile(io, "assets/hero_spline.svg", .{});
        defer f.close(io);
        var wbuf2: [4096]u8 = undefined;
        var fw2 = std.Io.File.writer(f, io, &wbuf2);
        try fw2.interface.writeAll(svg_spline);
    }

    const svg_labels = try zigraph.svg.render(&ir, allocator, .{
        .stitch_splines = true,
        .labels_on_path = true,
    });
    defer allocator.free(svg_labels);
    {
        var f = try std.Io.Dir.cwd().createFile(io, "assets/hero_labels.svg", .{});
        defer f.close(io);
        var wbuf3: [4096]u8 = undefined;
        var fw3 = std.Io.File.writer(f, io, &wbuf3);
        try fw3.interface.writeAll(svg_labels);
    }

    std.debug.print(">>> SVG assets exported to assets/\n", .{});
}
