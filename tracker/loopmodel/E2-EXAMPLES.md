# E2 — `core/examples/Algebra/`: the relational-algebra corners and the generic helpers around them

Stage E2 of `tracker/LOOP-MODEL-PLAN.md`. Brief: `tracker/loopmodel/briefs/brief-E2.md` on top of
`briefs/brief-E-common.md`. Repository at `2dd7dc3` (branch `scala3-migration`), the three row-solver
defaults adopted (`-Dermine.rowSound` on, `-Dermine.dequeuePolicy=smallcanon`,
`-Dermine.solveBudget=20000`). Every `bin/ermine` below ran with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time, 2026-09-06/07.

**Outcome: GREEN.** THIRTEEN `.e` modules under `core/examples/Algebra/` (twelve, plus `Comprehensions.e`
added at review) plus six negatives under `core/examples/Algebra/shouldfail/` and a group `README.md`.
**Reviewed 2026-09-07: FIX-THEN-ADVANCE**; every finding applied, §8 lists old → new. Everything that should load, loads; all six
negatives are rejected with the recorded diagnostic; the L2 differential over the group is
**156,368 segments, 0 skipped / 0 hashdiff / 0 eqdiff**; the census is reported below.
`sbt core/test` is **912/914**: one pre-existing failure plus one shared file-count constant that
every E-stage trips (`Expected 271 but got 315`) — see §G1(d) and §6(d). Neither is a defect in this
group.

---

## 1. The files

| module | subject | fields per fact row | helpers used | shapes exercised | check (per file / in batch) |
|---|---|---|---|---|---|
| `Helpers.e` | the generic library, 33 helpers | — | — | signatures publishing partition constraints; counts in §G4(b) | 1.05 s / 0.82 s |
| `OrderLedger.e` | order lines against five dimensions, three of them missing rows | **16** (`orderLines`); dims 4/4/2/3 | `enrich`, `enrichRight`, `lookupOr`, `semiJoin`, `antiJoin`, `intersectRows`, `exceptRows`, `groupSum` | `joinWithDefault`'s `exists c s.` instantiated twice; `leftJoinOr` against a RECORD row; `difference` over two 16-column concrete headers | 0.78 s / 0.35 s |
| `BillOfMaterials.e` | a BOM exploded, leaves, cost roll-up | 7 (`bom`) + **12** (`partDim`) | `closure`, `composeEdges`, `leaves`, `carry`, `alias`, `groupSum`, `semiJoin` | RECURSIVE definition carrying a partition; a GUID-named scratch column from `withFieldCopy`; `Relation.RTree`; `accumulate` | 1.38 s / 0.70 s |
| `Customer360.e` | six systems, six names for one customer | 4 each, joined to **19** | `alias`×6, `enrich`, `translate`, `dedupeBy`, `semiJoin`, `antiJoin`, `groupSum`, `carry`, `joinOnExactly` | six concrete-header cancellations then a 20-column `joinBy`; `partialLookup`'s `coalesce'` under a rename and an `except` | 0.71 s / 0.52 s |
| `InventorySnapshots.e` | two snapshots reconciled | **14**, twice | `unionRows`, `exceptRows`, `intersectRows`, `semiJoin`, `antiJoin`, `alias`, `joinOnExactly`, `groupSum`, `groupTop` | fourteen set operations over one 14-column concrete header — the `concrete` branch at its widest and most repetitive; `unionAllWithHeader` | 0.65 s / 0.50 s |
| `Deduplication.e` | a change feed, latest wins | **15** | `dedupeBy`, `groupTop`, `groupBottom`, `pickHighest`, `pickLowest`, `exceptRows`, `semiJoin`, `antiJoin` | four different `groupBy` group functions against one 15-column row; `exceptRows` proving the header survived a `Mem` round trip | 0.54 s / 0.38 s |
| `SoftSchema.e` | key/value telemetry widened three ways | 3 (soft) + **12** (`assetDim`) | `alias`, `lookupOr`, `semiJoin`, `antiJoin`, `groupTop` | five `except`s against five concrete two-column headers folded into one join; `keyValueTabular`'s THREE-part partition with `i` found by subtraction; `Relation.Pivot`'s eleven-existential residual | 0.70 s / 0.43 s |
| `ManagerChains.e` | an org chart, self-joined | **14** | `alias`×6 (five of them one rename sequence), `carry`, `joinOn1`, `joinOnExactly`, `closure`, `leaves`, `semiJoin`, `antiJoin`, `groupSum`, `groupTop` | five renames in sequence over one concrete header, then a `join1` whose witness must be in the intersection of two headers derived from the SAME one | 0.68 s / 0.37 s |
| `LedgerScan.e` | a general ledger, scanned | **13** | `scanTotals`, `scanCounts`, `semiJoin`, `groupSum` | a partition's OUTPUT row flowing into another partition's input (`groupBy1`'s `t` into `sumBy'`'s `r`) — the shape this directory has least of elsewhere | 0.66 s / 0.49 s |
| `RateStatistics.e` | interlaboratory runs, four averages | **13** | `groupMean`, `groupMedian`, `groupWeightedMean`, `groupSum`, `groupTop`, `alias`, `joinOnExactly`, `antiJoin` | four group functions with four constraint sets against one row, then the four one-column results joined back; `groupWeightedMean`'s three-part `v <- (wt, m, o)` | 0.55 s / 0.28 s |
| `KeyDiscipline.e` | readings valued, key written down | 12 + 7 + 5 | `joinOn1`, `joinOnExactly`, `joinOnAtLeast`, `carry`, `overwriteWith`, `semiJoin`, `groupSum` | `joinBy'`'s head/tail key split — `kt` found by a set difference of two concrete headers; `memoRelWithPK` / `letRWithPK`'s `Has r k` under a higher-order argument | 0.70 s / 0.36 s |
| `Comprehensions.e` | one report in two syntaxes, plus the three outer joins nobody else used | **12** (`orders`) | `lookupOrRight`, `rightOuter`, `translateKeeping`, `runningTotal`, `groupSum`, `antiJoin`, `alias` | `Syntax.Relation`'s parse-time rewrite in all three clause forms and combined — the `exists`-heavy residual `Syntax/Relation.e`'s own header advertises; the group's only DELIBERATE cartesian product and its only NESTED `withFieldCopy` (two GUID labels in one solve) | 1.66 s / 0.99 s |
| `Signatures.e` | the `xFull`/`xDeduped`/`xAsWritten` proofs | — | — | eight entailment proofs, each a definition `p = q`; the fourth over a 21-constraint / 27-existential inferred set | 0.58 s / 0.38 s |
| `shouldfail/alg01…alg06` | six negatives | 1–4 | the helper each misuses | four distinct refutation classes (see §G1(c)) | 0.37–0.73 s each |

Per-file figures are the module's own `Importing module` time in a session that also loaded
`Helpers.e`; wall clock per file is 8.6–12.5 s of which ~7–8 s is the stdlib boot. In-batch figures
are from the one-JVM run in §G1(b). All figures are the POST-REVIEW measurement of 2026-09-07.
Nothing is over 30 s; nothing needed `.slow`; the draw budget never fired.

## 2. The helpers, verbatim, with what they publish

