//! Q16.16 Fixed-Point Arithmetic
//!
//! All FDG algorithms use Q16.16 fixed-point internally for
//! bit-exact deterministic output across all platforms.
//!
//! ## Format
//!
//!   Bits:      [31 sign] [30..16 integer] [15..0 fraction]
//!   Range:     -32768.0 to +32767.99998
//!   Precision: 1/65536 ≈ 0.000015
//!   Storage:   4 bytes per value (i32)
//!
//! ## Standalone Usage
//!
//! ```zig
//! const fp = @import("zigraph").fdg.fixed_point;
//! const a = fp.fromInt(3);
//! const b = fp.fromInt(4);
//! const c = fp.sqrt(fp.add(fp.mul(a, a), fp.mul(b, b)));
//! // c ≈ 5.0 in Q16.16
//! ```

const std = @import("std");

/// Q16.16 fixed-point type.
pub const FP = i32;

/// Number of fractional bits.
pub const SHIFT: u5 = 16;

/// 1.0 in Q16.16.
pub const ONE: FP = 1 << SHIFT; // 65536

/// 0.0 in Q16.16.
pub const ZERO: FP = 0;

/// Maximum representable value (~32767.99998).
pub const MAX: FP = std.math.maxInt(i32);

/// Minimum representable value (-32768.0).
pub const MIN: FP = std.math.minInt(i32);

// ============================================================================
// Conversion
// ============================================================================

/// Convert an integer to Q16.16.
pub fn fromInt(val: i32) FP {
    return val << SHIFT;
}

/// Convert Q16.16 to integer (truncates toward zero).
pub fn toInt(val: FP) i32 {
    if (val >= 0) {
        return val >> SHIFT;
    } else {
        // Arithmetic right shift for negative values — truncate toward zero
        return -(@as(i32, (-val) >> SHIFT));
    }
}

/// Convert Q16.16 to integer (rounds to nearest).
pub fn toIntRounded(val: FP) i32 {
    if (val >= 0) {
        return (val + (ONE >> 1)) >> SHIFT;
    } else {
        return -((-val + (ONE >> 1)) >> SHIFT);
    }
}

/// Convert Q16.16 to f64 (for debugging / output only).
pub fn toFloat(val: FP) f64 {
    return @as(f64, @floatFromInt(val)) / @as(f64, @floatFromInt(ONE));
}

/// Convert f64 to Q16.16 (for initialization only — not used in simulation loop).
pub fn fromFloat(val: f64) FP {
    return @intFromFloat(val * @as(f64, @floatFromInt(ONE)));
}

// ============================================================================
// Basic arithmetic
// ============================================================================

/// Addition (saturating to prevent overflow).
pub fn add(a: FP, b: FP) FP {
    return a +| b;
}

/// Accumulating add for force kernels — **contract instrumentation, not a
/// general-purpose arithmetic API**. Intended for gather-kernel
/// implementations (zigraph's own, and custom kernels written against the
/// passive-parallelism contract that want the same invariant checking);
/// everyone else should use `add`.
///
/// Identical to `add` (saturating) in
/// every consumer build mode. **Test builds only** additionally assert the
/// exact sum stays in range: the attraction gather's golden equivalence
/// with the historical scatter ordering depends on accumulation not
/// saturating (saturating addition is not associative at overflow, so
/// regrouping/reordering changes results). Gating on `is_test` verifies
/// that precondition across the golden/fuzz corpus without turning valid
/// high-force workloads into panics for library consumers — saturation
/// remains supported, silently, exactly as it always was.
pub fn accumAdd(a: FP, b: FP) FP {
    if (@import("builtin").is_test) {
        const wide = @as(i64, a) + @as(i64, b);
        std.debug.assert(wide >= std.math.minInt(i32) and wide <= std.math.maxInt(i32));
    }
    return a +| b;
}

/// Subtracting counterpart of `accumAdd` (use instead of `accumAdd(a, -b)`,
/// which would overflow when `b` is the saturated minimum). Same
/// test-only instrumentation, same saturating consumer semantics.
pub fn accumSub(a: FP, b: FP) FP {
    if (@import("builtin").is_test) {
        const wide = @as(i64, a) - @as(i64, b);
        std.debug.assert(wide >= std.math.minInt(i32) and wide <= std.math.maxInt(i32));
    }
    return a -| b;
}

