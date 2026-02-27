//! SVG spline stitching — groups multi-segment edges into smooth curves.
//!
//! When `stitch_splines` is enabled (default), edges that pass through
//! dummy nodes are collected by `edge_index`, sorted top-to-bottom, and
//! rendered as a single Catmull-Rom → cubic-Bézier spline. Labels are
//! placed at the polyline midpoint.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const LayoutEdge = ir_mod.LayoutEdge(usize);
const config_mod = @import("config.zig");
const SvgConfig = config_mod.SvgConfig;
const ResolvedEdgeStyle = config_mod.ResolvedEdgeStyle;
const edge_render = @import("edges.zig");
const Point = edge_render.Point;

/// Render edges by grouping segments with the same edge_index into smooth splines.
/// This stitches multi-segment edges through dummy nodes into single curved paths.
pub fn renderStitchedEdges(writer: anytype, layout: *const LayoutIR, allocator: Allocator, config: SvgConfig, resolved_styles: []const ResolvedEdgeStyle) !void {
    // Group edges by edge_index
    // Use a simple approach: find max edge_index, then collect segments for each
    var max_edge_idx: usize = 0;
    for (layout.edges.items) |edge| {
        if (edge.edge_index > max_edge_idx) max_edge_idx = edge.edge_index;
    }

    // For each original edge, collect all its segments
    for (0..(max_edge_idx + 1)) |edge_idx| {
        // Collect segments for this edge (order by from_y to get top-to-bottom)
        var segments: std.ArrayListUnmanaged(LayoutEdge) = .{};
        defer segments.deinit(allocator);

        for (layout.edges.items) |edge| {
            if (edge.edge_index == edge_idx) {
                try segments.append(allocator, edge);
            }
        }

        if (segments.items.len == 0) continue;

        // Look up pre-computed style for this edge_index
        const style = if (edge_idx < resolved_styles.len) resolved_styles[edge_idx] else ResolvedEdgeStyle{
            .stroke = "#666666",
            .marker_end_id = null,
            .marker_start_id = null,
            .extra_attrs = null,
        };

        // Self-loops: render a loop arc to the right of the node
        if (segments.items[0].reversed and segments.items[0].from_id == segments.items[0].to_id) {
            try edge_render.renderSelfLoop(writer, &segments.items[0], config, style, layout.nodes.items);
            continue;
        }

        // Sort segments by from_y (top to bottom)
        std.mem.sort(LayoutEdge, segments.items, {}, struct {
            fn lessThan(_: void, a: LayoutEdge, b: LayoutEdge) bool {
                return a.from_y < b.from_y;
            }
        }.lessThan);

        // Build waypoint list for spline
        var points: std.ArrayListUnmanaged(Point) = .{};
        defer points.deinit(allocator);

        // Start point
        try points.append(allocator, .{ .x = segments.items[0].from_x, .y = segments.items[0].from_y });

        // Intermediate points (dummy nodes)
        for (segments.items[0..(segments.items.len - 1)]) |seg| {
            try points.append(allocator, .{ .x = seg.to_x, .y = seg.to_y });
        }

        // End point
        const last_seg = segments.items[segments.items.len - 1];
        try points.append(allocator, .{ .x = last_seg.to_x, .y = last_seg.to_y });

        // Check if any segment carries a label
        var edge_label: ?[]const u8 = null;
        for (segments.items) |seg| {
            if (seg.label) |l| {
                edge_label = l;
                break;
            }
        }
        const has_label = edge_label != null;

        // Check if any segment is marked as reversed (back edge)
        var is_reversed = false;
        for (segments.items) |seg| {
            if (seg.reversed) {
                is_reversed = true;
                break;
            }
        }

        // The last segment determines whether the edge carries an arrowhead.
        // For reversed edges, the directed flag was moved to the first segment
        // (since the arrow points at the semantic target, which is at the top).
        const first_seg = segments.items[0];
        const is_directed = if (is_reversed) first_seg.directed else last_seg.directed;

        // For reversed (back) edges, reverse the waypoint order so the SVG path
        // goes bottom→top. This makes marker-end point upward (the correct
        // semantic direction for back edges).
        if (is_reversed) {
            std.mem.reverse(Point, points.items);
        }

        // Render based on number of points
        if (points.items.len == 2) {
            // Simple direct edge
            try edge_render.renderSingleEdge(writer, points.items[0], points.items[1], edge_idx, config, style, has_label, is_directed, is_reversed);
        } else {
            // Multi-point: render as smooth spline
            try renderSplinePath(writer, points.items, edge_idx, config, style, has_label, is_directed, is_reversed);
        }

        // Render edge label (if any segment carries one)
        if (edge_label) |label| {
            if (config.labels_on_path) {
                // Text follows the edge path curve (hidden path is always L→R)
                try writer.print(
                    \\    <text font-family="monospace" font-size="12" fill="{s}" dy="-4">
                    \\      <textPath href="#edgepath{d}" startOffset="50%"
                    \\              text-anchor="middle" dominant-baseline="auto">"{s}"</textPath></text>
                    \\
                , .{ style.stroke, edge_idx, label });
            } else {
                // Center label at the midpoint along the actual edge path
                const np = points.items.len;
                const cw_f: f64 = @floatFromInt(config.char_width);
                const lh_f: f64 = @floatFromInt(config.line_height);
                const pad_f: f64 = @floatFromInt(config.padding);

                var ppx: [128]f64 = undefined;
                var ppy: [128]f64 = undefined;
                const pn = @min(np, 128);
                for (points.items[0..pn], 0..) |p, idx| {
                    ppx[idx] = @as(f64, @floatFromInt(p.x)) * cw_f + pad_f;
                    ppy[idx] = @as(f64, @floatFromInt(p.y)) * lh_f + pad_f;
                }

                // Compute total polyline length
                var total_len: f64 = 0;
                for (1..pn) |idx| {
                    const ddx = ppx[idx] - ppx[idx - 1];
                    const ddy = ppy[idx] - ppy[idx - 1];
                    total_len += @sqrt(ddx * ddx + ddy * ddy);
                }

                // Walk to midpoint
                const half_len = total_len / 2.0;
                var accum: f64 = 0;
                var mx: f64 = ppx[0];
                var my: f64 = ppy[0];
                for (0..(pn - 1)) |idx| {
                    const ddx = ppx[idx + 1] - ppx[idx];
                    const ddy = ppy[idx + 1] - ppy[idx];
                    const slen = @sqrt(ddx * ddx + ddy * ddy);
                    if (accum + slen >= half_len and slen > 0) {
                        const t = (half_len - accum) / slen;
                        mx = ppx[idx] + t * ddx;
                        my = ppy[idx] + t * ddy;
                        break;
                    }
                    accum += slen;
                }

                // For reversed edges, offset label to the right of the bezier arc
                const label_offset_x: f64 = if (is_reversed) 20.0 else 0.0;

                try writer.print(
                    \\    <text x="{d:.0}" y="{d:.0}" font-family="monospace" font-size="12"
                    \\          fill="{s}" text-anchor="middle" dy="-6" dominant-baseline="auto">"{s}"</text>
                    \\
                , .{ mx + label_offset_x, my, style.stroke, label });
            }
        }
    }
}