All 33 helpers carry explicit signatures. The `.ei` the compiler publishes (below each) is the
signature the author wrote, with the constraint list permuted and `Has` expanded — **no weakening, no
extra constraints, no residual the author did not write**. Snapshot taken with
`-Dermine.useInterface=true` on the whole group and read out of `core/examples/Algebra/Helpers.ei`
(the file is deleted again; the gate's rule).

### joins

```
lookupOr : forall rel extra a r1 r2 r3.
           (exists c s. r1 <- (c, s), r2 <- (c, extra), r3 <- (c, s, extra),
            PrimitiveAtom a, RelationalComb rel)
        => Field extra a -> a -> rel r1 -> rel r2 -> rel r3
lookupOr = joinWithDefault
```
published: `(exists (c: rho) (s: rho). r1 <- (c, s), r2 <- (c, extra), Builtin.PrimitiveAtom a, r3 <- (c, s, extra), Builtin.RelationalComb rel)` — the stdlib's only existentially quantified row constraints, published intact.

```
enrich : (RelationalComb rel, r1 <- (r, s), r2 <- (s, t), r3 <- (r, s, t))
      => rel r1 -> rel r2 -> {..t} -> rel r3
enrich = leftJoinOr

enrichRight : (RelationalComb rel, r1 <- (r, s), r2 <- (s, t), r3 <- (r, s, t))
           => rel r1 -> rel r2 -> {..r} -> rel r3
enrichRight = rightJoinOr
```
published: `(r3 <- (r, s, t), r2 <- (s, t), r1 <- (r, s), RelationalComb rel)` for both; note `{..t}` is published as `Builtin.Record t`, so the default record's row is the SAME variable as the dimension's private row — which is exactly why `shouldfail/alg01` fails.

```
semiJoin : (RelationalComb rel, r <- (k, o), p <- (k, q))
        => Row k -> rel p -> rel r -> rel r
semiJoin ks probe r = join r (project ks probe)

antiJoin : (RelationalComb rel, r <- (k, o), p <- (k, q))
        => Row k -> rel p -> rel r -> rel r
antiJoin ks probe r = difference r (semiJoin ks probe r)
```
published: `(p <- (k, q), r <- (k, o), RelationalComb rel)` for both.

```
intersectRows : RelationalComb rel => rel r -> rel r -> rel r
intersectRows = join
exceptRows : RelationalComb rel => rel r -> rel r -> rel r
exceptRows = difference
```
published: `RelationalComb rel => rel r -> rel r -> rel r` — no partition at all, which is the point: one row variable used three times IS the set-operation contract.

```
joinOn1 : (Relational rel, ra <- (k, r1), rb <- (k, r2), r <- (k, r1, r2))
       => Field k a -> rel ra -> rel rb -> rel r
joinOn1 = join1

joinOnExactly : (Relational rel, r1 <- (k, t1), r2 <- (k, t2), r <- (k, t1, t2))
             => Row k -> rel r1 -> rel r2 -> rel r
joinOnExactly = joinBy

joinOnAtLeast : (Relational rel, r1 <- (kh, kt, t1), r2 <- (kh, kt, t2),
                 r <- (kh, kt, t1, t2))
             => Row kh -> rel r1 -> rel r2 -> rel r
joinOnAtLeast = joinBy'
```
published verbatim (order permuted). `joinOnAtLeast`'s `kt` appears in all three constraints and in no
argument type — it is the only stdlib signature that asks the solver to compute a set difference of
two concrete headers to find a key.

```
translate : (RelationalComb rel, PrimitiveAtom a, kv <- (key, val), r <- (key, o))
         => Field key a -> Field val a -> rel kv -> rel r -> rel r
translate = partialLookup
```

### columns

```
carry : (Relational rel, ri <- (src, o), ro <- (src, dst, o))
     => Field src a -> Field dst a -> rel ri -> rel ro
carry = copyColumn

alias : (RelationalComb rel, r <- (from, o), out <- (to, o))
     => Field from a -> Field to a -> rel r -> rel out
alias = rename

overwriteWith : (RelationalComb rel, r <- (from, to, o), out <- (to, o))
             => Field from a -> Field to a -> rel r -> rel out
overwriteWith = rename'
```
`alias` and `overwriteWith` differ by ONE constraint — `to` on the input side — and are therefore type
errors in exactly complementary situations. There is no stdlib helper that does whichever is needed.

### grouping

```
groupSum : (Relational rel, kv <- (k, v), v <- (m, o), out <- (k, m), PrimitiveNum n)
        => Row k -> Field m n -> rel kv -> Mem out
groupSum ks amt r = groupBy ks (sumBy amt) r

groupMean : (Relational rel, kv <- (k, v), v <- (m, o), out <- (k, m), PrimitiveNum n)
         => Row k -> Field m n -> rel kv -> Mem out
groupMean ks amt r = groupBy ks (meanBy amt) r

groupTop : (Relational rel, kv <- (k, v), v <- (ord, o))
        => Row k -> Row ord -> Int -> rel kv -> Mem kv
groupTop ks ord n r = groupBy ks (topK ord n) r

groupBottom : (Relational rel, kv <- (k, v), v <- (ord, o))
           => Row k -> Row ord -> Int -> rel kv -> Mem kv
groupBottom ks ord n r = groupBy ks (bottomK ord n) r

dedupeBy : (Relational rel, kv <- (k, v), v <- (ord, o))
        => Row k -> Row ord -> rel kv -> Mem kv
dedupeBy ks ord r = groupTop ks ord 1 r

pickHighest : Has r ord => Row ord -> [..r] -> [..r]
pickHighest = firstBy
pickLowest : Has r ord => Row ord -> [..r] -> [..r]
pickLowest = lastBy
```
`pickHighest`/`pickLowest` publish the `Has` alias expanded: `(exists (c: rho). r <- (ord, c))`.
The names are deliberate: `Relation.firstBy` is a DESCENDING limit and so returns the highest row,
`lastBy` the lowest — the reverse of what the names suggest.

### `Relation.Process` pipes

```
groupMedian : (Relational rel, kv <- (k, v), v <- (m, o), out <- (k, m), PrimitiveNum n)
           => Row k -> Field m n -> rel kv -> Mem out
groupMedian ks m r = groupBy ks (medianBy_Proc m) r

groupWeightedMean : (Relational rel, kv <- (k, v), v <- (wt, m, o), out <- (k, m), PrimitiveNum n)
                 => Row k -> Field wt n -> Field m n -> rel kv -> Mem out
groupWeightedMean ks wf mf r = groupBy ks (weightedMeanBy_Proc wf mf) r
```
`Relation.Process`'s aggregators are already `rel r -> Mem v`, which is exactly `groupBy`'s group-function
shape, so these are one line each. Neither module had any example use before.

### the five added at review

```
unionRows : RelationalComb rel => rel r -> rel r -> rel r
unionRows = union

lookupOrRight : forall rel extra a r1 r2 r3.
                (exists c s. r1 <- (c, s), r2 <- (c, extra), r3 <- (c, s, extra),
                 PrimitiveAtom a, RelationalComb rel)
             => Field extra a -> a -> rel r2 -> rel r1 -> rel r3
lookupOrRight = rightJoinWithDefault

rightOuter : (RelationalComp rel, r1 <- (r, s), r2 <- (s, t), r3 <- (r, s, t))
          => rel r1 -> rel r2 -> rel r3
rightOuter = unsafeRightJoin

translateKeeping : (RelationalComb rel, PrimitiveAtom a, kv <- (key, val),
                    r <- (key, base), r2 <- (key, val, base))
                => Field key a -> Field val a -> rel kv -> rel r -> rel r2
translateKeeping = partialLookup'

runningTotal : (r <- (ord, amt, o), out <- (r, tot), PrimitiveNum n)
            => Field ord k -> Field amt n -> Field tot n -> Mem r -> Mem out
runningTotal ordF amtF totF r =
  withFieldCopy ordF (o' ->
  withFieldCopy amtF (a' ->
    let prior = rename amtF a' (rename ordF o' (r # {ordF, amtF}))
        pairs = filter_Pred (col_Op o' <=_Pred col_Op ordF) (join prior (r # {ordF}))
        sums  = rename a' totF (groupBy {ordF} (sumBy a') pairs)
    in join r sums))
```
`rightOuter` is the only user of the class `RelationalComp`, which appears in the stdlib in three
COMMENTED-OUT signatures and in `unsafeRightJoin`'s, and nowhere else. It resolves and the wrapper
checks. `runningTotal` is the group's only deliberate cartesian product (two renamed copies with no
column in common) and its only nested `withFieldCopy`, and its two constraints are proved equivalent
to the twenty-one the compiler infers without them (§8, `Signatures.e`).

### hierarchies

```
composeEdges : (e <- (from, to))
            => Field from a -> Field to a -> [..e] -> [..e] -> [..e]
composeEdges f t ab bc = withFieldCopy t (m ->
  except {m} (join (rename t m ab) (rename f m bc)))

closure : (e <- (from, to))
       => Field from a -> Field to a -> Int -> [..e] -> [..e]
closure f t n e =
  if (n <=_Primitive 0)
     e
     (closure f t (n - 1) (materialize (union e (composeEdges f t e e))))

leaves : (r <- (parent, child, o))
      => Field parent n -> Field child n -> [..r] -> [..r]
leaves = leafRows
```
`closure` is the only recursive definition in the library; `e <- (from, to)` is discharged at the
recursive call as well as at the top, and publishes unchanged. `composeEdges` renames a column to a
GUID-named scratch column that `withFieldCopy` mints, joins on it, and projects it away — so the
solver reasons about a label that appears in no header anywhere.

### scans

