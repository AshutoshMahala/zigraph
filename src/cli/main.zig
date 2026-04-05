//! zigraph CLI entry point
//!
//! Usage:
//!   zigraph render <file>              Render a .zgraph or .md file to terminal
//!   zigraph render <file> -f terminal  Choose output format (terminal, svg, json)
//!   zigraph render <file> -o <output>  Write output to a file instead of stdout
//!   echo "A -> B" | zigraph render     Read from stdin
//!   zigraph check <file>               Validate syntax, print OK or errors
//!   zigraph --help                     Show this help text

const std = @import("std");
const zigraph = @import("zigraph");
const dsl = @import("dsl");

const Format = enum { terminal, svg, json };

const RenderArgs = struct {
    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,
    format: Format = .terminal,
};

const CheckArgs = struct {
    input_file: []const u8,
};

const Command = union(enum) {
    render: RenderArgs,
    check: CheckArgs,
    help,
};

fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: zigraph <command> [options]
        \\
        \\Commands:
        \\  render [file]          Render a .zgraph or .md file (reads stdin if no file given)
        \\  check <file>           Validate syntax, print OK or errors
        \\
        \\Render options:
        \\  -f terminal|svg|json   Output format (default: terminal)
        \\  -o <output>            Write output to file (default: stdout)
        \\
        \\Examples:
        \\  zigraph render graph.zgraph
        \\  zigraph render graph.md -f svg -o graph.svg
        \\  echo "A -> B -> C" | zigraph render
        \\  zigraph check graph.zgraph
        \\
    );
}

fn parseArgs(args: []const []const u8) !Command {
    if (args.len == 0) return .help;

    const cmd_str = args[0];

    if (std.mem.eql(u8, cmd_str, "--help") or std.mem.eql(u8, cmd_str, "-h")) {
        return .help;
    }

    if (std.mem.eql(u8, cmd_str, "render")) {
        var render_args = RenderArgs{};
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "-f")) {
                i += 1;
                if (i >= args.len) {
                    return error.MissingFormatValue;
                }
                const fmt_str = args[i];
                if (std.mem.eql(u8, fmt_str, "terminal")) {
                    render_args.format = .terminal;
                } else if (std.mem.eql(u8, fmt_str, "svg")) {
                    render_args.format = .svg;
                } else if (std.mem.eql(u8, fmt_str, "json")) {
                    render_args.format = .json;
                } else {
                    return error.UnknownFormat;
                }
            } else if (std.mem.eql(u8, arg, "-o")) {
                i += 1;
                if (i >= args.len) {
                    return error.MissingOutputValue;
                }
                render_args.output_file = args[i];
            } else if (arg.len > 0 and arg[0] == '-') {
                return error.UnknownFlag;
            } else {
                render_args.input_file = arg;
            }
        }
        return Command{ .render = render_args };
    }

    if (std.mem.eql(u8, cmd_str, "check")) {
        if (args.len < 2) {
            return error.MissingFile;
        }
        return Command{ .check = CheckArgs{ .input_file = args[1] } };
    }

    return error.UnknownCommand;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 64 * 1024 * 1024);
}

fn readStdin(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.File.stdin().readToEndAlloc(allocator, 64 * 1024 * 1024);
}

fn isMarkdownFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".md") or std.mem.endsWith(u8, path, ".markdown");
}

fn renderSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    is_markdown: bool,
    format: Format,
    writer: anytype,
) !void {
    var result = if (is_markdown)
        try dsl.parseMarkdown(allocator, source)
    else
        try dsl.parseAndBuild(allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        for (result.err_list.errors.items) |err| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ err.loc.line, err.loc.col, err.message });
        }
        return error.ParseError;
    }

    if (result.graphs.len == 0) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.writeAll("No graphs found in input.\n");
        return error.NoGraphs;
    }

    for (result.graphs, 0..) |*built_graph, i| {
        if (result.graphs.len > 1) {
            try writer.print("--- Graph {d} ---\n", .{i + 1});
        }

        var ir = try zigraph.layout(&built_graph.graph, allocator, built_graph.config);
        defer ir.deinit();

        switch (format) {
            .terminal => {
                const output = try zigraph.terminal.render(&ir, allocator);
                defer allocator.free(output);
                try writer.writeAll(output);
                if (!std.mem.endsWith(u8, output, "\n")) {
                    try writer.writeByte('\n');
                }
            },
            .svg => {
                const output = try zigraph.svg.render(&ir, allocator, .{});
                defer allocator.free(output);
                try writer.writeAll(output);
            },
            .json => {
                const output = try zigraph.json.serialize(&ir, allocator);
                defer allocator.free(output);
                try writer.writeAll(output);
            },
        }
    }
}

