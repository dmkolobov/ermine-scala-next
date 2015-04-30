module GroupBy where

import Prelude
import Layout.Scan
import Layout.Legend as Lg
import Layout.Presentation as P

field value : Double
field ticker : String
field calculationId : String

calcs = relation [
    { ticker = "MSFT", calculationId = "Returns", value = 0.2 }
  , { ticker = "MSFT", calculationId = "Portfolio Weight",  value = 0.4 }
  , { ticker = "MSFT", calculationId = "Benchmark Weight",  value = 0.4 }
  , { ticker = "GOOG", calculationId = "Portfolio Weight", value = 0.3 }
  , { ticker = "GOOG", calculationId = "Benchmark Weight", value = 0.3 }
  , { ticker = "GOOG", calculationId = "Returns", value = 0.1 }
  , { ticker = "C", calculationId = "Portfolio Weight", value = 0.3 }
  , { ticker = "C", calculationId = "Benchmark Weight", value = 0.3 }
  , { ticker = "C", calculationId = "Returns", value = 0.1 }
  , { ticker = "AAPL", calculationId = "Portfolio Weight", value = 0.3 }
  , { ticker = "AAPL", calculationId = "Benchmark Weight", value = 0.3 }
  , { ticker = "AAPL", calculationId = "Returns", value = 0.1 }
  , { ticker = "GE", calculationId = "Portfolio Weight", value = 0.3 }
  , { ticker = "GE", calculationId = "Benchmark Weight", value = 0.3 }
  , { ticker = "GE", calculationId = "Returns", value = 0.1 }
]

ex1 = groupBy1 calculationId calcs
   |> mapV column
   |> columns '
      keys { ticker }

ex2 = groupBy1 calculationId calcs
   |> mapV column
   |> pickK ["Portfolio Weight", "Returns"]
   |> columns '
      legend1 "Ticker" ticker

