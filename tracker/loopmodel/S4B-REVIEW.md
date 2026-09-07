# S4 Part B review — the written-partition normalisation (`-Dermine.topNormalise`, default OFF)

Reviewer: agent (2026-09-07, Opus), independent of the S4 Part A/B author and of `S4A-REVIEW.md`.
Subject: `tracker/loopmodel/S4-CHANGE.md` and everything it delivers — the Scala in the worktree
`~/research/ermine/ermine-scala-wt-s4` (branch `top-normalise`, based on `4a9ed4b`), the model
mirror and `tracker/loopmodel/S4Top.lean` in the MAIN tree (uncommitted), the example and doc
edits, and the seeds.  Brief: `tracker/loopmodel/briefs/brief-S4.md` (Part B and the wild-code
gate).  Nothing outside `/home/dmitry/.claude/jobs/880c725d/tmp/review-S4B/` and this file was
edited; every `.ei` this review created was deleted in both trees.

## VERDICT — **FIX-THEN-ADVANCE**

The rule is right, the measurement is honest, and every headline number in `S4-CHANGE.md` that I
re-ran came back at the digit.  One delivered artefact is broken, and it is the one the stage's
own standing constraint names: **`lake build` fails.**  `Rowpartition/Loop/NoFalseAccept.lean`
does not elaborate any more, because the model mirror inserted `topNormalise` between
`buildQueue` and the checks and the S2 chain's lemmas are stated about `buildQueue`'s queue.  The
consequences are not cosmetic: the library's default target does not build, the project-wide
0-non-standard-axiom audit (`tracker/lean/Audit.lean`) cannot run at all, and `S4-CHANGE.md` §1's
central placement argument — "`solve_accepted_faithful` keeps its shape" — is false as delivered.
That is H-1 and it blocks the commit.

**Adoption recommendation: DO NOT flip `topNormalise` ON by default yet** — see §5.  Not because
the rule is unsound (it is not; the equivalence is real and I could not break it), but because
four things must be true first and today none of them is (§5.2).

| | |
|---|---|
| **the rule** | sound, and I could not break it — 29 adversarial seeds and 2 compiler probes, 0 verdict changes at the shipped defaults (one with the S2 layers off, H-2) |
| **the numbers** | every headline figure I re-ran came back at the digit: the `D(N)` ladder, `sat = 3^N − 2^N`, 15 `tnorm` sites, 131,248 / 90,694 / 59,603 segments, 83/69 → 84/68, 137 / 15, 720/720, 1,905,368 |
| **two open gates** | both now CLOSED by me: `slow/GU05MIN` budgeted **completes** (963 s / 921 s) and is SAME; `proj/PROJ8` budgeted is **REJECTED@20,009 → SOLVED@1** |
| **one gate the report skipped** | the per-file sweep: `Present/` 20 modules, **19 identical, 1 differs**, and the one is `proj01` |
| **blockers** | H-1 (`lake build`) and H-12 (four unpatched model call sites); H-2/H-3 must be written into the report before its "verdicts preserved" is safe to quote |

---
## 1. The rule, read line by line

`Constraints.topFamilies` / `Constraints.topNormalise` (worktree `Constraints.scala:2216-2283`)
and the one call in `Subst.solve` (`Subst.scala:1135-1178`).  I read both against the model
mirror in `Loop/Json.lean` and against `resolution`.

### 1.1 The trigger

```scala
def isRead(p) = p match { case Partition(_, RHS(Single(_), con), _) => con.nonEmpty ; case _ => false }
val cands = ps.filter(isRead).map(_._1).distinct                       // lhs, in QUEUE order
cands.flatMap { v =>
  if (ps.exists(p => p._1 == v && p._2.abstr.isEmpty)) None            // no concrete row at v
  else { val fam = ps.filter(p => p._1 == v && isRead(p))
         val dis = fam.map(_._2.concr).distinct                        // DISTINCT parts
         if (dis.length < 3) None                                      // k >= 3
         else if (dis.exists(c => dis.exists(d => c != d && c.subsetOf(d)))) None
         else Some(TopFamily(v, fam, dis.reduce(_ ++ _))) } }
```

* **"Pairwise-incomparable" is tested correctly.**  `dis` is already de-duplicated by `Set`
  equality, so `c != d && c.subsetOf(d)` is proper containment, the double `exists` covers both
  orders, and the family is dropped if ANY ordered pair is comparable.  It does NOT require
  disjointness, and it should not: overlapping incomparable parts are fine (seed `H3`,
  `{a,b} {b,c} {c,a}`, rewritten and solved both ways).
* **Duplicate parts** collapse in `dis` (so they do not count towards `k`) but every duplicate
  read is still in `fam`, so both are deleted and both get a re-expression, which is right:
  two reads with the same part have equal remainders and the two identical re-expressions are
  what `commonPartition` then unifies.  Seed `H9` (four reads, three distinct parts) fires and
  is verdict-preserving.
* **A premise that is also something else.**  A read's remainder `x_i` may be the left-hand side
  of other partitions, a part of another partition, or shared between two families; none of those
  partitions is deleted, and the rewrite only ADDS `x_i <- (c, F \ F_i)` beside them.  Seeds
  `H1`/`H2` (remainder read elsewhere), `H4`/`H4U` (the family's lhs is a part), `H5`/`H5U` (two
  families sharing a remainder), `H12`/`H12U` (one family's lhs is another's remainder) all
  preserve their verdict.
* **Two families at one lhs cannot happen**: `cands` is `distinct` and `fam` collects *all* reads
  at that lhs into one family.  Two families at DIFFERENT lhs each mint their own carrier — `H12`
  shows `drawn0 = 2`.

### 1.2 The replacement, the carrier, the draw

