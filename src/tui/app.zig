const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const dsl = @import("dsl");

const TextBuffer = @import("text_buffer.zig");
const EditorPane = @import("editor_pane.zig");
const UndoManager = @import("undo.zig");
const PreviewPane = @import("preview_pane.zig");
const StatusBar = @import("status_bar.zig");
const SourceMap = @import("source_map.zig");
const TabBar = @import("tab_bar.zig");
const CommandPalette = @import("command_palette.zig");
const Keybindings = @import("keybindings.zig");
const Definitions = @import("definitions.zig");
const Completion = @import("completion.zig");

const App = @This();

pub const Focus = enum { editor, preview };

pub const BufferState = struct {
    buffer: *TextBuffer,
    undo: *UndoManager,
    editor_pane: *EditorPane,
    filename: []const u8,
    modified: bool,
};

allocator: std.mem.Allocator,
focus: Focus = .editor,
quit_prompt_visible: bool = false,
split: vxfw.SplitView,
orientation: enum { horizontal, vertical } = .horizontal,
split_height: u16 = 15,
editor_pane: *EditorPane,
buffer: *TextBuffer,
undo: *UndoManager,
preview_pane: *PreviewPane,
status_bar: *StatusBar,
source_map: *SourceMap,
tab_bar: *TabBar,
command_palette: *CommandPalette,
keybindings: *Keybindings,
definitions: *Definitions,
completion: *Completion,
buffers: std.ArrayListUnmanaged(BufferState),
active_tab: usize = 0,
tab_cache: std.ArrayListUnmanaged(TabBar.Tab),
children: [7]vxfw.SubSurface = undefined,
/// Owned slice of error/warning annotations for the current buffer.
last_errors: []EditorPane.ErrorLine = &.{},
/// Set to true when the buffer is modified; cleared and acted on at the start of the next draw frame.
preview_dirty: bool = false,

/// Allocates and initializes a new App and all of its owned resources.
/// Caller must call `destroy` to free all resources when done.
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

    const source = buffer.contents(allocator) catch null; // OOM: skip initial render
    if (source) |s| {
        defer allocator.free(s);
        preview_pane.renderFromSource(allocator, s);
    }

    const status_bar = try allocator.create(StatusBar);
    status_bar.* = .{};

    const source_map = try allocator.create(SourceMap);
    source_map.* = SourceMap.init(allocator);

    const tab_bar = try allocator.create(TabBar);
    tab_bar.* = .{ .tabs = &.{} };

    const command_palette = try CommandPalette.create(allocator);

    const keybindings = try allocator.create(Keybindings);
    keybindings.* = .{};

    const definitions = try allocator.create(Definitions);
    definitions.* = Definitions.init(allocator);

    const completion = try allocator.create(Completion);
    completion.* = .{};

    const self = try allocator.create(App);
    self.* = .{
        .allocator = allocator,
        .buffer = buffer,
        .undo = undo,
        .editor_pane = editor_pane,
        .preview_pane = preview_pane,
        .status_bar = status_bar,
        .source_map = source_map,
        .tab_bar = tab_bar,
        .command_palette = command_palette,
        .keybindings = keybindings,
        .definitions = definitions,
        .completion = completion,
        .buffers = .{},
        .tab_cache = .{},
        .split = undefined,
        .last_errors = &.{},
    };
    self.split = .{
        .lhs = self.editor_pane.widget(),
        .rhs = self.preview_pane.widget(),
        .width = 40,
    };

    try self.buffers.append(allocator, .{
        .buffer = buffer,
        .undo = undo,
        .editor_pane = editor_pane,
        .filename = "[new]",
        .modified = false,
    });
    self.rebuildTabCache();

    return self;
}

/// Frees all owned resources including self. Do not use the App after calling this.
pub fn destroy(self: *App) void {
    self.allocator.free(self.last_errors);
    self.preview_pane.destroy();
    for (self.buffers.items) |bs| {
        self.allocator.destroy(bs.editor_pane);
        bs.undo.deinit();
        self.allocator.destroy(bs.undo);
        bs.buffer.deinit();
        self.allocator.destroy(bs.buffer);
    }
    self.buffers.deinit(self.allocator);
    self.tab_cache.deinit(self.allocator);
    self.source_map.deinit();
    self.allocator.destroy(self.source_map);
    self.allocator.destroy(self.status_bar);
    self.definitions.deinit();
    self.allocator.destroy(self.definitions);
    self.command_palette.destroy();
    self.allocator.destroy(self.keybindings);
    self.allocator.destroy(self.tab_bar);
    self.allocator.destroy(self.completion);
    self.allocator.destroy(self);
}

