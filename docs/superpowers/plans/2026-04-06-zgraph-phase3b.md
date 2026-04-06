# Phase 3b: TUI Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a terminal-based split-pane editor (`zigraph edit`) for `.zgraph` files with live graph preview, syntax highlighting, autocomplete, go-to-definition, bidirectional source-graph linking, node drag/pin, tabs, undo/redo, and a fuzzy-find command palette.

**Architecture:** libvaxis vxfw widget framework drives the event loop and rendering. The app is a tree of custom widgets: App (root) → TabBar + SplitView(EditorPane, PreviewPane) + StatusBar, with overlay widgets for CommandPalette, Completion, and Keybindings help. Pure-data modules (TextBuffer, UndoManager, SourceMap, Definitions, Highlighter) have no TUI dependency and are unit-tested independently.

**Tech Stack:** Zig 0.15, libvaxis 0.5.x (vxfw high-level API), zigraph (self — DSL tokenizer/parser/resolver/bridge, terminal renderer, RenderPlan + hit-testing)

---

## File Structure

### New files to create

| File | Responsibility |
|---|---|
| `src/tui/text_buffer.zig` | Piece table: insert, delete, line access, coordinate conversion |
| `src/tui/undo.zig` | Operation-based undo/redo with edit grouping |
| `src/tui/highlighter.zig` | TokenKind → vaxis Style mapping, error overlays |
| `src/tui/source_map.zig` | Bidirectional AST Loc ↔ graph node/edge index |
| `src/tui/definitions.zig` | Go-to-definition index (imports, vars, classes, nodes) |
| `src/tui/completion.zig` | Autocomplete: context detection, completion sources, fuzzy scoring |
| `src/tui/app.zig` | Root vxfw widget: event loop, focus, debounce, parse pipeline |
| `src/tui/editor_pane.zig` | Text editor widget: display, cursor, selection, editing |
| `src/tui/preview_pane.zig` | Graph preview widget: RenderPlan → cells, hit-test, drag/nudge/pin |
| `src/tui/status_bar.zig` | Bottom info line + toggleable context panel |
| `src/tui/tab_bar.zig` | File tab strip, auto-hide with 1 file |
| `src/tui/command_palette.zig` | Fuzzy-find overlay, command registry |
| `src/tui/keybindings.zig` | Keybinding registry + help screen overlay |
| `src/tui/main.zig` | Entry point: arg parsing, App init, run |

### Files to modify

| File | Change |
|---|---|
| `build.zig.zon` | Add libvaxis dependency |
| `build.zig` | Add vaxis import, TUI executable target, test target |
| `src/cli/main.zig` | Add `edit` subcommand that execs `zigraph-edit` or dispatches to tui/main |

---

## Task 1: Add libvaxis Dependency + Minimal TUI Shell

**Files:**
- Modify: `build.zig.zon`
- Modify: `build.zig:828-855` (after CLI section)
- Create: `src/tui/main.zig`

- [ ] **Step 1: Add libvaxis to build.zig.zon**

Run:
```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl && zig fetch --save git+https://github.com/rockorager/libvaxis.git
```

This auto-inserts the dependency with hash.

- [ ] **Step 2: Verify build.zig.zon was updated**

Run: `cat build.zig.zon`
Expected: `.vaxis` entry under `.dependencies`

- [ ] **Step 3: Create minimal src/tui/main.zig**

```zig
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
```

- [ ] **Step 4: Wire TUI executable in build.zig**

Add after the CLI section (around line 855):

```zig
    // TUI editor executable
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const tui_mod = b.createModule(.{
        .root_source_file = b.path("src/tui/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
            .{ .name = "dsl", .module = dsl_mod },
            .{ .name = "vaxis", .module = vaxis_dep.module("vaxis") },
        },
    });

    const tui_exe = b.addExecutable(.{
        .name = "zigraph-edit",
        .root_module = tui_mod,
    });
    b.installArtifact(tui_exe);

    const run_tui_edit = b.addRunArtifact(tui_exe);
    if (b.args) |a| run_tui_edit.addArgs(a);
    const run_tui_edit_step = b.step("run-edit", "Run the TUI editor");
    run_tui_edit_step.dependOn(&run_tui_edit.step);

    // TUI unit tests
    const tui_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tui/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
                .{ .name = "dsl", .module = dsl_mod },
                .{ .name = "vaxis", .module = vaxis_dep.module("vaxis") },
            },
        }),
    });
    const run_tui_tests = b.addRunArtifact(tui_tests);
    const tui_test_step = b.step("test-tui", "Run TUI unit tests");
    tui_test_step.dependOn(&run_tui_tests.step);
    test_step.dependOn(&run_tui_tests.step);
```

- [ ] **Step 5: Build and verify**

Run: `zig build run-edit`
Expected: Terminal enters alt screen, shows "zigraph editor — press 'q' to quit". Press 'q' to exit cleanly.

- [ ] **Step 6: Commit**

```bash
git add build.zig.zon build.zig src/tui/main.zig
git commit -m "feat(tui): add libvaxis dependency and minimal editor shell"
```

---

## Task 2: TextBuffer — Piece Table Implementation

**Files:**
- Create: `src/tui/text_buffer.zig`

This is a pure data structure with no TUI dependency. Piece table stores original file content immutably, all insertions go into an append-only add buffer, and a piece list describes the document as spans into either buffer.

- [ ] **Step 1: Write the failing tests**

```zig
const std = @import("std");
const TextBuffer = @This();

// ... (implementation comes in step 3)

test "init empty" {
    var buf = try TextBuffer.init(std.testing.allocator, "");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 0), buf.lineCount());
}

test "init with content" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello\nworld\n");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 3), buf.lineCount());
    const line0 = try buf.lineAt(0);
    defer std.testing.allocator.free(line0);
    try std.testing.expectEqualStrings("hello", line0);
}

test "insert at beginning" {
    var buf = try TextBuffer.init(std.testing.allocator, "world");
    defer buf.deinit();
    try buf.insert(0, "hello ");
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello world", full);
}

test "insert in middle" {
    var buf = try TextBuffer.init(std.testing.allocator, "helo");
    defer buf.deinit();
    try buf.insert(2, "l");
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello", full);
}

test "insert at end" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    try buf.insert(5, " world");
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello world", full);
}

test "delete from beginning" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello world");
    defer buf.deinit();
    const deleted = try buf.delete(0, 6);
    defer std.testing.allocator.free(deleted);
    try std.testing.expectEqualStrings("hello ", deleted);
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("world", full);
}

test "delete in middle" {
    var buf = try TextBuffer.init(std.testing.allocator, "helllo");
    defer buf.deinit();
    const deleted = try buf.delete(2, 1);
    defer std.testing.allocator.free(deleted);
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello", full);
}

test "lineCount with newlines" {
    var buf = try TextBuffer.init(std.testing.allocator, "a\nb\nc");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 3), buf.lineCount());
}

test "lineAt multiline" {
    var buf = try TextBuffer.init(std.testing.allocator, "line1\nline2\nline3");
    defer buf.deinit();
    const l0 = try buf.lineAt(0);
    defer std.testing.allocator.free(l0);
    try std.testing.expectEqualStrings("line1", l0);
    const l1 = try buf.lineAt(1);
    defer std.testing.allocator.free(l1);
    try std.testing.expectEqualStrings("line2", l1);
    const l2 = try buf.lineAt(2);
    defer std.testing.allocator.free(l2);
    try std.testing.expectEqualStrings("line3", l2);
}

test "positionToLineCol and lineColToPosition roundtrip" {
    var buf = try TextBuffer.init(std.testing.allocator, "ab\ncd\nef");
    defer buf.deinit();
    // 'c' is at offset 3, which is line 1 col 0
    const lc = buf.positionToLineCol(3);
    try std.testing.expectEqual(@as(usize, 1), lc.line);
    try std.testing.expectEqual(@as(usize, 0), lc.col);
    const pos = buf.lineColToPosition(1, 0);
    try std.testing.expectEqual(@as(usize, 3), pos);
}

test "slice" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello world");
    defer buf.deinit();
    const s = try buf.slice(std.testing.allocator, 6, 11);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("world", s);
}

test "insert newline increases line count" {
    var buf = try TextBuffer.init(std.testing.allocator, "ab");
    defer buf.deinit();
    try buf.insert(1, "\n");
    try std.testing.expectEqual(@as(usize, 2), buf.lineCount());
}

test "totalLen" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 5), buf.totalLen());
    try buf.insert(5, " world");
    try std.testing.expectEqual(@as(usize, 11), buf.totalLen());
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test-tui 2>&1 | head -20`
Expected: Compilation error (TextBuffer not yet implemented)

