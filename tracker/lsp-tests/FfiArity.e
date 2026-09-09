module FfiArity where

-- LSP-FFI kind (4): String.valueOf exists at arity 1 and 3, never 2.
foreign
  function "java.lang.String" "valueOf" f : String -> String -> String
