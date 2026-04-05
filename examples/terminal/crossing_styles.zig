//! Crossing Styles Demo — configurable edge crossing rendering.
//!
//! Shows the three crossing styles: flat (┼), arc (⌒), and gap (space).
//! Each style renders the same graph where edges visually cross.
//!
//! Run with: zig build run-terminal-crossing-styles

const std = @import("std");
const zigraph = @import("zigraph");

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Crossing Styles Demo                        ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // Build a K₃,₃-like graph where edge crossings are unavoidable.
    // Top layer: A, B, C — Bottom layer: D, E, F
    // Cross-edges force at least one visual crossing in the rendered output.

    const styles = [_]struct {
        name: []const u8,
        style: zigraph.terminal.CrossingStyle,
    }{
        .{ .name = "1) Flat (default) — edges merge into ┼ at crossings", .style = .flat },
        .{ .name = "2) Arc — horizontal edge hops over vertical with ⌒", .style = .arc },
        .{ .name = "3) Gap — horizontal edge breaks with a space", .style = .gap },
    };

    for (styles) |s| {
        printSection(s.name);

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // Top layer
        try g.addNode(1, "A");
        try g.addNode(2, "B");
        try g.addNode(3, "C");
        // Bottom layer
        try g.addNode(4, "D");
        try g.addNode(5, "E");
        try g.addNode(6, "F");

        // Straight edges to anchor positions
        try g.addDiEdge(1, 4); // A→D (left to left)
        try g.addDiEdge(2, 5); // B→E (center to center)
        try g.addDiEdge(3, 6); // C→F (right to right)

        // Cross-edges that must cross the straight edges
        try g.addDiEdge(1, 6); // A→F (left to right, crosses B→E and C→F)
        try g.addDiEdge(3, 4); // C→D (right to left, crosses B→E and A→D)

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .crossing_style = s.style,
            .color_mode = .ansi256,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
