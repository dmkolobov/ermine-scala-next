module Layout.Report.StyleGrid where

import Native
import Function
import List
import Pair

type StyleGrid a = List (Maybe String, List (Maybe String, a))

mapStyleGrid : (a -> b) -> StyleGrid a -> StyleGrid b 
mapStyleGrid f = map_List (mapSnd $ map_List (mapSnd f))

-- funcall1# : Function1 a b -> (a -> b)  -- (a -> b) is in Ermine world
toStyleGrid# : StyleGrid a -> StyleGrid# a
toStyleGrid# = 
  let 
    toStyleList# f = toList# . map_List (x -> toPair# (toMaybe# (fst x), f (snd x)))
  in
    funcall1# styleGridModule . toStyleList# (toStyleList# id)

foreign
   -- a is for the type paramter
  data "com.clarifi.reporting.writers.StyleGrid" StyleGrid# (a: *)
  private 
    value "com.clarifi.reporting.writers.StyleGrid$" "MODULE$"
      styleGridModule : Function1 (List# (Pair# (Maybe# String) (List# (Pair# (Maybe# String) a)))) (StyleGrid# a)