/// Subtraction (saturating).
pub fn sub(a: FP, b: FP) FP {
    return a -| b;
}

/// Multiplication: a * b in Q16.16.
/// Uses i64 intermediate to prevent overflow.
/// Saturates to MAX/MIN if the result exceeds i32 range.
pub fn mul(a: FP, b: FP) FP {
    const wide: i64 = @as(i64, a) * @as(i64, b);
    const result = wide >> SHIFT;
    if (result > std.math.maxInt(i32)) return MAX;
    if (result < std.math.minInt(i32)) return MIN;
    return @intCast(result);
}

/// Division: a / b in Q16.16.
/// Uses i64 intermediate for precision.
/// Returns MAX or MIN on division by zero or overflow (saturates).
pub fn div(a: FP, b: FP) FP {
    if (b == 0) {
        return if (a >= 0) MAX else MIN;
    }
    const wide: i64 = @as(i64, a) << SHIFT;
    const result = @divTrunc(wide, @as(i64, b));
    if (result > std.math.maxInt(i32)) return MAX;
    if (result < std.math.minInt(i32)) return MIN;
    return @intCast(result);
}

/// Negate.
pub fn neg(a: FP) FP {
    return -a;
}

/// Absolute value.
pub fn abs(a: FP) FP {
    return if (a >= 0) a else -a;
}

/// Minimum of two values.
pub fn min(a: FP, b: FP) FP {
    return @min(a, b);
}

/// Maximum of two values.
pub fn max(a: FP, b: FP) FP {
    return @max(a, b);
}

/// Clamp value to range [lo, hi].
pub fn clamp(val: FP, lo: FP, hi: FP) FP {
    return @min(@max(val, lo), hi);
}

// ============================================================================
// Advanced operations
// ============================================================================

/// Integer square root of a Q16.16 value.
///
/// Returns sqrt(val) in Q16.16.
/// Uses Newton's method on i64 intermediates for full precision.
pub fn sqrt(val: FP) FP {
    if (val <= 0) return 0;

    // To compute sqrt of a Q16.16 number:
    // sqrt(x * 2^16) = sqrt(x) * 2^8
    // We need the result in Q16.16, so shift input up by 16 first:
    // sqrt(x << 16) gives result in Q16.16
    const shifted: i64 = @as(i64, val) << SHIFT;

    // Newton's method: guess = (guess + shifted/guess) / 2
    var guess: i64 = shifted;
    // Start with a reasonable initial guess
    if (guess > (1 << 32)) {
        guess = 1 << 24;
    } else if (guess > (1 << 16)) {
        guess = 1 << 16;
    }

    var i: u32 = 0;
    while (i < 32) : (i += 1) {
        if (guess == 0) return 0;
        const next = (guess + @divTrunc(shifted, guess)) >> 1;
        if (next >= guess) break; // Converged
        guess = next;
    }

    // Clamp to i32 range
    if (guess > std.math.maxInt(i32)) return MAX;
    return @intCast(guess);
}

/// Distance between two 2D points in Q16.16.
/// Returns sqrt(dx² + dy²).
pub fn dist(dx: FP, dy: FP) FP {
    // Use i64 to compute dx² + dy² without overflow
    const dx2: i64 = @as(i64, dx) * @as(i64, dx);
    const dy2: i64 = @as(i64, dy) * @as(i64, dy);
    const sum = dx2 + dy2;

    // sum is in Q32.32 (two Q16.16 values multiplied).
    // We need sqrt(sum) in Q16.16.
    // sqrt(sum_q32) = sqrt(sum) in Q16.16 directly.
    if (sum <= 0) return 0;

    // Newton's method on i64
    var guess: i64 = sum;
    if (guess > (1 << 48)) {
        guess = 1 << 32;
    } else if (guess > (1 << 32)) {
        guess = 1 << 24;
    } else {
        guess = 1 << 16;
    }

    var i: u32 = 0;
    while (i < 48) : (i += 1) {
        if (guess == 0) return 0;
        const next = (guess + @divTrunc(sum, guess)) >> 1;
        if (next >= guess) break;
        guess = next;
    }

    if (guess > std.math.maxInt(i32)) return MAX;
    return @intCast(guess);
}

