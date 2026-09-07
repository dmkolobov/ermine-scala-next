# E3 REVIEW — `core/examples/Time/` judged as programs and as corpus

Reviewer pass over stage E3 (report `tracker/loopmodel/E3-EXAMPLES.md`, 590 lines; group
`core/examples/Time/`, 13 `.e` files + `README.md`, uncommitted). Brief:
`tracker/loopmodel/briefs/brief-E-review.md` with `$STAGE = E3`, `$GROUP = Time`, on top of
`brief-E-common.md` and `brief-E3.md`. Repository at `40f80aa` (branch `scala3-migration`), the three
row-solver defaults as adopted at `fe024a7`. Every `bin/ermine` below ran with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time, 2026-09-07, on a box
shared with other agents (wall clocks are therefore not comparable with the implementer's; the solver
counts are exact and are). Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-E3/`. Every `.ei` I
caused was deleted. No commits, no edits outside this file and that scratch directory. Findings are
prefixed `P-`.

---

## Verdict: **FIX-THEN-ADVANCE**

The library is excellent and the instrumentation is honest. `Helpers.e` is 34 helpers with explicit
signatures and doc comments that name the constraint and say why; I diffed the report's verbatim
`Helpers.ei` block against the real interface and **all 34 lines are identical**, and every `.ei`
figure in the report reproduces exactly. The L2 differential reproduces **to the digit** (115,674
segments, 0/0/0, both rejections at segments 115632 and 115663 with the same clause), and so does the
whole `Ai/` control column. `Signatures.e` is the best file of its kind in the tree: I re-inferred all
nine unannotated bodies and every transcription matches member for member. All eight stdlib/language
findings the brief singled out are **CONFIRMED**; none is refuted; `dateDiff`'s hole is a real
type-system hole and I state it precisely below. The `RUnion3` cliff really is gone.

What fails is a layer the reader depends on. **Three reports make substantive claims their own data
contradicts**, and I proved each by rendering the underlying relations to SQL and running them:
`MultiCurrencyPnl`'s advertised finding (a posting with no rate) never happens — `unrated` is always
empty; `ReadingHistory`'s `asOfWithin 1` is not empty and `asOfWithin 3` returns exactly the global
answer, so the three lookups that section contrasts return one answer; `ReadingHistory.carriedCells`
computes "every cell except 18 April" while its comment says "sessions where a station had no reading",
and the days the comment names are the wrong days. Five top-level names clash across the group and
**every one of them is `undefined term` in the session `Time/README.md` itself prescribes**. Six
census cells and four of the five "costliest solve" lines do not reproduce, and the group's actual
heaviest solve — the one shape the brief predicted — is missing from the report. And three of the four
wiring items are stale against E1's now-landed changes, one of them withdrawn outright.

None of this requires rewriting a module. The required fixes are in §10.

---

## 1. Gates re-run

| gate | report | mine | verdict |
|---|---|---|---|
| G1(a) 10 modules per file | 10 LOADED | **10 LOADED, 0 `error:`, 0 `Unable to load`** | ✔ |
| G1(a) own check time | 0.29–1.60 s | **0.29–1.38 s**, sum **8.28 s** | ✔ nothing near 30 s, no `.slow` |
| G1(a) 3 negatives per file | REJECTED, verbatim texts | **3 REJECTED**, texts character-identical, 0.09/0.05/0.11 s | ✔ |
| G1(b) one batch | rc=0, 19.7–28.1 s, own-time 5.23/8.51 s | **rc=0, 21.9 s, own-time 6.16 s**; with negatives 10 imported + 3 rejected, 28.5 s | ✔ |
| G1(b) the `bucket01` clause flip | flips per-file → batch | **reproduced**: per file "the whole contains it but no part does", in batch "**a part contains it but the whole does not**" | ✔ |
| G1(d) the three sweeps | `Expected 271 but got 315` | **20 properties proved, 0 falsified** — E1 made the count derived; see P-22(d) | ✖ report stale |
| G2 the differential | 115,674 seg, 0/0/0, nonpart 2,036, rejected 2 | **115,674 / 115,674 / 0 / 0 / 0, nonpart 2,036, rejected 2**, at segments **115632** and **115663** | ✔ exact |
| G2 `Ai` control | 83,942 seg, 0/0/0, nonpart 1,646, rejected 0 | **identical** | ✔ exact |
| G3 census | see §6 | 14 of 20 cells exact, **6 differ** | ✖ see P-17 |
| G3 `Ai` census column | see §6 | **every cell exact** | ✔ |
| G4(a) evaluate 8 reports | 0 errors, 68 bindings | **8/8 `Report f z`, 0 errors**; the `>> :load` recipe works verbatim in a bare REPL for all eight | ✔ |
| G4(a) trimmed renderings | see report §G4 | **every one I could check reproduces** (see §7) | ✔ |
| G4(b) `.ei` | 34/23/38, 32/26/68, eight reports at 0 | **identical, every figure**; the 34-line `Helpers.ei` block **verbatim, 34 of 34 lines** | ✔ exact |
| RUnion re-measurement | A 0.17 / B 0.23 / C 0.12 / C′ 0.15 | **A 0.14 / B 0.19 / C 0.21 / C′ 0.17** — same conclusion | ✔ (see §5) |

Per-file own times, mine (`Importing module 'Time.X' (t)`, one JVM per file, `Helpers.e` first):
Helpers 0.38, Signatures 0.29, MultiCurrencyPnl 0.75, SubscriptionWaterfall 1.38, InterestAccrual
0.76, SensorSeries 0.71, EmployeeTenure 0.83, ReadingHistory 0.63, CohortRetention 1.34, DemandForecast
1.21. Wall 14.2–22.1 s each, of which 12.5–15.5 s is the stdlib boot.

`sbt core/testOnly *TestSurfaceParsers *TestStatementExtents *TestTolerantRead`: **Total 20, Failed 0,
Errors 0** (85 s). No falsification of any kind, on a tree carrying 161 stdlib + 172 example `.e`
files. `TestStatementExtents`'s three property TITLES still say "(271 files)" — cosmetic, and it does
not assert the count.

---

## 2. The modules as programs

I read all 13 `.e` files and both READMEs in full. The data is small enough to check by hand and
almost all of it is right; the fiscal calendar, the fixing dates, the two network calendars and the
hiring windows are all internally consistent and I verified each by hand. What is not reliable is the
narration around three of the eight reports.

### The three best

1. **`Helpers.e`.** The reason the group exists. Thirty-four helpers, every one with an explicit
   signature and a doc comment that names the row constraint it carries and why; the `.ei` publishes
   them verbatim (34 of 34 lines identical to the report's block, which I diffed). The `nearestBy`
   comment quotes the exact stdlib body it is fixing (`groupBy {ffine} (maxRowBy fsparse)`) and says
   in one sentence what is wrong with it; `fillForward` is a combinator the stdlib genuinely does not
   have, built out of `nearestBy` plus a spine, with the key/calendar overlap (`k <- (ko, ck)`)
   spelled out and both its instances present in the group. The header's re-measurement of
   `Ai/Common.e`'s rule is exactly the kind of thing an example library should carry.
2. **`Signatures.e`.** It improves on its model. Three deletion rules, each proved once at the top of
   the file with a two-line witness (`tautIsFree`, `perm2A/B`, `perm4A/B`, `freshLhsFromWider`), then
   nine inferred residuals transcribed and deduped. **I re-inferred all nine bodies** (`probes/PInfer.e`,
   and three of them alone in their own modules) and every set matches member for member under the
   obvious renaming — `orZero` 1, `yearFrac365` 1, `pctChange` 6, `band3`/`band4` 1, `movingAgg` 2,
   `nearestBy` 13, `shiftBy` 9. `safeDiv`'s five reproduce **only when the body is alone in its
   module** (co-located with the other eight it infers three — the deduped set), which is precisely
   the perturbation the file's own header warns about: the file corroborates itself. And the
   `nearestBy` instability it reports is real: I got the thirteen-constraint form in one module and
   the twelve-constraint form in another, same bytes. The `bucketBy` note is the sharpest language
   finding in the whole E series.
3. **`SubscriptionWaterfall.e`.** The cleanest report. A dense integer month index derived by
   `dateDiff` from a fixed epoch, two shifted self-joins over the *same* relation at lags 1 and 12,
   a running and a trailing window on the **empty** partition row, and a banding helper called both
   on a 4-column and on a 20-column relation. Every number I checked is right: 16 events January 2011
   – April 2012, a dense index 1..16, exactly four months with a year-back counterpart, `mom` and
   `booked` four columns each, `detailBanded` 21. Nothing is claimed in the header that the code does
   not do.

(`CohortRetention.e` is a near miss: the "the triangle is NOT a pivot" argument and the
`aggregateByGroup` demonstration are the group's best teaching, spoiled only by a first-use claim that
is already false and a derived column, `cohortIx`, that nothing uses.)

### The three weakest

1. **`ReadingHistory.e`** — the module the group is named for and the one with three substantive
   defects: `asOfWithin 1` is not empty and `asOfWithin 3` returns the global answer (P-2), so the
   section that exists to contrast three lookups shows one; `carriedCells` computes something else
   than its comment and the comment's days are wrong (P-3); "the six ... 'as of' questions **the
   stdlib** can answer" counts a `Time.Helpers` function and misses two stdlib forms (P-11). It also
   carries the group's single heaviest solve, which the report never notices (P-17).
2. **`MultiCurrencyPnl.e`** — the widest and most ambitious report, whose advertised finding does not
   occur in its own data (P-1: `unrated` is always empty, proved by rendering), with a column count
   off by one (P-5), a weekend posting dated 12 March that is on 5 March (P-5), and a "total" that is
   a per-row column under the field name `periodTotal` (P-6).
3. **`EmployeeTenure.e`** — a headcount report with no headcount. `headcountByBand` sums tenure days;
   three declared fields (`headcount`, `meanSalary`, `bonusTotal`) are never used; the header claims
   grouped aggregates "with `mean` and `count`" and there is no count; the `band4`/`band3` call site
   is 21 columns, not the "eighteen-column relation" the header names (P-9). The code is correct and
   the `asOf`-is-right-here-and-wrong-there contrast with `ReadingHistory` is a good idea; the narration
   is the least reliable in the group.

### Findings from reading the code

* **P-1 (MUST FIX — the module's advertised finding does not happen).** `MultiCurrencyPnl.e:206-223`
  says the 3 April CHF posting "picks up nothing at all because CHF has no rate before 1 April -- and
  that MISSING ROW is the report's finding", and `unrated` is captioned "A P&L that does not show this
  line is lying about its own completeness". The CHF rate **is** published on 1 April, which is on or
  before 3 April. **Rendered and run** (`tracker/tools/sql-render.sh`, `probes/TimeRender.e`): the
  candidate set `[| rateDate <= bookDate |] (fxRates ** ledger)` has 21 rows covering **all twelve**
  `entryId`s, and its CHF slice is exactly one row, `4108 | 2011-04-03 | 2011-04-01`. `nearestBy`
  therefore returns a row for every posting, `rated # {entryId}` is all twelve, and `unrated` is
  **empty**. The report section "### Postings with NO rate on or before their book date" always
  renders zero rows. Fix: move a currency's first rate after its first posting (making the CHF rate
  `@2011/4/4` does it), or delete the claim.
