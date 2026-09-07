module Algebra.Shouldfail.Alg05 where

{- SHOULD FAIL -- `Relation.join1` on two relations that share TWO columns.

   `join1`'s doc comment says it "requires a witness that the intersection is
   nonempty, to guard against accidental cartesian joins". Its constraints say
   more:

       join1 : (ra <- (k, r1), rb <- (k, r2), r <- (k, r1, r2))
            => Field k a -> rel ra -> rel rb -> rel r

   `r <- (k, r1, r2)` is a PARTITION, so `r1` and `r2` -- everything the two
   operands hold apart from `k` -- must be disjoint. A second shared column is
   in both, and the partition has no solution. `join1 f` therefore means "`f`
   is the WHOLE key", exactly like `joinBy {f}`, and the weaker claim the
   documentation describes has to be written `joinBy' {f}`.

   Here `readings` and `calibrations` share `sensorId` and `readingDate`;
   `Algebra/KeyDiscipline.e` spelling 4 documents the same measurement and uses
   `joinBy'` instead.

   Expected diagnostic: at `alg05_join1_two_shared_columns.e:70:7`, field
   `Algebra.Shouldfail.Alg05.readingDate`, one of the three `rowSound` blame
   clauses below.

   THE FIELD AND THE POSITION ARE STABLE; THE CLAUSE IS NOT. `-Dermine.rowSound`
   has three blame clauses and which one you get depends on what else is in the
   session. Measured on this tree, 2026-09-07, at the adopted defaults:

     command line                                   alg05                 alg06
     bin/ermine Helpers.e <the one module>          whole/no-part         whole/no-part
     bin/ermine Helpers.e shouldfail/*.e            TWO-PARTS             part/not-whole
     bin/ermine Helpers.e <11 reports> shouldfail/*.e  whole/no-part      part/not-whole

   where the three sentences are

     whole/no-part   ... the whole contains it but no part does
     part/not-whole  ... a part contains it but the whole does not
     TWO-PARTS       ... two parts of one partition both contain it

   THE TWO MODULES FLIP AT DIFFERENT POINTS -- alg05 on the shouldfail-only
   line, alg06 on the per-file line -- so neither is a special case of the
   other. And the matrix itself moves: adding ONE unrelated definition
   (`unionRows`) to `Algebra/Helpers.e` changed alg06's whole-group clause from
   whole/no-part to part/not-whole, at the same field and the same position.
   A regression test must pin the FIELD and the POSITION and must not pin the
   sentence. This is `tracker/tools/corpus-run.sh`'s header note ("seven modules
   print a DIFFERENT CLAUSE of the same refutation") reproduced on modules
   written this week.

   The content either way: `r <- (k, r1, r2)` has `readingDate` in `r1` (from
   `readings`) and in `r2` (from `calibrations`), and a partition's parts are
   disjoint by definition.
-}

import Prelude
import Syntax.Relation
import Algebra.Helpers

field sensorId : Int
field readingDate : String
field rawCount, baseGain : Double

readings : [sensorId, readingDate, rawCount]
readings = relation [{ sensorId = 1, readingDate = "2026-01-20", rawCount = 10.0 }]

calibrations : [sensorId, readingDate, baseGain]
calibrations = relation [{ sensorId = 1, readingDate = "2026-01-20", baseGain = 99.5 }]

bad = joinOn1 sensorId readings calibrations
