# Table Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone Unicode/ASCII table renderer to zigraph's terminal output with configurable borders, alignment, and optional headers.

**Architecture:** Single self-contained module (`table.zig`) following the `tree.zig` pattern — renders to allocated string or streaming writer, plus `paintTable` for Buffer2D graph integration. All types defined in-module (no config.zig changes needed).

**Tech Stack:** Zig, Unicode box-drawing characters, existing Buffer2D/CharSet/TextAttrs from the terminal renderer.

---

## File Structure

| File | Responsibility |
|------|----------------|
| Create: `src/render/terminal/table.zig` | All table types, rendering logic, paintTable, dimension helpers |
| Create: `src/render/terminal/table_tests.zig` | Unit tests for all table functionality |
| Modify: `src/render/terminal/mod.zig` | Add `pub const table = @import("table.zig");` |
| Create: `examples/terminal/table_demo.zig` | Example showing border styles, alignment, headers |
| Modify: `build.zig` | Register table_demo example |
| Modify: `README.md` | Add Table Renderer section |

---

### Task 1: Core types and single-row borderless render

**Files:**
- Create: `src/render/terminal/table.zig`
- Create: `src/render/terminal/table_tests.zig`

- [ ] **Step 1: Write the failing test**

In `src/render/terminal/table_tests.zig`:

```zig
const std = @import("std");
const table = @import("table.zig");

test "table: single row no headers borderless" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{ "hello", "world" },
    };
    const output = try table.render(null, rows, allocator, .{ .border = .none });
    defer allocator.free(output);
    try std.testing.expectEqualStrings("hello  world\n", output);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | tail -5`
Expected: FAIL — `table.zig` does not exist.

- [ ] **Step 3: Write minimal implementation**

In `src/render/terminal/table.zig`:

