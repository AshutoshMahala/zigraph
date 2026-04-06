//! Minimal LSP server for .zgraph files.
//!
//! Capabilities:
//!   - Diagnostics on open/save/change (syntax errors from tokenizer/parser)
//!   - Document formatting (via dsl.formatter)
//!
//! Communicates via JSON-RPC 2.0 over stdin/stdout with Content-Length framing.

const std = @import("std");
const dsl = @import("dsl");

const Allocator = std.mem.Allocator;

// ── JSON-RPC transport ───────────────────────────────────────────────────────

fn readMessage(allocator: Allocator, reader: anytype) !?[]u8 {
    var content_length: ?usize = null;
    var header_buf: [1024]u8 = undefined;

    while (true) {
        const line = reader.readUntilDelimiterOrEof(&header_buf, '\n') catch |err| {
            switch (err) {
                error.StreamTooLong => return error.HeaderTooLong,
                else => return @as(?[]u8, null),
            }
        } orelse return null;

        const trimmed = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;

        if (trimmed.len == 0) break;

        if (std.ascii.startsWithIgnoreCase(trimmed, "content-length:")) {
            const value = std.mem.trimLeft(u8, trimmed["content-length:".len..], " ");
            content_length = std.fmt.parseInt(usize, value, 10) catch continue;
        }
    }

    const len = content_length orelse return error.MissingContentLength;

    const body = try allocator.alloc(u8, len);
    errdefer allocator.free(body);

    var total: usize = 0;
    while (total < len) {
        const n = reader.read(body[total..]) catch return null;
        if (n == 0) return null;
        total += n;
    }

    return body;
}

fn sendMessage(writer: anytype, json: []const u8) !void {
    var buf: [32]u8 = undefined;
    const len_str = std.fmt.bufPrint(&buf, "{d}", .{json.len}) catch unreachable;
    try writer.writeAll("Content-Length: ");
    try writer.writeAll(len_str);
    try writer.writeAll("\r\n\r\n");
    try writer.writeAll(json);
}

// ── JSON helpers ─────────────────────────────────────────────────────────────

fn jsonString(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, s: []const u8) !void {
    try buf.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
    try buf.append(allocator, '"');
}

fn jsonInt(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, n: anytype) !void {
    var num_buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&num_buf, "{d}", .{n}) catch unreachable;
    try buf.appendSlice(allocator, s);
}

// ── Document store ───────────────────────────────────────────────────────────

const DocumentStore = struct {
    allocator: Allocator,
    documents: std.StringHashMap([]u8),

    fn init(allocator: Allocator) DocumentStore {
        return .{
            .allocator = allocator,
            .documents = std.StringHashMap([]u8).init(allocator),
        };
    }

    fn deinit(self: *DocumentStore) void {
        var it = self.documents.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.documents.deinit();
    }

    fn put(self: *DocumentStore, uri: []const u8, text: []const u8) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        if (self.documents.fetchRemove(uri)) |removed| {
            self.allocator.free(removed.value);
            // Reuse existing key
            self.documents.put(removed.key, owned_text) catch unreachable;
        } else {
            const owned_uri = try self.allocator.dupe(u8, uri);
            errdefer self.allocator.free(owned_uri);
            try self.documents.put(owned_uri, owned_text);
        }
    }

    fn get(self: *const DocumentStore, uri: []const u8) ?[]const u8 {
        return self.documents.get(uri);
    }

    fn remove(self: *DocumentStore, uri: []const u8) void {
        if (self.documents.fetchRemove(uri)) |removed| {
            self.allocator.free(removed.key);
            self.allocator.free(removed.value);
        }
    }
};

