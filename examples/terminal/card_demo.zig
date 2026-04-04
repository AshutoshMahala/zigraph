//! Card Node Demo — multi-line boxes in graph layouts.
//!
//! Demonstrates card nodes (nodes with multi-line content) in two real-world
//! graph layouts:
//! 1. Data flow — catalog/mesh feeding into item metadata
//! 2. Architecture — VLM pipeline feeding into downstream services
//!
//! Run with: zig build run-terminal-card-demo

const std = @import("std");
const zigraph = @import("zigraph");

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Card Node Demo                              ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) Data flow: Catalog + Mesh → ItemMetadata
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) Data flow: Catalog + Mesh → ItemMetadata");

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        const catalog_lines: []const []const u8 = &.{ "Game (price)", "Brand info", "" };
        try g.addNode(1, zigraph.NodeOptions{
            .label = "Catalog",
            .lines = catalog_lines,
        });

        const mesh_lines: []const []const u8 = &.{ "(dims +", " geometry)" };
        try g.addNode(2, zigraph.NodeOptions{
            .label = "Mesh",
            .lines = mesh_lines,
        });

        const meta_lines: []const []const u8 = &.{ "catalog | game | graphics", "mesh | visual" };
        try g.addNode(3, zigraph.NodeOptions{
            .label = "ItemMetadata (Spanner)",
            .lines = meta_lines,
        });

        try g.addDiEdge(1, 3);
        try g.addDiEdge(2, 3);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &cardNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 2) Architecture: VLM pipeline → Downstream
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) Architecture: VLM pipeline → Downstream");

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        const showroom_lines: []const []const u8 = &.{ "(not yet", " connected)" };
        try g.addNode(10, zigraph.NodeOptions{
            .label = "Designer showroom",
            .lines = showroom_lines,
        });

        const review_lines: []const []const u8 = &.{"(corrections)"};
        try g.addNode(11, zigraph.NodeOptions{
            .label = "Human review",
            .lines = review_lines,
        });

        const vlm_lines: []const []const u8 = &.{ "(thumbnail ->", " 2-pass extract)" };
        try g.addNode(12, zigraph.NodeOptions{
            .label = "VLM pipeline",
            .lines = vlm_lines,
        });

        const downstream_lines: []const []const u8 = &.{ "quest matching", "search, recs" };
        try g.addNode(13, zigraph.NodeOptions{
            .label = "Downstream",
            .lines = downstream_lines,
        });

        try g.addDiEdge(11, 13);
        try g.addDiEdge(12, 13);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &cardNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}

fn cardNodeStyle(_: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    return .{
        .border = .single_box,
        .text_color = .{ .ansi256 = 252 }, // light gray
    };
}