- [ ] **Step 3: Implement TextBuffer**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const TextBuffer = @This();

const Source = enum { original, add };

const Piece = struct {
    source: Source,
    start: usize,
    len: usize,
};

allocator: Allocator,
original: []const u8,
add_buf: std.ArrayListUnmanaged(u8),
pieces: std.ArrayListUnmanaged(Piece),

pub fn init(allocator: Allocator, content: []const u8) !TextBuffer {
    var pieces: std.ArrayListUnmanaged(Piece) = .{};
    if (content.len > 0) {
        try pieces.append(allocator, .{ .source = .original, .start = 0, .len = content.len });
    }
    const owned = try allocator.dupe(u8, content);
    return .{
        .allocator = allocator,
        .original = owned,
        .add_buf = .{},
        .pieces = pieces,
    };
}

pub fn deinit(self: *TextBuffer) void {
    self.allocator.free(self.original);
    self.add_buf.deinit(self.allocator);
    self.pieces.deinit(self.allocator);
}

fn bufferSlice(self: *const TextBuffer, piece: Piece) []const u8 {
    const buf = switch (piece.source) {
        .original => self.original,
        .add => self.add_buf.items,
    };
    return buf[piece.start..piece.start + piece.len];
}

pub fn totalLen(self: *const TextBuffer) usize {
    var len: usize = 0;
    for (self.pieces.items) |p| len += p.len;
    return len;
}

/// Insert text at byte position `pos`.
pub fn insert(self: *TextBuffer, pos: usize, text: []const u8) !void {
    if (text.len == 0) return;
    const add_start = self.add_buf.items.len;
    try self.add_buf.appendSlice(self.allocator, text);
    const new_piece = Piece{ .source = .add, .start = add_start, .len = text.len };

    // Find which piece and offset within it
    var offset: usize = 0;
    for (self.pieces.items, 0..) |p, i| {
        if (pos >= offset and pos <= offset + p.len) {
            const local = pos - offset;
            if (local == 0) {
                // Insert before this piece
                try self.pieces.insert(self.allocator, i, new_piece);
                return;
            } else if (local == p.len) {
                // Insert after this piece
                try self.pieces.insert(self.allocator, i + 1, new_piece);
                return;
            } else {
                // Split this piece
                const left = Piece{ .source = p.source, .start = p.start, .len = local };
                const right = Piece{ .source = p.source, .start = p.start + local, .len = p.len - local };
                self.pieces.items[i] = left;
                try self.pieces.insert(self.allocator, i + 1, new_piece);
                try self.pieces.insert(self.allocator, i + 2, right);
                return;
            }
        }
        offset += p.len;
    }
    // Append at end
    try self.pieces.append(self.allocator, new_piece);
}

/// Delete `len` bytes starting at `pos`. Returns the deleted text.
pub fn delete(self: *TextBuffer, pos: usize, len: usize) ![]u8 {
    if (len == 0) return try self.allocator.alloc(u8, 0);

    // First, extract the text being deleted (for undo)
    const deleted = try self.slice(self.allocator, pos, pos + len);

    // Now remove the range by rebuilding affected pieces
    var remaining_pos = pos;
    var remaining_len = len;
    var i: usize = 0;
    var offset: usize = 0;

    while (i < self.pieces.items.len and remaining_len > 0) {
        const p = self.pieces.items[i];
        const piece_end = offset + p.len;

        if (remaining_pos >= piece_end) {
            // This piece is entirely before the delete range
            offset = piece_end;
            i += 1;
            continue;
        }

        const local_start = if (remaining_pos > offset) remaining_pos - offset else 0;
        const local_end = @min(local_start + remaining_len, p.len);
        const delete_in_piece = local_end - local_start;

        if (local_start == 0 and local_end == p.len) {
            // Delete entire piece
            _ = self.pieces.orderedRemove(i);
            remaining_len -= delete_in_piece;
            remaining_pos += delete_in_piece;
            // Don't increment i
        } else if (local_start == 0) {
            // Delete from start of piece
            self.pieces.items[i] = .{ .source = p.source, .start = p.start + local_end, .len = p.len - local_end };
            remaining_len -= delete_in_piece;
            remaining_pos += delete_in_piece;
            i += 1;
            offset = piece_end - delete_in_piece;
        } else if (local_end == p.len) {
            // Delete from end of piece
            self.pieces.items[i] = .{ .source = p.source, .start = p.start, .len = local_start };
            remaining_len -= delete_in_piece;
            remaining_pos += delete_in_piece;
            i += 1;
            offset = offset + local_start;
        } else {
            // Delete from middle — split into two
            const left = Piece{ .source = p.source, .start = p.start, .len = local_start };
            const right = Piece{ .source = p.source, .start = p.start + local_end, .len = p.len - local_end };
            self.pieces.items[i] = left;
            try self.pieces.insert(self.allocator, i + 1, right);
            remaining_len -= delete_in_piece;
            remaining_pos += delete_in_piece;
            i += 2;
            offset = offset + local_start + right.len;
        }
    }

    return deleted;
}

/// Materialize the full buffer content.
pub fn contents(self: *const TextBuffer, allocator: Allocator) ![]u8 {
    const total = self.totalLen();
    var result = try allocator.alloc(u8, total);
    var pos: usize = 0;
    for (self.pieces.items) |p| {
        const s = self.bufferSlice(p);
        @memcpy(result[pos..pos + s.len], s);
        pos += s.len;
    }
    return result;
}

/// Extract a byte range [start, end).
pub fn slice(self: *const TextBuffer, allocator: Allocator, start: usize, end: usize) ![]u8 {
    const len = end - start;
    var result = try allocator.alloc(u8, len);
    var written: usize = 0;
    var offset: usize = 0;
    for (self.pieces.items) |p| {
        const piece_end = offset + p.len;
        if (piece_end <= start) {
            offset = piece_end;
            continue;
        }
        if (offset >= end) break;

        const local_start = if (start > offset) start - offset else 0;
        const local_end = @min(end - offset, p.len);
        const s = self.bufferSlice(p);
        const chunk = s[local_start..local_end];
        @memcpy(result[written..written + chunk.len], chunk);
        written += chunk.len;
        offset = piece_end;
    }
    return result;
}

/// Count the number of lines (text after last \n counts as a line).
pub fn lineCount(self: *const TextBuffer) usize {
    if (self.totalLen() == 0) return 0;
    var count: usize = 1;
    for (self.pieces.items) |p| {
        const s = self.bufferSlice(p);
        for (s) |c| {
            if (c == '\n') count += 1;
        }
    }
    return count;
}

/// Get the content of line `line_num` (0-based), excluding the trailing \n.
pub fn lineAt(self: *const TextBuffer, line_num: usize) ![]u8 {
    var current_line: usize = 0;
    var line_start: usize = 0;
    var offset: usize = 0;

    // Find the byte offset of the target line
    if (line_num > 0) {
        for (self.pieces.items) |p| {
            const s = self.bufferSlice(p);
            for (s) |c| {
                if (c == '\n') {
                    current_line += 1;
                    if (current_line == line_num) {
                        line_start = offset + 1;
                        break;
                    }
                }
                offset += 1;
            } else {
                offset += 0; // loop completed normally
            }
            if (current_line == line_num) break;
            // Adjust offset: it was incremented per char in the for loop
            // Actually we need to re-count. Let me restructure.
        }
        // Simpler approach: iterate all bytes
        line_start = 0;
        current_line = 0;
        offset = 0;
        for (self.pieces.items) |p| {
            const s = self.bufferSlice(p);
            for (s) |c| {
                if (c == '\n') {
                    current_line += 1;
                    if (current_line == line_num) {
                        line_start = offset + 1;
                    }
                }
                offset += 1;
            }
        }
    }

    // Find the end of this line
    var line_end = self.totalLen();
    offset = 0;
    current_line = 0;
    for (self.pieces.items) |p| {
        const s = self.bufferSlice(p);
        for (s) |c| {
            if (c == '\n') {
                if (current_line == line_num) {
                    line_end = offset;
                    return self.slice(self.allocator, line_start, line_end);
                }
                current_line += 1;
            }
            offset += 1;
        }
    }
    // Last line (no trailing \n)
    return self.slice(self.allocator, line_start, line_end);
}

