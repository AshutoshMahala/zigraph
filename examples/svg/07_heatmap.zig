//! # 07 — Stress / Heatmap Diagram
//!
//! FEA-style stress visualization with per-node internal radial gradients,
//! **color spill** (glow extending beyond node bounds), **variable stress
//! focal points** (corners/edges, sometimes dual concentrations), and
//! **variable node sizing** (hotter nodes appear taller with more rounded
//! shapes).
//!
//! **What you'll learn:**
//!   - Per-node `<radialGradient>` with turbo multi-stop fills
//!   - Color spill/glow using gaussian blur filter + oversized shapes
//!   - Multiple stress focal points per node
//!   - Variable node visual sizing and corner radii
//!   - Color scale legend with axis ticks
//!
//! Run: `zig build run-svg_07_heatmap`

const std = @import("std");
const zigraph = @import("zigraph");
const Color = zigraph.color.Color;
const ColorMap = zigraph.color.ColorMap;

fn writeSvg(io: std.Io, name: []const u8, svg: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "assets/gallery/{s}.svg", .{name}) catch return;
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var wbuf: [4096]u8 = undefined;
    var fw = std.Io.File.writer(file, io, &wbuf);
    try fw.interface.writeAll(svg);
    std.debug.print("  \xe2\x9c\x93 {s} ({d} bytes)\n", .{ path, svg.len });
}

// ── Heat data ──────────────────────────────────────────────────────────────
//
// Each node has a throughput score 0.0–1.0.
// In production this would come from log-frequency / process-mining data.

fn getHeat(label: []const u8) f32 {
    const table = [_]struct { name: []const u8, heat: f32 }{
        .{ .name = "Main Processing", .heat = 1.00 },
        .{ .name = "Testing", .heat = 0.92 },
        .{ .name = "Buffer", .heat = 0.75 },
        .{ .name = "Refinement", .heat = 0.70 },
        .{ .name = "Advance", .heat = 0.50 },
        .{ .name = "Evaluate", .heat = 0.45 },
        .{ .name = "Quick Prep", .heat = 0.40 },
        .{ .name = "Feature Req", .heat = 0.25 },
        .{ .name = "Prepare", .heat = 0.20 },
        .{ .name = "Delivery", .heat = 0.18 },
        .{ .name = "Store", .heat = 0.15 },
        .{ .name = "Backlog", .heat = 0.05 },
        .{ .name = "Rejection", .heat = 0.03 },
    };
    for (table) |entry| {
        if (std.mem.eql(u8, label, entry.name)) return entry.heat;
    }
    return 0.2;
}

/// Choose text color for readability against the gradient's dominant hue.
fn textColor(heat: f32) []const u8 {
    if (heat < 0.25 or heat > 0.78) return "#f8fafc";
    return "#1e293b";
}

// ── Deterministic per-node randomness ──────────────────────────────────────

/// Produce a deterministic f32 in [0, 1) for a given node + salt.
/// Uses Knuth multiplicative hash with salt mixing.
fn nodeRand(node_id: usize, salt: u32) f32 {
    const h: u32 = @truncate((node_id *% 2654435761) +% (salt *% 1103515245));
    return @as(f32, @floatFromInt(h & 0xFFFF)) / 65536.0;
}

// ── Stress-point placement ─────────────────────────────────────────────────

const StressPoint = struct {
    fx: f32, // focal x in objectBoundingBox space (0–1)
    fy: f32, // focal y in objectBoundingBox space (0–1)
};

/// Seven placement patterns: corners, edges, and near-center.
const placements = [_]StressPoint{
    .{ .fx = 0.22, .fy = 0.25 }, // top-left
    .{ .fx = 0.78, .fy = 0.25 }, // top-right
    .{ .fx = 0.22, .fy = 0.75 }, // bottom-left
    .{ .fx = 0.78, .fy = 0.75 }, // bottom-right
    .{ .fx = 0.15, .fy = 0.50 }, // left edge
    .{ .fx = 0.85, .fy = 0.50 }, // right edge
    .{ .fx = 0.45, .fy = 0.30 }, // near center-top
};

