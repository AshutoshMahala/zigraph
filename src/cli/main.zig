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
    direction_override: ?dsl.ast.Direction = null,
};

const CheckArgs = struct {
    input_file: []const u8,
};

const FmtArgs = struct {
    input_file: ?[]const u8 = null,
    check_only: bool = false,
    write_inplace: bool = true,
};

const WatchArgs = struct {
    input_file: []const u8,
    format: Format = .terminal,
    direction_override: ?dsl.ast.Direction = null,
    poll_ms: u64 = 500,
};

const EditArgs = struct {
    files: []const []const u8 = &.{},
};

const Command = union(enum) {
    render: RenderArgs,
    check: CheckArgs,
    fmt: FmtArgs,
    watch: WatchArgs,
    edit: EditArgs,
    help,
};

fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: zigraph <command> [options]
        \\
        \\Commands:
        \\  render [file]          Render a .zgraph or .md file (reads stdin if no file given)
        \\  check <file>           Validate syntax, print OK or errors
        \\  fmt [file]             Format a .zgraph file (reads stdin if no file given)
        \\  watch <file>           Watch a file and re-render on changes
        \\  edit [file...]         Open file(s) in TUI editor
        \\
        \\Render options:
        \\  -f terminal|svg|json                          Output format (default: terminal)
        \\  -o <output>                                   Write output to file (default: stdout)
        \\  -d top-down|left-right|bottom-up|right-left   Override flow direction
        \\
        \\Fmt options:
        \\  --check                Check if file is formatted (exit 1 if not)
        \\  --stdin                Read from stdin, write to stdout
        \\
        \\Watch options:
        \\  -f terminal|svg|json   Output format (default: terminal)
        \\  -d <direction>         Override flow direction
        \\
        \\Examples:
        \\  zigraph render graph.zgraph
        \\  zigraph render graph.md -f svg -o graph.svg
        \\  echo "A -> B -> C" | zigraph render
        \\  zigraph check graph.zgraph
        \\  zigraph fmt graph.zgraph
        \\  zigraph fmt --check graph.zgraph
        \\  zigraph watch graph.zgraph
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
            } else if (std.mem.eql(u8, arg, "-d")) {
                i += 1;
                if (i >= args.len) return error.MissingDirectionValue;
                const dir_str = args[i];
                if (std.mem.eql(u8, dir_str, "top-down")) render_args.direction_override = .top_down
                else if (std.mem.eql(u8, dir_str, "left-right")) render_args.direction_override = .left_right
                else if (std.mem.eql(u8, dir_str, "bottom-up")) render_args.direction_override = .bottom_up
                else if (std.mem.eql(u8, dir_str, "right-left")) render_args.direction_override = .right_left
                else return error.UnknownDirection;
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

    if (std.mem.eql(u8, cmd_str, "fmt")) {
        var fmt_args = FmtArgs{};
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "--check")) {
                fmt_args.check_only = true;
                fmt_args.write_inplace = false;
            } else if (std.mem.eql(u8, arg, "--stdin")) {
                fmt_args.write_inplace = false;
            } else if (arg.len > 0 and arg[0] == '-') {
                return error.UnknownFlag;
            } else {
                fmt_args.input_file = arg;
            }
        }
        return Command{ .fmt = fmt_args };
    }

    if (std.mem.eql(u8, cmd_str, "watch")) {
        if (args.len < 2) {
            return error.MissingFile;
        }
        var watch_args = WatchArgs{ .input_file = args[1] };
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "-f")) {
                i += 1;
                if (i >= args.len) return error.MissingFormatValue;
                const fmt_str = args[i];
                if (std.mem.eql(u8, fmt_str, "terminal")) watch_args.format = .terminal
                else if (std.mem.eql(u8, fmt_str, "svg")) watch_args.format = .svg
                else if (std.mem.eql(u8, fmt_str, "json")) watch_args.format = .json
                else return error.UnknownFormat;
            } else if (std.mem.eql(u8, arg, "-d")) {
                i += 1;
                if (i >= args.len) return error.MissingDirectionValue;
                const dir_str = args[i];
                if (std.mem.eql(u8, dir_str, "top-down")) watch_args.direction_override = .top_down
                else if (std.mem.eql(u8, dir_str, "left-right")) watch_args.direction_override = .left_right
                else if (std.mem.eql(u8, dir_str, "bottom-up")) watch_args.direction_override = .bottom_up
                else if (std.mem.eql(u8, dir_str, "right-left")) watch_args.direction_override = .right_left
                else return error.UnknownDirection;
            } else if (arg.len > 0 and arg[0] == '-') {
                return error.UnknownFlag;
            }
        }
        return Command{ .watch = watch_args };
    }

    if (std.mem.eql(u8, cmd_str, "edit")) {
        // Collect remaining args as file paths
        const files = if (args.len > 1) args[1..] else args[0..0];
        return Command{ .edit = .{ .files = files } };
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
    base_dir: ?[]const u8,
    format: Format,
    direction_override: ?dsl.ast.Direction,
    writer: anytype,
) !void {
    var result = if (is_markdown)
        try dsl.parseMarkdown(allocator, source)
    else
        try dsl.parseAndBuildWithBase(allocator, source, base_dir);
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

        // Apply direction transform: CLI flag overrides file-level @direction
        const dir = direction_override orelse built_graph.direction;
        dsl.direction.applyDirection(&ir, dir);

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
    const base_dir: ?[]const u8 = if (args.input_file) |path| std.fs.path.dirname(path) orelse "." else null;

    // Prepare output writer
    if (args.output_file) |out_path| {
        const out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
        defer out_file.close();
        const file_writer = out_file.deprecatedWriter();
        try renderSource(allocator, source, is_md, base_dir, args.format, args.direction_override, file_writer);
    } else {
        const stdout = std.fs.File.stdout().deprecatedWriter();
        try renderSource(allocator, source, is_md, base_dir, args.format, args.direction_override, stdout);
    }
}

