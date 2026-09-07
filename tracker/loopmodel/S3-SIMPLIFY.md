# S3 — the omissions in `Subst.mkSimplified`: permuted duplicates and the tautology `a <- (a)`

Stage S3 of `tracker/LOOP-MODEL-PLAN.md`, 2026-09-07, from `tracker/ROSE-COMPARISON.md` §3 rank 1.
Brief `briefs/brief-S3.md`.  **GREEN**: both defects reproduce, both are fixed, every gate is green,
and every published residual the fix moves is proved ENTAILMENT-EQUIVALENT to the one it replaces —
mechanically, by a complete per-label decision, with a same-configuration control showing the
measurement is not sweep churn.

One expectation in the brief is **corrected by measurement** and it is the only thing here a reader
should not skim: the brief says the row trace "must be byte-identical" because `mkSimplified` is
post-loop.  It is not, it cannot be, and §5 says exactly why — `mkSimplified` runs a solve of its
own, and its output is the input of every later solve that instantiates the binding.  What IS
byte-identical is the loop's behaviour as a function of its input: `TestLoopTrace` 714/714, and the
model agrees with the compiler on 54,199 + 115,864 corpus segments on BOTH sides.

---

## 1. The reproduction (S3.1), before and after

One JVM, two modules, `-Dermine.loadInSeries=true`, interfaces on, the stdlib re-derived on each
side; the `.ei` text as published.

**(a) The tautology — `core/examples/incomplete/TopReadings.e`.**  `TopReadings.e:31` documents it
and `Incomplete.Signatures.tautIsFree` is the hand proof that it is vacuous.

```
BEFORE  topRowsBy : forall (h: rho) (a: rho -> *) (b: rho).
          (exists (c: rho). b <- (c, h), h <- (h), b <- (h, c), Builtin.RelationalComb a)
          => Relation.Row.Row h -> Builtin.Int -> a b -> a b

AFTER   topRowsBy : forall (h: rho) (a: rho -> *) (b: rho).
          (exists (c: rho). b <- (h, c), Builtin.RelationalComb a)
          => Relation.Row.Row h -> Builtin.Int -> a b -> a b
```

BOTH defects are in this one binding: `h <- (h)` is the tautology, and `b <- (c, h)` / `b <- (h, c)`
are one constraint printed twice with its parts permuted.  Three row constraints become **one**, and
that one is `Has b h` — literally the signature `TopReadings.e:18` says "a competent user expects"
and `Incomplete.Signatures.topRowsByDeduped` proves the body has.

**"Three become one" is the VIRGIN-LOAD figure** (review K-9), and this section is the only virgin
load in the report.  In the interface-carrying `.ei` sweep of §4 the same binding's pre-fix residual
is only `b <- (c, h), h <- (h)` — the permuted copy is already gone, because the module is compiled
against interfaces earlier chunks wrote — so there it is 3 constraints → 2.  Both are pre-fix states
and the fix cleans both; §4's table reports the sweep's.

**(b) The permuted duplicate — `core/examples/incomplete/np01_add_or_recompute.e`.**  This is
`A1-REVIEW.md` §R-1's binding.

```
BEFORE (9 row constraints; the two pairs marked)
  t1 <- ((|unitCost, qty, unitPrice|), a, so1, rs1)
  t1 <- ((|qty, unitPrice, unitCost, revenue|), rs, b)      <-- pair 2
  RelationalComb rel
  t  <- ((|qty, unitPrice, unitCost, revenue|), b, so, rs)
  (|margin|)  <- (so, rs)
  r  <- ((|unitCost, qty, unitPrice|), a, rs1)              <-- pair 1
  r  <- ((|unitCost, qty, unitPrice|), rs1, a)              <-- pair 1
  t1 <- ((|qty, unitPrice, unitCost, revenue|), b, rs)      <-- pair 2
  (|revenue|)  <- (so1, rs1)

AFTER (7 row constraints)
  t1 <- ((|qty, unitPrice, unitCost, revenue|), a, rs)
  t  <- ((|qty, unitPrice, unitCost, revenue|), a, so, rs)
  t1 <- ((|unitCost, qty, unitPrice|), rs, a, so1, rs1)
  r  <- ((|unitCost, qty, unitPrice|), rs1, rs, a)
  RelationalComb rel
  (|margin|)  <- (so, rs)
  (|revenue|)  <- (so1, rs1)
```

Nine become seven — the number `A1-REVIEW.md` §R-1 reached by hand ("de-duplicated, both sides have
7") is now what the compiler prints.  The two residuals are EQUIVALENT (§4, `rowequiv.py`, 2 universal
rows × 6 label classes = 24 patterns, agree on all).

## 2. The change (S3.2)

`core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala`, +13 −1, nothing else touched.

```diff
   private case class NormalPart(loc: Loc, left: TypeVar, concrete: Set[Name], abstrakt: List[TypeVar]) {
     override def equals(a: Any) = a match {
       case NormalPart(_, l, c, a) => l == left && c == concrete && a.sortWith(_.id < _.id) == abstrakt.sortWith(_.id < _.id)
+      case _ => false
     }
+    // MUST agree with `equals` above, which ignores `loc` and compares `abstrakt` SORTED:
+    // `List.distinct` buckets by `hashCode` and only compares within a bucket, so the
+    // synthesised case-class hashCode (which hashes `loc`, and hashes `abstrakt` in ORDER)
+    // sent two permuted copies of one constraint to different buckets and published both.
+    // `V.hashCode` is `id.hashCode`, so hashing the ids is hashing the variables.
+    override def hashCode: Int = (left.id, concrete, abstrakt.map(_.id).sorted).hashCode
     def part: Type = Part(loc, VarT(left), ConcreteRho(loc, concrete) :: abstrakt.map(VarT(_)))
   }
...
           case VarT(v) =>
-            Some(Left(NormalPart(loc, v, cs, vs)))
+            // `a <- (a)` is an identity, not a condition: the sibling of the ConcreteRho
+            // case just above, which already deletes `(|Foo|) <- (|Foo|)`.  It is true of
+            // every row, so deleting it cannot weaken the published residual.
+            if(cs.isEmpty && vs == List(v)) None
+            else Some(Left(NormalPart(loc, v, cs, vs)))
```

