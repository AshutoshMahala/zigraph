const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const TextBuffer = @import("text_buffer.zig");
const Highlighter = @import("highlighter.zig");

const EditorPane = @This();

const gutter_width: u16 = 5;

buffer: *TextBuffer,
cursor_line: usize = 0,
cursor_col: usize = 0,
scroll_top: usize = 0,
scroll_left: usize = 0,
focused: bool = true,

pub fn widget(self: *EditorPane) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *EditorPane = @ptrCast(@alignCast(ptr));
    switch (event) {
        .key_press => |key| {
            if (key.matches(vaxis.Key.up, .{})) {
                self.cursor_line -|= 1;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.down, .{})) {
                const line_count = self.buffer.lineCount();
                if (line_count > 0 and self.cursor_line < line_count - 1) {
                    self.cursor_line += 1;
                }
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
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.page_down, .{})) {
                const line_count = self.buffer.lineCount();
                self.cursor_line += 20;
                if (line_count > 0 and self.cursor_line >= line_count) {
                    self.cursor_line = line_count - 1;
                }
                ctx.consumeAndRedraw();
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

    // Clamp cursor to valid range
    const line_count = self.buffer.lineCount();
    if (line_count == 0) {
        self.cursor_line = 0;
        self.cursor_col = 0;
    } else {
        if (self.cursor_line >= line_count) {
            self.cursor_line = line_count - 1;
        }
    }

    // Ensure scroll_top keeps cursor visible
    if (self.cursor_line < self.scroll_top) {
        self.scroll_top = self.cursor_line;
    }
    if (visible_height > 0 and self.cursor_line >= self.scroll_top + visible_height) {
        self.scroll_top = self.cursor_line - visible_height + 1;
    }

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max);

    if (line_count == 0) {
        // Empty buffer — just show gutter for line 1
        writeGutter(&surface, 0, 1);
        if (self.focused) {
            surface.cursor = .{
                .col = gutter_width,
                .row = 0,
                .shape = .beam,
            };
        }
        return surface;
    }

    const text_width: usize = if (total_width > gutter_width) total_width - gutter_width else 0;
    _ = text_width;

    var row: u16 = 0;
    while (row < max.height) : (row += 1) {
        const buf_line = self.scroll_top + @as(usize, row);
        if (buf_line >= line_count) break;

        // Render gutter (line number, 1-based, right-aligned)
        writeGutter(&surface, row, buf_line + 1);

        // Get line content
        const line_content = self.buffer.lineAt(buf_line) catch continue;
        defer self.buffer.allocator.free(line_content);

        // Get syntax spans for this line
        const spans = Highlighter.tokenizeToSpans(ctx.arena, line_content) catch &[_]Highlighter.StyledSpan{};

        // Write each character with syntax style
        var col: u16 = gutter_width;
        for (line_content, 0..) |ch, ci| {
            if (col >= total_width) break;
            const style = spanStyleAt(spans, ci);

            // Apply cursor reverse if this is the cursor position
            var cell_style = style;
            if (buf_line == self.cursor_line and ci == self.cursor_col and self.focused) {
                cell_style.reverse = true;
            }

            surface.writeCell(col, row, .{
                .char = .{ .grapheme = line_content[ci .. ci + 1], .width = 1 },
                .style = cell_style,
            });
            _ = ch;
            col += 1;
        }

        // If cursor is at end of line, show reverse space block
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

    // Set terminal cursor position
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

fn writeGutter(surface: *vxfw.Surface, row: u16, line_num: usize) void {
    // Format line number right-aligned in gutter_width - 1 chars, then a space
    var num_buf: [16]u8 = undefined;
    const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{line_num}) catch return;
    const pad = if (gutter_width > num_str.len + 1) gutter_width - @as(u16, @intCast(num_str.len)) - 1 else 0;

    const dim_style: vaxis.Cell.Style = .{ .dim = true };

    var col: u16 = 0;
    // Write padding spaces
    while (col < pad) : (col += 1) {
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = dim_style,
        });
    }
    // Write digits
    for (num_str) |ch| {
        _ = ch;
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = num_str[col - pad .. col - pad + 1], .width = 1 },
            .style = dim_style,
        });
        col += 1;
    }
    // Write trailing space
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
    var pane = EditorPane{
        .buffer = &buf,
    };
    try testing.expectEqual(@as(usize, 0), pane.cursor_line);
    try testing.expectEqual(@as(usize, 0), pane.cursor_col);
    try testing.expectEqual(@as(usize, 0), pane.scroll_top);
    _ = pane.widget();
}

test "EditorPane: cursor clamp on empty buffer" {
    var buf = try TextBuffer.init(testing.allocator, "");
    defer buf.deinit();
    var pane = EditorPane{
        .buffer = &buf,
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
