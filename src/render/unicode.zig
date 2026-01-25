//! Unicode renderer using box drawing characters
//!
//! Converts LayoutIR to text using Unicode box drawing glyphs.
//!
//! ## Box Drawing Characters
//!
//! - `│` vertical line
//! - `─` horizontal line
//! - `↓` arrow down
//! - `└` corner down-right
//! - `┘` corner down-left
//! - `┌` corner up-right
//! - `┐` corner up-left

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR;
const LayoutNode = ir_mod.LayoutNode;
const LayoutEdge = ir_mod.LayoutEdge;
const EdgePath = ir_mod.EdgePath;
const colors = @import("colors.zig");

// Box drawing characters as u21 codepoints (comptime decoded)
const CP_V_LINE: u21 = '│';
const CP_H_LINE: u21 = '─';
const CP_ARROW_DOWN: u21 = '↓';
const CP_CORNER_DR: u21 = '└'; // down-right (from above, going right)
const CP_CORNER_DL: u21 = '┘'; // down-left (from above, going left)
const CP_CORNER_UR: u21 = '┌'; // from above-right, going down
const CP_CORNER_UL: u21 = '┐'; // from above-left, going down
const CP_T_DOWN: u21 = '┬'; // T-junction: horizontal with down
const CP_T_UP: u21 = '┴'; // T-junction: horizontal with up
const CP_T_RIGHT: u21 = '├'; // T-junction: vertical with right
const CP_T_LEFT: u21 = '┤'; // T-junction: vertical with left
const CP_CROSS: u21 = '┼'; // Crossing

/// 2D buffer backed by a single flat allocation for cache efficiency.
/// Includes optional color plane for ANSI edge coloring.
const Buffer2D = struct {
    data: []u21,
    colors: []u8, // ANSI color code per cell (0 = no color)
    width: usize,
    height: usize,

    const max_buffer_size: usize = 100_000_000; // 100M cells max (~400MB)

    fn init(allocator: Allocator, w: usize, h: usize) !Buffer2D {
        // Check for overflow and unreasonable sizes
        const size = std.math.mul(usize, w, h) catch return error.OutOfMemory;
        if (size > max_buffer_size) return error.OutOfMemory;

        const data = try allocator.alloc(u21, size);
        @memset(data, ' ');

        const color_plane = try allocator.alloc(u8, size);
        @memset(color_plane, 0); // 0 = no color

        return .{ .data = data, .colors = color_plane, .width = w, .height = h };
    }

    fn deinit(self: *Buffer2D, allocator: Allocator) void {
        allocator.free(self.data);
        allocator.free(self.colors);
    }

    inline fn get(self: *const Buffer2D, x: usize, y: usize) u21 {
        if (x >= self.width or y >= self.height) return ' ';
        return self.data[y * self.width + x];
    }

    inline fn getColor(self: *const Buffer2D, x: usize, y: usize) u8 {
        if (x >= self.width or y >= self.height) return 0;
        return self.colors[y * self.width + x];
    }

    inline fn set(self: *Buffer2D, x: usize, y: usize, val: u21) void {
        if (x >= self.width or y >= self.height) return;
        self.data[y * self.width + x] = val;
    }

    inline fn setWithColor(self: *Buffer2D, x: usize, y: usize, val: u21, color: u8) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        self.data[idx] = val;
        self.colors[idx] = color;
    }

    fn getRow(self: *const Buffer2D, y: usize) []const u21 {
        if (y >= self.height) return &.{};
        const start = y * self.width;
        return self.data[start .. start + self.width];
    }

    fn getColorRow(self: *const Buffer2D, y: usize) []const u8 {
        if (y >= self.height) return &.{};
        const start = y * self.width;
        return self.colors[start .. start + self.width];
    }
};

/// Configuration for Unicode rendering.
pub const Config = struct {
    /// Show dummy nodes as 'O' (for debugging layout)
    /// When false, dummy nodes are invisible (edges draw through them)
    show_dummy_nodes: bool = false,

    /// Edge color palette (ANSI 256-color codes)
    /// When set, edges will be colored based on their edge_index
    /// Use colors.ansi, colors.ansi_dark, or colors.ansi_light
    edge_palette: ?[]const u8 = null,
};

/// Render a LayoutIR to a Unicode string.
pub fn render(layout_ir: *const LayoutIR, allocator: Allocator) ![]u8 {
    return renderWithConfig(layout_ir, allocator, .{});
}

