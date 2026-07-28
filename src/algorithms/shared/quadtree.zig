//! Barnes-Hut Quadtree for O(N log N) Force Approximation
//!
//! Spatial index that groups distant nodes into aggregate bodies,
//! allowing repulsive force computation in O(N log N) instead of O(N²).
//!
//! ## Standalone Usage
//!
//! ```zig
//! const qt = @import("zigraph").fdg.quadtree;
//! var tree = try qt.Quadtree.build(xs, ys, allocator); // SoA Q16.16 arrays
//! defer tree.deinit();
//! const force = tree.computeForce(.{ .x = xs[i], .y = ys[i] }, k_squared, theta);
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
    nodes: std.ArrayListUnmanaged(QuadNode) = .empty,
    allocator: Allocator,

    /// Build a quadtree from SoA position arrays.
    ///
    /// Positions are in Q16.16 fixed-point. The tree covers the
    /// bounding box of all positions with some margin.
    /// Construction is a serial per-iteration phase; once built, the tree
    /// is frozen and `computeForce` reads are parallel-safe.
    pub fn build(xs: []const FP, ys: []const FP, allocator: Allocator) !Quadtree {
        std.debug.assert(xs.len == ys.len);
        var self = Quadtree{
            .allocator = allocator,
        };
        errdefer self.deinit();

        if (xs.len == 0) return self;

        // Compute bounding box
        var min_x: FP = fp.MAX;
        var min_y: FP = fp.MAX;
        var max_x: FP = fp.MIN;
        var max_y: FP = fp.MIN;

        for (xs, ys) |x, y| {
            min_x = fp.min(min_x, x);
            min_y = fp.min(min_y, y);
            max_x = fp.max(max_x, x);
            max_y = fp.max(max_y, y);
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
        for (xs, ys) |x, y| {
            try self.insert(0, Vec2{ .x = x, .y = y }, 0);
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

        // Weighted average for center of mass, in wide raw arithmetic:
        //   com = (com_raw × old_mass + pos_raw) / new_mass
        // The mass stays a plain integer — converting it to Q16.16 and
        // using fp.mul saturated the product for coordinate×mass beyond
        // ~32767 (e.g. coordinate 100 × mass 400), silently corrupting
        // every large cell's center of mass. i64 is safe: |raw| ≤ 2³¹ and
        // mass is i32 (≤ 2³¹−1, far beyond any layout workload), so the
        // product stays below 2⁶².
        node.center_of_mass.x = @intCast(@divTrunc(
            @as(i64, node.center_of_mass.x) * old_mass + pos.x,
            @as(i64, new_mass),
        ));
        node.center_of_mass.y = @intCast(@divTrunc(
            @as(i64, node.center_of_mass.y) * old_mass + pos.y,
            @as(i64, new_mass),
        ));
        node.mass = new_mass;
    }

    /// (k² × mass) / d in Q16.16 with wide intermediates. The former
    /// `fp.mul(k², fp.fromInt(mass))` saturated once k²×mass exceeded the
    /// Q16.16 integer range (mass > 81 at the default k² = 400), clamping
    /// every large cell's aggregate force. Mass stays a plain integer;
    /// saturation happens only after the distance division.
    ///
    /// Uses i64 quotient/remainder decomposition instead of a 128-bit
    /// division (which lowers to an expensive software helper on WASM and
    /// embedded targets): with a = q·d + r, (a·2¹⁶)/d == q·2¹⁶ + (r·2¹⁶)/d
    /// exactly under truncating division — for either sign of `a`, since
    /// @divTrunc/@rem are sign-symmetric. Sign-aware and saturating at both
    /// bounds: `k_squared` may be negative (a negative
    /// `Config.repulsion_strength` inverts repulsion into attraction, and
    /// has always been accepted by the pairwise kernel — the two variants
    /// must agree on the config domain). mass > 0 and d ≥ 2 are structural
    /// invariants from the caller.
    fn mulMassDiv(k_squared: FP, mass: i32, d: FP) FP {
        std.debug.assert(mass > 0 and d > 0);
        const a: i64 = @as(i64, k_squared) * mass;
        const q = @divTrunc(a, d);
        // If the scaled quotient alone leaves Q16.16, saturate (both signs).
        if (q > (std.math.maxInt(i32) >> fp.SHIFT)) return fp.MAX;
        if (q < (std.math.minInt(i32) >> fp.SHIFT)) return fp.MIN;
        // |q| ≤ 32768 → q·2¹⁶ fits i64; |r| < d keeps r·2¹⁶ within i64 and
        // the remainder term within (−2¹⁶, 2¹⁶).
        const r = @rem(a, d);
        const result = q * (1 << fp.SHIFT) + @divTrunc(r * (1 << fp.SHIFT), @as(i64, d));
        if (result > std.math.maxInt(i32)) return fp.MAX;
        if (result < std.math.minInt(i32)) return fp.MIN;
        return @intCast(result);
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

        // A leaf, or a childless max-depth accumulator (coincident bodies
        // past MAX_DEPTH collect into a node that is neither leaf nor has
        // children — before this check, such clusters were invisible to
        // any walk that recursed into them, e.g. at theta = 0). Both are
        // point masses: f_rep = k² × mass / d — bit-identical to the old
        // single-body k²/d when mass == 1.
        const childless = node.children[0] == 0 and node.children[1] == 0 and
            node.children[2] == 0 and node.children[3] == 0;
        if (node.is_leaf or childless) {
            const force_mag = mulMassDiv(k_squared, node.mass, d);
            return delta.normalizeScaledWithLength(force_mag, d);
        }

        // Barnes-Hut check: if cell_size / d < θ, treat as single body
        // (rearranged: cell_size < θ × d, all in Q16.16). Additionally the
        // target must lie OUTSIDE the cell's bounds (GADGET-style geometric
        // safety test): the d < 2 guard only catches coincidence with the
        // center of mass, so an unbalanced cell *containing* the target
        // could otherwise be accepted — folding the target's own mass into
        // its repulsion. Inside → always recurse.
        const cell_size = fp.mul(node.half_size, fp.fromInt(2));
        const inside = pos.x >= fp.sub(node.cx, node.half_size) and
            pos.x <= fp.add(node.cx, node.half_size) and
            pos.y >= fp.sub(node.cy, node.half_size) and
            pos.y <= fp.add(node.cy, node.half_size);
        if (!inside and cell_size < fp.mul(theta, d)) {
            // Far enough — approximate
            // Force magnitude = k² * mass / d (wide mass arithmetic)
            const force_mag = mulMassDiv(k_squared, node.mass, d);
            return delta.normalizeScaledWithLength(force_mag, d);
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
    var qt = try Quadtree.build(&.{}, &.{}, allocator);
    defer qt.deinit();
    try std.testing.expectEqual(@as(usize, 0), qt.nodes.items.len);
}

test "Quadtree: build single node" {
    const allocator = std.testing.allocator;
    const xs = [_]FP{fp.fromInt(5)};
    const ys = [_]FP{fp.fromInt(5)};
    var qt = try Quadtree.build(&xs, &ys, allocator);
    defer qt.deinit();
    try std.testing.expect(qt.nodes.items.len >= 1);
    try std.testing.expectEqual(@as(i32, 1), qt.nodes.items[0].mass);
}

test "Quadtree: build multiple nodes" {
    const allocator = std.testing.allocator;
    const xs = [_]FP{ fp.fromInt(0), fp.fromInt(10), fp.fromInt(0), fp.fromInt(10) };
    const ys = [_]FP{ fp.fromInt(0), fp.fromInt(0), fp.fromInt(10), fp.fromInt(10) };
    var qt = try Quadtree.build(&xs, &ys, allocator);
    defer qt.deinit();
    try std.testing.expectEqual(@as(i32, 4), qt.nodes.items[0].mass);
}

test "Quadtree: force pushes away" {
    const allocator = std.testing.allocator;
    const xs = [_]FP{ fp.fromInt(0), fp.fromInt(10) };
    const ys = [_]FP{ fp.fromInt(0), fp.fromInt(0) };
    var qt = try Quadtree.build(&xs, &ys, allocator);
    defer qt.deinit();

    const k_squared = fp.fromInt(100);
    const theta = fp.fromFloat(0.0); // Exact — no approximation

    // Force on node at (0,0) — should push it left (away from node at (10,0))
    const force = qt.computeForce(Vec2{ .x = xs[0], .y = ys[0] }, k_squared, theta);
    try std.testing.expect(force.x < 0); // Pushed left
}

test "Quadtree: force is deterministic" {
    const allocator = std.testing.allocator;
    const xs = [_]FP{ fp.fromInt(0), fp.fromInt(5), fp.fromInt(-2), fp.fromInt(7) };
    const ys = [_]FP{ fp.fromInt(0), fp.fromInt(3), fp.fromInt(8), fp.fromInt(-1) };

    var qt1 = try Quadtree.build(&xs, &ys, allocator);
    defer qt1.deinit();
    var qt2 = try Quadtree.build(&xs, &ys, allocator);
    defer qt2.deinit();

    const k_sq = fp.fromInt(50);
    const theta = fp.fromFloat(0.8);

    for (xs, ys) |x, y| {
        const pos = Vec2{ .x = x, .y = y };
        const f1 = qt1.computeForce(pos, k_sq, theta);
        const f2 = qt2.computeForce(pos, k_sq, theta);
        try std.testing.expectEqual(f1.x, f2.x);
        try std.testing.expectEqual(f1.y, f2.y);
    }
}

test "Quadtree: large-cell center of mass is not saturated" {
    const allocator = std.testing.allocator;
    // 200 bodies clustered near x=300: coordinate × mass far exceeds the
    // Q16.16 integer range, which corrupted the root COM before the wide
    // arithmetic fix (fp.mul saturated at coordinate × mass > ~32767).
    const n = 200;
    const xs = try allocator.alloc(FP, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(FP, n);
    defer allocator.free(ys);
    for (0..n) |i| {
        xs[i] = fp.fromInt(300) + fp.fromInt(@intCast(i % 10));
        ys[i] = fp.fromInt(300) + fp.fromInt(@intCast(i / 10));
    }
    var qt = try Quadtree.build(xs, ys, allocator);
    defer qt.deinit();

    // Root COM must sit inside the cluster (300..310, 300..320).
    const com = qt.nodes.items[0].center_of_mass;
    try std.testing.expect(com.x >= fp.fromInt(299) and com.x <= fp.fromInt(311));
    try std.testing.expect(com.y >= fp.fromInt(299) and com.y <= fp.fromInt(321));
}

test "Quadtree: aggregate force scales with mass (no k²·mass saturation)" {
    const allocator = std.testing.allocator;
    // Two clusters at the same location in separate trees, one twice the
    // mass. Aggregate far-field force must roughly double — before the
    // wide fix both saturated to the same clamped magnitude (k²·mass
    // saturated at mass > 81 for k² = 400).
    const far = Vec2{ .x = fp.fromInt(-500), .y = fp.ZERO };
    const k_squared = fp.fromInt(400);
    const theta = fp.fromFloat(0.8);

    var forces_by_mass: [2]Vec2 = undefined;
    for ([_]usize{ 100, 200 }, 0..) |n, which| {
        const xs = try allocator.alloc(FP, n);
        defer allocator.free(xs);
        const ys = try allocator.alloc(FP, n);
        defer allocator.free(ys);
        for (0..n) |i| {
            xs[i] = fp.fromInt(100) + fp.fromInt(@intCast(i % 8));
            ys[i] = fp.fromInt(@intCast(i / 8));
        }
        var qt = try Quadtree.build(xs, ys, allocator);
        defer qt.deinit();
        forces_by_mass[which] = qt.computeForce(far, k_squared, theta);
    }

    // Repulsion pushes the far target further in -x; magnitude ~2x.
    try std.testing.expect(forces_by_mass[0].x < 0);
    try std.testing.expect(forces_by_mass[1].x < 0);
    const f1: i64 = -forces_by_mass[0].x;
    const f2: i64 = -forces_by_mass[1].x;
    try std.testing.expect(f2 > @divTrunc(f1 * 3, 2)); // at least 1.5x
    try std.testing.expect(f2 < f1 * 3); // and no more than 3x
}

test "Quadtree: cells containing the target are never approximated" {
    const allocator = std.testing.allocator;
    // Target at (10,10) plus 20 coincident bodies at (200,200), all in one
    // tree. At theta=1.5 the ROOT (which contains the target) satisfies
    // the opening criterion — before the geometric safety test, the walk
    // approximated it, folding the target's own mass and a COM shifted
    // toward the target into the result. With the test, the root opens and
    // only the cluster's own cell aggregates. Because the cluster is a
    // single point, its aggregate equals the exact per-body sum up to
    // per-term truncation, giving a tight deterministic bound.
    const n = 21;
    var xs: [n]FP = undefined;
    var ys: [n]FP = undefined;
    xs[0] = fp.fromInt(10);
    ys[0] = fp.fromInt(10);
    for (1..n) |i| {
        xs[i] = fp.fromInt(200);
        ys[i] = fp.fromInt(200);
    }
    var qt = try Quadtree.build(&xs, &ys, allocator);
    defer qt.deinit();

    const target = Vec2{ .x = xs[0], .y = ys[0] };
    const k_squared = fp.fromInt(400);
    const exact = qt.computeForce(target, k_squared, fp.fromFloat(0.0));
    const aggressive = qt.computeForce(target, k_squared, fp.fromFloat(1.5));

    // Both point away from the cluster; magnitudes match within rounding
    // (pre-fix, the aggressive result was ~10% larger from self-inclusion).
    try std.testing.expect(exact.x < 0 and aggressive.x < 0);
    const tol: FP = 2000; // ~0.03 in Q16.16, far below the pre-fix error
    try std.testing.expect(fp.abs(fp.sub(exact.x, aggressive.x)) < tol);
    try std.testing.expect(fp.abs(fp.sub(exact.y, aggressive.y)) < tol);
}

test "Quadtree: negative k_squared inverts force on leaf and aggregate paths" {
    const allocator = std.testing.allocator;
    // Cluster heavy enough to exercise the aggregate (mass) path.
    const n = 120;
    const xs_arr = try allocator.alloc(FP, n);
    defer allocator.free(xs_arr);
    const ys_arr = try allocator.alloc(FP, n);
    defer allocator.free(ys_arr);
    for (0..n) |i| {
        xs_arr[i] = fp.fromInt(100) + fp.fromInt(@intCast(i % 8));
        ys_arr[i] = fp.fromInt(@intCast(i / 8));
    }
    var qt = try Quadtree.build(xs_arr, ys_arr, allocator);
    defer qt.deinit();

    const far = Vec2{ .x = fp.fromInt(-500), .y = fp.ZERO };

    // Aggregate path (theta accepts the cluster cell).
    const pos_agg = qt.computeForce(far, fp.fromInt(400), fp.fromFloat(0.8));
    const neg_agg = qt.computeForce(far, fp.fromInt(-400), fp.fromFloat(0.8));
    try std.testing.expect(pos_agg.x < 0); // repulsion pushes away
    try std.testing.expect(neg_agg.x > 0); // negative strength attracts
    try std.testing.expectEqual(pos_agg.x, -neg_agg.x); // exact mirror
    try std.testing.expectEqual(pos_agg.y, -neg_agg.y);

    // Leaf path (theta = 0 → exact per-body walk).
    const pos_leaf = qt.computeForce(far, fp.fromInt(400), fp.fromFloat(0.0));
    const neg_leaf = qt.computeForce(far, fp.fromInt(-400), fp.fromFloat(0.0));
    try std.testing.expect(pos_leaf.x < 0);
    try std.testing.expect(neg_leaf.x > 0);
    try std.testing.expectEqual(pos_leaf.x, -neg_leaf.x);
}

test "mulMassDiv: pins both saturation bounds" {
    // Early positive saturation: the scaled quotient alone exceeds Q16.16.
    try std.testing.expectEqual(fp.MAX, Quadtree.mulMassDiv(fp.fromInt(30000), 100, fp.fromInt(2)));
    // Early negative saturation.
    try std.testing.expectEqual(fp.MIN, Quadtree.mulMassDiv(fp.fromInt(-30000), 100, fp.fromInt(2)));
    // Exact negative corner: k²·mass/d lands on MIN exactly (q = −32768,
    // remainder 0 — passes the early guard, no clamping needed).
    try std.testing.expectEqual(fp.MIN, Quadtree.mulMassDiv(fp.MIN, 3, fp.fromInt(3)));
    // Post-sum negative clamp: q = −32768 with a negative remainder pushes
    // the sum below MIN — the final clamp branch must catch it.
    try std.testing.expectEqual(fp.MIN, Quadtree.mulMassDiv(fp.MIN, 3, 196607));
    // In-range sanity just inside the bound: exact division, no clamping.
    try std.testing.expectEqual(fp.fromInt(15000), Quadtree.mulMassDiv(fp.fromInt(30000), 1, fp.fromInt(2)));
}
