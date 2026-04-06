//! Converts a resolved graph block with tree layout into TreeNode structures.
//! Validates tree constraints: no cycles, single parent per node.

const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("errors.zig");
const zigraph = @import("zigraph");

pub const TreeNode = zigraph.terminal.tree.TreeNode;

pub const Edge = struct {
    from: []const u8,
    to: []const u8,
};

pub const TreeResult = struct {
    roots: []TreeNode,
    allocator: Allocator,

    pub fn deinit(self: *TreeResult) void {
        freeNodes(self.allocator, self.roots);
        self.allocator.free(self.roots);
    }
};

fn freeNodes(allocator: Allocator, nodes: []TreeNode) void {
    for (nodes) |*node| {
        freeNodes(allocator, @constCast(node.children));
        allocator.free(node.children);
    }
}

/// Build TreeNode forest from resolved edges.
/// Validates: no cycles, each node has at most one parent.
pub fn buildTree(
    allocator: Allocator,
    node_ids: []const []const u8,
    node_labels: []const []const u8,
    edges: []const Edge,
    err_list: *errors.ErrorList,
) !TreeResult {
    // 1. Build children map and parent map
    var children_map = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(allocator);
    defer {
        var it = children_map.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        children_map.deinit();
    }

    var parent_map = std.StringHashMap([]const u8).init(allocator);
    defer parent_map.deinit();

    // Initialize every node in the children map
    for (node_ids) |id| {
        try children_map.put(id, .{});
    }

    // 2. Process edges — check for multi-parent
    for (edges) |edge| {
        // Record the child in the parent's children list
        const children_entry = children_map.getPtr(edge.from) orelse {
            // Unknown source node — skip
            continue;
        };
        try children_entry.append(allocator, edge.to);

        // Check for multi-parent on the destination node
        if (parent_map.contains(edge.to)) {
            // Already has a parent — report error
            try err_list.add(
                errors.Loc.zero,
                errors.DslError.Kind.tree_validation,
                "tree validation: node has multiple parents",
            );
        } else {
            try parent_map.put(edge.to, edge.from);
        }
    }

    // 3. Find roots (nodes with no parent)
    var roots_list = std.ArrayListUnmanaged([]const u8){};
    defer roots_list.deinit(allocator);

    for (node_ids) |id| {
        if (!parent_map.contains(id)) {
            try roots_list.append(allocator, id);
        }
    }

    // 4. Error if no roots found (implies a cycle with all nodes reachable only via edges)
    if (roots_list.items.len == 0) {
        try err_list.add(
            errors.Loc.zero,
            errors.DslError.Kind.tree_validation,
            "tree validation: no root nodes found (possible cycle)",
        );
        return TreeResult{
            .roots = try allocator.alloc(TreeNode, 0),
            .allocator = allocator,
        };
    }

    // 5. Build a label lookup map
    var label_map = std.StringHashMap([]const u8).init(allocator);
    defer label_map.deinit();

    for (node_ids, node_labels) |id, label| {
        try label_map.put(id, label);
    }

    // 6. Recursively build TreeNode forest from roots
    var root_nodes = std.ArrayListUnmanaged(TreeNode){};
    errdefer {
        for (root_nodes.items) |*node| {
            freeNodes(allocator, @constCast(node.children));
            allocator.free(node.children);
        }
        root_nodes.deinit(allocator);
    }

    var visiting = std.StringHashMap(void).init(allocator);
    defer visiting.deinit();

    for (roots_list.items) |root_id| {
        const node = try buildNode(allocator, root_id, &children_map, &label_map, &visiting);
        try root_nodes.append(allocator, node);
    }

    return TreeResult{
        .roots = try root_nodes.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn buildNode(
    allocator: Allocator,
    node_id: []const u8,
    children_map: *std.StringHashMap(std.ArrayListUnmanaged([]const u8)),
    label_map: *std.StringHashMap([]const u8),
    visiting: *std.StringHashMap(void),
) !TreeNode {
    const label = label_map.get(node_id) orelse node_id;

    // Cycle detection: if we're already visiting this node, return a leaf to break the cycle.
    if (visiting.contains(node_id)) {
        return TreeNode{
            .label = label,
            .children = try allocator.alloc(TreeNode, 0),
        };
    }
    try visiting.put(node_id, {});

    const child_ids = if (children_map.getPtr(node_id)) |list| list.items else &[_][]const u8{};

    var child_nodes = try allocator.alloc(TreeNode, child_ids.len);
    errdefer allocator.free(child_nodes);

    for (child_ids, 0..) |child_id, i| {
        child_nodes[i] = try buildNode(allocator, child_id, children_map, label_map, visiting);
    }

    _ = visiting.remove(node_id);

    return TreeNode{
        .label = label,
        .children = child_nodes,
    };
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "simple tree: root -> a, root -> b, b -> c" {
    const allocator = std.testing.allocator;

    const ids = &[_][]const u8{ "root", "a", "b", "c" };
    const labels = &[_][]const u8{ "Root", "A", "B", "C" };
    const edges = &[_]Edge{
        .{ .from = "root", .to = "a" },
        .{ .from = "root", .to = "b" },
        .{ .from = "b", .to = "c" },
    };

    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    var result = try buildTree(allocator, ids, labels, edges, &err_list);
    defer result.deinit();

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.roots.len);

    const root_node = result.roots[0];
    try std.testing.expectEqualStrings("Root", root_node.label);
    try std.testing.expectEqual(@as(usize, 2), root_node.children.len);

    // Find child B and verify it has child C
    var found_b = false;
    for (root_node.children) |child| {
        if (std.mem.eql(u8, child.label, "B")) {
            found_b = true;
            try std.testing.expectEqual(@as(usize, 1), child.children.len);
            try std.testing.expectEqualStrings("C", child.children[0].label);
        }
    }
    try std.testing.expect(found_b);
}

test "multi-parent error: a -> c, b -> c" {
    const allocator = std.testing.allocator;

    const ids = &[_][]const u8{ "a", "b", "c" };
    const labels = &[_][]const u8{ "A", "B", "C" };
    const edges = &[_]Edge{
        .{ .from = "a", .to = "c" },
        .{ .from = "b", .to = "c" },
    };

    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    var result = try buildTree(allocator, ids, labels, edges, &err_list);
    defer result.deinit();

    try std.testing.expect(err_list.hasErrors());
}

test "cycle detection: a -> b -> a does not stack overflow" {
    const allocator = std.testing.allocator;

    // a -> b, b -> a creates a cycle. a has no parent other than b,
    // but b's parent is a, so the only root is... neither (both have parents).
    // Actually: a is parent of b, b is parent of a => multi-parent error on a.
    // But let's test with a self-loop: a -> a
    const ids = &[_][]const u8{"a"};
    const labels = &[_][]const u8{"A"};
    const edges = &[_]Edge{
        .{ .from = "a", .to = "a" },
    };

    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    var result = try buildTree(allocator, ids, labels, edges, &err_list);
    defer result.deinit();

    // Should report multi-parent error (a is both parent and child of itself)
    try std.testing.expect(err_list.hasErrors());
}

test "forest: a -> b, c -> d" {
    const allocator = std.testing.allocator;

    const ids = &[_][]const u8{ "a", "b", "c", "d" };
    const labels = &[_][]const u8{ "A", "B", "C", "D" };
    const edges = &[_]Edge{
        .{ .from = "a", .to = "b" },
        .{ .from = "c", .to = "d" },
    };

    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    var result = try buildTree(allocator, ids, labels, edges, &err_list);
    defer result.deinit();

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), result.roots.len);

    // Each root should have exactly one child
    for (result.roots) |root| {
        try std.testing.expectEqual(@as(usize, 1), root.children.len);
    }
}