Three things, as ROSE-COMPARISON §3 rank 1 asked: the `hashCode`, the `MatchError` default case
(`NormalPart.equals` had no `case _`), and the tautology.  `normal` is a `List[Either[NormalPart,
Type]]` and `List.distinct` is `distinctBy(identity)` over a `mutable.HashSet`; `Left`'s hashCode is
its payload's, so fixing `NormalPart.hashCode` is what makes `distinct` see the permuted copies at
all.

### The third sibling: it exists, in two readings, and NEITHER is fixed here

* **ROSE-COMPARISON §3 rank 1 item 3 — `Part.apply`.**  There is no variable-identity case, and
  `Part.isTrivialConstraint` is `false` unconditionally (`Type.scala:394`).  **But the symmetry both
  that document and the first version of this one used to motivate the item — "the concrete case is
  handled and the variable case is not" — DOES NOT HOLD HERE** (review K-1).  `Type.scala:414` reads

  ```scala
  val (ts, rcl, ss) = rh.foldLeft((List[Type](), l, List[Name]())) { … s.toList ++ ss … }
  case ConcreteRho(lclhs, cs) if ts.isEmpty && ss == cs => Exists(l)   // (|Foo,Bar|) <- (|Foo,Bar|)
  ```

  and `ss` is a `List[Name]` while `cs` is a `Set[Name]` (`ConcreteRho(loc, fields: Set[Name])`), so
  `ss == cs` is **always false** at this project's Scala 3.3.8 and the case is **dead code**:
  `(|Foo,Bar|) <- ((|Foo,Bar|))` falls through to `case _ if ss.toSet.size == ss.length`, is rebuilt
  unchanged and reaches the solver.  What deletes it is `normalPart`'s `ConcreteRho` branch, from the
  PUBLISHED residual only, where the comparison really is `Set == Set`.  So at `Part.apply` **neither**
  case is handled — a fourth omission of the same family, and the repair is one word, `ss.toSet == cs`.
  **Deliberately not fixed, and now it is two fixes rather than one.**  `Part.apply` is on the
  PRE-solver path, not after it: `Constraints.scala:786` (`PQueue.toTypes`) builds every partition
  through it and `PQueue.build` reads them back, so either case there stops a constraint reaching the
  solver at all — the row trace moves and the L2 corpus differential has to be re-established on every
  group.  `incomplete/Signatures.e:40`'s `taut : r <- (r) => …`, whose `tautIsFree` proves it
  discharges from an empty context, is a source-written constraint of exactly that shape, so the proof
  would stop proving what it says.  The published-residual benefit is already obtained by the
  `normalPart` case, which is after the loop.
* **The brief's reading — "no case for a constraint entailed by a duplicate-free sibling."**
  CONFIRMED by reading: `mkSimplified` does isolation pruning (`isolated`), normalisation and the
  concrete-identity deletion (`normalPart`), syntactic de-duplication (`distinct`) and ambiguity
  pruning (`ambiguitiesIn`) — and **no entailment test between surviving partitions anywhere**.
  That is real, and it is ROSE-COMPARISON's rank 3 (canonical simplification), a separate stage: it
  is not a bug of the same shape (a handled concrete case beside an unhandled variable case) but a
  missing feature, and it is the one change here that could NOT be justified by "this deletion is a
  tautology or a copy".  Two of the residuals S3 moves show what it would buy: `RunCalibration.valueAsOf`
  carries `t <- (e, c1, r)` entailed by three siblings (`A1-REVIEW.md` §4b proves it), and the
  `runningTotal` probe (§6) publishes `e <- (f1, f, e1, d1, so)` entailed by three others.

## 3. Gates (S3.3)

Everything below is one class snapshot per side (`snap-before` = the tree at the parent commit,
`snap-after` = the same tree with the diff above), so no measurement can be contaminated by the two
other agents compiling on this machine.