pub const LineCol = struct { line: usize, col: usize };

/// Convert a byte position to (line, col), 0-based.
pub fn positionToLineCol(self: *const TextBuffer, pos: usize) LineCol {
    var line: usize = 0;
    var col: usize = 0;
    var offset: usize = 0;
    for (self.pieces.items) |p| {
        const s = self.bufferSlice(p);
        for (s) |c| {
            if (offset == pos) return .{ .line = line, .col = col };
            if (c == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
            offset += 1;
        }
    }
    return .{ .line = line, .col = col };
}

/// Convert (line, col) to byte position, 0-based.
pub fn lineColToPosition(self: *const TextBuffer, line: usize, col: usize) usize {
    var current_line: usize = 0;
    var current_col: usize = 0;
    var offset: usize = 0;
    for (self.pieces.items) |p| {
        const s = self.bufferSlice(p);
        for (s) |c| {
            if (current_line == line and current_col == col) return offset;
            if (c == '\n') {
                current_line += 1;
                current_col = 0;
            } else {
                current_col += 1;
            }
            offset += 1;
        }
    }
    return offset;
}

// Tests at end of file — see Step 1 for all test cases
test "init empty" {
    var buf = try TextBuffer.init(std.testing.allocator, "");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 0), buf.lineCount());
}

test "init with content" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello\nworld\n");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 3), buf.lineCount());
    const line0 = try buf.lineAt(0);
    defer std.testing.allocator.free(line0);
    try std.testing.expectEqualStrings("hello", line0);
}

test "insert at beginning" {
    var buf = try TextBuffer.init(std.testing.allocator, "world");
    defer buf.deinit();
    try buf.insert(0, "hello ");
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello world", full);
}

test "insert in middle" {
    var buf = try TextBuffer.init(std.testing.allocator, "helo");
    defer buf.deinit();
    try buf.insert(2, "l");
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello", full);
}

test "insert at end" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    try buf.insert(5, " world");
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello world", full);
}

test "delete from beginning" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello world");
    defer buf.deinit();
    const deleted = try buf.delete(0, 6);
    defer std.testing.allocator.free(deleted);
    try std.testing.expectEqualStrings("hello ", deleted);
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("world", full);
}

test "delete in middle" {
    var buf = try TextBuffer.init(std.testing.allocator, "helllo");
    defer buf.deinit();
    const deleted = try buf.delete(2, 1);
    defer std.testing.allocator.free(deleted);
    const full = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(full);
    try std.testing.expectEqualStrings("hello", full);
}

test "lineCount with newlines" {
    var buf = try TextBuffer.init(std.testing.allocator, "a\nb\nc");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 3), buf.lineCount());
}

test "lineAt multiline" {
    var buf = try TextBuffer.init(std.testing.allocator, "line1\nline2\nline3");
    defer buf.deinit();
    const l0 = try buf.lineAt(0);
    defer std.testing.allocator.free(l0);
    try std.testing.expectEqualStrings("line1", l0);
    const l1 = try buf.lineAt(1);
    defer std.testing.allocator.free(l1);
    try std.testing.expectEqualStrings("line2", l1);
    const l2 = try buf.lineAt(2);
    defer std.testing.allocator.free(l2);
    try std.testing.expectEqualStrings("line3", l2);
}

test "positionToLineCol and lineColToPosition roundtrip" {
    var buf = try TextBuffer.init(std.testing.allocator, "ab\ncd\nef");
    defer buf.deinit();
    const lc = buf.positionToLineCol(3);
    try std.testing.expectEqual(@as(usize, 1), lc.line);
    try std.testing.expectEqual(@as(usize, 0), lc.col);
    const pos = buf.lineColToPosition(1, 0);
    try std.testing.expectEqual(@as(usize, 3), pos);
}

test "slice" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello world");
    defer buf.deinit();
    const s = try buf.slice(std.testing.allocator, 6, 11);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("world", s);
}

test "insert newline increases line count" {
    var buf = try TextBuffer.init(std.testing.allocator, "ab");
    defer buf.deinit();
    try buf.insert(1, "\n");
    try std.testing.expectEqual(@as(usize, 2), buf.lineCount());
}

test "totalLen" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 5), buf.totalLen());
    try buf.insert(5, " world");
    try std.testing.expectEqual(@as(usize, 11), buf.totalLen());
}
```

- [ ] **Step 4: Add text_buffer to main.zig imports**

In `src/tui/main.zig`, add at the top:
```zig
const TextBuffer = @import("text_buffer.zig");
```

And add a `comptime` block or `test` reference to pull in the tests:
```zig
test {
    _ = @import("text_buffer.zig");
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `zig build test-tui 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add src/tui/text_buffer.zig src/tui/main.zig
git commit -m "feat(tui): add piece table TextBuffer with full test suite"
```

---

## Task 3: UndoManager — Operation-Based Undo/Redo

**Files:**
- Create: `src/tui/undo.zig`
- Modify: `src/tui/main.zig` (add test import)

- [ ] **Step 1: Write the failing tests**

```zig
test "single insert undo" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 5, " world");
    const c1 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c1);
    try std.testing.expectEqualStrings("hello world", c1);
    try undo.undo(&buf);
    const c2 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c2);
    try std.testing.expectEqualStrings("hello", c2);
}

test "single delete undo" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello world");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.deleteText(&buf, 5, 6);
    const c1 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c1);
    try std.testing.expectEqualStrings("hello", c1);
    try undo.undo(&buf);
    const c2 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c2);
    try std.testing.expectEqualStrings("hello world", c2);
}

test "redo after undo" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 5, " world");
    try undo.undo(&buf);
    try undo.redo(&buf);
    const c = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c);
    try std.testing.expectEqualStrings("hello world", c);
}

test "new edit clears redo stack" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 5, " world");
    try undo.undo(&buf);
    try undo.insertText(&buf, 5, "!");
    try std.testing.expectEqual(@as(usize, 0), undo.redo_stack.items.len);
}

test "multiple undo redo sequence" {
    var buf = try TextBuffer.init(std.testing.allocator, "");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 0, "a");
    try undo.breakGroup();
    try undo.insertText(&buf, 1, "b");
    try undo.breakGroup();
    try undo.insertText(&buf, 2, "c");
    try undo.breakGroup();
    try undo.undo(&buf);
    const c1 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c1);
    try std.testing.expectEqualStrings("ab", c1);
    try undo.undo(&buf);
    const c2 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c2);
    try std.testing.expectEqualStrings("a", c2);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test-tui 2>&1 | head -5`
Expected: Compilation error

- [ ] **Step 3: Implement UndoManager**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const TextBuffer = @import("text_buffer.zig");

const UndoManager = @This();

pub const EditOp = union(enum) {
    insert: struct { pos: usize, text: []const u8 },
    delete: struct { pos: usize, text: []const u8 },
};

pub const EditGroup = struct {
    ops: std.ArrayListUnmanaged(EditOp),

    pub fn deinit(self: *EditGroup, allocator: Allocator) void {
        for (self.ops.items) |op| {
            switch (op) {
                .insert => |ins| allocator.free(ins.text),
                .delete => |del| allocator.free(del.text),
            }
        }
        self.ops.deinit(allocator);
    }
};

allocator: Allocator,
undo_stack: std.ArrayListUnmanaged(EditGroup),
redo_stack: std.ArrayListUnmanaged(EditGroup),
current_group: ?EditGroup,

pub fn init(allocator: Allocator) UndoManager {
    return .{
        .allocator = allocator,
        .undo_stack = .{},
        .redo_stack = .{},
        .current_group = null,
    };
}

pub fn deinit(self: *UndoManager) void {
    if (self.current_group) |*g| g.deinit(self.allocator);
    for (self.undo_stack.items) |*g| g.deinit(self.allocator);
    self.undo_stack.deinit(self.allocator);
    for (self.redo_stack.items) |*g| g.deinit(self.allocator);
    self.redo_stack.deinit(self.allocator);
}

fn ensureGroup(self: *UndoManager) !*EditGroup {
    if (self.current_group == null) {
        self.current_group = .{ .ops = .{} };
    }
    return &self.current_group.?;
}

pub fn breakGroup(self: *UndoManager) !void {
    if (self.current_group) |g| {
        if (g.ops.items.len > 0) {
            try self.undo_stack.append(self.allocator, g);
        } else {
            var mg = g;
            mg.deinit(self.allocator);
        }
        self.current_group = null;
    }
}

fn clearRedoStack(self: *UndoManager) void {
    for (self.redo_stack.items) |*g| g.deinit(self.allocator);
    self.redo_stack.items.len = 0;
}

pub fn insertText(self: *UndoManager, buf: *TextBuffer, pos: usize, text: []const u8) !void {
    try buf.insert(pos, text);
    self.clearRedoStack();
    const group = try self.ensureGroup();
    const owned = try self.allocator.dupe(u8, text);
    try group.ops.append(self.allocator, .{ .insert = .{ .pos = pos, .text = owned } });
}

pub fn deleteText(self: *UndoManager, buf: *TextBuffer, pos: usize, len: usize) !void {
    const deleted = try buf.delete(pos, len);
    self.clearRedoStack();
    const group = try self.ensureGroup();
    try group.ops.append(self.allocator, .{ .delete = .{ .pos = pos, .text = deleted } });
}

pub fn undo(self: *UndoManager, buf: *TextBuffer) !void {
    try self.breakGroup();
    if (self.undo_stack.items.len == 0) return;
    var group = self.undo_stack.pop();
    // Apply ops in reverse
    var i = group.ops.items.len;
    while (i > 0) {
        i -= 1;
        const op = group.ops.items[i];
        switch (op) {
            .insert => |ins| {
                const d = try buf.delete(ins.pos, ins.text.len);
                self.allocator.free(d);
            },
            .delete => |del| {
                try buf.insert(del.pos, del.text);
            },
        }
    }
    try self.redo_stack.append(self.allocator, group);
}

pub fn redo(self: *UndoManager, buf: *TextBuffer) !void {
    if (self.redo_stack.items.len == 0) return;
    var group = self.redo_stack.pop();
    // Apply ops forward
    for (group.ops.items) |op| {
        switch (op) {
            .insert => |ins| {
                try buf.insert(ins.pos, ins.text);
            },
            .delete => |del| {
                const d = try buf.delete(del.pos, del.text.len);
                self.allocator.free(d);
            },
        }
    }
    try self.undo_stack.append(self.allocator, group);
}

// Tests — see Step 1 for all test cases
test "single insert undo" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 5, " world");
    const c1 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c1);
    try std.testing.expectEqualStrings("hello world", c1);
    try undo.undo(&buf);
    const c2 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c2);
    try std.testing.expectEqualStrings("hello", c2);
}

