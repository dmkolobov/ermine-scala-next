module Heads where

import List
import Primitive

-- E14 (LSP interstage item 6.2c): a CONSTRAINED local head.  `*` is
-- `PrimitiveNum n => n -> n -> n`, so the scheme the checker publishes for
-- `go` carries a constraint the pre-generalisation rho cannot show.
conHead xs =
  let go []     acc = acc
      go (h::t) acc = go t (h * acc)
  in go xs 1

-- the control: a local head mentioning a variable the body fixes LATER
pairHead y =
  let gl x = (x, y)
  in (gl 1, y + 1)

-- the control: a local whose type is settled outright
laterHead y =
  let zl = y
  in (zl, y + 1)

-- Decision (a): a SIGNED local head shows its declaration
sigHead x =
  let sg : Int -> Int
      sg n = n + 1
  in sg x
