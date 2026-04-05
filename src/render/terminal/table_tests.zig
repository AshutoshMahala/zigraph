//! Tests for the standalone table renderer.

const std = @import("std");
const table = @import("table.zig");
const TableConfig = table.TableConfig;
const Alignment = table.Alignment;
const Border = table.Border;

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