test "single delete undo" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello world");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.deleteText(&buf, 5, 6);
    const c1 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c1);
    try std.testing.expectEqualStrings("hello", c1);
    try undo.undo(&buf);
    const c2 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c2);
    try std.testing.expectEqualStrings("hello world", c2);
}

test "redo after undo" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 5, " world");
    try undo.undo(&buf);
    try undo.redo(&buf);
    const c = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c);
    try std.testing.expectEqualStrings("hello world", c);
}

test "new edit clears redo stack" {
    var buf = try TextBuffer.init(std.testing.allocator, "hello");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 5, " world");
    try undo.undo(&buf);
    try undo.insertText(&buf, 5, "!");
    try std.testing.expectEqual(@as(usize, 0), undo.redo_stack.items.len);
}

test "multiple undo redo sequence" {
    var buf = try TextBuffer.init(std.testing.allocator, "");
    defer buf.deinit();
    var undo = UndoManager.init(std.testing.allocator);
    defer undo.deinit();
    try undo.insertText(&buf, 0, "a");
    try undo.breakGroup();
    try undo.insertText(&buf, 1, "b");
    try undo.breakGroup();
    try undo.insertText(&buf, 2, "c");
    try undo.breakGroup();
    try undo.undo(&buf);
    const c1 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c1);
    try std.testing.expectEqualStrings("ab", c1);
    try undo.undo(&buf);
    const c2 = try buf.contents(std.testing.allocator);
    defer std.testing.allocator.free(c2);
    try std.testing.expectEqualStrings("a", c2);
}
```

- [ ] **Step 4: Add undo import to main.zig test block**

```zig
test {
    _ = @import("text_buffer.zig");
    _ = @import("undo.zig");
}
```

- [ ] **Step 5: Run tests**

Run: `zig build test-tui 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add src/tui/undo.zig src/tui/main.zig
git commit -m "feat(tui): add UndoManager with operation-based undo/redo and grouping"
```

---

## Task 4: Highlighter — Token-to-Style Mapping

**Files:**
- Create: `src/tui/highlighter.zig`
- Modify: `src/tui/main.zig` (add test import)

- [ ] **Step 1: Write the failing tests**

```zig
test "identifier gets default style" {
    const style = Highlighter.styleForToken(.identifier);
    try std.testing.expectEqual(vaxis.Color.default, style.fg);
}

test "string gets green" {
    const style = Highlighter.styleForToken(.string);
    try std.testing.expect(style.fg == .{ .index = 2 } or style.fg == .{ .rgb = .{ 0, 180, 0 } });
}

test "comment gets dim" {
    const style = Highlighter.styleForToken(.comment);
    try std.testing.expect(style.dim);
}

test "at_keyword gets bold" {
    const style = Highlighter.styleForToken(.at_keyword);
    try std.testing.expect(style.bold);
}

test "arrow gets cyan" {
    const style = Highlighter.styleForToken(.arrow);
    // Just check it's not default
    try std.testing.expect(style.fg != .default);
}

test "tokenize source returns styled spans" {
    const spans = try Highlighter.tokenizeToSpans(std.testing.allocator, "A -> B # comment");
    defer std.testing.allocator.free(spans);
    try std.testing.expect(spans.len > 0);
}
```

- [ ] **Step 2: Implement Highlighter**

Maps `dsl.tokenizer.TokenKind` → `vaxis.Style`. Also provides `tokenizeToSpans()` which runs the DSL tokenizer and returns an array of `StyledSpan` (start offset, length, style) for the editor to use when rendering lines.

The implementation uses the DSL tokenizer directly — no separate highlighting engine needed.

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const dsl = @import("dsl");
const TokenKind = dsl.tokenizer.TokenKind;
const Token = dsl.tokenizer.Token;
const errors = dsl.errors;

const Highlighter = @This();

pub const StyledSpan = struct {
    start: usize,  // byte offset in source
    len: usize,
    style: vaxis.Style,
};

pub fn styleForToken(kind: TokenKind) vaxis.Style {
    return switch (kind) {
        .identifier => .{},
        .string => .{ .fg = .{ .index = 2 } },  // green
        .at_keyword => .{ .fg = .{ .index = 5 }, .bold = true },  // magenta bold
        .comment => .{ .fg = .{ .index = 8 }, .dim = true },  // gray dim
        .arrow, .arrow_reverse, .dash_dash, .arrow_bidi,
        .fat_arrow, .fat_arrow2, .dashed_arrow, .dotted_arrow, .dotted_line,
        => .{ .fg = .{ .index = 6 } },  // cyan
        .lbrace, .rbrace, .lbracket, .rbracket => .{ .fg = .{ .index = 3 } },  // yellow
        .colon, .comma, .semicolon => .{ .dim = true },
        .pipe => .{ .fg = .{ .index = 3 } },  // yellow
        .class => .{ .fg = .{ .index = 4 } },  // blue
        .dot => .{},
        .newline, .eof => .{},
    };
}

pub fn tokenizeToSpans(allocator: std.mem.Allocator, source: []const u8) ![]StyledSpan {
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    const tokens = dsl.tokenizer.tokenize(allocator, source, &err_list) catch return try allocator.alloc(StyledSpan, 0);
    defer allocator.free(tokens);

    var spans: std.ArrayListUnmanaged(StyledSpan) = .{};
    defer spans.deinit(allocator);

    for (tokens) |tok| {
        if (tok.kind == .newline or tok.kind == .eof) continue;
        try spans.append(allocator, .{
            .start = tok.loc.offset,
            .len = tok.text.len,
            .style = styleForToken(tok.kind),
        });
    }

    return try spans.toOwnedSlice(allocator);
}

// Error overlay styles
pub const error_underline: vaxis.Style = .{
    .ul = .{ .index = 1 },  // red
    .ul_style = .curly,
};

pub const warning_underline: vaxis.Style = .{
    .ul = .{ .index = 3 },  // yellow
    .ul_style = .curly,
};

// tests...
```