/// Get 1–2 stress focal points for a node based on its heat and id.
/// Hot nodes (heat > 0.6) get a second concentration on the opposite side.
fn getStressPoints(node_id: usize, heat: f32) struct { points: [2]StressPoint, count: u8 } {
    const r = nodeRand(node_id, 7);
    const idx = @as(usize, @intFromFloat(r * @as(f32, @floatFromInt(placements.len))));
    const p1 = placements[@min(idx, placements.len - 1)];

    if (heat > 0.6) {
        const jx = (nodeRand(node_id, 13) - 0.5) * 0.15;
        const jy = (nodeRand(node_id, 17) - 0.5) * 0.15;
        const p2 = StressPoint{
            .fx = @max(0.1, @min(0.9, 1.0 - p1.fx + jx)),
            .fy = @max(0.1, @min(0.9, 1.0 - p1.fy + jy)),
        };
        return .{ .points = .{ p1, p2 }, .count = 2 };
    }
    return .{ .points = .{ p1, p1 }, .count = 1 };
}

// ── Style functions ────────────────────────────────────────────────────────

/// FEA stress node: internal gradient + color spill + variable sizing.
///
/// Features:
///   1. **Variable height**: hot nodes grow taller (1.0x–1.8x of base).
///   2. **Variable corner radius**: cold = sharp (2px), hot = pill-like.
///   3. **Primary gradient**: multi-stop turbo radialGradient inside the node,
///      focal point placed at a corner/edge/near-center based on node id.
///   4. **Secondary overlay**: for very hot nodes (>0.6), a second semi-
///      transparent gradient from the opposite side (dual stress concentration).
///   5. **Color spill**: for nodes above 0.4 heat, a blurred ellipse extends
///      beyond the node bounds — like thermal radiation leaking out.
fn stressNode(ctx: zigraph.NodeStyleContext) zigraph.NodeStyle {
    const heat = getHeat(ctx.label);

    // ── Variable sizing ─────────────────────────────────────────────
    // Hot nodes grow taller (centered on midpoint so they expand equally
    // upward and downward).  h_scale ranges from 1.0 (cold) to 1.8 (hot).
    const h_scale: f32 = 1.0 + heat * 0.8;
    const base_h: f32 = @floatFromInt(ctx.height);
    const vis_h = base_h * h_scale;
    const y_off = -(vis_h - base_h) / 2.0;
    const vis_h_int: i32 = @intFromFloat(@round(vis_h));
    const y_off_int: i32 = @intFromFloat(@round(y_off));

    // Variable corner radius: cold → sharp (2px), hot → pill (vis_h / 3)
    const max_rx = vis_h / 3.0;
    const rx = 2.0 + heat * (@max(2.0, max_rx) - 2.0);
    const rx_int: u32 = @intFromFloat(@round(@max(2.0, rx)));

    // ── Turbo color stops ───────────────────────────────────────────
    // We spread across a portion of the turbo range anchored at `heat`.
    const spread: f32 = 0.35;
    const peak_t = heat;
    const ring1_t = @max(0.0, heat - spread * 0.33);
    const ring2_t = @max(0.0, heat - spread * 0.66);
    const edge_t = @max(0.0, heat - spread);

    const peak_hex = ColorMap.turbo.sample(peak_t).toHexAlloc(ctx.arena) catch "#888";
    const ring1_hex = ColorMap.turbo.sample(ring1_t).toHexAlloc(ctx.arena) catch "#888";
    const ring2_hex = ColorMap.turbo.sample(ring2_t).toHexAlloc(ctx.arena) catch "#888";
    const edge_hex = ColorMap.turbo.sample(edge_t).toHexAlloc(ctx.arena) catch "#888";

    // ── Stress focal points ─────────────────────────────────────────
    const stress = getStressPoints(ctx.node_id, heat);
    const p1 = stress.points[0];

    // ── Build gradient defs ─────────────────────────────────────────
    const gid = std.fmt.allocPrint(ctx.arena, "sg-{d}", .{ctx.node_id}) catch "sg";

    // Primary: full coverage radial gradient with focal point at p1
    const primary_grad = std.fmt.allocPrint(ctx.arena,
        \\<radialGradient id="{s}" gradientUnits="objectBoundingBox"
        \\  cx="0.5" cy="0.5" r="0.85" fx="{d:.2}" fy="{d:.2}">
        \\  <stop offset="0%"   stop-color="{s}"/>
        \\  <stop offset="30%"  stop-color="{s}"/>
        \\  <stop offset="65%"  stop-color="{s}"/>
        \\  <stop offset="100%" stop-color="{s}"/>
        \\</radialGradient>
    , .{ gid, p1.fx, p1.fy, peak_hex, ring1_hex, ring2_hex, edge_hex }) catch "";

    // Secondary: semi-transparent overlay from the opposite side (dual stress)
    const secondary_grad: []const u8 = if (stress.count == 2) blk: {
        const p2 = stress.points[1];
        const gid2 = std.fmt.allocPrint(ctx.arena, "sg2-{d}", .{ctx.node_id}) catch "sg2";
        break :blk std.fmt.allocPrint(ctx.arena,
            \\
            \\<radialGradient id="{s}" gradientUnits="objectBoundingBox"
            \\  cx="0.5" cy="0.5" r="0.7" fx="{d:.2}" fy="{d:.2}">
            \\  <stop offset="0%"   stop-color="{s}" stop-opacity="0.6"/>
            \\  <stop offset="50%"  stop-color="{s}" stop-opacity="0.3"/>
            \\  <stop offset="100%" stop-color="{s}" stop-opacity="0"/>
            \\</radialGradient>
        , .{ gid2, p2.fx, p2.fy, peak_hex, ring1_hex, edge_hex }) catch "";
    } else "";

    const defs_str: ?[]const u8 = std.mem.concat(ctx.arena, u8, &.{ primary_grad, secondary_grad }) catch null;

    // ── Build shape SVG ─────────────────────────────────────────────
    // Layer order: spill glow → main rect → overlay → labels

    // 1. Spill glow: blurred ellipse extending beyond node bounds
    const spill_svg: []const u8 = if (heat > 0.4) blk: {
        const spill_opacity = (heat - 0.4) * 0.8; // 0.0 – 0.48
        const w_f: f32 = @floatFromInt(ctx.width);
        const spill_rx_f = w_f * (0.55 + heat * 0.3);
        const spill_ry_f = vis_h * (0.6 + heat * 0.35);
        // Bias spill center toward the primary stress point
        const spill_cx = w_f * (0.35 + p1.fx * 0.3);
        const spill_cy = base_h * 0.5 + (p1.fy - 0.5) * base_h * 0.3;
        const spill_hex = ColorMap.turbo.sample(@min(1.0, heat + 0.05)).toHexAlloc(ctx.arena) catch "#f00";
        break :blk std.fmt.allocPrint(ctx.arena,
            \\<ellipse cx="{d:.0}" cy="{d:.0}" rx="{d:.0}" ry="{d:.0}" fill="{s}" opacity="{d:.2}" filter="url(#heatblur)"/>
        , .{ spill_cx, spill_cy, spill_rx_f, spill_ry_f, spill_hex, spill_opacity }) catch "";
    } else "";

    // 2. Main body rect: gradient-filled, variable height + corner radius
    const border_hex = ColorMap.turbo.sample(edge_t).darken(0.2).toHexAlloc(ctx.arena) catch "#555";

    const rect_svg = std.fmt.allocPrint(ctx.arena,
        \\
        \\<rect x="0" y="{d}" width="{d}" height="{d}" rx="{d}" ry="{d}" fill="url(#{s})" stroke="{s}" stroke-width="1.5"/>
    , .{ y_off_int, ctx.width, vis_h_int, rx_int, rx_int, gid, border_hex }) catch "";

    // 3. Secondary overlay rect for dual stress concentration
    const overlay_svg: []const u8 = if (stress.count == 2) blk: {
        const gid2 = std.fmt.allocPrint(ctx.arena, "sg2-{d}", .{ctx.node_id}) catch "sg2";
        break :blk std.fmt.allocPrint(ctx.arena,
            \\
            \\<rect x="0" y="{d}" width="{d}" height="{d}" rx="{d}" ry="{d}" fill="url(#{s})" stroke="none"/>
        , .{ y_off_int, ctx.width, vis_h_int, rx_int, rx_int, gid2 }) catch "";
    } else "";

    // 4. Text labels (positioned at original center — stays visually centered
    //    because the rect expands equally upward and downward)
    const txt = textColor(heat);
    const pct: usize = @intFromFloat(@round(heat * 100.0));

    const label_svg = std.fmt.allocPrint(ctx.arena,
        \\
        \\<text x="{d}" y="{d}" text-anchor="middle" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="600" font-size="11" fill="{s}" stroke="none">{s}</text>
        \\<text x="{d}" y="{d}" text-anchor="middle" font-family="Inter, Helvetica, Arial, sans-serif" font-size="9" fill="{s}" opacity="0.85" stroke="none">{d}%</text>
    , .{
        ctx.width / 2, ctx.height / 2 + 1,  txt, ctx.label,
        ctx.width / 2, ctx.height / 2 + 13, txt, pct,
    }) catch "";

    const shape = std.mem.concat(ctx.arena, u8, &.{ spill_svg, rect_svg, overlay_svg, label_svg }) catch "";

    return .{
        .shape_svg = shape,
        .fill = "none", // gradient handles fill
        .stroke = "none", // stroke is inside shape_svg
        .defs = defs_str,
    };
}

