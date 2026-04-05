//! Box-drawing codepoint constants and junction merging logic.
//!
//! Provides the Unicode codepoints used for edges, corners, T-junctions,
//! crossings, subgraph borders, and mixed-weight border crossings.
//!
//! ## Weight-aware junction merging
//!
//! `mergeJunction` resolves overlapping box-drawing characters by tracking
//! the weight (none/light/heavy/double) of each arm (up/down/left/right).
//! An existing cell is decomposed into a `DirWeights`, merged with the
//! new edge's directions and weight, then looked up to produce the
//! correct character — including mixed light↔heavy and light↔double
//! characters from the Unicode Box Drawing block (U+2500–U+257F).

const std = @import("std");
const LineWeight = @import("config.zig").LineWeight;

// ── Arm weight for junction resolution ──────────────────────────────────────

/// Weight of a single arm in a junction cell.
/// Ordered so that `.max()` picks the visually heavier weight.
pub const ArmWeight = enum(u3) {
    none = 0,
    light = 1,
    dashed = 2, // renders as light for junction purposes
    heavy = 3,
    double = 4,

    pub fn fromLineWeight(w: LineWeight) ArmWeight {
        return switch (w) {
            .light => .light,
            .heavy => .heavy,
            .double => .double,
            .dashed => .dashed,
        };
    }

    /// The effective weight for junction character lookup.
    /// Dashed arms are treated as light for junction resolution
    /// (dashed has no junction characters of its own).
    pub fn effective(self: ArmWeight) ArmWeight {
        return if (self == .dashed) .light else self;
    }

    /// Return the heavier of two weights.
    pub fn merge(a: ArmWeight, b: ArmWeight) ArmWeight {
        return if (@intFromEnum(a) >= @intFromEnum(b)) a else b;
    }
};

/// Per-direction weights for junction resolution.
pub const DirWeights = struct {
    up: ArmWeight = .none,
    down: ArmWeight = .none,
    left: ArmWeight = .none,
    right: ArmWeight = .none,

    pub fn mergeWith(self: DirWeights, other: DirWeights) DirWeights {
        return .{
            .up = ArmWeight.merge(self.up, other.up),
            .down = ArmWeight.merge(self.down, other.down),
            .left = ArmWeight.merge(self.left, other.left),
            .right = ArmWeight.merge(self.right, other.right),
        };
    }
};

// ── Light box-drawing characters ────────────────────────────────────────────

pub const CP_V_LINE: u21 = '│';
pub const CP_H_LINE: u21 = '─';
// Legacy arrow constants — kept for mergeJunction decomposition of existing cells.
pub const CP_ARROW_DOWN: u21 = '↓';
pub const CP_ARROW_UP: u21 = '↑';
pub const CP_ARROW_RIGHT: u21 = '→';
pub const CP_ARROW_LEFT: u21 = '←';
// Dashed arrows for reversed (back) edges
pub const CP_ARROW_DOWN_DASH: u21 = '⇣';
pub const CP_ARROW_UP_DASH: u21 = '⇡';
pub const CP_ARROW_RIGHT_DASH: u21 = '⇢';
pub const CP_ARROW_LEFT_DASH: u21 = '⇠';
// Dashed line characters for reversed (back) edge body segments
pub const CP_V_LINE_DASH: u21 = '┊'; // light quadruple dash vertical
pub const CP_H_LINE_DASH: u21 = '┈'; // light quadruple dash horizontal
pub const CP_CORNER_DR: u21 = '└'; // down-right (from above, going right)
pub const CP_CORNER_DL: u21 = '┘'; // down-left (from above, going left)
pub const CP_CORNER_UR: u21 = '┌'; // from above-right, going down
pub const CP_CORNER_UL: u21 = '┐'; // from above-left, going down
pub const CP_T_DOWN: u21 = '┬'; // T-junction: horizontal with down
pub const CP_T_UP: u21 = '┴'; // T-junction: horizontal with up
pub const CP_T_RIGHT: u21 = '├'; // T-junction: vertical with right
pub const CP_T_LEFT: u21 = '┤'; // T-junction: vertical with left
pub const CP_CROSS: u21 = '┼'; // Crossing

// ── Heavy box-drawing characters ────────────────────────────────────────────

pub const CP_HV_V_LINE: u21 = '┃'; // heavy vertical
pub const CP_HV_H_LINE: u21 = '━'; // heavy horizontal
pub const CP_HV_CORNER_DR: u21 = '┗'; // heavy └
pub const CP_HV_CORNER_DL: u21 = '┛'; // heavy ┘
pub const CP_HV_CORNER_UR: u21 = '┏'; // heavy ┌
pub const CP_HV_CORNER_UL: u21 = '┓'; // heavy ┐
pub const CP_HV_T_DOWN: u21 = '┳'; // heavy ┬
pub const CP_HV_T_UP: u21 = '┻'; // heavy ┴
pub const CP_HV_T_RIGHT: u21 = '┣'; // heavy ├
pub const CP_HV_T_LEFT: u21 = '┫'; // heavy ┤
pub const CP_HV_CROSS: u21 = '╋'; // heavy ┼

// ── Mixed light↔heavy box-drawing characters ────────────────────────────────
// Naming: MX_{up}_{down}_{left}_{right} where L=light, H=heavy