- [ ] **Step 3: Run tests**

Run: `zig build test-tui 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add src/tui/highlighter.zig src/tui/main.zig
git commit -m "feat(tui): add Highlighter for syntax-aware token-to-style mapping"
```

---

## Task 5: SourceMap — Bidirectional Source-Graph Linking

**Files:**
- Create: `src/tui/source_map.zig`
- Modify: `src/tui/main.zig` (add test import)

SourceMap stores two mappings rebuilt on every successful parse:
- `node_index → Loc` and `edge_index → Loc` (graph element → source position)
- Reverse lookup: given a source offset, find which graph node/edge it belongs to

- [ ] **Step 1: Write the failing tests**

```zig
test "add and lookup node" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addNode(0, .{ .line = 1, .col = 1, .offset = 0 }, 5);
    const result = sm.nodeAtOffset(2);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 0), result.?);
}

test "add and lookup edge" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addEdge(0, .{ .line = 1, .col = 3, .offset = 2 }, 4);
    const result = sm.edgeAtOffset(3);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 0), result.?);
}

test "locForNode" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    const loc = dsl.errors.Loc{ .line = 5, .col = 1, .offset = 40 };
    try sm.addNode(3, loc, 8);
    const result = sm.locForNode(3);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u32, 5), result.?.line);
}

test "offset outside any span returns null" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addNode(0, .{ .line = 1, .col = 1, .offset = 0 }, 3);
    const result = sm.nodeAtOffset(10);
    try std.testing.expect(result == null);
}

test "clear resets all mappings" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addNode(0, .{ .line = 1, .col = 1, .offset = 0 }, 3);
    sm.clear();
    try std.testing.expect(sm.nodeAtOffset(1) == null);
}
```

- [ ] **Step 2: Implement SourceMap**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const dsl = @import("dsl");
const Loc = dsl.errors.Loc;

const SourceMap = @This();

const NodeEntry = struct {
    node_index: usize,
    loc: Loc,
    len: usize,  // byte length of the source span for this node
};

const EdgeEntry = struct {
    edge_index: usize,
    loc: Loc,
    len: usize,
};

allocator: Allocator,
nodes: std.ArrayListUnmanaged(NodeEntry),
edges: std.ArrayListUnmanaged(EdgeEntry),

pub fn init(allocator: Allocator) SourceMap {
    return .{
        .allocator = allocator,
        .nodes = .{},
        .edges = .{},
    };
}

pub fn deinit(self: *SourceMap) void {
    self.nodes.deinit(self.allocator);
    self.edges.deinit(self.allocator);
}

pub fn clear(self: *SourceMap) void {
    self.nodes.items.len = 0;
    self.edges.items.len = 0;
}

pub fn addNode(self: *SourceMap, node_index: usize, loc: Loc, len: usize) !void {
    try self.nodes.append(self.allocator, .{ .node_index = node_index, .loc = loc, .len = len });
}

pub fn addEdge(self: *SourceMap, edge_index: usize, loc: Loc, len: usize) !void {
    try self.edges.append(self.allocator, .{ .edge_index = edge_index, .loc = loc, .len = len });
}

pub fn nodeAtOffset(self: *const SourceMap, offset: usize) ?usize {
    for (self.nodes.items) |entry| {
        if (offset >= entry.loc.offset and offset < entry.loc.offset + entry.len) {
            return entry.node_index;
        }
    }
    return null;
}

pub fn edgeAtOffset(self: *const SourceMap, offset: usize) ?usize {
    for (self.edges.items) |entry| {
        if (offset >= entry.loc.offset and offset < entry.loc.offset + entry.len) {
            return entry.edge_index;
        }
    }
    return null;
}

pub fn locForNode(self: *const SourceMap, node_index: usize) ?Loc {
    for (self.nodes.items) |entry| {
        if (entry.node_index == node_index) return entry.loc;
    }
    return null;
}

pub fn locForEdge(self: *const SourceMap, edge_index: usize) ?Loc {
    for (self.edges.items) |entry| {
        if (entry.edge_index == edge_index) return entry.loc;
    }
    return null;
}

// tests included inline — see Step 1
```

- [ ] **Step 3: Run tests, commit**

Run: `zig build test-tui 2>&1 | tail -5`

```bash
git add src/tui/source_map.zig src/tui/main.zig
git commit -m "feat(tui): add SourceMap for bidirectional source-graph linking"
```

---

## Task 6: App Shell — vxfw Root Widget with SplitView

**Files:**
- Create: `src/tui/app.zig`
- Modify: `src/tui/main.zig` (use App instead of inline widget)

Build the root App widget that owns the vxfw event loop and creates a SplitView with two placeholder Text widgets (editor left, preview right). Handles Ctrl+Q to quit and Tab to toggle focus indicator.

- [ ] **Step 1: Create app.zig with SplitView layout**

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const TextBuffer = @import("text_buffer.zig");

const App = @This();

pub const Focus = enum { editor, preview };

allocator: std.mem.Allocator,
focus: Focus = .editor,
split_width: u16 = 40,
split: vxfw.SplitView,
editor_text: vxfw.Text,
preview_text: vxfw.Text,
status_text: vxfw.Text,
children: [2]vxfw.SubSurface = undefined,

pub fn create(allocator: std.mem.Allocator) !*App {
    const self = try allocator.create(App);
    self.* = .{
        .allocator = allocator,
        .editor_text = .{ .text = "Editor pane (placeholder)" },
        .preview_text = .{ .text = "Preview pane (placeholder)" },
        .status_text = .{ .text = "zigraph editor | Ctrl+Q quit | Tab switch focus", .style = .{ .reverse = true } },
        .split = .{
            .lhs = undefined,
            .rhs = undefined,
            .width = 40,
        },
    };
    self.split.lhs = self.editor_text.widget();
    self.split.rhs = self.preview_text.widget();
    return self;
}

pub fn destroy(self: *App) void {
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
                return;
            }
            if (key.matches('\t', .{})) {
                self.focus = if (self.focus == .editor) .preview else .editor;
                ctx.consumeAndRedraw();
                return;
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *App = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    // Reserve 1 row for status bar at bottom
    const content_height = if (max.height > 1) max.height - 1 else max.height;
    const content_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = content_height },
        .{ .width = max.width, .height = content_height },
    );

    self.split.lhs = self.editor_text.widget();
    self.split.rhs = self.preview_text.widget();
    const split_surface = try self.split.widget().draw(content_ctx);

    // Status bar
    const status_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = 1 },
        .{ .width = max.width, .height = 1 },
    );
    const status_surface = try self.status_text.widget().draw(status_ctx);

    self.children[0] = .{ .origin = .{ .row = 0, .col = 0 }, .surface = split_surface };
    self.children[1] = .{ .origin = .{ .row = @intCast(content_height), .col = 0 }, .surface = status_surface };

    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = &self.children,
    };
}
```

- [ ] **Step 2: Update main.zig to use App**

```zig
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
}
```

- [ ] **Step 3: Build and verify**

Run: `zig build run-edit`
Expected: Split view with "Editor pane" left, "Preview pane" right, status bar at bottom. Tab toggles focus. Ctrl+Q quits.

- [ ] **Step 4: Commit**

```bash
git add src/tui/app.zig src/tui/main.zig
git commit -m "feat(tui): add App shell with SplitView, status bar, and focus switching"
```

---

## Task 7: EditorPane — Text Display with Syntax Highlighting

**Files:**
- Create: `src/tui/editor_pane.zig`
- Modify: `src/tui/app.zig` (replace editor_text placeholder)

EditorPane displays a TextBuffer with line numbers, syntax highlighting, and a cursor. This task handles display only — editing comes in Task 8.

- [ ] **Step 1: Create editor_pane.zig**

The EditorPane is a vxfw Widget that:
- Takes a TextBuffer reference and renders lines with syntax highlighting
- Shows line number gutter (4-char wide, right-aligned)
- Renders cursor at (cursor_line, cursor_col)
- Handles viewport scrolling (scroll_top, scroll_left)
- Arrow keys move cursor, PgUp/PgDn scroll

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const TextBuffer = @import("text_buffer.zig");
const Highlighter = @import("highlighter.zig");

const EditorPane = @This();

buffer: *TextBuffer,
cursor_line: usize = 0,
cursor_col: usize = 0,
scroll_top: usize = 0,
scroll_left: usize = 0,
focused: bool = true,

