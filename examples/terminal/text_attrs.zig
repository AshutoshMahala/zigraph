//! Terminal Text Attributes — bold, dim, italic, underline on labels.
//!
//! Demonstrates all four text attributes across three style hooks:
//! 1. Bold node labels — emphasize important nodes
//! 2. Italic edge labels — stylish inline annotations
//! 3. Combined bold + underline — maximum emphasis
//! 4. Dim nodes — de-emphasize background/utility nodes
//! 5. All attributes together — combined demonstration
//! 6. Subgraph label attrs — bold/italic group titles
//!
//! Run with: zig build run-terminal-text-attrs

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

/// Bold node labels to emphasize important nodes.
fn boldNodeStyle(_: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    return .{
        .border = .single_box,
        .text_color = .{ .ansi256 = 46 }, // green
        .attrs = .{ .bold = true },
    };
}

/// Dim nodes for background/utility steps.
fn dimNodeStyle(_: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    return .{
        .border = .bracket,
        .text_color = .{ .ansi256 = 250 }, // light gray
        .attrs = .{ .dim = true },
    };
}

/// Selectively style nodes: bold for entry/exit, dim for internal.
fn mixedNodeStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    // First and last nodes get bold, middle nodes get dim
    const is_endpoint = ctx.node_id == 1 or ctx.node_id == 5;
    if (is_endpoint) {
        return .{
            .border = .single_box,
            .text_color = .{ .ansi256 = 226 }, // yellow
            .attrs = .{ .bold = true, .underline = true },
        };
    }
    return .{
        .border = .bracket,
        .attrs = .{ .dim = true },
    };
}

/// Italic edge labels for stylish annotations.
fn italicEdgeLabelStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    return .{
        .attrs = .{ .italic = true },
        .color = .{ .ansi256 = 33 }, // blue
    };
}

/// Bold edge labels for critical-path annotations.
fn boldEdgeLabelStyle(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    return .{
        .attrs = .{ .bold = true },
        .color = .{ .ansi256 = 196 }, // red
    };
}

/// Each attribute on a different node — visual reference card.
fn allAttrsNodeStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    const styles = [_]zigraph.TextAttrs{
        .{ .bold = true }, // node 1
        .{ .dim = true }, // node 2
        .{ .italic = true }, // node 3
        .{ .underline = true }, // node 4
        .{ .bold = true, .italic = true }, // node 5
    };
    const idx = if (ctx.node_id >= 1 and ctx.node_id <= 5) ctx.node_id - 1 else 0;
    return .{
        .border = .single_box,
        .text_color = .{ .ansi256 = 255 },
        .attrs = styles[idx],
    };
}

/// Bold subgraph label to emphasize group titles.
fn boldSubgraphStyle(_: zigraph.SubgraphStyleContext) zigraph.TerminalSubgraphStyle {
    return .{
        .border = .double,
        .color = .{ .ansi256 = 33 }, // blue
        .attrs = .{ .bold = true },
    };
}

// ── Graph builders ────────────────────────────────────────────────────────────

fn buildPipeline(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "Input");
    try g.addNode(2, "Parse");
    try g.addNode(3, "Validate");
    try g.addNode(4, "Transform");
    try g.addNode(5, "Output");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);
    try g.addEdge(4, 5);
    return g;
}

fn buildLabeledPipeline(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "Fetch");
    try g.addNode(2, "Decode");
    try g.addNode(3, "Execute");
    try g.addNode(4, "Store");
    try g.addEdgeLabeled(1, 2, "HTTP");
    try g.addEdgeLabeled(2, 3, "JSON");
    try g.addEdgeLabeled(3, 4, "result");
    return g;
}

fn buildSubgraphPipeline(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "Read");
    try g.addNode(2, "Process");
    try g.addNode(3, "Write");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    const sg = try g.addSubgraph("Pipeline");
    try g.putNodes(&.{ 1, 2, 3 }).inside(sg);
    return g;
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Terminal Text Attributes Demo               ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) Bold node labels — all nodes bold with green text
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) Bold node labels  (.attrs = .{ .bold = true })");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &boldNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 2) Dim nodes — subdued utility steps
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) Dim node labels  (.attrs = .{ .dim = true })");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &dimNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 3) Mixed — bold+underline endpoints, dim internal nodes
    // ─────────────────────────────────────────────────────────────
    {
        printSection("3) Mixed: bold+underline endpoints, dim internals");

        var g = try buildPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &mixedNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 4) Italic edge labels
    // ─────────────────────────────────────────────────────────────
    {
        printSection("4) Italic edge labels  (.attrs = .{ .italic = true })");

        var g = try buildLabeledPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .edge_label_style_fn = &italicEdgeLabelStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 5) Bold edge labels
    // ─────────────────────────────────────────────────────────────
    {
        printSection("5) Bold edge labels  (.attrs = .{ .bold = true })");

        var g = try buildLabeledPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .edge_label_style_fn = &boldEdgeLabelStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 6) Reference card — one attribute per node
    // ─────────────────────────────────────────────────────────────
    {
        printSection("6) Reference card: bold / dim / italic / underline / bold+italic");

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();
        try g.addNode(1, "BOLD");
        try g.addNode(2, "DIM");
        try g.addNode(3, "ITALIC");
        try g.addNode(4, "UNDERLINE");
        try g.addNode(5, "BOLD+ITALIC");
        try g.addEdge(1, 2);
        try g.addEdge(2, 3);
        try g.addEdge(3, 4);
        try g.addEdge(4, 5);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .truecolor,
            .node_style_fn = &allAttrsNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 7) Subgraph label with bold attrs
    // ─────────────────────────────────────────────────────────────
    {
        printSection("7) Subgraph label  (.attrs = .{ .bold = true })");

        var g = try buildSubgraphPipeline(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .subgraph_style_fn = &boldSubgraphStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
