const std = @import("std");

pub const Completion = @This();

pub const Context = enum {
    directive,
    layout_value,
    direction_value,
    border_value,
    variable,
    class_ref,
    property_key,
    shape_value,
    node_name,
    none,
};

pub const CompletionItem = struct {
    text: []const u8,
    description: []const u8 = "",
};

const directive_completions = [_]CompletionItem{
    .{ .text = "align", .description = "Set alignment" },
    .{ .text = "layout", .description = "Set layout algorithm" },
    .{ .text = "direction", .description = "Set flow direction" },
    .{ .text = "import", .description = "Import another file" },
    .{ .text = "style", .description = "Define style rule" },
    .{ .text = "spacing", .description = "Set spacing" },
    .{ .text = "border", .description = "Set border style" },
    .{ .text = "theme", .description = "Set theme" },
};

const layout_completions = [_]CompletionItem{
    .{ .text = "sugiyama" },
    .{ .text = "dagre" },
    .{ .text = "force" },
    .{ .text = "tree" },
    .{ .text = "table" },
    .{ .text = "card" },
    .{ .text = "flow" },
};

const direction_completions = [_]CompletionItem{
    .{ .text = "top-down" },
    .{ .text = "left-right" },
    .{ .text = "bottom-up" },
    .{ .text = "right-left" },
};

const shape_completions = [_]CompletionItem{
    .{ .text = "rect" },
    .{ .text = "circle" },
    .{ .text = "diamond" },
    .{ .text = "cylinder" },
    .{ .text = "person" },
    .{ .text = "pill" },
    .{ .text = "hexagon" },
    .{ .text = "parallelogram" },
    .{ .text = "queue" },
    .{ .text = "cloud" },
    .{ .text = "card" },
};

const property_key_completions = [_]CompletionItem{
    .{ .text = "color" },
    .{ .text = "shape" },
    .{ .text = "label" },
    .{ .text = "style" },
    .{ .text = "weight" },
};

const border_completions = [_]CompletionItem{
    .{ .text = "none" },
    .{ .text = "light" },
    .{ .text = "heavy" },
    .{ .text = "double" },
    .{ .text = "rounded" },
};

visible: bool = false,
items: []const CompletionItem = &.{},
selected: usize = 0,
prefix: [64]u8 = .{0} ** 64,
prefix_len: usize = 0,

/// Detect the completion context by scanning backwards from the cursor position.
pub fn detectContext(line: []const u8, col: usize) Context {
    const pos = @min(col, line.len);
    const before = line[0..pos];

    // Check for @directive contexts — scan for the last '@' before cursor.
    if (std.mem.lastIndexOfScalar(u8, before, '@')) |at_pos| {
        const after_at = before[at_pos + 1 ..];
        // Check if the text after @ contains a known directive followed by a space.
        if (startsWithAndSpace(after_at, "layout")) return .layout_value;
        if (startsWithAndSpace(after_at, "direction")) return .direction_value;
        if (startsWithAndSpace(after_at, "border")) return .border_value;
        // Otherwise it's a bare directive being typed.
        return .directive;
    }

    // Check for ${ (variable interpolation).
    if (pos >= 2) {
        // Find last occurrence of "${" before cursor.
        var i: usize = pos;
        while (i >= 2) {
            i -= 1;
            if (i > 0 and before[i - 1] == '$' and before[i] == '{') {
                // Make sure there's no closing } between ${ and cursor.
                const after_brace = before[i + 1 ..];
                if (std.mem.indexOfScalar(u8, after_brace, '}') == null) {
                    return .variable;
                }
            }
        }
    }

    // Check for shape= context.
    if (findLastSubstring(before, "shape=")) |_| {
        return .shape_value;
    }

    // Check for property_key context — inside [ ] after [ or ,
    if (isInsideBrackets(before)) {
        return .property_key;
    }

    return .none;
}

/// Returns the appropriate completion items for the given context.
pub fn getCompletions(context: Context) []const CompletionItem {
    return switch (context) {
        .directive => &directive_completions,
        .layout_value => &layout_completions,
        .direction_value => &direction_completions,
        .border_value => &border_completions,
        .shape_value => &shape_completions,
        .property_key => &property_key_completions,
        .variable, .class_ref, .node_name, .none => &.{},
    };
}

// --- Helpers ---

fn startsWithAndSpace(text: []const u8, keyword: []const u8) bool {
    if (text.len <= keyword.len) return false;
    return std.mem.eql(u8, text[0..keyword.len], keyword) and text[keyword.len] == ' ';
}

fn findLastSubstring(haystack: []const u8, needle: []const u8) ?usize {
    if (haystack.len < needle.len) return null;
    var i: usize = haystack.len - needle.len;
    while (true) {
        if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) return i;
        if (i == 0) break;
        i -= 1;
    }
    return null;
}

fn isInsideBrackets(before: []const u8) bool {
    // Walk backwards to find the last unmatched '['.
    var depth: isize = 0;
    var i: usize = before.len;
    while (i > 0) {
        i -= 1;
        if (before[i] == ']') {
            depth += 1;
        } else if (before[i] == '[') {
            if (depth == 0) {
                // We found an unmatched '[', so we're inside brackets.
                return true;
            }
            depth -= 1;
        }
    }
    return false;
}

// --- Tests ---

test "detect directive context after @" {
    const ctx = Completion.detectContext("@lay", 4);
    try std.testing.expectEqual(Completion.Context.directive, ctx);
}

test "detect layout value context" {
    const ctx = Completion.detectContext("@layout sug", 11);
    try std.testing.expectEqual(Completion.Context.layout_value, ctx);
}

test "detect none for plain text" {
    const ctx = Completion.detectContext("hello", 5);
    try std.testing.expectEqual(Completion.Context.none, ctx);
}

test "getCompletions returns items for directive" {
    const items = Completion.getCompletions(.directive);
    try std.testing.expect(items.len > 0);
}

test "detect shape value context" {
    const ctx = Completion.detectContext("[shape=ci", 9);
    try std.testing.expectEqual(Completion.Context.shape_value, ctx);
}

test "detect direction value context" {
    const ctx = Completion.detectContext("@direction top", 14);
    try std.testing.expectEqual(Completion.Context.direction_value, ctx);
}

test "detect border value context" {
    const ctx = Completion.detectContext("@border rou", 11);
    try std.testing.expectEqual(Completion.Context.border_value, ctx);
}

test "detect variable context" {
    const ctx = Completion.detectContext("${my_var", 8);
    try std.testing.expectEqual(Completion.Context.variable, ctx);
}

test "detect property key context inside brackets" {
    const ctx = Completion.detectContext("[col", 4);
    try std.testing.expectEqual(Completion.Context.property_key, ctx);
}

test "getCompletions returns empty for none context" {
    const items = Completion.getCompletions(.none);
    try std.testing.expectEqual(@as(usize, 0), items.len);
}
