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
const LayoutIR = ir_mod.LayoutIR(usize);
const LayoutNode = ir_mod.LayoutNode(usize);
const LayoutEdge = ir_mod.LayoutEdge(usize);
const EdgePath = ir_mod.EdgePath(usize);
const colors = @import("colors.zig");

// Box drawing characters as u21 codepoints (comptime decoded)
const CP_V_LINE: u21 = '│';
const CP_H_LINE: u21 = '─';
const CP_ARROW_DOWN: u21 = '↓';
const CP_ARROW_UP: u21 = '↑';
const CP_ARROW_RIGHT: u21 = '→';
const CP_ARROW_LEFT: u21 = '←';
// Dashed arrows for reversed (back) edges
const CP_ARROW_DOWN_DASH: u21 = '⇣';
const CP_ARROW_UP_DASH: u21 = '⇡';
const CP_ARROW_RIGHT_DASH: u21 = '⇢';
const CP_ARROW_LEFT_DASH: u21 = '⇠';
// Dashed line characters for reversed (back) edge body segments
const CP_V_LINE_DASH: u21 = '┊'; // light quadruple dash vertical
const CP_H_LINE_DASH: u21 = '┈'; // light quadruple dash horizontal
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

/// Render any GenericLayoutIR to a Unicode string.
/// Converts coordinates to usize if needed, then renders.
pub fn renderGeneric(comptime Coord: type, layout_ir: *const ir_mod.LayoutIR(Coord), allocator: Allocator) ![]u8 {
    return renderGenericWithConfig(Coord, layout_ir, allocator, .{});
}

/// Render any GenericLayoutIR to a Unicode string with configuration.
pub fn renderGenericWithConfig(comptime Coord: type, layout_ir: *const ir_mod.LayoutIR(Coord), allocator: Allocator, config: Config) ![]u8 {
    if (Coord == usize) {
        return renderWithConfig(layout_ir, allocator, config);
    }
    var converted = try layout_ir.convertCoord(usize, allocator);
    defer converted.deinit();
    return renderWithConfig(&converted, allocator, config);
}

/// Render a LayoutIR to a Unicode string.
pub fn render(layout_ir: *const LayoutIR, allocator: Allocator) ![]u8 {
    return renderWithConfig(layout_ir, allocator, .{});
}

