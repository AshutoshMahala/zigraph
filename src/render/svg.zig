//! SVG Renderer for zigraph
//!
//! Renders LayoutIR to Scalable Vector Graphics (SVG) format.
//! Essential for:
//! - Visualizing bezier curves and spline control points
//! - High-quality output for documentation
//! - Browser-based visualization
//! - Debugging edge routing algorithms
//!
//! ## Usage
//!
//! ```zig
//! var ir = try zigraph.layout(&graph, allocator, .{});
//! defer ir.deinit();
//!
//! const svg = try zigraph.svg.render(&ir, allocator, .{});
//! defer allocator.free(svg);
//!
//! // Write to file
//! try std.fs.cwd().writeFile("graph.svg", svg);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const LayoutNode = ir_mod.LayoutNode(usize);
const LayoutEdge = ir_mod.LayoutEdge(usize);
const EdgePath = ir_mod.EdgePath(usize);
const colors = @import("colors.zig");

/// SVG rendering configuration
pub const SvgConfig = struct {
    /// Pixels per character cell (horizontal)
    char_width: usize = 10,
    /// Pixels per line (vertical)
    line_height: usize = 20,
    /// Padding around the entire SVG
    padding: usize = 20,
    /// Node corner radius
    node_radius: usize = 4,
    /// Node fill color
    node_fill: []const u8 = "#f0f0f0",
    /// Node stroke color
    node_stroke: []const u8 = "#333333",
    /// Edge stroke color (used when color_edges is false)
    edge_stroke: []const u8 = "#666666",
    /// Edge stroke width
    edge_width: usize = 2,
    /// Arrow size
    arrow_size: usize = 8,
    /// Stitch edge segments through dummies into smooth splines
    stitch_splines: bool = true,
    /// Show dummy nodes (when false, they're hidden)
    show_dummy_nodes: bool = false,
    /// Use distinct colors for each edge
    color_edges: bool = false,
    /// Color palette for edges (when color_edges is true)
    /// Defaults to colors.radix (Radix UI shade 9)
    edge_palette: []const []const u8 = &colors.radix,
    /// Font family
    font_family: []const u8 = "monospace",
    /// Font size in pixels
    font_size: usize = 12,
    /// Show control points for debugging bezier curves
    show_control_points: bool = false,
    /// Control point color (when show_control_points is true)
    control_point_color: []const u8 = "#ff0000",
    /// Render edge labels along the path using SVG <textPath>
    /// When false (default), labels are placed at fixed positions near the edge.
    /// When true, labels follow the edge curve using SVG text-on-a-path.
    labels_on_path: bool = false,

    /// Get the color for a specific edge index
    pub fn getEdgeColor(self: SvgConfig, edge_index: usize) []const u8 {
        if (!self.color_edges) return self.edge_stroke;
        return colors.get(self.edge_palette, edge_index);
    }
};

/// Render any GenericLayoutIR to SVG string.
/// Converts coordinates to usize if needed, then renders.
pub fn renderGeneric(comptime Coord: type, layout: *const ir_mod.LayoutIR(Coord), allocator: Allocator, config: SvgConfig) ![]u8 {
    if (Coord == usize) {
        return render(layout, allocator, config);
    }
    var converted = try layout.convertCoord(usize, allocator);
    defer converted.deinit();
    return render(&converted, allocator, config);
}