| gate | before | after | verdict |
|---|---|---|---|
| `sbt -batch -J-Xmx3g core/test` | — | **Total 914, Passed 913, Failed 1** | ✔ the single failure is `! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded` — the documented generator starvation (`tracker/06-tests.md`) |
| `sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'` | — | **714 solves, 714 segments, 714 agree**; `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls 46 and 58 of 714; `Passed: Total 3, Failed 0` | ✔ 714/714 — but see the note below the table (K-7) |
| `looptrace-corpus.sh` group `boot` | 54,199 segments, **54,199 agree**, skip 0 | 54,199 segments, **54,199 agree**, skip 0 | ✔ the model still matches the compiler on every solve |
| `looptrace-corpus.sh` group `Wide` | 115,864 segments, **115,864 agree**, skip 0 | 115,864 segments, **115,864 agree**, skip 0 | ✔ |
| byte-identity of the row trace | — | **NOT identical** — see §5 | ⚠ the brief's premise, corrected |
| `corpus-run.sh --batch` | **69 LOADED / 61 REJECTED** of 130 | 70 / 62 of 132 (E4 added two `Present/` files between the two runs) | ✔ over the 130 files common to both runs, **0 verdicts differ** — this gate compares **exit codes only**; the reviewer compared `.out` contents and found **one refutation CLAUSE moves**, see §8 (K-2) |
| `corpus-run.sh --incomplete --batch` | **18 LOADED / 16 REJECTED** of 34 | 18 / 16 | ✔ 0 of 34 differ |
| `.ei` sweep, deterministic loader | 242 interfaces / **2,946 bindings** | 242 / 2,946 | 10 interfaces and **21 bindings** change — §4 |
| `.ei` sweep, SAME-configuration control | — | — | ✔ **0 of 242 interfaces differ** between two runs of the after compiler: the sweep is deterministic and all 21 changes are the fix |
| `Signatures.e` still checks | 0 errors | 0 errors | ✔ all five: `Wide`, `Algebra`, `Time`, `Present`, `incomplete` |
| `perf-bench.sh batch -n 3` | **12.04 s** | **12.05 s** (a second run 12.10 s) | ✔ **unmoved** — run by the REVIEWER on a quiet machine (load ≈ 1.1); I could not run it (see below) |

**Perf** (review K-8).  I could not run `perf-bench.sh`: it refuses above load average 1.5 and this
machine ran at 3–7 with two other agents on it.  **The reviewer ran it, on both sides, on a quiet
machine: 12.04 s before, 12.05 s after (a second after-run 12.10 s), each started at load ≈ 1.1,
spreads 0.37 / 0.16 / 0.12 — the before median sits between the two after medians.  Unmoved.**  That
is the measurement of record and it supersedes the import-time proxy this report first quoted
(23.7 s → 21.9 s, 92 %), which was a single pair of runs on a machine at load 3 and does not
reproduce at that magnitude: the reviewer's re-measured proxy over the 70 modules his two batch runs
share is **21.40 s → 20.99 s (98.1 %)**, worst single regression +0.05 s, dominated by `WardRoster`
−0.62 s, with `incomplete` 2.67 s → 2.49 s.  Direction and dominant contributor agree; the magnitude
does not, so take the 98.1 % and the 12.04 → 12.05 s, not the 92 %.

**`TestLoopTrace` can pass vacuously** (review K-7).  It **skips its real work when the Lean model
binary is absent** from the tree it runs in — `[loop model trace] SKIPPED: the Lean model executable
is absent …` — and still reports `Passed: Total 3`.  The 714/714 above was taken in the main checkout,
where `tracker/lean/.lake/build/bin/looptrace` exists; anyone quoting a `core/test` 914/913/1 from a
worktree without it is quoting a gate with the loop-model property switched off, and should pass
`-Dermine.looptrace=<path>`.  The reviewer re-ran it that way on BOTH sides: 714/714 twice.

**Which corpus** (review K-5).  The `.ei` sweep is 174 files — the whole example corpus except the
then-uncommitted, in-flight `core/examples/Lang/` — taken against a FROZEN copy of `core/examples`,
in chunks of ten with each group's library hoisted, interfaces ON (they are the thing being
measured), `-Dermine.loadInSeries=true`.  The copy was taken **before** E4's `Present/ProjectionCost.e`
and `Present/shouldfail/proj01_seven_reads.e` were committed, so **at the reviewed commit `0741fb2`
the same sweep is 176 files / 243 interfaces / 2,966 bindings**, not 174 / 242 / 2,946.  Every
per-binding number is identical on both corpora — the reviewer re-swept at `0741fb2` and got the same
ten interfaces and the same twenty-one binding names — and the `Lang/` group, committed as `3b5ad49`
mid-review and swept separately, changes 13 bindings, all of them stdlib bindings already among the
21, with no `Lang_*.ei` binding moving at all.  The absolute counts below are this stage's corpus;
a committer re-running at HEAD will see the larger ones.

## 4. What moved in the published signatures, and the proof it is equivalent

**21 of 2,946 bindings, in 10 of 242 interfaces.**  Classified two ways.

**Syntactically** (`s3check3.py`: is AFTER exactly BEFORE minus permuted/exact duplicate partitions
minus `a <- (a)`, allowing an existential renaming because the printer names variables in order of
first appearance):

```
  EXPLAINED as exactly 'BEFORE minus permuted-duplicates minus tautologies': 19  (3 needed a renaming)
  duplicate copies deleted 10 ; tautologies deleted 15
  NOT EXPLAINED: 2
```

| interface | binding | before | after | dup | taut |
|---|---|---|---|---|---|
| `incomplete/TopReadings` | `topRowsBy` | 3 | 2 | 0 | 1 |
| `incomplete/RunCalibration` | `scaledRuns` | 7 | 6 | 1 | 0 |
| `incomplete/RunCalibration` | `valueAsOf` | 9 | 8 | 0 | 1 |
| `Layout.Report` | `drilldownKeyValueTable2` | 6 | 5 | 1 | 0 |
| `Layout.Report` | `drilldownPivotTabular` | 8 | 6 | 2 | 0 |
| `Layout.Report` | `drilldownPivotTabular'` | 8 | 6 | 2 | 0 |
| `Layout.Report` | `keyedDrilldown` | 6 | 5 | 0 | 1 |
| `Layout.Scan` | `legend1` | 2 | 1 | 0 | 1 |
| `Relation` | `count` | 2 | 1 | 0 | 1 |
| `Relation` | `lookbackJoin` | 10 | 9 | 0 | 1 |
| `Relation` | `maxRowBy` / `minRowBy` | 4 | 3 | 0 | 1 |
| `Relation.Aggregate` | `count` | 2 | 1 | 0 | 1 |
| `Relation.Op` | `dateRange` | 6 | 5 | 0 | 1 |
| `Relation.Op` | `growthOf10k` / `negate` | 2 | 1 | 0 | 1 |
| `Relation.RTree` | `level1` | 8 | 6 | 1 | 1 |
| `Present.WriterOutputs` | `asDocument`, `asProfiledDocument`, `reportFor` | — | — | 0 | 0 |
| `Layout.Report.Relation` | `cutoffGroupedFldsPosNegRel'` | 44 | 39 | 3 | 2 |

Of the last four, **two are propagation and two are print-order churn** (review K-4).  The only
change to `Present.WriterOutputs.asDocument` and `asProfiledDocument` is the ORDER the field names of
one concrete row print in — `(|pRegion, pTitle, pMinValue|)` → `(|pMinValue, pTitle, pRegion|)`, the
iteration order of a three-element `Set[Name]`, which Scala keeps in insertion order at that size and
which shifted with the constraint order; same constraint, same count, and `s3check3.py` classes them
as EXPLAINED with `dup=0 taut=0`.  The genuinely propagated pair is `reportFor` and
`cutoffGroupedFldsPosNegRel'`: with interfaces on, a module reads the (now smaller)
signature of a module above it and its own solve saturates differently.  `reportFor` swaps one
consequence of its own second constraint for another (`a <- ((|pTitle,pRegion|), c)` for
`a <- ((|pTitle,pMinValue|), c)`; both existential-`c` forms say exactly
`a ⊇ {pMinValue, pRegion, pTitle}`, which is what the constraint they sit beside says).
`cutoffGroupedFldsPosNegRel'` loses its five (three permuted duplicates, `i <- (i)` and `d <- (d)`)
and reaches a genuinely differently-shaped saturation of the same body.

