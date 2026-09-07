# E1 — `core/examples/Wide`: generic helpers over wide tables, pivots, window functions

Repository `ermine-scala`, branch `scala3-migration`, tree clean at `2dd7dc3` when the stage
started; the three row-solver defaults as adopted on 2026-09-05 (`-Dermine.rowSound` ON,
`-Dermine.dequeuePolicy=smallcanon`, `-Dermine.solveBudget=20000`). Measured 2026-09-06/07.
No commits; `tracker/lean/` untouched.

**Outcome: GREEN, with one gate that had to be repaired before it could go green and whose
breakage was not this stage's doing.** Ten `Wide/*.e` modules and three `Wide/shouldfail/*.e`
modules were written; all ten load, per file and in one batch, with identical verdicts either
way; all three are rejected with the expected diagnostics; the L2 differential over 170,619
solves is clean (0 skipped, 0 hashdiff, 0 eqdiff, 0 fuel). `sbt core/test` failed on a
**hard-coded corpus size** in `TestSurfaceParsers` (`files ?= 271`) that ANY added example
breaks — measured to fail with `Wide` moved aside as well — and is **913/914 with only the
documented flake** once the count is derived rather than written down (§3d).

Seven findings are in §7 — three about the RUNTIME rather than the type system, two of those
live bugs: one makes `Relation.Pivot.pivot` and `Relation.Predicate.all` unusable at runtime in
this build, and `render`, which every existing example's header tells the reader to use, does
not exist. The eighth, the test's hard-coded corpus size, is in §3d with the gate it broke.

A note on the measurements before any of them are read: **this stage ran on a machine that was
concurrently running three sibling example-corpus stages** (`core/examples/Algebra`, `Time` and
— appearing partway through — `Present`), each with its own JVM. Every wall clock below is
therefore an upper bound, and the per-module check times were taken twice, on separate runs,
wherever the number carries an argument. The one place the sharing shows up as more than noise
is `sbt core/test`, and §3d says exactly where.

---

## 0a. What was already there, and what this adds

The brief's premise, checked: before this stage `Relation.Pivot` appeared in exactly one
example (`core/examples/PivotTest.e`, a fifteen-row key/value toy whose pivot is never
forced) and `Relation.Windowed` appeared in **no example at all**. Neither module had a
single caller in `core/examples` that did real reporting work.

`Wide/` adds nine reports and a 24-helper library over fact tables of 20 to 36 columns. Its
subject is the corner of the standard library the brief calls *existential-generating*:
helpers whose signatures **mint row variables the caller never writes down** —

* `pivot`'s identity row `i` in `r <- (k, v, i)`, `s <- (i, p)`: the columns that are neither
  key nor value and therefore survive the transpose;
* `window`'s row `w` in `w <- (k, s)`: the partition columns together with the sort columns;
* `windowed`'s union of the window function's row with the window's own.


---

## 0b. The findings, in one place

Four are about things that do not work; two are measurements that came out the other way round
from the prediction. All are expanded in §7 (findings) and §5 (measurements).

| # | finding | where |
|---|---|---|
| 1 | **`render` does not exist in this repository.** The Ai examples' headers all say `render <report>`; the REPL answers `undefined term`. No concrete `Writer` ships in `ermine-scala` — they live in the separate `ermine-writers` project — so a `Report` cannot be run at all. The `Wide/` headers therefore do not say `render` | §7.1, §6 |
| 2 | **`Relation.Pivot.pivot` and `Relation.Predicate.all` panic when forced** — `Native.Record.scalaRecord# - MapView(<not computed>)`. `record#` answers `Prim(m.mapValues(_.whnf))` and since Scala 2.13 `mapValues` returns a `MapView`, which the `case Prim(t: Map[String, Runtime])` in `scalaRecord#` cannot match. A one-line fix, deliberately not applied here | §7.2 |
| 3 | **Window functions emit real SQL only through the MS SQL emitter.** Every other emitter inherits `SqlEmitter.emitOver`'s stub and emits `TODO I don't yet know how to play … over …` into the query — a silent wrong answer, not an error | §7.3 |
| 4 | **`dumpQuery` cannot dump a `Mem`, nor `lookupLatest`'s materialised temporary** | §7.4 |
| 5 | **The row-constraint cliff has moved.** The `RUnion3`+`RUnion2` helper that `Ai/README.md` records as "does not finish" now checks in 1.3–1.5 s on the very module the original measurement used. The advice survives for a weaker reason: bundling still costs 3–4× | §5 |
| 6 | **`share` is cheaper than `windowTotal`-then-divide, not dearer.** One larger solve beats two smaller ones, on a 6-column row and on a 26-column one alike | §5 |

And one that is not about the row solver at all but broke the `core/test` gate:
**`TestSurfaceParsers` asserts an exact corpus size** (`files ?= 271`), so adding any example
anywhere fails it — measured to fail with this directory moved aside too. Fixed by deriving the
count from the corpus instead of writing it down; §3d has the before/after and the argument
that it is not a weakening.

Two smaller ones are recorded as well: the wording of one refutation message describes the
opposite of the situation it is reporting — and the corpus gate proves it, because the SAME
module prints the OTHER clause when loaded in a batch (§7.5) — and two field names in ordinary
reporting vocabulary (`seq`, `currency`) collide with standard-library terms and fail several
lines from the declaration (§7.7).

---

## 1. The file table

Fact columns is the width of the fact relation's rows; joined row is the width after the
dimension joins, confirmed against the emitted SQL (§6). Check time is the module's own
`Importing module` figure, excluding the ~13 s standard-library boot; **two independent
per-file sweeps**, one JVM each, `-XX:ActiveProcessorCount=2`, both on the contended machine
described above — so the pair of figures brackets the number and the spread between them is
the contention. §9 carries a third sweep, taken after the review corrections and on the final
tree; the reviewer's independent sweep on a quieter box landed inside these brackets
(0.30–2.65 s, same ordering, same two slowest).

| module | subject | fact fields | joined row | helpers used | solver shapes exercised | check |
|---|---|---|---|---|---|---|
| `Wide/Helpers.e` | the library | — | — | — | 25 explicit signatures; nothing instantiated | 0.33 / 0.42 s |
| `Wide/Leaderboard.e` | esports season | 30 | 38 | `rankWithin`, `denseWithin`, `rowNumberWithin`, `nTileWithin`, `topNWithin`, `asc`/`desc`/`thenBy` | five window solves on one row, each minting `w <- (k,s)` and `r <- (w,o)`; `topNWithin`'s extra `t <- (c,u)` re-partitioning a row the same call minted; a two-column sort, so `w` is a union of three rows | 0.64 / 1.10 s |
| `Wide/SalesLedger.e` | order lines | 27 | 35 | `startPivot`, `pivotColumn`, `pivotBy` | **two pivots** over one ledger, `r <- (k,v,i)` + `s <- (i,p)` twice, sharing the existential shape; a four-deep `Fulcrum` chain (`p' <- (f,p)` and `RUnion2 v3 v2 v1` four times, each layer feeding the next); `groupBy` ahead of each | 1.17 / 1.18 s |
| `Wide/TrialBalance.e` | general ledger | 21 | 27 | `runningTotal`, `movingAverage`, **`melt2`**, `asc` | the **framed** window's three-deep chain `w <- (k,s)`, `wm <- (m,w)`, `r <- (wm,o)` before `combine`'s union is reached; twice, with different frames; and `melt2` on the full 27-column row | 0.49 / 0.47 s |
| `Wide/RevenueShare.e` | subscriptions | 21 | 26 | `share`, `windowTotal` | `windowTotal` twice with different partitions, results chained; `share`, the only place an `OpBin` inclusion–exclusion lattice meets a window's minted row; an unsorted window | 0.53 / 0.56 s |
| `Wide/SurveyPanel.e` | survey waves | 20 | — (never joined) | `melt4`, `startPivot`, `pivotColumn`, `pivotBy` | `melt4` at a call site — four `except`s, four `combine`s, four `rename`s, three `union`s — reconciled against a **two-constraint** signature; a pivot whose input is a melt's output, so the pivot's `i` is itself a minted row | 0.47 / 0.29 s |
| `Wide/WardRoster.e` | hospital shifts | 24 | 30 | `rowNumberWithin`, `runningTotal`, `windowTotal`, `withDerived2`, `withDerived3` | a **four-link chain**, each helper solved against the row the previous link minted; `withDerived2`/`withDerived3`, two and three row unions in one signature | 2.13 / 2.25 s |
| `Wide/BranchDeposits.e` | bank deposits | 22 | 27 | **`asOfDates`**, `movingAverage`, `latestPerKey`, `asc` | `lookupLatest` instantiated at two different date columns — one of the heaviest bodies in the standard library (`incomplete/Signatures.e` records fifteen inferred constraints for a close relative); `movingAverage`'s three-deep chain; `latestPerKey`'s degenerate `groupBy` where `kv2 = kv` | 0.70 / 0.57 s |
| `Wide/MediaSpend.e` | marketing spend | 23 | 26 | `pivotOnRow`, `pivotOnRowWithDefault`, `pivotBy`, `pivotByWithDefault`, `topNWithin`, `desc` | `defaultFulcrum`'s row-driven plan: `s <- (i,p)` solved against a five-field concrete `p` in ONE step instead of five `consFulcrum`s; the same pivot by two code paths | 0.60 / 0.52 s |
| `Wide/ClaimsExperience.e` | insurance claims | **36** | **43** | `withDerived3`, `nTileWithin`, `denseWithin`, `topNWithin`, **`melt3`**, `pivotOnRowWithDefault`, `pivotByWithDefault` | the widest instantiation in the corpus; `withDerived3` on it; three windows; a defaulted three-way pivot; and the tree's widest `melt3`, over a forty-column identity | 2.60 / 2.83 s |
| `Wide/Signatures.e` (added at review) | the helpers' own types | — | — | — | four equivalence proofs, two in both directions: `RUnion2` **is** its three-constraint lattice; `rankWithin`'s five published ≡ the four written; `melt3`'s 22 inferred ≡ 20 after deleting two order-permuted duplicates ≡ 2 written by hand; `withDerived2`'s eight ⊨ four | 0.18 s |
| `Wide/shouldfail/pivot01_key_column_is_also_value.e` | — | — | — | `startPivot`, `pivotColumn`, `pivotBy` | `r <- (k, v, i)` with `k = v` | rejected, 0.05–0.06 s |
| `Wide/shouldfail/win01_window_on_absent_column.e` | — | — | — | `rankWithin`, `desc` | `w <- (k,s)` / `r <- (w,o)` with a `k` not in `r` | rejected, 0.05–0.06 s |
| `Wide/shouldfail/win02_running_total_ordered_by_measure.e` | — | — | — | `runningTotal`, `asc` | `wm <- (m, w)` with `m ∈ w` | rejected, 0.06–0.14 s |

The two most expensive modules are the two that bundle: `WardRoster` (a four-link chain plus
`withDerived2` and `withDerived3`) and `ClaimsExperience` (`withDerived3` on a 43-column row).
Nothing in the group comes close to the 30 s the brief names as the threshold for comment,
nothing had to be renamed `.slow`, and the solve budget did not fire anywhere — the largest
draw count of any solve in the group is 100 against 20,000 (§4b).

---

## 2. The helper signatures, verbatim, with their published residuals

`Wide/Helpers.e` defines **25 helpers** (24 as first delivered, plus `asOfDates`, added at
review — see §7.8). Nineteen of them publish at least one row-partition
constraint, and between them they publish **85**. For scale, `Ai/README.md` records that the
whole pre-`Ai` example tree contained *12 row-partition constraints across 9 signatures*, and
that `Ai/Common.e` contributes *8 across 4*.

The nine report modules publish **zero** — every constraint the library exports is discharged
at its call sites and the emitted interfaces carry fully concrete rows. That includes the
pivots, which is the point: `revenueByQuarter`'s existential identity row `i` comes out as
`Mem (|q3, q2, customerName, q4, q1|)`, so the solver minted `i`, learned `i = {customerName}`
and `p = {q1..q4}`, and discharged both.

| module | bindings | signatures with row constraints | row-partition constraints published |
|---|---|---|---|
| `Helpers.e` | 24 (25 after review) | 19 | **85** |
| `Signatures.e` (added at review) | 12 | 12 | the four residuals under proof |
| every report module | 8–17 each | 0 | **0** |

