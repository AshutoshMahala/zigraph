//! Force-kernel benchmark harness — Stage D3 evidence.
//!
//! Run: `zig build bench` (kernels compiled ReleaseFast).
//!
//! Measures per-kernel cost per iteration, plus a micro-split of the
//! pairwise kernel that quantifies the *SIMD-vectorizable fraction*:
//! Q16.16 force math is dominated by 64-bit integer division (fp.div,
//! normalizeScaled) and a data-dependent Newton sqrt — none of which
//! vectorize on NEON/SSE (no vector integer divide). Option A of the
//! roadmap (fixed-point SIMD with manual widening) can only accelerate
//! the delta/distance² part, so its overall ceiling is that part's share
//! of the kernel. This harness measures the share and the actual vector
//! speedup of that part, grounding the option-A/option-B decision in data.

const std = @import("std");
const zigraph = @import("zigraph");
const fdg = zigraph.fdg;
const fp = fdg.fixed_point;
const FP = fp.FP;
const Range = fdg.common.Range;

fn startTs(io: std.Io) std.Io.Timestamp {
    return std.Io.Clock.now(.awake, io);
}

fn elapsedNsPer(io: std.Io, start: std.Io.Timestamp, iters: usize) u64 {
    const end = std.Io.Clock.now(.awake, io);
    return @as(u64, @intCast(end.nanoseconds - start.nanoseconds)) / iters;
}

const sizes = [_]usize{ 100, 500, 2000 };
const pairwise_max_n = 2000;

fn buildBenchGraph(allocator: std.mem.Allocator, n: usize) !zigraph.Graph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();
    for (0..n) |i| try g.addNode(i, "n");
    // Ring + chords: deterministic, average degree ~3.
    for (0..n) |i| try g.addDiEdge(i, (i + 1) % n);
    var i: usize = 0;
    while (i < n) : (i += 3) {
        try g.addDiEdge(i, (i + n / 3) % n);
    }
    return g;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const k_squared = fp.fromInt(100);
    const inv_k = fp.div(fp.ONE, fp.fromInt(10));
    const theta = fp.fromFloat(0.8);

    std.debug.print("zigraph force-kernel bench (ReleaseFast, ns per full pass)\n\n", .{});
    std.debug.print("{s:>6} {s:>14} {s:>14} {s:>14} {s:>14}\n", .{ "n", "pairwise", "bh(qt+force)", "attraction", "pos-update" });

    for (sizes) |n| {
        var g = try buildBenchGraph(allocator, n);
        defer g.deinit();
        const frozen = try g.ensureFrozen();

        const init_positions = try fdg.common.initGridJitter(n, fp.fromInt(10), 42, allocator);
        defer allocator.free(init_positions);
        const xs = try allocator.alloc(FP, n);
        defer allocator.free(xs);
        const ys = try allocator.alloc(FP, n);
        defer allocator.free(ys);
        for (init_positions, 0..) |p, i| {
            xs[i] = p.x;
            ys[i] = p.y;
        }
        const fxs = try allocator.alloc(FP, n);
        defer allocator.free(fxs);
        const fys = try allocator.alloc(FP, n);
        defer allocator.free(fys);
        const full = Range.full(n);

        const iters: usize = if (n <= 500) 200 else 20;

        // Pairwise repulsion
        var pairwise_ns: u64 = 0;
        if (n <= pairwise_max_n) {
            @memset(fxs, 0);
            @memset(fys, 0);
            const t_pw = startTs(io);
            for (0..iters) |_| {
                fdg.forces.accumulatePairwiseRepulsion(xs, ys, fxs, fys, k_squared, full);
            }
            pairwise_ns = elapsedNsPer(io, t_pw, iters);
            std.mem.doNotOptimizeAway(&fxs[0]);
        }

        // Barnes-Hut (quadtree build + force reads, as in computeFast)
        @memset(fxs, 0);
        @memset(fys, 0);
        const t_bh = startTs(io);
        for (0..iters) |_| {
            var qt = try fdg.quadtree.Quadtree.build(xs, ys, allocator);
            defer qt.deinit();
            fdg.forces.accumulateBarnesHutRepulsion(xs, ys, fxs, fys, &qt, k_squared, theta, full);
        }
        const bh_ns = elapsedNsPer(io, t_bh, iters);
        std.mem.doNotOptimizeAway(&fxs[0]);

        // Attraction (CSR gather)
        @memset(fxs, 0);
        @memset(fys, 0);
        const t_att = startTs(io);
        for (0..iters) |_| {
            fdg.forces.accumulateAttraction(frozen, xs, ys, fxs, fys, inv_k, full);
        }
        const att_ns = elapsedNsPer(io, t_att, iters);
        std.mem.doNotOptimizeAway(&fxs[0]);

        // Position update (displacement clamp) — approximated by gravity
        // kernel shape: length + normalize per node, the same math profile.
        @memset(fxs, 0);
        @memset(fys, 0);
        const t_pos = startTs(io);
        for (0..iters) |_| {
            fdg.forces.accumulateGravity(xs, ys, fxs, fys, .{ .x = 0, .y = 0 }, fp.ONE, full);
        }
        const pos_ns = elapsedNsPer(io, t_pos, iters);
        std.mem.doNotOptimizeAway(&fxs[0]);

        std.debug.print("{d:>6} {d:>14} {d:>14} {d:>14} {d:>14}\n", .{ n, pairwise_ns, bh_ns, att_ns, pos_ns });
    }

    // ── Micro-split: the SIMD-vectorizable fraction of the pairwise kernel ──
    try microSplit(allocator, io, 500, k_squared);

    // ── Regression: gather kernel vs the historical i<j scatter loop ──
    for ([_]usize{ 100, 500 }) |n| {
        try scatterVsGather(allocator, io, n, k_squared);
    }

    // ── Format comparison: what does Q16.16 cost vs f32, and what would
    //    float SIMD add? (bench-only mirror, not a proposal) ──
    for ([_]usize{ 500, 2000 }) |n| {
        try floatComparison(allocator, io, n);
    }
}