/// Render LayoutIR to SVG string
pub fn render(layout: *const LayoutIR, allocator: Allocator, config: SvgConfig) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    // Calculate dimensions with overflow checking
    const width = std.math.mul(usize, layout.width, config.char_width) catch return error.OutOfMemory;
    const width_padded = std.math.add(usize, width, config.padding * 2) catch return error.OutOfMemory;
    const height = std.math.mul(usize, layout.height, config.line_height) catch return error.OutOfMemory;
    const height_padded = std.math.add(usize, height, config.padding * 2) catch return error.OutOfMemory;

    // SVG header
    try writer.print(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<svg xmlns="http://www.w3.org/2000/svg" 
        \\     width="{d}" height="{d}" 
        \\     viewBox="0 0 {d} {d}">
        \\
        \\  <!-- Arrow marker definitions -->
        \\  <defs>
        \\
    , .{ width_padded, height_padded, width_padded, height_padded });

    // Generate arrowhead markers
    if (config.color_edges) {
        // One marker per color in palette
        for (config.edge_palette, 0..) |color, i| {
            try writer.print(
                \\    <marker id="arrow{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="0 0, {d} {d}, 0 {d}" fill="{s}"/>
                \\    </marker>
                \\
            , .{
                i,
                config.arrow_size,
                config.arrow_size,
                config.arrow_size,
                config.arrow_size / 2,
                config.arrow_size,
                config.arrow_size / 2,
                config.arrow_size,
                color,
            });
        }
    } else {
        // Single default arrowhead
        try writer.print(
            \\    <marker id="arrow0" markerWidth="{d}" markerHeight="{d}" 
            \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
            \\      <polygon points="0 0, {d} {d}, 0 {d}" fill="{s}"/>
            \\    </marker>
            \\
        , .{
            config.arrow_size,
            config.arrow_size,
            config.arrow_size,
            config.arrow_size / 2,
            config.arrow_size,
            config.arrow_size / 2,
            config.arrow_size,
            config.edge_stroke,
        });
    }

    try writer.writeAll(
        \\  </defs>
        \\
        \\  <!-- Background -->
        \\  <rect width="100%" height="100%" fill="white"/>
        \\
        \\  <!-- Edges (rendered first, under nodes) -->
        \\  <g id="edges">
        \\
    );

    // Render edges
    if (config.stitch_splines) {
        // Group edges by edge_index and render as stitched splines
        try renderStitchedEdges(writer, layout, allocator, config);
    } else {
        // Render each edge segment individually
        for (layout.edges.items) |edge| {
            // Self-loops: render a loop arc
            if (edge.reversed and edge.from_id == edge.to_id) {
                try renderSelfLoop(writer, &edge, edge.edge_index, config, layout.nodes.items);
                continue;
            }
            try renderEdge(writer, edge, config);
        }
    }

    try writer.writeAll(
        \\  </g>
        \\
        \\  <!-- Nodes -->
        \\  <g id="nodes">
        \\
    );

    // Render nodes
    for (layout.nodes.items) |node| {
        // Skip dummy nodes if not showing them
        if (node.kind == .dummy and !config.show_dummy_nodes) continue;
        try renderNode(writer, node, config);
    }

    // SVG footer
    try writer.writeAll(
        \\  </g>
        \\
        \\</svg>
        \\
    );

    return buffer.toOwnedSlice(allocator);
}

fn renderNode(writer: anytype, node: LayoutNode, config: SvgConfig) !void {
    const x = node.x * config.char_width + config.padding;
    const y = node.y * config.line_height + config.padding;
    const w = node.width * config.char_width;
    const h = config.line_height;

    // Dummy nodes are rendered as small circles
    if (node.kind == .dummy) {
        const cx = x + w / 2;
        const cy = y + h / 2;
        try writer.print(
            \\    <circle cx="{d}" cy="{d}" r="4" 
            \\            fill="#ff6600" stroke="#cc4400" stroke-width="1"/>
            \\
        , .{ cx, cy });
        return;
    }

    // Different styles based on node kind
    const stroke_style: []const u8 = switch (node.kind) {
        .explicit => "",
        .implicit => " stroke-dasharray=\"4,2\"", // Dashed border for implicit nodes
        .dummy => "", // Handled above
    };

    // Node rectangle
    try writer.print(
        \\    <rect x="{d}" y="{d}" width="{d}" height="{d}" 
        \\          rx="{d}" ry="{d}" 
        \\          fill="{s}" stroke="{s}" stroke-width="1"{s}/>
        \\
    , .{
        x,
        y,
        w,
        h,
        config.node_radius,
        config.node_radius,
        config.node_fill,
        config.node_stroke,
        stroke_style,
    });

    // Node label (centered)
    const text_x = x + w / 2;
    const text_y = y + h / 2 + config.font_size / 3; // Approximate vertical centering

    try writer.print(
        \\    <text x="{d}" y="{d}" 
        \\          font-family="{s}" font-size="{d}" 
        \\          text-anchor="middle" fill="{s}">{s}</text>
        \\
    , .{
        text_x,
        text_y,
        config.font_family,
        config.font_size,
        config.node_stroke,
        node.label,
    });
}