* **P-2 (MUST FIX — same class).** `ReadingHistory.e:159-164`: "At three days the 21 April rows still
  qualify; at ONE day nothing does, and an empty result is the correct answer". `lookupLatestWithin1`'s
  filter is `history <= asOf <= history + n days`; on 22 April with `n = 1` that admits **21 April**,
  and three stations read on 21 April. **Rendered**: the within-1 candidate set is 3 rows (FRD 20.32,
  BOU 35.07, LER.UK 1008.9, all at 21 April) and the within-3 set is 4 rows (those plus ESK.UK at 20
  April); `maxRowBy` reduces **both** to the same three 21 April rows — which is also exactly what
  `valueOn22Global` returns. So `valueOn22Within1`, `valueOn22Within3` and `valueOn22Global` are the
  same three rows, and the report's "### (2) asOfWithin 3 days, and within 1 day (empty)" is wrong
  twice. Fix: use `asOfWithin 0` for the empty case, and say that the 3-day window does **not** rescue
  ESK.UK — because the grouping is by date alone, which is the module's own point.
* **P-3 (MUST FIX). `ReadingHistory.carriedCells` computes "not 18 April", and its comment's days are
  wrong.** `carriedCells = difference X (X |> filterEq sessionDate @2011/4/18)` is every
  (station, session, read) triple whose session is not 18 April — not "sessions on which a station had
  NO reading of its own". And the comment "On the UKMO network that is 19, 27 and 28 April for both
  names" is false from the data: ESK.UK (18, 20, 26) also lacks 21 April; LER.UK (18, 21) also lacks 20 and 26.
  Both `carriedCells` and `staleFlags` are dead — neither appears in `readingReport`.
