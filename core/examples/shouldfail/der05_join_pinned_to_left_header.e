module Shouldfail.Der05 where

{- SHOULD FAIL -- error class 3, INCOMPATIBLE INSTANTIATIONS (subsumption),
   reached only through a DERIVED constraint.

   `selfJoin` is a join whose RESULT header is pinned to the left operand's:

       join     : (p <- (d, e), q <- (e, f), c <- (d, e, f)) => [..p] -> [..q] -> [..c]
       selfJoin : (p <- (d, e), q <- (e, f), p <- (d, e, f)) => [..p] -> [..q] -> [..p]

   That is a legitimate, satisfiable signature: it just says the right operand
   contributes no new columns.  (Control:
   core/examples/shouldfail-controls/control06_self_join.e.)

   Applying it to headers (|a, b|) and (|b, c|) is not satisfiable, but the
   input constraint set does not say so.  The solver has to:
     1. cancel `p <- (d, e)` against `p <- (d, e, f)` -- Constraints.scala:1017
        -- to learn `f <- ` (the right operand adds nothing);
     2. propagate that emptiness into `q <- (e, f)`, leaving `q <- e`, which
        unifies `e` with `q = (|b, c|)`;
     3. substitute `e := (|b, c|)` into `p <- (d, e)` and discover that
        p = (|a, b|) cannot contain the column `c`.

   Expected message (verbatim, default -Dermine.genRules=all) -- this one spans
   several lines; the first is:
     Row types failed to unify: 
   followed by the two-row report
     R1 =
       Shouldfail.Der05.{ b, c }
     R2 =
       Shouldfail.Der05.{ a, b }
   and two location lines, `R1 inferred from` and `R2`.

   Raised by: Constraints.scala:303, `ensureSuperset`
     "Row types failed to unify: " :/: ...
   reached from `makeConcrete` at Constraints.scala:976.

   Rule modes: rejected under all / cut / nongen alike.
-}

import Prelude

field a, b, c : Int

ab : [a, b]
ab = relation [{ a = 1, b = 2 }]

bc : [b, c]
bc = relation [{ b = 2, c = 3 }]

selfJoin : forall p q d e f. (p <- (d, e), q <- (e, f), p <- (d, e, f))
        => [..p] -> [..q] -> [..p]
selfJoin r s = join r s

bad = selfJoin ab bc