pub fn widget(self: *App) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

/// Adds a new buffer with the given `filename` and `content`, then switches to it.
/// `filename` is borrowed — not duplicated — so the caller must ensure the backing
/// memory outlives the App.
pub fn addBuffer(self: *App, filename: []const u8, content: []const u8) !void {
    const buffer = try self.allocator.create(TextBuffer);
    buffer.* = try TextBuffer.init(self.allocator, content);

    const undo = try self.allocator.create(UndoManager);
    undo.* = UndoManager.init(self.allocator);

    const editor_pane = try self.allocator.create(EditorPane);
    editor_pane.* = .{
        .buffer = buffer,
        .undo = undo,
    };

    try self.buffers.append(self.allocator, .{
        .buffer = buffer,
        .undo = undo,
        .editor_pane = editor_pane,
        .filename = filename,
        .modified = false,
    });

    self.switchTab(self.buffers.items.len - 1);
}

pub fn switchTab(self: *App, index: usize) void {
    if (index >= self.buffers.items.len) return;
    if (self.active_tab < self.buffers.items.len) {
        self.buffers.items[self.active_tab].modified = self.editor_pane.modified;
    }
    self.active_tab = index;
    const bs = self.buffers.items[index];
    self.buffer = bs.buffer;
    self.undo = bs.undo;
    self.editor_pane = bs.editor_pane;
    self.rebuildTabCache();
}

fn rebuildTabCache(self: *App) void {
    self.tab_cache.clearRetainingCapacity();
    for (self.buffers.items, 0..) |bs, i| {
        self.tab_cache.append(self.allocator, .{
            .filename = bs.filename,
            .modified = bs.modified or (i == self.active_tab and self.editor_pane.modified),
            .active = (i == self.active_tab),
        }) catch return;
    }
    self.tab_bar.tabs = self.tab_cache.items;
}

fn executeAction(self: *App, action: CommandPalette.Action, ctx: *vxfw.EventContext) void {
    switch (action) {
        .quit => ctx.quit = true,
        .save => {
            self.saveCurrentFile() catch {
                self.status_bar.message = "Save failed";
            };
            ctx.redraw = true;
        },
        .close_tab => {
            // Close tab: remove the current buffer and switch to an adjacent one
            if (self.buffers.items.len > 1) {
                const close_idx = self.active_tab;
                const next = if (close_idx == 0) 0 else close_idx - 1;
                self.switchTab(next);

                // Remove the closed buffer and free its resources
                const closed = self.buffers.orderedRemove(close_idx);
                self.allocator.destroy(closed.editor_pane);
                closed.undo.deinit();
                self.allocator.destroy(closed.undo);
                closed.buffer.deinit();
                self.allocator.destroy(closed.buffer);

                // Adjust active_tab if the closed tab was before the current one
                if (close_idx < self.active_tab) {
                    self.active_tab -= 1;
                }
                // Re-clamp active_tab in case we removed the last item
                if (self.active_tab >= self.buffers.items.len) {
                    self.active_tab = self.buffers.items.len - 1;
                }

                self.rebuildTabCache();
                self.refreshPreview();
            }
            ctx.redraw = true;
        },
        .toggle_orientation => {
            self.orientation = switch (self.orientation) {
                .horizontal => .vertical,
                .vertical => .horizontal,
            };
            self.status_bar.message = switch (self.orientation) {
                .horizontal => "Split: horizontal",
                .vertical => "Split: vertical",
            };
            ctx.redraw = true;
        },
        .show_keybindings => {
            self.keybindings.toggle();
            ctx.redraw = true;
        },
        .next_tab => {
            if (self.buffers.items.len > 1) {
                const next = (self.active_tab + 1) % self.buffers.items.len;
                self.switchTab(next);
                self.refreshPreview();
            }
            ctx.redraw = true;
        },
        .prev_tab => {
            if (self.buffers.items.len > 1) {
                const prev = if (self.active_tab == 0) self.buffers.items.len - 1 else self.active_tab - 1;
                self.switchTab(prev);
                self.refreshPreview();
            }
            ctx.redraw = true;
        },
        else => {
            self.status_bar.message = "Command not yet implemented";
            ctx.redraw = true;
        },
    }
}

