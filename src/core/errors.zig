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

    /// Node limit exceeded (026 = EXHAUSTED)
    pub const NODE_LIMIT_EXCEEDED = code(E, Graph, Node, EXHAUSTED);

    // ========================================================================
    // Graph.Edge errors
    // ========================================================================

    /// Edge already exists between nodes (007 = DUPLICATE)
    pub const EDGE_DUPLICATE = code(E, Graph, Edge, DUPLICATE);

    /// Self-loop not allowed in DAG (003 = INVALID)
    pub const SELF_LOOP = code(E, Graph, Edge, INVALID);

    /// Edge limit exceeded (026 = EXHAUSTED)
    pub const EDGE_LIMIT_EXCEEDED = code(E, Graph, Edge, EXHAUSTED);

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

// ============================================================================
// Diagnostic System
// ============================================================================

/// Comptime-known diagnostic metadata for each error code.
///
/// Every ZigraphError has a corresponding DiagnosticInfo with:
/// - WDP code (structured, parsable)
/// - Human-readable message (what happened)
/// - Actionable hint (what to do about it)
///
/// All fields are comptime string literals — zero allocation, zero cost.
pub const DiagnosticInfo = struct {
    /// WDP structured code (e.g., "E.Graph.Node.001")
    code: []const u8,
    /// What happened (e.g., "Graph has no nodes")
    message: []const u8,
    /// What to do about it (e.g., "Add at least one node with graph.addNode(id, label)")
    hint: []const u8,
};

/// Rich runtime diagnostic — carries full context for a single error.
///
/// Produced by `diagnosticInfo()` for comptime metadata, or by
/// `lastDiagnostic()` for full context including source location.
///
/// ## Usage
/// ```zig
/// const ir = zigraph.layout(&graph, allocator, .{}) catch |err| {
///     const info = zigraph.errors.diagnosticInfo(err);
///     std.debug.print("[{s}] {s}\n", .{ info.code, info.message });
///     std.debug.print("  Hint: {s}\n", .{ info.hint });
///     return err;
/// };
/// ```
pub const Diagnostic = struct {
    /// WDP structured code (e.g., "E.Graph.Node.001")
    code: []const u8,
    /// What happened
    message: []const u8,
    /// What to do about it
    hint: []const u8,
    /// Specific details (e.g., "node 42 does not exist", "A -> B -> C -> A")
    detail: ?[]const u8 = null,
    /// Involved node IDs — machine-readable (e.g., cycle path, missing node)
    nodes: ?[]const usize = null,
    /// Source location where the error was emitted (via @src())
    src: ?std.builtin.SourceLocation = null,

    pub fn format(
        self: Diagnostic,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{s}] {s}", .{ self.code, self.message });
        if (self.detail) |detail| {
            try writer.print("\n  Detail: {s}", .{detail});
        }
        if (self.nodes) |nodes| {
            try writer.print("\n  Nodes:", .{});
            for (nodes, 0..) |id, i| {
                if (i > 0) try writer.print(",", .{});
                try writer.print(" {d}", .{id});
            }
        }
        try writer.print("\n  Hint: {s}", .{self.hint});
        if (self.src) |src| {
            try writer.print("\n  at {s}:{d} in {s}", .{ src.file, src.line, src.fn_name });
        }
    }
};

