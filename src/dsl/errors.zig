const std = @import("std");

pub const Loc = struct {
    line: u32,
    col: u32,
    offset: u32,

    pub const zero = Loc{ .line = 1, .col = 1, .offset = 0 };

    pub fn format(self: Loc, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}", .{ self.line, self.col });
    }
};

pub const DslError = struct {
    loc: Loc,
    kind: Kind,
    message: []const u8,

    pub const Kind = enum {
        unexpected_character,
        unterminated_string,
        unterminated_block,
        expected_identifier,
        expected_arrow_or_operator,
        expected_closing_brace,
        expected_closing_bracket,
        unexpected_token,
        unknown_directive,
        invalid_property_value,
        unresolved_reference,
        duplicate_block_name,
        unknown_layout_type,
        unknown_shape,
    };

    pub fn format(self: DslError, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}: error: {s}", .{ self.loc, self.message });
    }
};

pub const ErrorList = struct {
    errors: std.ArrayListUnmanaged(DslError),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ErrorList {
        return .{ .errors = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *ErrorList) void {
        self.errors.deinit(self.allocator);
    }

    pub fn add(self: *ErrorList, loc: Loc, kind: DslError.Kind, message: []const u8) !void {
        try self.errors.append(self.allocator, .{ .loc = loc, .kind = kind, .message = message });
    }

    pub fn hasErrors(self: *const ErrorList) bool {
        return self.errors.items.len > 0;
    }
};
