module ChartsExample where

{-
To use, from REPL:

  >> import Environment.Dev
  Loading Environment.Dev
  Loaded one module (0.11 seconds)
  >> :load examples\ChartsExample.e
  Importing module 'ChartsExample' (0.73 seconds)
  >> render barChartExample

Also try:
  >> render lineTimeSeriesChart
  >> render barTimeSeriesChart
  >> render chartExample
-}

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

field calculationId : Int
field calculationLabel : Int
field endDate : Date
field groupingName : String
field label : String
field positionTypeId : Byte
field startDate : Date
field value : Nullable Double

field groupingId : Int
field parentGroupingId : Int
field xVal: Nullable Double

weightsTableLong = relation [
  { groupingName = "Information Technology",  value = Some 45.0},
  { groupingName = "Financials",              value = Some 30.0},
  { groupingName = "Consumer Staples",        value = Some 15.0},
  { groupingName = "Other",                   value = Some 10.0}
]

weightsTableLongDrilldown = relation [
  { groupingId = 1, parentGroupingId  = 0, groupingName = "Total",  value = Some 100.0},
  { groupingId = 10, parentGroupingId = 1, groupingName = "Infor[ma](http://ma.gov)tion Technology",  value = Some 45.0},
  { groupingId = 11, parentGroupingId = 10, groupingName = "IBM",  value = Some 25.0},
  { groupingId = 12, parentGroupingId = 10, groupingName = "Microsoft",  value = Some 20.0},
  { groupingId = 20, parentGroupingId = 1, groupingName = "Financials",              value = Some 45.0},
  { groupingId = 21, parentGroupingId = 20, groupingName = "Citi Group",              value = Some 22.5},
  { groupingId = 22, parentGroupingId = 20, groupingName = "Wells Fargo",              value = Some 22.5},
  { groupingId = 30, parentGroupingId = 1, groupingName = "__Consumer__ Staples",        value = Some 15.0},
  { groupingId = 40, parentGroupingId = 1, groupingName = "Other",                   value = Some 10.0}
]

-- Short chart verification blocked by bug with negative Double values in relation
weightsTableShort = relation [
  { groupingName = "Consumer Staples",        value = Some (neg 5.0)},
  { groupingName = "Information Technology",  value = Some (neg 15.0)},
  { groupingName = "Financials",              value = Some (neg 10.0)}
]

longWeightsChart = pieChart_K (pieTitle_O := "Portfolio Weight (Long)") groupingName value weightsTableLong
longWeightsDrilldownTable = drilldownTable Nothing groupingName parentGroupingId groupingId weightsTableLongDrilldown
longWeightsDrilldownChart = pieChart_K
  ([pieTitle_O := "Portfolio Weight (Long)",
    pieDrilldown_O := (parentGroupingId, groupingId)]_Opt)
  groupingName value weightsTableLongDrilldown
shortWeightsChart = pieChart_K (pieTitle_O := "Portfolio Weight (Short)") groupingName value weightsTableShort

-------------------------------------------------------------------------------------------------
-- Time Series Charts
-------------------------------------------------------------------------------------------------
simpleTable = relation [
  { label = "Price - Close - Monthly",  xVal = Some 10.0, value = Some 27.5},
  { label = "Price - Close - Monthly",  xVal = Some 20.0, value = Some 20.5},
  { label = "Price - Close - Monthly",  xVal = Some 30.0, value = Some 23.45}
]

timeSeriesCharacteristicsTable = relation [
  { label = "Price - Close - Monthly",  startDate = @2011/1/31, value = Some 27.5},
  { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 20.5},
  { label = "Price - Close - Monthly",  startDate = @2011/3/31, value = Some 23.45}
]

