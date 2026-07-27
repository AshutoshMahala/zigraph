//! Graph Validation Algorithms
//!
//! Standalone validation operations that can be used independently
//! of the Graph type. Provides cycle detection and structural validation.
//!
//! ## Design Philosophy
//!
//! These algorithms operate on frozen CSR adjacency (`core/csr.zig`) rather
//! than the Graph type directly, enabling use in different contexts like:
//! - Pre-layout validation
//! - Alternative graph representations
//! - Concurrent validation of independent graphs (CSR views are immutable)
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
const NodeIndex = @import("index.zig").NodeIndex;
const csr = @import("csr.zig");
pub const Csr = csr.Csr;
pub const ValidationResult = errors.ValidationResult;
pub const CycleInfo = errors.CycleInfo;
pub const ValidationFailures = errors.ValidationFailures;
pub const Requirements = errors.Requirements;
pub const GraphProperties = errors.GraphProperties;

/// Validate a graph represented by frozen CSR adjacency.
///
/// Parameters:
/// - `node_count`: Number of nodes in the graph
/// - `out`: Child adjacency (this → child), used for traversal
/// - `in`: Parent adjacency (parent → this), used for cycle reconstruction
/// - `allocator`: Allocator for temporary and result allocations
///
/// Returns:
/// - `.ok` if the graph is valid (acyclic, non-empty)
/// - `.empty` if the graph has no nodes
/// - `.cycle` with path information if a cycle is detected
pub fn validate(
    node_count: usize,
    out: *const Csr,
    in: *const Csr,
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
        var stack: std.ArrayListUnmanaged(usize) = .empty;
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
            for (out.neighbors(current)) |child| {
                if (color[child] == 1) {
                    // Found a back edge - cycle detected!
                    return try reconstructCycle(
                        child,
                        current,
                        color,
                        &stack,
                        in,
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
    in: *const Csr,
    allocator: Allocator,
) !ValidationResult {
    var cycle_path: std.ArrayListUnmanaged(usize) = .empty;
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
                for (in.neighbors(node)) |p| {
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
    out: *const Csr,
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

        var stack: std.ArrayListUnmanaged(usize) = .empty;
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
            for (out.neighbors(current)) |child| {
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

/// Count connected components using union-find.
/// Treats graph as undirected for connectivity check.
pub fn countComponents(
    node_count: usize,
    out: *const Csr,
    in: *const Csr,
    allocator: Allocator,
) !usize {
    if (node_count == 0) return 0;
    if (node_count == 1) return 1;

    // Union-Find with path compression
    var parent_arr = try allocator.alloc(usize, node_count);
    defer allocator.free(parent_arr);

    // Initialize each node as its own parent
    for (0..node_count) |i| {
        parent_arr[i] = i;
    }

    // Find with path compression
    const find = struct {
        fn f(x: usize, parent: []usize) usize {
            if (parent[x] != x) {
                parent[x] = f(parent[x], parent);
            }
            return parent[x];
        }
    }.f;

    // Union edges (treat as undirected)
    for (0..node_count) |i| {
        for (out.neighbors(i)) |j| {
            const root_i = find(i, parent_arr);
            const root_j = find(j, parent_arr);
            if (root_i != root_j) {
                parent_arr[root_i] = root_j;
            }
        }
        for (in.neighbors(i)) |j| {
            const root_i = find(i, parent_arr);
            const root_j = find(j, parent_arr);
            if (root_i != root_j) {
                parent_arr[root_i] = root_j;
            }
        }
    }

    // Count unique roots
    var component_count: usize = 0;
    for (0..node_count) |i| {
        if (find(i, parent_arr) == i) {
            component_count += 1;
        }
    }

    return component_count;
}

/// Compute all graph properties at once for validation.
///
/// This gathers: node count, edge counts (directed/undirected), cycle
/// detection, and component count into a single struct that can be checked
/// against Requirements.
pub fn computeProperties(
    node_count: usize,
    out: *const Csr,
    in: *const Csr,
    allocator: Allocator,
) !GraphProperties {
    // Each edge appears exactly once in the out direction.
    const directed_count = out.targets.len;

    // Check for cycles
    const has_cycle = try hasCycle(node_count, out, allocator);

    // Count components
    const components = try countComponents(node_count, out, in, allocator);

    return GraphProperties{
        .node_count = node_count,
        .directed_edge_count = directed_count,
        .undirected_edge_count = 0, // TODO: Support mixed graphs when edge metadata is available
        .has_cycle = has_cycle,
        .component_count = components,
    };
}

/// Check graph against requirements and return all failures.
///
/// Convenience function that computes properties and checks requirements in one call.
pub fn checkRequirements(
    node_count: usize,
    out: *const Csr,
    in: *const Csr,
    requirements: Requirements,
    allocator: Allocator,
) !ValidationFailures {
    const props = try computeProperties(node_count, out, in, allocator);
    return props.checkRequirements(requirements);
}

// ============================================================================
// Tests
// ============================================================================

const FrozenGraph = csr.FrozenGraph;

test "validate: empty graph" {
    const allocator = std.testing.allocator;
    var fg = try FrozenGraph.build(allocator, 0, &.{});
    defer fg.deinit();
    var result = try validate(0, &fg.out, &fg.in, allocator);
    defer result.deinit();
    try std.testing.expect(result == .empty);
}

test "validate: single node" {
    const allocator = std.testing.allocator;
    var fg = try FrozenGraph.build(allocator, 1, &.{});
    defer fg.deinit();
    var result = try validate(1, &fg.out, &fg.in, allocator);
    defer result.deinit();
    try std.testing.expect(result == .ok);
}

test "validate: simple chain" {
    const allocator = std.testing.allocator;
    // A -> B -> C
    var fg = try FrozenGraph.build(allocator, 3, &.{ .{ 0, 1 }, .{ 1, 2 } });
    defer fg.deinit();
    var result = try validate(3, &fg.out, &fg.in, allocator);
    defer result.deinit();
    try std.testing.expect(result == .ok);
}

test "validate: self-loop" {
    const allocator = std.testing.allocator;
    // A -> A
    var fg = try FrozenGraph.build(allocator, 1, &.{.{ 0, 0 }});
    defer fg.deinit();
    var result = try validate(1, &fg.out, &fg.in, allocator);
    defer result.deinit();
    try std.testing.expect(result == .cycle);
}

test "validate: triangle cycle" {
    const allocator = std.testing.allocator;
    // A -> B -> C -> A
    var fg = try FrozenGraph.build(allocator, 3, &.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 0 } });
    defer fg.deinit();
    var result = try validate(3, &fg.out, &fg.in, allocator);
    defer result.deinit();
    try std.testing.expect(result == .cycle);
}

test "hasCycle: quick check" {
    const allocator = std.testing.allocator;

    // A -> B (no cycle)
    var acyclic = try FrozenGraph.build(allocator, 2, &.{.{ 0, 1 }});
    defer acyclic.deinit();
    try std.testing.expect(!try hasCycle(2, &acyclic.out, allocator));

    // A -> B, B -> A (cycle)
    var cyclic = try FrozenGraph.build(allocator, 2, &.{ .{ 0, 1 }, .{ 1, 0 } });
    defer cyclic.deinit();
    try std.testing.expect(try hasCycle(2, &cyclic.out, allocator));
}

test "countComponents: empty graph" {
    const allocator = std.testing.allocator;
    var fg = try FrozenGraph.build(allocator, 0, &.{});
    defer fg.deinit();
    const count = try countComponents(0, &fg.out, &fg.in, allocator);
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "countComponents: single node" {
    const allocator = std.testing.allocator;
    var fg = try FrozenGraph.build(allocator, 1, &.{});
    defer fg.deinit();
    const count = try countComponents(1, &fg.out, &fg.in, allocator);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "countComponents: connected chain" {
    const allocator = std.testing.allocator;
    // A -> B -> C (all connected)
    var fg = try FrozenGraph.build(allocator, 3, &.{ .{ 0, 1 }, .{ 1, 2 } });
    defer fg.deinit();
    const count = try countComponents(3, &fg.out, &fg.in, allocator);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "countComponents: disconnected" {
    const allocator = std.testing.allocator;
    // A -> B, C (isolated) - two components
    var fg = try FrozenGraph.build(allocator, 3, &.{.{ 0, 1 }});
    defer fg.deinit();
    const count = try countComponents(3, &fg.out, &fg.in, allocator);
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "computeProperties: basic dag" {
    const allocator = std.testing.allocator;
    // A -> B -> C
    var fg = try FrozenGraph.build(allocator, 3, &.{ .{ 0, 1 }, .{ 1, 2 } });
    defer fg.deinit();

    const props = try computeProperties(3, &fg.out, &fg.in, allocator);

    try std.testing.expectEqual(@as(usize, 3), props.node_count);
    try std.testing.expectEqual(@as(usize, 2), props.directed_edge_count);
    try std.testing.expectEqual(@as(usize, 0), props.undirected_edge_count);
    try std.testing.expect(!props.has_cycle);
    try std.testing.expectEqual(@as(usize, 1), props.component_count);
    try std.testing.expect(props.isAllDirected());
    try std.testing.expect(props.isConnected());
}

test "checkRequirements: sugiyama validation" {
    const allocator = std.testing.allocator;
    // Valid DAG: A -> B -> C
    var fg = try FrozenGraph.build(allocator, 3, &.{ .{ 0, 1 }, .{ 1, 2 } });
    defer fg.deinit();

    const failures = try checkRequirements(3, &fg.out, &fg.in, Requirements.sugiyama, allocator);
    try std.testing.expect(failures.isOk());
}

test "checkRequirements: empty graph fails sugiyama" {
    const allocator = std.testing.allocator;
    var fg = try FrozenGraph.build(allocator, 0, &.{});
    defer fg.deinit();

    const failures = try checkRequirements(0, &fg.out, &fg.in, Requirements.sugiyama, allocator);
    try std.testing.expect(!failures.isOk());
    try std.testing.expect(failures.empty);
    try std.testing.expectEqual(@as(u8, 1), failures.count());
}
