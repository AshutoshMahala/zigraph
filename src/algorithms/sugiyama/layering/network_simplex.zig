//! Network Simplex layering algorithm
//!
//! Computes an optimal layer assignment that minimizes the total edge span
//! (sum of |layer[to] - layer[from]| across all edges). This produces
//! significantly more compact layouts than longest-path layering.
//!
//! ## Algorithm (Gansner, Koutsofios, North, Vo, 1993)
//!
//! 1. Compute an initial feasible layering (e.g., longest-path)
//! 2. Build a feasible spanning tree
//! 3. Iteratively improve by pivoting:
//!    a. Find a tree edge with negative cut value (leaving edge)
//!    b. Find a non-tree edge to replace it (entering edge)
//!    c. Update the tree and layer assignments
//! 4. Repeat until no negative cut values remain (optimal)
//!
//! ## Complexity
//!
//! - Typical: O(V·E) for sparse graphs
//! - Worst case: O(V²·E) but rare in practice
//! - Fast mode: O(V+E) init + O(max_iters·E) bounded pivoting
//!
//! ## Modes
//!
//! - `compute()` — Full network simplex (optimal result)
//! - `computeFast()` — Bounded iterations (good result, predictable time)
//!
//! ## References
//!
//! - Gansner et al., "A Technique for Drawing Directed Graphs" (1993)
//! - Graphviz dot layout engine

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const longest_path = @import("longest_path.zig");
pub const LayerAssignment = longest_path.LayerAssignment;

// =============================================================================
// Internal spanning tree structure
// =============================================================================

/// Edge in the network simplex formulation.
/// Each original DAG edge (u→v) has weight 1 and minimum length 1.
const NSEdge = struct {
    from: usize, // node index
    to: usize, // node index
    weight: i32 = 1, // edge weight (for objective function)
    min_len: i32 = 1, // minimum length constraint: layer[to] - layer[from] >= min_len
};

/// Spanning tree state for network simplex.
const SpanningTree = struct {
    allocator: Allocator,
    node_count: usize,
    edges: []NSEdge,
    edge_count: usize,

    // Tree structure
    in_tree: []bool, // in_tree[e] = true if edge e is in the spanning tree
    tree_parent: []?usize, // tree_parent[v] = parent node in tree (null for root)
    tree_parent_edge: []?usize, // tree_parent_edge[v] = edge index connecting v to parent
    tree_depth: []usize, // depth in the tree (root = 0)

    // Layer assignment (the solution)
    layers: []i32,

    // Cut values for tree edges
    cut_values: []i32,

    // Low/lim DFS numbering for O(1) subtree queries
    low: []usize, // low[v] = min DFS number in subtree rooted at v
    lim: []usize, // lim[v] = max DFS number in subtree rooted at v

    fn init(allocator: Allocator, node_count: usize, edges: []NSEdge) !SpanningTree {
        const edge_count = edges.len;
        return .{
            .allocator = allocator,
            .node_count = node_count,
            .edges = edges,
            .edge_count = edge_count,
            .in_tree = try allocator.alloc(bool, edge_count),
            .tree_parent = try allocator.alloc(?usize, node_count),
            .tree_parent_edge = try allocator.alloc(?usize, node_count),
            .tree_depth = try allocator.alloc(usize, node_count),
            .layers = try allocator.alloc(i32, node_count),
            .cut_values = try allocator.alloc(i32, edge_count),
            .low = try allocator.alloc(usize, node_count),
            .lim = try allocator.alloc(usize, node_count),
        };
    }

    fn deinit(self: *SpanningTree) void {
        self.allocator.free(self.in_tree);
        self.allocator.free(self.tree_parent);
        self.allocator.free(self.tree_parent_edge);
        self.allocator.free(self.tree_depth);
        self.allocator.free(self.layers);
        self.allocator.free(self.cut_values);
        self.allocator.free(self.low);
        self.allocator.free(self.lim);
    }

    /// Returns the slack of edge e: layer[to] - layer[from] - min_len.
    /// A tight edge has slack = 0.
    inline fn slack(self: *const SpanningTree, e: usize) i32 {
        return self.layers[self.edges[e].to] - self.layers[self.edges[e].from] - self.edges[e].min_len;
    }

    /// Check if node `u` is in the subtree rooted at `v` using low/lim numbering.
    /// This is O(1) after DFS numbering.
    inline fn inSubtree(self: *const SpanningTree, u: usize, v: usize) bool {
        return self.low[v] <= self.lim[u] and self.lim[u] <= self.lim[v];
    }
};

