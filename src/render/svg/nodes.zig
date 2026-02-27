//! SVG node rendering.
//!
//! Renders graph nodes as labeled rounded rectangles.
//! Explicit nodes get solid borders, implicit nodes get dashed borders,
//! and dummy nodes are rendered as small circles when visible.

const ir_mod = @import("../../core/ir.zig");
const LayoutNode = ir_mod.LayoutNode(usize);
const SvgConfig = @import("config.zig").SvgConfig;

/// Render a single LayoutNode as an SVG rectangle with a centered label.
pub fn renderNode(writer: anytype, node: LayoutNode, config: SvgConfig) !void {
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
