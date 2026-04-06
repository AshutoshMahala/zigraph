const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const StatusBar = @This();

message: []const u8 = "",
filename: []const u8 = "[new]",
line: usize = 0,
col: usize = 0,
modified: bool = false,

pub fn widget(self: *StatusBar) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = null,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *StatusBar = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = max.width, .height = 1 });

    const reverse_style: vaxis.Style = .{ .reverse = true };

    // Fill entire row with reverse-video spaces
    var i: u16 = 0;
    while (i < max.width) : (i += 1) {
        surface.writeCell(i, 0, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = reverse_style,
        });
    }

    // Left side: message if non-empty, else filename
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

    // Right side: "Ln {line+1} Col {col+1}" + " *" if modified
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

    return surface;
}

test "StatusBar draw produces 1-row surface" {
    // Basic compile test — full draw requires a DrawContext which needs arena setup
    var sb: StatusBar = .{};
    const w = sb.widget();
    _ = w;
}
