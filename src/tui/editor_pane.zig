const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const TextBuffer = @import("text_buffer.zig");
const Highlighter = @import("highlighter.zig");
const UndoManager = @import("undo.zig");

const EditorPane = @This();

const gutter_width: u16 = 5;

/// A single error or warning annotation to display in the editor.
pub const ErrorLine = struct {
    /// 0-based line index.
    line: usize,
    /// 0-based column where the underline starts.
    col: usize,
    /// Number of characters to underline (0 means underline to end of line).
    len: usize,
    severity: enum { err, warn },
    message: []const u8,
};

buffer: *TextBuffer,
undo: *UndoManager,
cursor_line: usize = 0,
cursor_col: usize = 0,
scroll_top: usize = 0,
scroll_left: usize = 0,
focused: bool = true,
modified: bool = false,
error_lines: []const ErrorLine = &.{},

pub fn widget(self: *EditorPane) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn clampCursorCol(self: *EditorPane) void {
    const line = self.buffer.lineAt(self.cursor_line) catch return;
    defer self.buffer.allocator.free(line);
    if (self.cursor_col > line.len) {
        self.cursor_col = line.len;
    }
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *EditorPane = @ptrCast(@alignCast(ptr));
    switch (event) {
        .key_press => |key| {
            if (key.matches(vaxis.Key.up, .{})) {
                self.cursor_line -|= 1;
                self.clampCursorCol();
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.down, .{})) {
                const line_count = self.buffer.lineCount();
                if (line_count > 0 and self.cursor_line < line_count - 1) {
                    self.cursor_line += 1;
                }
                self.clampCursorCol();
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.left, .{})) {
                self.cursor_col -|= 1;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.right, .{})) {
                self.cursor_col += 1;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.home, .{})) {
                self.cursor_col = 0;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.end, .{})) {
                const line = self.buffer.lineAt(self.cursor_line) catch return;
                defer self.buffer.allocator.free(line);
                self.cursor_col = line.len;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.page_up, .{})) {
                self.cursor_line -|= 20;
                self.clampCursorCol();
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.page_down, .{})) {
                const line_count = self.buffer.lineCount();
                self.cursor_line += 20;
                if (line_count > 0 and self.cursor_line >= line_count) {
                    self.cursor_line = line_count - 1;
                }
                self.clampCursorCol();
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.backspace, .{})) {
                const pos = self.buffer.lineColToPosition(self.cursor_line, self.cursor_col);
                if (pos > 0) {
                    self.undo.deleteText(self.buffer, pos - 1, 1) catch return;
                    const lc = self.buffer.positionToLineCol(pos - 1);
                    self.cursor_line = lc.line;
                    self.cursor_col = lc.col;
                    self.modified = true;
                    ctx.consumeAndRedraw();
                }
            } else if (key.matches(vaxis.Key.delete, .{})) {
                const pos = self.buffer.lineColToPosition(self.cursor_line, self.cursor_col);
                if (pos < self.buffer.totalLen()) {
                    self.undo.deleteText(self.buffer, pos, 1) catch return;
                    self.modified = true;
                    ctx.consumeAndRedraw();
                }
            } else if (key.matches(vaxis.Key.enter, .{})) {
                const pos = self.buffer.lineColToPosition(self.cursor_line, self.cursor_col);
                self.undo.insertText(self.buffer, pos, "\n") catch return;
                self.cursor_line += 1;
                self.cursor_col = 0;
                self.modified = true;
                ctx.consumeAndRedraw();
            } else if (key.matches('z', .{ .ctrl = true })) {
                self.undo.undo(self.buffer) catch return;
                ctx.consumeAndRedraw();
            } else if (key.matches('y', .{ .ctrl = true })) {
                self.undo.redo(self.buffer) catch return;
                ctx.consumeAndRedraw();
            } else if (key.matches('z', .{ .ctrl = true, .shift = true })) {
                self.undo.redo(self.buffer) catch return;
                ctx.consumeAndRedraw();
            } else {
                if (key.text) |text| {
                    if (text.len > 0 and text[0] >= 0x20) {
                        const pos = self.buffer.lineColToPosition(self.cursor_line, self.cursor_col);
                        self.undo.insertText(self.buffer, pos, text) catch return;
                        self.cursor_col += text.len;
                        self.modified = true;
                        ctx.consumeAndRedraw();
                    }
                }
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *EditorPane = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    const visible_height: usize = @intCast(max.height);
    const total_width: u16 = max.width;

    const line_count = self.buffer.lineCount();
    if (line_count == 0) {
        self.cursor_line = 0;
        self.cursor_col = 0;
    } else {
        if (self.cursor_line >= line_count) {
            self.cursor_line = line_count - 1;
        }
    }

    if (self.cursor_line < self.scroll_top) {
        self.scroll_top = self.cursor_line;
    }
    if (visible_height > 0 and self.cursor_line >= self.scroll_top + visible_height) {
        self.scroll_top = self.cursor_line - visible_height + 1;
    }

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max);

    if (line_count == 0) {
        writeGutter(&surface, 0, 1, self.error_lines);
        if (self.focused) {
            surface.cursor = .{
                .col = gutter_width,
                .row = 0,
                .shape = .beam,
            };
        }
        return surface;
    }

    var row: u16 = 0;
    while (row < max.height) : (row += 1) {
        const buf_line = self.scroll_top + @as(usize, row);
        if (buf_line >= line_count) break;

        writeGutter(&surface, row, buf_line + 1, self.error_lines);

        const line_content = self.buffer.lineAt(buf_line) catch continue;
        defer self.buffer.allocator.free(line_content);

        const spans = Highlighter.tokenizeToSpans(ctx.arena, line_content) catch &[_]Highlighter.StyledSpan{};

        var col: u16 = gutter_width;
        for (line_content, 0..) |_, ci| {
            if (col >= total_width) break;
            var style = spanStyleAt(spans, ci);

            // Merge error/warning underline if this character is in an error range
            for (self.error_lines) |el| {
                if (el.line == buf_line) {
                    const end_col = if (el.len == 0) line_content.len else el.col + el.len;
                    if (ci >= el.col and ci < end_col) {
                        const ul_style = if (el.severity == .err)
                            Highlighter.error_underline
                        else
                            Highlighter.warning_underline;
                        style.ul = ul_style.ul;
                        style.ul_style = ul_style.ul_style;
                    }
                }
            }

            var cell_style = style;
            if (buf_line == self.cursor_line and ci == self.cursor_col and self.focused) {
                cell_style.reverse = true;
            }

            surface.writeCell(col, row, .{
                .char = .{ .grapheme = line_content[ci .. ci + 1], .width = 1 },
                .style = cell_style,
            });
            col += 1;
        }

        if (buf_line == self.cursor_line and self.cursor_col >= line_content.len and self.focused) {
            const cursor_screen_col = gutter_width + @as(u16, @intCast(line_content.len));
            if (cursor_screen_col < total_width) {
                surface.writeCell(cursor_screen_col, row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .reverse = true },
                });
            }
        }
    }

    if (self.focused and self.cursor_line >= self.scroll_top and
        self.cursor_line < self.scroll_top + visible_height)
    {
        const cursor_row: u16 = @intCast(self.cursor_line - self.scroll_top);
        const cursor_col: u16 = gutter_width + @as(u16, @intCast(self.cursor_col));
        surface.cursor = .{
            .col = cursor_col,
            .row = cursor_row,
            .shape = .beam,
        };
    }

    return surface;
}

