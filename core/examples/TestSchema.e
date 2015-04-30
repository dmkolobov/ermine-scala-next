module TestSchema where

import Prelude
import Layout
import Field

field Timestamp: Date
field Label: String
field Value: Double

field CalculationID: Int
field DateRangeID: Int
field LSN: Int
field GroupingID: Int
field ReportInstanceID: String
field ParentGroupingID: Int
field GroupingName: String
field ParentDateRangeID: Int
field StartDate: Date
field EndDate: Date
table DateRange: [DateRangeID, ReportInstanceID, ParentDateRangeID, StartDate, EndDate]
table Grouping: [GroupingID, ReportInstanceID, ParentGroupingID, GroupingName]
table DateRangeDoubles: [CalculationID, DateRangeID, GroupingID, LSN, ReportInstanceID, Value]

drd = [
  { DateRangeID = 1, Value = 50.0  },
  { DateRangeID = 2, Value = 100.0 },
  { DateRangeID = 3, Value = 150.0 }
  ]

pieChartData = [
  { GroupingName = "MSFT", Value = 25.0 },
  { GroupingName = "GOOG", Value = 21.0 },
  { GroupingName = "C", Value = 54.0 }
]

googChart = join (join (rename EndDate Timestamp DateRange) ( [{Label = "GOOG"}] )) drd #
            { Value, Label, Timestamp }

t1 = tabular DateRangeDoubles
t2 = timeSeriesChart Nothing (Just "Closing price") (Just "USD") LineChart Label Timestamp Value googChart
t2Box = timeSeriesChart Nothing (Just "Closing price") (Just "USD") BoxAndWhiskersChart Label Timestamp Value googChart
t3 = pieChart "Percentages per date range" GroupingName Value pieChartData
t4 = border (Just t3) (Just t1) (Just t2) (Just t4) Nothing

exampleBorder = border Nothing Nothing Nothing (Just $ atom "k") (Just $ atom "train")

tabbedExample = tabbed [
  ("Some important tabular data", t1), ("Pimp time series chart", t2), ("Box and Whiskers, y'all", t2Box), ("A pie chart", t3) ]

tableAndChart = hspan [(Just 3, t1), (Just 2, t2)]

atomReport = (vspan . unweighted) [ atom "Important heading!", tableAndChart ]

exampleFlow = vflow [hflow [atom "Foo", atom "Bar"], hflow [atom "Baz", atom "Qux"]]

example2 = javaFX (Table (relation# DateRangeDoubles))
example3 = javaFX tableAndChart
example4 = javaFX atomReport
example5 = javaFX tabbedExample
example6 = javaFX t4
example7 = javaFX exampleBorder
example8 = javaFX exampleFlow

e = unsafePerformIO example5
