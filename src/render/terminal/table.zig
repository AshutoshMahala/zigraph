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
const Buffer2D = @import("buffer.zig").Buffer2D;

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
        if (config.header_attrs.bold) try writer.writeAll("\x1b[1m");
        try writeRow(h, writer, config, col_widths, false);
        if (config.header_attrs.bold) try writer.writeAll("\x1b[0m");
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
        // Header row – apply header_attrs (bold, etc.) around the row
        if (config.header_attrs.bold) try writer.writeAll("\x1b[1m");
        try writeRow(h, writer, config, col_widths, true);
        if (config.header_attrs.bold) try writer.writeAll("\x1b[0m");
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

// ── Dimension helpers ─────────────────────────────────────────────────────────

/// Compute the rendered width (in terminal columns) of a bordered or borderless table.
///
/// For bordered tables: `(num_cols + 1) + sum(col_width + 2)` — one border/separator
/// per column plus the final right border, with one space of padding on each side.
///
/// For borderless tables: `sum(col_widths) + 2 * (num_cols - 1)` — columns joined
/// by two-space gaps.
pub fn tableWidth(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
) usize {
    const num_cols: usize = blk: {
        if (headers) |h| break :blk h.len;
        if (rows.len > 0) break :blk rows[0].len;
        return 0;
    };
    if (num_cols == 0) return 0;
    const ncols = @min(num_cols, MAX_COLS);

    var col_widths: [MAX_COLS]usize = [_]usize{0} ** MAX_COLS;
    if (headers) |h| {
        for (0..ncols) |c| col_widths[c] = @max(col_widths[c], h[c].len);
    }
    for (rows) |row| {
        const rc = @min(row.len, ncols);
        for (0..rc) |c| col_widths[c] = @max(col_widths[c], row[c].len);
    }

    if (config.border == .none) {
        // sum of col widths + 2-space gaps between columns
        var w: usize = 0;
        for (0..ncols) |c| w += col_widths[c];
        w += 2 * (ncols - 1);
        return w;
    } else {
        // (num_cols + 1) border chars + sum(col_width + 2) padded content
        var w: usize = ncols + 1;
        for (0..ncols) |c| w += col_widths[c] + 2;
        return w;
    }
}

/// Compute the rendered height (in terminal rows) of a bordered or borderless table.
///
/// For bordered tables:
///   - With headers: `top + header + header_sep + data_rows + row_seps + bottom`
///     = 4 + rows.len + max(0, rows.len - 1)
///   - Without headers (rows > 0): `top + data_rows + row_seps + bottom`
///     = 2 + rows.len + (rows.len - 1) = rows.len * 2 + 1
///   - No headers and no rows: 0 (nothing rendered)
///
/// For borderless tables: `(1 if headers present) + rows.len`.
pub fn tableHeight(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
) usize {
    // Determine whether there is any column count to render
    const has_cols: bool = blk: {
        if (headers) |h| break :blk h.len > 0;
        if (rows.len > 0) break :blk rows[0].len > 0;
        break :blk false;
    };
    if (!has_cols) return 0;

    if (config.border == .none) {
        const header_rows: usize = if (headers != null) 1 else 0;
        return header_rows + rows.len;
    }

    // Bordered
    if (headers != null) {
        // top + header + header_sep + data + seps + bottom
        if (rows.len == 0) return 4; // top + hdr + hdr_sep + bottom
        return 4 + rows.len + (rows.len - 1);
    } else {
        if (rows.len == 0) return 0;
        // top + rows + row_seps + bottom
        return 2 + rows.len + (rows.len - 1);
    }
}

