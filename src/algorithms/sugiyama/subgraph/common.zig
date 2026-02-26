//! Common subgraph utilities shared across subgraph modules.
//!
//! Provides subgraph membership resolution, ancestor chain computation,
//! and boundary transition counting used by padding and crossing modules.

const std = @import("std");
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const virtual_mod = @import("../layering/virtual.zig");
const VNode = virtual_mod.VNode;

/// Default padding around subgraph bounding boxes (in layout cells).
pub const default_padding: usize = 2;

/// Determine which subgraph a VNode belongs to.
///
/// - **Real nodes**: returns the node's immediate subgraph via `nodeSubgraph`.
/// - **Dummy nodes**: returns the subgraph only when *both* endpoints of the
///   edge share the same immediate subgraph (intra-subgraph edge).
///   Cross-subgraph edge dummies return `null`, allowing them to float
///   freely between blocks during adjacency enforcement.
pub fn vnodeSubgraph(g: *const Graph, vnode: VNode) ?usize {
    return switch (vnode) {
        .real => |node_idx| blk: {
            const node = g.nodeAt(node_idx) orelse break :blk null;
            break :blk g.nodeSubgraph(node.id);
        },
        .dummy => |edge_idx| blk: {
            if (edge_idx >= g.edges.items.len) break :blk null;
            const edge = g.edges.items[edge_idx];
            const from_sg = g.nodeSubgraph(edge.from) orelse break :blk null;
            const to_sg = g.nodeSubgraph(edge.to) orelse break :blk null;
            break :blk if (from_sg == to_sg) from_sg else null;
        },
    };
}

/// Compute the nesting depth of a subgraph (0 for root-level subgraphs).
pub fn subgraphDepth(g: *const Graph, sg_id: usize) usize {
    var depth: usize = 0;
    var current = sg_id;
    while (true) {
        const sg = g.subgraphById(current) orelse break;
        if (sg.parent_id) |pid| {
            depth += 1;
            current = pid;
        } else break;
    }
    return depth;
}

/// Compute the full ancestor chain for a subgraph, ordered from
/// innermost (the subgraph itself) to outermost.
/// Returns the number of ancestors written into `buf`.
pub fn ancestorChain(g: *const Graph, sg_id: usize, buf: []usize) usize {
    var n: usize = 0;
    var current = sg_id;
    while (n < buf.len) {
        buf[n] = current;
        n += 1;
        const sg = g.subgraphById(current) orelse break;
        current = sg.parent_id orelse break;
    }
    return n;
}

/// Count the number of subgraph boundary transitions between two VNodes.
///
/// A boundary transition occurs when the set of enclosing subgraphs differs.
/// Each entered or exited subgraph contributes one boundary line that needs
/// a padding cell.
///
/// For example, if node A is in `[inner, outer]` and node B is in `[outer]`,
/// there is 1 transition (exiting `inner`). If node B is in a completely
/// different subgraph tree, the count is `depth(A) + depth(B)`.
pub fn countBoundaryTransitions(
    g: *const Graph,
    sg_a: ?usize,
    sg_b: ?usize,
    chain_buf_a: []usize,
    chain_buf_b: []usize,
) usize {
    // Same subgraph (including both null) → no transitions
    if (sg_a == sg_b) return 0;

    const depth_a = if (sg_a) |a| ancestorChain(g, a, chain_buf_a) else 0;
    const depth_b = if (sg_b) |b| ancestorChain(g, b, chain_buf_b) else 0;

    // If one is null (root), transitions = full depth of the other
    if (sg_a == null) return depth_b;
    if (sg_b == null) return depth_a;

    // Find the lowest common ancestor
    for (chain_buf_a[0..depth_a]) |a_id| {
        for (chain_buf_b[0..depth_b]) |b_id| {
            if (a_id == b_id) {
                // a_id == b_id is the LCA.
                // Transitions = levels above LCA in A + levels above LCA in B
                // Find index of a_id in chain A (chain is innermost-first)
                var idx_a: usize = 0;
                for (chain_buf_a[0..depth_a], 0..) |x, i| {
                    if (x == a_id) {
                        idx_a = i;
                        break;
                    }
                }
                var idx_b: usize = 0;
                for (chain_buf_b[0..depth_b], 0..) |x, i| {
                    if (x == b_id) {
                        idx_b = i;
                        break;
                    }
                }
                // idx_a = number of subgraphs between node A and the LCA
                // idx_b = number of subgraphs between node B and the LCA
                return idx_a + idx_b;
            }
        }
    }

    // No common ancestor → all boundaries crossed
    return depth_a + depth_b;
}

// ============================================================================
// Tests
// ============================================================================

test "vnodeSubgraph: real node with subgraph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{1}).inside(sg);

    // Node 1 (idx 0) is in sg
    try std.testing.expectEqual(@as(?usize, sg), vnodeSubgraph(&g, .{ .real = 0 }));
    // Node 2 (idx 1) has no subgraph
    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .real = 1 }));
}

test "vnodeSubgraph: real node without subgraph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");

    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .real = 0 }));
}

test "vnodeSubgraph: dummy intra-subgraph edge" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    try g.addEdge(1, 2); // edge 0: intra-subgraph
    try g.addEdge(1, 3); // edge 1: cross-subgraph (A in sg, C root)

    // Dummy for intra-subgraph edge → belongs to sg
    try std.testing.expectEqual(@as(?usize, sg), vnodeSubgraph(&g, .{ .dummy = 0 }));
    // Dummy for cross-subgraph edge → null
    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .dummy = 1 }));
}

test "vnodeSubgraph: dummy cross-subgraph edge" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");
    try g.putNodes(&.{1}).inside(sg_a);
    try g.putNodes(&.{2}).inside(sg_b);

    try g.addEdge(1, 2); // edge 0: cross-subgraph

    // Dummy for cross-subgraph edge → null (floats freely)
    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .dummy = 0 }));
}

test "countBoundaryTransitions: same subgraph = 0" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const sg = try g.addSubgraph("SG");
    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    try std.testing.expectEqual(@as(usize, 0), countBoundaryTransitions(&g, sg, sg, &buf_a, &buf_b));
}

test "countBoundaryTransitions: null to subgraph = depth" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);

    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    // null → inner (depth 2: inner + outer)
    try std.testing.expectEqual(@as(usize, 2), countBoundaryTransitions(&g, null, inner, &buf_a, &buf_b));
    // null → outer (depth 1: outer)
    try std.testing.expectEqual(@as(usize, 1), countBoundaryTransitions(&g, null, outer, &buf_a, &buf_b));
}

test "countBoundaryTransitions: sibling subgraphs" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const parent = try g.addSubgraph("parent");
    const child_a = try g.addSubgraph("child_a");
    const child_b = try g.addSubgraph("child_b");
    try g.putSubgraphs(&.{ child_a, child_b }).inside(parent);

    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    // child_a → child_b: both depth 2, LCA = parent
    // transitions = 1 (exit child_a) + 1 (enter child_b) = 2
    // But ancestorChain returns [child_a, parent] and [child_b, parent]
    // First match: when a_id == b_id → parent == parent at idx_a=1, idx_b=1
    // Transitions = 1 + 1 = 2
    try std.testing.expectEqual(@as(usize, 2), countBoundaryTransitions(&g, child_a, child_b, &buf_a, &buf_b));
}

test "countBoundaryTransitions: disjoint trees" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");

    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    // No common ancestor → depth_a + depth_b = 1 + 1 = 2
    try std.testing.expectEqual(@as(usize, 2), countBoundaryTransitions(&g, sg_a, sg_b, &buf_a, &buf_b));
}
