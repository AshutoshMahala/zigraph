const std = @import("std");
const ast = @import("ast.zig");
const tokenizer = @import("tokenizer.zig");
const errors = @import("errors.zig");

const Token = tokenizer.Token;
const TokenKind = tokenizer.TokenKind;

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: std.mem.Allocator,
    err_list: *errors.ErrorList,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, err_list: *errors.ErrorList) Parser {
        return .{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
            .err_list = err_list,
        };
    }

    // ---------- helpers ----------

    fn peek(self: *Parser) Token {
        return self.peekAt(0);
    }

    fn peekAt(self: *Parser, offset: usize) Token {
        const idx = self.pos + offset;
        if (idx >= self.tokens.len) return self.tokens[self.tokens.len - 1]; // eof
        return self.tokens[idx];
    }

    fn advance(self: *Parser) void {
        if (self.pos < self.tokens.len) self.pos += 1;
    }

    fn skipNewlines(self: *Parser) void {
        while (self.peek().kind == .newline or self.peek().kind == .comment) {
            self.advance();
        }
    }

    fn isEdgeOp(kind: TokenKind) bool {
        return switch (kind) {
            .arrow, .arrow_reverse, .dash_dash, .arrow_bidi,
            .fat_arrow, .fat_arrow2, .dashed_arrow, .dotted_arrow, .dotted_line => true,
            else => false,
        };
    }

    fn edgeOpFromToken(kind: TokenKind) ?ast.EdgeOp {
        return switch (kind) {
            .arrow          => .directed,
            .arrow_reverse  => .reverse,
            .dash_dash      => .undirected,
            .arrow_bidi     => .bidirectional,
            .fat_arrow      => .bold,
            .fat_arrow2     => .bold_double,
            .dashed_arrow   => .dashed_directed,
            .dotted_arrow   => .dotted_directed,
            .dotted_line    => .dotted_undirected,
            else            => null,
        };
    }

    /// Look ahead to detect `identifier [layout] { ... }` without a colon.
    fn isNamedBlock(self: *Parser) bool {
        // peek(0) == identifier already confirmed by caller
        var i: usize = 1;
        // skip optional [layout]
        if (self.peekAt(i).kind == .lbracket) {
            // identifier rbracket ...
            i += 1;
            // skip the layout identifier
            if (self.peekAt(i).kind == .identifier) i += 1;
            if (self.peekAt(i).kind == .rbracket) i += 1;
        }
        return self.peekAt(i).kind == .lbrace;
    }

    /// Peek inside `{` to decide: does this block contain edge operators (subgraph)
    /// or only key:value pairs (property block)?
    fn isSubgraphBrace(self: *Parser) bool {
        // self.peek() should be lbrace; scan forward
        var i: usize = 1; // skip the lbrace itself
        var depth: usize = 0;
        while (true) {
            const t = self.peekAt(i);
            switch (t.kind) {
                .eof => return false,
                .lbrace => { depth += 1; i += 1; },
                .rbrace => {
                    if (depth == 0) return false;
                    depth -= 1;
                    i += 1;
                },
                .arrow, .arrow_reverse, .dash_dash, .arrow_bidi,
                .fat_arrow, .fat_arrow2, .dashed_arrow, .dotted_arrow, .dotted_line => {
                    if (depth == 0) return true;
                    i += 1;
                },
                else => i += 1,
            }
        }
    }

    // ---------- public entry ----------

    pub fn parse(self: *Parser) anyerror!ast.Document {
        var directives: std.ArrayListUnmanaged(ast.Directive) = .{};
        var styles: std.ArrayListUnmanaged(ast.StyleRule) = .{};
        var statements: std.ArrayListUnmanaged(ast.Statement) = .{};
        var blocks: std.ArrayListUnmanaged(ast.NamedBlock) = .{};
        var doc_vars: std.ArrayListUnmanaged(ast.Property) = .{};

        self.skipNewlines();

        while (self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .eof) break;

            const tok = self.peek();

            if (tok.kind == .at_keyword) {
                const kw = tok.text;
                if (std.mem.eql(u8, kw, "style")) {
                    const rule = try self.parseStyleRule();
                    try styles.append(self.allocator, rule);
                } else {
                    const dir = try self.parseDirective();
                    try directives.append(self.allocator, dir);
                }
                self.skipNewlines();
                continue;
            }

            if (tok.kind == .comment) {
                self.advance();
                continue;
            }

            if (tok.kind == .identifier) {
                // vars block: `vars { key: value ... }`
                if (std.mem.eql(u8, tok.text, "vars") and self.peekAt(1).kind == .lbrace) {
                    const parsed_vars = try self.parseVarsBlock();
                    try doc_vars.appendSlice(self.allocator, parsed_vars);
                    self.allocator.free(parsed_vars);
                    self.skipNewlines();
                    continue;
                }
                // named block: `name [layout] { ... }` (no colon before brace)
                if (self.isNamedBlock()) {
                    const blk = try self.parseNamedBlock();
                    try blocks.append(self.allocator, blk);
                    self.skipNewlines();
                    continue;
                }
                const stmt = try self.parseStatement();
                try statements.append(self.allocator, stmt);
                self.skipNewlines();
                continue;
            }

            // unexpected token — skip it
            try self.err_list.add(tok.loc, .unexpected_token, "unexpected token at top level");
            self.advance();
        }

        return ast.Document{
            .directives = try directives.toOwnedSlice(self.allocator),
            .styles     = try styles.toOwnedSlice(self.allocator),
            .statements = try statements.toOwnedSlice(self.allocator),
            .blocks     = try blocks.toOwnedSlice(self.allocator),
            .vars       = try doc_vars.toOwnedSlice(self.allocator),
        };
    }

    // ---------- statement dispatcher ----------

    fn parseStatement(self: *Parser) anyerror!ast.Statement {
        self.skipNewlines();
        const tok = self.peek();

        if (tok.kind != .identifier) {
            try self.err_list.add(tok.loc, .expected_identifier, "expected identifier");
            return error.ParseError;
        }

        // check what follows the identifier
        const next = self.peekAt(1);

        // edge: identifier <edge-op> ...
        if (isEdgeOp(next.kind)) {
            return .{ .edge = try self.parseEdge() };
        }

        // colon: node decl or subgraph
        if (next.kind == .colon) {
            return try self.parseNodeDeclOrSubgraph();
        }

        // node with class or property block — treat as node decl
        return .{ .node_decl = try self.parseNodeDecl() };
    }

    // ---------- edge ----------

    fn parseEdge(self: *Parser) anyerror!ast.EdgeStatement {
        const loc = self.peek().loc;

        // collect first node ref
        var chain: std.ArrayListUnmanaged(ast.NodeRef) = .{};
        const first = try self.parseNodeRef();
        try chain.append(self.allocator, first);

        // the edge operator comes next
        const op_tok = self.peek();
        const op = edgeOpFromToken(op_tok.kind) orelse {
            try self.err_list.add(op_tok.loc, .expected_arrow_or_operator, "expected edge operator");
            return error.ParseError;
        };
        self.advance();

        // optional label right after the operator: `-> "label"`
        var edge_label: ?[]const u8 = null;

        // collect targets; watch for fan-out (comma/brace) and chaining (another op)
        var fan_out = false;

        // brace fan-out: `A -> { B; C; D }`
        self.skipNewlines();
        if (self.peek().kind == .lbrace) {
            fan_out = true;
            self.advance(); // consume `{`
            self.skipNewlines();
            while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
                self.skipNewlines();
                if (self.peek().kind == .rbrace) break;
                const target = try self.parseNodeRef();
                try chain.append(self.allocator, target);
                // skip semicolons and newlines between targets
                if (self.peek().kind == .semicolon) self.advance();
                self.skipNewlines();
            }
            if (self.peek().kind == .rbrace) self.advance();
        } else {
            // parse the immediate next node ref
            const second = try self.parseNodeRef();
            try chain.append(self.allocator, second);

            // optional label after the second node ref: `A -> B: "label"`
            if (self.peek().kind == .colon) {
                self.advance();
                if (self.peek().kind == .string) {
                    edge_label = self.peek().text;
                    self.advance();
                }
            }

            // fan-out: `A -> B, C, D`
            if (self.peek().kind == .comma) {
                fan_out = true;
                while (self.peek().kind == .comma) {
                    self.advance(); // consume comma
                    self.skipNewlines();
                    const target = try self.parseNodeRef();
                    try chain.append(self.allocator, target);
                }
            }
        }

        // chaining: `A -> B -> C` (only when not fan-out)
        if (!fan_out) {
            while (isEdgeOp(self.peek().kind)) {
                const chain_op = edgeOpFromToken(self.peek().kind);
                if (chain_op != null and chain_op.? != op) {
                    try self.err_list.add(self.peek().loc, .unexpected_token, "mixed edge operators in chain; use same operator throughout");
                    break;
                }
                self.advance();
                self.skipNewlines();
                const next_node = try self.parseNodeRef();
                try chain.append(self.allocator, next_node);

                // optional label on chained segment
                if (self.peek().kind == .colon) {
                    self.advance();
                    if (self.peek().kind == .string) {
                        edge_label = self.peek().text; // last label wins
                        self.advance();
                    }
                }
            }
        }

        // optional property block / classes at end
        var props: ?ast.PropertyBlock = null;
        var classes: std.ArrayListUnmanaged([]const u8) = .{};

        while (self.peek().kind == .class) {
            try classes.append(self.allocator, self.peek().text);
            self.advance();
        }
        if (self.peek().kind == .lbrace and !self.isSubgraphBrace()) {
            props = try self.parsePropertyBlock();
        }

        return ast.EdgeStatement{
            .chain      = try chain.toOwnedSlice(self.allocator),
            .operator   = op,
            .label      = edge_label,
            .properties = props,
            .classes    = try classes.toOwnedSlice(self.allocator),
            .fan_out    = fan_out,
            .loc        = loc,
        };
    }

    fn parseNodeRef(self: *Parser) anyerror!ast.NodeRef {
        const tok = self.peek();
        if (tok.kind != .identifier) {
            try self.err_list.add(tok.loc, .expected_identifier, "expected node identifier");
            return error.ParseError;
        }
        self.advance();
        return ast.NodeRef{
            .id  = tok.text,
            .loc = tok.loc,
        };
    }

    // ---------- node declaration ----------

    fn parseNodeDecl(self: *Parser) anyerror!ast.NodeDecl {
        const loc = self.peek().loc;
        const id_tok = self.peek();
        if (id_tok.kind != .identifier) {
            try self.err_list.add(id_tok.loc, .expected_identifier, "expected node identifier");
            return error.ParseError;
        }
        self.advance();

        var label: ?[]const u8 = null;
        var card_fields: ?[]const []const u8 = null;
        var props: ?ast.PropertyBlock = null;
        var classes: std.ArrayListUnmanaged([]const u8) = .{};

        // optional colon followed by label / bracket / property block
        if (self.peek().kind == .colon) {
            self.advance();

            if (self.peek().kind == .string) {
                label = self.peek().text;
                self.advance();
            } else if (self.peek().kind == .lbracket) {
                card_fields = try self.parseCardFields();
            }
        }

        // optional classes
        while (self.peek().kind == .class) {
            try classes.append(self.allocator, self.peek().text);
            self.advance();
        }

        // optional property block
        if (self.peek().kind == .lbrace and !self.isSubgraphBrace()) {
            props = try self.parsePropertyBlock();
        }

        // optional card fields after property block (edge case)
        if (card_fields == null and self.peek().kind == .lbracket) {
            card_fields = try self.parseCardFields();
        }

        const ref = ast.NodeRef{
            .id          = id_tok.text,
            .label       = label,
            .card_fields = card_fields,
            .properties  = props,
            .classes     = try classes.toOwnedSlice(self.allocator),
            .loc         = loc,
        };
        return ast.NodeDecl{ .ref = ref, .loc = loc };
    }

    // ---------- subgraph / node disambiguator ----------

    fn parseNodeDeclOrSubgraph(self: *Parser) anyerror!ast.Statement {
        // peek(0) == identifier, peek(1) == colon
        const id_tok = self.peek();
        const loc = id_tok.loc;
        self.advance(); // consume identifier
        self.advance(); // consume colon

        self.skipNewlines();

        // After `name:` we might have `{` — check whether it is a subgraph or property block
        if (self.peek().kind == .lbrace) {
            if (self.isSubgraphBrace()) {
                // subgraph
                return .{ .subgraph = try self.parseSubgraphBody(id_tok.text, loc) };
            } else {
                // node with property block
                var classes: std.ArrayListUnmanaged([]const u8) = .{};
                const props = try self.parsePropertyBlock();
                while (self.peek().kind == .class) {
                    try classes.append(self.allocator, self.peek().text);
                    self.advance();
                }
                const ref = ast.NodeRef{
                    .id         = id_tok.text,
                    .properties = props,
                    .classes    = try classes.toOwnedSlice(self.allocator),
                    .loc        = loc,
                };
                return .{ .node_decl = ast.NodeDecl{ .ref = ref, .loc = loc } };
            }
        }

        // After `name:` we might have a string label
        var label: ?[]const u8 = null;
        if (self.peek().kind == .string) {
            label = self.peek().text;
            self.advance();
        }

        // optional card fields
        var card_fields: ?[]const []const u8 = null;
        if (self.peek().kind == .lbracket) {
            card_fields = try self.parseCardFields();
        }

        // optional classes
        var classes: std.ArrayListUnmanaged([]const u8) = .{};
        while (self.peek().kind == .class) {
            try classes.append(self.allocator, self.peek().text);
            self.advance();
        }

        // optional property block
        var props: ?ast.PropertyBlock = null;
        if (self.peek().kind == .lbrace and !self.isSubgraphBrace()) {
            props = try self.parsePropertyBlock();
        }

        // if after all that we now see `{` and it IS a subgraph — shouldn't happen here
        // because we already consumed the colon.

        const ref = ast.NodeRef{
            .id          = id_tok.text,
            .label       = label,
            .card_fields = card_fields,
            .properties  = props,
            .classes     = try classes.toOwnedSlice(self.allocator),
            .loc         = loc,
        };
        return .{ .node_decl = ast.NodeDecl{ .ref = ref, .loc = loc } };
    }

    // ---------- subgraph body ----------

    fn parseSubgraphBody(self: *Parser, name: []const u8, loc: errors.Loc) anyerror!ast.SubgraphDecl {
        // consume `{`
        if (self.peek().kind != .lbrace) {
            try self.err_list.add(self.peek().loc, .expected_closing_brace, "expected '{'");
            return error.ParseError;
        }
        self.advance();

        var statements: std.ArrayListUnmanaged(ast.Statement) = .{};

        self.skipNewlines();
        while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .rbrace or self.peek().kind == .eof) break;

            if (self.peek().kind == .comment) { self.advance(); continue; }

            if (self.peek().kind == .identifier) {
                const stmt = try self.parseStatement();
                try statements.append(self.allocator, stmt);
            } else {
                try self.err_list.add(self.peek().loc, .unexpected_token, "unexpected token in subgraph");
                self.advance();
            }
            self.skipNewlines();
        }

        if (self.peek().kind == .rbrace) {
            self.advance();
        } else {
            try self.err_list.add(self.peek().loc, .unterminated_block, "unterminated subgraph block");
        }

        return ast.SubgraphDecl{
            .name       = name,
            .statements = try statements.toOwnedSlice(self.allocator),
            .loc        = loc,
        };
    }

    // ---------- property block ----------

    fn parsePropertyBlock(self: *Parser) anyerror!ast.PropertyBlock {
        const loc = self.peek().loc;
        if (self.peek().kind != .lbrace) {
            try self.err_list.add(loc, .expected_closing_brace, "expected '{'");
            return error.ParseError;
        }
        self.advance(); // consume `{`

        var props: std.ArrayListUnmanaged(ast.Property) = .{};

        self.skipNewlines();
        while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .rbrace) break;

            const key_tok = self.peek();
            if (key_tok.kind != .identifier) {
                try self.err_list.add(key_tok.loc, .expected_identifier, "expected property key");
                self.advance();
                continue;
            }
            self.advance();

            if (self.peek().kind != .colon) {
                try self.err_list.add(self.peek().loc, .unexpected_token, "expected ':' after property key");
                self.advance();
                continue;
            }
            self.advance(); // consume `:`

            const val_tok = self.peek();
            if (val_tok.kind != .identifier and val_tok.kind != .string) {
                try self.err_list.add(val_tok.loc, .invalid_property_value, "expected property value");
                self.advance();
                continue;
            }
            self.advance();

            try props.append(self.allocator, ast.Property{
                .key   = key_tok.text,
                .value = val_tok.text,
                .loc   = key_tok.loc,
            });

            // optional semicolon or newline separator
            if (self.peek().kind == .semicolon) self.advance();
            self.skipNewlines();
        }

        if (self.peek().kind == .rbrace) {
            self.advance();
        } else {
            try self.err_list.add(self.peek().loc, .unterminated_block, "unterminated property block");
        }

        return ast.PropertyBlock{
            .properties = try props.toOwnedSlice(self.allocator),
            .loc        = loc,
        };
    }

    // ---------- card fields ----------

    fn parseCardFields(self: *Parser) anyerror![]const []const u8 {
        // consume `[`
        if (self.peek().kind != .lbracket) {
            try self.err_list.add(self.peek().loc, .expected_closing_bracket, "expected '['");
            return error.ParseError;
        }
        self.advance();

        var fields: std.ArrayListUnmanaged([]const u8) = .{};

        // collect text until `]`, splitting on `|`
        var field_buf: std.ArrayListUnmanaged(u8) = .{};
        defer field_buf.deinit(self.allocator);

        while (self.peek().kind != .rbracket and self.peek().kind != .eof) {
            const tok = self.peek();
            switch (tok.kind) {
                .pipe => {
                    // end of this field
                    const trimmed = std.mem.trim(u8, field_buf.items, " \t");
                    const owned = try self.allocator.dupe(u8, trimmed);
                    try fields.append(self.allocator, owned);
                    field_buf.clearRetainingCapacity();
                    self.advance();
                },
                .identifier, .string => {
                    if (field_buf.items.len > 0) {
                        try field_buf.append(self.allocator, ' ');
                    }
                    try field_buf.appendSlice(self.allocator, tok.text);
                    self.advance();
                },
                .colon => {
                    try field_buf.appendSlice(self.allocator, ": ");
                    self.advance();
                },
                .newline, .comment => self.advance(),
                else => {
                    try field_buf.appendSlice(self.allocator, tok.text);
                    self.advance();
                },
            }
        }

        // last field
        const trimmed = std.mem.trim(u8, field_buf.items, " \t");
        if (trimmed.len > 0) {
            const owned = try self.allocator.dupe(u8, trimmed);
            try fields.append(self.allocator, owned);
        }

        if (self.peek().kind == .rbracket) {
            self.advance();
        } else {
            try self.err_list.add(self.peek().loc, .expected_closing_bracket, "unterminated card field block");
        }

        return fields.toOwnedSlice(self.allocator);
    }

    // ---------- directive ----------

    fn parseDirective(self: *Parser) anyerror!ast.Directive {
        const tok = self.peek();
        if (tok.kind != .at_keyword) {
            try self.err_list.add(tok.loc, .unexpected_token, "expected directive");
            return error.ParseError;
        }
        self.advance();

        const kind = blk: {
            if (std.mem.eql(u8, tok.text, "layout"))    break :blk ast.DirectiveKind.layout;
            if (std.mem.eql(u8, tok.text, "theme"))     break :blk ast.DirectiveKind.theme;
            if (std.mem.eql(u8, tok.text, "direction")) break :blk ast.DirectiveKind.direction;
            if (std.mem.eql(u8, tok.text, "spacing"))   break :blk ast.DirectiveKind.spacing;
            try self.err_list.add(tok.loc, .unknown_directive, "unknown directive");
            return error.ParseError;
        };

        const val_tok = self.peek();
        if (val_tok.kind != .identifier and val_tok.kind != .string) {
            try self.err_list.add(val_tok.loc, .unexpected_token, "expected directive value");
            return error.ParseError;
        }
        self.advance();

        return ast.Directive{
            .kind  = kind,
            .value = val_tok.text,
            .loc   = tok.loc,
        };
    }

    // ---------- style rule ----------

    fn parseStyleRule(self: *Parser) anyerror!ast.StyleRule {
        const loc = self.peek().loc;
        if (self.peek().kind != .at_keyword or !std.mem.eql(u8, self.peek().text, "style")) {
            try self.err_list.add(loc, .unexpected_token, "expected '@style'");
            return error.ParseError;
        }
        self.advance(); // consume @style

        // selector: identifier (node/edge) or class (.classname)
        const sel_tok = self.peek();
        var selector: ast.StyleSelector = undefined;

        if (sel_tok.kind == .class) {
            selector = .{ .class = sel_tok.text };
            self.advance();
        } else if (sel_tok.kind == .identifier) {
            if (std.mem.eql(u8, sel_tok.text, "node")) {
                selector = .{ .element = .node };
            } else if (std.mem.eql(u8, sel_tok.text, "edge")) {
                selector = .{ .element = .edge };
            } else {
                try self.err_list.add(sel_tok.loc, .unexpected_token, "expected 'node', 'edge', or class selector");
                return error.ParseError;
            }
            self.advance();
        } else {
            try self.err_list.add(sel_tok.loc, .unexpected_token, "expected style selector");
            return error.ParseError;
        }

        self.skipNewlines();
        const props = try self.parsePropertyBlock();

        return ast.StyleRule{
            .selector   = selector,
            .properties = props,
            .loc        = loc,
        };
    }

    // ---------- named block ----------

    fn parseNamedBlock(self: *Parser) anyerror!ast.NamedBlock {
        const loc = self.peek().loc;
        const name_tok = self.peek();
        if (name_tok.kind != .identifier) {
            try self.err_list.add(name_tok.loc, .expected_identifier, "expected block name");
            return error.ParseError;
        }
        self.advance();

        // optional [layout]
        var layout: ?ast.Layout = null;
        if (self.peek().kind == .lbracket) {
            self.advance(); // consume `[`
            const lt_tok = self.peek();
            if (lt_tok.kind == .identifier) {
                if (std.mem.eql(u8, lt_tok.text, "dag"))   layout = .dag
                else if (std.mem.eql(u8, lt_tok.text, "tree"))  layout = .tree
                else if (std.mem.eql(u8, lt_tok.text, "force")) layout = .force
                else try self.err_list.add(lt_tok.loc, .unknown_layout_type, "unknown layout type");
                self.advance();
            }
            if (self.peek().kind == .rbracket) self.advance();
        }

        // consume `{`
        if (self.peek().kind != .lbrace) {
            try self.err_list.add(self.peek().loc, .expected_closing_brace, "expected '{' for named block");
            return error.ParseError;
        }
        self.advance();

        var directives: std.ArrayListUnmanaged(ast.Directive) = .{};
        var styles: std.ArrayListUnmanaged(ast.StyleRule) = .{};
        var stmts: std.ArrayListUnmanaged(ast.Statement) = .{};
        var block_vars: std.ArrayListUnmanaged(ast.Property) = .{};

        self.skipNewlines();
        while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .rbrace or self.peek().kind == .eof) break;
            if (self.peek().kind == .comment) { self.advance(); continue; }

            const tok = self.peek();
            if (tok.kind == .at_keyword) {
                if (std.mem.eql(u8, tok.text, "style")) {
                    const rule = try self.parseStyleRule();
                    try styles.append(self.allocator, rule);
                } else {
                    const dir = try self.parseDirective();
                    try directives.append(self.allocator, dir);
                }
                self.skipNewlines();
                continue;
            }

            if (tok.kind == .identifier) {
                // vars block inside named block
                if (std.mem.eql(u8, tok.text, "vars") and self.peekAt(1).kind == .lbrace) {
                    const parsed_vars = try self.parseVarsBlock();
                    try block_vars.appendSlice(self.allocator, parsed_vars);
                    self.allocator.free(parsed_vars);
                    self.skipNewlines();
                    continue;
                }
                const stmt = try self.parseStatement();
                try stmts.append(self.allocator, stmt);
                self.skipNewlines();
                continue;
            }

            try self.err_list.add(tok.loc, .unexpected_token, "unexpected token in named block");
            self.advance();
        }

        if (self.peek().kind == .rbrace) {
            self.advance();
        } else {
            try self.err_list.add(self.peek().loc, .unterminated_block, "unterminated named block");
        }

        return ast.NamedBlock{
            .name       = name_tok.text,
            .layout     = layout,
            .directives = try directives.toOwnedSlice(self.allocator),
            .styles     = try styles.toOwnedSlice(self.allocator),
            .statements = try stmts.toOwnedSlice(self.allocator),
            .vars       = try block_vars.toOwnedSlice(self.allocator),
            .loc        = loc,
        };
    }

    // ---------- vars block ----------

    fn parseVarsBlock(self: *Parser) anyerror![]ast.Property {
        // consume "vars"
        self.advance();
        self.skipNewlines();

        // consume `{`
        if (self.peek().kind != .lbrace) {
            try self.err_list.add(self.peek().loc, .expected_closing_brace, "expected '{' after 'vars'");
            return error.ParseError;
        }
        self.advance();

        var props: std.ArrayListUnmanaged(ast.Property) = .{};

        self.skipNewlines();
        while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .rbrace) break;

            const key_tok = self.peek();
            if (key_tok.kind != .identifier) {
                try self.err_list.add(key_tok.loc, .expected_identifier, "expected variable key");
                self.advance();
                continue;
            }
            self.advance();

            if (self.peek().kind != .colon) {
                try self.err_list.add(self.peek().loc, .unexpected_token, "expected ':' after variable key");
                self.advance();
                continue;
            }
            self.advance(); // consume `:`

            const val_tok = self.peek();
            if (val_tok.kind != .identifier and val_tok.kind != .string) {
                try self.err_list.add(val_tok.loc, .invalid_property_value, "expected variable value");
                self.advance();
                continue;
            }
            self.advance();

            try props.append(self.allocator, ast.Property{
                .key   = key_tok.text,
                .value = val_tok.text,
                .loc   = key_tok.loc,
            });

            if (self.peek().kind == .semicolon) self.advance();
            self.skipNewlines();
        }

        if (self.peek().kind == .rbrace) {
            self.advance();
        } else {
            try self.err_list.add(self.peek().loc, .unterminated_block, "unterminated vars block");
        }

        return props.toOwnedSlice(self.allocator);
    }
};