/// Paint a table into a Buffer2D at offset (ox, oy).
///
/// Writes the same content as `renderBordered` / `renderBorderless` but places
/// individual codepoints into the buffer rather than serialising to a writer.
/// The caller is responsible for allocating a buffer large enough:
/// width >= ox + tableWidth(...) and height >= oy + tableHeight(...).
pub fn paintTable(
    buffer: *Buffer2D,
    ox: usize,
    oy: usize,
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
) void {
    const num_cols: usize = blk: {
        if (headers) |h| break :blk h.len;
        if (rows.len > 0) break :blk rows[0].len;
        return;
    };
    if (num_cols == 0) return;
    const ncols = @min(num_cols, MAX_COLS);

    var col_widths: [MAX_COLS]usize = [_]usize{0} ** MAX_COLS;
    if (headers) |h| {
        for (0..ncols) |c| col_widths[c] = @max(col_widths[c], h[c].len);
    }
    for (rows) |row| {
        const rc = @min(row.len, ncols);
        for (0..rc) |c| col_widths[c] = @max(col_widths[c], row[c].len);
    }

    if (config.border == .none) {
        paintBorderlessIntoBuffer(buffer, ox, oy, headers, rows, config, col_widths[0..ncols]);
    } else {
        paintBorderedIntoBuffer(buffer, ox, oy, headers, rows, config, col_widths[0..ncols]);
    }
}

/// Decode the first UTF-8 codepoint from a non-empty string slice.
/// Returns a space on empty input or decode error.
fn firstCodepoint(s: []const u8) u21 {
    if (s.len == 0) return ' ';
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return ' ';
    if (len > s.len) return ' ';
    return std.unicode.utf8Decode(s[0..len]) catch ' ';
}

fn paintHorizontalRuleIntoBuffer(
    buffer: *Buffer2D,
    x: *usize,
    y: usize,
    left: []const u8,
    fill: []const u8,
    sep: []const u8,
    right: []const u8,
    col_widths: []const usize,
) void {
    buffer.set(x.*, y, firstCodepoint(left));
    x.* += 1;
    for (col_widths, 0..) |width, c| {
        const fill_cp = firstCodepoint(fill);
        var i: usize = 0;
        while (i < width + 2) : (i += 1) {
            buffer.set(x.*, y, fill_cp);
            x.* += 1;
        }
        if (c + 1 < col_widths.len) {
            buffer.set(x.*, y, firstCodepoint(sep));
        } else {
            buffer.set(x.*, y, firstCodepoint(right));
        }
        x.* += 1;
    }
}

