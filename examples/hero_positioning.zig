//! Hero graph rendered with all three positioning algorithms
//!
//! Run with: zig build run-hero-pos

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const positionings = [_]struct { name: []const u8, pos: zigraph.Positioning }{
        .{ .name = ".compact", .pos = .compact },
        .{ .name = ".barycentric", .pos = .barycentric },
        .{ .name = ".brandes_kopf", .pos = .brandes_kopf },
    };

    for (positionings) |cfg| {
        // Build a fresh graph each time (layout mutates internal state)
        var dag = zigraph.Graph.init(allocator);
        defer dag.deinit();

        try dag.addNode(1, "Root");
        try dag.addNode(6, "Task E");
        try dag.addNode(2, "Task A");
        try dag.addNode(3, "Task B");
        try dag.addNode(4, "Task C");
        try dag.addNode(5, "Task D");
        try dag.addNode(7, "Task F");
        try dag.addNode(8, "Output");

        try dag.addEdgeLabeled(1, 6, "spawn");
        try dag.addEdge(1, 2);
        try dag.addEdge(1, 3);
        try dag.addEdge(1, 4);
        try dag.addEdge(1, 5);
        try dag.addEdge(2, 7);
        try dag.addEdge(3, 7);
        try dag.addEdge(4, 7);
        try dag.addEdge(5, 7);
        try dag.addEdgeLabeled(6, 8, "skip");
        try dag.addEdgeLabeled(7, 8, "merge");

        std.debug.print("\n============================================================\n", .{});
        std.debug.print("  positioning = {s}\n", .{cfg.name});
        std.debug.print("============================================================\n\n", .{});

        const output = zigraph.render(&dag, allocator, .{
            .crossing_reducers = &zigraph.crossing.quality,
            .positioning = cfg.pos,
            .node_spacing = 4,
            .level_spacing = 3,
        }) catch |err| {
            std.debug.print("  (error: {s})\n", .{@errorName(err)});
            continue;
        };
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
