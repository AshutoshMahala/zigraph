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

test "tree: extra continuation lines" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "Root",
        .children = &.{
            .{
                .label = "Corrections tracked as structured feedback",
                .extra_lines = &.{"(field, extracted_value, corrected_value)"},
            },
            .{ .label = "Last item" },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    // Continuation line should appear with │ prefix
    try std.testing.expect(std.mem.indexOf(u8, output, "(field, extracted_value, corrected_value)") != null);
    // The continuation line should have │ (pipe) somewhere before it
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x82   (field") != null); // │   (field...
}

test "tree: blank_above inserts visual gap" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "Root",
        .children = &.{
            .{ .label = "Group 1 item" },
            .{ .label = "Group 2 item", .blank_above = true },
            .{ .label = "Group 2 another" },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    // Should have a blank line with just │ before "Group 2 item"
    // Find "Group 1 item" and "Group 2 item" and check there's extra space
    const g1_pos = std.mem.indexOf(u8, output, "Group 1 item").?;
    const g2_pos = std.mem.indexOf(u8, output, "Group 2 item").?;
    // The gap between them should be larger than a single newline
    try std.testing.expect(g2_pos - g1_pos > "Group 1 item\n".len + 5);
}

test "tree: description text" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "Root",
        .children = &.{
            .{ .label = "Config", .description = "base64 encoded JSON" },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "Config \xe2\x94\x80\xe2\x94\x80 base64 encoded JSON") != null);
}

test "tree: full review queue example" {
    const allocator = std.testing.allocator;
    const nodes = [_]TreeNode{.{
        .label = "Variant appears in the review queue (split-panel UI)",
        .children = &.{
            .{ .label = "Reviewer sees thumbnail + all metadata sections" },
            .{ .label = "Can approve, flag, or edit individual fields" },
            .{
                .label = "Corrections tracked as structured feedback",
                .extra_lines = &.{"(field, extracted_value, corrected_value)"},
            },
            .{ .label = "Bulk operations: Cmd+click multiple", .blank_above = true },
            .{ .label = "Copy to siblings: share catalog/game data across color variants" },
            .{ .label = "Status: unreviewed -> approved / flagged", .blank_above = true },
        },
    }};
    const output = try tree.render(&nodes, allocator, .{});
    defer allocator.free(output);

    // All items present
    try std.testing.expect(std.mem.indexOf(u8, output, "Variant appears") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Reviewer sees") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Corrections tracked") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(field, extracted_value") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Bulk operations") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Status: unreviewed") != null);
    // Last item uses └─
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x94\x94\xe2\x94\x80 Status") != null);
}
