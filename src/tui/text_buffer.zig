const std = @import("std");
const Allocator = std.mem.Allocator;

const TextBuffer = @This();

const Source = enum { original, add };

const Piece = struct {
    source: Source,
    start: usize,
    len: usize,
};

allocator: Allocator,
original: []const u8,
add_buf: std.ArrayListUnmanaged(u8),
pieces: std.ArrayListUnmanaged(Piece),

pub const LineCol = struct {
    line: usize,
    col: usize,
};

pub fn init(allocator: Allocator, content: []const u8) Allocator.Error!TextBuffer {
    const original = try allocator.alloc(u8, content.len);
    @memcpy(original, content);

    var pieces: std.ArrayListUnmanaged(Piece) = .{};
    if (content.len > 0) {
        try pieces.append(allocator, .{
            .source = .original,
            .start = 0,
            .len = content.len,
        });
    }

    return .{
        .allocator = allocator,
        .original = original,
        .add_buf = .{},
        .pieces = pieces,
    };
}

pub fn deinit(self: *TextBuffer) void {
    self.allocator.free(self.original);
    self.add_buf.deinit(self.allocator);
    self.pieces.deinit(self.allocator);
}

pub fn totalLen(self: *const TextBuffer) usize {
    var total: usize = 0;
    for (self.pieces.items) |p| {
        total += p.len;
    }
    return total;
}

fn bufFor(self: *const TextBuffer, source: Source) []const u8 {
    return switch (source) {
        .original => self.original,
        .add => self.add_buf.items,
    };
}

fn pieceSlice(self: *const TextBuffer, p: Piece) []const u8 {
    const buf = self.bufFor(p.source);
    return buf[p.start..][0..p.len];
}

pub fn insert(self: *TextBuffer, pos: usize, text: []const u8) Allocator.Error!void {
    if (text.len == 0) return;

    const add_start = self.add_buf.items.len;
    try self.add_buf.appendSlice(self.allocator, text);

    const new_piece = Piece{
        .source = .add,
        .start = add_start,
        .len = text.len,
    };

    // Find which piece contains `pos`
    var offset: usize = 0;
    var i: usize = 0;
    while (i < self.pieces.items.len) : (i += 1) {
        const p = self.pieces.items[i];
        if (offset + p.len >= pos) break;
        offset += p.len;
    }

    if (i == self.pieces.items.len) {
        // Append at end
        try self.pieces.append(self.allocator, new_piece);
        return;
    }

    const local = pos - offset;
    const p = self.pieces.items[i];

    if (local == 0) {
        // Insert before piece i
        try self.pieces.insert(self.allocator, i, new_piece);
    } else if (local == p.len) {
        // Insert after piece i
        try self.pieces.insert(self.allocator, i + 1, new_piece);
    } else {
        // Split piece i
        const left = Piece{ .source = p.source, .start = p.start, .len = local };
        const right = Piece{ .source = p.source, .start = p.start + local, .len = p.len - local };
        self.pieces.items[i] = left;
        // Insert new_piece and right after i
        try self.pieces.insertSlice(self.allocator, i + 1, &.{ new_piece, right });
    }
}

pub fn delete(self: *TextBuffer, pos: usize, len: usize) Allocator.Error![]u8 {
    const deleted = try self.slice(self.allocator, pos, pos + len);

    var remaining = len;
    var offset: usize = 0;
    var i: usize = 0;

    // Find starting piece
    while (i < self.pieces.items.len) {
        const p = self.pieces.items[i];
        if (offset + p.len > pos) break;
        offset += p.len;
        i += 1;
    }

    while (remaining > 0 and i < self.pieces.items.len) {
        const p = self.pieces.items[i];
        const local = pos + (len - remaining) - offset;
        const avail = p.len - local;

        if (local == 0 and remaining >= p.len) {
            // Remove entire piece
            _ = self.pieces.orderedRemove(i);
            remaining -= p.len;
            // don't increment i, next piece shifts into position
        } else if (local == 0) {
            // Trim from start
            self.pieces.items[i] = .{
                .source = p.source,
                .start = p.start + remaining,
                .len = p.len - remaining,
            };
            remaining = 0;
        } else if (remaining >= avail) {
            // Trim from end
            self.pieces.items[i] = .{
                .source = p.source,
                .start = p.start,
                .len = local,
            };
            remaining -= avail;
            offset += local;
            i += 1;
        } else {
            // Split: remove middle portion
            const right = Piece{
                .source = p.source,
                .start = p.start + local + remaining,
                .len = p.len - local - remaining,
            };
            self.pieces.items[i] = .{
                .source = p.source,
                .start = p.start,
                .len = local,
            };
            try self.pieces.insert(self.allocator, i + 1, right);
            remaining = 0;
        }
    }

    return deleted;
}

