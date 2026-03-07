//! SVG subgraph rendering.
//!
//! Renders subgraph (cluster) bounding boxes as styled `<g>` wrappers
//! containing arbitrary SVG from `SubgraphStyle.box_svg`.
//! Parents are drawn first (lower z-order) so children paint on top.

const config_mod = @import("config.zig");
const SubgraphStyle = config_mod.SubgraphStyle;
const SvgConfig = config_mod.SvgConfig;
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);

/// Render subgraph bounding boxes as styled `<g>` elements.
/// Renders parent subgraphs first (lower z-order) so children draw on top.
///
/// Each subgraph is rendered as:
/// ```svg
/// <g transform="translate(x,y)" fill="..." fill-opacity="..." stroke="..." {extra_attrs}>
///   {box_svg}
/// </g>
/// ```
pub fn renderSubgraphs(
    writer: anytype,
    layout: *const LayoutIR,
    config: SvgConfig,
    subgraph_styles: []const SubgraphStyle,
) !void {
    // Render in IR order: parents before children (bottom-up computed, stored deepest first).
    // Reverse iteration gives parents first → correct z-order.
    const items = layout.subgraphs.items;
    var i: usize = items.len;
    while (i > 0) {
        i -= 1;
        const sg = items[i];
        const style = subgraph_styles[i];

        const x = sg.x * config.char_width + config.padding;
        const y = sg.y * config.line_height + config.padding;

        // Subgraph wrapper <g> with positioning and inherited colors
        try writer.print(
            \\    <g transform="translate({d},{d})" fill="{s}" fill-opacity="{s}" stroke="{s}"
        , .{ x, y, style.fill, style.fill_opacity, style.stroke });

        if (style.extra_attrs) |attrs| {
            try writer.print(" {s}", .{attrs});
        }
        try writer.writeAll(">\n");

        // Write box_svg content (shape + label, indented)
        try writer.writeAll("      ");
        try writer.writeAll(style.box_svg);
        try writer.writeAll("\n");

        try writer.writeAll("    </g>\n");
    }
}
