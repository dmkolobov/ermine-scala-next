module Incomplete.Gu01 where

{- INFERENCE GIVES UP WHERE CHECKING SUCCEEDS -- 1 of 4: the knee.

   THE SCENARIO.  A sales warehouse has one fact table of order lines and a
   dimension table per lookup.  The reporting module offers the denormalised
   view every downstream report starts from: one row per order line with every
   dimension attribute attached.  It is written as a FUNCTION over the tables
   rather than over inline literals, because the same star join has to run
   against the live warehouse, against last quarter's snapshot, and against the
   fixtures in the test module.  That is the ordinary reason to name it:

     wideOrderLines orderLine productDim regionDim ... =
       orderLine ** productDim ** regionDim ** ...

   `**` is `join` (Syntax/Relation.e:53), `infixl 5`, so the chain is
   left-nested exactly as a SQL star join would be.  core/examples/ai/
   SalesByRegion.e is the same query written against literals.

   WHAT A COMPETENT USER EXPECTS.  Join is the cheapest thing a relational
   language does.  Six of them in a row should cost about six times one of them.

   WHAT ACTUALLY HAPPENS.  Cost as dimensions are added, one JVM per file, read
   off the loader's own "Importing module" timer:

     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine <file.e> </dev/null

       dimensions joined   2      3      4      5      6        7
       inference           0.03s  0.05s  0.14s  0.85s  11.21s   329.58s
       step ratio                 1.7x   2.8x   6.1x   13.2x    29.4x

   The step ratio is itself growing, so this is worse than exponential.  The
   rows at 2..5 dimensions were measured on this same definition with the
   trailing dimensions dropped; the three top rungs are shipped as Gu01 (here,
   6 dimensions, 11.21s), Gu02 (7 dimensions, 329.58s) and Gu03 (8 dimensions,
   killed).  THIS FILE IS THE KNEE.

   THE INCOMPLETENESS.  Inference, not checking.  Every constraint here is
   discharged -- the module loads, the definition is well typed, and the
   residual it settles on is LINEAR in the number of joins (`join` contributes
   three partition constraints per call, Relation.e:259).  The solver spends 11
   seconds to arrive at an answer of 18 constraints.  Gu04 is the same
   definition with those constraints written down, at eight dimensions, in
   1.97s.
-}

import Prelude
import Relation
import Syntax.Relation

-- One row per order line, with every dimension attribute attached.
wideOrderLines orderLine productDim regionDim channelDim calendarDim customerDim currencyDim =
  orderLine ** productDim ** regionDim ** channelDim ** calendarDim
            ** customerDim ** currencyDim
