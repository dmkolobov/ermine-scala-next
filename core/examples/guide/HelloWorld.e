module HelloWorld where

-- comment syntax
import Prelude hiding sum
import Int
-- eventually:
-- import CapitalIQ using somePATable_tbl
-- import PortfolioAnalytics using { anotherTableName_tbl ; andAnother_tbl }

-- blah
msg = "Hello world!"
x = 2

-- the factorial function
factorial 0 = 1
factorial n = n * factorial (n - 1)

-- pattern matching, syntax for local definitions
sum xs =
  let go []     acc = acc
      go (h::t) acc = go t (h + acc)
  in go xs 0

-- all values have a type, including functions
-- functions can be passed as values to other functions
sum2 : List Int -> Int
sum2 xs = foldl (+) 0 xs

-- talking about relational data from Ermine
field Name : String
field ID : Int
field FavoriteColor : String

-- a literal dataset, though this could also be loaded from a database table
-- see `PASchema.e`
employees = relation [
  { Name = "Alice", ID = 1, FavoriteColor = "Blue" },
  { Name = "Bob",   ID = 2, FavoriteColor = "Red" },
  -- order of fields does not matter!
  { ID = 3, Name = "Carol", FavoriteColor = "Red" }
]

-- assembling data into a report
t1 = tabular defaultLegend employees

-- some very simple data manipulation
t2 = tabular defaultLegend (employees |> {
  FavoriteColor ID => FavoriteColor == "Blue", ID == 1 })
  -- employees |> {FavoriteColor == "Blue", ID == 1} FavoriteColor ID => FavoriteColor == "Blue", ID == 1 })

-- very simple report layout
tables = vflow [t1, t2]
