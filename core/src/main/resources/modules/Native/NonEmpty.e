module Native.NonEmpty where

import Function
import Native.List using type List# ; fromList#; toList#

import List.NonEmpty

foreign
  data "scalaz.NonEmptyList" NonEmpty# (a: *)

-- scalaz 7.1 changed NonEmptyList's `list` and `tail` from scala.List to
-- scalaz.IList, so the bridge below converts at the boundary and every
-- Ermine-visible name keeps the type it had.
private foreign
  data "scalaz.IList" IList# (a: *)
  data "scalaz.IList$" IListModule
  value "scalaz.IList$" "MODULE$" ilistModule : IListModule
  method "fromList" ilistFromList## : IListModule -> List# a -> IList# a
  method "toList" ilistToList# : IList# a -> List# a

ilistFromList# : List# a -> IList# a
ilistFromList# = ilistFromList## ilistModule

listNel# : NonEmpty# a -> List a
listNel# = fromList# . ilistToList# . listNel##

private foreign
  method "list" listNel## : NonEmpty# a -> IList# a

  data "scalaz.NonEmptyList$" NEL
  value "scalaz.NonEmptyList$" "MODULE$" nelModule : NEL
  method "nel" nel## : NEL -> a -> IList# a -> NonEmpty# a

nel# : a -> List# a -> NonEmpty# a
nel# x xs = nel## nelModule x (ilistFromList# xs)

private foreign
  method "tail" tail## : NonEmpty# a -> IList# a

foreign
  method "head" head# : NonEmpty# a -> a

tail# : NonEmpty# a -> List# a
tail# = ilistToList# . tail##

fromNel# : NonEmpty# a -> NonEmpty a
fromNel# n = head# n :| fromList# (tail# n)

toNel# : NonEmpty a -> NonEmpty# a
toNel# (x :| xs) = nel# x (toList# xs)
