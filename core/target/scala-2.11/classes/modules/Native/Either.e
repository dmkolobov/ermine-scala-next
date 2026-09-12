module Native.Either where

{- ^ The Scala Either, and conversion with Ermine Either. -}

import Either

foreign
  data "scalaz.$bslash$div" EitherZ# (a: *) (b: *)

private foreign
  data "scala.util.Left$" LeftModule
  value "scala.util.Left$" "MODULE$" leftModule : LeftModule
  method "apply" left# : LeftModule -> a -> Either# a b
  data "scala.util.Right$" RightModule
  value "scala.util.Right$" "MODULE$" rightModule : RightModule
  method "apply" right# : RightModule -> b -> Either# a b
  data "scalaz.$minus$bslash$div$" LeftzModule
  value "scalaz.$minus$bslash$div$" "MODULE$" leftzModule : LeftzModule
  method "apply" leftz# : LeftzModule -> a -> EitherZ# a b
  data "scalaz.$bslash$div$minus$" RightzModule
  value "scalaz.$bslash$div$minus$" "MODULE$" rightzModule : RightzModule
  method "apply" rightz# : RightzModule -> b -> EitherZ# a b

toEither# : Either a b -> Either# a b
toEither# (Left x) = left# leftModule x
toEither# (Right x) = right# rightModule x

toEitherZ# : Either a b -> EitherZ# a b
toEitherZ# (Left x) = leftz# leftzModule x
toEitherZ# (Right x) = rightz# rightzModule x

{-
builtin
  foreign data "scala.Either" Either# (a: *) (b: *)
-}