boxAndWhiskery = relation [
    { label = "Price - Close - Monthly",  startDate = @2011/1/31, value = Some 27.5}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 189.03098590704317}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 195.6114329740135}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 457.3316609272376}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 57.513032995500176}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 35.587309946241085}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 202.01614889924778}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 464.2765444557853}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 197.55873155622274}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 267.71271041803317}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 230.70780184067348}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 30.2825052516336}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 148.2957968200352}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 322.64375697059637}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 212.2550606254331}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 340.9132634453747}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 429.33166014643683}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 223.2155043864519}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 105.94267895549093}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 220.40983889370867}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 422.9216105489651}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 182.01062702854284}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 70.3415670004146}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 427.64144573625697}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 24.170800186451903}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 348.9295331704021}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 272.5894110830957}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 393.8149538371825}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 286.27622995830757}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 390.1098427974364}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 210.92081580425037}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 193.27254562490887}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 413.0850902095528}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 454.29900354049806}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 156.10858340751196}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 447.41852085030166}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 137.78240075990786}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 385.774535656653}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 146.7084702376079}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 280.28410427867124}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 366.263546919056}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 401.30606372867675}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 469.15695933115535}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 468.55820451212446}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 290.25949620587755}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 415.1128067339375}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 309.04193601407917}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 106.92278870415099}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 64.97337196683632}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 312.543267885154}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 331.84341446594544}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 82.35198580386914}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 160.3889130737115}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 210.77218799935105}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 186.89796240888836}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 485.3508404561734}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 347.1419817601033}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 190.34571574584413}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 31.574506764133147}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 270.2576171740433}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 308.1039970024375}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 491.12262694493}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 278.90438632609903}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 58.043672498203286}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 147.37684516266208}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 315.247270373359}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 164.12379025617287}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 19.527221981376734}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 31.958491484780314}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 432.8821012876295}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 408.2021386506023}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 55.92247303567184}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 262.1420599430808}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 121.99169294460724}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 23.544640895034874}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 28.706329781133114}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 175.14345666765513}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 15.967023682436261}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 152.4243735635042}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 217.55132022043568}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 67.47003522725896}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 330.3453102844181}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 197.97510365089389}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 174.27116975736928}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 126.499236362826}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 404.19760744466936}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 322.52332098536095}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 227.93503619446693}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 452.41132652055245}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 73.59547142456593}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 134.20711202366093}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 262.404421286008}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 7.0172898900180645}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 366.68016649085286}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 103.39351702289889}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 293.80374466354124}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 477.10790327713306}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 472.22566253692514}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 132.85034374867178}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 417.54640852073794}