// Corners (2-arm)
pub const CP_MX_LH_CORNER_DR: u21 = '┖'; // light up + heavy right (└ variant)
pub const CP_MX_HL_CORNER_DR: u21 = '┕'; // heavy up + light right
pub const CP_MX_LH_CORNER_DL: u21 = '┚'; // light up + heavy left (┘ variant)
pub const CP_MX_HL_CORNER_DL: u21 = '┙'; // heavy up + light left
pub const CP_MX_LH_CORNER_UR: u21 = '┎'; // light down + heavy right (┌ variant)
pub const CP_MX_HL_CORNER_UR: u21 = '┍'; // heavy down + light right
// Note: corner naming follows the pattern of which direction the arm extends FROM,
// not which corner of a box it represents.
pub const CP_MX_LH_CORNER_UL: u21 = '┒'; // light down + heavy left (┐ variant)
pub const CP_MX_HL_CORNER_UL: u21 = '┑'; // heavy down + light left

// T-junctions (3-arm) — many combinations
pub const CP_MX_T_DOWN_HH_L: u21 = '┭'; // heavy left + heavy right + light down (┬ variant)
pub const CP_MX_T_DOWN_LL_H: u21 = '┰'; // light left + light right + heavy down
pub const CP_MX_T_DOWN_HL_L: u21 = '┮'; // heavy left + light right + light down
pub const CP_MX_T_DOWN_LH_L: u21 = '┯'; // light left + heavy right + light down
pub const CP_MX_T_DOWN_HL_H: u21 = '┱'; // heavy left + light right + heavy down
pub const CP_MX_T_DOWN_LH_H: u21 = '┲'; // light left + heavy right + heavy down

pub const CP_MX_T_UP_HH_L: u21 = '┵'; // heavy left + heavy right + light up (┴ variant)
pub const CP_MX_T_UP_LL_H: u21 = '┸'; // light left + light right + heavy up
pub const CP_MX_T_UP_HL_L: u21 = '┶'; // heavy left + light right + light up
pub const CP_MX_T_UP_LH_L: u21 = '┷'; // light left + heavy right + light up
pub const CP_MX_T_UP_HL_H: u21 = '┹'; // heavy left + light right + heavy up
pub const CP_MX_T_UP_LH_H: u21 = '┺'; // light left + heavy right + heavy up

pub const CP_MX_T_RIGHT_LL_H: u21 = '┝'; // light up + light down + heavy right (├ variant)
pub const CP_MX_T_RIGHT_HH_L: u21 = '┠'; // heavy up + heavy down + light right
pub const CP_MX_T_RIGHT_LH_L: u21 = '┞'; // light up + heavy down + light right
pub const CP_MX_T_RIGHT_HL_L: u21 = '┟'; // heavy up + light down + light right
pub const CP_MX_T_RIGHT_LH_H: u21 = '┡'; // light up + heavy down + heavy right
pub const CP_MX_T_RIGHT_HL_H: u21 = '┢'; // heavy up + light down + heavy right

pub const CP_MX_T_LEFT_LL_H: u21 = '┥'; // light up + light down + heavy left (┤ variant)
pub const CP_MX_T_LEFT_HH_L: u21 = '┨'; // heavy up + heavy down + light left
pub const CP_MX_T_LEFT_LH_L: u21 = '┦'; // light up + heavy down + light left
pub const CP_MX_T_LEFT_HL_L: u21 = '┧'; // heavy up + light down + light left
pub const CP_MX_T_LEFT_LH_H: u21 = '┩'; // light up + heavy down + heavy left
pub const CP_MX_T_LEFT_HL_H: u21 = '┪'; // heavy up + light down + heavy left

// Crossings (4-arm)
pub const CP_MX_CROSS_HH_LL: u21 = '╂'; // heavy up+down + light left+right
pub const CP_MX_CROSS_LL_HH: u21 = '┿'; // light up+down + heavy left+right
pub const CP_MX_CROSS_HL_LL: u21 = '╀'; // heavy up + light down + light left+right
pub const CP_MX_CROSS_LH_LL: u21 = '╁'; // light up + heavy down + light left+right
pub const CP_MX_CROSS_LL_HL: u21 = '┽'; // light up+down + heavy left + light right
pub const CP_MX_CROSS_LL_LH: u21 = '┾'; // light up+down + light left + heavy right
pub const CP_MX_CROSS_HL_HH: u21 = '╈'; // heavy up + light down + heavy left+right
pub const CP_MX_CROSS_LH_HH: u21 = '╇'; // light up + heavy down + heavy left+right
pub const CP_MX_CROSS_HH_HL: u21 = '╉'; // heavy up+down + heavy left + light right
pub const CP_MX_CROSS_HH_LH: u21 = '╊'; // heavy up+down + light left + heavy right
pub const CP_MX_CROSS_HL_HL: u21 = '╃'; // heavy up + light down + heavy left + light right
pub const CP_MX_CROSS_HL_LH: u21 = '╄'; // heavy up + light down + light left + heavy right
pub const CP_MX_CROSS_LH_HL: u21 = '╅'; // light up + heavy down + heavy left + light right
pub const CP_MX_CROSS_LH_LH: u21 = '╆'; // light up + heavy down + light left + heavy right

// ── Double-line box-drawing characters ──────────────────────────────────────

pub const CP_DB_V_LINE: u21 = '║'; // double vertical
pub const CP_DB_H_LINE: u21 = '═'; // double horizontal
pub const CP_DB_CORNER_DR: u21 = '╚'; // double └
pub const CP_DB_CORNER_DL: u21 = '╝'; // double ┘
pub const CP_DB_CORNER_UR: u21 = '╔'; // double ┌
pub const CP_DB_CORNER_UL: u21 = '╗'; // double ┐
pub const CP_DB_T_DOWN: u21 = '╦'; // double ┬
pub const CP_DB_T_UP: u21 = '╩'; // double ┴
pub const CP_DB_T_RIGHT: u21 = '╠'; // double ├
pub const CP_DB_T_LEFT: u21 = '╣'; // double ┤
pub const CP_DB_CROSS: u21 = '╬'; // double ┼

