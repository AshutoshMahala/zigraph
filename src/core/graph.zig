//! Core graph data structures
//!
//! This module provides the fundamental Graph, Node, and Edge types.
//! Designed for heap allocation first; arena support will be added later.
//!
//! ## Performance Characteristics
//!
//! - **Node/Edge Insertion**: O(1) amortized
//! - **Child/Parent Lookups**: O(1) via cached adjacency lists
//! - **ID→Index Mapping**: O(1) via HashMap
//!
//! ## Example
//!
//! ```zig
//! var graph = Graph.init(allocator);
//! defer graph.deinit();
//!
//! try graph.addNode(1, "Start");
//! try graph.addNode(2, "End");
//! try graph.addEdge(1, 2);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("errors.zig");
const validation = @import("validation.zig");
pub const ValidationResult = errors.ValidationResult;
pub const CycleInfo = errors.CycleInfo;

/// How a node was created
pub const NodeKind = enum {
    /// Explicitly declared by user with full details
    explicit,
    /// Auto-created from edge reference (implicit)
    implicit,
    /// Layout dummy node for skip-level edge routing (internal)
    dummy,
};

/// A node in the graph.
pub const Node = struct {
    /// Unique identifier for this node
    id: usize,
    /// Display label for the node
    label: []const u8,
    /// Computed display width (including brackets)
    width: usize,
    /// Whether the label was heap-allocated (for cleanup)
    owned_label: bool = false,
    /// How this node was created
    kind: NodeKind = .explicit,

    pub fn init(id: usize, label: []const u8) Node {
        // Width = "[" + label + "]" = label.len + 2
        return .{
            .id = id,
            .label = label,
            .width = label.len + 2,
        };
    }
};

/// An edge connecting two nodes.
pub const Edge = struct {
    /// Source node ID
    from: usize,
    /// Target node ID
    to: usize,
    /// Whether this edge is directed (from → to) or undirected (from — to)
    directed: bool = true,
    /// Optional label (e.g., "depends on")
    label: ?[]const u8 = null,
};