/// Render a LayoutIR to a Unicode string with configuration.
pub fn renderWithConfig(layout_ir: *const LayoutIR, allocator: Allocator, config: Config) ![]u8 {
    const width = layout_ir.getWidth();
    const height = layout_ir.getHeight();

    if (width == 0 or height == 0) {
        const result = try allocator.alloc(u8, 0);
        return result;
    }

    // Single flat allocation for cache efficiency
    var buffer = try Buffer2D.init(allocator, width, height);
    defer buffer.deinit(allocator);

    // Paint edges first (so nodes overwrite them)
    for (layout_ir.getEdges()) |edge| {
        // Get color for this edge if palette is set
        const edge_color: u8 = if (config.edge_palette) |palette|
            colors.getAnsi(palette, edge.edge_index)
        else
            0;
        paintEdge(&buffer, &edge, edge_color);
    }

    // For invisible dummy nodes, paint a vertical line at their position
    // and clean up any arrows to make a continuous line
    if (!config.show_dummy_nodes) {
        for (layout_ir.getNodes()) |node| {
            if (node.kind == .dummy) {
                // Draw vertical line at dummy position
                const x = node.center_x;
                const y = node.y;
                
                // Set the dummy position itself to vertical line
                const current = buffer.get(x, y);
                const merged = mergeJunction(current, true, true, false, false);
                buffer.set(x, y, merged);
                
                // Also fix any arrows above/below to be vertical lines
                // Check row above
                if (y > 0) {
                    const above = buffer.get(x, y - 1);
                    if (above == CP_ARROW_DOWN) {
                        buffer.set(x, y - 1, CP_V_LINE);
                    }
                }
                // Check row below
                const below = buffer.get(x, y + 1);
                if (below == CP_ARROW_DOWN) {
                    buffer.set(x, y + 1, CP_V_LINE);
                }
            }
        }
    }

    // Paint nodes (overwrite edges)
    for (layout_ir.getNodes()) |node| {
        paintNode(&buffer, &node, config.show_dummy_nodes);
    }

    // Convert to UTF-8 string with optional ANSI color escapes
    // Pre-allocate: worst case is 4 bytes per char + 15 bytes for color escape + newline per row
    const bytes_per_char: usize = if (config.edge_palette != null) 20 else 4;
    var output: std.ArrayListUnmanaged(u8) = .{};
    errdefer output.deinit(allocator);
    try output.ensureTotalCapacity(allocator, height * (width * bytes_per_char + 1));

    var last_color: u8 = 0;

    for (0..height) |y| {
        const row = buffer.getRow(y);
        const color_row = buffer.getColorRow(y);

        // Trim trailing spaces
        var end: usize = row.len;
        while (end > 0 and row[end - 1] == ' ') {
            end -= 1;
        }

        // Encode each character with optional color
        for (row[0..end], color_row[0..end]) |codepoint, cell_color| {
            // Handle color changes
            if (config.edge_palette != null) {
                if (cell_color != 0 and cell_color != last_color) {
                    // Start new color
                    const seq = colors.escape.fg256(cell_color);
                    try output.appendSlice(allocator, &seq);
                    last_color = cell_color;
                } else if (cell_color == 0 and last_color != 0) {
                    // Reset to default
                    try output.appendSlice(allocator, colors.escape.reset);
                    last_color = 0;
                }
            }

            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &buf) catch 1;
            try output.appendSlice(allocator, buf[0..len]);
        }

        // Reset color at end of line if needed
        if (config.edge_palette != null and last_color != 0) {
            try output.appendSlice(allocator, colors.escape.reset);
            last_color = 0;
        }

        try output.append(allocator, '\n');
    }

    return output.toOwnedSlice(allocator);
}

/// Paint a node onto the buffer.
/// Uses different brackets based on node kind:
/// - explicit: [label]
/// - implicit: <label>
/// - dummy:    O (when show_dummy_nodes=true), invisible otherwise
fn paintNode(buffer: *Buffer2D, node: *const LayoutNode, show_dummy_nodes: bool) void {
    const y = node.y;
    var x = node.x;

    // Dummy nodes: show as 'O' if debugging, skip if not
    if (node.kind == .dummy) {
        if (show_dummy_nodes) {
            // Draw the label (e.g., 'O')
            for (node.label) |c| {
                buffer.set(x, y, c);
                x += 1;
            }
        }
        // If not showing dummies, don't paint anything
        // The edge lines will draw through this position
        return;
    }

    // Choose brackets based on node kind
    const open_bracket: u21 = switch (node.kind) {
        .explicit => '[',
        .implicit => '<',
        .dummy => unreachable, // Handled above
    };
    const close_bracket: u21 = switch (node.kind) {
        .explicit => ']',
        .implicit => '>',
        .dummy => unreachable,
    };

    // Draw opening bracket
    buffer.set(x, y, open_bracket);
    x += 1;

    // Draw label
    for (node.label) |c| {
        buffer.set(x, y, c);
        x += 1;
    }

    // Draw closing bracket
    buffer.set(x, y, close_bracket);
}

