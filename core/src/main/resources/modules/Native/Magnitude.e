module Native.Magnitude where

import Function
import Control.Functor

import Native.Pair
import Native.List
import List

import Unsafe.Coerce

foreign
  data "com.clarifi.reporting.writers.Magnitude" Magnitude a
  -- data "com.clarifi.reporting.writers.Magnitude.Area" Area
  private data "com.clarifi.reporting.writers.Cells" CellsT#
  private constructor cellsC : Int -> CellsT#
  private subtype Cells# : CellsT# -> Magnitude CellT
  private private data "com.clarifi.reporting.writers.Pixels" PixelsT#
  private constructor pixelsC : Int -> PixelsT#
  private subtype Pixels# : PixelsT# -> Magnitude PixelT
  private data "com.clarifi.reporting.writers.Dimensionless" DimensionlessT#
  private constructor dimensionlessC : Double -> DimensionlessT#
  private subtype Dimensionless# : DimensionlessT# -> Magnitude DimensionlessT

-- Types for the phantoms
private data CellT
private data PixelT
private data DimensionlessT


cells = Cells# . cellsC
pixels = Pixels# . pixelsC
dimensionless = Dimensionless# . dimensionlessC

toListMagnitude# = toList#

-- Area is here so toArea# isn't in Layout.Magnitude.
data Area = forall a. Area (Magnitude a) (Magnitude a)
data Volume = forall a. Volume (Magnitude a) (Magnitude a) (Magnitude a)

-- needed for toArea#
private data ErasedT
erasePhantom : forall a. Magnitude a -> Magnitude ErasedT
private erasePhantom = unsafeCoerce

-- unless we erase the phantom, we get "error: skolem variable escapes"
toArea# (Area a1 a2) = pair# (erasePhantom a1) (erasePhantom a2)

toListArea# = toList# . fmap listFunctor toArea#

private data ErasedMagnitude = forall a. M (Magnitude a)
type MagnitudeList = List ErasedMagnitude

toMagnitudeList# = toList# . fmap listFunctor ((M m) -> erasePhantom m)

cellsM = M . cells
pixelsM = M . pixels
dimensionlessM = M . dimensionless

cellsA height width = Area (cells height) (cells width)
pixelsA height width = Area (pixels height) (pixels width)

ratioA x y =  Area (dimensionless x) (dimensionless y)

