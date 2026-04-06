const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const TextBuffer = @import("text_buffer.zig");
const EditorPane = @import("editor_pane.zig");

const App = @This();

pub const Focus = enum { editor, preview };

allocator: std.mem.Allocator,
focus: Focus = .editor,
split: vxfw.SplitView,
editor_pane: *EditorPane,
buffer: *TextBuffer,
preview_text: vxfw.Text,
status_text: vxfw.Text,
children: [2]vxfw.SubSurface = undefined,

pub fn create(allocator: std.mem.Allocator) !*App {
    const buffer = try allocator.create(TextBuffer);
    buffer.* = try TextBuffer.init(allocator, "# Example\n@layout sugiyama\n\nA -> B -> C\nB -> D\n");

    const editor_pane = try allocator.create(EditorPane);
    editor_pane.* = .{
        .buffer = buffer,
    };

    const self = try allocator.create(App);
    self.* = .{
        .allocator = allocator,
        .buffer = buffer,
        .editor_pane = editor_pane,
        .preview_text = .{
            .text = "[preview pane]",
            .width_basis = .parent,
        },
        .status_text = .{
            .text = "zigraph editor | Ctrl+Q quit | Tab switch focus",
            .style = .{ .reverse = true },
            .width_basis = .parent,
        },
        .split = undefined,
    };
    self.split = .{
        .lhs = self.editor_pane.widget(),
        .rhs = self.preview_text.widget(),
        .width = 40,
    };
    return self;
}

pub fn destroy(self: *App) void {
    self.allocator.destroy(self.editor_pane);
    self.buffer.deinit();
    self.allocator.destroy(self.buffer);
    self.allocator.destroy(self);
}

pub fn widget(self: *App) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *App = @ptrCast(@alignCast(ptr));
    switch (event) {
        .key_press => |key| {
            if (key.matches('q', .{ .ctrl = true })) {
                ctx.quit = true;
            } else if (key.matches('\t', .{})) {
                self.focus = switch (self.focus) {
                    .editor => .preview,
                    .preview => .editor,
                };
                ctx.redraw = true;
            } else if (self.focus == .editor) {
                // Forward key events to editor pane
                const ep_widget = self.editor_pane.widget();
                if (ep_widget.eventHandler) |handler| {
                    try handler(ep_widget.userdata, ctx, event);
                }
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *App = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    // Reserve 1 row for the status bar
    const content_height = max.height -| 1;

    // Update focus state
    self.editor_pane.focused = (self.focus == .editor);

    // Update split's lhs/rhs
    self.split.lhs = self.editor_pane.widget();
    self.split.rhs = self.preview_text.widget();

    // Draw split view in content area
    const content_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = content_height },
        vxfw.MaxSize.fromSize(.{ .width = max.width, .height = content_height }),
    );
    const split_surface = try self.split.widget().draw(content_ctx);

    // Draw status bar
    const status_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = 1 },
        vxfw.MaxSize.fromSize(.{ .width = max.width, .height = 1 }),
    );
    const status_surface = try self.status_text.widget().draw(status_ctx);

    self.children[0] = .{
        .origin = .{ .row = 0, .col = 0 },
        .surface = split_surface,
    };
    self.children[1] = .{
        .origin = .{ .row = @intCast(content_height), .col = 0 },
        .surface = status_surface,
    };

    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = &self.children,
    };
}
