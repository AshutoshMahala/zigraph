const std = @import("std");
const dsl = @import("dsl");
const Loc = dsl.errors.Loc;
const Allocator = std.mem.Allocator;

const SourceMap = @This();

const NodeEntry = struct {
    node_index: usize,
    loc: Loc,
    len: usize,
};

const EdgeEntry = struct {
    edge_index: usize,
    loc: Loc,
    len: usize,
};

allocator: Allocator,
nodes: std.ArrayListUnmanaged(NodeEntry),
edges: std.ArrayListUnmanaged(EdgeEntry),

pub fn init(allocator: Allocator) SourceMap {
    return .{
        .allocator = allocator,
        .nodes = .{},
        .edges = .{},
    };
}

pub fn deinit(self: *SourceMap) void {
    self.nodes.deinit(self.allocator);
    self.edges.deinit(self.allocator);
}

pub fn clear(self: *SourceMap) void {
    self.nodes.clearRetainingCapacity();
    self.edges.clearRetainingCapacity();
}

pub fn addNode(self: *SourceMap, node_index: usize, loc: Loc, len: usize) !void {
    try self.nodes.append(self.allocator, .{
        .node_index = node_index,
        .loc = loc,
        .len = len,
    });
}

pub fn addEdge(self: *SourceMap, edge_index: usize, loc: Loc, len: usize) !void {
    try self.edges.append(self.allocator, .{
        .edge_index = edge_index,
        .loc = loc,
        .len = len,
    });
}

pub fn nodeAtOffset(self: *const SourceMap, offset: u32) ?usize {
    for (self.nodes.items) |entry| {
        if (offset >= entry.loc.offset and offset < entry.loc.offset + @as(u32, @intCast(entry.len))) {
            return entry.node_index;
        }
    }
    return null;
}

pub fn edgeAtOffset(self: *const SourceMap, offset: u32) ?usize {
    for (self.edges.items) |entry| {
        if (offset >= entry.loc.offset and offset < entry.loc.offset + @as(u32, @intCast(entry.len))) {
            return entry.edge_index;
        }
    }
    return null;
}

pub fn locForNode(self: *const SourceMap, node_index: usize) ?Loc {
    for (self.nodes.items) |entry| {
        if (entry.node_index == node_index) return entry.loc;
    }
    return null;
}

pub fn locForEdge(self: *const SourceMap, edge_index: usize) ?Loc {
    for (self.edges.items) |entry| {
        if (entry.edge_index == edge_index) return entry.loc;
    }
    return null;
}

test "add and lookup node" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addNode(0, .{ .line = 1, .col = 1, .offset = 0 }, 5);
    const result = sm.nodeAtOffset(2);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 0), result.?);
}

test "add and lookup edge" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addEdge(0, .{ .line = 1, .col = 3, .offset = 2 }, 4);
    const result = sm.edgeAtOffset(3);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 0), result.?);
}

test "locForNode" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addNode(3, .{ .line = 5, .col = 1, .offset = 40 }, 8);
    const result = sm.locForNode(3);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u32, 5), result.?.line);
}

test "offset outside any span returns null" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addNode(0, .{ .line = 1, .col = 1, .offset = 0 }, 3);
    try std.testing.expect(sm.nodeAtOffset(10) == null);
}

test "clear resets all mappings" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();
    try sm.addNode(0, .{ .line = 1, .col = 1, .offset = 0 }, 3);
    sm.clear();
    try std.testing.expect(sm.nodeAtOffset(1) == null);
}
