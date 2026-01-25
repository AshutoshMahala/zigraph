//! Graph Validation Algorithms
//!
//! Standalone validation operations that can be used independently
//! of the Graph type. Provides cycle detection and structural validation.
//!
//! ## Design Philosophy
//!
//! These algorithms operate on graph topology (adjacency lists) rather than
//! the Graph type directly, enabling use in different contexts like:
//! - Pre-layout validation
//! - Streaming edge processing
//! - Alternative graph representations
//!
//! ## Algorithm: Three-Color DFS
//!
//! Cycle detection uses depth-first search with three colors:
//! - WHITE (0): Unvisited
//! - GRAY (1): Currently in the DFS stack (part of current path)
//! - BLACK (2): Finished processing all descendants
//!
//! A back edge to a GRAY node indicates a cycle.
//!
//! ## Complexity
//!
//! - Time: O(V + E)
//! - Space: O(V) for color/parent arrays + O(V) stack
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("errors.zig");
pub const ValidationResult = errors.ValidationResult;
pub const CycleInfo = errors.CycleInfo;

/// Validate a graph represented by adjacency lists.
///
/// Parameters:
/// - `node_count`: Number of nodes in the graph
/// - `children`: For each node index, the indices of its children
/// - `parents`: For each node index, the indices of its parents (used for cycle reconstruction)
/// - `allocator`: Allocator for temporary and result allocations
///
/// Returns:
/// - `.ok` if the graph is valid (acyclic, non-empty)
/// - `.empty` if the graph has no nodes
/// - `.cycle` with path information if a cycle is detected
pub fn validate(
    node_count: usize,
    children: []const std.ArrayListUnmanaged(usize),
    parents: []const std.ArrayListUnmanaged(usize),
    allocator: Allocator,
) !ValidationResult {
    // Check for empty graph
    if (node_count == 0) {
        return .empty;
    }

    // Three-color DFS for cycle detection
    // WHITE (0) = unvisited, GRAY (1) = in progress, BLACK (2) = done
    var color = try allocator.alloc(u8, node_count);
    defer allocator.free(color);
    @memset(color, 0); // All WHITE

    var parent = try allocator.alloc(usize, node_count);
    defer allocator.free(parent);
    @memset(parent, std.math.maxInt(usize)); // No parent

    // DFS from each unvisited node
    for (0..node_count) |start| {
        if (color[start] != 0) continue; // Already visited

        // Explicit DFS stack
        var stack: std.ArrayListUnmanaged(usize) = .{};
        defer stack.deinit(allocator);
        try stack.append(allocator, start);

        while (stack.items.len > 0) {
            const current = stack.items[stack.items.len - 1];

            if (color[current] == 0) {
                // First visit - mark as in progress
                color[current] = 1; // GRAY
            } else if (color[current] == 1) {
                // Back from children - mark as done
                color[current] = 2; // BLACK
                _ = stack.pop();
                continue;
            } else {
                _ = stack.pop();
                continue;
            }

            // Visit children
            var all_children_done = true;
            for (children[current].items) |child| {
                if (color[child] == 1) {
                    // Found a back edge - cycle detected!
                    return try reconstructCycle(
                        child,
                        current,
                        color,
                        &stack,
                        parents,
                        allocator,
                    );
                } else if (color[child] == 0) {
                    // Unvisited - will visit
                    parent[child] = current;
                    try stack.append(allocator, child);
                    all_children_done = false;
                }
                // BLACK children are already done, skip
            }

            if (all_children_done) {
                color[current] = 2; // BLACK
                _ = stack.pop();
            }
        }
    }

    return .ok;
}

/// Reconstruct the cycle path for error reporting.
fn reconstructCycle(
    cycle_start: usize,
    cycle_end: usize,
    color: []const u8,
    stack: *const std.ArrayListUnmanaged(usize),
    parents: []const std.ArrayListUnmanaged(usize),
    allocator: Allocator,
) !ValidationResult {
    var cycle_path: std.ArrayListUnmanaged(usize) = .{};
    errdefer cycle_path.deinit(allocator);

    try cycle_path.append(allocator, cycle_start);
    var node = cycle_end;

    while (node != cycle_start and node != std.math.maxInt(usize)) {
        try cycle_path.append(allocator, node);
        // Walk up through the stack to find the path
        var found_parent = false;
        for (stack.items) |s| {
            if (s == node) {
                // Find who put us on the stack
                for (parents[node].items) |p| {
                    if (color[p] == 1) { // GRAY = in current path
                        node = p;
                        found_parent = true;
                        break;
                    }
                }
                break;
            }
        }
        if (!found_parent) break;
    }
    try cycle_path.append(allocator, cycle_start); // Complete the cycle

    // Reverse to get the correct order
    std.mem.reverse(usize, cycle_path.items);

    return .{ .cycle = .{
        .path = try cycle_path.toOwnedSlice(allocator),
        .allocator = allocator,
    } };
}

