//! WDP Level 0 Error Types for zigraph
//!
//! Waddling Diagnostic Protocol (WDP) compliant error codes.
//! Format: Severity.Component.Primary.Sequence
//!
//! Namespace: zigraph
//! Conformance: Level 0 (structured codes, no hashing)
//!
//! Components:
//!   - Graph: Graph structure operations
//!   - Layout: Layout algorithm operations
//!
//! Primaries:
//!   - Node: Node-related issues
//!   - Edge: Edge-related issues
//!   - Dag: DAG validation (acyclicity)
//!   - Algo: Algorithm execution
//!   - Reducer: Crossing reduction validation
//!
//! Sequence conventions (WDP Part 6):
//!   - 001 = MISSING
//!   - 002 = MISMATCH
//!   - 003 = INVALID
//!   - 007 = DUPLICATE
//!   - 021 = NOT_FOUND
//!   - 026 = EXHAUSTED

const std = @import("std");

/// WDP namespace for this library
pub const NAMESPACE = "zigraph";

/// WDP Error Codes
/// Format: Severity.Component.Primary.Sequence
pub const Code = struct {
    // ========================================================================
    // Graph.Node errors
    // ========================================================================

    /// Graph has no nodes (001 = MISSING)
    pub const EMPTY_GRAPH = "E.Graph.Node.001";

    /// Referenced node does not exist (021 = NOT_FOUND)
    pub const NODE_NOT_FOUND = "E.Graph.Node.021";

    // ========================================================================
    // Graph.Edge errors
    // ========================================================================

    /// Edge already exists between nodes (007 = DUPLICATE)
    pub const EDGE_DUPLICATE = "E.Graph.Edge.007";

    /// Self-loop not allowed in DAG (003 = INVALID)
    pub const SELF_LOOP = "E.Graph.Edge.003";

    // ========================================================================
    // Graph.Dag errors
    // ========================================================================

    /// Graph contains a cycle, not a valid DAG (003 = INVALID)
    pub const CYCLE_DETECTED = "E.Graph.Dag.003";

    // ========================================================================
    // Layout.Algo errors
    // ========================================================================

    /// Memory allocation failed (026 = EXHAUSTED)
    pub const OUT_OF_MEMORY = "E.Layout.Algo.026";

    /// Layout algorithm failed (003 = INVALID)
    pub const LAYOUT_FAILED = "E.Layout.Algo.003";

    // ========================================================================
    // Layout.Reducer errors (crossing reduction validation)
    // ========================================================================

    /// Reducer corrupted level structure (003 = INVALID)
    pub const REDUCER_LEVEL_COUNT_MISMATCH = "E.Layout.Reducer.003";

    /// Reducer changed node count in a level (002 = MISMATCH)
    pub const REDUCER_NODE_COUNT_MISMATCH = "E.Layout.Reducer.002";

    /// Reducer created duplicate node in levels (007 = DUPLICATE)
    pub const REDUCER_DUPLICATE_NODE = "E.Layout.Reducer.007";

    /// Reducer lost a node from levels (001 = MISSING)
    pub const REDUCER_MISSING_NODE = "E.Layout.Reducer.001";
};

/// Detailed error information with WDP code
pub const ErrorDetail = struct {
    /// WDP structured code (e.g., "E.Graph.Node.001")
    code: []const u8,
    /// Human-readable message
    message: []const u8,
    /// Optional: involved node IDs (for cycle, missing node, etc.)
    nodes: ?[]const usize = null,

    pub fn format(
        self: ErrorDetail,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{s}] {s}", .{ self.code, self.message });
        if (self.nodes) |nodes| {
            try writer.print(" (nodes: ", .{});
            for (nodes, 0..) |node, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{d}", .{node});
            }
            try writer.print(")", .{});
        }
    }
};

