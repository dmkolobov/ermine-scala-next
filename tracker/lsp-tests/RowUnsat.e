module RowUnsat where

import Prelude
import Relation.Op as Op
import Syntax.Relation

-- The B1 program of tracker/PROMPT-subsume-termination.md, as a file the editor opens.
-- `people` carries no date column, so the `dateDiff` combine cannot be satisfied and the
-- module must be REFUSED -- in the editor, within the debounce window, not by pinning a
-- core until the user restarts the server.
field startDate, endDate : Date
field gap : Int
field name : String

people : [ name ]
people = relation [ { name = "Ada" } ]

bad = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap people
