const std = @import("std");
const dsl = @import("dsl");
const Loc = dsl.errors.Loc;

const Definitions = @This();

pub const DefKind = enum { variable, class_style, node, import_file };

pub const Definition = struct {
    loc: Loc,
    kind: DefKind,
    name: []const u8,
};

allocator: std.mem.Allocator,
defs: std.StringHashMapUnmanaged(Definition),

pub fn init(allocator: std.mem.Allocator) Definitions {
    return .{
        .allocator = allocator,
        .defs = .{},
    };
}

pub fn deinit(self: *Definitions) void {
    self.defs.deinit(self.allocator);
}

pub fn clear(self: *Definitions) void {
    self.defs.clearRetainingCapacity();
}

pub fn addVar(self: *Definitions, name: []const u8, loc: Loc) !void {
    try self.defs.put(self.allocator, name, .{
        .loc = loc,
        .kind = .variable,
        .name = name,
    });
}

pub fn addClass(self: *Definitions, name: []const u8, loc: Loc) !void {
    try self.defs.put(self.allocator, name, .{
        .loc = loc,
        .kind = .class_style,
        .name = name,
    });
}

pub fn addNode(self: *Definitions, name: []const u8, loc: Loc) !void {
    try self.defs.put(self.allocator, name, .{
        .loc = loc,
        .kind = .node,
        .name = name,
    });
}

pub fn addImport(self: *Definitions, name: []const u8, loc: Loc) !void {
    try self.defs.put(self.allocator, name, .{
        .loc = loc,
        .kind = .import_file,
        .name = name,
    });
}

pub fn lookup(self: *const Definitions, name: []const u8) ?Definition {
    return self.defs.get(name);
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "add and lookup variable" {
    var defs = Definitions.init(std.testing.allocator);
    defer defs.deinit();
    try defs.addVar("color", .{ .line = 2, .col = 3, .offset = 15 });
    const def = defs.lookup("color");
    try std.testing.expect(def != null);
    try std.testing.expectEqual(DefKind.variable, def.?.kind);
    try std.testing.expectEqual(@as(u32, 2), def.?.loc.line);
}

test "add and lookup class" {
    var defs = Definitions.init(std.testing.allocator);
    defer defs.deinit();
    try defs.addClass("database", .{ .line = 10, .col = 1, .offset = 80 });
    const def = defs.lookup("database");
    try std.testing.expect(def != null);
    try std.testing.expectEqual(DefKind.class_style, def.?.kind);
}

test "lookup missing returns null" {
    var defs = Definitions.init(std.testing.allocator);
    defer defs.deinit();
    try std.testing.expect(defs.lookup("missing") == null);
}

test "clear removes all" {
    var defs = Definitions.init(std.testing.allocator);
    defer defs.deinit();
    try defs.addVar("x", .{ .line = 1, .col = 1, .offset = 0 });
    defs.clear();
    try std.testing.expect(defs.lookup("x") == null);
}
