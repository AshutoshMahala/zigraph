//! Tree renderer — renders hierarchical data as indented `├─└─` text.
//!
//! This is a standalone renderer that does not use the graph layout engine.
//! It produces tree diagrams like:
//!
//! ```text
//! Root
//!   ├─ Child A
//!   │  └─ Grandchild
//!   └─ Child B
//! ```
//!
//! Features:
//! - Multi-line items via `extra_lines` (continuation text under branch line)
//! - Visual grouping via `blank_above` (empty `│` line before an item)
//! - Optional description after the label via `description`
//! - Configurable indent width and character set (unicode/ascii)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A node in the tree. Trees are built by nesting children.
pub const TreeNode = struct {
    /// Primary label (displayed on the tree line)
    label: []const u8,
    /// Optional description displayed after ` ── `
    description: ?[]const u8 = null,
    /// Extra continuation lines displayed indented below the label line.
    /// Each string becomes its own line under the `│   ` prefix.
    extra_lines: []const []const u8 = &.{},
    /// If true, insert a blank `│` line before this node (visual grouping).
    blank_above: bool = false,
    /// Child nodes
    children: []const TreeNode = &.{},
};

pub const TreeConfig = struct {
    /// Indentation width per level (number of chars for each `│  ` or `   ` segment)
    indent: usize = 4,
    /// Character set for branches
    char_set: CharSet = .unicode,

    pub const CharSet = enum { unicode, ascii };
};

/// Render a tree to a UTF-8 string. Caller owns the returned slice.
pub fn render(roots: []const TreeNode, allocator: Allocator, config: TreeConfig) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    try renderStreaming(roots, buf.writer(allocator), config);
    return buf.toOwnedSlice(allocator);
}

/// Render a tree to any writer (streaming, zero accumulation).
pub fn renderStreaming(roots: []const TreeNode, writer: anytype, config: TreeConfig) !void {
    for (roots) |root| {
        // Root label
        try writer.writeAll(root.label);
        if (root.description) |desc| {
            try writer.writeAll(" \xe2\x94\x80\xe2\x94\x80 "); // " ── "
            try writer.writeAll(desc);
        }
        try writer.writeByte('\n');

        // Root extra_lines (no prefix)
        for (root.extra_lines) |line| {
            try writeIndent(writer, &.{}, config);
            try writer.writeAll(line);
            try writer.writeByte('\n');
        }

        // Root children
        try renderChildren(root.children, writer, config, &.{});
    }
}

fn renderChildren(
    children: []const TreeNode,
    writer: anytype,
    config: TreeConfig,
    ancestors_have_more: []const bool,
) !void {
    for (children, 0..) |child, i| {
        const is_last = (i == children.len - 1);

        // Blank line above for visual grouping
        if (child.blank_above) {
            try writeIndent(writer, ancestors_have_more, config);
            try writePipe(writer, config.char_set);
            try writer.writeByte('\n');
        }

        // Branch prefix: "├─ " or "└─ "
        try writeIndent(writer, ancestors_have_more, config);
        if (is_last) {
            try writeBranch(writer, config.char_set, true);
        } else {
            try writeBranch(writer, config.char_set, false);
        }
        try writer.writeByte(' ');

        // Label + optional description
        try writer.writeAll(child.label);
        if (child.description) |desc| {
            try writer.writeAll(" \xe2\x94\x80\xe2\x94\x80 "); // " ── "
            try writer.writeAll(desc);
        }
        try writer.writeByte('\n');

        // Extra continuation lines
        for (child.extra_lines) |line| {
            try writeIndent(writer, ancestors_have_more, config);
            // Continuation uses │ or space depending on is_last
            if (!is_last) {
                try writePipe(writer, config.char_set);
                // Pad to align with label start (branch is 2 chars + 1 space = 3)
                try writer.writeAll("   ");
            } else {
                // Last child: no pipe, just spaces
                try writer.writeAll("    ");
            }
            try writer.writeAll(line);
            try writer.writeByte('\n');
        }

        // Recurse into children
        if (child.children.len > 0) {
            // Stack-based ancestor tracking (max 64 levels deep)
            var new_ancestors: [64]bool = undefined;
            const new_len = @min(ancestors_have_more.len + 1, 64);
            @memcpy(new_ancestors[0..ancestors_have_more.len], ancestors_have_more);
            if (ancestors_have_more.len < 64) {
                new_ancestors[ancestors_have_more.len] = !is_last;
            }
            try renderChildren(child.children, writer, config, new_ancestors[0..new_len]);
        }
    }
}

/// Write the indent prefix for the current depth.
/// Each ancestor level contributes either `│   ` (has more siblings) or `    ` (last child).
fn writeIndent(writer: anytype, ancestors_have_more: []const bool, config: TreeConfig) !void {
    for (ancestors_have_more) |has_more| {
        if (has_more) {
            try writePipe(writer, config.char_set);
            for (1..config.indent) |_| try writer.writeByte(' ');
        } else {
            for (0..config.indent) |_| try writer.writeByte(' ');
        }
    }
}

fn writeBranch(writer: anytype, char_set: TreeConfig.CharSet, is_last: bool) !void {
    if (is_last) {
        switch (char_set) {
            .unicode => try writer.writeAll("\xe2\x94\x94\xe2\x94\x80"), // └─
            .ascii => try writer.writeAll("`-"),
        }
    } else {
        switch (char_set) {
            .unicode => try writer.writeAll("\xe2\x94\x9c\xe2\x94\x80"), // ├─
            .ascii => try writer.writeAll("+-"),
        }
    }
}

fn writePipe(writer: anytype, char_set: TreeConfig.CharSet) !void {
    switch (char_set) {
        .unicode => try writer.writeAll("\xe2\x94\x82"), // │
        .ascii => try writer.writeByte('|'),
    }
}