// =============================================================================
// Public API
// =============================================================================

/// Compute optimal layer assignment using full network simplex.
///
/// This finds the layering that minimizes total edge span (sum of edge lengths).
/// Optimal but may be slow on very large graphs (>10K nodes).
pub fn compute(g: *const Graph, allocator: Allocator) !LayerAssignment {
    return computeWithReversed(g, allocator, null);
}

/// Compute with reversed-edge mask for cycle breaking.
pub fn computeWithReversed(g: *const Graph, allocator: Allocator, reversed_edges: ?[]const bool) !LayerAssignment {
    // Safety bound: V*E is generous for convergence but prevents infinite cycling
    const v = g.nodeCount();
    const e = g.edges.items.len;
    const limit = @max(v * e, v * 10); // at least 10 iterations per node
    return computeWithLimit(g, allocator, @max(limit, 100), reversed_edges);
}

/// Compute layer assignment using network simplex with bounded iterations.
///
/// Uses at most `max_iters` pivot operations. With max_iters = V*sqrt(E),
/// this gives near-optimal results in O(V·sqrt(E)·E) worst case.
/// Falls back gracefully: even 0 iterations gives a feasible (longest-path) result.
pub fn computeFast(g: *const Graph, allocator: Allocator) !LayerAssignment {
    return computeFastWithReversed(g, allocator, null);
}

/// Fast compute with reversed-edge mask for cycle breaking.
pub fn computeFastWithReversed(g: *const Graph, allocator: Allocator, reversed_edges: ?[]const bool) !LayerAssignment {
    const v = g.nodeCount();
    const e = g.edges.items.len;
    if (v == 0) {
        return .{
            .levels = &.{},
            .max_level = 0,
            .allocator = allocator,
        };
    }
    // Heuristic iteration bound: V * sqrt(E) gives near-optimal for most graphs
    const sqrt_e = std.math.sqrt(@as(f64, @floatFromInt(@max(e, 1))));
    const max_iters: usize = @intFromFloat(@as(f64, @floatFromInt(v)) * sqrt_e);
    return computeWithLimit(g, allocator, @max(max_iters, v), reversed_edges); // at least V iterations
}

