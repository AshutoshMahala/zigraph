const std = @import("std");
const errors = @import("errors.zig");
pub const Loc = errors.Loc;

pub const EdgeOp = enum {
    directed,           // ->
    reverse,            // <-
    undirected,         // --
    bidirectional,      // <->
    bold,               // =>
    bold_double,        // ==>
    dashed_directed,    // -.->
    dotted_directed,    // -..->
    dotted_undirected,  // -..-
};

pub const Layout = enum { dag, tree, force, card, table, flow };

/// Flow direction for the rendered graph.
///
/// The layout engine always produces top-down coordinates. The direction
/// transform (see `direction.zig`) repositions nodes and edges after layout
/// to achieve the requested flow orientation.
///
/// Usage in DSL: `@direction left-right`
/// Usage in CLI: `zigraph render -d left-right`
pub const Direction = enum {
    top_down,
    left_right,
    bottom_up,
    right_left,
};

pub const Shape = enum {
    rect, circle, diamond, cylinder, person, pill,
    hexagon, parallelogram, queue, cloud, card,
};

pub const Property = struct {
    key: []const u8,
    value: []const u8,
    loc: Loc,
};

pub const PropertyBlock = struct {
    properties: []Property,
    loc: Loc,
};

pub const NodeRef = struct {
    id: []const u8,
    label: ?[]const u8 = null,
    card_fields: ?[]const []const u8 = null,
    properties: ?PropertyBlock = null,
    classes: []const []const u8 = &.{},
    loc: Loc,
};

pub const EdgeStatement = struct {
    chain: []NodeRef,
    operator: EdgeOp,
    label: ?[]const u8 = null,
    properties: ?PropertyBlock = null,
    classes: []const []const u8 = &.{},
    fan_out: bool = false,
    loc: Loc,
};

pub const NodeDecl = struct {
    ref: NodeRef,
    loc: Loc,
};

pub const SubgraphDecl = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    properties: ?PropertyBlock = null,
    statements: []Statement,
    loc: Loc,
};

pub const Statement = union(enum) {
    edge: EdgeStatement,
    node_decl: NodeDecl,
    subgraph: SubgraphDecl,
    table_headers: struct { fields: []const []const u8, loc: Loc },
    table_row: struct { fields: []const []const u8, loc: Loc },
    vars_block: struct { vars: []Property, loc: Loc },
};

pub const DirectiveKind = enum { layout, theme, direction, spacing, import_, border, align_ };

pub const Directive = struct {
    kind: DirectiveKind,
    value: []const u8,
    loc: Loc,
};

pub const StyleSelector = union(enum) {
    element: enum { node, edge },
    class: []const u8,
};

pub const StyleRule = struct {
    selector: StyleSelector,
    properties: PropertyBlock,
    loc: Loc,
};

pub const NamedBlock = struct {
    name: []const u8,
    layout: ?Layout = null,
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    vars: []Property,
    loc: Loc,
};

pub const Document = struct {
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    blocks: []NamedBlock,
    vars: []Property,
};

test "AST types compile and are usable" {
    const doc = Document{
        .directives = &.{},
        .styles = &.{},
        .statements = &.{},
        .blocks = &.{},
        .vars = &.{},
    };
    try std.testing.expectEqual(@as(usize, 0), doc.directives.len);

    const edge = EdgeStatement{
        .chain = &.{},
        .operator = .directed,
        .loc = Loc.zero,
    };
    try std.testing.expectEqual(EdgeOp.directed, edge.operator);
}

test "Phase 2a types are usable" {
    // Layout enum has new variants
    const lt: Layout = .card;
    try std.testing.expectEqual(Layout.card, lt);
    const lt2: Layout = .table;
    try std.testing.expectEqual(Layout.table, lt2);
    const lt3: Layout = .flow;
    try std.testing.expectEqual(Layout.flow, lt3);

    // DirectiveKind has new variants
    const dk: DirectiveKind = .import_;
    try std.testing.expectEqual(DirectiveKind.import_, dk);
    const dk2: DirectiveKind = .border;
    try std.testing.expectEqual(DirectiveKind.border, dk2);
    const dk3: DirectiveKind = .align_;
    try std.testing.expectEqual(DirectiveKind.align_, dk3);

    // Statement has new variants
    const stmt = Statement{ .table_headers = .{ .fields = &.{}, .loc = Loc.zero } };
    try std.testing.expect(stmt == .table_headers);

    const stmt2 = Statement{ .table_row = .{ .fields = &.{}, .loc = Loc.zero } };
    try std.testing.expect(stmt2 == .table_row);

    const stmt3 = Statement{ .vars_block = .{ .vars = &.{}, .loc = Loc.zero } };
    try std.testing.expect(stmt3 == .vars_block);

    // Document has vars field
    const doc = Document{
        .directives = &.{},
        .styles = &.{},
        .statements = &.{},
        .blocks = &.{},
        .vars = &.{},
    };
    try std.testing.expectEqual(@as(usize, 0), doc.vars.len);

    // NamedBlock has vars field
    const blk = NamedBlock{
        .name = "test",
        .directives = &.{},
        .styles = &.{},
        .statements = &.{},
        .vars = &.{},
        .loc = Loc.zero,
    };
    try std.testing.expectEqual(@as(usize, 0), blk.vars.len);
}