/// Get comptime diagnostic metadata for any ZigraphError.
///
/// Returns the WDP code, human-readable message, and actionable hint.
/// All returned strings are comptime literals — zero allocation.
///
/// ## Example
/// ```zig
/// const ir = zigraph.layout(&graph, allocator, .{}) catch |err| {
///     const info = zigraph.errors.diagnosticInfo(err);
///     std.log.err("[{s}] {s}\n  Hint: {s}", .{ info.code, info.message, info.hint });
///     return err;
/// };
/// ```
pub fn diagnosticInfo(err: ZigraphError) DiagnosticInfo {
    return switch (err) {
        // ── Graph.Node ──────────────────────────────────────────────
        error.EmptyGraph => .{
            .code = Code.EMPTY_GRAPH,
            .message = "Graph has no nodes",
            .hint = "Add at least one node with graph.addNode(id, label) before calling layout",
        },
        error.NodeNotFound => .{
            .code = Code.NODE_NOT_FOUND,
            .message = "Referenced node does not exist in the graph",
            .hint = "Ensure both endpoint nodes exist (added via graph.addNode) before adding an edge between them",
        },
        error.NodeLimitExceeded => .{
            .code = Code.NODE_LIMIT_EXCEEDED,
            .message = "Node count exceeds configured maximum",
            .hint = "Increase max_nodes in Graph.initWithOptions() (default: 100,000; set to 0 for unlimited)",
        },

        // ── Graph.Edge ──────────────────────────────────────────────
        error.EdgeLimitExceeded => .{
            .code = Code.EDGE_LIMIT_EXCEEDED,
            .message = "Edge count exceeds configured maximum",
            .hint = "Increase max_edges in Graph.initWithOptions() (default: 500,000; set to 0 for unlimited)",
        },
        error.GraphHasUndirectedEdges => .{
            .code = Code.GRAPH_HAS_UNDIRECTED,
            .message = "Graph contains undirected edges but algorithm requires all directed",
            .hint = "Use graph.addDiEdge() instead of graph.addUnDiEdge(), or choose a force-directed algorithm that accepts undirected edges",
        },
        error.GraphHasDirectedEdges => .{
            .code = Code.GRAPH_HAS_DIRECTED,
            .message = "Graph contains directed edges but algorithm requires all undirected",
            .hint = "Use graph.addUnDiEdge() instead of graph.addDiEdge()",
        },

        // ── Graph.Dag ───────────────────────────────────────────────
        error.CycleDetected => .{
            .code = Code.CYCLE_DETECTED,
            .message = "Graph contains a cycle — not a valid DAG",
            .hint = "Use .cycle_breaking = .depth_first to handle cycles automatically, or ensure your graph is acyclic",
        },

        // ── Graph.Component ─────────────────────────────────────────
        error.GraphDisconnected => .{
            .code = Code.GRAPH_DISCONNECTED,
            .message = "Graph is disconnected (multiple components)",
            .hint = "Ensure all nodes are reachable from each other, or process each connected component separately",
        },

        // ── Layout.Algo ─────────────────────────────────────────────
        error.OutOfMemory => .{
            .code = Code.OUT_OF_MEMORY,
            .message = "Memory allocation failed",
            .hint = "Reduce graph size or use an allocator with more capacity (e.g., std.heap.page_allocator or a larger arena)",
        },

        // ── Layout.Reducer ──────────────────────────────────────────
        error.ReducerCorruptedLevels => .{
            .code = Code.REDUCER_LEVEL_COUNT_MISMATCH,
            .message = "Crossing reducer corrupted level structure — level count changed",
            .hint = "Custom reducers must only reorder nodes within levels, never add or remove levels",
        },
        error.ReducerCorruptedNodeCount => .{
            .code = Code.REDUCER_NODE_COUNT_MISMATCH,
            .message = "Crossing reducer changed node count in a level",
            .hint = "Custom reducers must not move nodes between levels — only reorder within each level",
        },
        error.ReducerDuplicateNode => .{
            .code = Code.REDUCER_DUPLICATE_NODE,
            .message = "Crossing reducer created duplicate node entries",
            .hint = "Each node must appear exactly once across all levels — check for accidental duplication in custom reducer logic",
        },
        error.ReducerMissingNode => .{
            .code = Code.REDUCER_MISSING_NODE,
            .message = "Crossing reducer lost nodes — total count decreased",
            .hint = "Custom reducers must preserve all nodes — verify no nodes are dropped during reordering",
        },

        // ── Json.* ──────────────────────────────────────────────────
        error.JsonRootTypeMismatch => .{
            .code = Code.JSON_ROOT_TYPE_MISMATCH,
            .message = "JSON root is not an object",
            .hint = "The JSON IR must be a top-level object with 'version', 'nodes', and 'edges' fields",
        },
        error.JsonVersionMissing => .{
            .code = Code.JSON_VERSION_MISSING,
            .message = "JSON 'version' field is missing",
            .hint = "Add a 'version' field to the root object (e.g., \"version\": \"1.0\")",
        },
        error.JsonVersionTypeMismatch => .{
            .code = Code.JSON_VERSION_TYPE_MISMATCH,
            .message = "JSON 'version' field is not a string",
            .hint = "The 'version' field must be a string (e.g., \"version\": \"1.0\")",
        },
        error.JsonVersionUnsupported => .{
            .code = Code.JSON_VERSION_UNSUPPORTED,
            .message = "JSON IR version is not supported",
            .hint = "Use version \"1.0\" — this is the only currently supported IR version",
        },
        error.JsonNodesMissing => .{
            .code = Code.JSON_NODES_MISSING,
            .message = "JSON 'nodes' array is missing",
            .hint = "Add a 'nodes' array to the root object containing node objects",
        },
        error.JsonNodesTypeMismatch => .{
            .code = Code.JSON_NODES_TYPE_MISMATCH,
            .message = "JSON 'nodes' field is not an array",
            .hint = "The 'nodes' field must be a JSON array of node objects",
        },
        error.JsonNodeTypeMismatch => .{
            .code = Code.JSON_NODE_TYPE_MISMATCH,
            .message = "JSON node entry is not an object",
            .hint = "Each element in the 'nodes' array must be an object with 'id', 'label', 'x', 'y', 'width', 'center_x', 'level', 'level_position' fields",
        },
        error.JsonEdgesMissing => .{
            .code = Code.JSON_EDGES_MISSING,
            .message = "JSON 'edges' array is missing",
            .hint = "Add an 'edges' array to the root object containing edge objects",
        },
        error.JsonEdgesTypeMismatch => .{
            .code = Code.JSON_EDGES_TYPE_MISMATCH,
            .message = "JSON 'edges' field is not an array",
            .hint = "The 'edges' field must be a JSON array of edge objects",
        },
        error.JsonEdgeTypeMismatch => .{
            .code = Code.JSON_EDGE_TYPE_MISMATCH,
            .message = "JSON edge entry is not an object",
            .hint = "Each element in the 'edges' array must be an object with 'from', 'to', 'from_x', 'from_y', 'to_x', 'to_y' fields",
        },
        error.JsonFieldMissing => .{
            .code = Code.JSON_FIELD_MISSING,
            .message = "Required JSON field is missing",
            .hint = "Check the JSON IR schema in JSON_SCHEMA.md for required fields on each element",
        },
        error.JsonFieldTypeMismatch => .{
            .code = Code.JSON_FIELD_TYPE_MISMATCH,
            .message = "JSON field has wrong type",
            .hint = "Check the JSON IR schema — numeric fields must be integers, string fields must be strings",
        },
        error.JsonPathInvalid => .{
            .code = Code.JSON_PATH_INVALID,
            .message = "JSON edge path object is invalid",
            .hint = "Edge path must have a 'type' field with value 'direct', 'corner', 'side_channel', 'multi_segment', or 'spline'",
        },
        error.JsonWaypointsInvalid => .{
            .code = Code.JSON_WAYPOINTS_INVALID,
            .message = "JSON waypoints array is invalid",
            .hint = "Waypoints must be an array of [x, y] coordinate pairs (arrays of two integers)",
        },
    };
}

