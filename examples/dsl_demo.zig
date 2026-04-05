//! DSL Demo — Integration example for the full zgraph DSL pipeline.
//!
//! Demonstrates: parse .zgraph source → resolve → build → layout → render
//! to all three formats (terminal, SVG, JSON).
//!
//! Run with: zig build run-dsl-demo

const std = @import("std");
const zigraph = @import("zigraph");
const dsl = @import("dsl");

const source =
    \\@layout sugiyama
    \\
    \\Client -> API: "HTTPS"
    \\API -> Auth: "validate"
    \\Auth -> Cache: "token"
    \\
    \\backend: {
    \\  API -> Router -> Handler
    \\  Handler -> DB: "query"
    \\  DB: "PostgreSQL"
    \\}
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    var result = try dsl.parseAndBuild(allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        for (result.err_list.errors.items) |e| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ e.loc.line, e.loc.col, e.message });
        }
        return error.ParseError;
    }

    if (result.graphs.len == 0) {
        try stderr.writeAll("No graphs found in input.\n");
        return;
    }

    try stdout.print("Parsed {d} graph(s) from DSL source.\n\n", .{result.graphs.len});

    for (result.graphs, 0..) |*built, i| {
        if (result.graphs.len > 1) {
            try stdout.print("=== Graph {d} ===\n\n", .{i + 1});
        }

        var ir = try zigraph.layout(&built.graph, allocator, built.config);
        defer ir.deinit();

        // Apply direction transform (left-right, bottom-up, etc.)
        dsl.direction.applyDirection(&ir, built.direction);

        // ── Terminal render ──────────────────────────────────────────────
        try stdout.writeAll("--- Terminal ---\n");
        const terminal_output = try zigraph.terminal.render(&ir, allocator);
        defer allocator.free(terminal_output);
        try stdout.writeAll(terminal_output);
        if (!std.mem.endsWith(u8, terminal_output, "\n")) {
            try stdout.writeByte('\n');
        }

        // ── SVG render ───────────────────────────────────────────────────
        try stdout.writeAll("--- SVG (first 3 lines) ---\n");
        const svg_output = try zigraph.svg.render(&ir, allocator, .{});
        defer allocator.free(svg_output);
        var svg_lines = std.mem.splitScalar(u8, svg_output, '\n');
        var line_count: usize = 0;
        while (svg_lines.next()) |line| : (line_count += 1) {
            if (line_count >= 3) break;
            try stdout.print("{s}\n", .{line});
        }
        try stdout.print("... ({d} bytes total)\n", .{svg_output.len});

        // ── JSON render ───────────────────────────────────────────────────
        try stdout.writeAll("--- JSON (first 5 lines) ---\n");
        const json_output = try zigraph.json.serialize(&ir, allocator);
        defer allocator.free(json_output);
        var json_lines = std.mem.splitScalar(u8, json_output, '\n');
        var json_line_count: usize = 0;
        while (json_lines.next()) |line| : (json_line_count += 1) {
            if (json_line_count >= 5) break;
            try stdout.print("{s}\n", .{line});
        }
        try stdout.print("... ({d} bytes total)\n", .{json_output.len});

        try stdout.writeByte('\n');
    }
}
