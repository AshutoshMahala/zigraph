//! Force Components
//!
//! Reusable force primitives for force-directed graph layouts.
//! These can be composed by different algorithms:
//!
//! - **repulsion**: Coulomb-like repulsion between all node pairs
//! - **attraction**: Spring-like attraction along edges
//! - **gravity**: Pull toward center to prevent drift
//!
//! All forces operate on Q16.16 fixed-point SoA position arrays
//! (`xs`/`ys`) and force accumulators (`fxs`/`fys`). The hot-path kernels
//! (`accumulate*`) are gather-only and range-parameterized — see
//! docs/passive-parallelism.md. Cohesion/separation are serial phases.

pub const repulsion = @import("repulsion.zig");
pub const attraction = @import("attraction.zig");
pub const gravity = @import("gravity.zig");
pub const cohesion = @import("cohesion.zig");

// Re-export common force functions for convenience
pub const accumulatePairwiseRepulsion = repulsion.accumulatePairwise;
pub const accumulateBarnesHutRepulsion = repulsion.accumulateBarnesHut;
pub const accumulateAttraction = attraction.accumulateEdges;
pub const accumulateGravity = gravity.accumulateToCenter;
pub const accumulateStrongGravity = gravity.accumulateStrongGravity;
pub const computeCentroid = gravity.computeCentroid;
pub const applyCohesion = cohesion.applyCohesion;
pub const applySeparation = cohesion.applySeparation;
pub const SubgraphIndex = cohesion.SubgraphIndex;

test {
    _ = repulsion;
    _ = attraction;
    _ = gravity;
    _ = cohesion;
}