/// Quick check for cycles without path reconstruction.
///
/// More efficient when you only need a boolean result.
/// Use `validate()` for detailed cycle information.
pub fn hasCycle(
    node_count: usize,
    children: []const std.ArrayListUnmanaged(usize),
    allocator: Allocator,
) !bool {
    if (node_count == 0) {
        return false;
    }

    var color = try allocator.alloc(u8, node_count);
    defer allocator.free(color);
    @memset(color, 0);

    // Simplified DFS - just detect, don't track path
    for (0..node_count) |start| {
        if (color[start] != 0) continue;

        var stack: std.ArrayListUnmanaged(usize) = .{};
        defer stack.deinit(allocator);
        try stack.append(allocator, start);

        while (stack.items.len > 0) {
            const current = stack.items[stack.items.len - 1];

            if (color[current] == 0) {
                color[current] = 1;
            } else if (color[current] == 1) {
                color[current] = 2;
                _ = stack.pop();
                continue;
            } else {
                _ = stack.pop();
                continue;
            }

            var all_done = true;
            for (children[current].items) |child| {
                if (color[child] == 1) {
                    return true; // Cycle found
                } else if (color[child] == 0) {
                    try stack.append(allocator, child);
                    all_done = false;
                }
            }

            if (all_done) {
                color[current] = 2;
                _ = stack.pop();
            }
        }
    }

    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "validate: empty graph" {
    const allocator = std.testing.allocator;
    const empty: []const std.ArrayListUnmanaged(usize) = &.{};
    var result = try validate(0, empty, empty, allocator);
    defer result.deinit();
    try std.testing.expect(result == .empty);
}

test "validate: single node" {
    const allocator = std.testing.allocator;

    var children = [_]std.ArrayListUnmanaged(usize){.{}};
    var parents = [_]std.ArrayListUnmanaged(usize){.{}};

    var result = try validate(1, &children, &parents, allocator);
    defer result.deinit();
    try std.testing.expect(result == .ok);
}

test "validate: simple chain" {
    const allocator = std.testing.allocator;

    // A -> B -> C
    var child0: std.ArrayListUnmanaged(usize) = .{};
    defer child0.deinit(allocator);
    try child0.append(allocator, 1);

    var child1: std.ArrayListUnmanaged(usize) = .{};
    defer child1.deinit(allocator);
    try child1.append(allocator, 2);

    const child2: std.ArrayListUnmanaged(usize) = .{};

    const parent0: std.ArrayListUnmanaged(usize) = .{};
    var parent1: std.ArrayListUnmanaged(usize) = .{};
    defer parent1.deinit(allocator);
    try parent1.append(allocator, 0);

    var parent2: std.ArrayListUnmanaged(usize) = .{};
    defer parent2.deinit(allocator);
    try parent2.append(allocator, 1);

    const children = [_]std.ArrayListUnmanaged(usize){ child0, child1, child2 };
    const parents_arr = [_]std.ArrayListUnmanaged(usize){ parent0, parent1, parent2 };

    var result = try validate(3, &children, &parents_arr, allocator);
    defer result.deinit();
    try std.testing.expect(result == .ok);
}

test "validate: self-loop" {
    const allocator = std.testing.allocator;

    // A -> A
    var child0: std.ArrayListUnmanaged(usize) = .{};
    defer child0.deinit(allocator);
    try child0.append(allocator, 0);

    var parent0: std.ArrayListUnmanaged(usize) = .{};
    defer parent0.deinit(allocator);
    try parent0.append(allocator, 0);

    const children = [_]std.ArrayListUnmanaged(usize){child0};
    const parents_arr = [_]std.ArrayListUnmanaged(usize){parent0};

    var result = try validate(1, &children, &parents_arr, allocator);
    defer result.deinit();
    try std.testing.expect(result == .cycle);
}

test "validate: triangle cycle" {
    const allocator = std.testing.allocator;

    // A -> B -> C -> A
    var child0: std.ArrayListUnmanaged(usize) = .{};
    defer child0.deinit(allocator);
    try child0.append(allocator, 1);

    var child1: std.ArrayListUnmanaged(usize) = .{};
    defer child1.deinit(allocator);
    try child1.append(allocator, 2);

    var child2: std.ArrayListUnmanaged(usize) = .{};
    defer child2.deinit(allocator);
    try child2.append(allocator, 0);

    var parent0: std.ArrayListUnmanaged(usize) = .{};
    defer parent0.deinit(allocator);
    try parent0.append(allocator, 2);

    var parent1: std.ArrayListUnmanaged(usize) = .{};
    defer parent1.deinit(allocator);
    try parent1.append(allocator, 0);

    var parent2: std.ArrayListUnmanaged(usize) = .{};
    defer parent2.deinit(allocator);
    try parent2.append(allocator, 1);

    const children = [_]std.ArrayListUnmanaged(usize){ child0, child1, child2 };
    const parents_arr = [_]std.ArrayListUnmanaged(usize){ parent0, parent1, parent2 };

    var result = try validate(3, &children, &parents_arr, allocator);
    defer result.deinit();
    try std.testing.expect(result == .cycle);
}

test "hasCycle: quick check" {
    const allocator = std.testing.allocator;

    // A -> B (no cycle)
    var child0: std.ArrayListUnmanaged(usize) = .{};
    defer child0.deinit(allocator);
    try child0.append(allocator, 1);

    var child1: std.ArrayListUnmanaged(usize) = .{};

    const children = [_]std.ArrayListUnmanaged(usize){ child0, child1 };

    try std.testing.expect(!try hasCycle(2, &children, allocator));

    // Now add cycle: B -> A
    try child1.append(allocator, 0);
    const children_cycle = [_]std.ArrayListUnmanaged(usize){ child0, child1 };
    defer child1.deinit(allocator);

    try std.testing.expect(try hasCycle(2, &children_cycle, allocator));
}