```zig
//! Standalone table renderer — formatted ASCII/Unicode tables.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Alignment = enum { left, center, right };

pub const Border = enum { none, single, heavy, double };

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

pub fn render(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    allocator: Allocator,
    config: TableConfig,
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    try renderStreaming(headers, rows, buf.writer(allocator), config);
    return buf.toOwnedSlice(allocator);
}

pub fn renderStreaming(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
    config: TableConfig,
) !void {
    const col_count = columnCount(headers, rows);
    if (col_count == 0) return;

    var col_widths_buf: [64]usize = undefined;
    const col_widths = col_widths_buf[0..col_count];
    computeColumnWidths(col_widths, headers, rows);

    if (config.border != .none) {
        const bc = borderChars(config.border, config.char_set);
        try writeHorizontalRule(writer, col_widths, bc.tl, bc.top_tee, bc.tr, bc.h);
        if (headers) |hdrs| {
            try writeDataRow(writer, hdrs, col_widths, bc.v, config.alignment);
            try writeHorizontalRule(writer, col_widths, bc.left_tee, bc.cross, bc.right_tee, bc.h);
        }
        for (rows, 0..) |row, i| {
            try writeDataRow(writer, row, col_widths, bc.v, config.alignment);
            if (i < rows.len - 1) {
                try writeHorizontalRule(writer, col_widths, bc.left_tee, bc.cross, bc.right_tee, bc.h);
            }
        }
        try writeHorizontalRule(writer, col_widths, bc.bl, bc.bottom_tee, bc.br, bc.h);
    } else {
        if (headers) |hdrs| {
            try writeBorderlessRow(writer, hdrs, col_widths, config.alignment);
        }
        for (rows) |row| {
            try writeBorderlessRow(writer, row, col_widths, config.alignment);
        }
    }
}

fn columnCount(headers: ?[]const []const u8, rows: []const []const []const u8) usize {
    if (headers) |h| return h.len;
    if (rows.len > 0) return rows[0].len;
    return 0;
}

fn computeColumnWidths(widths: []usize, headers: ?[]const []const u8, rows: []const []const []const u8) void {
    for (widths) |*w| w.* = 0;
    if (headers) |hdrs| {
        for (hdrs, 0..) |h, i| {
            if (i < widths.len and h.len > widths[i]) widths[i] = h.len;
        }
    }
    for (rows) |row| {
        for (row, 0..) |cell, i| {
            if (i < widths.len and cell.len > widths[i]) widths[i] = cell.len;
        }
    }
}

fn writeBorderlessRow(writer: anytype, cells: []const []const u8, widths: []const usize, alignment: ?[]const Alignment) !void {
    for (cells, 0..) |cell, i| {
        if (i > 0) try writer.writeAll("  ");
        try writeAligned(writer, cell, widths[i], getAlignment(alignment, i));
    }
    try writer.writeByte('\n');
}

fn writeDataRow(writer: anytype, cells: []const []const u8, widths: []const usize, v: u21, alignment: ?[]const Alignment) !void {
    var enc: [4]u8 = undefined;
    const vlen = std.unicode.utf8Encode(v, &enc) catch 1;
    for (widths, 0..) |w, i| {
        try writer.writeAll(enc[0..vlen]);
        try writer.writeByte(' ');
        const cell = if (i < cells.len) cells[i] else "";
        try writeAligned(writer, cell, w, getAlignment(alignment, i));
        try writer.writeByte(' ');
    }
    try writer.writeAll(enc[0..vlen]);
    try writer.writeByte('\n');
}

fn writeHorizontalRule(writer: anytype, widths: []const usize, left: u21, mid: u21, right: u21, h: u21) !void {
    var enc_l: [4]u8 = undefined;
    var enc_m: [4]u8 = undefined;
    var enc_r: [4]u8 = undefined;
    var enc_h: [4]u8 = undefined;
    const ll = std.unicode.utf8Encode(left, &enc_l) catch 1;
    const ml = std.unicode.utf8Encode(mid, &enc_m) catch 1;
    const rl = std.unicode.utf8Encode(right, &enc_r) catch 1;
    const hl = std.unicode.utf8Encode(h, &enc_h) catch 1;

    for (widths, 0..) |w, i| {
        if (i == 0) {
            try writer.writeAll(enc_l[0..ll]);
        } else {
            try writer.writeAll(enc_m[0..ml]);
        }
        for (0..w + 2) |_| try writer.writeAll(enc_h[0..hl]);
    }
    try writer.writeAll(enc_r[0..rl]);
    try writer.writeByte('\n');
}

fn writeAligned(writer: anytype, text: []const u8, width: usize, align_mode: Alignment) !void {
    const pad = if (width > text.len) width - text.len else 0;
    switch (align_mode) {
        .left => {
            try writer.writeAll(text);
            for (0..pad) |_| try writer.writeByte(' ');
        },
        .right => {
            for (0..pad) |_| try writer.writeByte(' ');
            try writer.writeAll(text);
        },
        .center => {
            const left_pad = pad / 2;
            const right_pad = pad - left_pad;
            for (0..left_pad) |_| try writer.writeByte(' ');
            try writer.writeAll(text);
            for (0..right_pad) |_| try writer.writeByte(' ');
        },
    }
}

fn getAlignment(alignment: ?[]const Alignment, col: usize) Alignment {
    if (alignment) |a| {
        if (col < a.len) return a[col];
    }
    return .left;
}

const BorderChars = struct {
    tl: u21,
    tr: u21,
    bl: u21,
    br: u21,
    h: u21,
    v: u21,
    top_tee: u21,
    bottom_tee: u21,
    left_tee: u21,
    right_tee: u21,
    cross: u21,
};

fn borderChars(border: Border, char_set: TableConfig.CharSet) BorderChars {
    if (char_set == .ascii) return .{
        .tl = '+', .tr = '+', .bl = '+', .br = '+',
        .h = '-', .v = '|',
        .top_tee = '+', .bottom_tee = '+',
        .left_tee = '+', .right_tee = '+',
        .cross = '+',
    };
    return switch (border) {
        .single, .none => .{
            .tl = 0x250C, .tr = 0x2510, .bl = 0x2514, .br = 0x2518,
            .h = 0x2500, .v = 0x2502,
            .top_tee = 0x252C, .bottom_tee = 0x2534,
            .left_tee = 0x251C, .right_tee = 0x2524,
            .cross = 0x253C,
        },
        .heavy => .{
            .tl = 0x250F, .tr = 0x2513, .bl = 0x2517, .br = 0x251B,
            .h = 0x2501, .v = 0x2503,
            .top_tee = 0x2533, .bottom_tee = 0x253B,
            .left_tee = 0x2523, .right_tee = 0x252B,
            .cross = 0x254B,
        },
        .double => .{
            .tl = 0x2554, .tr = 0x2557, .bl = 0x255A, .br = 0x255D,
            .h = 0x2550, .v = 0x2551,
            .top_tee = 0x2566, .bottom_tee = 0x2569,
            .left_tee = 0x2560, .right_tee = 0x2563,
            .cross = 0x256C,
        },
    };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | tail -3`