`c = fresh(loc, none, Ambiguous(Free), Rho(loc.inferred))` is drawn from `solve`'s own implicit
`Supply`, once per FAMILY, before that family's re-expressions are built.  `GenRules.countDraw()`
is **not** called, and that is correct rather than a dodge: the only two call sites of
`countDraw()` in the tree are `splitConcrete` (`Constraints.scala:1845`) and `resolution`
(`:2361`), both inside `withLoopDraws`, which `PQueue.expand` scopes around the loop.  A pre-loop
mint has never been counted (`PQueue.build`'s own mint is not either), so the D1 identity
`sdraw == drawn − drawn0` survives; the model takes `drawn0` after the same mint.  The visible
consequence is that the carrier is invisible to `solveBudget`; the number of carriers is bounded
by the number of distinct left-hand sides in the input, so this cannot be exploited.

The queue is rebuilt with `PQueue(keep ++ added)`, which is `empty ++ ps` using the NON-processing
insert `+` — the same constructor `PQueue.build` itself uses, so no queue invariant is bypassed.
When no family fires, `Subst.solve` matches `case (_, Nil) => (q0, Nil)` and reuses the ORIGINAL
`q0` object, so a flag-ON solve that does not fire is not even a rebuild.

### 1.3 The relation to `resolution`, stated precisely (and it matters for H-2)

At `k = 2` the shipped `resolution` derives, from `v <- (x, C1)` and `v <- (y, C2)`,

```
v <- (z, C1 ∪ C2)      x <- (z, bots = C2 \ C1)      y <- (z, tops = C1 \ C2)
```

and with `F = C1 ∪ C2`, `bots = F \ C1` and `tops = F \ C2`.  Those are **exactly** S4's three
conclusions.  So the report's "`k = 2` the binary `resolution` IS this rule" is right about the
conclusions — with one difference the report does not draw out: `resolution` **adds**, S4
**deletes**.  Every read the rewrite removes is a premise some other rule could have used, and
the loop's own deaths (`selfSubstitution`'s "Infinite row partition", `RHS.merge`'s "Fields appear
twice in row") are SYNTACTIC.  `noloss_of_top` is a semantic entailment and does not carry them.
H-2 is the measured consequence.

### 1.4 Placement, live input, blame

* **Live input.**  `decideLabels`'s `liveInput` starts from `val base = q.toList.map(_.tup)`
  (`Subst.scala:1266`) and `q` is the rewritten queue, so layer (iii) decides the NORMALISED
  system.  `checkLabels(q.toList.map(_.tup))` and `q.expand` likewise.  All four readers see one
  system; the report's §1 claim is correct at the code level.
* **Blame.**  `rowUnsat` searches `cs.flatMap(_.rowConstraints)`, and `cs` is not rewritten, so
  the `Loc`s are structurally untouched.  I checked the case the report calls "the one that
  moves": `probes/AdvSelf3.e` is refuted ON with the rewrite having fired (`tnorm=1`), and the
  position is `AdvSelf3.e:16:7` — the SAME position as OFF.  Only the reason clause moves
  (H-3).
* **Fingerprint.**  `+topnorm` is appended by `(if (topNormalise) "+topnorm" else "")`, so at the
  default the string is byte-identical.  Note for the record that `Constraints.scala:1371` says
  "nothing keys a published `.ei` by `GenRules.toString`" — so there is no `.ei` fingerprint to
  change either way, and that pre-existing open gap (A1 review R-4) is the reason a warm `.ei`
  cache would silently survive a flag flip.  See §5.

## 2. The Lean

### 2.1 `S4Top.lean` — elaborates, 18/18 on the three standard axioms

```
cd tracker/lean && lake env lean ../loopmodel/S4Top.lean      # 1.8 s, no errors, no warnings
```
All 18 `#print axioms` lines came back `[propext, Classical.choice, Quot.sound]`
(`setVar_eq_update` needs only `propext, Quot.sound`).  No `sorryAx`, no `nativeDecide`.
Saved: `review-S4B/S4Top-axioms.txt`.

Nit (H-7): the file has **22** declarations — 2 `def`s (`topAdds`, `topReads`) and the two
membership helpers `top_mem_topAdds` / `reexpr_mem_topAdds` carry no audit line.  "18
declarations" in `S4-CHANGE.md` §2.3, the plan row and the state file is "18 audited theorems".

### 2.2 What is proved, and what is still not

| direction | statement | level |
|---|---|---|
| reads ⊨ replacements (SSat forward) | `ssat_rewrite_fwd`, premise `c ∉ allVars G`, via `sModels_setVar` | **SYSTEM** |
| replacements ⊨ reads (NoLoss) | `noloss_of_top` (from `read_of_top`, no side condition) | **SYSTEM** |
| step 1 is additive | `topAdd_noLoss` = `NoLoss.of_subset` | SYSTEM |
| step 1 is not a `requeue` | `topAdd_escapes` | SYSTEM |
| step 2 is a `drop` | `topDrop`, producing a real `Loop.LoopStrict.drop` | SYSTEM |
| the family versions | `models_rewrite` / `reads_of_rewrite` / `top_sat` / `reexpr_sat` | family |
| `F ⊆ rho v` is not an assumption | `F_subset_of_reads` | SYSTEM |

So **both directions are now at the system level** and G-1 is genuinely closed.  I checked
`ssat_rewrite_fwd`'s premises are the ones that matter: `hfresh : c ∉ allVars G` is used twice
(to get `c ≠ v` from `lhs_mem_allVars` and `c ≠ x_i` from `mem_allVars`), and `hFsub` is
discharged by `F_subset_of_reads`.  `topDrop` is a genuine `LoopStrict.drop`
(`Loop/Strict.lean:217`), and `requeue`'s `allVars G' ⊆ allVars G` really is refuted by
`topAdd_escapes`.

**Two gaps remain, one of them stated in the report and one not.**

* Stated (`S4-CHANGE.md` §6): no `LoopStrict` constructor was added, so the composite is not a
  `LoopStrictRun` and step 1 is a shape, not a step.
* **Not stated: there is no correspondence lemma.**  Everything above is about an abstract
  `System`, `topAdds`/`topReads` and a hypothesised family.  Nothing connects it to
  `Loop/Json.lean`'s executable `topFamilies` / `topNormalise` — not the trigger (`k ≥ 3`,
  incomparability, no concrete row), not `F = ⋃ F_i`, not the one-pass fold, not "the carrier is
  fresh for the whole system".  Every earlier stage in this programme delivered that link
  (KeyedSplit's correspondence lemma, `d736bf9`; `K2ResStep.mint_toGRes`; `scalaEmptyRes_run`).
  S4's Lean licenses the RULE; it does not yet license the CODE.  That is the right stage-sized
  follow-up if the flag is to be adopted, and it is why my adoption answer in §5 is "not yet".

### 2.3 **H-1: `lake build` FAILS.**  The S2 chain no longer elaborates

`lake build looptrace` (the only Lean build the report ran, "1,670 jobs") builds the executable's
import closure, which does **not** include `Loop/NoFalseAccept.lean`.  The library's default
target does:

```
cd tracker/lean && lake build
...
✖ [862/867] Building Rowpartition.Loop.NoFalseAccept (85s)
error: Rowpartition/Loop/NoFalseAccept.lean:946:76: unsolved goals
error: Lean exited with code 1
error: build failed
```

The failing declaration is `solveSeed_rejects_of_refuted` (`:933-946`), whose proof is

```lean
simp only [solveSeed, hq, hearly, hflag, if_true, href]
```

and whose premises are stated about `buildQueue`'s output `q`.  `Seed.solveSeed` now interposes
`let (q, su1, tnorms) := topNormalise fl.topNormalise q0 su0'`, so the goal that remains contains
`topNormalise fl.topNormalise q su1` and every subsequent `labelClash` / `labelDecide` /
`initState` mentions `(topNormalise fl.topNormalise q su1).1` instead of `q`.  Reproduced
standalone against the built `Loop.Seed` (`review-S4B/Repro1.lean`, same error).

Consequences, all checked:

* `Rowpartition/Loop/NoFalseAccept.olean` is **missing**; `FlaggedSound.olean` and
  `Rowpartition.olean` are stale (2026-09-06 17:29).
* **The axiom audit cannot run**: `lake env lean Audit.lean` →
  `object file '…/Rowpartition/Loop/NoFalseAccept.olean' of module Rowpartition.Loop.NoFalseAccept does not exist`.
  The brief's standing constraint is "audit 0 non-standard axioms if Lean changes"; today the
  audit produces no number at all.
* `S4-CHANGE.md` §1's placement argument — item 2, "**`solve_accepted_faithful` keeps its shape**
  … Rewriting before all of them keeps one `q` and leaves every premise syntactically where it
  was" — is **false as delivered**.  The premises are syntactically where they were; the
  DEFINITION they are about moved out from under them.

**The minimal repair, verified.**  Adding `(htn : fl.topNormalise = false)` and
`simp only [solveSeed, hq, htn, topNormalise, Bool.not_false, if_true, hearly, hflag, href]`
closes the goal (`review-S4B/Repro2.lean`, elaborates clean).  But that is the honest fix, and it
says out loud what §1 claimed was avoided: **the S2 no-false-acceptance chain does not cover the
flag-ON configuration.**  Covering it means restating the theorem on the rewritten queue and
adding the bridge from `reads_of_rewrite` — precisely the "bridge lemma" §1 argued the placement
made unnecessary.  Either repair is fine; shipping neither is not.

### 2.4 The mirror is the same function as the Scala's (five call sites, three left alone)

Read side by side, `Loop/Json.lean:169-224` and `Constraints.scala:2226-2283` agree clause for
clause: `isRead` (`abstrSingle?.isSome && !conc.isEmpty`), candidate lhs in queue order
(`eraseDups` / `distinct`), the concrete-row veto (`rhs.abstr.isEmpty`), `dis` de-duplicated by
set equality, `dis.length < 3`, the two-sided comparability test written as its own De Morgan
dual, `F` by union fold, one carrier per family drawn before that family's re-expressions,
`keep ++ added`, and `PQueue.ofList` = `empty.concatNP` = Scala's `empty ++ ps` (both the
NON-processing insert).  `SSet.eqv` is `size == size && subsetOf`, i.e. set equality;
`removedAll` is `F \ C` at the right argument order; `LPart.eqv` ignores `inf`, like
`Partition.equals`.  I found no divergence, and the byte-exact `tnorm` records in §3 are the
empirical confirmation.

