//! Force Components
//!
//! Reusable force primitives for force-directed graph layouts.
//! These can be composed by different algorithms:
//!
//! - **repulsion**: Coulomb-like repulsion between all node pairs
//! - **attraction**: Spring-like attraction along edges
//! - **gravity**: Pull toward center to prevent drift
//!
//! All forces operate on Q16.16 fixed-point Vec2 positions and accumulators.

pub const repulsion = @import("repulsion.zig");
pub const attraction = @import("attraction.zig");
pub const gravity = @import("gravity.zig");

// Re-export common force functions for convenience
pub const applyPairwiseRepulsion = repulsion.applyPairwise;
pub const applyBarnesHutRepulsion = repulsion.applyBarnesHut;
pub const applyAttraction = attraction.applyBetween;
pub const applyAttractionLinLog = attraction.applyBetweenLinLog;
pub const applyGravity = gravity.applyToCenter;
pub const applyStrongGravity = gravity.applyStrongGravity;
pub const computeCentroid = gravity.computeCentroid;

test {
    _ = repulsion;
    _ = attraction;
    _ = gravity;
}
