//! Node painting for the terminal renderer.

const ir_mod = @import("../../core/ir.zig");
const LayoutNode = ir_mod.LayoutNode(usize);
const Buffer2D = @import("buffer.zig").Buffer2D;
const config_mod = @import("config.zig");
const TerminalNodeStyle = config_mod.TerminalNodeStyle;
const CellColor = config_mod.CellColor;
const Color = config_mod.Color;
const TextAttrs = config_mod.TextAttrs;
const resolveColorAt = config_mod.resolveColorAt;

/// Box-drawing character set for a 3-row node border.
const BoxChars = struct {
    tl: u21, // top-left corner
    tr: u21, // top-right corner (0 = omit for open variants)
    bl: u21, // bottom-left corner (0 = omit for open variants)
    br: u21, // bottom-right corner
    h: u21, // horizontal line
    v: u21, // vertical line
};

fn boxCharsFor(border: config_mod.NodeBorder) BoxChars {
    return switch (border) {
        // Closed variants (all four corners)
        .single_box => .{ .tl = '┌', .tr = '┐', .bl = '└', .br = '┘', .h = '─', .v = '│' },
        .heavy_box => .{ .tl = '┏', .tr = '┓', .bl = '┗', .br = '┛', .h = '━', .v = '┃' },
        .double_box => .{ .tl = '╔', .tr = '╗', .bl = '╚', .br = '╝', .h = '═', .v = '║' },
        .rounded_box => .{ .tl = '╭', .tr = '╮', .bl = '╰', .br = '╯', .h = '─', .v = '│' },
        // Open variants (TL + BR only — implicit feel)
        .open_single => .{ .tl = '┌', .tr = 0, .bl = 0, .br = '┘', .h = '─', .v = '│' },
        .open_heavy => .{ .tl = '┏', .tr = 0, .bl = 0, .br = '┛', .h = '━', .v = '┃' },
        .open_double => .{ .tl = '╔', .tr = 0, .bl = 0, .br = '╝', .h = '═', .v = '║' },
        .open_rounded => .{ .tl = '╭', .tr = 0, .bl = 0, .br = '╯', .h = '─', .v = '│' },
        else => unreachable,
    };
}

