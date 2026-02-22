//! JSON Renderer
//!
//! Serializes and deserializes `LayoutIR` to/from JSON for external tool consumption.
//! Zero dependencies beyond the Zig standard library.
//!
//! ## Schema (v1.2)
//!
//! ```json
//! {
//!   "version": "1.2",
//!   "width": 120,
//!   "height": 40,
//!   "level_count": 4,
//!   "nodes": [
//!     {"id": 1, "label": "A", "x": 10, "y": 0, "width": 3, "center_x": 11, "level": 0, "level_position": 0, "kind": "explicit", "edge_index": null}
//!   ],
//!   "edges": [
//!     {"from": 1, "to": 2, "from_x": 11, "from_y": 1, "to_x": 20, "to_y": 3, "path": {"type": "direct"}, "edge_index": 0, "directed": true}
//!   ],
//!   "subgraphs": [
//!     {"id": 0, "label": "Backend", "parent_id": null, "x": 5, "y": 2, "width": 30, "height": 10}
//!   ]
//! }
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const EdgePath = ir_mod.EdgePath(usize);
const NodeKind = @import("../core/graph.zig").NodeKind;
const errors = @import("../core/errors.zig");

fn validateCoordTypeLocal(comptime Coord: type) void {
    const valid = switch (@typeInfo(Coord)) {
        .int, .float => true,
        else => false,
    };
    if (!valid) @compileError("Coord must be numeric, got " ++ @typeName(Coord));
}

/// Write a JSON-escaped string (handles ", \, and control characters).
fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => try writer.print("\\u{x:0>4}", .{c}),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

/// Current JSON schema version
pub const VERSION = "1.2";

/// Serialize any GenericLayoutIR as JSON string.
/// Works with any coordinate type (usize, u16, f32, etc.).
/// Returns a heap-allocated JSON string. Caller owns the memory.
pub fn serializeGeneric(comptime Coord: type, layout_ir: *const ir_mod.LayoutIR(Coord), allocator: Allocator) ![]u8 {
    return serializeImpl(Coord, layout_ir, allocator);
}

/// Serialize LayoutIR (usize coordinates) as JSON string.
///
/// Returns a heap-allocated JSON string. Caller owns the memory.
pub fn serialize(layout_ir: *const LayoutIR, allocator: Allocator) ![]u8 {
    return serializeImpl(usize, layout_ir, allocator);
}

/// Backward-compatible aliases
pub const renderGeneric = serializeGeneric;
pub const render = serialize;

