//! # 04 — Clusters
//!
//! Subgraph styling with depth-aware colors. Nested clusters get
//! progressively lighter fills — so the hierarchy reads naturally.
//!
//! **What you'll learn:** `subgraph_style_fn`, `SubgraphStyleContext.depth`,
//! nested subgraphs, how to coordinate node + subgraph colors.
//!
//! Run: `zig build run-svg-04`

const std = @import("std");
const zigraph = @import("zigraph");

fn writeSvg(io: std.Io, name: []const u8, svg: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "assets/gallery/{s}.svg", .{name}) catch return;
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var wbuf: [4096]u8 = undefined;
    var fw = std.Io.File.writer(file, io, &wbuf);
    try fw.interface.writeAll(svg);
    std.debug.print("  ✓ {s} ({d} bytes)\n", .{ path, svg.len });
}

// ── Depth-aware subgraph palette ───────────────────────────────────────────
//
// Three-level color scheme: blue → green → amber.
// Each level gets a lighter fill and matching stroke.

const cluster_fills = [_][]const u8{ "#dbeafe", "#dcfce7", "#fef3c7" };
const cluster_strokes = [_][]const u8{ "#3b82f6", "#22c55e", "#f59e0b" };

fn clusterStyle(ctx: zigraph.SubgraphStyleContext) zigraph.SubgraphStyle {
    const i = ctx.depth % cluster_fills.len;
    return .{
        .box_svg = std.fmt.allocPrint(ctx.arena,
            \\<rect x="0" y="0" width="{d}" height="{d}" rx="8" ry="8"/>
            \\<text x="8" y="16" font-family="sans-serif" font-size="11" font-weight="600" fill="{s}" stroke="none">{s}</text>
        , .{ ctx.width, ctx.height, cluster_strokes[i], ctx.label }) catch "",
        .fill = cluster_fills[i],
        .fill_opacity = "0.5",
        .stroke = cluster_strokes[i],
    };
}

// ── Coordinated node colors ────────────────────────────────────────────────

fn nodeStyle(ctx: zigraph.NodeStyleContext) zigraph.NodeStyle {
    var style = zigraph.shapes.rounded_rectangle(ctx);
    style.fill = "#f8fafc";
    style.stroke = "#64748b";
    return style;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    std.debug.print("\n── 04: Clusters ──\n\n", .{});

    // A microservice architecture with nested clusters
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "API Gateway");
    try g.addNode(2, "Auth");
    try g.addNode(3, "Users");
    try g.addNode(4, "Sessions");
    try g.addNode(5, "Products");
    try g.addNode(6, "Orders");
    try g.addNode(7, "Postgres");
    try g.addNode(8, "Redis");

    try g.addEdge(1, 2);
    try g.addEdge(1, 5);
    try g.addEdge(2, 3);
    try g.addEdge(2, 4);
    try g.addEdge(5, 6);
    try g.addEdge(3, 7);
    try g.addEdge(4, 8);
    try g.addEdge(6, 7);

    // Cluster hierarchy:
    //   "Platform" (depth 0)
    //     "Identity" (depth 1)   — Auth, Users, Sessions
    //     "Commerce" (depth 1)   — Products, Orders
    //   "Storage" (depth 0)      — Postgres, Redis
    const platform = try g.addSubgraph("Platform");
    const identity = try g.addSubgraph("Identity");
    const commerce = try g.addSubgraph("Commerce");
    const storage = try g.addSubgraph("Storage");

    try g.putSubgraphs(&.{ identity, commerce }).inside(platform);
    try g.putNodes(&.{ 2, 3, 4 }).inside(identity);
    try g.putNodes(&.{ 5, 6 }).inside(commerce);
    try g.putNodes(&.{ 7, 8 }).inside(storage);

    var ir = try zigraph.layout(&g, allocator, .{
        .positioning = .brandes_kopf,
    });
    defer ir.deinit();

    const svg = try zigraph.svg.render(&ir, allocator, .{
        .subgraph_style_fn = &clusterStyle,
        .node_style_fn = &nodeStyle,
        .edge_style_fn = &zigraph.svg.monoEdgeStyle,
    });
    defer allocator.free(svg);

    try writeSvg(io, "04_clusters", svg);

    // Also show Unicode for quick terminal preview
    const txt = try zigraph.terminal.renderWithConfig(&ir, allocator, .{});
    defer allocator.free(txt);
    std.debug.print("\n{s}\n", .{txt});
}
