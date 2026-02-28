//! SVG edge rendering — individual edge segments.
//!
//! Handles all edge path types (direct, corner, side-channel, multi-segment,
//! spline) plus self-loops for the non-stitched code path. Also provides
//! `renderSingleEdge` (two-point edges used by the stitched pipeline) and
//! `renderBezierEdge` (standalone cubic bezier).

const std = @import("std");
const ir_mod = @import("../../core/ir.zig");
const LayoutEdge = ir_mod.LayoutEdge(usize);
const LayoutNode = ir_mod.LayoutNode(usize);
const config_mod = @import("config.zig");
const SvgConfig = config_mod.SvgConfig;
const ResolvedEdgeStyle = config_mod.ResolvedEdgeStyle;
const EdgeLabelStyle = config_mod.EdgeLabelStyle;
const helpers = @import("helpers.zig");

/// 2-D pixel coordinate used by the stitched-spline pipeline.
pub const Point = struct {
    x: usize,
    y: usize,
};

// ────────────────────────────────────────────────────────────────────────────
// Non-stitched path: each LayoutEdge rendered individually
// ────────────────────────────────────────────────────────────────────────────

/// Render a single LayoutEdge (used when `stitch_splines = false`).
pub fn renderEdge(writer: anytype, edge: LayoutEdge, config: SvgConfig, style: ResolvedEdgeStyle, label_style: EdgeLabelStyle) !void {
    // Semantic wrapper for CSS/JS targeting
    try writer.writeAll("    <g");
    try writeEdgeDataAttrs(writer, style.extra_attrs, edge.from_id, edge.to_id);
    try writer.writeAll(">\n");
    try renderEdgeInner(writer, edge, config, style, label_style);
    try writer.writeAll("    </g>\n");
}

