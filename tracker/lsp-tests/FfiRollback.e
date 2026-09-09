module FfiRollback where

-- LSP-FFI review finding P-4: a tolerant load that records a foreign
-- warning and THEN dies for an unrelated reason must still show the
-- warning.  The REPL rolls the session back on a Death, and the rollback
-- restores a `copy`, which carries no notes.
foreign
  function "com.clarifi.reporting.writers.NoSuchWriter" "render" render : String -> String

bad : Int
bad = "not an int"
