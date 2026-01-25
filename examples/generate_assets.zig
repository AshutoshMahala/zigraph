//! Generate README assets - All hero formats
//!
//! Generates the same graph in all output formats for the README showcase.
//! Output files are written to ../assets/
//!
//! Run with: zig build run-generate-assets

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dag = zigraph.Graph.init(allocator);
    defer dag.deinit();

    // Build the hero graph
    // Task E is placed first (leftmost) since it has the skip-level edge to Output
    try dag.addNode(1, "Root");
    try dag.addNode(6, "Task E");  // Skip-level edge - leftmost
    try dag.addNode(2, "Task A");
    try dag.addNode(3, "Task B");
    try dag.addNode(4, "Task C");
    try dag.addNode(5, "Task D");
    try dag.addNode(7, "Task F");
    try dag.addNode(8, "Output");

    // Level 1 connections (Root fans out) - order matters for layout
    try dag.addEdge(1, 6);  // Root -> Task E (leftmost due to skip-level)
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
    try dag.addEdge(6, 8);  // E -> Output (skip-level edge, now on left)
    try dag.addEdge(7, 8);  // F -> Output

    // 1. Unicode (terminal) output - Plain (for README)
    {
        const output = try zigraph.render(&dag, allocator, .{
            .crossing_reducers = &zigraph.crossing.quality,
            .positioning = .brandes_kopf,
        });
        defer allocator.free(output);

        const file = try std.fs.cwd().createFile("assets/hero_unicode.txt", .{});
        defer file.close();
        try file.writeAll(output);
        std.debug.print("✓ Generated assets/hero_unicode.txt (plain)\n", .{});
    }

    // 1b. Unicode (terminal) output - Colored (preview only)
    {
        const output = try zigraph.render(&dag, allocator, .{
            .crossing_reducers = &zigraph.crossing.quality,
            .positioning = .brandes_kopf,
            .edge_palette = &zigraph.colors.ansi_dark,
        });
        defer allocator.free(output);
        
        // We don't save this to a file because raw ANSI codes look bad in editors/GitHub
        // Instead we just print a message that it's available via 'zig build run-hero'
        std.debug.print("✓ Verified colored output generation (run 'zig build run-hero' to view)\n", .{});
    }

    // 2. SVG with direct routing (shows dummy nodes)
    {
        var ir = try zigraph.layout(&dag, allocator, .{
            .routing = .direct,
            .crossing_reducers = &zigraph.crossing.quality,
            .positioning = .brandes_kopf,
        });
        defer ir.deinit();

        const svg = try zigraph.svg.render(&ir, allocator, .{
            .show_dummy_nodes = true,
            .stitch_splines = false, // Must be false to show direct polylines
        });
        defer allocator.free(svg);

        const file = try std.fs.cwd().createFile("assets/hero_direct.svg", .{});
        defer file.close();
        try file.writeAll(svg);
        std.debug.print("✓ Generated assets/hero_direct.svg\n", .{});
    }

    // 3. SVG with spline routing (colorful curves)
    {
        var ir = try zigraph.layout(&dag, allocator, .{
            .routing = .spline,
            .crossing_reducers = &zigraph.crossing.quality,
            .positioning = .brandes_kopf,
        });
        defer ir.deinit();

        const svg = try zigraph.svg.render(&ir, allocator, .{
            .edge_palette = &zigraph.colors.radix,
        });
        defer allocator.free(svg);

        const file = try std.fs.cwd().createFile("assets/hero_spline.svg", .{});
        defer file.close();
        try file.writeAll(svg);
        std.debug.print("✓ Generated assets/hero_spline.svg\n", .{});
    }

    // 4. JSON export
    {
        const json = try zigraph.exportJson(&dag, allocator, .{});
        defer allocator.free(json);

        const file = try std.fs.cwd().createFile("assets/hero.json", .{});
        defer file.close();
        try file.writeAll(json);
        std.debug.print("✓ Generated assets/hero.json\n", .{});
    }

    std.debug.print("\n✅ All hero assets generated in assets/\n", .{});
}