/// Core implementation with configurable iteration limit (0 = unlimited).
fn computeWithLimit(g: *const Graph, allocator: Allocator, max_iterations: usize, reversed_edges: ?[]const bool) !LayerAssignment {
    const node_count = g.nodeCount();

    if (node_count == 0) {
        return .{
            .levels = &.{},
            .max_level = 0,
            .allocator = allocator,
        };
    }

    if (g.edges.items.len == 0) {
        // No edges: all nodes on level 0
        const levels = try allocator.alloc(usize, node_count);
        @memset(levels, 0);
        return .{
            .levels = levels,
            .max_level = 0,
            .allocator = allocator,
        };
    }

    // =========================================================================
    // Step 1: Build edge list for network simplex
    // =========================================================================

    const ns_edges = try allocator.alloc(NSEdge, g.edges.items.len);
    defer allocator.free(ns_edges);

    for (g.edges.items, 0..) |edge, i| {
        // Flip direction for reversed (back) edges
        const is_reversed = if (reversed_edges) |re| re[i] else false;
        const from_id = if (is_reversed) edge.to else edge.from;
        const to_id = if (is_reversed) edge.from else edge.to;
        const from_idx = g.nodeIndex(from_id) orelse continue;
        const to_idx = g.nodeIndex(to_id) orelse continue;

        // Skip self-loops — they don't contribute to level ordering
        if (from_idx == to_idx) {
            ns_edges[i] = .{ .from = 0, .to = 0, .weight = 0, .min_len = 0 };
            continue;
        }

        ns_edges[i] = .{
            .from = from_idx,
            .to = to_idx,
            .weight = 1,
            .min_len = 1,
        };
    }

    // =========================================================================
    // Step 2: Compute initial feasible layering (longest-path)
    // =========================================================================

    var init_layers = try longest_path.computeWithReversed(g, allocator, reversed_edges);
    defer init_layers.deinit();

    var tree = try SpanningTree.init(allocator, node_count, ns_edges);
    defer tree.deinit();

    // Copy initial layers
    for (init_layers.levels, 0..) |level, i| {
        tree.layers[i] = @intCast(level);
    }

    // =========================================================================
    // Step 3: Build initial feasible spanning tree
    //
    // Strategy: Use a tight-tree growing approach.
    // Start from node 0, greedily add tight edges (slack = 0).
    // If the tree doesn't span all nodes, adjust layers to create
    // new tight edges and continue.
    // =========================================================================

    @memset(tree.in_tree, false);
    @memset(tree.tree_parent, null);
    @memset(tree.tree_parent_edge, null);
    @memset(tree.tree_depth, 0);

    try initFeasibleTree(&tree, allocator);

    // =========================================================================
    // Step 4: Compute low/lim DFS numbering and cut values
    // =========================================================================

    computeDfsNumbering(&tree);
    computeCutValues(&tree);

    // =========================================================================
    // Step 5: Network simplex pivoting
    //
    // While there exists a tree edge with negative cut value:
    //   1. Pick the tree edge with most negative cut value (leaving edge)
    //   2. Find the non-tree edge with minimum slack crossing the cut (entering edge)
    //   3. Exchange them in the tree
    //   4. Update layers, DFS numbering, and cut values
    // =========================================================================

    var iteration: usize = 0;
    var stall_count: usize = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        // Find leaving edge: tree edge with most negative cut value
        const leave_edge = findLeavingEdge(&tree) orelse break; // optimal!

        // Find entering edge: non-tree edge with minimum slack that crosses the cut
        const enter_edge = findEnteringEdge(&tree, leave_edge) orelse break;

        // Anti-cycling: if the entering edge already has slack 0, this is a
        // degenerate pivot that won't change layers. Count stalls and bail
        // after too many consecutive degenerate pivots.
        const enter_slack = tree.slack(enter_edge);
        if (enter_slack == 0) {
            stall_count += 1;
            if (stall_count > tree.node_count) break; // cycling detected
        } else {
            stall_count = 0;
        }

        // Perform the pivot: exchange leaving and entering edges
        pivot(&tree, leave_edge, enter_edge);

        // Recompute DFS numbering and cut values for affected subtree
        computeDfsNumbering(&tree);
        computeCutValues(&tree);
    }

    // =========================================================================
    // Step 6: Normalize layers (min layer = 0) and convert to usize
    // =========================================================================

    var min_layer: i32 = std.math.maxInt(i32);
    for (tree.layers[0..node_count]) |l| {
        min_layer = @min(min_layer, l);
    }

    const levels = try allocator.alloc(usize, node_count);
    var max_level: usize = 0;
    for (0..node_count) |i| {
        const normalized = tree.layers[i] - min_layer;
        levels[i] = @intCast(normalized);
        max_level = @max(max_level, levels[i]);
    }

    return .{
        .levels = levels,
        .max_level = max_level,
        .allocator = allocator,
    };
}

// =============================================================================
// Phase 1: Initial feasible spanning tree (tight-tree)
// =============================================================================

