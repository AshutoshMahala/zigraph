//! SVG subgraph rendering.
//!
//! Renders subgraph (cluster) bounding boxes as labeled dashed rounded
//! rectangles. Parents are drawn first (lower z-order) so children
//! paint on top.

const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const SvgConfig = @import("config.zig").SvgConfig;

/// Render subgraph bounding boxes as labeled rounded rectangles.
/// Renders parent subgraphs first (lower z-order) so children draw on top.
pub fn renderSubgraphs(writer: anytype, layout: *const LayoutIR, config: SvgConfig) !void {
    // Render in IR order: parents before children (bottom-up computed, stored deepest first).
    // Reverse iteration gives parents first → correct z-order.
    const items = layout.subgraphs.items;
    var i: usize = items.len;
    while (i > 0) {
        i -= 1;
        const sg = items[i];

        const x = sg.x * config.char_width + config.padding;
        const y = sg.y * config.line_height + config.padding;
        const w = sg.width * config.char_width;
        const h = sg.height * config.line_height;

        // Subgraph box
        try writer.print(
            \\    <rect x="{d}" y="{d}" width="{d}" height="{d}" 
            \\          rx="{d}" ry="{d}" 
            \\          fill="{s}" fill-opacity="{s}" 
            \\          stroke="{s}" stroke-width="1" stroke-dasharray="4,2"/>
            \\
        , .{
            x,                      y,                      w,                    h,
            config.subgraph_radius, config.subgraph_radius, config.subgraph_fill, config.subgraph_fill_opacity,
            config.subgraph_stroke,
        });

        // Subgraph label (top-left, inside the box)
        if (sg.label.len > 0) {
            const label_x = x + config.subgraph_radius;
            const label_y = y + config.subgraph_font_size + 2;
            try writer.print(
                \\    <text x="{d}" y="{d}" 
                \\          font-family="{s}" font-size="{d}" 
                \\          font-weight="bold" fill="{s}">{s}</text>
                \\
            , .{
                label_x,                     label_y,
                config.font_family,          config.subgraph_font_size,
                config.subgraph_label_color, sg.label,
            });
        }
    }
}
