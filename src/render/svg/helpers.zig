//! Shared helpers for the SVG renderer.
//!
//! Small utility functions extracted from mod.zig for reuse across submodules.

const std = @import("std");
const ir_mod = @import("../../core/ir.zig");
const LayoutNode = ir_mod.LayoutNode(usize);

/// Check whether a raw attribute string already contains a given attribute name.
///
/// This prevents the renderer from emitting a native `data-id`, `data-from`, etc.
/// when the user's `extra_attrs` already provides it — duplicating an XML attribute
/// is a fatal parse error in SVG.
pub fn attrsContain(extra_attrs: ?[]const u8, attr_name: []const u8) bool {
    const attrs = extra_attrs orelse return false;
    return std.mem.indexOf(u8, attrs, attr_name) != null;
}

/// Find a node label by ID. Returns empty string for unknown/dummy nodes.
pub fn findNodeLabel(nodes: []const LayoutNode, node_id: usize) []const u8 {
    for (nodes) |node| {
        if (node.id == node_id) return node.label;
    }
    return "";
}

/// Compute nesting depth for a subgraph by walking up parent_id chains.
/// Returns 0 for root-level subgraphs, 1 for one level nested, etc.
pub fn computeSubgraphDepth(subgraphs: []const ir_mod.SubgraphInfo(usize), parent_id: ?usize) usize {
    var depth: usize = 0;
    var current = parent_id;
    while (current) |pid| {
        depth += 1;
        // Find the parent subgraph and continue up
        var found = false;
        for (subgraphs) |sg| {
            if (sg.id == pid) {
                current = sg.parent_id;
                found = true;
                break;
            }
        }
        if (!found) break; // orphan parent_id — shouldn't happen, but be safe
    }
    return depth;
}