fn renderEdge(writer: anytype, edge: LayoutEdge, config: SvgConfig) !void {
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

    const marker: []const u8 = if (edge.directed)
        " marker-end=\"url(#arrowhead)\""
    else
        "";

    const dash: []const u8 = if (edge.reversed) " stroke-dasharray=\"6,3\"" else "";

    switch (edge.path) {
        .direct => {
            // Simple straight line with optional arrow
            try writer.print(
                \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
                \\          stroke="{s}" stroke-width="{d}"{s}{s}/>
                \\
            , .{
                from_x,
                from_y,
                to_x,
                to_y,
                config.edge_stroke,
                config.edge_width,
                dash,
                marker,
            });
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
                    \\          fill="none" stroke="{s}" stroke-width="{d}"{s}{s}/>
                    \\
                , .{
                    real_to_x,
                    real_to_y,
                    real_to_x,
                    corner_y,
                    real_from_x,
                    real_from_y,
                    config.edge_stroke,
                    config.edge_width,
                    dash,
                    marker,
                });
            } else {
            try writer.print(
                \\    <path d="M {d} {d} L {d} {d} L {d} {d}" 
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}{s}/>
                \\
            , .{
                from_x,
                from_y,
                from_x,
                corner_y,
                to_x,
                to_y,
                config.edge_stroke,
                config.edge_width,
                dash,
                marker,
            });
            }
        },
        .side_channel => |sc| {
            // Side channel routing
            const channel_x = sc.channel_x * config.char_width + config.padding;
            const start_y = sc.start_y * config.line_height + config.padding;
            const end_y = sc.end_y * config.line_height + config.padding;
            try writer.print(
                \\    <path d="M {d} {d} L {d} {d} L {d} {d} L {d} {d}" 
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}{s}/>
                \\
            , .{
                from_x,
                from_y,
                channel_x,
                start_y,
                channel_x,
                end_y,
                to_x,
                to_y,
                config.edge_stroke,
                config.edge_width,
                dash,
                marker,
            });
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
                \\ fill="none" stroke="{s}" stroke-width="{d}"{s}{s}/>
                \\
            , .{
                config.edge_stroke,
                config.edge_width,
                dash,
                marker,
            });
        },
        .spline => |sp| {
            // Cubic bezier curve
            const cp1_x = sp.cp1_x * config.char_width + config.padding;
            const cp1_y = sp.cp1_y * config.line_height + config.padding;
            const cp2_x = sp.cp2_x * config.char_width + config.padding;
            const cp2_y = sp.cp2_y * config.line_height + config.padding;

            try writer.print(
                \\    <path d="M {d} {d} C {d} {d}, {d} {d}, {d} {d}" 
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}{s}/>
                \\
            , .{
                from_x,
                from_y,
                cp1_x,
                cp1_y,
                cp2_x,
                cp2_y,
                to_x,
                to_y,
                config.edge_stroke,
                config.edge_width,
                dash,
                marker,
            });

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
        const stroke_color = if (config.color_edges) config.getEdgeColor(edge.edge_index) else config.edge_stroke;
        if (config.labels_on_path) {
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
                \\    <text font-family="monospace" font-size="12" fill="{s}" dy="-4">
                \\      <textPath href="#edgepath{d}" startOffset="50%"
                \\              text-anchor="middle" dominant-baseline="auto">"{s}"</textPath></text>
                \\
            , .{ stroke_color, edge.edge_index, label });
        } else {
            // Center label at the edge midpoint (not terminal layout position)
            const mid_x = (from_x + to_x) / 2;
            const mid_y = (from_y + to_y) / 2;
            try writer.print(
                \\    <text x="{d}" y="{d}" font-family="monospace" font-size="12"
                \\          fill="{s}" text-anchor="middle" dy="-6" dominant-baseline="auto">"{s}"</text>
                \\
            , .{ mid_x, mid_y, stroke_color, label });
        }
    }
}