/// Merge a junction character based on which directions are connected.
/// Returns the appropriate box-drawing character for the intersection.
fn mergeJunction(current: u21, from_above: bool, to_below: bool, to_right: bool, to_left: bool) u21 {
    // Determine what directions the current character connects
    var up = from_above;
    var down = to_below;
    var left = to_left;
    var right = to_right;

    // Check what the existing character already connects
    if (current == CP_V_LINE) {
        up = true;
        down = true;
    } else if (current == CP_ARROW_DOWN) {
        // Arrow indicates coming from above and pointing down
        up = true;
        down = true;
    } else if (current == CP_H_LINE) {
        left = true;
        right = true;
    } else if (current == CP_CORNER_DR) { // └
        up = true;
        right = true;
    } else if (current == CP_CORNER_DL) { // ┘
        up = true;
        left = true;
    } else if (current == CP_CORNER_UR) { // ┌
        down = true;
        right = true;
    } else if (current == CP_CORNER_UL) { // ┐
        down = true;
        left = true;
    } else if (current == CP_T_DOWN) { // ┬
        left = true;
        right = true;
        down = true;
    } else if (current == CP_T_UP) { // ┴
        left = true;
        right = true;
        up = true;
    } else if (current == CP_T_RIGHT) { // ├
        up = true;
        down = true;
        right = true;
    } else if (current == CP_T_LEFT) { // ┤
        up = true;
        down = true;
        left = true;
    } else if (current == CP_CROSS) { // ┼
        up = true;
        down = true;
        left = true;
        right = true;
    }

    // Select the right character based on connections
    const count = @as(u8, @intFromBool(up)) + @as(u8, @intFromBool(down)) + @as(u8, @intFromBool(left)) + @as(u8, @intFromBool(right));

    if (count == 4) {
        return CP_CROSS; // ┼
    } else if (count == 3) {
        if (!up) return CP_T_DOWN; // ┬
        if (!down) return CP_T_UP; // ┴
        if (!left) return CP_T_RIGHT; // ├
        if (!right) return CP_T_LEFT; // ┤
    } else if (count == 2) {
        if (up and down) return CP_V_LINE;
        if (left and right) return CP_H_LINE;
        if (up and right) return CP_CORNER_DR; // └
        if (up and left) return CP_CORNER_DL; // ┘
        if (down and right) return CP_CORNER_UR; // ┌
        if (down and left) return CP_CORNER_UL; // ┐
    }

    // Fallback
    if (up or down) return CP_V_LINE;
    if (left or right) return CP_H_LINE;
    return current;
}