```
scanTotals : (r <- (h, m), PrimitiveNum n)
          => Field h k -> Field m n -> Field tot n
          -> [..r] -> Scan_Sc (Report f z) (k, Relation tot)
scanTotals key amt tot r = sumBy'_Sc (col_Op amt) tot (groupBy1_Sc key r)

scanCounts : (r <- (h, o))
          => Field h k -> Field c Int -> [..r] -> Scan_Sc (Report f z) (k, Relation c)
scanCounts key cf r = count'_Sc cf (groupBy1_Sc key r)
```
`scanTotals` has NO remainder (`r <- (h, m)`, not `r <- (h, m, o)`) and that is forced, not chosen:
`Relation.Scan.sumBy'` constrains the aggregate's `Op` row to be the WHOLE group row, so the caller
must project to key-and-measure first. `scanCounts`, whose `count'` takes no `Op`, can carry a
remainder. That asymmetry is in the stdlib, not in this library.

## 3. Gates

### G1(a) — every module loads, per file

One JVM per file, `bin/ermine core/examples/Algebra/Helpers.e <file>`, `.ei` deleted first
(post-review, 2026-09-07):

```
Helpers.e             wall=10904ms  own 1.05s      OrderLedger.e         wall= 9050ms  own 0.78s
BillOfMaterials.e     wall=12368ms  own 1.38s      RateStatistics.e      wall= 8909ms  own 0.55s
Comprehensions.e      wall=12454ms  own 1.66s      Signatures.e          wall= 8604ms  own 0.58s
Customer360.e         wall=10505ms  own 0.71s      SoftSchema.e          wall= 9137ms  own 0.70s
Deduplication.e       wall= 9291ms  own 0.54s      KeyDiscipline.e       wall= 8915ms  own 0.70s
InventorySnapshots.e  wall= 9833ms  own 0.65s      ManagerChains.e       wall= 8972ms  own 0.68s
LedgerScan.e          wall= 8961ms  own 0.66s
```
**Thirteen of thirteen LOADED, `rc=0`, zero `Unable to load`; six of six negatives REJECTED**
(`unable=1` each, 8.1–10.9 s wall, 0.38–0.46 s to refuse). Nothing over 30 s. No `.slow`. The slowest
module is now `Comprehensions.e` at 1.66 s — the comprehension rewrite, the deliberate cartesian
product and the nested `withFieldCopy` in one file, which is what it is there to exercise.

### G1(b) — the whole group in one JVM

`bin/ermine core/examples/Algebra/Helpers.e $(ls core/examples/Algebra/*.e | grep -v 'Helpers\.e')
core/examples/Algebra/shouldfail/*.e` — post-review run: **rc=0, 14,808 ms wall, 13 modules imported
and 6 negatives rejected**. Own times in that batch: Comprehensions 0.99, Helpers 0.82,
BillOfMaterials 0.70, Customer360 0.52, InventorySnapshots 0.50, LedgerScan 0.49, SoftSchema 0.43,
Deduplication 0.38, Signatures 0.38, ManagerChains 0.37, KeyDiscipline 0.36, OrderLedger 0.35,
RateStatistics 0.28 — **sum of the group's own check time 6.57 s** for thirteen modules, against
5.55–8.20 s for twelve before review. The six negatives cost 0.04–0.07 s each to refuse.

### G1(c) — the negatives

All six REJECTED, each with one diagnostic, at the position its header records (post-review
positions; `alg05` and `alg06` moved when their headers were rewritten):

| module | position | diagnostic (whole-group batch) | class |
|---|---|---|---|
| `alg01_default_record_missing_column` | 43:7 | `error: failed to unify type (\|customerName, customerTier\|) with type (\|customerName\|)` | unification |
| `alg02_difference_mismatched_headers` | 41:7 | `error: failed to unify type (\|sku, binCode, onHandQty, allocatedQty\|) with type (\|sku, binCode, onHandQty\|)` | unification |
| `alg03_unify_cross_schema` | 44:7 | `Row partitions are unsatisfiable at field '…customerId': the whole contains it but no part does` | rowSound blame |
| `alg04_dedupe_key_contains_order` | 45:7 | `Fields appear twice in row: …eventVersion` | `RHS.merge`, reached by substitution |
| `alg05_join1_two_shared_columns` | 70:7 | `… '…readingDate': the whole contains it but no part does` | rowSound blame |
| `alg06_semijoin_probe_missing_key` | 66:7 | `… '…customerId': a part contains it but the whole does not` | rowSound blame |

**FINDING F4, sharpened by the review and by re-measuring after the fixes.** The FIELD and the
POSITION are stable; the CLAUSE is not, and the review showed my original headers had the matrix
wrong for `alg06`. The measured matrix on the post-review tree (2026-09-07, adopted defaults):

| command line | alg05 | alg06 |
|---|---|---|
| `bin/ermine Helpers.e <the one module>` | whole/no-part | whole/no-part |
| `bin/ermine Helpers.e shouldfail/*.e` | **two-parts** | **part/not-whole** |
| `bin/ermine Helpers.e <12 reports> shouldfail/*.e` | whole/no-part | **part/not-whole** |

**The two modules flip at DIFFERENT points** — `alg05` on the shouldfail-only line, `alg06` on the
per-file line — so neither is a special case of the other; my original headers were written as if
they behaved alike, which is what the reviewer caught. And the matrix itself moves under edits that
have nothing to do with either module: adding ONE definition (`unionRows`) to `Algebra/Helpers.e`
changed `alg06`'s whole-group clause from whole/no-part to part/not-whole, at the same field and the
same position. Both headers now carry the full matrix and say so. **A regression test must pin the
field and the position and must never pin the sentence.**

### G1(d) — `sbt core/test`

**912 / 914, Failed 2, Errors 0** (`sbt -batch core/test`, 405 s wall — see the caveat below):

```
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
[info] ! Surface parser 2.3a.headers agree with the fused pipeline across the stdlib:
         Falsified after 0 passed tests.
[info] > Labels of failing property:
[info]   Expected 271 but got 315
[info]   315 files
[info] Failed: Total 914, Failed 2, Errors 0, Passed 912
```

* `Constraints.disjunction sound` is the **pre-existing** generator-starvation failure documented in
  `tracker/06-tests.md`. Not mine, not new.
* `Surface parser 2.3a.headers agree …` is the **shared file-count constant**, and it is the ONLY
  thing in `core/test` that any E-stage moves. `TestSurfaceParsers.scala:81` ends
  `((files ?= 271) :| s"$files files")`, where `files` counts every `.e` under
  `core/src/main/resources/modules` (161) and `core/examples` (110 at `2dd7dc3`). At the moment of
  this run the tree held 315: 161 stdlib + 110 original examples + **18 from E2** + 13 from E1
  (`Wide/`) + 13 from E3 (`Time/`). The property is a HEADER-AGREEMENT property; its 315 headers all
  agreed — nothing about my modules failed to parse — and only the count assertion falsified. Fix in
  §6(d). Nothing else needs touching: `TestStatementExtents`'s three "271 files" properties name the
  count in their titles but do not assert it, and all three passed on 315 files;
  `TestTolerantRead`'s bound is `>= 180`, its `notGoodCode` set matches the PARENT DIRECTORY NAME so
  `Algebra/shouldfail` is excluded automatically, and its corpus sweep passed.
* WALL CLOCK IS NOT COMPARABLE this round. 405 s was measured with another agent's `sbt core/test`
  and a third agent's `bin/ermine` running concurrently on the same 12-core box (load average 8.9–13.6).
  The group's own contribution is bounded above by its own check time, **5.55 s** (§G1(b)); the six
  negatives add nothing to the type-checking sweeps because `shouldfail/` is excluded from them.

### G2 — the L2 differential on the group

Traced with `-Dermine.useInterface=false -Dermine.loadInSeries=true -Dermine.rowTrace=…`, replayed with
`tracker/lean/.lake/build/bin/looptrace --replay`, classified with
`tracker/tools/looptrace-diff.py --segments --per-thread`.

| group | segments | replayed | skipped | hashdiff | eqdiff | nonpart | rejected |
|---|---|---|---|---|---|---|---|
| `Algebra` (13 modules + boot) | 101,001 | 101,001 | 0 | 0 | 0 | 1,989 | 0 |
| `Algebra/shouldfail` (6 + boot) | 55,367 | 55,367 | 0 | 0 | 0 | 1,100 | 3 |
| **total** | **156,368** | **156,368** | **0** | **0** | **0** | 3,089 | 3 |