The report's five `buildQueue` call sites are real and all five are patched.  **They are not
all of them.**  There are NINE executable call sites, and four are still unpatched — see H-12.
There is also a tenth, proof-level occurrence, `NoFalseAccept.lean`'s premises, and that one is
H-1.

## 3. The gates, re-run

Everything below is mine, run fresh; where it differs from `S4-CHANGE.md` I say so.  Scratch and
logs: `/home/dmitry/.claude/jobs/880c725d/tmp/review-S4B/`.

### 3.1 OFF — the flag costs nothing

| gate | report | mine |
|---|---|---|
| model differential, `Present` | 131,248 / 131,248, 0 skip | **131,248 / 131,248, 0 skip** |
| model differential, `Lang` | 90,694 / 90,694, 0 skip | **90,694 / 90,694, 0 skip** |
| byte-identity main vs worktree, `Present` | identical after normalisation | **IDENTICAL, 593,667 record lines** |
| byte-identity main vs worktree, `Lang` | identical after normalisation | **IDENTICAL, 324,719 record lines** |
| raw (unnormalised) compare | differs, 2 causes | **differs**, and the two causes are exactly the tree prefix in `loc` and the `rsound ok` **micros** field |

One correction to the report's description of the normalisation: the `rsound ok` record is
`rsound \t site \t loc \t ok \t labels \t sourceLen \t nodes \t micros \t threadId`, so the
wall-clock field is the **second to last** column, not the last (the last is the thread id
`RowTrace.log` appends).  A normaliser that masks `$NF` masks the thread id and leaves the timing
in.  Mine masks `c[7]`; with that, both groups are byte-identical.

`GenRules.topNormalise = false` makes `Subst.solve` reuse the ORIGINAL `q0` object (the
`case (_, Nil) => (q0, Nil)` arm), so this is guaranteed by construction as the report says — and
now measured on two groups independently.

### 3.2 ON — the compiler ladder, `N = 2…10`

`bin/ermine` in the worktree, one JVM per rung, `-Dermine.rowTrace.draws=true`, shipped budget:

```
OFF   N= 2  3   4    5      6      7          8          9          10
      draws 3  30  207  1,230  6,783   REJECTED   REJECTED   REJECTED   REJECTED   (all at 20,009)
ON    draws 3   0    0      0      0          0          0          0           0
      tnorm 0   1    1      1      1          1          1          1           1
```

Identical to `S4-CHANGE.md` §0/§4.1 at every rung, and it fills in the two cells the report left
as "—": N = 9 and N = 10 are rejected OFF as well.  `D(N) = (5^N − 3·3^N + 2·2^N)/2` reproduces
3 / 30 / 207 / 1,230 / 6,783 / 35,910 / 185,727 arithmetically; the first five are the compiler's
own counter here.

### 3.3 ON — the differential with the mirror

`looptrace-corpus.sh` from the worktree with `LOOPTRACE_JAVA=-Dermine.topNormalise=true
LOOPTRACE_FLAGS=--flags=topnorm`, replayed by the MAIN tree's model binary:

| group | segments ON | agree | skip |
|---|---|---|---|
| Present | 131,248 | 131,248 | 0 |
| Lang | 90,694 | 90,694 | 0 |
| Present-shouldfail | **59,603** | 59,603 | 0 |

and `Present-shouldfail` OFF is **59,602** — the one extra segment ON is `proj01_seven_reads.e`
compiling instead of dying, exactly as §4.8 predicts.

**All 15 `tnorm` records matched byte for byte** and the sites are the report's 13 + the two in
`WildChain.e`:

```
Present            8   ProjectionCost.e(1:1) x4, ValidationReport.e(214:14),
                       VarianceStyling.e(321:23), WildChain.e(144:8), WildChain.e(168:8)
Lang               6   ForeignJdk.e(328:3), FreeReportDsl.e(153:17), RunningState.e(214:13),
                       TextTables.e(141:13), (177:23), (191:9)
Present-shouldfail 1   proj01_seven_reads.e(1:1)
```

The `solve` records show what the rewrite does to the closure, which is the cleanest single
number in the whole stage:

```
OFF  ProjectionCost.e(1:1)  inparts=6  sat=665  derived=659  Cancellation:46,Resolution:327,Substitution:286
ON   ProjectionCost.e(1:1)  inparts=7  sat=7    derived=7    TopNormalise:7
OFF  WildChain.e(144:8)     inparts=6  sat=665  derived=659  Cancellation:42,Resolution:331,Substitution:286
ON   WildChain.e(144:8)     inparts=7  sat=7    derived=7    TopNormalise:7
```

and the `inparts=2` rung of `ProjectionCost` still reads `Resolution:3` ON, which is the `k ≥ 3`
condition doing its job.  `sat = 665 = 3^6 − 2^6` is exact.

Model replay time for the two groups, mine: `Present` **177.6 s → 70.9 s**, `Lang` **16.5 s →
7.0 s** (the report has 165.2 → 60.2 and 15.6 → 7.0; same effect, my machine had a second job on
it).

### 3.4 The seeds

All 20 tracked top-level seeds (including `GROW`), the 7 `unsat/` witnesses and the 15 seeds in
the Part A/S4A scratch — **42 seeds, 0 verdict changes** ON vs OFF, on the FULL solve path
(`--trace`, i.e. `solveSeedP` with `labelCheck` and `rowSoundDecide` on).  Four of them change
the refutation MESSAGE (H-3): `GU3`, `GU4`, `GU6` and `PROJ4U2` — and `PROJ4U2` changes the
FIELD as well, `Repro.l0` → `Repro.l3`.

The ladder on the budgeted census path, re-run from `tracker/repro/satterm/seeds/proj/`:

```
PROJ2  SOLVED drawn=3      -> SOLVED drawn=3      (untouched, k = 2)
PROJ3  SOLVED drawn=30     -> SOLVED drawn=1  (drawn0=1, loop 0)
PROJ4  SOLVED drawn=207    -> SOLVED drawn=1
PROJ5  SOLVED drawn=1230   -> SOLVED drawn=1
PROJ6  SOLVED drawn=6783   -> SOLVED drawn=1
PROJ7  REJECTED drawn=20009 (budget) -> SOLVED steps=8 drawn=1
```

exactly `S4-CHANGE.md` §4.3, and the model's OFF draw counts (30 / 207 / 1,230 / 6,783) equal the
compiler's to the digit on this path.

