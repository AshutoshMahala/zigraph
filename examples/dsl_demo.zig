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

const flow_source =
    \\pipeline [flow] {
    \\  Input -> Parse -> Transform -> Output
    \\}
;

const tree_source =
    \\project [tree] {
    \\  src -> core
    \\  src -> render
    \\  src -> dsl
    \\  core -> parser
    \\  core -> resolver
    \\  core -> bridge
    \\  render -> terminal
    \\  render -> svg
    \\}
;

const table_source =
    \\status [table] {
    \\  headers: Component, Status, Tests
    \\  row: Parser, done, 12
    \\  row: Resolver, done, 8
    \\  row: Bridge, done, 6
    \\  row: "Tree Bridge", done, 3
    \\  row: Imports, done, 1
    \\  row: Formatter, planned, 0
    \\  row: LSP, planned, 0
    \\}
;

const card_source =
    \\team [card] {
    \\  alice: "Alice Smith"
    \\  bob: "Bob Jones"
    \\  carol: "Carol Chen"
    \\  alice -> bob: "collaborates"
    \\  bob -> carol: "reports to"
    \\}
;

const vars_source =
    \\vars {
    \\  env: production
    \\  db: PostgreSQL
    \\}
    \\server: "${env} server"
    \\db: "${db}"
    \\server -> db: "query"
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    // ── Demo 1: multi-block DAG source ───────────────────────────────────────
    try stdout.writeAll("=== Demo 1: Multi-block DAG ===\n\n");

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

    // ── Demo 2: [flow] block ──────────────────────────────────────────────────
    try stdout.writeAll("=== Demo 2: [flow] Block ===\n\n");

    var flow_result = try dsl.parseAndBuild(allocator, flow_source);
    defer flow_result.deinit();

    if (flow_result.hasErrors()) {
        for (flow_result.err_list.errors.items) |e| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ e.loc.line, e.loc.col, e.message });
        }
        return error.ParseError;
    }

    if (flow_result.graphs.len == 0) {
        try stderr.writeAll("No graphs found in flow input.\n");
        return;
    }

    try stdout.print("Parsed {d} graph(s) from flow DSL source.\n\n", .{flow_result.graphs.len});

    for (flow_result.graphs, 0..) |*built, i| {
        if (flow_result.graphs.len > 1) {
            try stdout.print("=== Flow Graph {d} ===\n\n", .{i + 1});
        }

        var ir = try zigraph.layout(&built.graph, allocator, built.config);
        defer ir.deinit();

        dsl.direction.applyDirection(&ir, built.direction);

        try stdout.writeAll("--- Terminal ---\n");
        const terminal_output = try zigraph.terminal.render(&ir, allocator);
        defer allocator.free(terminal_output);
        try stdout.writeAll(terminal_output);
        if (!std.mem.endsWith(u8, terminal_output, "\n")) {
            try stdout.writeByte('\n');
        }

        try stdout.writeByte('\n');
    }

    // ── Demo 3: [tree] block ──────────────────────────────────────────────────
    try stdout.writeAll("=== Demo 3: [tree] Block ===\n\n");

    var tree_result = try dsl.parseAndBuild(allocator, tree_source);
    defer tree_result.deinit();

    if (tree_result.hasErrors()) {
        for (tree_result.err_list.errors.items) |e| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ e.loc.line, e.loc.col, e.message });
        }
    } else if (tree_result.trees.len > 0) {
        const tree_output = try zigraph.terminal.tree.render(
            tree_result.trees[0].roots,
            allocator,
            .{ .indent = 4, .char_set = .unicode },
        );
        defer allocator.free(tree_output);
        try stdout.writeAll(tree_output);
        if (!std.mem.endsWith(u8, tree_output, "\n")) {
            try stdout.writeByte('\n');
        }
    } else {
        try stderr.writeAll("No trees found.\n");
    }

    try stdout.writeByte('\n');

    // ── Demo 4: [table] block ─────────────────────────────────────────────────
    try stdout.writeAll("=== Demo 4: [table] Block ===\n\n");

    var table_result = try dsl.parseAndBuild(allocator, table_source);
    defer table_result.deinit();

    if (table_result.hasErrors()) {
        for (table_result.err_list.errors.items) |e| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ e.loc.line, e.loc.col, e.message });
        }
    } else if (table_result.tables.len > 0) {
        const tbl = &table_result.tables[0];
        const table_output = try zigraph.terminal.table.render(
            tbl.headers,
            tbl.rows,
            allocator,
            .{ .border = .single, .char_set = .unicode, .header_attrs = .{ .bold = true } },
        );
        defer allocator.free(table_output);
        try stdout.writeAll(table_output);
        if (!std.mem.endsWith(u8, table_output, "\n")) {
            try stdout.writeByte('\n');
        }
    } else {
        try stderr.writeAll("No tables found.\n");
    }

    try stdout.writeByte('\n');

    // ── Demo 5: [card] block ──────────────────────────────────────────────────
    try stdout.writeAll("=== Demo 5: [card] Block ===\n\n");

    var card_result = try dsl.parseAndBuild(allocator, card_source);
    defer card_result.deinit();

    if (card_result.hasErrors()) {
        for (card_result.err_list.errors.items) |e| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ e.loc.line, e.loc.col, e.message });
        }
    } else if (card_result.graphs.len > 0) {
        var ir = try zigraph.layout(&card_result.graphs[0].graph, allocator, card_result.graphs[0].config);
        defer ir.deinit();
        dsl.direction.applyDirection(&ir, card_result.graphs[0].direction);

        const terminal_output = try zigraph.terminal.render(&ir, allocator);
        defer allocator.free(terminal_output);
        try stdout.writeAll(terminal_output);
        if (!std.mem.endsWith(u8, terminal_output, "\n")) {
            try stdout.writeByte('\n');
        }
    } else {
        try stderr.writeAll("No graphs found in card input.\n");
    }

    try stdout.writeByte('\n');

    // ── Demo 6: vars substitution ─────────────────────────────────────────────
    try stdout.writeAll("=== Demo 6: Vars Substitution ===\n\n");

    var vars_result = try dsl.parseAndBuild(allocator, vars_source);
    defer vars_result.deinit();

    if (vars_result.hasErrors()) {
        for (vars_result.err_list.errors.items) |e| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ e.loc.line, e.loc.col, e.message });
        }
    } else if (vars_result.graphs.len > 0) {
        var ir = try zigraph.layout(&vars_result.graphs[0].graph, allocator, vars_result.graphs[0].config);
        defer ir.deinit();
        dsl.direction.applyDirection(&ir, vars_result.graphs[0].direction);

        const terminal_output = try zigraph.terminal.render(&ir, allocator);
        defer allocator.free(terminal_output);
        try stdout.writeAll(terminal_output);
        if (!std.mem.endsWith(u8, terminal_output, "\n")) {
            try stdout.writeByte('\n');
        }
    } else {
        try stderr.writeAll("No graphs found in vars input.\n");
    }
}
