const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const App = @import("app.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vx_app = try vxfw.App.init(allocator);
    defer vx_app.deinit();

    const app = try App.create(allocator);
    defer app.destroy();

    try vx_app.run(app.widget(), .{});
}

test {
    _ = @import("text_buffer.zig");
    _ = @import("undo.zig");
    _ = @import("highlighter.zig");
    _ = @import("source_map.zig");
    _ = @import("editor_pane.zig");
    _ = @import("preview_pane.zig");
    _ = @import("status_bar.zig");
    _ = @import("tab_bar.zig");
}