pub fn contents(self: *const TextBuffer, allocator: Allocator) Allocator.Error![]u8 {
    return self.slice(allocator, 0, self.totalLen());
}

pub fn slice(self: *const TextBuffer, allocator: Allocator, start: usize, end: usize) Allocator.Error![]u8 {
    const len = end - start;
    var result = try allocator.alloc(u8, len);
    var written: usize = 0;
    var offset: usize = 0;

    for (self.pieces.items) |p| {
        const piece_end = offset + p.len;
        if (piece_end <= start) {
            offset = piece_end;
            continue;
        }
        if (offset >= end) break;

        const buf = self.pieceSlice(p);
        const local_start = if (start > offset) start - offset else 0;
        const local_end = if (end < piece_end) end - offset else p.len;
        const chunk = buf[local_start..local_end];
        @memcpy(result[written..][0..chunk.len], chunk);
        written += chunk.len;
        offset = piece_end;
    }

    return result;
}

pub fn lineCount(self: *const TextBuffer) usize {
    const total = self.totalLen();
    if (total == 0) return 0;

    var count: usize = 1;
    var offset: usize = 0;
    for (self.pieces.items) |p| {
        const buf = self.pieceSlice(p);
        for (buf) |c| {
            if (c == '\n') count += 1;
            offset += 1;
        }
    }
    return count;
}

pub fn lineAt(self: *const TextBuffer, line_num: usize) Allocator.Error![]u8 {
    // Find byte range for the line
    var current_line: usize = 0;
    var line_start: usize = 0;
    var pos: usize = 0;

    // Find line_start
    for (self.pieces.items) |p| {
        const buf = self.pieceSlice(p);
        for (buf) |c| {
            if (current_line == line_num) break;
            if (c == '\n') {
                current_line += 1;
                line_start = pos + 1;
            }
            pos += 1;
        }
        if (current_line == line_num) break;
    }

    // Find line_end (next \n or end of text)
    var line_end = line_start;
    current_line = 0;
    pos = 0;
    var found_start = false;
    for (self.pieces.items) |p| {
        const buf = self.pieceSlice(p);
        for (buf) |c| {
            if (pos == line_start) found_start = true;
            if (found_start) {
                if (c == '\n') {
                    line_end = pos;
                    return self.slice(self.allocator, line_start, line_end);
                }
            }
            pos += 1;
        }
    }
    // No trailing newline — line goes to end
    line_end = self.totalLen();
    return self.slice(self.allocator, line_start, line_end);
}

