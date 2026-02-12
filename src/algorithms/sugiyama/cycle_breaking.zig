//! Cycle Breaking for Sugiyama Layout
//!
//! Detects and marks back edges in a directed graph so the Sugiyama pipeline
//! can treat the graph as a DAG. Back edges are "virtually reversed" — the
//! original graph is not mutated. Instead, a boolean mask tells downstream
//! phases (layering, routing) which edges to flip.
//!
//! ## Algorithm: DFS-based back edge detection
//!
//! Uses the classic three-color DFS (WHITE/GRAY/BLACK). Any edge pointing
//! to a GRAY node is a back edge. Reversing all back edges makes the graph
//! acyclic (this is a standard result; see Cormen et al., CLRS §22.3).
//!
//! ## Complexity
//!
//! - Time: O(V + E)
//! - Space: O(V) for color array + O(V) explicit stack
//!
//! ## Usage
//!
//! ```zig
//! const reversed = try detectBackEdges(&graph, allocator);
//! defer allocator.free(reversed);
//! // reversed[i] == true means edge i should be treated as going to→from
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;

/// Detect back edges using DFS. Returns a boolean mask indexed by edge index.
///
/// `reversed[i] == true` means graph.edges.items[i] is a back edge and should
/// be treated as reversed (to→from) by downstream phases.
///
/// The original graph is NOT modified.
pub fn detectBackEdges(g: *const Graph, allocator: Allocator) ![]bool {
    const node_count = g.nodeCount();
    const edge_count = g.edges.items.len;

    const reversed = try allocator.alloc(bool, edge_count);
    @memset(reversed, false);

    if (node_count == 0 or edge_count == 0) return reversed;

    // Three-color DFS: WHITE=0, GRAY=1, BLACK=2
    var color = try allocator.alloc(u8, node_count);
    defer allocator.free(color);
    @memset(color, 0);

    // Explicit DFS stack (node index, child iterator position)
    const StackEntry = struct {
        node: usize,
        child_pos: usize,
    };
    var stack: std.ArrayListUnmanaged(StackEntry) = .{};
    defer stack.deinit(allocator);

    // DFS from each unvisited node (handles disconnected graphs)
    for (0..node_count) |start| {
        if (color[start] != 0) continue;

        try stack.append(allocator, .{ .node = start, .child_pos = 0 });
        color[start] = 1; // GRAY

        while (stack.items.len > 0) {
            const top = &stack.items[stack.items.len - 1];
            const children = g.getChildren(top.node);

            if (top.child_pos < children.len) {
                const child = children[top.child_pos];
                top.child_pos += 1;

                if (color[child] == 0) {
                    // Unvisited: push and mark GRAY
                    color[child] = 1;
                    try stack.append(allocator, .{ .node = child, .child_pos = 0 });
                } else if (color[child] == 1) {
                    // GRAY → back edge found! Mark the corresponding edge as reversed.
                    markBackEdge(g, top.node, child, reversed);
                }
                // BLACK children: cross/forward edge, ignore
            } else {
                // All children visited, mark BLACK and pop
                color[top.node] = 2;
                _ = stack.pop();
            }
        }
    }

    return reversed;
}

/// Find the edge index for edge (from→to) and mark it as reversed.
fn markBackEdge(g: *const Graph, from_idx: usize, to_idx: usize, reversed: []bool) void {
    const from_id = if (from_idx < g.nodes.items.len) g.nodes.items[from_idx].id else return;
    const to_id = if (to_idx < g.nodes.items.len) g.nodes.items[to_idx].id else return;

    for (g.edges.items, 0..) |edge, i| {
        if (edge.from == from_id and edge.to == to_id and !reversed[i]) {
            reversed[i] = true;
            return; // Mark only one edge per (from, to) pair
        }
    }
}

/// Count how many edges are marked as reversed.
pub fn countReversed(reversed: []const bool) usize {
    var count: usize = 0;
    for (reversed) |r| {
        if (r) count += 1;
    }
    return count;
}

// =============================================================================
// Tests
// =============================================================================

test "cycle_breaking: acyclic graph has no back edges" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // A → B → C → D (linear DAG)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);

    const reversed = try detectBackEdges(&g, allocator);
    defer allocator.free(reversed);

    try std.testing.expectEqual(@as(usize, 0), countReversed(reversed));
}

test "cycle_breaking: simple cycle A→B→C→A" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1); // Back edge

    const reversed = try detectBackEdges(&g, allocator);
    defer allocator.free(reversed);

    // Exactly one edge should be reversed to break the cycle
    try std.testing.expectEqual(@as(usize, 1), countReversed(reversed));

    // The back edge (C→A, edge index 2) should be reversed
    try std.testing.expect(reversed[2]);
}

test "cycle_breaking: self-loop" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);
    try g.addEdge(1, 1); // Self-loop

    const reversed = try detectBackEdges(&g, allocator);
    defer allocator.free(reversed);

    try std.testing.expectEqual(@as(usize, 1), countReversed(reversed));
    try std.testing.expect(reversed[1]); // Self-loop is a back edge
}

test "cycle_breaking: two separate cycles" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Cycle 1: A→B→A
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);
    try g.addEdge(2, 1); // Back edge

    // Cycle 2: C→D→C
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(3, 4);
    try g.addEdge(4, 3); // Back edge

    const reversed = try detectBackEdges(&g, allocator);
    defer allocator.free(reversed);

    try std.testing.expectEqual(@as(usize, 2), countReversed(reversed));
}

test "cycle_breaking: diamond (no cycle)" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    //   A
    //  / \
    // B   C
    //  \ /
    //   D
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);

    const reversed = try detectBackEdges(&g, allocator);
    defer allocator.free(reversed);

    try std.testing.expectEqual(@as(usize, 0), countReversed(reversed));
}

test "cycle_breaking: complex graph with one cycle" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // A→B→C→D, B→D, D→B (cycle: B→C→D→B or B→D→B)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2); // 0
    try g.addEdge(2, 3); // 1
    try g.addEdge(3, 4); // 2
    try g.addEdge(2, 4); // 3
    try g.addEdge(4, 2); // 4 - back edge

    const reversed = try detectBackEdges(&g, allocator);
    defer allocator.free(reversed);

    // D→B should be detected as back edge
    try std.testing.expect(reversed[4]);
}

test "cycle_breaking: empty graph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const reversed = try detectBackEdges(&g, allocator);
    defer allocator.free(reversed);

    try std.testing.expectEqual(@as(usize, 0), reversed.len);
}