/// Render a cubic bezier curve (for spline routing)
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
    directed: bool,
) !void {
    const marker: []const u8 = if (directed)
        " marker-end=\"url(#arrowhead)\""
    else
        "";
    // Cubic bezier curve: C p1x,p1y p2x,p2y x,y
    try writer.print(
        \\    <path d="M {d} {d} C {d} {d}, {d} {d}, {d} {d}" 
        \\          fill="none" stroke="{s}" stroke-width="{d}"{s}/>
        \\
    , .{
        from_x,
        from_y,
        p1_x,
        p1_y,
        p2_x,
        p2_y,
        to_x,
        to_y,
        config.edge_stroke,
        config.edge_width,
        marker,
    });

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

/// Point for spline path
const Point = struct {
    x: usize,
    y: usize,
};

/// Render edges by grouping segments with the same edge_index into smooth splines.
/// This stitches multi-segment edges through dummy nodes into single curved paths.
fn renderStitchedEdges(writer: anytype, layout: *const LayoutIR, allocator: Allocator, config: SvgConfig) !void {
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

        // Self-loops: render a loop arc to the right of the node
        if (segments.items[0].reversed and segments.items[0].from_id == segments.items[0].to_id) {
            try renderSelfLoop(writer, &segments.items[0], edge_idx, config, layout.nodes.items);
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
            try renderSingleEdge(writer, points.items[0], points.items[1], edge_idx, config, has_label, is_directed, is_reversed);
        } else {
            // Multi-point: render as smooth spline
            try renderSplinePath(writer, points.items, edge_idx, config, has_label, is_directed, is_reversed);
        }

        // Render edge label (if any segment carries one)
        if (edge_label) |label| {
            const stroke_color = if (config.color_edges) config.getEdgeColor(edge_idx) else config.edge_stroke;
            if (config.labels_on_path) {
                // Text follows the edge path curve (hidden path is always L→R)
                try writer.print(
                    \\    <text font-family="monospace" font-size="12" fill="{s}" dy="-4">
                    \\      <textPath href="#edgepath{d}" startOffset="50%"
                    \\              text-anchor="middle" dominant-baseline="auto">"{s}"</textPath></text>
                    \\
                , .{ stroke_color, edge_idx, label });
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
                , .{ mx + label_offset_x, my, stroke_color, label });
            }
        }
    }
}

/// Render a simple two-point edge
fn renderSingleEdge(writer: anytype, from: Point, to: Point, edge_idx: usize, config: SvgConfig, has_label: bool, directed: bool, reversed: bool) !void {
    const from_x = from.x * config.char_width + config.padding;
    const from_y = from.y * config.line_height + config.padding;
    const to_x = to.x * config.char_width + config.padding;
    const to_y = to.y * config.line_height + config.padding;

    const color = config.getEdgeColor(edge_idx);
    const arrow_id = if (config.color_edges) edge_idx % config.edge_palette.len else 0;
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

        if (directed) {
            try writer.print(
                \\    <path d="M {d:.0} {d:.0} C {d:.0} {d:.0}, {d:.0} {d:.0}, {d:.0} {d:.0}"
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}
                \\          marker-end="url(#arrow{d})"/>
                \\
            , .{ fx, fy, fx + bulge, fy, tx + bulge, ty, tx, ty, color, config.edge_width, dash, arrow_id });
        } else {
            try writer.print(
                \\    <path d="M {d:.0} {d:.0} C {d:.0} {d:.0}, {d:.0} {d:.0}, {d:.0} {d:.0}"
                \\          fill="none" stroke="{s}" stroke-width="{d}"{s}/>
                \\
            , .{ fx, fy, fx + bulge, fy, tx + bulge, ty, tx, ty, color, config.edge_width, dash });
        }
    } else {
        // Normal edge: straight line
        if (directed) {
            try writer.print(
                \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
                \\          stroke="{s}" stroke-width="{d}"{s} 
                \\          marker-end="url(#arrow{d})"/>
                \\
            , .{ from_x, from_y, to_x, to_y, color, config.edge_width, dash, arrow_id });
        } else {
            try writer.print(
                \\    <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" 
                \\          stroke="{s}" stroke-width="{d}"{s}/>
                \\
            , .{ from_x, from_y, to_x, to_y, color, config.edge_width, dash });
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

/// Render a self-loop: an arc that exits the right side of the node,
/// curves above it, and re-enters with an arrowhead.
/// Visual: a circle/arc above-right of the node pointing back into it.
fn renderSelfLoop(writer: anytype, edge: *const LayoutEdge, edge_idx: usize, config: SvgConfig, nodes: []const LayoutNode) !void {
    const color = config.getEdgeColor(edge_idx);
    const arrow_id = if (config.color_edges) edge_idx % config.edge_palette.len else 0;

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
        \\          marker-end="url(#arrow{d})"/>
        \\
    , .{ sx, sy, r, r, ex, ey, color, config.edge_width, arrow_id });

    // Label: positioned to the right of the arc
    if (edge.label) |label| {
        const label_x = right_x + r * 2.0 + 4.0;
        const label_y = center_y + 4.0;
        try writer.print(
            \\    <text x="{d:.0}" y="{d:.0}" font-family="monospace" font-size="12"
            \\          fill="{s}" text-anchor="start" dominant-baseline="auto">"{s}"</text>
            \\
        , .{ label_x, label_y, color, label });
    }
}

/// Render a multi-point path as a smooth cubic bezier spline.
/// Uses Catmull-Rom to Bezier conversion for smooth curves through all points.
fn renderSplinePath(writer: anytype, points: []const Point, edge_idx: usize, config: SvgConfig, has_label: bool, directed: bool, reversed: bool) !void {
    if (points.len < 2) return;

    const color = config.getEdgeColor(edge_idx);
    const arrow_id = if (config.color_edges) edge_idx % config.edge_palette.len else 0;

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

    if (directed) {
        try writer.print(
            \\ fill="none" stroke="{s}" stroke-width="{d}"{s} 
            \\          marker-end="url(#arrow{d})"/>
            \\
        , .{ color, config.edge_width, dash, arrow_id });
    } else {
        try writer.print(
            \\ fill="none" stroke="{s}" stroke-width="{d}"{s}/>
            \\
        , .{ color, config.edge_width, dash });
    }

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

// ============================================================================
// Tests
// ============================================================================

test "svg: basic render" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "Test",
        .x = 0,
        .y = 0,
        .width = 6,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(10, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain SVG structure
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Test") != null);
}

test "svg: edge rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 2,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 2,
        .path = .direct,
        .edge_index = 0,
    });

    layout.setDimensions(5, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain line element for direct edge
    try std.testing.expect(std.mem.indexOf(u8, svg, "<line") != null);
}