/// Paint an edge onto the buffer.
/// Paint an edge onto the buffer.
fn paintEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: u8) void {
    switch (edge.path) {
        .direct => {
            // Vertical line from from_y to to_y-1 at from_x
            const x = edge.from_x;
            var y = edge.from_y;
            while (y < edge.to_y) : (y += 1) {
                if (y == edge.to_y - 1) {
                    buffer.setWithColor(x, y, CP_ARROW_DOWN, color);
                } else {
                    buffer.setWithColor(x, y, CP_V_LINE, color);
                }
            }
        },
        .corner => |corner| {
            const x1 = edge.from_x;
            const x2 = edge.to_x;
            const h_y = corner.horizontal_y;
            const min_x = @min(x1, x2);
            const max_x = @max(x1, x2);

            // Vertical from source to horizontal
            var y = edge.from_y;
            while (y < h_y) : (y += 1) {
                buffer.setWithColor(x1, y, CP_V_LINE, color);
            }

            // Horizontal segment (only fill spaces)
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                if (x != x1 and x != x2) {
                    const current = buffer.get(x, h_y);
                    if (current == ' ') {
                        buffer.setWithColor(x, h_y, CP_H_LINE, color);
                    }
                }
            }

            // Junction at source x
            const current1 = buffer.get(x1, h_y);
            buffer.setWithColor(x1, h_y, mergeJunction(current1, true, false, x1 < x2, x1 > x2), color);

            // Corner at target x
            const current2 = buffer.get(x2, h_y);
            buffer.setWithColor(x2, h_y, mergeJunction(current2, false, true, x1 > x2, x1 < x2), color);

            // Vertical from horizontal to target
            y = h_y + 1;
            while (y < edge.to_y) : (y += 1) {
                if (y == edge.to_y - 1) {
                    buffer.setWithColor(x2, y, CP_ARROW_DOWN, color);
                } else {
                    buffer.setWithColor(x2, y, CP_V_LINE, color);
                }
            }
        },
        .side_channel => |sc| {
            const x1 = edge.from_x;
            const x2 = edge.to_x;
            const ch_x = sc.channel_x;

            // Vertical from source to start_y
            var y = edge.from_y + 1;
            while (y < sc.start_y) : (y += 1) {
                buffer.setWithColor(x1, y, CP_V_LINE, color);
            }

            // Horizontal at start_y
            const min_x1 = @min(x1, ch_x);
            const max_x1 = @max(x1, ch_x);
            var x = min_x1;
            while (x <= max_x1) : (x += 1) {
                if (buffer.get(x, sc.start_y) == ' ') {
                    buffer.setWithColor(x, sc.start_y, CP_H_LINE, color);
                }
            }

            // Vertical in channel
            y = sc.start_y + 1;
            while (y < sc.end_y) : (y += 1) {
                buffer.setWithColor(ch_x, y, CP_V_LINE, color);
            }

            // Horizontal at end_y
            const min_x2 = @min(ch_x, x2);
            const max_x2 = @max(ch_x, x2);
            x = min_x2;
            while (x <= max_x2) : (x += 1) {
                if (buffer.get(x, sc.end_y) == ' ') {
                    buffer.setWithColor(x, sc.end_y, CP_H_LINE, color);
                }
            }

            // Vertical from end_y to target
            y = sc.end_y + 1;
            while (y < edge.to_y) : (y += 1) {
                if (y == edge.to_y - 1) {
                    buffer.setWithColor(x2, y, CP_ARROW_DOWN, color);
                } else {
                    buffer.setWithColor(x2, y, CP_V_LINE, color);
                }
            }
        },
        .multi_segment => {
            // For multi-segment paths (skip-level edges through dummy nodes),
            // render the same as corner path for Unicode output.
            // The multi-segment waypoints are used for SVG rendering.
            const x1 = edge.from_x;
            const x2 = edge.to_x;
            const h_y = edge.from_y + 1; // Horizontal line just below source
            const min_x = @min(x1, x2);
            const max_x = @max(x1, x2);

            // Vertical from source to horizontal
            var y = edge.from_y;
            while (y < h_y) : (y += 1) {
                buffer.setWithColor(x1, y, CP_V_LINE, color);
            }

            // Horizontal segment (only fill spaces)
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                if (x != x1 and x != x2) {
                    const current = buffer.get(x, h_y);
                    if (current == ' ') {
                        buffer.setWithColor(x, h_y, CP_H_LINE, color);
                    }
                }
            }

            // Junction at source x
            const current1 = buffer.get(x1, h_y);
            buffer.setWithColor(x1, h_y, mergeJunction(current1, true, false, x1 < x2, x1 > x2), color);

            // Corner at target x
            const current2 = buffer.get(x2, h_y);
            buffer.setWithColor(x2, h_y, mergeJunction(current2, false, true, x1 > x2, x1 < x2), color);

            // Vertical from horizontal to target
            y = h_y + 1;
            while (y < edge.to_y) : (y += 1) {
                if (y == edge.to_y - 1) {
                    buffer.setWithColor(x2, y, CP_ARROW_DOWN, color);
                } else {
                    buffer.setWithColor(x2, y, CP_V_LINE, color);
                }
            }
        },
        .spline => {
            // For Unicode rendering, approximate spline as direct line
            // (Unicode can't render curves, so we fall back to straight connection)
            const x = edge.from_x;
            var y = edge.from_y;
            while (y < edge.to_y) : (y += 1) {
                if (y == edge.to_y - 1) {
                    buffer.setWithColor(x, y, CP_ARROW_DOWN, color);
                } else {
                    buffer.setWithColor(x, y, CP_V_LINE, color);
                }
            }
            // Handle horizontal offset with corner if needed
            if (edge.from_x != edge.to_x) {
                const min_x = @min(edge.from_x, edge.to_x);
                const max_x = @max(edge.from_x, edge.to_x);
                const mid_y = edge.from_y + (edge.to_y - edge.from_y) / 2;
                var hx = min_x;
                while (hx <= max_x) : (hx += 1) {
                    if (buffer.get(hx, mid_y) == ' ') {
                        buffer.setWithColor(hx, mid_y, CP_H_LINE, color);
                    }
                }
            }
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

test "unicode render: simple chain" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    // Add nodes
    try layout_ir.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout_ir.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 3,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });

    // Add edge
    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 0,
        .to_x = 1,
        .to_y = 3,
        .path = .{ .direct = {} },
        .edge_index = 0,
    });

    layout_ir.setDimensions(3, 4);

    const output = try render(&layout_ir, allocator);
    defer allocator.free(output);

    // Check output contains nodes
    try std.testing.expect(std.mem.indexOf(u8, output, "[A]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[B]") != null);

    // Check output contains arrow
    try std.testing.expect(std.mem.indexOf(u8, output, "↓") != null);
}

test "unicode render: empty graph" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    const output = try render(&layout_ir, allocator);
    defer allocator.free(output);

    try std.testing.expectEqual(@as(usize, 0), output.len);
}