, { label = "Price - Close - Monthly",  startDate = @2011/2/28, value = Some 230.78667271172503}
, { label = "Foo",  startDate = @2011/2/28, value = Some 449.68363968235536}
, { label = "Foo",  startDate = @2011/2/28, value = Some 24.369057836554592}
, { label = "Foo",  startDate = @2011/2/28, value = Some 342.08876102087777}
, { label = "Foo",  startDate = @2011/2/28, value = Some 270.6314099997702}
, { label = "Foo",  startDate = @2011/2/28, value = Some 133.66408721900044}
, { label = "Foo",  startDate = @2011/2/28, value = Some 469.9943891233949}
, { label = "Foo",  startDate = @2011/2/28, value = Some 449.20793017768244}
, { label = "Foo",  startDate = @2011/2/28, value = Some 447.0596257335175}
, { label = "Foo",  startDate = @2011/2/28, value = Some 227.19860373824804}
, { label = "Foo",  startDate = @2011/2/28, value = Some 267.93604553359444}
, { label = "Foo",  startDate = @2011/2/28, value = Some 27.71480606008081}
, { label = "Foo",  startDate = @2011/2/28, value = Some 386.4167281085035}
, { label = "Foo",  startDate = @2011/2/28, value = Some 232.55021127360433}
, { label = "Foo",  startDate = @2011/2/28, value = Some 124.46783840637576}
, { label = "Foo",  startDate = @2011/2/28, value = Some 160.4102248877912}
, { label = "Foo",  startDate = @2011/2/28, value = Some 394.59118155425}
, { label = "Foo",  startDate = @2011/2/28, value = Some 77.64550332829084}
, { label = "Foo",  startDate = @2011/2/28, value = Some 399.91004782308937}
, { label = "Foo",  startDate = @2011/2/28, value = Some 324.8621551561139}
, { label = "Foo",  startDate = @2011/2/28, value = Some 242.03624970919822}
, { label = "Foo",  startDate = @2011/2/28, value = Some 32.24107360564756}
, { label = "Foo",  startDate = @2011/2/28, value = Some 115.6134370589821}
, { label = "Foo",  startDate = @2011/2/28, value = Some 449.1838529289185}
, { label = "Foo",  startDate = @2011/2/28, value = Some 499.5078884386025}
, { label = "Foo",  startDate = @2011/2/28, value = Some 430.8293012003109}
, { label = "Foo",  startDate = @2011/2/28, value = Some 67.8009564061202}
, { label = "Foo",  startDate = @2011/2/28, value = Some 419.31919005512617}
, { label = "Foo",  startDate = @2011/2/28, value = Some 18.733638284138117}
, { label = "Foo",  startDate = @2011/2/28, value = Some 431.8746963627403}
, { label = "Foo",  startDate = @2011/2/28, value = Some 244.08433884512246}
, { label = "Foo",  startDate = @2011/2/28, value = Some 200.47783843400242}
, { label = "Foo",  startDate = @2011/2/28, value = Some 58.866476905465156}
, { label = "Foo",  startDate = @2011/2/28, value = Some 48.12442765370156}
, { label = "Foo",  startDate = @2011/2/28, value = Some 296.4638209303199}
, { label = "Foo",  startDate = @2011/2/28, value = Some 422.9792569661639}
, { label = "Foo",  startDate = @2011/2/28, value = Some 145.19793998951587}
, { label = "Foo",  startDate = @2011/2/28, value = Some 225.58214672794028}
, { label = "Foo",  startDate = @2011/2/28, value = Some 490.4145202010263}
, { label = "Foo",  startDate = @2011/2/28, value = Some 284.82707275816335}
, { label = "Foo",  startDate = @2011/2/28, value = Some 394.5847181500336}
, { label = "Foo",  startDate = @2011/2/28, value = Some 401.3942358996854}
, { label = "Foo",  startDate = @2011/2/28, value = Some 493.40045803589237}
, { label = "Foo",  startDate = @2011/2/28, value = Some 392.71504269462247}
, { label = "Foo",  startDate = @2011/2/28, value = Some 159.40207836470324}
, { label = "Foo",  startDate = @2011/2/28, value = Some 225.3062170661548}
, { label = "Foo",  startDate = @2011/2/28, value = Some 255.77598031105256}
, { label = "Foo",  startDate = @2011/2/28, value = Some 261.70629644704786}
, { label = "Foo",  startDate = @2011/2/28, value = Some 287.38168210685603}
, { label = "Foo",  startDate = @2011/2/28, value = Some 80.74954717363524}
, { label = "Foo",  startDate = @2011/2/28, value = Some 39.12890810476683}
, { label = "Bar",  startDate = @2011/2/28, value = Some 499.76680223872006}
, { label = "Bar",  startDate = @2011/2/28, value = Some 207.24786446792558}
, { label = "Bar",  startDate = @2011/2/28, value = Some 444.27767725303516}
, { label = "Bar",  startDate = @2011/2/28, value = Some 485.2917098152982}
, { label = "Bar",  startDate = @2011/2/28, value = Some 41.20995034554879}
, { label = "Bar",  startDate = @2011/2/28, value = Some 442.8789310377565}
, { label = "Bar",  startDate = @2011/2/28, value = Some 451.1531306827133}
, { label = "Bar",  startDate = @2011/2/28, value = Some 371.94087843673077}
, { label = "Bar",  startDate = @2011/2/28, value = Some 82.14440673367463}
, { label = "Bar",  startDate = @2011/2/28, value = Some 22.133998752334797}
, { label = "Bar",  startDate = @2011/2/28, value = Some 223.07675964007404}
, { label = "Bar",  startDate = @2011/2/28, value = Some 325.0223557903814}
, { label = "Bar",  startDate = @2011/2/28, value = Some 471.8625196079968}
, { label = "Bar",  startDate = @2011/2/28, value = Some 114.86412895875051}
, { label = "Bar",  startDate = @2011/2/28, value = Some 432.7170909171388}
, { label = "Bar",  startDate = @2011/2/28, value = Some 344.62397143247796}
, { label = "Bar",  startDate = @2011/2/28, value = Some 78.56099997383419}
, { label = "Bar",  startDate = @2011/2/28, value = Some 315.6752832855478}
, { label = "Bar",  startDate = @2011/2/28, value = Some 326.27698492170185}
, { label = "Bar",  startDate = @2011/2/28, value = Some 296.57370971889}
, { label = "Bar",  startDate = @2011/2/28, value = Some 97.34043826044794}
, { label = "Bar",  startDate = @2011/2/28, value = Some 20.47285571059281}
, { label = "Bar",  startDate = @2011/2/28, value = Some 463.89593578619593}
, { label = "Bar",  startDate = @2011/2/28, value = Some 354.34412127010836}
, { label = "Bar",  startDate = @2011/2/28, value = Some 83.75592352569102}
, { label = "Bar",  startDate = @2011/2/28, value = Some 254.36426433498713}
, { label = "Bar",  startDate = @2011/2/28, value = Some 187.56348362945369}
, { label = "Bar",  startDate = @2011/2/28, value = Some 404.4008335372463}
, { label = "Bar",  startDate = @2011/2/28, value = Some 182.5099533920067}
, { label = "Bar",  startDate = @2011/2/28, value = Some 221.70862493541264}
, { label = "Bar",  startDate = @2011/2/28, value = Some 190.93793867303611}
, { label = "Bar",  startDate = @2011/2/28, value = Some 100.7030934345586}
, { label = "Bar",  startDate = @2011/2/28, value = Some 328.75282175273463}
, { label = "Bar",  startDate = @2011/2/28, value = Some 23.669539598353786}
, { label = "Bar",  startDate = @2011/2/28, value = Some 457.55059279196564}
, { label = "Bar",  startDate = @2011/2/28, value = Some 43.70446573726454}
, { label = "Bar",  startDate = @2011/2/28, value = Some 371.01417812090386}
, { label = "Bar",  startDate = @2011/2/28, value = Some 181.59190474217337}
, { label = "Bar",  startDate = @2011/2/28, value = Some 152.1216967816045}
, { label = "Bar",  startDate = @2011/2/28, value = Some 353.58077078580146}
, { label = "Bar",  startDate = @2011/2/28, value = Some 27.887793954538225}
, { label = "Bar",  startDate = @2011/2/28, value = Some 161.81412348602052}
, { label = "Bar",  startDate = @2011/2/28, value = Some 96.02012029331308}
, { label = "Bar",  startDate = @2011/2/28, value = Some 271.04084322760957}
, { label = "Bar",  startDate = @2011/2/28, value = Some 111.47324020840283}
, { label = "Bar",  startDate = @2011/2/28, value = Some 342.22753119557666}
, { label = "Bar",  startDate = @2011/2/28, value = Some 190.1820324997882}
, { label = "Bar",  startDate = @2011/2/28, value = Some 487.90019067918206}
, { label = "Bar",  startDate = @2011/2/28, value = Some 172.5504095455946}
, { label = "Bar",  startDate = @2011/2/28, value = Some 20.92457753942257}
, { label = "Bar",  startDate = @2011/2/28, value = Some 437.4924244437822}
, { label = "Bar",  startDate = @2011/2/28, value = Some 18.02769667171147}
, { label = "Bar",  startDate = @2011/2/28, value = Some 420.202162366874}
, { label = "Bar",  startDate = @2011/2/28, value = Some 208.63500299099474}
, { label = "Bar",  startDate = @2011/2/28, value = Some 146.4216572675832}
, { label = "Bar",  startDate = @2011/2/28, value = Some 431.09903117491456}
, { label = "Bar",  startDate = @2011/2/28, value = Some 462.8855674694365}
, { label = "Bar",  startDate = @2011/2/28, value = Some 59.264876523131115}
, { label = "Bar",  startDate = @2011/2/28, value = Some 435.04036868318366}
, { label = "Bar",  startDate = @2011/2/28, value = Some 76.8376222260194}
, { label = "Bar",  startDate = @2011/2/28, value = Some 342.1876008171436}
, { label = "Bar",  startDate = @2011/2/28, value = Some 206.1189534484654}
, { label = "Bar",  startDate = @2011/2/28, value = Some 491.6147735711773}
, { label = "Bar",  startDate = @2011/2/28, value = Some 333.3512125907286}
, { label = "Bar",  startDate = @2011/2/28, value = Some 161.90908286276684}
, { label = "Bar",  startDate = @2011/2/28, value = Some 354.0883353286187}
, { label = "Bar",  startDate = @2011/2/28, value = Some 209.4066684062568}
, { label = "Bar",  startDate = @2011/2/28, value = Some 370.61219666127465}
, { label = "Bar",  startDate = @2011/2/28, value = Some 338.7359466675401}
, { label = "Bar",  startDate = @2011/2/28, value = Some 415.19795387248655}
, { label = "Bar",  startDate = @2011/2/28, value = Some 283.4908140032217}
, { label = "Bar",  startDate = @2011/2/28, value = Some 393.61061810503975}
, { label = "Bar",  startDate = @2011/2/28, value = Some 440.1246373213146}
, { label = "Bar",  startDate = @2011/2/28, value = Some 183.14245829892738}
, { label = "Bar",  startDate = @2011/2/28, value = Some 371.046077414427}
, { label = "Bar",  startDate = @2011/2/28, value = Some 106.70457531716183}
, { label = "Bar",  startDate = @2011/2/28, value = Some 177.2414614355733}
, { label = "Bar",  startDate = @2011/2/28, value = Some 152.40272068732077}
, { label = "Bar",  startDate = @2011/2/28, value = Some 330.3550298093245}
, { label = "Bar",  startDate = @2011/2/28, value = Some 476.00982805280233}
, { label = "Bar",  startDate = @2011/2/28, value = Some 160.00109049205565}
, { label = "Bar",  startDate = @2011/2/28, value = Some 173.00185954888545}
, { label = "Bar",  startDate = @2011/2/28, value = Some 115.2314742459189}
, { label = "Bar",  startDate = @2011/2/28, value = Some 240.91315580816703}
, { label = "Bar",  startDate = @2011/2/28, value = Some 45.97273658257286}
, { label = "Bar",  startDate = @2011/2/28, value = Some 315.7503322942484}
, { label = "Bar",  startDate = @2011/2/28, value = Some 232.46454731397415}
, { label = "Bar",  startDate = @2011/2/28, value = Some 476.4675678463661}
, { label = "Bar",  startDate = @2011/2/28, value = Some 92.02644740886872}
, { label = "Bar",  startDate = @2011/2/28, value = Some 398.98100235344504}
, { label = "Bar",  startDate = @2011/2/28, value = Some 57.6401941104312}
, { label = "Bar",  startDate = @2011/2/28, value = Some 323.71825126541773}
, { label = "Bar",  startDate = @2011/2/28, value = Some 336.11511004242965}
, { label = "Bar",  startDate = @2011/2/28, value = Some 268.6348800161252}
, { label = "Bar",  startDate = @2011/2/28, value = Some 98.26631044505727}
, { label = "Bar",  startDate = @2011/2/28, value = Some 196.6949536488158}
, { label = "Bar",  startDate = @2011/2/28, value = Some 350.65276471788405}
, { label = "Bar",  startDate = @2011/2/28, value = Some 70.68095013711115}
, { label = "Bar",  startDate = @2011/2/28, value = Some 455.1724488802497}
, { label = "Bar",  startDate = @2011/2/28, value = Some 459.10202976416144}
]

