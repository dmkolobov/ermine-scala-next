module Layout.Widgets.Column where

-- The widget-neutral half of typed columns (WP-37, D6): what a field's RUNTIME
-- primitive type says about its values.  A widget that lays out a relation
-- column (a table's alignment and colType, a chart axis's numeric flag) reads
-- `fieldKind` instead of asking the author.
--
-- The classification is by `PrimT.name` (com.clarifi.reporting.PrimT), which is
-- the same for the nullable and non-null variant of a type:
--   Byte Short Int Long Double   -> NumericField
--   Date Timestamp               -> TemporalField
--   String Bool UUID             -> OtherField
-- and any name not listed (a PrimT added later) falls back to OtherField.
--
-- The table-specific half (sort and row-group marks, and their lowering to
-- column indices) lives in Layout.Widgets.Table: the indices point into a
-- table's own column list, so no other widget shares them.

import Prim using prim#
import Field using fieldType

data FieldKind = NumericField | TemporalField | OtherField

-- | The runtime primitive type's name, e.g. "Int", "Date", "String".
primName : Field h a -> String
primName f = primTName# (prim# (fieldType f))

fieldKind : Field h a -> FieldKind
fieldKind f = kindOfPrimName (primName f)

private foreign
  method "name" primTName# : PrimT -> String

private
  kindOfPrimName : String -> FieldKind
  kindOfPrimName "Byte"      = NumericField
  kindOfPrimName "Short"     = NumericField
  kindOfPrimName "Int"       = NumericField
  kindOfPrimName "Long"      = NumericField
  kindOfPrimName "Double"    = NumericField
  kindOfPrimName "Date"      = TemporalField
  kindOfPrimName "Timestamp" = TemporalField
  kindOfPrimName _           = OtherField
