module FixTy where

-- A workspace sibling with a TYPE of its own, so Fix.e can import the
-- term `paint` without the type `Colour` its signature would name.
data Colour = Red | Green

paint = Red