/// Build an initial feasible spanning tree by growing from tight edges.
/// If the tight tree doesn't span all nodes, adjust layers to make new
/// edges tight and continue.
fn initFeasibleTree(tree: *SpanningTree, allocator: Allocator) !void {
    const n = tree.node_count;
    const m = tree.edge_count;

    // Track which nodes are in the tree
    const in_tree_node = try allocator.alloc(bool, n);
    defer allocator.free(in_tree_node);
    @memset(in_tree_node, false);

    var tree_size: usize = 0;

    // Start with node 0
    in_tree_node[0] = true;
    tree_size = 1;

    // Greedily grow the tree using tight edges
    while (tree_size < n) {
        var found_tight = false;

        for (0..m) |e| {
            if (tree.in_tree[e]) continue;
            if (tree.slack(e) != 0) continue;

            const from = tree.edges[e].from;
            const to = tree.edges[e].to;

            // Exactly one endpoint must be in the tree
            const from_in = in_tree_node[from];
            const to_in = in_tree_node[to];

            if (from_in == to_in) continue; // both in or both out

            // Add this edge to the tree
            tree.in_tree[e] = true;
            const new_node = if (!from_in) from else to;
            const parent_node = if (!from_in) to else from;
            in_tree_node[new_node] = true;
            tree.tree_parent[new_node] = parent_node;
            tree.tree_parent_edge[new_node] = e;
            tree_size += 1;
            found_tight = true;
        }

        if (!found_tight and tree_size < n) {
            // No tight edges found — adjust layers to create one.
            // Find the minimum slack among edges connecting tree to non-tree.
            var min_slack: i32 = std.math.maxInt(i32);
            var best_direction: enum { forward, backward } = .forward;

            for (0..m) |e| {
                if (tree.in_tree[e]) continue;
                const from = tree.edges[e].from;
                const to = tree.edges[e].to;
                const from_in = in_tree_node[from];
                const to_in = in_tree_node[to];

                if (from_in and !to_in) {
                    // Edge goes tree → non-tree: slack > 0
                    const s = tree.slack(e);
                    if (s < min_slack) {
                        min_slack = s;
                        best_direction = .forward;
                    }
                } else if (!from_in and to_in) {
                    // Edge goes non-tree → tree: need to decrease layers
                    const s = tree.slack(e);
                    if (s < min_slack) {
                        min_slack = s;
                        best_direction = .backward;
                    }
                }
            }

            if (min_slack == std.math.maxInt(i32)) {
                // Graph is disconnected — assign remaining nodes to level 0
                for (0..n) |v| {
                    if (!in_tree_node[v]) {
                        in_tree_node[v] = true;
                        tree_size += 1;
                    }
                }
                break;
            }

            // Shift tree node layers to make an edge tight
            switch (best_direction) {
                .forward => {
                    // Increase tree node layers by min_slack
                    for (0..n) |v| {
                        if (in_tree_node[v]) {
                            tree.layers[v] += min_slack;
                        }
                    }
                },
                .backward => {
                    // Decrease tree node layers by min_slack
                    for (0..n) |v| {
                        if (in_tree_node[v]) {
                            tree.layers[v] -= min_slack;
                        }
                    }
                },
            }
            // Now at least one crossing edge is tight — loop back to find it
        }
    }

    // Set up tree root: find a node with no tree parent
    // (The first node added, node 0, has tree_parent = null, serving as root)
}

// =============================================================================
// Phase 2: DFS numbering (low/lim) for O(1) subtree queries
// =============================================================================

/// Compute low/lim DFS numbering of the spanning tree.
/// After this, `inSubtree(u, v)` answers in O(1) whether u is in v's subtree.
fn computeDfsNumbering(tree: *SpanningTree) void {
    const n = tree.node_count;

    @memset(tree.low, 0);
    @memset(tree.lim, 0);

    // Build tree adjacency for DFS (tree_parent gives us the tree structure)
    // We do an iterative DFS from the root (node with tree_parent == null)

    // Find root
    var root: usize = 0;
    for (0..n) |v| {
        if (tree.tree_parent[v] == null) {
            root = v;
            break;
        }
    }

    // Build children list for tree DFS
    // Using a stack-based approach to avoid recursion (large graphs)
    const State = struct {
        node: usize,
        child_iter: usize, // which child we're processing next
    };

    // First, build tree children from tree_parent
    // tree_children[v] = list of nodes whose tree_parent is v
    var tree_children_starts = tree.allocator.alloc(usize, n + 1) catch return;
    defer tree.allocator.free(tree_children_starts);
    var tree_children_buf = tree.allocator.alloc(usize, n) catch return;
    defer tree.allocator.free(tree_children_buf);

    // Count children per node
    @memset(tree_children_starts, 0);
    for (0..n) |v| {
        if (tree.tree_parent[v]) |p| {
            tree_children_starts[p] += 1;
        }
    }

    // Prefix sum to get starts
    {
        var sum: usize = 0;
        for (0..n) |v| {
            const count = tree_children_starts[v];
            tree_children_starts[v] = sum;
            sum += count;
        }
        tree_children_starts[n] = sum;
    }

    // Fill children buffer
    const offsets = tree.allocator.alloc(usize, n) catch return;
    defer tree.allocator.free(offsets);
    @memcpy(offsets, tree_children_starts[0..n]);

    for (0..n) |v| {
        if (tree.tree_parent[v]) |p| {
            tree_children_buf[offsets[p]] = v;
            offsets[p] += 1;
        }
    }

    // Iterative DFS with post-order numbering
    var stack = tree.allocator.alloc(State, n) catch return;
    defer tree.allocator.free(stack);
    var stack_top: usize = 0;
    var counter: usize = 1;

    // Also compute tree depth
    tree.tree_depth[root] = 0;

    stack[0] = .{ .node = root, .child_iter = 0 };
    stack_top = 1;

    while (stack_top > 0) {
        const frame = &stack[stack_top - 1];
        const v = frame.node;
        const child_start = tree_children_starts[v];
        const child_end = tree_children_starts[v + 1];
        const num_children = child_end - child_start;

        if (frame.child_iter == 0) {
            // Pre-order: record low
            tree.low[v] = counter;
        }

        if (frame.child_iter < num_children) {
            // Push next child
            const child = tree_children_buf[child_start + frame.child_iter];
            frame.child_iter += 1;
            tree.tree_depth[child] = tree.tree_depth[v] + 1;
            if (stack_top < stack.len) {
                stack[stack_top] = .{ .node = child, .child_iter = 0 };
                stack_top += 1;
            }
        } else {
            // Post-order: record lim
            if (num_children == 0) {
                // Leaf: low = lim = counter
                tree.low[v] = counter;
            }
            tree.lim[v] = counter;
            counter += 1;
            stack_top -= 1;
        }
    }
}

