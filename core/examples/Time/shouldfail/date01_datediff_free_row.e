module Time.Shouldfail.Date01 where

{- SHOULD FAIL -- a date difference over a relation carrying NEITHER date.

   Until stage F3 this module LOADED. `Relation.Op.dateDiff`'s wrapper had no
   signature at all (`Relation/Op.e:150`, the line that would have given it one
   was commented out), so it inherited the result row of the primitive

       dateDiff# : PrimitiveTemporal d => TimeUnit -> Op r d -> Op r1 d -> Op r2 Int

   in which `r2` is FREE -- unconstrained by either operand. A `combine` of a
   date difference therefore type-checked over any relation whatsoever, and the
   mistake surfaced only when the value was forced, at header computation:

     <relation with Failure(NonEmpty[Operation refers to nonexistent column
       (startDate) in header., Operation refers to nonexistent column (endDate)
       in header.])>

   -- a run-time failure for a mistake every other `Op` combinator catches
   statically. `dateAdd'` one line above never had the hole; its wrapper ties the
   result row to the operands' with `RUnion2`, and `dateDiff` carries the same
   constraint now.

   EXPECTED DIAGNOSTIC (the field named is whichever date the solver reaches
   first, and the clause is the propagation reason, which ticket B6 records as
   varying with load order; the POSITION -- line 55, the `bad` binding -- and the
   verdict are what this module pins):

     core/examples/Time/shouldfail/date01_datediff_free_row.e:55:7: Row partitions are
     unsatisfiable at field 'Time.Shouldfail.Date01.startDate': the whole contains it
     but no part does

   Both halves of the caveat have been seen: with `Time/Helpers.e` ahead of it the
   field is `startDate` and the clause is "the whole contains it but no part does";
   in a whole-corpus batch it has also printed `endDate` and "a part contains it but
   the whole does not". Line 55, column 7, and REJECTED, are the invariants.

   The positive control is `Time.Signatures.yearFrac365Simple` and every use of
   `Time.Helpers.dayCount` in this directory: the same expression over a relation
   that DOES carry both dates still checks.
-}

import Prelude
import Relation.Op as Op
import Syntax.Relation

field startDate, endDate : Date
field gap : Int
field name : String

people : [ name ]
people = relation [ { name = "Ada" } ]

-- `people` has no `startDate` and no `endDate`.
bad = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap people
