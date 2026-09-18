module Layout.Widgets.Headline where

-- Registry name "headline": a title, the scope the numbers are about, and
-- three figures read off a relation -- how many rows, their total, and the
-- largest of them.
--
-- This is the widget whose SMART CONSTRUCTOR SCANS (stage J3g).  `headline`
-- is the pure one, for a caller that already has the numbers; `headlineOf`
-- takes the relation instead and is a `Fetch Node`, so it reads the rows
-- itself and can sit inside a layout:
--
--     vflowF [ headlineOf "Sales" "in north" amount northSales
--            , done (tabular (simpleTable cols northSales)) ]
--
-- Before J3g that was impossible: every layout combinator took a `Node`, so
-- a scan had to be hoisted above the whole layout and a widget could not
-- own one.  Nothing about `Fetch` makes a widget special -- it has one
-- operation, scan a plan in an order -- so a widget definition may use it.
--
-- The props carry no relation: the numbers ARE the widget, and the rows the
-- scan read are not sent (put a table beside it if they are wanted).

import Bool
import Double
import Field using getF
import Int
import Layout.Doc using widget; type Node
import Layout.Fetch using {type Fetch; done; scanRelation}
import Layout.Widgets.Format using {type CellFormat; Default}
import List using {length; sum'; foldl; map_List; empty_Bracket; cons_Bracket}
import Primitive
import Relation

-- `headlineTitle`, not `title`: Layout.Widgets re-exports every widget module
-- into one scope and Layout.Widgets.Scorecard already owns `title` (the same
-- reason Layout.Widgets.Chart spells its own `chartTitle`).
data HeadlineProps = HeadlineProps { headlineTitle : String
                                   , scope : String        -- what the numbers are about
                                   , rowCount : Int
                                   , total : Double
                                   , largest : Double
                                   , headlineFormat : CellFormat }

headline : HeadlineProps -> Node
headline p = widget "headline" p

-- | The largest of the values, folded from the FIRST one: over rows that are
-- all negative (a loss, a delta) the maximum is negative too, and 0.0 -- a
-- number that is in no row -- would be wrong.  0.0 over no values, the way
-- `sum'` is 0.0 over none.
biggest : List Double -> Double
biggest []        = 0.0
biggest (y :: ys) = foldl (a b -> if (b > a) b a) y ys

-- | Scan `rs`, and make the headline out of what it found: the row count,
-- the sum of `f` over the rows, and the largest `f` (see `biggest`: the
-- maximum of the rows, 0.0 only when there are none).  The format is
-- `Default`; build the props by hand for another one.
headlineOf : (Relational rel, r <- (h, t))
          => String -> String -> Field h Double -> rel r -> Fetch Node
headlineOf ttl scp f rs =
  scanRelation rs (rows ->
    let xs = map_List (getF f) rows
    in done (headline (HeadlineProps ttl scp (length rows) (sum' xs) (biggest xs) Default)))