test "svg: corner edge rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1, .label = "A", .x = 0, .y = 0, .width = 3,
        .center_x = 1, .level = 0, .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2, .label = "B", .x = 5, .y = 4, .width = 3,
        .center_x = 6, .level = 1, .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1, .to_id = 2, .from_x = 1, .from_y = 1,
        .to_x = 6, .to_y = 4, .path = .{ .corner = .{ .horizontal_y = 2 } },
        .edge_index = 0,
    });

    layout.setDimensions(10, 6);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Corner edges use path elements
    try std.testing.expect(std.mem.indexOf(u8, svg, "<path") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "marker-end") != null);
}

test "svg: multiple nodes and edges" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    // Build a small diamond: A -> B, A -> C, B -> D, C -> D
    try layout.addNode(.{
        .id = 1, .label = "A", .x = 5, .y = 0, .width = 3,
        .center_x = 6, .level = 0, .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2, .label = "B", .x = 0, .y = 4, .width = 3,
        .center_x = 1, .level = 1, .level_position = 0,
    });
    try layout.addNode(.{
        .id = 3, .label = "C", .x = 10, .y = 4, .width = 3,
        .center_x = 11, .level = 1, .level_position = 1,
    });
    try layout.addNode(.{
        .id = 4, .label = "D", .x = 5, .y = 8, .width = 3,
        .center_x = 6, .level = 2, .level_position = 0,
    });

    for ([_]struct { from: usize, to: usize, idx: usize }{
        .{ .from = 1, .to = 2, .idx = 0 },
        .{ .from = 1, .to = 3, .idx = 1 },
        .{ .from = 2, .to = 4, .idx = 2 },
        .{ .from = 3, .to = 4, .idx = 3 },
    }) |e| {
        try layout.addEdge(.{
            .from_id = e.from, .to_id = e.to,
            .from_x = 6, .from_y = 1,
            .to_x = 6, .to_y = 4,
            .path = .direct, .edge_index = e.idx,
        });
    }

    layout.setDimensions(15, 10);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain all 4 node labels
    try std.testing.expect(std.mem.indexOf(u8, svg, ">A<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">B<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">C<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">D<") != null);
    // Should have valid SVG structure
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
}

test "svg: empty layout" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    layout.setDimensions(0, 0);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should still produce valid SVG
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
}

test "svg: colored edges" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1, .label = "A", .x = 0, .y = 0, .width = 3,
        .center_x = 1, .level = 0, .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2, .label = "B", .x = 0, .y = 4, .width = 3,
        .center_x = 1, .level = 1, .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1, .to_id = 2, .from_x = 1, .from_y = 1,
        .to_x = 1, .to_y = 4, .path = .direct, .edge_index = 0,
    });

    layout.setDimensions(5, 5);

    const svg = try render(&layout, allocator, .{ .color_edges = true });
    defer allocator.free(svg);

    // Should contain colored stroke from palette
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke=") != null);
}
