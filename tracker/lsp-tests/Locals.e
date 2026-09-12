module Locals where

import Bool

data Shape = Circle Bool | Square Bool

type Boxed a = (a, Bool)

letLocal : Bool -> Bool
letLocal x =
  let flag = x && True
  in flag

whereLocal b = keep
  where keep = b || False

sigLocal b = strict b
  where strict : Bool -> Bool
        strict c = c && True

polyLocal b = idy b
  where idy u = u

argLocal p q = p && q

caseLocal s = case s of
  Circle r -> r
  Square r -> r

lastLocal = (let tail1 = True in tail1)

shapeOf : Bool -> Shape
shapeOf b = Circle b

konst k j = k

sigLetLocal : Bool -> Bool
sigLetLocal x =
  let slet : Bool -> Bool
      slet y = y && True
  in slet x

lamLocal = (m -> m && True)

conLocal s = case s of
  Circle inner -> inner
  Square other -> other

tupLocal bx = case bx of
  (tfst, tsnd) -> tfst && tsnd

asLocal t = case t of
  whole@(Circle wrapped) -> wrapped
  Square other2 -> other2
