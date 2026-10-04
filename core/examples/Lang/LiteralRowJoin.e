module Lang.LiteralRowJoin where

{- Joins against a literal row, under honest signatures.

   `join` splits its two operands into a shared key and two remainders:

       join : (r1 <- (k, t1), r2 <- (k, t2), r <- (k, t1, t2)) => ..

   When one operand's row is written out, as in `project {demoKey} rows`, the
   second constraint has a literal column set on its LEFT:

       (|demoKey|) <- (k, t2)

   Until 2026-10 the signature check could not read that shape.  It warned
   "NO VERDICT" and accepted the signature on trust.  Every binding below is
   honest, and now loads without the warning.

   The dishonest counterparts are shouldfail/sig06 .. sig08.
-}

import Prelude

field demoKey : Int
field k1 : Int
field k2 : Int

-- The module that was reported.
keepKey : Has inputRow (|demoKey|) => Relation inputRow -> Relation inputRow
keepKey rows = join (rows) (project {demoKey} rows)

-- The literal row on the other side of the join.
keepKeySwapped : Has inputRow (|demoKey|) => Relation inputRow -> Relation inputRow
keepKeySwapped rows = join (project {demoKey} rows) rows

-- A literal row of two columns.
keepKeys : Has inputRow (|k1, k2|) => Relation inputRow -> Relation inputRow
keepKeys rows = join rows (project {k1, k2} rows)

-- The same join under a signature on a `let` binding.
keepKeyLocal : Has r (|demoKey|) => Relation r -> Relation r
keepKeyLocal rows =
  let inner : Has s (|demoKey|) => Relation s -> Relation s
      inner xs = join xs (project {demoKey} xs)
  in inner rows

-- A join against a constant relation.
onlyKeyOne : Has r (|demoKey|) => Relation r -> Relation r
onlyKeyOne x = join x (relation [{demoKey = 1}])