**`GROW`** is `SOLVED` with **0 loop draws both ways** — the "no concrete row" condition stands
aside and `resRow`/`emptyRow` answer it, as claimed.

### 3.5 The blast radius, re-measured independently (the "19 vs 13")

I re-derived the census from my own OFF traces (`inpart` records; `review-S4B/census.py`), over
`Present` + `Lang` + `Present-shouldfail`, under BOTH keys:

```
PARTITION key (the Part A prototype)  20 solves
DISTINCT  key (Part B, shipped)       14 solves
```

The 14 are the 12 of `S4-CHANGE.md` §5 that live in these groups plus the two new `WildChain.e`
sites; `proj01_seven_reads.e` is absent from an OFF trace because its solve dies at the budget
before the `inpart` block is written, and it is the 15th `tnorm` ON.  So **14 + proj01 = 15 =
the number of `tnorm` records I measured**, and the report's 13 + 2 is the same set.

The six the distinct key excludes are, to the site, the six the S4A review's G-2 named:

```
k=3 kdist=2  Lang/DoNotation.e(329:35)      k=3 kdist=2  Lang/DoNotation.e(335:39)
k=3 kdist=2  Lang/RunningState.e(174:35)    k=3 kdist=2  Lang/RunningState.e(181:41)
k=3 kdist=1  Lang/TextTables.e(246:19)      k=3 kdist=1  Present/FulcrumPanel.e(1:1)
```

and `Present/ValidationReport.e(214:14)` is `k = 5`, `kdist = 4`, again exactly as G-2 said.  So
the report's "**19 → 13**" is right; in today's line numbering and with `WildChain.e` in the tree
the same measurement reads **20 → 14** on these three groups.  G-2 is properly discharged.

### 3.6 The rest of the gate set

| gate | report | mine |
|---|---|---|
| `TestLoopTrace` (MAIN tree) | 720/720, `hashdiff=0 eqdiff=0 skipped=0`, 9.7 s, controls 46 / 58 | **720 solves (20 seeds x 6 bases + 600 generated), 720 agree, `hashdiff=0 eqdiff=0 skipped=0`, 9,643 ms; controls 46 of 720 (base+1) and 58 of 720 (`--flags=nongen`)** — identical |
| model differential OFF, `incomplete/` (per file) | 1,905,368 / 1,905,368, 0 skip | **1,905,368 / 1,905,368, 0 skip**, 35 files, 608 s compiler + 118 s model |
| `corpus-run.sh --batch` verdicts | 83/69 → 84/68 | **83 LOADED / 69 REJECTED → 84 / 68**, 152 files |
| `--batch` per-file outputs | 137 identical, 15 differ (proj01 + 9 clauses + 5 skolem ids) | **137 identical, 15 differ** — `proj01`, nine `shouldfail/` clause moves (`der01 der04 der07 dup03 dup04 inc07 inc08 inf02 inf05`), five `sk0*` skolem-id moves.  Identical composition |
| **per-file sweep of one group ON vs OFF** (the report did NOT run this) | — | **`Present/` + `Present/shouldfail/`, 20 modules: 19 identical, 1 differs**, and the one is `proj01_seven_reads` (rejected → imported).  This settles §4.9 directly: outside `proj01` the 14 batch differences ARE id drift |
| `WildChain.e` alone | 13,566 draws / 1.65 s → 0 / 0.32 s, 2 `tnorm` | **13,566 / 1.79 s → 0 / 0.33 s, 2 `tnorm`** at (144:8) and (168:8); the two firing solves are 6,783 each and the stdlib boot contributes 0 |
| stdlib boot (the workload `perf-bench batch` measures) | 12.36 s → 12.33 s, unmoved | **7.38 / 7.17 s OFF vs 7.34 / 7.28 / 7.46 s ON** (3 reps each, in-process "Loaded 129 modules"), unmoved.  See the note below |
| `slow/GU05` budgeted | SAME, `SOLVED steps=414 drawn=306` | **SAME, `SOLVED steps=414 drawn=306`**, 18 s each side |
| **`slow/GU05MIN` budgeted** (report: NOT COMPLETED) | open | **COMPLETED and SAME**: `SOLVED steps=1138 drawn=256 drawn0=0` both ways, **963 s OFF / 921 s ON**.  Gate closed |
| **`proj/PROJ8` budgeted** (report: killed) | open | **`REJECTED steps=1683 drawn=20009` (budget) → `SOLVED steps=9 drawn=1`**, 93 s OFF / <1 s ON.  Gate closed |

