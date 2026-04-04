//! Subgraph-aware orchestration for Sugiyama layout
//!
//! Provides constraint enforcement for subgraph-grouped layouts.

// Re-export submodules for public API
pub const common = @import("subgraph/common.zig");
pub const crossing = @import("subgraph/crossing.zig");
pub const contiguous = @import("subgraph/contiguous.zig");
pub const padding = @import("subgraph/padding.zig");
pub const bbox = @import("subgraph/bbox.zig");
pub const overlap = @import("subgraph/overlap.zig");
pub const compact = @import("subgraph/compact.zig");

// Re-export public symbols at top level for backward compatibility
pub const default_padding = common.default_padding;
pub const vnodeSubgraph = common.vnodeSubgraph;
pub const blockBasedCrossingReduction = crossing.blockBasedCrossingReduction;
pub const blockOrderLevel = crossing.blockOrderLevel;
pub const enforceSubgraphAdjacency = crossing.enforceSubgraphAdjacency;
pub const enforceContiguousLevels = contiguous.enforceContiguousLevels;
pub const promoteSubgraphRoots = contiguous.promoteSubgraphRoots;
pub const applySubgraphPadding = padding.applySubgraphPadding;
pub const computeLevelYOffsets = padding.computeLevelYOffsets;
pub const computeBoundingBoxes = bbox.computeBoundingBoxes;
pub const fixSubgraphOverlaps = overlap.fixSubgraphOverlaps;
pub const refineAndCompact = compact.refineAndCompact;

// Pull in tests from all submodules
test {
    _ = common;
    _ = crossing;
    _ = contiguous;
    _ = padding;
    _ = bbox;
    _ = overlap;
    _ = compact;
}