fn serializeImpl(comptime Coord: type, layout_ir: *const ir_mod.LayoutIR(Coord), allocator: Allocator) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    // Start object
    try writer.writeAll("{\n");
    try writer.print("  \"version\": \"{s}\",\n", .{VERSION});
    try writer.print("  \"width\": {d},\n", .{layout_ir.width});
    try writer.print("  \"height\": {d},\n", .{layout_ir.height});
    try writer.print("  \"level_count\": {d},\n", .{layout_ir.level_count});

    // Nodes array
    try writer.writeAll("  \"nodes\": [\n");
    for (layout_ir.nodes.items, 0..) |node, i| {
        try writer.writeAll("    {");
        try writer.print("\"id\": {d}, ", .{node.id});
        try writer.writeAll("\"label\": ");
        try writeJsonString(writer, node.label);
        try writer.writeAll(", ");
        try writer.print("\"x\": {d}, ", .{node.x});
        try writer.print("\"y\": {d}, ", .{node.y});
        try writer.print("\"width\": {d}, ", .{node.width});
        try writer.print("\"center_x\": {d}, ", .{node.center_x});
        try writer.print("\"level\": {d}, ", .{node.level});
        try writer.print("\"level_position\": {d}, ", .{node.level_position});
        try writer.print("\"kind\": \"{s}\", ", .{kindToString(node.kind)});
        try writer.writeAll("\"edge_index\": ");
        if (node.edge_index) |ei| {
            try writer.print("{d}", .{ei});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("}");
        if (i < layout_ir.nodes.items.len - 1) try writer.writeAll(",");
        try writer.writeAll("\n");
    }
    try writer.writeAll("  ],\n");

    // Edges array
    try writer.writeAll("  \"edges\": [\n");
    for (layout_ir.edges.items, 0..) |edge, i| {
        try writer.writeAll("    {");
        try writer.print("\"from\": {d}, ", .{edge.from_id});
        try writer.print("\"to\": {d}, ", .{edge.to_id});
        try writer.print("\"from_x\": {d}, ", .{edge.from_x});
        try writer.print("\"from_y\": {d}, ", .{edge.from_y});
        try writer.print("\"to_x\": {d}, ", .{edge.to_x});
        try writer.print("\"to_y\": {d}, ", .{edge.to_y});
        try writer.print("\"edge_index\": {d}, ", .{edge.edge_index});
        try writer.print("\"directed\": {}, ", .{edge.directed});
        if (edge.reversed) {
            try writer.writeAll("\"reversed\": true, ");
        }

        // Path
        try writer.writeAll("\"path\": ");
        switch (edge.path) {
            .direct => try writer.writeAll("{\"type\": \"direct\"}"),
            .corner => |c| try writer.print("{{\"type\": \"corner\", \"horizontal_y\": {d}}}", .{c.horizontal_y}),
            .side_channel => |sc| try writer.print("{{\"type\": \"side_channel\", \"channel_x\": {d}, \"start_y\": {d}, \"end_y\": {d}}}", .{ sc.channel_x, sc.start_y, sc.end_y }),
            .multi_segment => |ms| {
                try writer.writeAll("{\"type\": \"multi_segment\", \"waypoints\": [");
                for (ms.waypoints.items, 0..) |wp, wi| {
                    try writer.print("[{d}, {d}]", .{ wp.x, wp.y });
                    if (wi < ms.waypoints.items.len - 1) try writer.writeAll(", ");
                }
                try writer.writeAll("]}");
            },
            .spline => |sp| try writer.print("{{\"type\": \"spline\", \"cp1_x\": {d}, \"cp1_y\": {d}, \"cp2_x\": {d}, \"cp2_y\": {d}}}", .{ sp.cp1_x, sp.cp1_y, sp.cp2_x, sp.cp2_y }),
        }

        // Label (optional)
        if (edge.label) |label| {
            try writer.writeAll(", \"label\": ");
            try writeJsonString(writer, label);
            try writer.print(", \"label_x\": {d}, \"label_y\": {d}", .{ edge.label_x, edge.label_y });
        }

        try writer.writeAll("}");
        if (i < layout_ir.edges.items.len - 1) try writer.writeAll(",");
        try writer.writeAll("\n");
    }

    // Subgraphs array (omitted when empty for backward compatibility)
    if (layout_ir.subgraphs.items.len > 0) {
        try writer.writeAll("  ],\n");
        try writer.writeAll("  \"subgraphs\": [\n");
        for (layout_ir.subgraphs.items, 0..) |sg, i| {
            try writer.writeAll("    {");
            try writer.print("\"id\": {d}, ", .{sg.id});
            try writer.writeAll("\"label\": ");
            try writeJsonString(writer, sg.label);
            try writer.writeAll(", ");
            try writer.writeAll("\"parent_id\": ");
            if (sg.parent_id) |pid| {
                try writer.print("{d}", .{pid});
            } else {
                try writer.writeAll("null");
            }
            try writer.print(", \"x\": {d}, \"y\": {d}, \"width\": {d}, \"height\": {d}", .{ sg.x, sg.y, sg.width, sg.height });
            try writer.writeAll("}");
            if (i < layout_ir.subgraphs.items.len - 1) try writer.writeAll(",");
            try writer.writeAll("\n");
        }
        try writer.writeAll("  ]\n");
    } else {
        try writer.writeAll("  ]\n");
    }

    try writer.writeAll("}\n");

    return buffer.toOwnedSlice(allocator);
}

