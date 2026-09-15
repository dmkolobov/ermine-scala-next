module JsonSmoke where

import Json
import List
import Function

field x : Int
field name : String

data Colour = Red | Green | Blue
data Shape = Circle Double | Rect Double Double | Dot
data Ser = Ser String (List Double)
data Cfg = Cfg String Ser
data Holder = Holder (Int -> Int)

-- compact text of any value's encoding
j : a -> String
j v = render (toJson v)

cfg : Cfg
cfg = Cfg "S" (Ser "q" [1.0])

-- a Json value encodes as itself; parse reads text back
viaJson : Json
viaJson = toJson [1, 2]

parsed : Maybe Json
parsed = parse "{\"a\":[1,2.5,null],\"b\":\"s\"}"

rows = [{ x = 1, name = "a" }, { x = 2, name = "b" }]

holder : List Holder
holder = [Holder id]
