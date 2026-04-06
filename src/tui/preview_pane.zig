const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const zigraph = @import("zigraph");
const dsl = @import("dsl");

const PreviewPane = @This();

allocator: std.mem.Allocator,
rendered_output: ?[]const u8 = null,
render_width: usize = 0,
render_height: usize = 0,
selected_node: ?usize = null,
selected_edge: ?usize = null,
scroll_x: usize = 0,
scroll_y: usize = 0,
focused: bool = false,
error_message: ?[]const u8 = null,

pub fn widget(self: *PreviewPane) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

pub fn renderFromSource(self: *PreviewPane, allocator: std.mem.Allocator, source: []const u8) void {
    // Free previous render
    if (self.rendered_output) |old| allocator.free(old);
    self.rendered_output = null;
    if (self.error_message) |old| allocator.free(old);
    self.error_message = null;
    self.render_width = 0;
    self.render_height = 0;

    if (source.len == 0) return;

    // Parse
    var result = dsl.parseAndBuild(allocator, source) catch |err| {
        self.error_message = std.fmt.allocPrint(allocator, "Parse error: {s}", .{@errorName(err)}) catch null;
        return;
    };
    defer result.deinit();

    if (result.hasErrors()) {
        // Build an error message from the first error
        if (result.err_list.errors.items.len > 0) {
            const first = result.err_list.errors.items[0];
            self.error_message = std.fmt.allocPrint(allocator, "{d}:{d}: {s}", .{
                first.loc.line, first.loc.col, first.message,
            }) catch null;
        }
        return;
    }

    if (result.graphs.len == 0) {
        self.error_message = std.fmt.allocPrint(allocator, "No graphs found in source", .{}) catch null;
        return;
    }

    // Layout
    var ir = zigraph.layout(&result.graphs[0].graph, allocator, result.graphs[0].config) catch |err| {
        self.error_message = std.fmt.allocPrint(allocator, "Layout error: {s}", .{@errorName(err)}) catch null;
        return;
    };
    defer ir.deinit();

    // Apply direction
    dsl.direction.applyDirection(&ir, result.graphs[0].direction);

    // Render to string
    const output = zigraph.terminal.render(&ir, allocator) catch |err| {
        self.error_message = std.fmt.allocPrint(allocator, "Render error: {s}", .{@errorName(err)}) catch null;
        return;
    };
    self.rendered_output = output;

    // Compute dimensions from the output
    var width: usize = 0;
    var height: usize = 0;
    var line_len: usize = 0;
    for (output) |ch| {
        if (ch == '\n') {
            if (line_len > width) width = line_len;
            height += 1;
            line_len = 0;
        } else {
            line_len += 1;
        }
    }
    if (line_len > 0) {
        if (line_len > width) width = line_len;
        height += 1;
    }
    self.render_width = width;
    self.render_height = height;
}