/// Deserialize JSON string into a new LayoutIR(usize).
/// Accepts schema v1.1. If fields introduced in 1.1 are missing (v1.0 input),
/// sensible defaults are applied: directed=true, kind=explicit, edge_index null, no labels.
pub fn deserialize(json_bytes: []const u8, allocator: Allocator) !LayoutIR {
    return deserializeImpl(usize, json_bytes, allocator);
}

/// Deserialize JSON into a LayoutIR with arbitrary coordinate type.
pub fn deserializeGeneric(comptime Coord: type, json_bytes: []const u8, allocator: Allocator) !ir_mod.LayoutIR(Coord) {
    return deserializeImpl(Coord, json_bytes, allocator);
}

/// Deinit a LayoutIR returned by `deserialize`.
/// 
/// **Important**: Always use this instead of `layout_ir.deinit()` for deserialized IRs.
/// This function frees the heap-allocated label strings before releasing the IR.
/// Calling `layout_ir.deinit()` directly will leak all label memory.
pub fn deinitDeserialized(layout_ir: *LayoutIR, allocator: Allocator) void {
    for (layout_ir.nodes.items) |node| {
        allocator.free(node.label);
    }
    for (layout_ir.edges.items) |edge| {
        if (edge.label) |lbl| allocator.free(lbl);
    }
    for (layout_ir.subgraphs.items) |sg| {
        allocator.free(sg.label);
    }
    layout_ir.deinit();
}

/// Deinit a LayoutIR returned by `deserializeGeneric`.
/// 
/// **Important**: Always use this instead of `layout_ir.deinit()` for deserialized IRs.
/// This function frees the heap-allocated label strings before releasing the IR.
/// Calling `layout_ir.deinit()` directly will leak all label memory.
pub fn deinitDeserializedGeneric(comptime Coord: type, layout_ir: *ir_mod.LayoutIR(Coord), allocator: Allocator) void {
    for (layout_ir.nodes.items) |node| {
        allocator.free(node.label);
    }
    for (layout_ir.edges.items) |edge| {
        if (edge.label) |lbl| allocator.free(lbl);
    }
    for (layout_ir.subgraphs.items) |sg| {
        allocator.free(sg.label);
    }
    layout_ir.deinit();
}

