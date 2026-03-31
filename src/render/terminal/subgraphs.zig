//! Subgraph box painting for the terminal renderer.
//!
//! Supports configurable border styles (single/double/heavy/dashed/none),
//! border color, and label positioning (top_left/top_center/inside).

const Buffer2D = @import("buffer.zig").Buffer2D;
const config_mod = @import("config.zig");
const CellColor = config_mod.CellColor;
const TextAttrs = config_mod.TextAttrs;
const SubgraphBorder = config_mod.SubgraphBorder;
const LabelPosition = config_mod.LabelPosition;
const TerminalSubgraphStyle = config_mod.TerminalSubgraphStyle;
const j = @import("junctions.zig");

/// Characters for each border style: { top-left, top-right, bottom-left, bottom-right, horizontal, vertical }
const BorderChars = struct {
    tl: u21, // top-left corner
    tr: u21, // top-right corner
    bl: u21, // bottom-left corner
    br: u21, // bottom-right corner
    h: u21, // horizontal line
    v: u21, // vertical line
};

fn borderCharsFor(border: SubgraphBorder) BorderChars {
    return switch (border) {
        .single => .{ .tl = j.CP_CORNER_UR, .tr = j.CP_CORNER_UL, .bl = j.CP_CORNER_DR, .br = j.CP_CORNER_DL, .h = j.CP_H_LINE, .v = j.CP_V_LINE },
        .double => .{ .tl = j.CP_DB_CORNER_UR, .tr = j.CP_DB_CORNER_UL, .bl = j.CP_DB_CORNER_DR, .br = j.CP_DB_CORNER_DL, .h = j.CP_DB_H_LINE, .v = j.CP_DB_V_LINE },
        .heavy => .{ .tl = j.CP_HV_CORNER_UR, .tr = j.CP_HV_CORNER_UL, .bl = j.CP_HV_CORNER_DR, .br = j.CP_HV_CORNER_DL, .h = j.CP_HV_H_LINE, .v = j.CP_HV_V_LINE },
        .dashed => .{ .tl = j.CP_CORNER_UR, .tr = j.CP_CORNER_UL, .bl = j.CP_CORNER_DR, .br = j.CP_CORNER_DL, .h = j.CP_H_LINE_DASH, .v = j.CP_V_LINE_DASH },
        // Defensive: paintSubgraphBox early-returns for .none, so this arm
        // is unreachable in normal use. Spaces prevent painting garbage if
        // borderCharsFor is ever called directly.
        .none => .{ .tl = ' ', .tr = ' ', .bl = ' ', .br = ' ', .h = ' ', .v = ' ' },
    };
}

/// Draw a single subgraph box with the given border style and color.
pub fn paintSubgraphBox(buffer: *Buffer2D, x: usize, y: usize, w: usize, h: usize, style: TerminalSubgraphStyle) void {
    if (w < 2 or h < 2) return;
    if (style.border == .none) return;

    const bc = borderCharsFor(style.border);
    const color = config_mod.resolveColor(style.color);

    const right = x + w - 1;
    const bottom = y + h - 1;

    // Corners
    setCell(buffer, x, y, bc.tl, color);
    setCell(buffer, right, y, bc.tr, color);
    setCell(buffer, x, bottom, bc.bl, color);
    setCell(buffer, right, bottom, bc.br, color);

    // Top and bottom horizontal lines
    var col = x + 1;
    while (col < right) : (col += 1) {
        setCell(buffer, col, y, bc.h, color);
        setCell(buffer, col, bottom, bc.h, color);
    }

    // Left and right vertical lines
    var row = y + 1;
    while (row < bottom) : (row += 1) {
        setCell(buffer, x, row, bc.v, color);
        setCell(buffer, right, row, bc.v, color);
    }
}

/// Paint a subgraph label at the position determined by `style.label_pos`.
pub fn paintSubgraphLabel(buffer: *Buffer2D, x: usize, y: usize, w: usize, h: usize, label: []const u8, style: TerminalSubgraphStyle) void {
    if (label.len == 0) return;
    if (w < 4 or h < 2) return;

    const color = config_mod.resolveColor(style.color);
    const has_attrs = @as(u8, @bitCast(style.attrs)) != 0;

    switch (style.label_pos) {
        .top_left => {
            // Label overwrites top border starting at x+2
            const max_len = w -| 4;
            const display_len = @min(label.len, max_len);
            if (display_len == 0) return;
            const start = x + 2;
            for (label[0..display_len], 0..) |ch, i| {
                setCell(buffer, start + i, y, @as(u21, ch), color);
                if (has_attrs) buffer.setAttrs(start + i, y, style.attrs);
            }
        },
        .top_center => {
            // Label centered on top border
            const max_len = w -| 4;
            const display_len = @min(label.len, max_len);
            if (display_len == 0) return;
            const start = x + 2 + (max_len - display_len) / 2;
            for (label[0..display_len], 0..) |ch, i| {
                setCell(buffer, start + i, y, @as(u21, ch), color);
                if (has_attrs) buffer.setAttrs(start + i, y, style.attrs);
            }
        },
        .inside => {
            // Label one row below top border (legacy behavior)
            if (h < 3) return;
            const max_len = w -| 4;
            const display_len = @min(label.len, max_len);
            if (display_len == 0) return;
            const start = x + 2;
            for (label[0..display_len], 0..) |ch, i| {
                setCell(buffer, start + i, y + 1, @as(u21, ch), color);
                if (has_attrs) buffer.setAttrs(start + i, y + 1, style.attrs);
            }
        },
    }
}

inline fn setCell(buffer: *Buffer2D, x: usize, y: usize, ch: u21, color: CellColor) void {
    buffer.setWithColor(x, y, ch, color);
}