/// Edges: thin, dark gray, clean arrows — data-neutral.
fn stressEdge(ctx: zigraph.EdgeStyleContext) zigraph.EdgeStyle {
    _ = ctx;
    return .{
        .stroke = "#64748b",
        .marker_end = .arrow,
        .extra_attrs = "opacity=\"0.7\"",
    };
}

/// Edge labels: small, gray, unobtrusive.
fn stressLabel(ctx: zigraph.EdgeStyleContext) zigraph.EdgeLabelStyle {
    _ = ctx;
    return .{
        .color = "#64748b",
        .font_size = 9,
        .font_family = "Inter, Helvetica, Arial, sans-serif",
    };
}

/// Subgraph boxes: very light gray fill, thin border — like FEA region boundaries.
fn stressCluster(ctx: zigraph.SubgraphStyleContext) zigraph.SubgraphStyle {
    return .{
        .box_svg = std.fmt.allocPrint(ctx.arena,
            \\<rect x="0" y="0" width="{d}" height="{d}" rx="3" ry="3"/>
            \\<text x="6" y="14" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="600" font-size="9" fill="#64748b" letter-spacing="0.5" stroke="none">{s}</text>
        , .{ ctx.width, ctx.height, ctx.label }) catch "",
        .fill = "#f1f5f9",
        .fill_opacity = "0.5",
        .stroke = "#cbd5e1",
        .extra_attrs = "stroke-width=\"1\"",
    };
}

