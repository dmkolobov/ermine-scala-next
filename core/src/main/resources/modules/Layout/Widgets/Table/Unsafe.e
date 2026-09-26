module Layout.Widgets.Table.Unsafe where

-- The escape hatch for a column whose name is only known at run time (WP-37, D7).
-- `rawColumn` names a relation column by a String: nothing checks that the
-- relation has it, and a wrong name is a blank column (or a client error) at
-- render time, not a type error.  Nothing in the stdlib or the fixtures may
-- import this module; use Layout.Widgets.Table.col/numCol/dateCol.

import Layout.Widgets.Table using {type Column; Column#; TableColumn; AlignLeft; OtherColumn}
import Layout.Widgets.Format using Default

-- | A left-aligned, unformatted OtherColumn named by a String; the header is the
-- name.  The usual marks and knobs (withHeader, withFormat, alignRight,
-- sortAsc, groupRows) apply to it like to any typed column.
rawColumn : String -> Column r
rawColumn c = Column# (TableColumn c c Default AlignLeft OtherColumn) Nothing False