// ============================================================================
// Exp lookup table for Simulated Annealing
// ============================================================================

/// Number of entries in the exp lookup table.
const EXP_TABLE_SIZE = 256;

/// Precomputed exp(-x) table for x in [0, 8) with Q16.16 output.
///
/// Table maps index i → exp(-i * 8 / 256) * ONE.
/// Covers exp(0) = 1.0 down to exp(-8) ≈ 0.00034.
/// Values below exp(-8) are effectively zero for SA acceptance.
const exp_table: [EXP_TABLE_SIZE]FP = blk: {
    var table: [EXP_TABLE_SIZE]FP = undefined;
    for (0..EXP_TABLE_SIZE) |i| {
        const x: f64 = @as(f64, @floatFromInt(i)) * 8.0 / @as(f64, @floatFromInt(EXP_TABLE_SIZE));
        const val: f64 = @exp(-x);
        table[i] = @intFromFloat(val * @as(f64, @floatFromInt(ONE)));
    }
    break :blk table;
};

/// Approximate exp(-x) for x >= 0 in Q16.16.
///
/// Used for SA acceptance probability: exp(-ΔE / T).
/// Returns a Q16.16 value in [0, ONE] (i.e., [0.0, 1.0]).
///
/// For x < 0 (energy improvement), returns ONE (always accept).
/// For x > 8.0 in Q16.16 (524288), returns 0 (never accept).
pub fn expNeg(x: FP) FP {
    if (x <= 0) return ONE; // exp(0) or exp(positive) → clamp to 1.0
    if (x >= fromInt(8)) return 0; // exp(-8) ≈ 0

    // Map x from Q16.16 to table index: idx = x * 256 / 8 / ONE
    // = x * 32 / ONE = (x * 32) >> 16
    const idx_wide: i64 = @as(i64, x) * 32;
    const idx_raw: i64 = idx_wide >> SHIFT;
    const idx: usize = @intCast(@min(idx_raw, EXP_TABLE_SIZE - 1));

    return exp_table[idx];
}

// ============================================================================
// 2D Vector type
// ============================================================================