// ============================================================
// Tests
// ============================================================

fn testParse(source: []const u8) !struct { doc: ast.Document, err_list: errors.ErrorList } {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    const tokens = try tokenizer.tokenize(std.testing.allocator, source, &err_list);
    var parser = Parser.init(std.testing.allocator, tokens, &err_list);
    const doc = try parser.parse();
    std.testing.allocator.free(tokens);
    return .{ .doc = doc, .err_list = err_list };
}

fn freeDoc(doc: ast.Document) void {
    // Free top-level slices
    std.testing.allocator.free(doc.directives);
    for (doc.styles) |sr| std.testing.allocator.free(sr.properties.properties);
    std.testing.allocator.free(doc.styles);
    for (doc.statements) |stmt| freeStatement(stmt);
    std.testing.allocator.free(doc.statements);
    for (doc.blocks) |blk| freeBlock(blk);
    std.testing.allocator.free(doc.blocks);
    std.testing.allocator.free(doc.vars);
}

fn freeStatement(stmt: ast.Statement) void {
    switch (stmt) {
        .edge => |e| {
            for (e.chain) |ref| freeNodeRef(ref);
            std.testing.allocator.free(e.chain);
            std.testing.allocator.free(e.classes);
            if (e.properties) |pb| std.testing.allocator.free(pb.properties);
        },
        .node_decl => |nd| {
            freeNodeRef(nd.ref);
        },
        .subgraph => |sg| {
            for (sg.statements) |s| freeStatement(s);
            std.testing.allocator.free(sg.statements);
            if (sg.properties) |pb| std.testing.allocator.free(pb.properties);
        },
        .table_headers, .table_row, .vars_block => {},
    }
}