Captured with interfaces ENABLED (`bin/ermine core/examples/Wide/Helpers.e <the rest>`, then
the `.ei` files next to the sources); the `.ei` files were deleted afterwards.

### The signatures as written, and what comes back

Below, "written" is the source and "published" is the constraint set from `Helpers.ei`, with
the `Builtin.`/`Relation.Row.` prefixes stripped. The published set is longer than the written
one because `RUnion2 t r c` is not a primitive: it expands to the three-constraint lattice
`r <- (ro, rs)`, `c <- (so, rs)`, `t <- (ro, so, rs)`.

**Ranking windows** — `rankWithin`, `denseWithin`, `rowNumberWithin` are the same signature
with a different window function; `nTileWithin` adds an `Int`.

```
rankWithin : forall k s w r t c rel.
             (exists o. w <- (k, s), r <- (w, o), RUnion2 t r c, RelationalComb rel)
          => Row k -> Sort s -> Field c Int -> rel r -> rel t
rankWithin ks so f = combine_Op (windowed_W rank_W (window_W ks so unboundedFrame_W)) f
```

published (5 row constraints):
`t <- (ro, so, rs), r <- (w, o), c <- (so, rs), w <- (k, s), r <- (ro, rs)`

`w` is the minted row: the caller writes a partition `Row k` and a `Sort s`, and never names
their union. Same for `denseWithin`, `rowNumberWithin`, `nTileWithin` (5 each).

**Framed windows** — the measure row must be disjoint from the window row.

```
runningTotal : forall k s w m wm r t c n rel.
               (exists o. w <- (k, s), wm <- (m, w), r <- (wm, o), RUnion2 t r c,
                PrimitiveNum n, RelationalComb rel)
            => Row k -> Sort s -> Field m n -> Field c n -> rel r -> rel t
runningTotal ks so m f =
  combine_Op (windowed_W (windowedAggregate_W (sum_Agg (col_Op m)))
                         (window_W ks so (F_W Unbounded_W (Bounded_W 0)))) f
```

published (6): `r <- (ro, rs), w <- (k, s), c <- (so, rs), r <- (wm, o), wm <- (m, w),
t <- (ro, so, rs)`

Two minted rows in a chain — `w` from the window, `wm` from `windowed`'s union of the
aggregate's row with the window's — before `combine`'s lattice is reached at all.
`movingAverage` is identical plus an `Int` (6).

**Partition totals.**

```
windowTotal : forall k m wm r t c n rel.
              (exists o. wm <- (m, k), r <- (wm, o), RUnion2 t r c,
               PrimitiveNum n, RelationalComb rel)
           => Row k -> Field m n -> Field c n -> rel r -> rel t

share : forall k m wm r t c n rel.
        (exists o. wm <- (m, k), r <- (wm, o), RUnion2 t r c,
         PrimitiveNum n, RelationalComb rel)
     => Row k -> Field m n -> Field c n -> rel r -> rel t
```

published: `windowTotal` 5, `share` 5 — the SAME constraint set, even though `share`'s body
carries `(/_Op)`'s `OpBin` lattice as well. The lattice is discharged inside the definition and
never reaches the interface. That is what an explicit signature buys, stated precisely.

**Top-N** — the one helper whose two constraints overlap on a column it minted itself:

```
topNWithin : forall k s w r t c rel.
             (exists o u. w <- (k, s), r <- (w, o), RUnion2 t r c, t <- (c, u))
          => Row k -> Sort s -> Int -> Field c Int -> [..r] -> [..t]
topNWithin ks so n f r =
  filter_Pred (col_Op f <=_Pred prim_Op n) (rankWithin ks so f r)
```

published (6): `t <- (ro, so, rs), w <- (k, s), t <- (c, u), r <- (w, o), c <- (so, rs),
r <- (ro, rs)` — `t` is constrained twice, once as the output of `combine` and once as the
input of `filter`, and `c` occurs on both sides.

**Derived columns, the deliberate counter-examples.**

```
withDerived2 : forall v1 v2 c1 c2 a b r t1 t op1 op2 rel.
               (exists o1 o2. RUnion2 t1 r c1, r <- (v1, o1),
                              RUnion2 t t1 c2, t1 <- (v2, o2),
                AsOp op1, AsOp op2, RelationalComb rel)
            => op1 v1 a -> Field c1 a -> op2 v2 b -> Field c2 b -> rel r -> rel t
withDerived2 o1 f1 o2 f2 = combine_Op o2 f2 . combine_Op o1 f1
```

published: 8 row constraints over 8 existentials. `withDerived3` (three unions) publishes
**12 over 12** — the largest residual in the file, and 1.5× the whole pre-`Ai` example tree in
one signature.

**Unpivots, the small-signature surprise.**

```
melt3 : forall key val fa fb fc i r out t rel.
        (r <- (i, fa, fb, fc), out <- (i, key, val), RelationalComb rel)
     => Field key String -> Field val t
     -> Field fa t -> Field fb t -> Field fc t
     -> rel r -> rel out
melt3 kf vf fa fb fc r =
  union (union (rename fa vf (combine_Op (prim_Op (fieldName fa)) kf (except {fb,fc} r)))
               (rename fb vf (combine_Op (prim_Op (fieldName fb)) kf (except {fa,fc} r))))
        (rename fc vf (combine_Op (prim_Op (fieldName fc)) kf (except {fa,fb} r)))
```

published (2): `out <- (i, key, val), r <- (i, fa, fb, fc)` — exactly what was written.

**Inferred, the same body publishes 20–22 row constraints over 19 existentials** — 22 in my
scratch module, 20 in the reviewer's, the difference being two order-permuted duplicate pairs
that the published list does not canonicalise (§7.6, review N-11). That measurement is worth
stating on its own, because it is the `incomplete/Signatures.e` lesson reproduced from ordinary
library code rather than from a synthetic case: the annotation is not decoration, it is a
tenfold-to-elevenfold reduction in what every downstream caller has to solve — and it is
*stable*, where the inferred form is not. `Wide/Signatures.e` proves the 22 and the 20
equivalent, in both directions, by machine.

**Pivots.**

```
pivotBy : forall k v i p r s rel.
          (RelationalComb rel, r <- (k, v, i), s <- (i, p))
       => Fulcrum_Piv k v p -> rel r -> rel s

pivotColumn : forall f p p' v1 v2 v3 k a.
              (p' <- (f, p), RUnion2 v3 v2 v1)
           => Field f a -> String -> Field k String -> Field v1 a
           -> Fulcrum_Piv k v2 p -> Fulcrum_Piv k v3 p'

pivotOnRow : forall p v k a. Row p -> Field v a -> Field k String -> Fulcrum_Piv k v p
```

published: `pivotBy` and `pivotByWithDefault` 2 each — `s <- (i, p), r <- (k, v, i)`, the
two-sided minting the brief asks for; `pivotColumn` 4; `pivotOnRow` and
`pivotOnRowWithDefault` 0, because the produced row is given whole.

**Key lookup, and the sort spellings.**

```
latestPerKey : forall k v d r rel. (r <- (k, v), Has v d, Relational rel)
            => Row k -> Field d Date -> rel r -> Mem r
```
published (2): `v <- (d, c), r <- (k, v)` — `Has v d` unfolded into its `exists` form.

`asc`, `desc` publish nothing; `thenBy` publishes one (`r <- (r1, r2)`).

---

## 3. The gates

### E1.4a Every `Wide/*.e` type-checks, per file

`tracker/tools/corpus-run.sh <outdir>`, one JVM per file, `-Dermine.useInterface=false`,
`Wide/Helpers.e` hoisted to the head of each Wide command line (the CLI cannot resolve
`Wide.Helpers` by name on its own — the same rule `corpus-run.sh` already applied to
`Ai/Common.e`).

**79 files, 1,376 s wall** (a contended machine — see the note at the top; the same sweep on a
quiet one is about 20 minutes). Verdicts by `tracker/tools/corpus-verdicts.py`:

```
33 LOADED, 46 REJECTED, 0 UNKNOWN, 79 total
```

which decomposes exactly as it should:

| | files | verdict |
|---|---|---|
| `core/examples/*.e` | 12 | LOADED |
| `core/examples/*.e` — `Interp.e`, `Sample.e`, `Yahoo.e` | 3 | REJECTED, **pre-existing** (the three `TestTolerantRead`'s own comment names as known-bad: `==` never declared, an explicit-layout source, and a definition shadowing an imported global) |
| `core/examples/Ai/*.e` | 11 | LOADED |
| **`core/examples/Wide/*.e`** | **10** | **all LOADED** |
| `core/examples/shouldfail/*.e` | 40 | REJECTED (unchanged) |
| **`core/examples/Wide/shouldfail/*.e`** | **3** | **all REJECTED** |

Nothing timed out: every one of the 79 exit codes is 0 (`corpus-run.sh` records a non-zero
code only for a timeout, and the verdict itself is read out of the output). No module needed
the `.slow` extension, and none came near the 120 s per-file cap.

### E1.4b Every `Wide/*.e` type-checks, in ONE batch

`tracker/tools/corpus-run.sh --batch <outdir>`: the whole corpus in one JVM, `Wide/Helpers.e`
hoisted once to the head of the Wide group.

**79 files, one JVM, 29 s** — the per-file sweep of the same 79 files takes 1,376 s, so the
batch is **47× faster**, which is the ~13 s stdlib boot paid once instead of 79 times. (The
first version of this sentence said "47× the per-file sweep", which reads as the opposite.)

```
33 LOADED, 46 REJECTED, 0 UNKNOWN, 79 total
```

**Identical verdicts to the per-file sweep, file for file.** `corpus-verdicts.py <per-file>
<batch>` reports `7 of 79 files differ`, and every one of the seven is a MESSAGE difference on
a module that is REJECTED either way, at the same field and the same source position:

| module | per file | in batch |
|---|---|---|
| `shouldfail/der01_rename_onto_existing_column.e` | "two parts of one partition both contain it" | "the whole contains it but no part does" |
| `shouldfail/der04_helper_drop_then_add.e` | "the whole contains it but no part does" | "a part contains it but the whole does not" |
| `shouldfail/der07_shared_three_var_remainder.e` | "the whole contains it but no part does" | "a part contains it but the whole does not" |
| `shouldfail/dup02_signature_chain.e` | "a part contains it but the whole does not" | "two parts of one partition both contain it" |
| `shouldfail/dup04_joinby_shared_column.e` | "the whole contains it but no part does" | "two parts of one partition both contain it" |
| `shouldfail/inc04_except_absent_field.e` | "the whole contains it but no part does" | "a part contains it but the whole does not" |
| **`Wide/shouldfail/win01_window_on_absent_column.e`** | "the whole contains it but no part does" | **"a part contains it but the whole does not"** |

Six of the seven are the pre-existing set `corpus-run.sh`'s own header documents ("seven modules
print a DIFFERENT CLAUSE of the same refutation, at the same field and position", measured
2026-09-03). The seventh is new, and it is the module from §7.5 — and the batch wording is the
**accurate** one for that program: a part does carry `divisionName` and the whole does not.
That is direct evidence for §7.5's diagnosis: the sentence is the reason attached to whichever
propagation step reached the label first, and the order depends on what else is in the session.


### And the comparison this section did not make, added at review (N-2)

§3b above compares the NEW per-file sweep against the NEW batch sweep. The question a
shared-file edit actually raises is a different one: **does the batch behave the same as it did
before `Wide/` joined the command line?** The reviewer ran the committed `2dd7dc3` script
against the same tree and diffed:

```
new batch vs new batch (2 runs)     0 of 79 files differ
old batch vs old batch (2 runs)     1 of 66 files differ   (der04, a clause flip)
old batch    vs new batch          22 of 79 files differ   = 13 new files + 9 MESSAGE differences
```

The nine are `der04`, `der07`, `der08`, `dup02`, `dup03`, `inc04`, `inc05`, `mis01` — the
refutation's blame CLAUSE moves — and **`inf02`, where the reported FIELD moves**,
`Shouldfail.Inf02.a` → `Shouldfail.Inf02.b`. **No verdict changes** (43 of 43 pre-existing
REJECTED files stay REJECTED, every LOADED stays LOADED) and **every position `file:line:col` is
unchanged**.

