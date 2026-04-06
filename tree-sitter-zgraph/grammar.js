/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: 'zgraph',

  extras: $ => [/\s/, $.comment, /;/],

  word: $ => $._word,

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

    _node_with_attrs: $ => prec.right(seq(
      choice($.identifier, $.string),
      optional($.annotation),
      repeat($.class_ref),
    )),

    node_decl: $ => prec(-1, seq(
      choice($.identifier, $.string),
      choice(
        seq($.annotation, repeat($.class_ref)),
        repeat1($.class_ref),
      ),
    )),

    annotation: $ => seq(
      '[',
      choice(
        seq($.property, repeat(seq(',', $.property))),
        $.identifier,
      ),
      ']',
    ),

    property: $ => seq(
      $.property_key,
      '=',
      $.property_value,
    ),

    property_key: $ => $.identifier,

    property_value: $ => choice($.identifier, $.string, $.number),

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

    class_ref: $ => seq('.', $._word),

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

    card_field: $ => seq(
      $.identifier,
      ':',
      choice($.identifier, $.string, $.number),
    ),

    identifier: _ => /[a-zA-Z_][a-zA-Z0-9_-]*(\.[a-zA-Z_][a-zA-Z0-9_-]*)*/,

    _word: _ => /[a-zA-Z_][a-zA-Z0-9_-]*/,

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

    number: _ => /\d+(\.\d+)?/,

    comment: _ => token(seq('#', /.*/)),
  },
});
