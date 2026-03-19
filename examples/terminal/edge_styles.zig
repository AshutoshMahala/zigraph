//! Terminal Edge Styles — line weights and marker shapes.
//!
//! Demonstrates Topics 3 (Edge Line Styles) and 4 (Arrow/Marker Characters):
//! 1. Default — light weight, filled-arrow markers
//! 2. Heavy weight — ━ ┃ characters for emphasis
//! 3. Double weight — ═ ║ characters for strong distinction
//! 4. Dashed weight — ┈ ┊ characters (reversed / back-edges)
//! 5. Mixed weights — critical path heavy, others light
//! 6. Marker shapes — arrow, open_arrow, diamond, circle, open_circle, none
//! 7. Bidirectional markers — marker_start + marker_end
//!
//! Run with: zig build run-terminal-edge-styles

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

fn heavyStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .weight = .heavy };
}

fn doubleStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .weight = .double };
}

fn dashedStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .weight = .dashed };
}

/// Critical path (by edge_index 0): heavy. Everything else: light.
fn criticalPathStyle(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .weight = if (ctx.edge_index == 0) .heavy else .light };
}

/// Map edge_index to a marker shape to show all available shapes.
fn markerShapeStyle(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    const shapes = [_]zigraph.MarkerShape{
        .arrow,
        .open_arrow,
        .diamond,
        .open_diamond,
        .circle,
        .open_circle,
    };
    return .{ .marker_end = shapes[ctx.edge_index % shapes.len] };
}

/// Both ends have markers — bidirectional / association edges.
fn biDirectionalStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .marker_start = .open_circle, .marker_end = .arrow };
}

/// No marker at the end — plain line.
fn noMarkerStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .marker_end = .none };
}

// ── Graph builders ────────────────────────────────────────────────────────────

/// Simple pipeline: A → B → C → D (four edges, four weights available)
fn buildPipeline(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);
    return g;
}

/// Six-node chain — one edge per marker shape.
fn buildMarkerChain(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    const labels = [_][]const u8{ "N1", "N2", "N3", "N4", "N5", "N6", "N7" };
    for (labels, 1..) |lbl, id| try g.addNode(id, lbl);
    for (1..labels.len) |from| try g.addEdge(from, from + 1);
    return g;
}

/// Three-node fan — bidirectional edges.
fn buildFan(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "Hub");
    try g.addNode(2, "X");
    try g.addNode(3, "Y");
    try g.addNode(4, "Z");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(1, 4);
    return g;
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Terminal Edge Styles Demo                   ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) Default: light weight, ↓↑→← arrows
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) Default: light weight  ─ │ ↓");

        var g = try buildPipeline(allocator);
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
    // 2) Heavy weight ━ ┃ ▼
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) Heavy weight  ━ ┃ ▼");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_style_fn = &heavyStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 3) Double weight ═ ║
    // ─────────────────────────────────────────────────────────────
    {
        printSection("3) Double weight  ═ ║");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_style_fn = &doubleStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 4) Dashed weight ┈ ┊ (back-edges / reversed)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("4) Dashed weight  ┈ ┊  (back-edges)");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_style_fn = &dashedStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 5) Mixed weights via edge_style_fn
    //    edge 0 = critical path (heavy), rest = light
    // ─────────────────────────────────────────────────────────────
    {
        printSection("5) Mixed: critical path heavy, others light");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_style_fn = &criticalPathStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        std.debug.print("Note: edge 0 (A→B) is heavy, edges 1–2 are light.\n\n", .{});
    }

    // ─────────────────────────────────────────────────────────────
    // 6) Marker shapes — each edge gets a different marker_end
    //    arrow | open_arrow | diamond | open_diamond | circle | open_circle
    // ─────────────────────────────────────────────────────────────
    {
        printSection("6) Marker shapes (one per edge)");

        var g = try buildMarkerChain(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_style_fn = &markerShapeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        std.debug.print(
            \\Markers in order (edge 0→5):
            \\  ▼ arrow  ▷ open_arrow  ◆ diamond  ◇ open_diamond  ● circle  ○ open_circle
            \\
            \\
        , .{});
    }

    // ─────────────────────────────────────────────────────────────
    // 7) Bidirectional markers: marker_start + marker_end
    // ─────────────────────────────────────────────────────────────
    {
        printSection("7) Bidirectional markers  ○──── ▼");

        var g = try buildFan(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_style_fn = &biDirectionalStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 8) No markers — plain lines
    // ─────────────────────────────────────────────────────────────
    {
        printSection("8) No markers  (marker_end = .none)");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .none,
            .edge_style_fn = &noMarkerStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