/// Op-for-op f32 mirror of the pairwise gather kernel: same per-pair
/// sequence (delta, d², sqrt, two divides, two multiply-accumulates).
/// Answers "what is the fixed-point representation itself costing" —
/// f32 sqrt/div are single hardware instructions where Q16.16 uses a
/// Newton loop and 64-bit integer division.
fn pairwiseF32Scalar(xs: []const f32, ys: []const f32, fxs: []f32, fys: []f32, k2: f32) void {
    const n = xs.len;
    for (0..n) |i| {
        var fx: f32 = 0;
        var fy: f32 = 0;
        for (0..n) |j| {
            if (j == i) continue;
            const dx = xs[i] - xs[j];
            const dy = ys[i] - ys[j];
            const d2 = dx * dx + dy * dy;
            if (d2 < 1e-9) continue; // coincident — mirror of d < 2
            const d = @sqrt(d2);
            const mag = k2 / d; // mirror fp.div(k², d)
            const s = mag / d; // mirror normalizeScaled's divide
            fx += dx * s;
            fy += dy * s;
        }
        fxs[i] += fx;
        fys[i] += fy;
    }
}

/// 8-lane @Vector version of the same math — on NEON, f32 divide and
/// sqrt ARE vector instructions, so the whole per-pair body vectorizes
/// (unlike Q16.16, where integer division has no vector form at all).
/// The self-lane and coincident lanes fall out of the d² < eps mask.
fn pairwiseF32Simd(xs: []const f32, ys: []const f32, fxs: []f32, fys: []f32, k2: f32) void {
    const L = 8;
    const V = @Vector(L, f32);
    const zero: V = @splat(0);
    const eps: V = @splat(1e-9);
    const k2v: V = @splat(k2);
    const n = xs.len;
    for (0..n) |i| {
        const xi: V = @splat(xs[i]);
        const yi: V = @splat(ys[i]);
        var accx: V = zero;
        var accy: V = zero;
        var j: usize = 0;
        while (j + L <= n) : (j += L) {
            const xj: V = xs[j..][0..L].*;
            const yj: V = ys[j..][0..L].*;
            const dx = xi - xj;
            const dy = yi - yj;
            const d2 = dx * dx + dy * dy;
            const d = @sqrt(d2);
            const mag = k2v / d;
            const s = mag / d;
            const valid = d2 >= eps; // masks coincident AND the j==i lane (d²=0)
            accx += @select(f32, valid, dx * s, zero);
            accy += @select(f32, valid, dy * s, zero);
        }
        var fx = @reduce(.Add, accx);
        var fy = @reduce(.Add, accy);
        while (j < n) : (j += 1) {
            if (j == i) continue;
            const dx = xs[i] - xs[j];
            const dy = ys[i] - ys[j];
            const d2 = dx * dx + dy * dy;
            if (d2 < 1e-9) continue;
            const d = @sqrt(d2);
            const s = (k2 / d) / d;
            fx += dx * s;
            fy += dy * s;
        }
        fxs[i] += fx;
        fys[i] += fy;
    }
}

