//! Barnes-Hut Quadtree for O(N log N) Force Approximation
//!
//! Spatial index that groups distant nodes into aggregate bodies,
//! allowing repulsive force computation in O(N log N) instead of O(N²).
//!
//! ## Standalone Usage
//!
//! ```zig
//! const qt = @import("zigraph").fdg.quadtree;
//! var tree = try qt.Quadtree.build(positions, allocator);
//! defer tree.deinit();
//! const force = tree.computeForce(node_pos, theta);
//! ```
//!
//! ## Algorithm
//!
//! For each node, walk the tree from root. At each cell:
//! - If cell_size / distance < θ: treat cell as single body (O(1) contribution)
//! - Otherwise: recurse into children
//!
//! θ = 0.0 → exact (O(N²)), θ = 1.0 → aggressive approximation, θ = 0.8 → default

const std = @import("std");
const Allocator = std.mem.Allocator;
const fp = @import("fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;

/// Maximum tree depth to prevent unbounded recursion from coincident points.
const MAX_DEPTH: u32 = 24;

/// A node in the quadtree. Can be empty, a leaf (single body), or internal (4 children).
const QuadNode = struct {
    /// Center of mass of all bodies in this cell (Q16.16).
    center_of_mass: Vec2 = Vec2{},
    /// Total mass (number of bodies) in this cell.
    mass: i32 = 0,

    /// Cell bounds.
    cx: FP = fp.ZERO, // center x
    cy: FP = fp.ZERO, // center y
    half_size: FP = fp.ZERO, // half the side length

    /// Children indices (0 = no child). Quadrants: NW, NE, SW, SE.
    children: [4]u32 = .{ 0, 0, 0, 0 },

    /// Whether this is a leaf containing exactly one body.
    is_leaf: bool = false,
    /// Body position (only valid if is_leaf).
    body_pos: Vec2 = Vec2{},
};

/// Barnes-Hut Quadtree for spatial force approximation.
pub const Quadtree = struct {
    nodes: std.ArrayListUnmanaged(QuadNode) = .{},
    allocator: Allocator,

    /// Build a quadtree from a set of positions.
    ///
    /// Positions are in Q16.16 fixed-point. The tree covers the
    /// bounding box of all positions with some margin.
    pub fn build(positions: []const Vec2, allocator: Allocator) !Quadtree {
        var self = Quadtree{
            .allocator = allocator,
        };
        errdefer self.deinit();

        if (positions.len == 0) return self;

        // Compute bounding box
        var min_x: FP = fp.MAX;
        var min_y: FP = fp.MAX;
        var max_x: FP = fp.MIN;
        var max_y: FP = fp.MIN;

        for (positions) |pos| {
            min_x = fp.min(min_x, pos.x);
            min_y = fp.min(min_y, pos.y);
            max_x = fp.max(max_x, pos.x);
            max_y = fp.max(max_y, pos.y);
        }

        // Make it square with some margin
        const dx = fp.sub(max_x, min_x);
        const dy = fp.sub(max_y, min_y);
        const size = fp.max(fp.max(dx, dy), fp.fromInt(1)); // At least 1.0
        const margin = fp.div(size, fp.fromInt(10));
        const total_size = fp.add(size, fp.mul(margin, fp.fromInt(2)));
        const half = fp.div(total_size, fp.fromInt(2));

        const cx = fp.div(fp.add(min_x, max_x), fp.fromInt(2));
        const cy = fp.div(fp.add(min_y, max_y), fp.fromInt(2));

        // Allocate root node
        try self.nodes.append(self.allocator, .{
            .cx = cx,
            .cy = cy,
            .half_size = half,
        });

        // Insert all bodies
        for (positions) |pos| {
            try self.insert(0, pos, 0);
        }

        return self;
    }

    pub fn deinit(self: *Quadtree) void {
        self.nodes.deinit(self.allocator);
    }

    /// Compute the approximate repulsive force on a body at `pos`.
    ///
    /// `k_squared` is the repulsion constant (k² from FR formula) in Q16.16.
    /// `theta` is the Barnes-Hut accuracy parameter in Q16.16 (0.8 = 52428).
    ///
    /// Returns the total force vector (Q16.16).
    pub fn computeForce(self: *const Quadtree, pos: Vec2, k_squared: FP, theta: FP) Vec2 {
        if (self.nodes.items.len == 0) return Vec2{};
        return self.walkForce(0, pos, k_squared, theta);
    }

    // ========================================================================
    // Internal
    // ========================================================================

    fn insert(self: *Quadtree, node_idx: u32, pos: Vec2, depth: u32) !void {
        if (depth >= MAX_DEPTH) {
            // At max depth, just accumulate mass
            self.updateMass(node_idx, pos);
            return;
        }

        var node = &self.nodes.items[node_idx];

        if (node.mass == 0) {
            // Empty cell → make it a leaf
            node.is_leaf = true;
            node.body_pos = pos;
            node.center_of_mass = pos;
            node.mass = 1;
            return;
        }

        if (node.is_leaf) {
            // Leaf with existing body → subdivide
            const existing_pos = node.body_pos;
            node.is_leaf = false;

            // Re-insert the existing body into a child
            const eq = self.quadrant(node_idx, existing_pos);
            try self.ensureChild(node_idx, eq);
            // Re-read node pointer after potential reallocation
            try self.insert(self.nodes.items[node_idx].children[eq], existing_pos, depth + 1);

            // Insert the new body into a child
            const nq = self.quadrant(node_idx, pos);
            try self.ensureChild(node_idx, nq);
            try self.insert(self.nodes.items[node_idx].children[nq], pos, depth + 1);

            // Update center of mass
            self.updateMass(node_idx, pos);
        } else {
            // Internal node → insert into appropriate child
            const q = self.quadrant(node_idx, pos);
            try self.ensureChild(node_idx, q);
            try self.insert(self.nodes.items[node_idx].children[q], pos, depth + 1);
            self.updateMass(node_idx, pos);
        }
    }

    fn updateMass(self: *Quadtree, node_idx: u32, pos: Vec2) void {
        var node = &self.nodes.items[node_idx];
        const old_mass = node.mass;
        const new_mass = old_mass + 1;

        // Weighted average for center of mass:
        // com = (com * old_mass + pos) / new_mass
        if (new_mass > 0) {
            const old_weight = fp.fromInt(old_mass);
            const new_weight = fp.fromInt(new_mass);
            node.center_of_mass.x = fp.div(
                fp.add(fp.mul(node.center_of_mass.x, old_weight), pos.x),
                new_weight,
            );
            node.center_of_mass.y = fp.div(
                fp.add(fp.mul(node.center_of_mass.y, old_weight), pos.y),
                new_weight,
            );
        }
        node.mass = new_mass;
    }

    /// Determine which quadrant a position falls in relative to a node's center.
    /// Returns 0=NW, 1=NE, 2=SW, 3=SE.
    fn quadrant(self: *const Quadtree, node_idx: u32, pos: Vec2) u2 {
        const node = &self.nodes.items[node_idx];
        const east: u2 = if (pos.x >= node.cx) 1 else 0;
        const south: u2 = if (pos.y >= node.cy) 2 else 0;
        return east | south;
    }

    fn ensureChild(self: *Quadtree, node_idx: u32, q: u2) !void {
        if (self.nodes.items[node_idx].children[q] != 0) return;

        const parent = self.nodes.items[node_idx];
        const quarter = fp.div(parent.half_size, fp.fromInt(2));

        const dx: FP = if (q & 1 != 0) quarter else fp.neg(quarter);
        const dy: FP = if (q & 2 != 0) quarter else fp.neg(quarter);

        try self.nodes.append(self.allocator, .{
            .cx = fp.add(parent.cx, dx),
            .cy = fp.add(parent.cy, dy),
            .half_size = quarter,
        });

        self.nodes.items[node_idx].children[q] = @intCast(self.nodes.items.len - 1);
    }

    fn walkForce(self: *const Quadtree, node_idx: u32, pos: Vec2, k_squared: FP, theta: FP) Vec2 {
        const node = &self.nodes.items[node_idx];
        if (node.mass == 0) return Vec2{};

        const delta = pos.subVec(node.center_of_mass);
        const d = delta.length();

        // Avoid self-interaction (distance ≈ 0 means same node)
        if (d < 2) return Vec2{};

        if (node.is_leaf) {
            // Single body — compute exact force
            // f_rep = k² / d, direction = delta / d (away from other body)
            const force_mag = fp.div(k_squared, d);
            return delta.normalizeScaled(force_mag);
        }

        // Barnes-Hut check: if cell_size / d < θ, treat as single body
        // Equivalent: cell_size < θ * d (all in Q16.16)
        const cell_size = fp.mul(node.half_size, fp.fromInt(2));
        if (fp.mul(cell_size, fp.fromInt(1)) < fp.mul(theta, d)) {
            // Far enough — approximate
            // Force magnitude = k² * mass / d
            const force_mag = fp.div(fp.mul(k_squared, fp.fromInt(node.mass)), d);
            return delta.normalizeScaled(force_mag);
        }

        // Too close — recurse into children
        var force = Vec2{};
        for (node.children) |child_idx| {
            if (child_idx != 0) {
                const child_force = self.walkForce(child_idx, pos, k_squared, theta);
                force = force.addVec(child_force);
            }
        }
        return force;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Quadtree: build empty" {
    const allocator = std.testing.allocator;
    var qt = try Quadtree.build(&.{}, allocator);
    defer qt.deinit();
    try std.testing.expectEqual(@as(usize, 0), qt.nodes.items.len);
}

test "Quadtree: build single node" {
    const allocator = std.testing.allocator;
    const positions = [_]Vec2{Vec2.init(fp.fromInt(5), fp.fromInt(5))};
    var qt = try Quadtree.build(&positions, allocator);
    defer qt.deinit();
    try std.testing.expect(qt.nodes.items.len >= 1);
    try std.testing.expectEqual(@as(i32, 1), qt.nodes.items[0].mass);
}

test "Quadtree: build multiple nodes" {
    const allocator = std.testing.allocator;
    const positions = [_]Vec2{
        Vec2.init(fp.fromInt(0), fp.fromInt(0)),
        Vec2.init(fp.fromInt(10), fp.fromInt(0)),
        Vec2.init(fp.fromInt(0), fp.fromInt(10)),
        Vec2.init(fp.fromInt(10), fp.fromInt(10)),
    };
    var qt = try Quadtree.build(&positions, allocator);
    defer qt.deinit();
    try std.testing.expectEqual(@as(i32, 4), qt.nodes.items[0].mass);
}

test "Quadtree: force pushes away" {
    const allocator = std.testing.allocator;
    const positions = [_]Vec2{
        Vec2.init(fp.fromInt(0), fp.fromInt(0)),
        Vec2.init(fp.fromInt(10), fp.fromInt(0)),
    };
    var qt = try Quadtree.build(&positions, allocator);
    defer qt.deinit();

    const k_squared = fp.fromInt(100);
    const theta = fp.fromFloat(0.0); // Exact — no approximation

    // Force on node at (0,0) — should push it left (away from node at (10,0))
    const force = qt.computeForce(positions[0], k_squared, theta);
    try std.testing.expect(force.x < 0); // Pushed left
}

test "Quadtree: force is deterministic" {
    const allocator = std.testing.allocator;
    const positions = [_]Vec2{
        Vec2.init(fp.fromInt(0), fp.fromInt(0)),
        Vec2.init(fp.fromInt(5), fp.fromInt(3)),
        Vec2.init(fp.fromInt(-2), fp.fromInt(8)),
        Vec2.init(fp.fromInt(7), fp.fromInt(-1)),
    };

    var qt1 = try Quadtree.build(&positions, allocator);
    defer qt1.deinit();
    var qt2 = try Quadtree.build(&positions, allocator);
    defer qt2.deinit();

    const k_sq = fp.fromInt(50);
    const theta = fp.fromFloat(0.8);

    for (positions) |pos| {
        const f1 = qt1.computeForce(pos, k_sq, theta);
        const f2 = qt2.computeForce(pos, k_sq, theta);
        try std.testing.expectEqual(f1.x, f2.x);
        try std.testing.expectEqual(f1.y, f2.y);
    }
}
