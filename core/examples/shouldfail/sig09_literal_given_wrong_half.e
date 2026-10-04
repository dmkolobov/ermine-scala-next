module ShouldFail.Sig09 where

{- SHOULD FAIL -- the signature's context is too weak (error class 6).

   The given says s and t split (|a, b|) between them.  It does not say which
   of them holds a.  The body projects a out of s.

   A caller may pick s = (|b|), t = (|a|).  Until 2026-10 the check dropped
   the given, saw an obligation it could not discharge, and could claim
   nothing: "NO VERDICT", accepted.  At run time:

       bad = needA (relation [{b = 1}])
       :type bad            Relation (|b|)
       bad                  Operation refers to nonexistent column (a) in header.

   The honest version of a literal-left given is shouldfail-controls/control10_literal_row_context.e.
-}

import Prelude

field a : Int
field b : Int

needA : ((|a, b|) <- (s, t)) => Relation s -> Relation s
needA x = join x (project {a} x)