Three things follow, and only the third was in the original report:

1. adding files to a batch command line **deterministically** reshuffles other modules'
   diagnostics — the new script is byte-stable across runs, and the difference against the old
   script is systematic, not random;
2. **the instability is not confined to the clause: the FIELD named can move too.** That is
   strictly stronger than §7.5's claim, which was about the sentence only, and it matters to
   anyone who pins a diagnostic;
3. nothing in the tree pins these strings — `core/examples/shouldfail/RESULTS.md` compares
   messages relatively ("same msg"), never verbatim — so no recorded expectation is invalidated.

The mechanism is §7.5's and is not new (`corpus-run.sh`'s own header records it from
2026-09-03, and `der04` flips between two runs of the *old* script with no `Wide` anywhere).
The consequence for anyone writing a negative example: **pin the field and the position, never
the sentence** — and even the field is not safe in a batch.

### E1.4c The `shouldfail` modules are rejected, with the expected messages

All three, per file and in batch, with the messages recorded verbatim in
`core/examples/Wide/shouldfail/RESULTS.md`:

| case | verdict | diagnostic |
|---|---|---|
| `pivot01_key_column_is_also_value.e` | REJECTED, 0.05–0.06 s | `…:36:7: Fields appear twice in row: Wide.Shouldfail.Pivot01.period` |
| `win01_window_on_absent_column.e` | REJECTED, 0.05–0.09 s | `…:32:7: Row partitions are unsatisfiable at field 'Wide.Shouldfail.Win01.divisionName': the whole contains it but no part does` (per file; the batch prints the other clause — §3b, §7.5) |
| `win02_running_total_ordered_by_measure.e` | REJECTED, 0.06–0.14 s | `…:36:7: Fields appear twice in row: Wide.Shouldfail.Win02.amount` |

Each is caught by a different constraint in the helper's signature: `pivotBy`'s
`r <- (k, v, i)` disjointness, `rankWithin`'s `r <- (w, o)` containment, and
`Relation.Windowed.windowed`'s `t <- (r, s)` union of the aggregate's row with the window's.
`RESULTS.md` explains why each mistake is one a person actually makes.


The three brackets are my two sweeps and the reviewer's independent one; `win02` is
consistently the dearest of the three, at 2–3× the other two, which is the extra work the
`windowed` union does before the duplicate-field detector fires.

### E1.4d `sbt core/test`

**This gate came out RED before a fix, and the fix is not in the examples.**

Run three ways: with `core/examples/Wide` present, with it moved aside, and — after the fix
below — with it present again.

| run | total | failed | passed | which |
|---|---|---|---|---|
| **with `Wide`** | 914 | 2 | 912 | `TestConstraints.disjunction sound` (the known flake: "Gave up after only 0 passed tests. 501 tests were discarded"); `TestSurfaceParsers 2.3a` — `Expected 271 but got 315` |
| **without `Wide`** | 914 | 3 | 911 | the same two, **plus** `TestLegend."extra args are ignored": Falsified after 39 passed tests` (a random-seed flake that passed in the other two runs); `TestSurfaceParsers 2.3a` — `Expected 271 but got 302` |
| **with `Wide`, after the fix** (01:13) | 914 | 2 | 912 | `TestConstraints.disjunction sound` (the same known flake); `TestTolerantRead` — **on a module that did not exist when the first two runs were taken**, see below |
| **with `Wide`, after the fix** (01:19, re-run) | 914 | **1** | **913** | `TestConstraints.disjunction sound` — the known flake, and nothing else |

### The finding: `TestSurfaceParsers` asserts an exact corpus size

`scalacheck-binding/src/main/scala/TestSurfaceParsers.scala:81` ended its 2.3a property with

```scala
(failures.isEmpty :| failures.take(6).mkString(" ;; ")) && ((files ?= 271) :| s"$files files")
```

— **271 is a hard-coded count of the `.e` files under `core/src/main/resources/modules` and
`core/examples`.** Adding any example breaks it. Four example groups landed in this tree at
once on 2026-09-07 (`Wide`, and the sibling stages' `Algebra`, `Time` and `Present`); the
corpus was 315 `.e` files when this stage measured it and is **333** on the settled tree.

That it is not `Wide`'s doing is measured, not argued: **with `Wide` moved aside the same
property still fails, at 302.** 315 − 302 = 13, which is exactly this directory's file count.

The failure is on the COUNT ALONE. The property's real content is the `failures` list, and in
both runs that list is empty: all 315 files' headers agree between the old and the fused
pipeline. Nothing about the new examples' *content* troubles the parser.

### The fix, in two parts — the second added at review (N-1)

The count is derived rather than written down, **and a floor is kept**:

```scala
val expected = moduleFiles.size
(failures.isEmpty :| failures.take(6).mkString(" ;; ")) &&
  ((expected >= 250) :| s"only $expected corpus files found -- sweep broken?") &&
  ((files ?= expected) :| s"$files of $expected files compared")
```

The first version of this fix had only the derived equality, and the reviewer was right that
**that alone asserts nothing**: every branch of the property's match either does `files += 1`
or appends to `bad`, so `failures.isEmpty` already implies `files == moduleFiles.size`. The
second conjunct was a tautology given the first, and the whole property collapsed to
`failures.isEmpty`.

What the literal 271 bought and the derived equality does not is the **floor**. If
`moduleFiles` ever comes back empty or truncated — the JVM's working directory is not the
repository root, `core/src/main/resources/modules` has moved, a checkout is partial — then
`bad` is empty, `files` and `expected` are both 0, and the property passes on a corpus of zero
files. The literal failed loudly at `Expected 271 but got 0`. That is a failure mode this
repository has been bitten by before and guards against in three other places
(`corpus-verdicts.py` refuses to compare two all-`UNKNOWN` runs; `TestTolerantRead` uses
`files.size >= 180`; **this very file's second property uses `fixities > 30` and
`statements > 1000`**).

So the report's original sentence — "it is also stronger than the lower-bound idiom the sibling
test already uses" — had it backwards, and is withdrawn. Against a silently skipped file the
derived count is no better than `failures` alone (a skipped file lands in `bad`); against a
vanished corpus the lower bound is strictly better. The two conjuncts catch different things
and the file now carries both, which is exactly what its own second property does.

The change is +22/−1 lines in one test file, with the history in a comment. **No production
code was touched by this stage.**

### The gate cannot be taken fully green while three sibling stages are mid-flight

After the fix, `TestSurfaceParsers` passes. The re-run's second failure is new and is not this
directory's:

```
! Tolerant read.strict and tolerant agree, and the tolerant read is silent, over the corpus
  newly noisy: … SalesDashboard.e (type check):
    core/examples/Present/SalesDashboard.e:246:3: error: failed to unify type Double with type Int
    core/examples/Present/SalesDashboard.e:309:1: unchecked: depends on a broken definition
```

`core/examples/Present/` did not exist when the first two runs were taken: the directory was
created at 01:11 and `SalesDashboard.e` last written at 01:08, between the 01:01 run (where
`TestTolerantRead` PASSED) and the 01:13 one (where it did not). It belongs to a **fourth**
concurrently-running example stage and does not type-check yet. Nothing in `Wide` is named by
the message, and the A/B above already shows `Wide` does not move this test.

**And it cleared.** Re-run six minutes later, with `core/examples/Present` still present but
its module now compiling, the gate is

```
[info] Failed: Total 914, Failed 1, Errors 0, Passed 913
[error] 	com.clarifi.reporting.TestConstraints
[error] Total time: 285 s (04:45), completed Sep 7, 2026, 1:19:16 AM
```

**913 of 914, one failure, and that one is the documented flake** — which is exactly the
target the brief names. The run also came in at 285 s against the earlier 362 s, so the new
modules add nothing measurable to the suite's time (the variation is machine load, not corpus
size: the walkers parse rather than type-check, and 13 files of ~200 lines are noise against a
315-file corpus).

So the honest statement of this gate is:

* the failure this stage CAUSED — the hard-coded corpus size — is found, diagnosed and fixed,
  and the fix is a strict strengthening;
* the `TestConstraints` flake is the one the brief anticipates, and it is the only failure left;
* the transient third failure was another stage's work-in-progress arriving mid-run, and it
  cleared on its own. **Final: 913/914.**

### Two things still stale, left alone

* `TestStatementExtents` names three of its properties "(271 files)". They are labels, not
  assertions — nothing there compares a count — so they are now merely misleading, and are
  left for whoever consolidates the three example stages.
* `TestConstraints.disjunction sound` gave up on 501 discarded tests in all three runs. That is
  the flake the brief anticipates ("912 with the known flake"); it is unrelated to this work
  and untouched.

---

## 4. The L2 differential and the census

### 4a The differential: the model reproduces the compiler on every new solve

`LOOPTRACE_GROUPS="Wide Wide-shouldfail Ai" tracker/tools/looptrace-corpus.sh <outdir>`.
`Ai` is included as the control: it is the closest existing group, and running it in the same
session at the same defaults is what makes the census comparison below like-for-like rather
than a comparison against numbers taken in another round.

Run twice: once mid-stage, and again on the **final** tree after the last source edits (an
explicit `forall` on `startPivot`, one field renamed in `WardRoster`, and doc comments). Both
runs are clean; the table is the final-tree run, with the mid-stage `Ai` control it is compared
against in §4b.

| group | files | ermine | segments | model | agree | skip | hashdiff | eqdiff | rejected | fuel |
|---|---|---|---|---|---|---|---|---|---|---|
| `Wide` (final tree) | 10 | 31 s (rc=0, 0 timeouts, 0 dropped) | 114,844 | 453.6 s | **114,844** | **0** | **0** | **0** | 0 | 0 |
| `Wide-shouldfail` (final tree) | 4 | 17 s (rc=0) | 55,775 | 1.4 s | **55,775** | **0** | **0** | **0** | 1 | 0 |
| `Ai` (control) | 11 | 28 s (rc=0) | 83,942 | 25.9 s | **83,942** | **0** | **0** | **0** | 0 | 0 |
| `Wide` (mid-stage) | 10 | 28 s (rc=0) | 114,844 | 634.6 s | **114,844** | **0** | **0** | **0** | 0 | 0 |
| `Wide-shouldfail` (mid-stage) | 4 | 31 s (rc=0) | 55,775 | 1.9 s | **55,775** | **0** | **0** | **0** | 0 | 0 |

Every solve the compiler performed while loading the new group was replayed in the Lean model
at the compiler's own ids and diffed record for record, and **every one agreed**. Nothing was
skipped, nothing hit fuel, nothing was rejected by the model that the compiler accepted or the
reverse. The model needed no change to replay a new group, as the brief predicted.

The `nonpart` count for `Wide` is 1,483 and for `Wide-shouldfail` 1,094 — segments with no
partition constraint at all, which the differ counts separately and which agree trivially. The
one `rejected` in the final `Wide-shouldfail` run is the model **refuting** a solve, in
agreement with the compiler: the negative examples are certified too, not merely skipped.

One thing worth reading off the table on its own: **the model is 24× slower per segment on the
new group than on `Ai`** (5.5 ms against 0.31 ms), which is the first quantitative signal that
these solves are harder, before any census column is looked at.

### 4b The census

Instrument: `lake exe looptrace --replay <trace> --depth`, one line per solve, summarised by
location so that the ~69,000 standard-library boot solves in each trace (identical in all
three, and trivial — depth 0, no generative rule, at most one draw) do not dilute the group's
own figures. The `Wide` figures are from the FINAL-tree run; `Ai` is the control, taken in the
same session at the same flags.

