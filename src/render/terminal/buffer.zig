//! 2D character buffer backed by a single flat allocation.
//!
//! Includes an optional color plane for ANSI edge colouring.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 2D buffer backed by a single flat allocation for cache efficiency.
/// Includes optional color plane for ANSI edge coloring.
pub const Buffer2D = struct {
    data: []u21,
    colors: []u8, // ANSI color code per cell (0 = no color)
    width: usize,
    height: usize,

    const max_buffer_size: usize = 100_000_000; // 100M cells max (~400MB)

    pub fn init(allocator: Allocator, w: usize, h: usize) !Buffer2D {
        // Check for overflow and unreasonable sizes
        const size = std.math.mul(usize, w, h) catch return error.OutOfMemory;
        if (size > max_buffer_size) return error.OutOfMemory;

        const data = try allocator.alloc(u21, size);
        @memset(data, ' ');

        const color_plane = try allocator.alloc(u8, size);
        @memset(color_plane, 0); // 0 = no color

        return .{ .data = data, .colors = color_plane, .width = w, .height = h };
    }

    pub fn deinit(self: *Buffer2D, allocator: Allocator) void {
        allocator.free(self.data);
        allocator.free(self.colors);
    }

    pub inline fn get(self: *const Buffer2D, x: usize, y: usize) u21 {
        if (x >= self.width or y >= self.height) return ' ';
        return self.data[y * self.width + x];
    }

    pub inline fn getColor(self: *const Buffer2D, x: usize, y: usize) u8 {
        if (x >= self.width or y >= self.height) return 0;
        return self.colors[y * self.width + x];
    }

    pub inline fn set(self: *Buffer2D, x: usize, y: usize, val: u21) void {
        if (x >= self.width or y >= self.height) return;
        self.data[y * self.width + x] = val;
    }

    pub inline fn setWithColor(self: *Buffer2D, x: usize, y: usize, val: u21, color: u8) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        self.data[idx] = val;
        self.colors[idx] = color;
    }

    pub fn getRow(self: *const Buffer2D, y: usize) []const u21 {
        if (y >= self.height) return &.{};
        const start = y * self.width;
        return self.data[start .. start + self.width];
    }

    pub fn getColorRow(self: *const Buffer2D, y: usize) []const u8 {
        if (y >= self.height) return &.{};
        const start = y * self.width;
        return self.colors[start .. start + self.width];
    }
};