/// Render a multi-point path as a smooth cubic bezier spline.
/// Uses Catmull-Rom to Bezier conversion for smooth curves through all points.
pub fn renderSplinePath(writer: anytype, points: []const Point, edge_idx: usize, config: SvgConfig, style: ResolvedEdgeStyle, has_label: bool, directed: bool, reversed: bool) !void {
    if (points.len < 2) return;

    // Convert points to pixel coordinates
    var px_points: [128]struct { x: f64, y: f64 } = undefined;
    const n = @min(points.len, 128);

    for (points[0..n], 0..) |p, i| {
        px_points[i] = .{
            .x = @floatFromInt(p.x * config.char_width + config.padding),
            .y = @floatFromInt(p.y * config.line_height + config.padding),
        };
    }

    // Store control points for debug rendering
    var control_points: [256]struct { x: f64, y: f64, from_x: f64, from_y: f64 } = undefined;
    var cp_count: usize = 0;

    // Start the visible path (text path is separate for correct L→R orientation)
    try writer.print("    <path d=\"M {d:.0} {d:.0}", .{ px_points[0].x, px_points[0].y });

    // For 2 points, just draw a line
    if (n == 2) {
        try writer.print(" L {d:.0} {d:.0}\"", .{ px_points[1].x, px_points[1].y });
    } else {
        // Use Catmull-Rom spline interpolation for smooth curves
        // For each segment, compute cubic bezier control points

        for (0..(n - 1)) |i| {
            // Get 4 points for Catmull-Rom (with clamping at ends)
            const p0 = if (i == 0) px_points[0] else px_points[i - 1];
            const p1 = px_points[i];
            const p2 = px_points[i + 1];
            const p3 = if (i + 2 >= n) px_points[n - 1] else px_points[i + 2];

            // Convert Catmull-Rom to Bezier control points
            // Using tension = 0 (standard Catmull-Rom)
            const tension: f64 = 6.0; // Higher = tighter curves
            const cp1_x = p1.x + (p2.x - p0.x) / tension;
            const cp1_y = p1.y + (p2.y - p0.y) / tension;
            const cp2_x = p2.x - (p3.x - p1.x) / tension;
            const cp2_y = p2.y - (p3.y - p1.y) / tension;

            try writer.print(" C {d:.0} {d:.0}, {d:.0} {d:.0}, {d:.0} {d:.0}", .{
                cp1_x,
                cp1_y,
                cp2_x,
                cp2_y,
                p2.x,
                p2.y,
            });

            // Store control points for debug rendering
            if (config.show_control_points and cp_count + 2 < 256) {
                control_points[cp_count] = .{ .x = cp1_x, .y = cp1_y, .from_x = p1.x, .from_y = p1.y };
                cp_count += 1;
                control_points[cp_count] = .{ .x = cp2_x, .y = cp2_y, .from_x = p2.x, .from_y = p2.y };
                cp_count += 1;
            }
        }
        try writer.writeAll("\"");
    }

    const dash: []const u8 = if (reversed) " stroke-dasharray=\"6,3\"" else "";

    try writer.print(
        \\ fill="none" stroke="{s}" stroke-width="{d}"{s}
    , .{ style.stroke, config.edge_width, dash });
    if (directed) {
        if (style.marker_end_id) |mid| {
            try writer.print(" marker-end=\"url(#zg-m-{d})\"", .{mid});
        }
    }
    if (style.extra_attrs) |attrs| {
        try writer.print(" {s}", .{attrs});
    }
    try writer.writeAll("/>\n");

    // Render control points if debugging
    if (config.show_control_points and cp_count > 0) {
        for (control_points[0..cp_count]) |cp| {
            // Control point circle
            try writer.print(
                \\    <circle cx="{d:.0}" cy="{d:.0}" r="4" fill="{s}" opacity="0.7"/>
                \\    <line x1="{d:.0}" y1="{d:.0}" x2="{d:.0}" y2="{d:.0}" 
                \\          stroke="{s}" stroke-width="1" stroke-dasharray="4,2"/>
                \\
            , .{
                cp.x,
                cp.y,
                config.control_point_color,
                cp.from_x,
                cp.from_y,
                cp.x,
                cp.y,
                config.control_point_color,
            });
        }
    }

    // Emit hidden text path for labels_on_path (always left-to-right for readable text)
    if (config.labels_on_path and has_label) {
        // Determine if path needs reversing (text should always read left-to-right)
        const needs_reverse = px_points[0].x > px_points[n - 1].x;
        var text_pts: @TypeOf(px_points) = undefined;
        if (needs_reverse) {
            for (0..n) |i| {
                text_pts[i] = px_points[n - 1 - i];
            }
        } else {
            for (0..n) |i| {
                text_pts[i] = px_points[i];
            }
        }

        try writer.print("    <path id=\"edgepath{d}\" d=\"M {d:.0} {d:.0}", .{ edge_idx, text_pts[0].x, text_pts[0].y });
        if (n == 2) {
            try writer.print(" L {d:.0} {d:.0}\"", .{ text_pts[1].x, text_pts[1].y });
        } else {
            for (0..(n - 1)) |i| {
                const tp0 = if (i == 0) text_pts[0] else text_pts[i - 1];
                const tp1 = text_pts[i];
                const tp2 = text_pts[i + 1];
                const tp3 = if (i + 2 >= n) text_pts[n - 1] else text_pts[i + 2];
                const t: f64 = 6.0;
                const c1x = tp1.x + (tp2.x - tp0.x) / t;
                const c1y = tp1.y + (tp2.y - tp0.y) / t;
                const c2x = tp2.x - (tp3.x - tp1.x) / t;
                const c2y = tp2.y - (tp3.y - tp1.y) / t;
                try writer.print(" C {d:.0} {d:.0}, {d:.0} {d:.0}, {d:.0} {d:.0}", .{
                    c1x, c1y, c2x, c2y, tp2.x, tp2.y,
                });
            }
            try writer.writeAll("\"");
        }
        try writer.writeAll(" fill=\"none\" stroke=\"none\"/>\n");
    }
}
