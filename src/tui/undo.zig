const std = @import("std");
const Allocator = std.mem.Allocator;
const TextBuffer = @import("text_buffer.zig");

const UndoManager = @This();

const EditOp = union(enum) {
    insert: struct { pos: usize, text: []const u8 },
    delete: struct { pos: usize, text: []const u8 },
};

const EditGroup = struct {
    ops: std.ArrayListUnmanaged(EditOp),

    fn deinit(self: *EditGroup, allocator: Allocator) void {
        for (self.ops.items) |op| {
            switch (op) {
                .insert => |data| allocator.free(data.text),
                .delete => |data| allocator.free(data.text),
            }
        }
        self.ops.deinit(allocator);
    }
};

allocator: Allocator,
undo_stack: std.ArrayListUnmanaged(EditGroup),
redo_stack: std.ArrayListUnmanaged(EditGroup),
current_group: ?EditGroup,

pub fn init(allocator: Allocator) UndoManager {
    return .{
        .allocator = allocator,
        .undo_stack = .{},
        .redo_stack = .{},
        .current_group = null,
    };
}

pub fn deinit(self: *UndoManager) void {
    for (self.undo_stack.items) |*group| {
        group.deinit(self.allocator);
    }
    self.undo_stack.deinit(self.allocator);

    for (self.redo_stack.items) |*group| {
        group.deinit(self.allocator);
    }
    self.redo_stack.deinit(self.allocator);

    if (self.current_group) |*group| {
        group.deinit(self.allocator);
    }
}

/// Inserts `text` at byte position `pos` in `buf` and records the operation in the
/// current undo group. Clears the redo stack.
pub fn insertText(self: *UndoManager, buf: *TextBuffer, pos: usize, text: []const u8) Allocator.Error!void {
    try buf.insert(pos, text);

    const duped = try self.allocator.dupe(u8, text);
    try self.ensureCurrentGroup();
    try self.current_group.?.ops.append(self.allocator, .{ .insert = .{ .pos = pos, .text = duped } });

    self.clearRedoStack();
}

/// Deletes `len` bytes starting at `pos` from `buf` and records the operation in
/// the current undo group. Clears the redo stack.
pub fn deleteText(self: *UndoManager, buf: *TextBuffer, pos: usize, len: usize) Allocator.Error!void {
    const deleted = try buf.delete(pos, len);

    try self.ensureCurrentGroup();
    try self.current_group.?.ops.append(self.allocator, .{ .delete = .{ .pos = pos, .text = deleted } });

    self.clearRedoStack();
}

/// Finalizes the current edit group so that subsequent edits start a new undo step.
/// Call this at logical edit boundaries (e.g., after a word is completed, on cursor
/// movement, or before a structurally distinct operation).
pub fn breakGroup(self: *UndoManager) Allocator.Error!void {
    if (self.current_group) |group| {
        if (group.ops.items.len > 0) {
            try self.undo_stack.append(self.allocator, group);
        } else {
            var g = group;
            g.deinit(self.allocator);
        }
        self.current_group = null;
    }
}

pub fn undo(self: *UndoManager, buf: *TextBuffer) Allocator.Error!void {
    try self.breakGroup();

    if (self.undo_stack.items.len == 0) return;
    const group = self.undo_stack.pop().?;

    var i: usize = group.ops.items.len;
    while (i > 0) {
        i -= 1;
        const op = group.ops.items[i];
        switch (op) {
            .insert => |data| {
                // Undo insert = delete from buffer (discard returned text)
                const deleted = try buf.delete(data.pos, data.text.len);
                self.allocator.free(deleted);
            },
            .delete => |data| {
                // Undo delete = re-insert into buffer
                try buf.insert(data.pos, data.text);
            },
        }
    }

    try self.redo_stack.append(self.allocator, group);
}

pub fn redo(self: *UndoManager, buf: *TextBuffer) Allocator.Error!void {
    if (self.redo_stack.items.len == 0) return;
    const group = self.redo_stack.pop().?;

    for (group.ops.items) |op| {
        switch (op) {
            .insert => |data| {
                try buf.insert(data.pos, data.text);
            },
            .delete => |data| {
                const deleted = try buf.delete(data.pos, data.text.len);
                self.allocator.free(deleted);
            },
        }
    }

    try self.undo_stack.append(self.allocator, group);
}

fn ensureCurrentGroup(self: *UndoManager) Allocator.Error!void {
    if (self.current_group == null) {
        self.current_group = .{ .ops = .{} };
    }
}

fn clearRedoStack(self: *UndoManager) void {
    for (self.redo_stack.items) |*group| {
        group.deinit(self.allocator);
    }
    self.redo_stack.clearRetainingCapacity();
}

// --- Tests ---

const testing = std.testing;

fn bufContents(buf: *TextBuffer) ![]u8 {
    return buf.contents(testing.allocator);
}

test "single insert undo" {
    var buf = try TextBuffer.init(testing.allocator, "hello");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();

    try um.insertText(&buf, 5, " world");
    try um.breakGroup();

    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("hello world", c);
    }

    try um.undo(&buf);

    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("hello", c);
    }
}

test "single delete undo" {
    var buf = try TextBuffer.init(testing.allocator, "hello world");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();

    try um.deleteText(&buf, 5, 6);
    try um.breakGroup();

    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("hello", c);
    }

    try um.undo(&buf);

    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("hello world", c);
    }
}

test "redo after undo" {
    var buf = try TextBuffer.init(testing.allocator, "hello");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();

    try um.insertText(&buf, 5, " world");
    try um.breakGroup();
    try um.undo(&buf);

    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("hello", c);
    }

    try um.redo(&buf);

    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("hello world", c);
    }
}

test "new edit clears redo stack" {
    var buf = try TextBuffer.init(testing.allocator, "hello");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();

    try um.insertText(&buf, 5, " world");
    try um.breakGroup();
    try um.undo(&buf);

    try testing.expectEqual(@as(usize, 1), um.redo_stack.items.len);

    try um.insertText(&buf, 5, "!");
    try testing.expectEqual(@as(usize, 0), um.redo_stack.items.len);
}

test "multiple undo redo sequence" {
    var buf = try TextBuffer.init(testing.allocator, "");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();

    try um.insertText(&buf, 0, "a");
    try um.breakGroup();

    try um.insertText(&buf, 1, "b");
    try um.breakGroup();

    try um.insertText(&buf, 2, "c");
    try um.breakGroup();

    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("abc", c);
    }

    try um.undo(&buf);
    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("ab", c);
    }

    try um.undo(&buf);
    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("a", c);
    }

    try um.redo(&buf);
    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("ab", c);
    }

    try um.redo(&buf);
    {
        const c = try bufContents(&buf);
        defer testing.allocator.free(c);
        try testing.expectEqualStrings("abc", c);
    }
}
