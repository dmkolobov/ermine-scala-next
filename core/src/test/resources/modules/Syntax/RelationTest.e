module Syntax.RelationTest where

import List
import Relation
import Field
import Syntax.Relation
import Relation.Op as Op

field x: Int
field xl: Long
field xb: Byte
field xs: Short
field xd: Double
field y: Int
field s: String
field ss: String
field z: Int

rel1 = relation [{x = 1, s = "eee"}]

-- simple op works
add1 = [| y = x + 1 |] rel1

-- that all numeric binary ops exist
othertyps : [x, s, xl, xb, xs, xd]
othertyps = [| xl = 1L + 1L - 1L * 1L / 1L // 1L,
               xb = 1B + 1B - 1B * 1B / 1B // 1B,
               xs = 1S + 1S - 1S * 1S / 1S // 1S,
               xd = 1.0 + 1.0 - 1.0 * 1.0 / 1.0 // 1.0 |] rel1

-- that renaming works
ren, ren2 : [x, y, s]
ren = [| y <- x, x <- y, y = x + 3 |] rel1
ren2 = [| y <- x, x = y + 3 |] rel1

-- that Op replacement descends through Apps
doubleS : [x, s, ss]
doubleS = [| ss = s ++_Op s |] rel1

-- that filters apply and rewrite
filt : [y, s]
filt = [| x < (x + 1),
          y <- x,
          y > (y - 1) && y == 42 || y < 33 |] rel1

-- that inferred numeric type percolates
transOp : [x, y, s]
transOp = [| y = x + (x + 0) |] rel1

testMain = True