pub fn destroy(self: *PreviewPane) void {
    if (self.rendered_output) |old| self.allocator.free(old);
    if (self.error_message) |old| self.allocator.free(old);
    self.allocator.destroy(self);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *PreviewPane = @ptrCast(@alignCast(ptr));
    switch (event) {
        .key_press => |key| {
            if (key.matches(vaxis.Key.escape, .{})) {
                self.selected_node = null;
                self.selected_edge = null;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.up, .{})) {
                self.scroll_y -|= 1;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.down, .{})) {
                if (self.render_height > 0) {
                    self.scroll_y += 1;
                }
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.left, .{})) {
                self.scroll_x -|= 1;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.right, .{})) {
                self.scroll_x += 1;
                ctx.consumeAndRedraw();
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *PreviewPane = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max);

    // Draw border/header
    const header = if (self.focused) "[ Preview (focused) ]" else "[ Preview ]";
    for (header, 0..) |_, i| {
        const col: u16 = @intCast(i);
        if (col >= max.width) break;
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = header[i .. i + 1], .width = 1 },
            .style = .{ .bold = self.focused },
        });
    }

    const content_start_row: u16 = 1;
    const available_height: usize = if (max.height > content_start_row)
        @as(usize, max.height - content_start_row)
    else
        0;

    if (available_height == 0) return surface;

    // Show error if present
    if (self.error_message) |msg| {
        const err_style: vaxis.Cell.Style = .{
            .fg = .{ .index = 1 }, // red
        };
        var col: u16 = 0;
        for (msg, 0..) |_, ci| {
            if (col >= max.width) break;
            surface.writeCell(col, content_start_row, .{
                .char = .{ .grapheme = msg[ci .. ci + 1], .width = 1 },
                .style = err_style,
            });
            col += 1;
        }
        return surface;
    }

    // Show rendered output
    const output = self.rendered_output orelse {
        const placeholder = "[no preview]";
        for (placeholder, 0..) |_, i| {
            const col: u16 = @intCast(i);
            if (col >= max.width) break;
            surface.writeCell(col, content_start_row, .{
                .char = .{ .grapheme = placeholder[i .. i + 1], .width = 1 },
                .style = .{ .dim = true },
            });
        }
        return surface;
    };

    // Render line by line with scroll offset
    var line_idx: usize = 0;
    var pos: usize = 0;
    while (pos < output.len) {
        // Find end of line
        var line_end = pos;
        while (line_end < output.len and output[line_end] != '\n') {
            line_end += 1;
        }

        if (line_idx >= self.scroll_y) {
            const screen_row = line_idx - self.scroll_y;
            if (screen_row >= available_height) break;

            const row: u16 = content_start_row + @as(u16, @intCast(screen_row));
            var col: u16 = 0;
            const line = output[pos..line_end];

            var char_idx: usize = self.scroll_x;
            while (char_idx < line.len) {
                if (col >= max.width) break;

                // Handle UTF-8: for now, write byte-by-byte (ASCII-safe for box drawing)
                const byte = line[char_idx];
                if (byte < 0x80) {
                    // ASCII
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = line[char_idx .. char_idx + 1], .width = 1 },
                        .style = .{},
                    });
                    col += 1;
                    char_idx += 1;
                } else {
                    // Multi-byte UTF-8: determine length
                    const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
                    const end = @min(char_idx + seq_len, line.len);
                    const grapheme = line[char_idx..end];
                    // Box-drawing characters are typically double-width visually but
                    // we'll treat them as width 1 in the terminal cell grid
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = grapheme, .width = 1 },
                        .style = .{},
                    });
                    col += 1;
                    char_idx = end;
                }
            }
        }

        line_idx += 1;
        pos = if (line_end < output.len) line_end + 1 else line_end;
    }

    return surface;
}

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "PreviewPane: initial state" {
    const allocator = testing.allocator;
    const pane = try allocator.create(PreviewPane);
    pane.* = .{ .allocator = allocator };
    defer pane.destroy();

    try testing.expect(pane.rendered_output == null);
    try testing.expect(pane.error_message == null);
    try testing.expect(!pane.focused);
    try testing.expect(pane.selected_node == null);
    try testing.expect(pane.selected_edge == null);
    _ = pane.widget();
}

test "PreviewPane: renderFromSource with valid DSL" {
    const allocator = testing.allocator;
    const pane = try allocator.create(PreviewPane);
    pane.* = .{ .allocator = allocator };
    defer pane.destroy();

    pane.renderFromSource(allocator, "A -> B");

    try testing.expect(pane.rendered_output != null);
    try testing.expect(pane.error_message == null);
    try testing.expect(pane.render_width > 0);
    try testing.expect(pane.render_height > 0);
}

test "PreviewPane: renderFromSource with empty source" {
    const allocator = testing.allocator;
    const pane = try allocator.create(PreviewPane);
    pane.* = .{ .allocator = allocator };
    defer pane.destroy();

    pane.renderFromSource(allocator, "");

    try testing.expect(pane.rendered_output == null);
    try testing.expect(pane.error_message == null);
}

test "PreviewPane: renderFromSource with invalid DSL shows error" {
    const allocator = testing.allocator;
    const pane = try allocator.create(PreviewPane);
    pane.* = .{ .allocator = allocator };
    defer pane.destroy();

    pane.renderFromSource(allocator, "@invalid_directive foo");

    // Should either have an error message or null output
    try testing.expect(pane.rendered_output == null);
}

test "PreviewPane: re-render replaces previous output" {
    const allocator = testing.allocator;
    const pane = try allocator.create(PreviewPane);
    pane.* = .{ .allocator = allocator };
    defer pane.destroy();

    pane.renderFromSource(allocator, "A -> B");
    try testing.expect(pane.rendered_output != null);

    pane.renderFromSource(allocator, "X -> Y -> Z");
    try testing.expect(pane.rendered_output != null);
}
