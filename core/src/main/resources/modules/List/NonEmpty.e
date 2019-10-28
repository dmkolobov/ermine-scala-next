module List.NonEmpty where

import List as List

infixr 5 :| ++

data NonEmpty a = (:|) a (List a)

head (a :| _) = a
tail (_ :| as) = as
cons a (b :| bs) = a :| b :: bs

(++) xs ys = head xs :| tail xs ++_List head ys :: tail ys

toList (a :| as) = (a :: as)

map f (x :| xs) = f x :| map_List_List f xs

singleton : a -> NonEmpty a
singleton x = x :| []_List

doubleton : a -> a -> NonEmpty a
doubleton x y = x :| [y]_List