**On `perf-bench`.**  I did not run `tracker/tools/perf-bench.sh`: in the worktree it aborts with
`module tree disagreement` because the checked-in `tracker/repl-classpath.txt` names the main
tree, and regenerating it would edit the worktree, which this review is not allowed to do.  I ran
the measurement it actually reports — the in-process "Loaded 129 modules (X s)" over three fresh
JVMs per side — instead.  It is also worth saying plainly why the harness cannot move: the
stdlib boot has **0** `tnorm` records over **54,523** segments, so `perf-bench batch`'s workload
contains none of the shapes the rule touches.  The report's "unmoved, 12.36 → 12.33 s" is what
must happen, and the informative numbers are the local ones (`WildChain.e` 1.79 s → 0.33 s; the
model's `Present` replay 177.6 s → 70.9 s).

### 3.7 The `.ei` gate — my numbers DIFFER from the report's, and the gate is noisy

`tracker/tools/ei-diff.sh --batch`, side A defaults, side B `-Dermine.topNormalise=true`:

```
report:  225 interfaces,  4 differ,  8 binding lines, order-only 8, substantive 0
mine:    225 interfaces,  6 differ, 36 binding lines, order-only 35, "other" 1
         (+1 interface on side B only: Present/shouldfail/proj01_seven_reads.ei -- expected)
```

The four the report names are in my six (`Present/ProjectionCost.ei`, `Present/Signatures.ei`,
`Layout/Chart.ei`, `Layout/Report.ei`) and my two extra are
`Relation.ei` and `Relation/Op.ei` — **the two files `tracker/TICKET-substitution-gap.md` (line
328) already documents as churning between two runs of the SAME build**, through thread timing
and the solver's id-hash queue, with `lookbackJoin` named as the binding that does it.  My one
`other` verdict is exactly `Relation.lookbackJoin` (constraints 9 → 8), i.e. that documented
churn, not a weakening.

The cause is methodological and applies to both runs: `ei-diff.sh` passes
`ERMINE_JAVA_OPTS="$flags"` with `flags=""` on side A, so **neither side sets
`-Dermine.loadInSeries=true`** and both load in parallel.  A same-configuration control is the
only way to bound that, and `ei-diff.sh`'s own header offers one; I ran it (§3.8 below).

**The substance is unchanged and G-4 is answered.**  `ProjectionCost.ei`:

```
A  proj3 : … a <- ((|pAlpha, pBeta, pGamma|), b) …          proj4 : … (|pBeta, pAlpha, pGamma, pDelta|) …
B  proj3 : … a <- ((|pBeta, pAlpha, pGamma|), b) …          proj4 : … (|pAlpha, pGamma, pBeta, pDelta|) …
```

— the published residual is the SAME single top partition ON and OFF, only the `Set` print order
moves, and the `k` re-expressions do NOT reach the interface.  (The report says `proj3` alone
moved; in my run `proj3` and `proj4` both did.  Order-only either way.)

### 3.8 The `.ei` noise floor — a SAME-CONFIGURATION control

`ei-diff.sh --batch <out> ""` (the control its own header offers: identical flags on both sides):

```
4 of 225 interfaces differ:  Layout/Chart.ei  Layout/Report.ei  Relation.ei  Relation/Predicate.ei
bindings: identical 2521, order-only 16, alpha-equivalent 2, other 1
```

**With no flag change at all, four interfaces differ and one binding is "other".**  Two of the
report's four (`Layout/Chart.ei`, `Layout/Report.ei`) are in the control, and `Relation.ei` is in
both the control and my A/B.  So the `.ei` gate as run has a noise floor of the same order as the
signal, and neither the report's "4 of 225, 8 lines, ORDER-ONLY 8, SUBSTANTIVE 0" nor my "6 of
225, 36 lines, 1 other" isolates the flag.

The report's explanation — "the same `Set`-iteration-order drift the batch mode produces
**whenever ids move**" — is close but not the mechanism: the control shows the drift with the ids
NOT moving.  It is thread timing, which `tracker/tools/g1-diff.sh` and
`tracker/TICKET-substitution-gap.md` line 328 both document, naming `Relation.lookbackJoin`
specifically.  To make the gate mean something both sides need `-Dermine.loadInSeries=true`;
`ei-diff.sh` passes `ERMINE_JAVA_OPTS="$flags"` and side A's `$flags` is empty, so neither side
gets it today.

**What survives the control, and is genuinely the flag:** `Present/ProjectionCost.ei` (order-only
on `proj3` and `proj4`, same top partition) and the new `Present/shouldfail/proj01_seven_reads.ei`
on side B.  That is enough for G-4's question, and the answer stands: the `k` re-expressions do
not reach an interface.

## 4. Trying to break it

I built 29 adversarial seeds (`review-S4B/seeds/H*.json`) and two compiler probes
(`review-S4B/probes/AdvSelf{2,3}.e`) for the shapes the brief names, plus five more the code
suggested.  **On the full solve path every one preserves its verdict.**  The rewrite is a genuine
equivalence and I could not make it accept a satisfiable-looking system that is unsatisfiable, or
the reverse.

| shape | seeds | ON vs OFF |
|---|---|---|
| a remainder `x_i` used elsewhere (`x1 <- (y,{a})`) | `H1` unsat / `H2` sat | verdict SAME (message differs on `H1`) |
| overlapping non-singleton incomparable parts `{a,b} {b,c} {c,a}` | `H3` / `H3U` | SAME |
| the family's lhs is a PART of another partition | `H4` / `H4U` | SAME |
| two families sharing a remainder | `H5` / `H5U` | SAME |
| duplicate abstract var, three different parts (unsat) | `H6` | SAME (field moves `l1`→`l2`) |
| a concrete row one LINK away (`v <- (w)`, `w <- ((|a,b|))`) — the "no concrete row" veto does NOT fire | `H7` / `H7S` | SAME |
| duplicate concrete parts beside three distinct ones | `H9` | SAME |
| one COMPARABLE part added — the trigger must switch off | `H10` | SAME, and no `tnorm`: correct |
| one family's lhs is another family's remainder | `H12` / `H12U` | SAME (2 carriers, `drawn0=2`) |
| infinite row only after substitution (`x1 <- (v,{d})`) | `H13` | SAME |
| the remainder pinned concrete / empty | `H14` / `H15` / `H16` | SAME |
| a fourth read reusing the first's remainder | `H17` | SAME |
| the family's lhs inside another partition's part | `H18` | SAME |
| two remainders linked | `H19` / `H20` | SAME |
| **the SELF-READ, `v <- (v, C)`, inside a k ≥ 3 family** | `H8`, `H8c`, `H21`, `H22` | verdict SAME **at the shipped defaults**, but see H-2 |

### 4.1 H-2 — the one that does break something

Seed `H8`: `v <- (v,{a})`, `v <- (x2,{b})`, `v <- (x3,{c})`.  Unsatisfiable (a row cannot
strictly contain itself), and OFF the LOOP kills it at once:

```
--depth              REJECTED steps=1 drawn=0   "Infinite row partition for 'v0^1000'"
--policy --budget    REJECTED steps=0 drawn=0   "Infinite row partition for 'v0^1000'"
```

ON, the rewrite deletes all three reads — including the self-read — and replaces them with
`v <- (c,{a,b,c})`, `v <- (c,{b,c})`, `x2 <- (c,{a,c})`, `x3 <- (c,{a,b})`.  That system is still
unsatisfiable (two rows at `v` over the same carrier with different concrete parts), but the LOOP
does not see it:

```
--depth              SOLVED steps=4 drawn=2 drawn0=1
--policy --budget    SOLVED steps=4 drawn=2 drawn0=1
```

Same at k = 4 (`H8c`) and with the self-read last (`H21`).  At k = 2 (`H8b`) the rule does not
fire and the loop still refutes — so the loss appears exactly when the rule fires.

**At the shipped defaults nothing escapes**: `labelCheckEarly` / `rowSoundDecide` refute the
rewritten system, and the compiler agrees — `probes/AdvSelf3.e` (the same shape written as a
signature, `r <- ((|a|), r)` beside two ordinary reads) is REJECTED both ways at
`AdvSelf3.e:16:7`.  Only the clause moves:

```
OFF  Row partitions are unsatisfiable at field 'AdvSelf3.a': two parts of one partition both contain it
ON   Row partitions are unsatisfiable at field 'AdvSelf3.a': the whole contains it but no part does   (tnorm=1)
```

Why it matters anyway, in three sentences.  (i) The rewrite is the first rule in this programme
that **deletes** premises the loop can still use — `resolution` derives the very same three
conclusions at k = 2 and leaves the premises in place — and `noloss_of_top` is a SEMANTIC
entailment, which does not carry a syntactic death like `selfSubstitution`'s occurs check or
`RHS.merge`'s duplicate-field check.  (ii) The report's seed gate (§4.3) is run on `--depth` and
`--policy=`/`--budget=`, and **both of those are loop-only paths** — they are precisely where
`H8` flips, so that gate would not have caught a genuine verdict change of this class; it happens
that no report seed contains a self-read.  (iii) The safety net is layer (iii), whose NO-VERDICT
escape on budget exhaustion is documented as "the one condition under which the theorem lapses"
(`Subst.scala:1316`), and `-Dermine.rowSound=false` removes it entirely.

This is not a blocker for a DEFAULT-OFF commit.  It is a blocker for "verdicts are preserved,
full stop", and it belongs in `S4-CHANGE.md` §3 beside the two side conditions.

### 4.2 H-3 — refutation text moves wherever the rule fires

Not a verdict change, but not nothing: on an unsatisfiable input that triggers the rule, the
reported CLAUSE changes in **12 of my 29** seeds and in **4 of the 8** adversarial seeds the S4A
review contributed (`GU3`, `GU4`, `GU6`, `PROJ4U2`), and the reported FIELD changes in five
(`H6` l1→l2, `H13` l3→l0, `H17` l3→l0, `H22` l1→l0, `PROJ4U2` l0→l3).  Confirmed on the compiler
(`AdvSelf3.e` above).

The report attributes all nine `shouldfail` clause changes it saw to `--batch` id drift and shows
the per-group `shouldfail` traces are byte-identical ON vs OFF; both are true, and the reason is
that no corpus `shouldfail` module has a `k ≥ 3` incomparable family.  The general statement is
different and should be written down: **where the rule fires on an unsatisfiable system, the
diagnostic text changes.**  Position is preserved; wording is not.

### 4.3 H-2, on the compiler, with the S2 layers off — the module LOADS

The decisive run.  `probes/AdvSelf3.e` in the worktree with
`-Dermine.labelCheck=false -Dermine.rowSound=false` (both supported switches; `rowSound` is the
master switch for all of S2):

```
OFF   AdvSelf3.e:16:7: Infinite row partition for 'r^303148'
      Unable to load module from '.../AdvSelf3.e' (0.04 seconds)
ON    Importing module 'AdvSelf3' (0.04 seconds)          <-- an UNSATISFIABLE module compiles
```

So it is not only a model-level loop artefact: **on the real compiler, with the S2 layers off, the
rewrite turns a rejection into an acceptance.**  At the shipped defaults (`labelCheck` on,
`rowSound` on) the module is still rejected, and that is the configuration that would ship — but
the report's unqualified "verdicts preserved" is resting on layer (iii), and S2's own comment at
`Subst.scala:1316` calls its NO-VERDICT case "the one condition under which the theorem lapses …
this solve is accepted on the shipped rules alone".  Here the shipped rules alone accept it.

Cheapest fix if adoption is wanted: exclude a read whose remainder is its own left-hand side
(`x == v`) from the family — one clause in `isRead`'s caller, zero corpus cost (no corpus family
has one), and it removes the whole class.

