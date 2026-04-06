; Keywords
["vars" "headers" "row"] @keyword
(style_rule "style" @keyword)

; Block names (first identifier child of block)
(block (identifier) @function)
(block (string) @function)

; Layout annotation (standalone identifier inside annotation, not a property)
(annotation (identifier) @type)

; Directives
(directive "@" @attribute)
(directive_name) @attribute

; Style rules
(style_rule "@" @attribute)
(style_selector (identifier) @type)
(style_selector (class_ref) @type)

; Edge operators
(edge_operator) @operator

; Strings
(string "\"" @string)
(string_content) @string
(string_interpolation "${" @punctuation.special)
(string_interpolation "}" @punctuation.special)
(string_interpolation (identifier) @variable)

; Numbers
(number) @number

; Comments
(comment) @comment

; Properties
(property_key (identifier) @property)
(property_value (identifier) @string.special)
(property_value (number) @number)

; Variables
(var_decl (identifier) @variable.parameter)

; Tables
(table_cell) @string

; Card fields
(card_field (identifier) @property)

; Class references
(class_ref) @type

; Identifiers in edge chains
(edge_chain (identifier) @variable)

; Node declarations
(node_decl (identifier) @variable)

; Punctuation
["{" "}"] @punctuation.bracket
["[" "]"] @punctuation.bracket
["," ":" "="] @punctuation.delimiter
