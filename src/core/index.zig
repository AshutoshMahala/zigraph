//! Internal index type for dense node/edge structures.
//!
//! A neutral leaf module so that `graph.zig`, `validation.zig`, and the CSR
//! module (Stage C) can share the index type without depending on each other.

const std = @import("std");

/// Internal dense node index type.
///
/// Node *IDs* (user-supplied, arbitrary) are `usize`; internal *indices*
/// (dense 0..n positions in the node array, adjacency lists, and — from the
/// CSR freeze onward — all pipeline structures) are `NodeIndex`. 32-bit
/// indices halve adjacency memory and double per-cache-line index density,
/// which is what the SoA/SIMD pipeline and caller-side parallelism scale on.
pub const NodeIndex = u32;

/// Maximum number of indexable nodes (or edges): counts up to this value
/// are representable, giving valid indices `0..index_capacity-1`. The value
/// `index_capacity` itself is never a valid index — it is reserved as
/// `nil_index`. Configured caps are clamped to this at runtime
/// (`0` = unlimited still means "limited by index width").
pub const index_capacity: usize = std.math.maxInt(NodeIndex);

/// Sentinel for "no node" in NodeIndex-typed storage (replaces ?usize
/// optionals in index-dense structures; 4 bytes instead of 16). Equal to
/// `index_capacity`, which the insertion cap guards keep unreachable as a
/// real index — see `Graph.effectiveMaxNodes()`.
pub const nil_index: NodeIndex = std.math.maxInt(NodeIndex);

test "sentinel and capacity relationship" {
    // A full graph (count == index_capacity) has max valid index
    // index_capacity - 1, so nil_index can never collide with a real node.
    comptime std.debug.assert(@as(usize, nil_index) == index_capacity);
    comptime std.debug.assert(index_capacity - 1 < nil_index);
    comptime std.debug.assert(@TypeOf(nil_index) == NodeIndex);
}
