//! Comptime Graph Builder
//!
//! Build and render graphs entirely at compile time.
//! The output is embedded as a string literal in the binary.
//!
//! ## Use Cases
//!
//! - Embedded systems: no runtime allocation needed
//! - Documentation: static diagrams with zero runtime cost
//! - CLI tools: pre-rendered help graphs
//!
//! ## Example
//!
//! ```zig
//! const diagram = comptime blk: {
//!     var builder = ComptimeGraph.init();
//!     builder.edge(1, 2);
//!     builder.edge(2, 3);
//!     break :blk builder.render();
//! };
//!
//! // diagram is now a comptime []const u8 embedded in binary
//! pub fn main() void {
//!     std.debug.print("{s}", .{diagram});
//! }
//! ```
//!
//! ## Limitations
//!
//! - Maximum 64 nodes (can be increased)
//! - Maximum 256 edges
//! - Fixed-size internal buffers
//! - Simple positioning only (no Brandes-Köpf at comptime)

const std = @import("std");

/// Maximum nodes supported in comptime graph
pub const MAX_NODES = 64;
/// Maximum edges supported
pub const MAX_EDGES = 256;
/// Maximum rendered output size
pub const MAX_OUTPUT = 16384;

/// A graph that can be built and rendered entirely at comptime.
pub const ComptimeGraph = struct {
    // Node data: id -> (exists, label_start, label_len)
    node_exists: [MAX_NODES]bool = [_]bool{false} ** MAX_NODES,
    node_labels: [MAX_NODES * 8]u8 = [_]u8{0} ** (MAX_NODES * 8),
    node_label_lens: [MAX_NODES]u8 = [_]u8{0} ** MAX_NODES,

    // Edges
    edges: [MAX_EDGES][2]u8 = [_][2]u8{.{ 0, 0 }} ** MAX_EDGES,
    edge_count: usize = 0,

    // Adjacency (for children lookup)
    children: [MAX_NODES][MAX_NODES]u8 = [_][MAX_NODES]u8{[_]u8{0} ** MAX_NODES} ** MAX_NODES,
    child_counts: [MAX_NODES]u8 = [_]u8{0} ** MAX_NODES,
    parent_counts: [MAX_NODES]u8 = [_]u8{0} ** MAX_NODES,

    node_count: usize = 0,
    max_id: usize = 0,

    const Self = @This();

    /// Initialize an empty comptime graph.
    pub fn init() Self {
        return .{};
    }

    /// Add a node with a numeric label (id as string).
    pub fn node(self: *Self, id: usize) void {
        if (id >= MAX_NODES) return;
        if (self.node_exists[id]) return;

        self.node_exists[id] = true;
        self.node_count += 1;
        if (id > self.max_id) self.max_id = id;

        // Generate label from id
        var buf: [8]u8 = undefined;
        const label = intToStr(id, &buf);
        const start = id * 8;
        for (label, 0..) |c, i| {
            self.node_labels[start + i] = c;
        }
        self.node_label_lens[id] = @intCast(label.len);
    }

    /// Add a node with a custom label.
    pub fn nodeLabeled(self: *Self, id: usize, label: []const u8) void {
        if (id >= MAX_NODES) return;
        if (self.node_exists[id]) return;

        self.node_exists[id] = true;
        self.node_count += 1;
        if (id > self.max_id) self.max_id = id;

        const start = id * 8;
        const len = @min(label.len, 8);
        for (0..len) |i| {
            self.node_labels[start + i] = label[i];
        }
        self.node_label_lens[id] = @intCast(len);
    }

    /// Add an edge (auto-creates nodes if needed).
    pub fn edge(self: *Self, from: usize, to: usize) void {
        if (from >= MAX_NODES or to >= MAX_NODES) return;
        if (self.edge_count >= MAX_EDGES) return;

        // Auto-create nodes
        if (!self.node_exists[from]) self.node(from);
        if (!self.node_exists[to]) self.node(to);

        self.edges[self.edge_count] = .{ @intCast(from), @intCast(to) };
        self.edge_count += 1;

        // Update adjacency
        const c_count = self.child_counts[from];
        self.children[from][c_count] = @intCast(to);
        self.child_counts[from] += 1;
        self.parent_counts[to] += 1;
    }

    /// Render the graph to a string at comptime.
    /// Returns a comptime-known string slice.
    pub fn render(comptime self: *const Self) *const [renderLen(self)]u8 {
        comptime {
            const result = doRender(self);
            const trimmed: [result.len]u8 = result.output[0..result.len].*;
            return &trimmed;
        }
    }

    fn renderLen(comptime self: *const Self) usize {
        @setEvalBranchQuota(100_000);
        return doRender(self).len;
    }

    const RenderResult = struct {
        output: [MAX_OUTPUT]u8,
        len: usize,
    };

    fn doRender(self: *const Self) RenderResult {
        @setEvalBranchQuota(100_000);
        // Phase 1: Layering (longest path from roots)
        var levels: [MAX_NODES]u8 = [_]u8{0} ** MAX_NODES;
        var max_level: usize = 0;

        // Fixed-point iteration
        var changed = true;
        var iterations: usize = 0;
        while (changed and iterations < 100) : (iterations += 1) {
            changed = false;
            for (0..self.edge_count) |e| {
                const from = self.edges[e][0];
                const to = self.edges[e][1];
                const new_level = levels[from] + 1;
                if (new_level > levels[to]) {
                    levels[to] = new_level;
                    changed = true;
                    if (new_level > max_level) max_level = new_level;
                }
            }
        }

        // Phase 2: Organize nodes by level
        var level_nodes: [MAX_NODES][MAX_NODES]u8 = [_][MAX_NODES]u8{[_]u8{0} ** MAX_NODES} ** MAX_NODES;
        var level_counts: [MAX_NODES]u8 = [_]u8{0} ** MAX_NODES;

        for (0..MAX_NODES) |id| {
            if (self.node_exists[id]) {
                const lvl = levels[id];
                level_nodes[lvl][level_counts[lvl]] = @intCast(id);
                level_counts[lvl] += 1;
            }
        }

        // Phase 3: Compute positions
        // Simple: center each level, nodes spaced by max_label_width + 4
        const spacing = 10; // [label] + gaps
        var positions: [MAX_NODES]u8 = [_]u8{0} ** MAX_NODES;

        for (0..max_level + 1) |lvl| {
            const count = level_counts[lvl];
            const total_width = count * spacing;
            const start_x: usize = if (total_width > 0) (80 - total_width) / 2 else 40;
            for (0..count) |i| {
                const node_id = level_nodes[lvl][i];
                positions[node_id] = @intCast(start_x + i * spacing);
            }
        }

        // Phase 4: Render to fixed buffer
        const height = (max_level + 1) * 3; // 3 rows per level (node, edge, gap)
        const width = 80;
        var buffer: [MAX_OUTPUT]u8 = [_]u8{' '} ** MAX_OUTPUT;
        var output_len: usize = 0;

        // Render each level
        for (0..max_level + 1) |lvl| {
            const y = lvl * 3;
            const count = level_counts[lvl];

            // Render nodes on this level
            for (0..count) |i| {
                const node_id = level_nodes[lvl][i];
                const x = positions[node_id];
                const label_start = node_id * 8;
                const label_len = self.node_label_lens[node_id];

                // Write [label]
                const row_start = y * width;
                if (row_start + x < MAX_OUTPUT) {
                    buffer[row_start + x] = '[';
                    for (0..label_len) |j| {
                        if (row_start + x + 1 + j < MAX_OUTPUT) {
                            buffer[row_start + x + 1 + j] = self.node_labels[label_start + j];
                        }
                    }
                    if (row_start + x + 1 + label_len < MAX_OUTPUT) {
                        buffer[row_start + x + 1 + label_len] = ']';
                    }
                }
            }

            // Render edges to next level
            if (lvl < max_level) {
                const edge_y = y + 1;
                const arrow_y = y + 2;
                for (0..self.edge_count) |e| {
                    const from = self.edges[e][0];
                    const to = self.edges[e][1];
                    if (levels[from] == lvl and levels[to] == lvl + 1) {
                        const from_center: usize = positions[from] + 1 + self.node_label_lens[from] / 2;
                        const to_center: usize = positions[to] + 1 + self.node_label_lens[to] / 2;
                        const edge_row = edge_y * width;
                        const arrow_row = arrow_y * width;

                        if (from_center == to_center) {
                            // Straight vertical edge
                            if (edge_row + from_center < MAX_OUTPUT) {
                                buffer[edge_row + from_center] = '|';
                            }
                            if (arrow_row + to_center < MAX_OUTPUT) {
                                buffer[arrow_row + to_center] = 'v';
                            }
                        } else {
                            // Manhattan routing: horizontal line on edge row, arrow at target
                            const min_x = @min(from_center, to_center);
                            const max_x = @max(from_center, to_center);
                            for (min_x..max_x + 1) |x| {
                                if (edge_row + x < MAX_OUTPUT) {
                                    if (x == from_center or x == to_center) {
                                        buffer[edge_row + x] = '+';
                                    } else {
                                        buffer[edge_row + x] = '-';
                                    }
                                }
                            }
                            if (arrow_row + to_center < MAX_OUTPUT) {
                                buffer[arrow_row + to_center] = 'v';
                            }
                        }
                    }
                }
            }
        }

        // Convert to output with newlines, trimming trailing spaces
        for (0..height) |row| {
            const row_start = row * width;
            var end = width;
            while (end > 0 and buffer[row_start + end - 1] == ' ') {
                end -= 1;
            }
            for (row_start..row_start + end) |i| {
                buffer[output_len] = buffer[i];
                output_len += 1;
            }
            buffer[output_len] = '\n';
            output_len += 1;
        }

        return .{ .output = buffer, .len = output_len };
    }

    fn intToStr(val: usize, buf: []u8) []const u8 {
        if (val == 0) {
            buf[0] = '0';
            return buf[0..1];
        }
        var v = val;
        var i: usize = 0;
        while (v > 0 and i < buf.len) : (i += 1) {
            buf[i] = @intCast('0' + (v % 10));
            v /= 10;
        }
        // Reverse
        var j: usize = 0;
        while (j < i / 2) : (j += 1) {
            const tmp = buf[j];
            buf[j] = buf[i - 1 - j];
            buf[i - 1 - j] = tmp;
        }
        return buf[0..i];
    }
};

// ============================================================================
// Tests
// ============================================================================

test "comptime graph: simple chain" {
    const diagram = comptime blk: {
        var g = ComptimeGraph.init();
        g.edge(1, 2);
        g.edge(2, 3);
        break :blk g.render();
    };

    // Should compile and have content
    try std.testing.expect(diagram.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "[2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "[3]") != null);
}

test "comptime graph: labeled nodes" {
    const diagram = comptime blk: {
        var g = ComptimeGraph.init();
        g.nodeLabeled(1, "Start");
        g.nodeLabeled(2, "End");
        g.edge(1, 2);
        break :blk g.render();
    };

    try std.testing.expect(std.mem.indexOf(u8, diagram, "[Start]") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "[End]") != null);
}

test "comptime graph: diamond" {
    const diagram = comptime blk: {
        var g = ComptimeGraph.init();
        g.edge(1, 2);
        g.edge(1, 3);
        g.edge(2, 4);
        g.edge(3, 4);
        break :blk g.render();
    };

    try std.testing.expect(diagram.len > 0);
    // All 4 nodes should be present
    try std.testing.expect(std.mem.indexOf(u8, diagram, "[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagram, "[4]") != null);
}