### 4.4 One more asymmetry worth recording: the concrete-row veto is SYNTACTIC

`topFamilies` tests "no concrete row at `v`" against `q0`'s partitions only.  A concrete row that
reaches `v` through a link (`v <- (w)`, `w <- ((|a,b|))`) or through `SubstEnv.types` — which
`solve` deliberately does NOT apply before `PQueue.build`, and which `decideLabels`'s `liveInput`
DOES add as facts — is invisible to it, so the rule fires where `resRow`/`emptyRow` would have
answered at 0 draws.  Not unsound (seed `H7` / `H7S` preserve their verdicts), and it costs one
carrier, but "no concrete row at `v`" in `S4-CHANGE.md` §0 and in the source comment means "no
concrete-row PARTITION at `v` in the freshly built queue", which is a weaker statement than it
reads as.

## 5. Prose, and the adoption question

### 5.1 `S4-CHANGE.md` §5 and the state file — accurate, with two exceptions

§5's "would not change" list checks out: the trigger needs `k ≥ 3` DISTINCT pairwise-incomparable
lone-abstract parts at one lhs with no concrete row there, and on my three-group ON run the rule
fired 15 times against 281,545 segments.  The **13 solves** are right and the "19 vs 13" story is
right: the prototype's partition key fired on six extra duplicate-part shapes, Part B's distinct
key does not, and the 15 `tnorm` records I measured are the 13 plus the two new `WildChain.e`
sites.  I did not re-derive the six excluded sites independently, but I did verify the mechanism
(`dis` is de-duplicated before the `< 3` test) and that `H9`, a duplicate-part family, does still
fire when it has three DISTINCT parts as well — so the exclusion is about counting, not about
refusing.

Two exceptions:

* §5's site list gives `Lang/RunningState.e(210:13)`, `TextTables.e(138:13)`, `(174:23)`,
  `(188:9)`; the ON traces give `(214:13)`, `(141:13)`, `(177:23)`, `(191:9)`.  Both are correct
  — §5 quotes the PRE-edit line numbers and §4.8 the post-edit ones — but the two tables are
  three pages apart in one document and read as a contradiction.
* §1's "**`solve_accepted_faithful` keeps its shape**" is false; see H-1.

The state-file section (`ROW-CONSTRAINT-STATE.md`, the new "NOT adopted, offered" block and the
re-measured budget block) is accurate and, to its credit, harder on the project than it had to
be: the 61x → **2.95x** headroom correction, "and **it does fire**", and the upgrade of the
"give the diagnostic a code" follow-up from cosmetic to real are all right and all supported by
what I measured.

### 5.2 Should `topNormalise` be flipped ON by default?

**Not yet.**  The rule is the right rule — it is `resolution`'s own k-ary generalisation, it is
what a user would write by hand, the equivalence is proved in both directions at the system
level, the ladder goes to one pre-loop draw at every N, and the one shape on which the adopted
budget rejects a valid program disappears.  I would expect to recommend adoption at the next
round.  FOUR things must be true first, and today none of them is.

1. **The four unpatched model call sites must be patched** (H-12) — a one-line change each, and
   without it no ON census over a corpus replay means anything.
2. **`lake build` must be green and `Audit.lean` must print its number again** (H-1).  Non-
   negotiable: today the project cannot state that it has 0 non-standard axioms, and the S2
   no-false-acceptance chain — which is the layer that catches the `H8` class, and the one
   §4.3 shows is load-bearing — is unproved.
   Whichever repair is taken, the resulting theorem must say explicitly whether it covers
   `topNormalise = true`; if it does not, that is a fact about the adoption, not a footnote.
3. **The correspondence lemma** (§2.2): `S4Top.lean` licenses an abstract rewrite; nothing
   licenses `Json.topNormalise`.  Every previously adopted default in this programme (`resGuard`,
   `splitRow`, `resRow`, `smallcanon`) came with the link from the code to the theorem.  A flag
   that DELETES premises should not be the first exception.
4. **The `H8` class must be written down and, ideally, closed** (H-2).  Either state in
   `S4-CHANGE.md` §3 and in the state file that the rewrite costs the loop its syntactic
   refutations and that layer (iii) is the net — including what happens under
   `-Dermine.rowSound=false` and under a layer-(iii) NO-VERDICT — or keep the self-read premise
   (a read whose remainder is its own lhs) out of the family, which is a one-line side condition
   and costs nothing on the corpus.

Two more things that are not blockers but must be in the adoption note:

* **`proj01_seven_reads.e` changes verdict** and must move out of `shouldfail/` (or grow more
  reads) in the same commit; the report says this and it is right.
* **The `.ei` cache does not know about the flag.**  `Constraints.scala:1371` records that
  nothing keys a published `.ei` by `GenRules.toString`, so `+topnorm` changes no interface key.
  Adoption therefore needs the same "clear the interface cache once" instruction the state file
  already carries for `smallcanon`/`solveBudget` — and it needs it more, because this flag
  demonstrably changes published bytes (`ProjectionCost.ei` order-only, plus the new
  `proj01_seven_reads.ei`).

## 6. Findings, ranked

### H-1 — CONFIRMED, **BLOCKS THE COMMIT**.  `lake build` fails; the axiom audit cannot run

`cd tracker/lean && lake build` → `✖ [862/867] Rowpartition.Loop.NoFalseAccept`,
`NoFalseAccept.lean:946:76: unsolved goals`.  Cause: `Seed.solveSeed` now interposes
`topNormalise fl.topNormalise q0 su0'` between `buildQueue` and the checks, and
`solveSeed_rejects_of_refuted` is stated about `buildQueue`'s `q`.  `NoFalseAccept.olean` is
missing, `Rowpartition.olean` and `FlaggedSound.olean` are stale, and
`lake env lean Audit.lean` errors out, so the standing "0 non-standard axioms over the whole
library" gate produces no number.  `S4-CHANGE.md` §1 item 2's claim that
`solve_accepted_faithful` "keeps its shape" is false as delivered.  Minimal repair verified in
`review-S4B/Repro2.lean` (add `fl.topNormalise = false`), which is honest but makes the S2 chain
explicitly not cover the ON configuration; the alternative is the bridge lemma §1 said the
placement avoided.  **Input:** `review-S4B/Repro1.lean` (standalone reproduction),
`review-S4B/lake-build-all.log`.

