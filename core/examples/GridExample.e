module GridExample where
 
import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Presentation as Pres
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Ord using lt
import Relation.Op as Op
import DateRange as DR

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
      (unscaled $ Right ltStringDateRange_DR)
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
