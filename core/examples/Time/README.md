# `core/examples/Time` — dates, calendars, time series, money and nulls

Ten self-contained Ermine reports, a shared library of **37 row-polymorphic
helpers** (`Helpers.e`), the residual signatures those helpers would otherwise
have published (`Signatures.e`), and three negative modules under
`shouldfail/`.  (`Corrected.e`, the tenth, is a three-column signature control
rather than a report.)

They exist because the "as of" pattern — *the FX rate on the invoice date, the
last reading before the review date, the salary-band policy in force in June* —
is what every reporting language is for, and `core/examples` barely contained it.
`Relation.e` ships **eight** date-keyed combinators — `lookupLatest`,
`lookupLatest1`, `lookupLatestWithin`, `lookupLatestWithin1`, `lookupLatest'`,
`nearestDate`, `nearestDateWithin` and `lookbackJoin` — and before this directory
only ONE of them had a use anywhere in `core/examples`: `nearestDateWithin`, in
`incomplete/RunCalibration.e` and `incomplete/Signatures.e`, where it is the
subject of a study of the SOLVER rather than a report a user learns from.
(`Wide/BranchDeposits.e` calls `lookupLatest`, written concurrently with this
directory.) All eight have a call site here, in `ReadingHistory.e`.

`Currency`, `DateRange`, `Ring`, `Nullable`'s own functions, `Relation.Windowed`,
`Relation.Aggregate` beyond `sum`/`count`, `Math`, `Vector` and `List.Util` had
no example either.

Load the library first — every report imports it:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2" \
      bin/ermine core/examples/Time/Helpers.e \
                 $(ls core/examples/Time/*.e | grep -v 'Helpers\.e')

or, from the REPL, `:load core/examples/Time/Helpers.e`, then the report you
want, then evaluate it by name.

**`render` does not exist.** It is not a term in the stdlib, not a REPL command,
and not a builtin — the `>> render <theReport>` line in the header of every
`core/examples/Ai/*.e` module is not executable. A report can only be rendered
through `Layout.harness`, which needs a `Scanner` and a `Runner`, and every
constructor of both is a database connection; there is no in-memory backend and
no way to print a relation's rows from `bin/ermine`. What the REPL *can* do is
evaluate the report, or any relation in the module, and print its resolved
header — the column set it will show, which is a real check on the row solver's
answer. That is what gate G4 in `tracker/loopmodel/E3-EXAMPLES.md` does.

## The reports

| file | subject | fact row | what it exercises |
|---|---|---|---|
| `MultiCurrencyPnl.e` | general ledger in five currencies | 19 cols | `bucketBy` into a 4-4-5 calendar, then `nearestBy` for the FX rate as of each posting's book date, then `fxConvert`; `Currency.currencies`; `runningSum`; a nullable `unitCost` and the skipping mean beside the zeroing one; one posting with **no rate at all**, which is the report's finding |
| `SubscriptionWaterfall.e` | MRR movement by month and type | 19 cols | a period index derived by `dateDiff`; `shiftBy` at lags 1 **and** 12 for month-over-month and year-over-year; `runningSum`, `movingSum`; `band3` |
| `InterestAccrual.e` | late-payment interest on overdue invoices, two day-count conventions | 18 cols | `dayCount` / `yearFrac365` / `yearFrac360`; the reference rate as of the value date; `orElseNum` for a null agreed rate; `pow`; **all ten** aggregates `Relation.Aggregate` exports, on one relation |
| `SensorSeries.e` | four sensors on irregular days | 16 cols | `fillForward` onto a dense day grid; `movingMean` / `movingStdDev`; `safeDiv` for a z-score; `Vector` + `Math` + `List.Util` at the value level |
| `EmployeeTenure.e` | headcount, tenure and age bands | 18 cols | `yearsOn` / `daysUntil`; `band4` and `band3`; `bucketBy` for hiring campaigns; `asOf` for the salary-band policy in force |
| `ReadingHistory.e` | two network calendars in April 2011 | 17 cols | **all eight** stdlib date-keyed combinators side by side plus the per-key one they lack, on a month where the UKMO and the NOAA networks disagree about which days exist |
| `CohortRetention.e` | retention triangle | 16 cols | `monthsBetween`; `aggregateByGroup`; `Layout.Scan`'s `columns`/`keys` for a column set derived from the data; `Layout.Report.Keyed.tabular` with a pinned legend |
| `DemandForecast.e` | electricity demand vs forecast | 16 cols | `movingAgg` instantiated four ways in one pipeline; `timeSeriesChart` and a four-series `chart_K`; `bucketBy` for seasons; `safeDiv` for a load factor against a rolling maximum that starts at zero |
| `Corrected.e` | the corrected date-difference signatures, called | 3 cols | the POSITIVE control for stage S3b: `dayCount` under its new `RUnion2 out r r1` with both date columns really in the relation, and `daysUntil` at its adopted result type `Op r Int` (the `Has out r` form was measured dishonest under the closure)|
| `FiscalTree.e` | service orders on a fiscal calendar held as a **tree of date ranges** | 18 cols | one relation serving as both a `drilldownTable` hierarchy and a set of ranges to `bucketBy` against; `nearestBy` with the fine relation drawn from the tree; all of `DateRange`, and `Ring`/`Num`/`Long`/`Int`/`Nullable` at the value level — with the two `Date.e` defects they expose |

## The two things a reader should take away

**1. The stdlib's date lookups group by the DATE ALONE.** `nearestDate` is

    groupBy {ffine} (maxRowBy fsparse) ([| fsparse <= ffine |] (join rsparse rfine))

