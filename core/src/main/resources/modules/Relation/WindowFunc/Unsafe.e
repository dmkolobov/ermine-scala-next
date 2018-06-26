module Relation.WindowFunc.Unsafe where

import Native
import Relation.Op.Type
import Relation.WindowFunc.Type
import Relation.Aggregate.Type

foreign
--  data "com.clarifi.reporting.Rank" Rank
--  data "com.clarifi.reporting.DenseRank" DenseRank
--  data "com.clarifi.reporting.RowNumber" RowNumber
--  data "com.clarifi.reporting.NTile" NTile

  value "com.clarifi.reporting.Rank$" "MODULE$"
      rankModule : WindowFunc (||) Int
  value "com.clarifi.reporting.DenseRank$" "MODULE$"
      denseRankModule : WindowFunc (||) Int
  value "com.clarifi.reporting.RowNumber$" "MODULE$"
      rowNumberModule : WindowFunc (||) Int
  value "com.clarifi.reporting.NTile$" "MODULE$"
      nTileModule : Function1 (Op r Int) (WindowFunc r Int)
  value "com.clarifi.reporting.AggWindowFunc$" "MODULE$"
      toWindowFuncModule : Function1 (Aggregate r a) (WindowFunc r a)