fn paintDataRowIntoBuffer(
    buffer: *Buffer2D,
    ox: usize,
    y: usize,
    row: []const []const u8,
    config: TableConfig,
    col_widths: []const usize,
    bordered: bool,
) void {
    const bc = borderChars(config);
    const ncols = col_widths.len;
    var x = ox;

    if (bordered) {
        buffer.set(x, y, firstCodepoint(bc.vl));
        x += 1;
    }

    for (0..ncols) |c| {
        const cell = if (c < row.len) row[c] else "";
        const width = col_widths[c];
        const align_ = if (config.alignment) |a| (if (c < a.len) a[c] else .left) else .left;

        if (bordered) {
            buffer.set(x, y, ' ');
            x += 1;
            // Paint cell with alignment (iterate UTF-8 codepoints, not bytes)
            const cell_view = std.unicode.Utf8View.initUnchecked(cell);
            var cp_count: usize = 0;
            {
                var it = cell_view.iterator();
                while (it.nextCodepoint() != null) cp_count += 1;
            }
            const pad = if (cp_count < width) width - cp_count else 0;
            switch (align_) {
                .left => {
                    var it = cell_view.iterator();
                    while (it.nextCodepoint()) |cp| {
                        buffer.set(x, y, cp);
                        x += 1;
                    }
                    var sp: usize = 0;
                    while (sp < pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                },
                .right => {
                    var sp: usize = 0;
                    while (sp < pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                    var it = cell_view.iterator();
                    while (it.nextCodepoint()) |cp| {
                        buffer.set(x, y, cp);
                        x += 1;
                    }
                },
                .center => {
                    const left_pad = pad / 2;
                    const right_pad = pad - left_pad;
                    var sp: usize = 0;
                    while (sp < left_pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                    var it = cell_view.iterator();
                    while (it.nextCodepoint()) |cp| {
                        buffer.set(x, y, cp);
                        x += 1;
                    }
                    sp = 0;
                    while (sp < right_pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                },
            }
            buffer.set(x, y, ' ');
            x += 1;
            if (c + 1 < ncols) {
                buffer.set(x, y, firstCodepoint(bc.vc));
            } else {
                buffer.set(x, y, firstCodepoint(bc.vr));
            }
            x += 1;
        } else {
            // Borderless: apply alignment the same way as the bordered branch
            const cell_view = std.unicode.Utf8View.initUnchecked(cell);
            var cp_count: usize = 0;
            {
                var it = cell_view.iterator();
                while (it.nextCodepoint() != null) cp_count += 1;
            }
            const pad = if (cp_count < width) width - cp_count else 0;
            switch (align_) {
                .left => {
                    var it = cell_view.iterator();
                    while (it.nextCodepoint()) |cp| {
                        buffer.set(x, y, cp);
                        x += 1;
                    }
                    var sp: usize = 0;
                    while (sp < pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                },
                .right => {
                    var sp: usize = 0;
                    while (sp < pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                    var it = cell_view.iterator();
                    while (it.nextCodepoint()) |cp| {
                        buffer.set(x, y, cp);
                        x += 1;
                    }
                },
                .center => {
                    const left_pad = pad / 2;
                    const right_pad = pad - left_pad;
                    var sp: usize = 0;
                    while (sp < left_pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                    var it = cell_view.iterator();
                    while (it.nextCodepoint()) |cp| {
                        buffer.set(x, y, cp);
                        x += 1;
                    }
                    sp = 0;
                    while (sp < right_pad) : (sp += 1) {
                        buffer.set(x, y, ' ');
                        x += 1;
                    }
                },
            }
            if (c + 1 < ncols) {
                buffer.set(x, y, ' ');
                x += 1;
                buffer.set(x, y, ' ');
                x += 1;
            }
        }
    }
}

fn paintBorderedIntoBuffer(
    buffer: *Buffer2D,
    ox: usize,
    oy: usize,
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
    col_widths: []const usize,
) void {
    const bc = borderChars(config);
    var y = oy;

    // Top border
    var x = ox;
    paintHorizontalRuleIntoBuffer(buffer, &x, y, bc.tl, bc.th, bc.tt, bc.tr, col_widths);
    y += 1;

    if (headers) |h| {
        // NOTE: header_attrs (bold, etc.) are applied in the streaming/string
        // rendering path but not here — Buffer2D stores raw codepoints and does
        // not support ANSI text attributes.
        paintDataRowIntoBuffer(buffer, ox, y, h, config, col_widths, true);
        y += 1;
        x = ox;
        paintHorizontalRuleIntoBuffer(buffer, &x, y, bc.ml, bc.mh, bc.mt, bc.mr, col_widths);
        y += 1;
    }

    for (rows, 0..) |row, i| {
        paintDataRowIntoBuffer(buffer, ox, y, row, config, col_widths, true);
        y += 1;
        if (i + 1 < rows.len) {
            x = ox;
            paintHorizontalRuleIntoBuffer(buffer, &x, y, bc.ml, bc.mh, bc.mt, bc.mr, col_widths);
            y += 1;
        }
    }

    // Bottom border
    x = ox;
    paintHorizontalRuleIntoBuffer(buffer, &x, y, bc.bl, bc.bh, bc.bt, bc.br, col_widths);
}

fn paintBorderlessIntoBuffer(
    buffer: *Buffer2D,
    ox: usize,
    oy: usize,
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
    col_widths: []const usize,
) void {
    var y = oy;
    if (headers) |h| {
        paintDataRowIntoBuffer(buffer, ox, y, h, config, col_widths, false);
        y += 1;
    }
    for (rows) |row| {
        paintDataRowIntoBuffer(buffer, ox, y, row, config, col_widths, false);
        y += 1;
    }
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
