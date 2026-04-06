["vars" "headers" "row"] @keyword
(style_rule "style" @keyword)

(block (identifier) @function)
(block (string) @function)

(annotation (identifier) @type)

(directive "@" @attribute)
(directive_name) @attribute

(style_rule "@" @attribute)
(style_selector (identifier) @type)
(style_selector (class_ref) @type)

(edge_operator) @operator

(string) @string
(string_interpolation "${" @punctuation.special)
(string_interpolation "}" @punctuation.special)
(string_interpolation (identifier) @variable)

(number) @number

(comment) @comment

(property_key (identifier) @property)
(property_value (identifier) @string.special)
(property_value (number) @number)

(var_decl (identifier) @variable.parameter)

(table_cell) @string

(card_field (identifier) @property)

(class_ref) @type

(edge_chain (identifier) @variable)

(node_decl (identifier) @variable)

["{" "}"] @punctuation.bracket
["[" "]"] @punctuation.bracket
["," ":" "="] @punctuation.delimiter
