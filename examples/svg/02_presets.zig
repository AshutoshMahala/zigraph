//! # 02 — Presets
//!
//! Change the entire look of your graph with one-liner config changes.
//! No custom functions needed — just swap a preset.
//!
//! Generates three SVGs from the same graph:
//!   • **default** — rounded rectangles, Radix palette
//!   • **diamonds** — diamond nodes, monochrome edges
//!   • **ellipses** — ellipse nodes, vibrant palette
//!
//! **What you'll learn:** built-in shape presets and edge style presets.
//!
//! Run: `zig build run-svg-02`

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n── 02: Presets ──\n\n", .{});

    // Same graph for all three variations
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "Parse");
    try g.addNode(3, "Validate");
    try g.addNode(4, "Transform");
    try g.addNode(5, "Output");

    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 5);
    try g.addEdge(4, 5);

    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    // ── Variation 1: Default (rounded rectangles, Radix colors) ─────────
    {
        const svg = try zigraph.svg.render(&ir, allocator, .{});
        defer allocator.free(svg);
        try writeSvg("02_preset_default", svg);
    }

    // ── Variation 2: Diamond nodes, monochrome edges ────────────────────
    //    Just swap one field each — that's it.
    {
        const svg = try zigraph.svg.render(&ir, allocator, .{
            .node_style_fn = &zigraph.shapes.diamond,
            .edge_style_fn = &zigraph.svg.monoEdgeStyle,
        });
        defer allocator.free(svg);
        try writeSvg("02_preset_diamond", svg);
    }

    // ── Variation 3: Ellipse nodes, vibrant palette ─────────────────────
    {
        const svg = try zigraph.svg.render(&ir, allocator, .{
            .node_style_fn = &zigraph.shapes.ellipse,
            .edge_style_fn = &struct {
                fn style(ctx: zigraph.EdgeStyleContext) zigraph.EdgeStyle {
                    return .{
                        .stroke = zigraph.color.get(&zigraph.color.vibrant, ctx.edge_index),
                        .marker_end = if (ctx.directed) .arrow else .none,
                    };
                }
            }.style,
        });
        defer allocator.free(svg);
        try writeSvg("02_preset_ellipse", svg);
    }

    std.debug.print("\n  Same graph, three looks — just by changing presets.\n\n", .{});
}
