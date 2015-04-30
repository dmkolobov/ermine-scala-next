module Bugs.VariableCapture where


{-  For some reason, the type checker tries to unify both x's together, even though they're in separate let clauses.
  To replicate, load in repl.  Should receive "error: failed to unify type String with type Int"
-}

foo =
  let x = 1
  in "foo"

bar =
  let x = "Not an Int"
  in "bar"