fn freeNodeRef(ref: ast.NodeRef) void {
    std.testing.allocator.free(ref.classes);
    if (ref.properties) |pb| std.testing.allocator.free(pb.properties);
    if (ref.card_fields) |cf| {
        for (cf) |f| std.testing.allocator.free(f);
        std.testing.allocator.free(cf);
    }
}

fn freeBlock(blk: ast.NamedBlock) void {
    std.testing.allocator.free(blk.directives);
    for (blk.styles) |sr| std.testing.allocator.free(sr.properties.properties);
    std.testing.allocator.free(blk.styles);
    for (blk.statements) |s| freeStatement(s);
    std.testing.allocator.free(blk.statements);
    std.testing.allocator.free(blk.vars);
}

test "parse simple edge" {
    const result = try testParse("A -> B");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);
    const edge = result.doc.statements[0].edge;
    try std.testing.expectEqual(ast.EdgeOp.directed, edge.operator);
    try std.testing.expectEqual(@as(usize, 2), edge.chain.len);
    try std.testing.expectEqualStrings("A", edge.chain[0].id);
    try std.testing.expectEqualStrings("B", edge.chain[1].id);
}

test "parse chained edge" {
    const result = try testParse("A -> B -> C -> D");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    const edge = result.doc.statements[0].edge;
    try std.testing.expectEqual(@as(usize, 4), edge.chain.len);
    try std.testing.expectEqualStrings("D", edge.chain[3].id);
}

