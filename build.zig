const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module for use as dependency
    const zigraph_mod = b.addModule("zigraph", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main library (static)
    const lib = b.addLibrary(.{
        .name = "zigraph",
        .root_module = zigraph_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Unit tests for the library module
    const lib_unit_tests = b.addTest(.{
        .root_module = zigraph_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Long-running stress/fuzz harness
    const fuzz_harness = b.addExecutable(.{
        .name = "fuzz_harness",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/stress_harness.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(fuzz_harness);

    const run_fuzz = b.addRunArtifact(fuzz_harness);
    if (b.args) |args| {
        run_fuzz.addArgs(args);
    }
    const fuzz_step = b.step("fuzz", "Run stress/fuzz harness (use -- <minutes> to set duration per target)");
    fuzz_step.dependOn(&run_fuzz.step);

    // Basic example
    const basic_example = b.addExecutable(.{
        .name = "basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(basic_example);

    const run_basic = b.addRunArtifact(basic_example);
    const run_example_step = b.step("run-basic", "Run the basic example");
    run_example_step.dependOn(&run_basic.step);

    // Debug example
    const debug_example = b.addExecutable(.{
        .name = "debug",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/debug.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(debug_example);

    const run_debug = b.addRunArtifact(debug_example);
    const run_debug_step = b.step("run-debug", "Run the debug example");
    run_debug_step.dependOn(&run_debug.step);

    // README Hero example
    const hero_example = b.addExecutable(.{
        .name = "readme_hero",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/readme_hero.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(hero_example);

    const run_hero = b.addRunArtifact(hero_example);
    const run_hero_step = b.step("run-hero", "Run the README hero example");
    run_hero_step.dependOn(&run_hero.step);

    // Hero positioning comparison
    const hero_pos_example = b.addExecutable(.{
        .name = "hero_positioning",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/hero_positioning.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(hero_pos_example);

    const run_hero_pos = b.addRunArtifact(hero_pos_example);
    const run_hero_pos_step = b.step("run-hero-pos", "Hero graph with all positioning algorithms");
    run_hero_pos_step.dependOn(&run_hero_pos.step);

    // Edge labels example
    const labels_example = b.addExecutable(.{
        .name = "edge_labels",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/edge_labels.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(labels_example);

    const run_labels = b.addRunArtifact(labels_example);
    const run_labels_step = b.step("run-labels", "Run the edge labels example");
    run_labels_step.dependOn(&run_labels.step);

    // Network simplex comparison
    const ns_compare = b.addExecutable(.{
        .name = "ns_compare",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/ns_compare.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(ns_compare);

    const run_ns = b.addRunArtifact(ns_compare);
    const run_ns_step = b.step("run-ns-compare", "Compare layering algorithms");
    run_ns_step.dependOn(&run_ns.step);

    // Stress test
    const stress_example = b.addExecutable(.{
        .name = "stress_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/stress_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(stress_example);

    const run_stress = b.addRunArtifact(stress_example);
    const run_stress_step = b.step("run-stress", "Run the stress test suite");
    run_stress_step.dependOn(&run_stress.step);

    // Error handling example
    const error_example = b.addExecutable(.{
        .name = "error_handling",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/error_handling.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(error_example);

    const run_error = b.addRunArtifact(error_example);
    const run_error_step = b.step("run-error", "Run the error handling example");
    run_error_step.dependOn(&run_error.step);

    // Arena allocator example
    const arena_example = b.addExecutable(.{
        .name = "arena_allocator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/arena_allocator.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(arena_example);

    const run_arena = b.addRunArtifact(arena_example);
    const run_arena_step = b.step("run-arena", "Run the arena allocator example");
    run_arena_step.dependOn(&run_arena.step);

    // Config demo example
    const config_example = b.addExecutable(.{
        .name = "config_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/config_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(config_example);

    const run_config = b.addRunArtifact(config_example);
    const run_config_step = b.step("run-config", "Run the config demo example");
    run_config_step.dependOn(&run_config.step);

    // Positioning demo example
    const positioning_example = b.addExecutable(.{
        .name = "positioning_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/positioning_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(positioning_example);

    const run_positioning = b.addRunArtifact(positioning_example);
    const run_positioning_step = b.step("run-positioning", "Run the positioning algorithms demo");
    run_positioning_step.dependOn(&run_positioning.step);

    // Presets demo example
    const presets_example = b.addExecutable(.{
        .name = "presets_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/presets_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(presets_example);

    const run_presets = b.addRunArtifact(presets_example);
    const run_presets_step = b.step("run-presets", "Run the presets demo example");
    run_presets_step.dependOn(&run_presets.step);

    // JSON export example
    const json_example = b.addExecutable(.{
        .name = "json_export",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/json_export.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(json_example);

    const run_json = b.addRunArtifact(json_example);
    const run_json_step = b.step("run-json", "Run the JSON export example");
    run_json_step.dependOn(&run_json.step);

    // Standalone algorithm example
    const standalone_example = b.addModule("standalone_example", .{
        .root_source_file = b.path("examples/standalone.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const standalone_exe = b.addExecutable(.{
        .name = "standalone",
        .root_module = standalone_example,
    });
    b.installArtifact(standalone_exe);

    const run_standalone = b.addRunArtifact(standalone_exe);
    const run_standalone_step = b.step("run-standalone", "Run the standalone algorithm example");
    run_standalone_step.dependOn(&run_standalone.step);

    // Benchmark example (run with ReleaseFast for accurate results)
    const benchmark_example = b.addModule("benchmark_example", .{
        .root_source_file = b.path("examples/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast, // Always use release for benchmarks
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const benchmark_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = benchmark_example,
    });
    b.installArtifact(benchmark_exe);

    const run_benchmark = b.addRunArtifact(benchmark_exe);
    const run_benchmark_step = b.step("run-benchmark", "Run performance benchmarks");
    run_benchmark_step.dependOn(&run_benchmark.step);

    // Verify and memory profile example
    const verify_example = b.addModule("verify_example", .{
        .root_source_file = b.path("examples/verify_and_profile.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const verify_exe = b.addExecutable(.{
        .name = "verify",
        .root_module = verify_example,
    });
    b.installArtifact(verify_exe);

    const run_verify = b.addRunArtifact(verify_exe);
    const run_verify_step = b.step("run-verify", "Run verification and memory profiling");
    run_verify_step.dependOn(&run_verify.step);

    // SVG export example
    const svg_example = b.addModule("svg_example", .{
        .root_source_file = b.path("examples/svg_export.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const svg_exe = b.addExecutable(.{
        .name = "svg_export",
        .root_module = svg_example,
    });
    b.installArtifact(svg_exe);

    const run_svg = b.addRunArtifact(svg_exe);
    const run_svg_step = b.step("run-svg", "Run SVG export example");
    run_svg_step.dependOn(&run_svg.step);

    // Subgraph demo example
    const subgraph_example = b.addModule("subgraph_example", .{
        .root_source_file = b.path("examples/subgraph_demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const subgraph_exe = b.addExecutable(.{
        .name = "subgraph_demo",
        .root_module = subgraph_example,
    });
    b.installArtifact(subgraph_exe);

    const run_subgraph = b.addRunArtifact(subgraph_exe);
    const run_subgraph_step = b.step("run-subgraph", "Run subgraph demo example");
    run_subgraph_step.dependOn(&run_subgraph.step);

    // Dummy visibility example
    const dummy_visibility_example = b.addModule("dummy_visibility_example", .{
        .root_source_file = b.path("examples/dummy_visibility.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const dummy_visibility_exe = b.addExecutable(.{
        .name = "dummy_visibility",
        .root_module = dummy_visibility_example,
    });
    b.installArtifact(dummy_visibility_exe);

    const run_dummy_visibility = b.addRunArtifact(dummy_visibility_exe);
    const run_dummy_visibility_step = b.step("run-dummy", "Run dummy visibility example");
    run_dummy_visibility_step.dependOn(&run_dummy_visibility.step);

    // Terminal node control example
    const terminal_node_control_mod = b.addModule("terminal_node_control", .{
        .root_source_file = b.path("examples/terminal/node_control.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const terminal_node_control_exe = b.addExecutable(.{
        .name = "terminal_node_control",
        .root_module = terminal_node_control_mod,
    });
    b.installArtifact(terminal_node_control_exe);

    const run_terminal_node_control = b.addRunArtifact(terminal_node_control_exe);
    const run_terminal_node_control_step = b.step("run-terminal-node-control", "Run terminal node control example");
    run_terminal_node_control_step.dependOn(&run_terminal_node_control.step);

    // Terminal subgraph styles example
    const terminal_subgraph_styles_mod = b.addModule("terminal_subgraph_styles", .{
        .root_source_file = b.path("examples/terminal/subgraph_styles.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const terminal_subgraph_styles_exe = b.addExecutable(.{
        .name = "terminal_subgraph_styles",
        .root_module = terminal_subgraph_styles_mod,
    });
    b.installArtifact(terminal_subgraph_styles_exe);

    const run_terminal_subgraph_styles = b.addRunArtifact(terminal_subgraph_styles_exe);
    const run_terminal_subgraph_styles_step = b.step("run-terminal-subgraph-styles", "Run terminal subgraph styles example");
    run_terminal_subgraph_styles_step.dependOn(&run_terminal_subgraph_styles.step);

    // Generate README assets (all hero formats)
    const generate_assets_example = b.addModule("generate_assets_example", .{
        .root_source_file = b.path("examples/generate_assets.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const generate_assets_exe = b.addExecutable(.{
        .name = "generate_assets",
        .root_module = generate_assets_example,
    });
    b.installArtifact(generate_assets_exe);

    const run_generate_assets = b.addRunArtifact(generate_assets_exe);
    const run_generate_assets_step = b.step("generate-assets", "Generate README hero assets (assets/)");
    run_generate_assets_step.dependOn(&run_generate_assets.step);

    // Force-directed graph layout example
    const fdg_example = b.addModule("fdg_example", .{
        .root_source_file = b.path("examples/fdg_basic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const fdg_exe = b.addExecutable(.{
        .name = "fdg_basic",
        .root_module = fdg_example,
    });
    b.installArtifact(fdg_exe);

    const run_fdg = b.addRunArtifact(fdg_exe);
    const run_fdg_step = b.step("run-fdg", "Run force-directed graph layout example");
    run_fdg_step.dependOn(&run_fdg.step);

    // FDG benchmark
    const fdg_bench_example = b.addModule("fdg_bench_example", .{
        .root_source_file = b.path("examples/fdg_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const fdg_bench_exe = b.addExecutable(.{
        .name = "fdg_benchmark",
        .root_module = fdg_bench_example,
    });
    b.installArtifact(fdg_bench_exe);

    const run_fdg_bench = b.addRunArtifact(fdg_bench_exe);
    const run_fdg_bench_step = b.step("run-fdg-bench", "Run FDG performance benchmarks");
    run_fdg_bench_step.dependOn(&run_fdg_bench.step);

    // Cycle breaking example
    const cycle_example = b.addModule("cycle_example", .{
        .root_source_file = b.path("examples/cycle_breaking.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigraph", .module = zigraph_mod },
        },
    });
    const cycle_exe = b.addExecutable(.{
        .name = "cycle_breaking",
        .root_module = cycle_example,
    });
    b.installArtifact(cycle_exe);

    const run_cycle = b.addRunArtifact(cycle_exe);
    const run_cycle_step = b.step("run-cycle", "Run cycle breaking example");
    run_cycle_step.dependOn(&run_cycle.step);

    // ── SVG Gallery Examples ────────────────────────────────────────────────

    const svg_gallery = [_]struct { file: []const u8, name: []const u8, desc: []const u8 }{
        .{ .file = "examples/svg/01_basic.zig", .name = "svg_01_basic", .desc = "SVG gallery: 01 basic" },
        .{ .file = "examples/svg/02_presets.zig", .name = "svg_02_presets", .desc = "SVG gallery: 02 presets" },
        .{ .file = "examples/svg/03_flowchart.zig", .name = "svg_03_flowchart", .desc = "SVG gallery: 03 flowchart" },
        .{ .file = "examples/svg/04_clusters.zig", .name = "svg_04_clusters", .desc = "SVG gallery: 04 clusters" },
        .{ .file = "examples/svg/05_dark_theme.zig", .name = "svg_05_dark_theme", .desc = "SVG gallery: 05 dark theme" },
        .{ .file = "examples/svg/06_interactive.zig", .name = "svg_06_interactive", .desc = "SVG gallery: 06 interactive" },
        .{ .file = "examples/svg/07_heatmap.zig", .name = "svg_07_heatmap", .desc = "SVG gallery: 07 heatmap" },
        .{ .file = "examples/svg/08_variable_sizes.zig", .name = "svg_08_variable_sizes", .desc = "SVG gallery: 08 variable sizes" },
        .{ .file = "examples/svg/09_drag_and_pin.zig", .name = "svg_09_drag_and_pin", .desc = "SVG gallery: 09 drag and pin" },
    };

    const run_gallery_step = b.step("run-svg-gallery", "Run all SVG gallery examples");

    inline for (svg_gallery) |ex| {
        const mod = b.addModule(ex.name, .{
            .root_source_file = b.path(ex.file),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        });
        const exe = b.addExecutable(.{
            .name = ex.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
        const run = b.addRunArtifact(exe);
        run_gallery_step.dependOn(&run.step);

        // Individual step: zig build run-svg-01, run-svg-02, etc.
        const step_name = "run-" ++ ex.name;
        const individual = b.step(step_name, ex.desc);
        individual.dependOn(&run.step);
    }
}