Expected: PASS (exit 0)

- [ ] **Step 5: Commit**

```bash
git add src/render/terminal/table.zig src/render/terminal/table_tests.zig
git commit -m "feat: add table renderer with borderless single-row rendering"
```

---

### Task 2: Bordered tables and headers

**Files:**
- Modify: `src/render/terminal/table_tests.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/render/terminal/table_tests.zig`:

```zig
test "table: single border with headers" {
    const allocator = std.testing.allocator;
    const headers: []const []const u8 = &.{ "Name", "Age" };
    const rows: []const []const []const u8 = &.{
        &.{ "Alice", "30" },
        &.{ "Bob", "25" },
    };
    const output = try table.render(headers, rows, allocator, .{ .border = .single });
    defer allocator.free(output);
    // Should contain top border, header, separator, rows, bottom border
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x8c") != null); // ┌
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x98") != null); // ┘
    try std.testing.expect(std.mem.indexOf(u8, output, "Alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Bob") != null);
    // Header separator exists (├)
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x9c") != null);
}

test "table: no headers with border" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{ "x", "y" },
        &.{ "a", "b" },
    };
    const output = try table.render(null, rows, allocator, .{ .border = .single });
    defer allocator.free(output);
    // No header separator (├ appears only between data rows, not as header sep)
    // Count lines: top border + row1 + separator + row2 + bottom border = 5
    var line_count: usize = 0;
    for (output) |c| {
        if (c == '\n') line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), line_count);
}

test "table: heavy border" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{"cell"},
    };
    const output = try table.render(null, rows, allocator, .{ .border = .heavy });
    defer allocator.free(output);
    // ┏ = U+250F = 0xE2 0x94 0x8F
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x8f") != null);
}

test "table: double border" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{"cell"},
    };
    const output = try table.render(null, rows, allocator, .{ .border = .double });
    defer allocator.free(output);
    // ╔ = U+2554 = 0xE2 0x95 0x94
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x94") != null);
}

test "table: ascii fallback" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{ "a", "b" },
    };
    const output = try table.render(null, rows, allocator, .{ .char_set = .ascii });
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "+") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "-") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "|") != null);
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -3`
Expected: PASS — the implementation from Task 1 already handles borders and headers.

- [ ] **Step 3: Commit**

```bash
git add src/render/terminal/table_tests.zig
git commit -m "test: add bordered table and header tests"
```

---

### Task 3: Column alignment

**Files:**
- Modify: `src/render/terminal/table_tests.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/render/terminal/table_tests.zig`:

```zig
test "table: right alignment" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{ "1", "hello" },
        &.{ "200", "hi" },
    };
    const alignment: []const table.Alignment = &.{ .right, .left };
    const output = try table.render(null, rows, allocator, .{ .border = .none, .alignment = alignment });
    defer allocator.free(output);
    // "  1" right-padded to width 3
    try std.testing.expect(std.mem.indexOf(u8, output, "  1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "200") != null);
}

test "table: center alignment" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{"ab"},
        &.{"abcdef"},
    };
    const alignment: []const table.Alignment = &.{.center};
    const output = try table.render(null, rows, allocator, .{ .border = .none, .alignment = alignment });
    defer allocator.free(output);
    // "ab" centered in width 6 → "  ab  "
    try std.testing.expect(std.mem.indexOf(u8, output, "  ab  ") != null);
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -3`
Expected: PASS — alignment is already implemented in Task 1.

- [ ] **Step 3: Commit**

```bash
git add src/render/terminal/table_tests.zig
git commit -m "test: add column alignment tests"
```

---

### Task 4: Dimension helpers and paintTable

**Files:**
- Modify: `src/render/terminal/table.zig`
- Modify: `src/render/terminal/table_tests.zig`

- [ ] **Step 1: Write the failing tests**

Append to `src/render/terminal/table_tests.zig`:

```zig
test "tableWidth: accounts for borders and padding" {
    const headers: []const []const u8 = &.{ "Name", "Age" };
    const rows: []const []const []const u8 = &.{
        &.{ "Alice", "30" },
    };
    // single border: │ + space + col1(5) + space + │ + space + col2(3) + space + │
    // = 1 + 2 + 5 + 1 + 2 + 3 + 2 + 1 = (cols * (width + 3)) + 1
    const w = table.tableWidth(headers, rows, .{});
    try std.testing.expectEqual(@as(usize, 15), w);
}

test "tableWidth: borderless uses 2-space separator" {
    const rows: []const []const []const u8 = &.{
        &.{ "ab", "cd" },
    };
    // borderless: col1(2) + 2-space sep + col2(2) = 6
    const w = table.tableWidth(null, rows, .{ .border = .none });
    try std.testing.expectEqual(@as(usize, 6), w);
}

test "tableHeight: with headers" {
    const headers: []const []const u8 = &.{ "A", "B" };
    const rows: []const []const []const u8 = &.{
        &.{ "1", "2" },
        &.{ "3", "4" },
    };
    // top + header + header_sep + row1 + sep + row2 + bottom = 7
    const h = table.tableHeight(headers, rows);
    try std.testing.expectEqual(@as(usize, 7), h);
}

test "tableHeight: without headers" {
    const rows: []const []const []const u8 = &.{
        &.{"a"},
        &.{"b"},
        &.{"c"},
    };
    // top + row1 + sep + row2 + sep + row3 + bottom = 7
    const h = table.tableHeight(null, rows);
    try std.testing.expectEqual(@as(usize, 7), h);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test 2>&1 | tail -5`
Expected: FAIL — `tableWidth` and `tableHeight` not defined.

- [ ] **Step 3: Implement dimension helpers**

Add to `src/render/terminal/table.zig` (after `renderStreaming`):

```zig
pub fn tableWidth(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
) usize {
    const col_count = columnCount(headers, rows);
    if (col_count == 0) return 0;

    var col_widths_buf: [64]usize = undefined;
    const col_widths = col_widths_buf[0..col_count];
    computeColumnWidths(col_widths, headers, rows);

    if (config.border == .none) {
        var total: usize = 0;
        for (col_widths, 0..) |w, i| {
            if (i > 0) total += 2; // 2-space separator
            total += w;
        }
        return total;
    }

    // bordered: │ sp col sp │ sp col sp │ ...
    var total: usize = 1; // left border
    for (col_widths) |w| {
        total += w + 2 + 1; // space + col + space + border
    }
    return total;
}

pub fn tableHeight(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
) usize {
    if (rows.len == 0 and headers == null) return 0;
    // top border + bottom border = 2
    // each row = 1, separators between rows = rows.len - 1
    var h: usize = 2 + rows.len;
    if (rows.len > 1) h += rows.len - 1; // separators between data rows
    if (headers != null) h += 2; // header row + header separator
    return h;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -3`
Expected: PASS

- [ ] **Step 5: Write paintTable test**

Append to `src/render/terminal/table_tests.zig`:

```zig
const Buffer2D = @import("buffer.zig").Buffer2D;

test "paintTable: writes to buffer at offset" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{"hi"},
    };
    var buf = try Buffer2D.init(allocator, 20, 10);
    defer buf.deinit();
    table.paintTable(&buf, 2, 1, null, rows, .{});
    // Check that ┌ is at (2, 1)
    try std.testing.expectEqual(@as(u21, 0x250C), buf.get(2, 1));
    // Check that 'h' is at (4, 2) — border(1) + space(1) + h
    try std.testing.expectEqual(@as(u21, 'h'), buf.get(4, 2));
}
```

- [ ] **Step 6: Implement paintTable**

Add to `src/render/terminal/table.zig`:

