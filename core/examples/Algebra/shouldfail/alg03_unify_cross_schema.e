module Algebra.Shouldfail.Alg03 where

{- SHOULD FAIL -- `Relation.UnifyFields.unify1` used for the one thing its name
   suggests: reconciling two schemas that key the same entity under different
   column names.

       unify1 : (r <- (h,f,t), r2 <- (h,f2,t))
             => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
       unify1 f1 f2 r r2 = join (rename f1 f2 (except {f2} r2)) r

   Both constraints share `h` AND `t`, so the two operands must agree on every
   column except one each; and `f1`, the column being renamed, is mentioned in
   no constraint at all. A CRM source keyed on `crmAccountId` and a canonical
   relation keyed on `customerId` do not have that shape, so the partition set
   has no solution.

   This module is the negative control for the finding recorded in
   `Algebra/Customer360.e` and in `Helpers.e`'s closing note: the stdlib's only
   "unify fields" function cannot unify fields, and the reports use plain
   `rename` (`alias`) instead.

   Expected diagnostic (measured 2026-09-06, defaults):
     core/examples/Algebra/shouldfail/alg03_unify_cross_schema.e:44:7: Row partitions are unsatisfiable at field 'Algebra.Shouldfail.Alg03.customerId': the whole contains it but no part does

   The `-Dermine.rowSound` blame message (adopted default since fe024a7): the
   whole is `canonical`'s header, which has `customerId`, and the parts are
   `h`, `f`, `t` -- all of which `r2 <- (h, f2, t)` has already forced into
   `crm`'s header, where `customerId` does not appear.
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