// ── Legend builder ──────────────────────────────────────────────────────────

/// Build a vertical color-scale bar legend as raw SVG markup.
/// Uses pre-baked comptime turbo palette for the gradient stops.
fn buildLegend(allocator: std.mem.Allocator) ![]const u8 {
    // Quantize turbo into 32 stops for a smooth visual gradient
    const n_stops = 32;
    const turbo_lut = comptime ColorMap.turbo.quantize(n_stops);

    var buf = std.Io.Writer.Allocating.init(allocator);
    errdefer buf.deinit();
    const w = &buf.writer;

    // Legend dimensions
    const bar_w: usize = 16;
    const bar_h: usize = 180;
    const cell_h = bar_h / n_stops;
    const x_off: usize = 12;
    const y_off: usize = 30;

    try w.writeAll("<g id=\"legend\" transform=\"translate(20, 20)\">\n");

    // Title
    try w.writeAll("  <text x=\"0\" y=\"14\" font-family=\"Inter, Helvetica, Arial, sans-serif\" font-weight=\"700\" font-size=\"10\" fill=\"#334155\" letter-spacing=\"0.5\">THROUGHPUT</text>\n");

    // Color bar — draw from top (=1.0) to bottom (=0.0)
    for (0..n_stops) |i| {
        const stop_idx = n_stops - 1 - i;
        const y = y_off + i * cell_h;

        try w.print("  <rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"{s}\" stroke=\"none\"/>\n", .{
            x_off,                y, bar_w, cell_h + 1,
            &turbo_lut[stop_idx],
        });
    }

    // Border around the bar
    try w.print("  <rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"none\" stroke=\"#94a3b8\" stroke-width=\"0.5\" rx=\"1\"/>\n", .{
        x_off, y_off, bar_w, bar_h,
    });

    // Tick marks and labels  (1.0 at top, 0.5 mid, 0.0 at bottom)
    const ticks = [_]struct { value: []const u8, y_frac: f32 }{
        .{ .value = "1.0", .y_frac = 0.0 },
        .{ .value = "0.75", .y_frac = 0.25 },
        .{ .value = "0.5", .y_frac = 0.5 },
        .{ .value = "0.25", .y_frac = 0.75 },
        .{ .value = "0.0", .y_frac = 1.0 },
    };
    for (ticks) |tick| {
        const ty: usize = y_off + @as(usize, @intFromFloat(tick.y_frac * @as(f32, @floatFromInt(bar_h))));
        const tx = x_off + bar_w + 3;

        // Tick line
        try w.print("  <line x1=\"{d}\" y1=\"{d}\" x2=\"{d}\" y2=\"{d}\" stroke=\"#94a3b8\" stroke-width=\"0.5\"/>\n", .{
            x_off + bar_w, ty, tx, ty,
        });

        // Label
        try w.print("  <text x=\"{d}\" y=\"{d}\" font-family=\"Inter, Helvetica, Arial, sans-serif\" font-size=\"8\" fill=\"#64748b\" dominant-baseline=\"central\">{s}</text>\n", .{
            tx + 2, ty, tick.value,
        });
    }

    try w.writeAll("</g>\n");

    return buf.toOwnedSlice();
}