/// A graph with layout capabilities.
///
/// Supports directed, undirected, and mixed edges. The graph stores
/// nodes and edges, maintaining adjacency lists for efficient traversal
/// during layout computation.
pub const Graph = struct {
    /// Default maximum number of nodes (security limit to prevent DoS)
    pub const default_max_nodes: usize = 100_000;

    /// Default maximum number of edges (security limit to prevent DoS)
    pub const default_max_edges: usize = 500_000;

    /// Configuration options for Graph initialization
    pub const Options = struct {
        /// Maximum nodes allowed. Set to 0 for unlimited (not recommended).
        max_nodes: usize = default_max_nodes,
        /// Maximum edges allowed. Set to 0 for unlimited (not recommended).
        max_edges: usize = default_max_edges,
    };

    allocator: Allocator,

    /// All nodes in insertion order
    nodes: std.ArrayListUnmanaged(Node),

    /// All edges
    edges: std.ArrayListUnmanaged(Edge),

    /// Map from node ID to index in nodes array (O(1) lookup)
    id_to_index: std.AutoHashMapUnmanaged(usize, usize),

    /// Adjacency list: children[idx] = indices of child nodes
    children: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)),

    /// Adjacency list: parents[idx] = indices of parent nodes
    parents: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)),

    /// Resource limits
    max_nodes: usize,
    max_edges: usize,

    const Self = @This();

    /// Initialize a new empty graph with default options.
    pub fn init(allocator: Allocator) Self {
        return initWithOptions(allocator, .{});
    }

    /// Initialize a new empty graph with custom options.
    pub fn initWithOptions(allocator: Allocator, options: Options) Self {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .edges = .{},
            .id_to_index = .{},
            .children = .{},
            .parents = .{},
            .max_nodes = options.max_nodes,
            .max_edges = options.max_edges,
        };
    }

    /// Free all memory used by the graph.
    pub fn deinit(self: *Self) void {
        // Free owned labels (from addEdgeAutoCreate)
        for (self.nodes.items) |node| {
            if (node.owned_label) {
                self.allocator.free(node.label);
            }
        }

        // Free adjacency lists
        for (self.children.items) |*child_list| {
            child_list.deinit(self.allocator);
        }
        self.children.deinit(self.allocator);

        for (self.parents.items) |*parent_list| {
            parent_list.deinit(self.allocator);
        }
        self.parents.deinit(self.allocator);

        self.id_to_index.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
    }

    /// Add a node to the graph.
    ///
    /// If a node with the same ID already exists, this is a no-op.
    /// Returns error.NodeLimitExceeded if max_nodes limit would be exceeded.
    pub fn addNode(self: *Self, id: usize, label: []const u8) !void {
        // Check if node already exists
        if (self.id_to_index.contains(id)) {
            return; // Already exists
        }

        // Security: enforce max node limit to prevent DoS (0 = unlimited)
        if (self.max_nodes > 0 and self.nodes.items.len >= self.max_nodes) {
            var detail_buf: [96]u8 = undefined;
            const detail = std.fmt.bufPrint(&detail_buf, "{d} nodes at limit of {d}", .{ self.nodes.items.len, self.max_nodes }) catch "node limit exceeded";
            errors.captureErrorWithDetail(error.NodeLimitExceeded, @src(), detail);
            return error.NodeLimitExceeded;
        }

        const idx = self.nodes.items.len;
        try self.nodes.append(self.allocator, Node.init(id, label));
        try self.id_to_index.put(self.allocator, id, idx);

        // Initialize empty adjacency lists for this node
        try self.children.append(self.allocator, .{});
        try self.parents.append(self.allocator, .{});
    }

    // ── Directed edge helpers ────────────────────────────────────────

    /// Add a directed edge from → to.
    ///
    /// Both nodes must already exist. Returns error if either node is missing.
    /// Returns error.EdgeLimitExceeded if max_edges limit would be exceeded.
    pub fn addDiEdge(self: *Self, from: usize, to: usize) !void {
        try self.addEdgeInternal(from, to, true, null);
    }

    /// Add a directed edge with a label.
    pub fn addDiEdgeLabeled(self: *Self, from: usize, to: usize, label: []const u8) !void {
        try self.addEdgeInternal(from, to, true, label);
    }

    // ── Undirected edge helpers ────────────────────────────────────

    /// Add an undirected edge between a and b.
    ///
    /// Internally stores a single edge record with `directed = false`.
    /// Both nodes must already exist.
    pub fn addUnDiEdge(self: *Self, a: usize, b: usize) !void {
        try self.addEdgeInternal(a, b, false, null);
    }

    /// Add an undirected edge with a label.
    pub fn addUnDiEdgeLabeled(self: *Self, a: usize, b: usize, label: []const u8) !void {
        try self.addEdgeInternal(a, b, false, label);
    }

    // ── Backward-compatible aliases ────────────────────────────────

    /// Add a directed edge (alias for `addDiEdge`).
    pub fn addEdge(self: *Self, from: usize, to: usize) !void {
        try self.addDiEdge(from, to);
    }

    /// Add a directed labeled edge (alias for `addDiEdgeLabeled`).
    pub fn addEdgeLabeled(self: *Self, from: usize, to: usize, label: []const u8) !void {
        try self.addDiEdgeLabeled(from, to, label);
    }

    /// Add a directed edge, auto-creating missing nodes with default labels.
    ///
    /// Nodes are created with their ID as the label (e.g., node 42 → label "42").
    /// The label is heap-allocated and freed when the graph is deinitialized.
    ///
    /// For graphs where you control node labels, prefer addNode() + addEdge().
    pub fn addEdgeAutoCreate(self: *Self, from: usize, to: usize) !void {
        // Auto-create 'from' node if missing
        if (!self.id_to_index.contains(from)) {
            const label = try self.allocIdLabel(from);
            try self.addNodeOwned(from, label);
        }
        // Auto-create 'to' node if missing
        if (!self.id_to_index.contains(to)) {
            const label = try self.allocIdLabel(to);
            try self.addNodeOwned(to, label);
        }

        try self.addDiEdge(from, to);
    }

    // ── Core edge insertion ────────────────────────────────────────

    /// Internal: single code-path for all edge additions.
    fn addEdgeInternal(
        self: *Self,
        from: usize,
        to: usize,
        directed: bool,
        label: ?[]const u8,
    ) !void {
        const from_idx = self.id_to_index.get(from) orelse {
            var detail_buf: [64]u8 = undefined;
            const detail = std.fmt.bufPrint(&detail_buf, "node {d} does not exist", .{from}) catch "node does not exist";
            errors.captureErrorFull(error.NodeNotFound, @src(), detail, &.{from});
            return error.NodeNotFound;
        };
        const to_idx = self.id_to_index.get(to) orelse {
            var detail_buf: [64]u8 = undefined;
            const detail = std.fmt.bufPrint(&detail_buf, "node {d} does not exist", .{to}) catch "node does not exist";
            errors.captureErrorFull(error.NodeNotFound, @src(), detail, &.{to});
            return error.NodeNotFound;
        };

        // Security: enforce max edge limit to prevent DoS (0 = unlimited)
        if (self.max_edges > 0 and self.edges.items.len >= self.max_edges) {
            var detail_buf: [96]u8 = undefined;
            const detail = std.fmt.bufPrint(&detail_buf, "{d} edges at limit of {d}", .{ self.edges.items.len, self.max_edges }) catch "edge limit exceeded";
            errors.captureErrorWithDetail(error.EdgeLimitExceeded, @src(), detail);
            return error.EdgeLimitExceeded;
        }

        try self.edges.append(self.allocator, .{
            .from = from,
            .to = to,
            .directed = directed,
            .label = label,
        });

        // Update adjacency lists
        try self.children.items[from_idx].append(self.allocator, to_idx);
        try self.parents.items[to_idx].append(self.allocator, from_idx);
    }

    /// Allocate a label string for an ID (e.g., 42 → "42")
    fn allocIdLabel(self: *Self, id: usize) ![]const u8 {
        // Count digits needed
        var temp = id;
        var len: usize = if (id == 0) 1 else 0;
        while (temp > 0) : (temp /= 10) {
            len += 1;
        }

        const buf = try self.allocator.alloc(u8, len);
        // Safe: we computed exact buffer size needed for this integer
        // bufPrint can't fail since we sized the buffer correctly
        _ = std.fmt.bufPrint(buf, "{d}", .{id}) catch {
            // This should never happen given correct buffer sizing
            self.allocator.free(buf);
            return error.OutOfMemory;
        };
        return buf;
    }

    /// Add a node with an owned (heap-allocated) label.
    /// The graph takes ownership and will free the label on deinit.
    /// These are implicit nodes (auto-created from edges).
    fn addNodeOwned(self: *Self, id: usize, label: []const u8) !void {
        if (self.id_to_index.contains(id)) {
            // Node exists, free the label we were given
            self.allocator.free(label);
            return;
        }

        const idx = self.nodes.items.len;
        var node = Node.init(id, label);
        node.owned_label = true; // Mark for cleanup
        node.kind = .implicit; // Auto-created from edge
        try self.nodes.append(self.allocator, node);
        try self.id_to_index.put(self.allocator, id, idx);
        try self.children.append(self.allocator, .{});
        try self.parents.append(self.allocator, .{});
    }

    /// Get the index of a node by its ID.
    pub fn nodeIndex(self: *const Self, id: usize) ?usize {
        return self.id_to_index.get(id);
    }

    /// Get a node by its index.
    pub fn nodeAt(self: *const Self, idx: usize) ?*const Node {
        if (idx >= self.nodes.items.len) return null;
        return &self.nodes.items[idx];
    }

    /// Get a node by its ID.
    pub fn nodeById(self: *const Self, id: usize) ?*const Node {
        const idx = self.nodeIndex(id) orelse return null;
        return self.nodeAt(idx);
    }

    /// Get indices of all children of a node (by index).
    pub fn getChildren(self: *const Self, idx: usize) []const usize {
        if (idx >= self.children.items.len) return &.{};
        return self.children.items[idx].items;
    }

    /// Get indices of all parents of a node (by index).
    pub fn getParents(self: *const Self, idx: usize) []const usize {
        if (idx >= self.parents.items.len) return &.{};
        return self.parents.items[idx].items;
    }

    /// Get the number of nodes.
    pub fn nodeCount(self: *const Self) usize {
        return self.nodes.items.len;
    }

    /// Get the number of edges.
    pub fn edgeCount(self: *const Self) usize {
        return self.edges.items.len;
    }

    /// Check if the graph is empty.
    pub fn isEmpty(self: *const Self) bool {
        return self.nodes.items.len == 0;
    }

    /// Find all root nodes (nodes with no parents).
    pub fn findRoots(self: *const Self, allocator: Allocator) !std.ArrayListUnmanaged(usize) {
        var roots: std.ArrayListUnmanaged(usize) = .{};
        for (self.parents.items, 0..) |parent_list, idx| {
            if (parent_list.items.len == 0) {
                try roots.append(allocator, idx);
            }
        }
        return roots;
    }

    /// Find all leaf nodes (nodes with no children).
    pub fn findLeaves(self: *const Self, allocator: Allocator) !std.ArrayListUnmanaged(usize) {
        var leaves: std.ArrayListUnmanaged(usize) = .{};
        for (self.children.items, 0..) |child_list, idx| {
            if (child_list.items.len == 0) {
                try leaves.append(allocator, idx);
            }
        }
        return leaves;
    }

    /// Validate the graph for layout operations.
    ///
    /// Returns:
    /// - `.ok` if the graph is valid for layout
    /// - `.empty` if the graph has no nodes
    /// - `.cycle` with cycle path if the graph contains a cycle
    ///
    /// This should be called before layout to get detailed error info.
    /// See `validation.zig` for the standalone algorithm.
    pub fn validate(self: *const Self, allocator: Allocator) !ValidationResult {
        return validation.validate(
            self.nodes.items.len,
            self.children.items,
            self.parents.items,
            allocator,
        );
    }

    /// Check if the graph contains a cycle.
    ///
    /// This is a convenience method that returns true/false.
    /// Use `validate()` for detailed cycle information.
    pub fn hasCycle(self: *const Self, allocator: Allocator) !bool {
        return validation.hasCycle(
            self.nodes.items.len,
            self.children.items,
            allocator,
        );
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Graph: basic node and edge operations" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "Middle");
    try g.addNode(3, "End");

    try std.testing.expectEqual(@as(usize, 3), g.nodeCount());

    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    try std.testing.expectEqual(@as(usize, 2), g.edgeCount());

    // Check adjacency
    const children_of_1 = g.getChildren(0);
    try std.testing.expectEqual(@as(usize, 1), children_of_1.len);
    try std.testing.expectEqual(@as(usize, 1), children_of_1[0]); // index of node 2

    const parents_of_2 = g.getParents(1);
    try std.testing.expectEqual(@as(usize, 1), parents_of_2.len);
    try std.testing.expectEqual(@as(usize, 0), parents_of_2[0]); // index of node 1
}

