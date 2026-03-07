//! # 03 — Flowchart
//!
//! A real-world use case: a flowchart with conditional node shapes.
//! Diamonds for decisions, parallelograms for I/O, rounded rects for process.
//!
//! Also demonstrates edge labels with custom styling —
//! "yes"/"no" labels colored green/red on decision branches.
//!
//! **What you'll learn:** custom `node_style_fn` with per-node logic,
//! custom `edge_label_style_fn` with semantic coloring.
//!
//! Run: `zig build run-svg-03`

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

// ── Node styling: shape depends on the node's role ─────────────────────────
//
// We encode the role in the label prefix:
//   "⬦ ..." → diamond (decision)
//   "▱ ..." → parallelogram (I/O)
//   everything else → rounded rectangle (process)
//
// This is a simple convention — in a real app you might use node metadata.

fn flowchartNode(ctx: zigraph.NodeStyleContext) zigraph.NodeStyle {
    // Decision nodes (label starts with a diamond marker)
    if (std.mem.startsWith(u8, ctx.label, "?")) {
        var style = zigraph.shapes.diamond(ctx);
        style.fill = "#fff8e1";
        style.stroke = "#f59e0b";
        return style;
    }

    // I/O nodes
    if (std.mem.startsWith(u8, ctx.label, ">")) {
        var style = zigraph.shapes.parallelogram(ctx);
        style.fill = "#e8f5e9";
        style.stroke = "#4caf50";
        return style;
    }

    // Process nodes (default)
    var style = zigraph.shapes.rounded_rectangle(ctx);
    style.fill = "#e3f2fd";
    style.stroke = "#2196f3";
    return style;
}

// ── Edge label styling: "yes" in green, "no" in red ────────────────────────

fn flowchartLabel(ctx: zigraph.EdgeStyleContext) zigraph.EdgeLabelStyle {
    if (ctx.label) |label| {
        if (std.mem.eql(u8, label, "yes")) {
            return .{ .color = "#2e7d32", .font_size = 11 };
        }
        if (std.mem.eql(u8, label, "no")) {
            return .{ .color = "#c62828", .font_size = 11 };
        }
    }
    return .{ .font_size = 11 };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n── 03: Flowchart ──\n\n", .{});

    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    // Build a login flow
    try g.addNode(1, "> Input");
    try g.addNode(2, "Parse Request");
    try g.addNode(3, "? Valid?");
    try g.addNode(4, "Authenticate");
    try g.addNode(5, "? Auth OK?");
    try g.addNode(6, "> Response 200");
    try g.addNode(7, "> Error 401");
    try g.addNode(8, "> Error 400");

    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdgeLabeled(3, 4, "yes");
    try g.addEdgeLabeled(3, 8, "no");
    try g.addEdge(4, 5);
    try g.addEdgeLabeled(5, 6, "yes");
    try g.addEdgeLabeled(5, 7, "no");

    var ir = try zigraph.layout(&g, allocator, .{
        .positioning = .brandes_kopf,
    });
    defer ir.deinit();

    const svg = try zigraph.svg.render(&ir, allocator, .{
        .node_style_fn = &flowchartNode,
        .edge_label_style_fn = &flowchartLabel,
        .edge_style_fn = &struct {
            fn style(ctx: zigraph.EdgeStyleContext) zigraph.EdgeStyle {
                // Green for "yes" branches, red for "no", default for rest
                if (ctx.label) |label| {
                    if (std.mem.eql(u8, label, "yes"))
                        return .{ .stroke = "#4caf50", .marker_end = .arrow };
                    if (std.mem.eql(u8, label, "no"))
                        return .{ .stroke = "#f44336", .marker_end = .arrow };
                }
                return .{
                    .stroke = "#90a4ae",
                    .marker_end = if (ctx.directed) .arrow else .none,
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    try writeSvg("03_flowchart", svg);
    std.debug.print("\n  Diamonds = decisions, parallelograms = I/O, rounded = process.\n", .{});
    std.debug.print("  Green/red edges for yes/no branches.\n\n", .{});
}