```zig
const buffer_mod = @import("buffer.zig");
const Buffer2D = buffer_mod.Buffer2D;

pub fn paintTable(
    buffer: *Buffer2D,
    x: usize,
    y: usize,
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
) void {
    const col_count = columnCount(headers, rows);
    if (col_count == 0) return;

    var col_widths_buf: [64]usize = undefined;
    const col_widths = col_widths_buf[0..col_count];
    computeColumnWidths(col_widths, headers, rows);

    if (config.border == .none) {
        var row_y = y;
        if (headers) |hdrs| {
            paintBorderlessRow(buffer, x, row_y, hdrs, col_widths, config.alignment);
            row_y += 1;
        }
        for (rows) |row| {
            paintBorderlessRow(buffer, x, row_y, row, col_widths, config.alignment);
            row_y += 1;
        }
        return;
    }

    const bc = borderChars(config.border, config.char_set);
    var row_y = y;

    paintHRule(buffer, x, row_y, col_widths, bc.tl, bc.top_tee, bc.tr, bc.h);
    row_y += 1;

    if (headers) |hdrs| {
        paintDataRow(buffer, x, row_y, hdrs, col_widths, bc.v, config.alignment);
        row_y += 1;
        paintHRule(buffer, x, row_y, col_widths, bc.left_tee, bc.cross, bc.right_tee, bc.h);
        row_y += 1;
    }

    for (rows, 0..) |row, i| {
        paintDataRow(buffer, x, row_y, row, col_widths, bc.v, config.alignment);
        row_y += 1;
        if (i < rows.len - 1) {
            paintHRule(buffer, x, row_y, col_widths, bc.left_tee, bc.cross, bc.right_tee, bc.h);
            row_y += 1;
        }
    }

    paintHRule(buffer, x, row_y, col_widths, bc.bl, bc.bottom_tee, bc.br, bc.h);
}

fn paintHRule(buffer: *Buffer2D, x: usize, y: usize, widths: []const usize, left: u21, mid: u21, right: u21, h: u21) void {
    var cx = x;
    for (widths, 0..) |w, i| {
        buffer.set(cx, y, if (i == 0) left else mid);
        cx += 1;
        for (0..w + 2) |_| {
            buffer.set(cx, y, h);
            cx += 1;
        }
    }
    buffer.set(cx, y, right);
}

fn paintDataRow(buffer: *Buffer2D, x: usize, y: usize, cells: []const []const u8, widths: []const usize, v: u21, alignment: ?[]const Alignment) void {
    var cx = x;
    for (widths, 0..) |w, i| {
        buffer.set(cx, y, v);
        cx += 1;
        buffer.set(cx, y, ' ');
        cx += 1;
        const cell = if (i < cells.len) cells[i] else "";
        const al = getAlignment(alignment, i);
        const pad = if (w > cell.len) w - cell.len else 0;
        const left_pad: usize = switch (al) {
            .left => 0,
            .right => pad,
            .center => pad / 2,
        };
        for (0..left_pad) |_| {
            buffer.set(cx, y, ' ');
            cx += 1;
        }
        for (cell) |ch| {
            buffer.set(cx, y, ch);
            cx += 1;
        }
        const right_pad = pad - left_pad;
        for (0..right_pad) |_| {
            buffer.set(cx, y, ' ');
            cx += 1;
        }
        buffer.set(cx, y, ' ');
        cx += 1;
    }
    buffer.set(cx, y, v);
}

fn paintBorderlessRow(buffer: *Buffer2D, x: usize, y: usize, cells: []const []const u8, widths: []const usize, alignment: ?[]const Alignment) void {
    var cx = x;
    for (widths, 0..) |w, i| {
        if (i > 0) {
            buffer.set(cx, y, ' ');
            cx += 1;
            buffer.set(cx, y, ' ');
            cx += 1;
        }
        const cell = if (i < cells.len) cells[i] else "";
        const al = getAlignment(alignment, i);
        const pad = if (w > cell.len) w - cell.len else 0;
        const left_pad: usize = switch (al) {
            .left => 0,
            .right => pad,
            .center => pad / 2,
        };
        for (0..left_pad) |_| {
            buffer.set(cx, y, ' ');
            cx += 1;
        }
        for (cell) |ch| {
            buffer.set(cx, y, ch);
            cx += 1;
        }
        const right_pad = pad - left_pad;
        for (0..right_pad) |_| {
            buffer.set(cx, y, ' ');
            cx += 1;
        }
    }
}
```

Note: add the `const buffer_mod` and `Buffer2D` imports near the top of the file (after the `std` import).

- [ ] **Step 7: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -3`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/render/terminal/table.zig src/render/terminal/table_tests.zig
git commit -m "feat: add tableWidth, tableHeight, and paintTable for Buffer2D"
```

---

### Task 5: Edge cases

**Files:**
- Modify: `src/render/terminal/table_tests.zig`

- [ ] **Step 1: Write edge case tests**

