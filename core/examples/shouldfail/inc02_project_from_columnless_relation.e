module ShouldFail.Inc02 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS.

   Expected message:
     Incompatible instantiations of 'N'
   (N is a raw TypeVar id and is NOT stable across runs. Match on the prefix.)

   Raised by: Constraints.scala:933, the `case _` of `makeEmpty`'s `aux`.

   Shape: the same contradiction reached without `except`. `blank` is annotated
   with the empty row, so its row variable is made empty directly; `project`
   then requires it to have `amount`. This is the minimal form of the error:
   one empty-row annotation plus one `Has` constraint.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field amount : Double

blank : Relation (| |)
blank = relation [{}]

bad = project {amount} blank