/// Render a LayoutIR to a Unicode string with configuration.
pub fn renderWithConfig(layout_ir: *const LayoutIR, allocator: Allocator, config: Config) ![]u8 {
    const base_width = layout_ir.getWidth();
    const height = layout_ir.getHeight();

    if (base_width == 0 or height == 0) {
        const result = try allocator.alloc(u8, 0);
        return result;
    }

    // Collect reversed edge groups: group segments by edge_index,
    // find the real source/target nodes and their right edges.
    // Each reversed edge group needs a side channel column.

    var reversed_groups: std.ArrayListUnmanaged(ReversedEdgeInfo) = .{};
    defer reversed_groups.deinit(allocator);

    // Track which edge_indices are reversed (to skip their segments in paintEdge)
    var max_edge_idx: usize = 0;
    for (layout_ir.getEdges()) |edge| {
        if (edge.edge_index > max_edge_idx) max_edge_idx = edge.edge_index;
    }

    const reversed_flags = try allocator.alloc(bool, max_edge_idx + 1);
    defer allocator.free(reversed_flags);
    @memset(reversed_flags, false);

    for (layout_ir.getEdges()) |edge| {
        if (edge.reversed) {
            reversed_flags[edge.edge_index] = true;
        }
    }

    // Build reversed edge groups
    for (0..reversed_flags.len) |edge_idx| {
        if (!reversed_flags[edge_idx]) continue;

        // Find first and last segments of this edge (by from_y)
        var first_seg: ?*const LayoutEdge = null;
        var last_seg: ?*const LayoutEdge = null;
        var seg_label: ?[]const u8 = null;
        var seg_label_y: usize = 0;
        for (layout_ir.getEdges()) |*edge| {
            if (edge.edge_index != edge_idx) continue;
            if (first_seg == null or edge.from_y < first_seg.?.from_y) {
                first_seg = edge;
            }
            if (last_seg == null or edge.from_y > last_seg.?.from_y) {
                last_seg = edge;
            }
            if (edge.label != null) {
                seg_label = edge.label;
                seg_label_y = edge.label_y;
            }
        }

        if (first_seg == null or last_seg == null) continue;

        // For reversed edges: from_id was swapped back to semantic direction.
        // Visually, first_seg is at the top (semantic target), last_seg is at the bottom (semantic source).
        // We need the node positions for source (bottom) and target (top).
        const source_node = layout_ir.nodeById(last_seg.?.from_id);
        const target_node = layout_ir.nodeById(first_seg.?.to_id);

        // If we can't find nodes (e.g., dummy IDs), fall back to edge coords
        const src_right_x = if (source_node) |n| n.x + n.width else last_seg.?.to_x + 1;
        const src_y = if (source_node) |n| n.y else last_seg.?.to_y;
        const tgt_right_x = if (target_node) |n| n.x + n.width else first_seg.?.from_x + 1;
        const tgt_y = if (target_node) |n| n.y else first_seg.?.from_y;

        const edge_color: u8 = if (config.edge_palette) |palette|
            colors.getAnsi(palette, edge_idx)
        else
            0;

        try reversed_groups.append(allocator, .{
            .edge_index = edge_idx,
            .source_right_x = src_right_x,
            .source_y = src_y,
            .target_right_x = tgt_right_x,
            .target_y = tgt_y,
            .channel_x = 0, // assigned below
            .color = edge_color,
            .label = seg_label,
            .label_y = seg_label_y,
            .from_id = last_seg.?.from_id,
            .to_id = first_seg.?.to_id,
        });
    }

    // Assign side channel columns for reversed edges.
    // Place channels to the right of the layout, spaced 2 apart.
    // Skip self-loops (source_y == target_y) — they have no visual side route.
    var extra_width: usize = 0;
    // Count only non-degenerate reversed edges for channel assignment
    var channel_count: usize = 0;
    for (reversed_groups.items) |*grp| {
        if (grp.target_y >= grp.source_y) continue; // self-loop or degenerate
        channel_count += 1;
    }
    if (channel_count > 0) {
        // Find the rightmost extent of all involved nodes
        var max_right: usize = base_width;
        for (reversed_groups.items) |grp| {
            if (grp.source_right_x + 1 > max_right) max_right = grp.source_right_x + 1;
            if (grp.target_right_x + 1 > max_right) max_right = grp.target_right_x + 1;
        }

        // Assign channel columns (each non-degenerate reversed edge gets its own column)
        var ch_idx: usize = 0;
        for (reversed_groups.items) |*grp| {
            if (grp.target_y >= grp.source_y) continue; // self-loop
            grp.channel_x = max_right + 1 + ch_idx * 2;
            ch_idx += 1;
        }

        var max_extent: usize = 0;
        for (reversed_groups.items) |grp| {
            if (grp.target_y >= grp.source_y) continue;
            if (grp.channel_x + 2 > max_extent) max_extent = grp.channel_x + 2;
        }
        // Account for labels centered on the channel that extend to the right
        for (reversed_groups.items) |grp| {
            if (grp.target_y >= grp.source_y) continue; // self-loop
            if (grp.label) |lbl| {
                const label_width = lbl.len + 2; // +2 for quotes
                const label_right = grp.channel_x + label_width / 2 + label_width % 2 + 1;
                if (label_right > max_extent) max_extent = label_right;
            }
        }
        extra_width = if (max_extent > base_width) max_extent - base_width else 0;
    }

    // Account for self-loop indicators (↺ + label) extending past base_width
    for (reversed_groups.items) |grp| {
        if (grp.target_y >= grp.source_y) {
            if (layout_ir.nodeById(grp.from_id)) |node| {
                var needed = node.x + node.width + 1; // +1 for ↺
                if (grp.label) |label| {
                    needed += label.len + 2; // +2 for quotes
                }
                if (needed > base_width + extra_width) {
                    extra_width = needed - base_width;
                }
            }
        }
    }

    const width = base_width + extra_width;

    // Single flat allocation for cache efficiency
    var buffer = try Buffer2D.init(allocator, width, height);
    defer buffer.deinit(allocator);

    // Paint edges first (so nodes overwrite them)
    // Skip reversed edges — they'll be drawn separately with side routing.
    for (layout_ir.getEdges()) |edge| {
        if (reversed_flags[edge.edge_index]) continue;

        // Get color for this edge if palette is set
        const edge_color: u8 = if (config.edge_palette) |palette|
            colors.getAnsi(palette, edge.edge_index)
        else
            0;
        paintEdge(&buffer, &edge, edge_color);
    }

    // Paint reversed edges with side routing
    for (reversed_groups.items) |grp| {
        paintReversedEdgeSide(&buffer, &grp, grp.color);
    }

    // For invisible dummy nodes, paint a vertical line at their position
    // and clean up any arrows to make a continuous line.
    // Skip dummy nodes belonging to reversed edges (those are side-routed).
    if (!config.show_dummy_nodes) {
        for (layout_ir.getNodes()) |node| {
            if (node.kind == .dummy) {
                // Skip dummies belonging to reversed edges
                if (node.edge_index) |ei| {
                    if (ei < reversed_flags.len and reversed_flags[ei]) continue;
                }
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
                    if (above == CP_ARROW_DOWN or above == CP_ARROW_DOWN_DASH) {
                        buffer.set(x, y - 1, CP_V_LINE);
                    } else if (above == CP_ARROW_UP_DASH) {
                        buffer.set(x, y - 1, CP_V_LINE_DASH);
                    }
                }
                // Check row below
                const below = buffer.get(x, y + 1);
                if (below == CP_ARROW_DOWN or below == CP_ARROW_DOWN_DASH) {
                    buffer.set(x, y + 1, CP_V_LINE);
                } else if (below == CP_ARROW_UP_DASH) {
                    buffer.set(x, y + 1, CP_V_LINE_DASH);
                }
            }
        }
    }

    // Paint edge labels (between edges and nodes)
    // Labels are rendered as "text" in quotes, centered on the edge.
    // If a label would collide with existing characters, it's deferred to a legend.
    var legend_edges: std.ArrayListUnmanaged(LegendEntry) = .{};
    defer legend_edges.deinit(allocator);

    // Paint reversed edge labels — centered on the channel column, same logic as normal edges
    for (reversed_groups.items) |grp| {
        if (grp.label) |label| {
            const top_y = grp.target_y;
            const bot_y = grp.source_y;

            // Self-loops (top_y >= bot_y) — handled after node painting with ↺ indicator
            if (top_y >= bot_y) continue;

            const label_width = label.len + 2; // +2 for quotes
            const ch_x = grp.channel_x;
            // Center the label on the channel column, like normal edges center on edge x
            const label_x = if (ch_x >= label_width / 2) ch_x - label_width / 2 else 0;
            // Preferred y: midpoint of vertical span
            const mid_y = top_y + (bot_y - top_y) / 2;

            if (canPlaceLabel(&buffer, label, label_x, mid_y)) {
                paintLabel(&buffer, label, label_x, mid_y, grp.color);
            } else {
                // Slide vertically to find a clear row
                var placed = false;
                const min_y = top_y + 1;
                const max_y = if (bot_y > 1) bot_y - 1 else bot_y;
                var try_y = min_y;
                while (try_y <= max_y) : (try_y += 1) {
                    if (try_y == mid_y) continue;
                    if (canPlaceLabel(&buffer, label, label_x, try_y)) {
                        paintLabel(&buffer, label, label_x, try_y, grp.color);
                        placed = true;
                        break;
                    }
                }
                if (!placed) {
                    try legend_edges.append(allocator, .{
                        .from_id = grp.from_id,
                        .to_id = grp.to_id,
                        .label = label,
                        .color = grp.color,
                    });
                }
            }
        }
    }

    for (layout_ir.getEdges()) |edge| {
        // Skip reversed edges — their labels are handled above
        if (reversed_flags[edge.edge_index]) continue;
        if (edge.label) |label| {
            const edge_color: u8 = if (config.edge_palette) |palette|
                colors.getAnsi(palette, edge.edge_index)
            else
                0;

            if (canPlaceLabel(&buffer, label, edge.label_x, edge.label_y)) {
                paintLabel(&buffer, label, edge.label_x, edge.label_y, edge_color);
            } else {
                // Couldn't place — try sliding Y within the edge's vertical span
                var placed = false;
                const min_y = edge.from_y + 1;
                const max_y = if (edge.to_y > 1) edge.to_y - 1 else edge.to_y;
                var try_y = min_y;
                while (try_y <= max_y) : (try_y += 1) {
                    if (try_y == edge.label_y) continue; // Already tried
                    if (canPlaceLabel(&buffer, label, edge.label_x, try_y)) {
                        paintLabel(&buffer, label, edge.label_x, try_y, edge_color);
                        placed = true;
                        break;
                    }
                }
                if (!placed) {
                    // Fallback: add to legend
                    try legend_edges.append(allocator, .{
                        .from_id = edge.from_id,
                        .to_id = edge.to_id,
                        .label = label,
                        .color = edge_color,
                    });
                }
            }
        }
    }

    // Paint nodes (overwrite edges)
    for (layout_ir.getNodes()) |node| {
        paintNode(&buffer, &node, config.show_dummy_nodes);
    }

    // Paint self-loop indicators (↺) after nodes, so they appear right after the node bracket
    for (reversed_groups.items) |grp| {
        if (grp.target_y >= grp.source_y) {
            // This is a self-loop — find the node to place ↺ after its closing bracket
            if (layout_ir.nodeById(grp.from_id)) |node| {
                const loop_x = node.x + node.width; // right after ']'
                const loop_y = node.y;
                buffer.setWithColor(loop_x, loop_y, 0x21BA, grp.color); // ↺
                // Paint label right after ↺ if present
                if (grp.label) |label| {
                    paintLabel(&buffer, label, loop_x + 1, loop_y, grp.color);
                }
            }
        }
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

    // Append legend for labels that couldn't be placed inline
    if (legend_edges.items.len > 0) {
        try output.appendSlice(allocator, "\nEdge labels:\n");
        for (legend_edges.items) |entry| {
            try output.appendSlice(allocator, "  ");

            // Look up source/target node labels for display
            const from_label = if (layout_ir.nodeById(entry.from_id)) |n| n.label else "?";
            const to_label = if (layout_ir.nodeById(entry.to_id)) |n| n.label else "?";

            // Emit colored label if palette is active
            if (config.edge_palette != null and entry.color != 0) {
                const seq = colors.escape.fg256(entry.color);
                try output.appendSlice(allocator, &seq);
            }

            try output.appendSlice(allocator, from_label);
            try output.appendSlice(allocator, " → ");
            try output.appendSlice(allocator, to_label);
            try output.appendSlice(allocator, ": \"");
            try output.appendSlice(allocator, entry.label);
            try output.appendSlice(allocator, "\"");

            if (config.edge_palette != null and entry.color != 0) {
                try output.appendSlice(allocator, colors.escape.reset);
            }
            try output.append(allocator, '\n');
        }
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

/// Draw a pure-vertical direct edge between y_from and y_to at column x.
/// Draws in the range [min(y_from,y_to) .. max(y_from,y_to)), with an
/// arrow one step before the target (only when directed).
/// Reversed edges use dashed arrow characters (⇣/⇡).
fn drawDirectVertical(buffer: *Buffer2D, x: usize, y_from: usize, y_to: usize, color: u8, directed: bool, reversed: bool) void {
    if (y_from == y_to) return;
    const lo = @min(y_from, y_to);
    const hi = @max(y_from, y_to);
    const going_down = y_to > y_from;
    const arrow_y = if (going_down) hi - 1 else lo;
    const arrow_char: u21 = if (going_down)
        (if (reversed) CP_ARROW_DOWN_DASH else CP_ARROW_DOWN)
    else
        (if (reversed) CP_ARROW_UP_DASH else CP_ARROW_UP);

    var y = lo;
    while (y < hi) : (y += 1) {
        if (directed and y == arrow_y) {
            buffer.setWithColor(x, y, arrow_char, color);
        } else if (reversed) {
            buffer.setWithColor(x, y, CP_V_LINE_DASH, color);
        } else {
            const cur = buffer.get(x, y);
            buffer.setWithColor(x, y, mergeJunction(cur, true, true, false, false), color);
        }
    }
}

/// Draw a pure-horizontal direct edge between x_from and x_to at row y.
/// Reversed edges use dashed arrow and line characters (⇢/⇠, ┈).
fn drawDirectHorizontal(buffer: *Buffer2D, y: usize, x_from: usize, x_to: usize, color: u8, directed: bool, reversed: bool) void {
    if (x_from == x_to) return;
    const lo = @min(x_from, x_to);
    const hi = @max(x_from, x_to);
    const going_right = x_to > x_from;
    const arrow_x = if (going_right) hi - 1 else lo;
    const arrow_char: u21 = if (going_right)
        (if (reversed) CP_ARROW_RIGHT_DASH else CP_ARROW_RIGHT)
    else
        (if (reversed) CP_ARROW_LEFT_DASH else CP_ARROW_LEFT);

    var x = lo;
    while (x < hi) : (x += 1) {
        if (directed and x == arrow_x) {
            buffer.setWithColor(x, y, arrow_char, color);
        } else if (reversed) {
            buffer.setWithColor(x, y, CP_H_LINE_DASH, color);
        } else {
            const cur = buffer.get(x, y);
            buffer.setWithColor(x, y, mergeJunction(cur, false, false, true, true), color);
        }
    }
}

/// Draw a Manhattan Z-shaped route between (x0,y0) and (x1,y1).
/// Route: (x0,y0) → (x0,mid_y) → (x1,mid_y) → (x1,y1)
/// Uses box-drawing corners at the two bends for clean visual connections.
/// Reversed edges use dashed line and arrow characters.
fn drawDirectManhattan(buffer: *Buffer2D, x0: usize, y0: usize, x1: usize, y1: usize, color: u8, directed: bool, reversed: bool) void {
    const lo_y = @min(y0, y1);
    const hi_y = @max(y0, y1);
    const mid_y = lo_y + (hi_y - lo_y) / 2;

    // --- Segment 1: vertical at x0 between y0 and mid_y (exclusive of both) ---
    {
        const seg_lo = @min(y0, mid_y);
        const seg_hi = @max(y0, mid_y);
        if (seg_hi > seg_lo + 1) {
            var y = seg_lo + 1;
            while (y < seg_hi) : (y += 1) {
                if (reversed) {
                    buffer.setWithColor(x0, y, CP_V_LINE_DASH, color);
                } else {
                    const cur = buffer.get(x0, y);
                    buffer.setWithColor(x0, y, mergeJunction(cur, true, true, false, false), color);
                }
            }
        }
    }

    // --- Corner 1 at (x0, mid_y) ---
    {
        const cur = buffer.get(x0, mid_y);
        buffer.setWithColor(x0, mid_y, mergeJunction(cur, y0 < mid_y, // from_above
            y0 > mid_y, // to_below
            x1 > x0, // to_right
            x1 < x0), color); // to_left
    }

    // --- Segment 2: horizontal at mid_y (exclusive of x0 and x1) ---
    {
        const lo_x = @min(x0, x1);
        const hi_x = @max(x0, x1);
        if (hi_x > lo_x + 1) {
            var x = lo_x + 1;
            while (x < hi_x) : (x += 1) {
                if (reversed) {
                    buffer.setWithColor(x, mid_y, CP_H_LINE_DASH, color);
                } else {
                    const cur = buffer.get(x, mid_y);
                    buffer.setWithColor(x, mid_y, mergeJunction(cur, false, false, true, true), color);
                }
            }
        }
    }

    // --- Corner 2 at (x1, mid_y) ---
    {
        const cur = buffer.get(x1, mid_y);
        buffer.setWithColor(x1, mid_y, mergeJunction(cur, y1 < mid_y, // from_above
            y1 > mid_y, // to_below
            x0 > x1, // to_right (horizontal from x0 which is right of x1)
            x0 < x1), color); // to_left
    }

    // --- Segment 3: vertical at x1 between mid_y and y1 (exclusive of both) ---
    {
        const seg_lo = @min(mid_y, y1);
        const seg_hi = @max(mid_y, y1);
        if (seg_hi > seg_lo + 1) {
            var y = seg_lo + 1;
            while (y < seg_hi) : (y += 1) {
                if (reversed) {
                    buffer.setWithColor(x1, y, CP_V_LINE_DASH, color);
                } else {
                    const cur = buffer.get(x1, y);
                    buffer.setWithColor(x1, y, mergeJunction(cur, true, true, false, false), color);
                }
            }
        }
    }

    // --- Arrow ---
    if (directed) {
        if (reversed) {
            // Reversed: arrow at FROM end (y0) pointing upward
            // The first segment goes from y0 toward mid_y
            if (y0 != mid_y) {
                const going_up_s1 = y0 < mid_y;
                if (going_up_s1) {
                    // y0 is above mid_y, arrow at y0 pointing up
                    buffer.setWithColor(x0, y0, CP_ARROW_UP_DASH, color);
                } else {
                    buffer.setWithColor(x0, y0, CP_ARROW_DOWN_DASH, color);
                }
            } else {
                // y0 == mid_y: arrow on horizontal approach at FROM end
                const going_right = x1 > x0;
                if (going_right) {
                    buffer.setWithColor(x0, y0, CP_ARROW_LEFT_DASH, color);
                } else {
                    buffer.setWithColor(x0, y0, CP_ARROW_RIGHT_DASH, color);
                }
            }
        } else {
            // Normal: arrow one cell before target at TO end
            if (y1 != mid_y) {
                const going_down_s3 = y1 > mid_y;
                const arrow_y = if (going_down_s3) y1 - 1 else y1 + 1;
                const arrow_char: u21 = if (going_down_s3) CP_ARROW_DOWN else CP_ARROW_UP;
                buffer.setWithColor(x1, arrow_y, arrow_char, color);
            } else {
                // mid_y == y1: edge approaches horizontally — arrow on horizontal approach
                const going_right = x1 > x0;
                const arrow_x = if (going_right) x1 - 1 else x1 + 1;
                const arrow_char: u21 = if (going_right) CP_ARROW_RIGHT else CP_ARROW_LEFT;
                if (arrow_x < buffer.width) {
                    buffer.setWithColor(arrow_x, y1, arrow_char, color);
                }
            }
        }
    }
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
    if (current == CP_V_LINE or current == CP_V_LINE_DASH) {
        up = true;
        down = true;
    } else if (current == CP_ARROW_DOWN) {
        // Arrow indicates coming from above and pointing down
        up = true;
        down = true;
    } else if (current == CP_ARROW_DOWN_DASH or current == CP_ARROW_UP_DASH) {
        // Dashed arrows (reversed edges) also connect vertically
        up = true;
        down = true;
    } else if (current == CP_ARROW_RIGHT_DASH or current == CP_ARROW_LEFT_DASH) {
        // Dashed horizontal arrows connect horizontally
        left = true;
        right = true;
    } else if (current == CP_H_LINE or current == CP_H_LINE_DASH) {
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

/// Entry for the legend (labels that couldn't be placed inline).
const LegendEntry = struct {
    from_id: usize,
    to_id: usize,
    label: []const u8,
    color: u8,
};

/// Check whether a label can be placed without overlapping anything except spaces and vertical lines.
fn canPlaceLabel(buffer: *const Buffer2D, label: []const u8, x: usize, y: usize) bool {
    if (y >= buffer.height) return false;
    const label_width = label.len + 2; // +2 for surrounding quotes
    if (x + label_width > buffer.width) return false;
    for (0..label_width) |i| {
        const c = buffer.get(x + i, y);
        // Allow overwriting spaces and vertical lines (including dashed)
        if (c != ' ' and c != CP_V_LINE and c != CP_V_LINE_DASH) return false;
    }
    return true;
}

/// Paint a label as `"text"` at the given position with optional ANSI color.
fn paintLabel(buffer: *Buffer2D, label: []const u8, x: usize, y: usize, color: u8) void {
    var px = x;
    buffer.setWithColor(px, y, '"', color);
    px += 1;
    for (label) |ch| {
        buffer.setWithColor(px, y, ch, color);
        px += 1;
    }
    buffer.setWithColor(px, y, '"', color);
}

/// Info for a reversed (back) edge to be drawn with side routing.
const ReversedEdgeInfo = struct {
    edge_index: usize,
    source_right_x: usize,
    source_y: usize,
    target_right_x: usize,
    target_y: usize,
    channel_x: usize,
    color: u8,
    label: ?[]const u8,
    label_y: usize,
    from_id: usize,
    to_id: usize,
};

/// Paint a reversed (back) edge using side routing.
/// Routes the edge from the RIGHT side of the source node, through a dedicated
/// side channel column, to the RIGHT side of the target node.
///
/// Visual result:
///   [Target]┈┈┐     ← dashed horizontal from target right to channel
///      │      ┊     ← dashed vertical in channel
///      ↓      ┊
///    [Source]┈┈┘     ← dashed horizontal from source right to channel
///
/// The ⇡ arrow is placed at the top of the channel (near the semantic target).
fn paintReversedEdgeSide(buffer: *Buffer2D, info: *const ReversedEdgeInfo, color: u8) void {
    const ch_x = info.channel_x;

    // Determine top and bottom y (target is at top, source is at bottom)
    const top_y = info.target_y;
    const bot_y = info.source_y;

    if (top_y >= bot_y) return; // degenerate

    // 1. Horizontal dashed line from source node right to channel
    {
        const src_x = info.source_right_x;
        var x = src_x;
        while (x < ch_x) : (x += 1) {
            buffer.setWithColor(x, bot_y, CP_H_LINE_DASH, color);
        }
        // Corner at channel: connects from left and from above
        buffer.setWithColor(ch_x, bot_y, mergeJunction(' ', true, false, false, true), color);
    }

    // 2. Vertical dashed line in channel from bottom to top
    {
        var y = top_y + 1;
        while (y < bot_y) : (y += 1) {
            buffer.setWithColor(ch_x, y, CP_V_LINE_DASH, color);
        }
    }

    // 3. Horizontal dashed line from target node right to channel, with ⇡ arrow
    {
        const tgt_x = info.target_right_x;
        // Corner at channel: connects from below and from left
        buffer.setWithColor(ch_x, top_y, mergeJunction(' ', false, true, false, true), color);
        // Dashed horizontal from target right to channel
        var x = tgt_x;
        while (x < ch_x) : (x += 1) {
            if (x == tgt_x) {
                // Arrow at the node side pointing left (toward the target)
                buffer.setWithColor(x, top_y, CP_ARROW_LEFT_DASH, color);
            } else {
                buffer.setWithColor(x, top_y, CP_H_LINE_DASH, color);
            }
        }
    }

}

/// Paint an edge onto the buffer.
fn paintEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: u8) void {
    switch (edge.path) {
        .direct => {
            // Orthogonal (Manhattan) routing from (from_x, from_y) to (to_x, to_y).
            // For axis-aligned edges: pure vertical │ or horizontal ─.
            // For other edges: Z-shaped route through a midpoint using
            // box-drawing corners (└┐┌┘) that always connect cleanly.
            const x0 = edge.from_x;
            const y0 = edge.from_y;
            const x1 = edge.to_x;
            const y1 = edge.to_y;

            if (x0 == x1 and y0 == y1) return; // degenerate

            if (x0 == x1) {
                drawDirectVertical(buffer, x0, y0, y1, color, edge.directed, edge.reversed);
            } else if (y0 == y1) {
                drawDirectHorizontal(buffer, y0, x0, x1, color, edge.directed, edge.reversed);
            } else {
                drawDirectManhattan(buffer, x0, y0, x1, y1, color, edge.directed, edge.reversed);
            }
        },
        .corner => |corner| {
            const x1 = edge.from_x;
            const x2 = edge.to_x;
            const h_y = corner.horizontal_y;
            const min_x = @min(x1, x2);
            const max_x = @max(x1, x2);

            // For reversed edges: arrow at FROM end (top) pointing UP
            // For normal edges: arrow at TO end (bottom) pointing DOWN

            // Vertical from source to horizontal
            var y = edge.from_y;
            while (y < h_y) : (y += 1) {
                if (edge.reversed and edge.directed and y == edge.from_y) {
                    buffer.setWithColor(x1, y, CP_ARROW_UP_DASH, color);
                } else if (edge.reversed) {
                    buffer.setWithColor(x1, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(x1, y);
                    buffer.setWithColor(x1, y, mergeJunction(current, true, true, false, false), color);
                }
            }

            // Horizontal segment: merge with existing characters for proper crossings
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                if (x != x1 and x != x2) {
                    if (edge.reversed) {
                        buffer.setWithColor(x, h_y, CP_H_LINE_DASH, color);
                    } else {
                        const current = buffer.get(x, h_y);
                        buffer.setWithColor(x, h_y, mergeJunction(current, false, false, true, true), color);
                    }
                }
            }

            // Junction at source x (vertical from above meets horizontal)
            const current1 = buffer.get(x1, h_y);
            buffer.setWithColor(x1, h_y, mergeJunction(current1, true, false, x1 < x2, x1 > x2), color);

            // Corner at target x (horizontal meets vertical going down)
            const current2 = buffer.get(x2, h_y);
            buffer.setWithColor(x2, h_y, mergeJunction(current2, false, true, x1 > x2, x1 < x2), color);

            // Vertical from horizontal to target
            y = h_y + 1;
            while (y < edge.to_y) : (y += 1) {
                if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
                    buffer.setWithColor(x2, y, CP_ARROW_DOWN, color);
                } else if (edge.reversed) {
                    buffer.setWithColor(x2, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(x2, y);
                    buffer.setWithColor(x2, y, mergeJunction(current, true, true, false, false), color);
                }
            }
        },
        .side_channel => |sc| {
            const x1 = edge.from_x;
            const x2 = edge.to_x;
            const ch_x = sc.channel_x;

            // For reversed edges: arrow at FROM end (top) pointing UP, dashed body
            // For normal edges: arrow at TO end (bottom) pointing DOWN

            // Vertical from source to start_y
            var y = edge.from_y + 1;
            const first_vert_start = edge.from_y + 1;
            while (y < sc.start_y) : (y += 1) {
                if (edge.reversed and edge.directed and y == first_vert_start) {
                    buffer.setWithColor(x1, y, CP_ARROW_UP_DASH, color);
                } else if (edge.reversed) {
                    buffer.setWithColor(x1, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(x1, y);
                    buffer.setWithColor(x1, y, mergeJunction(current, true, true, false, false), color);
                }
            }

            // Horizontal at start_y
            const min_x1 = @min(x1, ch_x);
            const max_x1 = @max(x1, ch_x);
            var x = min_x1;
            while (x <= max_x1) : (x += 1) {
                if (edge.reversed) {
                    buffer.setWithColor(x, sc.start_y, CP_H_LINE_DASH, color);
                } else {
                    const current = buffer.get(x, sc.start_y);
                    buffer.setWithColor(x, sc.start_y, mergeJunction(current, false, false, true, true), color);
                }
            }

            // Vertical in channel
            y = sc.start_y + 1;
            while (y < sc.end_y) : (y += 1) {
                if (edge.reversed) {
                    buffer.setWithColor(ch_x, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(ch_x, y);
                    buffer.setWithColor(ch_x, y, mergeJunction(current, true, true, false, false), color);
                }
            }

            // Horizontal at end_y
            const min_x2 = @min(ch_x, x2);
            const max_x2 = @max(ch_x, x2);
            x = min_x2;
            while (x <= max_x2) : (x += 1) {
                if (edge.reversed) {
                    buffer.setWithColor(x, sc.end_y, CP_H_LINE_DASH, color);
                } else {
                    const current = buffer.get(x, sc.end_y);
                    buffer.setWithColor(x, sc.end_y, mergeJunction(current, false, false, true, true), color);
                }
            }

            // Vertical from end_y to target
            y = sc.end_y + 1;
            while (y < edge.to_y) : (y += 1) {
                if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
                    buffer.setWithColor(x2, y, CP_ARROW_DOWN, color);
                } else if (edge.reversed) {
                    buffer.setWithColor(x2, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(x2, y);
                    buffer.setWithColor(x2, y, mergeJunction(current, true, true, false, false), color);
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
                if (edge.reversed and edge.directed and y == edge.from_y) {
                    buffer.setWithColor(x1, y, CP_ARROW_UP_DASH, color);
                } else if (edge.reversed) {
                    buffer.setWithColor(x1, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(x1, y);
                    buffer.setWithColor(x1, y, mergeJunction(current, true, true, false, false), color);
                }
            }

            // Horizontal segment (only fill spaces)
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                if (x != x1 and x != x2) {
                    const current = buffer.get(x, h_y);
                    if (current == ' ') {
                        if (edge.reversed) {
                            buffer.setWithColor(x, h_y, CP_H_LINE_DASH, color);
                        } else {
                            buffer.setWithColor(x, h_y, CP_H_LINE, color);
                        }
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
                if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
                    buffer.setWithColor(x2, y, CP_ARROW_DOWN, color);
                } else if (edge.reversed) {
                    buffer.setWithColor(x2, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(x2, y);
                    buffer.setWithColor(x2, y, mergeJunction(current, true, true, false, false), color);
                }
            }
        },
        .spline => {
            // For Unicode rendering, approximate spline as direct line
            // (Unicode can't render curves, so we fall back to straight connection)
            const x = edge.from_x;
            var y = edge.from_y;
            while (y < edge.to_y) : (y += 1) {
                if (edge.reversed and edge.directed and y == edge.from_y) {
                    // Reversed: arrow at FROM end pointing UP
                    buffer.setWithColor(x, y, CP_ARROW_UP_DASH, color);
                } else if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
                    // Normal: arrow at TO end pointing DOWN
                    buffer.setWithColor(x, y, CP_ARROW_DOWN, color);
                } else if (edge.reversed) {
                    buffer.setWithColor(x, y, CP_V_LINE_DASH, color);
                } else {
                    const current = buffer.get(x, y);
                    buffer.setWithColor(x, y, mergeJunction(current, true, true, false, false), color);
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
