//! Standalone tree renderer — hierarchical `├─└─` text diagrams.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TreeNode = struct {
    label: []const u8,
    description: ?[]const u8 = null,
    extra_lines: []const []const u8 = &.{},
    blank_above: bool = false,
    children: []const TreeNode = &.{},
};

pub const TreeConfig = struct {
    indent: usize = 4,
    char_set: CharSet = .unicode,

    pub const CharSet = enum { unicode, ascii };
};

pub fn render(roots: []const TreeNode, allocator: Allocator, config: TreeConfig) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    try renderStreaming(roots, buf.writer(allocator), config);
    return buf.toOwnedSlice(allocator);
}

pub fn renderStreaming(roots: []const TreeNode, writer: anytype, config: TreeConfig) !void {
    for (roots) |root| {
        try writer.writeAll(root.label);
        if (root.description) |desc| {
            try writer.writeAll(" \xe2\x94\x80\xe2\x94\x80 ");
            try writer.writeAll(desc);
        }
        try writer.writeByte('\n');

        for (root.extra_lines) |line| {
            try writeIndent(writer, &.{}, config);
            try writer.writeAll(line);
            try writer.writeByte('\n');
        }

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

        if (child.blank_above) {
            try writeIndent(writer, ancestors_have_more, config);
            try writePipe(writer, config.char_set);
            try writer.writeByte('\n');
        }

        try writeIndent(writer, ancestors_have_more, config);
        if (is_last) {
            try writeBranch(writer, config.char_set, true);
        } else {
            try writeBranch(writer, config.char_set, false);
        }
        try writer.writeByte(' ');

        try writer.writeAll(child.label);
        if (child.description) |desc| {
            try writer.writeAll(" \xe2\x94\x80\xe2\x94\x80 ");
            try writer.writeAll(desc);
        }
        try writer.writeByte('\n');

        for (child.extra_lines) |line| {
            try writeIndent(writer, ancestors_have_more, config);
            if (!is_last) {
                try writePipe(writer, config.char_set);
                try writer.writeAll("   ");
            } else {
                try writer.writeAll("    ");
            }
            try writer.writeAll(line);
            try writer.writeByte('\n');
        }

        if (child.children.len > 0) {
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
