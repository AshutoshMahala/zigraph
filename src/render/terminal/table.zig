//! Standalone table renderer for terminal output.
//!
//! Renders structured tabular data to text using Unicode box-drawing glyphs
//! or ASCII fallback. Supports optional headers, four border styles, and
//! per-column alignment.
//!
//! ## Example
//!
//! ```zig
//! const result = try table.render(
//!     &.{ "Name", "Age" },
//!     &.{ &.{ "Alice", "30" }, &.{ "Bob", "25" } },
//!     allocator,
//!     .{},
//! );
//! defer allocator.free(result);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Public types ─────────────────────────────────────────────────────────────

/// Per-column text alignment.
pub const Alignment = enum { left, center, right };

/// Table border style.
pub const Border = enum { none, single, heavy, double };

/// Configuration for table rendering.
pub const TableConfig = struct {
    border: Border = .single,
    char_set: CharSet = .unicode,
    header_attrs: TextAttrs = .{ .bold = true },
    alignment: ?[]const Alignment = null,

    pub const CharSet = enum { unicode, ascii };
    pub const TextAttrs = packed struct {
        bold: bool = false,
        dim: bool = false,
        italic: bool = false,
        underline: bool = false,
        _pad: u4 = 0,
    };
};

// ── Border character sets ────────────────────────────────────────────────────

/// Box-drawing characters for a given border style.
/// Layout: top_left, top_fill, top_sep, top_right,
///         side, mid_left, mid_fill, mid_sep, mid_right,
///         bot_left, bot_fill, bot_sep, bot_right
const BorderChars = struct {
    tl: []const u8, // top-left corner
    th: []const u8, // top horizontal fill
    tt: []const u8, // top T-junction (down)
    tr: []const u8, // top-right corner
    vl: []const u8, // vertical left border
    vc: []const u8, // vertical column separator
    vr: []const u8, // vertical right border
    ml: []const u8, // mid-row left corner
    mh: []const u8, // mid-row horizontal fill
    mt: []const u8, // mid-row cross / T-junction
    mr: []const u8, // mid-row right corner
    bl: []const u8, // bottom-left corner
    bh: []const u8, // bottom horizontal fill
    bt: []const u8, // bottom T-junction (up)
    br: []const u8, // bottom-right corner
};

const SINGLE: BorderChars = .{
    .tl = "┌", .th = "─", .tt = "┬", .tr = "┐",
    .vl = "│", .vc = "│", .vr = "│",
    .ml = "├", .mh = "─", .mt = "┼", .mr = "┤",
    .bl = "└", .bh = "─", .bt = "┴", .br = "┘",
};

const HEAVY: BorderChars = .{
    .tl = "┏", .th = "━", .tt = "┳", .tr = "┓",
    .vl = "┃", .vc = "┃", .vr = "┃",
    .ml = "┣", .mh = "━", .mt = "╋", .mr = "┫",
    .bl = "┗", .bh = "━", .bt = "┻", .br = "┛",
};

const DOUBLE: BorderChars = .{
    .tl = "╔", .th = "═", .tt = "╦", .tr = "╗",
    .vl = "║", .vc = "║", .vr = "║",
    .ml = "╠", .mh = "═", .mt = "╬", .mr = "╣",
    .bl = "╚", .bh = "═", .bt = "╩", .br = "╝",
};

const ASCII: BorderChars = .{
    .tl = "+", .th = "-", .tt = "+", .tr = "+",
    .vl = "|", .vc = "|", .vr = "|",
    .ml = "+", .mh = "-", .mt = "+", .mr = "+",
    .bl = "+", .bh = "-", .bt = "+", .br = "+",
};

fn borderChars(config: TableConfig) BorderChars {
    if (config.char_set == .ascii) return ASCII;
    return switch (config.border) {
        .none => ASCII, // won't be used for bordered output
        .single => SINGLE,
        .heavy => HEAVY,
        .double => DOUBLE,
    };
}

// ── Max columns ──────────────────────────────────────────────────────────────

const MAX_COLS: usize = 64;

// ── Public API ───────────────────────────────────────────────────────────────

/// Render a table to an allocated string. Caller owns the returned slice.
pub fn render(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    allocator: Allocator,
    config: TableConfig,
) ![]u8 {
    var list: std.ArrayListUnmanaged(u8) = .{};
    errdefer list.deinit(allocator);
    try renderStreaming(headers, rows, list.writer(allocator), config);
    return try list.toOwnedSlice(allocator);
}