fn deserializeImpl(comptime Coord: type, json_bytes: []const u8, allocator: Allocator) !ir_mod.LayoutIR(Coord) {
    comptime validateCoordTypeLocal(Coord);

    var ir = ir_mod.LayoutIR(Coord).init(allocator);
    errdefer ir.deinit();

    const parse_result = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parse_result.deinit();

    const obj = switch (parse_result.value) {
        .object => |o| o,
        else => return error.JsonRootTypeMismatch,
    };

    const version_val = obj.get("version") orelse return error.JsonVersionMissing;
    const version_str = switch (version_val) {
        .string => |s| s,
        else => return error.JsonVersionTypeMismatch,
    };
    if (!std.mem.eql(u8, version_str, VERSION)) {
        // Allow older schema versions with missing newer fields
        if (!std.mem.eql(u8, version_str, "1.0") and !std.mem.eql(u8, version_str, "1.1")) return error.JsonVersionUnsupported;
    }

    ir.width = try getInt(Coord, obj, "width");
    ir.height = try getInt(Coord, obj, "height");
    ir.level_count = try getInt(usize, obj, "level_count");

    // Nodes
    const nodes_val = obj.get("nodes") orelse return error.JsonNodesMissing;
    const nodes_arr = switch (nodes_val) {
        .array => |a| a,
        else => return error.JsonNodesTypeMismatch,
    };
    try ir.nodes.ensureTotalCapacity(allocator, nodes_arr.items.len);

    for (nodes_arr.items) |nv| {
        const nobj = switch (nv) {
            .object => |o| o,
            else => return error.JsonNodeTypeMismatch,
        };
        const id = try getInt(usize, nobj, "id");
        const label_src = try getString(nobj, "label");
        const label = try allocator.dupe(u8, label_src);
        errdefer allocator.free(label);
        const x = try getInt(Coord, nobj, "x");
        const y = try getInt(Coord, nobj, "y");
        const width = try getInt(Coord, nobj, "width");
        const center_x = try getInt(Coord, nobj, "center_x");
        const level = try getInt(usize, nobj, "level");
        const level_position = try getInt(usize, nobj, "level_position");
        const kind = getKind(nobj.get("kind"));
        const edge_index = getOptionalInt(nobj.get("edge_index"));

        try ir.addNode(.{
            .id = id,
            .label = label,
            .x = x,
            .y = y,
            .width = width,
            .center_x = center_x,
            .level = level,
            .level_position = level_position,
            .kind = kind,
            .edge_index = edge_index,
        });
    }

    // Edges
    const edges_val = obj.get("edges") orelse return error.JsonEdgesMissing;
    const edges_arr = switch (edges_val) {
        .array => |a| a,
        else => return error.JsonEdgesTypeMismatch,
    };
    try ir.edges.ensureTotalCapacity(allocator, edges_arr.items.len);

    for (edges_arr.items) |ev| {
        const eobj = switch (ev) {
            .object => |o| o,
            else => return error.JsonEdgeTypeMismatch,
        };
        const from_id = try getInt(usize, eobj, "from");
        const to_id = try getInt(usize, eobj, "to");
        const from_x = try getInt(Coord, eobj, "from_x");
        const from_y = try getInt(Coord, eobj, "from_y");
        const to_x = try getInt(Coord, eobj, "to_x");
        const to_y = try getInt(Coord, eobj, "to_y");
        const edge_index = getOptionalInt(eobj.get("edge_index")) orelse 0;
        const directed = getOptionalBool(eobj.get("directed")) orelse true;
        const reversed = getOptionalBool(eobj.get("reversed")) orelse false;
        const path_val = eobj.get("path") orelse return error.JsonFieldMissing;
        var path = try parsePath(Coord, allocator, path_val);

        const label_opt = getOptionalString(eobj.get("label"));
        var label_copy: ?[]const u8 = null;
        if (label_opt) |lbl| {
            label_copy = try allocator.dupe(u8, lbl);
        }
        errdefer if (label_copy) |lc| allocator.free(lc);
        const label_x = getOptionalNumber(Coord, eobj.get("label_x")) orelse 0;
        const label_y = getOptionalNumber(Coord, eobj.get("label_y")) orelse 0;

        ir.addEdge(.{
            .from_id = from_id,
            .to_id = to_id,
            .from_x = from_x,
            .from_y = from_y,
            .to_x = to_x,
            .to_y = to_y,
            .path = path,
            .edge_index = edge_index,
            .directed = directed,
            .reversed = reversed,
            .label = label_copy,
            .label_x = label_x,
            .label_y = label_y,
        }) catch |err| {
            path.deinit();
            return err;
        };
    }

    // Subgraphs (optional, introduced in v1.2)
    if (obj.get("subgraphs")) |sg_val| {
        const sg_arr = switch (sg_val) {
            .array => |a| a,
            else => return error.JsonSubgraphsTypeMismatch,
        };
        try ir.subgraphs.ensureTotalCapacity(allocator, sg_arr.items.len);
        for (sg_arr.items) |sv| {
            const sobj = switch (sv) {
                .object => |o| o,
                else => return error.JsonSubgraphsTypeMismatch,
            };
            const sg_id = try getInt(usize, sobj, "id");
            const sg_label_src = try getString(sobj, "label");
            const sg_label = try allocator.dupe(u8, sg_label_src);
            errdefer allocator.free(sg_label);
            const parent_id = getOptionalInt(sobj.get("parent_id"));
            const sg_x = try getInt(Coord, sobj, "x");
            const sg_y = try getInt(Coord, sobj, "y");
            const sg_w = try getInt(Coord, sobj, "width");
            const sg_h = try getInt(Coord, sobj, "height");
            ir.subgraphs.appendAssumeCapacity(.{
                .id = sg_id,
                .parent_id = parent_id,
                .label = sg_label,
                .x = sg_x,
                .y = sg_y,
                .width = sg_w,
                .height = sg_h,
            });
        }
    }

    // Levels are not serialized; rebuild basic levels array using level field.
    try ir.ensureLevels(ir.level_count);
    for (ir.nodes.items, 0..) |_, idx| {
        const level = ir.nodes.items[idx].level;
        try ir.addNodeToLevel(level, idx);
    }

    return ir;
}