pub fn widget(self: *EditorPane) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *EditorPane = @ptrCast(@alignCast(ptr));
    switch (event) {
        .key_press => |key| {
            // Arrow key navigation
            if (key.matches(vaxis.Key.up, .{})) {
                if (self.cursor_line > 0) self.cursor_line -= 1;
                self.ensureCursorVisible(ctx);
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.down, .{})) {
                const lc = self.buffer.lineCount();
                if (lc > 0 and self.cursor_line < lc - 1) self.cursor_line += 1;
                self.ensureCursorVisible(ctx);
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.left, .{})) {
                if (self.cursor_col > 0) self.cursor_col -= 1;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.right, .{})) {
                self.cursor_col += 1;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.home, .{})) {
                self.cursor_col = 0;
                ctx.consumeAndRedraw();
            } else if (key.matches(vaxis.Key.end, .{})) {
                self.cursor_col = std.math.maxInt(usize);
                ctx.consumeAndRedraw();
            }
        },
        else => {},
    }
}

fn ensureCursorVisible(self: *EditorPane, ctx: *vxfw.EventContext) void {
    _ = ctx;
    if (self.cursor_line < self.scroll_top) {
        self.scroll_top = self.cursor_line;
    }
    // Can't check against height here (no size info in event handler)
    // We'll clamp in draw
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *EditorPane = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();
    const gutter_width: u16 = 4;
    const visible_lines = max.height;

    // Ensure scroll keeps cursor visible
    if (self.cursor_line < self.scroll_top) {
        self.scroll_top = self.cursor_line;
    } else if (self.cursor_line >= self.scroll_top + visible_lines) {
        self.scroll_top = self.cursor_line - visible_lines + 1;
    }

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max);

    // Render each visible line
    var row: u16 = 0;
    while (row < visible_lines) : (row += 1) {
        const line_num = self.scroll_top + row;
        const lc = self.buffer.lineCount();
        if (line_num >= lc) break;

        // Line number gutter
        const num_str = try std.fmt.allocPrint(ctx.arena, "{d: >3} ", .{line_num + 1});
        for (num_str, 0..) |c, ci| {
            if (gutter_width + ci >= max.width) break;
            surface.writeCell(@intCast(ci), row, .{
                .char = .{ .grapheme = num_str[ci..ci+1], .width = 1 },
                .style = .{ .dim = true },
            });
        }

        // Line content with syntax highlighting
        const line_content = self.buffer.lineAt(line_num) catch "";
        defer if (line_content.len > 0) self.buffer.allocator.free(line_content);

        // Get syntax spans for this line
        const spans = Highlighter.tokenizeToSpans(ctx.arena, line_content) catch &.{};

        var col: u16 = 0;
        for (line_content, 0..) |ch, ci| {
            const screen_col = gutter_width + col;
            if (screen_col >= max.width) break;

            // Find style for this character
            var style = vaxis.Style{};
            for (spans) |span| {
                if (ci >= span.start and ci < span.start + span.len) {
                    style = span.style;
                    break;
                }
            }

            // Cursor highlight
            if (line_num == self.cursor_line and ci == self.cursor_col and self.focused) {
                style.reverse = true;
            }

            surface.writeCell(screen_col, row, .{
                .char = .{ .grapheme = line_content[ci..ci+1], .width = 1 },
                .style = style,
            });
            col += 1;
        }

        // Cursor at end of line
        if (line_num == self.cursor_line and self.cursor_col >= line_content.len and self.focused) {
            const screen_col = gutter_width + @as(u16, @intCast(line_content.len));
            if (screen_col < max.width) {
                surface.writeCell(screen_col, row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .reverse = true },
                });
            }
        }
    }

    // Set cursor position for terminal cursor if focused
    if (self.focused) {
        const cursor_screen_col = gutter_width + @as(u16, @intCast(@min(self.cursor_col, max.width - gutter_width)));
        const cursor_screen_row = @as(u16, @intCast(self.cursor_line -| self.scroll_top));
        surface.cursor = .{
            .col = cursor_screen_col,
            .row = cursor_screen_row,
            .shape = .beam,
        };
    }

    return surface;
}
```

- [ ] **Step 2: Wire EditorPane into App**

In `app.zig`, replace the `editor_text: vxfw.Text` field with `editor_pane: EditorPane` (or a pointer). Initialize it in `create()` with a TextBuffer loaded from a file or default content.

- [ ] **Step 3: Build and verify**

Run: `zig build run-edit`
Expected: Left pane shows line numbers and text content with syntax highlighting. Arrow keys move cursor. Line numbers in gutter.

- [ ] **Step 4: Commit**

```bash
git add src/tui/editor_pane.zig src/tui/app.zig
git commit -m "feat(tui): add EditorPane with line numbers, cursor, and syntax highlighting"
```

---

## Task 8: EditorPane — Text Editing via UndoManager

**Files:**
- Modify: `src/tui/editor_pane.zig`
- Modify: `src/tui/app.zig`

Add character insertion, deletion (Backspace/Delete), Enter (newline), and route all edits through UndoManager. Wire Ctrl+Z/Ctrl+Y in App.

- [ ] **Step 1: Add UndoManager to EditorPane**

Add field `undo: *UndoManager` and `modified: bool = false`.

- [ ] **Step 2: Handle text input in event handler**

In the key_press handler, add:
- Printable characters: `insertText` at cursor position, advance cursor
- Backspace: `deleteText` at cursor-1, move cursor back
- Delete: `deleteText` at cursor position
- Enter: `insertText "\n"`, move cursor to next line col 0
- Ctrl+Z: `undo.undo(buffer)`
- Ctrl+Y: `undo.redo(buffer)`

```zig
// Inside key_press handler:
if (key.matches(vaxis.Key.backspace, .{})) {
    const pos = self.buffer.lineColToPosition(self.cursor_line, self.cursor_col);
    if (pos > 0) {
        self.undo.deleteText(self.buffer, pos - 1, 1) catch return;
        const lc = self.buffer.positionToLineCol(pos - 1);
        self.cursor_line = lc.line;
        self.cursor_col = lc.col;
        self.modified = true;
        ctx.consumeAndRedraw();
    }
} else if (key.matches(vaxis.Key.enter, .{})) {
    const pos = self.buffer.lineColToPosition(self.cursor_line, self.cursor_col);
    self.undo.insertText(self.buffer, pos, "\n") catch return;
    self.cursor_line += 1;
    self.cursor_col = 0;
    self.modified = true;
    ctx.consumeAndRedraw();
} else if (key.matches('z', .{ .ctrl = true })) {
    self.undo.undo(self.buffer) catch return;
    ctx.consumeAndRedraw();
} else if (key.matches('y', .{ .ctrl = true })) {
    self.undo.redo(self.buffer) catch return;
    ctx.consumeAndRedraw();
} else if (key.text) |text| {
    const pos = self.buffer.lineColToPosition(self.cursor_line, self.cursor_col);
    self.undo.insertText(self.buffer, pos, text) catch return;
    self.cursor_col += text.len;
    self.modified = true;
    ctx.consumeAndRedraw();
}
```

- [ ] **Step 3: Build and verify**

Run: `zig build run-edit`
Expected: Can type text, backspace works, Enter creates new lines, Ctrl+Z undoes, Ctrl+Y redoes.

- [ ] **Step 4: Commit**

```bash
git add src/tui/editor_pane.zig src/tui/app.zig
git commit -m "feat(tui): add text editing with undo/redo in EditorPane"
```

---

## Task 9: PreviewPane — Graph Rendering with Hit-Testing

**Files:**
- Create: `src/tui/preview_pane.zig`
- Modify: `src/tui/app.zig`

PreviewPane takes a RenderPlan and maps its Buffer2D cells to vxfw Surface cells. Handles click → elementAt → selection highlight.

- [ ] **Step 1: Create preview_pane.zig**

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const zigraph = @import("zigraph");
const RenderPlan = zigraph.TerminalRenderPlan;
const HitResult = zigraph.TerminalHitResult;

const PreviewPane = @This();

plan: ?*RenderPlan = null,
selected_node: ?usize = null,
selected_edge: ?usize = null,
scroll_x: usize = 0,
scroll_y: usize = 0,
focused: bool = false,

pub fn widget(self: *PreviewPane) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *PreviewPane = @ptrCast(@alignCast(ptr));
    switch (event) {
        .mouse => |mouse| {
            if (mouse.type == .press and mouse.button == .left) {
                if (self.plan) |plan| {
                    const graph_col = @as(usize, @intCast(@max(0, mouse.col))) + self.scroll_x;
                    const graph_row = @as(usize, @intCast(@max(0, mouse.row))) + self.scroll_y;
                    const hit = plan.elementAt(graph_col, graph_row);
                    switch (hit) {
                        .node => |id| {
                            self.selected_node = if (self.selected_node == id) null else id;
                            self.selected_edge = null;
                        },
                        .edge => |idx| {
                            self.selected_edge = if (self.selected_edge == idx) null else idx;
                            self.selected_node = null;
                        },
                        else => {
                            self.selected_node = null;
                            self.selected_edge = null;
                        },
                    }
                    ctx.consumeAndRedraw();
                }
            }
        },
        .key_press => |key| {
            if (key.matches(vaxis.Key.escape, .{})) {
                self.selected_node = null;
                self.selected_edge = null;
                ctx.consumeAndRedraw();
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *PreviewPane = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    if (self.plan == null) {
        var text: vxfw.Text = .{ .text = "No preview available", .style = .{ .dim = true } };
        return try text.widget().draw(ctx);
    }

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), max);

    // Map RenderPlan output to surface cells
    // The plan's rendered output is obtained by rendering to a string,
    // but for cell-level mapping we need to render to Buffer2D.
    // For now, render to string and display as text.
    // TODO: Use Buffer2D directly for cell-level styling when available.

    return surface;
}
```

