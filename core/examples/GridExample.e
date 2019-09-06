module GridExample where
 
import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Ord using lt
import Relation.Op as Op
import DateRange as DR
import Syntax.Relation

field label : String
field startDate : Date
field value : Nullable Double
field category : String

datum l d v = { label = l, startDate = d, value = Some v }

stackedTable = relation [
  { label = "Europe", category = "2003", value = Some 2.5 },
  { label = "Europe", category = "2004", value = Some 2.6 },
  { label = "North&nbsp;America", category = "2003", value = Some 2.5 },
  { label = "North&nbsp;America", category = "2004", value = Some 2.7 }
]

stackedChart opts v s x y r =
    chart_K opts
      (unscaled Ascending)
      defaultScaled
      [v s x y r]

stackedBarChart opts s x y r = stackedChart opts stackedBar s x y r
stackedAreaChart opts s x y r = stackedChart opts stackedArea s x y r
      
stacked1 v =
  stackedChart    
    ([chartTitle_O := "Let's See"]_Opt)
    v
    label
    category
    value
    stackedTable    

stackedBar1 = stacked1 stackedBar    
stackedArea1 = stacked1 stackedArea
line1 = stacked1 line
step1 = stacked1 step
bar1 = stacked1 bar

flow1 = hflow[ text "hi", text "there" ]
span1 = hspan[ text "hi", text "there" ]

vflow1 = vflow[ (centered flow1), span1 ]

grid1 = grid [
    [atomShown "Number of Holdings - Total", atomShown "?"],
    [atomShown "Number of **Holdings** - Long",  atomShown "?"],
    [atomShown "Number of Holdings - Long",  atomShown "?"],
    [atomShown "Number of Holdings - Short", (prefA [pixelsA 200 180] bar1)],
    [atomShown "Cash", atomShown "?"],
	[atomShown "Long Value", atomShown "?"],
	[atomShown "Short Value", atomShown "?"],
	[atomShown "Net Equity Value", atomShown "?"]
  ]

-- A grid example focusing on text effects.
--
-- This is meant to test Ermine Writers bug
-- https://bitbucket.org/ermine-language/ermine-writers/issue/15/copy-pasting-numbers-from-grid-table
-- by providing a basis for exercising the various formats we may want
-- special rules for.
formattedTextsGrid = grid [
    [atomShown "Pi", fmt (round_Fmt 2) pi],
    [atomShown "e", fmt (integralRound_Fmt 5) (exp 1.0)],
    [atomShown "just 5", fmt (integralRound_Fmt 2) 5.0],
    [fmt (markdown_Fmt unit_Fmt) "**Pi** slice of *Pie*",
     fmt percentage_Fmt (1.0 / (2.0 * pi))],
    [atomShown "Many words",
     fmt (truncate_Fmt 15) "Are too much for this box"],
    [atomShown "Fewer words",
     fmt (truncate_Fmt 15) "will suffice"]
  ]

-- The [...]_FmtFld_Lg syntax.
empty_Bracket_FmtFld_Lg = empty_Bracket_Simple_Lg
cons_Bracket_FmtFld_Lg (ft, fld) =
  cons_Bracket_Simple_Lg (presentation_Pres ft fld, fieldName fld)

field plainText, plainText2, truncText, mdText : String
field roundFmtTwo, iRoundFmtFive, pctFmt : Double

-- Like formattedTextsGrid, but for tabular and rearranged a bit to
-- fit, for comparison.
tabularEquivalentFTG =
  tabular $ Just ([(unit_Fmt, plainText),
                   (round_Fmt 2, roundFmtTwo),
                   (integralRound_Fmt 5, iRoundFmtFive),
                   (unit_Fmt, plainText2),
                   (truncate_Fmt 15, truncText),
                   (markdown_Fmt unit_Fmt, mdText),
                   (percentage_Fmt, pctFmt)]_FmtFld_Lg)
  $ mem [{plainText = "Pi", roundFmtTwo = pi, iRoundFmtFive = pi},
         {plainText = "e", roundFmtTwo = exp 1.0, iRoundFmtFive = exp 1.0},
         {plainText = "just 5", roundFmtTwo = 5.0, iRoundFmtFive = 5.0}]
  ** mem [{plainText2 = "Many words", truncText = "Are too much for this box"},
          {plainText2 = "Fewer words", truncText = "will suffice"}]
  ** mem [{mdText = "**Pi** slice of *Pie*", pctFmt = 1.0 / (2.0 * pi)}]