* **P-4 (MUST FIX). `InterestAccrual.statsPanel` is nine columns, not eleven, and "EVERY aggregate"
  is not every aggregate.** Measured in the REPL: `statsPanel : Relation (|overdueSum,
  overdueMean, rateMean, rateStdDev, invoiceCount, weightedRate, overdueMin,
  rateVariance, overdueMax|)` — **9**. `InterestAccrual.e:225` says "One row, eleven columns".
  `Relation/Aggregate.e` exports `countAgg, sum, mean, avg, stddev, variance, min, max, weightedMean,
  weightedHarmonicMean`; **`weightedHarmonicMean` is used nowhere in the group**, so the header's
  "EVERY aggregate in `Relation.Aggregate`" overclaims. (The E3 report's §1 says "**all eight
  aggregates** plus `weightedMean`", which double-counts: `weightedMean` is one of the eight distinct
  aggregate functions actually used.)
* **P-5 (MUST FIX). Two wrong facts in `MultiCurrencyPnl.e`.** (i) `:214` "STEP 3. Translate. 27
  columns." — `translated` is **28** (measured); 27 is `rated`, the step before. The report's own G4
  block prints the 28 names. (ii) `:207` "the 12 March weekend posting picks up the 4 March GBP rate" —
  the weekend posting is entry 4105 on **5 March** (the file's own fact-table comment says so two
  screens earlier). The 4 March rate is right.
* **P-6 (MUST FIX). `MultiCurrencyPnl.unitCostZeroed` is not a total.** `:248-250` says "the same
  total with nulls read as zero, which is a DIFFERENT number when the aggregate is a mean rather than
  a sum"; the definition is `combine_Op (orZero unitCost) periodTotal ledger` — a per-row column, no
  aggregate at all — and the column it lands in is called `periodTotal`. Either aggregate it or
  rename the field and the comment.
* **P-7 (MUST FIX). Five names clash across the group, and the README's own group-load command breaks
  all five.** `banded` (EmployeeTenure, InterestAccrual, SubscriptionWaterfall — **three**), `indexed`
  (CohortRetention, ReadingHistory, SubscriptionWaterfall — **three**), `scored` (DemandForecast,
  SensorSeries), `rated` (InterestAccrual, MultiCurrencyPnl), `smoothed` (DemandForecast,
  ReadingHistory). Measured in exactly the session `Time/README.md` prescribes (`bin/ermine
  Time/Helpers.e $(ls Time/*.e | grep -v Helpers)`): every one answers `<interactive>:1:1: error:
  undefined term`, while every non-clashing binding in the same session evaluates cleanly. The report
  says "`banded` and `scored` are each defined in two modules" — it is five names, two of them in
  three modules. Fix: qualify them (`mrrBanded`, `tenureBanded`, `accrualBanded`, `meanIndexed`, …),
  as E2 was asked to do for `valued`.
* **P-8 (should fix). `DemandForecast.e:19` lists `safeDiv` under "SHAPES EXERCISED" and never calls
  it.** The only occurrence of the string in the file is that header line; the relative error is
  `pctChange` and the absolute one a plain subtraction. (The E3 report's §1 table is right; the module
  header is not.)
* **P-9 (should fix). `EmployeeTenure.e` — four defects in one header.** "Grouped aggregates with
  `mean` and `count`": there is no count anywhere. `headcountByBand` is
  `groupBy {ageBand, department} (sumBy tenureDays)` — a sum of tenure days under a name and a
  report title ("Headcount, tenure and age bands") that promise a headcount. `field headcount,
  meanSalary, bonusTotal : Double` are declared and never used. "at a call site on an
  eighteen-column relation": the `band4`/`band3` call site is `aged`, **21** columns (measured); 18 is
  the roster.
* **P-10 (should fix). "Before this directory NOT ONE of them had an example" is false.**
  `Helpers.e:16-22` and `Time/README.md` both say it. `core/examples/incomplete/RunCalibration.e:145`
  and `core/examples/incomplete/Signatures.e:80,123` — committed at `03a288d`, and both on this
  brief's own required-reading list — call `nearestDateWithin`. `Relation.e` also ships
  `lookbackJoin`, an eighth date-keyed combinator the group never mentions (and which
  `RunCalibration.e` discusses at length). `Wide/BranchDeposits.e` uses `lookupLatest`, concurrently.
  Also: the README says "`Relation.e` ships **six** date-keyed combinators" and then lists seven names.
* **P-11 (should fix). `ReadingHistory.e`'s "the six different 'as of' questions the stdlib can
  answer".** One of the six, `nearestBy`, is a `Time.Helpers` function, not stdlib — the module says so
  itself four lines later ("`nearestBy` -- the PER-KEY version"). The stdlib forms **not** exercised
  directly are `lookupLatestWithin` (the relation-of-dates form), `nearestDateWithin` and
  `lookbackJoin`. `Time/README.md`'s "**all six** as-of lookups side by side" and the E3 report's §1
  ("**all six** stdlib as-of lookups") inherit the error.
* **P-12 (should fix). `DemandForecast.e:4` — "the one report shape `core/examples` had exactly one
  instance of (`Ai/BatteryCycling.e`)".** `core/examples/ChartsExample.e` (committed) calls
  `timeSeriesChart` twice, at lines 383 and 411.
* **P-13 (should fix). `CohortRetention.e:22` — "`aggregateByGroup` ... No other example uses it".**
  Four `core/examples/Present/*.e` modules use it in this same tree. Concurrent, but already false.
  Also `cohortIx` is computed in STEP 1 and used nowhere.
* **P-14 (should fix). `SensorSeries.e` names sensors that do not exist and miscounts a gap.** The
  header talks about `S-102` and `S-104`; `sensorId` is an `Int` and the values are 101–104 — there is
  no `S-`prefixed identifier in the data. "`S-102` misses three days in the middle of the window" — 102
  reports on 1, 2, 7 and 10 June, so the mid-window gap is **four** days (3, 4, 5, 6). And the field
  `deviation` carries two different quantities in one module (`scored`: value − rolling mean;
  `withRms`: value ÷ RMS).
* **P-15 (should fix, in the file whose job is precision). `Signatures.e` gives `sd` and `fd` opposite
  meanings in the same section.** In `nearestByFull`/`nearestByDeduped` the signature is
  `Row k -> Field fd a -> rel sparse -> Field sd a -> rel fine`, i.e. **`fd` is the sparse field**;
  in `nearestBySimple` (and in `Helpers.nearestBy`) `sd` is the sparse one. The transcription is
  faithful — that is what the compiler minted, and I verified all thirteen members under the swap —
  but a reader comparing the deduped set to the shipped one name-for-name gets nonsense. One sentence
  saying "the inferred names are swapped relative to the shipped signature" fixes it.
