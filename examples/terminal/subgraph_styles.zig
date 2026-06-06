//! Terminal Subgraph Styles — border types, colors, label positions, presets.
//!
//! Run with: zig build run-terminal-subgraph-styles

const std = @import("std");
const zigraph = @import("zigraph");

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n\n", .{});
}

/// Build a graph with a single subgraph containing two nodes.
fn buildFlatGraph(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "Read");
    try g.addNode(2, "Parse");
    try g.addNode(3, "Eval");

    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    const sg = try g.addSubgraph("Frontend");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    return g;
}

/// Build a graph with nested subgraphs (3 levels).
fn buildNestedGraph(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "Source");
    try g.addNode(2, "Lex");
    try g.addNode(3, "Parse");
    try g.addNode(4, "Optimize");
    try g.addNode(5, "Emit");

    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);
    try g.addEdge(4, 5);

    const outer = try g.addSubgraph("Compiler");
    const inner = try g.addSubgraph("Parser");

    try g.putNodes(&.{ 2, 3 }).inside(inner);
    try g.putNodes(&.{ 4, 5 }).inside(outer);
    try g.putSubgraphs(&.{inner}).inside(outer);

    return g;
}

/// Build a graph with two sibling subgraphs for side-by-side display.
fn buildSiblingGraph(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "Input");
    try g.addNode(2, "Validate");
    try g.addNode(3, "Transform");
    try g.addNode(4, "Store");
    try g.addNode(5, "Notify");
    try g.addNode(6, "Done");

    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);
    try g.addEdge(3, 5);
    try g.addEdge(4, 6);
    try g.addEdge(5, 6);

    const sg_proc = try g.addSubgraph("Processing");
    const sg_out = try g.addSubgraph("Output");

    try g.putNodes(&.{ 2, 3 }).inside(sg_proc);
    try g.putNodes(&.{ 4, 5 }).inside(sg_out);

    return g;
}

// ── Custom style functions ──────────────────────────────────────────────────

/// All subgraphs use heavy border.
fn heavyStyle(_: zigraph.SubgraphStyleContext) zigraph.TerminalSubgraphStyle {
    return .{ .border = .heavy };
}

/// Dashed border with inside labels.
fn dashedInsideStyle(_: zigraph.SubgraphStyleContext) zigraph.TerminalSubgraphStyle {
    return .{ .border = .dashed, .label_pos = .inside };
}

/// Centered label on single border.
fn centeredLabelStyle(_: zigraph.SubgraphStyleContext) zigraph.TerminalSubgraphStyle {
    return .{ .border = .single, .label_pos = .top_center };
}

/// Hide borders entirely (labels still visible inside the region).
fn noBorderStyle(_: zigraph.SubgraphStyleContext) zigraph.TerminalSubgraphStyle {
    return .{ .border = .none, .label_pos = .inside };
}

/// Color by depth — red for outer, green for inner.
fn colorByDepth(ctx: zigraph.SubgraphStyleContext) zigraph.TerminalSubgraphStyle {
    const colors = [_]zigraph.terminal.Color{
        .{ .rgb = .{ .r = 220, .g = 80, .b = 80 } }, // red
        .{ .rgb = .{ .r = 80, .g = 200, .b = 120 } }, // green
        .{ .rgb = .{ .r = 80, .g = 140, .b = 220 } }, // blue
    };
    return .{
        .border = .double,
        .color = colors[ctx.depth % colors.len],
        .label_pos = .top_left,
    };
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║  Terminal Subgraph Styles Demo                          ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) Default (double border, top-left label)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) Default: double border, top-left label");

        var g = try buildFlatGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 2) Single border with centered label
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) Single border, centered label");

        var g = try buildFlatGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .subgraph_style_fn = &centeredLabelStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 3) Heavy border
    // ─────────────────────────────────────────────────────────────
    {
        printSection("3) Heavy border");

        var g = try buildFlatGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .subgraph_style_fn = &heavyStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 4) Dashed border with inside label
    // ─────────────────────────────────────────────────────────────
    {
        printSection("4) Dashed border, inside label");

        var g = try buildFlatGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .subgraph_style_fn = &dashedInsideStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 5) No border (label only)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("5) No border (label only)");

        var g = try buildFlatGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .subgraph_style_fn = &noBorderStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 6) Depth-cycled preset — ANSI 256 colors (nested subgraphs)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("6) Depth-cycled preset, ANSI 256 (nested subgraphs)");

        var g = try buildNestedGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .subgraph_style_fn = &zigraph.terminal_subgraph_presets.depthCycled,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        std.debug.print("  (Outer = double/blue, inner = single/cyan — style cycles by depth)\n", .{});
    }

    // ─────────────────────────────────────────────────────────────
    // 7) Custom color by depth (truecolor)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("7) Custom RGB color by depth (truecolor)");

        var g = try buildNestedGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .truecolor,
            .subgraph_style_fn = &colorByDepth,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        std.debug.print("  (Red = depth 0, green = depth 1, blue = depth 2)\n", .{});
    }

    // ─────────────────────────────────────────────────────────────
    // 8) Sibling subgraphs with double borders + truecolor
    // ─────────────────────────────────────────────────────────────
    {
        printSection("8) Sibling subgraphs (double + truecolor)");

        var g = try buildSiblingGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .truecolor,
            .subgraph_style_fn = &colorByDepth,
            .node_style_fn = &zigraph.terminal_node_presets.roundedBox,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 9) Combined: subgraph + node styles, ANSI 256
    // ─────────────────────────────────────────────────────────────
    {
        printSection("9) Combined: subgraph + node styles, ANSI 256");

        var g = try buildNestedGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .subgraph_style_fn = &zigraph.terminal_subgraph_presets.depthCycled,
            .node_style_fn = &zigraph.terminal_node_presets.singleBox,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        std.debug.print("  (Single-box nodes inside depth-cycled subgraphs)\n", .{});
    }
}
