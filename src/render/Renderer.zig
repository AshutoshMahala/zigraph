//! Type-erased renderer interface, following the `std.mem.Allocator` pattern.
//!
//! Allows generic code to work with any renderer backend (SVG, Unicode, JSON,
//! or user-defined) without compile-time knowledge of which backend is in use.
//!
//! ## Usage
//!
//! ```zig
//! const zigraph = @import("zigraph");
//!
//! // Wrap a concrete renderer:
//! const r = zigraph.Renderer.initSvg(.{});
//! // — or —
//! const r = zigraph.Renderer.initTerminal(.{});
//! // — or —
//! const r = zigraph.Renderer.initJson();
//!
//! // Use uniformly:
//! const output = try r.render(&layout, allocator);
//! defer allocator.free(output);
//! ```
//!
//! ## Custom renderers
//!
//! Any type that provides `fn render(*const LayoutIR, Allocator) ![]u8` can
//! be wrapped via `Renderer.init()`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);

const svg_mod = @import("svg/mod.zig");
const terminal_mod = @import("terminal/mod.zig");
const json_mod = @import("json.zig");

const Renderer = @This();

/// Opaque pointer to the backend's config (or null for config-free backends).
ctx: *const anyopaque,

/// Backend vtable — one static instance per backend type.
vtable: *const VTable,

pub const VTable = struct {
    /// Render a LayoutIR to an owned byte slice.
    /// Caller owns the returned memory and must free it with `allocator`.
    renderFn: *const fn (ctx: *const anyopaque, layout: *const LayoutIR, allocator: Allocator) anyerror![]u8,
};

/// Render the layout using the wrapped backend.
pub fn render(self: Renderer, layout: *const LayoutIR, allocator: Allocator) ![]u8 {
    return self.vtable.renderFn(self.ctx, layout, allocator);
}

// ── Built-in backend constructors ───────────────────────────────────────────

/// Create a Renderer backed by the SVG backend.
/// The pointed-to config must outlive the Renderer.
pub fn initSvg(config: *const svg_mod.SvgConfig) Renderer {
    return .{
        .ctx = @ptrCast(config),
        .vtable = &svg_vtable,
    };
}

/// Create a Renderer backed by the terminal backend.
/// The pointed-to config must outlive the Renderer.
pub fn initTerminal(config: *const terminal_mod.Config) Renderer {
    return .{
        .ctx = @ptrCast(config),
        .vtable = &terminal_vtable,
    };
}

/// Create a Renderer backed by the JSON backend (no config needed).
pub fn initJson() Renderer {
    return .{
        .ctx = @ptrCast(&json_sentinel),
        .vtable = &json_vtable,
    };
}

// ── Generic constructor ─────────────────────────────────────────────────────

/// Wrap any type that has a `render(*const LayoutIR, Allocator) ![]u8` method.
///
/// ```zig
/// const MyRenderer = struct {
///     prefix: []const u8,
///     pub fn render(self: *const @This(), layout: *const LayoutIR, allocator: Allocator) ![]u8 {
///         _ = layout;
///         return allocator.dupe(u8, self.prefix);
///     }
/// };
/// var my = MyRenderer{ .prefix = "custom" };
/// const r = Renderer.init(&my);
/// ```
pub fn init(ptr: anytype) Renderer {
    const Ptr = @TypeOf(ptr);
    const PtrChild = @typeInfo(Ptr).pointer.child;

    return .{
        .ctx = @ptrCast(ptr),
        .vtable = &.{
            .renderFn = struct {
                fn call(ctx: *const anyopaque, layout: *const LayoutIR, allocator: Allocator) anyerror![]u8 {
                    const self: *const PtrChild = @ptrCast(@alignCast(ctx));
                    return self.render(layout, allocator);
                }
            }.call,
        },
    };
}

// ── VTable implementations ──────────────────────────────────────────────────

const svg_vtable = VTable{
    .renderFn = struct {
        fn call(ctx: *const anyopaque, layout: *const LayoutIR, allocator: Allocator) anyerror![]u8 {
            const config: *const svg_mod.SvgConfig = @ptrCast(@alignCast(ctx));
            return svg_mod.render(layout, allocator, config.*);
        }
    }.call,
};

const terminal_vtable = VTable{
    .renderFn = struct {
        fn call(ctx: *const anyopaque, layout: *const LayoutIR, allocator: Allocator) anyerror![]u8 {
            const config: *const terminal_mod.Config = @ptrCast(@alignCast(ctx));
            return terminal_mod.renderWithConfig(layout, allocator, config.*);
        }
    }.call,
};

const json_vtable = VTable{
    .renderFn = struct {
        fn call(_: *const anyopaque, layout: *const LayoutIR, allocator: Allocator) anyerror![]u8 {
            return json_mod.serialize(layout, allocator);
        }
    }.call,
};

// ── Sentinel for config-free backends ───────────────────────────────────────

const json_sentinel: u8 = 0;

// ── Tests ───────────────────────────────────────────────────────────────────

test "Renderer: SVG backend produces valid SVG" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    layout.setDimensions(5, 3);

    const config = svg_mod.SvgConfig{};
    const r = Renderer.initSvg(&config);
    const output = try r.render(&layout, allocator);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ">A<") != null);
}

test "Renderer: Unicode backend produces output" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "B",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    layout.setDimensions(5, 3);

    const config = terminal_mod.Config{};
    const r = Renderer.initTerminal(&config);
    const output = try r.render(&layout, allocator);
    defer allocator.free(output);

    try std.testing.expect(output.len > 0);
}

test "Renderer: JSON backend produces valid JSON" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "C",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    layout.setDimensions(5, 3);

    const r = Renderer.initJson();
    const output = try r.render(&layout, allocator);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "\"nodes\"") != null);
}

test "Renderer: all backends produce non-empty output for same layout" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "X",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    layout.setDimensions(5, 3);

    const svg_config = svg_mod.SvgConfig{};
    const uni_config = terminal_mod.Config{};

    const renderers = [_]Renderer{
        Renderer.initSvg(&svg_config),
        Renderer.initTerminal(&uni_config),
        Renderer.initJson(),
    };

    for (renderers) |r| {
        const output = try r.render(&layout, allocator);
        defer allocator.free(output);
        try std.testing.expect(output.len > 0);
    }
}