`AGREE 101001 / SKIP 0` and `AGREE 55367 / SKIP 0`; one thread each (serialized loader).
(Before review, with twelve modules: 96,815 + 55,178 = 151,993, also 0/0/0 — reproduced exactly by
the reviewer. `Comprehensions.e` adds 4,186 segments and the header edits to the six negatives add
189, because a `sin` segment is a `solve` and the negatives' longer headers shift nothing but the
solve count of `Helpers.e`, which grew by five definitions.)
The model's three `#REJECTED` lines carry the compiler's own sentence, e.g.

```
#REJECTED  55177  Row partitions are unsatisfiable at field
                  'Algebra.Shouldfail.Alg06.customerId': a part contains it but the whole does not
```

**No disagreement of any kind**, before or after the review's fixes. Compiler trace time 22 s + 17 s.

### G3 — the census, against a same-run baseline

`looptrace --replay … --cycle | --depth | --mints`, aggregated per solve. The published round-7/8
figures (≤4 chain depth, ≤11 per-key mints, 97.4 % vocabulary-fixed, 2.6 % generative, ~25 % concrete)
use ROW-CARRYING solves as the denominator; both denominators are given here. `Ai` was traced in the
same session as a directly comparable baseline, and the stdlib boot as a floor.

| population | solves | vocab-fixed | generative | concrete | max draws | max dequeues | max mint depth | max per-key mints | max parts | max vars | max labels |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Algebra reports, all (13) | 37,563 | 99.61 % | 0.43 % | 5.85 % | 53 | 184 | 3 | 1 | 22 | 32 | 26 |
| Algebra reports, row-carrying | 7,932 | 98.15 % | 2.05 % | **27.71 %** | 53 | 184 | 3 | 1 | 22 | 32 | **26** |
| Algebra shouldfail, all | 102 | 95.10 % | 5.88 % | 8.82 % | 3 | 16 | 1 | 1 | 5 | 6 | 4 |
| Algebra shouldfail, row-carrying | 19 | 73.68 % | 31.58 % | 47.37 % | 3 | 16 | 1 | 1 | 5 | 6 | 4 |
| `Ai` baseline, row-carrying | 4,069 | 95.45 % | 4.55 % | 28.46 % | 52 | 137 | 3 | 1 | 7 | 11 | 14 |
| stdlib boot, row-carrying | 409 | 100 % | 0 % | 0 % | 1 | 34 | 0 | 0 | 13 | 30 | 0 |

(The `stdlib boot` row is the NON-Algebra part of the Algebra trace — 48,528 solves of which 409
carry a row. A free-standing `bin/ermine` boot gives a slightly different population with the same
maxima; the reviewer checked both.)

**Before `Comprehensions.e`** the twelve-module group measured 34,226 / 7,309 solves, 98.65 %
vocabulary-fixed, 1.45 % generative, 27.47 % concrete, max draws **14**, max dequeues **54**, depth
**2**, parts **8**, vars **10** — every cell of which the reviewer reproduced exactly. One module
moved four of those maxima, which is itself the most interesting thing in this section.

Per module (row-carrying solves; `conc%` and `gen%` are shares of those):

```
module                  solves rowcarry maxdraw maxdeq maxdepth maxparts maxlbl  conc%  gen%
BillOfMaterials           5006     1167      13     49        2        8     20   26.6   1.5
ManagerChains             3528      790      11     46        2        5     19   27.6   1.6
OrderLedger               3504      759      11     44        2        6     26   27.9   1.7
LedgerScan                3805      758       1      4        0        3     13   30.7   0.0
InventorySnapshots        3503      754      12     46        2        5     15   27.2   1.3
RateStatistics            3250      736       3      8        1        4     13   27.7   2.4
Deduplication             2955      649       1      4        0        3     15   25.9   0.0
KeyDiscipline             2900      595      13     53        2        7     24   28.1   3.5
SoftSchema                2997      589       8     33        2        6     17   27.0   1.7
Comprehensions            2897      574      53    184        3       13     16   31.9   8.5
Customer360               2393      491       8     36        1        5     19   28.1   2.4
Helpers                    610       47       0     93        0       22      0    0.0   0.0
Signatures                 215       23       0     93        0       22      0    0.0   0.0
```

**The heaviest eight solves, with the source line read at each site** (this is the correction the
review demanded: my first pass labelled four of five from nearby definitions rather than from the
position in the trace, and drew the wrong conclusion from them):

```
deq=184 draws=44 parts=13 vars=14 lbl=15 conc=11  Comprehensions.e(116:3)
      [| revenueEur = unitsSold * unitPrice * (1.0 - discountPct), ...
deq=147 draws=53 parts= 8 vars=11 lbl= 6 conc= 2  Comprehensions.e(116:3)   -- same site, second solve
deq= 93 draws= 0 parts=22 vars=32 lbl= 0 conc= 0  Helpers.e(309:5)
      let prior = rename amtF a' (rename ordF o' (r # {ordF, amtF}))        -- runningTotal's body
deq= 93 draws= 0 parts=22 vars=32 lbl= 0 conc= 0  Signatures.e(208:5)       -- the same body, again
deq= 81 draws=23 parts=12 vars=15 lbl= 7 conc= 3  Comprehensions.e(116:3)
deq= 77 draws= 0 parts=18 vars=28 lbl= 0 conc= 0  Helpers.e(309:5)
deq= 77 draws= 0 parts=18 vars=28 lbl= 0 conc= 0  Signatures.e(208:5)
deq= 53 draws=12 parts= 5 vars= 6 lbl=17 conc=10  KeyDiscipline.e(114:17)
      joinedAtLeast = joinOnAtLeast {sensorId} readings calibrations
```

**What moved, and what did not.**

* **THE JOIN SPELLINGS ARE CHEAP; `combine` IS NOT.** This is the review's Q-12 and it is the
  headline. In the twelve-module group four of the five heaviest solves were `combine_Op` and I had
  labelled them `joinOnExactly` / `accumulate` / "the 14-column union" / `letRWithPK`; extending to
  eight, seven of the eight were `combine`. With the thirteenth module the point is unmissable: the
  three heaviest solves in the group are ONE `[| ... |]` bracket containing three `combine`s, and the
  single heaviest relational-algebra solve — `joinBy'`, the only stdlib signature that makes the
  solver find a key by set difference — is eighth at 53 dequeues against the comprehension's 184.
  **What costs this group is the same thing that costs `Ai`: `combine`'s `RUnion2`, only over a wider
  concrete row.** That is why the label maximum moved from `Ai`'s 14 to 26 while the join arity did
  not matter.
* **`Comprehensions.e` alone raised four maxima**: draws 14 → **53**, dequeues 54 → **184**, mint
  depth 2 → **3**, generative share 1.45 % → 2.05 % (8.5 % within that module). The desugaring is
  `combine`/`filter`/`rename` applied left to right with each step's output feeding the next, so the
  solver meets three chained `RUnion2`s with nothing named between them — which is exactly the shape
  `Syntax/Relation.e`'s own header advertises as inferring two extra existential row variables.
* **The group now MATCHES `Ai` rather than being gentler than it**: 53 draws against 52, depth 3
  against 3, per-key mints 1 against 1 — and EXCEEDS it on everything structural: 184 dequeues
  against 137, 22 input partitions against 7, 32 variables against 11, 26 labels against 14. The
  pre-review claim ("gentler than `Ai`") was true of the twelve-module group and the reviewer
  reproduced it; it is no longer true of the thirteen, and the thing that changed it is one module of
  surface syntax.
* **The widest input system in the corpus is a definition, not a call site.** `runningTotal`'s body
  presents **22 partition constraints over 32 row variables** and draws ZERO ids — the solver
  discharges the whole system without minting. That is the same system `Signatures.e` writes out as
  21 published constraints and proves equivalent to two, so the census and the entailment proof are
  two views of one fact.
* **Budget headroom is still enormous**: the largest solve draws 53 against 20,000 — 377x. The budget
  never fired anywhere in the group, before or after.
* **Chain depth ≤ 3 and per-key mints ≤ 1**, inside the published ≤4 / ≤11. Nothing in this
  directory re-mints at a key, comprehensions included.
* **Two modules still mint nothing at all** (`LedgerScan`, `Deduplication`: max draws 1, depth 0,
  0 % generative). They are the cheapest realistic reports in the tree, and — as the review points
  out — that also makes them the thinnest as corpus contributions.
* The negatives reach 31.6 % generative and 47.4 % concrete on row-carrying solves, a much hotter mix
  per solve than any positive module, on 19 solves.

