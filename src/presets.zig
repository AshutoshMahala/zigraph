//! Curated layout presets for common use cases.
//!
//! Presets provide sensible defaults for different quality/speed trade-offs.
//! Each preset returns a `LayoutConfig` that can be passed directly to `layout()`.
//!
//! ## Quick Start
//!
//! ```zig
//! const zigraph = @import("zigraph");
//!
//! // Use a preset
//! const ir = try zigraph.layout(&graph, allocator, zigraph.presets.sugiyama.standard());
//!
//! // Or for force-directed
//! const ir = try zigraph.layout(&graph, allocator, zigraph.presets.fdg.fast());
//! ```
//!
//! ## Available Presets
//!
//! ### Sugiyama (Hierarchical)
//! - `sugiyama.standard()` - Balanced quality/speed (default)
//! - `sugiyama.fast()` - Fastest, acceptable quality
//! - `sugiyama.quality()` - Best quality, slower
//!
//! ### Force-Directed
//! - `fdg.standard()` - Fruchterman-Reingold O(N²) exact
//! - `fdg.fast()` - Barnes-Hut O(N log N) approximation

const root = @import("root.zig");
const LayoutConfig = root.LayoutConfig;
const Algorithm = root.Algorithm;
const Layering = root.Layering;
const Positioning = root.Positioning;
const Routing = root.Routing;
const crossing = root.crossing;
const fdg = root.fdg;
const errors = @import("core/errors.zig");
const Requirements = errors.Requirements;

/// Preset metadata - configuration plus validation requirements.
pub const Preset = struct {
    /// The layout configuration
    config: LayoutConfig,
    /// Requirements that must be met for this preset
    requirements: Requirements,
    /// Human-readable name
    name: []const u8,
};

/// Sugiyama hierarchical layout presets.
///
/// Sugiyama layouts are best for directed acyclic graphs (DAGs) where
/// you want to show hierarchy or flow direction.
pub const sugiyama = struct {
    /// Standard preset: balanced quality and speed.
    ///
    /// - Layering: longest_path (fast, good results)
    /// - Crossing: balanced (median + adjacent exchange, 4 iterations)
    /// - Positioning: compact (left-to-right packing, no collisions)
    /// - Routing: direct (Manhattan routing)
    ///
    /// Requirements: non_empty, acyclic, all_directed
    pub fn standard() LayoutConfig {
        return .{
            .algorithm = .sugiyama,
            .layering = .longest_path,
            .crossing_reducers = &crossing.balanced,
            .positioning = .compact,
            .routing = .direct,
        };
    }

    /// Fast preset: prioritize speed over quality.
    ///
    /// - Layering: longest_path (fast)
    /// - Crossing: fast (single median pass)
    /// - Positioning: compact (fastest, no collisions)
    /// - Routing: direct
    ///
    /// Requirements: non_empty, acyclic, all_directed
    pub fn fast() LayoutConfig {
        return .{
            .algorithm = .sugiyama,
            .layering = .longest_path,
            .crossing_reducers = &crossing.fast,
            .positioning = .compact,
            .routing = .direct,
        };
    }

    /// Quality preset: best visual quality, slower.
    ///
    /// - Layering: network_simplex_fast (minimizes edge span)
    /// - Crossing: quality (more iterations for fewer crossings)
    /// - Positioning: compact (TODO: brandes_kopf for best quality)
    /// - Routing: spline (smooth bezier curves)
    ///
    /// Requirements: non_empty, acyclic, all_directed
    pub fn quality() LayoutConfig {
        return .{
            .algorithm = .sugiyama,
            .layering = .network_simplex_fast,
            .crossing_reducers = &crossing.quality,
            .positioning = .compact, // TODO: .brandes_kopf for best quality
            .routing = .spline,
        };
    }

    /// Get preset with full metadata including requirements.
    pub fn preset(which: enum { standard, fast, quality }) Preset {
        const config = switch (which) {
            .standard => standard(),
            .fast => fast(),
            .quality => quality(),
        };
        return .{
            .config = config,
            .requirements = Requirements.sugiyama,
            .name = switch (which) {
                .standard => "sugiyama.standard",
                .fast => "sugiyama.fast",
                .quality => "sugiyama.quality",
            },
        };
    }
};

/// Force-directed layout presets.
///
/// Force-directed layouts work for any graph (directed, undirected, cyclic).
/// They simulate physical forces to find aesthetically pleasing arrangements.
pub const fdg_presets = struct {
    /// Standard preset: Fruchterman-Reingold with exact O(N²) forces.
    ///
    /// Good for graphs up to ~500 nodes. Uses default parameters:
    /// - 300 iterations
    /// - Automatic area calculation
    /// - Direct edge routing
    ///
    /// Requirements: non_empty
    pub fn standard() LayoutConfig {
        return .{
            .algorithm = .{ .fruchterman_reingold = .{} },
            .routing = .direct,
        };
    }

    /// Fast preset: Fruchterman-Reingold with Barnes-Hut O(N log N) approximation.
    ///
    /// Good for larger graphs (500-10000 nodes). Uses:
    /// - 100 iterations (faster convergence with BH)
    /// - Barnes-Hut theta = 0.5 (balance accuracy/speed)
    /// - Direct edge routing
    ///
    /// Requirements: non_empty
    pub fn fast() LayoutConfig {
        return .{
            .algorithm = .{
                .fruchterman_reingold_fast = .{
                    .convergence = .{ .max_iterations = 100 },
                },
            },
            .routing = .direct,
        };
    }

    /// Get preset with full metadata including requirements.
    pub fn preset(which: enum { standard, fast }) Preset {
        const config = switch (which) {
            .standard => standard(),
            .fast => fast(),
        };
        return .{
            .config = config,
            .requirements = Requirements.force_directed,
            .name = switch (which) {
                .standard => "fdg.standard",
                .fast => "fdg.fast",
            },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "sugiyama.standard returns valid config" {
    const config = sugiyama.standard();
    try std.testing.expect(config.algorithm == .sugiyama);
    try std.testing.expect(config.layering == .longest_path);
    try std.testing.expect(config.positioning == .compact);
    try std.testing.expect(config.routing == .direct);
}

test "sugiyama.fast uses fast crossing" {
    const config = sugiyama.fast();
    // Fast preset uses single median pass (1 reducer)
    try std.testing.expectEqual(@as(usize, 1), config.crossing_reducers.len);
}

test "sugiyama.quality uses network simplex and spline" {
    const config = sugiyama.quality();
    try std.testing.expect(config.layering == .network_simplex_fast);
    try std.testing.expect(config.routing == .spline);
}

test "fdg.standard uses exact FR" {
    const config = fdg_presets.standard();
    try std.testing.expect(config.algorithm == .fruchterman_reingold);
}

test "fdg.fast uses Barnes-Hut FR" {
    const config = fdg_presets.fast();
    try std.testing.expect(config.algorithm == .fruchterman_reingold_fast);
}

test "preset metadata includes requirements" {
    const sug_preset = sugiyama.preset(.standard);
    try std.testing.expect(sug_preset.requirements.non_empty);
    try std.testing.expect(sug_preset.requirements.acyclic);
    try std.testing.expect(sug_preset.requirements.all_directed);
    try std.testing.expectEqualStrings("sugiyama.standard", sug_preset.name);

    const fdg_preset = fdg_presets.preset(.fast);
    try std.testing.expect(fdg_preset.requirements.non_empty);
    try std.testing.expect(!fdg_preset.requirements.acyclic);
    try std.testing.expectEqualStrings("fdg.fast", fdg_preset.name);
}