Append to `src/render/terminal/table_tests.zig`:

```zig
test "table: single column single row" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{
        &.{"only"},
    };
    const output = try table.render(null, rows, allocator, .{});
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "only") != null);
    // 3 lines: top + data + bottom
    var line_count: usize = 0;
    for (output) |c| {
        if (c == '\n') line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), line_count);
}

test "table: empty rows slice" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{};
    const headers: []const []const u8 = &.{ "A", "B" };
    const output = try table.render(headers, rows, allocator, .{});
    defer allocator.free(output);
    // top + header + header_sep + bottom = 4 lines
    var line_count: usize = 0;
    for (output) |c| {
        if (c == '\n') line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), line_count);
}

test "table: no headers no rows returns empty" {
    const allocator = std.testing.allocator;
    const rows: []const []const []const u8 = &.{};
    const output = try table.render(null, rows, allocator, .{});
    defer allocator.free(output);
    try std.testing.expectEqualStrings("", output);
}
```

- [ ] **Step 2: Run tests — fix any failures**

Run: `zig build test 2>&1 | tail -5`

The "empty rows with headers" test may require a small fix to `renderStreaming` — when `rows.len == 0` but headers are present, the function should still render top border + header + header separator + bottom border. Check and fix if needed.

If `renderStreaming` needs a fix for the headers-only case, update the bordered branch:

```zig
if (config.border != .none) {
    const bc = borderChars(config.border, config.char_set);
    try writeHorizontalRule(writer, col_widths, bc.tl, bc.top_tee, bc.tr, bc.h);
    if (headers) |hdrs| {
        try writeDataRow(writer, hdrs, col_widths, bc.v, config.alignment);
        try writeHorizontalRule(writer, col_widths, bc.left_tee, bc.cross, bc.right_tee, bc.h);
    }
    for (rows, 0..) |row, i| {
        try writeDataRow(writer, row, col_widths, bc.v, config.alignment);
        if (i < rows.len - 1) {
            try writeHorizontalRule(writer, col_widths, bc.left_tee, bc.cross, bc.right_tee, bc.h);
        }
    }
    try writeHorizontalRule(writer, col_widths, bc.bl, bc.bottom_tee, bc.br, bc.h);
}
```

The same logic applies to `paintTable` — ensure the bottom border is drawn even when `rows.len == 0`.

- [ ] **Step 3: Run tests to verify all pass**

Run: `zig build test 2>&1 | tail -3`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/render/terminal/table.zig src/render/terminal/table_tests.zig
git commit -m "test: add table edge case tests"
```

---

### Task 6: Module integration

**Files:**
- Modify: `src/render/terminal/mod.zig`

- [ ] **Step 1: Add table re-export**

In `src/render/terminal/mod.zig`, find the line with `pub const plan_mod` or the section after submodule imports. Add alongside the other submodule imports:

```zig
pub const table = @import("table.zig");
```

Place it near the other public re-exports (after `pub const Buffer2D = ...`).

- [ ] **Step 2: Run full test suite**

Run: `zig build test 2>&1 | tail -3`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add src/render/terminal/mod.zig
git commit -m "feat: re-export table module from terminal renderer"
```

---

### Task 7: Example and build registration

**Files:**
- Create: `examples/terminal/table_demo.zig`
- Modify: `build.zig`

- [ ] **Step 1: Create the example**

In `examples/terminal/table_demo.zig`:

```zig
//! Table Renderer Demo — border styles, alignment, and headers.
//!
//! Run with: zig build run-terminal-table-demo

const std = @import("std");
const zigraph = @import("zigraph");
const table = zigraph.terminal.table;

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Table Renderer Demo                         ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    const headers: []const []const u8 = &.{ "ID", "Name", "Status" };
    const rows: []const []const []const u8 = &.{
        &.{ "1", "Parser", "done" },
        &.{ "2", "Resolver", "in progress" },
        &.{ "3", "Bridge", "planned" },
    };

    // 1) Single border (default)
    printSection("1) Single border with headers");
    {
        const output = try table.render(headers, rows, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 2) Heavy border
    printSection("2) Heavy border");
    {
        const output = try table.render(headers, rows, allocator, .{ .border = .heavy });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 3) Double border
    printSection("3) Double border");
    {
        const output = try table.render(headers, rows, allocator, .{ .border = .double });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 4) Borderless
    printSection("4) Borderless");
    {
        const output = try table.render(headers, rows, allocator, .{ .border = .none });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 5) Right-aligned numbers
    printSection("5) Right-aligned ID column");
    {
        const alignment: []const table.Alignment = &.{ .right, .left, .center };
        const output = try table.render(headers, rows, allocator, .{ .alignment = alignment });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 6) ASCII fallback
    printSection("6) ASCII fallback");
    {
        const output = try table.render(headers, rows, allocator, .{ .char_set = .ascii });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 7) No headers
    printSection("7) No headers");
    {
        const output = try table.render(null, rows, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
```