### G4(a) — rendering

**There is no `render`.** `core/examples/Ai/README.md` documents `render <theReport>`; no such term
exists in any stdlib module (`grep -rn '\brender\b' core/src/main/resources/modules/` finds four
comments and nothing else) and the `Console` has no such command (its only `render` is a private
printer inside `:browse`). A `Report` is `Report (Writer f z -> f z)` and running one needs a
`Writer`, which lives in the separate `ermine-writers` project.

Two things can be done instead, and this stage did both.

**(i) The REPL, forcing each value.** A report prints as `(Report <function>)` — which forces the
constructor — and a relation prints as its COMPUTED HEADER, which is a real check because computing
the header runs the whole relational expression. Eleven sessions, one per module,
`bin/ermine core/examples/Algebra/Helpers.e core/examples/Algebra/<M>.e < <M>.in`:
**rc=0 and zero errors in all eleven.** Trimmed headers, one per report:

```
Algebra.OrderLedger.ledgerReport   res0 : forall (f: * -> *) z. Report f z = (Report <function>)
Algebra.OrderLedger.priced         Relation (|listPrice, salesRepId, customerId, quantity,
     customerTier, channelId, taxPct, promoCode, orderDate, productCategory, warehouseId, lineNo,
     unitPrice, channelName, currencyCode, discountPct, orderId, freightCost, repTeam, customerName,
     productId, customerCountry, orderStatus, repName, productName, lineTotal|)      -- 26 columns
Algebra.BillOfMaterials.reachable  Relation (|bomNodeId, parentBomNodeId|)
Algebra.BillOfMaterials.rolledUp   Mem (|extCost, bomNodeId|)
Algebra.Customer360.displayed      Mem (|pointsBalance, accountSegment, loginEmail, marketingOptIn,
     tierName, ownerEmail, paymentTerms, openTickets, satisfaction, billingCountry, enrolledDate,
     customerId, lastTicketDate, blocked, accountName, legalName, creditLimitEur, signupDate, taxId|)
Algebra.InventorySnapshots.qtyMoves  Relation (|onHandQty, binCode, warehouseId, deltaQty, sku,
     availableQty, lotNumber|)
Algebra.Deduplication.latest       Mem (|ingestBatch, countryCode, addressLine, phoneNumber, eventId,
     loyaltyScore, consentFlag, customerId, sourceSystem, postalCode, tierBand, operation,
     eventTimestamp, eventVersion, emailAddress|)                                    -- 15 columns
Algebra.SoftSchema.assetWithReadings  Relation (|warrantyEnd, criticality, installDate, voltageV,
     firmware, siteCode, hoursRun, assetId, tempC, modelCode, manufacturer, lastFault, assetName,
     siteName, serialNo, assetType, ownerTeam|)                                      -- 17 columns
Algebra.ManagerChains.compared     Relation (|gradeLevel, department, managerName, fteFraction,
     costCentre, managerId, fullName, managerDept, jobTitle, managerTitle, salaryGapEur,
     employmentType, salaryEur, employeeId, bonusPct, officeCode, hireDate, leaverFlag,
     managerSalary|)                                                                 -- 19 columns
Algebra.LedgerScan.totalsRelational  Mem (|amountEur, accountCode|)
Algebra.RateStatistics.averages    Mem (|weightedStress, specimenId, medianStress,
     harmonicScatter, meanStress|)
Algebra.KeyDiscipline.valued       Relation (|scaleToSi, calibQuality, siValue, rawCount,
     channelName, calibSource, gainDrift, sensorId, scaledValue, siteCountry, isFlagged,
     streamCode, fullGain, stationId, readingDate, latencyDays, sampleId, unitCode, siteType,
     baseGain, sensorName, sensorClass, networkCode|)                                -- 23 columns
Algebra.Signatures.antiJoinDeduped forall r1 a r b. (b <- (c1, r1), r <- (r1, c), RelationalComb a)
                                     => Row r1 -> a r -> a b -> a b
```

**(ii) REAL TABLES, through E1's `tracker/tools/sql-render.sh`.** Stage E1 built the missing half
while this stage was running: compile a relation to SQL with `Scanners.dumpQuery` and execute it
against SQLite. I drove it at this group with my own probe (scratch:
`alg-render-probe.e` / `.in`, `ERMINE_RENDER_MODULES` pointed at `Algebra/`), 23 relations and two
`Mem`s:

```
q_order_priced   (8 rows)   q_inv_unchanged  (3 rows)   q_mgr_compared  (11 rows)
q_order_semi     (7 rows)   q_inv_removed    (1 rows)   q_mgr_ic         (6 rows)
q_order_noCust   (1 rows)   q_inv_added      (1 rows)   q_ledger_unrec   (4 rows)
q_bom_cost      (14 rows)   q_inv_leftover   (0 rows)   q_rate_firm      (8 rows)
q_bom_leaves     (8 rows)   q_c360_core      (4 rows)   q_key_valued     (6 rows)
q_soft_wide      (4 rows)   q_c360_never     (0 rows)   q_dedupe_noerp   (4 rows)
```
**18 of 23 relations executed and produced a table**; every row count is the one the module's prose
claims. Three examples, which are the actual renderings the gate asks for:

`OrderLedger.priced` — all EIGHT order lines survive the outer joins, and the three missing dimension
rows show as the defaults the module supplies:

```
channelId | channelName  | customerId | customerName        | customerTier | repName          | repTeam    | lineTotal
1         | web          | 4001       | Aurora Retail       | gold         | R. Okonjo        | north      | 660.0
1         | web          | 4001       | Aurora Retail       | gold         | R. Okonjo        | north      | 473.09999999999997
1         | web          | 4004       | (unknown customer)  | unrated      | R. Okonjo        | north      | 1813.0
2         | field sales  | 4001       | Aurora Retail       | gold         | M. Haldi         | north      | 3700.0
2         | field sales  | 4002       | Basalt Trading      | silver       | M. Haldi         | north      | 359.64000000000004
2         | field sales  | 4002       | Basalt Trading      | silver       | (house account)  | unassigned | 1496.0
3         | (partner)    | 4003       | Cinder & Co         | gold         | (house account)  | unassigned | 207.5
3         | (partner)    | 4003       | Cinder & Co         | gold         | (house account)  | unassigned | 479.52
(8 rows)
```
(A natural join drops four of these; the module computes both and puts them side by side.)

`InventorySnapshots` — the three-way split of a snapshot diff, and the proof that it is exact:
`unchanged` 3 rows, `trulyRemoved` 1 (BAT-9001 lot 5514, the quarantined one), `trulyAdded` 1
(TAP-1000), **`mondayLeftOver` 0 rows** — Monday's six rows are exactly changed + removed + unchanged.

`ManagerChains.paidAboveManager` — the self-join, filtered:

```
fullName     | jobTitle          | managerName  | managerSalary | salaryEur | salaryGapEur
I. Moreau    | Contract Engineer | E. Nakamura  | 138000.0      | 152000.0  | -14000.0
F. Bassi     | Senior Engineer   | D. Ilves     | 142000.0      | 145000.0  |  -3000.0
(2 rows)
```

**The five that did not execute, and why** — two error classes, both of them E1's documented limits or
next to them, recorded here because they are measurements about the SQL emitter, not about these
modules (the same relations type-check and produce correct headers):

* `q_bom_reach`, `q_mgr_reports` — `SQLITE_ERROR ... near "insert"`. Both are `closure`, whose
  `materialize` at each round emits a temp-table `insert into <guid>(...)` ahead of the select;
  `SqlRun` executes one statement. This is the same shape as E1's limit 2 (`SqlLoad`).
* `q_inv_moves`, `q_key_serial`, `q_soft_assets` — `SQLITE_ERROR ... near "on"`. Not correlated with
  outer joins: `q_order_priced` contains a `LEFT JOIN` and runs, and in all five files the `join` and
  `on (` counts are equal with no comma-join. Left as an observation for whoever owns
  `SqlEmitter`; the SQL is in the stage scratch under `render-sql/sql/`.
* `latest` (`dedupeBy`) and `stationTotal` (`groupSum`) answer **`Don't know how to dump a mem.`** —
  E1's limit 1, and it bites here harder than there: everything `groupBy` produces in this group is a
  `Mem`, so no grouped result in the directory can be rendered this way.

### G4(b) — what the interfaces publish

`-Dermine.useInterface=true` over the group (files deleted afterwards):