// ── LSP Server ───────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    const reader = stdin.deprecatedReader();
    const writer = stdout.deprecatedWriter();

    var doc_store = DocumentStore.init(allocator);
    defer doc_store.deinit();

    try stderr.writeAll("zgraph-lsp: starting\n");

    while (true) {
        const body = readMessage(allocator, reader) catch |err| {
            try stderr.print("zgraph-lsp: read error: {s}\n", .{@errorName(err)});
            continue;
        } orelse break;
        defer allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
            try stderr.writeAll("zgraph-lsp: invalid JSON\n");
            continue;
        };
        defer parsed.deinit();
        const root = parsed.value;

        const method_val = root.object.get("method") orelse continue;
        const method = if (method_val == .string) method_val.string else continue;

        if (std.mem.eql(u8, method, "initialize")) {
            const id = root.object.get("id") orelse continue;
            try handleInitialize(allocator, id, writer);
        } else if (std.mem.eql(u8, method, "initialized")) {
            try stderr.writeAll("zgraph-lsp: initialized\n");
        } else if (std.mem.eql(u8, method, "shutdown")) {
            const id = root.object.get("id") orelse continue;
            try sendResponse(allocator, id, "null", writer);
            try stderr.writeAll("zgraph-lsp: shutdown\n");
        } else if (std.mem.eql(u8, method, "exit")) {
            break;
        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            const params = root.object.get("params") orelse continue;
            try handleDidOpen(allocator, params, &doc_store, writer, stderr);
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const params = root.object.get("params") orelse continue;
            try handleDidChange(allocator, params, &doc_store, writer, stderr);
        } else if (std.mem.eql(u8, method, "textDocument/didSave")) {
            const params = root.object.get("params") orelse continue;
            try handleDidSave(allocator, params, &doc_store, writer, stderr);
        } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
            const params = root.object.get("params") orelse continue;
            handleDidClose(params, &doc_store);
        } else if (std.mem.eql(u8, method, "textDocument/formatting")) {
            const id = root.object.get("id") orelse continue;
            const params = root.object.get("params") orelse continue;
            try handleFormatting(allocator, id, params, &doc_store, writer);
        }
    }

    try stderr.writeAll("zgraph-lsp: exiting\n");
}