**Semantically** — and this is the acceptance criterion, "nothing weaker or stronger".
`rowequiv.py` decides equivalence completely rather than syntactically.  A residual is
`exists E. G` over the universals; `Sat` decomposes per label (`Rowpartition/Basic.lean`
`sat_iff_forall_label`) and a row variable's membership bits at distinct labels are independent, so
`exists` distributes over labels and the residual IS the per-label Boolean function
`f(bits of the universal rows, which named label this is) = SAT(G at that label)`.  Each instance is
a handful of Booleans and is decided by DPLL; the whole function is 2–256 patterns per binding.

```
EQUIVALENT  21        (of 21 changed bindings)
```

with **zero** `AFTER-STRICTLY-WEAKER` and **zero** `AFTER-STRICTLY-STRONGER`.  The checker is
sanity-tested against hand-built pairs in both directions (a deleted `b <- ()` is reported
`AFTER-STRICTLY-STRONGER`, an added one `AFTER-STRICTLY-WEAKER`, a permuted copy plus a tautology
`EQUIVALENT`).

**What that tool does and does not decide** (review K-3 — this report's first version overstated it).
`rowequiv.py` is a complete decision of the **row-partition part** of the residual and of nothing
else.  The reviewer verified the completeness against brute-force enumeration (0 mismatches over
17,416 instances) and the per-label decomposition it rests on against honest finite-set semantics
(0 mismatches over 43,200 universal assignments) — but it **reads neither the body nor the class
constraints**, and he built pairs where it therefore answers `EQUIVALENT` for a strictly weaker
signature (a class constraint deleted) and for a different type (the body changed).  So "nothing
weaker, nothing stronger" rests on three things together: `rowequiv.py` for the partitions of all 21,
`s3check3.py` for the bodies and `forall` binders of the 19 it explains syntactically, and the
class-constraint multiset check below.  The two bindings `s3check3.py` cannot explain are exactly the
ones where only `rowequiv.py` applied — and the reviewer closed that gap mechanically with an
independent CNF+DPLL checker (`indep.py`, no shared code) that compares bodies, `forall` binders,
class-constraint multisets and per-interface binding sets as well as the partitions: **21 of 21
EQUIVALENT, 0 weaker, 0 stronger, on his sweep and on mine.**

The class-constraint multiset (existential heads anonymised) is unchanged in all 21.

**A1's thirty movers.**  See §7.

**What is left.**  After the fix the ONLY bindings in the whole 2,946-binding sweep that still
publish a permuted duplicate or an `a <- (a)` are **21 hand-written signatures in the five
`Signatures.e` proof files** — `melt3Full`, `runningTotalFull`, `safeDivFull`, `band3Full`,
`valueAsOfFormA`, `topRowsByFull`, … — which carry the noisy sets *deliberately, verbatim*, as the
thing they prove redundant.  Every INFERRED residual in the corpus is now free of both.  That is
also the answer to the brief's question "is any of `Signatures.e`'s hand-deduplication now done by
the compiler?": **not for the declared signatures** (a declared type is published as written and does
not pass through `mkSimplified`, so those files' `xDeduped = xFull` proofs are untouched and still
check), **but yes for the residual the compiler infers for the same bodies** — §6.

## 5. Why the row trace is NOT byte-identical, and what is

The brief's premise was "`mkSimplified` is post-loop, so the trace cannot move".  Post-loop for ONE
binding, yes; but its output is an input twice over:

1. `mkSimplified` **runs a solve itself** — `RowTrace.withSite("mkSimplified-extinct")(solve(Exists(l, List(), extinct)))`
   (`Subst.scala:1670`), the guard that keeps an unsatisfiable dropped set failing.  A deleted
   duplicate or tautology can be in `extinct`, so that solve's input changes.
2. The published residual is **instantiated at every later use** of the binding.  Deleting `h <- (h)`
   from a signature deletes it from the constraint set every call site solves, and shifts the `Supply`.

Measured on `boot` (the stdlib, 54,199 solves), with the snapshot path prefix and the one wall-clock
field of the `rsound ok` record (`dt/1000`, microseconds) normalised away:

```
  segments 54199/54199 ; DIFFERING 26 (0.048%)
     A carries a TAUTOLOGY the after side does not   18
     A carries a DUPLICATE the after side does not    4
     same constraint COUNT and shape: ids shifted     4
```

and the record totals move only where they should: `scon` 1,999 → 1,975, `svar` 1,731 → 1,721,
`in` 748 → 724, while `learn`, `step`, `sat`, `splice`, `inpart`, `ex`, `slbl` are **identical**.
The first differing segment is `Relation/Op.e`, where the before side's input carries
`part v111545|v111545` — `c <- (c)` — and the after side's does not.

On `Wide` the first divergence is the same segment (the group loads the same stdlib), after which
the `Supply` has shifted and pairing segments by index stops meaning anything: 41,168 of 115,864
index-pairs differ, 36,035 of them with the same constraint count and shape.  Segment counts per
site are identical on both sides (707 `inferImplicitBindingTypes`, 78,153 `mkSimplified-extinct`,
37,004 `trySolveOn`).  The `learn` record count rises 36,666 → 66,447, all of it at `trySolveOn`;
wall clock went the other way (§3), so this is queue bookkeeping under a shifted id supply, not work.

**What IS invariant, and is the property that matters:** the loop model reproduces the compiler
solve for solve on BOTH sides — 54,199/54,199 and 115,864/115,864 agree, 0 skips, and
`TestLoopTrace` 714/714.  No rule, no dequeue order and no refutation changed; only what is handed
to the loop did.

## 6. The E-series signatures, before and after

Re-inferred by loading each body **unannotated** in a scratch module with the same imports as the
`Signatures.e` file that records it (`tmp/S3/probe/*.e`; `core/examples/**` was not touched).

| helper | recorded in | inferred BEFORE | inferred AFTER | equivalent? | `Signatures.e` still checks |
|---|---|---|---|---|---|
| `melt3` | `Wide/Signatures.e` (`melt3Full`) | 20 partitions, 19 existentials | **19** (1 permuted pair deleted) | EQUIVALENT (7 universals × 128 patterns) | yes, 0 errors |
| `runningTotal` | `Algebra/Signatures.e` (`runningTotalFull`) | 20 partitions, **27 existentials** | **19** (2 pairs) | EQUIVALENT (5 universals × 32 patterns) | yes, 0 errors |
| `safeDiv` | `Time/Signatures.e` (`safeDivFull`) | **5** | **3** (2 pairs) | EQUIVALENT (3 universals × 8 patterns) | yes, 0 errors |

