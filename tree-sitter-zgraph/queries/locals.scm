; Blocks create scopes
(block) @local.scope

; Variable definitions in vars blocks
(var_decl (identifier) @local.definition)

; Variable references in string interpolation
(string_interpolation (identifier) @local.reference)
