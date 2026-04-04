//! Card node rendering — multi-line box nodes with header, separator, and content lines.

const std = @import("std");
const buffer_mod = @import("buffer.zig");
const Buffer2D = buffer_mod.Buffer2D;
const config_mod = @import("config.zig");
const Color = config_mod.Color;
const CellColor = config_mod.CellColor;
const TextAttrs = config_mod.TextAttrs;
const NodeBorder = config_mod.NodeBorder;
const CardStyle = config_mod.CardStyle;
const resolveColorAt = config_mod.resolveColorAt;

pub fn cardWidth(header: []const u8, lines: []const []const u8) usize {
    var max_len = header.len;
    for (lines) |line| {
        if (line.len > max_len) max_len = line.len;
    }
    return max_len + 2;
}

pub fn cardHeight(lines_count: usize) usize {
    return lines_count + 4;
}

pub fn paintCard(
    buffer: *Buffer2D,
    x: usize,
    y: usize,
    width: usize,
    header: []const u8,
    lines: []const []const u8,
    style: CardStyle,
) void {
    if (width < 2) return;
    const inner_w = width - 2;
    const bc = boxCharsFor(style.border);
    const border_cc = resolveColorAt(style.border_color, 0.0);
    const header_cc = resolveColorAt(style.header_color, 0.0);
    const content_cc = resolveColorAt(style.content_color, 0.0);

    buffer.setWithColor(x, y, bc.tl, border_cc);
    for (1..width - 1) |col| {
        buffer.setWithColor(x + col, y, bc.h, border_cc);
    }
    buffer.setWithColor(x + width - 1, y, bc.tr, border_cc);

    buffer.setWithColor(x, y + 1, bc.v, border_cc);
    const pad = if (inner_w > header.len) (inner_w - header.len) / 2 else 0;
    for (0..inner_w) |col| {
        const idx = if (col >= pad and col < pad + header.len) col - pad else inner_w;
        if (idx < header.len) {
            buffer.setWithColor(x + 1 + col, y + 1, header[idx], header_cc);
            if (@as(u8, @bitCast(style.header_attrs)) != 0) {
                buffer.setAttrs(x + 1 + col, y + 1, style.header_attrs);
            }
        } else {
            buffer.set(x + 1 + col, y + 1, ' ');
        }
    }
    buffer.setWithColor(x + width - 1, y + 1, bc.v, border_cc);

    buffer.setWithColor(x, y + 2, 0x251C, border_cc);
    for (1..width - 1) |col| {
        buffer.setWithColor(x + col, y + 2, bc.h, border_cc);
    }
    buffer.setWithColor(x + width - 1, y + 2, 0x2524, border_cc);

    for (lines, 0..) |line, li| {
        const fy = y + 3 + li;
        buffer.setWithColor(x, fy, bc.v, border_cc);
        var lx: usize = 0;
        while (lx < inner_w) : (lx += 1) {
            if (lx < line.len) {
                buffer.setWithColor(x + 1 + lx, fy, line[lx], content_cc);
            } else {
                buffer.set(x + 1 + lx, fy, ' ');
            }
        }
        buffer.setWithColor(x + width - 1, fy, bc.v, border_cc);
    }

    const bottom_y = y + 3 + lines.len;
    buffer.setWithColor(x, bottom_y, bc.bl, border_cc);
    for (1..width - 1) |col| {
        buffer.setWithColor(x + col, bottom_y, bc.h, border_cc);
    }
    buffer.setWithColor(x + width - 1, bottom_y, bc.br, border_cc);
}

const BoxChars = struct { tl: u21, tr: u21, bl: u21, br: u21, h: u21, v: u21 };

fn boxCharsFor(border: NodeBorder) BoxChars {
    return switch (border) {
        .single_box, .open_single => .{ .tl = 0x250C, .tr = 0x2510, .bl = 0x2514, .br = 0x2518, .h = 0x2500, .v = 0x2502 },
        .heavy_box, .open_heavy => .{ .tl = 0x250F, .tr = 0x2513, .bl = 0x2517, .br = 0x251B, .h = 0x2501, .v = 0x2503 },
        .double_box, .open_double => .{ .tl = 0x2554, .tr = 0x2557, .bl = 0x255A, .br = 0x255D, .h = 0x2550, .v = 0x2551 },
        .rounded_box, .open_rounded => .{ .tl = 0x256D, .tr = 0x256E, .bl = 0x2570, .br = 0x256F, .h = 0x2500, .v = 0x2502 },
        else => .{ .tl = 0x250C, .tr = 0x2510, .bl = 0x2514, .br = 0x2518, .h = 0x2500, .v = 0x2502 },
    };
}
