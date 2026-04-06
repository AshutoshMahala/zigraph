//! Token-based formatter for .zgraph files.
//!
//! Normalizes whitespace, indentation (2 spaces per level), and preserves comments.
//! Works directly on the token stream to avoid losing comments during AST round-trip.

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const errors = @import("errors.zig");

const Token = tokenizer.Token;
const TokenKind = tokenizer.TokenKind;

/// Format a .zgraph source string into canonical form.
/// Returns a newly allocated formatted string.
pub fn format(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);

    return formatTokens(allocator, tokens);
}

fn formatTokens(allocator: std.mem.Allocator, tokens: []const Token) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    var indent: u32 = 0;
    var at_line_start = true;
    var blank_line_pending = false;
    var prev_kind: TokenKind = .eof;

    for (tokens) |tok| {
        switch (tok.kind) {
            .eof => break,

            .newline => {
                if (prev_kind == .newline or prev_kind == .lbrace) {
                    // Skip duplicate newlines after { (already emitted) or collapse blank lines
                    if (prev_kind == .newline) blank_line_pending = true;
                } else {
                    try buf.append(allocator, '\n');
                }
                at_line_start = true;
                prev_kind = .newline;
                continue;
            },

            .comment => {
                if (at_line_start) {
                    if (blank_line_pending) {
                        try buf.append(allocator, '\n');
                        blank_line_pending = false;
                    }
                    try writeIndent(&buf, allocator, indent);
                } else {
                    try buf.append(allocator, ' ');
                }
                try buf.appendSlice(allocator, tok.text);
                at_line_start = false;
                prev_kind = .comment;
                continue;
            },

            .rbrace => {
                if (indent > 0) indent -= 1;
                if (!at_line_start) {
                    // Force } onto its own line
                    try buf.append(allocator, '\n');
                    at_line_start = true;
                }
                if (blank_line_pending) {
                    try buf.append(allocator, '\n');
                    blank_line_pending = false;
                }
                try writeIndent(&buf, allocator, indent);
                try buf.append(allocator, '}');
                at_line_start = false;
                prev_kind = .rbrace;
                continue;
            },

            .at_keyword => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                try buf.append(allocator, '@');
                try buf.appendSlice(allocator, tok.text);
                try buf.append(allocator, ' ');
            },

            .identifier => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                if (spaceBetween(prev_kind)) try buf.append(allocator, ' ');
                try buf.appendSlice(allocator, tok.text);
            },

            .string => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                if (spaceBetween(prev_kind)) try buf.append(allocator, ' ');
                try buf.append(allocator, '"');
                try buf.appendSlice(allocator, tok.text);
                try buf.append(allocator, '"');
            },

            .class => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                if (prev_kind != .eof and prev_kind != .newline) try buf.append(allocator, ' ');
                try buf.append(allocator, '.');
                try buf.appendSlice(allocator, tok.text);
            },

            .colon => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                try buf.appendSlice(allocator, ": ");
            },

            .comma => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                try buf.appendSlice(allocator, ", ");
            },

            .semicolon => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                try buf.appendSlice(allocator, "; ");
            },

            .pipe => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                if (prev_kind != .lbracket) try buf.append(allocator, ' ');
                try buf.appendSlice(allocator, "| ");
            },

            .lbrace => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                if (prev_kind != .newline and prev_kind != .eof) try buf.append(allocator, ' ');
                try buf.append(allocator, '{');
                indent += 1;
                // Always start a new line after {
                try buf.append(allocator, '\n');
                at_line_start = true;
            },

            .lbracket => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                if (spaceBetween(prev_kind)) try buf.append(allocator, ' ');
                try buf.append(allocator, '[');
            },

            .rbracket => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                try buf.append(allocator, ']');
            },

            .dot => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                try buf.append(allocator, '.');
            },

            .arrow, .arrow_reverse, .dash_dash, .arrow_bidi,
            .fat_arrow, .fat_arrow2, .dashed_arrow, .dotted_arrow, .dotted_line => {
                try emitLineStart(&buf, allocator, &at_line_start, &blank_line_pending, indent);
                try buf.append(allocator, ' ');
                try buf.appendSlice(allocator, edgeOpText(tok.kind));
                try buf.append(allocator, ' ');
            },
        }

        prev_kind = tok.kind;
    }

    // Ensure trailing newline
    if (buf.items.len > 0 and buf.items[buf.items.len - 1] != '\n') {
        try buf.append(allocator, '\n');
    }

    return buf.toOwnedSlice(allocator);
}

fn emitLineStart(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, at_line_start: *bool, blank_line_pending: *bool, indent: u32) !void {
    if (at_line_start.*) {
        if (blank_line_pending.*) {
            try buf.append(allocator, '\n');
            blank_line_pending.* = false;
        }
        try writeIndent(buf, allocator, indent);
        at_line_start.* = false;
    }
}

fn writeIndent(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, level: u32) !void {
    var j: u32 = 0;
    while (j < level * 2) : (j += 1) {
        try buf.append(allocator, ' ');
    }
}

/// Returns true when previous token needs a space after it before a content token.
fn spaceBetween(prev: TokenKind) bool {
    return switch (prev) {
        .identifier, .string, .rbrace, .rbracket => true,
        else => false,
    };
}

fn edgeOpText(kind: TokenKind) []const u8 {
    return switch (kind) {
        .arrow => "->",
        .arrow_reverse => "<-",
        .dash_dash => "--",
        .arrow_bidi => "<->",
        .fat_arrow => "=>",
        .fat_arrow2 => "==>",
        .dashed_arrow => "-.->",
        .dotted_arrow => "-..->" ,
        .dotted_line => "-..-",
        else => "",
    };
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "format simple edge" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "A  ->  B  ->  C");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("A -> B -> C\n", result);
}

test "format preserves comments" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "# header comment\nA -> B");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("# header comment\nA -> B\n", result);
}

test "format normalizes indentation" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "pipeline [dag] {\nA -> B\n}");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pipeline [dag] {\n  A -> B\n}\n", result);
}

test "format directive" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "@layout  sugiyama");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("@layout sugiyama\n", result);
}

test "format node with label" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "db:\"PostgreSQL\"");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("db: \"PostgreSQL\"\n", result);
}

test "format collapses blank lines" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "A -> B\n\n\n\nC -> D");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("A -> B\n\nC -> D\n", result);
}

test "format properties block" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "db: \"PostgreSQL\"  { shape: cylinder }");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("db: \"PostgreSQL\" {\n  shape: cylinder\n}\n", result);
}

test "format edge with label" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "A -> B:\"query\"");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("A -> B: \"query\"\n", result);
}

test "format vars block" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "vars {\nenv: production\ndb: PostgreSQL\n}");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("vars {\n  env: production\n  db: PostgreSQL\n}\n", result);
}

test "format named block with layout" {
    const allocator = std.testing.allocator;
    const result = try format(allocator, "pipeline  [flow]  {\n  A -> B -> C\n}");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pipeline [flow] {\n  A -> B -> C\n}\n", result);
}

test "format is idempotent" {
    const allocator = std.testing.allocator;
    const input = "# comment\n@layout sugiyama\n\nA -> B: \"edge\"\nbackend [dag] {\n  X -> Y\n}\n";
    const first = try format(allocator, input);
    defer allocator.free(first);
    const second = try format(allocator, first);
    defer allocator.free(second);
    try std.testing.expectEqualStrings(first, second);
}