// ── Mixed light↔double box-drawing characters ───────────────────────────────

// Corners
pub const CP_MD_CORNER_DR_LD: u21 = '╘'; // light up + double right (└ variant)
pub const CP_MD_CORNER_DR_DL: u21 = '╙'; // double up + light right
pub const CP_MD_CORNER_DL_LD: u21 = '╛'; // light up + double left (┘ variant)
pub const CP_MD_CORNER_DL_DL: u21 = '╜'; // double up + light left
pub const CP_MD_CORNER_UR_LD: u21 = '╒'; // light down + double right (┌ variant)
pub const CP_MD_CORNER_UR_DL: u21 = '╓'; // double down + light right
pub const CP_MD_CORNER_UL_LD: u21 = '╕'; // light down + double left (┐ variant)
pub const CP_MD_CORNER_UL_DL: u21 = '╖'; // double down + light left

// T-junctions
pub const CP_MD_T_DOWN_DD_L: u21 = '╤'; // double left + double right + light down
pub const CP_MD_T_DOWN_LL_D: u21 = '╥'; // light left + light right + double down

// Note: Unicode only has 5 mixed light+double T/cross characters.
// The full set doesn't exist. We use what's available.

// Crossings
pub const CP_MD_CROSS_DH: u21 = '╪'; // light vert + double horiz crossing
pub const CP_MD_CROSS_DV: u21 = '╫'; // double vert + light horiz crossing

// T-junctions (the 5 that exist in Unicode for light↔double)
pub const CP_MD_T_RIGHT_DV: u21 = '╞'; // light right from double vertical
pub const CP_MD_T_LEFT_DV: u21 = '╡'; // light left from double vertical
pub const CP_MD_T_DOWN_DH: u21 = '╤'; // light down from double horizontal
pub const CP_MD_T_UP_DH: u21 = '╧'; // light up from double horizontal

// ── Subgraph border aliases (backward compatibility) ────────────────────────
// These alias the double-line characters for subgraph borders.

pub const CP_SG_UR: u21 = CP_DB_CORNER_UR; // ╔ top-left
pub const CP_SG_UL: u21 = CP_DB_CORNER_UL; // ╗ top-right
pub const CP_SG_DR: u21 = CP_DB_CORNER_DR; // ╚ bottom-left
pub const CP_SG_DL: u21 = CP_DB_CORNER_DL; // ╝ bottom-right
pub const CP_SG_H: u21 = CP_DB_H_LINE; // ═ horizontal
pub const CP_SG_V: u21 = CP_DB_V_LINE; // ║ vertical

// ── Mixed single/double box-drawing (backward-compat aliases) ───────────────

pub const CP_MIX_CROSS_DH: u21 = CP_MD_CROSS_DH; // ╪
pub const CP_MIX_CROSS_DV: u21 = CP_MD_CROSS_DV; // ╫
pub const CP_MIX_T_DOWN_DH: u21 = CP_MD_T_DOWN_DH; // ╤
pub const CP_MIX_T_UP_DH: u21 = CP_MD_T_UP_DH; // ╧
pub const CP_MIX_T_RIGHT_DV: u21 = CP_MD_T_RIGHT_DV; // ╞
pub const CP_MIX_T_LEFT_DV: u21 = CP_MD_T_LEFT_DV; // ╡

// ── Character decomposition and lookup ───────────────────────────────────────

/// Map a Unicode codepoint to its ASCII equivalent for `.ascii` char_set.
/// Box-drawing characters are classified via arm decomposition:
///   corners / T-junctions / crossings → '+'
///   horizontal lines → '-' (or '=' for double weight)
///   vertical lines → '|'
/// Arrows, markers, and other special characters have explicit mappings.
/// Non-box-drawing characters pass through unchanged.
pub fn toAscii(cp: u21) u21 {
    // Fast path: already ASCII
    if (cp < 128) return cp;

    // Arrows and markers
    return switch (cp) {
        '\u{2193}', '\u{25BC}', '\u{25BD}', '\u{21E3}' => 'v', // ↓ ▼ ▽ ⇣
        '\u{2191}', '\u{25B2}', '\u{25B3}', '\u{21E1}' => '^', // ↑ ▲ △ ⇡
        '\u{2192}', '\u{25B6}', '\u{25B7}', '\u{21E2}' => '>', // → ▶ ▷ ⇢
        '\u{2190}', '\u{25C0}', '\u{25C1}', '\u{21E0}' => '<', // ← ◀ ◁ ⇠
        '\u{25C6}', '\u{25C7}' => '*', // ◆ ◇
        '\u{25CF}', '\u{25CB}' => 'o', // ● ○
        0x21BA => '@', // ↺ self-loop (@ suggests circular/self-referencing)
        0x2312 => '+', // ⌒ (arc crossing)
        else => blk: {
            // Box-drawing: decompose into directional arm weights
            const dw = decomposeChar(cp);
            const has_up = dw.up != .none;
            const has_down = dw.down != .none;
            const has_left = dw.left != .none;
            const has_right = dw.right != .none;
            const vert: u2 = @as(u2, @intFromBool(has_up)) + @intFromBool(has_down);
            const horiz: u2 = @as(u2, @intFromBool(has_left)) + @intFromBool(has_right);

            if (@as(u3, vert) + horiz == 0) break :blk cp; // not a recognized box char
            if (vert > 0 and horiz > 0) break :blk '+'; // corner, T, or cross
            if (horiz > 0) {
                // Horizontal line — use '=' for double weight
                if (dw.left == .double or dw.right == .double) break :blk '=';
                break :blk '-';
            }
            break :blk '|'; // vertical line
        },
    };
}