### H-2 — CONFIRMED, medium.  The rewrite costs the LOOP a refutation, and the report's seed gate runs on exactly the path where that shows

Seeds `H8` / `H8c` / `H21`: a k ≥ 3 family containing a self-read `v <- (v, C)`.  OFF the loop
dies with "Infinite row partition"; ON it SOLVES an unsatisfiable system — on `--depth` AND on
`--policy=`/`--budget=`, the two paths `S4-CHANGE.md` §4.3 uses for its "20 SAME / 7 SAME"
verdict gate.  At the shipped defaults `labelCheckEarly` / `rowSoundDecide` still refute
(checked on the compiler with `probes/AdvSelf3.e`), so no shipped verdict moves — but with
`-Dermine.labelCheck=false -Dermine.rowSound=false` the compiler **LOADS** the unsatisfiable
module ON where it rejects it OFF (§4.3), so the general claim "verdicts preserved" is resting
entirely on layer (iii), which has a documented NO-VERDICT escape and can be switched off.  Root cause is structural and worth stating in the source: this is the first
rule that DELETES premises the loop can still use, and `noloss_of_top` is semantic while
`selfSubstitution`'s occurs check and `RHS.merge`'s duplicate-field check are syntactic.
**Input:** `review-S4B/seeds/H8.json`, `H8c.json`, `H21.json`, `probes/AdvSelf3.e`.

### H-3 — CONFIRMED, medium (adoption).  Refutation TEXT moves wherever the rule fires

12 of my 29 seeds, 4 of the S4A review's 8 (`GU3`, `GU4`, `GU6`, `PROJ4U2`), and the compiler
probe `AdvSelf3.e` all report a different CLAUSE of the same refutation ON, and five change the
reported FIELD.  Position is preserved (`rowUnsat` searches `cs`, which is not rewritten — the
report is right about that).  The corpus does not show it only because no `shouldfail` module has
a `k ≥ 3` family, so `S4-CHANGE.md` §4.9 attributes every clause move it saw to `--batch` id
drift, which is true of those nine and not the general rule.  **Input:** any unsat seed above.

### H-12 — CONFIRMED, medium.  There are NINE live `buildQueue` call sites, not five, and four are still unpatched

The report's §2.2 is the best paragraph in it — "there are FIVE live `buildQueue` call sites and
a mirror must cover all of them", found twice by a `drawn` that did not move.  The count is
wrong, and the same bug is still in the tree.  `Loop/Main.lean` has FOUR MORE executable
`buildQueue` calls, at lines **156, 172, 191 and 236** — `replayCycleOne`, `replayDepthOne`,
`replayPolicyOne` and `replayMintOne`, the CORPUS-REPLAY versions of `--cycle`, `--depth`,
`--policy=`/`--budget=` and `--mints`.  The report patched the `json:`-SEED versions of those
same four instruments (`mainImpl`, lines 486 / 496 / 507 / 527) and left the replay versions
alone; `buildQueueTop` is even defined at line 436, after all four of them.

Measured, on one segment cut from my own OFF trace (`Present/ProjectionCost.e(1:1)`, the
six-read solve):

```
looptrace --replay <seg> --depth                       drawn=6804
looptrace --replay <seg> --depth   --flags=topnorm     drawn=6804   <-- INERT
looptrace --replay <seg> --mints   --flags=topnorm     drawn=6804   <-- INERT
looptrace --replay <seg> --policy=smallcanon --budget=20000 --flags=topnorm
                                                       drawn=6783   <-- INERT
looptrace --replay <seg>           --flags=topnorm     solve … 7 7 7 … TopNormalise:7   <-- runs
```

(the same solve as a `json:` seed under `--policy=smallcanon --budget=20000 --flags=topnorm`
gives `drawn=1`).  So this is exactly the failure the report describes — "`PROJ6.json` under
`--budget=20000 --flags=topnorm` came back `drawn=6783`, i.e. unchanged, which is impossible if
the rewrite ran" — still live, on the replay path.

**No gate in this stage is invalidated**: the corpus differential goes through `replayMain` →
`PolicyReplay.solveSeedP`, which IS patched, and my ON differential agreed 100 % on three
groups.  What is broken is every ON census over a corpus replay — which is how the E-series and
D1/L5 measure the corpus, and how anyone will measure the rewrite's effect on it next.  Four
lines, the same `buildQueueTop fl` the other four call sites use.

### H-4 — CONFIRMED, minor.  The `sin` record does not carry `topNormalise`

D1/A1 put `dequeuePolicy` and `solveBudget` on the `sin` record precisely so a replay applies the
configuration the trace was taken under (`RowTrace.scala:344-347`).  `topNormalise` is not there,
so an ON trace replayed without `--flags=topnorm` diverges instead of reproducing — which is
loud, but it is also exactly the failure mode that hid the `solveSeedP` omission for a while.
One field, same place, and the `Loop/Replay.lean` parser is already positional-with-wildcard.

### H-5 — CONFIRMED, minor.  `WildChain.e`'s own header gives the wrong sites

The module header's table says `wildChain (140:8)` and `wildHelpers (164:8)`; the bindings are at
142-144 and 166-168 and the `tnorm` records name **(144:8)** and **(168:8)** (as `S4-CHANGE.md`
§4.8 does).

### H-6 — CONFIRMED, minor.  One module still carries the round-1 ladder

`core/examples/Present/shouldfail/proj01_seven_reads.e:9-10` still says "about **six times** as
much per additional read: **3 / 30 / 212 / 1,232 / 6,804**".  §7.2's sweep corrected exactly this
sentence in `ProjectionCost.e`, `Helpers.e`, both READMEs, `TextTables.e`, `RunningState.e` and
`ProjectionCliff.slow`, and missed the one module whose whole subject is the ladder.  It is also
the module that changes verdict at adoption, so it will be edited anyway.

### H-7 — CONFIRMED, minor.  "18 declarations" is 18 audited theorems out of 22 declarations

`S4Top.lean` has 22 declarations; 18 carry `#print axioms`.  All 18 are clean.  The phrase is
repeated in `S4-CHANGE.md` §2.3, the plan row and `ROW-CONSTRAINT-STATE.md`.

### H-8 — CONFIRMED, minor but adoption-relevant.  The `.ei` cache cannot tell the flag apart

`Constraints.scala:1371` already records that nothing keys a published `.ei` by
`GenRules.toString`, so the new `+topnorm` token changes no interface key.  Pre-existing (A1
review R-4), but this flag changes published bytes, so the "clear the interface cache once"
instruction is load-bearing for it.

### H-9 — CONFIRMED, medium (Lean).  No correspondence lemma from the code to `S4Top.lean`

`S4Top.lean` is entirely about an abstract `System` and a hypothesised family; nothing ties it to
`Loop/Json.lean`'s `topFamilies` / `topNormalise` — not the trigger, not `F = ⋃ F_i`, not the
freshness of the carrier with respect to the whole system, not the one-pass fold.  Every adopted
default in this programme so far came with that link.  Stated here because `S4-CHANGE.md` §6
lists the missing `LoopStrict` constructor as the Lean gap and this one is the larger of the two.

### H-10 — CONFIRMED, medium (methodology).  The `.ei` gate has a noise floor as large as its signal