test "parse edge with label" {
    const result = try testParse("A -> B: \"transforms\"");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    const edge = result.doc.statements[0].edge;
    try std.testing.expect(edge.label != null);
    try std.testing.expectEqualStrings("transforms", edge.label.?);
}

test "parse node declaration with label" {
    const result = try testParse("db: \"PostgreSQL 15\"");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);
    const nd = result.doc.statements[0].node_decl;
    try std.testing.expectEqualStrings("db", nd.ref.id);
    try std.testing.expectEqualStrings("PostgreSQL 15", nd.ref.label.?);
}

test "parse directive" {
    const result = try testParse("@layout sugiyama");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.directives.len);
    try std.testing.expectEqual(ast.DirectiveKind.layout, result.doc.directives[0].kind);
    try std.testing.expectEqualStrings("sugiyama", result.doc.directives[0].value);
}

test "parse style rule" {
    const result = try testParse("@style .database { shape: cylinder }");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.styles.len);
    const rule = result.doc.styles[0];
    try std.testing.expectEqualStrings("database", rule.selector.class);
    try std.testing.expectEqual(@as(usize, 1), rule.properties.properties.len);
    try std.testing.expectEqualStrings("shape", rule.properties.properties[0].key);
    try std.testing.expectEqualStrings("cylinder", rule.properties.properties[0].value);
}