/// Check if a character has any double-weight arm (pure double or mixed light↔double).
/// NOTE: only detects double-line characters. For other border weights (single,
/// heavy, dashed), a broader predicate will be introduced with the scanline
/// renderer. Renamed from `isSubgraphBorderChar` for clarity.
pub fn isDoubleBorderChar(ch: u21) bool {
    const dw = decomposeChar(ch);
    return dw.left == .double or dw.right == .double or dw.up == .double or dw.down == .double;
}

/// Decompose a box-drawing character into per-direction arm weights.
/// Returns `.none` for all arms if the character is not a recognized box-drawing char.
pub fn decomposeChar(ch: u21) DirWeights {
    return switch (ch) {
        // ── Light ──
        CP_V_LINE, CP_V_LINE_DASH => .{ .up = .light, .down = .light },
        CP_H_LINE, CP_H_LINE_DASH => .{ .left = .light, .right = .light },
        CP_CORNER_DR => .{ .up = .light, .right = .light }, // └
        CP_CORNER_DL => .{ .up = .light, .left = .light }, // ┘
        CP_CORNER_UR => .{ .down = .light, .right = .light }, // ┌
        CP_CORNER_UL => .{ .down = .light, .left = .light }, // ┐
        CP_T_DOWN => .{ .left = .light, .right = .light, .down = .light }, // ┬
        CP_T_UP => .{ .left = .light, .right = .light, .up = .light }, // ┴
        CP_T_RIGHT => .{ .up = .light, .down = .light, .right = .light }, // ├
        CP_T_LEFT => .{ .up = .light, .down = .light, .left = .light }, // ┤
        CP_CROSS => .{ .up = .light, .down = .light, .left = .light, .right = .light }, // ┼

        // Arrows treated as vertical/horizontal light connectors
        CP_ARROW_DOWN, CP_ARROW_UP, CP_ARROW_DOWN_DASH, CP_ARROW_UP_DASH => .{ .up = .light, .down = .light },
        CP_ARROW_RIGHT, CP_ARROW_LEFT, CP_ARROW_RIGHT_DASH, CP_ARROW_LEFT_DASH => .{ .left = .light, .right = .light },

        // ── Heavy ──
        CP_HV_V_LINE => .{ .up = .heavy, .down = .heavy },
        CP_HV_H_LINE => .{ .left = .heavy, .right = .heavy },
        CP_HV_CORNER_DR => .{ .up = .heavy, .right = .heavy },
        CP_HV_CORNER_DL => .{ .up = .heavy, .left = .heavy },
        CP_HV_CORNER_UR => .{ .down = .heavy, .right = .heavy },
        CP_HV_CORNER_UL => .{ .down = .heavy, .left = .heavy },
        CP_HV_T_DOWN => .{ .left = .heavy, .right = .heavy, .down = .heavy },
        CP_HV_T_UP => .{ .left = .heavy, .right = .heavy, .up = .heavy },
        CP_HV_T_RIGHT => .{ .up = .heavy, .down = .heavy, .right = .heavy },
        CP_HV_T_LEFT => .{ .up = .heavy, .down = .heavy, .left = .heavy },
        CP_HV_CROSS => .{ .up = .heavy, .down = .heavy, .left = .heavy, .right = .heavy },

        // ── Mixed light↔heavy corners ──
        CP_MX_LH_CORNER_DR => .{ .up = .light, .right = .heavy },
        CP_MX_HL_CORNER_DR => .{ .up = .heavy, .right = .light },
        CP_MX_LH_CORNER_DL => .{ .up = .light, .left = .heavy },
        CP_MX_HL_CORNER_DL => .{ .up = .heavy, .left = .light },
        CP_MX_LH_CORNER_UR => .{ .down = .light, .right = .heavy },
        CP_MX_HL_CORNER_UR => .{ .down = .heavy, .right = .light },
        CP_MX_LH_CORNER_UL => .{ .down = .light, .left = .heavy },
        CP_MX_HL_CORNER_UL => .{ .down = .heavy, .left = .light },

        // ── Mixed light↔heavy T-junctions: T_DOWN (┬ variants) ──
        CP_MX_T_DOWN_HH_L => .{ .left = .heavy, .right = .heavy, .down = .light },
        CP_MX_T_DOWN_LL_H => .{ .left = .light, .right = .light, .down = .heavy },
        CP_MX_T_DOWN_HL_L => .{ .left = .heavy, .right = .light, .down = .light },
        CP_MX_T_DOWN_LH_L => .{ .left = .light, .right = .heavy, .down = .light },
        CP_MX_T_DOWN_HL_H => .{ .left = .heavy, .right = .light, .down = .heavy },
        CP_MX_T_DOWN_LH_H => .{ .left = .light, .right = .heavy, .down = .heavy },

        // ── T_UP (┴ variants) ──
        CP_MX_T_UP_HH_L => .{ .left = .heavy, .right = .heavy, .up = .light },
        CP_MX_T_UP_LL_H => .{ .left = .light, .right = .light, .up = .heavy },
        CP_MX_T_UP_HL_L => .{ .left = .heavy, .right = .light, .up = .light },
        CP_MX_T_UP_LH_L => .{ .left = .light, .right = .heavy, .up = .light },
        CP_MX_T_UP_HL_H => .{ .left = .heavy, .right = .light, .up = .heavy },
        CP_MX_T_UP_LH_H => .{ .left = .light, .right = .heavy, .up = .heavy },

        // ── T_RIGHT (├ variants) ──
        CP_MX_T_RIGHT_LL_H => .{ .up = .light, .down = .light, .right = .heavy },
        CP_MX_T_RIGHT_HH_L => .{ .up = .heavy, .down = .heavy, .right = .light },
        CP_MX_T_RIGHT_LH_L => .{ .up = .light, .down = .heavy, .right = .light },
        CP_MX_T_RIGHT_HL_L => .{ .up = .heavy, .down = .light, .right = .light },
        CP_MX_T_RIGHT_LH_H => .{ .up = .light, .down = .heavy, .right = .heavy },
        CP_MX_T_RIGHT_HL_H => .{ .up = .heavy, .down = .light, .right = .heavy },

        // ── T_LEFT (┤ variants) ──
        CP_MX_T_LEFT_LL_H => .{ .up = .light, .down = .light, .left = .heavy },
        CP_MX_T_LEFT_HH_L => .{ .up = .heavy, .down = .heavy, .left = .light },
        CP_MX_T_LEFT_LH_L => .{ .up = .light, .down = .heavy, .left = .light },
        CP_MX_T_LEFT_HL_L => .{ .up = .heavy, .down = .light, .left = .light },
        CP_MX_T_LEFT_LH_H => .{ .up = .light, .down = .heavy, .left = .heavy },
        CP_MX_T_LEFT_HL_H => .{ .up = .heavy, .down = .light, .left = .heavy },

        // ── Mixed light↔heavy crossings ──
        CP_MX_CROSS_HH_LL => .{ .up = .heavy, .down = .heavy, .left = .light, .right = .light },
        CP_MX_CROSS_LL_HH => .{ .up = .light, .down = .light, .left = .heavy, .right = .heavy },
        CP_MX_CROSS_HL_LL => .{ .up = .heavy, .down = .light, .left = .light, .right = .light },
        CP_MX_CROSS_LH_LL => .{ .up = .light, .down = .heavy, .left = .light, .right = .light },
        CP_MX_CROSS_LL_HL => .{ .up = .light, .down = .light, .left = .heavy, .right = .light },
        CP_MX_CROSS_LL_LH => .{ .up = .light, .down = .light, .left = .light, .right = .heavy },
        CP_MX_CROSS_HL_HH => .{ .up = .heavy, .down = .light, .left = .heavy, .right = .heavy },
        CP_MX_CROSS_LH_HH => .{ .up = .light, .down = .heavy, .left = .heavy, .right = .heavy },
        CP_MX_CROSS_HH_HL => .{ .up = .heavy, .down = .heavy, .left = .heavy, .right = .light },
        CP_MX_CROSS_HH_LH => .{ .up = .heavy, .down = .heavy, .left = .light, .right = .heavy },
        CP_MX_CROSS_HL_HL => .{ .up = .heavy, .down = .light, .left = .heavy, .right = .light },
        CP_MX_CROSS_HL_LH => .{ .up = .heavy, .down = .light, .left = .light, .right = .heavy },
        CP_MX_CROSS_LH_HL => .{ .up = .light, .down = .heavy, .left = .heavy, .right = .light },
        CP_MX_CROSS_LH_LH => .{ .up = .light, .down = .heavy, .left = .light, .right = .heavy },

        // ── Double ──
        CP_DB_V_LINE => .{ .up = .double, .down = .double },
        CP_DB_H_LINE => .{ .left = .double, .right = .double },
        CP_DB_CORNER_DR => .{ .up = .double, .right = .double },
        CP_DB_CORNER_DL => .{ .up = .double, .left = .double },
        CP_DB_CORNER_UR => .{ .down = .double, .right = .double },
        CP_DB_CORNER_UL => .{ .down = .double, .left = .double },
        CP_DB_T_DOWN => .{ .left = .double, .right = .double, .down = .double },
        CP_DB_T_UP => .{ .left = .double, .right = .double, .up = .double },
        CP_DB_T_RIGHT => .{ .up = .double, .down = .double, .right = .double },
        CP_DB_T_LEFT => .{ .up = .double, .down = .double, .left = .double },
        CP_DB_CROSS => .{ .up = .double, .down = .double, .left = .double, .right = .double },

        // ── Mixed light↔double corners ──
        CP_MD_CORNER_DR_LD => .{ .up = .light, .right = .double },
        CP_MD_CORNER_DR_DL => .{ .up = .double, .right = .light },
        CP_MD_CORNER_DL_LD => .{ .up = .light, .left = .double },
        CP_MD_CORNER_DL_DL => .{ .up = .double, .left = .light },
        CP_MD_CORNER_UR_LD => .{ .down = .light, .right = .double },
        CP_MD_CORNER_UR_DL => .{ .down = .double, .right = .light },
        CP_MD_CORNER_UL_LD => .{ .down = .light, .left = .double },
        CP_MD_CORNER_UL_DL => .{ .down = .double, .left = .light },

        // ── Mixed light↔double T-junctions and crossings ──
        CP_MD_T_DOWN_DD_L => .{ .left = .double, .right = .double, .down = .light },
        CP_MD_T_DOWN_LL_D => .{ .left = .light, .right = .light, .down = .double },
        CP_MD_T_RIGHT_DV => .{ .up = .double, .down = .double, .right = .light },
        CP_MD_T_LEFT_DV => .{ .up = .double, .down = .double, .left = .light },
        CP_MD_T_UP_DH => .{ .left = .double, .right = .double, .up = .light },
        CP_MD_CROSS_DH => .{ .up = .light, .down = .light, .left = .double, .right = .double },
        CP_MD_CROSS_DV => .{ .up = .double, .down = .double, .left = .light, .right = .light },

        else => .{}, // not a box-drawing char — all arms none
    };
}

