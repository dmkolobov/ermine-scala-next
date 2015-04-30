module LayoutTesting where

import Prelude
import Layout

a = text "abra"
b = text "cadabra"
bs = vflow . take 50 ' repeat b
c = text "hocus pocus!"

-- distinction between 'expandable' components and 'fixed' components
-- text "abra" is fixed (could potentially be horizontally expandable, if we space out the letters, could also restrict the space available, cut of the text with ... or something)
-- scroll bs is (potentially) expandable
-- flow [ fixed, fixed, expandable, fixed ], fixeds add up to some height, if we have any remaining height, we could choose to grow the expandable (perhaps up to its maximum)
-- flow [ fixed, expandable, fixed, expandable], fixeds add up to some height, there will be some space leftover, which is split evenly between the expandables, until they reach their maximum(s), if they have a maximum, at which point all the remaining space goes to the remaining expandable that can still absorb more space
-- flow [ fixed, expandable, fixed, expandable] - as above, but may want to weight the expandables

expandable : Report f z -> Report f z
expandable r = _

weightedExpandable : Double -> Report f z -> Report f z
weightedExpandable = _

maxBounds : Maybe (Magnitude a)
         -> Maybe (Magnitude a)
         -> Report f z
         -> Report f z
maxBounds = _

bound : List Area
     -> Report f z
     -> Report f z
bound = _

-- boundW
-- boundH

-- vflow [ expandable charta, slider, maxBound blah ' expandable chartb ]
-- uberhflow : List (Report f z) -> Report f z

ex1 = scroll ' vflow [a, c]
ex2 = vflow [vflow [a], scroll bs, c]
ex3 = vspan [a, scroll bs, c]
ex3a = vflow [prefH [pixelsM 0] a, scroll bs, scroll bs, prefH [pixelsM 0] c]
ex4 = stack a (scroll bs)

mytab = vflow [
  sectionHeader ' text "Blah",
  vstrut,
  vspace3,
  ex4
]

-- we are thinking - replace vflow to set grow of NEVER on everything
-- set everything to SOMETIMES if it is unset
collapsibleAboveTabs = vflow [
  collapsible False "A section" ' vflow [a, c],
  vflow [ vflow [a, vflow [ hflow [a] ], a, c] ]
]
--  tabbed [("Uno", prefH [pixelsM 0] ' scroll bs), ("Dos", ex2), ("Tres", ex3)]
--  , scroll bs]
