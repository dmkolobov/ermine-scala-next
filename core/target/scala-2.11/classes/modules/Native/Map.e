module Native.Map where

private foreign
  data "scalaz.$eq$eq$greater$greater$" MapZModule
  value "scalaz.$eq$eq$greater$greater$" "MODULE$" mapZModule : MapZModule
  method "empty" empty## : MapZModule -> MapZ# k v

foreign
  data "scalaz.$eq$eq$greater$greater" MapZ# (k: *) (v: *)

empty# : MapZ# k v
empty# = empty## mapZModule

{-
builtin
  data Map (k: *) (v: *)
  insert : k -> v -> Map k v -> Map k v
  empty : Map k v
  union : Map k v -> Map k v -> Map k v
  size : Map k v -> Int
  lookup# : k -> Map k v -> Maybe# v
-}
