//! # 01 — Basic SVG
//!
//! The simplest possible example: build a graph and render it to SVG.
//! No configuration needed — all defaults produce clean, readable output.
//!
//! **What you'll learn:** zero-config SVG rendering.
//!
//! Run: `zig build run-svg-01`

const std = @import("std");
const zigraph = @import("zigraph");

fn writeSvg(io: std.Io, name: []const u8, svg: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "assets/gallery/{s}.svg", .{name}) catch return;
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var wbuf: [4096]u8 = undefined;
    var fw = std.Io.File.writer(file, io, &wbuf);
    try fw.interface.writeAll(svg);
    std.debug.print("  ✓ {s} ({d} bytes)\n", .{ path, svg.len });
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    std.debug.print("\n── 01: Basic SVG ──\n\n", .{});

    // Build a small dependency graph
    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "main.zig");
    try g.addNode(2, "http.zig");
    try g.addNode(3, "json.zig");
    try g.addNode(4, "auth.zig");
    try g.addNode(5, "db.zig");
    try g.addNode(6, "log.zig");

    try g.addEdge(1, 2); // main → http
    try g.addEdge(1, 3); // main → json
    try g.addEdge(2, 4); // http → auth
    try g.addEdge(2, 5); // http → db
    try g.addEdge(3, 5); // json → db
    try g.addEdge(4, 6); // auth → log
    try g.addEdge(5, 6); // db → log

    // Layout with defaults
    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    // Render SVG — that's it. No config needed.
    const svg = try zigraph.svg.render(&ir, allocator, .{});
    defer allocator.free(svg);

    try writeSvg(io, "01_basic", svg);

    // Also show the Unicode preview for comparison
    const txt = try zigraph.terminal.render(&ir, allocator);
    defer allocator.free(txt);
    std.debug.print("\n{s}\n", .{txt});
}
