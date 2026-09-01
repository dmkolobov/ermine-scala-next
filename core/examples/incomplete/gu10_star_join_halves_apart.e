module Incomplete.Gu10 where

{- INFERENCE GIVES UP WHERE CHECKING SUCCEEDS -- the control for Gu09.

   THE SCENARIO.  Gu09's two definitions, unchanged, with one edit: the second
   takes the core view as an ARGUMENT instead of calling the first.  The user
   writes `wideOrderLines (coreOrderLines a b c d e) f g h i` at the report
   site.  Same two functions, same data, same result.

   WHAT A COMPETENT USER EXPECTS.  No difference from Gu09 -- moving an
   application from inside a definition to outside it is not a change of
   meaning.

   WHAT ACTUALLY HAPPENS.  It compiles, fast.  See the family notes for the
   number.

   THE INCOMPLETENESS.  Gu09 and Gu10 are the same program, and one of them
   compiles.  Which of the two you wrote is the whole difference, and there is
   nothing in the language, the documentation or the diagnostics that would let
   a user predict that.  (The escape is not free either: the composition still
   has to happen somewhere, and the caller pays Gu09's cost unless it supplies
   fully concrete tables.)
-}

import Prelude
import Relation
import Syntax.Relation

coreOrderLines orderLine productDim regionDim channelDim calendarDim =
  orderLine ** productDim ** regionDim ** channelDim ** calendarDim

wideOrderLines core customerDim currencyDim taxDim promoDim =
  core ** customerDim ** currencyDim ** taxDim ** promoDim
