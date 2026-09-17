module Guide where

import Json
import List
import Function
import Date
import GUID
import Nullable
import Prim
import Relation

field x : Int
field name : String

data Colour = Red | Green | Blue
data Shape = Circle Double | Rect Double Double | Dot
data Pt = Pt { px : Int, py : Int }
data Fig = Disc { rad : Double, tip : Maybe Int } | Nought
data Holder = Holder (Int -> Int)

-- compact text of any value's encoding
j : a -> String
j v = render (toJson v)

ts : Timestamp
ts = timestampFromLong 1767625445123L

gid : GUID
gid = stringGuid "3f2504e0-4f89-11d3-9a0c-0305e82c3301"

nulls : List (Nullable Int)
nulls = [Some 3, Null Int]

rows = [{ x = 1, name = "a" }, { x = 2, name = "b" }]

pt : Pt
pt = Pt 3 4

holder : List Holder
holder = [Holder id]

points : [x, name]
points = relation [{ x = 1, name = "a" }, { x = 2, name = "b" }]

inlinePoints : Inline (|x, name|)
inlinePoints = Inline points

deferredPoints : Deferred (|x, name|)
deferredPoints = Deferred points

data Boxed = Boxed { bx : Int, extra : Spread Json }

boxed : Boxed
boxed = Boxed 1 (Spread (obj [("hue", str "red"), ("size", int 3L)]))

data Clash = Clash { cx : Int, cExtra : Spread Json }

clash : Clash
clash = Clash 1 (Spread (obj [("cx", int 9L)]))

repeated : Boxed
repeated = Boxed 1 (Spread (obj [("hue", str "a"), ("hue", str "b")]))

notAnObject : Boxed
notAnObject = Boxed 1 (Spread (str "nope"))

data TwoSpreads = TwoSpreads { tx : Int, s1 : Spread Json, s2 : Spread Json }

twoSpreads : TwoSpreads
twoSpreads = TwoSpreads 1 (Spread (obj [])) (Spread (obj []))

data PosSpread = PosSpread Int (Spread Json)

posSpread : PosSpread
posSpread = PosSpread 1 (Spread (obj [("a", int 1L)]))