fn refreshPreview(self: *App) void {
    const source = self.buffer.contents(self.allocator) catch return;
    defer self.allocator.free(source);
    self.preview_pane.renderFromSource(self.allocator, source);
    self.definitions.clear();
    self.rebuildSourceMap(source);
    self.refreshErrors(source);
}

fn refreshErrors(self: *App, source: []const u8) void {
    // Free previous error annotations
    self.allocator.free(self.last_errors);
    self.last_errors = &.{};
    self.editor_pane.error_lines = &.{};

    // Run tokenize + parse to collect DSL errors
    var err_list = dsl.errors.ErrorList.init(self.allocator);
    defer err_list.deinit();

    const tokens = dsl.tokenizer.tokenize(self.allocator, source, &err_list) catch {
        // Tokenizer returned a fatal error; any errors are already in err_list via the error path,
        // but since tokenize returns error on OOM (not parse errors), just return.
        return;
    };
    defer self.allocator.free(tokens);

    if (!err_list.hasErrors()) {
        // Also run the parser to collect parse-level errors
        var p = dsl.parser.Parser.init(self.allocator, tokens, &err_list);
        _ = p.parse() catch {};
    }

    if (!err_list.hasErrors()) {
        self.status_bar.message = "";
        return;
    }

    // Convert DslError list → []ErrorLine
    var lines = std.ArrayListUnmanaged(EditorPane.ErrorLine){};
    for (err_list.errors.items) |e| {
        // DslError.loc.line is 1-based; ErrorLine.line is 0-based
        const buf_line: usize = if (e.loc.line > 0) e.loc.line - 1 else 0;
        const buf_col: usize = if (e.loc.col > 0) e.loc.col - 1 else 0;
        lines.append(self.allocator, .{
            .line = buf_line,
            .col = buf_col,
            .len = 1,
            .severity = .err,
            .message = e.message,
        }) catch break;
    }

    self.last_errors = lines.toOwnedSlice(self.allocator) catch &.{};
    self.editor_pane.error_lines = self.last_errors;

    // Show first error message in status bar
    if (self.last_errors.len > 0) {
        self.status_bar.message = self.last_errors[0].message;
    }
}

fn saveCurrentFile(self: *App) !void {
    const active = &self.buffers.items[self.active_tab];
    if (std.mem.eql(u8, active.filename, "[new]")) {
        self.status_bar.message = "No filename — use :save <path>";
        return;
    }
    const content = try self.buffer.contents(self.allocator);
    defer self.allocator.free(content);
    const file = try std.fs.cwd().createFile(active.filename, .{ .truncate = true });
    defer file.close();
    try file.writeAll(content);
    self.editor_pane.modified = false;
    active.modified = false;
    self.status_bar.message = "Saved";
}