fn castNumber(comptime T: type, val: std.json.Value) !T {
    return switch (val) {
        .integer => |i| switch (@typeInfo(T)) {
            .int => @intCast(i),
            .float => @floatFromInt(i),
            else => return error.JsonFieldTypeMismatch,
        },
        .float => |f| switch (@typeInfo(T)) {
            .int => @intFromFloat(@as(f64, f)),
            .float => @floatCast(f),
            else => return error.JsonFieldTypeMismatch,
        },
        else => return error.JsonFieldTypeMismatch,
    };
}

fn getInt(comptime T: type, obj: anytype, key: []const u8) !T {
    const val = obj.get(key) orelse return error.JsonFieldMissing;
    return castNumber(T, val);
}

fn getOptionalInt(val_opt: ?std.json.Value) ?usize {
    const val = val_opt orelse return null;
    return switch (val) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(@as(f64, f)),
        .null => null,
        else => null,
    };
}

fn getOptionalNumber(comptime T: type, val_opt: ?std.json.Value) ?T {
    const val = val_opt orelse return null;
    return switch (val) {
        .integer => |i| switch (@typeInfo(T)) {
            .int => @intCast(i),
            .float => @floatFromInt(i),
            else => null,
        },
        .float => |f| switch (@typeInfo(T)) {
            .int => @intFromFloat(@as(f64, f)),
            .float => @floatCast(f),
            else => null,
        },
        .null => null,
        else => null,
    };
}

fn getOptionalBool(val_opt: ?std.json.Value) ?bool {
    const val = val_opt orelse return null;
    return switch (val) {
        .bool => |b| b,
        else => null,
    };
}

fn getString(obj: anytype, key: []const u8) ![]const u8 {
    const val = obj.get(key) orelse return error.JsonFieldMissing;
    return switch (val) {
        .string => |s| s,
        else => return error.JsonFieldTypeMismatch,
    };
}

