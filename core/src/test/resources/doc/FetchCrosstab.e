module FetchCrosstab where

-- THE TABLE A QUERY CANNOT WRITE.
--
-- `table` shows the columns its `Column r` list names, and that list is
-- written at compile time; a relation's row type is fixed then too.  So a
-- table of regions DOWN the side and one column PER MONTH THAT HAS SALES
-- cannot come out of the algebra: the column set is in the data.  A scan is
-- the only way to learn it, which is what `crosstabOf` does -- it reads the
-- rows, sorts the distinct keys of each axis, and sends a MATRIX
-- (`List (List (Maybe Double))`) rather than a relation.
--
-- A `Nothing` cell is a pair no row had (west sold nothing in January), and
-- it is not 0.0.  On the wire it is `null`.
--
--   {"params": {"measureUnits": false}}   the amounts
--   {"params": {"measureUnits": true}}    the units, over the same layout
--
-- Two things worth copying from here:
--
--  * THE KEYS ARE STRINGS the caller chose.  `day` is a Date, so this module
--    joins a small calendar dimension that labels each day `"2026-01"` and
--    so on -- a spelling that sorts the way a reader expects, which
--    `"Jan"`/`"Feb"`/`"Mar"` would not.
--  * THE MEASURE IS ONE COLUMN.  `crosstabOf` takes one `Field h Double`, so
--    a parameter that picks between two measures renames them both to one
--    column first (`units` is an Int, so it is cast on the way).
--
-- The headline below the crosstab is the OTHER widget that scans, over the
-- same relation: two `Fetch Node`s in one `vflowF`, two scans, one document.

import Bool
import Field
import Layout.Doc
import Layout.Fetch
import Layout.Widgets.Crosstab
import Layout.Widgets.Format
import Layout.Widgets.Headline
import List using {empty_Bracket; cons_Bracket}
import Relation
import Relation.Op using {col; combine; fromNumericOp}
import Relation.Row hiding empty_Bracket; cons_Bracket
import FetchData

field monthName : String
field measure : Double

data Query = Query { measureUnits : Bool }

-- | The month each sale day falls in, as a dimension table: `day` is a Date,
-- and a crosstab's keys are Strings the caller chose.
calendar : [day, monthName]
calendar = relation
  [ { day = @2026/1/5,  monthName = "2026-01" }
  , { day = @2026/1/9,  monthName = "2026-01" }
  , { day = @2026/1/19, monthName = "2026-01" }
  , { day = @2026/2/2,  monthName = "2026-02" }
  , { day = @2026/2/14, monthName = "2026-02" }
  , { day = @2026/2/20, monthName = "2026-02" }
  , { day = @2026/3/3,  monthName = "2026-03" }
  , { day = @2026/3/17, monthName = "2026-03" }
  ]

-- | The sales, labelled with their month, with the chosen measure under the
-- one name `crosstabOf` is given.  Both arms are Double: `units` is cast.
measured : Query -> [region, monthName, measure]
measured q =
  let labelled = join sales calendar
  in if (measureUnits q)
       (combine (fromNumericOp (col units)) measure labelled # {region, monthName, measure})
       (rename amount measure labelled # {region, monthName, measure})

cellFmt : Query -> CellFormat
cellFmt q = if (measureUnits q) (IntegralRound False False 0) (Currency False False "$" 2)

report : Query -> Fetch Node
report q =
  vflowF [ crosstabOf (CrosstabSource "Sales by region and month" "Region" "Month"
                                      region monthName measure (measured q) (cellFmt q))
         , headlineOf (HeadlineSource "Sales" "every region" measure (measured q)) ]
