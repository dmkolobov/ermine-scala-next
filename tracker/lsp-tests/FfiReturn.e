module FfiReturn where

-- LSP-FFI kind (5): String.length returns int, not String.
foreign
  method "length" f : String -> String
