module Time.Shouldfail.Bucket01 where

{- SHOULD FAIL -- a calendar that SHARES A COLUMN with the facts it buckets.

   `Time.Helpers.bucketBy` assigns each fact to the calendar range containing
   its date, by crossing the two relations and filtering:

       bucketBy : (exists cv fv. cal <- (s, e, cv), facts <- (d, fv)
                  , out <- (s, e, cv, d, fv), RelationalComb rel)
                => Field s Date -> Field e Date -> Field d Date
                -> rel cal -> rel facts -> rel out

   `out <- (s, e, cv, d, fv)` is a DISJOINT union, so the calendar and the facts
   must have no column in common. That is not a whim: `join` in Ermine is a
   NATURAL join, so a shared column silently turns the intended cross-product
   into an equi-join on it, and the report would then contain only the facts
   whose region happened to match the calendar row's -- a wrong answer rather
   than an error. The signature turns it into an error.

   Here both `salesCal` and `bookings` carry `region`.

   THE FIX is to project the shared column away from the calendar
   (`salesCal -# {region}`) if the cross product is what was wanted, or to say
   what was really meant -- a per-region calendar -- and use
   `Time.Helpers.nearestBy` / `fillForward`, which take the shared key
   explicitly. `Time.ReadingHistory` does exactly that for two network calendars.

   EXPECTED DIAGNOSTIC (verbatim):

     core/examples/Time/shouldfail/bucket01_calendar_overlaps_facts.e:77:7: Row partitions are unsatisfiable at field 'Time.Shouldfail.Bucket01.region': a part contains it but the whole does not

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

   For this module specifically: a per-file run of the group as first written
   gave "the whole contains it but no part does" twice out of two; a per-file run
   after three helpers were added to `Time/Helpers.e` gives "a part contains it
   but the whole does not"; and the two whole-group traces give one clause each,
   differing only in the order of the ten other modules on the command line. The
   VERDICT, the field and the position are the same in all four.
-}

import Prelude
import Layout
import Relation.Op as Op
import Syntax.Relation
import Time.Helpers

field bookingId : Int
field region, periodName : String
field bookDate, periodStart, periodEnd : Date
field netRevenue : Double

salesCal : [ periodStart, periodEnd, periodName, region ]
salesCal = relation [ { periodStart = @2011/1/1, periodEnd = @2011/3/31,
                        periodName = "Q1", region = "EMEA" } ]

bookings : [ bookingId, bookDate, region, netRevenue ]
bookings = relation [ { bookingId = 1, bookDate = @2011/2/14,
                        region = "EMEA", netRevenue = 42000.0 } ]

bad = bucketBy periodStart periodEnd bookDate salesCal bookings