A same-configuration control (`ei-diff.sh --batch <out> ""`, identical flags on both sides) gives
**4 of 225 interfaces differing**, 16 order-only + 2 alpha-equivalent + **1 "other"** binding
lines, and two of them (`Layout/Chart.ei`, `Layout/Report.ei`) are two of the four the report
attributes to the flag.  `ei-diff.sh` sets `ERMINE_JAVA_OPTS="$flags"` with side A's `$flags`
empty, so neither side gets `-Dermine.loadInSeries=true` and both load in parallel; the resulting
churn is the one `tracker/tools/g1-diff.sh` and `TICKET-substitution-gap.md:328` document, naming
`Relation.lookbackJoin`.  The report's reading ("the same `Set`-iteration-order drift the batch
mode produces **whenever ids move**") is not the mechanism — the control has no id movement at
all.  My own A/B reads 6 of 225 / 36 lines / 1 "other" for the same reason.  What survives the
control and IS the flag is `Present/ProjectionCost.ei` (order-only) and the new
`proj01_seven_reads.ei`, which is enough to answer G-4 and is the part of §4.10 that stands.

### H-13 — observation, not a finding against Part B

`tracker/LOOP-MODEL-HANDOFF.md` was `M` (uncommitted) when this review started and is identical
to `HEAD` now, with an mtime of 13:29 today.  Nothing this review ran touches it.  Flagging it so
whoever collects the S4 deliverables notices that the handoff edit is no longer in the tree.

---

## 7. Every number of mine that differs from `S4-CHANGE.md`

| | report | mine | why |
|---|---|---|---|
| `.ei` A/B | 4 of 225, 8 lines, order-only 8, substantive 0 | **6 of 225, 36 lines, order-only 35, "other" 1** | H-10; the control's floor is 4 / 19 / 1 |
| `.ei`, which bindings moved in `ProjectionCost.ei` | `proj3` | **`proj3` and `proj4`** | both order-only |
| `slow/GU05MIN` budgeted | NOT COMPLETED (> 30 min per side) | **COMPLETED: 963 s OFF / 921 s ON, SAME (`SOLVED steps=1138 drawn=256`)** | gate closed |
| `proj/PROJ8` budgeted | killed | **`REJECTED@20,009` → `SOLVED steps=9 drawn=1`**, 93 s / <1 s | gate closed |
| ladder OFF, N = 9 / N = 10 | "—" | **REJECTED at 20,009, both** | the report only ran ON there |
| model replay, `Present` | 165.2 s → 60.2 s | **177.6 s → 70.9 s** | machine load; same ratio |
| model replay, `Lang` | 15.6 s → 7.0 s | **16.5 s → 7.0 s** | same |
| `WildChain.e` import | 1.65 s → 0.32 s | **1.79 s → 0.33 s** | same |
| `perf-bench batch -n 3` | 12.36 s → 12.33 s | **not run** (worktree `repl-classpath.txt` names the main tree and I may not edit it); the in-process boot number is **7.38/7.17 s OFF vs 7.34/7.28/7.46 s ON** | unmoved either way, and the boot has 0 `tnorm` over 54,523 segments so it cannot move |
| blast radius | 19 (partition key) → 13 (distinct key) | **20 → 14** over `Present`+`Lang`+`Present-shouldfail` | +2 `WildChain.e`, −1 `proj01` (invisible in an OFF trace); same six exclusions |
| `S4Top.lean` | "18 declarations" | **22 declarations, 18 audited** | H-7 |
| `WildChain.e` sites | §4.8: (144:8), (168:8) — right; module header: (140:8), (164:8) — wrong | **(144:8), (168:8)** | H-5 |
| `rsound ok` timing field | "the last field is `micros`" | **second to last** (the last is `RowTrace.log`'s thread id) | a normaliser masking `$NF` masks the wrong column |
| `lake build` | not run (only `lake build looptrace`) | **FAILS** | H-1 |
| live `buildQueue` call sites in the model | "FIVE … a mirror must cover all of them", all five patched | **NINE**, four still unpatched (`Main.replay{Cycle,Depth,Policy,Mint}One`), measured inert under `--flags=topnorm` | H-12 |

Everything else I re-ran matched exactly: the `D(N)` ladder 3 / 30 / 207 / 1,230 / 6,783 and the
budget stop at 20,009; `sat = 3^N − 2^N` = 5 / 19 / 65 / 211 / 665; `TopNormalise:7` replacing
`Resolution:327,Substitution:286,Cancellation:46` on the six-read solves; 15 `tnorm` records at
the 15 named sites, byte-exact against the model; 131,248 / 90,694 / 59,602→59,603 segments with
`agree = segments` and 0 skips OFF and ON; 1,905,368 on `incomplete/`; byte-identity of the
worktree and main-tree OFF traces on both groups; 83/69 → 84/68 with 137 identical and 15
differing outputs of the documented composition; `TestLoopTrace` 720/720 with both controls still
failing; `GROW` 0 draws both ways; 42 seeds with 0 verdict changes.

---

## 8. What this review did not run

* `perf-bench.sh` itself (above).  `core/test` in full — the brief did not ask for it and
  `TestLoopTrace`, the suite this change can affect, is green at 720/720.
* The other 15 corpus groups, OFF and ON.  The brief scoped this to 3 + 2 groups; the rule fires
  on none of the 15 by construction (`k ≥ 3` incomparable lone-abstract at one lhs), the report
  measured them, and my `incomplete/` run (1.9 M segments, the largest group) agrees exactly.
* A second `.ei` A/B with `-Dermine.loadInSeries=true` on both sides, which is what H-10 asks for.
---

## 9. Reproduction

```bash
# Lean (MAIN tree)
cd tracker/lean
export PATH=$HOME/.elan/bin:$PATH; export LEAN_NUM_THREADS=2
lake env lean ../loopmodel/S4Top.lean          # 18/18 standard axioms, 1.8 s
lake build                                     # H-1: FAILS at Loop/NoFalseAccept.lean:946
lake env lean Audit.lean                       # H-1: cannot load NoFalseAccept.olean
lake env lean <scratch>/Repro1.lean            # H-1 standalone; Repro2.lean is the repair

# the compiler ladder (worktree), one JVM per rung
<scratch>/ladder.sh off ; <scratch>/ladder.sh on

# the adversarial seeds, FULL solve path (this is the path the report's gate does not use)
LT=tracker/lean/.lake/build/bin/looptrace
$LT <scratch>/seeds/H8.json 1000 300000 --trace [--flags=topnorm]
$LT <scratch>/seeds/H8.json 1000 300000 --policy=smallcanon --budget=20000 [--flags=topnorm]
$LT <scratch>/seeds/H8.json 1000 300000 --depth [--flags=topnorm]

# the adversarial compiler probes (worktree)
ERMINE_JAVA_OPTS="... [-Dermine.topNormalise=true]" bin/ermine <scratch>/probes/AdvSelf3.e

# the corpus gates
LOOPTRACE_BIN=$MAIN/tracker/lean/.lake/build/bin/looptrace LOOPTRACE_GROUPS="Present Lang" \
  tracker/tools/looptrace-corpus.sh <out>                          # OFF, from each tree
LOOPTRACE_JAVA=-Dermine.topNormalise=true LOOPTRACE_FLAGS=--flags=topnorm \
  LOOPTRACE_GROUPS="Present Lang Present-shouldfail" tracker/tools/looptrace-corpus.sh <out>
python3 <scratch>/norm.py <A>/traces/<g>.tsv.gz <B>/traces/<g>.tsv.gz   # tree prefix + rsound col 7
```

State on disk: nothing outside the scratch directory and this file was edited.  Every `.ei` this
review produced was deleted in both trees (`find core/examples -name '*.ei' -delete`, which
`looptrace-corpus.sh` and `corpus-run.sh` also do themselves).