fn cmdFmt(allocator: std.mem.Allocator, args: FmtArgs) !void {
    const source = if (args.input_file) |path|
        try readFile(allocator, path)
    else
        try readStdin(allocator);
    defer allocator.free(source);

    const formatted = try dsl.formatter.format(allocator, source);
    defer allocator.free(formatted);

    if (args.check_only) {
        if (!std.mem.eql(u8, source, formatted)) {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            if (args.input_file) |path| {
                try stderr.print("Would reformat {s}\n", .{path});
            } else {
                try stderr.writeAll("Input is not formatted\n");
            }
            return error.NotFormatted;
        }
        const stdout = std.fs.File.stdout().deprecatedWriter();
        if (args.input_file) |path| {
            try stdout.print("Already formatted: {s}\n", .{path});
        }
        return;
    }

    if (args.write_inplace) {
        if (args.input_file) |path| {
            // Only write if changed
            if (!std.mem.eql(u8, source, formatted)) {
                const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
                defer file.close();
                try file.writeAll(formatted);
                const stderr = std.fs.File.stderr().deprecatedWriter();
                try stderr.print("Formatted {s}\n", .{path});
            }
            return;
        }
    }

    // Write to stdout
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.writeAll(formatted);
}

fn cmdWatch(allocator: std.mem.Allocator, args: WatchArgs) !void {
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const stdout = std.fs.File.stdout().deprecatedWriter();

    try stderr.print("Watching {s} (Ctrl-C to stop)...\n", .{args.input_file});

    var prev_mtime: i128 = 0;
    var first = true;

    while (true) {
        const stat = std.fs.cwd().statFile(args.input_file) catch |err| {
            try stderr.print("error: cannot stat {s}: {s}\n", .{ args.input_file, @errorName(err) });
            std.Thread.sleep(args.poll_ms * std.time.ns_per_ms);
            continue;
        };

        const mtime = stat.mtime;
        if (mtime != prev_mtime or first) {
            prev_mtime = mtime;
            first = false;

            const source = readFile(allocator, args.input_file) catch |err| {
                try stderr.print("error: cannot read {s}: {s}\n", .{ args.input_file, @errorName(err) });
                std.Thread.sleep(args.poll_ms * std.time.ns_per_ms);
                continue;
            };
            defer allocator.free(source);

            const is_md = isMarkdownFile(args.input_file);
            const base_dir: ?[]const u8 = std.fs.path.dirname(args.input_file) orelse ".";

            // Clear screen (ANSI escape)
            try stdout.writeAll("\x1b[2J\x1b[H");

            renderSource(allocator, source, is_md, base_dir, args.format, args.direction_override, stdout) catch |err| {
                if (err != error.ParseError and err != error.NoGraphs) {
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                }
            };

            try stderr.print("[{s} updated]\n", .{args.input_file});
        }

        std.Thread.sleep(args.poll_ms * std.time.ns_per_ms);
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
        } else if (err == error.MissingDirectionValue) {
            try stderr.writeAll("error: -d requires a direction argument (top-down, left-right, bottom-up, right-left)\n");
        } else if (err == error.UnknownDirection) {
            try stderr.writeAll("error: unknown direction (use top-down, left-right, bottom-up, or right-left)\n");
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
        .fmt => |fmt_args| {
            cmdFmt(allocator, fmt_args) catch |err| {
                if (err != error.NotFormatted) {
                    const stderr = std.fs.File.stderr().deprecatedWriter();
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                }
                std.process.exit(1);
            };
        },
        .watch => |watch_args| {
            cmdWatch(allocator, watch_args) catch |err| {
                const stderr = std.fs.File.stderr().deprecatedWriter();
                try stderr.print("error: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };
        },
        .edit => |edit_args| {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            try stderr.writeAll("TUI editor not available in this binary.\n");
            try stderr.writeAll("Use 'zig build run-edit' or 'zigraph-edit' instead.\n");
            _ = edit_args;
            std.process.exit(1);
        },
    }
}
