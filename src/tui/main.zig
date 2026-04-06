const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const App = struct {
    children: [1]vxfw.SubSurface = undefined,

    pub fn widget(self: *App) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        _ = ptr;
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                }
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *App = @ptrCast(@alignCast(ptr));
        const max_size = ctx.max.size();

        var text: vxfw.Text = .{
            .text = "zigraph editor — press 'q' to quit",
            .style = .{ .bold = true },
        };
        const text_surface = try text.widget().draw(ctx);

        self.children[0] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = text_surface,
        };

        return .{
            .size = max_size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = &self.children,
        };
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    var model = App{};
    try app.run(model.widget(), .{});
}

test {
    // Will import submodule tests as they're created
}
