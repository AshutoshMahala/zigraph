//! Subgraph box painting for the terminal renderer.

const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const Buffer2D = @import("buffer.zig").Buffer2D;
const j = @import("junctions.zig");

/// Paint subgraph bounding boxes onto the buffer using double-line box characters.
/// Renders parent subgraphs first (larger boxes in background), then children on top.
/// Labels are painted separately via `paintSubgraphLabels` after edges and nodes.
pub fn paintSubgraphs(buffer: *Buffer2D, layout_ir: *const LayoutIR) void {
    const items = layout_ir.subgraphs.items;
    if (items.len == 0) return;

    // Render in reverse order: parents first (they appear last in the array
    // since computeBoundingBoxes processes deepest-first).
    var idx: usize = items.len;
    while (idx > 0) {
        idx -= 1;
        const sg = items[idx];
        paintSubgraphBox(buffer, sg.x, sg.y, sg.width, sg.height);
    }
}

/// Paint subgraph labels after edges and nodes so they remain visible.
pub fn paintSubgraphLabels(buffer: *Buffer2D, layout_ir: *const LayoutIR) void {
    for (layout_ir.subgraphs.items) |sg| {
        if (sg.label.len == 0) continue;
        if (sg.width < 4 or sg.height < 3) continue;

        const max_label_len = sg.width - 4; // leave room for borders + spacing
        const display_len = @min(sg.label.len, max_label_len);
        if (display_len == 0) continue;

        // Place label starting at x+2 on the row just below the top border
        const label_start = sg.x + 2;
        const label_y = sg.y + 1;
        for (sg.label[0..display_len], 0..) |ch, i| {
            buffer.set(label_start + i, label_y, @as(u21, ch));
        }
    }
}

/// Draw a single subgraph box with double-line borders.
pub fn paintSubgraphBox(buffer: *Buffer2D, x: usize, y: usize, w: usize, h: usize) void {
    if (w < 2 or h < 2) return;

    const right = x + w - 1;
    const bottom = y + h - 1;

    // Corners
    buffer.set(x, y, j.CP_SG_UR); // top-left
    buffer.set(right, y, j.CP_SG_UL); // top-right
    buffer.set(x, bottom, j.CP_SG_DR); // bottom-left
    buffer.set(right, bottom, j.CP_SG_DL); // bottom-right

    // Top and bottom horizontal lines
    var col = x + 1;
    while (col < right) : (col += 1) {
        buffer.set(col, y, j.CP_SG_H);
        buffer.set(col, bottom, j.CP_SG_H);
    }

    // Left and right vertical lines
    var row = y + 1;
    while (row < bottom) : (row += 1) {
        buffer.set(x, row, j.CP_SG_V);
        buffer.set(right, row, j.CP_SG_V);
    }
}
