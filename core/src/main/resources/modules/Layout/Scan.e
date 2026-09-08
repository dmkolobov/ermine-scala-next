module Layout.Scan where

import Relation.Scan as S
import Function
import Layout.Report as L
import Vector as V
import Void using { type Bound; type Unbound }
import Primitive
import Layout.Presentation as P
import Layout.Column as C
import Layout.Legend as Lg

type Scan = Scan_S
type Legend = Legend_Lg

scan = fromRelation_S runner

runner : forall f z . RunScan_S List (Report_L f z)
runner = RunScan_S scanRelation_L

consume = consume_S
scanList = fromList_S
scanVector = fromVector_S
transform = transform_S
map_Scan = mapScan_S
filterK = filterK_S
filterV = filterV_S
mapK = mapK_S
mapV = mapV_S
sortScan = sort_S
sortK = sortK_S
sortV = sortV_S
pick_Scan = pick_S
pickBy = pickBy_S
pickK = pickK_S
pickByK = pickByK_S
deriveFromK = deriveFromK_S
updateK = updateK_S
-- Stage F3, ticket C5: `Relation.Scan` publishes fourteen combinators over a
-- `Scan`; this module used to re-export eleven of them, and the three below were
-- the ones it left out, for no reason anyone recorded -- `removeK` in particular
-- is the exact opposite of `pickK`, which IS here. `multiply` takes the runner,
-- like `groupBy`/`sumBy`/`count` do.
removeK = removeK_S
removeBy = removeBy_S
multiply = multiply_S runner
groupBy' = groupBy'_S runner
groupBy = groupBy_S runner
groupBy1 = groupBy1_S runner
groupBy1' = groupBy1'_S runner
sumBy' = sumBy'_S
sumBy = sumBy_S runner
avgBy' = avgBy'_S
avgBy = avgBy_S runner
count = count_S runner
count' = count'_S
keys = keys_C
legend = formatV_C
legend1 name op = formatK_C ([(op, name)]_Simple_Lg)
formatPercent op = formatV_C (percent_P op)
formatCurrency cur op = formatV_C (currency_P cur op)
reformatPercent op = reformatV_C (percent_P op)
reformaCurrency cur op = reformatV_C (currency_P cur op)
nestBy = drilldown_C

column = column_C

columns s f = runScan_L (const j)
  where j = consume (kvs -> map_V go kvs |> toList_V |> joinAll_C |> f |> columnTable_L) s
        go (k, v) = heading_C (val_L k) v

{-

-- simple use case
columns ' groupBy1 calculationId rel ' keys {ticker}

groupBy1 calculationId rel
|> mapK calculationName
|> pickK ["Portfolio Weight", "Benchmark Weight", "Active Weight"]
|> columns
|> keys {ticker} . formatV (percent_P value)

-- add a presentation
import Layout.Presentation as P
columns ' groupBy1 calculationId rel ' keys {ticker} . percent_P value

columns ' groupBy {startDate, endDate} rel ' keys {sector} . drilldown nodeId parentId
columns ' groupPeriods startDate endDate rel ' ...
-}
