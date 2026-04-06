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
pinned_positions: std.AutoHashMapUnmanaged(usize, [2]i32) = .{},
drag_active: bool = false,
drag_node: ?usize = null,
drag_start_x: i16 = 0,
drag_start_y: i16 = 0,

pub fn widget(self: *PreviewPane) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

pub fn renderFromSource(self: *PreviewPane, allocator: std.mem.Allocator, source: []const u8) void {
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

pub fn nudgeSelected(self: *PreviewPane, dx: i32, dy: i32) void {
    if (self.selected_node) |node_id| {
        const entry = self.pinned_positions.getOrPut(self.allocator, node_id) catch return;
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ 0, 0 };
        }
        entry.value_ptr[0] += dx;
        entry.value_ptr[1] += dy;
    }
}

pub fn togglePin(self: *PreviewPane) void {
    if (self.selected_node) |node_id| {
        if (self.pinned_positions.contains(node_id)) {
            _ = self.pinned_positions.remove(node_id);
        } else {
            self.pinned_positions.put(self.allocator, node_id, .{ 0, 0 }) catch return;
        }
    }
}

pub fn isPinned(self: *const PreviewPane, node_id: usize) bool {
    return self.pinned_positions.contains(node_id);
}

pub fn destroy(self: *PreviewPane) void {
    if (self.rendered_output) |old| self.allocator.free(old);
    if (self.error_message) |old| self.allocator.free(old);
    self.pinned_positions.deinit(self.allocator);
    self.allocator.destroy(self);
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *PreviewPane = @ptrCast(@alignCast(ptr));
    switch (event) {
        .key_press => |key| {
            if (key.matches(vaxis.Key.escape, .{})) {
                self.selected_node = null;
                self.selected_edge = null;
                self.drag_active = false;
                self.drag_node = null;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.up, .{})) {
                if (self.selected_node != null) {
                    self.nudgeSelected(0, -1);
                } else {
                    self.scroll_y -|= 1;
                }
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.down, .{})) {
                if (self.selected_node != null) {
                    self.nudgeSelected(0, 1);
                } else if (self.render_height > 0) {
                    self.scroll_y += 1;
                }
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.left, .{})) {
                if (self.selected_node != null) {
                    self.nudgeSelected(-1, 0);
                } else {
                    self.scroll_x -|= 1;
                }
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.right, .{})) {
                if (self.selected_node != null) {
                    self.nudgeSelected(1, 0);
                } else {
                    self.scroll_x += 1;
                }
                ctx.consumeAndRedraw();
            } else if (key.matches('p', .{})) {
                self.togglePin();
                ctx.consumeAndRedraw();
            }
        },
        .mouse => |mouse| {
            switch (mouse.type) {
                .press => {
                    // Start drag on mouse press (basic infrastructure)
                    if (self.selected_node) |node_id| {
                        self.drag_active = true;
                        self.drag_node = node_id;
                        self.drag_start_x = mouse.col;
                        self.drag_start_y = mouse.row;
                        ctx.consumeAndRedraw();
                    }
                },
                .release => {
                    // Commit drag: pin the node at its current offset
                    if (self.drag_active) {
                        if (self.drag_node) |node_id| {
                            if (!self.pinned_positions.contains(node_id)) {
                                self.pinned_positions.put(self.allocator, node_id, .{ 0, 0 }) catch {}; // OOM: skip pin on drag release
                            }
                        }
                        self.drag_active = false;
                        self.drag_node = null;
                        ctx.consumeAndRedraw();
                    }
                },
                .drag => {
                    // Update offset during drag
                    if (self.drag_active) {
                        if (self.drag_node) |node_id| {
                            const dx: i32 = @as(i32, mouse.col) - @as(i32, self.drag_start_x);
                            const dy: i32 = @as(i32, mouse.row) - @as(i32, self.drag_start_y);
                            const entry = self.pinned_positions.getOrPut(self.allocator, node_id) catch return;
                            if (!entry.found_existing) {
                                entry.value_ptr.* = .{ 0, 0 };
                            }
                            entry.value_ptr[0] += dx;
                            entry.value_ptr[1] += dy;
                            self.drag_start_x = mouse.col;
                            self.drag_start_y = mouse.row;
                            ctx.consumeAndRedraw();
                        }
                    }
                },
                .motion => {},
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *PreviewPane = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max);

    // Draw border/header with optional node/pin info
    var header_buf: [128]u8 = undefined;
    const header: []const u8 = blk: {
        if (self.selected_node) |node_id| {
            const pinned = self.isPinned(node_id);
            if (pinned) {
                break :blk std.fmt.bufPrint(&header_buf, "[ Preview | Node: {d} [pinned] ]", .{node_id}) catch "[ Preview ]";
            } else {
                break :blk std.fmt.bufPrint(&header_buf, "[ Preview | Node: {d} ]", .{node_id}) catch "[ Preview ]";
            }
        } else if (self.focused) {
            break :blk "[ Preview (focused) ]";
        } else {
            break :blk "[ Preview ]";
        }
    };
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
    try testing.expect(!pane.drag_active);
    try testing.expect(pane.drag_node == null);
    _ = pane.widget();
}

test "PreviewPane: nudge pins and moves selected node" {
    const allocator = testing.allocator;
    const pane = try allocator.create(PreviewPane);
    pane.* = .{ .allocator = allocator };
    defer pane.destroy();

    // No selected node — nudge is a no-op
    pane.nudgeSelected(1, 0);
    try testing.expectEqual(@as(usize, 0), pane.pinned_positions.count());

    // Select a node and nudge
    pane.selected_node = 42;
    pane.nudgeSelected(1, 0);
    try testing.expect(pane.isPinned(42));

    const pos = pane.pinned_positions.get(42).?;
    try testing.expectEqual(@as(i32, 1), pos[0]);
    try testing.expectEqual(@as(i32, 0), pos[1]);

    // Nudge again
    pane.nudgeSelected(0, -3);
    const pos2 = pane.pinned_positions.get(42).?;
    try testing.expectEqual(@as(i32, 1), pos2[0]);
    try testing.expectEqual(@as(i32, -3), pos2[1]);
}

test "PreviewPane: toggle pin on selected node" {
    const allocator = testing.allocator;
    const pane = try allocator.create(PreviewPane);
    pane.* = .{ .allocator = allocator };
    defer pane.destroy();

    // No selected node — toggle is a no-op
    pane.togglePin();
    try testing.expectEqual(@as(usize, 0), pane.pinned_positions.count());

    // Select and pin
    pane.selected_node = 7;
    pane.togglePin();
    try testing.expect(pane.isPinned(7));

    // Toggle again — unpin
    pane.togglePin();
    try testing.expect(!pane.isPinned(7));
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