// ============================================================================
// Source Location Capture
// ============================================================================

/// Most recent error source location (single-threaded; set by captureSrc).
/// This is module-level state — safe because zigraph is single-threaded.
var last_src: ?std.builtin.SourceLocation = null;

/// Most recent error code (set alongside last_src).
var last_err: ?ZigraphError = null;

/// Buffer for the most recent error detail string (no allocation needed).
var last_detail_buf: [512]u8 = undefined;
var last_detail_len: usize = 0;

/// Buffer for the most recent error node IDs (no allocation needed).
const max_captured_nodes = 64;
var last_nodes_buf: [max_captured_nodes]usize = undefined;
var last_nodes_len: usize = 0;

/// Record source location for the most recent error.
///
/// Call this immediately before returning an error to capture where it happened:
/// ```zig
/// captureSrc(@src());
/// return error.NodeNotFound;
/// ```
pub fn captureSrc(src: std.builtin.SourceLocation) void {
    last_src = src;
}

/// Record both the error and source location.
///
/// Convenience for capturing context in a single call:
/// ```zig
/// captureError(error.CycleDetected, @src());
/// return error.CycleDetected;
/// ```
pub fn captureError(err: ZigraphError, src: std.builtin.SourceLocation) void {
    last_err = err;
    last_src = src;
    last_detail_len = 0;
    last_nodes_len = 0;
}

