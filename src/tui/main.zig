const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const App = @import("app.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line args
    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);
    const args = if (raw_args.len > 1) raw_args[1..] else raw_args[0..0];

    var vx_app = try vxfw.App.init(allocator);
    defer vx_app.deinit();

    const app = try App.create(allocator);
    defer app.destroy();

    // Load files from args
    for (args) |file_path| {
        const content = readFile(allocator, file_path) catch |err| {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            stderr.print("error: cannot open {s}: {s}\n", .{ file_path, @errorName(err) }) catch {};
            continue;
        };
        defer allocator.free(content);
        // Use the full file path so save can write back to disk
        app.addBuffer(file_path, content) catch continue;
    }

    try vx_app.run(app.widget(), .{});
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 64 * 1024 * 1024);
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
    _ = @import("command_palette.zig");
    _ = @import("keybindings.zig");
    _ = @import("definitions.zig");
    _ = @import("completion.zig");
}