- [ ] **Step 2: Wire into App, add debounced parse pipeline**

In `app.zig`, add:
- `preview_pane: PreviewPane` field
- On text change, start a debounce timer (100ms via `ctx.tick(100, ...)`)
- On tick: tokenize → parse → layout → RenderPlan → assign to preview_pane.plan

- [ ] **Step 3: Build and verify**

Run: `zig build run-edit`
Expected: Right pane shows graph preview after typing valid zgraph source. Clicking nodes highlights them.

- [ ] **Step 4: Commit**

```bash
git add src/tui/preview_pane.zig src/tui/app.zig
git commit -m "feat(tui): add PreviewPane with graph rendering and hit-testing"
```

---

## Task 10: StatusBar

**Files:**
- Create: `src/tui/status_bar.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Create status_bar.zig**

A 1-row widget showing: left-aligned message (error or selection info), right-aligned cursor position + modified indicator.

```zig
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

pub fn widget(self: *StatusBar) vxfw.Widget {
    return .{
        .userdata = self,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const self: *StatusBar = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();
    const height: u16 = if (self.context_panel_open) 4 else 1;
    const size = vxfw.Size{ .width = max.width, .height = @min(height, max.height) };

    var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

    // Fill status line with reverse video
    var col: u16 = 0;
    while (col < max.width) : (col += 1) {
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = .{ .reverse = true },
        });
    }

    // Left: message
    const left_text = if (self.message.len > 0) self.message else self.filename;
    for (left_text, 0..) |_, i| {
        if (i + 1 >= max.width) break;
        surface.writeCell(@intCast(i + 1), 0, .{
            .char = .{ .grapheme = left_text[i..i+1], .width = 1 },
            .style = .{ .reverse = true },
        });
    }

    // Right: Ln X Col Y [*]
    const mod_str: []const u8 = if (self.modified) " *" else "";
    const right = try std.fmt.allocPrint(ctx.arena, "Ln {d} Col {d}{s} ", .{ self.line + 1, self.col + 1, mod_str });
    const right_start = if (max.width > right.len) max.width - @as(u16, @intCast(right.len)) else 0;
    for (right, 0..) |_, i| {
        surface.writeCell(right_start + @as(u16, @intCast(i)), 0, .{
            .char = .{ .grapheme = right[i..i+1], .width = 1 },
            .style = .{ .reverse = true },
        });
    }

    return surface;
}
```

- [ ] **Step 2: Wire into App, update on cursor move**

- [ ] **Step 3: Build, verify, commit**

```bash
git add src/tui/status_bar.zig src/tui/app.zig
git commit -m "feat(tui): add StatusBar with cursor position and modified indicator"
```

---

## Task 11: Bidirectional Linking — Source ↔ Graph Navigation

**Files:**
- Modify: `src/tui/app.zig`
- Modify: `src/tui/editor_pane.zig`
- Modify: `src/tui/preview_pane.zig`

- [ ] **Step 1: Build SourceMap during parse pipeline**

After successful parse, iterate the resolved AST and populate SourceMap with node/edge → Loc entries.

- [ ] **Step 2: Editor cursor → Preview highlight**

When cursor moves in EditorPane, lookup `sourceMap.nodeAtOffset(cursor_pos)` → if found, set `preview_pane.selected_node`.

- [ ] **Step 3: Preview click → Editor jump**

When node is clicked in PreviewPane, lookup `sourceMap.locForNode(node_id)` → if found, set `editor_pane.cursor_line/col` and scroll.

- [ ] **Step 4: Build, verify, commit**

```bash
git add src/tui/app.zig src/tui/editor_pane.zig src/tui/preview_pane.zig
git commit -m "feat(tui): add bidirectional source-graph linking"
```

---

## Task 12: TabBar + Multi-Buffer Support

**Files:**
- Create: `src/tui/tab_bar.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Create tab_bar.zig**

A widget that renders tab titles horizontally. Auto-hides when only 1 buffer open. Each tab shows filename + modified indicator + close button (×).

- [ ] **Step 2: Add buffer collection to App**

App manages a list of `BufferState` (TextBuffer + UndoManager + filename + modified flag). Tab switching swaps the active buffer.

- [ ] **Step 3: Wire Ctrl+T (open file via palette), Ctrl+W (close tab), Ctrl+Tab/Ctrl+Shift+Tab (cycle)**

- [ ] **Step 4: Build, verify, commit**

```bash
git add src/tui/tab_bar.zig src/tui/app.zig
git commit -m "feat(tui): add TabBar with multi-buffer tab management"
```

---

## Task 13: CommandPalette — Fuzzy-Find Overlay

**Files:**
- Create: `src/tui/command_palette.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Implement fuzzy matching**

Character-order substring matching with scoring: consecutive matches and word-boundary matches score higher.

- [ ] **Step 2: Create CommandPalette widget**

Overlay centered on screen with text input at top, filtered results below. Register all commands from spec (Save, Quit, Open, Close tab, Toggle orientation, etc.).

- [ ] **Step 3: Wire Ctrl+P in App to toggle palette**

When active, palette captures all key events. Enter executes selected command, Esc dismisses.

- [ ] **Step 4: Add tests for fuzzy matching**

```zig
test "fuzzy match exact" {
    const score = fuzzyScore("save", "Save file");
    try std.testing.expect(score > 0);
}
test "fuzzy match partial" {
    const score = fuzzyScore("sf", "Save file");
    try std.testing.expect(score > 0);
}
test "fuzzy no match" {
    const score = fuzzyScore("xyz", "Save file");
    try std.testing.expectEqual(@as(i32, 0), score);
}
```

- [ ] **Step 5: Build, verify, commit**

```bash
git add src/tui/command_palette.zig src/tui/app.zig
git commit -m "feat(tui): add CommandPalette with fuzzy-find overlay"
```

---

## Task 14: Definitions — Go-to-Definition

**Files:**
- Create: `src/tui/definitions.zig`
- Modify: `src/tui/editor_pane.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Implement Definitions index**

HashMap mapping name → Loc, rebuilt from resolved AST on each parse. Handles:
- `@import "file.zgraph"` → file path
- `${var}` → vars block definition
- `.classname` → @style rule
- Node identifier → first declaration with properties

- [ ] **Step 2: Wire Ctrl+Click in EditorPane**

Detect token under cursor, lookup in Definitions. If @import → open file in new tab. Otherwise → jump cursor to definition Loc.

- [ ] **Step 3: Add tests**

```zig
test "resolve variable definition" {
    var defs = Definitions.init(std.testing.allocator);
    defer defs.deinit();
    try defs.addVar("color", .{ .line = 2, .col = 3, .offset = 15 });
    const loc = defs.lookup("color");
    try std.testing.expect(loc != null);
    try std.testing.expectEqual(@as(u32, 2), loc.?.line);
}
```

- [ ] **Step 4: Build, verify, commit**