fn cmdRender(allocator: std.mem.Allocator, args: RenderArgs) !void {
    // Read source
    const source = if (args.input_file) |path|
        try readFile(allocator, path)
    else
        try readStdin(allocator);
    defer allocator.free(source);

    const is_md = if (args.input_file) |path| isMarkdownFile(path) else false;

    // Prepare output writer
    if (args.output_file) |out_path| {
        const out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
        defer out_file.close();
        const file_writer = out_file.deprecatedWriter();
        try renderSource(allocator, source, is_md, args.format, file_writer);
    } else {
        const stdout = std.fs.File.stdout().deprecatedWriter();
        try renderSource(allocator, source, is_md, args.format, stdout);
    }
}

fn cmdCheck(allocator: std.mem.Allocator, args: CheckArgs) !void {
    const source = try readFile(allocator, args.input_file);
    defer allocator.free(source);

    const is_md = isMarkdownFile(args.input_file);

    var result = if (is_md)
        try dsl.parseMarkdown(allocator, source)
    else
        try dsl.parseAndBuild(allocator, source);
    defer result.deinit();

    const stderr = std.fs.File.stderr().deprecatedWriter();
    const stdout = std.fs.File.stdout().deprecatedWriter();

    if (result.hasErrors()) {
        for (result.err_list.errors.items) |err| {
            try stderr.print("{d}:{d}: error: {s}\n", .{ err.loc.line, err.loc.col, err.message });
        }
        try stderr.print("{d} error(s) found in {s}\n", .{ result.err_list.errors.items.len, args.input_file });
        return error.ParseError;
    }

    try stdout.print("OK: {s} ({d} graph(s))\n", .{ args.input_file, result.graphs.len });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    // Skip argv[0] (binary name)
    const args = if (raw_args.len > 1) raw_args[1..] else raw_args[0..0];

    const cmd = parseArgs(args) catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        if (err == error.UnknownCommand) {
            try stderr.print("error: unknown command '{s}'\n", .{if (args.len > 0) args[0] else ""});
        } else if (err == error.MissingFile) {
            try stderr.writeAll("error: 'check' requires a file argument\n");
        } else if (err == error.UnknownFormat) {
            try stderr.print("error: unknown format (use terminal, svg, or json)\n", .{});
        } else if (err == error.MissingFormatValue) {
            try stderr.writeAll("error: -f requires a format argument (terminal, svg, json)\n");
        } else if (err == error.MissingOutputValue) {
            try stderr.writeAll("error: -o requires a file path argument\n");
        } else if (err == error.UnknownFlag) {
            try stderr.writeAll("error: unknown flag\n");
        } else {
            try stderr.print("error: {s}\n", .{@errorName(err)});
        }
        try stderr.writeAll("Run 'zigraph --help' for usage.\n");
        std.process.exit(1);
    };

    switch (cmd) {
        .help => {
            const stdout = std.fs.File.stdout().deprecatedWriter();
            try printHelp(stdout);
        },
        .render => |render_args| {
            cmdRender(allocator, render_args) catch |err| {
                if (err != error.ParseError and err != error.NoGraphs) {
                    const stderr = std.fs.File.stderr().deprecatedWriter();
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                }
                std.process.exit(1);
            };
        },
        .check => |check_args| {
            cmdCheck(allocator, check_args) catch |err| {
                if (err != error.ParseError) {
                    const stderr = std.fs.File.stderr().deprecatedWriter();
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                }
                std.process.exit(1);
            };
        },
    }
}
