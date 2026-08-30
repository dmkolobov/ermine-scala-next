module Relations where

-- comment syntax
import Prelude hiding sum
import Int

-- blah
msg = "Hello world!"
x = 2

-- the factorial function
factorial 0 = 1
factorial n = n * factorial (n - 1)

-- pattern matching, syntax for local definitions
sum xs =
  let go []     acc = acc
      go (hd::tl) acc = go tl (hd + acc)
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
employees = relation [
  { Name = "Alice", ID = 1, FavoriteColor = "Blue" },
  { Name = "Bob",   ID = 2, FavoriteColor = "Red" },
  -- order of fields does not matter!
  { ID = 3, Name = "Carol", FavoriteColor = "Red" }
]
