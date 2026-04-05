//! Table Renderer Demo — border styles, alignment, and headers.
//!
//! Run with: zig build run-terminal-table-demo

const std = @import("std");
const zigraph = @import("zigraph");
const table = zigraph.terminal.table;

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Table Renderer Demo                         ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    const headers: []const []const u8 = &.{ "ID", "Name", "Status" };
    const rows: []const []const []const u8 = &.{
        &.{ "1", "Parser", "done" },
        &.{ "2", "Resolver", "in progress" },
        &.{ "3", "Bridge", "planned" },
    };

    // 1) Single border (default)
    printSection("1) Single border with headers");
    {
        const output = try table.render(headers, rows, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 2) Heavy border
    printSection("2) Heavy border");
    {
        const output = try table.render(headers, rows, allocator, .{ .border = .heavy });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 3) Double border
    printSection("3) Double border");
    {
        const output = try table.render(headers, rows, allocator, .{ .border = .double });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 4) Borderless
    printSection("4) Borderless");
    {
        const output = try table.render(headers, rows, allocator, .{ .border = .none });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 5) Right-aligned numbers
    printSection("5) Right-aligned ID column");
    {
        const alignment: []const table.Alignment = &.{ .right, .left, .center };
        const output = try table.render(headers, rows, allocator, .{ .alignment = alignment });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 6) ASCII fallback
    printSection("6) ASCII fallback");
    {
        const output = try table.render(headers, rows, allocator, .{ .char_set = .ascii });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // 7) No headers
    printSection("7) No headers");
    {
        const output = try table.render(null, rows, allocator, .{});
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
