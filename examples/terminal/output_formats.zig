//! Output Format Variants — ASCII charset and HTML output
//!
//! Demonstrates the TerminalCharSet and TerminalOutputFormat options:
//! 1. Unicode (default) — box-drawing characters and Unicode arrows
//! 2. ASCII — +, -, |, v, ^ equivalents for legacy terminals
//! 3. HTML <pre> — colored spans instead of ANSI escape codes
//!
//! Run with: zig build run-output-formats

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\╔══════════════════════════════════════╗
        \\║   zigraph — Output Format Variants   ║
        \\╚══════════════════════════════════════╝
        \\
        \\
    , .{});

    // Build a small graph with a subgraph
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Server");
    try g.addNode(2, "Auth");
    try g.addNode(3, "DB");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 3);

    const backend = try g.addSubgraph("backend");
    try g.putNodes(&.{ 2, 3 }).inside(backend);

    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    // ═══════════════════════════════════════════
    // 1. Default: Unicode box-drawing + ANSI color
    // ═══════════════════════════════════════════
    {
        std.debug.print("1. Unicode + ANSI 256 color (default)\n", .{});
        std.debug.print("══════════════════════════════════════\n\n", .{});

        const output = try zigraph.terminal.renderGenericWithConfig(usize, &ir, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n\n", .{output});
    }

    // ═══════════════════════════════════════════
    // 2. ASCII charset — no Unicode box-drawing
    // ═══════════════════════════════════════════
    {
        std.debug.print("2. ASCII charset (no box-drawing, no color)\n", .{});
        std.debug.print("════════════════════════════════════════════\n\n", .{});

        const output = try zigraph.terminal.renderGenericWithConfig(usize, &ir, allocator, .{
            .char_set = .ascii,
            .color_mode = .none,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n\n", .{output});
    }

    // ═══════════════════════════════════════════
    // 3. HTML <pre> output — for embedding in web pages
    // ═══════════════════════════════════════════
    {
        std.debug.print("3. HTML <pre> output (ANSI 256 palette)\n", .{});
        std.debug.print("════════════════════════════════════════\n\n", .{});

        const output = try zigraph.terminal.renderGenericWithConfig(usize, &ir, allocator, .{
            .output_format = .html_pre,
            .color_mode = .ansi256,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n\n", .{output});
    }

    // ═══════════════════════════════════════════
    // 4. ASCII + HTML combined with custom style
    // ═══════════════════════════════════════════
    {
        std.debug.print("4. ASCII charset + HTML output (custom font)\n", .{});
        std.debug.print("══════════════════════════════════════════════\n\n", .{});

        const output = try zigraph.terminal.renderGenericWithConfig(usize, &ir, allocator, .{
            .char_set = .ascii,
            .output_format = .html_pre,
            .color_mode = .ansi256,
            .html_pre_style = "font-family:'Fira Code',monospace;font-size:14px;line-height:1.4",
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