// =============================================================================
// Phase 3: Cut value computation
// =============================================================================

/// Compute cut values for all tree edges.
///
/// For a tree edge e, removing e partitions the tree into two components:
/// the "tail" component (containing e.from) and the "head" component (containing e.to).
///
/// cut_value(e) = sum of weights of edges going tail→head
///              - sum of weights of edges going head→tail
///
/// A negative cut value means we can reduce the total edge length by pivoting.
fn computeCutValues(tree: *SpanningTree) void {
    const m = tree.edge_count;

    @memset(tree.cut_values, 0);

    for (0..m) |e| {
        if (!tree.in_tree[e]) continue;

        // For tree edge e (from→to), determine which subtree is "head side"
        // The head component is the subtree containing the node further from root.
        // Since tree edge connects parent→child, we use depth to determine direction.
        const from = tree.edges[e].from;
        const to = tree.edges[e].to;

        // Determine which node is deeper (child side of the tree edge)
        // The subtree rooted at the deeper node is one component.
        const child_node = if (tree.tree_depth[from] > tree.tree_depth[to]) from else to;

        // Now count all edges crossing this cut
        var cut_val: i32 = 0;
        for (0..m) |f| {
            const f_from = tree.edges[f].from;
            const f_to = tree.edges[f].to;
            const from_in_child = tree.inSubtree(f_from, child_node);
            const to_in_child = tree.inSubtree(f_to, child_node);

            if (from_in_child and !to_in_child) {
                // Edge from child component to parent component
                // Direction depends on whether child_node is the "to" of the tree edge
                if (child_node == to) {
                    // child is head side: head→tail = negative contribution
                    cut_val -= tree.edges[f].weight;
                } else {
                    // child is tail side: tail→head = positive
                    cut_val += tree.edges[f].weight;
                }
            } else if (!from_in_child and to_in_child) {
                // Edge from parent component to child component
                if (child_node == to) {
                    // parent→head: tail→head = positive
                    cut_val += tree.edges[f].weight;
                } else {
                    // parent→tail: head→tail = negative
                    cut_val -= tree.edges[f].weight;
                }
            }
        }

        tree.cut_values[e] = cut_val;
    }
}

// =============================================================================
// Phase 4: Simplex pivoting
// =============================================================================

/// Find the leaving edge: the tree edge with the most negative cut value.
/// Returns null if no tree edge has a negative cut value (optimal).
fn findLeavingEdge(tree: *const SpanningTree) ?usize {
    var best: ?usize = null;
    var best_val: i32 = 0;

    for (0..tree.edge_count) |e| {
        if (!tree.in_tree[e]) continue;
        if (tree.cut_values[e] < best_val) {
            best_val = tree.cut_values[e];
            best = e;
        }
    }

    return best;
}

