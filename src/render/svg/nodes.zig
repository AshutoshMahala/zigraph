//! SVG node rendering.
//!
//! Shape-agnostic: the renderer places a `<g>` wrapper at the node's
//! coordinates with inherited fill/stroke, then writes whatever SVG
//! geometry `NodeStyle.shape_svg` contains (rect, polygon, ellipse,
//! path, image — anything). Built-in shapes are presets in `config.shapes`.
//! Dummy nodes are rendered as small circles directly (no style fn).

const config_mod = @import("config.zig");
const SvgConfig = config_mod.SvgConfig;
const NodeStyle = config_mod.NodeStyle;
const ir_mod = @import("../../core/ir.zig");
const LayoutNode = ir_mod.LayoutNode(usize);
const helpers = @import("helpers.zig");

/// Render a real (non-dummy) node using its pre-computed `NodeStyle`.
///
/// Writes a `<g>` wrapper with `translate`, `fill`, and `stroke`, then
/// the shape_svg content. The style function controls everything inside
/// the bounding box — shape geometry, label text, font, etc.
pub fn renderNode(writer: anytype, node: LayoutNode, style: NodeStyle, config: SvgConfig) !void {
    const x = node.x * config.char_width + config.padding;
    const y = node.y * config.line_height + config.padding;

    try writer.print(
        \\    <g transform="translate({d},{d})" fill="{s}" stroke="{s}"
    , .{ x, y, style.fill, style.stroke });
    // Emit native data attrs only when extra_attrs doesn't already provide them
    if (!helpers.attrsContain(style.extra_attrs, "data-type"))
        try writer.print(" data-type=\"node\"", .{});
    if (!helpers.attrsContain(style.extra_attrs, "data-id"))
        try writer.print(" data-id=\"{d}\"", .{node.id});
    if (style.extra_attrs) |attrs| {
        try writer.print(" {s}", .{attrs});
    }
    try writer.writeAll(">\n");
    try writer.writeAll("      ");
    try writer.writeAll(style.shape_svg);
    try writer.writeAll("\n    </g>\n");
}

/// Render a dummy node as a small fixed-style circle.
///
/// Dummy nodes are internal to the Sugiyama layout algorithm — they exist
/// as waypoints for multi-segment edges. Not customizable via `node_style_fn`.
pub fn renderDummyNode(writer: anytype, node: LayoutNode, config: SvgConfig) !void {
    const x = node.x * config.char_width + config.padding;
    const y = node.y * config.line_height + config.padding;
    const w = node.width * config.char_width;
    const h = node.height * config.line_height;
    const cx = x + w / 2;
    const cy = y + h / 2;
    try writer.print(
        \\    <circle cx="{d}" cy="{d}" r="4" 
        \\            fill="#ff6600" stroke="#cc4400" stroke-width="1"/>
        \\
    , .{ cx, cy });
}