test "parse named block" {
    const result = try testParse("pipeline [dag] { A -> B }");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.blocks.len);
    const blk = result.doc.blocks[0];
    try std.testing.expectEqualStrings("pipeline", blk.name);
    try std.testing.expectEqual(ast.Layout.dag, blk.layout.?);
    try std.testing.expectEqual(@as(usize, 1), blk.statements.len);
}

test "parse subgraph" {
    const result = try testParse("backend: { API -> DB }");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);
    const sg = result.doc.statements[0].subgraph;
    try std.testing.expectEqualStrings("backend", sg.name);
    try std.testing.expectEqual(@as(usize, 1), sg.statements.len);
}

test "parse card fields" {
    const result = try testParse("svc: [Auth Service | Port: 8080 | Status: healthy]");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    const nd = result.doc.statements[0].node_decl;
    try std.testing.expect(nd.ref.card_fields != null);
    try std.testing.expectEqual(@as(usize, 3), nd.ref.card_fields.?.len);
}

test "parse brace fan-out" {
    const result = try testParse("A -> { B; C; D }");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);
    const edge = result.doc.statements[0].edge;
    try std.testing.expect(edge.fan_out);
    // chain: A, B, C, D
    try std.testing.expectEqual(@as(usize, 4), edge.chain.len);
    try std.testing.expectEqualStrings("A", edge.chain[0].id);
    try std.testing.expectEqualStrings("B", edge.chain[1].id);
    try std.testing.expectEqualStrings("C", edge.chain[2].id);
    try std.testing.expectEqualStrings("D", edge.chain[3].id);
}

