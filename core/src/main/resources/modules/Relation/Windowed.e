
module Relation.Windowed where

import Function
import List using map_List

import Relation.Row
import Relation.Op
import Relation.Op.Unsafe
import Relation.Sort
import Relation.Aggregate

import Native.Function
import Native.List
import Native.Maybe
import Native.Pair

data Bound = Unbounded | Bounded Int

data Frame = F Bound Bound

unboundedFrame : Frame
unboundedFrame = F Unbounded Unbounded

data Window (s : rho) =
  forall t. W (List (String, PrimT)) (Sort t) Frame

window : (t <- (r, s)) => Row r -> Sort s -> Frame -> Window t
window (Row ps) s f = W ps s f

windowed : (t <- (r, s)) => Windowed r a -> Window s -> Op t a
windowed agg (W p s (F b e)) = funcall2# windowedModule agg w
  where
  f = funcall2# frameModule (unbound b) (unbound e)
  w = simpleWindow windowModule (toList# . map_List toPair# $ p) (toTypedSort# s) f

foreign
  data "com.clarifi.reporting.WindowFunc" Windowed (r: ρ) (a: *)

  value "com.clarifi.reporting.Rank$" "MODULE$"
    rank : Windowed (||) Int

  value "com.clarifi.reporting.DenseRank$" "MODULE$"
    dense : Windowed (||) Int

  value "com.clarifi.reporting.RowNumber$" "MODULE$"
    rowNumber : Windowed (||) Int

nTile : (AsOp op) => op r Int -> Windowed r Int
nTile = funcall1# nTileModule . asOp

windowedAggregate : Aggregate r a -> Windowed r a
windowedAggregate = funcall1# windowedAggregateModule


private
  unbound : Bound -> Maybe# Int
  unbound Unbounded = Nothing#
  unbound (Bounded i) = Just# i

private foreign
  data "com.clarifi.reporting.Frame" Frame#
  value "com.clarifi.reporting.Frame$" "MODULE$"
      frameModule : Function2 (Maybe# Int) (Maybe# Int) Frame#

  data "com.clarifi.reporting.Window" Window#

  data "com.clarifi.reporting.Window$" WindowModule
  value "com.clarifi.reporting.Window$" "MODULE$"
      windowModule : WindowModule
  method "simple"
    simpleWindow : WindowModule
                -> List# (Pair# String PrimT)
                -> TypedSort#
                -> Frame# 
                -> Window#

  method "apply"
    fancyWindow : WindowModule
               -> List# Op#
               -> List# (Pair# Op# SortOrder#)
               -> Frame#
               -> Window#

  value "com.clarifi.reporting.Op$Windowed$" "MODULE$"
      windowedModule : (t <- (s,r)) => Function2 (Windowed r a) Window# (Op t a)

  value "com.clarifi.reporting.NTile$" "MODULE$"
    nTileModule : Function1 (Op r Int) (Windowed r Int)
  value "com.clarifi.reporting.AggWindowFunc$" "MODULE$"
    windowedAggregateModule : Function1 (Aggregate r a) (Windowed r a)