* Smaller, in `Helpers.e`: the quoted foreign declaration `dateDiff# : PrimitiveTemporal d => Op r d
  -> Op r1 d -> Op r2 Int` drops the real first parameter (`TimeUnit ->`, `Relation/Op.e:178`);
  `:45-46` "`safeDiv` and `band3` below are `if`-based helpers that DO carry `RUnion3`" — neither
  *shipped* signature carries an `RUnion3` (`band3`'s carries no row constraint at all); `:350`
  "keeps it to three residual constraints" is the deduped count, while what `Helpers.e` ships is one.

### Negative modules

All three headers record the diagnostic my per-file run produced, character for character, including
the position. `bucket01`'s "AND THE CLAUSE IS NOT STABLE ACROSS LOADING MODES" note reproduces: my
batch run (a different negative ordering from the implementer's) printed "**a part contains it but
the whole does not**" where the per-file run printed "the whole contains it but no part does". The
`-#` spelling suggested in `bucket01`'s FIX paragraph is real (`Relation/Row.e:71`, `(-#) = flip
except`). These three files are the best-documented negatives in the tree.

---

## 3. The findings about Ermine itself — every one CONFIRMED

I wrote a minimal module for each (`review-E3/probes/`), one JVM.

1. **`lookupLatest`/`nearestDate` group by the DATE ALONE — CONFIRMED (source + data).**
   `Relation.e:220` is literally `groupBy {ffine} (maxRowBy fsparse) ([| fsparse <= ffine |] (join
   rsparse rfine))`, and `lookupLatest1` → `lookupLatest` → `nearestDate`,
   `lookupLatestWithin1` → `lookupLatestWithin` → `nearestDateWithin` are the only paths. `lookupLatest'`
   is the one per-key form (it unions a day at a time over the key set). The ReadingHistory
   demonstration is right: `readings` has ESK.UK on 18/20/26 April and three other stations on 21 April,
   so the globally latest date at or before 22 April is 21 April and **ESK.UK is dropped**. I rendered
   `readings` to confirm the dates (11 rows; 21 April = FRD/BOU/LER.UK, ESK.UK's nearest is 20 April).
   **Ticket-worthy** — this is a stdlib defect, not a documentation one.
2. **`nearestDate` is dates → dates — CONFIRMED (my module).** `probes/PNearestWide.e` passes a
   two-column sparse relation and gets
   `error: failed to unify type (|sd|) with type (|sd, lbl|)`. `:type nearestDate` prints
   `Field rsparse Date -> Relation rsparse -> Field rfine Date -> Relation rfine -> Relation r`: the
   `Field`'s row and the `Relation`'s row are the same variable, and a `Field`'s row is the singleton.
   The report's diagnosis ("an arity mistake with a confusing message") is exactly right.
3. **`Relation.Op.dateDiff`'s result row is UNCONSTRAINED — CONFIRMED, and it is a type-system hole.**
   Stated precisely: `Relation/Op.e:178` declares
   `dateDiff# : PrimitiveTemporal d => TimeUnit -> Op r d -> Op r1 d -> Op r2 Int`, and its wrapper
   `dateDiff` at `:151` **has no signature at all** (line 150, which would have given one, is
   commented out), so it generalises to
   `forall a b c d e r2. (AsOp a, PrimitiveTemporal c, AsOp d) => TimeUnit -> a b c -> d e c -> Op r2 Int`
   — the result row `r2` is related to neither argument row. Consequence, measured
   (`probes/PDateDiff.e`): on a relation `t : [a1, x1]` carrying **neither** date column,
   `holeDiff = combine_Op (dateDiff_Op days (col_Op d1) (col_Op d2)) gap t` **type-checks**, and
   evaluates to `Relation (|a1, x1, gap|)` whose header carries
   `Failure(NonEmpty[Operation refers to nonexistent column (d1) in header., Operation refers to
   nonexistent column (d2) in header.])`. So the row discipline that every other `Op` combinator
   enforces statically is, for date differences, deferred to header computation — a static guarantee
   silently downgraded to a run-time one for one primitive. `dateAdd#` has the same foreign shape but
   its wrapper `dateAdd : ... -> op r d -> Op r d` ties the rows, so the hole is `dateDiff`'s alone
   and the fix is one signature. `Helpers.dayCount`/`monthsBetween`/`daysSince`/`daysUntil`/`yearsOn`/
   `yearFrac365`/`yearFrac360` all inherit it and say so. **The clearest ticket in this review.**
4. **`weightedMean` forces value and weight to one type — CONFIRMED (my module).**
   `Relation/Aggregate.e:26` is `weightedMean x w = funcall2# wmeanModule (asOp x) (asOp w)` with no
   signature. `probes/PWeighted.e` (nullable value, `Double` weight) fails with
   `error: failed to unify type (Nullable Double) with type Double`; `probes/PWeightedOk.e`, the same
   with `annul_Op` on the weight, loads. Exactly as reported. **Ticket-worthy** (one signature).
5. **The `RUnion3` cliff is gone — CONFIRMED, see §5.**
6. **`Math` and `Vector` cannot reach a column — CONFIRMED (source).** `Relation.Op.e`'s complete
   per-row vocabulary is `prim col if coalesce coalesce' cast tryCast + - * / // % pow logBase log
   log10 exp abs upper lower replace negate fromNumericOp annul ++ show dateRange combine dateAdd
   dateAdd' typeOfOp foldFromRow weaken` plus `dateDiff`; there is no lifting of an Ermine function
   into an `Op`, and `Math`/`Vector`/`List.Util` are ordinary value-level modules. `SensorSeries.e`'s
   answer (fold at the value level, inject with `prim_Op`) is the only one available and the module
   says so.
7. **No date-part accessor at the `Op` level — CONFIRMED (source).** No `year`/`month`/`quarter`/`day`
   anywhere in `Relation/Op.e`; `Date.e`'s `getYear`/`getMonth`/`quarter` are value-level and by (6)
   cannot reach a column. This really is the most consequential limit in the group and it is why four
   reports carry a calendar table.
8. **`bucketBy`'s inferred type cannot be written down — CONFIRMED, twice.** `:type` on the
   unannotated body prints a type that opens `forall {a}` — an implicit **kind** variable — and whose
   existential group contains **four** binders of the form `(AsOp: (rho -> a -> *) -> f)`, the class
   `AsOp` bound as an existential variable of a kind the surface syntax has no binder for. Exactly as
   reported, and I got the same four in two independent runs. **One number differs**: I count **32
   constraints over 33 existentials**, not the report's "thirty-four constraints over thirty-four
   existentials" (P-21). The qualitative finding is untouched and is the most interesting language
   result in the group.
9. **The refutation clause is not stable across loading modes — CONFIRMED**, see §1.
10. **`groupBy` returns a `Mem` — CONFIRMED (source + REPL).** `probes/PMem.e`: `mem [...]` evaluates
    to `Mem (|s1, a1|)`, `relation [...]` to `Relation (|a1, s1|)`; `materialize` is the bridge and
    `nearestDate` itself uses it.
11. **`Random` is usable, with the caveats needing one correction.** `Random.e` is exactly as
    described: `randomInts = randomThings nextInt#`, and `randomThings` binds **one** `Random#` from
    the seed (`fromSeed# l`) and then draws from it through `unsafePerformIO`. But it is one generator
    **per stream**, created from the seed each time `randomInts s` is evaluated — not one process-wide
    generator, which is what "one shared mutable generator" reads as. The implementer's own
    measurement (identical prefixes across three evaluations and a fresh JVM) is what the code
    predicts. The decision not to use it for corpus data is sound and well argued; the *reason* should
    say "the sharing is per stream and depends on how the stream is forced", not "one shared mutable
    generator".
12. **The surface-syntax traps — CONFIRMED by construction.** `empty_Rw` for the empty row is used in
    `SubscriptionWaterfall`; `import Relation.Op.Type using type Op` appears in both library modules;
    `dayGrid` is named that because `Date.days` is a global; `%` and the relational `filter` are as
    described. I hit the shadowing rule myself: in a module importing `Scanners`/`IO.Unsafe`, the
    relational `join` is shadowed and `**` is the usable spelling.

**Recommendation.** Open `tracker/TICKET-stdlib-findings.md` with three entries: (3) `dateDiff`'s
unconstrained result row — a static guarantee silently deferred to run time, fixable with one
signature; (1) the date-alone grouping in `nearestDate` and the whole `lookupLatest` family, with
`Helpers.nearestBy` as the reference fix; (4) `weightedMean`'s missing signature. Add (8) —
`bucketBy`'s unprintable residual — to `tracker/TICKET-editor-and-solver-followups.md`, since it is a
pretty-printer/parser round-trip defect rather than a library one.

---

## 4. The `Signatures.e` entailment triples

**They hold**, and the module compiling is the proof — `Time.Signatures` LOADED in every run.
Independently, I re-inferred all nine unannotated bodies and the transcriptions are faithful (§2).

**But there are NINE, not eight** (P-16). `xFull`/`xDeduped` pairs exist for `orZero`, `yearFrac365`,
`pctChange`, `safeDiv`, `band3`, `band4`, `movingAgg`, `nearestBy`, `shiftBy` — nine. The report's own
table has nine rows while its prose says "Eight helpers" and "8 entailment proofs", and
`Time/README.md` says "For eight helpers". Only **five** of the nine are full `xFull`/`xDeduped`/
`xSimple` triples (`yearFrac365`, `pctChange`, `safeDiv`, `nearestBy`, `shiftBy`); `orZero`, `band3`,
`band4` and `movingAgg` have no `xSimple` (their shipped signature is unchanged from the deduped one,
which is worth saying), and `bucketBy` has a `bucketBySimple` with no `xFull` — deliberately, and
explained.

Every count in the report's deletion table is right: 1→0→0, 1→0→0, 6(5 row)→3→1, 5→3→1, 1→0→0, 1→0→0,
2→1→1, 13→6→4, 9→7→4.

**Are the `xSimple` forms the ones a person would write?** Yes, with one reservation. `pctChangeSimple`
(`out <- (cur, prior)`), `safeDivSimple` (`out <- (num, den)`), `movingAgg`'s
`t <- (dateR, part, valR)` and `shiftBySimple`'s four are exactly what one writes: they name the
caller's own columns, in the caller's vocabulary, and every one of the deleted constraints is over an
intermediate the caller never sees. `nearestBySimple`'s four (`sparse <- (k, sd, sv)`,
`fine <- (k, fd, fv)`, `out <- (k, sd, sv, fd, fv)`, `Primitive a`) are the best of the set — they
read as a sentence about the three relations. The reservation is P-15: the Full/Deduped pair for
`nearestBy` uses `sd` and `fd` with the *opposite* meanings, so the very comparison the file exists to
make is booby-trapped by its own variable names.

---

## 5. The RUnion re-measurement — CONFIRMED

Reproduced from scratch (`review-E3/runion/Run{A,B,C,Cp}.e`, a 19-column fact table, one JVM per
form, module time only, matching the four forms `Ai/Common.e` measured):

| form | `Ai/Common.e` | report | **mine** |
|---|---|---|---|
| A — the conditional INLINE at the call site | 1.04 s | 0.17 s | **0.14 s** |
| B — via an `Op`-returning helper, `combine` at the call site | 0.50 s | 0.23 s | **0.19 s** |
| C — conditional AND `combine` bundled in one relation-returning helper, no signature | *does not finish* | 0.12 s | **0.21 s** |
| C′ — the same with the inferred set written out | — | 0.15 s | **0.17 s** |

**The cliff is gone**: form C, the one `Ai/Common.e` records as never finishing, checks in a fifth of
a second, and C′ compiles with the report's transcribed signature verbatim, so the residual is
re-enterable. The four forms are now within 0.07 s of each other, which is inside this machine's
noise — so the *ordering* in the report's "now" column (C fastest) is not reproducible and should not
be read as one; the finding is that all four are cheap. **P-20**: the report calls C's residual "a
mere seven constraints"; its own quoted block lists **eight**, and I infer the same eight
(`Primitive b, r <- (c, o), Primitive a, RelationalComb rel, c1 <- (so, rs), t <- (ro, so, rs),
c <- (c), r <- (ro, rs)`).

---

## 6. The census

Traced with `-Dermine.useInterface=false -Dermine.loadInSeries=true -Dermine.rowTrace=…` over all 13
files, replayed and censused with `looptrace --replay … --depth | --cycle | --mints`, aggregated with
my own summariser (`review-E3/summ.py`). The **`Ai/` control column reproduces cell for cell**, which
is what makes the Time column's misses legible.

| measure | report (Time) | **mine (Time)** | report (Ai) | **mine (Ai)** |
|---|---|---|---|---|
| solves attributable to the group | 43,258 | **43,258** ✔ | 20,393 | **20,393** ✔ |
| verdicts | 43,256 S / 2 R | **identical** ✔ | 20,393 S | **identical** ✔ |
| draws per solve, max | 13 | **16** ✖ | 52 | **52** ✔ |
| draws per solve, mean | 0.03 | **0.031** ✔ | 0.06 | **0.062** ✔ |
| solves that draw at all | 487 (1.1 %) | **487 (1.13 %)** ✔ | 352 (1.7 %) | **352 (1.73 %)** ✔ |
| dequeues (steps), max / total | 60 / 16,360 | **56 / 16,324** ✖ | 137 / 10,035 | **137 / 10,035** ✔ |
| chain depth, max | 2 | **2** ✔ | 3 | **3** ✔ |
| "per-key mints", max | 4 | **4** (see P-18) | 8 | **8** (see P-18) |
| re-minted keys, max | 0 | **0** ✔ | 0 | **0** ✔ |
| `concrete`, share of dequeues | 19.0 % (3,101/16,360) | **19.0 % (3,106/16,324)** ✖ counts | 15.5 % (1,551/10,035) | **identical** ✔ |
| `concrete`, share of solves | 6.2 % | **6.16 %** ✔ | 5.7 % | **5.68 %** ✔ |
| vocabulary-fixed | 99.49 % | **99.49 %** ✔ | 99.09 % | **99.09 %** ✔ |
| generative | 0.51 % (220) | **0.51 % (220)** ✔ | 0.91 % (185) | **0.91 % (185)** ✔ |
| splits, max / total | 4 / 349 | **4 / 349** ✔ | 8 / 303 | **8 / 303** ✔ |
| resolution steps, max / total | 7 / 471 | **9 / 462** ✖ | 41 / 525 | **41 / 525** ✔ |
| input row variables, max | **42** | **42** ✔ | 11 | **11** ✔ |
| input partitions, max | **24** | **24** ✔ | 7 | **7** ✔ |
| label table, max | **31** | **31** ✔ | 14 | **14** ✔ |
| decision nodes, max | 60 | **57** ✖ | 137 | **137** (= steps; `states` is 138) |

* **P-17 (should fix — it changes what the census MEANS). Six Time cells do not reproduce, and the
  group's heaviest solve is missing from the report.** The report's five "costliest solves" block
  presents five lines "all at `drawn=13 maxmint=10 grew=true`". In my trace **one** of the five is
  right (`SensorSeries.e(197:10)`: drawn=13 steps=50 conc=5 maxmint=10 ✔). The other four are each off
  by one or more: `InterestAccrual.e(177:3)` is 12/47/5/10, `DemandForecast.e(166:3)` is 12/44/5/9,
  `EmployeeTenure.e(194:3)` is 12/49/5/9, `ReadingHistory.e(235:3)` is 12/49/5/9. And the **actual
  heaviest solve in the group is not in the list**: `core/examples/Time/ReadingHistory.e(208:11)` —
  `perStation = nearestBy {station, network} readDate readings sessionDate spine` — at
  **drawn=16 steps=56 conc=9 grew=true**, the most expensive solve anywhere in `Time/`. Since the
  replay summary, both rejection indices, the `Ai` control and fourteen other cells all reproduce
  exactly, the likeliest explanation is that the census was read off the run-1 trace and only the
  replay summary re-run on the final bytes; the report's "§G2/§G3 reproduce to the number" claim is
  what fails. **This matters because the missing solve is the group's best result**: the brief
  predicted that "`lookupLatest`'s `r <- (h, t)` family at call sites over wide rows … should produce
  residual chains and `concrete` steps the census never sees", and a two-column-key `nearestBy` over a
  17-column fact table and a 4-column spine is precisely that — it is the group's peak on draws,
  dequeues and `concrete` steps at once. The report's conclusion ("the five costliest solves are all
  `combine_Op` of a helper `Op` onto a wide relation") is the wrong conclusion from the wrong five
  lines. Consequential knock-ons: "the group's peak DRAW count (13) is a quarter of `Ai`'s (52)" —
  it is 16, under a third; the budget headroom is 1,250×, not 1,538×.
* **P-18 (should fix — a mislabelled metric).** The row called "per-key mints, max" is **not** per-key
  mints. `looptrace --mints` reports `max` (the largest mint count on any one key) and `keys` (how
  many keys were minted); `--depth` reports `maxdkey`. The report's 4 (Time) and 8 (`Ai`) are `keys`/
  `maxdkey`; the actual **per-key mint maximum is 1 in Time and 1 in `Ai`**. The E2 review reports
  `max per-key mints 1` for its group and `1` for `Ai` — the same metric, read correctly — so the two
  reviews' tables currently disagree by a factor of 4 for no reason. Likewise "decision nodes
  (distinct states visited)" is `steps`, not `states` (Time steps 56 / states 57; `Ai` 137 / 138).
* **P-19 (should fix — the headline claim is true but is not what it says it is).** The brief asks
  whether `band4`'s 42-variable input is a realistic shape or an artefact of nested conditionals.
  **It is an artefact of nested conditionals.** The 42/24 solve is `Helpers.e(448:1)` — `band4`'s own
  *definition*, seven arguments and three nested `if_Op`s over **one column** — and its twin
  `Signatures.e(194:1)` (`band4Full`); `band3` and its twin are next at 28/16, `bucketBy` and its twin
  at 24/10. Every one of them is `depth=0 nlbl=0 split=0 res=0` and costs at most 7 draws: a
  big-but-completely-flat system with **no labels in it at all**, i.e. nothing to do with the group's
  16–19-column fact tables. Per module, the widest input at any *call site* over a wide row is
  `nvars=11 nparts=7` — **exactly `Ai`'s maximum**. So "this group hands the model solves with 3.8×
  the row variables and 3.4× the partitions of anything in the previous corpus" is arithmetically
  true (42/11 = 3.8, 24/7 = 3.4) and reads as a claim about wide rows, which it is not. What the wide
  rows really moved is the **label table** — 31 against `Ai`'s 14, at
  `MultiCurrencyPnl.e(256:3)`, the `join translated currencies` after `bucketBy`+`nearestBy`+
  `fxConvert` — and the **heaviest solve**, `ReadingHistory`'s two-column-key `nearestBy` (P-17). Both
  are real, both are exactly what the brief hoped for, and the report buries them under the banding
  helpers.

Per-module census (mine), for the record:

```
module                   solves rowcarry maxdraw maxdeq maxdepth maxparts maxvars maxlbl  gen%
CohortRetention            5844     1407      11     45        2        7       8     18  0.17
MultiCurrencyPnl           5551     1327      12     47        2        7      11     31  0.41
SubscriptionWaterfall      5527     1324      12     48        2        7       8     21  0.49
SensorSeries               5351     1243      13     50        2        7      10     25  0.54
EmployeeTenure             5184     1193      13     49        2        7       8     28  0.39
ReadingHistory             5111     1177      16     56        2        7      10     20  0.39
DemandForecast             4919     1147      12     46        2        7       8     29  0.85
InterestAccrual            4044      916      12     48        2        7       8     29  1.04
Helpers                    1036       67       7     44        0       24      42      0  0.00
Signatures                  632       60       7     50        0       24      42      0  0.00
asof01 / bucket01 / null01   27/25/7          3/3/2  15/13/9  1/1/1    4/4/2   8/8/6  4/7/1
```

**Is the group gentler on the solver than the old corpus? Yes, on everything generative** — depth 2
against ≤ 4, generative rules on 0.51 % against ~2.6 %, `concrete` on 19.0 % against ~25 %, draws 16
against `Ai`'s 52 — **and harder on everything static**: 42 input variables, 24 partitions, 31 labels.
That is a finding, not a failure, and the report says so plainly, which is right.

---

## 7. G4 — the recipe, the renderings, and what cannot be rendered

* **The `render` finding is CONFIRMED.** `render` is not a term in the 161 stdlib modules, not a REPL
  command and not a builtin; the `>> render <report>` line in every `Ai/*.e` header is not executable.
  Independently confirmed by E1 and E2.
* **The replacement recipe works for every report.** I ran each module header's `>> :load …/Helpers.e`
  / `>> :load …/<Module>.e` / `>> <reportName>` verbatim, in a **fresh bare `bin/ermine`** with
  relative paths from the repository root, one JVM per module: **8/8 print
  `forall (f: * -> *) z. Report f z = (Report <function>)`, zero errors**. The recipe is correct as
  written.
* **The renderings in the report are real.** Every one I could check reproduces: `translated` 28
  columns (and the exact 28 names), `bucketed` 25, `withSymbol` 30, `unrated` 19, `statsPanel` **9**
  (the report's block is right; the module's comment is not — P-4), `byTeam (|teamCode,
  overdueSum|)`, `filled` 19, `perStation` 19, `nearestUk` **2** (dates to dates), `retention` 5,
  `booked` 4, `mom` 4, `gapDays (|calDate, sensorId|)`, and the four `InterestAccrual` scalars to the
  last digit (`1.0125784515406344`, `1.0122722344290394`, `0.5`, `0.012500000000000039`) and the three
  `SensorSeries` ones (`937.6`, `Just 71.8`, `423.98782057978974`). One imprecision: the annotation
  "`nearestBy`: the whole 17-column row, per key" describes a 19-column result.
* **E1's `tracker/tools/sql-render.sh` works on this group and its limits are severe here** — worth
  recording, because it is the group most affected. Driving it with
  `ERMINE_RENDER_MODULES=…`: the relation literals and the pure join/filter pipelines render and run
  (`ledger` 12 rows, `fxRates` 11, `bucketed` **12** — a nice check that the 4-4-5 calendar covers
  every posting exactly once, `readings` 11), and **everything that goes through `materialize` does
  not**: `rated`, `unrated`, `valueOn22Global`, `nearestUk`, `policyInForce` and `gapDays` all answer
  `Emission not supported for sql statement SqlLoad(...)`. Since `asOf`, `asOfEach`, `asOfWithin`,
  `nearest`, `nearestBy`, `fillForward`, `latestPerKey` and every `groupBy` roll-up materialise, **the
  as-of family is exactly the part of this group that cannot be rendered by any route in this
  repository** — which is why P-1 and P-2 needed the candidate sets rendered instead of the answers.
  `dateAdd` is also unemittable on the sqlite backend (`todo - sqlite dateadd function`), so a
  staleness window cannot be dumped at all without the MS SQL emitter.

---

## 8. Coverage against the brief

**Delivered in full**: all eight reports the brief asks for, one for one; `asOf`, `asOfWithin`,
`nearest`, `fxConvert`, `bucketBy`, `fillForward`, `pctChange`, `safeDiv`, `nullSum` and more (34
against the "eight to ten modules plus `Helpers.e`" asked for); `Currency`, `Math`, `Vector`,
`List.Util`, `Relation.Windowed`'s framed half, `Relation.Sort`'s `single`/`Ascending`,
`Relation.Aggregate` beyond sum/count, nullable arithmetic via `coalesce`/`annul`/`selectNulls`; the
`xFull`/`xSimple` pairs (nine, more than the two asked for); a negative module (three, more than the
one asked for). `Random` was investigated, documented and deliberately not used, with a reason that is
about corpus reproducibility and is right.

**Missed, and not on the report's "could not write" list:**

* **`DateRange` — not used, not mentioned, anywhere in the group.** The brief names `DateRange.e` in
  its required reading and opens by saying `DateRange` is imported by two examples "only through the Ai
  date-range trees". The group's whole answer to "there is no month accessor" is a hand-written
  calendar *relation*, and four reports carry one; whether `DateRange` is the right tool for that, or
  why it is not, is exactly the question a reader will ask and the group never raises it. This is the
  one real coverage gap.
* **`Ring`, `Num`, `Double.e`, `Long.e`, `Int.e`** — named in the brief as zero-use; none is imported
  by any module in the group (all the arithmetic is `Relation.Op`'s). Not mentioned in §7.
* **`Nullable.e` itself** — not imported. The nullable work is all via `Relation.Op.coalesce`/`annul`
  and `Relation.Predicate.selectNulls`. That is arguably the *right* level for a reporting language,
  but the brief asked for `Nullable` and the difference deserves a sentence. (`Relation.Predicate.isNull`
  is likewise only reached indirectly, though the plan row lists it.)
* **`weightedHarmonicMean`** — the one aggregate not exercised, while the header says "EVERY
  aggregate" (P-4).
* **`lookupLatestWithin` (the relation-of-dates form), `nearestDateWithin` and `lookbackJoin`** — the
  three stdlib date combinators reached only indirectly (P-11), in the group that exists to exercise
  them.
* The brief's second suggested negative was "a nullable **sum** where a non-nullable is expected";
  what shipped is a nullable **rate** into a `Double` conversion. Equivalent in spirit, and `nullSum`
  is exercised positively, so I do not count this as a gap.

**A follow-up module worth writing**: one that builds a fiscal calendar as a `DateRange` tree and
buckets against it, side by side with `bucketBy`'s flat calendar relation — it would close the gap
above, connect this group to `Ai/FiscalCalendar.e`, and put a *tree*-shaped input under the as-of
helpers, which is a solver shape neither this group nor `Ai/` currently reaches.

---

## 9. The wiring lines, checked against E1's landed shape

**P-22 (MUST FIX — three of four are stale).**

* **(a) `tracker/tools/corpus-run.sh` — correct, applies cleanly.** The report's three hunks quote the
  current text (E1's `Wide` version) and the additions are exactly parallel. **One omission**: E1
  updated the header comment "Directories covered, **79** files: …" when it added `Wide`; the E3
  wiring lines do not, so the comment must also gain
  `core/examples/Time/*.e (10), core/examples/Time/shouldfail/*.e (3)` and the count must go 79 → 92.
* **(b) `tracker/tools/looptrace-corpus.sh` — STALE, and applying it as written loses `Wide`.** The
  report's diff quotes
  `groups="${LOOPTRACE_GROUPS:-boot top Ai shouldfail bugs guide shouldfail-controls incomplete}"`,
  which no longer exists — the current line already carries `Wide Wide-shouldfail`, so the proposed
  replacement would **delete both**. The orchestrator must instead insert into the existing list.
  Second, E1 changed the group *shape*: `Wide)` uses `-maxdepth 1` and the negatives live in a
  separate `Wide-shouldfail)` group. E3 proposes a single `Time)` rule with no `-maxdepth`, following
  the older `Ai)` shape, which folds two rejecting modules into the positives' trace. Recommended:
  ```
  groups="${LOOPTRACE_GROUPS:-boot top Ai Wide Wide-shouldfail Time Time-shouldfail shouldfail bugs guide shouldfail-controls incomplete}"
  Time) mapfile -t gf < <( { echo core/examples/Time/Helpers.e
                             find core/examples/Time -maxdepth 1 -name '*.e' ! -name 'Helpers.e' | sort; } ) ;;
  Time-shouldfail)
        mapfile -t gf < <( { echo core/examples/Time/Helpers.e
                             find core/examples/Time/shouldfail -maxdepth 1 -name '*.e' | sort; } ) ;;
  ```
* **(c) `core/examples/README.md` — CORRECT, and it fits E1's rewrite.** E1's table is
  `| directory | subject | library |`; the proposed row is three cells with `Time/Helpers.e` in the
  library column, the code-block line follows the `bin/ermine <library> <module>` pattern, and the
  closing-paragraph addition matches the existing `shouldfail/` (and `Wide/shouldfail/`) sentence.
  Apply as written. (Unlike E2's, which the E2 review had to rewrite.)
* **(d) `scalacheck-binding/src/main/scala/TestSurfaceParsers.scala` — WITHDRAW.** E1 has already
  replaced the constant with `val expected = moduleFiles.size` and a comment explaining why. There is
  nothing to change, the report's "the only shared file whose change is *required* for the gate" is no
  longer true, and its arithmetic ("315 = 161 stdlib + 154 example files") is already 161 + **172** =
  **333** on today's tree — a number that would be wrong again tomorrow, which is exactly why E1
  derived it. **My three sweeps pass 20/20 with no falsification.** The report's §G1(d) and the plan
  row's `sbt core/test 912/914` sentence should be rewritten to say so.

The report's own §6 preamble ("this stage did **not** edit `tracker/tools/*`, `core/examples/README.md`
or `scalacheck-binding/`") is true — I checked `git status`: the only files E3 touched are
`core/examples/Time/**` and the two tracker documents it was told to write. Good discipline.

---

## 10. Required fixes before the group is committed

Module text (the files a user reads):

1. **P-1** `MultiCurrencyPnl.e` — make a posting genuinely unrated (move the CHF rate to `@2011/4/4`),
   or delete the "MISSING ROW", the `unrated` caption and the report section.
2. **P-2** `ReadingHistory.e` — `asOfWithin 1` is not empty. Use `asOfWithin 0`, fix the comment and the
   report caption, and say that within-3 does not rescue ESK.UK.
3. **P-3** `ReadingHistory.e` — fix `carriedCells` (or delete it and `staleFlags`, both dead) and the
   days its comment names.
4. **P-4** `InterestAccrual.e` — "eleven columns" → nine; "EVERY aggregate" → "every aggregate except
   `weightedHarmonicMean`".
5. **P-5** `MultiCurrencyPnl.e` — "27 columns" → 28; "12 March" → 5 March.
6. **P-6** `MultiCurrencyPnl.e` — `unitCostZeroed` is not a total; rename `periodTotal` or make it one.
7. **P-7** — rename the five clashing top-level names so the README's own group-load session works.
8. **P-8** `DemandForecast.e` — drop `safeDiv` from the header, or use it.
9. **P-9** `EmployeeTenure.e` — drop the `count` claim; rename `headcountByBand` or make it a count;
   delete the three unused field declarations; "eighteen-column" → 21 at the call site.
10. **P-10 / P-11 / P-12 / P-13 / P-14** — the five first-use and data claims that do not hold.
11. **P-15** — one sentence in `Signatures.e` saying the inferred `sd`/`fd` are swapped relative to
    the shipped signature.

Report text (`E3-EXAMPLES.md`) and the plan row:

12. **P-16** — "eight helpers" → nine `xDeduped = xFull` proofs, five full triples.
13. **P-17** — re-run the census on the committed bytes and replace the five-costliest block; state
    `ReadingHistory.e(208:11)` as the group's heaviest solve and draw the conclusion the brief predicted.
14. **P-18** — relabel "per-key mints" as mint *keys* (and state the per-key maximum, 1) and
    "decision nodes" as dequeues.
15. **P-19** — say that the 42/24 solve is `band4`'s definition-site conditional lattice over one
    column, not a wide-row effect, and promote the label table (31) and the `nearestBy` call site as
    the shapes the wide rows actually moved.
16. **P-20 / P-21** — "seven constraints" → eight; "34 over 34" → 32 over 33 (or re-measure and quote).
17. **P-22** — rewrite wiring (b), extend (a) with the header-comment count, withdraw (d).
18. The §G1 `sbt core/test` paragraph and the plan row's corresponding sentence are superseded by
    E1's derived count; the three sweeps now pass 20/20.

Nice to have: the `Random` caveat's wording (§3.11), and the `dateDiff#` quotation's missing
`TimeUnit ->`.

---

## 11. Summary

Everything mechanical in this report reproduces: the differential to the segment index, the `Ai`
control cell for cell, every `.ei` count, the 34-line interface block verbatim, all nine inferred
residuals, the negatives' diagnostics character for character, the clause flip, the trimmed
renderings, the scalars to the last digit, the RUnion conclusion. Every stdlib and language finding is
**CONFIRMED** and none is refuted; `dateDiff`'s unconstrained result row is a genuine type-system hole
worth a ticket, and `bucketBy`'s unprintable residual is the best language finding of the E series.
The helper library and `Signatures.e` are the two strongest files, and the group closes the biggest
subject-matter gap in `core/examples` — the "as of" pattern — with a per-key fix for a real stdlib
defect.

What is not yet fit to commit is the prose and one census block: three reports assert things their own
data denies (two of which I disproved by running SQL against the relations), five names collide in the
session the README prescribes, and the census under-reads the group's own best result while three of
its four wiring lines no longer match the tree. All of it is cheap to fix, and none of it touches the
code. **FIX-THEN-ADVANCE.**
