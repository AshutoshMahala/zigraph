/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: 'zgraph',

  extras: $ => [/\s/],

  rules: {
    source_file: $ => repeat($._statement),

    _statement: $ => choice(
      $.comment,
    ),

    comment: _ => token(seq('#', /.*/)),
  },
});