timeSeriesData = relation [
    { label = "MSFT", startDate = @2011/1/1, value = Some 0.2 }
  , { label = "GOOG", startDate = @2011/1/1, value = Some 0.1 }
  , { label = "C", startDate = @2011/1/1, value = Some 0.11 }

  , { label = "MSFT", startDate = @2011/2/5, value = Some 0.07 }
  , { label = "GOOG", startDate = @2011/2/5, value = Some 0.12 }
  , { label = "C", startDate = @2011/2/5, value = Some 0.13 }

  , { label = "MSFT", startDate = @2011/8/19, value = Some 0.09 }
  , { label = "GOOG", startDate = @2011/8/19, value = Some 0.19 }
  , { label = "C", startDate = @2011/8/23, value = Some 0.19 }
]




-- a few things:
--   * lower bound on y-axis is being ignored
--   * spacing between date markers is on strange boundaries, should use dates from the series, fall back to monthly frequency + tooltips if this is too many markers
scalingTest = chart_K
  ([yFormat_O := percentage_Fmt]_Opt)
  defaultScaled
  (scaled Ascending (Just (Some 0.05)) Nothing Linear)
  [line label startDate value timeSeriesData]

-- dateRangeAxisTest = chart_K
--   ([yFormat_O := percentage_Fmt]_Opt)
--   unscaledDateRange
--   defaultScaled
--   [line label (dateRange_Op startDate startDate) value timeSeriesData]