/// Render a table directly to a writer (zero heap allocation for writing).
pub fn renderStreaming(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
    config: TableConfig,
) !void {
    // Determine column count from headers or first row.
    const num_cols: usize = blk: {
        if (headers) |h| break :blk h.len;
        if (rows.len > 0) break :blk rows[0].len;
        return; // nothing to render
    };

    if (num_cols == 0) return;
    const ncols = @min(num_cols, MAX_COLS);

    // ── Compute per-column widths ────────────────────────────────────────
    var col_widths: [MAX_COLS]usize = [_]usize{0} ** MAX_COLS;

    if (headers) |h| {
        for (0..ncols) |c| {
            col_widths[c] = @max(col_widths[c], h[c].len);
        }
    }
    for (rows) |row| {
        const row_cols = @min(row.len, ncols);
        for (0..row_cols) |c| {
            col_widths[c] = @max(col_widths[c], row[c].len);
        }
    }

    // ── Dispatch to bordered or borderless renderer ──────────────────────
    if (config.border == .none) {
        try renderBorderless(headers, rows, writer, config, col_widths[0..ncols]);
    } else {
        try renderBordered(headers, rows, writer, config, col_widths[0..ncols]);
    }
}

// ── Borderless rendering ─────────────────────────────────────────────────────

fn renderBorderless(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
    config: TableConfig,
    col_widths: []const usize,
) !void {
    if (headers) |h| {
        try writeRow(h, writer, config, col_widths, false);
    }
    for (rows) |row| {
        try writeRow(row, writer, config, col_widths, false);
    }
}

/// Write one data row, padding each cell to its column width.
/// `bordered`: when true, wrap cells with `│` separators; when false, use 2-space gap.
fn writeRow(
    row: []const []const u8,
    writer: anytype,
    config: TableConfig,
    col_widths: []const usize,
    bordered: bool,
) !void {
    const bc = borderChars(config);
    const ncols = col_widths.len;

    if (bordered) try writer.writeAll(bc.vl);

    for (0..ncols) |c| {
        const cell = if (c < row.len) row[c] else "";
        const width = col_widths[c];
        const align_ = if (config.alignment) |a| (if (c < a.len) a[c] else .left) else .left;

        if (bordered) {
            try writer.writeByte(' ');
            try writePadded(writer, cell, width, align_);
            try writer.writeByte(' ');
            if (c + 1 < ncols) {
                try writer.writeAll(bc.vc);
            } else {
                try writer.writeAll(bc.vr);
            }
        } else {
            // Borderless: pad to width, then 2-space gap (except after last column)
            try writePadded(writer, cell, width, align_);
            if (c + 1 < ncols) try writer.writeAll("  ");
        }
    }
    try writer.writeByte('\n');
}

/// Write a cell value padded to `width` characters using the given alignment.
fn writePadded(writer: anytype, cell: []const u8, width: usize, align_: Alignment) !void {
    const len = cell.len;
    if (len >= width) {
        try writer.writeAll(cell);
        return;
    }
    const pad = width - len;
    switch (align_) {
        .left => {
            try writer.writeAll(cell);
            try writeSpaces(writer, pad);
        },
        .right => {
            try writeSpaces(writer, pad);
            try writer.writeAll(cell);
        },
        .center => {
            const left_pad = pad / 2;
            const right_pad = pad - left_pad;
            try writeSpaces(writer, left_pad);
            try writer.writeAll(cell);
            try writeSpaces(writer, right_pad);
        },
    }
}

fn writeSpaces(writer: anytype, n: usize) !void {
    const spaces = "                                                                ";
    var remaining = n;
    while (remaining > 0) {
        const chunk = @min(remaining, spaces.len);
        try writer.writeAll(spaces[0..chunk]);
        remaining -= chunk;
    }
}

// ── Bordered rendering ───────────────────────────────────────────────────────

fn renderBordered(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
    config: TableConfig,
    col_widths: []const usize,
) !void {
    const bc = borderChars(config);

    // Top border
    try writeHorizontalRule(writer, bc.tl, bc.th, bc.tt, bc.tr, col_widths);

    if (headers) |h| {
        // Header row
        try writeRow(h, writer, config, col_widths, true);
        // Header separator
        try writeHorizontalRule(writer, bc.ml, bc.mh, bc.mt, bc.mr, col_widths);
    }

    // Data rows with separators between them
    for (rows, 0..) |row, i| {
        try writeRow(row, writer, config, col_widths, true);
        if (i + 1 < rows.len) {
            try writeHorizontalRule(writer, bc.ml, bc.mh, bc.mt, bc.mr, col_widths);
        }
    }

    // Bottom border
    try writeHorizontalRule(writer, bc.bl, bc.bh, bc.bt, bc.br, col_widths);
}

/// Write a horizontal rule line: left_corner [fill*(width+2) sep]... right_corner
fn writeHorizontalRule(
    writer: anytype,
    left: []const u8,
    fill: []const u8,
    sep: []const u8,
    right: []const u8,
    col_widths: []const usize,
) !void {
    try writer.writeAll(left);
    for (col_widths, 0..) |width, c| {
        // fill width+2 (one space padding on each side)
        var i: usize = 0;
        while (i < width + 2) : (i += 1) {
            try writer.writeAll(fill);
        }
        if (c + 1 < col_widths.len) {
            try writer.writeAll(sep);
        }
    }
    try writer.writeAll(right);
    try writer.writeByte('\n');
}