/// Look up the box-drawing character for a given set of per-direction weights.
/// Uses effective weights (dashed → light) for character selection.
/// Falls back to heavier-wins when no mixed Unicode character exists.
pub fn lookupChar(dw: DirWeights) u21 {
    const u = dw.up.effective();
    const d = dw.down.effective();
    const l = dw.left.effective();
    const r = dw.right.effective();

    // Count active arms
    const has_u = u != .none;
    const has_d = d != .none;
    const has_l = l != .none;
    const has_r = r != .none;
    const count = @as(u8, @intFromBool(has_u)) + @as(u8, @intFromBool(has_d)) +
        @as(u8, @intFromBool(has_l)) + @as(u8, @intFromBool(has_r));

    if (count == 0) return ' ';

    // ── 1 arm (straight segment or fallback) ──
    if (count == 1) {
        if (has_u or has_d) return switch (ArmWeight.merge(u, d).effective()) {
            .heavy => CP_HV_V_LINE,
            .double => CP_DB_V_LINE,
            else => CP_V_LINE,
        };
        return switch (ArmWeight.merge(l, r).effective()) {
            .heavy => CP_HV_H_LINE,
            .double => CP_DB_H_LINE,
            else => CP_H_LINE,
        };
    }

    // ── 2 arms (straight line or corner) ──
    if (count == 2) {
        // Straight vertical
        if (has_u and has_d) {
            if (u == .double or d == .double) return CP_DB_V_LINE;
            if (u == .heavy and d == .heavy) return CP_HV_V_LINE;
            // mixed heavy↔light: heavier wins for straight lines
            if (u == .heavy or d == .heavy) return CP_HV_V_LINE;
            return CP_V_LINE;
        }
        // Straight horizontal
        if (has_l and has_r) {
            if (l == .double or r == .double) return CP_DB_H_LINE;
            if (l == .heavy and r == .heavy) return CP_HV_H_LINE;
            if (l == .heavy or r == .heavy) return CP_HV_H_LINE;
            return CP_H_LINE;
        }
        // Corners
        return lookupCorner(u, d, l, r);
    }

    // ── 3 arms (T-junction) ──
    if (count == 3) {
        return lookupTJunction(u, d, l, r);
    }

    // ── 4 arms (crossing) ──
    return lookupCrossing(u, d, l, r);
}