fn floatComparison(allocator: std.mem.Allocator, io: std.Io, n: usize) !void {
    const xs_q = try allocator.alloc(FP, n);
    defer allocator.free(xs_q);
    const ys_q = try allocator.alloc(FP, n);
    defer allocator.free(ys_q);
    fdg.common.initGridJitterSoa(xs_q, ys_q, fp.fromInt(10), 42);

    const xs = try allocator.alloc(f32, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(f32, n);
    defer allocator.free(ys);
    for (xs, xs_q) |*x, q| x.* = @as(f32, @floatFromInt(q)) / 65536.0;
    for (ys, ys_q) |*y, q| y.* = @as(f32, @floatFromInt(q)) / 65536.0;

    const fxs_q = try allocator.alloc(FP, n);
    defer allocator.free(fxs_q);
    const fys_q = try allocator.alloc(FP, n);
    defer allocator.free(fys_q);
    const fxs = try allocator.alloc(f32, n);
    defer allocator.free(fxs);
    const fys = try allocator.alloc(f32, n);
    defer allocator.free(fys);

    const iters: usize = if (n <= 500) 200 else 20;

    @memset(fxs_q, 0);
    @memset(fys_q, 0);
    const t_q = startTs(io);
    for (0..iters) |_| {
        fdg.forces.accumulatePairwiseRepulsion(xs_q, ys_q, fxs_q, fys_q, fp.fromInt(100), Range.full(n));
    }
    const q16_ns = elapsedNsPer(io, t_q, iters);
    std.mem.doNotOptimizeAway(&fxs_q[0]);

    @memset(fxs, 0);
    @memset(fys, 0);
    const t_f = startTs(io);
    for (0..iters) |_| {
        pairwiseF32Scalar(xs, ys, fxs, fys, 100.0);
    }
    const f32_ns = elapsedNsPer(io, t_f, iters);
    std.mem.doNotOptimizeAway(&fxs[0]);

    @memset(fxs, 0);
    @memset(fys, 0);
    const t_v = startTs(io);
    for (0..iters) |_| {
        pairwiseF32Simd(xs, ys, fxs, fys, 100.0);
    }
    const simd_ns = elapsedNsPer(io, t_v, iters);
    std.mem.doNotOptimizeAway(&fxs[0]);

    const r_scalar = @as(f64, @floatFromInt(q16_ns)) / @as(f64, @floatFromInt(f32_ns));
    const r_simd = @as(f64, @floatFromInt(q16_ns)) / @as(f64, @floatFromInt(simd_ns));
    const r_vec = @as(f64, @floatFromInt(f32_ns)) / @as(f64, @floatFromInt(simd_ns));
    std.debug.print("f32-vs-q16 (n={d}): q16 gather={d}ns  f32 scalar={d}ns ({d:.2}x vs q16)  " ++
        "f32 simd={d}ns ({d:.2}x vs q16, {d:.2}x vs f32 scalar)\n", .{ n, q16_ns, f32_ns, r_scalar, simd_ns, r_simd, r_vec });
}

/// The pre-Stage-D scatter loop, reproduced for measurement: each i<j pair
/// computed once, written to both endpoints. The gather kernel computes
/// each pair twice (once per endpoint) — this quantifies that cost on the
/// serial path.
fn legacyScatterPairwise(xs: []const FP, ys: []const FP, fxs: []FP, fys: []FP, k_squared: FP) void {
    const Vec2 = fp.Vec2;
    const n = xs.len;
    for (0..n) |i| {
        for ((i + 1)..n) |j| {
            const delta = Vec2{ .x = xs[i] -| xs[j], .y = ys[i] -| ys[j] };
            const d = delta.length();
            if (d < 2) continue;
            const force_mag = fp.div(k_squared, d);
            const force_vec = delta.normalizeScaled(force_mag);
            fxs[i] = fxs[i] +| force_vec.x;
            fys[i] = fys[i] +| force_vec.y;
            fxs[j] = fxs[j] -| force_vec.x;
            fys[j] = fys[j] -| force_vec.y;
        }
    }
}

/// The historical scatter loop WITH the same normalization-reuse
/// optimization the gather kernel now has. Comparing gather against this
/// isolates the pure architectural gather tax (each pair computed twice);
/// comparing against `legacyScatterPairwise` measures the regression vs
/// the code that actually shipped pre-Stage-D.
fn optimizedScatterPairwise(xs: []const FP, ys: []const FP, fxs: []FP, fys: []FP, k_squared: FP) void {
    const Vec2 = fp.Vec2;
    const n = xs.len;
    for (0..n) |i| {
        for ((i + 1)..n) |j| {
            const delta = Vec2{ .x = xs[i] -| xs[j], .y = ys[i] -| ys[j] };
            const d = delta.length();
            if (d < 2) continue;
            const force_mag = fp.div(k_squared, d);
            const force_vec = delta.normalizeScaledWithLength(force_mag, d);
            fxs[i] = fxs[i] +| force_vec.x;
            fys[i] = fys[i] +| force_vec.y;
            fxs[j] = fxs[j] -| force_vec.x;
            fys[j] = fys[j] -| force_vec.y;
        }
    }
}

fn scatterVsGather(allocator: std.mem.Allocator, io: std.Io, n: usize, k_squared: FP) !void {
    const xs = try allocator.alloc(FP, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(FP, n);
    defer allocator.free(ys);
    fdg.common.initGridJitterSoa(xs, ys, fp.fromInt(10), 42);
    const fxs = try allocator.alloc(FP, n);
    defer allocator.free(fxs);
    const fys = try allocator.alloc(FP, n);
    defer allocator.free(fys);

    const iters: usize = 200;

    // Per-pass resets keep accumulator values (and thus Newton-iteration
    // counts) identical across repetitions; the memset cost is noise
    // relative to the O(n²) kernels.
    const t_sc = startTs(io);
    for (0..iters) |_| {
        @memset(fxs, 0);
        @memset(fys, 0);
        legacyScatterPairwise(xs, ys, fxs, fys, k_squared);
    }
    const scatter_ns = elapsedNsPer(io, t_sc, iters);
    std.mem.doNotOptimizeAway(&fxs[0]);

    const t_opt = startTs(io);
    for (0..iters) |_| {
        @memset(fxs, 0);
        @memset(fys, 0);
        optimizedScatterPairwise(xs, ys, fxs, fys, k_squared);
    }
    const opt_scatter_ns = elapsedNsPer(io, t_opt, iters);
    std.mem.doNotOptimizeAway(&fxs[0]);

    const t_ga = startTs(io);
    for (0..iters) |_| {
        @memset(fxs, 0);
        @memset(fys, 0);
        fdg.forces.accumulatePairwiseRepulsion(xs, ys, fxs, fys, k_squared, Range.full(n));
    }
    const gather_ns = elapsedNsPer(io, t_ga, iters);
    std.mem.doNotOptimizeAway(&fxs[0]);

    const vs_shipped = @as(f64, @floatFromInt(gather_ns)) / @as(f64, @floatFromInt(scatter_ns));
    const gather_tax = @as(f64, @floatFromInt(gather_ns)) / @as(f64, @floatFromInt(opt_scatter_ns));
    std.debug.print("scatter-vs-gather (n={d}): legacy={d}ns  optimized-scatter={d}ns  gather={d}ns  " ++
        "vs-shipped={d:.2}x  gather-tax={d:.2}x\n", .{ n, scatter_ns, opt_scatter_ns, gather_ns, vs_shipped, gather_tax });
}

/// Measure (a) the full pairwise kernel, (b) only its delta+distance² part
/// (what option-A SIMD could vectorize), and (c) a @Vector implementation
/// of (b). Option A's overall ceiling ≈ share(b) × (1 − c/b).
fn microSplit(allocator: std.mem.Allocator, io: std.Io, n: usize, k_squared: FP) !void {
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();

    const xs = try allocator.alloc(FP, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(FP, n);
    defer allocator.free(ys);
    for (xs, ys) |*x, *y| {
        x.* = fp.fromInt(random.intRangeAtMost(i32, -500, 500));
        y.* = fp.fromInt(random.intRangeAtMost(i32, -500, 500));
    }
    const fxs = try allocator.alloc(FP, n);
    defer allocator.free(fxs);
    const fys = try allocator.alloc(FP, n);
    defer allocator.free(fys);
    @memset(fxs, 0);
    @memset(fys, 0);

    const iters: usize = 200;

    // (a) Full kernel.
    const t_full = startTs(io);
    for (0..iters) |_| {
        fdg.forces.accumulatePairwiseRepulsion(xs, ys, fxs, fys, k_squared, Range.full(n));
    }
    const full_ns = elapsedNsPer(io, t_full, iters);
    std.mem.doNotOptimizeAway(&fxs[0]);

    // (b) Scalar delta + distance² only (the vectorizable part).
    var sink: i64 = 0;
    const t_sc = startTs(io);
    for (0..iters) |_| {
        for (0..n) |i| {
            var acc: i64 = 0;
            for (0..n) |j| {
                const dx = xs[i] -| xs[j];
                const dy = ys[i] -| ys[j];
                acc +%= @as(i64, dx) * dx + @as(i64, dy) * dy;
            }
            sink +%= acc;
        }
    }
    const scalar_d2_ns = elapsedNsPer(io, t_sc, iters);
    std.mem.doNotOptimizeAway(&sink);

    // (c) @Vector(8, i32) version of (b).
    const L = 8;
    const V = @Vector(L, i32);
    const t_vec = startTs(io);
    for (0..iters) |_| {
        for (0..n) |i| {
            const xi: V = @splat(xs[i]);
            const yi: V = @splat(ys[i]);
            var acc: @Vector(L, i64) = @splat(0);
            var j: usize = 0;
            while (j + L <= n) : (j += L) {
                const xj: V = xs[j..][0..L].*;
                const yj: V = ys[j..][0..L].*;
                const dx = xi -| xj;
                const dy = yi -| yj;
                const dx64: @Vector(L, i64) = dx;
                const dy64: @Vector(L, i64) = dy;
                acc +%= dx64 * dx64 + dy64 * dy64;
            }
            var tail: i64 = @reduce(.Add, acc);
            while (j < n) : (j += 1) {
                const dx = xs[i] -| xs[j];
                const dy = ys[i] -| ys[j];
                tail +%= @as(i64, dx) * dx + @as(i64, dy) * dy;
            }
            sink +%= tail;
        }
    }
    const vector_d2_ns = elapsedNsPer(io, t_vec, iters);
    std.mem.doNotOptimizeAway(&sink);

    const share = @as(f64, @floatFromInt(scalar_d2_ns)) / @as(f64, @floatFromInt(full_ns));
    const vec_speedup = @as(f64, @floatFromInt(scalar_d2_ns)) / @as(f64, @floatFromInt(vector_d2_ns));
    const ceiling = share * (1.0 - 1.0 / vec_speedup);

    std.debug.print("\nmicro-split (n={d}): full={d}ns  delta+d2 scalar={d}ns ({d:.1}% of full)  " ++
        "vector={d}ns ({d:.2}x on that part)\n", .{ n, full_ns, scalar_d2_ns, share * 100.0, vector_d2_ns, vec_speedup });
    std.debug.print("option-A overall ceiling: {d:.1}% of pairwise kernel time\n", .{ceiling * 100.0});
}