`safeDiv` reproduces `E3-EXAMPLES.md`'s table exactly — 5 → 3, two permuted pairs — and the three
constraints the compiler now publishes are `Time.Signatures.safeDivDeduped`'s three, which that file
proves equivalent by hand.  **The compiler now does that hand-deduplication itself.**

`runningTotal`'s after set carries one constraint the before set does not (`e <- (f1, f, e1, d1, so)`),
which is ENTAILED by three constraints both sides carry: `e <- (o, l, f1, so, d1)`, `h <- (o, l)` and
`h <- (e1, f)` give `o ⊎ l = h = e1 ⊎ f`, hence `e = e1 ⊎ f ⊎ f1 ⊎ so ⊎ d1`.  That is `A1-REVIEW.md`
§4b's `valueAsOf` pattern again, and `rowequiv.py` confirms the two are equivalent.

**Two corrections to the E-series memos**, found by the duplicate scanner and worth carrying:

* `E1-EXAMPLES.md` N-11 and `Wide/Signatures.e` say `melt3Full`'s twenty-two carry **two**
  order-permuted duplicate pairs.  There are **three**: besides `r22 <- (ro2,rs2)`/`r22 <- (rs2,ro2)`
  and `r23 <- (rs1,ro1)`/`r23 <- (ro1,rs1)`, the set also holds `r21 <- (ro,rs)` and
  `r21 <- (rs,ro)` — and that third pair survives into `melt3Deduped`, so the hand-deduplicated
  twenty is **nineteen** by the rule the compiler now applies.
* `Time/Signatures.e`'s `nearestByFull` carries two permuted pairs AND two tautologies (13 items),
  and `incomplete/Signatures.e`'s `valueAsOfFormA` two pairs and a tautology.  Those files are
  correct as proofs; the counts in their prose are the recorded inferred sets, not minimal ones.

## 7. A1's thirty movers

The brief asks whether the count of A1's thirty movers drops.  Measured by re-running A1's own
configuration flip — `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` (the pre-adoption
settings, still reachable as flags) against the shipped defaults — on BOTH compilers, over the same
frozen 174-file corpus:

| | interfaces | bindings | bindings the flip moves |
|---|---|---|---|
| **before** S3 | 240 (one chunk timed out, see below) | 2,941 | **45** |
| **after** S3 | 242 | 2,946 | **45** (44 on the 2,941 both sweeps share) |

**The count does not drop, and it should not have been expected to.**  A1's thirty were counted over
1,921 bindings; this corpus has 2,946, and what a dequeue-order flip moves is dominated by
alpha-renaming and print order — neither of which S3 touches.  What S3 changes is not how many
bindings move but **why one of them was misclassified**: `A1-REVIEW.md` §R-1's finding was that
`np01.inferredRestate` was called "a different saturated set" only because the old side's two
verbatim permuted duplicates were counted.  At the fixed compiler that side publishes **7**, not 8 or
9 (measured: OLD-config/pre-fix 8, OLD-config/post-fix 7, NEW-config 7 on both), so the manual
de-duplication R-1 had to perform is now done by the compiler and the classifier no longer needs it.

**Two findings fall out of this comparison and are worth carrying.**

* **`A1-REVIEW.md` §R-6 is CONFIRMED mechanically.**  Of the 45 bindings the flip moves at the fixed
  compiler, `rowequiv.py` reports 44 EQUIVALENT and exactly one **`AFTER-STRICTLY-WEAKER`**:
  `incomplete/RevenueShare.shareOfGroup`, "10 patterns gained" — the new defaults publish a strictly
  MORE GENERAL residual, which is what R-6 established by hand (`OLD |= NEW`, `NEW |/= OLD`) and
  which `Signatures.shareOfGroupFull` certifies.  This is an independent complete decision, not an
  eyeball.  (In the pre-fix run that binding is absent, see the next bullet, which is why the pre-fix
  column reports 45 EQUIVALENT.)
* **An asymmetry at the OLD configuration that does NOT survive its control — recorded so nobody
  re-finds it and believes it.**  Under `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` the
  sweep's `incomplete/` chunk (ten modules, `np02`…`np05`, `.probeC`, `RevenueShare`) hit the 600 s
  chunk timeout on the pre-fix compiler and finished in 14 s on the fixed one — which is why the
  pre-fix sweep captured 240 interfaces and the post-fix one 242, and why `shareOfGroup` is absent
  from the pre-fix column above.  **Re-run in isolation with every `.ei` deleted, BOTH compilers time
  out identically** (900 s, 5 of the 10 modules imported).  So the sweep asymmetry is a property of
  the interface state the earlier chunks left behind, or of dequeue-order luck at a non-default
  configuration, and **is not evidence that S3 removes a divergence.**  No claim is made from it.

## 8. The entailment-equivalence argument

**The claim.**  `mkSimplified` publishes a residual `R`.  The change alters `R` in exactly two ways,
and each is a deletion of a member `c` such that `R \ {c} ⊨ c`.  Therefore `R` and `R \ {c}` entail
one another — `R ⊨ R \ {c}` because it is a subset, and `R \ {c} ⊨ R` because the only member not
trivially there is `c` — and the published signature is unchanged in meaning.

**(i) The permuted duplicate.**  `distinct` deletes `c₂` only when an EARLIER `c₁` satisfies
`NormalPart.equals`, which is: the same left-hand variable (by `id`), the same concrete field set,
and the same MULTISET of abstract part ids.  `NormalPart.part` rebuilds
`Part(loc, VarT(left), ConcreteRho(loc, concrete) :: abstrakt.map(VarT))`, so `c₁` and `c₂` can
differ ONLY in `loc` and in the ORDER of the parts in the `rhs` list.  `loc` is a source position
and carries no semantic content.  Permuting the parts is invisible to satisfaction: `Sat` is "the
left row is the union of the parts AND the parts are pairwise disjoint", and both a `foldr` union
and `Pairwise Disjoint` (over a symmetric relation) are permutation-invariant.  Hence
`{c₁} ⊨ c₂`, and `c₁` survives in `R \ {c₂}`.  In the model this is not even a lemma about a rule:
`Rowpartition.mk` takes a `Finset`, so `mk a {x,y,z} K = mk a {z,x,y} K` is an equation.