pub fn positionToLineCol(self: *const TextBuffer, pos: usize) LineCol {
    var line: usize = 0;
    var col: usize = 0;
    var offset: usize = 0;

    for (self.pieces.items) |p| {
        const buf = self.pieceSlice(p);
        for (buf) |c| {
            if (offset == pos) return .{ .line = line, .col = col };
            if (c == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
            offset += 1;
        }
    }
    return .{ .line = line, .col = col };
}

pub fn lineColToPosition(self: *const TextBuffer, line: usize, col: usize) usize {
    var current_line: usize = 0;
    var current_col: usize = 0;
    var offset: usize = 0;

    for (self.pieces.items) |p| {
        const buf = self.pieceSlice(p);
        for (buf) |_| {
            if (current_line == line and current_col == col) return offset;
            if (self.byteAt(offset) == '\n') {
                current_line += 1;
                current_col = 0;
            } else {
                current_col += 1;
            }
            offset += 1;
        }
    }
    return offset;
}

fn byteAt(self: *const TextBuffer, pos: usize) u8 {
    var offset: usize = 0;
    for (self.pieces.items) |p| {
        if (pos < offset + p.len) {
            const buf = self.pieceSlice(p);
            return buf[pos - offset];
        }
        offset += p.len;
    }
    unreachable;
}

// --- Tests ---

const testing = std.testing;

test "init empty" {
    var buf = try TextBuffer.init(testing.allocator, "");
    defer buf.deinit();
    try testing.expectEqual(@as(usize, 0), buf.lineCount());
}

test "init with content" {
    var buf = try TextBuffer.init(testing.allocator, "hello\nworld\n");
    defer buf.deinit();
    try testing.expectEqual(@as(usize, 3), buf.lineCount());
    const line0 = try buf.lineAt(0);
    defer testing.allocator.free(line0);
    try testing.expectEqualStrings("hello", line0);
}

test "insert at beginning" {
    var buf = try TextBuffer.init(testing.allocator, "world");
    defer buf.deinit();
    try buf.insert(0, "hello ");
    const c = try buf.contents(testing.allocator);
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("hello world", c);
}

test "insert in middle" {
    var buf = try TextBuffer.init(testing.allocator, "helo");
    defer buf.deinit();
    try buf.insert(2, "l");
    const c = try buf.contents(testing.allocator);
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("hello", c);
}

test "insert at end" {
    var buf = try TextBuffer.init(testing.allocator, "hello");
    defer buf.deinit();
    try buf.insert(5, " world");
    const c = try buf.contents(testing.allocator);
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("hello world", c);
}

test "delete from beginning" {
    var buf = try TextBuffer.init(testing.allocator, "hello world");
    defer buf.deinit();
    const deleted = try buf.delete(0, 6);
    defer testing.allocator.free(deleted);
    try testing.expectEqualStrings("hello ", deleted);
    const c = try buf.contents(testing.allocator);
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("world", c);
}

test "delete in middle" {
    var buf = try TextBuffer.init(testing.allocator, "helllo");
    defer buf.deinit();
    const deleted = try buf.delete(2, 1);
    defer testing.allocator.free(deleted);
    const c = try buf.contents(testing.allocator);
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("hello", c);
}

test "lineCount with newlines" {
    var buf = try TextBuffer.init(testing.allocator, "a\nb\nc");
    defer buf.deinit();
    try testing.expectEqual(@as(usize, 3), buf.lineCount());
}

test "lineAt multiline" {
    var buf = try TextBuffer.init(testing.allocator, "line1\nline2\nline3");
    defer buf.deinit();

    const l0 = try buf.lineAt(0);
    defer testing.allocator.free(l0);
    try testing.expectEqualStrings("line1", l0);

    const l1 = try buf.lineAt(1);
    defer testing.allocator.free(l1);
    try testing.expectEqualStrings("line2", l1);

    const l2 = try buf.lineAt(2);
    defer testing.allocator.free(l2);
    try testing.expectEqualStrings("line3", l2);
}

test "positionToLineCol and lineColToPosition roundtrip" {
    var buf = try TextBuffer.init(testing.allocator, "ab\ncd\nef");
    defer buf.deinit();

    const lc = buf.positionToLineCol(3);
    try testing.expectEqual(@as(usize, 1), lc.line);
    try testing.expectEqual(@as(usize, 0), lc.col);

    const pos = buf.lineColToPosition(1, 0);
    try testing.expectEqual(@as(usize, 3), pos);
}

test "slice" {
    var buf = try TextBuffer.init(testing.allocator, "hello world");
    defer buf.deinit();
    const s = try buf.slice(testing.allocator, 6, 11);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("world", s);
}

test "insert newline increases line count" {
    var buf = try TextBuffer.init(testing.allocator, "ab");
    defer buf.deinit();
    try buf.insert(1, "\n");
    try testing.expectEqual(@as(usize, 2), buf.lineCount());
}

test "totalLen" {
    var buf = try TextBuffer.init(testing.allocator, "hello");
    defer buf.deinit();
    try testing.expectEqual(@as(usize, 5), buf.totalLen());
    try buf.insert(5, " world");
    try testing.expectEqual(@as(usize, 11), buf.totalLen());
}