/// Find the entering edge: the non-tree edge with minimum slack that crosses
/// the cut defined by the leaving edge, in the correct direction.
fn findEnteringEdge(tree: *const SpanningTree, leave_edge: usize) ?usize {
    const from = tree.edges[leave_edge].from;
    const to = tree.edges[leave_edge].to;

    // Determine the child subtree (the deeper node's side)
    const child_node = if (tree.tree_depth[from] > tree.tree_depth[to]) from else to;

    var best: ?usize = null;
    var best_slack: i32 = std.math.maxInt(i32);

    for (0..tree.edge_count) |e| {
        if (tree.in_tree[e]) continue; // only non-tree edges

        const e_from = tree.edges[e].from;
        const e_to = tree.edges[e].to;
        const from_in_child = tree.inSubtree(e_from, child_node);
        const to_in_child = tree.inSubtree(e_to, child_node);

        // The entering edge must cross the cut in the opposite direction
        // of the leaving edge's negative cut value (to improve the solution).
        // We want edges where one endpoint is in the child subtree and one is not.
        var crosses = false;
        if (child_node == to) {
            // Child is on the "to" side of the leaving edge.
            // We need a non-tree edge going from outside-child to inside-child
            // (same direction as the tree edge) to replace it.
            crosses = (!from_in_child and to_in_child);
        } else {
            // Child is on the "from" side.
            crosses = (from_in_child and !to_in_child);
        }

        if (crosses) {
            const s = tree.slack(e);
            if (s < best_slack) {
                best_slack = s;
                best = e;
            }
        }
    }

    return best;
}

/// Perform a pivot: exchange the leaving tree edge with the entering non-tree edge.
/// Updates layers and tree structure.
fn pivot(tree: *SpanningTree, leave_edge: usize, enter_edge: usize) void {
    // Compute the layer shift needed to make the entering edge tight.
    // The entering edge's slack tells us how much to shift.
    const s = tree.slack(enter_edge);

    // Determine which subtree to shift.
    // The leaving edge splits the tree into two components.
    // We shift the component that makes the entering edge tight.
    const leave_from = tree.edges[leave_edge].from;
    const leave_to = tree.edges[leave_edge].to;
    const child_node = if (tree.tree_depth[leave_from] > tree.tree_depth[leave_to]) leave_from else leave_to;

    // Determine shift direction: does the entering edge go into or out of child subtree?
    const enter_to = tree.edges[enter_edge].to;
    const enter_to_in_child = tree.inSubtree(enter_to, child_node);

    if (enter_to_in_child) {
        // Entering edge's `to` is in child subtree.
        // slack = layers[to] - layers[from] - min_len > 0
        // To make slack=0: decrease layers[to] → shift child subtree UP by s
        for (0..tree.node_count) |v| {
            if (tree.inSubtree(v, child_node)) {
                tree.layers[v] -= s;
            }
        }
    } else {
        // Entering edge's `from` is in child subtree.
        // slack = layers[to] - layers[from] - min_len > 0
        // To make slack=0: increase layers[from] → shift child subtree DOWN by s
        for (0..tree.node_count) |v| {
            if (tree.inSubtree(v, child_node)) {
                tree.layers[v] += s;
            }
        }
    }

    // Exchange edges in the tree
    tree.in_tree[leave_edge] = false;
    tree.in_tree[enter_edge] = true;

    // Rebuild tree parent structure from in_tree edges.
    // This is simpler and more robust than incremental updates.
    rebuildTreeParents(tree);
}

/// Rebuild tree_parent and tree_parent_edge from the in_tree[] flags.
/// Uses BFS from the root.
fn rebuildTreeParents(tree: *SpanningTree) void {
    const n = tree.node_count;

    @memset(tree.tree_parent, null);
    @memset(tree.tree_parent_edge, null);

    // Build undirected adjacency for tree edges
    // (tree edges can go either direction in the original DAG)
    const visited = tree.allocator.alloc(bool, n) catch return;
    defer tree.allocator.free(visited);
    @memset(visited, false);

    const queue = tree.allocator.alloc(usize, n) catch return;
    defer tree.allocator.free(queue);
    var q_front: usize = 0;
    var q_back: usize = 0;

    // Find root (node 0 or first node)
    visited[0] = true;
    queue[q_back] = 0;
    q_back += 1;

    while (q_front < q_back) {
        const v = queue[q_front];
        q_front += 1;

        // Find all tree edges incident to v
        for (0..tree.edge_count) |e| {
            if (!tree.in_tree[e]) continue;
            const from = tree.edges[e].from;
            const to = tree.edges[e].to;

            var neighbor: ?usize = null;
            if (from == v and !visited[to]) {
                neighbor = to;
            } else if (to == v and !visited[from]) {
                neighbor = from;
            }

            if (neighbor) |nb| {
                visited[nb] = true;
                tree.tree_parent[nb] = v;
                tree.tree_parent_edge[nb] = e;
                tree.tree_depth[nb] = tree.tree_depth[v] + 1;
                if (q_back < queue.len) {
                    queue[q_back] = nb;
                    q_back += 1;
                }
            }
        }
    }
}

