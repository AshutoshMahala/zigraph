const std = @import("std");
const vaxis = @import("vaxis");
const dsl = @import("dsl");

const Style = vaxis.Cell.Style;
const Color = vaxis.Cell.Color;
const TokenKind = dsl.tokenizer.TokenKind;

pub const StyledSpan = struct {
    start: usize,
    len: usize,
    style: Style,
};

/// Curly red underline for error markers.
pub const error_underline: Style = .{
    .fg = .{ .index = 1 },
    .ul = .{ .index = 1 },
    .ul_style = .curly,
};

/// Curly yellow underline for warning markers.
pub const warning_underline: Style = .{
    .fg = .{ .index = 3 },
    .ul = .{ .index = 3 },
    .ul_style = .curly,
};

/// Map a DSL TokenKind to its syntax-highlighting style.
pub fn styleForToken(kind: TokenKind) Style {
    return switch (kind) {
        .string => .{ .fg = .{ .index = 2 } },
        .at_keyword => .{ .fg = .{ .index = 5 }, .bold = true },
        .comment => .{ .fg = .{ .index = 8 }, .dim = true },
        .arrow,
        .arrow_reverse,
        .dash_dash,
        .arrow_bidi,
        .fat_arrow,
        .fat_arrow2,
        .dashed_arrow,
        .dotted_arrow,
        .dotted_line,
        => .{ .fg = .{ .index = 6 } },
        .lbrace, .rbrace, .lbracket, .rbracket => .{ .fg = .{ .index = 3 } },
        .colon, .comma, .semicolon => .{ .dim = true },
        .pipe => .{ .fg = .{ .index = 3 } },
        .class => .{ .fg = .{ .index = 4 } },
        .identifier, .dot, .newline, .eof => .{},
    };
}

/// Run the DSL tokenizer over `source` and return an array of StyledSpans
/// (one per visible token, skipping newline/eof).
pub fn tokenizeToSpans(allocator: std.mem.Allocator, source: []const u8) ![]StyledSpan {
    var err_list = dsl.errors.ErrorList.init(allocator);
    defer err_list.deinit();

    const tokens = dsl.tokenizer.tokenize(allocator, source, &err_list) catch {
        return allocator.alloc(StyledSpan, 0);
    };
    defer allocator.free(tokens);

    var spans: std.ArrayListUnmanaged(StyledSpan) = .{};
    defer spans.deinit(allocator);

    for (tokens) |tok| {
        if (tok.kind == .newline or tok.kind == .eof) continue;
        try spans.append(allocator, .{
            .start = tok.loc.offset,
            .len = tok.text.len,
            .style = styleForToken(tok.kind),
        });
    }

    return spans.toOwnedSlice(allocator);
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "styleForToken: identifier returns default fg" {
    const s = styleForToken(.identifier);
    try std.testing.expectEqual(Color.default, s.fg);
}

test "styleForToken: string returns green" {
    const s = styleForToken(.string);
    try std.testing.expectEqual(Color{ .index = 2 }, s.fg);
}

test "styleForToken: comment is dim" {
    const s = styleForToken(.comment);
    try std.testing.expect(s.dim);
}

test "styleForToken: at_keyword is bold" {
    const s = styleForToken(.at_keyword);
    try std.testing.expect(s.bold);
}

test "styleForToken: arrow has non-default fg" {
    const s = styleForToken(.arrow);
    try std.testing.expect(s.fg != .default);
}

test "tokenizeToSpans returns non-empty for valid input" {
    const spans = try tokenizeToSpans(std.testing.allocator, "A -> B # comment");
    defer std.testing.allocator.free(spans);
    try std.testing.expect(spans.len > 0);
}