| | `Ai` (control) | `Wide` | `Wide/shouldfail` |
|---|---|---|---|
| solves located in the group | 20,393 | **45,778** | 910 |
| verdicts | 20,393 SOLVED | 45,778 SOLVED | 909 SOLVED, **1 REJECTED** |
| **steps** max / mean | 137 / 0.49 | **249** / 0.39 | 29 / 0.54 |
| **nvars** max | 11 | **21** | 20 |
| **nparts** max | 7 | **14** | 9 |
| **nlbl** max | 14 | **46** | 4 |
| draws (total, incl. build) max / mean | 52 / 0.06 | **77** / 0.03 | 5 / 0.02 |
| draws in the LOOP, >0 on | 185 (0.91 %) | 165 (0.36 %) | 6 (0.66 %) |
| **vocabulary-fixed** (no loop draw) | 99.09 % | 99.64 % | 99.34 % |
| **chain depth** max | 3 | 3 | 1 |
| chain depth histogram | 0:20208, 1:153, 2:31, **3:1** | 0:45613, 1:116, 2:41, **3:8** | 0:904, 1:6 |
| `SplitConcrete` total / max on one solve | 303 / 8 | **396 / 14** | 10 / 3 |
| `Resolution` total / max on one solve | 525 / 41 | **811 / 62** | 3 / 3 |
| either generative rule fired on | 185 (0.91 %) | 165 (0.36 %) | 6 (0.66 %) |
| per-key mints: `maxdkey` / `remint` / `cremint` | 8 / 1 / 5 | 8 / **3** / **7** | 2 / 1 / 1 |
| **budget headroom**: largest draw count against 20,000 | 52 (0.26 %) | **77 (0.385 %)** | 5 (0.03 %) |

(The mid-stage run of the same group gave 295 steps, 100 draws and `Resolution` 834/83 — the
same picture one sample wider. Everything that carries an argument below holds on both.)

### What the new group reaches that the old one did not

**Size, not depth.** The chain-depth ceiling is the same, 3, in both groups — the new corpus
does **not** make the solver's derivation chain deeper. What it does is make every other
dimension bigger:

* **twice the variables (21 against 11), twice the partitions (14 against 7) and more than
  three times the labels (46 against 14)** in the largest solve. That is the direct consequence
  of a 38- to 43-column joined row meeting a helper whose signature has five row constraints,
  and it is the shape the old corpus simply did not contain;
* **1.8× the steps** in the largest solve (249 against 137);
* **1.5× the draws** in the largest solve (77 against 52);
* **`Resolution` fires 62 times in one solve** against 41 in the old corpus's worst, and 811
  times in all against 525 — from a group with 2.2× the solves;
* **eight solves at depth 3, against one.** The old corpus reaches depth 3 exactly once in
  20,393 solves; the new one does it eight times in 45,778. (The first version of this report
  turned that into "a 3.6× higher rate"; a rate computed from a denominator of one solve is not
  a rate, and the claim is withdrawn — the counts are the statement. Review N-8.);
* **the per-key re-mint counters move for the first time in a while**: `remint` 3 against 1 and
  `cremint` 7 against 5. Those are the counters round 5's pump argument is about, and this is a
  corpus that pushes them without a synthetic generator.

**Generative rules fire on a SMALLER fraction and a LARGER number.** 0.36 % of the new group's
solves fire `SplitConcrete` or `Resolution`, against 0.91 % of `Ai`'s — but that is 165 solves
against 185 from a group with 2.2× as many, and the ones that do fire go much further (396 and
811 firings against 303 and 525). The percentage falls because a wide fact table produces a
great many trivial solves — one per field literal, in effect — not because the interesting
solves got rarer. Both figures are far below the round-7/8 census's ~2.6 %, which was measured
before the 2026-09-05 defaults and over a different set of groups; the two columns here are
comparable to each other because they were taken in the same run at the same flags.

**The vocabulary-fixed fraction goes UP, not down.** 99.64 % of the new group's solves never
let an id enter a partition (the round-7 fragment), against 99.09 % for `Ai`. The wide corpus
is, by that measure, *easier* to certify than the tree corpus — again because width multiplies
the trivial solves.

**Budget headroom is enormous.** The largest draw count of any solve in the new group is
**77 against a budget of 20,000** — 0.385 %. The budget did not fire anywhere, on any module,
including the three that are meant to be refuted, and no module needed the `.slow` extension.
Nothing in this corpus comes within two orders of magnitude of the limit.

**The negative examples are certified too.** `Wide/shouldfail` contributes one solve the model
**refutes**, in agreement with the compiler — `rejected=1` in the differential, `1 REJECTED` in
the census. The other two modules are refuted before the loop is reached (the duplicate-field
detector fires in `RHS.merge`), which is why only one shows up here.

**What the `Wide/shouldfail` column actually counts** (added at review): the filter is
`core/examples/Wide/`, and that group's session loads `Helpers.e` first, so **837 of its 910
solves are `Helpers.e` being re-checked** and only **73 come from the three negative modules
themselves** (72 SOLVED plus the 1 REJECTED; steps 26, nvars 11, nparts 6, and all six loop
draws). The column is therefore mostly a second sample of the library. The same is true of the
`Wide` column, which includes `Helpers.e` too — the method is consistent, but the reader should
know which number is which.

**Two rows of this table are the same measurement.** "draws in the LOOP, >0 on" and "either
generative rule fired on" are 185 and 185 in `Ai`, and 165 and 165 in `Wide` — not a
coincidence of presentation: `SplitConcrete` and `Resolution` are the only rules that mint, so
the two rows are the same predicate seen twice, and the identity holds on all 66,171 solves
here. The "vocabulary-fixed" percentage and the "generative rules" percentage are therefore
complements of one another by construction, not two independent findings. (Review §9.1.)

### The honest reading

The new group is a substantially harder corpus by every size measure and by the absolute count
of generative steps, it moves the per-key re-mint counters, and it is the first example code
anywhere in the tree that exercises `Relation.Windowed` at all. It does **not** find a deeper
chain, a re-mint at a key beyond the old maximum of 8, or a solve anywhere near the budget. If
the point of extending the corpus was to find a case that breaks the termination story, this
did not find one — which is itself a result, and one the model's clean differential over
170,619 new segments makes precise.

---

## 5. The RUnion re-measurement at the new defaults

**A caveat that came out of review, and that has to be read before the tables: this is not a
reproduction of `Ai/README.md`'s figures, and cannot be.** The README says its three rows were
measured "on one small module" and **never names the module**. So neither the 1.04 s baseline
nor the "does not finish" one is reproducible by anybody, and three E-stages have now produced
three different reconstructions of it (this one, E2's, and E3's, whose form A is 1.04 s → 0.17 s
and whose bundled form is 0.12 s). What follows is therefore a fresh controlled experiment that
answers the brief's question — *does the bundled form finish now?* — not a re-run of a recorded
measurement. Review N-4.

`Ai/README.md` and the header of `Ai/Common.e` both record the measurement that shaped that
library:

| form | time (as recorded, pre-2026-09-05 defaults) |
|---|---|
| inline `combine_Op (if_Op p a b) fld rel` | 1.04 s |
| via `withColumn` (adds one `RUnion2`) | 0.50 s |
| via a helper whose signature bundles `RUnion3` **and** `RUnion2` | **does not finish** |

The brief asks whether the bundled form finishes now. **It does.**

### The faithful reproduction

Three copies of `core/examples/Ai/SupplyChainInventory.e`, byte-identical except for the module
name and the definition of `labelled`, loaded behind `core/examples/Ai/Common.e`, one JVM each,
`-Dermine.useInterface=false -XX:ActiveProcessorCount=2`, twice each. Times are the module's own
`Importing module` figure.

| form | run 1 | run 2 | verdict |
|---|---|---|---|
| **A** inline, exactly as shipped | 1.46 s | 1.05 s | loads |
| **B** via `Ai.Common.withColumn` (one `RUnion2`) | 1.12 s | 1.11 s | loads |
| **C** via a helper bundling `RUnion3` + `RUnion2` | 1.30 s | 1.51 s | **loads** |

Form A lands on 1.05–1.46 s, which happens to bracket the README's 1.04 s — but see the caveat
above: that agreement cannot be used to identify the module, and this report's own second table
below gives form A at 0.29–0.36 s on a smaller module, which does not agree with it at all. Two
reconstructions of one baseline that differ threefold cannot both be the original.

**On a quiet machine the reviewer measured the same three forms as A 1.06/1.08, B 1.09/1.06,
C 1.28/1.27 s** — tighter than mine and the same conclusion. Taking those as the controlled
figures: **form C, which previously did not terminate, costs 1.2× form A**, and the three forms
are within a factor of 1.2 of one another instead of being separated by non-termination.

The helper in form C, in full — this is the shape the README describes:

```
withConditionalColumn : forall v r s t a c rin out opc opa rel.
                        (exists o. RUnion3 v r s t, RUnion2 out rin c, rin <- (v, o),
                         AsOp opc, AsOp opa, RelationalComb rel)
                     => Predicate r -> opc s a -> opa t a -> Field c a
                     -> rel rin -> rel out
withConditionalColumn p x y f = combine_Op (if_Op p x y) f
```

### The same three forms on a smaller module

Stripped to the nine-column join and the conditional, nothing else:

| form | run 1 | run 2 |
|---|---|---|
| A inline | 0.29 s | 0.36 s |
| B via a one-`RUnion2` helper | 0.33 s | 0.61 s |
| C via the `RUnion3`+`RUnion2` helper | 0.51 s | 0.83 s |

Same ordering, same conclusion, and the spread between the three is smaller than the
run-to-run spread of any one of them.

### What this changes, and what it does not

The **cliff has moved**: bundling two overlapping row unions in one signature is no longer
fatal. `Wide/Helpers.e` therefore ships `withDerived2` (two unions) and `withDerived3` (three),
which `Ai/Common.e` could not have.

The **advice survives, with a much smaller multiplier than the first version of this report
claimed.** That version argued from the group's own check times: `ClaimsExperience.e` (2.60 s)
and `WardRoster.e` (2.13 s) are the two modules that bundle and the two slowest, "3–4× the
group's median". The reviewer is right that this is worse than uncontrolled — `ClaimsExperience`
also carries the widest row in the corpus, three window helpers and a defaulted pivot, and
`WardRoster` also carries a four-link chain, so the comparison measures four things at once.
**The controlled number is the A/B/C table above: 1.2×** (1.28 s against 1.06 s), and ~2× on
the nine-column module. The "3–4×" is withdrawn from this report, from `Wide/README.md` and
from `Helpers.e`'s header. (Review N-4.)

What survives is a different argument, and it is the one the library now makes: bundling is not
expensive, but a two-union helper publishes **eight** partition constraints and a three-union
helper **twelve**, against `rankWithin`'s five — so the cost is what a reader has to understand,
not what the solver has to do. Reach for it last for that reason.

`Ai/Common.e`'s own warning has been left as it is: it is a true record of a measurement taken
at the defaults of the day, and `Wide/Helpers.e`'s header points at this section for the
re-measurement rather than editing history.

### A second re-measurement, taken because the prediction was wrong

