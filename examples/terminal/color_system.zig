//! Terminal Color System — ColorMode, flat colors, gradients, node colors.
//!
//! Demonstrates Topic 5 (Color System):
//! 1. No color — plain text, suitable for CI logs and piped output
//! 2. ANSI 256 — broad terminal compatibility (\e[38;5;Nm)
//! 3. Truecolor (RGB) — 24-bit color on modern terminals (\e[38;2;R;G;Bm)
//! 4. Gradient edge — per-cell color sampled from a ColorMap
//! 5. Palette edge coloring — each edge picks from a discrete palette
//! 6. Node colors — border_color, text_color, and bg_color
//! 7. TextAttrs — bold, dim, italic, underline on node labels
//!
//! Run with: zig build run-terminal-color-system

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

/// Each edge gets a manually assigned ANSI 256 color.
fn ansi256EdgeStyle(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    const palette = [_]u8{ 196, 46, 33, 226, 201 }; // red, green, blue, yellow, magenta
    return .{ .color = .{ .ansi256 = palette[ctx.edge_index % palette.len] } };
}

/// Each edge gets a manually assigned RGB truecolor.
fn truecolorEdgeStyle(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    const palette = [_]zigraph.TerminalColor{
        .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, // coral red
        .{ .rgb = .{ .r = 80, .g = 220, .b = 120 } }, // mint green
        .{ .rgb = .{ .r = 80, .g = 140, .b = 255 } }, // sky blue
        .{ .rgb = .{ .r = 240, .g = 200, .b = 60 } }, // golden yellow
    };
    return .{ .color = palette[ctx.edge_index % palette.len] };
}

/// Per-edge viridis gradient: each edge gets a different slice of the colormap.
fn gradientEdgeStyle(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    const n = @as(f32, @floatFromInt(ctx.total_edges));
    const i = @as(f32, @floatFromInt(ctx.edge_index));
    const from = i / n;
    const to = (i + 1.0) / n;
    return .{
        .color = .{ .gradient = .{
            .map = &zigraph.color.ColorMap.viridis,
            .from = from,
            .to = to,
        } },
    };
}

/// Discrete ANSI palette via `zigraph.color.getAnsi` helper.
fn paletteEdgeStyle(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .color = .{
        .ansi256 = zigraph.color.getAnsi(&zigraph.color.ansi_dark, ctx.edge_index),
    } };
}

/// Colored node borders + colored labels.
fn coloredNodeStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    const border_colors = [_]zigraph.TerminalColor{
        .{ .ansi256 = 196 }, // red
        .{ .ansi256 = 46 }, // green
        .{ .ansi256 = 33 }, // blue
        .{ .ansi256 = 226 }, // yellow
    };
    return .{
        .border = .single_box,
        .border_color = border_colors[ctx.node_id % border_colors.len],
        .text_color = .{ .ansi256 = 255 }, // white text
    };
}

/// Node with a background color fill.
fn bgColorNodeStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    const bg_colors = [_]zigraph.TerminalColor{
        .{ .ansi256 = 52 }, // dark red
        .{ .ansi256 = 22 }, // dark green
        .{ .ansi256 = 17 }, // dark blue
        .{ .ansi256 = 58 }, // dark yellow
    };
    return .{
        .border = .single_box,
        .bg_color = bg_colors[ctx.node_id % bg_colors.len],
        .text_color = .{ .ansi256 = 255 }, // white text on dark bg
    };
}

/// TextAttrs: bold on even node indices, italic on odd ones.
fn textAttrsNodeStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    const is_even = ctx.node_id % 2 == 0;
    return .{
        .border = .single_box,
        .attrs = .{
            .bold = is_even,
            .italic = !is_even,
        },
    };
}

// ── Graph builder ─────────────────────────────────────────────────────────────

fn buildGraph(allocator: std.mem.Allocator) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "Input");
    try g.addNode(2, "Parse");
    try g.addNode(3, "Check");
    try g.addNode(4, "Emit");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);
    return g;
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Terminal Color System Demo                  ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) No color — plain text, CI-friendly
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) color_mode = .none  (plain text, CI-friendly)");

        var g = try buildGraph(allocator);
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
    // 2) ANSI 256 — broad compatibility (\e[38;5;Nm)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) color_mode = .ansi256  (\\e[38;5;Nm)");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .edge_style_fn = &ansi256EdgeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 3) Truecolor RGB — 24-bit color (\e[38;2;R;G;Bm)
    // ─────────────────────────────────────────────────────────────
    {
        printSection("3) color_mode = .truecolor  (\\e[38;2;R;G;Bm)");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .truecolor,
            .edge_style_fn = &truecolorEdgeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 4) Gradient edge — per-cell color sampled from viridis
    // ─────────────────────────────────────────────────────────────
    {
        printSection("4) Gradient edges — viridis colormap");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .truecolor,
            .edge_style_fn = &gradientEdgeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 5) Discrete palette via zigraph.color.getAnsi
    // ─────────────────────────────────────────────────────────────
    {
        printSection("5) Discrete palette (zigraph.color.ansi_dark)");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .edge_style_fn = &paletteEdgeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 6) Node colors — border_color + text_color
    // ─────────────────────────────────────────────────────────────
    {
        printSection("6) Node colors — border_color + text_color");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &coloredNodeStyle,
            .edge_palette = &zigraph.color.ansi_dark,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 7) Node bg_color — background fill behind node text
    // ─────────────────────────────────────────────────────────────
    {
        printSection("7) Node bg_color — background fill");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &bgColorNodeStyle,
            .edge_palette = &zigraph.color.ansi_dark,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 8) TextAttrs — bold and italic on node labels
    // ─────────────────────────────────────────────────────────────
    {
        printSection("8) TextAttrs — bold (even) and italic (odd) nodes");

        var g = try buildGraph(allocator);
        defer g.deinit();

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &textAttrsNodeStyle,
            .edge_palette = &zigraph.color.ansi_dark,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