fn lookupCorner(u: ArmWeight, d: ArmWeight, l: ArmWeight, r: ArmWeight) u21 {
    // └ up + right
    if (u != .none and r != .none) {
        if (u == .double and r == .double) return CP_DB_CORNER_DR;
        if (u == .double) return CP_MD_CORNER_DR_DL; // double up + light right
        if (r == .double) return CP_MD_CORNER_DR_LD; // light up + double right
        if (u == .heavy and r == .heavy) return CP_HV_CORNER_DR;
        if (u == .heavy) return CP_MX_HL_CORNER_DR; // heavy up + light right
        if (r == .heavy) return CP_MX_LH_CORNER_DR; // light up + heavy right
        return CP_CORNER_DR;
    }
    // ┘ up + left
    if (u != .none and l != .none) {
        if (u == .double and l == .double) return CP_DB_CORNER_DL;
        if (u == .double) return CP_MD_CORNER_DL_DL;
        if (l == .double) return CP_MD_CORNER_DL_LD;
        if (u == .heavy and l == .heavy) return CP_HV_CORNER_DL;
        if (u == .heavy) return CP_MX_HL_CORNER_DL;
        if (l == .heavy) return CP_MX_LH_CORNER_DL;
        return CP_CORNER_DL;
    }
    // ┌ down + right
    if (d != .none and r != .none) {
        if (d == .double and r == .double) return CP_DB_CORNER_UR;
        if (d == .double) return CP_MD_CORNER_UR_DL;
        if (r == .double) return CP_MD_CORNER_UR_LD;
        if (d == .heavy and r == .heavy) return CP_HV_CORNER_UR;
        if (d == .heavy) return CP_MX_HL_CORNER_UR;
        if (r == .heavy) return CP_MX_LH_CORNER_UR;
        return CP_CORNER_UR;
    }
    // ┐ down + left
    if (d != .none and l != .none) {
        if (d == .double and l == .double) return CP_DB_CORNER_UL;
        if (d == .double) return CP_MD_CORNER_UL_DL;
        if (l == .double) return CP_MD_CORNER_UL_LD;
        if (d == .heavy and l == .heavy) return CP_HV_CORNER_UL;
        if (d == .heavy) return CP_MX_HL_CORNER_UL;
        if (l == .heavy) return CP_MX_LH_CORNER_UL;
        return CP_CORNER_UL;
    }
    return ' ';
}