fn getOptionalString(val_opt: ?std.json.Value) ?[]const u8 {
    const val = val_opt orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn kindToString(kind: NodeKind) []const u8 {
    return switch (kind) {
        .explicit => "explicit",
        .implicit => "implicit",
        .dummy => "dummy",
    };
}

fn getKind(val_opt: ?std.json.Value) NodeKind {
    const val = val_opt orelse return .explicit;
    const s = switch (val) {
        .string => |str| str,
        else => return .explicit,
    };
    if (std.mem.eql(u8, s, "explicit")) return .explicit;
    if (std.mem.eql(u8, s, "implicit")) return .implicit;
    if (std.mem.eql(u8, s, "dummy")) return .dummy;
    return .explicit;
}

fn parsePath(comptime Coord: type, allocator: Allocator, val: std.json.Value) !ir_mod.EdgePath(Coord) {
    const obj = switch (val) {
        .object => |o| o,
        else => return error.JsonPathInvalid,
    };
    const type_val = obj.get("type") orelse return error.JsonFieldMissing;
    const type_str = switch (type_val) {
        .string => |s| s,
        else => return error.JsonFieldTypeMismatch,
    };

    if (std.mem.eql(u8, type_str, "direct")) return .direct;
    if (std.mem.eql(u8, type_str, "corner")) {
        return .{ .corner = .{ .horizontal_y = try getInt(Coord, obj, "horizontal_y") } };
    }
    if (std.mem.eql(u8, type_str, "side_channel")) {
        return .{ .side_channel = .{
            .channel_x = try getInt(Coord, obj, "channel_x"),
            .start_y = try getInt(Coord, obj, "start_y"),
            .end_y = try getInt(Coord, obj, "end_y"),
        } };
    }
    if (std.mem.eql(u8, type_str, "multi_segment")) {
        const wps_val = obj.get("waypoints") orelse return error.JsonFieldMissing;
        const arr = switch (wps_val) {
            .array => |a| a,
            else => return error.JsonWaypointsInvalid,
        };
        var waypoints: std.ArrayListUnmanaged(ir_mod.EdgePath(Coord).Waypoint) = .{};
        errdefer waypoints.deinit(allocator);
        try waypoints.ensureTotalCapacity(allocator, arr.items.len);
        for (arr.items) |wv| {
            const pair = switch (wv) {
                .array => |a| a,
                else => return error.JsonWaypointsInvalid,
            };
            if (pair.items.len != 2) return error.JsonWaypointsInvalid;
            const x = try castNumber(Coord, pair.items[0]);
            const y = try castNumber(Coord, pair.items[1]);
            waypoints.appendAssumeCapacity(.{ .x = x, .y = y });
        }
        return .{ .multi_segment = .{ .waypoints = waypoints, .allocator = allocator } };
    }
    if (std.mem.eql(u8, type_str, "spline")) {
        return .{ .spline = .{
            .cp1_x = try getInt(Coord, obj, "cp1_x"),
            .cp1_y = try getInt(Coord, obj, "cp1_y"),
            .cp2_x = try getInt(Coord, obj, "cp2_x"),
            .cp2_y = try getInt(Coord, obj, "cp2_y"),
        } };
    }

    // Unknown path type
    return error.JsonPathInvalid;
}

// ============================================================================
// Tests
// ============================================================================

test "json: serialize basic layout" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 3,
        .path = .direct,
        .edge_index = 0,
    });

    layout_ir.setDimensions(10, 5);

    const json = try serialize(&layout_ir, allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"1.2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\": \"explicit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"edge_index\": 0") != null);
}

test "json: deserialize v1.0 compatibility" {
    const allocator = std.testing.allocator;
    const json_bytes = "{\"version\":\"1.0\",\"width\":5,\"height\":4,\"level_count\":1,\"nodes\":[{\"id\":1,\"label\":\"A\",\"x\":0,\"y\":0,\"width\":3,\"center_x\":1,\"level\":0,\"level_position\":0}],\"edges\":[{\"from\":1,\"to\":2,\"from_x\":1,\"from_y\":1,\"to_x\":1,\"to_y\":3,\"path\":{\"type\":\"direct\"}}]}";

    var layout_ir = try deserialize(json_bytes, allocator);
    defer deinitDeserialized(&layout_ir, allocator);

    try std.testing.expectEqual(@as(usize, 1), layout_ir.nodes.items.len);
    try std.testing.expectEqual(@as(NodeKind, .explicit), layout_ir.nodes.items[0].kind);
    try std.testing.expect(layout_ir.nodes.items[0].edge_index == null);
    try std.testing.expectEqual(@as(usize, 1), layout_ir.edges.items.len);
    try std.testing.expect(layout_ir.edges.items[0].directed); // default true
}