| interface | bindings | with a residual | partition constraints |
|---|---|---|---|
| `Helpers.ei` | 33 | 30 | **66** |
| `Signatures.ei` | 19 | 18 | **75** |
| `SoftSchema.ei` | 27 | 2 | 3 |
| `Comprehensions.ei` | 21 | 1 | 2 |
| the other nine (`BillOfMaterials`, `Customer360`, `Deduplication`, `InventorySnapshots`, `KeyDiscipline`, `LedgerScan`, `ManagerChains`, `OrderLedger`, `RateStatistics`) | 14–25 each | **0** | **0** |
| TOTAL | — | 51 | **146** |

(Before review, twelve modules: 43 signatures / 89 constraints — reproduced exactly by the reviewer,
who also checked the interfaces are byte-identical across two separate JVMs. `Signatures.ei` jumped
from 31 to 75 because the `runningTotal` pair writes the 21-constraint inferred set out twice.)

For scale, `core/examples/Ai/README.md` measured the pre-existing top-level corpus at **12 partition
constraints across 9 signatures** and `Ai/Common.e` at 8 across 4. This group multiplies the corpus's
published row-polymorphic surface by roughly twelve.

Nine of the eleven report modules publish ZERO residuals — every relation in them is concrete and the solver
discharges everything, the same pattern as the stdlib (105 of 129 modules) and as `Ai/`. The two
exceptions in `SoftSchema.ei` are instructive and are documented in the source:

* `tf` (a `private` one-liner, `flip (!)`) publishes `(exists d. c <- (d, a))`.
* `Comprehensions.accumulate1`, the hand-written running-balance fold, publishes
  `(exists c. b <- ((|balanceEur|), a), a <- ((|revenueEur|), c)) => Vector {..a} -> Vector {..b}` —
  the only residual any report in the group publishes that is about RECORDS rather than relations,
  because it is the one place in the directory where a row is built by hand with `cons`.
* `pivoted` — `Relation.Pivot.pivot` with a five-entry `Fulcrum` — publishes **eleven existentials
  and five `RUnion2`s, one per `consFulcrum`**:

```
pivoted : forall (s: rho). (exists RUnion2 v3 i v31 RUnion21 v32 v33 RUnion22 v34 RUnion23 RUnion24.
    RUnion23 v31 v32 (|readingValue|),
    (|assetId, readingKey, readingValue|) <- ((|readingKey|), v31, i),
    RUnion22 v33 v34 (|readingValue|),
    RUnion21 v32 v33 (|readingValue|),
    RUnion2  v3  (|readingValue|) (|readingValue|),
    RUnion24 v34 v3 (|readingValue|),
    s <- ((|voltageV, lastFault, firmware, hoursRun, tempC|), i))
  => Mem s
```

A `Fulcrum`'s column list is a VALUE, so `pivot`'s result row is not determined by its arguments'
types and the residual grows one `RUnion2` per pivoted column. `SoftSchema.e` keeps the unannotated
`pivoted` (the corpus wants the hard residual) and adds `pivotedTyped` with the concrete annotation.
Measured: `pivotedTyped` publishes `Mem (|assetId, voltageV, tempC, hoursRun, firmware, lastFault|)`
and NO residual, so the annotation discharges all eleven existentials and all five `RUnion2`s.

## 4. The RUnion pitfall, re-measured at the adopted defaults

`core/examples/Ai/README.md` reports that a helper bundling `if`'s `RUnion3` on top of `combine`'s
`RUnion2` **"does not finish"**, against 1.04 s inline and 0.50 s via `withColumn`. The common brief
asks whether it still bites. **I could not reproduce it — at EITHER the new or the old defaults.**

Four shapes, three chained call sites each, on a 16-column fact table (scratch modules, not part of
the corpus; source under `/home/dmitry/.claude/jobs/880c725d/tmp/E2/runion_*.e`):

