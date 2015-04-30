module Layout.Presentation where

{- Description of how to format result datapoints, such as the cells
   in a `Layout.Report.tabular`, for display. -}

import Bool
import Function
import Layout.Format as Fmt
import Layout.Report.Atomic
import List hiding reverse
import Map as M
import Native
import Native.NonEmpty
import Native.TraversableColumns hiding rowUsed#
import Prim using type PrimExpr#
import Relation.Row using type Row; Row; rowUsed#
import String as S
import Relation.Op.Type
import Relation.Op using asOp; show
import Relation.Sort using {type Sort; type SortOrder; Sort}

private foreign
  subtype AsTraversableColumns : Presentation r a -> TraversableColumns# r
  function "com.clarifi.reporting.writers.Presentation" "oneOp"
      presentation# : Format_Fmt a -> Op r a -> Presentation r a
  function "com.clarifi.reporting.writers.Presentation" "twoOps"
      presentation2# : Format_Fmt (a, b) -> Op r a -> Op s b -> Presentation t (a, b)
  method "format" format# : Presentation r a -> Format_Fmt a
  method "extract" extract# : Presentation r a -> ScalaRecord#
                           -> NonEmpty# PrimExpr#
  function "com.clarifi.reporting.writers.Writer" "fromPrimExprNel"
      unsafeFromPrimExprNel : NonEmpty# PrimExpr# -> a

  function "com.clarifi.reporting.writers.Presentation" "devolve"
      unsafeDevolve : Presentation r a -> Op r b

-- Describe how to display values of a column or two, and also how to
-- sort by that column.
presentation : (AsOp op) => Format_Fmt a -> op r a -> Presentation r a
dualPresentation : forall a b r s t. (t <- (r, s), AsOp op1, AsOp op2)
                   => Format_Fmt (a, b)
                   -> op1 r a -> op2 s b -> Presentation t (a, b)
presentation fmt op = presentation# fmt (asOp op)
dualPresentation fmt op1 op2 = presentation2# fmt (asOp op1) (asOp op2)

-- | Alias for dualPresentation dateRange_Fmt.
dateRange : (r <- (r1, r2), AsOp o1, AsOp o2)
         => o1 r1 Date
         -> o2 r2 Date
         -> Presentation r (Date, Date)
dateRange = dualPresentation dateRange_Fmt

percent : (AsOp op, PrimitiveNum n) => op r n -> Presentation r n
percent o = presentation percentage_Fmt o

round : (AsOp op, PrimitiveNum n) => Int -> op r n -> Presentation r n
round n o = presentation (round_Fmt n) o

integralRound : (AsOp op, PrimitiveNum n) => Int -> op r n -> Presentation r n
integralRound n o = presentation (integralRound_Fmt n) o

truncate : (AsOp op, Primitive a) => Int -> op r a -> Presentation r a
truncate a o = presentation (truncate_Fmt a) o

currency : (AsOp op, PrimitiveNum n) => String -> op r n -> Presentation r n
currency = presentation . currency_Fmt

-- Lift `op` to its default presentation.
basic : (Primitive a, AsOp op) => op r a -> Presentation r a
basic = presentation unit_Fmt

withMarkdown : (AsOp op, Unscaled a) => Format_Fmt a -> op r a -> Presentation r a
withMarkdown fmt =  presentation $ markdown_Fmt fmt

markdown : (AsOp op, Unscaled a) => op r a -> Presentation r a
markdown =  withMarkdown unit_Fmt

-- | Extract record elements to render.
extractScalar : AsPresentation pr => pr r a -> {..r} -> Atomic a
extractScalar pr = let pr' = asPresentation pr
                   in Atomic (format# pr') . unsafeFromPrimExprNel
                    . extract# pr' . scalaRecord# . record#

-- | Build a sort, left-to-right, on a presentation's columns.
ordering : AsPresentation pr => SortOrder -> pr r a -> Sort r
ordering so pr = Sort $ zip (columnsUsed pr) (fix $ (::) so)

-- | Answer all unique columns referenced in a presentation, in order.
columnsUsed : AsPresentation pr => pr r a -> List String
columnsUsed = columnsUsed# . AsTraversableColumns . asPresentation

-- | Answer the Row schema used by a presentation.
rowUsed : AsPresentation pr => pr r a -> Row r
rowUsed = rowUsed# . AsTraversableColumns . asPresentation

-- | Extract an existentially-typed 'Op' that implements *some* of the
-- underlying presentation logic.  'Relation.Op.show' is a good first
-- argument.
devolve : forall r a z. (forall b. Op r b -> z) -> Presentation r a -> z
devolve (f : some r z. forall b. Op r b -> z) = f . unsafeDevolve

-- | Just 'devolve show_Op'.  Turn *some* of the presentation's logic
-- into an Op, discarding the unimplementable parts.
devolveShowOp : Presentation r a -> Op r String
devolveShowOp = devolve show

{-
builtin
  foreign data "com.clarifi.reporting.writers.Presentation" Presentation (r: ρ) (a: *)

  class AsPresentation a where
    asPresentation : a r b -> Presentation r b

  instance AsPresentation Presentation where
    asPresentation = id

  instance AsPresentation Op where
    asPresentation = basic

  instance AsPresentation Field where
    asPresentation = basic . asOp
-}
