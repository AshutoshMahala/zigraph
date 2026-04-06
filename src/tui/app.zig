const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const TextBuffer = @import("text_buffer.zig");
const EditorPane = @import("editor_pane.zig");
const UndoManager = @import("undo.zig");
const PreviewPane = @import("preview_pane.zig");
const StatusBar = @import("status_bar.zig");
const SourceMap = @import("source_map.zig");

const App = @This();

pub const Focus = enum { editor, preview };

allocator: std.mem.Allocator,
focus: Focus = .editor,
split: vxfw.SplitView,
editor_pane: *EditorPane,
buffer: *TextBuffer,
undo: *UndoManager,
preview_pane: *PreviewPane,
status_bar: *StatusBar,
source_map: *SourceMap,
children: [2]vxfw.SubSurface = undefined,

pub fn create(allocator: std.mem.Allocator) !*App {
    const buffer = try allocator.create(TextBuffer);
    buffer.* = try TextBuffer.init(allocator, "# Example\n@layout sugiyama\n\nA -> B -> C\nB -> D\n");

    const undo = try allocator.create(UndoManager);
    undo.* = UndoManager.init(allocator);

    const editor_pane = try allocator.create(EditorPane);
    editor_pane.* = .{
        .buffer = buffer,
        .undo = undo,
    };

    const preview_pane = try allocator.create(PreviewPane);
    preview_pane.* = .{ .allocator = allocator };

    // Initial render from the default buffer contents
    const source = buffer.contents(allocator) catch null;
    if (source) |s| {
        defer allocator.free(s);
        preview_pane.renderFromSource(allocator, s);
    }

    const status_bar = try allocator.create(StatusBar);
    status_bar.* = .{};

    const source_map = try allocator.create(SourceMap);
    source_map.* = SourceMap.init(allocator);

    const self = try allocator.create(App);
    self.* = .{
        .allocator = allocator,
        .buffer = buffer,
        .undo = undo,
        .editor_pane = editor_pane,
        .preview_pane = preview_pane,
        .status_bar = status_bar,
        .source_map = source_map,
        .split = undefined,
    };
    self.split = .{
        .lhs = self.editor_pane.widget(),
        .rhs = self.preview_pane.widget(),
        .width = 40,
    };
    return self;
}

pub fn destroy(self: *App) void {
    self.preview_pane.destroy();
    self.allocator.destroy(self.editor_pane);
    self.undo.deinit();
    self.allocator.destroy(self.undo);
    self.buffer.deinit();
    self.allocator.destroy(self.buffer);
    self.source_map.deinit();
    self.allocator.destroy(self.source_map);
    self.allocator.destroy(self.status_bar);
    self.allocator.destroy(self);
}

pub fn widget(self: *App) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn refreshPreview(self: *App) void {
    const source = self.buffer.contents(self.allocator) catch return;
    defer self.allocator.free(source);
    self.preview_pane.renderFromSource(self.allocator, source);
    self.rebuildSourceMap();
}

fn rebuildSourceMap(self: *App) void {
    self.source_map.clear();
    // For now, populate basic node mappings from the parse result.
    // This is a simplified version — we extract node names from the DSL source
    // and map them to their byte offsets.
    // Full implementation would use AST node locations from the parser.
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
                // Track whether the buffer was modified before forwarding
                const was_modified = self.editor_pane.modified;

                // Forward key events to editor pane
                const ep_widget = self.editor_pane.widget();
                if (ep_widget.eventHandler) |handler| {
                    try handler(ep_widget.userdata, ctx, event);
                }

                // If the editor modified the buffer, refresh the preview
                if (self.editor_pane.modified and !was_modified) {
                    self.refreshPreview();
                } else if (self.editor_pane.modified) {
                    // Also refresh on continued edits (modified was already true)
                    self.refreshPreview();
                }

                // Editor → Preview linking: highlight corresponding graph node
                const cursor_pos = self.buffer.lineColToPosition(
                    self.editor_pane.cursor_line,
                    self.editor_pane.cursor_col,
                );
                if (self.source_map.nodeAtOffset(@intCast(cursor_pos))) |node_idx| {
                    self.preview_pane.selected_node = node_idx;
                }
            } else if (self.focus == .preview) {
                // Forward key events to preview pane
                const pp_widget = self.preview_pane.widget();
                if (pp_widget.eventHandler) |handler| {
                    try handler(pp_widget.userdata, ctx, event);
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
    self.preview_pane.focused = (self.focus == .preview);

    // Update split's lhs/rhs
    self.split.lhs = self.editor_pane.widget();
    self.split.rhs = self.preview_pane.widget();

    // Draw split view in content area
    const content_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = content_height },
        vxfw.MaxSize.fromSize(.{ .width = max.width, .height = content_height }),
    );
    const split_surface = try self.split.widget().draw(content_ctx);

    // Update status bar fields from editor state
    self.status_bar.line = self.editor_pane.cursor_line;
    self.status_bar.col = self.editor_pane.cursor_col;
    self.status_bar.modified = self.editor_pane.modified;

    // Preview → Editor linking: show info about selected node in status bar
    if (self.preview_pane.selected_node) |node_idx| {
        if (self.source_map.locForNode(node_idx)) |loc| {
            _ = loc;
            // Status bar message could show node info once we have richer mappings
        }
    }

    // Draw status bar
    const status_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = 1 },
        vxfw.MaxSize.fromSize(.{ .width = max.width, .height = 1 }),
    );
    const status_surface = try self.status_bar.widget().draw(status_ctx);

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