**(ii) The tautology.**  The new case fires only on `Part(loc, VarT(v), rs)` where the accumulated
concrete part is EMPTY and the variable parts are exactly `List(v)` — i.e. `v <- (v)`.  Its `parts`
are `∅ :: [rho v]`, whose union is `rho v` and whose `Pairwise Disjoint` obligation is
`Disjoint ∅ (rho v)` plus a one-element tail.  Both hold for EVERY assignment, so `∅ ⊨ v <- (v)`,
a fortiori `R \ {c} ⊨ c`.

**Four side conditions, checked in the code or measured rather than assumed.**

* `mkSimplified` runs `solve` on the constraints it drops as isolated, "to ensure failure for
  unsatisfiable sets", and both new deletions bypass that.  Neither can hide a refutation: the
  duplicate's surviving copy has the SAME variables, so it lands on the same side of the
  `dumb`/`extinct` partition and is still solved; and `S ∪ {v <- (v)}` has exactly the models of `S`,
  so it is unsatisfiable iff `S` is.
* The deletions cannot change WHICH OTHER constraints are dropped.  `iso = isolated(exts.toSet, ps)`
  is computed from the full `ps` BEFORE `normalPart` runs, and the existential binder list is
  `exts filterNot (v => iso(v) || am(v))` — neither depends on the deletions.
* No vacuous existential binder is left behind by (ii).  If `v` occurs only in `v <- (v)` and is
  existential then `isolated` never dirties it, so `iso(v)` holds, `v` is filtered out of the binder
  list and the constraint went to `extinct` anyway; the tautology can only SURVIVE to the published
  set when `v` is universal or occurs elsewhere.
