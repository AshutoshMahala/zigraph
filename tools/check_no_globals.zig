//! No-globals gate for the passive-parallelism contract.
//!
//! Scans every .zig file under src/ for module-level mutable state
//! (`var`, `pub var`, `export var`, `threadlocal var` at file scope) and
//! exits nonzero if any is found. Runs as a dependency of `zig build test`,
//! so the concurrency invariant cannot be silently reintroduced.
//!
//! File-scope declarations start at column zero, so a line-start prefix
//! match is sufficient; container-level and function-local `var`s are
//! always indented.

const std = @import("std");

const bad_prefixes = [_][]const u8{
    "var ",
    "pub var ",
    "export var ",
    "threadlocal var ",
    "pub threadlocal var ",
    "export threadlocal var ",
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var src = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer src.close(io);

    var walker = try src.walk(allocator);
    defer walker.deinit();

    var violations: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;

        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(64 * 1024 * 1024));
        defer allocator.free(source);

        var line_no: usize = 1;
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| : (line_no += 1) {
            for (bad_prefixes) |prefix| {
                if (std.mem.startsWith(u8, line, prefix)) {
                    std.debug.print("src/{s}:{d}: module-level mutable state: {s}\n", .{ entry.path, line_no, line });
                    violations += 1;
                    break;
                }
            }
        }
    }

    if (violations != 0) {
        std.debug.print(
            "\nno-globals check FAILED: {d} violation(s).\n" ++
                "Module-level mutable state breaks the passive-parallelism contract\n" ++
                "(independent graphs must be usable from independent threads).\n" ++
                "Move the state into a per-graph or per-call context instead.\n",
            .{violations},
        );
        std.process.exit(1);
    }
}