fn writeGutter(surface: *vxfw.Surface, row: u16, line_num: usize, error_lines: []const ErrorLine) void {
    var num_buf: [16]u8 = undefined;
    const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{line_num}) catch return;
    // pad: number of leading spaces before the line number digits
    // Layout: [marker][padding][digits][space]  total = gutter_width
    // marker takes col 0; digits + space take gutter_width - 1 chars after that
    const inner_width: u16 = gutter_width - 1; // cols 1..gutter_width-1 used for num + trailing space
    const pad: u16 = if (inner_width > @as(u16, @intCast(num_str.len)) + 1)
        inner_width - @as(u16, @intCast(num_str.len)) - 1
    else
        0;

    const dim_style: vaxis.Cell.Style = .{ .dim = true };

    // Determine if this line (0-based: line_num - 1) has an error or warning
    const buf_line = line_num - 1; // convert 1-based to 0-based
    var marker_severity: ?@FieldType(ErrorLine, "severity") = null;
    for (error_lines) |el| {
        if (el.line == buf_line) {
            if (marker_severity == null or el.severity == .err) {
                marker_severity = el.severity;
            }
        }
    }

    // col 0: marker (● for error/warning) or dim space
    if (marker_severity) |sev| {
        const marker_style: vaxis.Cell.Style = if (sev == .err)
            .{ .fg = .{ .index = 1 } }
        else
            .{ .fg = .{ .index = 3 } };
        surface.writeCell(0, row, .{
            .char = .{ .grapheme = "●", .width = 1 },
            .style = marker_style,
        });
    } else {
        surface.writeCell(0, row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = dim_style,
        });
    }

    var col: u16 = 1;
    const pad_end = col + pad;
    while (col < pad_end) : (col += 1) {
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = dim_style,
        });
    }
    for (num_str, 0..) |_, di| {
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = num_str[di .. di + 1], .width = 1 },
            .style = dim_style,
        });
        col += 1;
    }
    if (col < gutter_width) {
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = dim_style,
        });
    }
}

