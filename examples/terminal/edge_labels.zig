//! Terminal Edge Labels — placement modes and color overrides.
//!
//! Demonstrates the `edge_label_style_fn` hook and `LabelPlacement` options:
//! 1. Default (auto) — labels placed inline near the IR-computed position
//! 2. near_source — each label hugs the start of its edge
//! 3. near_target — each label hugs the end of its edge
//! 4. center — labels sit at the midpoint of the edge
//! 5. Color override — per-edge label colors independent of the edge color
//! 6. Legend fallback — labels that cannot be placed inline appear as a legend
//!
//! Run with: zig build run-terminal-edge-labels

const std = @import("std");
const zigraph = @import("zigraph");

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n\n", .{});
}

// ── Style functions ───────────────────────────────────────────────────────────

fn nearSourceStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    return .{ .placement = .near_source };
}

fn nearTargetStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    return .{ .placement = .near_target };
}

fn centerStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    return .{ .placement = .center };
}

/// Color each label based on its edge_index so they are visually distinct.
fn coloredLabelStyle(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    const palette = [_]zigraph.TerminalColor{
        .{ .ansi256 = 196 }, // red
        .{ .ansi256 = 46 },  // green
        .{ .ansi256 = 33 },  // blue
        .{ .ansi256 = 226 }, // yellow
        .{ .ansi256 = 201 }, // magenta
    };
    return .{
        .color = palette[ctx.edge_index % palette.len],
        .placement = .center,
    };
}

// ── Graph builders ────────────────────────────────────────────────────────────

/// A simple pipeline: Build → Test → Lint → Deploy
fn buildPipelineGraph(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "Build");
    try g.addNode(2, "Test");
    try g.addNode(3, "Lint");
    try g.addNode(4, "Deploy");

    try g.addEdgeLabeled(1, 2, "compile");
    try g.addEdgeLabeled(2, 3, "check");
    try g.addEdgeLabeled(3, 4, "ship");

    return g;
}

/// A dependency graph with several labeled edges that may need legend fallback.
fn buildDependencyGraph(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "App");
    try g.addNode(2, "Auth");
    try g.addNode(3, "DB");
    try g.addNode(4, "Cache");

    try g.addEdgeLabeled(1, 2, "requires");
    try g.addEdgeLabeled(1, 3, "reads");
    try g.addEdgeLabeled(2, 3, "queries");
    try g.addEdgeLabeled(1, 4, "uses");

    return g;
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Terminal Edge Labels Demo                   ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) Default (auto) placement
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) Default: auto placement");

        var g = try buildPipelineGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 2) near_source placement
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) near_source placement");

        var g = try buildPipelineGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_label_style_fn = &nearSourceStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 3) near_target placement
    // ─────────────────────────────────────────────────────────────
    {
        printSection("3) near_target placement");

        var g = try buildPipelineGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_label_style_fn = &nearTargetStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 4) center placement
    // ─────────────────────────────────────────────────────────────
    {
        printSection("4) center placement");

        var g = try buildPipelineGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_label_style_fn = &centerStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 5) Per-edge label color override
    // ─────────────────────────────────────────────────────────────
    {
        printSection("5) Per-edge label color (ANSI 256)");

        var g = try buildPipelineGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .edge_label_style_fn = &coloredLabelStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 6) Legend fallback (dense graph, many labels)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("6) Legend fallback (dense graph)");

        var g = try buildDependencyGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
