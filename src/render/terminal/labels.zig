//! Edge label painting and legend support for the terminal renderer.

const Buffer2D = @import("buffer.zig").Buffer2D;
const CellColor = @import("config.zig").CellColor;
const j = @import("junctions.zig");

/// Entry for the legend (labels that couldn't be placed inline).
pub const LegendEntry = struct {
    from_id: usize,
    to_id: usize,
    label: []const u8,
    color: CellColor,
};

/// Check whether a label can be placed without overlapping anything except spaces and vertical lines.
pub fn canPlaceLabel(buffer: *const Buffer2D, label: []const u8, x: usize, y: usize) bool {
    if (y >= buffer.height) return false;
    const label_width = label.len + 2; // +2 for surrounding quotes
    if (x + label_width > buffer.width) return false;
    for (0..label_width) |i| {
        const c = buffer.get(x + i, y);
        // Allow overwriting spaces and vertical lines (including dashed)
        if (c != ' ' and c != j.CP_V_LINE and c != j.CP_V_LINE_DASH) return false;
    }
    return true;
}

/// Paint a label as `"text"` at the given position with optional color.
pub fn paintLabel(buffer: *Buffer2D, label: []const u8, x: usize, y: usize, color: CellColor) void {
    var px = x;
    buffer.setWithColor(px, y, '"', color);
    px += 1;
    for (label) |ch| {
        buffer.setWithColor(px, y, ch, color);
        px += 1;
    }
    buffer.setWithColor(px, y, '"', color);
}
