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
//!   - 009 = UNSUPPORTED
//!   - 021 = NOT_FOUND
//!   - 026 = EXHAUSTED

const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;

/// WDP namespace for this library
pub const NAMESPACE = "zigraph";

/// WDP Error Codes
/// Format: Severity.Component.Primary.Sequence
///
/// Uses comptime string composition for consistency and self-documentation.
pub const Code = struct {
    // ========================================================================
    // WDP Building Blocks
    // ========================================================================

    // Severity
    const E = "E"; // Error

    // Components
    const Graph = "Graph";
    const Layout = "Layout";
    const Json = "Json";

    // Primaries
    const Node = "Node";
    const Edge = "Edge";
    const Dag = "Dag";
    const Component = "Component";
    const Algo = "Algo";
    const Reducer = "Reducer";
    const Root = "Root";
    const Version = "Version";
    const Nodes = "Nodes";
    const Edges = "Edges";
    const Field = "Field";
    const Path = "Path";
    const Waypoints = "Waypoints";

    // Sequences (WDP Part 6 conventions)
    const MISSING = "001";
    const MISMATCH = "002";
    const INVALID = "003";
    const DUPLICATE = "007";
    const UNSUPPORTED = "009";
    const NOT_FOUND = "021";
    const EXHAUSTED = "026";

    // Helper for consistent formatting
    fn code(sev: []const u8, comp: []const u8, prim: []const u8, seq: []const u8) []const u8 {
        return comptimePrint("{s}.{s}.{s}.{s}", .{ sev, comp, prim, seq });
    }

    // ========================================================================
    // Graph.Node errors
    // ========================================================================

    /// Graph has no nodes (001 = MISSING)
    pub const EMPTY_GRAPH = code(E, Graph, Node, MISSING);

    /// Referenced node does not exist (021 = NOT_FOUND)
    pub const NODE_NOT_FOUND = code(E, Graph, Node, NOT_FOUND);

    // ========================================================================
    // Graph.Edge errors
    // ========================================================================

    /// Edge already exists between nodes (007 = DUPLICATE)
    pub const EDGE_DUPLICATE = code(E, Graph, Edge, DUPLICATE);

    /// Self-loop not allowed in DAG (003 = INVALID)
    pub const SELF_LOOP = code(E, Graph, Edge, INVALID);

    /// Graph has undirected edges but algorithm requires all directed (002 = MISMATCH)
    pub const GRAPH_HAS_UNDIRECTED = code(E, Graph, Edge, MISMATCH);

    /// Graph has directed edges but algorithm requires all undirected (002 = MISMATCH)
    pub const GRAPH_HAS_DIRECTED = code(E, Graph, Edge, MISMATCH);

    // ========================================================================
    // Graph.Dag errors
    // ========================================================================

    /// Graph contains a cycle, not a valid DAG (003 = INVALID)
    pub const CYCLE_DETECTED = code(E, Graph, Dag, INVALID);

    // ========================================================================
    // Graph.Component errors
    // ========================================================================

    /// Graph is disconnected but algorithm requires connected (003 = INVALID)
    pub const GRAPH_DISCONNECTED = code(E, Graph, Component, INVALID);

    // ========================================================================
    // Layout.Algo errors
    // ========================================================================

    /// Memory allocation failed (026 = EXHAUSTED)
    pub const OUT_OF_MEMORY = code(E, Layout, Algo, EXHAUSTED);

    /// Layout algorithm failed (003 = INVALID)
    pub const LAYOUT_FAILED = code(E, Layout, Algo, INVALID);

    // ========================================================================
    // Layout.Reducer errors (crossing reduction validation)
    // ========================================================================

    /// Reducer corrupted level structure (003 = INVALID)
    pub const REDUCER_LEVEL_COUNT_MISMATCH = code(E, Layout, Reducer, INVALID);

    /// Reducer changed node count in a level (002 = MISMATCH)
    pub const REDUCER_NODE_COUNT_MISMATCH = code(E, Layout, Reducer, MISMATCH);

    /// Reducer created duplicate node in levels (007 = DUPLICATE)
    pub const REDUCER_DUPLICATE_NODE = code(E, Layout, Reducer, DUPLICATE);

    /// Reducer lost a node from levels (001 = MISSING)
    pub const REDUCER_MISSING_NODE = code(E, Layout, Reducer, MISSING);

    // ========================================================================
    // Json.* errors (JSON IR parsing)
    // ========================================================================

    /// JSON root is not an object (002 = MISMATCH)
    pub const JSON_ROOT_TYPE_MISMATCH = code(E, Json, Root, MISMATCH);

    /// JSON version field missing (001 = MISSING)
    pub const JSON_VERSION_MISSING = code(E, Json, Version, MISSING);

    /// JSON version field is not a string (002 = MISMATCH)
    pub const JSON_VERSION_TYPE_MISMATCH = code(E, Json, Version, MISMATCH);

    /// JSON version is not supported (009 = UNSUPPORTED)
    pub const JSON_VERSION_UNSUPPORTED = code(E, Json, Version, UNSUPPORTED);

    /// JSON nodes array missing (001 = MISSING)
    pub const JSON_NODES_MISSING = code(E, Json, Nodes, MISSING);

    /// JSON nodes is not an array (002 = MISMATCH)
    pub const JSON_NODES_TYPE_MISMATCH = code(E, Json, Nodes, MISMATCH);

    /// JSON node entry is not an object (002 = MISMATCH)
    pub const JSON_NODE_TYPE_MISMATCH = code(E, Json, Node, MISMATCH);

    /// JSON edges array missing (001 = MISSING)
    pub const JSON_EDGES_MISSING = code(E, Json, Edges, MISSING);

    /// JSON edges is not an array (002 = MISMATCH)
    pub const JSON_EDGES_TYPE_MISMATCH = code(E, Json, Edges, MISMATCH);

    /// JSON edge entry is not an object (002 = MISMATCH)
    pub const JSON_EDGE_TYPE_MISMATCH = code(E, Json, Edge, MISMATCH);

    /// JSON required field missing (001 = MISSING)
    pub const JSON_FIELD_MISSING = code(E, Json, Field, MISSING);

    /// JSON field has wrong type (002 = MISMATCH)
    pub const JSON_FIELD_TYPE_MISMATCH = code(E, Json, Field, MISMATCH);

    /// JSON path object invalid (003 = INVALID)
    pub const JSON_PATH_INVALID = code(E, Json, Path, INVALID);

    /// JSON waypoints invalid (003 = INVALID)
    pub const JSON_WAYPOINTS_INVALID = code(E, Json, Waypoints, INVALID);
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

// ============================================================================
// Bitset-based validation (Phase 3)
// ============================================================================

/// Validation failures as a bitset - allows reporting multiple errors at once.
/// Uses packed struct for efficient storage and bitwise operations.
pub const ValidationFailures = packed struct(u8) {
    /// Graph has no nodes
    empty: bool = false,
    /// Graph contains one or more cycles (not a DAG)
    has_cycle: bool = false,
    /// Graph has undirected edges (fails `all_directed` requirement)
    has_undirected_edges: bool = false,
    /// Graph has directed edges (fails `all_undirected` requirement)
    has_directed_edges: bool = false,
    /// Graph is not connected (multiple components)
    disconnected: bool = false,
    /// Reserved for future use
    _reserved: u3 = 0,

    /// Returns true if no failures are set
    pub fn isOk(self: ValidationFailures) bool {
        return @as(u8, @bitCast(self)) == 0;
    }

    /// Returns the count of failures
    pub fn count(self: ValidationFailures) u8 {
        const bits: u8 = @bitCast(self);
        // Count only the 5 failure bits (mask out reserved)
        return @popCount(bits & 0b00011111);
    }

    /// Combine two failure sets (union)
    pub fn merge(self: ValidationFailures, other: ValidationFailures) ValidationFailures {
        const a: u8 = @bitCast(self);
        const b: u8 = @bitCast(other);
        return @bitCast(a | b);
    }

    /// Get all WDP codes for the failures (returns slice of codes)
    pub fn codes(self: ValidationFailures, buffer: *[5][]const u8) [][]const u8 {
        var idx: usize = 0;
        if (self.empty) {
            buffer[idx] = Code.EMPTY_GRAPH;
            idx += 1;
        }
        if (self.has_cycle) {
            buffer[idx] = Code.CYCLE_DETECTED;
            idx += 1;
        }
        if (self.has_undirected_edges) {
            buffer[idx] = Code.GRAPH_HAS_UNDIRECTED;
            idx += 1;
        }
        if (self.has_directed_edges) {
            buffer[idx] = Code.GRAPH_HAS_DIRECTED;
            idx += 1;
        }
        if (self.disconnected) {
            buffer[idx] = Code.GRAPH_DISCONNECTED;
            idx += 1;
        }
        return buffer[0..idx];
    }

    /// Format failures for display
    pub fn format(
        self: ValidationFailures,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (self.isOk()) {
            try writer.writeAll("ok");
            return;
        }
        var first = true;
        if (self.empty) {
            try writer.writeAll("empty");
            first = false;
        }
        if (self.has_cycle) {
            if (!first) try writer.writeAll(", ");
            try writer.writeAll("has_cycle");
            first = false;
        }
        if (self.has_undirected_edges) {
            if (!first) try writer.writeAll(", ");
            try writer.writeAll("has_undirected_edges");
            first = false;
        }
        if (self.has_directed_edges) {
            if (!first) try writer.writeAll(", ");
            try writer.writeAll("has_directed_edges");
            first = false;
        }
        if (self.disconnected) {
            if (!first) try writer.writeAll(", ");
            try writer.writeAll("disconnected");
        }
    }
};

/// Algorithm requirements - what properties a graph must have.
/// These are checked against GraphProperties to produce ValidationFailures.
pub const Requirements = struct {
    /// Graph must have at least one node
    non_empty: bool = false,
    /// Graph must be acyclic (a DAG)
    acyclic: bool = false,
    /// All edges must be directed
    all_directed: bool = false,
    /// All edges must be undirected
    all_undirected: bool = false,
    /// Graph must be connected (single component)
    connected: bool = false,

    /// Sugiyama layout requirements: non-empty, acyclic, all directed
    pub const sugiyama = Requirements{
        .non_empty = true,
        .acyclic = true,
        .all_directed = true,
        .connected = false,
    };

    /// Force-directed layout requirements: non-empty only
    pub const force_directed = Requirements{
        .non_empty = true,
        .acyclic = false,
        .all_directed = false,
        .connected = false,
    };
};

/// Properties of a graph - computed once and compared against Requirements.
pub const GraphProperties = struct {
    /// Number of nodes in the graph
    node_count: usize,
    /// Number of directed edges
    directed_edge_count: usize,
    /// Number of undirected edges
    undirected_edge_count: usize,
    /// Whether the graph has any cycles
    has_cycle: bool,
    /// Number of connected components (0 if not computed)
    component_count: usize,

    /// Check if graph is empty
    pub fn isEmpty(self: GraphProperties) bool {
        return self.node_count == 0;
    }

    /// Check if graph has only directed edges
    pub fn isAllDirected(self: GraphProperties) bool {
        return self.undirected_edge_count == 0;
    }

    /// Check if graph has only undirected edges
    pub fn isAllUndirected(self: GraphProperties) bool {
        return self.directed_edge_count == 0;
    }

    /// Check if graph is connected (single component)
    pub fn isConnected(self: GraphProperties) bool {
        return self.component_count <= 1;
    }

    /// Check requirements and return all failures
    pub fn checkRequirements(self: GraphProperties, reqs: Requirements) ValidationFailures {
        var failures = ValidationFailures{};

        if (reqs.non_empty and self.isEmpty()) {
            failures.empty = true;
        }
        if (reqs.acyclic and self.has_cycle) {
            failures.has_cycle = true;
        }
        if (reqs.all_directed and self.undirected_edge_count > 0) {
            failures.has_undirected_edges = true;
        }
        if (reqs.all_undirected and self.directed_edge_count > 0) {
            failures.has_directed_edges = true;
        }
        if (reqs.connected and !self.isConnected()) {
            failures.disconnected = true;
        }

        return failures;
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
    /// Graph has undirected edges but algorithm requires all directed
    GraphHasUndirectedEdges,
    /// Graph has directed edges but algorithm requires all undirected
    GraphHasDirectedEdges,
    /// Graph is disconnected but algorithm requires connected
    GraphDisconnected,
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
    /// JSON root is not an object [E.Json.Root.002]
    JsonRootTypeMismatch,
    /// JSON version field missing [E.Json.Version.001]
    JsonVersionMissing,
    /// JSON version field is not a string [E.Json.Version.002]
    JsonVersionTypeMismatch,
    /// JSON version is unsupported [E.Json.Version.009]
    JsonVersionUnsupported,
    /// JSON nodes array missing [E.Json.Nodes.001]
    JsonNodesMissing,
    /// JSON nodes is not an array [E.Json.Nodes.002]
    JsonNodesTypeMismatch,
    /// JSON node entry is not an object [E.Json.Node.002]
    JsonNodeTypeMismatch,
    /// JSON edges array missing [E.Json.Edges.001]
    JsonEdgesMissing,
    /// JSON edges is not an array [E.Json.Edges.002]
    JsonEdgesTypeMismatch,
    /// JSON edge entry is not an object [E.Json.Edge.002]
    JsonEdgeTypeMismatch,
    /// JSON required field missing [E.Json.Field.001]
    JsonFieldMissing,
    /// JSON field has wrong type [E.Json.Field.002]
    JsonFieldTypeMismatch,
    /// JSON path object invalid [E.Json.Path.003]
    JsonPathInvalid,
    /// JSON waypoints invalid [E.Json.Waypoints.003]
    JsonWaypointsInvalid,
};

/// Map Zig error to WDP code
pub fn errorCode(err: ZigraphError) []const u8 {
    return switch (err) {
        error.NodeNotFound => Code.NODE_NOT_FOUND,
        error.EmptyGraph => Code.EMPTY_GRAPH,
        error.CycleDetected => Code.CYCLE_DETECTED,
        error.GraphHasUndirectedEdges => Code.GRAPH_HAS_UNDIRECTED,
        error.GraphHasDirectedEdges => Code.GRAPH_HAS_DIRECTED,
        error.GraphDisconnected => Code.GRAPH_DISCONNECTED,
        error.OutOfMemory => Code.OUT_OF_MEMORY,
        error.ReducerCorruptedLevels => Code.REDUCER_LEVEL_COUNT_MISMATCH,
        error.ReducerCorruptedNodeCount => Code.REDUCER_NODE_COUNT_MISMATCH,
        error.ReducerDuplicateNode => Code.REDUCER_DUPLICATE_NODE,
        error.ReducerMissingNode => Code.REDUCER_MISSING_NODE,
        error.JsonRootTypeMismatch => Code.JSON_ROOT_TYPE_MISMATCH,
        error.JsonVersionMissing => Code.JSON_VERSION_MISSING,
        error.JsonVersionTypeMismatch => Code.JSON_VERSION_TYPE_MISMATCH,
        error.JsonVersionUnsupported => Code.JSON_VERSION_UNSUPPORTED,
        error.JsonNodesMissing => Code.JSON_NODES_MISSING,
        error.JsonNodesTypeMismatch => Code.JSON_NODES_TYPE_MISMATCH,
        error.JsonNodeTypeMismatch => Code.JSON_NODE_TYPE_MISMATCH,
        error.JsonEdgesMissing => Code.JSON_EDGES_MISSING,
        error.JsonEdgesTypeMismatch => Code.JSON_EDGES_TYPE_MISMATCH,
        error.JsonEdgeTypeMismatch => Code.JSON_EDGE_TYPE_MISMATCH,
        error.JsonFieldMissing => Code.JSON_FIELD_MISSING,
        error.JsonFieldTypeMismatch => Code.JSON_FIELD_TYPE_MISMATCH,
        error.JsonPathInvalid => Code.JSON_PATH_INVALID,
        error.JsonWaypointsInvalid => Code.JSON_WAYPOINTS_INVALID,
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
    try std.testing.expectEqualStrings("E.Graph.Edge.002", Code.GRAPH_HAS_UNDIRECTED);
    try std.testing.expectEqualStrings("E.Graph.Edge.002", Code.GRAPH_HAS_DIRECTED);
    try std.testing.expectEqualStrings("E.Graph.Component.003", Code.GRAPH_DISCONNECTED);
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
    try std.testing.expectEqualStrings(Code.GRAPH_HAS_UNDIRECTED, errorCode(error.GraphHasUndirectedEdges));
    try std.testing.expectEqualStrings(Code.GRAPH_HAS_DIRECTED, errorCode(error.GraphHasDirectedEdges));
    try std.testing.expectEqualStrings(Code.GRAPH_DISCONNECTED, errorCode(error.GraphDisconnected));
}

test "namespace is zigraph" {
    try std.testing.expectEqualStrings("zigraph", NAMESPACE);
}

test "ValidationFailures bitset operations" {
    // Test empty failures (all ok)
    const ok = ValidationFailures{};
    try std.testing.expect(ok.isOk());
    try std.testing.expectEqual(@as(u8, 0), ok.count());

    // Test single failure
    const empty_only = ValidationFailures{ .empty = true };
    try std.testing.expect(!empty_only.isOk());
    try std.testing.expectEqual(@as(u8, 1), empty_only.count());

    // Test multiple failures
    const multiple = ValidationFailures{
        .empty = true,
        .has_cycle = true,
        .has_undirected_edges = true,
    };
    try std.testing.expect(!multiple.isOk());
    try std.testing.expectEqual(@as(u8, 3), multiple.count());

    // Test merge
    const a = ValidationFailures{ .empty = true };
    const b = ValidationFailures{ .has_cycle = true };
    const merged = a.merge(b);
    try std.testing.expect(merged.empty);
    try std.testing.expect(merged.has_cycle);
    try std.testing.expectEqual(@as(u8, 2), merged.count());
}

test "ValidationFailures codes" {
    const failures = ValidationFailures{
        .empty = true,
        .has_cycle = true,
        .disconnected = true,
    };

    var buffer: [5][]const u8 = undefined;
    const codes_slice = failures.codes(&buffer);

    try std.testing.expectEqual(@as(usize, 3), codes_slice.len);
    try std.testing.expectEqualStrings(Code.EMPTY_GRAPH, codes_slice[0]);
    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, codes_slice[1]);
    try std.testing.expectEqualStrings(Code.GRAPH_DISCONNECTED, codes_slice[2]);
}

test "GraphProperties checkRequirements" {
    // Valid DAG for Sugiyama
    const valid_dag = GraphProperties{
        .node_count = 5,
        .directed_edge_count = 4,
        .undirected_edge_count = 0,
        .has_cycle = false,
        .component_count = 1,
    };
    const dag_failures = valid_dag.checkRequirements(Requirements.sugiyama);
    try std.testing.expect(dag_failures.isOk());

    // Empty graph fails non_empty
    const empty_graph = GraphProperties{
        .node_count = 0,
        .directed_edge_count = 0,
        .undirected_edge_count = 0,
        .has_cycle = false,
        .component_count = 0,
    };
    const empty_failures = empty_graph.checkRequirements(Requirements.sugiyama);
    try std.testing.expect(empty_failures.empty);
    try std.testing.expect(!empty_failures.has_cycle);

    // Cyclic graph with undirected edges fails multiple requirements
    const bad_graph = GraphProperties{
        .node_count = 3,
        .directed_edge_count = 2,
        .undirected_edge_count = 1,
        .has_cycle = true,
        .component_count = 1,
    };
    const bad_failures = bad_graph.checkRequirements(Requirements.sugiyama);
    try std.testing.expect(!bad_failures.empty);
    try std.testing.expect(bad_failures.has_cycle);
    try std.testing.expect(bad_failures.has_undirected_edges);
    try std.testing.expectEqual(@as(u8, 2), bad_failures.count());
}

test "Requirements presets" {
    // Sugiyama requires: non_empty, acyclic, all_directed
    try std.testing.expect(Requirements.sugiyama.non_empty);
    try std.testing.expect(Requirements.sugiyama.acyclic);
    try std.testing.expect(Requirements.sugiyama.all_directed);
    try std.testing.expect(!Requirements.sugiyama.all_undirected);
    try std.testing.expect(!Requirements.sugiyama.connected);

    // Force-directed only requires: non_empty
    try std.testing.expect(Requirements.force_directed.non_empty);
    try std.testing.expect(!Requirements.force_directed.acyclic);
    try std.testing.expect(!Requirements.force_directed.all_directed);
    try std.testing.expect(!Requirements.force_directed.connected);
}