| shape | mine, adopted defaults | mine, pre-adoption (`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`) | the reviewer's re-run (loaded box) |
|---|---|---|---|
| A: `combine_Op (if_Op p a b) f rel` inline | 0.35 s | — | 0.34 s |
| B: via a `withColumn` helper (`RUnion2` only) | 0.20 s | — | 0.65 s |
| C: via a helper whose signature bundles `RUnion3` AND `RUnion2` | **0.53 s** | **0.48 s** | **1.39 s** / **1.47 s** pre-adoption |
| D: the same helper with NO signature (the inference case) | 0.56 s | — | **2.20 s** |
| E (the reviewer's): the two lattices sharing every variable, no partition between | — | — | ill-typed, refused in 1.05 s |

So on this construction the cliff is not there and was not there before the adoption either: C
finishes at BOTH default sets, on two machines, at two load levels. The honest reading: the Ai figure
is real but its helper's source was not preserved, so this REFUTES the reconstruction, not the
historical measurement. `Ai/README.md` should either name the helper it measured or soften the claim.

**And the ordering carries the lesson the report first missed.** The absolute numbers are not
comparable across the two runs (load average 9–17 during the reviewer's), but the RANKING inside each
run is, and in the reviewer's run **D — the helper with NO signature — is the slowest of the four**,
2.20 s against C's 1.39 s and A's 0.34 s. That is direct evidence for `Helpers.e`'s Rule 1: it is not
bundling `RUnion3` with `RUnion2` that costs, it is leaving the helper unsignatured, because then
every call site re-solves an inferred residual instead of the set the author chose. The A < B ordering
the `Ai` README reports is not stable across runs and should not be quoted.

`Algebra/Signatures.e` now measures the same thing exactly rather than by wall clock:
`Helpers.runningTotal`'s TWO hand-written constraints and the TWENTY-ONE the compiler infers when the
signature is removed (over twenty-seven existential row variables) are proved EQUIVALENT in both
directions — so nineteen of the twenty-one are noise, the largest such ratio measured in this
repository. That is Rule 1 stated as a theorem instead of a stopwatch.

## 5. Findings

**F1. `Relation.UnifyFields.unify1` cannot unify differently-named schemas — the one thing it is for.**

```
unify1 : (r <- (h,f,t), r2 <- (h,f2,t)) => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
unify1 f1 f2 r r2 = join (rename f1 f2 (except {f2} r2)) r
```
`r` and `r2` share BOTH `h` and `t`, so the two operands must agree on every column but one each; and
`f1` — the column actually being renamed — is mentioned in NO constraint. A source keyed on
`crmAccountId` against a canonical relation keyed on `customerId` is rejected:
`Row partitions are unsatisfiable at field 'customerId': the whole contains it but no part does`.
Working calls have the two operands at the SAME header, which makes it a self-semi-join under a key
alias, not a unification (`Customer360.selfAliasSemiJoin` is such a call, and it loads). The reports
use plain `rename` (`Helpers.alias`) instead. `Relation/UnifyFields.e` is 8 lines and exports one
function; it is the only stdlib module in this area that is effectively unusable as documented.

**F2. `Relation.join1` is not "the intersection is nonempty".** Its comment says it "requires a
witness that the intersection is nonempty, to guard against accidental cartesian joins". Its
constraint `r <- (k, r1, r2)` is a PARTITION, so `r1` and `r2` — everything outside `k` on each side —
must be DISJOINT. A second shared column makes it unsatisfiable. `join1 f` therefore means "`f` is the
WHOLE key", exactly `joinBy {f}`; the weaker claim the comment describes has to be spelled
`joinBy' {f}`. Measured in `shouldfail/alg05`, documented in `KeyDiscipline.e` spelling 4.

**F3. A row variable written inside the `[f1, f2]` relation-type syntax is read as a LABEL.**
`mk : Field c String -> [a, c]` checks, and the compiler reports it as
`forall (c: rho). Field c String -> Relation (|a, c|)` where the `c` in the result is fixed: `mk c1`
has type `Relation (|a, c|)`, not `Relation (|a, c1|)`, and annotating the call site
`a1 : [aid, c1]` gives `failed to unify type (|aid, c1|) with type (|aid, c|)`. So a helper that looks
row-polymorphic in its RESULT compiles happily and its uses fail later and elsewhere — the mistake I
made writing `SoftSchema.e`'s hand pivot, where the failure surfaced two definitions away at a
`joinWithDefault`. The correct spelling is `[..r]` with a partition constraint. Reproduction:
`probeI.e` / `probeJ.e` / `probeJ2.e` in the stage scratch.

**F4. The `rowSound` blame CLAUSE depends on the command line.** `alg05` and `alg06` print
"two parts of one partition both contain it" / "a part contains it but the whole does not" under one
command line and "the whole contains it but no part does" — both of them — under another, at the same
field and the same position, deterministically per command line. This corroborates the note in
`tracker/tools/corpus-run.sh` on fresh modules and says a regression test should pin the field.

**F5. There is no `render`, and `Ai/README.md` says there is.** See §G4(a). E1's
`tracker/tools/sql-render.sh` is the working substitute for RELATIONS (18 of this group's 23 render
real tables through it); it cannot render a `Mem`, so nothing this group computes with `groupBy` can
be executed that way.

**F6. `TestSurfaceParsers` pins the corpus at exactly 271 files.** Any example added anywhere breaks
it. See §6.

**F7. `Relation.rename'` demands that the destination column ALREADY EXIST**, which is the opposite of
what "rename" suggests and cost an iteration here. `rename' f1 f2 = rename f1 f2 . except {f2}`, and
`except` requires its argument to be present — so `rename'` is "replace `f2` with `f1`", not "rename
`f1` to `f2`". `Relation.UnifyFields.unify1` opens with the same `except {f2}` and inherits the same
requirement (F1). `Helpers.e` splits the two cases into `alias` (plain `rename`, destination ABSENT)
and `overwriteWith` (`rename'`, destination PRESENT) so the choice is visible in the type; the two
signatures differ by exactly one constraint, and each is a type error where the other works.

**F8. `Relation.Scan`'s `sumBy'`/`sumBy`/`avgBy'` force the aggregate's `Op` row to be the WHOLE group
row**, so a scan fold over a wide relation must project to key-and-measure first. `count'` does not.
`Helpers.scanTotals` carries the restriction in its signature (`r <- (h, m)`, no remainder);
`scanCounts` does not need to.

**F9. `Layout.Scan` does not re-export all of `Relation.Scan`.** Its re-export list is what decides
the Scan vocabulary a report can reach, and `removeK`, `removeBy` and `multiply` are not on it —
they are reachable only under `Relation.Scan`'s own module suffix. `LedgerScan.e` imports
`Relation.Scan as S` for `removeK_S` alone and says why.

## 6. Wiring the orchestrator must add

I did not edit `tracker/tools/*` or `core/examples/README.md` (E1 owns them this round). These are the
lines needed. E1 has already added the `Wide` cases, so these slot in beside them.

**(a) `tracker/tools/looptrace-corpus.sh`** — the default group list and two `case` arms. E1 has
already added `Wide`/`Wide-shouldfail`; these follow the same shape and the same NAMING (a group name
becomes a file name, so `Algebra-shouldfail`, not `Algebra/shouldfail`):

```bash
groups="${LOOPTRACE_GROUPS:-boot top Ai Wide Wide-shouldfail Algebra Algebra-shouldfail shouldfail bugs guide shouldfail-controls incomplete}"
```
in the `case "$g" in` block, beside the `Wide` arms:
```bash
    # Algebra/ is the Ai/ case with a different library: every Algebra module imports
    # `Algebra.Helpers`, and so does every module under Algebra/shouldfail, so the library
    # goes first on both command lines (stage E2, 2026-09-06).
    Algebra) mapfile -t gf < <( { echo core/examples/Algebra/Helpers.e
                                  find core/examples/Algebra -maxdepth 1 -name '*.e' \
                                       ! -name 'Helpers.e' | sort; } ) ;;
    Algebra-shouldfail)
          mapfile -t gf < <( { echo core/examples/Algebra/Helpers.e
                               find core/examples/Algebra/shouldfail -maxdepth 1 -name '*.e' \
                                 | sort; } ) ;;
```
Verified by driving the tools by hand with exactly these file lists (§G2): 96,815 and 55,178 segments,
both clean.

**(b) `tracker/tools/corpus-run.sh`** — against the file as E1 left it (lines 102–103, 108–118,
142–148):

```bash
files=( core/examples/*.e core/examples/Ai/*.e core/examples/Wide/*.e \
        core/examples/Wide/shouldfail/*.e core/examples/Algebra/*.e \
        core/examples/Algebra/shouldfail/*.e core/examples/shouldfail/*.e )
```
batch loop — `alg_done=0` beside `ai_done=0`/`wide_done=0`, and two arms in the `case`:
```bash
  bfiles=(); ai_done=0; wide_done=0; alg_done=0
...
      core/examples/Algebra/Helpers.e) ;;
      core/examples/Algebra/*)
        if [[ $alg_done == 0 ]]; then bfiles+=( core/examples/Algebra/Helpers.e ); alg_done=1; fi
        bfiles+=( "$f" ) ;;
```
per-file loop:
```bash
    core/examples/Algebra/Helpers.e) ;;
    core/examples/Algebra/*)      args=( core/examples/Algebra/Helpers.e "$f" ) ;;
```
The header's directory census ("66 files", updated by E1) gains
`core/examples/Algebra/*.e (12), core/examples/Algebra/shouldfail/*.e (6)`.

**(c) `core/examples/README.md` — CORRECTED after review.** My original two-column rows are stale:
E1 rewrote that table to THREE columns (`directory | subject | library`) and moved `shouldfail/` out
of the table into prose. The row that fits:

```
| `Algebra/` | eleven reports over **relational algebra** — outer joins with defaults, set operations, semi/anti-joins, transitive closure, deduplication, key/value schemas, self-joins, `Relation.Scan`, `Relation.Process`, `Syntax.Relation` comprehensions | `Algebra/Helpers.e` |
```

and the prose sentence about negatives becomes "`shouldfail/` (and `Wide/shouldfail/`,
`Algebra/shouldfail/`) hold modules that must **not** compile …". The load line to add beside the
others:

```
bin/ermine core/examples/Algebra/Helpers.e core/examples/Algebra/OrderLedger.e
```

**(d) `scalacheck-binding/src/main/scala/TestSurfaceParsers.scala:81` — WITHDRAWN, no longer needed.**
The `(files ?= 271)` constant has since been replaced with a derived `moduleFiles.size`, so no count
needs bumping by any E-stage. The reviewer re-ran the three sweeps against that fix and the
header-agreement property passes. Across three runs on three different trees **no `Algebra/` file
appears in any failure label**; the two falsifications either run saw were the old count constant and
another group's broken module. A per-group `core/test` verdict is not obtainable while several agents
write into one tree — the orchestrator should re-run the sweeps once the E-groups have settled.

**(e) also for the orchestrator, from the review.** `Algebra/README.md` names
`tracker/tools/sql-render.sh` and `ERMINE_RENDER_MODULES`, which are E1's uncommitted files
(`sql-render.sh`, `SqlRun.java`, `tsql2sqlite.py`). If E1's tooling does not land, that section of
`Algebra/README.md` points at nothing. They should be committed together.

## 7. What I could not write

* **A generic "widen one attribute of a key/value table" helper.** `Field c String -> [aid, c]` is not
  the type it looks like (F3); the honest generic form would need the output row as a constrained row
  variable and a way to say "the input's key plus this one field", which the partition language can
  express (`out <- (key, c)`) but which then needs `except`/`rename`'s own constraints threaded
  through — and the moment the helper is applied at five different `c`s, the five results have to be
  proved pairwise disjoint at the join. `SoftSchema.e` writes the five columns out instead, with a
  comment saying why.
* **A cross-schema `unify` on top of `Relation.UnifyFields`.** F1: the stdlib function cannot do it
  and there is nothing to build on. `alias` (plain `rename`) is the replacement, and it is not generic
  in the number of columns being reconciled — one call per source.
* **`join1` as a weak witness.** F2: there is no cheap spelling of "`f` is among the key columns".
  `joinBy' {f}` is the only one, and it costs a four-part partition.
* **A `Relation.Scan` fold that returns a relation.** `Scan z a` is a `Cont`, and `Layout.Scan` fixes
  `z` to `Report`; there is no `Scan → Relation`. A scanned running total cannot be joined against
  anything. `LedgerScan.e` computes the same totals both ways to show the difference.
* **A `letRWithPK` body that groups.** Its continuation is `Relation a -> Relation b`, not
  `rel a -> rel b`, and `groupBy` returns `Mem`, so the scoped form cannot contain an aggregation.
  `KeyDiscipline.goodCalibsOnly` filters instead, and says so.
* **A pipeline that stays in one relation type.** `Relation` and `Mem` are separate types with
  separate instances, and the stdlib is split across them without a conversion in both directions:
  `filterEq`, `filterNEq`, `firstBy`, `lastBy`, `leafRows`, `lookupLatest*` and `unionAll` are
  `Relation`-only; `groupBy`, `accumulate` and `medianBy` return `Mem`; `join`, `union` and
  `difference` are `RelationalComb rel` but insist BOTH operands be the same `rel`. `asMem` goes one
  way and nothing goes back, so any report that groups and then filters has to push `asMem` outward
  through the whole expression. Eight of the ten modules here carry an `asMem` that exists only for
  that reason, and it is the single most common thing that had to be fixed while writing them.
* **A `Relation.Scan` total that `columns` can render.** `Relation.Scan.sumBy`/`count` fold a group to
  a NUMBER (`Scan z (k, n)`), and `Layout.Scan.columns` needs a `Column`, which is built from a
  relation. Only the primed forms — `sumBy'`, `count'`, which fold to a one-column RELATION — can be
  rendered. `Helpers.scanTotals`/`scanCounts` use those; the unprimed pair has no use I could find
  short of writing a `consume` by hand.
* **Actual row output for a `Mem`.** No backend, no `render` (F5). E1's `sql-render.sh` executes a
  RELATION (18 of 23 here), but a `Mem` answers `Don't know how to dump a mem.` — and everything
  `groupBy` produces in this group is a `Mem`, so no grouped result in the directory can be executed.
  For those the strongest check available is the computed header (§G4(a)(i)).

**Closed at review** (they were in the brief's list and absent from the first delivery, which §7 did
not admit): `rightJoinWithDefault`, `unsafeRightJoin`, `partialLookup'` and `Syntax.Relation`'s
`[\| … \|]` comprehension forms are all used in `Comprehensions.e`, and the running total
`LedgerScan.e` advertised is computed there twice.

---

## 8. Post-review corrections (2026-09-07)

`tracker/loopmodel/E2-REVIEW.md` (818 lines) returned **FIX-THEN-ADVANCE**: every solver number,
interface count, render row count and census cell reproduced to the digit, all seven stdlib/language
findings were confirmed with the reviewer's own minimal modules, and the census claim the brief
singled out (gentler than `Ai` on draws/depth/mints while reaching the widest concrete label set)
was reproduced. What failed was the prose. Every finding Q-1…Q-17 is applied. Old → new:

### In the files a user reads

| # | was | is now |
|---|---|---|
| Q-1 | `valued` defined in BOTH `InventorySnapshots.e` and `KeyDiscipline.e`, so `KeyDiscipline.e`'s own `>> valued` recipe answered `undefined term` in the whole-group session `Algebra/README.md` prescribes | `InventorySnapshots.valued` → **`fridayValued`** (2 uses), with a comment saying why. It was the group's only name collision — the reviewer diffed every top-level binder. |
| Q-2 | "The joined row is 20 columns wide" (`Customer360.e`, `README.md`, report §1) | **19**, everywhere, with the arithmetic spelled out (4+3+3+3+3+3, the six key columns collapsing into one) |
| Q-3 | `ManagerChains.e`: "Four renames" (line 77) and "Six `rename`s in sequence" (header) | **FIVE** in the sequence, both places, and the header now says the file makes six `alias` calls in all — the sixth is on the closure result |
| Q-4 | `ManagerChains.e` listed `carry` as used and never called it; the `carry` comment sat above a plain `groupBy` | `carry` is now **actually used**: `spanOfControl = groupBy {managerOf} count (carry managerId managerOf employees)`, and the comment says why copying beats renaming here (the join key has to survive) |
| Q-5 | "The five most expensive teams, ranked inside the whole org (one group)" over `groupTop {department} {salaryEur} 3` | renamed `bestPaidPerDepartment`, captioned "the three best-paid people in each department", with the note that `groupTop`'s ranking column must be outside the key |
| Q-6 | `Deduplication.e` listed `groupSum` (never called); `LedgerScan.e` listed `updateK` (never called) | `groupSum` dropped from `Deduplication`'s header; `updateK` **used** in `LedgerScan.largestFreightOnly`, with the observation that its function is `[..t] -> [..t]`, so any relational operator can be applied to ONE column of a pivot |
| Q-7 | `KeyDiscipline.e`: "calibrations (… + 5 more)", "sensors (… + 8 more)" | the real widths, as counts: calibrations **7**, sensors **5**, readings **12** |
| Q-8 | `SoftSchema.hottest` ranked by `assetId`, was named for temperature, and was dead | `newestPerSite`, ranked on `criticality`, in the report, with the note that the widened columns are all STRINGS so `tempC` would sort lexically — which is what a key/value schema costs you |
| Q-9 | `Deduplication.neverTouchedByErp` and `RateStatistics.preliminaryOnly` captioned as if they returned entities | renamed `eventsOfCustomersErpNeverTouched` and `runsOnSpecimensWithNoFinalRun`, captions corrected, and the structurally-empty one says so |
| Q-10 | `intersectRows`/`exceptRows` wrapped, `union` called raw four times | **`unionRows`** added to `Helpers.e` with the same doc comment, and used in `InventorySnapshots.e` |
| Q-11 | `alg06`'s header claimed it switches clause per file, like `alg05` | both headers now carry the **measured 3×2 matrix** (§G1(c)). `alg05` flips on the shouldfail-only line, `alg06` on the per-file line — different points. And the matrix is not stable under unrelated edits: adding `unionRows` to `Helpers.e` moved `alg06`'s whole-group clause. |
| Q-13 | `antiJoinAsWritten`'s comment: "Note it is NOT the deduped set renamed" | it IS, and the comment now gives the bijection and says so — and says the other two pairs are the substantive ones |

### In the measurement

| # | was | is now |
|---|---|---|
| Q-12 | §G3's five heaviest-solve labels named `joinOnExactly`, `accumulate`, "the 14-column union" and `letRWithPK`; the conclusion read "relational algebra over concrete headers is cheap" | four of the five were `combine_Op`. §G3 now names the real construct at each site and draws the conclusion the numbers support: **the join spellings ARE cheap; what costs this group is `combine`'s `RUnion2`, the same thing that costs `Ai`, over a wider concrete row** |
| §4 | four shapes, one machine, one load level | the reviewer's independent re-run added, including shape E, and **D — the helper with NO signature — is the slowest**, which is the direct evidence for `Helpers.e` Rule 1 that the section previously lacked |
| Q-16 | `LOOP-MODEL-PLAN.md` E2 row: 151,519 segments | 156,368 (post-review), with the pre-review 151,993 recorded beside it |
| Q-14 | `rightJoinWithDefault`, `unsafeRightJoin`, `partialLookup'` named in the brief and absent | all three used, in `Comprehensions.e`, through three new signed helpers |
| Q-15 | zero uses of `Syntax.Relation`'s `[\| … \|]` in the group | `Comprehensions.e` uses all three clause forms and their combination, each proved to have the same type as its longhand by putting the pair in a two-element list. Measured while writing it: four pre-existing example files use the syntax and none exercises it — `Yahoo.e:202` and `incomplete/RunCalibration.e:147` use ONE clause of ONE form, `ChartsExample.e:439` has one inside a comment; the combined form appears only in `Syntax/Relation.e`'s header and the stdlib's own test module |
| — | `LedgerScan.e` sold running totals and delivered per-group folds | its header now says exactly what it does and does not show, and points at `Comprehensions.e`, which computes a running balance **twice** — relationally (`Helpers.runningTotal`) and by scanning |

### The wiring

(a) `looptrace-corpus.sh` and (b) `corpus-run.sh` were checked by the reviewer and are **correct as
written** (and the `case` arms are required, not cosmetic: the `*)` fallback would glob
`BillOfMaterials.e` ahead of `Helpers.e`). (c) is **rewritten** for the three-column table E1
introduced. (d) is **withdrawn**: the `files ?= 271` constant is now a derived `moduleFiles.size`.
(e) is new — `Algebra/README.md` depends on E1's uncommitted `sql-render.sh`.

### What the review confirmed that I could not have

The reviewer diagnosed the three `near "on"` SQL failures I had left as an observation: `SqlEmitter`
flattens a NON-LEFT-DEEP join tree without parentheses, so `A JOIN B ON c1 JOIN (C JOIN D ON c2) ON
c3` is emitted with two trailing `ON`s and SQLite rejects the second. All three failures are
relations whose right operand is itself a join. That is a one-line reproduction for whoever owns the
emitter (`render-sql/sql/q_inv_moves.lite.sql`), and it belongs in the ticket rather than in this
report's "observation" bucket.
