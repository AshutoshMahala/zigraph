//! Tests for the standalone table renderer.

const std = @import("std");
const table = @import("table.zig");
const TableConfig = table.TableConfig;
const Alignment = table.Alignment;
const Border = table.Border;
const Buffer2D = @import("buffer.zig").Buffer2D;

// ── Task 1: single row, no headers, borderless ───────────────────────────────

test "table: single row no headers borderless" {
    const allocator = std.testing.allocator;

    const rows: []const []const []const u8 = &.{
        &.{ "hello", "world" },
    };

    const result = try table.render(null, rows, allocator, .{ .border = .none });
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello  world\n", result);
}

// ── Task 2: borders and headers ──────────────────────────────────────────────

test "table: single border with headers" {
    const allocator = std.testing.allocator;

    const headers: []const []const u8 = &.{ "Name", "City" };
    const rows: []const []const []const u8 = &.{
        &.{ "Alice", "NY" },
        &.{ "Bob", "LA" },
    };

    const result = try table.render(headers, rows, allocator, .{ .border = .single });
    defer allocator.free(result);

    // Top-left corner must be present
    try std.testing.expect(std.mem.indexOf(u8, result, "┌") != null);
    // Bottom-right corner must be present
    try std.testing.expect(std.mem.indexOf(u8, result, "┘") != null);
    // Header separator must be present
    try std.testing.expect(std.mem.indexOf(u8, result, "├") != null);
    // Data must appear
    try std.testing.expect(std.mem.indexOf(u8, result, "Alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Bob") != null);
}

test "table: no headers with border" {
    const allocator = std.testing.allocator;

    const rows: []const []const []const u8 = &.{
        &.{ "foo", "bar" },
        &.{ "baz", "qux" },
    };

    const result = try table.render(null, rows, allocator, .{ .border = .single });
    defer allocator.free(result);

    // Count lines: top border + row1 + separator + row2 + bottom border = 5 lines
    var line_count: usize = 0;
    var it = std.mem.splitScalar(u8, result, '\n');
    while (it.next()) |line| {
        if (line.len > 0) line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), line_count);
}

test "table: heavy border" {
    const allocator = std.testing.allocator;

    const rows: []const []const []const u8 = &.{
        &.{ "x", "y" },
    };

    const result = try table.render(null, rows, allocator, .{ .border = .heavy });
    defer allocator.free(result);

    // ┏ is U+250F, encoded as 0xE2 0x94 0x8F in UTF-8
    try std.testing.expect(std.mem.indexOf(u8, result, "┏") != null);
}

test "table: double border" {
    const allocator = std.testing.allocator;

    const rows: []const []const []const u8 = &.{
        &.{ "x", "y" },
    };

    const result = try table.render(null, rows, allocator, .{ .border = .double });
    defer allocator.free(result);

    // ╔ is U+2554, encoded as 0xE2 0x95 0x94 in UTF-8
    try std.testing.expect(std.mem.indexOf(u8, result, "╔") != null);
}

test "table: ascii fallback" {
    const allocator = std.testing.allocator;

    const rows: []const []const []const u8 = &.{
        &.{ "a", "b" },
    };

    const result = try table.render(null, rows, allocator, .{
        .border = .single,
        .char_set = .ascii,
    });
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "+") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "-") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "|") != null);
}

// ── Task 3: alignment ────────────────────────────────────────────────────────

test "table: right alignment" {
    const allocator = std.testing.allocator;

    // Column width will be 3 (from "123"), value "1" should be right-padded to "  1"
    const rows: []const []const []const u8 = &.{
        &.{ "1", "x" },
        &.{ "123", "y" },
    };
    const aligns: []const Alignment = &.{ .right, .left };

    const result = try table.render(null, rows, allocator, .{
        .border = .none,
        .alignment = aligns,
    });
    defer allocator.free(result);

    // First row, first column should be right-aligned "  1"
    try std.testing.expect(std.mem.indexOf(u8, result, "  1") != null);
}

test "table: center alignment" {
    const allocator = std.testing.allocator;

    // Column width will be 6 (from "longer"), value "ab" centered in 6 = "  ab  "
    const rows: []const []const []const u8 = &.{
        &.{"ab"},
        &.{"longer"},
    };
    const aligns: []const Alignment = &.{.center};

    const result = try table.render(null, rows, allocator, .{
        .border = .none,
        .alignment = aligns,
    });
    defer allocator.free(result);

    // "ab" centered in width 6: 2 spaces left, 2 spaces right → "  ab  "
    try std.testing.expect(std.mem.indexOf(u8, result, "  ab  ") != null);
}