test "Graph: find roots and leaves" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    var roots = try g.findRoots(allocator);
    defer roots.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), roots.items.len);
    try std.testing.expectEqual(@as(usize, 0), roots.items[0]); // Node 1 is root

    var leaves = try g.findLeaves(allocator);
    defer leaves.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), leaves.items.len);
}

test "Graph: duplicate node is no-op" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "First");
    try g.addNode(1, "Duplicate"); // Should be ignored

    try std.testing.expectEqual(@as(usize, 1), g.nodeCount());
    try std.testing.expectEqualStrings("First", g.nodeAt(0).?.label);
}

test "Graph: edge to missing node returns error" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Only");

    const result = g.addEdge(1, 999);
    try std.testing.expectError(error.NodeNotFound, result);
}
test "Graph: validate empty graph" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    var result = try g.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .empty);
    try std.testing.expect(g.isEmpty());
}

test "Graph: validate acyclic graph" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    var result = try g.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .ok);
    try std.testing.expect(!try g.hasCycle(allocator));
}

test "Graph: detect simple cycle" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C -> A (cycle)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1); // Creates cycle

    var result = try g.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .cycle);
    try std.testing.expect(try g.hasCycle(allocator));
}

test "Graph: addEdgeAutoCreate creates nodes" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // No explicit addNode - just add edges
    try g.addEdgeAutoCreate(1, 2);
    try g.addEdgeAutoCreate(2, 3);
    try g.addEdgeAutoCreate(1, 3);

    // Should have 3 nodes
    try std.testing.expectEqual(@as(usize, 3), g.nodeCount());

    // Labels should be the ID as a string
    const node1 = g.nodeById(1).?;
    const node2 = g.nodeById(2).?;
    const node3 = g.nodeById(3).?;

    try std.testing.expectEqualStrings("1", node1.label);
    try std.testing.expectEqualStrings("2", node2.label);
    try std.testing.expectEqualStrings("3", node3.label);

    // Edges should work
    try std.testing.expectEqual(@as(usize, 3), g.edges.items.len);
}

test "Graph: addEdgeAutoCreate with existing nodes" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Add one node explicitly
    try g.addNode(1, "Start");

    // Add edge with auto-create - node 1 exists, node 2 will be created
    try g.addEdgeAutoCreate(1, 2);

    try std.testing.expectEqual(@as(usize, 2), g.nodeCount());
    try std.testing.expectEqualStrings("Start", g.nodeById(1).?.label); // Kept original
    try std.testing.expectEqualStrings("2", g.nodeById(2).?.label); // Auto-created
}

test "Graph: detect self-loop" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addEdge(1, 1); // Self-loop

    var result = try g.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .cycle);
}

test "Graph: diamond is acyclic" {
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

    var result = try g.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .ok);
}
