module Time.Shouldfail.AsOf01 where

{- SHOULD FAIL -- an as-of lookup whose KEY ROW is not a subset of the fact row.

   `Time.Helpers.nearestBy` is the per-key as-of. Its signature says the sparse
   relation carries the key, its date column and its own values:

       nearestBy : (exists sv fv. sparse <- (k, sd, sv), fine <- (k, fd, fv)
                   , out <- (k, sd, sv, fd, fv), Primitive a)
                => Row k -> Field sd a -> Relation sparse
                -> Field fd a -> Relation fine -> Relation out

   Here the key row is `{station, network}` but `readings` has no `network`
   column -- the mistake a reader makes on the second day, having seen
   `Time.ReadingHistory` key its lookup by both. So `sparse <- (k, sd, sv)` has
   no solution: `network` is on the right of the partition and nowhere on the left.

   EXPECTED DIAGNOSTIC (verbatim; see the header of E3-EXAMPLES.md for the
   command):

     core/examples/Time/shouldfail/asof01_key_not_in_fact.e:69:7: Row partitions are unsatisfiable at field 'Time.Shouldfail.AsOf01.network': a part contains it but the whole does not

   THE CLAUSE IS NOT STABLE, AND THE POSITION AND FIELD ARE. Measured on this
   module across four runs of the identical bytes -- two per-file (before and
   after three helpers were added to `Time/Helpers.e`) and two whole-group traces
   differing only in the ORDER of the files on the command line -- the message
   ends

     ... : the whole contains it but no part does
     ... : a part contains it but the whole does not

   in different runs, at the same field, the same line and the same column, with
   the same verdict. The clause is chosen by whichever derived constraint the
   solver refutes first, and that depends on the dequeue order, which depends on
   the `Supply`'s id base -- i.e. on how much was loaded before this module.
   `tracker/tools/corpus-run.sh` records the same phenomenon for seven modules of
   the pre-existing corpus. The Lean loop model reproduces WHICHEVER clause the
   compiler produced in the same run, which is the useful part: the instability
   is in the solver's search order, not between the compiler and the model.

   WORTH NOTING SEPARATELY, and a limit of the diagnostic rather than of the
   checker: the message is IDENTICAL in shape to the one `bucket01` in this
   directory produces for the opposite mistake (a field shared between two
   relations that had to be disjoint). By the time the solver refutes, the
   constraint it is looking at is a derived one over the result row, and the name
   it can report is the field, not the argument the user got wrong. The field
   name is the only part of the message that localises the error -- which is why
   every helper in `Time/Helpers.e` names the columns it needs in its
   signature.
-}

import Prelude
import Layout
import Relation.Op as Op
import Syntax.Relation
import Time.Helpers

field station, network, sessionType : String
field readDate, sessionDate : Date
field dailyMean : Double

readings : [ station, readDate, dailyMean ]
readings = relation [ { station = "ESK.UK", readDate = @2011/4/20, dailyMean = 17810.0 } ]

sessions : [ station, network, sessionDate, sessionType ]
sessions = relation [ { station = "ESK.UK", network = "UKMO",
                        sessionDate = @2011/4/26, sessionType = "Regular" } ]

bad = nearestBy {station, network} readDate readings sessionDate sessions
