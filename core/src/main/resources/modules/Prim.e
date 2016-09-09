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

{-
builtin
primCata : Int -> Nullable Int -> String -> Nullable String
      -> Bool -> Nullable Bool -> Double -> Nullable Double
      -> Byte -> Nullable Byte -> Short -> Nullable Short
      -> Long -> Nullable Long -> Date -> Nullable Date
      -> GUID => Nullable GUID
      -> PrimT -> PrimExpr#


to add to builtin?
  cata : Int -> Nullable Int -> String -> Nullable String
      -> Bool -> Nullable Bool -> Double -> Nullable Double
      -> Byte -> Nullable Byte -> Short -> Nullable Short
      -> Long -> Nullable Long -> Date -> Nullable Date
      -> GUID -> Nullable GUID
      -> Prim a -> a

cataNonnull : Int -> String -> Bool -> Double
           -> Byte -> Short -> Long -> Date
           -> Prim a -> a
cataNonnull i s b d by sh l da p =
  cata i (Some i) s (Some s) b (Some b) d (Some d)
       by (Some by) sh (Some sh) l (Some l) da (Some da) p
-}
