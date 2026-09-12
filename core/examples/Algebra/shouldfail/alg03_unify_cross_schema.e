module Algebra.Shouldfail.Alg03 where

{- SHOULD FAIL -- `Relation.UnifyFields.unify1` used for the one thing its name
   suggests: reconciling two schemas that key the same entity under different
   column names.

       unify1 : (r2 <- (f1,f2,p), r <- (f2,p,u))          -- since stage S3b
             => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
       unify1 f1 f2 r r2 = join (rename f1 f2 (except {f2} r2)) r

   The second operand must carry BOTH the column being renamed (`f1`) and the
   one it is renamed to (`f2`), and the first must carry `f2` and the shared
   part `p`. A CRM source keyed on `crmAccountId` and a canonical relation keyed
   on `customerId` do not have that shape -- `crm` has no `customerId` for `f2`
   to be -- so the partition set has no solution. (Before stage S3b the
   constraints were `r <- (h, f, t)` and `r2 <- (h, f2, t)`, which shared `h`
   AND `t` and said nothing about `f1` at all; this module was rejected then too,
   at the same position and with the same message, for the neighbouring reason
   that `h`, `f2` and `t` had already been forced into `crm`'s header.)

   This module is the negative control for the finding recorded in
   `Algebra/Customer360.e` and in `Helpers.e`'s closing note: the stdlib's only
   "unify fields" function cannot unify fields, and the reports use plain
   `rename` (`alias`) instead.

   Expected diagnostic (measured 2026-09-06, defaults):
     core/examples/Algebra/shouldfail/alg03_unify_cross_schema.e:49:7: Row partitions are unsatisfiable at field 'Algebra.Shouldfail.Alg03.customerId': the whole contains it but no part does

   The `-Dermine.rowSound` blame message (adopted default since fe024a7, and
   unchanged by the S3b correction -- re-measured 2026-09-11): the whole is
   `canonical`'s header, which has `customerId`, and its parts are `f2`, `p` and
   `u`, of which `f2` and `p` have already been forced into `crm`'s header,
   where `customerId` does not appear.
-}

import Prelude
import Relation.UnifyFields as UF
import Syntax.Relation

field customerId, crmAccountId : Int
field accountName, region : String

canonical : [customerId, region]
canonical = relation [{ customerId = 1, region = "west" }]

crm : [crmAccountId, accountName]
crm = relation [{ crmAccountId = 1, accountName = "Aurora" }]

bad = unify1_UF crmAccountId customerId canonical crm
