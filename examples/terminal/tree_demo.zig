//! Tree Renderer Demo — hierarchical text diagrams.
//!
//! Shows the tree renderer with examples relevant to graph visualization
//! and the Zig ecosystem.
//!
//! Run with: zig build run-terminal-tree-demo

const std = @import("std");
const zigraph = @import("zigraph");
const T = zigraph.terminal;
const TreeNode = T.tree.TreeNode;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════════╗
        \\║  Tree Renderer Demo                                         ║
        \\╚══════════════════════════════════════════════════════════════╝
        \\
        \\
    , .{});

    // ── Example 1: Sugiyama layout pipeline ───────────────────────────
    std.debug.print("--- Sugiyama Layout Pipeline ---\n\n", .{});
    {
        const nodes = [_]TreeNode{.{
            .label = "Graph",
            .description = "input DAG with nodes, edges, subgraphs",
            .children = &.{
                .{
                    .label = "Cycle breaking",
                    .description = "DFS-based back-edge detection",
                    .extra_lines = &.{"(reversed edges rendered as dashed lines)"},
                },
                .{
                    .label = "Layering",
                    .description = "assign nodes to horizontal ranks",
                    .children = &.{
                        .{ .label = "longest_path", .description = "simple, fast (default)" },
                        .{ .label = "network_simplex", .description = "optimal: minimizes total edge span" },
                    },
                },
                .{
                    .label = "Crossing reduction",
                    .description = "minimize edge crossings",
                    .children = &.{
                        .{ .label = "median heuristic", .description = "O(V log V) per pass" },
                        .{ .label = "adjacent exchange", .description = "local swap optimization" },
                    },
                    .blank_above = true,
                },
                .{
                    .label = "Positioning",
                    .children = &.{
                        .{ .label = "compact", .description = "left-to-right packing (default)" },
                        .{ .label = "brandes_kopf", .description = "multi-pass parent/child centering" },
                    },
                },
                .{
                    .label = "Routing",
                    .children = &.{
                        .{ .label = "direct", .description = "Manhattan paths with slot-based h_y" },
                        .{ .label = "spline", .description = "Bezier curves for SVG output" },
                        .{ .label = "bus", .description = "shared horizontal bus with T-junctions" },
                    },
                    .blank_above = true,
                },
                .{
                    .label = "LayoutIR",
                    .description = "stable contract between layout and renderers",
                    .blank_above = true,
                },
            },
        }};
        const out = try T.tree.render(&nodes, alloc, .{});
        defer alloc.free(out);
        std.debug.print("{s}\n", .{out});
    }

    // ── Example 2: Zig build system ───────────────────────────────────
    std.debug.print("--- Zig Build System ---\n\n", .{});
    {
        const nodes = [_]TreeNode{.{
            .label = "build.zig",
            .children = &.{
                .{
                    .label = "addExecutable",
                    .description = "main binary",
                    .children = &.{
                        .{ .label = "root_module", .description = "src/main.zig" },
                        .{ .label = "addImport(\"zigraph\")", .description = "graph layout library" },
                        .{ .label = "target", .description = "native or cross-compile" },
                    },
                },
                .{
                    .label = "addTest",
                    .description = "unit tests",
                    .children = &.{
                        .{ .label = "root_source_file", .description = "src/root.zig" },
                        .{ .label = "filter", .description = "run specific test by name" },
                    },
                    .blank_above = true,
                },
                .{
                    .label = "addRunArtifact",
                    .description = "run step",
                    .extra_lines = &.{"(zig build run-terminal-tree-demo)"},
                    .blank_above = true,
                },
            },
        }};
        const out = try T.tree.render(&nodes, alloc, .{});
        defer alloc.free(out);
        std.debug.print("{s}\n", .{out});
    }

    // ── Example 3: zigraph module structure ───────────────────────────
    std.debug.print("--- Module Structure ---\n\n", .{});
    {
        const nodes = [_]TreeNode{.{
            .label = "zigraph",
            .children = &.{
                .{
                    .label = "core/",
                    .children = &.{
                        .{ .label = "graph.zig", .description = "Graph, Node, Edge, Subgraph" },
                        .{ .label = "ir.zig", .description = "LayoutIR, LayoutNode, LayoutEdge" },
                    },
                },
                .{
                    .label = "algorithms/",
                    .children = &.{
                        .{
                            .label = "sugiyama/",
                            .children = &.{
                                .{ .label = "layering/", .description = "longest_path, network_simplex" },
                                .{ .label = "crossing/", .description = "median, adjacent_exchange" },
                                .{ .label = "positioning/", .description = "compact, brandes_kopf" },
                                .{ .label = "routing/", .description = "direct, spline, bus" },
                            },
                        },
                        .{ .label = "fdg.zig", .description = "Fruchterman-Reingold + Barnes-Hut" },
                    },
                },
                .{
                    .label = "render/",
                    .children = &.{
                        .{
                            .label = "terminal/",
                            .children = &.{
                                .{ .label = "buffer.zig", .description = "Buffer2D (char + color grid)" },
                                .{ .label = "nodes.zig", .description = "paintNode (1-row, 3-row, card)" },
                                .{ .label = "edges.zig", .description = "paintEdge, bus edges" },
                                .{ .label = "tree.zig", .description = "standalone tree renderer" },
                                .{ .label = "card.zig", .description = "multi-line box painting" },
                            },
                        },
                        .{ .label = "svg/", .description = "SVG with splines, gradients, JS" },
                        .{ .label = "json.zig", .description = "JSON export (schema v1.2)" },
                    },
                },
            },
        }};
        const out = try T.tree.render(&nodes, alloc, .{});
        defer alloc.free(out);
        std.debug.print("{s}\n", .{out});
    }

    // ── Example 4: ASCII fallback ─────────────────────────────────────
    std.debug.print("--- ASCII Mode (for CI/piping) ---\n\n", .{});
    {
        const nodes = [_]TreeNode{.{
            .label = "Graph.init(allocator)",
            .children = &.{
                .{ .label = "addNode(id, label)" },
                .{ .label = "addDiEdge(from, to)" },
                .{
                    .label = "layout(&graph, allocator, config)",
                    .children = &.{
                        .{ .label = "terminal.render(&ir, allocator)" },
                        .{ .label = "svg.render(&ir, allocator, .{})" },
                        .{ .label = "json.render(&ir, allocator)" },
                    },
                },
            },
        }};
        const out = try T.tree.render(&nodes, alloc, .{ .char_set = .ascii });
        defer alloc.free(out);
        std.debug.print("{s}\n", .{out});
    }
}