fn renderEdgeInner(writer: anytype, edge: LayoutEdge, config: SvgConfig, style: ResolvedEdgeStyle, label_style: EdgeLabelStyle) !void {
    // For reversed (back) edges, swap from/to coordinates so the SVG path
    // goes bottom→top. This makes marker-end point upward (correct semantic
    // direction), while the visual route remains the same.
    const from_x = if (edge.reversed)
        edge.to_x * config.char_width + config.padding
    else
        edge.from_x * config.char_width + config.padding;
    const from_y = if (edge.reversed)
        edge.to_y * config.line_height + config.padding
    else
        edge.from_y * config.line_height + config.padding;
    const to_x = if (edge.reversed)
        edge.from_x * config.char_width + config.padding
    else
        edge.to_x * config.char_width + config.padding;
    const to_y = if (edge.reversed)
        edge.from_y * config.line_height + config.padding
    else
        edge.to_y * config.line_height + config.padding;

    const dash: []const u8 = if (edge.reversed) " stroke-dasharray=\"6,3\"" else "";

    switch (edge.path) {
        .direct => {
            // Simple straight line with optional arrow
            try writer.print(
                \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
                \\          stroke="{s}" stroke-width="{d}"{s}
            , .{
                from_x,
                from_y,
                to_x,
                to_y,
                style.stroke,
                config.edge_width,
                dash,
            });
            try writeMarkerEndAttr(writer, style);
            try writeExtraAttrs(writer, style);
            try writer.writeAll("/>\n");
        },
        .corner => |c| {
            // L-shaped path (reversed edges: draw bottom→top for correct arrow)
            const corner_y = c.horizontal_y * config.line_height + config.padding;
            if (edge.reversed) {
                // Reverse path: to → corner → from (bottom→top)
                const real_from_x = edge.from_x * config.char_width + config.padding;
                const real_from_y = edge.from_y * config.line_height + config.padding;
                const real_to_x = edge.to_x * config.char_width + config.padding;
                const real_to_y = edge.to_y * config.line_height + config.padding;
                try writer.print(
                    \\    <path d="M {d} {d} L {d} {d} L {d} {d}" 
                    \\          fill="none" stroke="{s}" stroke-width="{d}"{s}
                , .{
                    real_to_x,
                    real_to_y,
                    real_to_x,
                    corner_y,
                    real_from_x,
                    real_from_y,
                    style.stroke,
                    config.edge_width,
                    dash,
                });
            } else {
                try writer.print(
                    \\    <path d="M {d} {d} L {d} {d} L {d} {d}" 
                    \\          fill="none" stroke="{s}" stroke-width="{d}"{s}
                , .{
                    from_x,
                    from_y,
                    from_x,
                    corner_y,
                    to_x,
                    to_y,
                    style.stroke,
                    config.edge_width,
                    dash,
                });
            }
            try writeMarkerEndAttr(writer, style);
            try writeExtraAttrs(writer, style);
            try writer.writeAll("/>\n");
        },
        .side_channel => |sc| {
            // Side channel routing
            const channel_x = sc.channel_x * config.char_width + config.padding;
            const start_y = sc.start_y * config.line_height + config.padding;
            const end_y = sc.end_y * config.line_height + config.padding;
            try writer.print(
                \\    <path d="M {d} {d} L {d} {d} L {d} {d} L {d} {d}" 
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}
            , .{
                from_x,
                from_y,
                channel_x,
                start_y,
                channel_x,
                end_y,
                to_x,
                to_y,
                style.stroke,
                config.edge_width,
                dash,
            });
            try writeMarkerEndAttr(writer, style);
            try writeExtraAttrs(writer, style);
            try writer.writeAll("/>\n");
        },
        .multi_segment => |ms| {
            // Path through waypoints (reversed edges: reverse order for correct arrow)
            if (edge.reversed) {
                const real_from_x = edge.from_x * config.char_width + config.padding;
                const real_from_y = edge.from_y * config.line_height + config.padding;
                const real_to_x = edge.to_x * config.char_width + config.padding;
                const real_to_y = edge.to_y * config.line_height + config.padding;
                try writer.print("    <path d=\"M {d} {d}", .{ real_to_x, real_to_y });
                // Waypoints in reverse order
                var wi: usize = ms.waypoints.items.len;
                while (wi > 0) {
                    wi -= 1;
                    const wp = ms.waypoints.items[wi];
                    const wx = wp.x * config.char_width + config.padding;
                    const wy = wp.y * config.line_height + config.padding;
                    try writer.print(" L {d} {d}", .{ wx, wy });
                }
                try writer.print(" L {d} {d}\"", .{ real_from_x, real_from_y });
            } else {
                try writer.print("    <path d=\"M {d} {d}", .{ from_x, from_y });
                for (ms.waypoints.items) |wp| {
                    const wx = wp.x * config.char_width + config.padding;
                    const wy = wp.y * config.line_height + config.padding;
                    try writer.print(" L {d} {d}", .{ wx, wy });
                }
                try writer.print(" L {d} {d}\"", .{ to_x, to_y });
            }
            try writer.print(
                \\ fill="none" stroke="{s}" stroke-width="{d}"{s}
            , .{
                style.stroke,
                config.edge_width,
                dash,
            });
            try writeMarkerEndAttr(writer, style);
            try writeExtraAttrs(writer, style);
            try writer.writeAll("/>\n");
        },
        .spline => |sp| {
            // Cubic bezier curve
            const cp1_x = sp.cp1_x * config.char_width + config.padding;
            const cp1_y = sp.cp1_y * config.line_height + config.padding;
            const cp2_x = sp.cp2_x * config.char_width + config.padding;
            const cp2_y = sp.cp2_y * config.line_height + config.padding;

            try writer.print(
                \\    <path d="M {d} {d} C {d} {d}, {d} {d}, {d} {d}" 
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}
            , .{
                from_x,
                from_y,
                cp1_x,
                cp1_y,
                cp2_x,
                cp2_y,
                to_x,
                to_y,
                style.stroke,
                config.edge_width,
                dash,
            });
            try writeMarkerEndAttr(writer, style);
            try writeExtraAttrs(writer, style);
            try writer.writeAll("/>\n");

            // Show control points if debugging
            if (config.show_control_points) {
                // Control point 1 with handle line
                try writer.print(
                    \\    <circle cx="{d}" cy="{d}" r="4" fill="{s}" opacity="0.7"/>
                    \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
                    \\          stroke="{s}" stroke-width="1" stroke-dasharray="4,2"/>
                    \\
                , .{
                    cp1_x,
                    cp1_y,
                    config.control_point_color,
                    from_x,
                    from_y,
                    cp1_x,
                    cp1_y,
                    config.control_point_color,
                });

                // Control point 2 with handle line
                try writer.print(
                    \\    <circle cx="{d}" cy="{d}" r="4" fill="{s}" opacity="0.7"/>
                    \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
                    \\          stroke="{s}" stroke-width="1" stroke-dasharray="4,2"/>
                    \\
                , .{
                    cp2_x,
                    cp2_y,
                    config.control_point_color,
                    to_x,
                    to_y,
                    cp2_x,
                    cp2_y,
                    config.control_point_color,
                });
            }
        },
    }

    // Edge label (if present)
    if (edge.label) |label| {
        const use_path = label_style.on_path orelse config.labels_on_path;
        const label_color = label_style.color orelse style.stroke;
        const font_family = label_style.font_family orelse "monospace";
        const font_size = label_style.font_size orelse 12;
        const position = @min(label_style.position, 100);

        if (use_path) {
            // Emit a hidden path for text (always left-to-right for readable text)
            const ltr = from_x <= to_x;
            const text_x1 = if (ltr) from_x else to_x;
            const text_y1 = if (ltr) from_y else to_y;
            const text_x2 = if (ltr) to_x else from_x;
            const text_y2 = if (ltr) to_y else from_y;
            try writer.print(
                \\    <path id="edgepath{d}" d="M {d} {d} L {d} {d}" fill="none" stroke="none"/>
                \\
            , .{ edge.edge_index, text_x1, text_y1, text_x2, text_y2 });
            try writer.print(
                \\    <text font-family="{s}" font-size="{d}" fill="{s}" dy="-4"
            , .{ font_family, font_size, label_color });
            if (label_style.extra_attrs) |attrs| try writer.print(" {s}", .{attrs});
            try writer.print(
                \\>
                \\      <textPath href="#edgepath{d}" startOffset="{d}%"
                \\              text-anchor="middle" dominant-baseline="auto">"{s}"</textPath></text>
                \\
            , .{ edge.edge_index, position, label });
        } else {
            // Position label along the edge path at the given percentage
            const t_pos: f64 = @as(f64, @floatFromInt(position)) / 100.0;
            const fx: f64 = @floatFromInt(from_x);
            const fy: f64 = @floatFromInt(from_y);
            const tx: f64 = @floatFromInt(to_x);
            const ty: f64 = @floatFromInt(to_y);
            const label_x: isize = @intFromFloat(fx + t_pos * (tx - fx));
            const label_y: isize = @intFromFloat(fy + t_pos * (ty - fy));
            try writer.print(
                \\    <text x="{d}" y="{d}" font-family="{s}" font-size="{d}"
                \\          fill="{s}" text-anchor="middle" dy="-6" dominant-baseline="auto"
            , .{ label_x, label_y, font_family, font_size, label_color });
            if (label_style.extra_attrs) |attrs| try writer.print(" {s}", .{attrs});
            try writer.print(">\"{s}\"</text>\n", .{label});
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers used by the stitched-spline pipeline
// ────────────────────────────────────────────────────────────────────────────

/// Render a simple two-point edge (straight line, dome curve, or reversed arc).
pub fn renderSingleEdge(writer: anytype, from: Point, to: Point, edge_idx: usize, config: SvgConfig, style: ResolvedEdgeStyle, has_label: bool, directed: bool, reversed: bool, from_id: usize, to_id: usize) !void {
    const from_x = from.x * config.char_width + config.padding;
    const from_y = from.y * config.line_height + config.padding;
    const to_x = to.x * config.char_width + config.padding;
    const to_y = to.y * config.line_height + config.padding;

    const dash: []const u8 = if (reversed) " stroke-dasharray=\"6,3\"" else "";

    if (reversed) {
        // Reversed edges arc to the right to avoid overlapping the forward edge.
        // Use a cubic bezier with control points offset to the right.
        const fx: f64 = @floatFromInt(from_x);
        const fy: f64 = @floatFromInt(from_y);
        const tx: f64 = @floatFromInt(to_x);
        const ty: f64 = @floatFromInt(to_y);
        const dist = @abs(ty - fy);
        const bulge = @max(dist * 0.4, 20.0); // arc offset to the right

        try writer.print(
            \\    <path d="M {d:.0} {d:.0} C {d:.0} {d:.0}, {d:.0} {d:.0}, {d:.0} {d:.0}"
            \\          fill="none" stroke="{s}" stroke-width="{d}"{s}
            \\          data-type="edge" data-from="{d}" data-to="{d}"
        , .{ fx, fy, fx + bulge, fy, tx + bulge, ty, tx, ty, style.stroke, config.edge_width, dash, from_id, to_id });
        if (directed) try writeMarkerEndAttr(writer, style);
        try writeExtraAttrs(writer, style);
        try writer.writeAll("/>\n");
    } else {
        // Check if the edge is nearly horizontal (same Y or very close).
        // Horizontal straight lines overlap node borders and are hard to see,
        // so render them as a dome-shaped curve instead.
        const fx: f64 = @floatFromInt(from_x);
        const fy: f64 = @floatFromInt(from_y);
        const tx: f64 = @floatFromInt(to_x);
        const ty: f64 = @floatFromInt(to_y);
        const dy = @abs(ty - fy);
        const dx = @abs(tx - fx);
        const is_horizontal = dy < 2.0 or (dx > 0 and dy / dx < 0.15);

        if (is_horizontal and dx > 10.0) {
            // Dome curve: arc above the nodes so the edge is clearly visible.
            // Control points are offset upward by a fraction of the horizontal span.
            const bulge = @max(dx * 0.35, 20.0);
            // Control points: both above the line, creating a smooth dome
            const cp_y = @min(fy, ty) - bulge;
            try writer.print(
                \\    <path d="M {d:.0} {d:.0} C {d:.0} {d:.0}, {d:.0} {d:.0}, {d:.0} {d:.0}"
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}
            , .{ fx, fy, fx, cp_y, tx, cp_y, tx, ty, style.stroke, config.edge_width, dash });
            try writeEdgeDataAttrs(writer, style.extra_attrs, from_id, to_id);
            if (directed) try writeMarkerEndAttr(writer, style);
            try writeExtraAttrs(writer, style);
            try writer.writeAll("/>\n");
        } else {
            // Normal edge: straight line
            try writer.print(
                \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
                \\          stroke="{s}" stroke-width="{d}"{s}
            , .{ from_x, from_y, to_x, to_y, style.stroke, config.edge_width, dash });
            try writeEdgeDataAttrs(writer, style.extra_attrs, from_id, to_id);
            if (directed) try writeMarkerEndAttr(writer, style);
            try writeExtraAttrs(writer, style);
            try writer.writeAll("/>\n");
        }
    }

    // Emit hidden text path (always left-to-right for readable text)
    if (config.labels_on_path and has_label) {
        const ltr = from_x <= to_x;
        const tx1 = if (ltr) from_x else to_x;
        const ty1 = if (ltr) from_y else to_y;
        const tx2 = if (ltr) to_x else from_x;
        const ty2 = if (ltr) to_y else from_y;
        try writer.print(
            \\    <path id="edgepath{d}" d="M {d} {d} L {d} {d}" fill="none" stroke="none"/>
            \\
        , .{ edge_idx, tx1, ty1, tx2, ty2 });
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Self-loops
// ────────────────────────────────────────────────────────────────────────────

/// Render a self-loop: an arc that exits the right side of the node,
/// curves above it, and re-enters with an arrowhead.
pub fn renderSelfLoop(writer: anytype, edge: *const LayoutEdge, config: SvgConfig, style: ResolvedEdgeStyle, label_style: EdgeLabelStyle, nodes: []const LayoutNode) !void {
    // Semantic wrapper for CSS/JS targeting
    try writer.writeAll("    <g");
    try writeEdgeDataAttrs(writer, style.extra_attrs, edge.from_id, edge.to_id);
    try writer.writeAll(">\n");
    try renderSelfLoopInner(writer, edge, config, style, label_style, nodes);
    try writer.writeAll("    </g>\n");
}

fn renderSelfLoopInner(writer: anytype, edge: *const LayoutEdge, config: SvgConfig, style: ResolvedEdgeStyle, label_style: EdgeLabelStyle, nodes: []const LayoutNode) !void {
    // Find the node to get its position and width
    var node_left_x: usize = edge.from_x;
    var node_width: usize = 3; // fallback
    var node_top_y: usize = edge.from_y;
    for (nodes) |node| {
        if (node.id == edge.from_id) {
            node_left_x = node.x;
            node_width = node.width;
            node_top_y = node.y;
            break;
        }
    }

    // Node rectangle position and dimensions in pixels
    const node_x: f64 = @floatFromInt(node_left_x * config.char_width + config.padding);
    const node_y: f64 = @floatFromInt(node_top_y * config.line_height + config.padding);
    const node_w: f64 = @floatFromInt(node_width * config.char_width);
    const node_h: f64 = @floatFromInt(config.line_height);

    // Right edge of the node box
    const right_x = node_x + node_w;
    const center_y = node_y + node_h / 2.0;

    // Loop arc on the right side of the node:
    //   - Starts from the right edge, slightly above center
    //   - Arcs outward to the right
    //   - Ends at the right edge, slightly below center (arrow points in)
    const gap = 6.0; // half the vertical gap between start and end points
    const r: f64 = 14.0; // arc radius

    // Start: upper point on the right edge of the node
    const sx = right_x;
    const sy = center_y - gap;
    // End: lower point on the right edge — arrow tip enters here
    const ex = right_x;
    const ey = center_y + gap;

    // SVG arc: sweep-flag=1 (clockwise) draws the arc bulging to the right
    try writer.print(
        \\    <path d="M {d:.0} {d:.0} A {d:.0} {d:.0} 0 1 1 {d:.0} {d:.0}"
        \\          fill="none" stroke="{s}" stroke-width="{d}" stroke-dasharray="6,3"
    , .{ sx, sy, r, r, ex, ey, style.stroke, config.edge_width });
    try writeMarkerEndAttr(writer, style);
    try writeExtraAttrs(writer, style);
    try writer.writeAll("/>\n");

    // Label: positioned to the right of the arc
    if (edge.label) |label| {
        const label_color = label_style.color orelse style.stroke;
        const font_family = label_style.font_family orelse "monospace";
        const font_size = label_style.font_size orelse 12;
        const label_x = right_x + r * 2.0 + 4.0;
        const label_y = center_y + 4.0;
        try writer.print(
            \\    <text x="{d:.0}" y="{d:.0}" font-family="{s}" font-size="{d}"
            \\          fill="{s}" text-anchor="start" dominant-baseline="auto"
        , .{ label_x, label_y, font_family, font_size, label_color });
        if (label_style.extra_attrs) |attrs| try writer.print(" {s}", .{attrs});
        try writer.print(">\"" ++ "{s}" ++ "\"</text>\n", .{label});
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Standalone bezier (public API)
// ────────────────────────────────────────────────────────────────────────────

/// Render a cubic bezier curve (for spline routing).
/// Control points p1 and p2 define the curve shape.
pub fn renderBezierEdge(
    writer: anytype,
    from_x: usize,
    from_y: usize,
    p1_x: usize,
    p1_y: usize,
    p2_x: usize,
    p2_y: usize,
    to_x: usize,
    to_y: usize,
    config: SvgConfig,
    style: ResolvedEdgeStyle,
    directed: bool,
) !void {
    // Cubic bezier curve: C p1x,p1y p2x,p2y x,y
    try writer.print(
        \\    <path d="M {d} {d} C {d} {d}, {d} {d}, {d} {d}" 
        \\          fill="none" stroke="{s}" stroke-width="{d}"
    , .{
        from_x,
        from_y,
        p1_x,
        p1_y,
        p2_x,
        p2_y,
        to_x,
        to_y,
        style.stroke,
        config.edge_width,
    });
    if (directed) try writeMarkerEndAttr(writer, style);
    try writeExtraAttrs(writer, style);
    try writer.writeAll("/>\n");

    // Show control points for debugging
    if (config.show_control_points) {
        // Control point 1
        try writer.print(
            \\    <circle cx="{d}" cy="{d}" r="4" fill="{s}" opacity="0.7"/>
            \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
            \\          stroke="{s}" stroke-width="1" stroke-dasharray="4,2"/>
            \\
        , .{
            p1_x,
            p1_y,
            config.control_point_color,
            from_x,
            from_y,
            p1_x,
            p1_y,
            config.control_point_color,
        });

        // Control point 2
        try writer.print(
            \\    <circle cx="{d}" cy="{d}" r="4" fill="{s}" opacity="0.7"/>
            \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
            \\          stroke="{s}" stroke-width="1" stroke-dasharray="4,2"/>
            \\
        , .{
            p2_x,
            p2_y,
            config.control_point_color,
            to_x,
            to_y,
            p2_x,
            p2_y,
            config.control_point_color,
        });
    }
}

// ── Shared helpers ──────────────────────────────────────────────────────────

/// Conditionally write ` data-type="edge" data-from="{id}" data-to="{id}"`.
///
/// Skips any attribute already present in `extra_attrs` to avoid XML
/// duplicate-attribute errors (fatal in SVG).
fn writeEdgeDataAttrs(writer: anytype, extra_attrs: ?[]const u8, from_id: usize, to_id: usize) !void {
    if (!helpers.attrsContain(extra_attrs, "data-type"))
        try writer.print(" data-type=\"edge\"", .{});
    if (!helpers.attrsContain(extra_attrs, "data-from"))
        try writer.print(" data-from=\"{d}\"", .{from_id});
    if (!helpers.attrsContain(extra_attrs, "data-to"))
        try writer.print(" data-to=\"{d}\"", .{to_id});
}

/// Write ` marker-end="url(#zg-m-{id})"` and/or ` marker-start="url(#zg-m-{id})"` if set.
fn writeMarkerEndAttr(writer: anytype, style: ResolvedEdgeStyle) !void {
    if (style.marker_end_id) |mid| {
        try writer.print(" marker-end=\"url(#zg-m-{d})\"", .{mid});
    }
    if (style.marker_start_id) |mid| {
        try writer.print(" marker-start=\"url(#zg-m-{d})\"", .{mid});
    }
}

/// Write ` {extra_attrs}` if present.
fn writeExtraAttrs(writer: anytype, style: ResolvedEdgeStyle) !void {
    if (style.extra_attrs) |attrs| {
        try writer.print(" {s}", .{attrs});
    }
}
