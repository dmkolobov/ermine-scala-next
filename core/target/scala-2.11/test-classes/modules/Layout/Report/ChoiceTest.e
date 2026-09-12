module Layout.Report.ChoiceTest where

import Builtin
import Control.Functor
import Function
import List
import Native
import Prim

foreign
  data "scalaz.NonEmptyList" NEL (a: *)
  function "com.clarifi.reporting.writers.Writer" "toPrimExprNel"
      toPrimExprNel : a -> NEL PrimExpr#

tp = toPrimExprNel

trials = [(tp 5B, "5"),
          (tp 5S, "5"),
          (tp 5, "5"),
          (tp 5L, "5"),
          (tp 5.0, "5.0"),
          (tp "hi", "hi"),
          (tp True, "true"),
          (tp False, "false"),
          (tp (Some 3), "3"),
          (tp (Null String), "null!!!"),
          (tp (3,8L), "3++8")]

foreignTrials = toList# $ fmap listFunctor toPair# trials