/// Record error, source location, and a runtime detail string.
///
/// The detail is copied into an internal fixed buffer (truncated at 512 bytes).
pub fn captureErrorWithDetail(err: ZigraphError, src: std.builtin.SourceLocation, detail: []const u8) void {
    last_err = err;
    last_src = src;
    const len = @min(detail.len, last_detail_buf.len);
    @memcpy(last_detail_buf[0..len], detail[0..len]);
    last_detail_len = len;
    last_nodes_len = 0;
}

/// Record error, source location, detail string, and involved node IDs.
///
/// Both detail and nodes are copied into internal fixed buffers — zero allocation.
/// Detail truncates at 512 bytes, nodes at 64 entries.
///
/// ```zig
/// errors.captureErrorFull(error.CycleDetected, @src(), "A -> B -> C -> A", &.{1, 2, 3, 1});
/// ```
pub fn captureErrorFull(
    err: ZigraphError,
    src: std.builtin.SourceLocation,
    detail: []const u8,
    node_ids: []const usize,
) void {
    last_err = err;
    last_src = src;
    const dlen = @min(detail.len, last_detail_buf.len);
    @memcpy(last_detail_buf[0..dlen], detail[0..dlen]);
    last_detail_len = dlen;
    const nlen = @min(node_ids.len, max_captured_nodes);
    @memcpy(last_nodes_buf[0..nlen], node_ids[0..nlen]);
    last_nodes_len = nlen;
}

/// Retrieve a full Diagnostic for the most recently captured error.
///
/// Returns null if no error has been captured via captureSrc/captureError.
/// Combines the comptime DiagnosticInfo with the runtime source location.
pub fn lastDiagnostic() ?Diagnostic {
    const err = last_err orelse return null;
    const info = diagnosticInfo(err);
    return Diagnostic{
        .code = info.code,
        .message = info.message,
        .hint = info.hint,
        .detail = if (last_detail_len > 0) last_detail_buf[0..last_detail_len] else null,
        .nodes = if (last_nodes_len > 0) last_nodes_buf[0..last_nodes_len] else null,
        .src = last_src,
    };
}

/// Clear the captured error state.
pub fn clearDiagnostic() void {
    last_src = null;
    last_err = null;
    last_detail_len = 0;
    last_nodes_len = 0;
}

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
    /// Node count exceeds configured max_nodes limit
    NodeLimitExceeded,
    /// Edge count exceeds configured max_edges limit
    EdgeLimitExceeded,
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
        error.NodeLimitExceeded => Code.NODE_LIMIT_EXCEEDED,
        error.EdgeLimitExceeded => Code.EDGE_LIMIT_EXCEEDED,
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
    try std.testing.expectEqualStrings("E.Graph.Node.026", Code.NODE_LIMIT_EXCEEDED);
    try std.testing.expectEqualStrings("E.Graph.Edge.026", Code.EDGE_LIMIT_EXCEEDED);
    try std.testing.expectEqualStrings("E.Layout.Algo.026", Code.OUT_OF_MEMORY);
    try std.testing.expectEqualStrings("E.Graph.Edge.002", Code.GRAPH_HAS_UNDIRECTED);
    try std.testing.expectEqualStrings("E.Graph.Edge.002", Code.GRAPH_HAS_DIRECTED);
    try std.testing.expectEqualStrings("E.Graph.Component.003", Code.GRAPH_DISCONNECTED);
}