lineTimeSeriesChart =
  let
    title = Just "Price - Close - Monthly Characteristics"
    xlabel = Just (val "X Axis Label")
    ylabel = Just (val "Y Axis Label")
  in timeSeriesChart title xlabel ylabel line label startDate value timeSeriesCharacteristicsTable

-- boxAndWhiskersExample =
--   timeSeriesChart
--     (Just "Price - Close - Monthly Characteristics")
--     (Just $ val "X Axis Label")
--     (Just $ val "Y Axis Label")
--     boxAndWhiskers
--     label
--     startDate
--     value
--     boxAndWhiskery


barTimeSeriesChart =
  chart_K ([chartTitle_O := "Price - Close - Monthly Characteristics",
            xLabel_O := val "X Axis Label",
            yLabel_O := val "Y Axis Label"]_Opt)
    defaultScaled defaultScaled
    [bar label startDate value timeSeriesCharacteristicsTable]

chartExample = vflow [ lineTimeSeriesChart, tabular Nothing timeSeriesCharacteristicsTable]

simpleChart =
  let
    title = Just "Simple"
    xlabel = Just (val "X Axis Label")
    ylabel = Just (val "Y Axis Label")
  in timeSeriesChart title xlabel ylabel line label xVal value simpleTable

------------------------------------------------------------------------
-- Bar Chart
------------------------------------------------------------------------
groupValueTable = relation [
  { label = "Asset Allocation", groupingName = "Information Technology",  value = Some 0.2354 },
  { label = "Stock Selection",  groupingName = "Information Technology",  value = Some 0.124 },
  { label = "Interaction",      groupingName = "Information Technology",  value = Some 0.0854 },
  { label = "Total Effect",     groupingName = "Information Technology",  value = Some 0.4563 },

  { label = "Asset Allocation", groupingName = "Consumer Staples",  value = Some 0.1254 },
  { label = "Stock Selection",  groupingName = "Consumer Staples",  value = Some 0.144 },
  { label = "Interaction",      groupingName = "Consumer Staples",  value = Some 0.0454 },
  { label = "Total Effect",     groupingName = "Consumer Staples",  value = Some 0.3563 },

  { label = "Asset Allocation", groupingName = "Energy",  value = Some 0.1054 },
  { label = "Stock Selection",  groupingName = "Energy",  value = Some 0.2344 },
  { label = "Interaction",      groupingName = "Energy",  value = Some 0.0154 },
  { label = "Total Effect",     groupingName = "Energy",  value = Some 0.3963 }
]

