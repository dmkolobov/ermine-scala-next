module Layout.Writer where

import Native
import Native.Function
import Control.Monad
import List
import Error
import IO

foreign data "com.clarifi.reporting.writers.Writer" Writer (f : * -> *) a
foreign data "com.clarifi.reporting.writers.SelectorEvent" SelectorEvent a
writerFunctor w = Functor (mapW w)
writerAp w = Ap (pureW w) (apW w)
writerMonad w = Monad (pureW w) (bindW w)
live = liveS
orEvent = orEventS

private foreign
  method "pureW" pureW : forall f a x .     Writer f a -> x -> f x
  method "bindW" bindW : forall f a x y.    Writer f a -> f x -> (x -> f y) -> f y
  method "mapW"  mapW  : forall f a x y .   Writer f a -> (x -> y) -> f x -> f y
  method "apW"   apW   : forall f a x y z . Writer f a -> f (x -> y) -> f x -> f y
  method "or" orEventS : forall z . SelectorEvent z -> SelectorEvent z -> SelectorEvent z
  function "com.clarifi.reporting.writers.SelectorEvents" "live" liveS : SelectorEvent z

foreign method "run" runW : forall f a . Writer f a -> a -> IO ()
