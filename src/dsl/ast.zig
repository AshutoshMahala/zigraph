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

pub const Layout = enum { dag, tree, force };

pub const Direction = enum {
    top_down,   // default — no transform
    left_right, // swap X↔Y (flow goes left to right)
    bottom_up,  // flip Y axis
    right_left, // swap X↔Y then flip X axis
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
};

pub const DirectiveKind = enum { layout, theme, direction, spacing };

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
    loc: Loc,
};

pub const Document = struct {
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    blocks: []NamedBlock,
};

test "AST types compile and are usable" {
    const doc = Document{
        .directives = &.{},
        .styles = &.{},
        .statements = &.{},
        .blocks = &.{},
    };
    try std.testing.expectEqual(@as(usize, 0), doc.directives.len);

    const edge = EdgeStatement{
        .chain = &.{},
        .operator = .directed,
        .loc = Loc.zero,
    };
    try std.testing.expectEqual(EdgeOp.directed, edge.operator);
}