fn handleInitialize(allocator: Allocator, id: std.json.Value, writer: anytype) !void {
    const result =
        \\{"capabilities":{"textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"documentFormattingProvider":true},"serverInfo":{"name":"zgraph-lsp","version":"0.1.0"}}
    ;
    try sendResponse(allocator, id, result, writer);
}

fn sendResponse(allocator: Allocator, id: std.json.Value, result: []const u8, writer: anytype) !void {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    switch (id) {
        .integer => |n| try jsonInt(&buf, allocator, n),
        .string => |s| try jsonString(&buf, allocator, s),
        else => try buf.appendSlice(allocator, "null"),
    }
    try buf.appendSlice(allocator, ",\"result\":");
    try buf.appendSlice(allocator, result);
    try buf.append(allocator, '}');

    try sendMessage(writer, buf.items);
}

fn handleDidOpen(allocator: Allocator, params: std.json.Value, doc_store: *DocumentStore, writer: anytype, stderr: anytype) !void {
    const td = params.object.get("textDocument") orelse return;
    const uri_val = td.object.get("uri") orelse return;
    const uri = if (uri_val == .string) uri_val.string else return;
    const text_val = td.object.get("text") orelse return;
    const text = if (text_val == .string) text_val.string else return;

    try doc_store.put(uri, text);
    try publishDiagnostics(allocator, uri, text, writer, stderr);
}

fn handleDidChange(allocator: Allocator, params: std.json.Value, doc_store: *DocumentStore, writer: anytype, stderr: anytype) !void {
    const td = params.object.get("textDocument") orelse return;
    const uri_val = td.object.get("uri") orelse return;
    const uri = if (uri_val == .string) uri_val.string else return;

    const changes = params.object.get("contentChanges") orelse return;
    if (changes != .array or changes.array.items.len == 0) return;

    // Full sync (change mode 1): last change has the full text
    const last = changes.array.items[changes.array.items.len - 1];
    const text_val = last.object.get("text") orelse return;
    const text = if (text_val == .string) text_val.string else return;

    try doc_store.put(uri, text);
    try publishDiagnostics(allocator, uri, text, writer, stderr);
}

fn handleDidSave(allocator: Allocator, params: std.json.Value, doc_store: *DocumentStore, writer: anytype, stderr: anytype) !void {
    const td = params.object.get("textDocument") orelse return;
    const uri_val = td.object.get("uri") orelse return;
    const uri = if (uri_val == .string) uri_val.string else return;

    // Save may include text if server requested includeText
    const text = if (params.object.get("text")) |tv|
        (if (tv == .string) tv.string else null)
    else
        doc_store.get(uri);

    if (text) |t| {
        try publishDiagnostics(allocator, uri, t, writer, stderr);
    }
}

fn handleDidClose(params: std.json.Value, doc_store: *DocumentStore) void {
    const td = params.object.get("textDocument") orelse return;
    const uri_val = td.object.get("uri") orelse return;
    const uri = if (uri_val == .string) uri_val.string else return;
    doc_store.remove(uri);
}

fn publishDiagnostics(allocator: Allocator, uri: []const u8, text: []const u8, writer: anytype, stderr: anytype) !void {
    _ = stderr;

    var err_list = dsl.errors.ErrorList.init(allocator);
    defer err_list.deinit();

    // Use an arena for tokenizer/parser allocations so we can free everything at once
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const tokens = dsl.tokenizer.tokenize(arena_alloc, text, &err_list) catch {
        return;
    };

    var p = dsl.parser.Parser.init(arena_alloc, tokens, &err_list);
    if (p.parse()) |_| {} else |_| {}

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":");
    try jsonString(&buf, allocator, uri);
    try buf.appendSlice(allocator, ",\"diagnostics\":[");

    for (err_list.errors.items, 0..) |err, i| {
        if (i > 0) try buf.append(allocator, ',');

        // LSP lines/cols are 0-based; our Loc is 1-based
        const line = if (err.loc.line > 0) err.loc.line - 1 else 0;
        const col = if (err.loc.col > 0) err.loc.col - 1 else 0;

        try buf.appendSlice(allocator, "{\"range\":{\"start\":{\"line\":");
        try jsonInt(&buf, allocator, line);
        try buf.appendSlice(allocator, ",\"character\":");
        try jsonInt(&buf, allocator, col);
        try buf.appendSlice(allocator, "},\"end\":{\"line\":");
        try jsonInt(&buf, allocator, line);
        try buf.appendSlice(allocator, ",\"character\":");
        try jsonInt(&buf, allocator, col + 1);
        try buf.appendSlice(allocator, "}},\"severity\":1,\"source\":\"zgraph\",\"message\":");
        try jsonString(&buf, allocator, err.message);
        try buf.append(allocator, '}');
    }

    try buf.appendSlice(allocator, "]}}");

    try sendMessage(writer, buf.items);
}

fn handleFormatting(allocator: Allocator, id: std.json.Value, params: std.json.Value, doc_store: *const DocumentStore, writer: anytype) !void {
    const td = params.object.get("textDocument") orelse return;
    const uri_val = td.object.get("uri") orelse return;
    const uri = if (uri_val == .string) uri_val.string else return;

    const text = doc_store.get(uri) orelse {
        try sendResponse(allocator, id, "null", writer);
        return;
    };

    const formatted = dsl.formatter.format(allocator, text) catch {
        try sendResponse(allocator, id, "null", writer);
        return;
    };
    defer allocator.free(formatted);

    // Count lines in original text for full-document replacement
    var line_count: usize = 0;
    for (text) |c| {
        if (c == '\n') line_count += 1;
    }
    // If text doesn't end with newline, there's one more line
    if (text.len > 0 and text[text.len - 1] != '\n') line_count += 1;

    // Build a single TextEdit replacing the entire document
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":");
    try jsonInt(&buf, allocator, line_count);
    try buf.appendSlice(allocator, ",\"character\":0}},\"newText\":");
    try jsonString(&buf, allocator, formatted);
    try buf.appendSlice(allocator, "}]");

    try sendResponse(allocator, id, buf.items, writer);
}
