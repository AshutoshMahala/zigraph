//! Interactive TUI demo — click on nodes/edges in the terminal.
//!
//! Uses raw terminal mode + ANSI mouse tracking to detect clicks,
//! then uses RenderPlan.elementAt() for hit-testing.
//! No external TUI framework dependencies.
//!
//! Run with: zig build run-interactive-tui
//! Press 'q' or Ctrl-C to exit.

const std = @import("std");
const posix = std.posix;
const zigraph = @import("zigraph");

const TermConfig = zigraph.terminal.Config;
const RenderPlan = zigraph.TerminalRenderPlan;
const HitResult = zigraph.TerminalHitResult;

/// Application state shared with style closures.
const AppState = struct {
    selected_node: ?usize = null,
    selected_edge: ?usize = null,
};

var app_state = AppState{};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.fs.File.stdout();
    const writer = stdout.deprecatedWriter();
    const stdin = std.fs.File.stdin();

    // Build a demo graph
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "Start");
    try graph.addNode(2, "Process");
    try graph.addNode(3, "Validate");
    try graph.addNode(4, "Branch A");
    try graph.addNode(5, "Branch B");
    try graph.addNode(6, "Merge");
    try graph.addEdge(1, 2);
    try graph.addEdgeLabeled(2, 3, "check");
    try graph.addEdge(3, 4);
    try graph.addEdge(3, 5);
    try graph.addEdge(4, 6);
    try graph.addEdge(5, 6);

    // Compute layout once (reused across re-renders)
    var layout_ir = try zigraph.layout(&graph, allocator, .{});
    defer layout_ir.deinit();

    // Enter raw terminal mode
    const orig_termios = try enableRawMode(stdin.handle);
    defer restoreTerminal(stdout, stdin.handle, orig_termios);

    // Enable mouse click tracking (SGR mode)
    try writer.writeAll("\x1b[?1000h\x1b[?1006h");
    // Hide cursor
    try writer.writeAll("\x1b[?25l");

    // Initial render
    try renderFrame(writer, allocator, &layout_ir);

    // Event loop
    var buf: [32]u8 = undefined;
    while (true) {
        const n = stdin.read(&buf) catch break;
        if (n == 0) break;

        const input = buf[0..n];

        // Check for quit
        if (input[0] == 'q' or input[0] == 3) break; // 'q' or Ctrl-C

        // Parse SGR mouse: \x1b[<button;col;rowM (press) or ...m (release)
        if (parseSgrMouse(input)) |mouse| {
            if (mouse.pressed) {
                // Build plan for hit-testing (coordinates match rendered output)
                var plan = RenderPlan.build(allocator, &layout_ir, makeConfig()) catch continue;
                defer plan.deinit();

                const hit = plan.elementAt(mouse.col, mouse.row);
                switch (hit) {
                    .node => |id| {
                        app_state.selected_node = if (app_state.selected_node == id) null else id;
                        app_state.selected_edge = null;
                    },
                    .edge => |idx| {
                        app_state.selected_edge = if (app_state.selected_edge == idx) null else idx;
                        app_state.selected_node = null;
                    },
                    .subgraph => {
                        app_state.selected_node = null;
                        app_state.selected_edge = null;
                    },
                    .none => {
                        app_state.selected_node = null;
                        app_state.selected_edge = null;
                    },
                }
                try renderFrame(writer, allocator, &layout_ir);
            }
        }
    }
}

fn renderFrame(writer: anytype, allocator: std.mem.Allocator, layout_ir: *const zigraph.LayoutIR(usize)) !void {
    // Clear screen + move to top-left
    try writer.writeAll("\x1b[2J\x1b[H");

    // Header
    try writer.writeAll("Interactive Graph — click nodes/edges, press 'q' to quit\r\n");

    if (app_state.selected_node) |id| {
        try writer.print("Selected: node {d}\r\n", .{id});
    } else if (app_state.selected_edge) |idx| {
        try writer.print("Selected: edge {d}\r\n", .{idx});
    } else {
        try writer.writeAll("Click on a node or edge to select it\r\n");
    }
    try writer.writeAll("\r\n");

    // Stream-render with selection-aware styles
    // NOTE: we wrap stdout writer with a CR-inserter for raw mode
    var cr_writer = crWriter(writer);
    try zigraph.terminal.renderStreamingWithConfig(layout_ir, cr_writer.writer(), allocator, makeConfig());
}