// ── Task 4: Dimension helpers and paintTable ──────────────────────────────────

test "tableWidth: bordered" {
    // headers: {"Name","Age"}, rows: {{"Alice","30"}}
    // col widths: Name=5 (Alice), Age=3 (Age)
    // width = (2+1) + (5+2) + (3+2) = 3 + 7 + 5 = 15
    const headers: []const []const u8 = &.{ "Name", "Age" };
    const rows: []const []const []const u8 = &.{
        &.{ "Alice", "30" },
    };

    const w = table.tableWidth(headers, rows, .{ .border = .single });
    try std.testing.expectEqual(@as(usize, 15), w);
}

test "tableWidth: borderless" {
    // rows: {{"ab","cd"}}, col widths both 2, borderless: 2 + 2 + 2*1 = 6
    const rows: []const []const []const u8 = &.{
        &.{ "ab", "cd" },
    };

    const w = table.tableWidth(null, rows, .{ .border = .none });
    try std.testing.expectEqual(@as(usize, 6), w);
}

test "tableHeight: with headers" {
    // 2 headers, 2 data rows → top + hdr + hdr_sep + r1 + sep + r2 + bot = 7
    const headers: []const []const u8 = &.{ "A", "B" };
    const rows: []const []const []const u8 = &.{
        &.{ "1", "2" },
        &.{ "3", "4" },
    };

    const h = table.tableHeight(headers, rows, .{ .border = .single });
    try std.testing.expectEqual(@as(usize, 7), h);
}

test "tableHeight: without headers" {
    // 3 data rows, no headers → top + r1 + sep + r2 + sep + r3 + bot = 7
    const rows: []const []const []const u8 = &.{
        &.{"a"},
        &.{"b"},
        &.{"c"},
    };

    const h = table.tableHeight(null, rows, .{ .border = .single });
    try std.testing.expectEqual(@as(usize, 7), h);
}

test "paintTable: writes to buffer" {
    const allocator = std.testing.allocator;

    // Single row "hi" at buffer offset (2, 1)
    const rows: []const []const []const u8 = &.{
        &.{"hi"},
    };
    // tableWidth = (1+1) + (2+2) = 6, tableHeight = 2+1+1 = 3 (top+row+bot)
    const tw = table.tableWidth(null, rows, .{ .border = .single });
    const th = table.tableHeight(null, rows, .{ .border = .single });

    const buf_w = tw + 2; // offset 2 in x
    const buf_h = th + 1; // offset 1 in y
    var buf = try Buffer2D.init(allocator, buf_w, buf_h);
    defer buf.deinit(allocator);

    table.paintTable(&buf, 2, 1, null, rows, .{ .border = .single });

    // Top-left corner (┌ = U+250C) should be at (2, 1)
    try std.testing.expectEqual(@as(u21, '┌'), buf.get(2, 1));

    // 'h' should appear at column 4 (offset 2 + border 1 + space 1 = 4), row 2
    try std.testing.expectEqual(@as(u21, 'h'), buf.get(4, 2));
    // 'i' should follow at column 5
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(5, 2));
}

// ── Task 5: Edge case tests ───────────────────────────────────────────────────

test "table: single column single row" {
    const allocator = std.testing.allocator;

    const rows: []const []const []const u8 = &.{
        &.{"x"},
    };

    const result = try table.render(null, rows, allocator, .{ .border = .single });
    defer allocator.free(result);

    // Expect exactly 3 non-empty lines: top border, data row, bottom border
    var line_count: usize = 0;
    var it = std.mem.splitScalar(u8, result, '\n');
    while (it.next()) |line| {
        if (line.len > 0) line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), line_count);
}

test "table: empty rows with headers" {
    const allocator = std.testing.allocator;

    const headers: []const []const u8 = &.{ "Col1", "Col2" };
    const rows: []const []const []const u8 = &.{};

    const result = try table.render(headers, rows, allocator, .{ .border = .single });
    defer allocator.free(result);

    // Expect 4 non-empty lines: top border, header row, header separator, bottom border
    var line_count: usize = 0;
    var it = std.mem.splitScalar(u8, result, '\n');
    while (it.next()) |line| {
        if (line.len > 0) line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), line_count);
}

test "table: no headers no rows" {
    const allocator = std.testing.allocator;

    const rows: []const []const []const u8 = &.{};

    const result = try table.render(null, rows, allocator, .{ .border = .single });
    defer allocator.free(result);

    // Nothing to render — result should be empty
    try std.testing.expectEqualStrings("", result);
}
