//! Box-drawing codepoint constants and junction merging logic.
//!
//! Provides the Unicode codepoints used for edges, corners, T-junctions,
//! crossings, subgraph borders, and mixed single/double border crossings.
//! Also contains the `mergeJunction`, `mergeWithDoubleLine`, and
//! `isSubgraphBorderChar` functions that resolve overlapping characters.

const std = @import("std");

// ── Single-line box-drawing characters ──────────────────────────────────────

pub const CP_V_LINE: u21 = '│';
pub const CP_H_LINE: u21 = '─';
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

// ── Double-line box-drawing characters for subgraph borders ─────────────────

pub const CP_SG_UR: u21 = '╔'; // top-left
pub const CP_SG_UL: u21 = '╗'; // top-right
pub const CP_SG_DR: u21 = '╚'; // bottom-left
pub const CP_SG_DL: u21 = '╝'; // bottom-right
pub const CP_SG_H: u21 = '═'; // horizontal
pub const CP_SG_V: u21 = '║'; // vertical

// ── Mixed single/double box-drawing characters ──────────────────────────────

pub const CP_MIX_CROSS_DH: u21 = '╪'; // single vert + double horiz crossing
pub const CP_MIX_CROSS_DV: u21 = '╫'; // double vert + single horiz crossing
pub const CP_MIX_T_DOWN_DH: u21 = '╤'; // single down from double horizontal
pub const CP_MIX_T_UP_DH: u21 = '╧'; // single up from double horizontal
pub const CP_MIX_T_RIGHT_DV: u21 = '╞'; // single right from double vertical
pub const CP_MIX_T_LEFT_DV: u21 = '╡'; // single left from double vertical

// ── Junction resolution ─────────────────────────────────────────────────────

/// Check if a character is a double-line subgraph border or mixed crossing character.
pub fn isSubgraphBorderChar(ch: u21) bool {
    return switch (ch) {
        CP_SG_H,
        CP_SG_V,
        CP_SG_UR,
        CP_SG_UL,
        CP_SG_DR,
        CP_SG_DL,
        CP_MIX_CROSS_DH,
        CP_MIX_CROSS_DV,
        CP_MIX_T_DOWN_DH,
        CP_MIX_T_UP_DH,
        CP_MIX_T_RIGHT_DV,
        CP_MIX_T_LEFT_DV,
        => true,
        else => false,
    };
}

/// Merge a single-line edge direction into a double-line subgraph border character.
/// Produces the appropriate mixed single/double box-drawing character.
pub fn mergeWithDoubleLine(current: u21, from_above: bool, to_below: bool, to_right: bool, to_left: bool) u21 {
    return switch (current) {
        // ═ double horizontal border
        CP_SG_H => {
            if (from_above and to_below) return CP_MIX_CROSS_DH; // ╪
            if (to_below) return CP_MIX_T_DOWN_DH; // ╤
            if (from_above) return CP_MIX_T_UP_DH; // ╧
            return current; // horizontal-only: keep ═
        },
        // ║ double vertical border
        CP_SG_V => {
            if (to_right and to_left) return CP_MIX_CROSS_DV; // ╫
            if (to_right) return CP_MIX_T_RIGHT_DV; // ╞
            if (to_left) return CP_MIX_T_LEFT_DV; // ╡
            return current; // vertical-only: keep ║
        },
        // Mixed T-junctions: upgrade to full crossing if opposite direction added
        CP_MIX_T_DOWN_DH => if (from_above) CP_MIX_CROSS_DH else current,
        CP_MIX_T_UP_DH => if (to_below) CP_MIX_CROSS_DH else current,
        CP_MIX_T_RIGHT_DV => if (to_left) CP_MIX_CROSS_DV else current,
        CP_MIX_T_LEFT_DV => if (to_right) CP_MIX_CROSS_DV else current,
        // Full crossings and corners: preserve as-is
        CP_MIX_CROSS_DH,
        CP_MIX_CROSS_DV,
        CP_SG_UR,
        CP_SG_UL,
        CP_SG_DR,
        CP_SG_DL,
        => current,
        else => current,
    };
}

/// Merge a junction character based on which directions are connected.
/// Returns the appropriate box-drawing character for the intersection.
/// Handles mixed single/double crossings when edges cross subgraph borders.
pub fn mergeJunction(current: u21, from_above: bool, to_below: bool, to_right: bool, to_left: bool) u21 {
    // Handle double-line (subgraph border) characters first.
    if (isSubgraphBorderChar(current)) {
        return mergeWithDoubleLine(current, from_above, to_below, to_right, to_left);
    }

    // Determine what directions the current character connects
    var up = from_above;
    var down = to_below;
    var left = to_left;
    var right = to_right;

    // Check what the existing character already connects
    if (current == CP_V_LINE or current == CP_V_LINE_DASH) {
        up = true;
        down = true;
    } else if (current == CP_ARROW_DOWN) {
        up = true;
        down = true;
    } else if (current == CP_ARROW_DOWN_DASH or current == CP_ARROW_UP_DASH) {
        up = true;
        down = true;
    } else if (current == CP_ARROW_RIGHT_DASH or current == CP_ARROW_LEFT_DASH) {
        left = true;
        right = true;
    } else if (current == CP_H_LINE or current == CP_H_LINE_DASH) {
        left = true;
        right = true;
    } else if (current == CP_CORNER_DR) { // └
        up = true;
        right = true;
    } else if (current == CP_CORNER_DL) { // ┘
        up = true;
        left = true;
    } else if (current == CP_CORNER_UR) { // ┌
        down = true;
        right = true;
    } else if (current == CP_CORNER_UL) { // ┐
        down = true;
        left = true;
    } else if (current == CP_T_DOWN) { // ┬
        left = true;
        right = true;
        down = true;
    } else if (current == CP_T_UP) { // ┴
        left = true;
        right = true;
        up = true;
    } else if (current == CP_T_RIGHT) { // ├
        up = true;
        down = true;
        right = true;
    } else if (current == CP_T_LEFT) { // ┤
        up = true;
        down = true;
        left = true;
    } else if (current == CP_CROSS) { // ┼
        up = true;
        down = true;
        left = true;
        right = true;
    }

    // Select the right character based on connections
    const count = @as(u8, @intFromBool(up)) + @as(u8, @intFromBool(down)) + @as(u8, @intFromBool(left)) + @as(u8, @intFromBool(right));

    if (count == 4) {
        return CP_CROSS; // ┼
    } else if (count == 3) {
        if (!up) return CP_T_DOWN; // ┬
        if (!down) return CP_T_UP; // ┴
        if (!left) return CP_T_RIGHT; // ├
        if (!right) return CP_T_LEFT; // ┤
    } else if (count == 2) {
        if (up and down) return CP_V_LINE;
        if (left and right) return CP_H_LINE;
        if (up and right) return CP_CORNER_DR; // └
        if (up and left) return CP_CORNER_DL; // ┘
        if (down and right) return CP_CORNER_UR; // ┌
        if (down and left) return CP_CORNER_UL; // ┐
    }

    // Fallback
    if (up or down) return CP_V_LINE;
    if (left or right) return CP_H_LINE;
    return current;
}