fn lookupTJunction(u: ArmWeight, d: ArmWeight, l: ArmWeight, r: ArmWeight) u21 {
    // ┬ variant: left + right + down (no up)
    if (u == .none) {
        // All double
        if (d == .double and l == .double and r == .double) return CP_DB_T_DOWN;
        // All heavy
        if (d == .heavy and l == .heavy and r == .heavy) return CP_HV_T_DOWN;
        // All light
        if (d == .light and l == .light and r == .light) return CP_T_DOWN;
        // Mixed light↔double: limited Unicode coverage
        if (l == .double and r == .double) return CP_MD_T_DOWN_DD_L; // ╤ (double horiz + light down)
        if (d == .double and l == .light and r == .light) return CP_MD_T_DOWN_LL_D; // ╥ (light horiz + double down)
        if (l == .double or r == .double) return CP_MD_T_DOWN_DH; // ╤ (best approx for one double horiz)
        // Mixed light↔heavy: full coverage
        if (l == .heavy and r == .heavy) return CP_MX_T_DOWN_HH_L;
        if (d == .heavy and l == .light and r == .light) return CP_MX_T_DOWN_LL_H;
        if (l == .heavy and r == .light) return if (d == .heavy) CP_MX_T_DOWN_HL_H else CP_MX_T_DOWN_HL_L;
        if (l == .light and r == .heavy) return if (d == .heavy) CP_MX_T_DOWN_LH_H else CP_MX_T_DOWN_LH_L;
        // heavy↔double: double wins
        return CP_T_DOWN;
    }
    // ┴ variant: left + right + up (no down)
    if (d == .none) {
        if (u == .double and l == .double and r == .double) return CP_DB_T_UP;
        if (u == .heavy and l == .heavy and r == .heavy) return CP_HV_T_UP;
        if (u == .light and l == .light and r == .light) return CP_T_UP;
        if (l == .double or r == .double) return CP_MD_T_UP_DH;
        if (l == .heavy and r == .heavy) return CP_MX_T_UP_HH_L;
        if (u == .heavy and l == .light and r == .light) return CP_MX_T_UP_LL_H;
        if (l == .heavy and r == .light) return if (u == .heavy) CP_MX_T_UP_HL_H else CP_MX_T_UP_HL_L;
        if (l == .light and r == .heavy) return if (u == .heavy) CP_MX_T_UP_LH_H else CP_MX_T_UP_LH_L;
        return CP_T_UP;
    }
    // ├ variant: up + down + right (no left)
    if (l == .none) {
        if (u == .double and d == .double and r == .double) return CP_DB_T_RIGHT;
        if (u == .heavy and d == .heavy and r == .heavy) return CP_HV_T_RIGHT;
        if (u == .light and d == .light and r == .light) return CP_T_RIGHT;
        if (u == .double and d == .double) return CP_MD_T_RIGHT_DV;
        if (u == .double or d == .double) return CP_MD_T_RIGHT_DV; // best approx
        if (u == .heavy and d == .heavy) return CP_MX_T_RIGHT_HH_L;
        if (r == .heavy and u == .light and d == .light) return CP_MX_T_RIGHT_LL_H;
        if (u == .light and d == .heavy) return if (r == .heavy) CP_MX_T_RIGHT_LH_H else CP_MX_T_RIGHT_LH_L;
        if (u == .heavy and d == .light) return if (r == .heavy) CP_MX_T_RIGHT_HL_H else CP_MX_T_RIGHT_HL_L;
        return CP_T_RIGHT;
    }
    // ┤ variant: up + down + left (no right)
    if (r == .none) {
        if (u == .double and d == .double and l == .double) return CP_DB_T_LEFT;
        if (u == .heavy and d == .heavy and l == .heavy) return CP_HV_T_LEFT;
        if (u == .light and d == .light and l == .light) return CP_T_LEFT;
        if (u == .double and d == .double) return CP_MD_T_LEFT_DV;
        if (u == .double or d == .double) return CP_MD_T_LEFT_DV;
        if (u == .heavy and d == .heavy) return CP_MX_T_LEFT_HH_L;
        if (l == .heavy and u == .light and d == .light) return CP_MX_T_LEFT_LL_H;
        if (u == .light and d == .heavy) return if (l == .heavy) CP_MX_T_LEFT_LH_H else CP_MX_T_LEFT_LH_L;
        if (u == .heavy and d == .light) return if (l == .heavy) CP_MX_T_LEFT_HL_H else CP_MX_T_LEFT_HL_L;
        return CP_T_LEFT;
    }
    return CP_T_DOWN; // shouldn't reach here
}