```bash
git add src/tui/definitions.zig src/tui/editor_pane.zig src/tui/app.zig
git commit -m "feat(tui): add go-to-definition for imports, vars, classes, and nodes"
```

---

## Task 15: Completion — Autocomplete Popup

**Files:**
- Create: `src/tui/completion.zig`
- Modify: `src/tui/editor_pane.zig`

- [ ] **Step 1: Implement context detection**

Analyze token before cursor to determine completion context: after `@` (directives), after `${` (variables), after `.` in class position, inside `[` (properties), after `=` (values), identifier position (node names).

- [ ] **Step 2: Implement completion sources**

Static lists for directives, directions, shapes, border styles, property keys. Dynamic lists from parsed AST for variables, classes, node names.

- [ ] **Step 3: Create popup widget**

Overlay below cursor, max 10 items, arrow keys to navigate, Tab/Enter to accept, Esc to dismiss. Continues filtering as user types.

- [ ] **Step 4: Wire Ctrl+Space manual trigger + auto-trigger on `@`, `${`, `.`**

- [ ] **Step 5: Add tests for context detection**

```zig
test "detect directive context after @" {
    const ctx = Completion.detectContext("@lay", 4);
    try std.testing.expectEqual(Completion.Context.directive, ctx);
}
test "detect variable context after ${" {
    const ctx = Completion.detectContext("\"${co", 5);
    try std.testing.expectEqual(Completion.Context.variable, ctx);
}
```

- [ ] **Step 6: Build, verify, commit**

```bash
git add src/tui/completion.zig src/tui/editor_pane.zig
git commit -m "feat(tui): add autocomplete with context-aware completion sources"
```

---

## Task 16: Preview Interactions — Drag, Nudge, Pin

**Files:**
- Modify: `src/tui/preview_pane.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Implement mouse drag**

Track drag start on mouse press over node, update visual position on mouse motion, commit on mouse up. Pin the node at new position.

- [ ] **Step 2: Implement arrow key nudge**

When preview is focused and a node is selected, arrow keys move node by 1 cell. Pin after nudge.

- [ ] **Step 3: Implement P to pin/unpin**

Toggle pin state on selected node. Pinned positions are passed as constraints to layout engine on re-layout.

- [ ] **Step 4: Add pinned positions storage to App**

HashMap of node_id → (x, y) for pinned positions per buffer. Pass to layout engine.

- [ ] **Step 5: Build, verify, commit**

```bash
git add src/tui/preview_pane.zig src/tui/app.zig
git commit -m "feat(tui): add node drag, arrow nudge, and pin/unpin in preview"
```

---

## Task 17: Keybindings Help Screen

**Files:**
- Create: `src/tui/keybindings.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Create keybindings registry**

Static array of `Binding` structs with category, key description, and action description. Grouped by: File, Navigation, Editing, Layout, Preview, Global.

- [ ] **Step 2: Create help screen overlay**

Centered overlay showing all bindings in columns. Dismissable with Esc or Ctrl+H.

- [ ] **Step 3: Wire Ctrl+H in App**

- [ ] **Step 4: Build, verify, commit**

```bash
git add src/tui/keybindings.zig src/tui/app.zig
git commit -m "feat(tui): add keybindings help screen overlay"
```

---

## Task 18: CLI Integration — `edit` Subcommand

**Files:**
- Modify: `src/cli/main.zig`
- Modify: `src/tui/main.zig`

- [ ] **Step 1: Add `edit` to Command union in CLI**

```zig
const EditArgs = struct {
    files: []const []const u8,
};

const Command = union(enum) {
    render: RenderArgs,
    check: CheckArgs,
    fmt: FmtArgs,
    watch: WatchArgs,
    edit: EditArgs,
    help,
};
```

- [ ] **Step 2: Parse `edit` subcommand arguments**

```zig
if (std.mem.eql(u8, cmd_str, "edit")) {
    var files: std.ArrayListUnmanaged([]const u8) = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        try files.append(allocator, args[i]);
    }
    return Command{ .edit = .{ .files = files.items } };
}
```

- [ ] **Step 3: Update help text**

Add `edit [file...]` to the help output.

- [ ] **Step 4: Dispatch to TUI**

In the main switch, for `.edit`, either exec `zigraph-edit` or call TUI main directly (if compiled into same binary).

- [ ] **Step 5: Update main.zig to accept file arguments**

Parse command-line args for file paths, load initial TextBuffers, open as tabs.

- [ ] **Step 6: Build and verify**

Run: `zig build run-cli -- edit examples/dsl/demo.zgraph`
Expected: Opens TUI editor with the file loaded.

- [ ] **Step 7: Commit**

```bash
git add src/cli/main.zig src/tui/main.zig
git commit -m "feat(cli): add 'edit' subcommand to launch TUI editor"
```

---

## Task 19: File Save + Quit with Unsaved Prompt

**Files:**
- Modify: `src/tui/app.zig`
- Modify: `src/tui/editor_pane.zig`

- [ ] **Step 1: Implement Ctrl+S save**

Write TextBuffer contents to the file path. Clear modified flag.

- [ ] **Step 2: Implement unsaved-changes prompt on Ctrl+Q**

If any buffer is modified, show a confirmation overlay: "Unsaved changes. Save? [Y]es / [N]o / [C]ancel"

- [ ] **Step 3: Build, verify, commit**

```bash
git add src/tui/app.zig src/tui/editor_pane.zig
git commit -m "feat(tui): add file save and quit-with-unsaved-changes prompt"
```

---

## Task 20: Split Orientation Toggle + Resize

**Files:**
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Add orientation field**

`orientation: enum { horizontal, vertical } = .horizontal` (horizontal = side-by-side).

- [ ] **Step 2: Wire Ctrl+\ to toggle orientation**

Swap between horizontal SplitView and vertical stacking.

- [ ] **Step 3: Wire Ctrl+] and Ctrl+[ to resize split**

Increment/decrement `split.width` by 5 columns.

- [ ] **Step 4: Build, verify, commit**

```bash
git add src/tui/app.zig
git commit -m "feat(tui): add split orientation toggle and resize keybindings"
```

---

## Task 21: Error/Warning Display — Gutter Markers + Underlines

**Files:**
- Modify: `src/tui/editor_pane.zig`
- Modify: `src/tui/highlighter.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Pass ErrorList to EditorPane**

After parse (successful or not), pass the ErrorList to EditorPane for display.

- [ ] **Step 2: Render gutter markers**

Red dot `●` on lines with errors, yellow dot for warnings.

- [ ] **Step 3: Render error underlines**

Apply curly red underline style to the token range indicated by each error's Loc.

- [ ] **Step 4: Show first error in StatusBar**

- [ ] **Step 5: Build, verify, commit**

```bash
git add src/tui/editor_pane.zig src/tui/highlighter.zig src/tui/app.zig
git commit -m "feat(tui): add error/warning gutter markers and underline overlays"
```

---

## Task 22: Context Panel Toggle

**Files:**
- Modify: `src/tui/status_bar.zig`
- Modify: `src/tui/app.zig`

- [ ] **Step 1: Wire Ctrl+I to toggle context panel**

Sets `status_bar.context_panel_open`. When on, StatusBar expands to 4 lines showing selected node/edge properties.

- [ ] **Step 2: Populate context info from SourceMap + graph data**

On selection change, build context string: "Node: name\nProperties: ...\nEdges: ...\nClasses: ..."

- [ ] **Step 3: Build, verify, commit**

```bash
git add src/tui/status_bar.zig src/tui/app.zig
git commit -m "feat(tui): add toggleable context panel in status bar"
```

---

## Task 23: Final Integration Test + Polish

**Files:**
- All TUI files

- [ ] **Step 1: Create a test .zgraph file**

```
# Test file for TUI editor
@layout sugiyama
@direction top-down

vars {
    color = "blue"
}

frontend -> api -> db [shape=cylinder]
api -> cache [shape=diamond]

@style .database {
    color = "${color}"
}
```

- [ ] **Step 2: Run full integration test**

```bash
zig build run-edit -- test.zgraph
```

Verify: editor loads file, syntax highlighting works, preview shows graph, clicking nodes highlights in both panes, Ctrl+S saves, Ctrl+Q quits, all keybindings work.

- [ ] **Step 3: Run all unit tests**

Run: `zig build test-tui`
Expected: All tests pass

- [ ] **Step 4: Final commit**

```bash
git add -A src/tui/
git commit -m "feat(tui): complete TUI editor with all Phase 3b features"
```
