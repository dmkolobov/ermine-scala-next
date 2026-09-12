module Layout.Color where

import Bool
import Control.Monad
import Eq
import Function
import List
import Map using fromAssocList; type Map
import Maybe
import Num
import Ord
import Parse using parseInt
import String as S
import StringManip using allMatches
import Syntax.Maybe

foreign
  -- | A color in some colorspace.
  data "java.awt.Color" Color
  value "java.awt.Color" "black"     black     : Color
  value "java.awt.Color" "blue"      blue      : Color
  value "java.awt.Color" "cyan"      cyan      : Color
  value "java.awt.Color" "darkGray"  darkGray  : Color
  value "java.awt.Color" "gray"      gray      : Color
  value "java.awt.Color" "green"     green     : Color
  value "java.awt.Color" "lightGray" lightGray : Color
  value "java.awt.Color" "magenta"   magenta   : Color
  value "java.awt.Color" "orange"    orange    : Color
  value "java.awt.Color" "pink"      pink      : Color
  value "java.awt.Color" "red"       red       : Color
  value "java.awt.Color" "white"     white     : Color
  value "java.awt.Color" "yellow"    yellow    : Color

-- | Color without an alpha channel, all args in [0,255].
rgb : Int -> Int -> Int -> Color
rgb = rgb# ` on3 ' sanergb

-- | Color with an alpha channel, all args in [0,255].
rgba : Int -> Int -> Int -> Int -> Color
rgba r g b a = (rgba# ` on3 ' sanergb) r g b (sanergb a)

rgbRead : String -> Maybe Color
rgbRead = map (uncurry3 rgb) . hexread

underlineColor = rgb 230 230 230

-- Colors from PA reports
paRed = (rgb 138 28 2)

standardColors : Map String Color
standardColors = fromAssocList ord_S
  [("black",     black),
   ("blue",      blue),
   ("cyan",      cyan),
   ("darkGray",  darkGray),
   ("gray",      gray),
   ("green",     green),
   ("lightGray", lightGray),
   ("magenta",   magenta),
   ("orange",    orange),
   ("pink",      pink),
   ("red",       red),
   ("white",     white),
   ("yellow",    yellow)]

private
  boundi mi ma = max numOrd mi . min numOrd ma
  sanergb = boundi 0 255

  hexread : String -> Maybe (Int, Int, Int)
  hexread s =
    let cut pif = liftA3 maybeAp (,,) ` on3 ' map pif . parseInt 16
    in case (allMatches "[0-9A-Fa-f]{2}" s,
             allMatches "[0-9A-Fa-f]" s) of
        (r :: g :: b :: _, _) -> cut id r g b
        (_, r :: g :: b :: _) -> cut (i -> i * 16 + i) r g b
        _ -> Nothing

  on3 f g a b c = f $ g a $ g b $ g c
  uncurry3 f ~(a, b, c) = f a b c

private foreign
  constructor rgb# : Int -> Int -> Int -> Color
  constructor rgba# : Int -> Int -> Int -> Int -> Color