test "error detail formatting" {
    const detail = Diagnostic{
        .code = Code.CYCLE_DETECTED,
        .message = "Graph contains a cycle",
        .hint = "Use .cycle_breaking = .depth_first",
        .detail = "A -> B -> C -> A",
        .nodes = &[_]usize{ 1, 2, 3, 1 },
    };

    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, detail.code);
    try std.testing.expectEqualStrings("Graph contains a cycle", detail.message);
    try std.testing.expectEqualStrings("A -> B -> C -> A", detail.detail.?);
    try std.testing.expectEqual(@as(usize, 4), detail.nodes.?.len);
    try std.testing.expectEqual(@as(usize, 1), detail.nodes.?[0]);
    try std.testing.expectEqual(@as(usize, 3), detail.nodes.?[2]);
}

test "diagnosticInfo provides hints for all errors" {
    // Every ZigraphError must have a non-empty hint
    const info_empty = diagnosticInfo(error.EmptyGraph);
    try std.testing.expectEqualStrings(Code.EMPTY_GRAPH, info_empty.code);
    try std.testing.expect(info_empty.hint.len > 0);
    try std.testing.expect(info_empty.message.len > 0);

    const info_cycle = diagnosticInfo(error.CycleDetected);
    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, info_cycle.code);
    try std.testing.expect(std.mem.indexOf(u8, info_cycle.hint, "cycle_breaking") != null);

    const info_node = diagnosticInfo(error.NodeNotFound);
    try std.testing.expectEqualStrings(Code.NODE_NOT_FOUND, info_node.code);
    try std.testing.expect(std.mem.indexOf(u8, info_node.hint, "addNode") != null);

    const info_node_limit = diagnosticInfo(error.NodeLimitExceeded);
    try std.testing.expectEqualStrings(Code.NODE_LIMIT_EXCEEDED, info_node_limit.code);
    try std.testing.expect(std.mem.indexOf(u8, info_node_limit.hint, "max_nodes") != null);

    const info_edge_limit = diagnosticInfo(error.EdgeLimitExceeded);
    try std.testing.expectEqualStrings(Code.EDGE_LIMIT_EXCEEDED, info_edge_limit.code);
    try std.testing.expect(std.mem.indexOf(u8, info_edge_limit.hint, "max_edges") != null);

    const info_oom = diagnosticInfo(error.OutOfMemory);
    try std.testing.expectEqualStrings(Code.OUT_OF_MEMORY, info_oom.code);

    const info_json = diagnosticInfo(error.JsonVersionUnsupported);
    try std.testing.expectEqualStrings(Code.JSON_VERSION_UNSUPPORTED, info_json.code);
    try std.testing.expect(std.mem.indexOf(u8, info_json.hint, "1.0") != null);
}

test "diagnosticInfo code matches errorCode" {
    // Verify diagnosticInfo and errorCode return the same WDP code for every error
    const all_errors = [_]ZigraphError{
        error.EmptyGraph,
        error.NodeNotFound,
        error.NodeLimitExceeded,
        error.EdgeLimitExceeded,
        error.CycleDetected,
        error.GraphHasUndirectedEdges,
        error.GraphHasDirectedEdges,
        error.GraphDisconnected,
        error.OutOfMemory,
        error.ReducerCorruptedLevels,
        error.ReducerCorruptedNodeCount,
        error.ReducerDuplicateNode,
        error.ReducerMissingNode,
        error.JsonRootTypeMismatch,
        error.JsonVersionMissing,
        error.JsonVersionTypeMismatch,
        error.JsonVersionUnsupported,
        error.JsonNodesMissing,
        error.JsonNodesTypeMismatch,
        error.JsonNodeTypeMismatch,
        error.JsonEdgesMissing,
        error.JsonEdgesTypeMismatch,
        error.JsonEdgeTypeMismatch,
        error.JsonFieldMissing,
        error.JsonFieldTypeMismatch,
        error.JsonPathInvalid,
        error.JsonWaypointsInvalid,
    };
    for (all_errors) |err| {
        const info = diagnosticInfo(err);
        const code_from_fn = errorCode(err);
        try std.testing.expectEqualStrings(code_from_fn, info.code);
    }
}

