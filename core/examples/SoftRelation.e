module SoftRelation where

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Presentation as Pres
import Layout.Legend as Lg
import Layout.Report.SoftRelation
import Layout.SortPriority
import Layout.Magnitude
import Field
import Ord using fromLess
import Relation.Op as Op
import Syntax.Relation
import Relation.Sort using ordering

import DrilldownList as DDL

field idc : String
field dt: String
field dtGroup : String
field pid : Int
field cid : Int
field k : String
field v : String

-- | Information about words, in soft-table form.
wordstats : [idc, k, v]
wordstats = relation [
    {idc = "word", k = "First Letter", v = "w"},
    {idc = "word", k = "Length", v = "4"},
    {idc = "sentence", k = "First Letter", v = "s"},
    {idc = "sentence", k = "Length", v = "8"}
]

-- | More words.
ddWordstats : [idc, k, v, pid, cid]
ddWordstats = relation [
    {idc = "word", k = "First Letter", v = "w", pid = 1, cid = 2},
    {idc = "word", k = "Length", v = "4", pid = 1, cid = 2},
    {idc = "sentence", k = "First Letter", v = "s", pid = 0, cid = 1},
    {idc = "sentence", k = "Length", v = "8", pid = 0, cid = 1},
    {idc = "other", k = "First Letter", v = "o", pid = 1, cid = 3},
    {idc = "other", k = "Length", v = "5", pid = 1, cid = 3},

    {idc = "pencil", k = "First Letter", v = "p", pid = 10, cid = 20},
    {idc = "pencil", k = "Length", v = "6", pid = 10, cid = 20},
    {idc = "box", k = "First Letter", v = "b", pid = 0, cid = 10},
    {idc = "box", k = "Length", v = "3", pid = 0, cid = 10},
    {idc = "eraser", k = "First Letter", v = "e", pid = 10, cid = 30},
    {idc = "eraser", k = "Length", v = "6", pid = 10, cid = 30}
]

ddWordstats2 = relation [
  {dtGroup = "2010", dt = "12/31/2010" },
  {dtGroup = "2011", dt = "01/31/2011" }
] ** ddWordstats

private
  -- | Take a field from a record.
  tf = flip (!)
  -- | Distribute UN over BIN's two args.
  on' bin un x y = bin (un x) (un y)

type WordstatsRel = SoftRelation String String (|k|) (|v|)

-- | Just use standard sorting rules and standard presentation.
stdSort : WordstatsRel
stdSort = softRelation k (Left $ ordering {k}) (valuePres . tf k)
  where valuePres "First Letter" = (v, Nothing) ^ 0
        valuePres _ = unsorted (v, Nothing)

-- | Put "Length" to the left, and ‘quote’ the First Letter contents.
lengthFirst : WordstatsRel
lengthFirst = softRelation k (Right . fromLess $ on' sk (tf k)) (showingValues . pres . tf k)
  where sk "Length" "First Letter" = True
        sk _ _ = False
        pres "First Letter" = [prim_Op "‘", v, prim_Op "’"]_Op
        pres _ = asOp_Op v

aboutIdc : Legend_Lg (|idc|)
aboutIdc = legend_Lg idc "Some Word"

-- | Tabular for wordstats, given a SoftRelation.
showWordstats sr = keyValueTabular sr (Just aboutIdc) wordstats

keyValueTabularExample = vflow [
  atomShown "standard colsort, initial sort by first letter, standard presentation",
  prefH [pixelsM 200] $ showWordstats stdSort,
  atomShown "Length to left, and ‘quote’ First Letter",
  prefH [pixelsM 200] $ showWordstats lengthFirst,
  atomShown "drilldown",
  prefH [pixelsM 200] $ drilldownKeyValueTable stdSort (Just aboutIdc)
                                     idc pid cid ddWordstats,
  atomShown "thanks"
]

-- TWO levels, and the second one needs TWO columns: `cons_Bracket` asks for
-- `rout <- (f1, f2, r)` since stage S3b (2026-09-11), so a level whose parent and
-- child are the SAME column is refused -- the body appends both to the list's row,
-- and `(dt, dt)` would put `dt` in it twice.  It used to be `[(pid, cid), (dt, dt)]`,
-- which type-checked only because the three `Has` constraints `cons_Bracket` carried
-- asserted nothing at all (`SIG-1-SURVEY.md` item c3).  The date level is keyed on
-- (year, date) instead, which is what a date drilldown means anyway.
groupingDateDrilldown = [(pid, cid), (dtGroup, dt)]_DDL

ddWordstatsRoots = ddWordstats2
--ddWordstatsRoots = ddWordstats2 ** (relation [ {pid = 0} ])

drillDown2Example = scroll ' vflow [
  atomShown "Source data",
  tabular Nothing ddWordstats2,
  atomShown "Roots data",
  tabular Nothing ddWordstatsRoots,
  atomShown "Drilldown2",
  drilldownKeyValueTable2 stdSort Nothing idc groupingDateDrilldown ddWordstats2 ddWordstatsRoots
]
