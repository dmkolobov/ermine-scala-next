module Lang.Shouldfail.Lang05 where

{- NEGATIVE: `traverseRel` whose per-row function drops a column the result is annotated
   to have.

   `Helpers.traverseRel : Ap f -> ({..r} -> f {..s}) -> List {..r} -> f (Relation (|..s|))`
   has TWO rows, and the output row is whatever the function returns. Here the function
   returns a two-field record and the annotation asks for three.

   EXPECTED:

     error: failed to unify type (|orderQty, orderRef, orderTeam|) with type
     (|orderQty, orderRef|)
-}

import Prelude
import List as L
import Lang.Helpers

field orderRef  : String
field orderQty  : Int
field orderTeam : String

orderRows : List {orderRef, orderQty, orderTeam}
orderRows = [ {orderRef = "O-1", orderQty = 5, orderTeam = "Optics"} ]_L

badTraverse : Maybe (Relation (|orderRef, orderQty, orderTeam|))
badTraverse = traverseRel maybeAp (t -> Just {orderRef = t ! orderRef,
                                              orderQty = t ! orderQty}) orderRows
