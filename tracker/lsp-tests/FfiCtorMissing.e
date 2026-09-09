module FfiCtorMissing where

-- LSP-FFI kind (7): String has no (String, String) constructor.  A
-- `foreign constructor` names no class and no member, so the warning
-- lands on the declared name.
foreign
  constructor mk : String -> String -> String
