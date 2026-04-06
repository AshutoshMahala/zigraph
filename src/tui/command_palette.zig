const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const CommandPalette = @This();

pub const Action = enum {
    save,
    quit,
    open_file,
    close_tab,
    toggle_orientation,
    toggle_context_panel,
    jump_to_line,
    find,
    show_keybindings,
    next_tab,
    prev_tab,
};

pub const Command = struct {
    name: []const u8,
    description: []const u8,
    keybinding: []const u8,
    action: Action,
};

const default_commands = [_]Command{
    .{ .name = "Save", .description = "Save current file", .keybinding = "Ctrl+S", .action = .save },
    .{ .name = "Quit", .description = "Quit editor", .keybinding = "Ctrl+Q", .action = .quit },
    .{ .name = "Close tab", .description = "Close current tab", .keybinding = "Ctrl+W", .action = .close_tab },
    .{ .name = "Toggle orientation", .description = "Switch split direction", .keybinding = "Ctrl+\\", .action = .toggle_orientation },
    .{ .name = "Show keybindings", .description = "Show all keybindings", .keybinding = "Ctrl+H", .action = .show_keybindings },
};

allocator: std.mem.Allocator,
commands: []const Command,
input_buf: [256]u8 = .{0} ** 256,
input_len: usize = 0,
selected: usize = 0,
filtered_indices: [64]usize = undefined,
filtered_count: usize = 0,
visible: bool = false,

pub fn create(allocator: std.mem.Allocator) !*CommandPalette {
    const self = try allocator.create(CommandPalette);
    self.* = .{
        .allocator = allocator,
        .commands = &default_commands,
    };
    self.filterCommands();
    return self;
}

pub fn destroy(self: *CommandPalette) void {
    self.allocator.destroy(self);
}

pub fn show(self: *CommandPalette) void {
    self.visible = true;
    self.input_len = 0;
    self.selected = 0;
    self.filterCommands();
}

pub fn hide(self: *CommandPalette) void {
    self.visible = false;
    self.input_len = 0;
    self.selected = 0;
}

pub fn widget(self: *CommandPalette) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

/// Returns the action of the selected command, or null if nothing selected.
pub fn selectedAction(self: *CommandPalette) ?Action {
    if (self.filtered_count == 0) return null;
    const idx = self.filtered_indices[self.selected];
    return self.commands[idx].action;
}

pub fn filterCommands(self: *CommandPalette) void {
    self.filtered_count = 0;
    self.selected = 0;
    if (self.input_len == 0) {
        for (self.commands, 0..) |_, i| {
            if (self.filtered_count >= self.filtered_indices.len) break;
            self.filtered_indices[self.filtered_count] = i;
            self.filtered_count += 1;
        }
        return;
    }
    const pattern = self.input_buf[0..self.input_len];
    for (self.commands, 0..) |cmd, i| {
        if (fuzzyScore(pattern, cmd.name) > 0 or fuzzyScore(pattern, cmd.description) > 0) {
            if (self.filtered_count >= self.filtered_indices.len) break;
            self.filtered_indices[self.filtered_count] = i;
            self.filtered_count += 1;
        }
    }
}

pub fn fuzzyScore(pattern: []const u8, text: []const u8) i32 {
    if (pattern.len == 0) return 1;
    if (pattern.len > text.len) return 0;

    var score: i32 = 0;
    var text_idx: usize = 0;
    var prev_matched: bool = false;
    var prev_was_boundary: bool = true;

    for (pattern) |pch| {
        const p_lower = toLower(pch);
        var found = false;
        while (text_idx < text.len) {
            const t_lower = toLower(text[text_idx]);
            const is_boundary = text_idx == 0 or
                text[text_idx - 1] == ' ' or
                text[text_idx - 1] == '_' or
                text[text_idx - 1] == '-';
            text_idx += 1;
            if (p_lower == t_lower) {
                score += 1;
                if (prev_matched) score += 2; // consecutive bonus
                if (is_boundary or prev_was_boundary) score += 3; // boundary bonus
                prev_matched = true;
                prev_was_boundary = is_boundary;
                found = true;
                break;
            }
            prev_matched = false;
            prev_was_boundary = is_boundary;
        }
        if (!found) return 0;
    }
    return score;
}

