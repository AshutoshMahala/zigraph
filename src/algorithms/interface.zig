//! Layout Algorithm Interface
//!
//! Defines the contract for pluggable layout algorithms (BYOA pattern).
//! Custom algorithms can implement this interface to be used with zigraph's
//! rendering and conversion utilities.
//!
//! ## Implementing a Custom Algorithm
//!
//! ```zig
//! const MyAlgorithm = struct {
//!     pub const Config = struct {
//!         // Your configuration fields
//!     };
//!
//!     pub fn compute(
//!         g: *const Graph,
//!         allocator: Allocator,
//!         config: Config,
//!     ) !LayoutResult {
//!         // Your implementation
//!     }
//! };
//!
//! // Verify interface compliance at comptime
//! comptime {
//!     interface.assertValidAlgorithm(MyAlgorithm);
//! }
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Graph = @import("../core/graph.zig").Graph;
const fp = @import("shared/fixed_point.zig");
const Vec2 = fp.Vec2;

// ============================================================================
// Result Types
// ============================================================================

/// Standard result type for force-directed algorithms.
/// Contains Q16.16 fixed-point positions.
pub const LayoutResult = @import("shared/common.zig").PositionResult;

// ============================================================================
// Interface Validation
// ============================================================================

/// Compile-time check that an algorithm type conforms to the interface.
///
/// Requirements:
/// - Must have a `Config` type
/// - Must have a `compute(g: *const Graph, allocator: Allocator, config: Config) !LayoutResult` function
///
/// Example:
/// ```zig
/// comptime {
///     interface.assertValidAlgorithm(@import("my_algorithm.zig"));
/// }
/// ```
pub fn assertValidAlgorithm(comptime T: type) void {
    // Check for Config type
    if (!@hasDecl(T, "Config")) {
        @compileError("Layout algorithm must have a 'Config' type");
    }

    // Check for compute function
    if (!@hasDecl(T, "compute")) {
        @compileError("Layout algorithm must have a 'compute' function");
    }

    // Verify compute signature
    const compute_info = @typeInfo(@TypeOf(T.compute));
    if (compute_info != .@"fn") {
        @compileError("'compute' must be a function");
    }

    const func = compute_info.@"fn";
    if (func.params.len != 3) {
        @compileError("'compute' must take exactly 3 parameters: (graph, allocator, config)");
    }

    // Parameter 1: *const Graph
    if (func.params[0].type != *const Graph) {
        @compileError("'compute' parameter 1 must be '*const Graph'");
    }

    // Parameter 2: Allocator
    if (func.params[1].type != Allocator) {
        @compileError("'compute' parameter 2 must be 'Allocator'");
    }

    // Parameter 3: Config type
    if (func.params[2].type != T.Config) {
        @compileError("'compute' parameter 3 must be the algorithm's 'Config' type");
    }

    // Return type: !LayoutResult
    const return_info = @typeInfo(func.return_type.?);
    if (return_info != .error_union) {
        @compileError("'compute' must return '!LayoutResult'");
    }
    if (return_info.error_union.payload != LayoutResult) {
        @compileError("'compute' must return '!LayoutResult', got different payload type");
    }
}

/// Check if a type implements the layout algorithm interface.
/// Returns true if valid, false otherwise (doesn't cause compile error).
pub fn isValidAlgorithm(comptime T: type) bool {
    if (!@hasDecl(T, "Config")) return false;
    if (!@hasDecl(T, "compute")) return false;

    const compute_info = @typeInfo(@TypeOf(T.compute));
    if (compute_info != .@"fn") return false;

    const func = compute_info.@"fn";
    if (func.params.len != 3) return false;
    if (func.params[0].type != *const Graph) return false;
    if (func.params[1].type != Allocator) return false;
    if (func.params[2].type != T.Config) return false;

    const return_info = @typeInfo(func.return_type.?);
    if (return_info != .error_union) return false;
    if (return_info.error_union.payload != LayoutResult) return false;

    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "interface: valid algorithm passes check" {
    const ValidAlgorithm = struct {
        pub const Config = struct {
            iterations: u32 = 100,
        };

        pub fn compute(
            _: *const Graph,
            allocator: Allocator,
            _: Config,
        ) !LayoutResult {
            return LayoutResult{
                .positions = try allocator.alloc(Vec2, 0),
                .width = 0,
                .height = 0,
                .iterations = 0,
                .allocator = allocator,
            };
        }
    };

    // Should compile without error
    comptime {
        assertValidAlgorithm(ValidAlgorithm);
    }

    try std.testing.expect(isValidAlgorithm(ValidAlgorithm));
}

test "interface: isValidAlgorithm returns false for invalid types" {
    const NoConfig = struct {
        pub fn compute() void {}
    };

    const NoCompute = struct {
        pub const Config = struct {};
    };

    try std.testing.expect(!isValidAlgorithm(NoConfig));
    try std.testing.expect(!isValidAlgorithm(NoCompute));
    try std.testing.expect(!isValidAlgorithm(u32));
}

test "interface: fruchterman_reingold passes validation" {
    const fr = @import("fruchterman_reingold/mod.zig");
    comptime {
        assertValidAlgorithm(fr);
    }
    try std.testing.expect(isValidAlgorithm(fr));
}