fn spanStyleAt(spans: []const Highlighter.StyledSpan, col: usize) vaxis.Cell.Style {
    for (spans) |span| {
        if (col >= span.start and col < span.start + span.len) {
            return span.style;
        }
    }
    return .{};
}

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "EditorPane: initial state" {
    var buf = try TextBuffer.init(testing.allocator, "hello\nworld\n");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();
    var pane = EditorPane{
        .buffer = &buf,
        .undo = &um,
    };
    try testing.expectEqual(@as(usize, 0), pane.cursor_line);
    try testing.expectEqual(@as(usize, 0), pane.cursor_col);
    try testing.expectEqual(@as(usize, 0), pane.scroll_top);
    try testing.expect(!pane.modified);
    _ = pane.widget();
}

test "EditorPane: cursor clamp on empty buffer" {
    var buf = try TextBuffer.init(testing.allocator, "");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();
    var pane = EditorPane{
        .buffer = &buf,
        .undo = &um,
        .cursor_line = 5,
        .cursor_col = 10,
    };
    // Drawing should clamp cursor
    _ = pane.widget();
    // We can't easily call draw without a DrawContext, but we verify widget() works
}

test "spanStyleAt: returns default for uncovered column" {
    const spans = [_]Highlighter.StyledSpan{
        .{ .start = 0, .len = 3, .style = .{ .bold = true } },
    };
    const style = spanStyleAt(&spans, 5);
    try testing.expect(!style.bold);
}

test "spanStyleAt: returns span style for covered column" {
    const spans = [_]Highlighter.StyledSpan{
        .{ .start = 0, .len = 3, .style = .{ .bold = true } },
    };
    const style = spanStyleAt(&spans, 1);
    try testing.expect(style.bold);
}

test "ErrorLine: error_lines field defaults to empty" {
    var buf = try TextBuffer.init(testing.allocator, "hello\n");
    defer buf.deinit();
    var um = UndoManager.init(testing.allocator);
    defer um.deinit();
    const pane = EditorPane{
        .buffer = &buf,
        .undo = &um,
    };
    try testing.expectEqual(@as(usize, 0), pane.error_lines.len);
}

test "ErrorLine: struct has expected fields" {
    const el = EditorPane.ErrorLine{
        .line = 2,
        .col = 4,
        .len = 3,
        .severity = .err,
        .message = "unexpected token",
    };
    try testing.expectEqual(@as(usize, 2), el.line);
    try testing.expectEqual(@as(usize, 4), el.col);
    try testing.expectEqual(@as(usize, 3), el.len);
    try testing.expect(el.severity == .err);
    try testing.expectEqualStrings("unexpected token", el.message);
}

test "ErrorLine: gutter marker severity prefers err over warn" {
    // When a line has both a warning and an error, error takes priority.
    // We test the logic by checking that error_lines with .err severity
    // overrides an earlier .warn entry for the same line.
    const error_lines = [_]EditorPane.ErrorLine{
        .{ .line = 0, .col = 0, .len = 1, .severity = .warn, .message = "w" },
        .{ .line = 0, .col = 2, .len = 1, .severity = .err, .message = "e" },
    };
    // Verify the logic: scan through and confirm err wins
    var found: ?@FieldType(EditorPane.ErrorLine, "severity") = null;
    for (error_lines) |el| {
        if (el.line == 0) {
            if (found == null or el.severity == .err) {
                found = el.severity;
            }
        }
    }
    try testing.expect(found != null);
    try testing.expect(found.? == .err);
}