`share` (one helper call, whose Op carries `(/_Op)`'s four-constraint `OpBin` lattice on top of
a window's minted row) was expected to be dearer than `windowTotal` followed by an ordinary
division. It is not:

| form | 6-column row | 26-column row (`RevenueShare.book`) | reviewer, 6-column, 3 runs |
|---|---|---|---|
| `share ks m f` | 0.06 / 0.05 s | 0.06 / 0.05 s | **0.08 / 0.08 / 0.07 s** |
| `windowTotal` then `combine_Op (col m /_Op col tot)` | 0.09 / 0.08 s | 0.08 / 0.08 s | **0.15 / 0.10 / 0.11 s** |

The reviewer's absolute numbers are higher (different relations) but the one-call spelling wins
every run with no overlap between the two sets, at 1.3–1.9× against my 1.5–1.6×. **Confirmed.**

One larger solve beats two smaller ones, and the width of the carried row does not move either
number. That is worth recording as a small piece of evidence for a claim the termination work
makes structurally: **the solver's cost tracks the constraint set, not the row.** The corpus
shows the same thing at scale — `ClaimsExperience` carries 43 columns and checks in 2.60 s,
while `Leaderboard` carries 38 and checks in 0.64 s; the difference is `withDerived3`, not
five columns.

Both spellings are kept side by side in `Wide/RevenueShare.e`, and the doc comment on `share`
records the measurement rather than the prediction.

---

## 6. Renderings

The brief asks for every report to be rendered through the REPL harness. **It cannot be:
there is no `render` and no `Writer` in this repository** (§7.1). What follows is the nearest
substitute that is honest, and it is a stronger check than a header dump: every report's
underlying RELATION is compiled to SQL by the shipped scanners and then EXECUTED, so the
tables below are computed, not transcribed.

### Method, and how to re-run it

```
tracker/tools/sql-render.sh tracker/tools/wide-render-probe.e /tmp/wide-render
```

(That command needs no JVM and no jar. It does need `bin/ermine`, for the probe itself.)

`wide-render-probe.e` imports the nine report modules and defines, per relation,
`unsafePerformIO (dumpQuery <scanner> <relation>)`. `sql-render.sh` extracts each String,
rewrites MS SQL to SQLite where needed (`tracker/tools/tsql2sqlite.py`) and executes it against
an in-memory SQLite database using **`python3`'s stdlib `sqlite3`** — no jar, no classpath, no
JVM.

Two amendments were made to that route at review, and both were right:

* **the name↔SQL mapping was positional** and would have shifted silently if a name in the
  `.in` file were one the probe module does not define — writing real SQL under the wrong
  `q_*` name with no error anywhere (N-7). The `.in` file is now **self-labelling**: every
  binding name is preceded by the string literal `"@@<name>"`, the extractor pairs a name with
  the answer that follows it, and it **exits non-zero** if any name never answers. The run
  below prints `names: 30 asked, 30 answered, 15 produced SQL`.
* **the executor was a 35-line `SqlRun.java`** run by single-file source launch, with the
  driver jar scraped out of `target/ermine-classpath` by `grep sqlite-jdbc` — an undeclared
  dependency on a file `bin/ermine` happens to have written, and an empty classpath would have
  failed per query with no diagnostic (N-8). It is now ten lines of `python3` inline in the
  script, and `SqlRun.java` is deleted.

Two scanners, because of §7.3: non-window relations are dumped through `sqlite` and run as they
stand; window relations are dumped through `sqlServer`, which is the only emitter with a real
`OVER` clause, and rewritten. The rewriter handles exactly two dialect differences — the
table-value constructor `(values (…)) as lit([c],…)` becomes a `union all` of selects, and the
emitter's missing space in `[col]desc` is restored. Nothing about the window clauses is
touched; SQLite has supported `OVER` since 3.25 and the jar here is 3.51.

### What came back

| relations probed | 27 |
|---|---|
| dumped and **executed**, real rows | **15** |
| `Mem` (a `groupBy` result) — "Don't know how to dump a mem" | 4 |
| `lookupLatest`'s temp table — "Emission not supported for SqlLoad" | 2 |
| pivots — **panic** in `Native.Record.scalaRecord#` | 6 |

Eight of the nine report modules render at least one table. `SalesLedger.e` is the exception:
both of its outputs are pivots and both panic, and its inputs are `Mem`s. Its result is still
visible, as a type: the published interface says

```
revenueByQuarter : Mem (|q3, q2, customerName, q4, q1|)
revenueByLine    : Mem (|customerName, bikes, period, apparel, spares|)
```

— the existential identity row `i` minted by `pivot` came out as `{customerName}` and
`{customerName, period}`, which is the pivot doing its job at the type level even though it
cannot do it at the value level in this build.

### The tables

Every one below is the actual output of the actual query, trimmed to the interesting columns;
the column count in each caption is the full width of the relation. Regenerated after the
review corrections, so `q_survey_melt` now carries the four profile columns the widened melt
keeps and the numbers print in Python's `float` form rather than Java's `4.12E7`.

**`Leaderboard`** — `rankWithin {division} (desc kills) killRank season`

```
division  handle  kills   killRank
--------  ------  ------  --------
North     vex     1204.0  1
North     kite    1188.0  2
North     nova    1120.0  3
North     sable   1041.0  4
North     orrin   903.0   5
South     rax     1096.0  1
South     brant   1009.0  2
South     tessel  981.0   3
South     quill   842.0   4
```

**`Leaderboard`** — `topNWithin {division} (desc damageDealt) 3 damageRank season`

```
division  handle  damageDealt  damageRank
--------  ------  -----------  ----------
North     kite    172100.0     1
North     vex     168400.0     2
North     nova    159300.0     3
South     rax     156200.0     1
South     brant   147600.0     2
South     tessel  141800.0     3
```

**`Leaderboard`** — `nTileWithin {division} (desc economyRating) 4 economyQuartile season`

```
division  handle  economyRating  economyQuartile
--------  ------  -------------  ---------------
North     nova    96.0           1
North     vex     91.0           1
North     sable   88.0           2
North     orrin   84.0           3
North     kite    79.0           4
South     rax     82.0           1
South     brant   77.0           2
South     tessel  74.0           3
South     quill   68.0           4
```

**`TrialBalance`** — `runningTotal {accountCode} (asc postingDay) netAmt runningBalance ledger`

```
accountCode  postingDay  netAmt     runningBalance
-----------  ----------  ---------  --------------
4000         2025-01-31  -412000.0  -412000.0
4000         2025-02-28  -388500.0  -800500.0
4000         2025-03-31  24000.0    -776500.0
4000         2025-04-30  -451200.0  -1227700.0
6100         2025-01-31  188000.0   188000.0
6100         2025-02-28  191400.0   379400.0
6100         2025-03-31  203900.0   583300.0
6400         2025-01-15  41200.0    41200.0
6400         2025-02-15  38800.0    80000.0
6400         2025-03-15  52600.0    132600.0
```

**`TrialBalance`** — `movingAverage 3 {accountCode} (asc postingDay) netAmt trailingAvg ledger`

```
accountCode  postingDay  netAmt     trailingAvg
-----------  ----------  ---------  -------------------
4000         2025-01-31  -412000.0  -412000.0
4000         2025-02-28  -388500.0  -400250.0
4000         2025-03-31  24000.0    -258833.33333333334
4000         2025-04-30  -451200.0  -271900.0
6100         2025-01-31  188000.0   188000.0
6100         2025-02-28  191400.0   189700.0
6100         2025-03-31  203900.0   194433.33333333334
6400         2025-01-15  41200.0    41200.0
6400         2025-02-15  38800.0    40000.0
6400         2025-03-15  52600.0    44200.0
```

**`RevenueShare`** — `windowTotal` at two levels, then two divisions

```
accountName        regionName  segmentName  mrr      regionTotal  regionPct            segmentTotal  segmentPct
-----------------  ----------  -----------  -------  -----------  -------------------  ------------  -------------------
Ostrava Bank       Americas    Financial    27400.0  93500.0      0.293048128342246    61300.0       0.4469820554649266
Cadence Health     Americas    Healthcare   41800.0  93500.0      0.4470588235294118   78700.0       0.531130876747141
Bramble Logistics  Americas    Logistics    18200.0  93500.0      0.1946524064171123   33500.0       0.5432835820895522
Pellet Foods       Americas    Logistics    6100.0   93500.0      0.06524064171122995  33500.0       0.18208955223880596
Kestrel Insure     EMEA        Financial    33900.0  80000.0      0.42375              61300.0       0.5530179445350734
Vireo Clinics      EMEA        Healthcare   15600.0  80000.0      0.195                78700.0       0.19822109275730623
Marrow Labs        EMEA        Healthcare   21300.0  80000.0      0.26625              78700.0       0.27064803049555275
Talus Freight      EMEA        Logistics    9200.0   80000.0      0.115                33500.0       0.2746268656716418
```

**`RevenueShare`** — `share {regionName} mrr shareOfRegionPct book`

```
accountName        regionName  mrr      shareOfRegionPct
-----------------  ----------  -------  -------------------
Cadence Health     Americas    41800.0  0.4470588235294118
Bramble Logistics  Americas    18200.0  0.1946524064171123
Ostrava Bank       Americas    27400.0  0.293048128342246
Pellet Foods       Americas    6100.0   0.06524064171122995
Kestrel Insure     EMEA        33900.0  0.42375
Vireo Clinics      EMEA        15600.0  0.195
Talus Freight      EMEA        9200.0   0.115
Marrow Labs        EMEA        21300.0  0.26625
```

**`SurveyPanel`** — `melt4 questionKey questionScore scoreSpeed scorePrice scoreSupport scoreQuality scored` — four profile columns kept in the identity, so the analysis can group by country

```
countryCode  industryName   waveId  respondentId  questionKey   questionScore
-----------  -------------  ------  ------------  ------------  -------------
BR           Software       2       8004          scorePrice    5.0
BR           Software       2       8004          scoreQuality  3.0
BR           Software       2       8004          scoreSpeed    2.0
BR           Software       2       8004          scoreSupport  2.0
DE           Software       1       8002          scorePrice    4.0
DE           Software       1       8002          scoreQuality  5.0
DE           Software       1       8002          scoreSpeed    3.0
DE           Software       1       8002          scoreSupport  3.0
DE           Manufacturing  1       8001          scorePrice    2.0
DE           Manufacturing  1       8001          scoreQuality  4.0
... (24 rows in all)
```

**`WardRoster`** — the four-link pipeline

```
wardName  shiftStart  staffName    shiftIndex  overtimeHours  cumulativeOvertime  agencyCost  wardAgencyTotal  totalCost  agencySharePct
--------  ----------  -----------  ----------  -------------  ------------------  ----------  ---------------  ---------  --------------
Ash       2025-06-02  A. Whitlock  1           0.5            0.5                 0.0         1200.0           408.0      0.0
Ash       2025-06-03  D. Serrano   2           2.0            2.5                 0.0         1200.0           416.0      0.0
Ash       2025-06-04  F. Nkemelu   3           0.0            2.5                 588.0       1200.0           588.0      0.49
Ash       2025-06-05  A. Whitlock  4           1.0            3.5                 0.0         1200.0           432.0      0.0
Ash       2025-06-06  G. Petrides  5           0.0            3.5                 612.0       1200.0           612.0      0.51
Birch     2025-06-02  H. Mbeki     1           0.0            0.0                 0.0         495.0            420.0      0.0
Birch     2025-06-03  J. Karlsen   2           1.5            1.5                 0.0         495.0            428.0      0.0
Birch     2025-06-04  K. Ozturk    3           0.0            1.5                 495.0       495.0            495.0      1.0
Birch     2025-06-05  H. Mbeki     4           2.0            3.5                 0.0         495.0            536.0      0.0
```

**`BranchDeposits`** — `movingAverage 3 {branchName} (asc asOfDay) balanceEur balance3m`

```
branchName  asOfDay     balanceEur  balance3m
----------  ----------  ----------  ------------------
Rathmines   2025-01-31  41200000.0  41200000.0
Rathmines   2025-02-28  42800000.0  42000000.0
Rathmines   2025-03-31  41100000.0  41700000.0
Rathmines   2025-04-30  43900000.0  42600000.0
Rathmines   2025-05-31  45300000.0  43433333.333333336
Salthill    2025-01-31  17800000.0  17800000.0
Salthill    2025-02-28  17400000.0  17600000.0
Salthill    2025-03-31  18600000.0  17933333.333333332
Salthill    2025-04-30  19100000.0  18366666.666666668
Salthill    2025-05-31  18900000.0  18866666.666666668
```

**`MediaSpend`** — `topNWithin {monthName} (desc spendUsd) 2 spendRank media`

```
monthName  campaignName         channelName  spendUsd  spendRank
---------  -------------------  -----------  --------  ---------
Feb        Spring range launch  search       91000.0   1
Feb        Spring range launch  video        68000.0   2
Jan        Spring range launch  search       84000.0   1
Jan        Spring range launch  social       51000.0   2
Mar        Spring range launch  social       47000.0   1
Mar        Always-on retention  search       36000.0   2
```

**`ClaimsExperience`** — `withDerived3 … claims`

```
claimId  lineOfBusiness  perilName      incurredAmt  paidAmt   paidToIncurredPct   lossRatioPct        netIncurred
-------  --------------  -------------  -----------  --------  ------------------  ------------------  -----------
7003     Property        Windstorm      329000.0     241000.0  0.7325227963525835  26.11111111111111   288000.0
7007     Motor           Theft          31900.0      31900.0   1.0                 5.406779661016949   27500.0
7001     Motor           Collision      18400.0      18400.0   1.0                 4.487804878048781   16300.0
7005     Liability       Bodily injury  415000.0     0.0       0.0                 18.20175438596491   415000.0
7008     Property        Bodily injury  14200.0      0.0       0.0                 2.406779661016949   14200.0
7002     Motor           Theft          62000.0      0.0       0.0                 15.121951219512194  62000.0
7004     Property        Windstorm      96500.0      96500.0   1.0                 7.658730158730159   88300.0
7006     Liability       Collision      7300.0       7300.0    1.0                 0.3201754385964912  7300.0
```

**`ClaimsExperience`** — `nTileWithin {lineOfBusiness} (desc incurredAmt) 10 severityDecile claims`

```
lineOfBusiness  claimId  incurredAmt  severityDecile
--------------  -------  -----------  --------------
Liability       7005     415000.0     1
Liability       7006     7300.0       2
Motor           7002     62000.0      1
Motor           7007     31900.0      2
Motor           7001     18400.0      3
Property        7003     329000.0     1
Property        7004     96500.0      2
Property        7008     14200.0      3
```

### Reproducibility

The whole of §6 was produced twice, once by hand during the stage and once at the end through
`tracker/tools/sql-render.sh` as a check that the tool committed to the tree reproduces it.
**Thirteen of the fifteen rendered tables were byte-identical between the two runs**, and the
twelve failures were the same twelve with the same messages. A third run, after the review
corrections and through the rewritten (python) executor, changes exactly two: `q_survey_melt`
gains the four profile columns the widened melt now keeps, and `q_branch_trend` prints
`41200000.0` where the JVM printed `4.12E7`. Every other table, and every failure, is
unchanged.

---

## 7. What could not be written, and what turned out to be broken

Seven findings. Three are about the RUNTIME rather than the type system, and two of those are
live bugs that a user of these examples will hit. None of them affects type-checking, which is
what the certification corpus measures — but the brief asks for renderings, and these are why
§6 is shaped the way it is. The eighth, the hard-coded corpus size in `TestSurfaceParsers`, is
in §3d with the gate it broke.

### 7.1 `render` does not exist in this repository

The Ai examples' header blocks all say

```
>> :load core/examples/Ai/SupplyChainInventory.e
>> render inventoryReport
```

and the REPL answers

```
>> render inventoryReport
runtime error: <interactive>:1:1: error: undefined term
```

There is no `render` — not as a REPL command (`Console.scala` has no such case) and not as an
Ermine term (nothing in `core/src/main/resources/modules` defines one). Running a `Report`
needs a `Writer f z`, and `Layout/Writer.e` declares
`foreign data "com.clarifi.reporting.writers.Writer" Writer` while
`core/src/main/scala/com/clarifi/reporting/writers/Writer.scala` defines only the abstract
class; every concrete writer (HTML, JavaFX) lives in the separate `ermine-writers` project,
which is not on this build's classpath.

So a `Report` value in this repository can be constructed, type-checked and shown by type — and
that is all. **The `Wide/*.e` headers therefore do not say `render`**; they say what actually
works.

This is not a regression introduced here; it is a documentation error in the existing
`core/examples/Ai/*.e` headers and README that a reader will hit on their first attempt.

### 7.2 `Relation.Pivot.pivot` and `Relation.Predicate.all` panic when forced — a live bug

Forcing any pivoted relation gives

```
>> revenueByQuarter
runtime error: Panic: unexpected runtime value in Native.Record.scalaRecord# - MapView(<not computed>)
```

and so does forcing any `Relation.Predicate.all`.

Diagnosis, from the source and confirmed by probe:

* `Relation/Pivot.e`'s `pivot` builds each column's filter with `record# k` and then feeds it
  to `scalaRecord#`.
* `Lib.scala:986-990` — `record#` answers `Prim(m.mapValues(_.whnf))`. Since Scala 2.13,
  `Map#mapValues` returns a lazy **`MapView`**, which is *not* a `Map`.
* `Lib.scala:1005-1009` — `scalaRecord#` is
  `Fun(x => x.whnfMatch("Native.Record.scalaRecord#") { case Prim(t: Map[String, Runtime]) => … })`.
  A `MapView` does not match `Map`, so `whnfMatch` falls through to its panic.
* Probed directly, in one REPL session:
  `probeRecord = record# { q = 1 }` answers `res0 : Record# = MapView(<not computed>)`, and
  `probeScalaRecord = scalaRecord# (record# { q = 1 })` panics. That is the whole bug in two
  lines.

**Blast radius** — widened at review (N-5), and `header#` promoted from a guess to a measured
fact. Grepping every consumer of `record#` / `scalaRecord#` / `header#` in
`core/src/main/resources/modules`:

| stdlib function | site | why |
|---|---|---|
| `Relation.Pivot.pivot` / `pivotWithDefault` | `Pivot.e:112,116` | `scalaRecord# . record#` — and with them `Layout.Report.pivotTabular` and `Layout/Report/Fulcrum/Legendary.e` |
| `Relation.Predicate.all` | `Predicate.e:77` | `fromRecord# … . scalaRecord# . record#` |
| `Record.header : {..r} -> Row r` | `Record.e:24` | `header# . record#`; `header#` (`Lib.scala:1016`) matches on `Map` the same way |
| `Record.anyRecordOrd : Ord {..r}` | `Record.e:21` | **the record `Ord`** |
| `Relation.Sort.partialRecordOrd` | `Sort.e:109` | the record comparator used for sorting |
| `Relation.nonEmptyRelation` | `Relation.e:33` | `mkRelationWithHeader# (header#_Rec . record#_Rec $ r) …` |
| `Layout.Chart.srecKeys` | `Chart.e:188` | `part (scalaRecord# . record#)` |
| `Layout.Presentation`'s `extract#` path | `Presentation.e:82` | `extract# pr' . scalaRecord# . record#` |

`header#` is **not** a guess: the reviewer probed it directly and it panics with its own
message, `Panic: unexpected runtime value in Record.header# - MapView(<not computed>)`. The
first version of this section hedged; it should not have.

**What is NOT affected, and this matters:** `Relation.relation` builds its result with
`mkRelation# (toList# r)` (`Relation.e:24`) and never goes near `record#`. That is why the
fifteen SQL renderings in §6 work at all, and it is worth saying explicitly, because "`record#`
is broken" would otherwise read as "no relation literal can be forced".

**Why it was not caught.** `core/examples/PivotTest.e`, the only pre-existing pivot example,
never forces `pivotData`; Ermine is lazy, and `:load` type-checks without evaluating. Nothing
in `core/test` evaluates a pivot either. This directory found it because it is the first thing
that ran one.

**The fix is THREE `.toMap`s, not one** — the first version of this section said one, and the
reviewer is right that it understates it (N-5). Patching only `Lib.scala:988` makes
`scalaRecord#` *match*, and it then answers `Prim(t mapValues (toPrimExpr(_)))` — a `MapView`
again, published at type `ScalaRecord#`. Its own consumer two lines further down,

```scala
primOp(Global("Native.Record", "scalaRecordIn#"),
       Fun(x => x.whnfMatch("Native.Record.scalaRecordIn#") {
         case Prim(t: Record) => Prim(t mapValues (fromPrimExpr(_)))
       }), scalaRec ->: rec)
```

matches on `Map` in exactly the same way and would panic on it — and `scalaRecordIn#` is live,
at `Layout/Report.e:1594` and `:1608`. So the minimum is **`Lib.scala:988`, `:1007` and
`:1012`**; `header#` (`:1016`) already forces its own result and needs none. Downstream of
`pivot#`, `km.extract[List[(Record, …)]]` is an unchecked `asInstanceOf`, so a `MapView` that
got that far would surface as a `ClassCastException` with no message rather than as a panic.

**And a test that FORCES a pivot.** Three lines in `core/test` evaluating
`PivotTest.pivotData` would have caught this and will catch the next one; laziness is the whole
reason five years of `core/test` never saw it.

The repository already has `tracker/tools/fix_mapvalues.py`, written for exactly this class of
migration site, and
`core/src/main/scala/com/clarifi/reporting/record/RecordMap.scala:25` carries a comment
warning about precisely this trap; every other `mapValues` in `core/src/main/scala` (34 of
them) ends in `.toMap` — these three are the exceptions. **The fix was deliberately NOT applied
here**: this stage is an examples stage, the brief restricts `sbt` to the `core/test` gate, and
recompiling the compiler mid-stage would invalidate every measurement in this report. It is
left as a follow-up with a ready-made reproduction (`probeScalaRecord` above, or forcing
`core/examples/PivotTest.e`'s `pivotData`).

### 7.3 Window functions emit real SQL only through the MS SQL emitter

`SqlEmitter.emitOver` (`SqlEmitter.scala:265-268`) is a stub:

```scala
def emitOver(e: SqlExpr, over: SqlOver): RawSql =
  "TODO I don't yet know how to play %s over %s".format(e.emitSql(this), over)
```

and only `MsSqlEmitter` mixes in the real implementation, `EmitOver_UsingOver`
(`SqlEmitter.scala:538-577`, at `:832`). `SqliteEmitter`, `MySqlEmitter`, `PostgreSqlEmitter`
and `VerticaSqlEmitter` all inherit the stub. Dumping `Wide.Leaderboard.killLeaders` through
the SQLite scanner produces, in the middle of an otherwise valid query,

```
(TODO I don't yet know how to play RawSql(Vector(RANK, (, , ))) over SqlOver(List(...),...)) rankInTeam
```

This is a silent wrong answer, not an error: the string is emitted into the SQL and fails at
the database. Postgres and SQLite have supported `OVER` since 2009 and 3.25 respectively, so
the stub is stale rather than a real capability gap. §6 works around it by dumping the window
reports through the MS SQL emitter and rewriting the two dialect differences.

### 7.4 `dumpQuery` cannot dump a `Mem`, and cannot emit `lookupLatest`'s temporary

Two further gaps found while rendering:

* Anything whose head is a `Mem` — i.e. everything `groupBy` produces — answers
  `<error: Don't know how to dump a mem.>`. `Scanner.dumpMem` is
  `sys.error("Don't know how to dump a mem.")` (`Scanner.scala:35`) and `SqlScanner` does
  not override it. Four of the twenty-seven relations probed are in this class.
* `Wide.BranchDeposits.withSpread` and `withUsd`, which go through `lookupLatest`, answer
  `<error: Emission not supported for sql statement SqlLoad(TableName(t…))>` — the
  `materialize`/`letR` inside `nearestDate` compiles to a temp-table load that the dumper has
  no case for.

Both are limits of *dumping*, not of execution: a real `Scanner` running against a database
would materialise the temp table and scan the `Mem`. They matter here only because dumping is
the only execution this repository can do.

### 7.5 One diagnostic's wording is the reason for a propagation, not a description of the clash

`Wide/shouldfail/win01_window_on_absent_column.e` — a window partitioned by a column the
relation has not got — is correctly rejected, at the right field, with

```
Row partitions are unsatisfiable at field 'Wide.Shouldfail.Win01.divisionName':
the whole contains it but no part does
```

but here a **part** carries `divisionName` and the whole does not; the sentence describes the
opposite situation. The string is the reason recorded for a unit-propagation step
(`Constraints.scala:2451`, `setVar(v, false, "the whole contains it but no part does")`, and
its `assign` twin at `:2670`), and the refutation prints the label together with the last
reason attached to it. Verdict and field are right; the explanation will misdirect a reader.

**The corpus gate proves the diagnosis on its own.** Loaded in a batch instead of per file, the
SAME module prints the OTHER clause —

```
per file:  … 'Wide.Shouldfail.Win01.divisionName': the whole contains it but no part does
in batch:  … 'Wide.Shouldfail.Win01.divisionName': a part contains it but the whole does not
```

— and the batch wording is the accurate one. The sentence is therefore not a description of
the clash at all; it is whichever propagation reason happened to be attached to the label
first, and which that is depends on what else the session already holds. Six pre-existing
`shouldfail/` modules behave the same way, which `corpus-run.sh`'s own header records as a
measurement from 2026-09-03; `win01` is the seventh, and the first for which both clauses can
be checked against the program.

Recorded, not fixed — the same reason as 7.2. The fix is not the wording of either string but
the choice of which reason to report: the refutation should carry the reason for the CLASH, not
for the last propagation to touch the label.

### 7.6 What the type system cannot express: a variadic melt, and a relation-level dynamic pivot

Both directions of the wide/long round trip are **fixed arity**, and neither can be otherwise:

* **`meltN` must name its columns.** Each arm of a melt drops the other melted columns,
  adds the literal column name, and renames the survivor; the arms are then unioned. A melt
  over "whatever columns this row happens to have" would have to iterate a row variable,
  minting one `except`/`combine`/`rename` per field and one row union per arm. There is no
  construct in the language that folds over the fields of an abstract row at the type level —
  `Row r` is a runtime value (`Row (List (String, PrimT))`) but its *type* is opaque, so a
  fold over it cannot produce a type. `Helpers.e` therefore ships `melt2`, `melt3` and
  `melt4`, and says so.

  The consolation is that the fixed-arity form is *cheap*: `melt3`'s hand-written signature is
  two constraints. Its inferred signature, for comparison, verbatim:

  ```
  (exists r3 r21 rs ro so r4 t e so1 rs1 ro1 ro2 so2 rs2 r22 r5 r23 t1 t2.
     t1 <- (rs, so, ro),   r5 <- (c1, r),        c <- (rs, so),
     c <- (rs2, so2),      r1 <- (c1, r2, ro1, rs1), RelationalComb rel,
     r22 <- (ro2, rs2),    t2 <- (rs1, so1, ro1), t2 <- (e, r),
     r21 <- (ro, rs),      r23 <- (rs1, ro1),    t1 <- (e, r2),
     t <- (e, c1),         r1 <- (c1, r, ro, rs), r4 <- (r, r2),
     r23 <- (ro1, rs1),    d <- (e, a),          r3 <- (c1, r2),
     c <- (rs1, so1),      r1 <- (r2, r, ro2, rs2), r22 <- (rs2, ro2),
     r21 <- (rs, ro),      t <- (rs2, so2, ro2))
  => Field c String -> Field a b -> Field c1 b -> Field r b -> Field r2 b -> rel r1 -> rel d
  ```

  **20 to 22 row constraints over 19 existentials, against 2 over 1** — and the range is the
  point. The reviewer put the same body in their own scratch module and got **20**; mine gives
  22. The difference is exactly two *duplicated-up-to-argument-order* pairs — `r22 <- (ro2, rs2)`
  with `r22 <- (rs2, ro2)`, and `r23 <- (rs1, ro1)` with `r23 <- (ro1, rs1)` — and the
  right-hand side of a partition constraint is a SET, so each rotation entails its twin and is
  pure noise. Published constraint lists print in `Set` = hash = id order and are not
  canonicalised (the residual non-canonicality D1's review documents), so **the count is a
  property of where the definition sits, not of the body**. `Wide/Signatures.e` proves the two
  sets equivalent by machine, in both directions, which is the sharpened version of the lesson:
  a hand-written signature is not merely smaller but *stable*, where the inferred one is not.
  The reduction is therefore tenfold to elevenfold, not "elevenfold". (Review N-11.)

* **A pivot whose columns come from the DATA cannot be a relation.** `Relation.Pivot.pivot`
  needs a `Fulcrum k v p` whose `p` is a *type-level* row, so the produced column names must
  be known statically. Pivoting on "whichever periods are actually in the table" is possible,
  but only at the *report* level: `Layout.Report.pivotTabular` scans the key column at runtime
  (`orderedScanner`/`scanRelation`) and builds the `Fulcrum` inside a continuation, where the
  produced row is existentially bound by `PivotSpec` and never escapes. That path needs a
  live `Scanner`, so it cannot appear in a self-contained example in this repository (7.1),
  and no `Wide/` module uses it. Recorded as the boundary: **static columns → relation-level
  pivot; dynamic columns → report-level pivot, and no way to get a relation back out.**

  `Helpers.e` covers the static case twice over — `startPivot`/`pivotColumn` when the produced
  names differ from the key values, `pivotOnRow` when they do not — and says which to use.

### 7.7 Two field names that cannot be used, found the hard way

Field declarations share a namespace with terms, so a field whose name collides with anything
`Prelude` or `Layout` exports fails with a type error at the *record literal*, several lines
from the declaration. Two were hit while writing this group:

* `seq` — `Prelude` exports it, and `field seq : Int` makes every record mentioning it fail
  with `failed to unify type Field with type (->)`;
* `currency` — `Layout.Report.currency : String -> Double -> Report f z`, same symptom.

Neither is a bug, and the diagnostic is not wrong, but it points at the record rather than the
declaration and the cause is invisible in the message. Worth a line in a style guide:
**check a new field name against the standard library before using it.** The check is
`grep -rlE '^<name> *(:|=)' core/src/main/resources/modules/`.



### 7.8 The helper the brief named, and the one that shipped

`brief-E1.md` E1.1 asks for "a `lookupLatestBy` over a generic key". What shipped first was
`latestPerKey` (`groupBy ks (maxRowBy dF)`), and the reviewer is right that it is **not that
function**: it is a per-key argmax, not an as-of join. The two answer different questions —

* `asOfDates dF ds r` — *what did the history say on each of these dates?* One answer per date,
  looking back arbitrarily far.
* `latestPerKey ks dF r` — *what is the most recent row for each key?* One answer per key, no
  date argument at all.

`BranchDeposits.e` needed the first and got it by calling the stdlib `lookupLatest` directly,
which left the brief's helper unwritten and the report silent about the substitution.

**Fixed at review**: `Helpers.e` now carries `asOfDates` as well —

```
asOfDates : forall h t r. r <- (h, t)
         => Field h Date -> Relation h -> Relation r -> Relation r
asOfDates = lookupLatest
```

— which is `Relation.lookupLatest` with its signature written out (the same treatment
`pivotBy` gives `Relation.Pivot.pivot`), and `BranchDeposits.e` calls it at both of its two
calendars. Both doc comments now point at each other and say which question each answers, and
the module's header says it uses both on one table, three lines apart. `latestPerKey` is kept:
it is the cheaper helper, it is a real report step, and having the pair side by side is the
clearest way to make the distinction.

---

## 8. What a reviewer should re-run

Everything in this report is reproducible from the tree with five commands. The two long ones
are marked.

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH

# the group loads, per file and in one batch (§3a, §3b) -- LONG, ~25 min per file
tracker/tools/corpus-run.sh          /tmp/corpus-file
tracker/tools/corpus-run.sh --batch  /tmp/corpus-batch
python3 tracker/tools/corpus-verdicts.py /tmp/corpus-file /tmp/corpus-batch

# the model reproduces the compiler on every new solve (§4a) -- LONG, ~10 min of model time
export PATH=$HOME/.elan/bin:$PATH
LOOPTRACE_GROUPS="Wide Wide-shouldfail" tracker/tools/looptrace-corpus.sh /tmp/lt

# the census (§4b)
gunzip -c /tmp/lt/traces/Wide.tsv.gz > /tmp/Wide.tsv
tracker/lean/.lake/build/bin/looptrace --replay /tmp/Wide.tsv --depth > /tmp/Wide.depth

# the renderings (§6)
tracker/tools/sql-render.sh tracker/tools/wide-render-probe.e /tmp/wide-render
cat /tmp/wide-render/out/q_leader_rank.txt
```

Files this stage added or changed, in full:

| path | what |
|---|---|
| `core/examples/Wide/Helpers.e` | the library, 24 helpers |
| `core/examples/Wide/{Leaderboard,SalesLedger,TrialBalance,RevenueShare,SurveyPanel,WardRoster,BranchDeposits,MediaSpend,ClaimsExperience}.e` | nine reports |
| `core/examples/Wide/Signatures.e` | added at review: four machine-checked signature equivalences (§9) |
| `core/examples/Wide/README.md` | the group's own README, in `Ai/README.md`'s style |
| `core/examples/Wide/shouldfail/{pivot01,win01,win02}*.e` | three negative examples |
| `core/examples/Wide/shouldfail/RESULTS.md` | their diagnostics, verbatim |
| `core/examples/README.md` | +25 lines: a "grouped example sets" section (additive; the original text is untouched) |
| `tracker/tools/corpus-run.sh` | the `Wide` group wired in, both modes, `Helpers.e` hoisted like `Ai/Common.e` |
| `tracker/tools/looptrace-corpus.sh` | `Wide` and `Wide-shouldfail` in the default group list, `Helpers.e` first |
| `tracker/tools/sql-render.sh`, `tsql2sqlite.py`, `wide-render-probe.{e,in}` | new: the SQL rendering path of §6 (`SqlRun.java` was added and then deleted at review — the executor is `python3`'s stdlib `sqlite3` now) |
| `scalacheck-binding/src/main/scala/TestSurfaceParsers.scala` | +22/−1: the corpus size is derived, not hard-coded, **and floored at 250** (§3d) |
| `tracker/LOOP-MODEL-PLAN.md` | the `E1` row, added at review (N-6) |
| `tracker/loopmodel/E1-EXAMPLES.md` | this report |

No production code was touched. No commits were made. `tracker/lean/` is untouched.

**One wiring line left for the orchestrator.** `tracker/tools/corpus-run.sh`'s header says
"Directories covered, 79 files: … `core/examples/Wide/*.e` (10)". `Signatures.e` makes that 11
and 80, and the sibling groups will make it more again; the counts are prose in a comment, the
`files=(…)` globs pick the new file up on their own, and the review's §12 already lists that
header among the things the consolidation pass rewrites. It is left there rather than
half-updated here.

---

## 9. Post-review corrections — 2026-09-07

`tracker/loopmodel/E1-REVIEW.md` (1,059 lines) returned **FIX-THEN-ADVANCE**. The reviewer
re-ran the differential (170,619 new segments plus an 83,942-segment control), the whole census
(three columns, every cell), the `.ei` sweep (85 partitions across 19 of 24, per helper,
byte-identical across two JVMs), the batch and per-file loads, the three negatives, the fifteen
renderings and the RUnion experiment. **Nothing in §4 or the interface counts moved.** What
follows is every change made in response, old → new.

### 9.1 Code and module changes

| # | what | old | new |
|---|---|---|---|
| N-1 | `TestSurfaceParsers.scala:81` — the derived count is implied by the failure list and passes on an empty corpus | `(files ?= expected)` alone | `(expected >= 250)` **and** `(files ?= expected)`; the "stronger than the lower bound" sentence withdrawn from the comment and from §3d |
| N-7 | `sql-render.sh` — the name↔SQL mapping was positional | extractor counted `res` answers | the `.in` file is self-labelling (`"@@<name>"` before each name), the extractor pairs, and it **exits non-zero** if a name never answers |
| N-8 | `sql-render.sh` — the executor scraped a jar out of `target/ermine-classpath` | `SqlRun.java`, single-file source launch, `grep sqlite-jdbc` | ten lines of `python3`'s stdlib `sqlite3`, inline; **`SqlRun.java` deleted** |
| N-9 | `melt2` and `melt3` had no call site; `melt4`'s was six columns wide | — | `melt2` on `TrialBalance`'s **27-column** row (debit/credit → side/amount, plus the per-side totals it makes writable); `melt3` on `ClaimsExperience`'s **43-column** row (paid/reserved/recovered, plus the per-bucket totals); `SurveyPanel.scored` widened from 6 to 10 columns so four profile columns survive the melt and the module's promised "mean score by question and country" is actually written |
| N-10 | no `Signatures.e` | — | **`core/examples/Wide/Signatures.e`** — four proofs, two of them in both directions (§9.3) |
| §7.4 | `brief-E1.md`'s `lookupLatestBy` was silently replaced by `latestPerKey`, which is a per-key argmax and not an as-of join | — | `Helpers.asOfDates` added (the as-of join, `lookupLatest` with its signature written out) and called at both of `BranchDeposits`' calendars; both doc comments now say which question each answers; §7.8 records the substitution |
| N-3 | `TrialBalance.e:156` named a file that does not exist | `shouldfail/RunningTotalOrderedByMeasure.e` | `shouldfail/win02_running_total_ordered_by_measure.e` |
| N-3 | `MediaSpend.e` — wrong cell count | "six of the thirty cells have no row behind them" | **sixteen** (14 fact rows, 14 distinct campaign×month×channel triples, 30 cells) |
| N-3 | `ClaimsExperience.e` — false universal | "Every helper here is applied to a 43-column joined row" | "Every WINDOW and DERIVED-COLUMN helper", with a sentence saying the two pivot helpers see the three-column `groupBy` result, as they must |
| N-3 | `BranchDeposits.e` — a helper it does not call | "Helpers used: … groupBy (stdlib)" | `groupBy` removed, with a note that it is reached only through `latestPerKey`'s body |
| N-6 | no `E1` row in `tracker/LOOP-MODEL-PLAN.md` | — | added, before E2's |
| §5.3 | three binding names defined in two modules each, and the README tells you to load all ten | — | one section in `Wide/README.md`: `ledger`, `accountDim` and `productDim` are each defined twice, `:type ledger` in such a session answers `undefined term` rather than reporting an ambiguity |

### 9.2 Numbers corrected

| # | claim | old | new |
|---|---|---|---|
| N-4 | the RUnion table's provenance | "a reproduction of `Ai/README.md`'s figure … Form A reproduces the README's 1.04 s to two figures" | it is **not** a reproduction and cannot be: the README never names its module, so no baseline of its three rows is reproducible, and three E-stages have produced three reconstructions. What is measured here is a fresh controlled experiment answering the brief's question |
| N-4 | the cost of bundling | "3–4× the group's median" (from `WardRoster`/`ClaimsExperience` against the median) | **1.2×** from the controlled A/B/C (1.28 s vs 1.06 s), ~2× on a nine-column module. The whole-module comparison measures four things at once and is withdrawn from the report, `Wide/README.md` and `Helpers.e` |
| N-11 | the inferred `melt3` residual | "22 constraints over 19 existentials … an elevenfold reduction" | **20–22** over 19 — 20 in the reviewer's scratch module, 22 in mine, the difference being exactly two order-permuted duplicate pairs the published list does not canonicalise. Tenfold to elevenfold, and the sharper lesson is that the hand-written signature is *stable* where the inferred one is not |
| N-8 | depth-3 comparison | "eight solves at depth 3 against one — a 3.6× higher rate" | the counts, and nothing more: a rate from a denominator of one solve is not a rate |
| §15.10 | the batch's speed | "47× the per-file sweep" | the batch is **47× faster** than the per-file sweep (1,376 s → 29 s); the old phrasing reads as its opposite |
| §15.7 | the corpus size | "271 → 315" | 315 when this stage measured it, **333** on the settled tree |
| §15.4 | how fast the negatives are refused | "0.05 s (both sweeps)" | 0.05–0.06 s for `pivot01`/`win01`, **0.06–0.14 s** for `win02`, which is consistently 2–3× the other two |
| §9.1 | what `Wide/shouldfail`'s 910 census solves are | presented as the group's census | **837 are `Helpers.e`** being re-checked in that session; only **73** are the negatives themselves |
| — | two census rows | presented as two findings | "draws in the LOOP" and "either generative rule fired" are the **same predicate** — 185/185 in `Ai`, 165/165 in `Wide` — because `SplitConcrete` and `Resolution` are the only rules that mint |
| N-5 | the `MapView` fix | "one character-sequence, `.toMap` at `Lib.scala:988`" | **three `.toMap`s** — `:988`, `:1007`, `:1012` — because `scalaRecord#`'s own output is a `MapView` and `scalaRecordIn#` (live at `Layout/Report.e:1594,1608`) matches on `Map` the same way; **plus a test that FORCES a pivot** |
| N-5 | the `MapView` blast radius | four functions, `header#` "presumably" | eight, `header#` **confirmed by probe** (`Panic: … in Record.header#`), and `Relation.relation` explicitly **not** affected — which is why the fifteen renderings work at all |
| N-2 | the batch comparison | per-file vs batch only | plus old-script vs new-script: **nine** pre-existing `shouldfail/` modules change their refutation clause when `Wide/` joins the command line, and on `inf02` the reported **FIELD** moves (`Inf02.a` → `Inf02.b`) — stronger than §7.5's claim, which was about the sentence only |

### 9.3 The new module

`core/examples/Wide/Signatures.e` (12 bindings, 0.18–0.29 s) does for this group what
`core/examples/incomplete/Signatures.e` does for the row-constraint corpus: it writes residual
signatures by hand and lets the compiler prove them equivalent. `xDeduped = xFull` is the
proof — it assumes the deduped constraints and discharges the full ones — and where the
converse is also written the two sets are equivalent outright.

1. **`RUnion2 t r c` IS `r <- (ro, rs), c <- (so, rs), t <- (ro, so, rs)`**, in both directions
   (`withColumnExpanded = withColumnSugar` and `withColumnSugarViaExpanded = withColumnExpanded`).
   §2 asserts this equality in prose to explain why every helper is written with the sugar and
   published with the expansion; here it is checked.
2. **`rankWithin`'s five published constraints ≡ the four it was written with**, again both ways.
3. **`melt3`'s 22 inferred constraints ≡ 20 after deleting two order-permuted duplicates**
   (`r22 <- (ro2, rs2)` with `r22 <- (rs2, ro2)`, `r23 <- (rs1, ro1)` with `r23 <- (ro1, rs1)`),
   both ways — the machine-checked half of N-11 — **and ≡ 2 when a person says what the
   function means**, written out as a specialisation.
4. **`withDerived2`'s eight published constraints ⊨ four.**

It is also a call site for `rankWithin` and `withDerived2` at their exact published residuals.

### 9.4 Gates re-run after the corrections

Everything below is on the **final** tree (after all of §9.1), one JVM at a time,
`-Xmx2g -XX:ActiveProcessorCount=2`, `.ei` deleted before and after.

**G1a — per file, the whole group including `Signatures.e`.** All eleven LOADED, all three
negatives REJECTED at the recorded position and message:

```
Helpers.e 0.64   Signatures.e 0.29   SurveyPanel.e 0.37   BranchDeposits.e 0.66
TrialBalance.e 0.76 (+melt2)   RevenueShare.e 0.78   MediaSpend.e 0.92   Leaderboard.e 0.96
SalesLedger.e 1.79   WardRoster.e 1.82   ClaimsExperience.e 2.14 (+melt3)
pivot01 rejected 0.06   win01 rejected 0.06   win02 rejected 0.06
```

The three sweeps this report now carries (two before review, one after) bracket every module,
and the reviewer's independent sweep on a quieter box (0.30–2.65 s) lands inside them. Nothing
is near 30 s; nothing needs `.slow`. **The two melt call sites cost nothing measurable**:
`TrialBalance` 0.47–0.76 s across the three sweeps with `melt2` on its 27-column row against
0.47–0.49 s without, `ClaimsExperience` 2.14–2.83 s with `melt3` on its 43-column row against
2.60–2.83 s without.

**G1b — one batch, the whole corpus.** Eighty files now (the corpus grew by `Signatures.e`),
one JVM, **30 s**:

```
34 LOADED, 46 REJECTED, 0 UNKNOWN, 80 total
```

— eleven `Wide/*.e` LOADED, three `Wide/shouldfail/*.e` REJECTED, and the 43 pre-existing
`shouldfail/` and 3 pre-existing top-level rejections unchanged. One incidental datum for
§7.5: in **this** batch `win01` printed the per-file clause ("the whole contains it but no part
does") where the pre-`Signatures.e` batch printed the other one. Adding one unrelated module to
the command line flipped it back. That is the third independent demonstration in this report
that the clause is not a property of the program.

**G2 — the L2 differential, on the final tree:**

| group | files | segments | agree | skip | hashdiff | eqdiff | rejected | fuel |
|---|---|---|---|---|---|---|---|---|
| `Wide` | 11 | **115,864** | 115,864 | 0 | 0 | 0 | 0 | 0 |
| `Wide-shouldfail` | 4 | **55,777** | 55,777 | 0 | 0 | 0 | **1** | 0 |

**171,641 segments, every one replayed, not one disagreement**, and the model still reproduces
the compiler's own refutation on the one negative solve that reaches the loop. The group grew
by 1,020 solves (`Signatures.e`, the two melt call sites and the widened `scored`) and the
differential is unchanged in kind. `nonpart` 1,559 and 1,094.

**G3 — the census.** Re-run on the final trace, filtered to `core/examples/Wide/`:

| | §4b (pre-correction, reviewer-verified cell for cell) | final tree |
|---|---|---|
| solves in the group | 45,778 | **46,513** |
| verdicts | all SOLVED | all SOLVED |
| steps max | 249 | 202 |
| **nvars** max | 21 | 21 |
| **nparts** max | 14 | **15** |
| **nlbl** max | 46 | 46 |
| draws max | 77 | 57 |
| loop draws, >0 on | 165 (0.36 %) | 171 (0.37 %) |
| vocabulary-fixed | 99.64 % | **99.63 %** |
| chain depth max / histogram | 3 / 0:45613, 1:116, 2:41, 3:8 | 3 / 0:46342, 1:131, 2:34, **3:6** |
| `SplitConcrete` total / max | 396 / 14 | 386 / 13 |
| `Resolution` total / max | 811 / 62 | 701 / 43 |
| `maxdkey` / `remint` / `cremint` | 8 / 3 / 7 | 5 / 3 / 3 |
| budget headroom | 77 (0.385 %) | **57 (0.285 %)** |

`Wide/shouldfail` on the final tree: 912 solves (839 `Helpers.e`, 73 negatives), 911 SOLVED and
**1 REJECTED**, depth ≤ 1, max draws 6.

**What is stable and what is not, which is a finding in its own right.** Across the three
samples this stage now has of the same group — two before the review corrections and one after
— the SHAPE does not move: chain depth ceiling **3** every time, vocabulary-fixed **99.63–99.64 %**,
generative rules on **0.36–0.37 %**, `nvars` **21**, `nlbl` **46**, and budget headroom never
worse than **260×**. The MAXIMA do: steps 202 / 249 / 295, draws 57 / 77 / 100, `Resolution`
max 43 / 62 / 83, `maxdkey` 5 / 8. Adding `Signatures.e` and two `melt` call sites did not make
the group harder — it changed which solve happens to be the worst, and by how much, because the
id order changes and with it the queue order.

That is the same non-canonicality N-11 finds in the published residual, seen from the other
end, and it has a practical consequence for anyone reading a census: **the shape claims
("bigger, not deeper"; "two orders of magnitude of budget headroom"; "depth ceiling 3") are
robust; a single maximum quoted to two figures is not.** §4b's comparison against `Ai` rests on
ratios of maxima (21 vs 11, 46 vs 14, 15 vs 7) that are large enough to survive this — the
smallest of them is 2× and the drift here is ~25 % — but the reader should know the drift
exists. The one number that went UP is `nparts`, 14 → **15**, which is the `melt3` call site on
the 43-column row: the widest input system this corpus has produced.

**G4 — the three walker suites**, `sbt 'core/testOnly *TestSurfaceParsers *TestStatementExtents
*TestTolerantRead'`, which is where the N-1 change lives:

```
[info] Passed: Total 20, Failed 0, Errors 0, Passed 20
[success] Total time: 90 s (01:30)
```

**All twenty properties proved**, including `Surface parser 2.3a.headers agree with the fused
pipeline across the stdlib` — the one the hard-coded 271 was breaking — and
`Tolerant read.strict and tolerant agree, and the tolerant read is silent, over the corpus`,
which type-checks every `.e` under `core/examples` including all eleven new ones.

**And the new floor is LIVE, not decoration.** The whole point of N-1 is that the derived
equality asserts nothing on its own, so the floor had to be checked rather than assumed. Raising
it above the corpus size and re-running the one suite:

```
-  ((expected >= 250) :| s"only $expected corpus files found -- sweep broken?") &&
+  ((expected >= 9999) :| s"only $expected corpus files found -- sweep broken?") &&

[info] ! Surface parser 2.3a.headers agree with the fused pipeline across the stdlib: Falsified
[info] > Labels of failing property:
[info] only 338 corpus files found -- sweep broken?
```

— the conjunct fires, with its own message, on its own. Restored to 250, the suite is
`Passed: Total 5, Failed 0`. (The corpus is 338 `.e` files as I write this and was 333 an hour
ago; the sibling stages are still landing. That drift is exactly what the derived count is for
and exactly why the floor has to be a floor and not an equality.)

A note in passing, because it is the third instance of the same thing in this report: the
9999 run also showed a *second* failure, `CsvIntake.e:190: unparsed:binding fell back to
placeholder`, in a file belonging to a fifth example stage that appeared between two of my
runs. It had cleared by the restore run four minutes later. Measuring a shared gate while four
other stages are writing into the same tree gives transient failures that are not the measurer's
and not reproducible; both this and the `SalesDashboard.e` failure in §3d cleared on their own.