fn makeConfig() TermConfig {
    return .{
        .node_style_fn = &nodeStyleFn,
        .edge_style_fn = &edgeStyleFn,
    };
}

fn nodeStyleFn(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    if (app_state.selected_node) |sel| {
        if (ctx.node_id == sel) {
            return .{
                .border = .double_box,
                .border_color = .{ .ansi256 = 46 }, // bright green
                .text_color = .{ .ansi256 = 15 }, // white
                .bg_color = .{ .ansi256 = 22 }, // dark green bg
            };
        }
    }
    return .{};
}

fn edgeStyleFn(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    if (app_state.selected_edge) |sel| {
        if (ctx.edge_index == sel) {
            return .{
                .color = .{ .ansi256 = 226 }, // yellow
                .weight = .heavy,
            };
        }
    }
    return .{};
}

// ── Raw terminal mode ───────────────────────────────────────────────────────

fn enableRawMode(fd: posix.fd_t) !posix.termios {
    const orig = try posix.tcgetattr(fd);
    var raw = orig;
    // Disable canonical mode, echo, signals, and extensions
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    // Disable software flow control and CR translation
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    try posix.tcsetattr(fd, .FLUSH, raw);
    return orig;
}

fn restoreTerminal(stdout: std.fs.File, fd: posix.fd_t, orig: posix.termios) void {
    const w = stdout.deprecatedWriter();
    w.writeAll("\x1b[?1000l\x1b[?1006l") catch {}; // disable mouse
    w.writeAll("\x1b[?25h") catch {}; // show cursor
    w.writeAll("\x1b[0m") catch {}; // reset attributes
    posix.tcsetattr(fd, .FLUSH, orig) catch {};
}

// ── SGR mouse parsing ───────────────────────────────────────────────────────

const MouseEvent = struct {
    col: usize,
    row: usize,
    pressed: bool,
};

fn parseSgrMouse(buf: []const u8) ?MouseEvent {
    // SGR format: \x1b[<button;col;rowM (press) or \x1b[<button;col;rowm (release)
    if (buf.len < 6) return null;
    if (buf[0] != 0x1b or buf[1] != '[' or buf[2] != '<') return null;

    var i: usize = 3;
    // Skip button number
    while (i < buf.len and buf[i] != ';') : (i += 1) {}
    if (i >= buf.len) return null;
    i += 1; // skip ';'

    // Parse col (1-based in SGR)
    const col_start = i;
    while (i < buf.len and buf[i] != ';') : (i += 1) {}
    if (i >= buf.len) return null;
    const col = std.fmt.parseInt(usize, buf[col_start..i], 10) catch return null;
    i += 1; // skip ';'

    // Parse row (1-based in SGR)
    const row_start = i;
    while (i < buf.len and buf[i] != 'M' and buf[i] != 'm') : (i += 1) {}
    if (i >= buf.len) return null;
    const row = std.fmt.parseInt(usize, buf[row_start..i], 10) catch return null;
    const pressed = buf[i] == 'M';

    // Convert to 0-based and subtract header rows (2 header lines + 1 blank)
    const header_rows: usize = 3;
    const row_0 = if (row > 0) row - 1 else 0;
    const col_0 = if (col > 0) col - 1 else 0;
    if (row_0 < header_rows) return null;

    return .{
        .col = col_0,
        .row = row_0 - header_rows,
        .pressed = pressed,
    };
}

// ── CR writer (inserts \r before \n for raw terminal mode) ──────────────────

fn CrWriter(comptime Inner: type) type {
    return struct {
        inner: Inner,

        const Self = @This();

        pub const Writer = std.io.GenericWriter(*Self, Inner.Error, write);

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        fn write(self: *Self, data: []const u8) Inner.Error!usize {
            var start: usize = 0;
            for (data, 0..) |c, i| {
                if (c == '\n') {
                    if (i > start) {
                        try self.inner.writeAll(data[start..i]);
                    }
                    try self.inner.writeAll("\r\n");
                    start = i + 1;
                }
            }
            if (start < data.len) {
                try self.inner.writeAll(data[start..]);
            }
            return data.len;
        }
    };
}

fn crWriter(inner: anytype) CrWriter(@TypeOf(inner)) {
    return .{ .inner = inner };
}
