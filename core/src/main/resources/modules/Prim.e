module Prim where

import Nullable
import Maybe
import Native.Maybe

private foreign
  subtype Prim# : Prim a -> PrimT
  subtype UnsafePrim# : PrimT -> Prim a

prim# : Prim a -> PrimT
prim# = Prim#

unsafePrim# : Primitive a => PrimT -> Prim a
unsafePrim# = UnsafePrim#

primExpr# : Primitive a => a -> PrimExpr#
primExpr# = primExpr##

unsafePrimExprIn# : Primitive a => PrimExpr# -> a
unsafePrimExprIn# = unsafePrimExprIn##

primCata int nullInt string nullString bool nullBool double nullDouble byte nullByte short nullShort long nullLong date nullDate primt =
  let prim x = toMaybe# (toMaybe x)
  in primCata# int (prim nullInt) string (prim nullString) bool (prim nullBool) double (prim nullDouble) byte (prim nullByte) short (prim nullShort) long (prim nullLong) date (prim nullDate) primt 

{-
builtin
primCata : Int -> Maybe# Int -> String -> Maybe# String
      -> Bool -> Maybe# Bool -> Double -> Maybe# Double
      -> Byte -> Maybe# Byte -> Short -> Maybe# Short
      -> Long -> Maybe# Long -> Date -> Maybe# Date
      -> PrimT -> PrimExpr#


to add to builtin?
  cata : Int -> Nullable Int -> String -> Nullable String
      -> Bool -> Nullable Bool -> Double -> Nullable Double
      -> Byte -> Nullable Byte -> Short -> Nullable Short
      -> Long -> Nullable Long -> Date -> Nullable Date
      -> Prim a -> a

cataNonnull : Int -> String -> Bool -> Double
           -> Byte -> Short -> Long -> Date
           -> Prim a -> a
cataNonnull i s b d by sh l da p =
  cata i (Some i) s (Some s) b (Some b) d (Some d)
       by (Some by) sh (Some sh) l (Some l) da (Some da) p
-}