// =============================================================================
// Tests
// =============================================================================

test "network_simplex: empty graph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    var result = try compute(&g, allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.max_level);
}

test "network_simplex: single node" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "A");

    var result = try compute(&g, allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.levels[0]);
    try std.testing.expectEqual(@as(usize, 0), result.max_level);
}

test "network_simplex: simple chain" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    var result = try compute(&g, allocator);
    defer result.deinit();

    // Chain should be: A=0, B=1, C=2
    try std.testing.expectEqual(@as(usize, 0), result.levels[0]);
    try std.testing.expectEqual(@as(usize, 1), result.levels[1]);
    try std.testing.expectEqual(@as(usize, 2), result.levels[2]);
}

test "network_simplex: diamond minimizes span" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    //     A
    //    / \
    //   B   C
    //    \ /
    //     D
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);

    var result = try compute(&g, allocator);
    defer result.deinit();

    // Optimal: A=0, B=1, C=1, D=2  (total span = 4)
    try std.testing.expectEqual(@as(usize, 0), result.levels[0]); // A
    try std.testing.expectEqual(@as(usize, 1), result.levels[1]); // B
    try std.testing.expectEqual(@as(usize, 1), result.levels[2]); // C
    try std.testing.expectEqual(@as(usize, 2), result.levels[3]); // D
}

test "network_simplex: skip-level optimization" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Graph: A → B → D, A → C → D, A → D (skip-level)
    // Longest-path gives: A=0, B=1, C=1, D=2 (span: 1+1+1+1+2=6)
    // Optimal should be:  A=0, B=1, C=1, D=2 (same here, but NS verifies it)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);
    try g.addEdge(1, 4); // skip-level

    var result = try compute(&g, allocator);
    defer result.deinit();

    // All edges must point downward
    for (g.edges.items) |edge| {
        const from_idx = g.nodeIndex(edge.from).?;
        const to_idx = g.nodeIndex(edge.to).?;
        try std.testing.expect(result.levels[from_idx] < result.levels[to_idx]);
    }
}

test "network_simplex: fast mode matches feasibility" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);

    var result = try computeFast(&g, allocator);
    defer result.deinit();

    // Must be feasible: all edges point downward
    for (g.edges.items) |edge| {
        const from_idx = g.nodeIndex(edge.from).?;
        const to_idx = g.nodeIndex(edge.to).?;
        try std.testing.expect(result.levels[from_idx] < result.levels[to_idx]);
    }
}

test "network_simplex: wide fan-out" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    //  Root → A, B, C, D, E
    //  All → Sink
    try g.addNode(0, "Root");
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addNode(5, "E");
    try g.addNode(6, "Sink");

    for (1..6) |i| {
        try g.addEdge(0, i);
        try g.addEdge(i, 6);
    }

    var result = try compute(&g, allocator);
    defer result.deinit();

    // Root=0, A..E=1, Sink=2 — this is optimal (total span = 10)
    try std.testing.expectEqual(@as(usize, 0), result.levels[0]); // Root
    for (1..6) |i| {
        try std.testing.expectEqual(@as(usize, 1), result.levels[i]);
    }
    try std.testing.expectEqual(@as(usize, 2), result.levels[6]); // Sink
}

test "network_simplex: disconnected components" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Component 1: A → B
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    // Component 2: C → D
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(3, 4);

    var result = try compute(&g, allocator);
    defer result.deinit();

    // Both components should have proper layering
    try std.testing.expect(result.levels[0] < result.levels[1]); // A < B
    try std.testing.expect(result.levels[2] < result.levels[3]); // C < D
}

test "network_simplex: no edges" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");

    var result = try compute(&g, allocator);
    defer result.deinit();

    // No edges: all on level 0
    try std.testing.expectEqual(@as(usize, 0), result.levels[0]);
    try std.testing.expectEqual(@as(usize, 0), result.levels[1]);
    try std.testing.expectEqual(@as(usize, 0), result.levels[2]);
}