// ── Main ───────────────────────────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    std.debug.print("\n\xe2\x94\x80\xe2\x94\x80 07: Stress Heatmap (ColorMap.turbo) \xe2\x94\x80\xe2\x94\x80\n\n", .{});

    // ── Build a process-mining workflow ─────────────────────────────────

    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Feature Req");
    try g.addNode(2, "Evaluate");
    try g.addNode(3, "Advance");
    try g.addNode(4, "Backlog");
    try g.addNode(5, "Prepare");
    try g.addNode(6, "Quick Prep");
    try g.addNode(7, "Buffer");
    try g.addNode(8, "Main Processing");
    try g.addNode(9, "Refinement");
    try g.addNode(10, "Testing");
    try g.addNode(11, "Delivery");
    try g.addNode(12, "Store");
    try g.addNode(13, "Rejection");

    // Main flow
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 5);
    try g.addEdge(3, 6);
    try g.addEdge(5, 7);
    try g.addEdge(6, 7);
    try g.addEdge(7, 8);
    try g.addEdge(8, 9);
    try g.addEdge(9, 10);

    // Output fan-out
    try g.addEdge(10, 11);
    try g.addEdge(10, 12);
    try g.addEdge(10, 13);

    // Group into phases
    const intake = try g.addSubgraph("Intake");
    const core = try g.addSubgraph("Core");
    const output = try g.addSubgraph("Output");

    try g.putNodes(&.{ 1, 2, 4 }).inside(intake);
    try g.putNodes(&.{ 7, 8, 9 }).inside(core);
    try g.putNodes(&.{ 11, 12, 13 }).inside(output);

    // ── Layout ─────────────────────────────────────────────────────────

    var ir = try zigraph.layout(&g, allocator, .{
        .positioning = .brandes_kopf,
    });
    defer ir.deinit();

    // ── Build color legend ─────────────────────────────────────────────

    const legend_svg = try buildLegend(allocator);
    defer allocator.free(legend_svg);

    // ── Render ─────────────────────────────────────────────────────────

    const svg = try zigraph.svg.render(&ir, allocator, .{
        .node_style_fn = &stressNode,
        .edge_style_fn = &stressEdge,
        .edge_label_style_fn = &stressLabel,
        .subgraph_style_fn = &stressCluster,
        .global_style =
        \\<style>
        \\  svg { background: #ffffff; }
        \\  rect[width="100%"] { fill: #ffffff; }
        \\</style>
        \\<filter id="heatblur" x="-50%" y="-50%" width="200%" height="200%">
        \\  <feGaussianBlur stdDeviation="8"/>
        \\</filter>
        ,
        .global_script = legend_svg,
    });
    defer allocator.free(svg);

    try writeSvg(io, "07_heatmap", svg);

    std.debug.print("\n  FEA stress-diagram heatmap with color spill.\n", .{});
    std.debug.print("  Node fill = ColorMap.turbo(throughput), 0.0 \xe2\x86\x92 1.0\n", .{});
    std.debug.print("  Hot nodes: taller, rounder, dual stress points, glow spill.\n", .{});
    std.debug.print("  Cold nodes: flat, sharp corners, no spill.\n\n", .{});
}