test "captureSrc and lastDiagnostic" {
    // Initially no diagnostic
    clearDiagnostic();
    try std.testing.expect(lastDiagnostic() == null);

    // Capture an error
    captureError(error.EmptyGraph, @src());
    const diag = lastDiagnostic().?;
    try std.testing.expectEqualStrings(Code.EMPTY_GRAPH, diag.code);
    try std.testing.expect(diag.src != null);
    try std.testing.expect(diag.hint.len > 0);
    try std.testing.expect(diag.detail == null);

    // Clear
    clearDiagnostic();
    try std.testing.expect(lastDiagnostic() == null);
}

test "captureErrorWithDetail" {
    clearDiagnostic();

    // NodeNotFound with detail only — nodes should be null
    captureErrorWithDetail(error.NodeNotFound, @src(), "node 42 does not exist");
    const diag = lastDiagnostic().?;
    try std.testing.expectEqualStrings(Code.NODE_NOT_FOUND, diag.code);
    try std.testing.expect(diag.detail != null);
    try std.testing.expectEqualStrings("node 42 does not exist", diag.detail.?);
    try std.testing.expect(diag.nodes == null);

    // Overlong detail is truncated, not a crash
    var long: [600]u8 = undefined;
    @memset(&long, 'x');
    captureErrorWithDetail(error.OutOfMemory, @src(), &long);
    const diag2 = lastDiagnostic().?;
    try std.testing.expectEqual(@as(usize, 512), diag2.detail.?.len);

    clearDiagnostic();
}

test "captureErrorFull with nodes" {
    clearDiagnostic();

    // CycleDetected with detail + node IDs
    captureErrorFull(error.CycleDetected, @src(), "A -> B -> C -> A", &.{ 1, 2, 3, 1 });
    const diag = lastDiagnostic().?;
    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, diag.code);
    try std.testing.expectEqualStrings("A -> B -> C -> A", diag.detail.?);
    try std.testing.expect(diag.nodes != null);
    try std.testing.expectEqual(@as(usize, 4), diag.nodes.?.len);
    try std.testing.expectEqual(@as(usize, 1), diag.nodes.?[0]);
    try std.testing.expectEqual(@as(usize, 2), diag.nodes.?[1]);
    try std.testing.expectEqual(@as(usize, 3), diag.nodes.?[2]);
    try std.testing.expectEqual(@as(usize, 1), diag.nodes.?[3]);

    // NodeNotFound with single node ID
    captureErrorFull(error.NodeNotFound, @src(), "node 42 does not exist", &.{42});
    const diag2 = lastDiagnostic().?;
    try std.testing.expectEqual(@as(usize, 1), diag2.nodes.?.len);
    try std.testing.expectEqual(@as(usize, 42), diag2.nodes.?[0]);

    // captureError clears nodes
    captureError(error.EmptyGraph, @src());
    const diag3 = lastDiagnostic().?;
    try std.testing.expect(diag3.nodes == null);
    try std.testing.expect(diag3.detail == null);

    clearDiagnostic();
}

test "error to WDP code mapping" {
    try std.testing.expectEqualStrings(Code.EMPTY_GRAPH, errorCode(error.EmptyGraph));
    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, errorCode(error.CycleDetected));
    try std.testing.expectEqualStrings(Code.NODE_NOT_FOUND, errorCode(error.NodeNotFound));
    try std.testing.expectEqualStrings(Code.NODE_LIMIT_EXCEEDED, errorCode(error.NodeLimitExceeded));
    try std.testing.expectEqualStrings(Code.EDGE_LIMIT_EXCEEDED, errorCode(error.EdgeLimitExceeded));
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
