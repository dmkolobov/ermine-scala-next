module Native.Either where

{- ^ The Scala Either, and conversion with Ermine Either. -}

import Either

private foreign
  data "scala.Left$" LeftModule
  value "scala.Left$" "MODULE$" leftModule : LeftModule
  method "apply" left# : LeftModule -> a -> Either# a b
  data "scala.Right$" RightModule
  value "scala.Right$" "MODULE$" rightModule : RightModule
  method "apply" right# : RightModule -> b -> Either# a b

toEither# : Either a b -> Either# a b
toEither# (Left x) = left# leftModule x
toEither# (Right x) = right# rightModule x

{-
builtin
  foreign data "scala.Either" Either# (a: *) (b: *)
-}
