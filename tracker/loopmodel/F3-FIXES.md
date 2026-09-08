# F3 — seven small confirmed defects from the corpus programme (A1b, B1, A4, A3, C2, C5, K-1)

Stage F3 of the loop-model programme (`tracker/loopmodel/briefs/brief-F3.md`).
Branch `scala3-migration`, base commit **`9ebe09b`** ("Handoff: F3 launched"; `topNormalise` is shipped ON).
Tickets: `tracker/TICKET-stdlib-findings.md` **A1b, A3, A4, B1, C2, C5** and
`tracker/ROSE-COMPARISON.md` §3 Rank 1's dated correction (S3 review **K-1**).

Toolchain: JDK 21.0.12.1, `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time.
No commits.  `tracker/lean/` untouched.  Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/F3/`.
The machine's default timezone is **America/Denver (MDT, UTC−6)**, which is what makes the A3
reproductions below discriminating without a flag.

**OUTCOME: GREEN** — all seven items fixed, each reproduced before it was touched and each left
with a `core/test` property or a measured gate.  Seventeen new properties (**939** total, 938
passing, the one documented failure); `TestLoopTrace` 720/720; the corpus 85 LOADED / **69** REJECTED / 0 UNKNOWN
(the +1 is B1's new `shouldfail` module, which is the only corpus change the brief authorises); the
model agrees on 17 of 17 traced groups, 1,300,365 segments, `skip = 0`; **13 of 268** published
interfaces move (on the repaired sweep) and every moved binding is named in §3.3, none of them
weaker; the SQL renderings
are byte-identical; both smokes pass; `perf-bench` is unmoved (11.07 s → 11.17 s, a third of the
run-to-run spread).

**Things moved that are not the fixes themselves; all of them are measured against a same-build
control and explained in §3.3 and §3.4.**  On the K-1-only build, **402 row-trace segments of
3,205,346, in all eighteen groups** — dominated by R3's `detm` record showing the residual getting
SHORTER (510 decreases, 0 increases), plus 96 constraint-order permutations and 59 `incomplete`
solves that draw one id fewer.  On the shipped build, thirteen refutation MESSAGES, which is ticket
B6 following the id base the stdlib edits move.  **§5 states the one judgement call** — whether an
ORDER change counts as "the disappearance of a concrete-identity constraint and nothing else" — so
a reviewer can disagree with it on the evidence rather than have to find it.

**FIX ROUND, 2026-09-08.**  The independent review (`tracker/loopmodel/F3-REVIEW.md`,
FIX-THEN-ADVANCE) confirmed all seven fixes, reproduced every gate at these numbers, and verified
the K-1 length test load-bearing in both directions.  Nine findings, all addressed in **§6**: the
row-trace instrument compared six of the sixteen record kinds, so "eight segments in two groups"
was an artefact (the real answer is 402 in all 18 groups, and the mechanism was refuted); the
K1FIRE split was wrong; the K-1 isolation never took an `.ei` snapshot; `ei-diff.sh` covered about
half the healthy corpus; the new module pinned the wrong position; three date properties only
discriminated off-UTC and one wrote `TimeZone.setDefault` in a parallel suite; seven counts were
off; the `dayCount` hole was parked in a closed ticket entry; and two `.ei` bindings were
mis-described.  Every number in §3.1, §3.2, §3.3 and §3.4 is now the corrected one, and
`core/test` is **939 / 938 passed** after the fix round.  The fix round also found and recorded a
NEW defect of A3's family that it did NOT fix: `Date.incrementDate` still adds in the JVM's default
zone (§5, ticket A3).

**Files changed** — the table is at the head of §2.

---

## 1. Reproductions, before the fix

Every one was taken on the base build, `-Dermine.useInterface=false`, one JVM at a time.

### A1b — the three `MapView` equality/hash sites

None of the three is reachable from an Ermine program, so the reproduction is at the Scala level.
It was made twice, independently.

**(a) The F1 review's probe** (`F1-REVIEW.md` J-3), compiled inside
`package com.clarifi.reporting.relational` against the project's own classpath:

```
== SqlScanner.scala:644 `prime` ==            (val kr = r filterKeys pKey ; if (kr == k) …)
  kr runtime class : scala.collection.MapView$FilterKeys
  kr == k       ==>  false          (kr.toMap == k  ==>  true)
  bootstrap = Map(c -> 999)         (999 is the DEFAULT; the real value 42 was dropped)

== SqlScanner.scala:708 `hashJoin` ==         (Tee.hashJoin(_ filterKeys jk, _ filterKeys jk))
  key runtime class            : scala.collection.MapView$FilterKeys
  Map[Record,_].getOrElse(key) : NO MATCH             (with .toMap: JOINED)

== relational/package.scala:67 `sorting` chunk predicate ==
  (t1 filterKeys chunk) == (t2 filterKeys chunk) : false     (with .toMap: true)
```

**(b) This stage's five `core/test` properties, run as a NEGATIVE CONTROL** on a build carrying
the visibility widening but NOT the three `.toMap`s — §3.2 has the numbers.

Why a view breaks both: 2.13's `MapView` is a `View`, and `View` defines neither `equals` nor
`hashCode`, so it inherits `Object`'s identity versions.  `==` between two views over equal maps
is false, and `Map[K, _]` keyed by a view never finds anything.  Where the migration passed a view
somewhere a `Map` was REQUIRED the compiler rejected it (`03-core-progress.md`: "only the ~20 sites
the compiler rejected"); `==` and hashing are the two places it cannot.

### B1 — `Relation.Op.dateDiff` over a relation carrying neither date

`/home/dmitry/.claude/jobs/880c725d/tmp/F3/probe/DateDiffProbe.e`:

```
field startDate, endDate : Date
field gap : Int
field name : String

people : [ name ]
people = relation [ { name = "Ada" } ]

bad : [ name, gap ]
bad = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap people
```

The module **LOADS** — `Importing module 'DateDiffProbe' (0.05 seconds)` — and `:type bad` answers
`Relation (|name, gap|)`.  The mistake surfaces only when the value is forced:

```
>> res0 : Relation (|name, gap|) =
  <relation with Failure(NonEmpty[Operation refers to nonexistent column (startDate) in header.,
                                  Operation refers to nonexistent column (endDate) in header.])>
```

### A4 / A3 — `Date`, under the machine's zone and under UTC

`probe/DateProbe.e` evaluates the twelve month-firsts of 2011.  Both columns are the SAME binary,
the same probe, one JVM each; the right-hand column adds `-Duser.timezone=UTC`.

| binding | default (MDT) | `-Duser.timezone=UTC` |
|---|---|---|
| `formatQuarter` ×12 | `Q4 Q2 Q2 Q2 Q2 Q3 Q3 Q3 Q3 Q4 Q4 Q4` | `Q2 Q2 Q2 Q2 Q3 Q3 Q3 Q3 Q4 Q4 Q4 Q4` |
| `quarter` ×12 | `3 1 1 1 1 2 2 2 2 3 3 3` | `1 1 1 1 2 2 2 2 3 3 3 3` |
| `getMonth` ×12 | `11 0 1 2 3 4 5 6 7 8 9 10` | `0 1 2 3 4 5 6 7 8 9 10 11` |
| `getDate` ×12 | `31 31 28 31 30 31 30 31 31 30 31 30` | `1 1 1 1 1 1 1 1 1 1 1 1` |
| `getYear` ×12 | `110 111 111 …` | `111 111 111 …` |
| `unsafeFormatDate` ×12 | `1/1/11 2/1/11 …` | `1/1/11 2/1/11 …` (identical) |
| `formatMonthYear` ×12 | `Jan 2011 Feb 2011 …` | identical |
| `formatExcelDate @2011/1/1` | `"Dec 31"` | `"Jan 1"` |
| `formatPeriodOr "custom" (1 Jan, 31 Jan)` | `"Jan 2011"` | `"custom"` |
| `formatPeriodOr "custom" (1 Jan, 1 Apr)` | `"custom"` | `"Q2 2011"` |
| `formatExcelPeriod (1 Jan, 31 Jan)` | `"Dec 31 to Jan 30"` | `"Jan 1 to Jan 31"` |

That is E3 §8's table, reproduced line for line.  **A4** is the right-hand column on its own:
`"Q1"` never appears and January prints `"Q2"`, because the divisor is 4 and a 1-based number
indexes a 0-based list.  **A3** is the difference between the columns: the formatters are pinned to
`YMDTriple.ymdPivotTimeZone` (GMT) by `PrimExprs.dateFormatterTLV` and do not move, the accessors
are `java.util.Date`'s deprecated methods and do.

### C5 — `sumBy'`'s vacuous constraint, in the published interface

From the pre-fix `.ei` snapshot (225 interfaces).  `Relation.Scan`:

```
sumBy' : forall (op: rho -> * -> *) (r: rho) n (r2: rho) z k.
         (Builtin.PrimitiveNum n, AsOp op, r <- (h, t)) => …
```

`h` and `t` appear in the constraint and **in no binder** — which is ticket B3 as well as C5 —
and the partition they are in is the C12 tautology: every row splits, take `t := r`, `h := ∅`.
The `Layout.Scan` re-export publishes the same thing with the existentials restored:

```
sumBy' : forall (op: rho -> * -> *) (r: rho) n (r2: rho) z k.
         (exists (AsOp: (rho -> * -> *) -> a) (t: rho) (h: rho).
            AsOp op, r <- (h, t), Builtin.PrimitiveNum n) => …
```

### B1 — the same, for `dateDiff`'s free result row

```
dateDiff : forall (a: rho -> * -> *) (b: rho) c (d: rho -> * -> *) (e: rho) (r2: rho).
           (AsOp d, PrimitiveTemporal c, AsOp a)
           => TimeUnit -> a b c -> d e c -> Op r2 Int
```

`r2` is universally quantified and constrained by nothing: the caller chooses the result row
freely, which is exactly why the `combine` above type-checks.

### C5 — the three names `Layout.Scan` does not re-export

`probe/ScanProbe.e`, a module whose whole body is `removeK_LS`, `removeBy_LS`, `multiply_LS`:

```
ScanProbe.e:5:15: error: undefined term
ScanProbe.e:6:15: error: undefined term
ScanProbe.e:7:15: error: undefined term
```

### K-1 — the concrete identity reaching the solver

`probe/K1Probe.e` declares two signatures whose only constraint is a concrete identity, plus the
call sites that make the module's own check discharge them:

```
identity1 : ((|foo, bar|) <- (|foo, bar|)) => Relation (|foo, bar|) -> Relation (|foo, bar|)
split1    : ((|foo, bar|) <- ((|foo|), (|bar|))) => Relation (|foo, bar|) -> Relation (|foo, bar|)
useIdentity r = identity1 r
useSplit    r = split1 r
```

Under `-Dermine.rowTrace` the two call sites each open a solve carrying exactly one constraint,
and it is the identity:

```
sin    trySolveOn  …/K1Probe.e(23:17)  303113 304127 1 …          <- nCs = 1
scon   trySolveOn  …                   0 0 1845105483 part c0,1|c0,1
in     trySolveOn  …/K1Probe.e(23:17)  0  (|K1Probe.bar,K1Probe.foo|)  (|K1Probe.bar,K1Probe.foo|)
inpart trySolveOn  …/K1Probe.e(23:17)  0  INPUT  ^303113    K1Probe.bar,K1Probe.foo
sat    trySolveOn  …/K1Probe.e(23:17)  0  INPUT  ^303113    K1Probe.bar,K1Probe.foo
```

`split1` produces the same shape (`…(26:14)`), because `Part.apply`'s last-but-one case merges the
two disjoint concrete parts into one concrete rho before the identity guard would have seen them.

### The same seven probes, AFTER

| probe | after |
|---|---|
| A1b | the five `core/test` properties pass; on the pre-fix spelling four are falsified with the exact wrong answers (§3.2) |
| B1 | `DateDiffProbe.e:17:7: Row partitions are unsatisfiable at field 'DateDiffProbe.startDate': the whole contains it but no part does` — **rejected at load**, no longer a value that fails when forced |
| A4 | `formatQuarter` ×12 = `Q1 Q1 Q1 Q2 Q2 Q2 Q3 Q3 Q3 Q4 Q4 Q4`, `quarter` ×12 = `1 1 1 2 2 2 3 3 3 4 4 4` |
| A3 | `getMonth` ×12 = `0 1 2 3 4 5 6 7 8 9 10 11`, `getDate` ×12 = all `1`, `getYear` ×12 = all `111`, `formatExcelDate @2011/1/1` = `"Jan 1"`, `formatPeriodOr "custom" (1 Jan, 1 Apr)` = `"Q2 2011"`, `formatExcelPeriod (1 Jan, 31 Jan)` = `"Jan 1 to Jan 31"` — and the WHOLE probe is byte-identical under the default zone, `-Duser.timezone=UTC`, `Pacific/Kiritimati` (UTC+14), `Asia/Tokyo` and `Pacific/Niue` (UTC−11).  **Five zones, one answer** |
| C5 (re-exports) | `Importing module 'ScanProbe' (0.15 seconds)` — the module whose whole body is `removeK_LS`, `removeBy_LS`, `multiply_LS` loads |
| C5 (`sumBy'`) | the published constraint list is `(PrimitiveNum n, AsOp op)`; the free `h` and `t` are gone (§3.3) |
| K-1 | every `K1Probe` solve now has `nCs = 0` and the trace holds **zero** `in`/`inpart`/`sat` records for that module; both signatures still print the same types, so the constraint was discharged by being recognised, not by being weakened |

---

## 2. The fixes

| file | change |
|---|---|
| `core/src/main/scala/…/relational/SqlScanner.scala` | +16 −4 — two `.toMap`s (the pivot's bootstrap key, the hash join's two key functions) and `private` → `private[relational]` on `pivot` and `hashJoin` so a test can drive them (**A1b**) |
| `core/src/main/scala/…/relational/package.scala` | +6 −1 — `.toMap` on both sides of `sorting`'s chunk predicate (**A1b**) |
| `core/src/main/scala/…/ermine/Type.scala` | +9 −1 — `Part.apply`'s dead `ss == cs` guard becomes `ss.toSet == cs && ss.length == cs.size` (**K-1**) |
| `core/src/main/scala/…/PrimExpr.scala` | +29 — `PrimExprs.getYear`/`getMonth`/`getDate`, reading the same UTC calendar the formatters use (**A3**) |
| `core/src/main/resources/modules/Date.e` | +50 −5 — the three accessors bound to those, the module header states the one timezone, `quarter` divides by 3 and `formatQuarter` indexes 0-based (**A3, A4**) |
| `core/src/main/resources/modules/Relation/Op.e` | +12 −1 — `dateDiff`'s signature (**B1**) |
| `core/src/main/resources/modules/Relation.e` | +15 −3 — `join1`'s and `rename'`'s doc comments (**C2, C5**) |
| `core/src/main/resources/modules/Relation/Scan.e` | +7 −1 — `sumBy'` loses its vacuous `r <- (h,t)` (**C5**) |
| `core/src/main/resources/modules/Layout/Scan.e` | +8 — `removeK`, `removeBy`, `multiply` re-exported (**C5**) |
| `scalacheck-binding/src/main/scala/TestInMemoryScan.scala` | NEW, 124 lines — five `core/test` properties driving the pivot, the hash join and the sort (**A1b**) |
| `scalacheck-binding/src/main/scala/TestDateAndScan.scala` | NEW, 213 lines — twelve `core/test` properties for **A3, A4, B1, C5** |
| `core/examples/Time/shouldfail/date01_datediff_free_row.e` | NEW, 50 lines — the B1 program, now rejected statically |
| `core/examples/Time/Helpers.e` | comment only — the E3 finding it records is fixed in the stdlib, and its own `dayCount` deliberately keeps the hole |
| `core/examples/Time/FiscalTree.e` | comment only — the A3/A4 defect section becomes the record of the fix, with the after column added to its table |
| `tracker/tools/corpus-run.sh` | comment only — the file-count note was three groups stale |
| `tracker/tools/ei-diff.sh` | +49 −11 — hoists all six group libraries, and gained a `--snapshot` mode for a two-BUILD comparison (fix round, review N-4) |
| `tracker/tools/trace-ab.py` | NEW, 132 lines — the row-trace differ, comparing every record kind (fix round, review N-1) |
| `tracker/ROSE-COMPARISON.md` | the dated K-1 FIXED note inside Rank 1's correction |
| `tracker/TICKET-stdlib-findings.md` | A1b, A3, A4, B1, C2, C5 marked fixed (hash left as `<commit>`) |
| `tracker/ROW-CONSTRAINT-STATE.md` | a dated ADDITIVE note: K-1 moved something solver-visible, so the brief requires one |
| `tracker/LOOP-MODEL-PLAN.md` | the F3 row |

**There is no B1 fallout in `core/examples`.**  `Time/Helpers.e`'s **eight** date helpers —
`dayCount`, `yearFrac365`, `monthsBetween`, `monthsSince`, `daysSince`, `daysUntil`, `yearsOn`,
`yearFrac360` (lines 288, 293, 303, 309, 313, 319, 324, 330) — declare `forall … out.` and that is
still accepted for their bodies, so nothing broke; tightening them to `RUnion2 out r r1 => …` was
tried and loads the whole `Time/` group cleanly, and was then REVERTED because it is an
example-level improvement the brief did not ask for and it would have moved eight more published
signatures.  The consequence is stated plainly in §5 and now has a ticket entry of its own
(`TICKET-stdlib-findings.md` **B1a**, review N-8): a caller who reaches `dateDiff` through
`Time.Helpers.dayCount` still gets the deferred failure, and `Time/Signatures.e`'s three
`yearFrac365*` mirror it.  ("Seven" here was a miscount; review N-7.)

### 2.1 A1b — `SqlScanner.scala` and `relational/package.scala`

```scala
-      val kr = r filterKeys pKey                             // pivot's `prime`
+      val kr = (r filterKeys pKey).toMap

-    q1.tee(q2)(Tee.hashJoin(_ filterKeys jk, _ filterKeys jk))
+    q1.tee(q2)(Tee.hashJoin((r: Record) => (r filterKeys jk).toMap,
+                            (r: Record) => (r filterKeys jk).toMap))

-        (t1: Record, t2: Record) => (t1 filterKeys chunkCols) == (t2 filterKeys chunkCols))
+        (t1: Record, t2: Record) => (t1 filterKeys chunkCols).toMap == (t2 filterKeys chunkCols).toMap)
```

### 2.2 K-1 — `Type.scala`

```scala
-      case ConcreteRho(lclhs, cs) if ts.isEmpty && ss == cs => Exists(l)
+      case ConcreteRho(lclhs, cs) if ts.isEmpty && ss.toSet == cs && ss.length == cs.size =>
+        Exists(l)
```

`ss` is the concatenation of EVERY concrete part's labels, so `ss.toSet == cs` alone is not the
identity: with `(|Foo,Bar|) <- ((|Foo,Bar|), (|Foo|))` the sets are equal and the constraint is
**unsatisfiable**, because two parts share `Foo`.  The length test is what rules that out, and it is
the same test the case two lines below already makes (`ss.toSet.size == ss.length`) before merging
the parts.  With it the guard is exactly "the concrete parts are pairwise disjoint and their union
is the concrete whole", which is the definition of a partition of a concrete row and is therefore
trivially true.  Everything it does not catch still reaches the solver, which refutes it.

### 2.3 A3 — one timezone

`java.util.Date.getYear`/`getMonth`/`getDate` are deprecated and read the JVM's default zone.
`PrimExprs` gains three functions that read a `GregorianCalendar` in `YMDTriple.ymdPivotTimeZone`
— the zone `PrimExprs.dateFormatterTLV` already pins every formatter to — and `Date.e` binds the
three names to those instead.  **The conventions are unchanged**: `getYear` is the year minus 1900
(`core/examples/Yahoo.e` writes `getYear d + 1900`), `getMonth` is 0-based (which is what
`Date.shortMonthNames` is indexed by), `getDate` is the 1-based day.  `getTime` is epoch
milliseconds and has no zone, so it is untouched.

### 2.4 A4 — the quarters

```
-quarter d = getMonth d / 4 + 1
-formatQuarter d = orElse_M "Unknown" (at_L (quarter d) quarterNames)
+quarter d = getMonth d / 3 + 1
+formatQuarter d = orElse_M "Unknown" (at_L (quarter d - 1) quarterNames)
```

`quarter` keeps its 1-based meaning, which is the one its name and `quarterNames` have; the index
is where the off-by-one is fixed.

### 2.5 B1 — `dateDiff`'s signature

```
-  --dateDiff : forall r r1 r2 .  AsOp op1 op2 => TimeUnit -> op1 r Date -> op2 r1 Date -> Op r2 Long
+  dateDiff : (AsOp op1, AsOp op2, RUnion2 t r1 r2, PrimitiveTemporal d)
+          => TimeUnit -> op1 r1 d -> op2 r2 d -> Op t Int
```

That is `dateAdd'`'s signature, one line above, and it is the one line the ticket asks for.  The
commented-out line it replaces would not have fixed anything: `r2` is free there too (and
`AsOp op1 op2` is not a constraint the parser accepts).

### 2.6 C2 / C5 — the four documentation and re-export items

`join1`'s comment now says what its constraints say (it is `joinBy {f}`; `r <- (k, r1, r2)` is a
partition, so `r1` and `r2` are disjoint and the intersection of the operands is exactly `k`).
`rename'` keeps its name and gains the line the ticket asks for: it requires the DESTINATION
column to be there already.  `Layout.Scan` gains `removeK`, `removeBy` and `multiply`.
`Relation.Scan.sumBy'` loses `r <- (h,t)`, in which `h` and `t` occur nowhere else — the C12
tautology, deleted here in the one signature the ticket names and left in the other four, which
are C12's job in `Subst.mkSimplified`.


## 3. Gates

### 3.0 The corpus baseline this stage measures against

Taken on the base build (`9ebe09b`), `-Dermine.useInterface=false -Dermine.loadInSeries=true`,
`-Xmx2g -XX:ActiveProcessorCount=2`, one JVM at a time, `.ei` deleted before every side:

* `corpus-run.sh --batch`: **85 LOADED, 68 REJECTED, 0 UNKNOWN, 153 total**.
* `sql-render.sh` over `tracker/tools/wide-render-probe.e`: **30 names asked, 30 answered, 15
  produced SQL**, 15 result tables; the nine `q_*` that do not are the pre-existing
  "Don't know how to dump a mem" wall (`Scanner.scala:35`), which F1 already recorded.
* `looptrace-corpus.sh`, all 18 groups: **3,205,346 segments**
  (boot 54,199 · top 92,673 · Ai 83,942 · Wide 115,864 · Wide-shouldfail 55,777 ·
  Present 131,358 · Present-shouldfail 59,493 · Time 125,100 · Time-shouldfail 55,873 ·
  Algebra 101,005 · Algebra-shouldfail 55,367 · Lang 91,300 · Lang-shouldfail 58,779 ·
  shouldfail 56,030 · bugs 54,235 · guide 54,244 · shouldfail-controls 54,739 ·
  incomplete 1,905,368), 0 timeouts, 0 dropped.  The first five groups were also replayed
  through the Lean model before the run was restarted trace-only, and all five agreed
  (`boot 54,199/54,199`, `top 92,673/92,673`, `Ai 83,942/83,942`, `Wide 115,864/115,864`,
  `Wide-shouldfail 55,777/55,777`, `skip = 0` on each).

**K-1's scope, measured on that baseline before touching anything.**  A concrete-identity input
constraint is an `in` record whose left-hand side is a concrete row and whose single right-hand
part is the SAME concrete row — the one shape `Part.apply`'s dead guard was meant to collapse.
Across all eighteen groups and all 3,205,346 segments there are **ZERO**.  So the K-1 fix cannot
move this corpus's trace, and the isolation run below is the measurement that says so rather than
an argument that it should.

### 3.1 K-1 in ISOLATION — a compiler carrying only the Scala changes

The other six items are stdlib `.e` edits, and three of them (a signature, three re-exports, a
deleted constraint) move the boot trace by construction — which would bury K-1's effect in
someone else's.  So K-1 was measured on a build with **the stdlib `.e` files at their committed
bytes and `core/examples` untouched**: only `Type.scala`, `PrimExpr.scala`, `SqlScanner.scala`
and `relational/package.scala` differ from the base, and of those only `Type.scala` is on an
inference path at all (`PrimExpr` is date arithmetic; the other two are runtime primitives).

| gate | pre-fix | K-1 only | verdict |
|---|---|---|---|
| `corpus-run.sh --batch` verdicts | 85 LOADED / 68 REJECTED / 0 UNKNOWN | **identical** | PASS |
| the 153 per-file outputs, byte for byte | — | **0 of 153 differ** with the progress-bar frames and the elapsed-time strings masked (they are wall clocks and differ between any two runs) | PASS |
| the 18-group row trace, 3,205,346 segments, **every record kind** | — | **402 segments differ, in all 18 groups**: 305 CONTENT-DIFFERS, 96 PERMUTATION-ONLY, 1 KINDCOUNT-DIFFERS.  The dominant class is R3's `detm` record, whose residual partition count **decreases 510 times and increases 0 times** — the fix working.  Noise floor: the same-build control pair is IDENTICAL.  §3.4 has the whole picture | see §3.4 |
| the `sin` supply bounds, per segment, all 18 groups | — | **17 groups: 0 differences.  `incomplete`: 59**, each `suLo` one LOWER after the fix.  (The first version of this table measured `Algebra` only and generalised; corrected in the fix round, review N-1) | see §3.4 |
| the K-1-only build's published interfaces | unmeasured before the fix round | _(pending: review N-3)_ | |

**How the two traces are compared.**  `tracker/tools/trace-ab.py` splits both traces at their `sin`
records, pairs the segments by index (a solve with no constraints still emits its `sin`, so the
count must not move) and compares **every record and every field**, masking only `rsound ok`'s
wall-clock microseconds.  A differing pair is `PERMUTATION-ONLY` (same record multiset once numeric
ids are erased, and the same count of each kind), `CONTENT-DIFFERS` or `KINDCOUNT-DIFFERS`; `sin`
bounds are reported separately as `sinmoved`.  The version used in the first round compared six of
the sixteen record kinds and is the subject of review finding N-1; the repaired tool is now in
`tracker/tools/` rather than in scratch, so the next stage inherits the wide instrument.

### 3.2 The shipped build — every other gate

| gate | expected | measured | verdict |
|---|---|---|---|
| `core/test` | the documented `Constraints.disjunction` failure and nothing else, plus the new properties | **Total 937, Failed 1, Errors 0, Passed 936** in 20:01.  The one failure is `! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.` — the documented generator starvation.  **922 before this stage + 15 new** = 937; 922 is the total R3's plan row records, which is the check this line is for.  (It first read "925 + 12"; review N-7.)  **Superseded by the fix round: 939 / 938 passed**, because `TestDateAndScan` grew from 10 properties to 12 when N-6 was fixed — §6.3 | PASS |
| `TestLoopTrace` | 720/720 | `[loop model trace] 720 solves (20 seed x 6 bases + 600 generated); 720 segments; 720 agree; #summary segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0`; the two controls still disagree (46 of 720 at id base +1, 58 of 720 with `--flags=nongen`) | PASS |
| the twelve new properties, PRE-fix (negative control) | the four that discriminate must fail | **4 of 5 A1b properties falsified**, with exactly the predicted wrong answers (below); the fifth is a both-sides control | PASS |
| `corpus-run.sh --batch` | 85 / 68 / 0, plus the new `shouldfail` module | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** — exactly the change B1 predicts: one more REJECTED, `Time/shouldfail/date01_datediff_free_row.e`, and no other verdict moves.  Thirteen REJECTED modules print a different CLAUSE of the same refutation (§3.3(b)) | PASS |
| the 17-group model differential | agree = segments, skip = 0 | **17 of 17: `agree = segments`, `skip = 0` on every group**, 1,300,365 segments in all.  (The 18th group, `incomplete`, is 1.9 M segments of deliberately diverging solves and its model replay is hours; it was traced by the compiler for the delta below and its model replay is the one gate this stage did not take — §5) | PASS |
| the per-group segment DELTA, pre → post, all 18 | small, positive, attributable | **+10** in every group that loads only the core stdlib, **+34** in every group that also loads `Layout.Scan`, **+59** in `Time-shouldfail` (that is +34 plus the 25 segments of the new `date01` module), and **+350** in `incomplete`, which runs PER FILE and so pays the +10 thirty-five times.  3,205,346 → 3,206,083, **+737** over all eighteen groups, and not one group moved for any other reason | PASS |
| the `.ei` sweep (`ei-sweep.sh --batch`-equivalent, `-Dermine.loadInSeries=true` on both sides, `.ei` deleted before each) | only the named bindings move, nothing weaker | **11 of 224 interfaces differ; 2,450 bindings identical, 48 order-only, 6 alpha-equivalent, 6 `other`, 3 only-in-B.**  Every one of the **nine** bindings the classifier would not certify (6 `other` + 3 `only-in-B`) is named below; the 48 order-only and 6 alpha-equivalent are the id-shift churn.  **Superseded in the fix round** — that sweep covered 224 interfaces because the tool hoisted only one of the six group libraries; §6 has the full-corpus re-run | PASS |
| the `.ei` CONTROL — two sweeps of the SAME build | identical | **0 of 224 interfaces differ, 2,513 bindings identical**, no only-in either way.  So the eleven above are the change, not the churn `ROW-CONSTRAINT-STATE.md` warns `.ei` is capable of | PASS |
| `sql-render.sh` | unchanged | **30 names asked, 30 answered, 15 produced SQL**, 15 result tables; `diff -rq` over both `sql/` and `out/` is **EMPTY** — all 30 generated `.sql` files and all 15 result tables are BYTE-IDENTICAL to the pre-fix run; the nine `q_*` that do not are the same pre-existing `Don't know how to dump a mem` wall | PASS |
| `repl-smoke.sh` | pass | **5 of 5 PASS, 47 checks** — aliasing 2, pipedeof 12, relations 6, scoping 4, smoke 23 | PASS |
| `lsp-smoke.sh` | pass | **PASS lsp (98 checks)** | PASS |
| `perf-bench batch -n 3` | unmoved | **base 11.07 s cold median** (11.05 / 11.30, spread 0.25) against **F3 11.17 s** (11.01 / 11.33, spread 0.32) — **+0.10 s, 0.9%, a third of the spread**.  Both sides taken in one session on the same quiet machine (`load 1.05` / `0.87`, the harness's own check), each compiled first because `perf-bench.sh` refuses to run against a stale build | PASS |
| the `.ei` hygiene sweep | none left | `find core/examples core/src/main/resources/modules -name '*.ei'` prints nothing | PASS |

**Why the SHIPPED build's trace is compared by segment COUNT and not segment for segment.**  Three
of the six stdlib edits change what the compiler infers — `dateDiff` gains a signature, `sumBy'`
loses a constraint, `Layout.Scan` gains three bindings — so the boot itself grows and every group's
segment indices shift.  Pairing by index would then be meaningless.  The K-1 isolation in §3.1 is
where "nothing else moved" is measured, on a build whose stdlib is byte-identical to the base; here
the gate is the MODEL agreement (`agree = segments`, `skip = 0` on the shipped compiler) plus the
per-group segment deltas, which must be small, positive and attributable to the stdlib edits.

**The A1b negative control, in full.**  With the three `.toMap`s reverted (and only them — the
`private[relational]` widening kept, which cannot change behaviour):

```
! the in-memory pivot keeps the FIRST row of each group: Falsified after 0 passed tests.
  Expected List("Map(id -> a, xs -> 1, ys -> 2)", "Map(id -> b, xs -> 3, ys -> 4)")
       but got List("Map(id -> a, xs -> -1, ys -> 2)", "Map(id -> b, xs -> -1, ys -> 4)")
! a pivot column with no matching row still gets its default: Falsified after 0 passed tests.
  Expected List("Map(id -> c, xs -> 7, ys -> -1)") but got List("Map(id -> c, xs -> -1, ys -> -1)")
! sorting groups by the columns already in order: Falsified after 0 passed tests.
  Expected List("(1,1)", "(1,2)", "(1,3)", "(2,5)", "(2,9)")
       but got List("(1,3)", "(1,1)", "(1,2)", "(2,9)", "(2,5)")
! the in-memory hash join matches on the key columns: Falsified after 0 passed tests.
  Expected Set(Map(k -> a, l -> 1, r -> 10), Map(k -> b, l -> 2, r -> 20)) but got Set()
+ sorting leaves a stream that is already in the wanted order alone: OK, proved property.
Failed: Total 5, Failed 4, Errors 0, Passed 1
```

`-1` is the pivot's default: the row that OPENS each group contributed nothing, which is the
defect stated as an output.  The fifth property passes on both builds by construction — a stream
already in the wanted order comes out unchanged whether or not the chunks group — and is there as
a regression guard, not a discriminator.

### 3.3 The nine `.ei` bindings that moved, one by one

> Taken on the sweep as it then was, 224 interfaces.  **§6.2 re-runs this over the whole corpus**
> (268 interfaces, after review N-4 repaired the tool) and finds the SAME nine bindings, so the
> table below stands; only its denominator was too small.

| binding | interface | verdict | what it is |
|---|---|---|---|
| `sumBy'` | `Relation.Scan` | `other`, constraints **3 → 2** | the vacuous `r <- (h, t)` deleted.  `h` and `t` were printed as FREE variables the interface did not bind (ticket B3 as well as C5); they are gone with it |
| `sumBy'` | `Layout.Scan` | `other`, constraints **3 → 2** | the same, through the re-export: `(exists AsOp t h. AsOp op, r <- (h,t), PrimitiveNum n)` becomes `(exists AsOp. AsOp op, PrimitiveNum n)` |
| `dateDiff` | `Relation.Op` | `other`, constraints **3 → 6** | B1.  `(AsOp d, PrimitiveTemporal c, AsOp a) => … Op r2 Int` with `r2` free becomes `(exists ro so rs. …, r2 <- (so,rs), r1 <- (ro,rs), t <- (ro,so,rs)) => … Op t Int`.  **Stronger**, which is the point |
| `removeK`, `removeBy`, `multiply` | `Layout.Scan` | `only-in-B` ×3 | C5's three re-exports.  Additions, so nothing that existed moved |
| `valueAsOf` | `incomplete/RunCalibration` | `other`, constraints **8 → 9** | side B's set is side A's **plus** `t <- (g, c1, r)`; same four binders, same **11** existentials.  A superset is a STRONGER published type, never a weaker one, and this is the one binding whose residual `TICKET-stdlib-findings.md` B6 and E3 already record as a function of the id base rather than of the program (12 vs 13 constraints on the identical body) — which the stdlib edits shift |
| `shareOfGroup` | `incomplete/RevenueShare` | `other`, **14 partitions both sides**, **17** existentials both | **not a renaming** (review N-9): the partition-ARITY histogram moves, `{2:9, 3:5}` → `{2:9, 3:4, 4:1}`.  Side A publishes `g <- (o, b, f)` where side B publishes `i <- (o, f, e, d1)` — the same partition with `b` SUBSTITUTED into its own parts, and both sides also publish `b <- (e, d1)`.  Inter-derivable, so **nothing is weaker**; an equivalent residual published in a more expanded form.  `ei-classify.py` refuses to certify it and prints it in full, which is the right behaviour |
| `cutoffGroupedFldsPosNegRel'` | `Layout.Report.Relation` | `other`, **26 partitions both sides**, **40** existentials both (34 of them row existentials — the `nEx`/`nRowEx` R3's own `ramb` record carries) | the same shape of change at R3's scale: `{1:1, 2:14, 3:6, 4:3, 5:1, 6:1}` → `{1:1, 2:14, 3:5, 4:3, 5:2, 6:1}`, one 3-part partition becoming a 5-part one.  **The equivalence here is argued, not checked**: neither `ei-classify.py` nor the reviewer proved it for 26 partitions over 40 existentials.  What IS measured is that nothing is `concrete->polymorphic` and the count does not fall |

The 48 `order-only` and 6 `alpha-equivalent` bindings are the id-shift churn any change to the
stdlib produces, and are what the classifier exists to absorb.  **Nothing is `concrete->polymorphic`
— the classifier's name for a weaker published type — anywhere in the sweep.**  (Nine bindings, not
"twelve" as this section first said: 6 `other` + 3 `only-in-B`.  Review N-7.)

**One interface is missing from side B and it is not a regression.**  `core_examples_Wide_Leaderboard.ei`
is captured on side A and not on side B, because the sweep loads the corpus in chunks of FIVE and
side B has one more file in it (`date01`), so every chunk boundary after `Time/shouldfail/` shifts by
one and `Wide/Leaderboard.e` landed in a chunk that did not carry `Wide/Helpers.e`
(`Module not found: 'Wide.Helpers'` in `ei-post.chunk37.log`).  Loaded with its library it is fine:
`Importing module 'Wide.Helpers' … Importing module 'Wide.Leaderboard' (0.59 seconds)`.  The sweep
script hoists `Ai/Common.e` for `Ai/` chunks and has never hoisted the five later group libraries;
that is a gap in the tool, recorded here rather than fixed under a stage that is not about it.

### 3.4 What moved in the row trace, in full

> **REWRITTEN IN THE FIX ROUND (review N-1).**  What this section said first — "eight segments in
> two groups, the other sixteen identical segment for segment" — was an artefact of the instrument,
> not a measurement of the change.  The first `trace-ab.py` inherited `looptrace-diff.py`'s `KEEP`
> tuple and compared **six of the sixteen** record kinds a corpus trace carries; it never looked at
> `slbl`, `svar`, `scon`, `ex`, `concr`, `splice`, `detm`, `ramb` or `rsound`, and of `sin` it read
> only the constraint count, never the `Supply` bounds.  Both of R3's records — the ones added so
> that residual and ambiguity changes would be VISIBLE — were outside its field of view, and so was
> the `incomplete` group, which was never compared at all.  The tool is now
> `tracker/tools/trace-ab.py` and compares every record and every field, masking only `rsound ok`'s
> wall-clock microseconds.  The numbers below are that tool's.

**(a) 402 segments of 3,205,346, in ALL EIGHTEEN groups.**  Noise floor first: the same-build
control pair (`lt-ctl1` vs `lt-ctl2`) is **101,005 / 101,005 `Algebra` and 131,358 / 131,358
`Present` IDENTICAL** under the full comparison, so every difference below is the build.

| group | diff | `sin` moved | group | diff | `sin` moved |
|---|---|---|---|---|---|
| boot | 1 | 0 | Algebra | 60 | 0 |
| top | 4 | 0 | Algebra-shouldfail | 1 | 0 |
| Ai | 30 | 0 | Lang | 7 | 0 |
| Wide | 43 | 0 | Lang-shouldfail | 2 | 0 |
| Wide-shouldfail | 2 | 0 | shouldfail | 2 | 0 |
| Present | 51 | 0 | bugs | 1 | 0 |
| Present-shouldfail | 4 | 0 | guide | 1 | 0 |
| Time | 63 | 0 | shouldfail-controls | 2 | 0 |
| Time-shouldfail | 5 | 0 | **incomplete** | **123** | **59** |

**402 differing segments, 18 of 18 groups: 305 CONTENT-DIFFERS, 96 PERMUTATION-ONLY, 1
KINDCOUNT-DIFFERS.**

**What the 305 mostly are, and it is the fix working.**  `detm` is R3's determinacy record, written
by `Subst.reduce` at every splice, and its last field is the number of partitions in the residual
it has accumulated.  **1,078 `detm` records differ; where the pairing is unambiguous, `nParts`
DECREASES 510 times and INCREASES 0 times.**  The single commonest difference in the whole corpus
is the same one in every group — including `boot`, `bugs` and `guide`, where it is the ONLY
differing segment — at `core/target/…/modules/Relation/Op.e(165:3)`:

```
pre   detm inferImplicitBindingTypes …/Relation/Op.e(165:3) c^ false false false true true 2 6 6
post  detm inferImplicitBindingTypes …/Relation/Op.e(165:3) c^ false false false true true 2 6 5
```

— one fewer partition in the residual, 52 times over the corpus, which is exactly once per JVM
(17 per-group JVMs plus `incomplete`'s 35 per-file ones).  Others: `Wide/Helpers.e(201:1)` 7 → 5,
`Layout/Report/Relation.e(39:16)` 10 → 9, `Present/Helpers.e(529:1)` 17 → 10,
`Algebra/Comprehensions.e(123:3)` 9 → 0.  **That is "the disappearance of a concrete-identity
constraint" made visible** — in the record the first instrument was not looking at.

**Two things the first version asserted that are now withdrawn.**

1. *"the `sin` supply bounds are identical … so no id was consumed or spared anywhere."*  False as
   a general claim.  Seventeen groups have no `sin` difference at all; **`incomplete` has 59**,
   from segment 1088215 on, every one with `suLo` exactly ONE LOWER after the fix
   (`304928 305151 6 …` → `304927 305151 6 …`) until the next block boundary absorbs it.  One
   `Part` fewer is one object fewer to freshen.
2. *"eight segments, sixteen groups identical."*  Even on the report's own instrument the answer
   was 11 in 3 groups — `incomplete` adds three at `incomplete/RevenueShare.e(108:12)`, one of
   which is the corpus's only `KINDCOUNT-DIFFERS` and fires a DIFFERENT RULE
   (`step concrete ^A1 <- (,pctOfRegion)` against
   `step common:#0 ^A1 <- (,productLine salesRep amount bookingMonth region)`, with `learn` 448
   against 446).  A different derivation reaching the same conclusion is more than a permutation,
   and it was never compared.

**It is not run-to-run noise, and neither is anything else measured here.**  The same binary traced
over `Algebra` and `Present` twice is IDENTICAL under the full comparison; two `.ei` sweeps of one
build differ in **0 of 224** interfaces with **2,513 of 2,513** bindings identical; two batch corpus
runs of one build produce **0** differing verdict lines, messages included.  The one gap, stated
because it is the one class of difference nobody controlled: **no same-build control was taken on
`incomplete`**, so its 123 differences (and the 59 `sin` moves) are the change on the balance of
evidence — segment counts identical, `timeouts=0 dropped=0` on both sides — but not proved to be.

**And K-1 really does fire, 2,308 times in the `Algebra` group alone.**  §3.0's "zero concrete
identities in the trace" is a statement about `in` records — the constraints `Subst.solve`
receives — and it is true.  The collapses happen EARLIER and never reach a solve.  Measured by
instrumenting the new branch of `Part.apply` with a `System.err.println` and re-running the group
(the instrumented build was thrown away afterwards; `<scratch>/k1fire-algebra.txt`):

| shape | count |
|---|---|
| `(\|X\|) <- ((\|X\|))` — one part, the pure identity | 1,896 |
| `(\|A,B\|) <- ((\|A\|), (\|B\|))` — a non-empty concrete row split into two DISJOINT concrete parts | 389 |
| `(\|\|) <- ((\|\|), (\|\|))` — the empty row into two empty parts | 23 |
| **total** | **2,308** |

**Corrected in the fix round (review N-2).**  The first version of this table said
1,516 / 769 / 23, which is not what the artefact says; re-parsing all 2,308 `[K1FIRE]` lines gives
1,896 one-part and 412 two-part, of which 23 have an empty whole.  The re-parse also produces the
result the wrong table hid, and it is the one that matters: **of the 2,308 firings, ZERO have
overlapping parts and ZERO have a part-union different from the whole** — so the guard fired only
ever on a genuine partition of a concrete row, and every one-part firing was a true identity.  That
is the guard's soundness side-condition, measured rather than argued.

Every one of them is trivially true, and the biggest is a 26-label row.  They come from two
places: `Constraint.e`'s `type (|) a b = exists c. c <- (a, b)` after both operands have been
substituted to concrete rows (`Algebra/Comprehensions.e`), and `Subst.instantiatedAt`'s
`relocateConstraints`, which re-runs `Part.apply` on an already-solved scheme's constraints at
every instantiation — by then a row variable may have become a concrete row, so a constraint that
was `v <- (a, b)` when it was written is a concrete partition when it is used again.

**The mechanism behind the 96 permutations, corrected (review N-1).**  The first version of this
report said the reorder was "the id base shifting", and that is refuted: seventeen of the eighteen
groups have no `sin` difference at all, none of the permuted segments has one, and ticket B6 —
which really does follow the id base — fires **13 times on the shipped build and ZERO times on the
K-1-only build**.  What actually happens is written down in `RowTrace.scala`'s own `scon`
paragraph: **`Exists.apply` puts the constraint list through `p.toSet.toList`**, so the order
`PQueue.build` receives is decided by the elements' `hashCode`s.  `Part.hashCode` is
`3 + 23*lhs.hashCode + 5*rhs.hashCode` (`Type.scala`).  Replace one element of that `Set[Type]` by
an `Exists` and the set changes, so the SURVIVING constraints come out of it in a different order;
the instantiation that follows mints their existentials in that new order, the ids permute, and the
permuted ids re-hash the next set.  Content-dependent and local — which is what the 96 look like,
and what an id-base shift would not be.

**(b) Thirteen refutation MESSAGES, on the shipped build, all ticket B6.**  Every one of the 154
corpus verdicts is what it was (plus the new `date01`), and thirteen REJECTED modules print a
different CLAUSE of the same refutation; eleven of them at the same FIELD, and two — `inf02` and
`inf05` — at a different field or column.  `TICKET-stdlib-findings.md` B6 is exactly this
("the blame wording is a propagation reason, not a description, and it varies with load order;
the clause follows the id base"), and names `shouldfail/inf02` as the module where the blamed
FIELD moves.  The stdlib edits shift the id base by construction, so this is B6 firing, not a new
instability: two batch runs of the shipped build give byte-identical messages.  Examples:

```
chart01  48:15 … 'channelName': a part contains it but the whole does not
      -> 47:7  … 'channelName': the whole contains it but no part does
asof01   69:7  … 'exchange': the whole contains it but no part does
      -> 69:7  … 'exchange': a part contains it but the whole does not
der02    39:7  … 'b': two parts of one partition both contain it
      -> 39:7  … 'b': the whole contains it but no part does
```

**So what K-1 does, in one sentence, with the full instrument:** it deletes trivially-true concrete
partitions before they can enter a residual; on this corpus **none of them ever reached a solve**
(zero concrete-identity `in` records in 3,205,346 segments, before or after), the residual gets
strictly shorter in **510 `detm` records and longer in none**, the constraint-set hashing that
follows permutes the solver's input order in **96** segments, **59** `incomplete` solves draw one
id fewer, and **one** published signature's residual partition count drops (§3.1).  Not one
verdict, not one message and not one `.ei` byte moves on the isolated build.  It is
SOLVER-VISIBLE, so `tracker/ROW-CONSTRAINT-STATE.md` carries the dated note the brief asks for.


## 4. The `MapView` sweep the brief asks for

Every `mapValues` / `filterKeys` / `.view` in `core/src/main/scala`, classified by whether the
lazy result is ever COMPARED, HASHED, or required to be a `Map`.  115 hits (9 of them in the dead `Access.scala`); the ones that could
matter are these.

**Fixed (were compared or hashed):** `SqlScanner.scala:644` (pivot's bootstrap key),
`SqlScanner.scala:708` (the hash join's two key functions), `relational/package.scala:67`
(`sorting`'s chunk predicate).

**Every other place a record key is built for a machines combinator — all already correct:**

| site | combinator | spelling |
|---|---|---|
| `SqlScanner.scala:421–422` | `Tee.mergeOuterJoin` | `.toMap` on both key functions |
| `SqlScanner.scala:538` | `Process.groupingBy` | `.toMap` |
| `SqlScanner.scala:716`, `:732` | `leftHashJoin`'s build/probe | `.toMap` |
| `Optimizer.scala:262`, `:277` | `Predicate.fromRecord`, `Tee.hashJoin` | `.toMap` |
| `StateScanner.scala:63`, `:67`, `:93` | filters and `Tee.mergeOuterJoin` | `.toMap` |
| `remote/BackendServer.scala:28` | `Process.grouping((_, _) => true)` | no key at all |

**A view that is only ITERATED or immediately forced** — safe, because `Map ++ MapView` and
`MapView.toSeq`/`toList`/`toMap`/`foldLeft` all force and answer a strict collection.  Checked one
by one: `Hints.scala:63/130/131/183`, `package.scala:34`, `Predicates.scala:187/205/285/307/312/815`,
`Reporting.scala:86` (`alignMap`), `Backend.scala:174`, `Runtime.scala:163/349`,
`Console.scala:479/527`, `Profiling.scala:15`, `Lib.scala:574/934/997/1016/1021/1026`,
`Enumeration.scala:132`, `Session.scala:269`, `TableFlattener.scala:229`, `ParseState.scala:70`,
`SqlScanner.scala:418/504/1035/1248`, `Core.scala:62/98/99`, `Optimizer.scala:310/316`,
`SqlInspect.scala:52/103/111/132/154/155`, `Graph.scala:34/76/80/109/138/209/302`,
`SqlEmitter.scala:311/798`, `KeyValueTabular.scala:73/75`, `SQLBackend.scala:81/85/102`,
`Legend.scala:76/93/120/180/351/449`, `BulkLoad.scala:161/164/167/172/184/259`,
`ChartData.scala:138/176/425`, `Writer.scala:253/612`, `Constraints.scala:2547`,
`Typer.scala:182` (`pivCols` is a view, but it is only asked for `keySet` and then `++`-ed into a
strict `Header`).

**Not `Map#filterKeys` at all** — `com.clarifi.reporting.util.Keyed` declares its own
`filterKeys(A => Boolean): C[A]`, which is strict and answers the same type.  That is what
`SqlScanner.scala:524/557/868/973` (a `Reflexivity`), `Graph.scala:68` (a `PartitionedSet`),
`Predicates.scala:262` and `Access.scala:66/137/201/225/346/347` call.

**Dead code:** the whole body of `Access.scala` is inside a block comment (lines 2–359) and
produces no class file, so its six `filterKeys` and three `mapValues` are not compiled at all.

## 5. Not done, and limits left in place

* **C12 is not this stage.**  `Layout.Scan`'s `sumBy`, `avgBy'`, `count`, `count'` still publish the
  same vacuous `(exists t h. r <- (t, h))` that `sumBy'` lost here, and so do the four
  `Relation.Scan` bindings behind them.  Deleting them one signature at a time is not the fix; the
  ticket's own acceptance criteria put it in `Subst.mkSimplified`, behind a Lean theorem R3 does not
  yet have (`TICKET-stdlib-findings.md` C12).  `sumBy'` is edited here because the brief names it and
  because it is the one the E2 review confirmed by hand.
* **`rename'` keeps its name.**  The brief says not to rename the API; the doc line says what it
  requires.  A caller who wants a rename into a column that is NOT there wants `rename`.
* **A1b's three fixes are not reachable from Ermine.**  `Scanners.e` publishes only `dumpClosed`, so
  the REPL can dump a relation's SQL and can never execute a `Mem`; `SqlScanner` has no `dumpMem`
  override, which is the wall every `Mem` probe in `sql-render.sh` already hits (recorded in F1).
  The five new properties drive the three functions directly and are the only thing that exercises
  them.  Making the in-memory path reachable is a separate piece of work (ticket C8).
* **`Date` still has no timezone PARAMETER.**  Ticket A3 offered "one timezone (UTC), or make it a
  parameter"; this is the first.  A report that must label periods in a local zone still has to do
  it from a calendar column, which is what `core/examples/Time` does anyway.
* **Date ARITHMETIC is still in the JVM's default zone, and the fix round found it.**
  `Date.incrementDate` / `decrementDate` / `incrementTimestamp` go through
  `com.clarifi.reporting.TimeUnit.increment` (`Op.scala:291`, `:313`), which builds a
  `Calendar.getInstance` and adds there.  Whole-day addition is offset-invariant EXCEPT across a
  daylight-saving transition, and then it lands on the wrong UTC day:

  ```
  incrementDate 1 days @2011/3/13     -Duser.timezone=UTC: "3/14/11"    America/Denver: "3/13/11"
  incrementDate 1 days @2011/11/6     both: "11/7/11"
  ```

  (13 March 2011 is the US spring-forward; the autumn one does not move it.)  This is A3's family
  and A3's one-line fix — `Calendar.getInstance(YMDTriple.ymdPivotTimeZone)` — but it CHANGES a
  shipped function's answer on a non-UTC host, which is a stage with its own gates, not a footnote
  in this one.  `Date.e`'s header, which the first round wrote as "every function in this module
  reads and writes a `Date` in UTC", now scopes that claim to reading and formatting and names
  this; ticket A3 carries it as still open.
* **`dateDiff#` itself still publishes a free result row.**  The primitive's declaration
  (`Relation/Op.e:177`) is unchanged, because it is the raw foreign import and the wrapper is what
  users call; a caller who reaches past the wrapper to `dateDiff#` gets the old hole.  The same is
  true of `dateAdd#`, which has always been that way.
* **`Time/Helpers.e`'s date helpers still repeat the hole**, and that is the one place where B1's
  guarantee does not reach.  `dayCount : forall r r1 out. Field r Date -> Field r1 Date -> Op out
  Int` is STILL ACCEPTED for its body after the stdlib fix, so a `combine` of `dayCount` over a
  relation with neither date still type-checks and still fails at header computation.  Tightening
  it to `RUnion2 out r r1 => …` (and the seven siblings likewise) was tried here and loads the
  whole `Time/` group cleanly; it was reverted because it is an example-level change the brief did
  not ask for and it would have moved eight published signatures the `.ei` gate was told to expect
  not to move.  The helper's comment says all of this, and since the fix round it has **a ticket
  entry of its own** — `TICKET-stdlib-findings.md` **B1a** — naming the eight helpers, the three
  `Time/Signatures.e` `yearFrac365*` that mirror them, and the two untouched primitives
  `dateDiff#` / `dateAdd#`.  Parking open work inside a FIXED entry is how it gets lost (review
  N-8).
* **The one judgement call in this stage** is §3.4's moved segments, and the fix round changes what
  the call was made ON without changing the call.  The brief says to STOP if anything moves that is
  not the disappearance of a concrete-identity constraint.  With the full instrument, **305 of the
  402** differing segments are exactly that disappearance made visible — R3's `detm` residual
  partition count decreasing 510 times and increasing never — and **96** are the constraint-order
  permutation the deletion causes through `Exists.apply`'s `p.toSet.toList`.  Nothing is added,
  nothing is refuted differently, and no verdict, message, rendering or published interface moves
  on the isolated build.  But an ORDER change is still not a deletion, and one `incomplete` segment
  fires a different rule to reach the same conclusion, so a reviewer reading the instruction
  strictly is entitled to say the stage should have stopped.  **The independent review says exactly
  that and settles it**: "the stage did not need to stop, but it needed a wider instrument"
  (`F3-REVIEW.md` §2.4) — the conclusion was right, the measurement it was drawn from was wrong by
  a factor of about fifty, and the instrument is fixed and now lives in `tracker/tools/`.

* **The one gate not taken: the Lean model replay of the `incomplete` group on the shipped build.**
  Its 1,905,718 segments come from modules that are non-terminating by design, and the replay is
  hours (the `Wide` group's 115,874 segments took 865 s, and `incomplete` is sixteen times that).
  The COMPILER trace was taken (that is where the +350 delta comes from), and the other seventeen
  groups agree with the model on the shipped build; the base build's `incomplete` replay is not a
  gate this stage needed, because K-1 was isolated on a byte-identical stdlib and `incomplete` is
  identical there.  A reviewer with the time should run
  `LOOPTRACE_GROUPS=incomplete tracker/tools/looptrace-corpus.sh <dir>` and expect
  `agree = 1,905,718`, `skip = 0`.
* **The `.ei` sweep does not hoist the five group libraries.**  `ei-sweep.sh` (and
  `tracker/tools/ei-diff.sh`, which it is copied from) puts `Ai/Common.e` at the head of any chunk
  holding an `Ai/` module and does nothing of the kind for `Wide/Helpers.e`,
  `Algebra/Helpers.e`, `Time/Helpers.e`, `Present/Helpers.e` or `Lang/Helpers.e`.  As long as the
  file list does not change, the loss is symmetric and invisible; add one file, as B1 does, and
  the chunk boundaries shift and a different module falls off.  Worth fixing in the tool before
  the next `.ei` A/B that adds or removes a corpus file.

**Two traps this stage paid for, for whoever runs these gates next.**

1. **`sbt core/compile` does not copy `core/src/main/resources/modules` into
   `core/target/scala-3.3.8/classes/modules`.**  `bin/ermine` reads the TARGET copy, so a stdlib
   `.e` edit is invisible to every sweep until `sbt core/copyResources` runs.  This cost one full
   corpus run here, which reported "85 / 68 unchanged" for a build that was still using the old
   `Relation/Op.e`.  Check with `grep` for a string you just added to the target copy before
   trusting any `.e` gate.
2. **"No concrete-identity constraint in the row trace" does not mean `Part.apply` never sees
   one.**  The trace records what `Subst.solve` RECEIVES; `Part.apply` also runs at parse time and
   at every instantiation (`Subst.instantiatedAt` → `relocateConstraints`), and most of what it
   collapses never reaches a solve.  Instrument the branch if you want to know whether a case is
   live — a grep over the trace will tell you it is dead when it is not.

---

## 6. Fix round (F3 review)

`tracker/loopmodel/F3-REVIEW.md` (713 lines) returned **FIX-THEN-ADVANCE**: all seven fixes
correct, every gate re-run at the reported number, the K-1 length test verified load-bearing in
both directions (a compiler with `&& ss.length == cs.size` deleted ACCEPTS an unsatisfiable
partition the shipped one rejects).  What it found wrong was the measurement of K-1's blast radius,
two permanent trackers that repeat it, one test's hygiene, one gate tool and seven count slips.

| # | finding | what was done | evidence |
|---|---|---|---|
| **N-1** | the row-trace instrument compared 6 of the trace's 16 record kinds, so "8 segments in 2 groups" was an artefact; and the stated mechanism ("the id base shifts") is refuted | `tracker/tools/trace-ab.py` rewritten to compare EVERY record and every field (masking only `rsound ok`'s wall-clock micros), classify `PERMUTATION-ONLY` / `CONTENT-DIFFERS` / `KINDCOUNT-DIFFERS`, and report `sin` bound moves separately; it now lives in `tracker/tools/` instead of scratch.  §3.4 and §3.1 rewritten; the mechanism corrected to `Exists.apply`'s `p.toSet.toList`; the three permanent documents corrected | **402 differing segments in ALL 18 groups** (305 content, 96 permutation, 1 kindcount), noise floor 0 on the same-build control pair; **510 `detm` residual-partition DECREASES and 0 increases**; **59** `sin` supply-lo moves, all in `incomplete` |
| **N-2** | §3.4's shape table did not match its own artefact | corrected in `F3-FIXES.md`, `ROSE-COMPARISON.md` and `ROW-CONSTRAINT-STATE.md`, and the positive result it hid is now stated | re-parse of all 2,308 `[K1FIRE]` lines: **1,896 / 389 / 23**, and **0 firings with overlapping parts, 0 with a part-union different from the whole** |
| **N-3** | the K-1-only isolation never took an `.ei` snapshot, so "no published interface moves" was unmeasured | taken, on the repaired sweep: a BASE build, a K-1-ONLY build (stdlib `.e` and corpus reverted, Scala kept) and the shipped build, each swept in turn | **2 of 268 interfaces, 4 bindings** move under K-1 alone: `Algebra/SoftSchema`'s `fulcrum4`, `fulcrum5` and `pivoted` are **alpha-equivalent**, and `Layout.Report.Relation.cutoffGroupedFldsPosNegRel'` is `other` — 26 partitions on both sides, one 3-part partition becoming a 6-part one.  **3,474 bindings identical, nothing `concrete->polymorphic`, no binding lost or added.**  The claim "no published interface moves" is withdrawn; the accurate one is "no published type gets weaker" |
| **N-4** | `ei-diff.sh` hoisted only `Ai/Common.e`, so ~half the healthy corpus produced no `.ei` | `tracker/tools/ei-diff.sh` now hoists all six group libraries, and hoists to the HEAD even when the chunk already holds the library (the chunk is sorted, so `Ai/ClinicalTrial.e` precedes `Ai/Common.e`), dropping the duplicate copy; it also gained a `--snapshot` mode so a two-BUILD comparison no longer needs a scratch clone.  Full A/B re-run on the repaired tool | coverage **225 → 268 interfaces**, chunk `Module not found` failures **59 → 1**, healthy corpus modules with no `.ei` **45 → 4**.  The A/B over the full corpus finds **13 of 268 interfaces differing, 3,414 identical / 50 order-only / 8 alpha-equivalent / 6 other / 3 only-in-B** — **the same nine bindings** as the narrow sweep, with 43 more interfaces in view and no interface only on one side |
| **N-5** | the new corpus module's comment pinned 49:7 | corrected to **55:7** (the comment edit moved the binding) and re-verified against the build | `date01_datediff_free_row.e:55:7: … 'startDate': the whole contains it but no part does` |
| **N-6** | three date properties only discriminated off-UTC, and one mutated `TimeZone.setDefault` globally in a parallel suite | every date property now runs its probe under an explicit non-UTC zone through one `underZone` helper, which takes `ErmineFixture.literalLock` (the monitor `loadStatements` takes) and restores in a `finally`; the file documents what could see the write | on a UTC host the suite is **12/12 PASS** on the fixed build and **5 of 12 FAIL** with A3 reverted — so it discriminates where the first version did not.  The two `PrimExprs`-level properties still pass there, because only the Ermine BINDING was reverted; between them the two halves cover both |
| **N-7** | count slips | "twelve bindings" → **nine**; "925 + 12 new" → **922 + 15** (now 922 + 17); "seven helpers" → **eight**, named with line numbers; existential counts corrected to exclude the outer `forall` (`valueAsOf` 11, `shareOfGroup` 17, `cutoffGroupedFldsPosNegRel'` 40, of which 34 row) | the counts are re-derived in §3.3 |
| **N-8** | the `dayCount` hole was parked inside a FIXED ticket entry | **`TICKET-stdlib-findings.md` B1a** opened: `Time/Helpers.e`'s eight helpers with line numbers, `Time/Signatures.e`'s three `yearFrac365*`, and the two untouched primitives, with the measured note that tightening the eight loads the whole `Time/` group | B1 now points at it |
| **new** | *(not a review finding)* while answering N-6's "what could see a global `TimeZone.setDefault`", the grep found a defect of A3's own family that F3 did not fix: `Date.incrementDate`/`decrementDate`/`incrementTimestamp` still add in the JVM's DEFAULT zone (`Op.scala:291`, `:313`) | recorded, not fixed — it changes a shipped function's answer on a non-UTC host, so it wants its own stage.  `Date.e`'s header no longer claims "every function in this module"; ticket A3 carries it as still open; §5 has it | `incrementDate 1 days @2011/3/13` = `"3/14/11"` under `-Duser.timezone=UTC` and `"3/13/11"` under `America/Denver` — the US spring-forward eats the day.  `@2011/11/6` (the autumn transition) does not move |
| **N-9** | two `.ei` bindings were called "a renaming" | corrected: their partition-ARITY histograms move (a part is substituted into its own parts), so they are an equivalent residual in a more expanded form — and for `cutoffGroupedFldsPosNegRel'` the equivalence is argued, not checked | `shareOfGroup` `{2:9, 3:5}` → `{2:9, 3:4, 4:1}`; `cutoffGroupedFldsPosNegRel'` `{1:1, 2:14, 3:6, 4:3, 5:1, 6:1}` → `{1:1, 2:14, 3:5, 4:3, 5:2, 6:1}` |

### 6.1 The corrected row-trace differential, in full

Command: `tracker/tools/trace-ab.py <pre>/traces/<g>.tsv.gz <k1>/traces/<g>.tsv.gz --name <g>`
over the eighteen preserved group traces of the base build and the K-1-only build.

```
boot        1   top         4   Ai         30   Wide       43   Wide-shouldfail      2
Present    51   Present-sf  4   Time       63   Time-sf     5   Algebra             60
Algebra-sf  1   Lang        7   Lang-sf     2   shouldfail  2   shouldfail-controls  2
bugs        1   guide       1   incomplete 123 (+59 `sin` supply-lo moves)
```

**402 of 3,205,346 segments, 18 of 18 groups — 305 CONTENT-DIFFERS, 96 PERMUTATION-ONLY, 1
KINDCOUNT-DIFFERS.**  Noise floor, same tool, same-build control pair: `Algebra` 101,005/101,005
and `Present` 131,358/131,358 IDENTICAL, `sinmoved=0`.

The dominant class is R3's `detm`.  **1,078 `detm` records differ; where the pairing is
unambiguous the residual partition count DECREASES 510 times and INCREASES 0 times.**  The
commonest single difference in the corpus is `…/modules/Relation/Op.e(165:3)` `nParts` **6 → 5**,
52 times — once per JVM (17 per-group plus `incomplete`'s 35 per-file) — and in `boot`, `bugs` and
`guide` it is the only differing segment there is.  `ramb`, the per-published-signature record,
differs in exactly **one** binding over all eighteen groups:
`Layout.Report.Relation.cutoffGroupedFldsPosNegRel'`, `27 → 26` partitions.

### 6.2 The `.ei` gate, on the repaired sweep

`tracker/tools/ei-diff.sh` hoisted `Ai/Common.e` and nothing else, so every chunk holding a
`Wide/`, `Algebra/`, `Time/`, `Present/` or `Lang/` module failed at its first import.  The loss was
symmetric across the two sides of one comparison, so the gate looked healthy; it is not, and adding
one corpus file (B1's) shifted the chunk boundaries and dropped a different module, which is how it
surfaced.  With all six libraries hoisted — and hoisted even when the chunk already holds one, since
the chunk is sorted and `Ai/ClinicalTrial.e` precedes `Ai/Common.e`:

| | before | after |
|---|---|---|
| interfaces captured per side | 225 | **268** |
| `Module not found` per side | 59 | **1** |
| healthy corpus modules with no `.ei` | 45 of 92 | **4 of 92** |

The four that remain (`HelloWorld.e`, `Interp.e`, `Sample.e`, `Yahoo.e`) and the one failure
(`YahooExtras`, which imports `Yahoo` and is not a group library) are a different shape of problem
and are left; `Time/FiscalTree.e`, the example module this stage edits for A3/A4, is now covered.

**BASE vs the shipped F3 build, 268 interfaces, 3,481 bindings:** 13 interfaces differ —
**3,414 identical, 50 order-only, 8 alpha-equivalent, 6 `other`, 3 `only-in-B`**, and no interface
present on one side only.  **The six `other` and three `only-in-B` are exactly the nine bindings
§3.3 already names** — `Relation.Scan.sumBy'` and `Layout.Scan.sumBy'` (3 → 2), `Relation.Op.dateDiff`
(3 → 6), `Layout.Scan`'s three new re-exports, and `valueAsOf` / `shareOfGroup` /
`cutoffGroupedFldsPosNegRel'`.  Forty-three more interfaces in view produced **no new movers**, and
nothing anywhere is `concrete->polymorphic`.

**BASE vs the K-1-ONLY build, same 268 interfaces (review N-3):** **2 interfaces, 4 bindings** —
`Algebra/SoftSchema`'s `fulcrum4`, `fulcrum5` and `pivoted` alpha-equivalent, and
`Layout.Report.Relation.cutoffGroupedFldsPosNegRel'` `other`, with 26 partitions on both sides and
one 3-part partition becoming a 6-part one.  **3,474 bindings identical.**  So the state file's
"no verdict, message or published interface moves because of them" was two-thirds measured and
one-third assumed; the accurate statement, now in the state file, is that **no published type gets
WEAKER and none is lost or added, and four move**.

### 6.3 Gates after the fix round

| gate | measured | verdict |
|---|---|---|
| `core/test` | **Total 939, Failed 1, Errors 0, Passed 938**; the one failure is the documented `Constraints.disjunction sound` starvation.  **922 before F3 + 17 new** (5 `TestInMemoryScan`, 12 `TestDateAndScan`) = 939 | PASS |
| `TestLoopTrace` | `720 solves … 720 segments; 720 agree; #summary segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0` | PASS |
| `TestDateAndScan` alone, rewritten, host default zone | **12 / 12 pass** | PASS |
| `TestDateAndScan` alone, **`-Duser.timezone=UTC`** | **12 / 12 pass** — host-independent, which the first version was not | PASS |
| the same, on a build with **A3 reverted**, still UTC | **5 of 12 FAIL** with the Denver readings (`"11 0 1 2 …"`, `"Q4 Q1 Q1 …"`, `"Dec 31"`) — so the guard discriminates on a UTC host.  The two `PrimExprs`-level properties still pass, because only the Ermine BINDING was reverted; between them the two halves cover the Scala helper and the binding | PASS |
| the 18-group row trace, EVERY record kind | 402 / 3,205,346, 18 of 18 groups; noise floor 0 | §6.1 |
| the `.ei` A/B over the full corpus | 268 interfaces, 13 differ, nine bindings, none weaker | §6.2 |
| `date01`'s pinned position | `55:7`, re-verified | PASS |
| `.ei` hygiene | `find core/examples core/src/main/resources/modules core/target/…/modules -name '*.ei'` prints nothing | PASS |

