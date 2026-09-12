module Layout.BorderOptions where

import Maybe
import Control.Functor

data BorderOptions a = BorderOptions (Maybe a) (Maybe a) (Maybe a) (Maybe a)

defaultBorderOptions = BorderOptions Nothing Nothing Nothing Nothing

overAllBorders f (BorderOptions n e s w) = BorderOptions (g n) (g e) (g s) (g w)
  where g = fmap maybeFunctor f

setAllBorders x (BorderOptions _ _ _ _) = BorderOptions (Just x)(Just x)(Just x)(Just x)

top   t (BorderOptions _ r b l) = BorderOptions (Just t) r b l
right r (BorderOptions t _ b l) = BorderOptions t (Just r) b l
bottom b (BorderOptions t r _ l) = BorderOptions t r (Just b) l
left  l (BorderOptions t r b _) = BorderOptions t r b (Just l)