/// Cycle information returned when a cycle is detected
pub const CycleInfo = struct {
    /// Node indices forming the cycle (first == last for complete cycle)
    path: []usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CycleInfo) void {
        self.allocator.free(self.path);
    }

    pub fn format(
        self: CycleInfo,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{s}] Cycle: ", .{Code.CYCLE_DETECTED});
        for (self.path, 0..) |node_idx, i| {
            if (i > 0) try writer.print(" -> ", .{});
            try writer.print("{d}", .{node_idx});
        }
    }
};

/// Graph validation result
pub const ValidationResult = union(enum) {
    /// Graph is valid for layout
    ok,
    /// Graph is empty (no nodes)
    empty,
    /// Graph contains a cycle
    cycle: CycleInfo,

    pub fn deinit(self: *ValidationResult) void {
        switch (self.*) {
            .cycle => |*info| info.deinit(),
            else => {},
        }
    }

    pub fn isOk(self: ValidationResult) bool {
        return self == .ok;
    }

    /// Get the WDP error code for this result
    pub fn code(self: ValidationResult) ?[]const u8 {
        return switch (self) {
            .ok => null,
            .empty => Code.EMPTY_GRAPH,
            .cycle => Code.CYCLE_DETECTED,
        };
    }
};

/// Zigraph error set
pub const ZigraphError = error{
    /// A referenced node does not exist
    NodeNotFound,
    /// The graph is empty (no nodes)
    EmptyGraph,
    /// The graph contains a cycle
    CycleDetected,
    /// Out of memory
    OutOfMemory,
    /// Reducer corrupted level structure
    ReducerCorruptedLevels,
    /// Reducer corrupted node count
    ReducerCorruptedNodeCount,
    /// Reducer created duplicate node
    ReducerDuplicateNode,
    /// Reducer lost a node
    ReducerMissingNode,
};

/// Map Zig error to WDP code
pub fn errorCode(err: ZigraphError) []const u8 {
    return switch (err) {
        error.NodeNotFound => Code.NODE_NOT_FOUND,
        error.EmptyGraph => Code.EMPTY_GRAPH,
        error.CycleDetected => Code.CYCLE_DETECTED,
        error.OutOfMemory => Code.OUT_OF_MEMORY,
        error.ReducerCorruptedLevels => Code.REDUCER_LEVEL_COUNT_MISMATCH,
        error.ReducerCorruptedNodeCount => Code.REDUCER_NODE_COUNT_MISMATCH,
        error.ReducerDuplicateNode => Code.REDUCER_DUPLICATE_NODE,
        error.ReducerMissingNode => Code.REDUCER_MISSING_NODE,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "WDP code format" {
    // Verify codes follow WDP format: Severity.Component.Primary.Sequence
    try std.testing.expectEqualStrings("E.Graph.Node.001", Code.EMPTY_GRAPH);
    try std.testing.expectEqualStrings("E.Graph.Dag.003", Code.CYCLE_DETECTED);
    try std.testing.expectEqualStrings("E.Graph.Node.021", Code.NODE_NOT_FOUND);
    try std.testing.expectEqualStrings("E.Layout.Algo.026", Code.OUT_OF_MEMORY);
}

test "error detail formatting" {
    const detail = ErrorDetail{
        .code = Code.CYCLE_DETECTED,
        .message = "Graph contains a cycle",
        .nodes = &[_]usize{ 1, 2, 3, 1 },
    };

    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, detail.code);
    try std.testing.expectEqualStrings("Graph contains a cycle", detail.message);
    try std.testing.expectEqual(@as(usize, 4), detail.nodes.?.len);
}

test "error to WDP code mapping" {
    try std.testing.expectEqualStrings(Code.EMPTY_GRAPH, errorCode(error.EmptyGraph));
    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, errorCode(error.CycleDetected));
    try std.testing.expectEqualStrings(Code.NODE_NOT_FOUND, errorCode(error.NodeNotFound));
    try std.testing.expectEqualStrings(Code.OUT_OF_MEMORY, errorCode(error.OutOfMemory));
}

test "namespace is zigraph" {
    try std.testing.expectEqualStrings("zigraph", NAMESPACE);
}
