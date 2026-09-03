module Repro.CRuleHang where

{- Source-level form of the Lean witness W (tracker/repro/crule/README.md): the eight
   partition constraints of `Rowpartition/ResGuardDiverge.lean`'s gSeed hidden behind
   two folds.  The system has no model, but the per-label check on the INPUT partitions
   cannot see it; the shipped saturation finds it (`RHS.merge`, "Fields appear twice").

       a  <- (p, (|l1|))       b  <- (q, (|l4|))
       w2 <- (a, s2)           w2 <- (q1, q2, s2, (|l2|))      q <- (q1, q2)
       w3 <- (b, s3)           w3 <- (p1, p2, s3, (|l3|))      p <- (p1, p2)

   Shape borrowed from core/examples/shouldfail/der06_shared_two_var_remainder.e. -}

import Prelude
import Relation.Row as Rw

field l1, l2, l3, l4 : Int

wit : forall a b p q p1 p2 q1 q2 w2 s2 w3 s3.
      ( a <- (p, (|l1|)), b <- (q, (|l4|))
      , w2 <- (a, s2), w2 <- (q1, q2, s2, (|l2|)), q <- (q1, q2)
      , w3 <- (b, s3), w3 <- (p1, p2, s3, (|l3|)), p <- (p1, p2) )
   => Row a -> Row b -> Int
wit _ _ = 0

bad = wit

bad2 r s = wit r s
