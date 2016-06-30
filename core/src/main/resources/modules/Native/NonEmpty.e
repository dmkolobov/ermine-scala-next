module Native.NonEmpty where

import Function
import Native.List using type List# ; fromList#; toList#

import List.NonEmpty

foreign
  data "scalaz.NonEmptyList" NonEmpty# (a: *)

listNel# : NonEmpty# a -> List a
listNel# = fromList# . listNel##

private foreign
  method "list" listNel## : NonEmpty# a -> List# a

  data "scalaz.NonEmptyList$" NEL
  value "scalaz.NonEmptyList$" "MODULE$" nelModule : NEL
  method "nel" nel## : NEL -> a -> List# a -> NonEmpty# a

nel# : a -> List# a -> NonEmpty# a
nel# = nel## nelModule

foreign
  method "head" head# : NonEmpty# a -> a
  method "tail" tail# : NonEmpty# a -> List# a

fromNel# : NonEmpty# a -> NonEmpty a
fromNel# n = head# n :| fromList# (tail# n)

toNel# : NonEmpty a -> NonEmpty# a
toNel# (x :| xs) = nel# x (toList# xs)