test "parse mixed operators in chain reports error" {
    const result = try testParse("A -> B -- C");
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    // Should have an error about mixed operators
    try std.testing.expect(result.err_list.hasErrors());
}

test "parse full example" {
    const src =
        \\@layout sugiyama
        \\@theme dark
        \\
        \\@style .db { shape: cylinder }
        \\
        \\Client -> API: "HTTPS"
        \\API -> Auth
        \\
        \\backend: {
        \\  API -> DB
        \\  DB: "PostgreSQL" .db
        \\}
        \\
        \\modules [tree] {
        \\  app -> handlers
        \\  app -> models
        \\}
    ;
    const result = try testParse(src);
    defer freeDoc(result.doc);
    defer @constCast(&result.err_list).deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), result.doc.directives.len);
    try std.testing.expectEqual(@as(usize, 1), result.doc.styles.len);
    // 2 top-level edges + 1 subgraph = 3 statements
    try std.testing.expectEqual(@as(usize, 3), result.doc.statements.len);
    try std.testing.expectEqual(@as(usize, 1), result.doc.blocks.len);
}

test "parse vars block" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const source =
        \\vars {
        \\  env: production
        \\  db: PostgreSQL
        \\}
        \\A -> B
    ;
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);
    var p = Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();
    defer {
        allocator.free(doc.directives);
        for (doc.styles) |sr| allocator.free(sr.properties.properties);
        allocator.free(doc.styles);
        for (doc.statements) |stmt| freeStatement(stmt);
        allocator.free(doc.statements);
        for (doc.blocks) |blk| freeBlock(blk);
        allocator.free(doc.blocks);
        allocator.free(doc.vars);
    }

    try std.testing.expectEqual(@as(usize, 2), doc.vars.len);
    try std.testing.expectEqualStrings("env", doc.vars[0].key);
    try std.testing.expectEqualStrings("production", doc.vars[0].value);
    try std.testing.expectEqualStrings("db", doc.vars[1].key);
    try std.testing.expectEqualStrings("PostgreSQL", doc.vars[1].value);
    try std.testing.expectEqual(@as(usize, 1), doc.statements.len);
}
