# E3 — `core/examples/Time/`: dates, calendars, time series, money, nullable arithmetic

**GREEN**, and revised after review (`tracker/loopmodel/E3-REVIEW.md`, FIX-THEN-ADVANCE) --
see §8 for the old → new list of every changed sentence and number. Delivered 2026-09-06/07,
uncommitted. Group `core/examples/Time/` (14 `.e` files: `Helpers.e`, `Signatures.e`, **nine**
reports, three `shouldfail/` negatives, plus `README.md`). Every module loads per file and in
one batch, and **all eleven load in ONE session with every binding in every header recipe
evaluating**; the three negatives are rejected; the L2 differential over the group is clean
(**125,176** segments, 0 skipped / 0 hashdiff / 0 eqdiff) **in two different file orders**.
The census puts the group's widest solve at 42 input row variables and 24 input partitions --
but that is `band4`'s own definition, a conditional lattice over one column, and the honest
call-site figure is 11 variables / 7 partitions, exactly `Ai/`'s maximum (§3, G3). What the
wide rows really moved is the **label table (31 against `Ai/`'s 14)** and the **heaviest
solve**, which is a `fillForward` call site at 16-17 draws.

Toolchain for every figure below (branch `scala3-migration`, at `2dd7dc3` + the adopted
row-solver defaults `-Dermine.rowSound` ON / `dequeuePolicy=smallcanon` / `solveBudget=20000`):

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false" bin/ermine <files>

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/E3/`. Boot is 12.5–13.5 s of every wall
figure and is excluded from the per-module times, which are the compiler's own
`Importing module 'X' (t seconds)` line.

---

## 1. The file table (G5)

Command: `bin/ermine core/examples/Time/Helpers.e core/examples/Time/<M>.e`, one JVM per row,
re-measured on the post-review bytes (2026-09-07). The machine is shared with two other
example-writing agents, so wall clocks are not comparable between runs; the solver counts in
§3 are.

| module | subject | fields per fact row | helpers used | shapes exercised | per file | in batch |
|---|---|---|---|---|---|---|
| `Helpers.e` | **37** row-polymorphic helpers | — | — | 43 partition constraints across 26 of 37 signatures (vs `Ai/Common.e`'s 8/4, whole old tree 12/9) | 0.70 s | 0.42 s |
| `Signatures.e` | `xFull`/`xDeduped` for 9 helpers, `xSimple` for 5 | — | — | 68 partitions across 26 published signatures; 9 entailment proofs by `xDeduped = xFull` | 0.32 s | 0.35 s |
| `MultiCurrencyPnl.e` | GL in 5 currencies → 4-4-5 calendar | **19** | `bucketBy` `nearestBy` `fxConvert` `orZero` `nullSum` `missing` `present` `runningSum` | range join then per-key as-of on its own 25-column output; `Currency.currencies`; **one posting with no rate at all** (proved by rendering, §3); the skipping mean beside the zeroing one; the group's largest label table, **31** | 0.81 s | 0.70 s |
| `SubscriptionWaterfall.e` | MRR waterfall, MoM + YoY | **19** | `monthsSince` `shiftBy`×2 `pctChange` `runningSum` `movingSum` `band3` | period index derived by `dateDiff`; two shifted self-joins at lags 1 and 12; empty-row window partition | 1.24 s | 0.44 s |
| `InterestAccrual.e` | ACT/365 vs ACT/360, nullable agreed rates | **18** | `nearestBy` `orElseNum` `dayCount` `yearFrac365/360` `accrual` `band3` `missing` `present` | `pow` in the algebra; **all ten** aggregates `Relation.Aggregate` exports, including `weightedHarmonicMean`, as a ten-column cartesian panel; `annul` | 0.85 s | 0.83 s |
| `SensorSeries.e` | gaps filled forward, rolling z-score | **16** | `fillForward` `orZero` `movingMean` `movingStdDev` `safeDiv` `band3` `missing` `present` | (key × day) spine; two framed windows per sensor; guarded z-score; `Vector`+`Math`+`List.Util` at value level; **the group's heaviest solve in one file order** | 0.68 s | 0.51 s |
| `EmployeeTenure.e` | tenure and age bands as of a date | **18** | `yearsOn` `daysUntil` `band4` `band3` `bucketBy` `asOf` `safeDiv` `nullSum` | 3- and 4-way nested conditionals on a 21-column relation; a real headcount via `aggregateByGroup countAgg`; a policy history resolved by the GLOBAL as-of, where global is right | 0.81 s | 0.46 s |
| `ReadingHistory.e` | two disagreeing network calendars | **17** | `asOf` `asOfWithin` `asOfEach` `asOfEachWithin` `nearest` `nearestWithin` `lookback` `latestPerKey` `nearestBy` `fillForward` `indexOf` `movingMean` `dayCount` | **all eight** stdlib date-keyed combinators plus the per-key one they lack; `asOfWithin` shown to be a binary gate; **the group's heaviest solve in the other file order** | 0.76 s | 0.48 s |
| `CohortRetention.e` | retention triangle | **16** | `monthsBetween` `monthsSince` `indexOf` `safeDiv` | `aggregateByGroup`; `Layout.Scan` `columns`/`keys` for a **derived** column set, not `Relation.Pivot`; `Layout.Report.Keyed.tabular` + pinned `Legend` | 1.39 s | 1.45 s |
| `DemandForecast.e` | demand vs forecast | **16** | `movingAgg`×4 `runningSum` `bucketBy` `pctChange` `safeDiv` `band3` | the generic window helper instantiated four ways in one pipeline; `timeSeriesChart`×2 and a 4-series `chart_K` | 1.37 s | 0.56 s |
| **`FiscalTree.e` (NEW)** | service orders on a fiscal calendar held as a **tree of date ranges** | **18** | `bucketBy` `nearestBy` `present` `missing` | one relation serving as both a `drilldownTable` hierarchy and a set of ranges to bucket against; **a tree-shaped fine relation under `nearestBy`**; all seven `DateRange` functions and all of `Ring`/`Num`/`Long`/`Int`/`Nullable` at the value level, with the **two `Date.e` defects** they expose measured in a table | 0.83 s | 0.93 s |
| `shouldfail/asof01_key_not_in_fact.e` | key row not a subset of the fact row | 3 | `nearestBy` | REJECTED at 69:7 | — | — |
| `shouldfail/null01_nullable_rate_into_double.e` | nullable rate into a non-nullable conversion | 3 | `fxConvert` | REJECTED at 50:7 | — | — |
| `shouldfail/bucket01_calendar_overlaps_facts.e` | calendar sharing a column with the facts | 4 | `bucketBy` | REJECTED at 77:7 | — | — |

Nothing is over 30 s; nothing needed `.slow`; the draw budget never fired. Sum of the eleven
positive modules' own check time: **9.76 s** per file, **7.13 s** in one batch (24.0 s wall,
of which ~14 s is the stdlib boot).

---

## 2. The helper signatures, verbatim, with their published residuals (G5)

`core/examples/Time/Helpers.ei` in full — what a `-Dermine.useInterface=true` load publishes.
**26 of the 37 signatures carry a partition constraint; there are 43 partition constraints in
the file.** `Ai/Common.e` publishes 8 across 4; the whole pre-existing `core/examples` tree
carried 12 across 9.

```
accrual : forall (p: rho) n (rt: rho) (opr: rho -> * -> *) (yr: rho) (out: rho). (AsOp opr, Builtin.PrimitiveNum n, out <- (p, rt, yr)) => Builtin.Field p n -> Builtin.Field rt n -> opr yr n -> Relation.Op.Type.Op out n
asOf : forall (h: rho) (r: rho). r <- (t, h) => Builtin.Field h Builtin.Date -> Builtin.Date -> Builtin.Relation r -> Builtin.Relation r
asOfEach : forall (h: rho) (r: rho). r <- (t, h) => Builtin.Field h Builtin.Date -> Builtin.Relation h -> Builtin.Relation r -> Builtin.Relation r
asOfEachWithin : forall (h: rho) (out: rho). (exists (c: rho). out <- (h, c)) => Builtin.Int -> Builtin.Field h Builtin.Date -> Builtin.Relation h -> Builtin.Relation out -> Builtin.Relation out
asOfWithin : forall (h: rho) (r: rho). r <- (h, t) => Builtin.Int -> Builtin.Field h Builtin.Date -> Builtin.Date -> Builtin.Relation r -> Builtin.Relation r
band3 : forall (v: rho) a b. (Builtin.Primitive b, Builtin.Primitive a) => Builtin.Field v a -> a -> b -> a -> b -> b -> Relation.Op.Type.Op v b
band4 : forall (v: rho) a b. (Builtin.Primitive b, Builtin.Primitive a) => Builtin.Field v a -> a -> b -> a -> b -> a -> b -> b -> Relation.Op.Type.Op v b
bucketBy : forall (s: rho) (e: rho) (d: rho) (rel: rho -> *) (cal: rho) (facts: rho) (out: rho). (exists (cv: rho) (fv: rho). Builtin.RelationalComb rel, out <- (s, e, cv, d, fv), facts <- (d, fv), cal <- (s, e, cv)) => Builtin.Field s Builtin.Date -> Builtin.Field e Builtin.Date -> Builtin.Field d Builtin.Date -> rel cal -> rel facts -> rel out
dayCount : forall (r: rho) (r1: rho) (out: rho). Builtin.Field r Builtin.Date -> Builtin.Field r1 Builtin.Date -> Relation.Op.Type.Op out Builtin.Int
daysSince : forall (r: rho) (out: rho). Builtin.Date -> Builtin.Field r Builtin.Date -> Relation.Op.Type.Op out Builtin.Int
daysUntil : forall (r: rho) (out: rho). Builtin.Field r Builtin.Date -> Builtin.Date -> Relation.Op.Type.Op out Builtin.Int
fillForward : forall (k: rho) (od: rho) a (obs: rho) (cd: rho) (cal: rho) (out: rho). (exists (cv: rho) (ov: rho). Builtin.Primitive a, cal <- (cd, ck, cv), out <- (ko, ck, od, ov, cd, cv), k <- (ko, ck), obs <- (ko, ck, od, ov)) => Relation.Row.Row k -> Builtin.Field od a -> Builtin.Relation obs -> Builtin.Field cd a -> Builtin.Relation cal -> Builtin.Relation out
fxConvert : forall (amt: rho) n (rate: rho) (out: rho) (rel: rho -> *) (r: rho) (t: rho). (exists (o: rho). Builtin.RelationalComb rel, Builtin.PrimitiveNum n, t <- (r, out), r <- (amt, rate, o)) => Builtin.Field amt n -> Builtin.Field rate n -> Builtin.Field out n -> rel r -> rel t
indexOf : forall (cur: rho) n (prior: rho) (out: rho). (Builtin.PrimitiveNum n, out <- (cur, prior)) => Builtin.Field cur n -> Builtin.Field prior n -> Relation.Op.Type.Op out n
latestPerKey : forall (dr: rho) (hist: rho) (keys: rho) (out: rho). (exists (kc: rho) (kt: rho) (ho: rho) (hd: rho). keys <- (kc, kt), out <- (ho, kc, kt), out <- (ho, keys), hist <- (ho, kc), hist <- (dr, hd)) => Builtin.Field dr Builtin.Date -> Builtin.Relation hist -> Builtin.Date -> Builtin.Date -> Builtin.Relation keys -> Builtin.Relation out
lookback : forall (k: rho) (r1: rho) (r2: rho) (r3: rho). (r3 <- (k, s, t), r2 <- (k, t), r1 <- (k, s)) => Builtin.Int -> Builtin.Field k Builtin.Date -> Builtin.Relation r1 -> Builtin.Relation r2 -> Builtin.Relation r3
missing : forall (h: rho) a (rel: rho -> *) (r: rho). (exists (c: rho). r <- (h, c), Builtin.Relational rel) => Builtin.Field h a -> rel r -> rel r
monthsBetween : forall (r: rho) (r1: rho) (out: rho). Builtin.Field r Builtin.Date -> Builtin.Field r1 Builtin.Date -> Relation.Op.Type.Op out Builtin.Int
monthsSince : forall (r: rho) (out: rho). Builtin.Date -> Builtin.Field r Builtin.Date -> Relation.Op.Type.Op out Builtin.Int
movingAgg : forall (valR: rho) n (part: rho) (dateR: rho) a (t: rho). t <- (dateR, part, valR) => Relation.Aggregate.Type.Aggregate valR n -> Relation.Row.Row part -> Builtin.Field dateR a -> Builtin.Int -> Relation.Op.Type.Op t n
movingMean : forall (part: rho) (dateR: rho) a (valR: rho) n (t: rho). (Builtin.PrimitiveNum n, t <- (dateR, part, valR)) => Relation.Row.Row part -> Builtin.Field dateR a -> Builtin.Field valR n -> Builtin.Int -> Relation.Op.Type.Op t n
movingStdDev : forall (part: rho) (dateR: rho) a (valR: rho) n (t: rho). (Builtin.PrimitiveNum n, t <- (dateR, part, valR)) => Relation.Row.Row part -> Builtin.Field dateR a -> Builtin.Field valR n -> Builtin.Int -> Relation.Op.Type.Op t n
movingSum : forall (part: rho) (dateR: rho) a (valR: rho) n (t: rho). (Builtin.PrimitiveNum n, t <- (dateR, part, valR)) => Relation.Row.Row part -> Builtin.Field dateR a -> Builtin.Field valR n -> Builtin.Int -> Relation.Op.Type.Op t n
nearest : forall (rsparse: rho) (rfine: rho) (r: rho). r <- (rsparse, rfine) => Builtin.Field rsparse Builtin.Date -> Builtin.Relation rsparse -> Builtin.Field rfine Builtin.Date -> Builtin.Relation rfine -> Builtin.Relation r
nearestBy : forall (k: rho) (sd: rho) a (sparse: rho) (fd: rho) (fine: rho) (out: rho). (exists (sv: rho) (fv: rho). Builtin.Primitive a, out <- (k, sd, sv, fd, fv), fine <- (k, fd, fv), sparse <- (k, sd, sv)) => Relation.Row.Row k -> Builtin.Field sd a -> Builtin.Relation sparse -> Builtin.Field fd a -> Builtin.Relation fine -> Builtin.Relation out
nearestWithin : forall (rsparse: rho) (rfine: rho) (r: rho). r <- (rsparse, rfine) => Builtin.Int -> Builtin.Field rsparse Builtin.Date -> Builtin.Relation rsparse -> Builtin.Field rfine Builtin.Date -> Builtin.Relation rfine -> Builtin.Relation r
nullSum : forall (h: rho) n (rel: rho -> *) (b: rho). (exists (c: rho). b <- (h, c), Builtin.RelationalComb rel, Builtin.PrimitiveNum n) => Builtin.Field h n -> rel b -> rel h
orElseNum : forall (opc: rho -> * -> *) (s: rho) a (opa: rho -> * -> *) (t: rho) (v: rho). (exists (ro: rho) (so: rho) (rs: rho). t <- (so, rs), v <- (ro, so, rs), AsOp opc, s <- (ro, rs), AsOp opa) => opc s (Builtin.Nullable a) -> opa t a -> Relation.Op.Type.Op v a
orZero : forall (opc: rho -> * -> *) (v: rho). AsOp opc => opc v (Builtin.Nullable Builtin.Double) -> Relation.Op.Type.Op v Builtin.Double
pctChange : forall (cur: rho) n (prior: rho) (out: rho). (Builtin.PrimitiveNum n, out <- (cur, prior)) => Builtin.Field cur n -> Builtin.Field prior n -> Relation.Op.Type.Op out n
present : forall (h: rho) a (rel: rho -> *) (r: rho). (exists (c: rho). r <- (h, c), Builtin.Relational rel) => Builtin.Field h a -> rel r -> rel r
runningSum : forall (part: rho) (dateR: rho) a (valR: rho) n (t: rho). (Builtin.PrimitiveNum n, t <- (dateR, part, valR)) => Relation.Row.Row part -> Builtin.Field dateR a -> Builtin.Field valR n -> Relation.Op.Type.Op t n
safeDiv : forall (num: rho) (den: rho) (out: rho). out <- (num, den) => Builtin.Field num Builtin.Double -> Builtin.Field den Builtin.Double -> Relation.Op.Type.Op out Builtin.Double
shiftBy : forall (p: rho) n (v: rho) a (pv: rho) (rel: rho -> *) (r: rho) (out: rho). (exists (o: rho). Builtin.RelationalComb rel, Builtin.PrimitiveNum n, out <- (p, pv, o), r <- (p, v, o)) => Builtin.Field p n -> Builtin.Field v a -> Builtin.Field pv a -> n -> rel r -> rel out
yearFrac360 : forall (r: rho) (r1: rho) (out: rho). Builtin.Field r Builtin.Date -> Builtin.Field r1 Builtin.Date -> Relation.Op.Type.Op out Builtin.Double
yearFrac365 : forall (r: rho) (r1: rho) (out: rho). Builtin.Field r Builtin.Date -> Builtin.Field r1 Builtin.Date -> Relation.Op.Type.Op out Builtin.Double
yearsOn : forall (r: rho) (out: rho). Builtin.Date -> Builtin.Field r Builtin.Date -> Relation.Op.Type.Op out Builtin.Double
```

### `.ei` residuals per module

| `.ei` | published bindings | with a partition constraint | partition constraints |
|---|---|---|---|
| `Helpers.ei` | 37 | 26 | **43** |
| `Signatures.ei` | 32 | 26 | **68** |
| `MultiCurrencyPnl.ei` | 18 | 0 | 0 |
| `SubscriptionWaterfall.ei` | 13 | 0 | 0 |
| `InterestAccrual.ei` | 28 | 0 | 0 |
| `SensorSeries.ei` | 17 | 0 | 0 |
| `EmployeeTenure.ei` | 18 | 0 | 0 |
| `ReadingHistory.ei` | 27 | 0 | 0 |
| `CohortRetention.ei` | 15 | 0 | 0 |
| `DemandForecast.ei` | 13 | 0 | 0 |
| `FiscalTree.ei` | 58 | 0 | 0 |

Same pattern as `Ai/`: the **reports** are fully concrete and leave no residual, and all of the
row polymorphism lives in the two library modules. `FiscalTree.ei`'s 58 bindings with zero
partitions are the value-level `Ring`/`Num`/`Long`/`Int`/`Nullable`/`DateRange` scalars, which
is the point that section makes: none of those modules can reach a row.

### The `xFull` / `xDeduped` / `xSimple` chains (`Signatures.e`)

**Nine** helpers, each with the residual the compiler infers for the unannotated body carried
verbatim and the deduped set defined as `= xFull` (the module compiling is the entailment
proof). **Five** of the nine also carry an `xSimple`, the specialisation `Helpers.e` ships; for
the other four the deduped set *is* what `Helpers.e` ships.

| helper | inferred | deduped | shipped | `xSimple`? | what was deleted |
|---|---|---|---|---|---|
| `orZero` | 1 | 0 | 0 | no (deduped = shipped) | the tautology `v <- (v)` |
| `yearFrac365` | 1 | 0 | 0 | yes | the tautology |
| `pctChange` | 6 (5 row) | 3 row | 1 row | yes | a tautology; `out <- (prior, d)`, entailed by two others |
| `safeDiv` | 5 | 3 | 1 | yes | **two** permuted pairs |
| `band3` | 1 | 0 | 0 | no | the tautology |
| `band4` | 1 | 0 | 0 | no | the tautology |
| `movingAgg` | 2 | 1 | 1 | no | a constraint whose LHS occurs nowhere else |
| `nearestBy` | 13 | 6 | 4 | yes | 2 tautologies, 2 permuted copies, 3 fresh-LHS |
| `shiftBy` | 9 | 7 | 4 | yes | the tautology plus one fresh-LHS |

The three deletion rules are the same three `core/examples/incomplete/Signatures.e` names, and
`Signatures.e` proves each once at the top of the file (`tautIsFree`, `perm2A/perm2B`,
`perm4A/perm4B`, `freshLhsFromWider`). A note now warns that the compiler minted `sd`/`fd` with
the OPPOSITE meanings in `nearestByFull` from the ones `nearestBySimple` uses, so the two sets
must be compared by shape and not by name.

---

## 3. Gates

### G1 — every module type-checks, per file and in one batch; the negatives are rejected

Per file (one JVM each, `Helpers.e` first): **11/11 LOADED, 0 errors**, own check time
0.32–1.39 s, wall 17.3–21.9 s each. Batch (one JVM, all eleven): **11/11 LOADED**, wall
**24.0 s**, of which ~14 s is boot and **7.13 s** the eleven modules.

**The whole group in ONE session.** `bin/ermine Time/Helpers.e $(ls Time/*.e | grep -v Helpers)`
— the session `Time/README.md` prescribes — loads all eleven and evaluates **80 bindings with
zero errors**, including every binding named in every module header. Before the review five
top-level names collided across the group (`banded` and `indexed` in three modules each,
`scored`, `rated`, `smoothed` in two) and every one answered `undefined term`; `valued` and
`byPeriod` collided once `FiscalTree.e` was added. All seven are renamed. There are now **no
duplicate top-level term names in the group at all**. (Duplicate `field` declarations of the
same name and type — `region`, `readDate` and a dozen others — do NOT collide: a `field`
declaration is keyed globally by name and type.)

The negatives, one JVM each, verbatim:

```
core/examples/Time/shouldfail/asof01_key_not_in_fact.e:69:7: Row partitions are unsatisfiable at field 'Time.Shouldfail.AsOf01.network': a part contains it but the whole does not
core/examples/Time/shouldfail/null01_nullable_rate_into_double.e:50:7: error: failed to unify type Double with type (Nullable Double)
core/examples/Time/shouldfail/bucket01_calendar_overlaps_facts.e:77:7: Row partitions are unsatisfiable at field 'Time.Shouldfail.Bucket01.region': a part contains it but the whole does not
```

**The clause is not stable and the finding is now sharper than "per file vs batch".** Across
four runs of identical bytes — two per-file (before and after three helpers were added to
`Helpers.e`) and the two whole-group traces of §G3, which differ only in the ORDER of the files
on the command line — both row-partition negatives print each clause in some runs:

```
... : the whole contains it but no part does
... : a part contains it but the whole does not
```

at the same field, line and column, with the same verdict. So it is not a loading *mode*: the
clause is chosen by whichever derived constraint the solver refutes first, which depends on the
dequeue order, which depends on the `Supply`'s id base — i.e. on how much was loaded before the
module. **The Lean model reproduces whichever clause the compiler produced in the same run**
(order A gives "a part contains it…" for `bucket01`, order B "the whole contains it…", and the
replay of each matches), so the instability is in the solver's search order and not between the
compiler and the model. Both headers record both clauses and the reason.

**`sbt core/test`.** The item this report previously raised is **WITHDRAWN**: E1 has replaced
`TestSurfaceParsers`'s hard-coded corpus size with `val expected = moduleFiles.size` plus a
`>= 250` sanity bound, so the sweep no longer needs an edit when a group is added. Verified in
the source at `scalacheck-binding/src/main/scala/TestSurfaceParsers.scala:99-102`; the reviewer
ran `core/testOnly *TestSurfaceParsers *TestStatementExtents *TestTolerantRead` on a tree
carrying this group and got **20 properties, 0 falsified**. The other failure this report noted,
`Constraints.disjunction sound`, is pre-existing and so documented twice in `Constraints.scala`
("the one failure being the *pre-existing* `Constraints.disjunction sound` generator");
`TestConstraints.scala` reads no file under `core/examples`, and three re-runs failed
identically. Neither is attributable to this group.

### G2 — the L2 differential on the group

    ERMINE_JAVA_OPTS="... -Dermine.useInterface=false -Dermine.loadInSeries=true \
      -Dermine.rowTrace=<scratch>/<order>.tsv" bin/ermine <all 14 Time files>
    tracker/lean/.lake/build/bin/looptrace --replay <scratch>/<order>.tsv

Run in **two different file orders** (A: `Helpers` then alphabetical; B: `Helpers` then reverse
alphabetical; negatives last in both):

```
order A  #summary segments=125176 replayed=125176 skipped=0 hashdiff=0 eqdiff=0 nonpart=2209 rejected=2
order B  #summary segments=125176 replayed=125176 skipped=0 hashdiff=0 eqdiff=0 nonpart=2209 rejected=2
```

**0 skipped / 0 hashdiff / 0 eqdiff in both.** Traces 543,256 and 543,236 lines. The two
rejections are the two row-partition negatives at segments 125134 and 125165 in both orders, and
the model reproduces each refutation *including the clause the compiler chose in that run*.
Baseline control over `Ai/`, unchanged: `segments=83942 replayed=83942 skipped=0 hashdiff=0
eqdiff=0 nonpart=1646 rejected=0`.

### G3 — the census, and a finding about censuses

`--cycle`, `--depth` and `--mints` over the same replays, filtered to the solves located inside
the group.

| measure | **order A** | **order B** | `Ai/` control | round 7/8 corpus |
|---|---|---|---|---|
| solves attributable to the group | **50,822** | 50,822 | 20,393 | — |
| verdicts | 50,820 S / 2 R | identical | 20,393 S | — |
| draws per solve, max | **16** | **17** | 52 | — |
| draws per solve, mean | 0.030 | 0.030 | 0.062 | — |
| solves that draw at all | 572 (1.13 %) | 572 (1.13 %) | 352 (1.73 %) | — |
| dequeues, max / total | **62 / 18,748** | **60 / 18,737** | 137 / 10,035 | — |
| distinct states visited, max | 63 | 61 | 138 | — |
| chain depth, max | **3** | 3 | 3 | ≤ 4 |
| mint KEYS, max | 5 | 5 | 8 | ≤ 11 |
| **per-key mints, max** | **1** | **1** | **1** | — |
| re-minted keys, max | 0 | 0 | 0 | — |
| `concrete`, share of dequeues | 19.4 % (3,638) | 19.4 % (3,630) | 15.5 % (1,551) | ~25 % |
| `concrete`, share of solves | 6.12 % | 6.12 % | 5.68 % | — |
| vocabulary-fixed solves | **99.51 %** | 99.51 % | 99.09 % | 97.4 % |
| generative rules fired | **0.49 %** (247) | 0.49 % (247) | 0.91 % (185) | ~2.6 % |
| splits, max / total | 5 / 393 | 5 / 389 | 8 / 303 | — |
| resolution steps, max / total | 9 / 515 | 10 / 533 | 41 / 525 | — |
| input row variables, max (all solves) | 42 | 42 | 11 | — |
| input partitions, max (all solves) | 24 | 24 | 7 | — |
| **input row variables, max AT A CALL SITE** | **11** | **11** | **11** | — |
| **input partitions, max AT A CALL SITE** | **7** | **7** | **7** | — |
| label table, max | **31** | **31** | 14 | — |

**FINDING — a per-solve COST figure is a property of the trace, not of the module.** The two
orders differ only in the sequence of the eleven files on one command line. Every *structural*
quantity is identical to the unit: solve count, verdicts, chain depth, input widths, label
tables, generative-rule count, mint keys, per-key mints. Every *cost* quantity moves: max draws
16 → 17, max dequeues 62 → 60, total dequeues 18,748 → 18,737, `concrete` steps 3,638 → 3,630,
splits 393 → 389, resolution steps 9/515 → 10/533 — and so does the refutation clause of
`shouldfail/bucket01`. The cause is the same one behind the clause flip: the `Supply`'s id base
depends on what was loaded before, and `smallcanon`'s dequeue order is a function of the ids. So
**a census must state its file order**, and a cost cell that differs between two reports of the
same group is not necessarily an error in either. (This is what produced the discrepancy the
review found between the pre-review census and the reviewer's own: neither was wrong.)

**The group's heaviest solve is a `fillForward` call site, in both orders.**

```
order A  drawn=16 steps=62 conc=4 maxmint=7  grew=true  SensorSeries.e(194:10)
           filled = fillForward {sensorId} readingDate readings calDate dayGrid
order B  drawn=17 steps=55 conc=9 maxmint=8  grew=true  ReadingHistory.e(252:11)
         drawn=16 steps=60 conc=4 maxmint=7  grew=true  ReadingHistory.e(252:11)
           carried = fillForward {station, network} readDate readings sessionDate sessions
```

`fillForward` is `nearestBy` over a spine, so **this is exactly the shape the brief predicted**:
"`lookupLatest`'s `r <- (h, t)` family at call sites over wide rows … should produce residual
chains and `concrete` steps the census never sees". The `ReadingHistory` instance is the extreme
case — a TWO-column key, a 17-column sparse relation and a calendar that is itself keyed — and
it is the group's peak on draws and on `concrete` steps at once. The next tier
(`EmployeeTenure.e(197:3)` `band4`, `FiscalTree.e(278:3)`, `SubscriptionWaterfall.e(195:7)`
`pctChange`, `DemandForecast.e(170:3)` `movingAgg`) sits at 12–13 draws.

**The 42/24 solve is NOT a wide-row effect.** It is `Helpers.e(519:1)` — `band4`'s own
*definition*, seven arguments and three nested `if_Op`s over ONE column — and its twin
`Signatures.e(194:1)`; `band3` and its twin are next at 28/16 and `bucketBy` at 24/10. Every one
of them is `depth=0 nlbl=0 split=0 res=0` and costs at most 7 draws: a big-but-completely-flat
system with **no labels in it at all**. At a CALL SITE over a 16–19-column fact table the widest
input anywhere in the group is `nvars=11 nparts=7` — *exactly* `Ai/`'s maximum. What the wide
rows actually moved is the **label table**: 31 against `Ai/`'s 14, at `MultiCurrencyPnl.e(280:3)`
and `FiscalTree.e(289:35)` — the solves after `bucketBy`+`nearestBy`+`fxConvert` have composed a
28-column row — and the heaviest solve above.

**Budget headroom.** The largest draw count anywhere in the group is **17** against the adopted
`solveBudget=20000` — 0.085 % of it, headroom **1,176×**. The budget never fired.

### The `RUnion3` cliff, re-measured

Unchanged conclusion, one number corrected. On a 19-column fact table, module time only:

| form | `Ai/Common.e` (pre-adoption) | this stage | the reviewer |
|---|---|---|---|
| A — the conditional INLINE at the call site | 1.04 s | 0.17 s | 0.14 s |
| B — via an `Op`-returning helper, `combine` at the call site | 0.50 s | 0.23 s | 0.19 s |
| C — conditional AND `combine` bundled in ONE relation-returning helper, no signature | *does not finish* | **0.12 s** | 0.21 s |
| C′ — the same with the inferred set written out | — | 0.15 s | 0.17 s |

The cliff is gone. The four forms are now within 0.1 s of each other, which is inside this
machine's noise, so the ORDERING in either "now" column should not be read as a result — the
result is that all four are cheap. C's inferred residual is **eight** constraints, not the seven
this report first said:

```
forall (c: rho) a b (c1: rho) (rel: rho -> *) (r: rho) (t: rho).
  (exists (rs: rho) (ro: rho) (so: rho) (o: rho).
   c <- (c), r <- (c, o), r <- (ro, rs), Primitive b,
   c1 <- (so, rs), Primitive a, t <- (ro, so, rs), RelationalComb rel) =>
  Field c a -> a -> b -> b -> Field c1 b -> rel r -> rel t
```

### G4 — every report evaluated through the REPL

`render` is **not a defined term** anywhere: not in the 161 stdlib modules, not in
`Console.scala`, not as a builtin. `Layout.harness` needs a `Scanner` and a `Runner` and every
constructor of both is a DB connection, so **no report in `core/examples` can be rendered from
`bin/ermine`** and the `>> render <report>` line in every `Ai/*.e` header is not executable.
Independently confirmed by E1, E2 and the E3 reviewer. Every module header here now says so and
gives the evaluate-in-the-REPL recipe instead; the reviewer ran all eight of the original
recipes verbatim in a bare REPL and got `Report f z` from each with zero errors.

**Post-review**: the whole group now also evaluates in ONE session — 11 modules, 80 bindings,
zero errors (see G1) — which is the session the README prescribes and which previously failed on
five names.

**And three claims are now measured rather than asserted.** `nearestBy`'s answers go through
`materialize` and cannot be dumped to SQL, but their inputs can. Driving E1's
`tracker/tools/sql-render.sh` over this group and running the emitted SQL against SQLite:

| rendered | rows | what it settles |
|---|---|---|
| `[\| rateDate <= bookDate \|] (fxRates ** ledger) # {entryId, currencyCode, bookDate, rateDate}` | **20**, covering **11 of the 12** `entryId`s — 4108 absent | `MultiCurrencyPnl.unrated` is exactly `{4108}`. Before the review the CHF rate was published 1 April, on or before the 3 April posting, and `unrated` was **always empty** — the module's advertised finding never happened. The rate is now 4 April. |
| `filterEq readDate @2011/4/22 readings # {station, readDate}` | **0** | with `n = 0` the window filter collapses to `histDate = asOfDate`, so `asOfWithin 0` on Good Friday is empty. `asOfWithin 1` is **not** empty (21 April is inside `histDate <= asOf <= histDate + 1`), which is what the module claimed before the review. |
| `difference (spine # {station, sessionDate}) (rename readDate sessionDate (readings # {station, readDate}))` | **19** | the carried cells, exactly: ESK.UK misses 19/21/27/28, LER.UK 19/20/26/27/28, BOU 19/20/26/27/28, FRD 19/20/27/28/29. The pre-review `carriedCells` computed "every cell whose session is not 18 April" and its comment named the wrong days. |
| `inMonth # {orderId, orderDate, periodShort}` | **10** for 10 orders | `FiscalTree`'s twelve leaf ranges tile the fiscal year: nothing duplicated on a boundary, nothing lost. |

(The SQL was emitted by `sql-render.sh` and executed with a five-line JDBC runner in this
stage's scratch, because the `SqlRun.java` the script names is not in the tree.)

### G5 — this report, the plan row, the wiring lines, and what could not be written

This file; the status row in `tracker/LOOP-MODEL-PLAN.md`; §6 and §7; §8 for the corrections.

---

## 4. Findings

1. **`lookupLatest` and `nearestDate` group by the DATE ALONE.** `nearestDate` is
   `groupBy {ffine} (maxRowBy fsparse) ([| fsparse <= ffine |] (join rsparse rfine))`, and
   `lookupLatest`/`lookupLatest1`/`lookupLatestWithin` are all built on it. On any multi-series
   history the globally latest date wins and a series that stopped reporting disappears.
   Demonstrated in `ReadingHistory.e`: `asOf readDate @2011/4/22 readings` drops `ESK.UK`, because
   another station read on 21 April. `Helpers.nearestBy` is the per-key fix and
   `Helpers.fillForward` builds the (key × day) spine for it. **Ticket-worthy** (the reviewer
   agrees): this is a stdlib defect, not a documentation one.
2. **`asOfWithin` is a BINARY GATE on `asOf`'s answer, not a per-row staleness filter.** New
   since the review, and a consequence of (1). `nearestDateWithin` filters to
   `histDate <= asOfDate <= histDate + n` and then groups by the as-of date — ONE group — so
   `maxRowBy` collapses whatever survived to a single history date. The answer is therefore
   either exactly `asOf`'s (when the globally latest date is inside the window) or empty. It
   can never substitute a series' own older row for a fresher one from another series.
   `ReadingHistory.e` shows n = 3, 1 and 0 side by side: the first two are the global answer and
   only the third is empty.
3. **`nearestDate` maps dates to dates, not tables to tables.** Both relation arguments are
   forced to ONE column by `Field r a`'s singleton row. Passing a fact table gives
   `failed to unify type (|readDate|) with type (|terrain, dataQuality, ...|)`; passing a
   two-column calendar gives `failed to unify type (|sessionDate|) with type (|sessionDate,
   sessionType|)`.
4. **`Relation.Op.dateDiff`'s result row is unconstrained.** The foreign declaration is
   `dateDiff# : PrimitiveTemporal d => TimeUnit -> Op r d -> Op r1 d -> Op r2 Int`, and its
   wrapper `dateDiff` (`Relation/Op.e:151`) has **no signature at all** — the line that would
   have given it one is commented out immediately above — so `r2` is related to neither argument.
   A `combine` of a date difference type-checks over a relation containing neither date column
   and fails at run time with `Operation refers to nonexistent column`. `dateAdd` does not have
   the hole; the fix is one signature. **The clearest ticket in the group** (the reviewer
   verified the run-time failure directly).
5. **`Relation.Aggregate.weightedMean` — and `weightedHarmonicMean` — have no signature** and
   infer value and weight to the same type, so a nullable measure cannot be weighted by a
   non-null weight without `Relation.Op.annul`. **Ticket-worthy**: one signature each.
6. **The `RUnion3` cliff is gone.** `band3` (two nested `if`s) and `band4` (three) each infer a
   residual of ONE constraint, the tautology, and their *shipped* signatures carry none; the
   relation-returning bundled form that `Ai/Common.e` records as never finishing checks in about
   a fifth of a second.
7. **`Math`, `Vector`, `List.Util`, `DateRange`, `Ring`, `Num`, `Long`, `Int` and `Nullable`
   cannot reach a column.** There is no way to lift an Ermine function into an `Op`. Per row
   there is only `Relation.Op`'s own vocabulary and `Relation.Aggregate`'s ten aggregates;
   anything else must be composed out of those or precomputed as a scalar and injected with
   `prim_Op`. `SensorSeries.e` and `FiscalTree.e` do the latter and say so. **`Double.e` is an
   EMPTY module** — two lines, `module Double where` and nothing else — so it cannot be
   exercised at all.
8. **No date-part accessor exists at the `Op` level.** No `year`, `month`, `quarter`, `day`.
   `Date.e` has them as *value*-level functions, which by (7) cannot reach a column. This is the
   most consequential limit in the group: it is why five of the nine reports carry a calendar
   relation and why `bucketBy` and `monthsSince` exist.
9. **`Date`'s accessors read the instant in the JVM's DEFAULT TIMEZONE while its formatters do
   not, so a date literal is two different days at once.** New since the review. Measured for
   the single literal `@2011/1/1`, with and without `-Duser.timezone=UTC`:

   | | system TZ (MDT) | UTC |
   |---|---|---|
   | `unsafeFormatDate` | `"1/1/11"` | `"1/1/11"` |
   | `formatMonthYear` | `"Jan 2011"` | `"Jan 2011"` |
   | `getYear` / `getMonth` / `getDate` | 110 / 11 / 31 | 111 / 0 / 1 |
   | `formatExcelDate` | `"Dec 31"` | `"Jan 1"` |
   | `quarter` / `formatQuarter` | 3 / `"Q4"` | 1 / `"Q2"` |
   | `formatPeriodOr "custom" (1 Jan, 31 Jan)` | `"Jan 2011"` | `"custom"` |
   | `formatPeriodOr "custom" (1 Jan, 1 Apr)` | `"custom"` | `"Q2 2011"` |
   | `formatExcelPeriod (1 Jan, 31 Jan)` | `"Dec 31 to Jan 30"` | `"Jan 1 to Jan 31"` |

   `Date.quarter`, `formatQuarter`, `formatExcelDate` and both of `DateRange`'s period
   formatters are built on the accessors, so **a period label computed with `DateRange` is not
   reproducible across machines**. `FiscalTree.e` carries this table and the values are
   evaluable from its own bindings. **Ticket-worthy.**
10. **`Date.formatQuarter` is wrong on its own terms, in two independent ways.** New since the
    review. `quarter d = getMonth d / 4 + 1` divides by FOUR rather than three, so its
    "quarters" are four months long; and it then indexes the 0-based `quarterNames` with that
    1-based number, so the lookup is off by one and **`"Q1"` is unreachable**. Under UTC,
    1 January reports `"Q2"`; under MDT it reports `"Q4"`. Measured for January, April, July and
    October in `FiscalTree.e`. **Ticket-worthy**, and independent of (9).
11. **`bucketBy`'s inferred type cannot be written down.** With the signature removed the
    compiler infers **32 constraints (23 row partitions, 9 class constraints) over 33
    existentials**, four of the existentials being `(AsOp: (rho -> a -> *) -> f)` — the *class*
    `AsOp` bound as an existential variable of a kind the surface syntax has no binder for — and
    the type opens `forall {a}`, an implicit KIND variable. The compiler prints a type its own
    parser cannot read back. The cause is that the `[| ... |]` sugar is applied to field
    *variables* rather than literal names, so `Relation.Predicate.(<=)`'s `AsOp` constraints are
    generalised over instead of solved. **A pretty-printer/parser round-trip defect**, worth an
    entry in `TICKET-editor-and-solver-followups.md`.
12. **A refutation clause, and every per-solve cost figure, depend on the id base.** See G1 and
    G3. Structural quantities do not.
13. **`Relation.groupBy` returns a `Mem`**, so every grouped roll-up needs `materialize`.
    `aggregateByGroup` does not, and is the better combinator.
14. **`Random` is usable, with caveats — one of them corrected.** `randomInts : Long -> Stream
    Int`; `List.Stream.take n` gives a `List Int`; `map_List` into records feeds `relation`. The
    seed is a `Long` and there is no `Long` literal (use `Date.getTime @2011/6/1`), and `map` is
    not in scope unqualified. Measured: `take 6 (randomInts (getTime @2011/6/1))` gave
    `[1196297743,-519626257,888236693,-374199393,-448392562,1078877423]` three times in one
    session and identically in a second fresh JVM. It is nevertheless not used for corpus data:
    `randomThings` binds **one `java.util.Random` per stream** (not one process-wide, as this
    report first said) and draws from it through `unsafePerformIO`, so reproducibility depends on
    how the stream is forced rather than on the seed alone — and a certification corpus whose
    data could change between runs would invalidate every trace built on it.
15. **Surface-syntax traps**, each recorded in the module that hits it: `{}` is a *record*
    literal, not the empty row (`Relation.Row.empty`); the *types* `Op` and `Aggregate` need
    `import X.Type using type T` even when the module is imported under an alias; a top-level
    definition may not shadow a global, so a day calendar cannot be called `days`; `%` is a
    `Relation.Op` operator with no value-level counterpart; the relational `filter` is shadowed
    by `List.filter` under `Prelude`, so `[| ... |]` is the usable spelling; the `[| ... |]`
    sugar does not accept a date literal (`@2011/4/19`) as a comparand.

---

## 5. Renderings

See G4 — the trimmed rendering of every report, the four relations rendered to SQL and run, and
the note that a rendering with rows in it is not reachable from `bin/ermine`.

---

## 6. Wiring lines the orchestrator must add

Re-checked against E1's landed changes on 2026-09-07. This stage edited no shared file.

**(a) `tracker/tools/corpus-run.sh`** — four edits. The three `case`/`files` hunks are exactly
parallel to the existing `Wide` ones:

```diff
-files=( core/examples/*.e core/examples/Ai/*.e core/examples/Wide/*.e \
-        core/examples/Wide/shouldfail/*.e core/examples/shouldfail/*.e )
+files=( core/examples/*.e core/examples/Ai/*.e core/examples/Wide/*.e \
+        core/examples/Wide/shouldfail/*.e core/examples/Time/*.e \
+        core/examples/Time/shouldfail/*.e core/examples/shouldfail/*.e )
```

```diff
-  bfiles=(); ai_done=0; wide_done=0
+  bfiles=(); ai_done=0; wide_done=0; time_done=0
       core/examples/Wide/Helpers.e) ;;
+      core/examples/Time/Helpers.e) ;;
 ...
+      core/examples/Time/*)
+        if [[ $time_done == 0 ]]; then bfiles+=( core/examples/Time/Helpers.e ); time_done=1; fi
+        bfiles+=( "$f" ) ;;
```

```diff
     core/examples/Wide/Helpers.e) ;;
+    core/examples/Time/Helpers.e) ;;
     core/examples/Wide/*)         args=( core/examples/Wide/Helpers.e "$f" ) ;;
+    core/examples/Time/*)         args=( core/examples/Time/Helpers.e "$f" ) ;;
```

and the header comment E1 keeps current (line 69), whose count must go **79 → 93**:

```diff
-# Directories covered, 79 files: core/examples/*.e (15), core/examples/Ai/*.e (11),
-# core/examples/Wide/*.e (10), core/examples/Wide/shouldfail/*.e (3),
-# core/examples/shouldfail/*.e (40).
+# Directories covered, 93 files: core/examples/*.e (15), core/examples/Ai/*.e (11),
+# core/examples/Wide/*.e (10), core/examples/Wide/shouldfail/*.e (3),
+# core/examples/Time/*.e (11), core/examples/Time/shouldfail/*.e (3),
+# core/examples/shouldfail/*.e (40).
```

**(b) `tracker/tools/looptrace-corpus.sh`** — rewritten against the file as it now stands (E1
changed both the `groups=` line and the group shape, so this report's first version would have
DELETED `Wide` and `Wide-shouldfail`). Insert into the existing list, and follow the `Wide`
shape with `-maxdepth 1` and a separate negatives group:

```diff
-groups="${LOOPTRACE_GROUPS:-boot top Ai Wide Wide-shouldfail shouldfail bugs guide shouldfail-controls incomplete}"
+groups="${LOOPTRACE_GROUPS:-boot top Ai Wide Wide-shouldfail Time Time-shouldfail shouldfail bugs guide shouldfail-controls incomplete}"
```

```diff
     Wide-shouldfail)
           mapfile -t gf < <( { echo core/examples/Wide/Helpers.e
                                find core/examples/Wide/shouldfail -maxdepth 1 -name '*.e' \
                                  | sort; } ) ;;
+    # Time/ is the Wide/ case with a different library: every Time module imports
+    # `Time.Helpers`, and so does every module under Time/shouldfail (stage E3, 2026-09-07).
+    Time) mapfile -t gf < <( { echo core/examples/Time/Helpers.e
+                               find core/examples/Time -maxdepth 1 -name '*.e' \
+                                    ! -name 'Helpers.e' | sort; } ) ;;
+    Time-shouldfail)
+          mapfile -t gf < <( { echo core/examples/Time/Helpers.e
+                               find core/examples/Time/shouldfail -maxdepth 1 -name '*.e' \
+                                 | sort; } ) ;;
```

**(c) `core/examples/README.md`** — one row in E1's `| directory | subject | library |` table,
one line in the code block, and `Time/shouldfail/` in the closing paragraph:

```
| `Time/` | nine reports over **dates** — as-of lookups, calendars, time series, money, nullable arithmetic | `Time/Helpers.e` |
```

```
bin/ermine core/examples/Time/Helpers.e core/examples/Time/ReadingHistory.e
```

**(d) `scalacheck-binding/src/main/scala/TestSurfaceParsers.scala` — WITHDRAWN.** E1 has
replaced the constant with `val expected = moduleFiles.size`; there is nothing to change and
this stage's earlier claim that it was "the only shared file whose change is required" is
retracted.

---

## 7. What could NOT be written, and why

* **A rendering with rows in it.** Finding in G4. The four relations in the G4 table are the
  most that can be got: `sql-render.sh` emits SQL for plain joins, filters and set operations,
  but anything through `materialize` (which is every as-of lookup and every `groupBy` roll-up)
  answers `Emission not supported for sql statement SqlLoad`, a `Mem` answers "Don't know how to
  dump a mem", and `dateAdd` is unemittable on the SQLite backend. **The as-of family is exactly
  the part of this group that cannot be rendered by any route in this repository** — which is why
  the three claims in G4 were settled by rendering their *inputs*.
* **A per-row statistic Ermine does not already have.** Findings 7 and 8. A rolling median, an
  interquartile range, a percentile or a correlation cannot be a column: `Relation.Aggregate` has
  ten aggregates and no extension point, and no Ermine function can be lifted into an `Op`.
* **A calendar-free period label.** Finding 8, and now finding 9 as well: even the labels
  `DateRange` *can* compute are timezone-dependent, so a reproducible report must label its
  periods from a calendar column. Five of the nine reports carry a calendar for this reason.
* **A `DateRange`-valued column.** `DateRange` is seven value-level functions over a
  `(Date, Date)` pair; a range held in an Ermine pair cannot be joined against a fact table.
  `FiscalTree.e` therefore holds each tree node's range as two `Date` COLUMNS and uses
  `DateRange` only to label pairs the program already has.
* **An `xFull` for `bucketBy`.** Finding 11: the compiler's own output for it is not a term of
  the language it accepts.
* **`fillForward` with two separate overlapping key groups.** The shipped signature splits the
  key as `k <- (ko, ck)` with `ck` the part shared with the calendar, which covers both cases in
  the group (a plain day grid, `ck` empty; a per-network session calendar, `ck = {network}`).
  A calendar sharing two *different* groups of columns with two different key parts was not
  attempted.
* **`bucketBy` with a calendar that shares a column with the facts.** Refused by design — Ermine's
  `join` is natural, so a shared column would silently make the cross product an equi-join and
  give a wrong answer instead of an error. That is `shouldfail/bucket01`.
* **A `Random`-seeded report.** Finding 14: usable, deliberately not used.
* **Anything from `Double.e`.** Finding 7: the module is empty.
* **A `Bool` column, or a `Nullable Date`.** Not attempted; every flag in the group is a
  `String`. `Null Double` works because `Double` is a `Prim Double` value; `Null Date` was not
  tested.


---

## 8. Post-review corrections (2026-09-07)

Applied after `tracker/loopmodel/E3-REVIEW.md` (FIX-THEN-ADVANCE). Everything below is a change
to this stage's own files; no shared file was touched.

### 8a. Three claims the data denied — all now measured (§G4 table)

| where | was | now |
|---|---|---|
| `MultiCurrencyPnl.e` | "the 3 April posting picks up nothing at all because CHF has no rate before 1 April -- and that MISSING ROW is the report's finding". The CHF rate was published **1 April**, on or before the 3 April posting, so `unrated` was **always empty** and the section printed zero rows. | The CHF fixing moved to **4 April**. Rendered candidate set: 20 rows covering 11 of 12 `entryId`s, 4108 absent. `unrated` is exactly `{4108}` and the finding happens. |
| `MultiCurrencyPnl.e` | "the 12 March weekend posting picks up the 4 March GBP rate" | "the **5 March** weekend posting (entry 4105, a Saturday)" — the file's own fact table says 5 March. |
| `MultiCurrencyPnl.e` | "STEP 3. Translate. 27 columns." | "`pnlRated` is 27 columns and `translated` is 28." |
| `MultiCurrencyPnl.e` | `unitCostZeroed = combine_Op (orZero unitCost) periodTotal ledger`, captioned "the same **total** with nulls read as zero … when the aggregate is a mean" — a per-row column under a field called `periodTotal`, and no aggregate at all. | Two real aggregates, `unitCostMeanSkipped` (divides by nine) and `unitCostMeanZeroed` (divides by twelve), both in the report; the per-row column kept under `unitCostZero`. `periodTotal` deleted. |
| `ReadingHistory.e` | "at three days the 21 April rows still qualify; at ONE day nothing does, and an empty result is the correct answer" — `asOfWithin 1` is **not** empty (the filter is `histDate <= asOf <= histDate + n`, so n = 1 admits 21 April) and `asOfWithin 3` returns exactly the global answer, so the section contrasting three lookups showed one. | Three calls — n = 3, 1 and **0** — with the algebra spelled out: the window is a BINARY GATE (new finding 2), n = 3 and n = 1 are both the global answer and only n = 0 is empty. Rendered: `filterEq readDate @2011/4/22 readings` is 0 rows. |
| `ReadingHistory.e` | `carriedCells = difference X (X |> filterEq sessionDate @2011/4/18)` — "every cell whose session is not 18 April", not "sessions where a station had no reading"; and the named days ("19, 27 and 28 April for both names") were wrong. | Rewritten as `difference (perStation # {station, sessionDate}) (rename readDate sessionDate (readings # {station, readDate}))`, the `gapDays` idiom. Rendered: **19 rows**, and the comment now names them per station, correctly. `carriedCells` and `staleFlags` were both dead; both are now in `readingReport`. |
| `EmployeeTenure.e` | `headcountByBand = groupBy {ageBand, department} (sumBy tenureDays)` — a sum of service days under a name and a report title promising a headcount; header claimed aggregates "with `mean` and `count`" and there was no count; `headcount`, `meanSalary`, `bonusTotal` declared and unused. | `headcountByBand` is `aggregateByGroup countAgg`, a real headcount; the sum keeps its own name `serviceDaysByBand`; `meanSalaryByLevel` renames onto `meanSalary`; `bonusPctTotal` renames onto `bonusTotal`. All three fields used, both new relations in the report. |
| `InterestAccrual.e` | "One row, eleven columns"; "EVERY aggregate in `Relation.Aggregate`" with `weightedHarmonicMean` unused. | `weightedHarmonicMean` **added** (amount-weighted, `annul_Op` on the weight, with a sentence on why it is the right average for a rate), so the panel is **ten** columns and the claim is true. |
| `DemandForecast.e` | `safeDiv` listed in the header and never called. | `safeDiv` now computes a load factor against the rolling maximum, which is zero on a partition's first row. |

### 8b. Five (in fact seven) clashing top-level names

`banded` (EmployeeTenure, InterestAccrual, SubscriptionWaterfall), `indexed` (CohortRetention,
ReadingHistory, SubscriptionWaterfall), `scored` (DemandForecast, SensorSeries), `rated`
(InterestAccrual, MultiCurrencyPnl), `smoothed` (DemandForecast, ReadingHistory) — every one
`undefined term` in the session `Time/README.md` prescribes — plus `valued` and `byPeriod`, which
`FiscalTree.e` would have added. All renamed (`momBanded`, `accrualBanded`, `tenureBanded`,
`monthIndexed`, `meanIndexed`, `cohortIndexed`, `forecastScored`, `sensorScored`, `accrualRated`,
`pnlRated`, `meanSmoothed`, `demandSmoothed`, `orderValued`, `byFiscalPeriod`). The group now has
**no duplicate top-level term name**, and the README's own group-load session evaluates 80
bindings with zero errors.

### 8c. Census corrections

Every figure re-measured on the post-review bytes, in two file orders (§3, G3).

| cell | was | now |
|---|---|---|
| segments | 115,674 | **125,176** (a module was added) |
| solves in the group | 43,258 | **50,822** |
| draws per solve, max | 13 | **16 (order A) / 17 (order B)** |
| dequeues, max / total | 60 / 16,360 | **62 / 18,748 (A)**, 60 / 18,737 (B) |
| resolution steps, max / total | 7 / 471 | **9 / 515 (A)**, 10 / 533 (B) |
| "decision nodes" | 60 | relabelled: **dequeues** 62; *distinct states* is 63 |
| "per-key mints, max" 4 / `Ai` 8 | mislabelled | those are mint **KEYS** (5 / 8); the **per-key maximum is 1** in both, which is what E2's review reports for its group |
| the five costliest solves | five `combine_Op` sites "all at drawn=13" | four of the five did not reproduce; the block is replaced, and **the group's heaviest solve is a `fillForward` call site** (`SensorSeries.e(194:10)` at 16 draws in order A, `ReadingHistory.e(252:11)` at 17 in order B) — the shape the brief predicted, which the first census missed |
| budget headroom | 1,538× | **1,176×** (17 draws against 20,000) |
| "3.8× the row variables … of anything in the previous corpus" | read as a wide-row claim | it is `band4`'s **definition-site** conditional lattice over one column (depth 0, no labels, ≤ 7 draws). **At a call site the maximum is 11 variables / 7 partitions — exactly `Ai`'s.** The wide rows moved the **label table** (31 vs 14) and the heaviest solve. |
| RUnion form C's residual | "a mere seven constraints" | **eight** (the report's own quoted block listed eight) |
| `bucketBy`'s inferred type | "thirty-four constraints over thirty-four existentials" | **32 constraints (23 row + 9 class) over 33 existentials**, four of them `AsOp` binders |
| `Signatures.e` | "eight helpers", "8 entailment proofs" | **nine** `xDeduped = xFull` proofs; **five** are full `xFull`/`xDeduped`/`xSimple` triples, and for the other four the deduped set *is* the shipped signature |
| the `Random` caveat | "one shared mutable generator" | **one generator per stream**, created from the seed each time `randomInts s` is evaluated; the sharing is within a stream and depends on how it is forced |
| `sbt core/test` | "912/914, one failure is the hard-coded corpus size" | **withdrawn**: E1 derived the count; the three sweeps pass 20/20 |

### 8d. Coverage gap closed, and the smaller claims fixed

* **`FiscalTree.e` (new, 18-column fact row).** A fiscal calendar held as a **tree of date
  ranges** — the `Ai/FiscalCalendar.e` parent/child id shape, with each node also carrying its
  own `(start, end)` pair, so one relation is both a `drilldownTable` hierarchy and a set of
  ranges to `bucketBy` against. It puts a **tree-shaped fine relation under `nearestBy`** (the
  tariff in force at each period start, per service class), which neither this directory nor
  `Ai/` reached; it exercises **all seven `DateRange` functions** and all of `Ring`, `Num`,
  `Long`, `Int` and `Nullable`'s own functions at the value level; and it measures the two
  `Date.e` defects (findings 9 and 10) in a table a reader can re-evaluate from its own bindings.
  It also records that `Double.e` is empty.
* `Helpers.e` and `README.md`: "before this directory NOT ONE of them had an example" → only
  `nearestDateWithin` had, in `incomplete/RunCalibration.e` and `incomplete/Signatures.e`;
  `Wide/BranchDeposits.e` calls `lookupLatest` concurrently. "six date-keyed combinators" →
  **eight**, and `lookbackJoin` — previously unmentioned — is now a helper (`lookback`) with a
  call site.
* `ReadingHistory.e`: "the six … questions **the stdlib** can answer" counted a `Time.Helpers`
  function and missed three stdlib forms. Rather than weaken the claim, three helpers were added
  — `asOfEachWithin` (`lookupLatestWithin`), `nearestWithin` (`nearestDateWithin`) and `lookback`
  (`lookbackJoin`) — so **all eight** now have a call site, and `Helpers.e` is 37 helpers.
* `DemandForecast.e`: `timeSeriesChart` had **two** callers before this directory
  (`Ai/BatteryCycling.e` and `ChartsExample.e`), not one; the module's claim is now that neither
  put a window function on the series it plots.
* `CohortRetention.e`: `aggregateByGroup` is used by `core/examples/Present/` too; and the dead
  `cohortIx` column now keys `cohortCountsByIx`, in the report.
* `SensorSeries.e`: sensors are `101`–`104`, not `S-102`/`S-104`; sensor 102's mid-window hole is
  **four** days, not three; the field `deviation` carried two different quantities and is split
  into `devFromMean` and `rmsRatio`.
* `Helpers.e`: the quoted `dateDiff#` declaration regains its `TimeUnit ->` parameter, and the
  sentence claiming `safeDiv`/`band3` "DO carry `RUnion3`" is replaced — neither *shipped*
  signature does; the lattice appears only in the inferred type.
* `Signatures.e`: a note that the compiler minted `sd`/`fd` with the opposite meanings in
  `nearestByFull` from the ones `nearestBySimple` uses.
* Both row-partition negatives record **both** refutation clauses and the id-base reason, in
  place of the narrower "per file vs batch" story.
