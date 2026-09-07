# S3 review — the `Subst.mkSimplified` omissions, re-run from scratch

Reviewer agent, 2026-09-07, against `scala3-migration` at `0741fb2` **with the S3 change
uncommitted in the working tree** (see K-0).  HEAD moved to `3b5ad49` (E5's `core/examples/Lang`)
while I was measuring; the S3 diff is byte-identical throughout, and I swept the new group
separately (§9a).  Brief `briefs/brief-S3.md`, implementer report
`S3-SIMPLIFY.md`, scratch `/home/dmitry/.claude/jobs/880c725d/tmp/review-S3/`.

## VERDICT: **ADVANCE (commit)**, with the documentation corrections below applied first

The change is +13 −1 in one file and it does exactly what it claims.  I rebuilt both compilers
myself in a throwaway worktree, re-ran every gate, re-swept the whole example corpus, and decided
entailment-equivalence with a checker I wrote from the Lean model rather than reusing the
implementer's.  **Every load-bearing number in `S3-SIMPLIFY.md` reproduces to the digit** — the
21 changed bindings and their names, the 10/15 duplicate/tautology split, the 26 of 54,199 boot
segments and their 18/4/4 classification, `scon` 1999→1975 / `svar` 1731→1721 / `in` 748→724,
714/714, 913/914, the byte-identical same-configuration control, `safeDiv` 5→3, `melt3` 20→19,
`runningTotal` 20→19.  Nothing is weaker, nothing is stronger, and I could not construct an
input that makes the deletions unsound.

Nothing found is a defect *in the change*.  The findings are (a) one wrong statement of fact
about neighbouring code that both `S3-SIMPLIFY.md` §2 and `ROSE-COMPARISON.md` §3 rank 1 make
(K-1), (b) one user-visible message change the report does not mention and the origin document
explicitly asked to watch (K-2), and (c) three places where the report's numbers or wording
overstate what was measured (K-3, K-4, K-8).  Fix the prose, then commit.

`perf-bench.sh`, which the implementer could not run, I ran on a quiet machine on both sides:
**12.04 s before, 12.05 s after** — unmoved.

---

## 1. What I re-ran, and how

| step | how |
|---|---|
| both compilers | `git worktree add … --detach 0741fb2` → `sbt core/compile` → class snapshot (**before**); `git apply` the working-tree diff → recompile → snapshot (**after**).  `diff -rq` between the snapshots: **only the 9 `Subst.scala`-derived class/tasty files differ**, every other module byte-identical. |
| corpus | `core/examples` **from the committed worktree** — 176 `.e` files excluding `Lang/` (which is uncommitted), frozen into scratch.  Identical input on both sides. |
| `.ei` sweep | my own script, chunks of 10 with each group's library hoisted, `-Dermine.loadInSeries=true`, interfaces ON, every `.ei` deleted first — **243 interfaces / 2,966 bindings**. |
| equivalence | `indep.py`, written from `Rowpartition/Basic.lean`: a **CNF encoding + textbook DPLL**, a deliberately different formulation from `rowequiv.py`'s hand-written propagator, and it also compares the **body**, the **`forall` binders**, the **class-constraint multiset** and the **per-interface binding sets**, none of which `rowequiv.py` looks at. |
| verdicts | `corpus-run.sh --batch` and `--incomplete --batch` from an isolated copy of the tree, `ERMINE_CP` pinned to each snapshot — and I compared the `.out` **contents** (modulo wall-clock), not only the exit codes. |
| loop | `TestLoopTrace` with `-Dermine.looptrace` pointed at the built model binary, **on both sides**; plus a full `boot` row trace on both sides and a `looptrace --replay` model differential on each. |
| Lean | `lake env lean` on `S3Simplify.lean` plus my own `#print axioms` for the two declarations the file does not print, a non-vacuity example and a negative control. |
| perf | `perf-bench.sh batch -n 3` on both sides, each started at 1-minute load ≈ 1.1. |

Every `.ei` I caused is inside my scratch copies; the live tree was not written to.

## 2. The change, read line by line

```scala
override def equals(a: Any) = a match {
  case NormalPart(_, l, c, a) => l == left && c == concrete &&
    a.sortWith(_.id < _.id) == abstrakt.sortWith(_.id < _.id)
  case _ => false                                              // added
}
override def hashCode: Int = (left.id, concrete, abstrakt.map(_.id).sorted).hashCode   // added
```

* **`hashCode` agrees with `equals` exactly, not merely conservatively.**  `V` is
  `case class V[+A](loc, id: Int, name, ty, extract)` with `override def equals` = `id == oid`
  and `override def hashCode = id.hashCode` (`Vars.scala:100-110`).  So `equals` on `NormalPart`
  is precisely equality of `(left.id, concrete, sorted ids of abstrakt)` — `sortWith(_.id < _.id)`
  followed by element-wise id equality *is* comparison of the sorted id lists — and that is
  precisely the triple the new `hashCode` hashes.  It reads every field `equals` reads and no
  other: `loc` is read by neither.  `ROSE-COMPARISON`'s suggested
  `(left, concrete, abstrakt.map(_.id).sorted).hashCode` computes the same value, since
  `left.hashCode == left.id.hashCode`.  ✔
* **`case _ => false` is right for the `MatchError` it replaces.**  Nothing that is not a
  `NormalPart` can be equal to one, and `null` now answers `false` instead of throwing.  On the
  path that exists it is unreachable — `normal` is the `Left` half of a
  `List[Either[NormalPart,Type]]` partitioned on `_.isRight`, so `distinct`'s `HashSet` only ever
  compares `Left(NormalPart)` with `Left(NormalPart)` — so this is hardening, exactly as
  `ROSE-COMPARISON` §3 rank 1 risk (ii) asked.  (Small imprecision in the report: `Left`'s
  `hashCode` is `MurmurHash3.productHash`, a *function of* the payload's hash, not literally the
  payload's; the bucketing argument is unaffected.)
* **The tautology case fires on exactly `a <- (a)` and nothing else.**  It requires `l` to be
  `VarT(v)`, the accumulated concrete set `cs` to be empty, and the accumulated variable list to
  be exactly `List(v)`.  Answering the brief's three probes:
  * `a <- (a, (||))` — **fires, and correctly**: `ConcreteRho(_, Set())` contributes nothing to
    `cs`, so `cs` is still empty and `vs == List(a)`.  `∅ ⊎ ρa = ρa` with `Disjoint ∅ (ρa)`, a
    tautology.
  * `C <- ((|C|))` (the concrete identity) — **already handled**, by the pre-existing
    `case ConcreteRho(loc, s) => if(vs.isEmpty && cs == s) None` immediately above; `cs` and `s`
    are both `Set[Name]` there, so that comparison is real.  (Contrast K-1.)
  * `a <- (a, (|C|))` with `C` non-empty, `a <- (a, b)`, `a <- (a, a)` — **do not fire, and must
    not**: the first forces `C = ∅` (a refutation, not a tautology), the second forces `b = ∅`,
    the third `a = ∅`.  The guard is exactly tight.
* **The three side conditions in §8 of the report check out in the code.**  `iso` is computed
  from the full `ps` *before* `normalPart` runs, so neither deletion can change which constraints
  are pruned as isolated.  A deleted duplicate's surviving twin has the same variable set, so it
  lands on the same side of the `dumb`/`extinct` split and the `mkSimplified-extinct` solve still
  sees it.  A tautology's models are everything, so `S ∪ {v <- (v)}` is unsatisfiable iff `S` is;
  and if `v` occurs nowhere else and is existential then `isolated` never dirties it, so it was
  already filtered out of the binder list.  I checked each by reading `Subst.scala:1631-1694`.

## 3. Reproduction (brief item 1) — reproduced

Virgin `.ei`, both modules in one JVM, `-Dermine.loadInSeries=true`, my own snapshots.

```
topRowsBy   BEFORE  (exists (c: rho). b <- (c, h), h <- (h), b <- (h, c), RelationalComb a)
            AFTER   (exists (c: rho). b <- (h, c), RelationalComb a)
```
Three row constraints → one, and that one is `Has b h`.  The tautology and the permuted pair both
go.  ✔ exactly `S3-SIMPLIFY.md` §1(a).

```
inferredRestate  BEFORE  9 constraints (8 partitions + RelationalComb), 7 existentials
                 AFTER   7 constraints (6 partitions + RelationalComb), 6 existentials
```
✔ exactly §1(b), including the `9 → 7` that `A1-REVIEW.md` §R-1 reached by hand.  Both pairs are
`EQUIVALENT` under my checker **and** under `rowequiv.py`.

One nuance worth recording (K-9): in the **sweep** the pre-fix `topRowsBy` carries only
`b <- (c, h), h <- (h)` — no permuted duplicate — because the module is loaded against interfaces
earlier chunks wrote.  "Three row constraints become one" is the virgin-load figure; in the sweep
the same binding goes 3 constraints → 2.  Both are pre-fix states and the fix cleans both.

## 4. Gates (brief item 2) — every one reproduced

| gate | implementer | reviewer | |
|---|---|---|---|
| `core/test` | 914 / 913 / 1 | **Total 914, Passed 913, Failed 1** — `! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded` | ✔ same |
| `TestLoopTrace` | 714/714 (after only) | **714 solves; 714 segments; 714 agree**, `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls **46** and **58** of 714 — **on BOTH sides** | ✔ stronger |
| `looptrace --replay`, `boot` | 54,199/54,199 both sides | **AGREE=54199 SKIP=0 on both sides** (my own traces, my own replay) | ✔ same |
| `corpus-run.sh --batch` | 0 verdict changes over 130 | **132 files, verdicts identical**; **1 of 132 `.out` files differs in content** — see **K-2** | ✔ verdicts; ⚠ messages |
| `corpus-run.sh --incomplete --batch` | 0 of 34 | **34 files, verdicts identical, 0 of 34 `.out` differ** (after normalising wall-clock) | ✔ same |
| `.ei` sweep | 242 int / 2,946 bindings, 21 change in 10 | **243 int / 2,966 bindings, 21 change in 10 — the same ten interfaces and the same twenty-one binding names** | ✔ same (corpus differs, see K-5) |
| same-configuration control | 0 of 242 | **`ei-after` vs a fresh re-run: byte-identical, 0 of 243** | ✔ same |
| five `Signatures.e` check | 0 errors | **0 errors, all five, on BOTH sides** | ✔ stronger |
| `perf-bench.sh batch -n 3` | not run | **before 12.04 s, after 12.05 s** cold in-process median, spreads 0.37 / 0.16, both started at load ≈ 1.1 | ✔ **unmoved** |

`s3check3.py` on my sweep, digit for digit:

```
bindings compared 2966 ; CHANGED 21
  EXPLAINED as exactly 'BEFORE minus permuted-duplicates minus tautologies': 19 (3 needed a renaming)
  duplicate copies deleted 10 ; tautologies deleted 15
  NOT EXPLAINED: 2      (Present.WriterOutputs.reportFor, Layout.Report.Relation.cutoffGroupedFldsPosNegRel')
```
and every row of the report's §4 per-binding table (3→2, 7→6, 9→8, 6→5, 8→6, 8→6, 6→5, 2→1, 2→1,
10→9, 4→3, 4→3, 2→1, 6→5, 2→1, 2→1, 8→6, 44→39) is what I measure.

`dupscan.py` before → after: bindings carrying a permuted/exact duplicate **16 → 10** (deletable
copies **30 → 20**), bindings carrying a tautology **28 → 14** (copies **30 → 15**), bindings
affected at all **39 → 21**.  The report's headline claim holds and I can sharpen it:
**after the fix, no INFERRED residual anywhere in the corpus publishes a duplicate or a
tautology.**  The 21 that remain are all hand-written declarations in the five `*/Signatures.e`
proof files — and there are in fact **24**, because `dupscan.py`'s parser silently drops a
single unparenthesised constraint and so misses `taut : r <- (r) => …` in
`Time`/`Present`/`incomplete` `Signatures.e`.  All 24 are declared, so the conclusion is
unchanged.

## 5. The entailment-equivalence audit (brief item 2, the load-bearing claim)

**Result: 21 of 21 EQUIVALENT, 0 weaker, 0 stronger, 0 incomparable, 0 errors — under a checker
that does not share a line of code with `rowequiv.py`.**  Same 21 on the implementer's `ei-A`/`ei-B`
and on my own `ei-before`/`ei-after`.  Sizes: `|U|` 1–8 (so the `>14` bail-out never fires), `|E|`
0–40, 2–256 patterns per binding.  My checker additionally confirms, for all 21: identical
`forall` binder lists, **identical bodies**, **identical class-constraint multisets**, and
identical per-interface **binding sets** (no binding appears or disappears).

### Is `rowequiv.py` right?

**The encoding.**  A residual is `forall U. exists E. G`.  `Sat rho c` is
`rho c.lhs = ⋃ parts ∧ Pairwise Disjoint parts` (`Rowpartition/Basic.lean:56-61`), and both
conjuncts are per-label, so at a label the constraint is `bit(lhs) = OR bits(parts)` **and** at
most one part bit is 1.  That is exactly what `sat_at`'s propagator enforces.  A label enters only
through which concrete sets contain it — its *atom* — so enumerating a representative per atom is
complete; `rowequiv.py` enumerates every named label plus one fresh, which covers every realised
atom (redundantly, harmlessly).  I enumerate one per atom.  The interchange
`exists E. forall l. G_l ⟺ forall l. exists bits_E(l). G_l` is sound because at a label where every
universal and concrete bit is 0 the all-zero assignment satisfies `G`, and all but finitely many
labels are of that kind, so the per-label witnesses assemble into *finite* rows.

**Three tests, all mine.**

1. `rowequiv.sat_at` vs brute-force enumeration of every existential assignment, on 600 random
   partition systems: **0 mismatches over 17,416 instances**.  It is a **complete decision**, not a
   propagation.
2. My independent CNF+DPLL vs the same brute force: **0 mismatches over 400 random systems**.
3. The per-label decomposition itself — the theory both checkers rest on — against honest
   finite-set semantics (universals and existentials ranging over real subsets of a 4-label
   universe, satisfaction checked as set union and disjointness): **0 mismatches over 43,200
   universal assignments across 300 random systems**.

**Two inputs that WOULD mis-classify it** (brief: "try to construct a binding it would
mis-classify") — constructed, run, confirmed:

| constructed pair | `rowequiv.py` says | truth |
|---|---|---|
| `(exists c. a <- ((\|Foo\|), c), RelationalComb c) => Int` → `(exists c. a <- ((\|Foo\|), c)) => Int` | **EQUIVALENT** | strictly weaker — a **class constraint** was deleted, which `rowequiv.py` never reads |
| `… => Int -> Int` → `… => Int` | **EQUIVALENT** | different type — the **body** changed, which `rowequiv.py` never reads |

A third hazard, a rho-kinded `forall` binder printed without its `(x: rho)` annotation, would be
silently demoted to an existential; I scanned all 2,946 bindings and **0** occur.  I also scanned
for an existential shadowing a universal name (**0**).  166 bindings do mention a row variable
bound nowhere — that is the pre-existing `.ei` printer defect already tracked as
`TICKET-stdlib-findings` B7, treating them as existential is the intended reading, and **none of
the 21** is among them.

So: the *conclusion* "nothing weaker, nothing stronger" is correct and now doubly established,
but it does not follow from `rowequiv.py` alone — see **K-3**.

## 6. The row-trace claim (brief item 3) — reproduced exactly

My own `boot` traces, both sides, path prefix and the `rsound` microsecond field normalised away:

```
segments  54199 / 54199
DIFFERING 26  (0.0480 %)
   A carries a TAUTOLOGY the after side does not   18
   A carries a DUPLICATE the after side does not    4
   same constraint COUNT and shape: ids shifted     4
```

and the record totals move only where the report says: `scon` **1999 → 1975**, `svar`
**1731 → 1721**, `in` **748 → 724**, while `learn`, `step`, `sat`, `splice`, `inpart`, `ex`, `sin`,
`solve`, `rsound` counts are **identical**.  Per-site segment counts are identical on both sides
(16,728 `trySolveOn`, 36,873 `mkSimplified-extinct`, 598 `inferImplicitBindingTypes`).  The first
differing segment is `Relation/Op.e`, before-side input carrying `c^111545 <- (c^111545)` and the
after-side not — the report's `part v111545|v111545`.  ✔

The brief's byte-identical premise is indeed wrong, for the reason the report gives:
`mkSimplified` runs `RowTrace.withSite("mkSimplified-extinct")(solve(…))` at `Subst.scala:1670`,
so a deleted member changes that solve's input, and the published residual is the input of every
later instantiation.  **The loop itself is untouched**: `learn`/`step` counts identical, model
agreement 714/714 and 54,199/54,199 on both builds, 0 skips.

**Could a downstream instantiation change a VERDICT?**  Measured, not argued: the corpus verdicts
are identical on 132 + 34 files, and the two propagation bindings are fine.
`Present.WriterOutputs.reportFor` loses `a <- ((|pTitle,pMinValue|), d)` and keeps two constraints
that between them still say exactly `a ⊇ {pTitle, pMinValue, pRegion}` — equivalent, and
`Present/` still loads.  `Layout.Report.Relation.cutoffGroupedFldsPosNegRel'` goes 44 → 39 with
`|E| = 40` and is `EQUIVALENT` under both checkers; `Layout/Report/Relation.e` is stdlib and every
module above it still boots (54,199 solves, no refutation).  Satisfiability cannot move at all:
the Lean `SEquiv.sat_iff` covers it, and both deletions preserve the model set by construction.

## 7. The scratch Lean (brief item 4)

`cd tracker/lean && lake env lean ../loopmodel/S3Simplify.lean` — **2.0 s, one style hint
("Variable name `rho` is not explicitly referenced"), no error, no `sorry`, no `axiom`.**  All
**eight** declarations, including the two the file does not print, depend on exactly
`[propext, Classical.choice, Quot.sound]`:

```
sat_congr_of_perm  sEntails_of_perm  sat_taut  sEntails_taut
sEntails_of_mem_subset  erase_perm_dup_equiv  erase_taut_equiv  SEquiv.sat_iff
```

**What they prove, and it is the right thing.**  `Constraint` is `⟨lhs : Var, vars : List Var,
conc : Finset Label⟩` — the same triple as `NormalPart(left, abstrakt, concrete)` — and
`taut a := ⟨a, [a], ∅⟩` is exactly the compiler's guard `cs.isEmpty && vs == List(v)`.
`sat_congr_of_perm` needs same `lhs`, same `conc`, `vars.Perm` — exactly what `NormalPart.equals`
tests (multiset equality of the abstract parts).  `erase_perm_dup_equiv` and `erase_taut_equiv`
then give **two-way** `SEquiv` between the system and the system with the member deleted; the
tautology one needs no hypothesis on `G` at all.  `SEquiv.sat_iff` is the side condition the
`mkSimplified-extinct` solve needs.  I added a non-vacuity example (`taut 0 = ⟨0,[0],∅⟩` by `rfl`,
`Sat rho (taut 3)`) and a negative control (`¬ ∀ rho, Sat rho ⟨0,[1],∅⟩`, discharged by a witness)
— both elaborate, so the statements are not accidentally trivial.

**Do they belong in the library?**  **Recommend: no, and record why.**  `Rowpartition/Canonical.lean`
already implements and proves both rules (`Step.dedup` up to RHS permutation, `Step.occurs` deleting
`r <- (r)`, with `Step.preserves`), so as *mathematics* this file is a restatement.  Its value is as
the *specification the compiler's diff is checked against*, phrased over a raw `System` with no
`State` and no rule machinery, which is precisely what `Loop/Strict.lean`'s `NoLoss`/`Conserv`
vocabulary is not about.  The right home is either (a) leave it as scratch beside `S3-SIMPLIFY.md`,
which is what the implementer chose, or (b) if it is wanted under `lake build`, add it as
`Rowpartition/Simplify.lean` re-deriving `erase_perm_dup_equiv`/`erase_taut_equiv` as corollaries of
`Canonical.Step.preserves` rather than from scratch, so there is one proof of each rule and not two.
Do **not** put it in `Loop/Strict.lean`: nothing here is about the loop.

## 8. The third sibling (brief item 5) — **agree, out of scope, but the report's reason is wrong**

**Both readings agree with the implementer's decision to defer.**  What I disagree with is the
factual premise, which is K-1.

* **`Part.apply` (`Type.scala:407-422`).**  Deferring is right, and the *real* reason is stronger
  than the one given.  This is the PRE-solver smart constructor: `Constraints.scala:786`
  (`PQueue.toTypes`) rebuilds every partition through it and `PQueue.build` reads them back, so a
  variable-identity case there stops `r <- (r)` reaching the solver at all — the row trace moves,
  the L2 corpus differential has to be re-established on every group, and
  `incomplete/Signatures.e:40`'s `taut : r <- (r) => …` (with `tautIsFree` proving it discharges
  from an empty context) is a source-written constraint of exactly that shape, so the proof would
  stop proving what it says.  **Cost: one full stage** — the one-line change is free; the
  acceptance criterion (a fresh L2 differential over all groups, plus a decision about what
  `taut`/`tautIsFree` then mean) is the whole cost.  And because of K-1 it is really *two* fixes,
  not one, and the concrete one alone already moves the trace.
* **Entailment pruning between surviving partitions.**  Confirmed absent by reading:
  `mkSimplified` does isolation pruning, normalisation, the concrete-identity deletion, syntactic
  `distinct` and ambiguity pruning, and **no entailment test anywhere**.  This is
  `ROSE-COMPARISON` rank 3 (canonical simplification) and is a *feature*, not a sibling bug: it is
  the one change whose every deletion needs its own certificate, so "this deletion is a copy or a
  tautology" stops being available as the soundness argument.  **Cost: 1–2 stages** — a decision
  procedure inside the compiler (the per-label decision my `indep.py` implements is complete but
  is exponential in the existentials in the worst case, and `cutoffGroupedFldsPosNegRel'` already
  has 40), a cost/termination argument, a Lean correspondence, and a much larger `.ei` sweep since
  every published type would move.  Two residuals S3 leaves behind show the payoff
  (`RunCalibration.valueAsOf`, and the `runningTotal` probe's `e <- (f1, f, e1, d1, so)`).  Agree:
  separate stage.

## 9. E-series consequences (brief item 6) — all three confirmed

Re-inferred from the unannotated bodies in scratch modules, both compilers:

| helper | inferred BEFORE | inferred AFTER | equivalent? |
|---|---|---|---|
| `melt3` | 21 constraints = **20 partitions** + 1 class, 19 existentials | **19 partitions** + 1 class | EQUIVALENT, `|U|=7 |E|=19`, 128 patterns |
| `runningTotal` | 21 = **20 partitions** + 1 class, **27 existentials** | **19 partitions** + 1 class, 27 existentials | EQUIVALENT, `|U|=5 |E|=27`, 32 patterns |
| `safeDiv` | **5 partitions** | **3 partitions** | EQUIVALENT, `|U|=3 |E|=3`, 8 patterns |

`safeDiv`'s three are `r <- (so, e)`, `c <- (e, f)`, `c1 <- (so, e, f)` — which is exactly
`Time.Signatures.safeDivDeduped`'s `num <- (so, e)`, `den <- (e, f)`, `out <- (so, f, e)`.
**The compiler now performs that hand-deduplication itself.**  ✔  `runningTotal`'s 20 → 19 is
`−2 permuted copies +1 new consequence`, as the report explains, and the new member
`e <- (f1, f, e1, d1, so)` is entailed by three both sides carry.  ✔

**E1's N-11 undercount is confirmed**, by the scanner rather than by eye: `melt3Full` carries
**three** permuted pairs (`r22 <- (ro2,rs2)`, `r23 <- (ro1,rs1)`, **`r21 <- (ro,rs)`**), not two,
and the third one **survives into `melt3Deduped`**, so the hand-deduplicated "twenty" is
nineteen.  ✔  `nearestByFull` 2 pairs + 2 tautologies (13 constraints) ✔; `valueAsOfFormA` 2 pairs
+ 1 tautology ✔.

**All five `Signatures.e` still check, 0 errors, on both compilers** — and I confirmed the
mechanism the report asserts: a *declared* signature is published verbatim and does not pass
through `mkSimplified`, so post-fix `incomplete/Signatures.ei` still reads
`taut : forall (r: rho). r <- (r) => …` and
`topRowsByFull : … (RelationalComb rel, b <- (h, c), h <- (h)) => …`.  The `xDeduped = xFull`
proofs are untouched.

## 9a. The `Lang/` group, committed as `3b5ad49` while this review ran

Neither sweep covered it (it was uncommitted and in flux).  I swept it separately on both
snapshots — 12 example modules with `Lang/Helpers.e` hoisted, 156 interfaces, **2,003 bindings**:

```
changed 13 ; EQUIVALENT 13 ; 0 weaker, 0 stronger ; binding sets identical in every interface
```

All thirteen are the stdlib bindings already in the 21 (`Layout.Report` ×4, `Layout.Scan.legend1`,
`Relation` ×4, `Relation.Aggregate.count`, `Relation.Op` ×3).  **No `Lang_*.ei` binding changes at
all**, and post-fix the whole Lang closure publishes **0** duplicates and **0** tautologies.  The
new group adds nothing to the risk.

### The `Signatures.e` comments that now describe a defect the compiler no longer has

These should be updated by whoever commits.  Each anchor below declares, or discusses, a set that
carries a member the compiler no longer publishes for an inferred residual (measured, from
`dupscan.py` on the post-fix sweep).

| file | lines | what is now stale |
|---|---|---|
| `Wide/Signatures.e` | **36-38** (header point 3) | "`melt3`'s TWENTY-TWO inferred constraints reduce to TWENTY by deleting **two** order-permuted duplicates" — there are **three**, the reduction is to **nineteen**, and the compiler now does it |
| `Wide/Signatures.e` | **147-158** (above `melt3Deduped`) | "The SAME set with **two** members deleted … proves the twenty entail the twenty-two" — a third pair (`r21 <- (ro, rs)` / `r21 <- (rs, ro)`) is still in `melt3Deduped` |
| `Algebra/Signatures.e` | **43-49** (above `antiJoinFull`), **57** | "The interesting member of the inferred set is `r1 <- (r1)`, a TAUTOLOGY" / "The tautology deleted" — the compiler no longer infers it |
| `Algebra/Signatures.e` | **159-181** (above `runningTotalFull`) | "the compiler infers TWENTY-ONE … Below is that set VERBATIM (REPL `:type` …, 2026-09-07)" — now **twenty** |
| `Time/Signatures.e` | **86-99** (`orZeroFull`/`orZeroDeduped`) | "One is the tautology" / "The tautology deleted. Nothing is left but the class constraint" — now the inferred set |
| `Time/Signatures.e` | **100-108** (`yearFrac365Full`) | the recorded set's `out <- (out)` |
| `Time/Signatures.e` | **116-129** (`pctChangeFull`) | "SIX constraints … One is the tautology" — now five |
| `Time/Signatures.e` | **144-165** (`safeDivFull`/`safeDivDeduped`) | "FIVE constraints … they come in PERMUTED PAIRS" / "Both permuted copies deleted" — **the compiler now infers `safeDivDeduped`'s three**; this is the sharpest one |
| `Time/Signatures.e` | **175-205** (`band3Full`, `band4Full`) | the recorded `v <- (v)` and "This is the measurement `Ai/Common.e` asked for" |
| `Time/Signatures.e` | **218-258** (`nearestByFull`) | "THIRTEEN constraints … verbatim. Two tautologies, one permuted pair over four parts, one permuted pair over two" — now nine |
| `Time/Signatures.e` | **281-304** (`shiftByFull`) | "the tautology on the index column, minted by `withFieldCopy`" / "`p <- (p)` deleted" |
| `incomplete/Signatures.e` | **60-105** (`valueAsOfFormA`, `valueAsOfFormAviaB`) | "The LARGER of the two residuals `RunCalibration.e` emits, verbatim, all fifteen" — the recorded set has 2 pairs + a tautology the compiler no longer emits |
| `incomplete/Signatures.e` | **128-158** (`shareOfGroupFull`) | "The inferred set, verbatim: fifteen row constraints" (carries the `kv2` permuted pair) |
| `incomplete/Signatures.e` | **186-198** (`topRowsByFull`/`Deduped`) | "The tautology deleted. What is left … is exactly the [expected signature]" — the compiler now produces `topRowsByDeduped`'s signature itself |
| `Present/Signatures.e` | **49-79** | **already correct** — E4/E5 wrote the "STAGE S3 HAS LANDED IN THE WORKING TREE (uncommitted)" block; only "(uncommitted)" and "compiled in at 03:56 on 2026-09-07" need the commit hash |

Beyond `Signatures.e`, three more files quote an inferred residual S3 changes and should get the
same treatment: **`incomplete/TopReadings.e:26-45`** (the whole "WHAT ACTUALLY HAPPENS … Identical
on every run" block, including "printing it in the user's face" — this is the module the fix was
built from), **`incomplete/RunCalibration.e:35-105`**, and **`Time/Helpers.e:60, 357, 396, 514`**.

## 10. Perf (brief item 7) — run, on a quiet machine, both sides

The implementer could not run it.  I could: I waited for the 1-minute load to fall below 1.3 and
ran `perf-bench.sh batch -n 3` on each side, rebuilding in between.

```
AFTER  (run 1)  cold median 12.05 s in-process (min 11.97, max 12.13, spread 0.16), load_before 1.01
BEFORE (run 1)  cold median 12.04 s in-process (min 11.70, max 12.07, spread 0.37), load_before 1.11
AFTER  (run 2)  cold median 12.10 s in-process (min 12.08, max 12.20, spread 0.12), load_before 1.24
```

**Unmoved.**  The before-side median sits between the two after-side medians; the whole range is
12.04-12.10 s, inside a single run's own spread (0.12-0.37 s).  The stdlib boot does not notice
the change, which is what one should expect - the stdlib's own residuals carry few duplicates
relative to total work.

The example-corpus import proxy, re-measured from my own batch logs over the 70 shared modules:
**21.40 s → 20.99 s (98.1 %)**, worst single regression +0.05 s, dominated by `WardRoster`
−0.62 s; `incomplete` 2.67 s → 2.49 s.  Direction and dominant contributor agree with the report;
the magnitude does not (**K-8**).

---

## Findings

### K-0 · CONFIRMED · process, not a defect
The S3 change is **uncommitted** in the working tree (`git status` shows `M Subst.scala`, plus the
untracked `S3-SIMPLIFY.md` / `S3Simplify.lean` and the state/plan edits) — the review brief says
"everything else is committed", which is not the case.  Convenient for this review (HEAD `0741fb2`
*is* the pre-fix compiler, so a `--detach` worktree gives it for free), but it means the tree other
agents are working in has a compiler change in it.  **The live `core/target/scala-3.3.8/classes`
carry the fix** — `Subst$.class` and `Subst$NormalPart.class` are byte-identical to my post-fix
snapshot, mtime 03:56 — so every measurement any agent has taken against the live classes since
then was taken with S3 in.  The report says this in §10; I confirm it, and note that
`build-and-test.sh`'s restore-the-pre-fix-classes step has since been undone by a later compile.

### K-1 · CONFIRMED · **the report's and `ROSE-COMPARISON`'s statement about `Part.apply` is factually wrong; the case is dead code**
`S3-SIMPLIFY.md` §2 says "CONFIRMED: `Type.scala:414` collapses the concrete identity
`(|Foo,Bar|) <- (|Foo,Bar|)` to `Exists(l)`", and `ROSE-COMPARISON.md` §3 rank 1 item 3 says the
same.  **It never fires.**  The guard is

```scala
val (ts, rcl, ss) = rh.foldLeft((List[Type](), l, List[Name]())) { … s.toList ++ ss … }
case ConcreteRho(lclhs, cs) if ts.isEmpty && ss == cs => Exists(l)
```

`ss` is a `List[Name]`, `cs` is a `Set[Name]` (`ConcreteRho(loc, fields: Set[Name])`), and
`List == Set` is **always false** in Scala — verified at the project's own Scala 3.3.8 (`direct
List == Set : false`; the same expression is a compile error at newer 3.x, which is why it has
survived).  `(|Foo,Bar|) <- ((|Foo,Bar|))` therefore falls through to
`case _ if ss.toSet.size == ss.length` and is rebuilt unchanged, reaching the solver.  It is
deleted later, from the *published* residual only, by `normalPart`'s `ConcreteRho` branch — where
the comparison is `Set == Set` and is real.

Consequences: (a) two documents assert something false about the code and should be corrected;
(b) the "the concrete case is handled and the variable case is not" symmetry that
`ROSE-COMPARISON` uses to motivate item 3 **does not hold at `Part.apply`** — *neither* case is
handled there, which is a fourth omission of the same family; (c) the one-word repair is
`ss.toSet == cs`, and it belongs in the same follow-up as the variable-identity case because it
too moves the pre-solver path.  **No effect on the S3 change itself** — nothing in the diff
touches `Part.apply`, and I confirmed `Part.isTrivialConstraint` is `false` unconditionally
(`Type.scala:394`) as both documents say.

### K-2 · CONFIRMED · **a refutation message moves, and the report does not mention it**
`ROSE-COMPARISON` §3 rank 1 lists as acceptance item (i): "`normal.distinct` preserves first
occurrence, and the surviving representative's `loc` is what a blame message points at, so
collapsing more constraints changes *which* `loc` survives."  The report addresses the `iso`,
`extinct` and vacuous-binder side conditions and **not** this one, and its corpus gate compares
exit codes only.  Comparing the `.out` **contents** (wall-clock normalised) finds exactly one
change in 132 + 34 files:

```
core/examples/Time/shouldfail/bucket01_calendar_overlaps_facts.e:77:7:
  BEFORE  Row partitions are unsatisfiable at field '…Bucket01.region': the whole contains it but no part does
  AFTER   Row partitions are unsatisfiable at field '…Bucket01.region': a part contains it but the whole does not
```

Same verdict, same position, same field — a different **clause** of the same refutation.  Two
mitigations, both measured: run **per file** the clause is identical on both sides (I checked),
so this is the whole-corpus-batch configuration only; and the clause the fixed compiler prints is
the one `bucket01`'s own header (line 30) and `E3-EXAMPLES.md:176` record first, so if anything it
moved toward the recorded answer.  This clause is already known to be unstable
(`corpus-run.sh` header; `E2-REVIEW.md` §G1; `bucket01`'s "AND THE CLAUSE IS NOT STABLE ACROSS
LOADING MODES").  **Not a regression — but it is a user-visible change caused by S3, it is exactly
what the origin document asked to watch for, and it must be in the report and the state file.**

### K-3 · CONFIRMED · `rowequiv.py` is not "the complete decision" of the property the report claims
The report calls it "a complete per-label decision" and rests "nothing weaker or stronger" on it.
It **is** a complete decision of the *row-partition* part — I proved that against brute force on
17,416 instances — but it reads neither the **class constraints** nor the **body**, and I
constructed pairs where it therefore answers `EQUIVALENT` for a strictly weaker signature and for
a different type (§5).  The report's conclusion survives because `s3check3.py` compares bodies and
`forall` binders for the 19 syntactically-explained bindings and the report separately asserts the
class multiset is unchanged — but the two bindings `s3check3.py` cannot explain are exactly the
ones where only `rowequiv.py` was applied.  My `indep.py` closes it mechanically for all 21
(bodies, binders, class multisets, binding sets all identical).  **Fix: say which tool covers
which part, or re-run with a checker that covers all of it.**

### K-4 · CONFIRMED · two of the four "propagation" bindings are print-order churn, not propagation
§4's table and the plan row say "The last four are propagation".  Measured, the *only* change to
`Present.WriterOutputs.asDocument` and `asProfiledDocument` is the print order of the field names
inside one concrete row — `(|pRegion, pTitle, pMinValue|)` → `(|pMinValue, pTitle, pRegion|)` —
i.e. the iteration order of a three-element `Set[Name]`, which Scala keeps in insertion order for
sizes ≤ 4, and the insertion order shifted with the constraint order.  Same constraint, same
count, same everything else; `s3check3.py` classes them as *explained* with `dup=0 taut=0`.  Only
`reportFor` and `cutoffGroupedFldsPosNegRel'` are propagation, which is also why "NOT EXPLAINED: 2"
and "the last four are propagation" cannot both be read literally.

### K-5 · CONFIRMED · the corpus the sweep ran against is not the corpus at the reviewed commit
`examples-frozen/` was taken before E4's `Present/ProjectionCost.e` and
`Present/shouldfail/proj01_seven_reads.e` were committed, so the sweep is 174 files / 242
interfaces / 2,946 bindings where the same sweep at `0741fb2` is **176 / 243 / 2,966**; and the
`corpus-run.sh` figures (130 then 132 files, 69/61 then 70/62) came from the *live* tree, whereas
the brief says the corpus is "now 151 files" (151 includes the 19 `Lang/` files, which were
uncommitted during both the implementer's work and mine and landed as `3b5ad49` mid-review; I
swept them separately, §9a, and nothing there moves).
**No conclusion moves** — the 21 changed bindings, their names, and every per-binding number are
identical on both corpora — but the absolute counts in the report, the state file and the plan row
are not what a committer re-running at HEAD will see.  Worth one sentence saying which corpus.

### K-6 · CONFIRMED · trivial, but the row is already committed
The plan row says "Lean: … **six** theorems"; the file has seven named theorems plus
`sEntails_of_mem_subset` (eight declarations), and `#print axioms` covers only six —
`sEntails_taut` and `sEntails_of_mem_subset` are not printed.  I printed them: same three
standard axioms.  Note that the S3 plan row was **swept into E5's commit `3b5ad49`** mid-review,
so it is already in history reading "GREEN, DELIVERED 2026-09-07 (**uncommitted**)" with the
reviewer column "pending" — the S3 commit must amend that row (reviewer verdict, drop
"uncommitted", six → eight, and the corrections in K-1/K-2/K-4/K-5/K-8) rather than only add to it.

### K-7 · CONFIRMED · informational, for whoever commits
`TestLoopTrace` **silently skips** its real work when the model binary is absent from the tree it
runs in (`[loop model trace] SKIPPED: the Lean model executable is absent …`) and still reports
`Passed: Total 3`.  My first run in a fresh worktree passed vacuously.  The real result needs
`-Dermine.looptrace=<path>`; with it, 714/714 on both sides.  Anyone reading a `core/test` "914 /
913 / 1" from a tree without `tracker/lean/.lake/build/bin/looptrace` is reading a gate with the
loop-model property switched off.

### K-8 · PLAUSIBLE · the import-time perf proxy does not reproduce at the reported magnitude
The report's proxy is 23.7 s → 21.9 s (92 %).  Mine, over the 70 modules my two batch runs share,
is **21.40 s → 20.99 s (98.1 %)**.  Direction and the dominant contributor (`WardRoster`) agree;
the size does not, and both are single runs on a machine at load 3.  The measurement of record now
exists and says **unmoved** across three quiet-machine runs (§10), so I would drop the "92 %" claim rather than defend it.

### K-9 · CONFIRMED · informational
The `3 row constraints → 1` headline for `TopReadings.topRowsBy` is the **virgin-load** figure.
In the interface-carrying sweep the same binding's pre-fix residual has only
`b <- (c, h), h <- (h)` and goes 3 constraints → 2.  Both figures are in the report (§1 and §4's
table) but nothing says they are different runs.

---

## What I did not re-run

* **§7, A1's thirty movers.**  Re-running the `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`
  flip on both compilers over the whole corpus is a second full double sweep, and the brief does not
  ask for it.  I note that the report itself **withdraws** the one claim in §7 that would have
  mattered (the `incomplete/` chunk asymmetry does not survive its control) and that its
  `45 → 45/44` conclusion is explicitly "the count does not drop and should not have been expected
  to".  The independent confirmation of §R-6 rests on `rowequiv.py`, so **K-3** applies to it too.
* **`looptrace-corpus.sh` on the `Wide` group.**  I ran the model differential on `boot`
  (54,199/54,199, both sides).  Past the first divergence the `Wide` index-pairing is dominated by
  `Supply` drift, exactly as the report says, so re-running it would add a number and no
  information.

## Recommended before the commit

1. Correct **K-1** in `S3-SIMPLIFY.md` §2 *and* in `ROSE-COMPARISON.md` §3 rank 1 item 3; add the
   dead `ss == cs` guard to the follow-up ticket (`ss.toSet == cs`) alongside the variable case.
2. Add **K-2** to the report and to the `ROW-CONSTRAINT-STATE.md` section: one refutation clause
   moves in the whole-corpus batch, same verdict/position/field, per-file unchanged.
3. Soften **K-3**: name what `rowequiv.py` decides and what checks the bodies and class
   constraints.
4. Fix **K-4** (two of the four are print order), **K-5** (say which corpus), **K-6** (six → eight)
   — and note that the plan row is already committed in `3b5ad49`, so it needs amending, not
   appending: reviewer verdict, and drop "(uncommitted)".
5. Replace the 92 % perf proxy with the real measurement: `perf-bench.sh batch -n 3`,
   **12.04 s → 12.05 s**, both sides at load ≈ 1.1 (**K-8**).
6. Update the `Signatures.e` (and `TopReadings.e` / `RunCalibration.e` / `Time/Helpers.e`) comments
   listed in §9.

Reviewer scratch, scripts and artefacts: `/home/dmitry/.claude/jobs/880c725d/tmp/review-S3/`
(`build-side.sh`, `sweep.sh`, `gates.sh`, `sbtgates.sh`, `lt3.sh`, `final.sh`, `perf.sh`,
`perf2.sh`, `indep.py`, snapshots `snap-before` / `snap-after`, sweeps `ei-before` / `ei-after` /
`ei-ctl`, traces `boot-*.tsv`, corpora `corpus-*`, probes `probe-*`, `adv/` for the constructed
mis-classification pairs, `S3check.lean`).
