module FfiMemberUnloadable where

-- LSP-FFI review finding P-1.  `probejar.PresentMember` LOADS.  `ok` is
-- a perfectly ordinary static method -- but `getMethod` resolves the
-- signature classes of every public method while it searches, and the
-- sibling `bad` returns the absent `probejar.Missing`, so the lookup
-- throws NoClassDefFoundError.  That is an Error: it used to escape
-- TolerantCheck.guard AND Diagnostics.run and blank the whole file.
foreign
  function "probejar.PresentMember" "ok" ok : String -> String