fn toLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *CommandPalette = @ptrCast(@alignCast(ptr));
    if (!self.visible) return;

    switch (event) {
        .key_press => |key| {
            if (key.matches(vaxis.Key.escape, .{})) {
                self.hide();
                ctx.redraw = true;
            } else if (key.matches(vaxis.Key.enter, .{})) {
                ctx.redraw = true;
            } else if (key.matches(vaxis.Key.backspace, .{})) {
                if (self.input_len > 0) {
                    self.input_len -= 1;
                    self.filterCommands();
                }
                ctx.redraw = true;
            } else if (key.matches(vaxis.Key.up, .{})) {
                if (self.selected > 0) self.selected -= 1;
                ctx.redraw = true;
            } else if (key.matches(vaxis.Key.down, .{})) {
                if (self.filtered_count > 0 and self.selected + 1 < self.filtered_count) {
                    self.selected += 1;
                }
                ctx.redraw = true;
            } else if (key.text) |text| {
                // Printable character input
                for (text) |ch| {
                    if (self.input_len < self.input_buf.len) {
                        self.input_buf[self.input_len] = ch;
                        self.input_len += 1;
                    }
                }
                self.filterCommands();
                ctx.redraw = true;
            } else if (key.codepoint > 0x1F and key.codepoint < 0x7F) {
                // Fallback for printable ASCII without .text
                if (self.input_len < self.input_buf.len) {
                    self.input_buf[self.input_len] = @intCast(key.codepoint);
                    self.input_len += 1;
                    self.filterCommands();
                }
                ctx.redraw = true;
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *CommandPalette = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    if (!self.visible) {
        return try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = 0, .height = 0 });
    }

    const overlay_width: u16 = @min(50, max.width);
    const max_results: u16 = 12;
    const visible_results: u16 = @intCast(@min(max_results, self.filtered_count));
    const overlay_height: u16 = 2 + visible_results; // 1 input row + 1 separator + results
    const total_height: u16 = @min(overlay_height, max.height);

    const start_col: u16 = (max.width -| overlay_width) / 2;
    const start_row: u16 = @min(2, max.height -| total_height);

    // Create a surface that covers the full screen
    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = max.width, .height = max.height });

    const bg_style: vaxis.Style = .{ .dim = true };
    const input_style: vaxis.Style = .{ .bold = true };
    const selected_style: vaxis.Style = .{ .reverse = true };
    const normal_style: vaxis.Style = .{};
    const border_style: vaxis.Style = .{ .dim = true };

    // Fill overlay background
    var row: u16 = start_row;
    while (row < start_row + total_height and row < max.height) : (row += 1) {
        var col: u16 = start_col;
        while (col < start_col + overlay_width and col < max.width) : (col += 1) {
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = bg_style,
            });
        }
    }

    // Draw input row: "> " + input text
    {
        const prompt = "> ";
        var col: u16 = start_col;
        for (prompt) |ch| {
            if (col >= start_col + overlay_width) break;
            surface.writeCell(col, start_row, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = input_style,
            });
            col += 1;
        }
        const input = self.input_buf[0..self.input_len];
        for (input) |ch| {
            if (col >= start_col + overlay_width) break;
            surface.writeCell(col, start_row, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = input_style,
            });
            col += 1;
        }
    }

    // Draw separator line
    {
        var col: u16 = start_col;
        while (col < start_col + overlay_width and col < max.width) : (col += 1) {
            surface.writeCell(col, start_row + 1, .{
                .char = .{ .grapheme = "\xe2\x94\x80", .width = 1 }, // ─
                .style = border_style,
            });
        }
    }

    // Draw filtered results
    var result_row: u16 = start_row + 2;
    var idx: usize = 0;
    while (idx < self.filtered_count and idx < max_results) : (idx += 1) {
        if (result_row >= max.height) break;
        const cmd_idx = self.filtered_indices[idx];
        const cmd = self.commands[cmd_idx];
        const style = if (idx == self.selected) selected_style else normal_style;

        // "  command_name    keybinding"
        var col: u16 = start_col;

        // Leading spaces
        const prefix = "  ";
        for (prefix) |ch| {
            if (col >= start_col + overlay_width) break;
            surface.writeCell(col, result_row, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = style,
            });
            col += 1;
        }

        // Command name
        for (cmd.name) |ch| {
            if (col >= start_col + overlay_width) break;
            surface.writeCell(col, result_row, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = style,
            });
            col += 1;
        }

        // Right-align keybinding
        const kb_len: u16 = @intCast(cmd.keybinding.len);
        const kb_start = start_col + overlay_width -| kb_len -| 2;
        // Fill gap with spaces
        while (col < kb_start and col < start_col + overlay_width) : (col += 1) {
            surface.writeCell(col, result_row, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = style,
            });
        }
        col = kb_start;
        for (cmd.keybinding) |ch| {
            if (col >= start_col + overlay_width) break;
            surface.writeCell(col, result_row, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
        // Fill remaining with spaces (for selected highlight)
        while (col < start_col + overlay_width) : (col += 1) {
            surface.writeCell(col, result_row, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = style,
            });
        }

        result_row += 1;
    }

    return surface;
}

// --- Tests ---

test "fuzzyScore: exact match scores high" {
    try std.testing.expect(fuzzyScore("save", "save") > 0);
}

test "fuzzyScore: partial match" {
    try std.testing.expect(fuzzyScore("sv", "save") > 0);
}

test "fuzzyScore: no match returns 0" {
    try std.testing.expectEqual(@as(i32, 0), fuzzyScore("xyz", "save"));
}

test "fuzzyScore: case insensitive" {
    try std.testing.expect(fuzzyScore("SAVE", "save") > 0);
}

test "filterCommands: empty input shows all" {
    var palette: CommandPalette = .{
        .allocator = std.testing.allocator,
        .commands = &default_commands,
    };
    palette.input_len = 0;
    palette.filterCommands();
    try std.testing.expectEqual(default_commands.len, palette.filtered_count);
}

test "filterCommands: filters correctly" {
    var palette: CommandPalette = .{
        .allocator = std.testing.allocator,
        .commands = &default_commands,
    };
    // Type "sav"
    palette.input_buf[0] = 's';
    palette.input_buf[1] = 'a';
    palette.input_buf[2] = 'v';
    palette.input_len = 3;
    palette.filterCommands();

    // Should match "Save" but not "Quit"
    try std.testing.expect(palette.filtered_count >= 1);
    // First match should be "Save"
    const first_cmd = palette.commands[palette.filtered_indices[0]];
    try std.testing.expectEqualStrings("Save", first_cmd.name);

    // Verify "Quit" is not in results
    var found_quit = false;
    for (0..palette.filtered_count) |i| {
        const cmd = palette.commands[palette.filtered_indices[i]];
        if (std.mem.eql(u8, cmd.name, "Quit")) {
            found_quit = true;
        }
    }
    try std.testing.expect(!found_quit);
}