- [ ] **Step 2: Register in build.zig**

Find the last terminal example registration block in `build.zig` (before `// ── SVG Gallery Examples`) and add:

```zig
    const terminal_table_demo_mod = b.addModule("terminal_table_demo", .{
        .root_source_file = b.path("examples/terminal/table_demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const terminal_table_demo_exe = b.addExecutable(.{
        .name = "terminal_table_demo",
        .root_module = terminal_table_demo_mod,
    });
    b.installArtifact(terminal_table_demo_exe);

    const run_terminal_table_demo = b.addRunArtifact(terminal_table_demo_exe);
    const run_terminal_table_demo_step = b.step("run-terminal-table-demo", "Run table renderer demo");
    run_terminal_table_demo_step.dependOn(&run_terminal_table_demo.step);
```

- [ ] **Step 3: Build and run**

Run: `zig build run-terminal-table-demo 2>&1`
Expected: Tables rendered with all border styles, alignment, ASCII fallback.

- [ ] **Step 4: Commit**

```bash
git add examples/terminal/table_demo.zig build.zig
git commit -m "feat: add table renderer demo example"
```

---

### Task 8: README documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add Table Renderer section**

Find the `## Card Nodes` section in README.md. Add a new `## Table Renderer` section before it (after `## Tree Renderer`):

```markdown
## Table Renderer

Render tabular data as formatted Unicode tables — no graph engine needed:

```zig
const zigraph = @import("zigraph");
const table = zigraph.terminal.table;

const headers: []const []const u8 = &.{ "Task", "Component", "Status" };
const rows: []const []const []const u8 = &.{
    &.{ "1", "Tokenizer", "done" },
    &.{ "2", "Parser", "in progress" },
    &.{ "3", "Resolver", "planned" },
};
const output = try table.render(headers, rows, allocator, .{});
defer allocator.free(output);
std.debug.print("{s}\n", .{output});
```

Output:
```text
┌──────┬───────────┬─────────────┐
│ Task │ Component │ Status      │
├──────┼───────────┼─────────────┤
│ 1    │ Tokenizer │ done        │
├──────┼───────────┼─────────────┤
│ 2    │ Parser    │ in progress │
├──────┼───────────┼─────────────┤
│ 3    │ Resolver  │ planned     │
└──────┴───────────┴─────────────┘
```

Features:
- **Border styles** — `.single` (default), `.heavy` (`┏━┓`), `.double` (`╔═╗`), `.none` (borderless)
- **Column alignment** — per-column `.left`, `.center`, `.right` via `alignment` config
- **Optional headers** — pass `null` for headerless tables
- **ASCII fallback** — `.{ .char_set = .ascii }` for `+-|` borders
- **Streaming** — `renderStreaming()` writes to any `Writer` without allocation
- **Graph integration** — `paintTable()` writes to `Buffer2D` for use as graph node content
```

- [ ] **Step 2: Also add to Features list**

Find the features bullet list near the top of README and add:

```markdown
- **Table renderer** — Standalone formatted Unicode/ASCII tables with borders, alignment, and headers
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add table renderer section to README"
```

---

## Self-Review Checklist

1. **Spec coverage**: All spec requirements covered — render/renderStreaming (Task 1), borders (Task 2), alignment (Task 3), paintTable + dimensions (Task 4), edge cases (Task 5), mod.zig integration (Task 6), example (Task 7), README (Task 8).
2. **Placeholder scan**: No TBD/TODO. All code blocks complete.
3. **Type consistency**: `TableConfig`, `Border`, `Alignment`, `tableWidth`, `tableHeight`, `paintTable` — consistent across all tasks. `render`/`renderStreaming` signatures match throughout.
