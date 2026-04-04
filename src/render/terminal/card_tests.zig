//! Tests for card node rendering.

const std = @import("std");
const card = @import("card.zig");
const buffer_mod = @import("buffer.zig");
const Buffer2D = buffer_mod.Buffer2D;
const config_mod = @import("config.zig");
const CardStyle = config_mod.CardStyle;

test "card: paint basic card on buffer" {
    const allocator = std.testing.allocator;
    // Card: top(1) + header(1) + sep(1) + 2 lines + bottom(1) = 6 rows
    var buf = try Buffer2D.init(allocator, 20, 8);
    defer buf.deinit(allocator);

    const lines = [_][]const u8{ "line 1", "line 2" };
    card.paintCard(&buf, 0, 0, 12, "Header", &lines, .{});

    // Top-left corner should be ┌ (0x250C)
    try std.testing.expectEqual(@as(u21, 0x250C), buf.get(0, 0));
    // Top-right corner should be ┐ (0x2510)
    try std.testing.expectEqual(@as(u21, 0x2510), buf.get(11, 0));
    // Separator left should be ├ (0x251C)
    try std.testing.expectEqual(@as(u21, 0x251C), buf.get(0, 2));
    // Bottom-left corner should be └ (0x2514)
    try std.testing.expectEqual(@as(u21, 0x2514), buf.get(0, 5));
    // Bottom-right corner should be ┘ (0x2518)
    try std.testing.expectEqual(@as(u21, 0x2518), buf.get(11, 5));
    // Header text (centered) — "Header" is 6 chars in width 12 (inner=10), pad=2
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(3, 1));
    // First content line at row 3 — "line 1" starts at x=1
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(1, 3));
}

test "card: zero lines produces header-only box" {
    const allocator = std.testing.allocator;
    var buf = try Buffer2D.init(allocator, 15, 5);
    defer buf.deinit(allocator);

    card.paintCard(&buf, 0, 0, 10, "Title", &.{}, .{});

    // Should be 4 rows: top, header, sep, bottom
    try std.testing.expectEqual(@as(u21, 0x250C), buf.get(0, 0)); // ┌
    try std.testing.expectEqual(@as(u21, 0x2514), buf.get(0, 3)); // └
}

test "card: width from content" {
    const lines1 = [_][]const u8{"A longer line"};
    try std.testing.expectEqual(@as(usize, 15), card.cardWidth("Short", &lines1));
    const lines2 = [_][]const u8{"abc"};
    try std.testing.expectEqual(@as(usize, 7), card.cardWidth("Title", &lines2));
}

test "card: height calculation" {
    try std.testing.expectEqual(@as(usize, 6), card.cardHeight(2));
    try std.testing.expectEqual(@as(usize, 4), card.cardHeight(0));
    try std.testing.expectEqual(@as(usize, 5), card.cardHeight(1));
}