fn rebuildSourceMap(self: *App, source: []const u8) void {
    self.source_map.clear();

    var err_list = dsl.errors.ErrorList.init(self.allocator);
    defer err_list.deinit();

    const tokens = dsl.tokenizer.tokenize(self.allocator, source, &err_list) catch return;
    defer self.allocator.free(tokens);

    // Walk tokens and register identifier tokens as node candidates.
    // We use a simple incrementing counter as the node_index (approximate mapping).
    var node_index: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const tok = tokens[i];
        if (tok.kind != .identifier) continue;

        const loc = dsl.errors.Loc{
            .line = tok.loc.line,
            .col = tok.loc.col,
            .offset = @intCast(tok.loc.offset),
        };
        self.source_map.addNode(node_index, loc, tok.text.len) catch {};
        self.definitions.addNode(tok.text, loc) catch {};
        node_index += 1;
    }
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *App = @ptrCast(@alignCast(ptr));
    switch (event) {
        .key_press => |key| {
            // Ctrl+H toggles keybindings help
            if (key.matches('h', .{ .ctrl = true })) {
                self.keybindings.toggle();
                ctx.redraw = true;
                return;
            }

            // When keybindings overlay is visible, it captures all key events
            if (self.keybindings.visible) {
                const kb_widget = self.keybindings.widget();
                if (kb_widget.eventHandler) |handler| {
                    try handler(kb_widget.userdata, ctx, event);
                }
                return;
            }

            // Ctrl+P toggles command palette
            if (key.matches('p', .{ .ctrl = true })) {
                if (self.command_palette.visible) {
                    self.command_palette.hide();
                } else {
                    self.command_palette.show();
                }
                ctx.redraw = true;
                return;
            }

            // When command palette is visible, it captures all key events
            if (self.command_palette.visible) {
                // Check for Enter before forwarding (to capture the action)
                const is_enter = key.matches(vaxis.Key.enter, .{});

                const cp_widget = self.command_palette.widget();
                if (cp_widget.eventHandler) |handler| {
                    try handler(cp_widget.userdata, ctx, event);
                }

                // If Enter was pressed, execute the selected action
                if (is_enter) {
                    if (self.command_palette.selectedAction()) |action| {
                        self.command_palette.hide();
                        self.executeAction(action, ctx);
                    }
                }
                return;
            }

            if (key.matches('s', .{ .ctrl = true })) {
                self.saveCurrentFile() catch {
                    self.status_bar.message = "Save failed";
                };
                ctx.redraw = true;
                return;
            }

            // Ctrl+\ toggles split orientation
            if (key.matches('\\', .{ .ctrl = true })) {
                self.orientation = switch (self.orientation) {
                    .horizontal => .vertical,
                    .vertical => .horizontal,
                };
                self.status_bar.message = switch (self.orientation) {
                    .horizontal => "Split: horizontal",
                    .vertical => "Split: vertical",
                };
                ctx.redraw = true;
                return;
            }

            // Ctrl+I toggles context panel in status bar
            if (key.matches('i', .{ .ctrl = true })) {
                self.status_bar.toggle();
                ctx.redraw = true;
                return;
            }

            // Ctrl+] increases split size, Ctrl+[ decreases
            if (key.matches(']', .{ .ctrl = true })) {
                switch (self.orientation) {
                    .horizontal => self.split.width +|= 5,
                    .vertical => self.split_height +|= 3,
                }
                ctx.redraw = true;
                return;
            }
            if (key.matches('[', .{ .ctrl = true })) {
                switch (self.orientation) {
                    .horizontal => self.split.width = @max(10, self.split.width -| 5),
                    .vertical => self.split_height = @max(5, self.split_height -| 3),
                }
                ctx.redraw = true;
                return;
            }

            if (self.quit_prompt_visible and !key.matches('q', .{ .ctrl = true })) {
                self.quit_prompt_visible = false;
                self.status_bar.message = "";
            }

            if (key.matches('q', .{ .ctrl = true })) {
                var has_unsaved = false;
                for (self.buffers.items) |bs| {
                    if (bs.modified) {
                        has_unsaved = true;
                        break;
                    }
                }
                if (self.editor_pane.modified) has_unsaved = true;

                if (has_unsaved and !self.quit_prompt_visible) {
                    self.quit_prompt_visible = true;
                    self.status_bar.message = "Unsaved changes! Press Ctrl+Q again to quit, or Ctrl+S to save";
                    ctx.redraw = true;
                } else {
                    ctx.quit = true;
                }
            } else if (key.matches('\t', .{ .ctrl = true, .shift = true })) {
                // Ctrl+Shift+Tab: previous tab
                if (self.buffers.items.len > 1) {
                    const prev = if (self.active_tab == 0) self.buffers.items.len - 1 else self.active_tab - 1;
                    self.switchTab(prev);
                    self.refreshPreview();
                    ctx.redraw = true;
                }
            } else if (key.matches('\t', .{ .ctrl = true })) {
                // Ctrl+Tab: next tab
                if (self.buffers.items.len > 1) {
                    const next = (self.active_tab + 1) % self.buffers.items.len;
                    self.switchTab(next);
                    self.refreshPreview();
                    ctx.redraw = true;
                }
            } else if (key.matches('\t', .{})) {
                self.focus = switch (self.focus) {
                    .editor => .preview,
                    .preview => .editor,
                };
                ctx.redraw = true;
            } else if (self.focus == .editor) {
                // Ctrl+Space: toggle completion popup explicitly
                if (key.matches(' ', .{ .ctrl = true })) {
                    if (self.completion.visible) {
                        self.completion.hide();
                    } else {
                        const line = self.buffer.lineAt(self.editor_pane.cursor_line) catch "";
                        defer if (line.len > 0) self.buffer.allocator.free(line);
                        const ctx_kind = Completion.detectContext(line, self.editor_pane.cursor_col);
                        if (ctx_kind != .none) {
                            const comp_items = Completion.getCompletions(ctx_kind);
                            if (comp_items.len > 0) {
                                self.completion.show(comp_items);
                            }
                        }
                    }
                    ctx.redraw = true;
                    return;
                }

                // When completion popup is visible, intercept navigation/accept/dismiss keys.
                if (self.completion.visible) {
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.completion.hide();
                        ctx.redraw = true;
                        return;
                    } else if (key.matches(vaxis.Key.up, .{})) {
                        self.completion.moveUp();
                        ctx.redraw = true;
                        return;
                    } else if (key.matches(vaxis.Key.down, .{})) {
                        self.completion.moveDown();
                        ctx.redraw = true;
                        return;
                    } else if (key.matches('\t', .{}) or key.matches(vaxis.Key.enter, .{})) {
                        // Accept selected completion: insert its text at cursor position.
                        if (self.completion.selectedItem()) |item| {
                            const pos = self.buffer.lineColToPosition(
                                self.editor_pane.cursor_line,
                                self.editor_pane.cursor_col,
                            );
                            self.undo.insertText(self.buffer, pos, item.text) catch {};
                            self.editor_pane.cursor_col += item.text.len;
                            self.editor_pane.modified = true;
                            self.preview_dirty = true;
                        }
                        self.completion.hide();
                        ctx.redraw = true;
                        return;
                    }
                }

                // Forward the key event to the editor pane.
                const ep_widget = self.editor_pane.widget();
                if (ep_widget.eventHandler) |handler| {
                    try handler(ep_widget.userdata, ctx, event);
                }

                if (self.editor_pane.modified) {
                    self.preview_dirty = true;
                }

                // After editing, update the completion popup based on context.
                {
                    const line = self.buffer.lineAt(self.editor_pane.cursor_line) catch "";
                    defer if (line.len > 0) self.buffer.allocator.free(line);
                    const ctx_kind = Completion.detectContext(line, self.editor_pane.cursor_col);
                    if (ctx_kind != .none) {
                        const comp_items = Completion.getCompletions(ctx_kind);
                        if (comp_items.len > 0) {
                            // Auto-trigger on '@' character or keep popup updated if already visible.
                            const typed_at = key.text != null and key.text.?[0] == '@';
                            if (typed_at or self.completion.visible) {
                                self.completion.show(comp_items);
                            }
                        } else {
                            self.completion.hide();
                        }
                    } else {
                        self.completion.hide();
                    }
                }

                const cursor_pos = self.buffer.lineColToPosition(
                    self.editor_pane.cursor_line,
                    self.editor_pane.cursor_col,
                );
                if (self.source_map.nodeAtOffset(@intCast(cursor_pos))) |node_idx| {
                    self.preview_pane.selected_node = node_idx;
                }
            } else if (self.focus == .preview) {
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

    if (self.preview_dirty) {
        self.preview_dirty = false;
        self.refreshPreview();
    }

    self.rebuildTabCache();

    const tab_bar_height: u16 = if (self.buffers.items.len > 1) 1 else 0;

    // Reserve rows for the status bar (dynamic) + tab bar height
    const status_height = self.status_bar.height();
    const content_height = max.height -| (status_height + tab_bar_height);

    self.editor_pane.focused = (self.focus == .editor);
    self.preview_pane.focused = (self.focus == .preview);

    self.split.lhs = self.editor_pane.widget();
    self.split.rhs = self.preview_pane.widget();

    var child_idx: usize = 0;

    if (tab_bar_height > 0) {
        const tab_ctx = ctx.withConstraints(
            .{ .width = max.width, .height = 1 },
            vxfw.MaxSize.fromSize(.{ .width = max.width, .height = 1 }),
        );
        const tab_surface = try self.tab_bar.widget().draw(tab_ctx);
        self.children[child_idx] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = tab_surface,
        };
        child_idx += 1;
    }

    const content_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = content_height },
        vxfw.MaxSize.fromSize(.{ .width = max.width, .height = content_height }),
    );

    if (self.orientation == .horizontal) {
        const split_surface = try self.split.widget().draw(content_ctx);
        self.children[child_idx] = .{
            .origin = .{ .row = @intCast(tab_bar_height), .col = 0 },
            .surface = split_surface,
        };
        child_idx += 1;
    } else {
        const editor_h = @min(self.split_height, content_height -| 1);
        const preview_h = content_height -| editor_h;

        const editor_ctx = ctx.withConstraints(
            .{ .width = max.width, .height = editor_h },
            vxfw.MaxSize.fromSize(.{ .width = max.width, .height = editor_h }),
        );
        const editor_surface = try self.editor_pane.widget().draw(editor_ctx);
        self.children[child_idx] = .{
            .origin = .{ .row = @intCast(tab_bar_height), .col = 0 },
            .surface = editor_surface,
        };
        child_idx += 1;

        if (preview_h > 0) {
            const preview_ctx = ctx.withConstraints(
                .{ .width = max.width, .height = preview_h },
                vxfw.MaxSize.fromSize(.{ .width = max.width, .height = preview_h }),
            );
            const preview_surface = try self.preview_pane.widget().draw(preview_ctx);
            self.children[child_idx] = .{
                .origin = .{ .row = @intCast(tab_bar_height + editor_h), .col = 0 },
                .surface = preview_surface,
            };
            child_idx += 1;
        }
    }

    self.status_bar.line = self.editor_pane.cursor_line;
    self.status_bar.col = self.editor_pane.cursor_col;
    self.status_bar.modified = self.editor_pane.modified;
    if (self.active_tab < self.buffers.items.len) {
        self.status_bar.filename = self.buffers.items[self.active_tab].filename;
    }

    if (self.preview_pane.selected_node) |node_idx| {
        self.status_bar.setContextInfo("Node: {d}", .{node_idx});
    } else {
        self.status_bar.context_info = "";
    }

    const status_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = status_height },
        vxfw.MaxSize.fromSize(.{ .width = max.width, .height = status_height }),
    );
    const status_surface = try self.status_bar.widget().draw(status_ctx);

    self.children[child_idx] = .{
        .origin = .{ .row = @intCast(tab_bar_height + content_height), .col = 0 },
        .surface = status_surface,
    };
    child_idx += 1;

    if (self.keybindings.visible) {
        const kb_ctx = ctx.withConstraints(
            .{ .width = max.width, .height = max.height },
            vxfw.MaxSize.fromSize(.{ .width = max.width, .height = max.height }),
        );
        const kb_surface = try self.keybindings.widget().draw(kb_ctx);
        self.children[child_idx] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = kb_surface,
        };
        child_idx += 1;
    }

    if (self.command_palette.visible) {
        const cp_ctx = ctx.withConstraints(
            .{ .width = max.width, .height = max.height },
            vxfw.MaxSize.fromSize(.{ .width = max.width, .height = max.height }),
        );
        const cp_surface = try self.command_palette.widget().draw(cp_ctx);
        self.children[child_idx] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = cp_surface,
        };
        child_idx += 1;
    }

    if (self.completion.visible) {
        // Calculate max items and popup dimensions to position near cursor.
        var max_text_len: usize = 0;
        for (self.completion.items) |it| {
            if (it.text.len > max_text_len) max_text_len = it.text.len;
        }
        const popup_w: u16 = @intCast(@min(max_text_len + 4, max.width));
        const max_rows: usize = 8;
        const visible_rows: u16 = @intCast(@min(self.completion.items.len, max_rows));
        const popup_h: u16 = visible_rows + 2;

        // Position popup just below the cursor in the editor area.
        const gutter_width: u16 = 5;
        const cursor_screen_col: u16 = gutter_width + @as(u16, @intCast(self.editor_pane.cursor_col));
        const cursor_screen_row: u16 = @intCast(
            tab_bar_height + self.editor_pane.cursor_line -| self.editor_pane.scroll_top,
        );
        // Place popup below the cursor row; clamp so it stays on screen.
        const popup_row: u16 = @min(cursor_screen_row + 1, max.height -| popup_h);
        const popup_col: u16 = if (cursor_screen_col + popup_w <= max.width)
            cursor_screen_col
        else
            max.width -| popup_w;

        const comp_ctx = ctx.withConstraints(
            .{ .width = popup_w, .height = popup_h },
            vxfw.MaxSize.fromSize(.{ .width = popup_w, .height = popup_h }),
        );
        const comp_surface = try self.completion.widget().draw(comp_ctx);
        self.children[child_idx] = .{
            .origin = .{ .row = popup_row, .col = popup_col },
            .surface = comp_surface,
        };
        child_idx += 1;
    }

    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = self.children[0..child_idx],
    };
}
