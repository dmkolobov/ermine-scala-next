module FfiMemberMissing where

-- LSP-FFI kind (3): the class is here, the method is not.
foreign
  function "java.lang.String" "noSuchMethodAtAll" f : String -> String