fn lookupCrossing(u: ArmWeight, d: ArmWeight, l: ArmWeight, r: ArmWeight) u21 {
    // All same weight
    if (u == d and d == l and l == r) {
        return switch (u) {
            .heavy => CP_HV_CROSS,
            .double => CP_DB_CROSS,
            else => CP_CROSS,
        };
    }

    // Mixed light↔double
    if (u == .double or d == .double or l == .double or r == .double) {
        const vert_dbl = (u == .double and d == .double);
        const horiz_dbl = (l == .double and r == .double);
        if (vert_dbl and horiz_dbl) return CP_DB_CROSS;
        if (horiz_dbl) return CP_MD_CROSS_DH; // light vert + double horiz
        if (vert_dbl) return CP_MD_CROSS_DV; // double vert + light horiz
        // Only one arm double: best approximation
        if (l == .double or r == .double) return CP_MD_CROSS_DH;
        return CP_MD_CROSS_DV;
    }

    // Mixed light↔heavy: full Unicode coverage
    const vert_heavy = (u == .heavy and d == .heavy);
    const horiz_heavy = (l == .heavy and r == .heavy);

    if (vert_heavy and horiz_heavy) return CP_HV_CROSS;
    if (vert_heavy) {
        if (l == .heavy) return CP_MX_CROSS_HH_HL;
        if (r == .heavy) return CP_MX_CROSS_HH_LH;
        return CP_MX_CROSS_HH_LL;
    }
    if (horiz_heavy) {
        if (u == .heavy) return CP_MX_CROSS_HL_HH;
        if (d == .heavy) return CP_MX_CROSS_LH_HH;
        return CP_MX_CROSS_LL_HH;
    }

    // Individual heavy arms
    if (u == .heavy and d == .light and l == .heavy and r == .light) return CP_MX_CROSS_HL_HL;
    if (u == .heavy and d == .light and l == .light and r == .heavy) return CP_MX_CROSS_HL_LH;
    if (u == .light and d == .heavy and l == .heavy and r == .light) return CP_MX_CROSS_LH_HL;
    if (u == .light and d == .heavy and l == .light and r == .heavy) return CP_MX_CROSS_LH_LH;
    if (u == .heavy and d == .light) return CP_MX_CROSS_HL_LL;
    if (u == .light and d == .heavy) return CP_MX_CROSS_LH_LL;
    if (l == .heavy and r == .light) return CP_MX_CROSS_LL_HL;
    if (l == .light and r == .heavy) return CP_MX_CROSS_LL_LH;

    return CP_CROSS;
}

/// Merge a new edge direction (with weight) into an existing cell character.
/// This is the weight-aware replacement for the old boolean-only mergeJunction.
///
/// The new edge's arms are specified via `new_dirs`. The existing cell is decomposed
/// into its arm weights, merged with the new directions, and the resulting character
/// is looked up.
///
/// Backward compatibility: the old `mergeJunction(current, from_above, to_below,
/// to_right, to_left)` signature is preserved below as a wrapper that assumes
/// `.light` weight.
pub fn mergeJunctionWeighted(current: u21, new_dirs: DirWeights, crossing_style: @import("config.zig").CrossingStyle) u21 {
    if (isMarkerChar(current)) return current;

    const existing = decomposeChar(current);
    const merged = existing.mergeWith(new_dirs);
    const ch = lookupChar(merged);

    if (crossing_style != .flat) {
        const eu = merged.up.effective();
        const ed = merged.down.effective();
        const el = merged.left.effective();
        const er = merged.right.effective();
        if (eu != .none and ed != .none and el != .none and er != .none) {
            return switch (crossing_style) {
                .arc => 0x2312, // ⌒
                .gap => ' ',
                .flat => unreachable,
            };
        }
    }

    return ch;
}

/// Legacy mergeJunction — assumes light weight for all new arms.
/// Handles mixed single/double crossings when edges cross subgraph borders.
pub fn mergeJunction(current: u21, from_above: bool, to_below: bool, to_right: bool, to_left: bool) u21 {
    return mergeJunctionWeighted(current, .{
        .up = if (from_above) .light else .none,
        .down = if (to_below) .light else .none,
        .right = if (to_right) .light else .none,
        .left = if (to_left) .light else .none,
    }, .flat);
}

/// Legacy mergeWithDoubleLine — kept for backward compatibility.
/// Internally uses the weight-aware system.
pub fn mergeWithDoubleLine(current: u21, from_above: bool, to_below: bool, to_right: bool, to_left: bool) u21 {
    return mergeJunction(current, from_above, to_below, to_right, to_left);
}

// ── Marker character lookup ─────────────────────────────────────────────────

const MarkerShape = @import("config.zig").MarkerShape;

/// Cardinal direction for marker/arrow placement.
pub const Direction = enum { down, up, right, left };

/// Check if a character is any marker/arrow output (from any MarkerShape).
/// Used by dummy node cleanup to recognize and replace marker chars with lines.
pub fn isMarkerChar(ch: u21) bool {
    return switch (ch) {
        // .arrow (thin)
        '↓',
        '↑',
        '→',
        '←',
        // .arrow dashed (legacy)
        '⇣',
        '⇡',
        '⇢',
        '⇠',
        // .filled_arrow
        '▼',
        '▲',
        '▶',
        '◀',
        // .open_arrow
        '▽',
        '△',
        '▷',
        '◁',
        // .diamond / .open_diamond / .circle / .open_circle
        '◆',
        '◇',
        '●',
        '○',
        => true,
        else => false,
    };
}

/// Map a `MarkerShape` + direction to a terminal codepoint.
/// Returns `null` for `.none` (no marker to paint).
pub fn markerChar(shape: MarkerShape, dir: Direction, weight: ArmWeight) ?u21 {
    return switch (shape) {
        .none => null,
        .arrow => switch (weight) {
            .heavy => switch (dir) {
                .down => '▼',
                .up => '▲',
                .right => '▶',
                .left => '◀',
            },
            .double => switch (dir) {
                .down => '⇓',
                .up => '⇑',
                .right => '⇒',
                .left => '⇐',
            },
            .dashed => switch (dir) {
                .down => '⇣',
                .up => '⇡',
                .right => '⇢',
                .left => '⇠',
            },
            else => switch (dir) {
                .down => '↓',
                .up => '↑',
                .right => '→',
                .left => '←',
            },
        },
        .filled_arrow => switch (dir) {
            .down => '▼',
            .up => '▲',
            .right => '▶',
            .left => '◀',
        },
        .open_arrow => switch (dir) {
            .down => '▽',
            .up => '△',
            .right => '▷',
            .left => '◁',
        },
        .diamond => '◆',
        .open_diamond => '◇',
        .circle => '●',
        .open_circle => '○',
    };
}
