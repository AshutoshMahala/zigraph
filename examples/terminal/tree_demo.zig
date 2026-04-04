//! Tree Renderer Demo — hierarchical text diagrams.
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

    // ── Example 1: Review queue ─────────────────────────────────────────
    std.debug.print("--- Review Queue ---\n\n", .{});
    {
        const nodes = [_]TreeNode{.{
            .label = "Variant appears in the review queue (split-panel UI)",
            .children = &.{
                .{ .label = "Reviewer sees thumbnail + all metadata sections" },
                .{ .label = "Can approve, flag, or edit individual fields" },
                .{
                    .label = "Corrections tracked as structured feedback",
                    .extra_lines = &.{"(field, extracted_value, corrected_value)"},
                },
                .{ .label = "Bulk operations: Cmd+click multiple \xe2\x86\x92 approve/flag all", .blank_above = true },
                .{ .label = "Copy to siblings: share catalog/game data across color variants" },
                .{ .label = "Status: unreviewed \xe2\x86\x92 approved / flagged", .blank_above = true },
            },
        }};
        const out = try T.tree.render(&nodes, alloc, .{});
        defer alloc.free(out);
        std.debug.print("{s}\n", .{out});
    }

    // ── Example 2: Data pipeline ────────────────────────────────────────
    std.debug.print("--- Data Pipeline ---\n\n", .{});
    {
        const nodes = [_]TreeNode{.{
            .label = "Unity Designer",
            .children = &.{
                .{ .label = "MaterialConfig JSON (base64)", .description = "GraphicsMetadataPropagator \xe2\x86\x92 GraphicsMetadata" },
                .{ .label = "VXLB binary (voxel colors)", .description = "VxlbParser \xe2\x86\x92 ColorProfile" },
                .{ .label = "GLB mesh", .description = "MeshGeometryAnalyzer \xe2\x86\x92 MeshMetadata" },
                .{
                    .label = "Thumbnail PNG",
                    .description = "ColorExtractor (K-Means) \xe2\x86\x92 color hints",
                    .children = &.{
                        .{ .label = "VLM (GPT-4.1-mini)", .description = "VisualMetadata" },
                    },
                },
                .{ .label = "SceneGraph (positions/rotations)", .description = "stored, never evaluated" },
            },
        }};
        const out = try T.tree.render(&nodes, alloc, .{});
        defer alloc.free(out);
        std.debug.print("{s}\n", .{out});
    }

    // ── Example 3: Build pipeline steps ─────────────────────────────────
    std.debug.print("--- Build Pipeline ---\n\n", .{});
    {
        const nodes = [_]TreeNode{.{
            .label = "Step 1: BLENDER_CONVERT",
            .children = &.{
                .{ .label = "Download source GLB from GCS" },
                .{
                    .label = "Send to remote Blender service",
                    .children = &.{
                        .{ .label = "Ambient occlusion baking" },
                        .{ .label = "Format conversion to standardized GLB" },
                        .{ .label = "Bounding box extraction (width, height, depth in meters)" },
                    },
                },
                .{ .label = "Upload baked GLB to GCS" },
                .{ .label = "Store bounding box on parent" },
                .{ .label = "Propagate mesh dimensions to ALL variants' ItemMetadata.mesh.dimensions" },
            },
        }};
        const out = try T.tree.render(&nodes, alloc, .{});
        defer alloc.free(out);
        std.debug.print("{s}\n", .{out});
    }
}
