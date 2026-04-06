const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const StatusBar = @This();

message: []const u8 = "",
filename: []const u8 = "[new]",
line: usize = 0,
col: usize = 0,
modified: bool = false,
context_panel_open: bool = false,
context_info: []const u8 = "",
/// Backing storage for context_info when set via setContextInfo
context_buf: [128]u8 = undefined,

pub fn widget(self: *StatusBar) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = null,
        .drawFn = typeErasedDrawFn,
    };
}

pub fn toggle(self: *StatusBar) void {
    self.context_panel_open = !self.context_panel_open;
}

/// Write formatted context info into the internal buffer and point context_info at it.
pub fn setContextInfo(self: *StatusBar, comptime fmt: []const u8, args: anytype) void {
    self.context_info = std.fmt.bufPrint(&self.context_buf, fmt, args) catch "";
}

pub fn height(self: *const StatusBar) u16 {
    return if (self.context_panel_open) 4 else 1;
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *StatusBar = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();
    const bar_height = self.height();

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = max.width, .height = bar_height });

    const reverse_style: vaxis.Style = .{ .reverse = true };

    var i: u16 = 0;
    while (i < max.width) : (i += 1) {
        surface.writeCell(i, 0, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = reverse_style,
        });
    }

    const left_text = if (self.message.len > 0) self.message else self.filename;
    {
        var c: u16 = 1;
        for (left_text) |ch| {
            if (c >= max.width) break;
            surface.writeCell(c, 0, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = reverse_style,
            });
            c += 1;
        }
    }

    var buf: [64]u8 = undefined;
    const right_text = if (self.modified)
        std.fmt.bufPrint(&buf, "Ln {d} Col {d} *", .{ self.line + 1, self.col + 1 }) catch return surface
    else
        std.fmt.bufPrint(&buf, "Ln {d} Col {d}", .{ self.line + 1, self.col + 1 }) catch return surface;

    const right_len: u16 = @intCast(right_text.len);
    if (right_len + 1 < max.width) {
        const start_col = max.width - right_len - 1;
        var c: u16 = 0;
        while (c < right_len) : (c += 1) {
            surface.writeCell(start_col + c, 0, .{
                .char = .{ .grapheme = right_text[c .. c + 1], .width = 1 },
                .style = reverse_style,
            });
        }
    }

    // Rows 1-3: context panel (dim style)
    if (self.context_panel_open) {
        const dim_style: vaxis.Style = .{ .dim = true };

        // Fill rows 1-3 with spaces
        var row: u16 = 1;
        while (row < bar_height) : (row += 1) {
            var col: u16 = 0;
            while (col < max.width) : (col += 1) {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = dim_style,
                });
            }
        }

        // Split context_info by newlines and write each line to rows 1-3
        var line_iter = std.mem.splitScalar(u8, self.context_info, '\n');
        var panel_row: u16 = 1;
        while (line_iter.next()) |line_text| {
            if (panel_row >= bar_height) break;
            var col: u16 = 1;
            for (line_text) |ch| {
                if (col >= max.width) break;
                surface.writeCell(col, panel_row, .{
                    .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                    .style = dim_style,
                });
                col += 1;
            }
            panel_row += 1;
        }
    }

    return surface;
}

test "StatusBar height returns 1 when closed" {
    const sb: StatusBar = .{};
    try std.testing.expectEqual(@as(u16, 1), sb.height());
}

test "StatusBar height returns 4 when open" {
    const sb: StatusBar = .{ .context_panel_open = true };
    try std.testing.expectEqual(@as(u16, 4), sb.height());
}

test "StatusBar toggle flips context_panel_open" {
    var sb: StatusBar = .{};
    try std.testing.expectEqual(false, sb.context_panel_open);
    sb.toggle();
    try std.testing.expectEqual(true, sb.context_panel_open);
    sb.toggle();
    try std.testing.expectEqual(false, sb.context_panel_open);
}

test "StatusBar widget compiles" {
    var sb: StatusBar = .{};
    const w = sb.widget();
    _ = w;
}