multiSeriesBar = chart_K
  ([chartTitle_O := "Blah",
    yFormat_O := percentage_Fmt,
    yDirection_O := Horizontal]_Opt)
  defaultUnscaled
  defaultScaled
  -- [line label groupingName value (groupValueTable |> [| label == "Total Effect" |]),
  [bar label groupingName value groupValueTable]

barChartExample = chart_K
  ([chartTitle_O := "Sector Cumulative Attribution"]_Opt)
  defaultUnscaled defaultScaled
  [categoryTickLabels [({groupingName = "Information Technology"},
                        {groupingName = "IT"})]
                      bar label groupingName value groupValueTable]

longWeightsDrilldownBarChart =
  drilldownBarChart_K
    defaultUnscaled defaultScaled
    ([titleB_O := "Portfolio Weight (Long)"
     ,yDirectionB_O := Horizontal
     ,xTicksB_O := [({groupingName = "Infor[ma](http://ma.gov)tion Technology"},
                     {groupingName = "IT"})]]_Opt)
    groupingName
    value
    parentGroupingId
    groupingId
    weightsTableLongDrilldown

------------------------------------------------------------------------
-- Stacked Charts
------------------------------------------------------------------------
stacked1Table = relation [
  { label = "Asset Allocation Effect", groupingName = "12/31/10 - 01/31/11",  value = Some 50.0 },
  { label = "Asset Allocation Effect", groupingName = "01/31/11 - 02/28/11",  value = Some 142.5 },
  { label = "Asset Allocation Effect", groupingName = "02/28/11 - 03/31/11",  value = Some 60.0 }
]

dateRangeBarChart opts s x y r =
    chart_K opts
      (unscaled Ascending)
      defaultScaled
      [bar s x y r]

stacked1Bar =
  dateRangeBarChart
    ([chartTitle_O := "Factor Return v Asset Allocation Effect"]_Opt)
    label
    groupingName
    value
    stacked1Table

stacked2Table = relation [
  { label = "Factor Return", groupingName = "12/31/10 - 01/31/11",  value = Some 50.0 },
  { label = "Factor Return", groupingName = "01/31/11 - 02/28/11",  value = Some 125.0 },
  { label = "Factor Return", groupingName = "02/28/11 - 03/31/11",  value = Some 77.0 }
]

stackedPair opts s x y r1 r2=
    chart_K opts
      (unscaled Ascending)
      defaultScaled
      [bar s x y r1, line s x y r2]

stackedGuy =
  stackedPair
    ([chartTitle_O := "Factor Return v Asset Allocation Effect"]_Opt)
    label
    groupingName
    value
    stacked1Table
    stacked2Table
