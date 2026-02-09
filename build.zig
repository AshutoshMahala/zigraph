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

    // Comptime example
    const comptime_example = b.addExecutable(.{
        .name = "comptime_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/comptime_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(comptime_example);

    const run_comptime = b.addRunArtifact(comptime_example);
    const run_comptime_step = b.step("run-comptime", "Run the comptime graph example");
    run_comptime_step.dependOn(&run_comptime.step);

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
}
