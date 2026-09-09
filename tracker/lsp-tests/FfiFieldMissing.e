module FfiFieldMissing where

-- LSP-FFI kind (6): no such static field on java.lang.Integer.
foreign
  value "java.lang.Integer" "NO_SUCH_FIELD" x : Int
