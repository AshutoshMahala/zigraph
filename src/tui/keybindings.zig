const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Keybindings = @This();

pub const Category = enum { file, navigation, editing, layout, preview, global };

pub const Binding = struct {
    key: []const u8,
    description: []const u8,
    category: Category,
};

pub const all_bindings = [_]Binding{
    // File
    .{ .key = "Ctrl+S", .description = "Save", .category = .file },
    .{ .key = "Ctrl+Q", .description = "Quit", .category = .file },
    .{ .key = "Ctrl+T", .description = "Open file", .category = .file },
    .{ .key = "Ctrl+W", .description = "Close tab", .category = .file },
    // Navigation
    .{ .key = "Ctrl+Tab", .description = "Next tab", .category = .navigation },
    .{ .key = "Ctrl+Shift+Tab", .description = "Previous tab", .category = .navigation },
    .{ .key = "Ctrl+G", .description = "Jump to line", .category = .navigation },
    .{ .key = "Ctrl+F", .description = "Find", .category = .navigation },
    .{ .key = "Tab", .description = "Switch focus", .category = .navigation },
    .{ .key = "Ctrl+Click", .description = "Go to definition", .category = .navigation },
    // Editing
    .{ .key = "Ctrl+Z", .description = "Undo", .category = .editing },
    .{ .key = "Ctrl+Y", .description = "Redo", .category = .editing },
    .{ .key = "Ctrl+Space", .description = "Autocomplete", .category = .editing },
    // Layout
    .{ .key = "Ctrl+\\", .description = "Toggle orientation", .category = .layout },
    .{ .key = "Ctrl+]", .description = "Increase editor", .category = .layout },
    .{ .key = "Ctrl+[", .description = "Decrease editor", .category = .layout },
    // Preview
    .{ .key = "Arrows", .description = "Nudge node", .category = .preview },
    .{ .key = "P", .description = "Pin/unpin", .category = .preview },
    .{ .key = "Esc", .description = "Deselect", .category = .preview },
    // Global
    .{ .key = "Ctrl+P", .description = "Command palette", .category = .global },
    .{ .key = "Ctrl+I", .description = "Context panel", .category = .global },
    .{ .key = "Ctrl+H", .description = "This help", .category = .global },
};

visible: bool = false,

pub fn widget(self: *Keybindings) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

pub fn toggle(self: *Keybindings) void {
    self.visible = !self.visible;
}

pub fn hide(self: *Keybindings) void {
    self.visible = false;
}

fn categoryName(cat: Category) []const u8 {
    return switch (cat) {
        .file => "File",
        .navigation => "Navigation",
        .editing => "Editing",
        .layout => "Layout",
        .preview => "Preview",
        .global => "Global",
    };
}

/// Count total rows needed: title + blank + (category header + bindings) per category
fn totalRows() u16 {
    var rows: u16 = 2; // title + blank line
    const categories = [_]Category{ .file, .navigation, .editing, .layout, .preview, .global };
    for (categories) |cat| {
        var count: u16 = 0;
        for (all_bindings) |b| {
            if (b.category == cat) count += 1;
        }
        if (count > 0) {
            rows += 1 + count; // header + bindings
        }
    }
    rows += 1; // footer hint
    return rows;
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *Keybindings = @ptrCast(@alignCast(ptr));
    if (!self.visible) return;

    switch (event) {
        .key_press => |key| {
            if (key.matches(vaxis.Key.escape, .{}) or key.matches('h', .{ .ctrl = true })) {
                self.hide();
                ctx.redraw = true;
                return;
            }
            // Consume all other events when visible (overlay captures focus)
            ctx.redraw = true;
        },
        else => {},
    }
}

