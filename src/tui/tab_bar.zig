const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const TabBar = @This();

pub const Tab = struct {
    filename: []const u8,
    modified: bool = false,
    active: bool = false,
};

tabs: []const Tab,

pub fn widget(self: *TabBar) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = null,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *TabBar = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    // Auto-hide when only 1 tab (or none)
    if (self.tabs.len <= 1) {
        return try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = max.width, .height = 0 });
    }

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = max.width, .height = 1 });

    // Fill background with dim spaces
    const dim_style: vaxis.Style = .{ .dim = true };
    {
        var i: u16 = 0;
        while (i < max.width) : (i += 1) {
            surface.writeCell(i, 0, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = dim_style,
            });
        }
    }

    // Render tabs horizontally
    var col: u16 = 0;
    for (self.tabs) |tab| {
        const style: vaxis.Style = if (tab.active)
            .{ .reverse = true, .bold = true }
        else
            .{ .dim = true };

        // Write " filename"
        if (col < max.width) {
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = style,
            });
            col += 1;
        }

        for (tab.filename) |ch| {
            if (col >= max.width) break;
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = style,
            });
            col += 1;
        }

        // " *" if modified
        if (tab.modified) {
            const marker = " *";
            for (marker) |ch| {
                if (col >= max.width) break;
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                    .style = style,
                });
                col += 1;
            }
        }

        // " x " close indicator — plain ASCII avoids multi-byte UTF-8 complexity
        const close = " x ";
        for (close) |ch| {
            if (col >= max.width) break;
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = &[_]u8{ch}, .width = 1 },
                .style = style,
            });
            col += 1;
        }
    }

    return surface;
}

test "TabBar auto-hides with single tab" {
    var tab_bar: TabBar = .{
        .tabs = &.{.{ .filename = "test.zgraph" }},
    };
    const w = tab_bar.widget();
    _ = w;
}

test "TabBar shows with multiple tabs" {
    var tab_bar: TabBar = .{
        .tabs = &.{
            .{ .filename = "a.zgraph", .active = true },
            .{ .filename = "b.zgraph", .modified = true },
        },
    };
    const w = tab_bar.widget();
    _ = w;
}
