module Relation.UnifyFields where

import Relation
import Relation.Row

unify1 : forall (r:row) (r2:row) . (r2 <- (f1,f2,p), r <- (f2,p,u))
      => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
unify1 f1 f2 r r2 = join (rename f1 f2 (except {f2} r2)) r