fn writeString(surface: *vxfw.Surface, col_start: u16, row: u16, text: []const u8, style: vaxis.Style, max_col: u16) u16 {
    var col = col_start;
    for (text) |ch| {
        if (col >= max_col) break;
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
            .style = style,
        });
        col += 1;
    }
    return col;
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Keybindings = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    if (!self.visible) {
        return try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = 0, .height = 0 });
    }

    const overlay_width: u16 = @min(50, max.width);
    const overlay_height: u16 = @min(totalRows(), max.height);

    const start_col: u16 = (max.width -| overlay_width) / 2;
    const start_row: u16 = (max.height -| overlay_height) / 2;
    const end_col: u16 = start_col + overlay_width;

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = max.width, .height = max.height });

    const bg_style: vaxis.Style = .{};
    const title_style: vaxis.Style = .{ .bold = true };
    const header_style: vaxis.Style = .{ .bold = true, .dim = true };
    const key_style: vaxis.Style = .{ .bold = true };
    const desc_style: vaxis.Style = .{};
    const hint_style: vaxis.Style = .{ .dim = true };

    // Fill overlay background
    {
        var row: u16 = start_row;
        while (row < start_row + overlay_height and row < max.height) : (row += 1) {
            var col: u16 = start_col;
            while (col < end_col and col < max.width) : (col += 1) {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = bg_style,
                });
            }
        }
    }

    var row: u16 = start_row;

    // Title centered
    {
        const title = "Keybindings";
        const title_col = start_col + (overlay_width -| @as(u16, @intCast(title.len))) / 2;
        _ = writeString(&surface, title_col, row, title, title_style, end_col);
        row += 2; // title + blank
    }

    // Draw bindings grouped by category
    const categories = [_]Category{ .file, .navigation, .editing, .layout, .preview, .global };
    for (categories) |cat| {
        // Check if any bindings in this category
        var has_bindings = false;
        for (all_bindings) |b| {
            if (b.category == cat) {
                has_bindings = true;
                break;
            }
        }
        if (!has_bindings) continue;
        if (row >= start_row + overlay_height) break;

        // Category header
        _ = writeString(&surface, start_col + 1, row, categoryName(cat), header_style, end_col);
        row += 1;

        // Bindings
        for (all_bindings) |b| {
            if (b.category != cat) continue;
            if (row >= start_row + overlay_height) break;

            // "  key          description"
            var col = writeString(&surface, start_col + 2, row, b.key, key_style, end_col);
            // Pad to column 20 from start
            const desc_col = start_col + 20;
            while (col < desc_col and col < end_col) : (col += 1) {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = desc_style,
                });
            }
            _ = writeString(&surface, desc_col, row, b.description, desc_style, end_col);
            row += 1;
        }
    }

    // Footer hint
    if (row < start_row + overlay_height) {
        const hint = "Press Esc or Ctrl+H to close";
        const hint_col = start_col + (overlay_width -| @as(u16, @intCast(hint.len))) / 2;
        _ = writeString(&surface, hint_col, row, hint, hint_style, end_col);
    }

    return surface;
}

// --- Tests ---

test "all_bindings has expected count" {
    try std.testing.expectEqual(@as(usize, 22), all_bindings.len);
}

test "category names are non-empty" {
    const categories = [_]Category{ .file, .navigation, .editing, .layout, .preview, .global };
    for (categories) |cat| {
        try std.testing.expect(categoryName(cat).len > 0);
    }
}

test "totalRows returns reasonable value" {
    const rows = totalRows();
    // title(1) + blank(1) + 6 headers + 22 bindings + 1 footer = 31
    try std.testing.expectEqual(@as(u16, 31), rows);
}

test "toggle flips visibility" {
    var kb: Keybindings = .{};
    try std.testing.expect(!kb.visible);
    kb.toggle();
    try std.testing.expect(kb.visible);
    kb.toggle();
    try std.testing.expect(!kb.visible);
}

test "hide sets visible to false" {
    var kb: Keybindings = .{ .visible = true };
    kb.hide();
    try std.testing.expect(!kb.visible);
}
