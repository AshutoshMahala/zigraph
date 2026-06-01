//! Terminal Node Control — box types, implicit vs explicit, dummy nodes.
//!
//! Run with: zig build run-terminal-node-control

const std = @import("std");
const zigraph = @import("zigraph");

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("─", .{});
    std.debug.print("\n\n", .{});
}

/// Build a graph with both explicit and implicit nodes.
/// - Explicit: Parse, Compile, Link (added via addNode)
/// - Implicit: Optimize (only referenced via edges, auto-created)
/// - The long edge Parse→Link will produce dummy nodes internally.
fn buildGraph(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();

    // Explicit nodes — user-defined
    try g.addNode(1, "Parse");
    try g.addNode(2, "Compile");
    try g.addNode(3, "Link");

    // Edges — node 4 "Optimize" is NOT added via addNode, so it becomes implicit
    try g.addEdgeAutoCreate(1, 4); // Parse → Optimize (implicit)
    try g.addEdge(1, 2); // Parse → Compile
    try g.addEdge(2, 3); // Compile → Link
    try g.addEdgeAutoCreate(4, 3); // Optimize → Link

    // Long edge to force dummy nodes in layout
    try g.addEdge(1, 3); // Parse → Link (spans 2+ levels)

    return g;
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║  Terminal Node Control Demo                              ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) Default rendering — bracket for explicit, angle for implicit
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) Default: [explicit] vs <implicit>");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.render(&ir, allocator);
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    //  2) Single-box preset — closed box for explicit, open for implicit
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) Single-box preset: closed=explicit, open=implicit");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .node_style_fn = &zigraph.terminal_node_presets.singleBox,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    //  3) Rounded-box preset — same idea, rounded corners
    // ─────────────────────────────────────────────────────────────
    {
        printSection("3) Rounded-box preset: closed=explicit, open=implicit");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .node_style_fn = &zigraph.terminal_node_presets.roundedBox,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    //  4) All same: double-box for EVERY node (no differentiation)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("4) No differentiation: every node = double box");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .node_style_fn = &allDoubleBox,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    //  5) Mix-and-match — per-node custom style via label
    // ─────────────────────────────────────────────────────────────
    {
        printSection("5) Mix-and-match: different box per node label");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .node_style_fn = &perLabelStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    //  6) Dummy nodes visible — layout debugging
    // ─────────────────────────────────────────────────────────────
    {
        printSection("6) Dummy nodes visible (layout debugging)");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .show_dummy_nodes = true,
            .node_style_fn = &zigraph.terminal_node_presets.singleBox,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        std.debug.print("  (Dummy nodes appear as their internal label — layout artifacts\n", .{});
        std.debug.print("   placed where long edges cross intermediate levels.)\n", .{});
    }

    // ─────────────────────────────────────────────────────────────
    //  7) Per-node border / text / background colors
    // ─────────────────────────────────────────────────────────────
    {
        printSection("7) Border, text, and background colors");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .truecolor,
            .node_style_fn = &colorfulStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    //  8) Gradient border + background (turbo & viridis)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("8) Gradient border + background (turbo & viridis)");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .truecolor,
            .node_style_fn = &gradientStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}

// ── Custom style functions ──────────────────────────────────────────────────

/// Every node gets the same double-box — no implicit/explicit difference.
fn allDoubleBox(_: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    return .{ .border = .double_box };
}

/// Pick a different box style based on node label.
fn perLabelStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    if (std.mem.eql(u8, ctx.label, "Parse"))
        return .{ .border = .heavy_box, .border_color = .{ .ansi256 = 196 }, .text_color = .{ .ansi256 = 196 } }; // red
    if (std.mem.eql(u8, ctx.label, "Compile"))
        return .{ .border = .rounded_box, .border_color = .{ .ansi256 = 33 }, .text_color = .{ .ansi256 = 33 } }; // blue
    if (std.mem.eql(u8, ctx.label, "Link"))
        return .{ .border = .double_box, .border_color = .{ .ansi256 = 34 }, .text_color = .{ .ansi256 = 34 } }; // green
    // Implicit / unknown → open single
    return .{ .border = .open_single, .border_color = .{ .ansi256 = 245 }, .text_color = .{ .ansi256 = 245 } }; // gray
}

/// Demonstrate border, text, and background colors independently.
fn colorfulStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    if (std.mem.eql(u8, ctx.label, "Parse"))
        return .{
            .border = .rounded_box,
            .border_color = .{ .rgb = .{ .r = 0, .g = 204, .b = 255 } }, // cyan border
            .text_color = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }, // white text
            .bg_color = .{ .rgb = .{ .r = 25, .g = 25, .b = 76 } }, // dark blue bg
        };
    if (std.mem.eql(u8, ctx.label, "Compile"))
        return .{
            .border = .single_box,
            .border_color = .{ .rgb = .{ .r = 255, .g = 128, .b = 0 } }, // orange border
            .text_color = .{ .ansi256 = 226 }, // yellow text
            .bg_color = .{ .rgb = .{ .r = 51, .g = 0, .b = 0 } }, // dark red bg
        };
    if (std.mem.eql(u8, ctx.label, "Link"))
        return .{
            .border = .double_box,
            .border_color = .{ .rgb = .{ .r = 0, .g = 255, .b = 102 } }, // green border
            .text_color = .{ .rgb = .{ .r = 0, .g = 255, .b = 102 } }, // green text
        };
    return .{};
}

/// Demonstrate gradient border and background colors using scientific colormaps.
fn gradientStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    if (std.mem.eql(u8, ctx.label, "Compile"))
        return .{
            .border = .single_box,
            .border_color = .{ .ansi256 = 255 },
            .text_color = .{ .ansi256 = 255 }, // white text
            .bg_color = .{ .gradient = .{
                .map = &zigraph.color.ColorMap.viridis,
                .from = 0.0,
                .to = 1.0,
            } },
        };
    return .{
        .border = .rounded_box,
        .border_color = .{ .gradient = .{
            .map = &zigraph.color.ColorMap.turbo,
            .from = 0.0,
            .to = 1.0,
        } },
        .text_color = .{ .ansi256 = 255 }, // bright white text
    };
}