and `lookupLatest` is built on it. For a single series that is right. For a
history keyed by station, sensor or employee it takes the *globally* latest date,
so a series that stopped reporting last week vanishes instead of carrying its
last value forward. `Time.ReadingHistory` shows the failure directly: `asOf` on
22 April 2011 loses `ESK.UK` entirely, because some other station read a day
later. `Helpers.nearestBy` is the fix — the same body with the caller's key row
appended to the grouping row — and `Helpers.fillForward` builds the (key × day)
spine for it.

**2. `nearestDate` maps dates to dates, not tables to tables.** Its relation
arguments are typed `Relation rsparse` beside `Field rsparse Date`, and a
`Field`'s row is the *singleton* row of that column — so both relations are
forced to one column. You project, map, and join back yourself. Passing a fact
table gives

    failed to unify type (|readDate|) with type (|terrain, dataQuality, ...|)

which is a confusing message for what is really an arity mistake.
`Helpers.nearestBy` takes whole relations, which is the other half of why it
exists.

**3. `DateRange` cannot reach a column, and the labels it computes are not
reproducible.** `DateRange.e` is seven *value*-level functions over a
`(Date, Date)` pair, so a range held in an Ermine pair cannot be joined against a
fact table — which is why every calendar here is a relation of
`periodStart`/`periodEnd` instead. Worse, everything it formats goes through
`Date.getYear`/`getMonth`/`getDate`, which read the stored instant in the **JVM's
default timezone** while `Date.unsafeFormatDate` and `formatMonthYear` do not. In
any zone west of UTC the literal `@2011/1/1` is simultaneously `"1/1/11"` and
`"Dec 31"`, and `formatPeriodOr "custom" (1 Jan, 31 Jan)` answers `"Jan 2011"` on
one machine and `"custom"` on another. `Date.formatQuarter` is separately wrong:
`quarter d = getMonth d / 4 + 1` divides by four rather than three and then
indexes a 0-based list with a 1-based number, so its "quarters" are four months
long and **"Q1" is unreachable**. `FiscalTree.e` measures all of it, in a table,
side by side with `-Duser.timezone=UTC`.

## `Helpers.e`

Thirty-seven helpers, every one with an explicit signature and a doc comment
naming the row constraint it carries and why:

| group | helpers |
|---|---|
| as-of | `asOf` `asOfEach` `asOfWithin` `asOfEachWithin` `latestPerKey` `nearest` `nearestWithin` `lookback` `nearestBy` `fillForward` |
| calendars | `bucketBy` `dayCount` `yearFrac365` `yearFrac360` `monthsBetween` `monthsSince` `daysSince` `daysUntil` `yearsOn` |
| money | `fxConvert` `accrual` |
| period over period | `pctChange` `indexOf` `shiftBy` |
| nullable | `orZero` `orElseNum` `safeDiv` `nullSum` `missing` `present` |
| windows | `movingAgg` `movingMean` `movingSum` `movingStdDev` `runningSum` |
| banding | `band3` `band4` |

### The `Ai/Common.e` rule, re-measured

`Ai/Common.e` warns that bundling `if`'s four-constraint `RUnion3` into a
helper's signature on top of `combine`'s `RUnion2` hangs the compiler, and
concludes: keep the conditional at the call site.

Re-measured here at the row-solver defaults adopted at `fe024a7`, **the cliff is
gone**. The bundled form — conditional *and* `combine` in one relation-returning
helper, the one recorded as never finishing — checks in about a fifth of a
second, and all four forms are now within noise of each other. `band3` (two
nested `if`s) and `band4` (three) infer a residual of **one constraint** each —
the tautology `v <- (v)` — and their shipped signatures carry none at all.

The conditionals here still return an `Op` and let the caller pass it to
`combine`, but the reason is now composability, not the solver: `band3` is called
on four different value types in four different reports, which a
relation-returning form could not be.

## `Signatures.e`

For **nine** helpers — `orZero`, `yearFrac365`, `pctChange`, `safeDiv`, `band3`,
`band4`, `movingAgg`, `nearestBy`, `shiftBy` — the residual the compiler infers
with the signature removed,
carried verbatim (`xFull`); the same set minus its redundant members, defined as
`= xFull` so that the module compiling is the proof of entailment (`xDeduped`);
and — for the **five** where the shipped signature is a specialisation rather
than the deduped set itself (`yearFrac365`, `pctChange`, `safeDiv`, `nearestBy`,
`shiftBy`) — that specialisation too (`xSimple`). For the other four the deduped
set *is* what `Helpers.e` ships, which is worth knowing on its own. Same method
as `core/examples/incomplete/Signatures.e`, and it finds the same three kinds of
noise: tautologies `r <- (r)`, permuted right-hand sides, and constraints whose
left-hand side occurs nowhere else.

It also records the one residual that **cannot be transcribed**: `bucketBy`'s
inferred type quantifies existentially over the *class* `AsOp` and over an
implicit kind variable, neither of which the surface syntax has a binder for.

## `shouldfail/`

| file | mistake | diagnostic |
|---|---|---|
| `asof01_key_not_in_fact.e` | an as-of key row that is not a subset of the fact row | `Row partitions are unsatisfiable at field '…network': the whole contains it but no part does` |
| `null01_nullable_rate_into_double.e` | a `Nullable Double` rate into a `Double` conversion | `failed to unify type Double with type (Nullable Double)` |
| `bucket01_calendar_overlaps_facts.e` | a calendar sharing a column with the facts it buckets | `Row partitions are unsatisfiable at field '…region': …` — **and the clause flips** between a per-file and a batch load |
