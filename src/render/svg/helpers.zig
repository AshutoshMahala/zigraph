//! Shared helpers for the SVG renderer.
//!
//! Small utility functions extracted from mod.zig for reuse across submodules.
//! Subgraph depth computation is delegated to `src/render/helpers.zig` (shared).

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../../core/ir.zig");
const LayoutNode = ir_mod.LayoutNode(usize);
const shared_helpers = @import("../helpers.zig");

/// Re-export from shared helpers — used by SVG mod.zig and potentially other submodules.
pub const computeSubgraphDepths = shared_helpers.computeSubgraphDepths;

/// Check whether a raw attribute string already contains a given attribute name.
///
/// This prevents the renderer from emitting a native `data-id`, `data-from`, etc.
/// when the user's `extra_attrs` already provides it — duplicating an XML attribute
/// is a fatal parse error in SVG.
pub fn attrsContain(extra_attrs: ?[]const u8, attr_name: []const u8) bool {
    const attrs = extra_attrs orelse return false;
    return std.mem.indexOf(u8, attrs, attr_name) != null;
}

/// Escape a string for safe embedding in SVG/XML text content.
/// Replaces `&`, `<`, `>`, `"`, `'` with their XML entity equivalents.
/// Uses the arena allocator — result persists until the render pass ends.
/// Returns the original string unchanged if no escaping is needed (zero-cost fast path).
pub fn xmlEscape(arena: Allocator, raw: []const u8) []const u8 {
    // Fast path: check if escaping is needed at all
    var needs_escape = false;
    for (raw) |c| {
        if (c == '&' or c == '<' or c == '>' or c == '"' or c == '\'') {
            needs_escape = true;
            break;
        }
    }
    if (!needs_escape) return raw;

    // Count output size
    var out_len: usize = 0;
    for (raw) |c| {
        out_len += switch (c) {
            '&' => 5, // &amp;
            '<' => 4, // &lt;
            '>' => 4, // &gt;
            '"' => 6, // &quot;
            '\'' => 6, // &apos;
            else => 1,
        };
    }

    const buf = arena.alloc(u8, out_len) catch return raw;
    var i: usize = 0;
    for (raw) |c| {
        switch (c) {
            '&' => {
                @memcpy(buf[i..][0..5], "&amp;");
                i += 5;
            },
            '<' => {
                @memcpy(buf[i..][0..4], "&lt;");
                i += 4;
            },
            '>' => {
                @memcpy(buf[i..][0..4], "&gt;");
                i += 4;
            },
            '"' => {
                @memcpy(buf[i..][0..6], "&quot;");
                i += 6;
            },
            '\'' => {
                @memcpy(buf[i..][0..6], "&apos;");
                i += 6;
            },
            else => {
                buf[i] = c;
                i += 1;
            },
        }
    }
    return buf;
}

/// Find a node label by ID using the IR's id_to_index hashmap. O(1) lookup.
/// Returns empty string for unknown/dummy nodes.
pub fn findNodeLabel(nodes: []const LayoutNode, node_id: usize, id_to_index: std.AutoHashMapUnmanaged(usize, usize)) []const u8 {
    const idx = id_to_index.get(node_id) orelse return "";
    if (idx >= nodes.len) return "";
    return nodes[idx].label;
}

/// Write XML-escaped text directly to a writer. Zero-allocation streaming escape.
/// Replaces `&`, `<`, `>`, `"`, `'` with their XML entity equivalents.
pub fn writeXmlEscaped(writer: anytype, raw: []const u8) !void {
    for (raw) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),
            else => try writer.writeByte(c),
        }
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "xmlEscape escapes special XML characters" {
    const result = xmlEscape(testing.allocator, "<b>A&B</b>");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("&lt;b&gt;A&amp;B&lt;/b&gt;", result);
}

test "xmlEscape returns original for safe strings" {
    const safe = "hello world 123";
    const result = xmlEscape(testing.allocator, safe);
    // Should return the same pointer (no allocation) for safe input
    try testing.expectEqual(safe.ptr, result.ptr);
}

test "writeXmlEscaped streams correctly" {
    var buf: [256]u8 = undefined;
    var stream_writer = std.Io.Writer.fixed(&buf);
    try writeXmlEscaped(&stream_writer, "a\"b'c");
    try testing.expectEqualStrings("a&quot;b&apos;c", stream_writer.buffered());
}
