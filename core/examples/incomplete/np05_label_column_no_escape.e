module Incomplete.Np05 where

{- NO BEST TYPE (5/5) -- the case where the polymorphic escape is priced out.

   np01 to np04 all end the same way: the set of concrete typings has several
   maximal elements, and Ermine sidesteps Wand by keeping a constrained type
   that covers all of them.  Written out by hand, that constrained type checks
   in milliseconds and works at every call site.  In those four files the
   theorem is absorbed and annotation really is optional.

   This file is the one where it is not.

   SCENARIO.  The `displayName` column that every report in core/examples/ai
   builds: direct orders show the product name, partner orders show the product
   name and the channel.  One `if` inside one `combine`:

       combine (if (isDirect == "yes") productName
                   (productName ++ " via " ++ channelName)) displayName

   Two of that expression's maximal typings, both realistic, both accepted in
   this file:

       labelFresh : [orderId, productName, channelName, isDirect]
                 -> [orderId, productName, channelName, isDirect, displayName]

       labelAgain : [orderId, productName, channelName, isDirect, displayName]
                 -> [orderId, productName, channelName, isDirect, displayName]

   -- label a fresh extract, versus relabel a stored table after the channel
   list was re-cut.  Incomparable, exactly as in np01.  A third report over a
   different fact table gives a third, and so on.

   WHAT A COMPETENT USER EXPECTS.  To do what np01 to np04 permit: factor the
   expression into one helper, give the helper the constrained signature that
   covers every table, stop repeating the conditional.

   WHAT ACTUALLY HAPPENS.  The helper exists and it is priced out.  `if`
   contributes `RUnion3 v r s t` -- four partitions over three row variables --
   on top of `combine`'s `RUnion2`, and the row solver's cost on that
   combination is not in the same universe as the rest of this corpus.
   MEASURED 2026-09-01, `ERMINE_JAVA_OPTS=-Dermine.useInterface=false timeout N
   bin/ermine <file> </dev/null`, times as reported by the compiler's own
   "Importing module" line:

     form                                             time to check
     -----------------------------------------------  ------------------------
     labelRow c y n f r = combine (if c y n) f r       280.65 s
       -- no signature, definition alone
       [np05a_inferring_the_helper.slow]

     the same helper with the full constrained          0.17 s
       signature, definition alone
       [np05b_helper_signature_only.e]

     that helper plus ONE call site                    526.99 s
       [np05c_helper_at_a_call_site.slow]

     the two concrete typings in THIS file,              1.18 s
       conditional written out at each site

   Nothing here diverges -- earlier runs of this corpus reported both slow files
   as non-terminating, but they were 300s timeouts, and with a longer budget
   both finish.  The honest number is the ratio: writing the general type and
   using it once costs about 450x what writing the two concrete ones costs, and
   every additional call site pays again.  core/examples/ai/Common.e records the
   same shape as "does not finish"; on this machine it finishes, in nine
   minutes, which for a report module edited all day is the same thing.

   So the escape hatch of np01 to np04 is, here, unaffordable.  What real code
   does instead is what this file does and what Common.e's rule prescribes --
   "KEEP THE CONDITIONAL AT THE CALL SITE and let the helper take a ready-made
   Op" -- which means writing a concrete header, which means choosing one of the
   incomparable maximal typings, which means every report that needed a
   different one is rejected exactly as in np01b, np02b, np03b and np04b.

   WHICH INCOMPLETENESS.  Non-principality, made load-bearing by cost.  The
   first half is Wand and no implementation could do better; the second half is
   this solver, and it is why the first half bites here and not in np04.  Read
   as a style guide, Common.e's rule is a performance workaround.  Read as a
   statement about types, it says: for this expression, annotation is not an
   optimisation, and annotating is choosing.

   NOTE ON THE TWO `.slow` FILES.  They are named `.slow` rather than `.e` so
   that a sweep over `core/examples/**/*.e` does not appear to hang on them.  To
   reproduce, copy one to a `.e` file and run it with a generous timeout.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false: this file loads
   clean, "Importing module 'Incomplete.Np05' (0.98-1.18 seconds over several runs)".
-}

import Prelude
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation

field orderId : Int
field productName, channelName, isDirect, displayName : String

-- This morning's extract from the order system.
sales : [orderId, productName, channelName, isDirect]
sales = relation [
  { orderId = 5001, productName = "Desk Lamp",    channelName = "Direct", isDirect = "yes" },
  { orderId = 5002, productName = "Office Chair", channelName = "Acme",   isDirect = "no"  }
]

-- Last night's stored table, whose labels are wrong since the channel list was
-- re-cut this morning.
storedSales : [orderId, productName, channelName, isDirect, displayName]
storedSales = relation [
  { orderId = 5001, productName = "Desk Lamp", channelName = "Direct", isDirect = "yes"
  , displayName = "Desk Lamp via Direct" }
]

-- ------------------------------------------------------------------ the query
-- One expression.  Two maximal typings.  Both accepted -- and, per the header,
-- there is no helper that holds both, so the repetition below is forced.

labelFresh : [orderId, productName, channelName, isDirect]
          -> [orderId, productName, channelName, isDirect, displayName]
labelFresh rel =
  combine_Op (if_Op (col_Op isDirect ==_Pred prim_Op "yes")
                    (col_Op productName)
                    (col_Op productName ++_Op prim_Op " via " ++_Op col_Op channelName))
             displayName rel

labelAgain : [orderId, productName, channelName, isDirect, displayName]
          -> [orderId, productName, channelName, isDirect, displayName]
labelAgain rel =
  combine_Op (if_Op (col_Op isDirect ==_Pred prim_Op "yes")
                    (col_Op productName)
                    (col_Op productName ++_Op prim_Op " via " ++_Op col_Op channelName))
             displayName rel

thisMorning = labelFresh sales
relabelled  = labelAgain storedSales