/// Paint a node onto the buffer at `rendered_y`.
///
/// For 1-row borders, `rendered_y` is the single row.
/// For 3-row borders, `rendered_y` is the top border row; the label is at
/// `rendered_y + 1` and the bottom border at `rendered_y + 2`.
///
/// `level_height` is the maximum rendered height of this node's level
/// (e.g. 3 when the level contains 3-row boxes). Dummy nodes use this
/// to draw vertical connectors through the whole band.
///
/// Dummy nodes bypass the style system — they're layout artifacts.
pub fn paintNode(buffer: *Buffer2D, node: *const LayoutNode, show_dummy_nodes: bool, style: TerminalNodeStyle, rendered_y: usize, level_height: usize) void {
    var x = node.x;

    // Dummy nodes: show as '◍' if debugging, skip if not
    if (node.kind == .dummy) {
        if (show_dummy_nodes) {
            const mid = rendered_y + level_height / 2;
            // Vertical connector above label
            var dy: usize = rendered_y;
            while (dy < mid) : (dy += 1) {
                buffer.set(node.center_x, dy, '│');
            }
            // Label at the middle of the level band
            var lx = node.x;
            for (node.label) |c| {
                buffer.set(lx, mid, c);
                lx += 1;
            }
            // Vertical connector below label
            dy = mid + 1;
            while (dy < rendered_y + level_height) : (dy += 1) {
                buffer.set(node.center_x, dy, '│');
            }
        }
        return;
    }

    const w = node.width;
    const w_f: f32 = @floatFromInt(if (w > 1) w - 1 else 1);

    // For 1-row nodes in a multi-row level band, center vertically
    // and draw vertical connectors through the extra rows.
    const node_h = style.border.height();
    const actual_y = if (node_h == 1 and level_height > 1)
        rendered_y + level_height / 2
    else
        rendered_y;

    if (node_h == 1 and level_height > 1) {
        // Vertical connector above the centered 1-row node
        var dy: usize = rendered_y;
        while (dy < actual_y) : (dy += 1) {
            buffer.set(node.center_x, dy, '│');
        }
        // Vertical connector below the centered 1-row node
        dy = actual_y + 1;
        while (dy < rendered_y + level_height) : (dy += 1) {
            buffer.set(node.center_x, dy, '│');
        }
    }

    switch (style.border) {
        // ── 1-row variants ──────────────────────────────────────────────
        .bracket => {
            emitCell(buffer, x, actual_y, '[', style.border_color, style.bg_color, 0, .{});
            x += 1;
            for (node.label) |c| {
                const t: f32 = @as(f32, @floatFromInt(x - node.x)) / w_f;
                emitCell(buffer, x, actual_y, c, style.text_color, style.bg_color, t, style.attrs);
                x += 1;
            }
            emitCell(buffer, x, actual_y, ']', style.border_color, style.bg_color, 1.0, .{});
        },
        .angle => {
            emitCell(buffer, x, actual_y, '<', style.border_color, style.bg_color, 0, .{});
            x += 1;
            for (node.label) |c| {
                const t: f32 = @as(f32, @floatFromInt(x - node.x)) / w_f;
                emitCell(buffer, x, actual_y, c, style.text_color, style.bg_color, t, style.attrs);
                x += 1;
            }
            emitCell(buffer, x, actual_y, '>', style.border_color, style.bg_color, 1.0, .{});
        },
        .none => {
            for (node.label) |c| {
                const t: f32 = if (node.label.len > 1)
                    @as(f32, @floatFromInt(x - node.x)) / @as(f32, @floatFromInt(node.label.len - 1))
                else
                    0.5;
                emitCell(buffer, x, actual_y, c, style.text_color, style.bg_color, t, style.attrs);
                x += 1;
            }
        },

        // ── 3-row variants ──────────────────────────────────────────────
        .single_box,
        .heavy_box,
        .double_box,
        .rounded_box,
        .open_single,
        .open_heavy,
        .open_double,
        .open_rounded,
        => {
            const bc = boxCharsFor(style.border);

            // Top border row (rendered_y)
            emitCell(buffer, x, rendered_y, bc.tl, style.border_color, style.bg_color, 0, .{});
            var col: usize = 1;
            while (col < w - 1) : (col += 1) {
                const t: f32 = @as(f32, @floatFromInt(col)) / w_f;
                emitCell(buffer, x + col, rendered_y, bc.h, style.border_color, style.bg_color, t, .{});
            }
            if (bc.tr != 0) {
                emitCell(buffer, x + w - 1, rendered_y, bc.tr, style.border_color, style.bg_color, 1.0, .{});
            }

            // Label row (rendered_y + 1)
            const label_y = rendered_y + 1;
            emitCell(buffer, x, label_y, bc.v, style.border_color, style.bg_color, 0, .{});

            var lx = x + 1;
            const inner_w = if (w >= 2) w - 2 else 0;
            const pad = if (inner_w > node.label.len) (inner_w - node.label.len) / 2 else 0;
            var fill: usize = 0;
            while (fill < pad) : (fill += 1) {
                const t: f32 = @as(f32, @floatFromInt(lx - x)) / w_f;
                emitCell(buffer, lx, label_y, ' ', style.text_color, style.bg_color, t, .{});
                lx += 1;
            }
            for (node.label) |c| {
                const t: f32 = @as(f32, @floatFromInt(lx - x)) / w_f;
                emitCell(buffer, lx, label_y, c, style.text_color, style.bg_color, t, style.attrs);
                lx += 1;
            }
            while (lx < x + w - 1) : (lx += 1) {
                const t: f32 = @as(f32, @floatFromInt(lx - x)) / w_f;
                emitCell(buffer, lx, label_y, ' ', style.text_color, style.bg_color, t, .{});
            }
            emitCell(buffer, x + w - 1, label_y, bc.v, style.border_color, style.bg_color, 1.0, .{});

            // Bottom border row (rendered_y + 2)
            const bottom_y = rendered_y + 2;
            if (bc.bl != 0) {
                emitCell(buffer, x, bottom_y, bc.bl, style.border_color, style.bg_color, 0, .{});
            }
            col = 1;
            while (col < w - 1) : (col += 1) {
                const t: f32 = @as(f32, @floatFromInt(col)) / w_f;
                emitCell(buffer, x + col, bottom_y, bc.h, style.border_color, style.bg_color, t, .{});
            }
            emitCell(buffer, x + w - 1, bottom_y, bc.br, style.border_color, style.bg_color, 1.0, .{});
        },
    }
}

/// Emit a single cell with foreground + optional background color + optional text attrs.
/// `t` is the horizontal position within the node (0.0–1.0) for gradient sampling.
inline fn emitCell(buffer: *Buffer2D, x: usize, y: usize, ch: u21, fg_color: Color, bg_color: Color, t: f32, text_attrs: TextAttrs) void {
    const fg = resolveColorAt(fg_color, t);
    if (fg.isSet()) {
        buffer.setWithColor(x, y, ch, fg);
    } else {
        buffer.set(x, y, ch);
    }
    const bg = resolveColorAt(bg_color, t);
    if (bg.isSet()) {
        buffer.setBgColor(x, y, bg);
    }
    if (@as(u8, @bitCast(text_attrs)) != 0) {
        buffer.setAttrs(x, y, text_attrs);
    }
}
