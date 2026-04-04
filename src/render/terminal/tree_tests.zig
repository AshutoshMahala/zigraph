//! Tests for the tree renderer.

const std = @import("std");
const tree = @import("tree.zig");
const TreeNode = tree.TreeNode;

test "tree: single root no children" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{ .label = "Root" }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    try std.testing.expectEqualStrings("Root\n", output);
}

test "tree: root with two children" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "Root",
        .children = &.{
            .{ .label = "Child A" },
            .{ .label = "Child B" },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "Root\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x9c\xe2\x94\x80 Child A") != null); // ├─ Child A
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x94\xe2\x94\x80 Child B") != null); // └─ Child B
}

test "tree: nested children with continuation lines" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "Root",
        .children = &.{
            .{ .label = "A", .children = &.{
                .{ .label = "A1" },
            } },
            .{ .label = "B" },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    // A is not last, so its children have │ continuation from B
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x82") != null); // │
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x94\xe2\x94\x80 A1") != null); // └─ A1
}

test "tree: ascii charset" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "Root",
        .children = &.{
            .{ .label = "A" },
            .{ .label = "B" },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{ .char_set = .ascii });
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "+- A") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "`- B") != null);
}

test "tree: deeply nested 4 levels" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "L0",
        .children = &.{
            .{ .label = "L1", .children = &.{
                .{ .label = "L2", .children = &.{
                    .{ .label = "L3" },
                } },
            } },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "L0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "L3") != null);
}

test "tree: multiple roots" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{
        .{ .label = "Root A", .children = &.{.{ .label = "A1" }} },
        .{ .label = "Root B", .children = &.{.{ .label = "B1" }} },
    };
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "Root A") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Root B") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "A1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "B1") != null);
}

test "tree: empty children array" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{ .label = "Leaf", .children = &.{} }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    try std.testing.expectEqualStrings("Leaf\n", output);
}
