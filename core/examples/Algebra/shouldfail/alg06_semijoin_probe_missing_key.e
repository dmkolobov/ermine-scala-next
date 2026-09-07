module Algebra.Shouldfail.Alg06 where

{- SHOULD FAIL -- a semi-join whose PROBE relation does not carry the key.

       semiJoin : (RelationalComb rel, r <- (k, o), p <- (k, q))
               => Row k -> rel p -> rel r -> rel r
       semiJoin ks probe r = join r (project ks probe)

   Both operands must contain the key row: `r <- (k, o)` for the relation being
   filtered and `p <- (k, q)` for the probe. Dropping the second constraint
   would not make this work at run time either -- `project` would have nothing
   to project -- but with it, the mistake is caught where it is made rather
   than where the empty result is noticed.

   This is the anti-join / semi-join counterpart of `alg02`: `difference`
   demands equal headers, `semiJoin` demands a common key, and between them
   they cover the two ways a set operation goes wrong.

   Expected diagnostic: at `alg06_semijoin_probe_missing_key.e:66:7`, field
   `Algebra.Shouldfail.Alg06.customerId`, one of the three `rowSound` blame
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

   The content: the PART (`k`, given as the literal `{customerId}`) has the
   field and the whole (`names`'s header) does not.
-}

import Prelude
import Syntax.Relation
import Algebra.Helpers

field customerId, orderId : Int
field customerName, orderStatus : String

orders : [orderId, customerId, orderStatus]
orders = relation [{ orderId = 1, customerId = 4001, orderStatus = "shipped" }]

-- no `customerId` here: only the display name
names : [customerName]
names = relation [{ customerName = "Aurora Retail" }]

bad = semiJoin {customerId} names orders