* **Which `loc` survives — and it moves one user-visible message.**  This is `ROSE-COMPARISON.md`
  §3 rank 1's acceptance item (i), which the first version of this report did not address:
  `normal.distinct` keeps the FIRST occurrence, so collapsing more constraints changes which
  constraint's `loc` a blame message points at.  My corpus gate compared **exit codes only**.  The
  reviewer compared the `.out` **contents** (wall-clock normalised) and found exactly **one change in
  132 + 34 files** (review K-2):

  ```
  core/examples/Time/shouldfail/bucket01_calendar_overlaps_facts.e:77:7
    BEFORE  Row partitions are unsatisfiable at field '…Bucket01.region': the whole contains it but no part does
    AFTER   Row partitions are unsatisfiable at field '…Bucket01.region': a part contains it but the whole does not
  ```

  Same verdict, same position, same field — a different **clause** of the same refutation.  Two
  mitigations, both his and both measured: run **per file** the clause is identical on both sides, so
  this is the whole-corpus-batch configuration only; and the clause the fixed compiler prints is the
  one `bucket01`'s own header (line 30) and `E3-EXAMPLES.md:176` record first, so it moved TOWARD the
  recorded answer.  The clause is already documented as unstable across loading modes
  (`corpus-run.sh`'s header, `E2-REVIEW.md` §G1, `bucket01`'s own "AND THE CLAUSE IS NOT STABLE
  ACROSS LOADING MODES").  **Not a regression, but it is a user-visible change caused by S3 and it
  belongs here.**

**In Rose's terms** (`ROSE-COMPARISON.md` §1.1, §3): (i) is `∼simp`, which "identifies sequences up
to permutation" — Ermine honoured it in the solver (`RHS` is a `Set`) and violated it in the
published type; (ii) is the combination axiom of Figure 1 at `k = 0`, `∅ ⊎ ζ = ζ`, an instance
`⇒simp` proves outright because `ε` is the unit of the partial monoid.

### The Lean lemma

`tracker/loopmodel/S3Simplify.lean` — a SCRATCH file, deliberately outside `tracker/lean/`'s source
tree so that `lake build` and the `looptrace` binary other agents are running are untouched.  Check
it with

```
cd tracker/lean && lake env lean ../loopmodel/S3Simplify.lean
```

It elaborates clean in 2.0 s (one style hint, no error, no `sorry`, no `axiom`) and, in the
`SEntails`/`System` vocabulary of `Rowpartition/Divergence.lean`, proves — **eight declarations, not
the six the first version of this report and the plan row said** (review K-6):

| theorem | statement |
|---|---|
| `sat_congr_of_perm` | same lhs, same concrete part, `c.vars.Perm c'.vars` ⟹ `Sat rho c ↔ Sat rho c'` |
| `sEntails_of_perm` | a permuted duplicate is entailed by the copy that is kept |
| `sat_taut` | `∀ rho a, Sat rho ⟨a, [a], ∅⟩` — `a <- (a)` holds of every assignment |
| `sEntails_taut` | hence every system entails it, the empty one included |
| `erase_perm_dup_equiv` | `G` and `G.erase c'` entail each other when `c ∈ G`, `c ≠ c'` and they differ by a permutation |
| `erase_taut_equiv` | `G` and `G.erase (taut a)` entail each other, with NO hypothesis on `G` |
| `sEntails_of_mem_subset` | a subset is entailed by its superset, member by member — `Conserv`, in `Loop/Strict.lean`'s vocabulary |
| `SEquiv.sat_iff` | equivalent systems are satisfiable together — the side condition above |

```
'Rowpartition.S3.sat_congr_of_perm'    depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.S3.sEntails_of_perm'     depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.S3.sat_taut'             depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.S3.sEntails_taut'        depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.S3.sEntails_of_mem_subset' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.S3.erase_perm_dup_equiv' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.S3.erase_taut_equiv'     depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.S3.SEquiv.sat_iff'       depends on axioms: [propext, Classical.choice, Quot.sound]
```

(The file's `#print axioms` block was extended after the review, which had noticed that two of the
eight declarations were not printed and printed them itself; same three axioms.)

None of this is new mathematics — `Rowpartition/Canonical.lean` already implements both rules
(`Step.dedup`, "duplicate constraints, RECOGNISED UP TO PERMUTATION of the RHS", and `Step.occurs`,
which "also deletes the vacuous `r <- (r)`") and already proves `Step.preserves`.  As
ROSE-COMPARISON §3 put it: **the model was the specification here and the compiler was behind it.**
The reviewer's recommendation on where it should live: leave it as scratch beside this report, or —
if it is ever wanted under `lake build` — add it as `Rowpartition/Simplify.lean` deriving
`erase_perm_dup_equiv` / `erase_taut_equiv` as corollaries of `Canonical.Step.preserves` rather than
from scratch, so there is one proof of each rule and not two.  **Not** in `Loop/Strict.lean`:
nothing here is about the loop.

## 9. Reproducing this

Scratch, scripts and artefacts: `/home/dmitry/.claude/jobs/880c725d/tmp/S3/`.

| what | how |
|---|---|
| the diff | `S3.diff` |
| class snapshots | `snap-before/`, `snap-after/` (each with a `classpath` file; `run.sh <cp> <files…>` is `bin/ermine` pinned to one) |
| frozen corpus | `examples-frozen/` — a copy of `core/examples` taken before the runs, so that the two other agents editing `core/examples/Present` and `core/examples/Lang` during the window could not move the input |
| `.ei` sweep | `ei-sweep.sh <cp> <outdir>`; snapshots `ei-A` (before), `ei-B` (after), `ei-B2` (same-configuration control), `ei-OLDpre`/`ei-OLDpost` (§7) |
| duplicate/tautology scanner | `dupscan.py <ei-dir>` |
| syntactic acceptance | `s3check3.py <A> <B>` — "is AFTER exactly BEFORE minus duplicates and tautologies", with a colour-refinement search for the existential renaming |
| semantic acceptance | `rowequiv.py <A> <B>` — the complete per-label decision; `sanity/` holds the weaker/stronger/equivalent control pairs |
| trace segment classifier | `segclass.py <traceA> <traceB>` |
| corpus, probes, traces, Signatures | `side.sh before` / `side.sh after` |
| build + JVM gates | `build-and-test.sh` |
| Lean | `lean/S3Simplify.lean` (copied to `tracker/loopmodel/S3Simplify.lean`), `lean/check4.log` |

## 10. What could not be done

* **`perf-bench.sh` was not run BY ME — and has since been run.**  It refuses above load average 1.5
  and is "the measurement of record" only on a quiet machine; two other agents were running the whole
  time and the load sat between 3 and 7.  **The reviewer ran it on both sides at load ≈ 1.1: 12.04 s
  before, 12.05 s after, unmoved** (§3).  This item is CLOSED; the import-time proxy this report first
  quoted is retired in its favour (K-8).
* **The row trace is not byte-identical and cannot be** — §5 replaces that gate with the two things
  that ARE invariant (model agreement on every corpus segment, both sides; `TestLoopTrace` 714/714)
  and a classification of every structural difference in `boot`.  Past the first divergence the
  `Wide` comparison is dominated by `Supply` drift and is not informative segment by segment.
* **Two example files entered `core/examples/Present` between the before and after corpus runs**
  (E4's `ProjectionCost.e` and `shouldfail/proj01_seven_reads.e`), so the after run reports 132 files
  and 70/62 where the before run reports 130 and 69/61.  The comparison in §3 is over the 130 files
  common to both, where nothing moves.  The `.ei` sweep is immune: it ran against a frozen copy.
* **Another agent's `sbt` run compiled this uncommitted change into the live
  `core/target/scala-3.3.8/classes` at 03:30**, before I ran `sbt core/compile` myself (which then
  correctly found nothing to do).  So from 03:30 onwards any measurement the other agents took
  against the live classes was taken with S3 in place.  Everything in this report is pinned to a
  class snapshot and is unaffected.  The live tree is left consistent (source and classes both
  carrying the fix) and every `.ei` cache — 154 stdlib and all example interfaces — was deleted, so
  no stale pre-fix interface survives.
* **The third sibling is not fixed**, in either reading (§2).  Both are separate stages, and one of
  them (entailment-based pruning) is ROSE-COMPARISON's rank 3.  The review sizes them: `Part.apply`
  is one stage whose cost is entirely the acceptance criterion (a fresh L2 differential over every
  group, plus a decision about what `taut`/`tautIsFree` then mean), and it is now **two** repairs
  rather than one (K-1); entailment pruning is 1–2 stages and needs a decision procedure inside the
  compiler, whose worst case is exponential in the existentials — `cutoffGroupedFldsPosNegRel'`
  already has 40.
* **§7's independent confirmation of `A1-REVIEW.md` §R-6 rests on `rowequiv.py` alone**, so K-3
  applies to it: what is decided there is the row-partition part of `shareOfGroup`'s two residuals,
  not their bodies or class constraints.  The reviewer did not re-run the movers sweep (the brief did
  not ask for it), so that one number is the only load-bearing claim in this report that has not been
  reproduced by a second party.
* **No commit was made**, per the brief.

---

## 11. Post-review corrections, 2026-09-07

`tracker/loopmodel/S3-REVIEW.md` (557 lines, findings K-1…K-9) returns **ADVANCE (commit) after
documentation corrections**.  It found **no defect in the change**: both compilers were rebuilt in a
throwaway worktree, every gate re-run, the whole corpus re-swept at the reviewed commit, and
entailment-equivalence re-decided with an independent CNF+DPLL checker — **21 of 21 EQUIVALENT, 0
weaker, 0 stronger** — and every load-bearing number above reproduces to the digit.  What follows is
what changed in the prose, old → new.  Nothing in `Subst.scala` was touched.

| # | old | new | where |
|---|---|---|---|
| **K-1** | "`Type.scala:414` collapses the concrete identity … to `Exists(l)`", so at `Part.apply` the concrete case is handled and only the variable case is missing | The guard is `ss == cs` with `ss : List[Name]` and `cs : Set[Name]`, always false at Scala 3.3.8 — the case is **dead code**, at `Part.apply` **NEITHER** case is handled, and the repair is two changes, the concrete one being the single word `ss.toSet == cs` | §2 here, **and `ROSE-COMPARISON.md` §3 rank 1 item 3**, which asserted the same thing and now carries the correction inline |
| **K-2** | the corpus gate is "0 verdict changes"; ROSE-COMPARISON's acceptance item (i) about which `loc` survives is not addressed | the gate compared **exit codes only**; a content comparison finds **one refutation CLAUSE moves** (`Time/shouldfail/bucket01…:77:7`, same verdict/position/field, per-file identical both sides, and toward the clause the module's own header records) | §3's corpus row and a fourth bullet in §8's side-condition list |
| **K-3** | "all 21 proved ENTAILMENT-EQUIVALENT by a complete per-label decision (`rowequiv.py`)" | `rowequiv.py` decides the **row-partition part** completely and reads neither the body nor the class constraints; the claim rests on it together with `s3check3.py` (bodies, binders) and the class-multiset check, and the reviewer's `indep.py` closes all four for all 21 | §4 |
| **K-4** | "the last four are propagation" | **two** are propagation (`reportFor`, `cutoffGroupedFldsPosNegRel'`); the other two (`asDocument`, `asProfiledDocument`) are the print order of a three-element `Set[Name]` | §4 |
| **K-5** | 174 files / 242 interfaces / 2,946 bindings, stated without qualification | that is the frozen copy taken before two `Present/` files landed; **at the reviewed commit the same sweep is 176 / 243 / 2,966**, with the same 21 bindings, and the `Lang/` group adds none | §3 |
| **K-6** | "six theorems" | **eight declarations**, all on the three standard axioms; `sEntails_of_mem_subset` was missing from the table and two were not printed — the two `#print axioms` lines are now in `S3Simplify.lean` and re-run | §8, the Lean file, the plan row |
| **K-7** | `TestLoopTrace` 714/714 quoted flat | it **passes vacuously where the Lean model binary is absent** and still reports `Passed: Total 3`; the 714/714 was taken in the main checkout, and the reviewer re-ran it with `-Dermine.looptrace` on both sides | §3 |
| **K-8** | "corpus import-time proxy 23.7 s → 21.9 s (92 %)" | **`perf-bench.sh batch -n 3` on a quiet machine, 12.04 s → 12.05 s, unmoved** (reviewer); the proxy re-measured is 21.40 s → 20.99 s (98.1 %). The 92 % is withdrawn | §3, §10 |
| **K-9** | "three row constraints become one" | that is the **virgin-load** figure; in the interface-carrying sweep the same binding is 3 → 2 | §1 |
| — | `perf-bench.sh` listed under "what could not be done" | it has since been run, by the reviewer, on both sides: item CLOSED | §10 |
| — | §7's confirmation of `A1-REVIEW.md` §R-6 | flagged as resting on `rowequiv.py` alone, so K-3 applies to it and it is the one load-bearing number here not reproduced by a second party | §10 |

### The example-corpus comments that described a defect the compiler no longer has

The review's §9 table lists every comment in `core/examples/**` that quotes an inferred residual S3
changes.  All of them are updated, each saying what the compiler inferred BEFORE S3 and what it
infers now; **no signature, no proof and no body was changed**, because a DECLARED signature is
published verbatim and does not pass through `mkSimplified`.  The post-S3 figures below were
re-measured against the fixed compiler, one body per scratch module (`tmp/S3/probe3/`), except
`safeDiv`'s five-to-three and `melt3`/`runningTotal`, which are §6's dedicated probes.

| file | what it now says |
|---|---|
| `Wide/Signatures.e` (header point 3, and above `melt3Deduped`) | `melt3Full` carries **three** permuted pairs, not two, so the minimal set is **nineteen** and the third pair survives into `melt3Deduped`; and the compiler now does the deletion itself, 20 → 19 |
| `Algebra/Signatures.e` (header, `antiJoin`, `runningTotal`) | `antiJoin` 3 partitions → **2**, i.e. the compiler now infers `antiJoinDeduped`; `runningTotal` twenty-one → **twenty** |
| `Time/Signatures.e` (header, and seven definitions) | `orZero` 1 → **0**, `yearFrac365` 1 → **0**, `band3` 1 → **0**, `band4` 1 → **0**, `pctChange` 5 → **4**, `safeDiv` 5 → **3** (= `safeDivDeduped`, the sharpest case), `shiftBy` 7 → **6**, `nearestBy` 10 → **7**, `movingAgg` unchanged |
| `incomplete/Signatures.e` (header, `valueAsOfFormA`, `shareOfGroupFull`, `topRowsByFull`) | which member each set loses, and that the compiler now produces `topRowsByDeduped`'s signature itself |
| `incomplete/TopReadings.e` | rewritten "WHAT USED TO HAPPEN, AND WHAT S3 FIXED", with the exact `:type topRowsBy` output before (`b <- (h, c), h <- (h), b <- (c, h)`) and after (`b <- (c, h)`) under the header's own recipe, and what remains incomplete |
| `incomplete/RunCalibration.e` | a new closing block: Form A loses three of its fifteen (its tautology and both permuted pairs), Form B loses its tautology, `lookbackJoin` loses three; re-measured under the header's recipe, `valueAsOf` **10 → 9** and `lookbackJoin` **10 → 9** on a Form-B run; the OTHER two complaints (entailed-but-not-duplicate members, run-to-run instability) stand |
| `Time/Helpers.e` (4 places) | the `if`-lattice measurement is now stronger — `safeDiv` costs three constraints and `band3`/`band4` none at all; `pctChange` and `orZero` lose their tautology |
| `Present/Signatures.e` | **already correct** — E4 wrote the S3 block during this stage.  Whoever commits should replace its "(uncommitted)" and "compiled in at 03:56 on 2026-09-07" with the commit hash. |

**All five `Signatures.e` still check after the edits**, together with the two `incomplete/` query
files and `Time/Helpers.e`: eleven modules in one JVM against the fixed compiler with
`-Dermine.useInterface=false`, **0 errors**.

**Still open after the review**, and not addressed here: the two pre-solver repairs at `Part.apply`
(one stage, whose cost is the acceptance criterion — a fresh L2 differential over every group and a
decision about what `taut`/`tautIsFree` then mean); entailment pruning between surviving partitions
(ROSE-COMPARISON rank 3, 1–2 stages, and its decision procedure is exponential in the existentials in
the worst case — `cutoffGroupedFldsPosNegRel'` already has 40); and, on the reviewer's
recommendation, whether `S3Simplify.lean` should stay scratch or become `Rowpartition/Simplify.lean`
deriving its two erase lemmas from `Canonical.Step.preserves` rather than from scratch.
