//! README Hero - Showcase example for zigraph
//!
//! A complex graph demonstrating fan-out, fan-in, and skip-level edges.
//!
//! Run with: zig build run-hero

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

    // Layout with quality settings to minimize edge crossings
    var ir = try zigraph.layout(&dag, allocator, .{
        .crossing_reducers = &zigraph.crossing.quality,
        .positioning = .brandes_kopf,
        .node_spacing = 4,
        .level_spacing = 3,
    });
    defer ir.deinit();

    // Render (dummy nodes hidden for clean output)
    const output = try zigraph.unicode.renderWithConfig(&ir, allocator, .{
        .show_dummy_nodes = false,
        .edge_palette = &zigraph.colors.ansi_dark,
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
}
