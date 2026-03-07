//! # 05 — Dark Theme
//!
//! A fully coordinated dark theme using all 4 style functions + `global_style`.
//! Shows how every piece works together for a cohesive look.
//!
//! **What you'll learn:** coordinating `node_style_fn`, `edge_style_fn`,
//! `subgraph_style_fn`, `edge_label_style_fn`, and `global_style`
//! for a complete visual theme.
//!
//! Run: `zig build run-svg-05`

const std = @import("std");
const zigraph = @import("zigraph");

fn writeSvg(name: []const u8, svg: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "assets/gallery/{s}.svg", .{name}) catch return;
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(svg);
    std.debug.print("  ✓ {s} ({d} bytes)\n", .{ path, svg.len });
}

// ── Dark palette ───────────────────────────────────────────────────────────

const bg = "#1e1e2e"; // Catppuccin Mocha base
const surface = "#313244";
const overlay = "#45475a";
const text_color = "#cdd6f4";
const subtext = "#a6adc8";
const blue = "#89b4fa";
const green = "#a6e3a1";
const peach = "#fab387";
const red = "#f38ba8";
const mauve = "#cba6f7";

const edge_colors = [_][]const u8{ blue, green, peach, red, mauve };

// ── Style functions ────────────────────────────────────────────────────────

fn darkNode(ctx: zigraph.NodeStyleContext) zigraph.NodeStyle {
    return .{
        .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<rect x="0" y="0" width="{d}" height="{d}" rx="6" ry="6"/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="{s}" stroke="none">{s}</text>
        , .{ ctx.width, ctx.height, ctx.width / 2, ctx.height / 2 + 4, text_color, ctx.label }) catch "",
        .fill = surface,
        .stroke = overlay,
    };
}

fn darkEdge(ctx: zigraph.EdgeStyleContext) zigraph.EdgeStyle {
    const color = edge_colors[ctx.edge_index % edge_colors.len];
    return .{
        .stroke = color,
        .marker_end = if (ctx.directed) .arrow else .none,
    };
}

fn darkLabel(ctx: zigraph.EdgeStyleContext) zigraph.EdgeLabelStyle {
    const color = edge_colors[ctx.edge_index % edge_colors.len];
    return .{
        .color = color,
        .font_size = 11,
    };
}

fn darkCluster(ctx: zigraph.SubgraphStyleContext) zigraph.SubgraphStyle {
    return .{
        .box_svg = std.fmt.allocPrint(ctx.arena,
            \\<rect x="0" y="0" width="{d}" height="{d}" rx="8" ry="8" stroke-dasharray="6,3"/>
            \\<text x="8" y="16" font-family="monospace" font-size="11" font-weight="bold" fill="{s}" stroke="none">{s}</text>
        , .{ ctx.width, ctx.height, subtext, ctx.label }) catch "",
        .fill = overlay,
        .fill_opacity = "0.3",
        .stroke = subtext,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n── 05: Dark Theme ──\n\n", .{});

    // Build a compiler pipeline
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Source");
    try g.addNode(2, "Lexer");
    try g.addNode(3, "Parser");
    try g.addNode(4, "AST");
    try g.addNode(5, "Sema");
    try g.addNode(6, "IR");
    try g.addNode(7, "Optimize");
    try g.addNode(8, "Codegen");

    try g.addEdgeLabeled(1, 2, "tokenize");
    try g.addEdgeLabeled(2, 3, "tokens");
    try g.addEdge(3, 4);
    try g.addEdgeLabeled(4, 5, "check");
    try g.addEdge(5, 6);
    try g.addEdgeLabeled(6, 7, "passes");
    try g.addEdgeLabeled(7, 8, "emit");

    // Group into phases
    const frontend = try g.addSubgraph("Frontend");
    const backend = try g.addSubgraph("Backend");
    try g.putNodes(&.{ 1, 2, 3, 4 }).inside(frontend);
    try g.putNodes(&.{ 6, 7, 8 }).inside(backend);

    var ir = try zigraph.layout(&g, allocator, .{
        .positioning = .brandes_kopf,
    });
    defer ir.deinit();

    // The dark background is set via global_style, overriding the default white rect
    const svg = try zigraph.svg.render(&ir, allocator, .{
        .node_style_fn = &darkNode,
        .edge_style_fn = &darkEdge,
        .edge_label_style_fn = &darkLabel,
        .subgraph_style_fn = &darkCluster,
        .global_style =
            \\<style>
            \\  svg { background: #1e1e2e; }
            \\  rect[width="100%"] { fill: #1e1e2e; }
            \\</style>
        ,
    });
    defer allocator.free(svg);

    try writeSvg("05_dark_theme", svg);
    std.debug.print("\n  Catppuccin Mocha theme — all 4 style functions working together.\n\n", .{});
}
