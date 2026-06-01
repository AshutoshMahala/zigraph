//! Shared render helpers used by multiple renderers (SVG, Terminal, etc.).
//!
//! Functions here operate on renderer-agnostic IR types and have no
//! dependency on any specific output format.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../core/ir.zig");

/// Pre-compute nesting depths for all subgraphs in a single pass.
/// Returns an arena-allocated slice of depths indexed the same as the input.
/// O(S) total — builds id→index map, then resolves each chain with memoization.
pub fn computeSubgraphDepths(subgraphs: []const ir_mod.SubgraphInfo(usize), arena: Allocator) []const usize {
    if (subgraphs.len == 0) return &.{};

    const depths = arena.alloc(usize, subgraphs.len) catch return &.{};
    @memset(depths, std.math.maxInt(usize)); // sentinel for "not computed"

    // Build id → index map
    var id_map = std.AutoHashMapUnmanaged(usize, usize).empty;
    defer id_map.deinit(arena);
    for (subgraphs, 0..) |sg, i| {
        id_map.put(arena, sg.id, i) catch {};
    }

    for (subgraphs, 0..) |_, i| {
        _ = resolveDepth(subgraphs, depths, id_map, i);
    }
    return depths;
}

fn resolveDepth(
    subgraphs: []const ir_mod.SubgraphInfo(usize),
    depths: []usize,
    id_map: std.AutoHashMapUnmanaged(usize, usize),
    idx: usize,
) usize {
    if (depths[idx] != std.math.maxInt(usize)) return depths[idx];
    // Mark as in-progress (0) BEFORE recursing to break cycles.
    // If A→B→A, the second visit to A sees 0 instead of maxInt,
    // preventing infinite recursion.
    depths[idx] = 0;
    const parent_id = subgraphs[idx].parent_id orelse return 0;
    const parent_idx = id_map.get(parent_id) orelse return 0;
    depths[idx] = resolveDepth(subgraphs, depths, id_map, parent_idx) + 1;
    return depths[idx];
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "computeSubgraphDepths handles cyclic parent chains" {
    const SubgraphInfo = ir_mod.SubgraphInfo(usize);
    const subgraphs = [_]SubgraphInfo{
        .{ .id = 10, .parent_id = 20, .label = "A", .x = 0, .y = 0, .width = 0, .height = 0 },
        .{ .id = 20, .parent_id = 10, .label = "B", .x = 0, .y = 0, .width = 0, .height = 0 },
    };
    const depths = computeSubgraphDepths(&subgraphs, testing.allocator);
    defer testing.allocator.free(depths);
    try testing.expect(depths[0] < std.math.maxInt(usize));
    try testing.expect(depths[1] < std.math.maxInt(usize));
}

test "computeSubgraphDepths correct for linear chain" {
    const SubgraphInfo = ir_mod.SubgraphInfo(usize);
    const subgraphs = [_]SubgraphInfo{
        .{ .id = 1, .parent_id = null, .label = "root", .x = 0, .y = 0, .width = 0, .height = 0 },
        .{ .id = 2, .parent_id = 1, .label = "child", .x = 0, .y = 0, .width = 0, .height = 0 },
        .{ .id = 3, .parent_id = 2, .label = "grandchild", .x = 0, .y = 0, .width = 0, .height = 0 },
    };
    const depths = computeSubgraphDepths(&subgraphs, testing.allocator);
    defer testing.allocator.free(depths);
    try testing.expectEqual(@as(usize, 0), depths[0]);
    try testing.expectEqual(@as(usize, 1), depths[1]);
    try testing.expectEqual(@as(usize, 2), depths[2]);
}