test "json: roundtrip serialize/deserialize" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1,
        .label = "Root",
        .x = 0,
        .y = 0,
        .width = 4,
        .center_x = 2,
        .level = 0,
        .level_position = 0,
    });
    try layout_ir.addNode(.{
        .id = 2,
        .label = "Dummy",
        .x = 2,
        .y = 1,
        .width = 3,
        .center_x = 3,
        .level = 1,
        .level_position = 0,
        .kind = .dummy,
        .edge_index = 5,
    });

    var waypoints: std.ArrayListUnmanaged(EdgePath.Waypoint) = .{};
    try waypoints.append(allocator, .{ .x = 2, .y = 1 });
    try waypoints.append(allocator, .{ .x = 4, .y = 2 });

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 2,
        .from_y = 1,
        .to_x = 4,
        .to_y = 2,
        .path = .{ .multi_segment = .{ .waypoints = waypoints, .allocator = allocator } },
        .edge_index = 5,
        .directed = false,
        .label = "labeled",
        .label_x = 3,
        .label_y = 1,
    });

    layout_ir.setDimensions(20, 10);
    try layout_ir.addNodeToLevel(0, 0);
    try layout_ir.addNodeToLevel(1, 1);

    const json_bytes = try serialize(&layout_ir, allocator);
    defer allocator.free(json_bytes);

    var decoded = try deserialize(json_bytes, allocator);
    defer deinitDeserialized(&decoded, allocator);

    try std.testing.expectEqual(@as(usize, 2), decoded.nodes.items.len);
    try std.testing.expectEqual(@as(NodeKind, .dummy), decoded.nodes.items[1].kind);
    try std.testing.expectEqual(@as(usize, 5), decoded.nodes.items[1].edge_index.?);

    try std.testing.expectEqual(@as(usize, 1), decoded.edges.items.len);
    try std.testing.expect(!decoded.edges.items[0].directed);
    try std.testing.expectEqualStrings("labeled", decoded.edges.items[0].label.?);
    try std.testing.expectEqual(@as(usize, 20), decoded.width);
    try std.testing.expectEqual(@as(usize, 10), decoded.height);
    try std.testing.expectEqual(@as(usize, 2), decoded.levels.items.len);
}

test "json: subgraph serialization" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1, .label = "A", .x = 5, .y = 3, .width = 3,
        .center_x = 6, .level = 0, .level_position = 0,
    });

    try layout_ir.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "backend",
        .x = 3, .y = 1, .width = 10, .height = 8,
    });

    layout_ir.setDimensions(20, 15);

    const json = try serialize(&layout_ir, allocator);
    defer allocator.free(json);

    // Should contain subgraphs array
    try std.testing.expect(std.mem.indexOf(u8, json, "\"subgraphs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"backend\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"parent_id\": null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"1.2\"") != null);
}

test "json: subgraph roundtrip" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1, .label = "X", .x = 0, .y = 0, .width = 3,
        .center_x = 1, .level = 0, .level_position = 0,
    });

    try layout_ir.subgraphs.append(allocator, .{
        .id = 10,
        .parent_id = null,
        .label = "outer",
        .x = 0, .y = 0, .width = 20, .height = 15,
    });
    try layout_ir.subgraphs.append(allocator, .{
        .id = 20,
        .parent_id = 10,
        .label = "inner",
        .x = 2, .y = 2, .width = 10, .height = 8,
    });

    layout_ir.setDimensions(25, 20);
    try layout_ir.ensureLevels(1);
    try layout_ir.addNodeToLevel(0, 0);

    const json = try serialize(&layout_ir, allocator);
    defer allocator.free(json);

    var decoded = try deserialize(json, allocator);
    defer deinitDeserialized(&decoded, allocator);

    try std.testing.expectEqual(@as(usize, 2), decoded.subgraphs.items.len);

    const sg0 = decoded.subgraphs.items[0];
    try std.testing.expectEqual(@as(usize, 10), sg0.id);
    try std.testing.expectEqualStrings("outer", sg0.label);
    try std.testing.expect(sg0.parent_id == null);
    try std.testing.expectEqual(@as(usize, 20), sg0.width);

    const sg1 = decoded.subgraphs.items[1];
    try std.testing.expectEqual(@as(usize, 20), sg1.id);
    try std.testing.expectEqualStrings("inner", sg1.label);
    try std.testing.expectEqual(@as(usize, 10), sg1.parent_id.?);
}

test "json: no subgraphs omits array" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1, .label = "A", .x = 0, .y = 0, .width = 3,
        .center_x = 1, .level = 0, .level_position = 0,
    });
    layout_ir.setDimensions(5, 3);

    const json = try serialize(&layout_ir, allocator);
    defer allocator.free(json);

    // Should NOT contain subgraphs key when empty
    try std.testing.expect(std.mem.indexOf(u8, json, "\"subgraphs\"") == null);
}
