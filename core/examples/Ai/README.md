# `core/examples/Ai` — ten reporting examples

Ten self-contained Ermine reports over different subject matter, plus one shared
library (`Common.e`). They exist to give the corpus something wider than the
handful of examples that were here before: the pre-existing `core/examples` tree
contains only **12 row-partition constraints across 9 signatures** in total,
which is not much with which to exercise the row machinery or catch a regression
in it.

What these add, precisely — worth knowing before you use them as a test corpus:

- **The reports are concrete and leave no residual constraints.** Each one
  operates on fully-determined relations, so the solver discharges everything and
  the emitted `.ei` carries no partition constraint. That is the same pattern as
  the stdlib, where 105 of 129 modules produce zero.
- **They do real solver work while checking**, 0.4–1.3s each, which is where
  their value as a regression corpus lies: a change that breaks row inference
  will show up here as a slowdown or a failure to check.
- **`Common.e` is where the row polymorphism lives**, contributing 8 partition
  constraints across 4 signatures — including `withColumn`, whose signature
  constrains the same row variable twice, the shape the solver finds hardest.

Every file in this directory type-checks. Load the library first — the examples
import it:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
    bin/ermine core/examples/Ai/Common.e $(ls core/examples/Ai/*.e | grep -v 'Common\.e')

or, from the REPL, `:load core/examples/Ai/Common.e` then the example you want,
then `render <theReport>`.

## The examples

The three in bold are the date-range-tree ones.

| file | subject | what it exercises |
|---|---|---|
| `TelescopeTime.e` | observatory time | 4-way star join; heterogeneous leaves (star / galaxy / planet); nested conditional `displayName`; programme drilldown; pie + grid |
| `BatteryCycling.e` | cell capacity history | time series on a date axis; derived retention column; two renames; `timeSeriesChart` |
| `SalesByRegion.e` | orders | 4-way star join; geography rollup World → continent → country → region; direct-vs-partner labelling |
| `SupplyChainInventory.e` | warehouse stock | leaves are units / cases / pallets / containers; three-level conditional label with a hazmat override; 4-level location tree |
| `HeadcountPlan.e` | org chart | leaves are employee / contractor / open requisition — only one has a person's name; org drilldown |
| `ClinicalTrial.e` | trial data | key-value ("soft") schema for genuinely heterogeneous measurements; `softRelation` + `keyValueTabular`; per-key presentation and ordering |
| **`FiscalCalendar.e`** | fiscal calendar | **a tree of date ranges** (FY → 4 quarters → 3 months → days) and **table columns grouped by it**, with rows nested by a product hierarchy |
| **`RevenueByPeriod.e`** | bookings | star schema whose time dimension is a date-range tree rather than a date column, so one fact table reports at year / quarter / month |
| `IncidentSeverity.e` | service incidents | severity hierarchy drilldown; `[...]_Sorted_Lg` legend pinning column order; stacked bar |
| **`GridTelemetry.e`** | grid sensors | date-range tree down to **days**; heterogeneous metrics (MW / °C / status) where the unit belongs in the label |

## Trees: grouping and date ranges are the same shape

A grouping hierarchy and a calendar are both just parent/child id columns, and
the same helpers work on both, each example naming its pair for what it groups:

    programmeId   / parentProgrammeId     -- also territories, org units, bands
    dateRangeId   / parentDateRangeId     -- FY2011 → Q1 → Jan → 1 Jan

`FiscalCalendar.e` uses both at once: rows drill down the product hierarchy while
columns are grouped by the date-range tree.

## `Common.e` — and a warning worth reading before you extend it

`Common.e` holds the row-polymorphic helpers: `treeTable`, `childrenOf`,
`nodesOfKind`, `withColumn`. Each names only the columns it needs and carries the
rest as a row variable, which is what the partition constraints in its signatures
say.

**The non-obvious part**, and the reason `Common.e` is shaped the way it is: a
generic helper is only useful if its *call sites* check. An explicit signature
makes the definition cheap, but every caller still has to solve the instantiated
constraints. Measured on this repo, on one small module:

| form | time |
|---|---|
| inline `combine_Op (if_Op p a b) fld rel` | 1.04s |
| via `withColumn` (adds one `RUnion2`) | 0.50s |
| via a helper whose signature bundles `RUnion3` **and** `RUnion2` | **does not finish** |

`if` alone contributes a four-constraint `RUnion3` — a hand-written
inclusion–exclusion lattice over three row variables. Bundling that into a
helper's signature on top of `combine`'s `RUnion2` produces exactly the
overlapping-constraint shape the row solver diverges on. The first draft of
`Common.e` did this and hung the compiler.

So the rule the library follows: **keep the conditional at the call site, and let
the helper take a ready-made `Op`.** `withColumn` does that and is both generic
and fast.

This is not a quirk of these examples; it is the row-constraint cliff documented
in `tracker/TICKET-row-constraint-decision.md`, reached from ordinary library
code rather than from a synthetic stress test.
