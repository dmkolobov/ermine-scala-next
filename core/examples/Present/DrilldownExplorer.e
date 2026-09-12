module Present.DrilldownExplorer where

{- A THREE-LEVEL DRILLDOWN with a control panel: company to division to unit to
   team, with the level, the region and the measure all chosen by SELECTORS.

   Fact: orgNodes (17 fields: nodeId, nodeLabel, nodeKind, orgId, orgParent,
         unitId, unitParent, teamId, teamParent, headcount, budgetAmt,
         actualAmt, varianceAmt, regionName, managerName, openRoles,
         attritionPct)

   WHY THIS FILE EXISTS. `DrilldownList` -- the type that says how a grid nests --
   had NO example anywhere, and the whole selector API (`Layout.Report`'s
   `dropdown`, `radioButton`, `slider`, `checkBox`, `stringInput`,
   `stringAreaInput`, `intInput`, `Selector`, `Signal`, `Syntax.Selector`,
   `Layout.Report.SelectorMode`) had none either, in a repository whose README
   says interactivity is the point of the writers.

   TWO WAYS TO NEST, and the difference matters:

     drilldownTable  ONE (parent, child) pair. Every row is identified the same
                     way, so the tree is homogeneous: a manager chain, a bill of
                     materials, a chart of accounts.

     drilldownTable2 A `DrilldownList` -- one (parent, child) pair PER LEVEL,
                     plus a second relation naming the ROOTS. Each level may be
                     identified by its own pair of columns, so the tree is
                     heterogeneous: divisions have division ids, units have unit
                     ids, teams have team ids, and none of them share a keyspace.
                     `DrilldownList`'s `cons_Bracket` carries
                     `rout <- (f1, f2, r)` -- the PARTITION, since stage S3b
                     (2026-09-11) -- which is how it accumulates one row out of
                     the pairs. It used to carry `Has rout f1`, `Has rout f2`
                     and `Has rout r`, which asserted nothing at all:
                     `DrilldownList.e` imports neither `Constraint` nor
                     `Prelude`, so `Has` there was an ordinary implicitly
                     quantified type VARIABLE, and even in scope `Has` gives
                     membership where the body's two `append`s need
                     DISJOINTNESS (`SIG-1-SURVEY.md` item c3).

   WHAT A SELECTOR IS. `Selector f z a` is an EVENT plus a SIGNAL:

       data Selector f z a = Selector (SelectorEvent z) ((a -> Report f z) -> Report f z)

   The signal is a continuation, which is why every selector combinator has the
   shape `... -> (Report f z -> Selector f z a -> Report f z) -> Report f z`: it
   hands you the widget AND the value stream, and you decide where each goes.
   `using` re-renders a region when the event fires; `zipSelector` (`***`) pairs
   two streams and ORs their events; `Syntax.Selector` gives the applicative, so
   four independent controls become one `Selector f z (a, b, c, d)`.

   In production these become JS widgets in the browser and the report is
   re-evaluated server-side -- `tracker/JSON-API-DESIGN.md`. Nothing here can be
   clicked from `bin/ermine`; what CAN be checked, and is, is that the value the
   widget produces is the type the report consumes.

   SHAPES EXERCISED
     * `nestedOf` / `drilldownOf` from `Helpers.e`: `v <- (label, o)` and
       `Has r r1` over a 17-column row.
     * A THREE-element `DrilldownList` over three disjoint id pairs.
     * `dropdown`, `radioButton`, `slider`, `checkBox'`, `stringInput`,
       `stringAreaInput`, `intInput` -- every widget the stdlib has.
     * `Syntax.Selector`'s `<$>` / `<*>` composing four selectors into one.
     * `zipSelector` (`***`), `mapSelector`, `unitSelector`, `sequenceSelector`
       and `makeSelectors`.
     * `on` and `live`: an explicitly-supplied event rather than the selector's
       own.
     * `Layout.Report.SelectorMode`'s six constructors written out and matched
       on, so a reader can see which stdlib combinator produces which widget;
       and `widget`, the escape hatch.
     * `drilldownPieChart` and `drilldownBarChart_K` -- the two drilldown CHARTS.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/DrilldownExplorer.e
     >> explorer
     >> teamTree
     >> orgRoots

   There is no `render`; evaluate the report and the relations. See
   `tracker/loopmodel/E4-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Color
import Layout.Magnitude
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import DrilldownList as DDL
import Syntax.Selector as Sel
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Sort as Sort
import Syntax.Relation
import Syntax.List
import Present.Helpers

field nodeId, orgId, orgParent, unitId, unitParent, teamId, teamParent : Int
field headcount, openRoles : Int
field nodeLabel, nodeKind, regionName, managerName : String
field budgetAmt, actualAmt, varianceAmt, attritionPct : Double

field budgetM, actualM : Double

-- ------------------------------------------------------------- the fact table

-- Seventeen columns, eighteen nodes: one company, three divisions, five units,
-- nine teams. Each LEVEL is identified by its own pair of columns and carries a
-- zero in the other two pairs -- which is exactly the situation `DrilldownList`
-- exists for.
orgNodes : [ nodeId, nodeLabel, nodeKind, orgId, orgParent, unitId, unitParent
           , teamId, teamParent, headcount, budgetAmt, actualAmt, varianceAmt
           , regionName, managerName, openRoles, attritionPct ]
orgNodes = relation [
  { nodeId = 1, nodeLabel = "Global", nodeKind = "Company", orgId = 1, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 0, teamParent = 0, headcount = 412,
    budgetAmt = 41200000.0, actualAmt = 42380000.0, varianceAmt = 1180000.0, regionName = "Global",
    managerName = "c.eze", openRoles = 18, attritionPct = 0.0940 },
  { nodeId = 2, nodeLabel = "Americas", nodeKind = "Division", orgId = 2, orgParent = 1,
    unitId = 0, unitParent = 0, teamId = 0, teamParent = 0, headcount = 168,
    budgetAmt = 17400000.0, actualAmt = 18110000.0, varianceAmt = 710000.0, regionName = "AMER",
    managerName = "r.alvarez", openRoles = 7, attritionPct = 0.1010 },
  { nodeId = 3, nodeLabel = "EMEA", nodeKind = "Division", orgId = 3, orgParent = 1,
    unitId = 0, unitParent = 0, teamId = 0, teamParent = 0, headcount = 141,
    budgetAmt = 14100000.0, actualAmt = 14020000.0, varianceAmt = -80000.0, regionName = "EMEA",
    managerName = "k.baumann", openRoles = 6, attritionPct = 0.0820 },
  { nodeId = 4, nodeLabel = "APAC", nodeKind = "Division", orgId = 4, orgParent = 1,
    unitId = 0, unitParent = 0, teamId = 0, teamParent = 0, headcount = 103,
    budgetAmt = 9700000.0, actualAmt = 10250000.0, varianceAmt = 550000.0, regionName = "APAC",
    managerName = "y.tanaka", openRoles = 5, attritionPct = 0.1120 },
  { nodeId = 5, nodeLabel = "AMER Engineering", nodeKind = "Unit", orgId = 0, orgParent = 0,
    unitId = 21, unitParent = 2, teamId = 0, teamParent = 0, headcount = 92,
    budgetAmt = 10400000.0, actualAmt = 10920000.0, varianceAmt = 520000.0, regionName = "AMER",
    managerName = "d.chen", openRoles = 4, attritionPct = 0.0870 },
  { nodeId = 6, nodeLabel = "AMER Commercial", nodeKind = "Unit", orgId = 0, orgParent = 0,
    unitId = 22, unitParent = 2, teamId = 0, teamParent = 0, headcount = 76,
    budgetAmt = 7000000.0, actualAmt = 7190000.0, varianceAmt = 190000.0, regionName = "AMER",
    managerName = "s.park", openRoles = 3, attritionPct = 0.1180 },
  { nodeId = 7, nodeLabel = "EMEA Engineering", nodeKind = "Unit", orgId = 0, orgParent = 0,
    unitId = 31, unitParent = 3, teamId = 0, teamParent = 0, headcount = 78,
    budgetAmt = 8100000.0, actualAmt = 7980000.0, varianceAmt = -120000.0, regionName = "EMEA",
    managerName = "l.dubois", openRoles = 3, attritionPct = 0.0750 },
  { nodeId = 8, nodeLabel = "EMEA Commercial", nodeKind = "Unit", orgId = 0, orgParent = 0,
    unitId = 32, unitParent = 3, teamId = 0, teamParent = 0, headcount = 63,
    budgetAmt = 6000000.0, actualAmt = 6040000.0, varianceAmt = 40000.0, regionName = "EMEA",
    managerName = "s.okonkwo", openRoles = 3, attritionPct = 0.0900 },
  { nodeId = 9, nodeLabel = "APAC Engineering", nodeKind = "Unit", orgId = 0, orgParent = 0,
    unitId = 41, unitParent = 4, teamId = 0, teamParent = 0, headcount = 61,
    budgetAmt = 5900000.0, actualAmt = 6180000.0, varianceAmt = 280000.0, regionName = "APAC",
    managerName = "h.kim", openRoles = 3, attritionPct = 0.1210 },
  { nodeId = 10, nodeLabel = "Platform", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 211, teamParent = 21, headcount = 34,
    budgetAmt = 4100000.0, actualAmt = 4330000.0, varianceAmt = 230000.0, regionName = "AMER",
    managerName = "d.chen", openRoles = 2, attritionPct = 0.0790 },
  { nodeId = 11, nodeLabel = "Data", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 212, teamParent = 21, headcount = 31,
    budgetAmt = 3600000.0, actualAmt = 3710000.0, varianceAmt = 110000.0, regionName = "AMER",
    managerName = "n.osei", openRoles = 1, attritionPct = 0.0960 },
  { nodeId = 12, nodeLabel = "Mobile", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 213, teamParent = 21, headcount = 27,
    budgetAmt = 2700000.0, actualAmt = 2880000.0, varianceAmt = 180000.0, regionName = "AMER",
    managerName = "j.wu", openRoles = 1, attritionPct = 0.0890 },
  { nodeId = 13, nodeLabel = "Field sales", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 221, teamParent = 22, headcount = 44,
    budgetAmt = 4200000.0, actualAmt = 4310000.0, varianceAmt = 110000.0, regionName = "AMER",
    managerName = "s.park", openRoles = 2, attritionPct = 0.1260 },
  { nodeId = 14, nodeLabel = "Inside sales", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 222, teamParent = 22, headcount = 32,
    budgetAmt = 2800000.0, actualAmt = 2880000.0, varianceAmt = 80000.0, regionName = "AMER",
    managerName = "t.ibarra", openRoles = 1, attritionPct = 0.1080 },
  { nodeId = 15, nodeLabel = "Core services", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 311, teamParent = 31, headcount = 41,
    budgetAmt = 4300000.0, actualAmt = 4210000.0, varianceAmt = -90000.0, regionName = "EMEA",
    managerName = "l.dubois", openRoles = 2, attritionPct = 0.0710 },
  { nodeId = 16, nodeLabel = "Integrations", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 312, teamParent = 31, headcount = 37,
    budgetAmt = 3800000.0, actualAmt = 3770000.0, varianceAmt = -30000.0, regionName = "EMEA",
    managerName = "b.ferreira", openRoles = 1, attritionPct = 0.0800 },
  { nodeId = 17, nodeLabel = "Partner sales", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 321, teamParent = 32, headcount = 35,
    budgetAmt = 3300000.0, actualAmt = 3350000.0, varianceAmt = 50000.0, regionName = "EMEA",
    managerName = "s.okonkwo", openRoles = 2, attritionPct = 0.0930 },
  { nodeId = 18, nodeLabel = "Runtime", nodeKind = "Team", orgId = 0, orgParent = 0,
    unitId = 0, unitParent = 0, teamId = 411, teamParent = 41, headcount = 33,
    budgetAmt = 3200000.0, actualAmt = 3390000.0, varianceAmt = 190000.0, regionName = "APAC",
    managerName = "h.kim", openRoles = 2, attritionPct = 0.1180 }]

-- The roots of the forest: the one company node. It must have the SAME row as
-- the fact relation `drilldownTable2` scans, so it is taken from the scaled one.
orgRoots = scaledNodes |> filterEq nodeKind "Company"

-- Amounts in millions, so the grid is readable.
scaledNodes =
     orgNodes
  |> combine_Op (scaledBy 1000000.0 budgetAmt) budgetM
  |> combine_Op (scaledBy 1000000.0 actualAmt) actualM
  |> except { budgetAmt, actualAmt, varianceAmt }

-- ================================================== 1. the homogeneous drilldown

-- ONE pair. `orgParent` / `orgId` nests divisions under the company; the unit
-- and team rows have zeros there and simply do not appear.
divisionLegend : Legend_Lg (| nodeLabel, nodeKind, regionName, managerName
                            , headcount, openRoles, budgetM, actualM, attritionPct |)
divisionLegend =
  withFormats ([ (nodeLabel,   "Node")    ^ 0
               , (nodeKind,    "Kind")    ^ 1
               , (regionName,  "Region")  ^ 2
               , (managerName, "Manager") ^ 3 ]_Sorted_Lg)
              (round_Fmt 2)
              { headcount, openRoles, budgetM, actualM, attritionPct }

divisionTree =
  drilldownOf divisionLegend nodeLabel orgParent orgId
              (scaledNodes # { nodeLabel, nodeKind, regionName, managerName
                             , headcount, openRoles, budgetM, actualM
                             , attritionPct, orgParent, orgId })

-- ================================================ 2. the heterogeneous drilldown

-- THREE pairs, one per level. `[...]_DDL` is `DrilldownList`'s bracket syntax;
-- each `cons` asks for `rout <- (f1, f2, r)`, so the list's own row is the
-- DISJOINT union of all six columns -- which these three pairs are.
orgLevels : DrilldownList_DDL (| orgParent, orgId, unitParent, unitId
                                , teamParent, teamId |)
orgLevels = [ (orgParent,  orgId)
            , (unitParent, unitId)
            , (teamParent, teamId) ]_DDL

teamTree =
  nestedOf divisionLegend nodeLabel orgLevels scaledNodes orgRoots

-- ==================================================== 3. every widget there is

-- A `dropdown` over the four regions. The continuation receives the WIDGET and
-- the SELECTOR; `using` re-renders its argument each time the event fires.
regionPicker k = dropdown id "Global" ["Global", "AMER", "EMEA", "APAC"] k

-- A `radioButton` over the level to show, and a `slider` over a headcount
-- floor. Both are `simpleSelector` at a different `SelectorMode`; the mode is
-- the ONLY difference, which is why they share a signature.
levelPicker k = radioButton id "Division" ["Division", "Unit", "Team"] k
floorPicker k = slider toString 0 [0, 25, 50, 100] k

-- A checkbox, a text box, a multi-line text box and a parsed integer box.
teamsToggle k = checkBox' "Include teams" True k
nameFilter  k = stringInput "" k
noteBox     k = stringAreaInput "" k
topNPicker  k = intInput 5 k

-- ---------------------------------------------------- composing the selectors

-- `Syntax.Selector` is the applicative over `Selector f z`. Four independent
-- widgets, four independent event streams, ONE value: `<*>` ors the events and
-- zips the signals, so the report below re-renders when ANY of the four moves.
controls kont =
  regionPicker  $ regionUI region ->
  levelPicker   $ levelUI  level  ->
  floorPicker   $ floorUI  floor  ->
  teamsToggle   $ teamsUI  teams  ->
    kont (vflow [ hflow [ text "Region ", regionUI, text "  Level ", levelUI ]
                , hflow [ text "Headcount at least ", floorUI, text "  ", teamsUI ] ])
         ((r l f t -> (r, l, f, t)) <$>_Sel region <*>_Sel level
                                                   <*>_Sel floor
                                                   <*>_Sel teams)

-- The same thing with the primitive combinators, for comparison: `***` is
-- `zipSelector`, and `mapSelector` is the functor.
controlsPrimitive kont =
  regionPicker $ regionUI region ->
  levelPicker  $ levelUI  level  ->
    kont (hflow [regionUI, levelUI])
         (mapSelector ((r, l) -> r ++_String " / " ++_String l) (region ***  level))

-- `unitSelector` is `pure`: a selector that never fires and always yields.
alwaysGlobal = unitSelector "Global"

-- `sequenceSelector` turns a LIST of selectors into a selector of a list;
-- `makeSelectors` builds that list from a list of defaults, one widget each,
-- and flows the widgets vertically. Note the constraint the signature imposes:
-- every widget must yield the SAME type as the list element it was built from,
-- so this is a row of THREE dropdowns over the same option set, not a row of
-- mixed controls. A mixed row is `<*>`, above.
levelRow kont =
  makeSelectors (d -> dropdown id d ["Division", "Unit", "Team"])
                ["Division", "Unit", "Team"] kont

-- `on` supplies the event explicitly rather than taking the selector's own;
-- `live` is the event that has already fired, so the region below is rendered
-- once at load and then whenever the region changes.
regionOnLoad kont =
  regionPicker $ ui sel -> vflow [ ui, on live sel kont ]

-- ------------------------------------------- what the six widgets actually are

-- `Layout.Report.SelectorMode` is the type the writer switches on. Every
-- combinator above is `simpleSelector` at one of these six, and the mode is the
-- ONLY difference between `dropdown`, `radioButton` and `slider` -- which is why
-- they share a signature. The stdlib's `selector` is private, so these
-- constructors cannot be passed to it from here; they can be named, matched on
-- and listed, which is what a reader needs in order to know what exists.
allModes : List SelectorMode
allModes = [ DropDown, RadioButton, Slider, TextBox, CheckBox, TextArea ]

modeName : SelectorMode -> String
modeName DropDown    = "DropDown"
modeName RadioButton = "RadioButton"
modeName Slider      = "Slider"
modeName TextBox     = "TextBox"
modeName CheckBox    = "CheckBox"
modeName TextArea    = "TextArea"

-- Which combinator reaches which mode (`Layout/Report.e`, the private
-- `simpleSelector` / `input_` block).
modeUser : SelectorMode -> String
modeUser DropDown    = "dropdown, dropdownLateBinding"
modeUser RadioButton = "radioButton, radioButtonLateBinding"
modeUser Slider      = "slider, sliderLateBinding"
modeUser TextBox     = "input, stringInput, intInput, parseInput"
modeUser CheckBox    = "checkBox, checkBox'"
modeUser TextArea    = "stringAreaInput (via inputAreaW, not via selector)"

modeTable = valueGrid (map (m -> (modeName m, textNoMarkdown (modeUser m))) allModes)

-- `widget` is the escape hatch: a value, a view of it, and a controller that can
-- push a new value. Nothing in the stdlib uses it; it is how a writer-specific
-- control is wired in.
counter = widget 0 (n -> text (toString n))
                   (n push -> button "increment" (b _ -> hflow [b, push (n + 1)]))

-- ---------------------------------------------------------- the filtered views

atLeast n r = r |> filter_Pred (headcount >=_Pred prim_Op n)
inRegion  s r = if (s == "Global") r (r |> filterEq regionName s)
ofKind    s r = r |> filterEq nodeKind s

selected region level floor teams =
  scaledNodes |> inRegion region |> atLeast floor
              |> (r -> if teams r (r |> filter_Pred (not_Pred (nodeKind ==_Pred prim_Op "Team"))))
              |> (r -> if (level == "Division") (ofKind "Division" r) r)

-- ============================================================ 4. the drilldown charts

-- `drilldownPieChart`: click a slice and the chart re-plots the children of
-- that node. The parent/child pair is the same `(orgParent, orgId)` the grid
-- nests on, which is the point -- one hierarchy, two presentations.
divisionPie =
  pieChart_K ([ pieTitle_O := "Budget by division ($m)"
              , pieDrilldown_O := (orgParent, orgId) ]_Opt)
             nodeLabel (round_Pres 2 budgetM)
             (scaledNodes # { nodeLabel, budgetM, orgParent, orgId })

-- `drilldownBarChart_K` takes the two axes explicitly, then the options, then
-- the category presentation, the value presentation and the two id columns.
divisionBars =
  drilldownBarChart_K
    (unscaled Ascending_Sort) defaultScaled
    ([ titleB_O := "Actual by division ($m)"
     , yDirectionB_O := Horizontal ]_Opt)
    nodeLabel (round_Pres 2 actualM) orgParent orgId
    (scaledNodes # { nodeLabel, actualM, orgParent, orgId })

-- ==================================================================== the page

explorer = controls $ panelUI picks ->
  vflow [
    h2 "Organisation explorer",
    box (pad2 panelUI),
    vstrut,
    using picks ((region, level, floor, teams) ->
      vflow [ h3 ("Showing " ++_String level ++_String " in " ++_String region)
            , tabular_K ([tabLegend_O := divisionLegend]_Opt)
                        (selected region level floor teams
                           # { nodeLabel, nodeKind, regionName, managerName
                             , headcount, openRoles, budgetM, actualM
                             , attritionPct }) ]),
    vstrut,
    h3 "The whole tree, nested three levels deep",
    teamTree,
    h3 "Divisions only, one parent/child pair",
    divisionTree,
    h3 "The same hierarchy as charts",
    hspan [ panel "Budget" divisionPie, panel "Actual" divisionBars ],
    vstrut,
    h3 "The six selector modes, and which combinator reaches each",
    modeTable
  ]
