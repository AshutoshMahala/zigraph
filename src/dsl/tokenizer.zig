const std = @import("std");
const errors = @import("errors.zig");
const Loc = errors.Loc;

pub const TokenKind = enum {
    identifier,
    string,
    arrow,          // ->
    arrow_reverse,  // <-
    dash_dash,      // --
    arrow_bidi,     // <->
    fat_arrow,      // =>
    fat_arrow2,     // ==>
    dashed_arrow,   // -.->
    dotted_arrow,   // -..->
    dotted_line,    // -..-
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    colon,
    comma,
    semicolon,
    pipe,
    dot,
    at_keyword,     // @layout, @theme, @style, @direction, @spacing
    class,          // .classname
    newline,
    comment,
    eof,
};

pub const Token = struct {
    kind: TokenKind,
    text: []const u8,
    loc: Loc,
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8, err_list: *errors.ErrorList) ![]Token {
    var tokens: std.ArrayListUnmanaged(Token) = .{};
    defer tokens.deinit(allocator);

    var line: u32 = 1;
    var col: u32 = 1;
    var i: usize = 0;

    while (i < source.len) {
        const c = source[i];

        if (c == ' ' or c == '\t') { i += 1; col += 1; continue; }

        if (c == '\n') {
            try tokens.append(allocator, .{ .kind = .newline, .text = "\n", .loc = .{ .line = line, .col = col, .offset = @intCast(i) } });
            i += 1; line += 1; col = 1; continue;
        }
        if (c == '\r') { i += 1; continue; }

        const loc = Loc{ .line = line, .col = col, .offset = @intCast(i) };

        // Comment
        if (c == '#') {
            const start = i;
            while (i < source.len and source[i] != '\n') : (i += 1) {}
            try tokens.append(allocator, .{ .kind = .comment, .text = source[start..i], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // @ directive
        if (c == '@') {
            const start = i;
            i += 1;
            while (i < source.len and (std.ascii.isAlphabetic(source[i]) or source[i] == '_')) : (i += 1) {}
            try tokens.append(allocator, .{ .kind = .at_keyword, .text = source[start..i], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // String literal
        if (c == '"') {
            const start = i;
            i += 1;
            while (i < source.len and source[i] != '"' and source[i] != '\n') : (i += 1) {}
            if (i >= source.len or source[i] == '\n') {
                try err_list.add(loc, .unterminated_string, "unterminated string literal");
                continue;
            }
            i += 1;
            try tokens.append(allocator, .{ .kind = .string, .text = source[start + 1 .. i - 1], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // Multi-char operators starting with '-'
        if (c == '-') {
            if (matchStr(source, i, "-..->")) {
                try tokens.append(allocator, .{ .kind = .dotted_arrow, .text = "-..->" , .loc = loc });
                i += 5; col += 5; continue;
            }
            if (matchStr(source, i, "-.->")) {
                try tokens.append(allocator, .{ .kind = .dashed_arrow, .text = "-.->" , .loc = loc });
                i += 4; col += 4; continue;
            }
            if (matchStr(source, i, "-..-")) {
                try tokens.append(allocator, .{ .kind = .dotted_line, .text = "-..-" , .loc = loc });
                i += 4; col += 4; continue;
            }
            if (matchStr(source, i, "->")) {
                try tokens.append(allocator, .{ .kind = .arrow, .text = "->" , .loc = loc });
                i += 2; col += 2; continue;
            }
            if (matchStr(source, i, "--")) {
                try tokens.append(allocator, .{ .kind = .dash_dash, .text = "--" , .loc = loc });
                i += 2; col += 2; continue;
            }
            try err_list.add(loc, .unexpected_character, "unexpected '-'");
            i += 1; col += 1; continue;
        }

        // Operators starting with '<'
        if (c == '<') {
            if (matchStr(source, i, "<->")) {
                try tokens.append(allocator, .{ .kind = .arrow_bidi, .text = "<->" , .loc = loc });
                i += 3; col += 3; continue;
            }
            if (matchStr(source, i, "<-")) {
                try tokens.append(allocator, .{ .kind = .arrow_reverse, .text = "<-" , .loc = loc });
                i += 2; col += 2; continue;
            }
            try err_list.add(loc, .unexpected_character, "unexpected '<'");
            i += 1; col += 1; continue;
        }

        // Operators starting with '='
        if (c == '=') {
            if (matchStr(source, i, "==>")) {
                try tokens.append(allocator, .{ .kind = .fat_arrow2, .text = "==>" , .loc = loc });
                i += 3; col += 3; continue;
            }
            if (matchStr(source, i, "=>")) {
                try tokens.append(allocator, .{ .kind = .fat_arrow, .text = "=>" , .loc = loc });
                i += 2; col += 2; continue;
            }
            try err_list.add(loc, .unexpected_character, "unexpected '='");
            i += 1; col += 1; continue;
        }

        // Single-char delimiters
        if (c == '{') { try tokens.append(allocator, .{ .kind = .lbrace, .text = "{", .loc = loc }); i += 1; col += 1; continue; }
        if (c == '}') { try tokens.append(allocator, .{ .kind = .rbrace, .text = "}", .loc = loc }); i += 1; col += 1; continue; }
        if (c == '[') { try tokens.append(allocator, .{ .kind = .lbracket, .text = "[", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ']') { try tokens.append(allocator, .{ .kind = .rbracket, .text = "]", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ':') { try tokens.append(allocator, .{ .kind = .colon, .text = ":", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ',') { try tokens.append(allocator, .{ .kind = .comma, .text = ",", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ';') { try tokens.append(allocator, .{ .kind = .semicolon, .text = ";", .loc = loc }); i += 1; col += 1; continue; }
        if (c == '|') { try tokens.append(allocator, .{ .kind = .pipe, .text = "|", .loc = loc }); i += 1; col += 1; continue; }

        // Dot: class reference or standalone
        if (c == '.') {
            if (i + 1 < source.len and isIdentStart(source[i + 1])) {
                const start = i;
                i += 1;
                while (i < source.len and isIdentContinue(source[i])) : (i += 1) {}
                try tokens.append(allocator, .{ .kind = .class, .text = source[start + 1 .. i], .loc = loc });
                col += @intCast(i - start);
                continue;
            }
            try tokens.append(allocator, .{ .kind = .dot, .text = ".", .loc = loc });
            i += 1; col += 1; continue;
        }

        // Numeric identifier (for card fields like 8080, version numbers, etc.)
        if (std.ascii.isDigit(c)) {
            const start = i;
            while (i < source.len and isIdentContinue(source[i])) : (i += 1) {}
            try tokens.append(allocator, .{ .kind = .identifier, .text = source[start..i], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // Identifier (including dot-paths like frontend.App)
        if (isIdentStart(c)) {
            const start = i;
            while (i < source.len and (isIdentContinue(source[i]) or source[i] == '.')) : (i += 1) {}
            if (i > start and source[i - 1] == '.') { i -= 1; }
            try tokens.append(allocator, .{ .kind = .identifier, .text = source[start..i], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        try err_list.add(loc, .unexpected_character, "unexpected character");
        i += 1; col += 1;
    }

    try tokens.append(allocator, .{ .kind = .eof, .text = "", .loc = .{ .line = line, .col = col, .offset = @intCast(source.len) } });
    return tokens.toOwnedSlice(allocator);
}

fn matchStr(source: []const u8, pos: usize, needle: []const u8) bool {
    if (pos + needle.len > source.len) return false;
    return std.mem.eql(u8, source[pos..][0..needle.len], needle);
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

test "tokenize simple edge" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "A -> B", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("A", tokens[0].text);
    try std.testing.expectEqual(TokenKind.arrow, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
    try std.testing.expectEqualStrings("B", tokens[2].text);
    try std.testing.expectEqual(TokenKind.eof, tokens[3].kind);
}

test "tokenize all edge operators" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "-> <- -- <-> => ==> -.-> -..-> -..-", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.arrow, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.arrow_reverse, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.dash_dash, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.arrow_bidi, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.fat_arrow, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.fat_arrow2, tokens[5].kind);
    try std.testing.expectEqual(TokenKind.dashed_arrow, tokens[6].kind);
    try std.testing.expectEqual(TokenKind.dotted_arrow, tokens[7].kind);
    try std.testing.expectEqual(TokenKind.dotted_line, tokens[8].kind);
}

test "tokenize directive and string" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "@layout sugiyama\ndb: \"PostgreSQL\"", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.at_keyword, tokens[0].kind);
    try std.testing.expectEqualStrings("@layout", tokens[0].text);
    try std.testing.expectEqual(TokenKind.identifier, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.newline, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.colon, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.string, tokens[5].kind);
    try std.testing.expectEqualStrings("PostgreSQL", tokens[5].text);
}

test "tokenize class references" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "db .database .large", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.class, tokens[1].kind);
    try std.testing.expectEqualStrings("database", tokens[1].text);
    try std.testing.expectEqual(TokenKind.class, tokens[2].kind);
    try std.testing.expectEqualStrings("large", tokens[2].text);
}

test "tokenize comment" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "# this is a comment\nA -> B", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.comment, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.newline, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
}

test "tokenize dot-path identifier" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "frontend.App -> backend.API", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("frontend.App", tokens[0].text);
    try std.testing.expectEqual(TokenKind.arrow, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
    try std.testing.expectEqualStrings("backend.API", tokens[2].text);
}

test "tokenize card bracket syntax" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "svc: [Auth | Port: 8080]", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.colon, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.lbracket, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.pipe, tokens[4].kind);
}

test "tokenize braces and named block" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenize(std.testing.allocator, "pipeline [dag] {\n  A -> B\n}", &err_list);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("pipeline", tokens[0].text);
    try std.testing.expectEqual(TokenKind.lbracket, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
    try std.testing.expectEqualStrings("dag", tokens[2].text);
    try std.testing.expectEqual(TokenKind.rbracket, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.lbrace, tokens[4].kind);
}
