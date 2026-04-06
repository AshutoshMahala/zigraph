/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: 'zgraph',

  extras: $ => [/\s/, $.comment, /;/],

  word: $ => $._word,

  conflicts: $ => [],

  rules: {
    source_file: $ => repeat($._statement),

    _statement: $ => choice(
      $.block,
      $.edge_chain,
      $.node_decl,
      $.directive,
      $.style_rule,
      $.vars_block,
      $.card_field,
      $.table_headers,
      $.table_row_decl,
    ),

    // ── Blocks ──────────────────────────────────────────────
    // A block can be: { ... } or [layout] { ... } or name { ... } or name [layout] { ... }
    // Named blocks: the name (identifier/string) is followed by
    // optional annotation and then block_body.
    block: $ => prec.right(choice(
      seq($.block_body),
      seq($.annotation, $.block_body),
      seq(
        choice($.identifier, $.string),
        optional($.annotation),
        $.block_body,
      ),
    )),

    block_body: $ => seq('{', repeat($._statement), '}'),

    // ── Edge chains ─────────────────────────────────────────
    edge_chain: $ => prec.left(1, seq(
      $._node_with_attrs,
      repeat1(seq($.edge_operator, $._node_with_attrs)),
    )),

    edge_operator: _ => choice(
      '<->',
      '->',
      '<-',
      '--',
      '==>',
      '=>',
      '-.->',
      '-..->',
      '-..-',
    ),

    // ── Node with attributes (shared between edge_chain start and node_decl)
    _node_with_attrs: $ => prec.right(seq(
      choice($.identifier, $.string),
      optional($.annotation),
      repeat($.class_ref),
    )),

    // ── Node declarations (standalone with properties/classes)
    node_decl: $ => prec(-1, seq(
      choice($.identifier, $.string),
      choice(
        seq($.annotation, repeat($.class_ref)),
        repeat1($.class_ref),
      ),
    )),

    // ── Annotation: [ident] or [key=val, ...] ───────────────
    annotation: $ => seq(
      '[',
      choice(
        seq($.property, repeat(seq(',', $.property))),
        $.identifier,
      ),
      ']',
    ),

    // ── Property (used inside annotation and style_rule) ────
    property: $ => seq(
      $.property_key,
      '=',
      $.property_value,
    ),

    property_key: $ => $.identifier,

    property_value: $ => choice($.identifier, $.string, $.number),

    // ── Directives ──────────────────────────────────────────
    directive: $ => prec.right(seq(
      '@',
      $.directive_name,
      optional($._directive_value),
    )),

    directive_name: $ => $._word,

    _directive_value: $ => choice(
      $.string,
      $._directive_value_list,
    ),

    _directive_value_list: $ => seq(
      $._directive_value_item,
      repeat(seq(',', $._directive_value_item)),
    ),

    _directive_value_item: $ => $.identifier,

    // ── Style rules ─────────────────────────────────────────
    style_rule: $ => seq(
      '@',
      'style',
      $.style_selector,
      '{',
      repeat($.property),
      '}',
    ),

    style_selector: $ => choice(
      $.identifier,
      $.class_ref,
    ),

    // ── Class references ────────────────────────────────────
    class_ref: $ => seq('.', $._word),

    // ── Vars block ──────────────────────────────────────────
    vars_block: $ => seq(
      'vars',
      '{',
      repeat($.var_decl),
      '}',
    ),

    var_decl: $ => seq(
      $.identifier,
      ':',
      choice($.identifier, $.string, $.number),
    ),

    // ── Tables ──────────────────────────────────────────────
    table_headers: $ => seq(
      'headers',
      ':',
      $._table_value,
      repeat(seq(',', $._table_value)),
    ),

    table_row_decl: $ => seq(
      'row',
      ':',
      $._table_value,
      repeat(seq(',', $._table_value)),
    ),

    _table_value: $ => choice($.identifier, $.string, $.number, $.table_cell),

    table_cell: _ => /[a-zA-Z0-9_][a-zA-Z0-9_-]*/,

    // ── Card fields ─────────────────────────────────────────
    card_field: $ => seq(
      $.identifier,
      ':',
      choice($.identifier, $.string, $.number),
    ),

    // ── Identifiers ─────────────────────────────────────────
    identifier: _ => /[a-zA-Z_][a-zA-Z0-9_-]*(\.[a-zA-Z_][a-zA-Z0-9_-]*)*/,

    _word: _ => /[a-zA-Z_][a-zA-Z0-9_-]*/,

    // ── Strings ─────────────────────────────────────────────
    string: $ => seq(
      '"',
      repeat(choice(
        $.string_content,
        $.string_interpolation,
      )),
      '"',
    ),

    string_content: _ => prec(-1, /[^"$\\]+|\\.|(\$[^{])/),

    string_interpolation: $ => seq(
      '${',
      $.identifier,
      '}',
    ),

    // ── Numbers ─────────────────────────────────────────────
    number: _ => /\d+(\.\d+)?/,

    // ── Comments ────────────────────────────────────────────
    comment: _ => token(seq('#', /.*/)),
  },
});
