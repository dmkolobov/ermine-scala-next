module Relation.Process where

import Native.Relation
import Field
import Function

private foreign
  data "com.clarifi.reporting.relational.ProcessSymbol" ProcessSymbol (a:row) (b:row)
  data "com.clarifi.reporting.Attribute" Attribute
  constructor attr# : String -> Prim a -> Attribute
  function "com.clarifi.reporting.relational.ProcessSymbols" "median" median# :
    Attribute -> ProcessSymbol a b
  function "com.clarifi.reporting.relational.ProcessSymbols" "weightedMean" weightedMean# :
    Attribute -> Attribute -> ProcessSymbol a b
  function "com.clarifi.reporting.relational.ProcessSymbols" "weightedHarmonicMean" weightedHarmonicMean# :
    Attribute -> Attribute -> ProcessSymbol a b

private
  attr f = attr# (fieldName f) (fieldType f)
  toMem r = letM r id

medianBy : (PrimitiveNum n, Relational rel, r <- (v,t))
        => Field v n -> rel r -> Mem v
medianBy value r = pipe# (toMem r) (median# (attr value))

weightedMeanBy : (PrimitiveNum n, Relational rel, r <- (w,v,t))
              => Field w n -> Field v n -> rel r -> Mem v
weightedMeanBy weight value r = pipe# (toMem r) (weightedMean# (attr weight) (attr value))

weightedHarmonicMeanBy : (PrimitiveNum n, Relational rel, r <- (w,v,t))
                      => Field w n -> Field v n -> rel r -> Mem v
weightedHarmonicMeanBy weight value r = pipe# (toMem r) (weightedHarmonicMean# (attr weight) (attr value))