/// 2D vector in Q16.16 fixed-point.
pub const Vec2 = struct {
    x: FP = ZERO,
    y: FP = ZERO,

    pub fn init(x: FP, y: FP) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn addVec(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = add(self.x, other.x), .y = add(self.y, other.y) };
    }

    pub fn subVec(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = sub(self.x, other.x), .y = sub(self.y, other.y) };
    }

    /// Scale vector by a Q16.16 scalar.
    pub fn scale(self: Vec2, s: FP) Vec2 {
        return .{ .x = mul(self.x, s), .y = mul(self.y, s) };
    }

    /// Euclidean length of the vector.
    pub fn length(self: Vec2) FP {
        return dist(self.x, self.y);
    }

    /// Distance to another vector.
    pub fn distTo(self: Vec2, other: Vec2) FP {
        return dist(sub(self.x, other.x), sub(self.y, other.y));
    }

    /// Normalize to unit length, scaled by `target_length`.
    /// If the vector is zero-length, returns (target_length, 0) to avoid NaN.
    pub fn normalizeScaled(self: Vec2, target_length: FP) Vec2 {
        return self.normalizeScaledWithLength(target_length, self.length());
    }

    /// Like `normalizeScaled`, but reuses an already-computed `len` (which
    /// must equal `self.length()` — asserted in **test builds only**, since
    /// the check itself recomputes the sqrt this variant exists to avoid;
    /// consumer builds, including Debug and ReleaseSafe, trust the caller
    /// and keep the single-sqrt win). Every force interaction computes the
    /// length for its distance guard and magnitude anyway; passing it in
    /// removes the second Newton-loop square root per interaction.
    /// Bit-identical to `normalizeScaled` given the same vector.
    pub fn normalizeScaledWithLength(self: Vec2, target_length: FP, len: FP) Vec2 {
        if (@import("builtin").is_test) {
            std.debug.assert(len == self.length());
        }
        if (len == 0) {
            return .{ .x = target_length, .y = ZERO };
        }
        // Wide intermediates: the former div(mul(x, target), len) saturated
        // the *intermediate* product once |coordinate × magnitude| exceeded
        // the Q16.16 integer range (e.g. delta 600 × force 66), silently
        // corrupting large force vectors in every kernel. The wide form
        // performs the identical shift/truncation sequence without the
        // intermediate clamp — bit-identical whenever the old path did not
        // saturate — and clamps only the final result.
        const wx = (@as(i64, self.x) * target_length) >> SHIFT;
        const wy = (@as(i64, self.y) * target_length) >> SHIFT;
        return .{ .x = divWide(wx, len), .y = divWide(wy, len) };
    }

    fn divWide(a: i64, b: FP) FP {
        const result = @divTrunc(a << SHIFT, @as(i64, b));
        if (result > std.math.maxInt(i32)) return MAX;
        if (result < std.math.minInt(i32)) return MIN;
        return @intCast(result);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "fromInt / toInt round-trip" {
    try std.testing.expectEqual(@as(i32, 0), toInt(fromInt(0)));
    try std.testing.expectEqual(@as(i32, 1), toInt(fromInt(1)));
    try std.testing.expectEqual(@as(i32, -1), toInt(fromInt(-1)));
    try std.testing.expectEqual(@as(i32, 100), toInt(fromInt(100)));
    try std.testing.expectEqual(@as(i32, -100), toInt(fromInt(-100)));
}

test "fromFloat / toFloat round-trip" {
    const val = fromFloat(3.14159);
    const back = toFloat(val);
    try std.testing.expect(@abs(back - 3.14159) < 0.0001);
}

test "mul basic" {
    // 3 * 4 = 12
    try std.testing.expectEqual(fromInt(12), mul(fromInt(3), fromInt(4)));
    // 1.5 * 2 = 3
    const one_half = fromInt(1) + (ONE >> 1); // 1.5
    try std.testing.expectEqual(fromInt(3), mul(one_half, fromInt(2)));
    // -2 * 3 = -6
    try std.testing.expectEqual(fromInt(-6), mul(fromInt(-2), fromInt(3)));
}

test "div basic" {
    // 12 / 4 = 3
    try std.testing.expectEqual(fromInt(3), div(fromInt(12), fromInt(4)));
    // 1 / 2 = 0.5
    const half = div(fromInt(1), fromInt(2));
    try std.testing.expectEqual(ONE >> 1, half);
    // Division by zero saturates
    try std.testing.expectEqual(MAX, div(fromInt(1), ZERO));
    try std.testing.expectEqual(MIN, div(fromInt(-1), ZERO));
}

test "sqrt basic" {
    // sqrt(4) = 2
    const s4 = sqrt(fromInt(4));
    try std.testing.expect(abs(sub(s4, fromInt(2))) < 2); // Within 1 ULP

    // sqrt(9) = 3
    const s9 = sqrt(fromInt(9));
    try std.testing.expect(abs(sub(s9, fromInt(3))) < 2);

    // sqrt(1) = 1
    const s1 = sqrt(fromInt(1));
    try std.testing.expect(abs(sub(s1, fromInt(1))) < 2);

    // sqrt(0) = 0
    try std.testing.expectEqual(@as(FP, 0), sqrt(ZERO));

    // sqrt(2) ≈ 1.4142
    const s2 = sqrt(fromInt(2));
    const expected = fromFloat(1.41421356);
    try std.testing.expect(abs(sub(s2, expected)) < fromFloat(0.001));
}

test "dist: 3-4-5 triangle" {
    const d = dist(fromInt(3), fromInt(4));
    try std.testing.expect(abs(sub(d, fromInt(5))) < fromFloat(0.01));
}

test "expNeg basic" {
    // exp(0) = 1.0
    try std.testing.expectEqual(ONE, expNeg(ZERO));

    // exp(-large) ≈ 0
    try std.testing.expectEqual(@as(FP, 0), expNeg(fromInt(10)));

    // exp(-1) ≈ 0.368
    const e1 = expNeg(fromInt(1));
    const expected = fromFloat(0.368);
    try std.testing.expect(abs(sub(e1, expected)) < fromFloat(0.05));
}

test "Vec2 operations" {
    const a = Vec2.init(fromInt(3), fromInt(4));
    const b = Vec2.init(fromInt(1), fromInt(2));

    // add
    const c = a.addVec(b);
    try std.testing.expectEqual(fromInt(4), c.x);
    try std.testing.expectEqual(fromInt(6), c.y);

    // sub
    const d = a.subVec(b);
    try std.testing.expectEqual(fromInt(2), d.x);
    try std.testing.expectEqual(fromInt(2), d.y);

    // length of (3, 4) = 5
    const len = a.length();
    try std.testing.expect(abs(sub(len, fromInt(5))) < fromFloat(0.01));

    // normalizeScaled to length 10
    const n = a.normalizeScaled(fromInt(10));
    const nlen = n.length();
    try std.testing.expect(abs(sub(nlen, fromInt(10))) < fromFloat(0.1));
}

test "saturating add/sub" {
    // These should not overflow
    const big = MAX - fromInt(1);
    const result = add(big, fromInt(2));
    try std.testing.expectEqual(MAX, result);

    const small = MIN + fromInt(1);
    const result2 = sub(small, fromInt(2));
    try std.testing.expectEqual(MIN, result2);
}

test "add/sub: saturating semantics at the extremes" {
    // accumAdd/accumSub share these exact semantics in consumer builds;
    // their test-only instrumentation asserts the golden/fuzz corpus never
    // reaches saturation (which is why they cannot be exercised with
    // saturating inputs here — see the accumAdd doc comment).
    try std.testing.expectEqual(MAX, add(MAX, ONE));
    try std.testing.expectEqual(MAX, add(MAX, MAX));
    try std.testing.expectEqual(MIN, add(MIN, -ONE));
    try std.testing.expectEqual(MIN, sub(MIN, ONE));
    try std.testing.expectEqual(MAX, sub(MAX, -ONE));
}

test "normalizeScaledWithLength: equivalent to normalizeScaled" {
    // Edge cases: zero vector, negatives, extremes near saturation.
    const cases = [_]Vec2{
        .{ .x = 0, .y = 0 },
        .{ .x = fromInt(3), .y = fromInt(-4) },
        .{ .x = -ONE, .y = -ONE },
        .{ .x = MAX, .y = 0 },
        .{ .x = MIN + 1, .y = ONE },
    };
    for (cases) |v| {
        const a = v.normalizeScaled(fromInt(7));
        const b = v.normalizeScaledWithLength(fromInt(7), v.length());
        try std.testing.expectEqual(a.x, b.x);
        try std.testing.expectEqual(a.y, b.y);
    }

    // Randomized vectors and target lengths.
    var prng = std.Random.DefaultPrng.init(99);
    const random = prng.random();
    for (0..200) |_| {
        const v = Vec2{
            .x = random.intRangeAtMost(FP, -1_000_000, 1_000_000),
            .y = random.intRangeAtMost(FP, -1_000_000, 1_000_000),
        };
        const target = random.intRangeAtMost(FP, 0, 500_000);
        const a = v.normalizeScaled(target);
        const b = v.normalizeScaledWithLength(target, v.length());
        try std.testing.expectEqual(a.x, b.x);
        try std.testing.expectEqual(a.y, b.y);
    }
}

test "normalizeScaledWithLength: no intermediate saturation (oracle)" {
    // (600, 0) scaled to length 66. The pre-fix implementation saturated
    // the intermediate 600 × 66 product (> 32767 in value space) and
    // returned ~54.6 instead of 66 — this expected-value oracle pins the
    // wide-arithmetic fix directly (the equivalence test alone cannot,
    // since both entry points share the wide implementation).
    const v = Vec2{ .x = fromInt(600), .y = ZERO };
    const len = v.length();
    try std.testing.expectEqual(fromInt(600), len);

    const scaled = v.normalizeScaledWithLength(fromInt(66), len);
    try std.testing.expectEqual(fromInt(66), scaled.x);
    try std.testing.expectEqual(ZERO, scaled.y);

    // Same through the recomputing wrapper.
    const scaled2 = v.normalizeScaled(fromInt(66));
    try std.testing.expectEqual(fromInt(66), scaled2.x);

    // Negative component: same magnitude, mirrored sign.
    const vn = Vec2{ .x = fromInt(-600), .y = ZERO };
    const scaled_n = vn.normalizeScaledWithLength(fromInt(66), vn.length());
    try std.testing.expectEqual(fromInt(-66), scaled_n.x);
}
