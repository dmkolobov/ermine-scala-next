# S4 Part B — the written-partition normalisation, behind `-Dermine.topNormalise`

Stage S4 of `tracker/LOOP-MODEL-PLAN.md`, ticket B5.  Part A is `tracker/loopmodel/S4-DESIGN.md`
(round 2, corrected against `S4A-REVIEW.md`, whose verdict was **ADVANCE with changes**).  This
document is Part B: the **flagged Scala change, DEFAULT OFF**, its placement decision, its model
mirror, and the gates.

Worktree `~/research/ermine/ermine-scala-wt-s4`, branch `top-normalise`, from `4a9ed4b`.
Model mirror and all Part A corrections are in the MAIN tree (`scala3-migration`, uncommitted).
**No commits.**  Adoption is the user's.

---

## 0. What it does, in one screen

`Record.(!)` is a row PARTITION.  N reads `p ! f_i` of one record parameter whose row is a
VARIABLE hand `Subst.solve`

```
    t <- ((|f_1|), c_1)   …   t <- ((|f_N|), c_N)
```

— N lone-abstract premises at one left-hand side with pairwise-disjoint singleton concrete
parts.  `resolution` closes them by walking the whole subset lattice, and since `countDraw()` is
taken before the applicability test and before all three guards, the budget's unit is the number
of same-lhs PAIRS COMPARED:

```
    D(N) = (5^N − 3·3^N + 2·2^N) / 2       exact on this compiler for N = 2…8
         = 3 / 30 / 207 / 1,230 / 6,783 / 35,910 / 185,727
```

×5 per extra read, so at N = 7 a **valid** program is rejected by the adopted
`solveBudget=20000` at 20,009 draws.

With `-Dermine.topNormalise=true`, when one left-hand side `v` carries **k ≥ 3** lone-abstract
partitions whose **distinct** concrete parts are pairwise **incomparable** and non-empty, and `v`
has **no concrete row** of its own, the k reads are REPLACED by

```
    v   <- (c, F)            F = F_1 ∪ … ∪ F_k,  c fresh
    c_i <- (c, F \ F_i)      for each read
```

— the 0-draw form the user could have written.  Measured on the compiler:

| N | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| loop draws OFF | 3 | 30 | 207 | 1,230 | 6,783 | **budget** | **budget** | — | — |
| loop draws ON | 3 | **0** | **0** | **0** | **0** | **0** | **0** | **0** | **0** |
| module import ON | 0.04 s | 0.03 s | 0.03 s | 0.03 s | 0.03 s | 0.03 s | 0.03 s | 0.04 s | 0.04 s |

(N = 2 is untouched by the `k ≥ 3` condition.  The carrier is minted BEFORE the loop, so — like
`PQueue.build`'s own mint — it is not counted by `GenRules.countDraw()`; the model's
`drawn − drawn0` is 0 to match.  Ten reads of one record now compile in 0.04 s where seven did
not compile at all.)

---

## 1. (G-3) WHERE IT RUNS, and why — the design decision of Part B

`Subst.solve` reads its input FOUR times, not once (`Subst.scala:1301-1305`, the review's G-3):

```scala
val (q, esp) = PQueue.build(Exists(l, List(), cs))
...
if (GenRules.labelCheckEarly) checkLabels(q.toList.map(_.tup))  // (a) unit propagation, INCOMPLETE
if (GenRules.rowSoundDecide)  decideLabels()                    // (b) COMPLETE per-label decision,
                                                                //     live input = q + env facts,
                                                                //     budgeted, NO-VERDICT escape
var ps = q.expand.toList                                        // (c) the loop
if (GenRules.rowSoundSat)     checkSaturated(ps.map(_.tup))     // (d) unit propagation on the CLOSURE
```

(b) and (d) are **DEFAULT ON since 2026-09-06** and Part A named only (a).

**DECISION: the rewrite runs immediately after `PQueue.build`, before all four.**  In the
worktree that is one `val` between `PQueue.build` and `checkLabels`; in the model it is one line
in `Loop/Seed.lean`'s `solveSeed`, at the same point.

**Why there, and not after `decideLabels()`.**

1. **One live input.**  Every check and the loop then see the same system.  The alternative —
   rewrite between (b) and (c) — gives (a) and (b) one system and (c)/(d) another, which is
   exactly the split-brain a no-false-acceptance layer must not have: the layer that is allowed
   to REFUTE would be deciding a system the loop never solves.
2. **The S2 chain keeps ONE `q` — and it now says out loud that it covers the flag OFF only.**
   `Loop/NoFalseAccept.lean:1025` is stated with one `q`, from `buildQueue cs su0 = .ok (q, su1)`,
   and that same `q` appears in `hearly` (`labelClash ns q.elems`), in `hbud`
   (`labelDecide (q.elems ++ envFacts) …`) and in `initState q su1 …`.

   **CORRECTED 2026-09-07 (S4B review H-1).**  Round 1 of this document claimed the placement
   made a bridge lemma unnecessary — "`solve_accepted_faithful` keeps its shape … leaves every
   premise syntactically where it was".  The premises stayed where they were; **the DEFINITION
   they are about moved out from under them**, and `lake build` (the library's default target,
   which `lake build looptrace` does not reach) failed at
   `Loop/NoFalseAccept.lean:946` with `unsolved goals`.  The claim was false as delivered.

   The repair, taken: `solveSeed_rejects_of_refuted`, `solve_noFalseAccept`,
   `solve_accepted_faithful` and their three policy twins in `Loop/PolicyStep.lean` now carry
   **`htn : fl.topNormalise = false`**.  So the honest statement is:

   > **The S2 no-false-acceptance chain covers the flag-OFF configuration — which is the shipped
   > one — and only that.**

   Covering `topNormalise = true` means restating the chain on the REWRITTEN queue and bridging
   it back with the two directions that ARE proved at the system level
   (`S4Top.reads_of_rewrite` / `read_of_top` gives rewritten-`SSat` → original-`SSat` with no
   side condition; `S4Top.ssat_rewrite_fwd` gives the converse with `c ∉ allVars G`).  That is
   an adoption prerequisite and is stage **S4c** (§6), not a default-OFF commit's business.
3. **It is the placement the model can mirror.**  `--replay` reaches `Loop/Seed.lean`'s
   `solveSeed` and nothing else; a rewrite living in the driver (Part A's `Main.lean` prototype)
   is invisible to it and there is no ON-mode corpus differential at all.

**What it does to each of the four, measured rather than assumed.**

| | what changes under the rewrite | measured |
|---|---|---|
| (a) `labelCheckEarly` | k singleton partitions become 1 partition of k labels + k re-expressions.  The propagation is INCOMPLETE, so an equivalence can still change what it sees | verdicts identical on all 27 tracked seeds, the 7 `unsat/` witnesses, `GROW`, the five adversarial projection seeds and the three from Part A: **35 of 35 preserved** (§4.3), and on all 18 corpus groups (§4.4) |
| (b) `rowSoundDecide` | decides the same labels over `k+1` constraints instead of `k`, with one more variable.  Its budget exhaustion is a NO-VERDICT, i.e. a silently missed refutation, so a rewrite that made it dearer could turn a refutation into an acceptance without any theorem lapsing | the input SHRINKS (one partition of k labels replaces k of one), and no `rsound budget` record appears anywhere in the ON corpus (§4.4) |
| (c) the loop | the whole point: `D(N)` draws become 0 | §0 |
| (d) `rowSoundSat` | reads the CLOSURE, which shrinks from `3^N − 2^N` partitions to `k+1` — strictly less to propagate over, so a refutation could in principle be MISSED (never wrongly gained: the rewrite is an equivalence and (b), which is complete, runs first) | verdicts unchanged everywhere above |

**Blame is unaffected, and structurally so.**  `rowUnsat` searches `cs.flatMap(_.rowConstraints)`
— the user's own `Part`s, with their `Loc`s — and `cs` is NOT rewritten; a `Partition` carries no
`Loc` at all.  The one case that moves is a refutation blamed on the fresh carrier, which appears
in no `Part`: the search then falls back to the first candidate `Part` mentioning the field,
still in the user's file.  (This is why "move the blame `Loc`s onto the replacements", Part A's
risk 3, turns out to need no code: the `Loc`s never left.)

**One pass, over the ORIGINAL families** (review G-11).  Every family is read off the queue as
`PQueue.build` left it and the replacements are applied afterwards, so no rewrite can see a
family the input did not have and the answer cannot depend on the fold order.  Candidates are
taken in the QUEUE's own order (`q.toList` in Scala, `q.elems` in the model), so both sides mint
the same ids in the same order.

---

## 2. The change

### 2.1 Scala (worktree `~/research/ermine/ermine-scala-wt-s4`, branch `top-normalise`)

Three files, ~120 lines of which most is the comment block that states the rule, the two side
conditions and the soundness argument in the source where the next reader will be.

* **`Constraints.scala`**
  * `GenRules.topNormalise` — `System.getProperty("ermine.topNormalise", "false")`, DEFAULT OFF,
    and `+topnorm` appended to `GenRules.toString`, so the `--verdict` fingerprint the model
    prints and the compiler's own configuration string stay the same string.
  * `case object TopNormalise extends Inference` — its own provenance tag.  (Part A's prototype
    reused `.resolution`; the review's item 7 asked for this and it is what the trace records
    and the model's `Inference.topNormalise` now agree on.)
  * `private case class TopFamily`, `private def topFamilies`, `def topNormalise`.  The trigger,
    verbatim:

    ```scala
    val cands = ps.filter(isRead).map(_._1).distinct           // queue order
    cands.flatMap { v =>
      if (ps.exists(p => p._1 == v && p._2.abstr.isEmpty)) None        // no concrete row
      else {
        val fam = ps.filter(p => p._1 == v && isRead(p))
        val dis = fam.map(_._2.concr).distinct                          // DISTINCT parts
        if (dis.length < 3) None                                        // k >= 3
        else if (dis.exists(c => dis.exists(d => c != d && c.subsetOf(d)))) None  // incomparable
        else Some(TopFamily(v, fam, dis.reduce(_ ++ _)))
      }
    }
    ```
    `isRead` is `Partition(_, RHS(Single(_), con), _)` with `con.nonEmpty` — lone-abstract with a
    non-empty concrete part, which is exactly `resolution`'s own premise pattern.
  * The carrier is `fresh(loc, none, Ambiguous(Free), Rho(loc.inferred))` and **`countDraw()` is
    deliberately NOT called**: this is a pre-loop mint, like `PQueue.build`'s own, and
    `countDraw` is scoped by `withLoopDraws` around `q.expand`.  That keeps D1's gate exact —
    the compiler's `sdraw` still equals the model's `drawn − drawn0`.
* **`Subst.scala`** — the call, between `PQueue.build` and `checkLabels` (§1), plus the `tnorm`
  trace records.  `esp` is untouched.
* **`RowTrace.scala`** — the record's FORMAT block:

  ```
  tnorm   site  loc  <lhs var>  <fresh carrier>  <(|F|)>
  ```
  printed with `solve`'s own `sv` and `st` helpers, so the model can reproduce it byte for byte.
  It is the FIRST record of a rewritten segment.  Emitted only when the rewrite fires, so a trace
  at the shipped defaults is byte-identical to one taken before S4.

### 2.2 The model mirror (MAIN tree, `tracker/lean/`)

Part A's prototype lived in `Loop/Main.lean`, which `--replay` never reaches.  Part B moved it:

* **`Loop/State.lean`** — `Flags.topNormalise : Bool := false` (+ `+topnorm` in `Flags.toStr`)
  and `Inference.topNormalise` / `"TopNormalise"`.
* **`Loop/Json.lean`** — `topFamilies` and `topNormalise`, the same trigger, the same one pass
  over the original families, the same queue order.
* **`Loop/Seed.lean`** — one line in `solveSeed`, immediately after `buildQueue` and before
  `labelClash` / `labelDecide` / the loop, plus the `tnorm` records prefixed to every outcome's
  record list.
* **`Loop/PolicyReplay.lean`** — **the same line in `solveSeedP`, and it is the one that
  matters.**  `Seed.solveSeed` is NOT the path a corpus replay takes: `Main.lean:354` dispatches
  on the policy and budget the trace's own `sin` record carries, and since A1 those are
  `smallcanon` and `20000`, so every corpus segment goes through `PolicyReplay.solveSeedP`.
  Patching only `solveSeed` left the mirror silently inert on the corpus — the model quietly
  did the full 6,783-draw resolution while the compiler did the rewrite.  **The differential
  caught it**: 56,944 of 56,946 segments agreed and the two that did not were exactly the two
  rewritten solves.  Recorded because the next person to add a rule to the model will make the
  same mistake.

  **There are FIVE live `buildQueue` call sites in the model and a mirror must cover all of
  them**, which is the general form of that mistake: `Seed.solveSeed` (the `json:` seed and
  `--verdict` path), `PolicyReplay.solveSeedP` (**every corpus `--replay` segment**, because the
  trace's `sin` carries `smallcanon`/`20000`), and three in `Main.lean` — the `--policy=`/
  `--budget=` census, `--depth`/`--cycle`, and `--mints`.  The census one was found the same way
  the first was: `PROJ6.json` under `--budget=20000 --flags=topnorm` came back `drawn=6783`,
  i.e. unchanged, which is impossible if the rewrite ran.  All five now go through
  `buildQueueTop fl` or the explicit `topNormalise fl.topNormalise` line.  (`Budget.lean` and
  `Depth.lean` mention `buildQueue` only in theorem statements.)
* **`tracker/tools/looptrace-diff.py`** — `tnorm` added to `KEEP`, so the record is COMPARED
  rather than dropped.  The model mints the carrier itself instead of reading the compiler's, so
  comparing the record proves both sides agree on the family, the carrier id and the union `F`.
  With the flag off neither side emits one, so every pre-S4 differential is unaffected.
* **`Loop/Main.lean`** — `--flags=topnorm`; `--topres` is kept as a spelling of it so Part A's
  reproduction lines still work; the prototype is deleted and `buildQueueTop` now just calls the
  real `topNormalise` for the `--depth`/`--cycle`/`--mints` census paths.

`lake build looptrace`: **Build completed successfully (1,670 jobs)**.

### 2.3 The Lean, corrected (review G-1, item 2 and 3)

`tracker/loopmodel/S4Top.lean` is now **22 declarations of which 18 are audited theorems, 18/18 on the three standard axioms** (the four unaudited are the two `def`s `topAdds`/`topReads` and the two membership helpers `top_mem_topAdds`/`reexpr_mem_topAdds`; S4B review H-7)
(`propext`, `Classical.choice`, `Quot.sound`; no `sorryAx`, no `nativeDecide`).  Added in round 2:

* `setVar_eq_update` — the file is now stated in the library's `setVar`, so `sModels_setVar`
  applies without a rewrite at each use;
* `ssat_rewrite_fwd` — the WHOLE-SYSTEM forward direction with the genuine freshness premise
  `c ∉ allVars G`, the obligation `LoopStrict.sat` discharges for every existing constructor and
  the one round 1 was missing (its `top_sat`/`reexpr_sat` are about the family alone).  This is
  the reviewer's `GapCheck.lean`, adopted;
* `F_subset_of_reads` — `F ⊆ rho v` is not an extra assumption, it follows from the reads;
* **`topAdds` / `topReads` / `topAdd_noLoss` / `topAdd_escapes` / `topDrop` / `mem_topReads`** —
  the rule as **TWO `LoopStrict` steps**, which is what the brief asked and round 1 did not
  answer:
  1. an ADDITIVE mint, shaped like `res : ResStep G G' → LoopStrict G G'`, carrying
     `fresh : c ∉ allVars G`.  `NoLoss` is free (`topAdd_noLoss`); `SSat` is `ssat_rewrite_fwd`;
  2. then `LoopStrict.drop`, deleting the k reads, `NoLoss` discharged by `noloss_of_top`
     (`topDrop` builds the application).
  It is **not** `requeue` — that demands `allVars G' ⊆ allVars G`, which `topAdd_escapes` refutes
  for a genuinely fresh `c` — and never `weaken`.

---

## 3. What the rule does NOT do, and the numbers behind each condition

**`k ≥ 3`, counted in DISTINCT concrete parts.**  At `k = 2` the shipped binary `resolution` IS
this rule — same two conclusions, same single mint — so firing there gains nothing and only
pre-empts the cheaper `cancellation` path; seed `NE6` goes **3 → 10** draws without the
condition.  Counting PARTITIONS rather than distinct parts (what Part A's prototype did) widens
the corpus blast radius from **13 to 19** solves, and the six extra draw 2–5 and gain nothing
(review G-2, re-measured here — the six are `Lang/RunningState.e(174:35)` and `(181:41)`,
`Lang/DoNotation.e(329:35)` and `(335:39)`, `Lang/TextTables.e(243:19)`,
`Present/FulcrumPanel.e(1:1)`).

**No concrete row at the left-hand side.**  That case is `resRow`'s (Stage 5) and `emptyRow`'s
(Stage 7), which answer it at 0 draws.  The condition had no witness at `k ≥ 3` until the review
built one; it is now tracked as `tracker/repro/satterm/seeds/GROW.json` (three pairwise-
incomparable reads at `t` PLUS `t <- ((|f0,f1,f2,f3|))`) and draws **0 both ways**.

**It is one pass, not a fixpoint** (§1).

**It is not a budget change and not a cap.**  Raising `solveBudget` buys one read per ×5 and
the wall clock reaches 99.74 s at N = 9 and 843.90 s at N = 10; moving `countDraw()` past the
applicability test still needs 23,772 at N = 7; a per-record cap breaks `Loop/Strict.lean`'s
`NoLoss`.  All three are measured and rejected in `S4-DESIGN.md` §3.2, §3.2b, §3.3.

### 3.5 What the rewrite costs, beyond draws — the two facts the round-1 report did not state

**(a) It DELETES premises the loop can use, and that is structurally new.**  `resolution` derives
the very same three conclusions at `k = 2` and leaves its premises in place; S4 is the first rule
in this solver that removes them.  `S4Top.noloss_of_top` says the replacements ENTAIL every
deleted read — but that is a SEMANTIC entailment, and two of the loop's own refutations are
SYNTACTIC: `selfSubstitution`'s occurs check ("Infinite row partition for 'v'") and `RHS.merge`'s
duplicate-field check ("Fields appear twice in row").  A rewrite that is a perfect equivalence in
models can still take away the SHAPE the loop was going to die on.

The one class of that found (S4B review H-2) is the **SELF-READ** `v <- (v, C)` with `C`
non-empty: unsatisfiable, killed by the occurs check at once, and — before this round — deleted
by the rewrite when it sat inside a `k ≥ 3` family.  The rewritten system was still unsatisfiable
and the shipped layers still refuted it, but with `-Dermine.labelCheck=false
-Dermine.rowSound=false` the compiler LOADED a module it used to reject.

**It is closed, by one clause in `isRead` on each side**: a read whose lone abstract variable IS
its own left-hand side is not part of a family.  It is then neither counted towards `k` nor
deleted, so the loop still sees it and still dies on it.  Cost on the corpus: **zero** — no corpus
family contains a self-read, and all 15 `tnorm` sites are unchanged.  Measured after the fix:

```
seeds H8 / H8a / H8b / H8c / H21 / H22   REJECTED both ways, on --depth AND on
                                          --policy=smallcanon --budget=20000  (was: 3 SOLVED ON)
probes/AdvSelf3.e, -Dermine.labelCheck=false -Dermine.rowSound=false
   OFF  AdvSelf3.e:16:7: Infinite row partition for 'r^579400'   Unable to load
   ON   AdvSelf3.e:16:7: Infinite row partition for 'r^579400'   Unable to load   <-- identical
probes/AdvSelf3.e at the shipped defaults, ON: rejected at 16:7 with the SAME clause as OFF,
   tnorm = 0 (with the self-read out, the family is k = 2 and the rule does not fire at all)
```

`S4Top.lean` needs **no change**, and the reason is worth stating: its theorems quantify over a
HYPOTHESISED family — they never mention the trigger — so narrowing the trigger cannot invalidate
them, and it was never their soundness that was at stake.  What the self-read cost was the LOOP's
refutation power, which no theorem in `S4Top.lean` is about.

**The residual risk, and the net.**  The self-read is the one class found; a syntactic death the
rewrite hides is the class, and layer (iii) (`rowSoundDecide`, the COMPLETE per-label decision,
default ON) is the net for the rest.  That net has two documented holes: its NO-VERDICT escape on
budget exhaustion (`Subst.scala:1316`, "this solve is accepted on the shipped rules alone") and
`-Dermine.rowSound=false`.  Anyone adopting this flag is relying on layer (iii), and should say
so.

**(b) Where the rule fires on an unsatisfiable system, the DIAGNOSTIC TEXT moves.**  Not the
position — `rowUnsat` searches `cs.flatMap(_.rowConstraints)`, which is not rewritten, so the
`Loc`s are structurally untouched and the reviewer confirmed the position on the compiler.  But
the CLAUSE changes ("two parts of one partition both contain it" → "the whole contains it but no
part does"), and in about a sixth of the unsat seeds the reported FIELD changes too.  Measured by
the reviewer over 29 + 8 seeds: 12 of 29 and 4 of 8 change the clause, 5 change the field.  This
is a real user-visible consequence of adoption and belongs beside the two side conditions.


---

## 4. The gates

### 4.1 The ladder, on the compiler (ON)

`bin/ermine` on `ProbeProj{2..10}.e`, one body per module, one JVM per side,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, shipped budget:

```
OFF   2 3 4 5 6 compile (3 / 30 / 207 / 1,230 / 6,783 draws);  7, 8, 9 and 10 all REJECTED at 20,009
ON    2 3 4 5 6 7 8 9 10 all compile, 0.03-0.04 s each;  loop draws 3 / 0 / 0 / 0 / 0 / 0 / 0 / 0 / 0
```
(the two `—` cells round 1 left at N = 9 and N = 10 OFF are the reviewer's: both REJECTED at
20,009, as `D(9) = 947,550` and `D(10) = 4,795,263` require.)

Eight `tnorm` records, one per rewritten solve (N = 3…10; N = 2 is below `k ≥ 3`).  The one at
N = 6 reads

```
tnorm inferImplicitBindingTypes ProbeProj6.e(1:1) ^307991 ^307998
      (|ProbeProj6.pAlpha,...,pZeta|)
```

**Ten reads of one open-row record now compile in 0.04 s where seven did not compile at all.**

### 4.2 THE WILD-CODE GATE — `core/examples/Present/WildChain.e` (new)

The module the user's brief asked for: a **25-column** fact row, six reads of it spelled three
ways.  Measured on the compiler, this module alone, one JVM per side:

| binding | shape | site | draws OFF | draws ON |
|---|---|---|---|---|
| `wildChain` | six un-annotated **`let`-bound** steps, combined at the end | `(140:8)` | **6,783** | **0** |
| `wildHelpers` | six un-annotated **top-level one-line helpers**, applied at one call site | `(164:8)` | **6,783** | **0** |
| `wildPinned` | the same six under **one written partition** | — | **0** | **0** |
| module total | 2,247 solves | | **13,566** | **0** |
| module import | | | **1.65 s** | **0.32 s** |

Both wild spellings are `D(6) = 6,783` **exactly** — the same number `proj6` costs with all six
reads in one expression.  **The fan does not need the reads in one expression, or even in one
function**: six generalised one-line helpers over a shared row reach the cliff, and a seventh of
either breaks the module at the shipped defaults.  That reproduces, on a realistic 25-column
input, what the S4A reviewer measured on `ProbeWildLet.e` / `ProbeWildChain.e` /
`ProbeWildChain7.e` (6,783 / 6,783 / rejected at 20,009).

ON, two `tnorm` records name the same six-field partition at both sites, and the module's entire
draw bill goes to zero.

### 4.3 The seeds (model, OFF vs ON)

`looptrace <seed> 1000 300000 --depth` both ways, every tracked seed:

| population | result |
|---|---|
| 20 top-level tracked seeds (incl. the new `GROW`) | **20 SAME**, verdict and draw count |
| 7 `unsat/` witnesses | **7 SAME** |
| `slow/GU05` on the BUDGETED path (`--budget=20000`, review G-7: `--depth` is unbudgeted and tested nothing) | **SAME** — `SOLVED steps=414 drawn=306 drawn0=0` both ways |
| `slow/GU05MIN` on the budgeted path | **COMPLETES and is SAME** (closed by the S4B reviewer, §7): `SOLVED steps=1138 drawn=256 drawn0=0` both ways, **963 s OFF / 921 s ON**.  Round 1 killed it at 30 minutes to free the machine and recorded it as open; it simply needed longer |
| the ladder on the BUDGETED path | `PROJ5` 1,230 → **1**, `PROJ6` 6,783 → **1** (`drawn0=1` in both, so the LOOP draws 0), `PROJ7` **`REJECTED steps=1683 drawn=20009` → `SOLVED steps=8 drawn=1`**, and `PROJ8` (closed by the reviewer) **`REJECTED@20,009` → `SOLVED steps=9 drawn=1`**, 93 s / <1 s |
| the 5 adversarial projection seeds the reviewer added (`GU3`,`GU4`,`GU5`,`GS1`,`GU6`) | **verdicts all preserved** (REJECTED/REJECTED/SOLVED/SOLVED/REJECTED); draws 3→4, 6→2, 208→4, 32→2, 3→2 |
| Part A's three (`PROJ3U1`,`PROJ4U2`,`PROJ3S1`) | **verdicts preserved**; draws 0→1, 0→1, 3→1 |
| `proj/PROJ2..8` (the ladder) | 3 unchanged; 30/207/1,276/6,794/35,958 → **1** |

**`GROW` is the witness the "no concrete row" condition never had** (review G-13): three
pairwise-incomparable reads at `t` PLUS a concrete row at `t`, **0 draws both ways** — `resRow`
answers it and the rewrite stands aside.

The budgeted path is `Main.lean`'s `--policy=`/`--budget=` census, and it is worth its own row
for two reasons.  It is where G-7 said the slow seeds had to be run — and it is where the FIFTH
`buildQueue` call site was found (§2.2): before that fix `PROJ6 --budget=20000 --flags=topnorm`
came back `drawn=6783`, unchanged, which is impossible if the rewrite ran.  It is also
BASE-INVARIANT (it uses the adopted `smallcanon` order), so it reproduces the compiler's ladder
to the digit — 1,230 and 6,783 — where the `--depth` path's shipped order is base-dependent
(review G-5).

Note the two REJECTED seeds that go `drawn = 0 → 1`: the rewrite spends its carrier before the
refutation fires.  Harmless, and it shows in every differential, so it is stated rather than
hidden.

### 4.4 `core/test` and `TestLoopTrace`

| run | result |
|---|---|
| worktree, flag OFF (the shipped default) | **920 / 922**, 305 s |
| main tree, baseline at the same moment | **920 / 922** |
| `TestLoopTrace` alone, after the seed move (below) | **720 / 720 agree**, `hashdiff=0 eqdiff=0 skipped=0`, 9.7 s; both negative controls still disagree (46 of 720 at base+1, 58 of 720 at `--flags=nongen`) |

Both sides show the same COUNT and one of the two failures is the documented pre-existing
`Constraints.disjunction sound` (generator starvation, `tracker/06-tests.md`).  The other differs
between the two runs and is not the change:

* worktree: `TestInterfaceRoundTrip.new-pipeline cold write, fresh warm read` — its own comment
  says the dep cache is **process-global** and carries other suites' `useInterface` into its
  read closures.  **It passes in isolation** (`core/testOnly …TestInterfaceRoundTrip`: "OK,
  proved property"), so it is a suite-ordering artefact.
* main tree: `TestLoopTrace` — **caused by me, and fixed**: `TestLoopTrace` runs every top-level
  `tracker/repro/satterm/seeds/*.json` at six id bases in ONE child JVM with a **180 s** budget,
  and the seven `PROJ<N>.json` seeds I had added there cost more than the whole budget
  (`PROJ7`/`PROJ8` alone).  They now live in `tracker/repro/satterm/seeds/proj/` (a subdirectory,
  which `listFiles` does not descend into, like `slow/` and `unsat/`), with a `README.md` saying
  why.  `GROW.json` stays at top level — it is free (0 draws) and is exactly what the suite is
  for — which is why the count is **720, not 714**: one more seed at six bases.

### 4.5 The ON differential, first evidence (`Present/WildChain.e`)


Before the 18-group run, the same gate on the one module where the rewrite fires twice — the
worktree's ON trace, replayed by the main tree's model with `--flags=topnorm`:

```
#summary  segments=56946  replayed=56946  skipped=0  hashdiff=0  eqdiff=0  nonpart=1009  rejected=0
AGREE     56946        SKIP 0        hashdiff segments: 0     eqdiff segments: 0
```

**56,946 of 56,946, byte for byte, including both `tnorm` records** — so the model and the
compiler agree not only that a rewrite happened but on which family, which carrier id and which
`F`.  (This is the run that found the `solveSeedP` omission above: before the fix it was
56,944 / 56,946, with the two rewritten solves as the only disagreements.)

### 4.6 The OFF differential — the model, flag off, on all 18 corpus groups

`tracker/tools/looptrace-corpus.sh` in the MAIN tree, the S4 model binary, flags at the shipped
defaults:

| group | segments | agree | skip | | group | segments | agree | skip |
|---|---|---|---|---|---|---|---|---|
| boot | 54,199 | 54,199 | 0 | | Time | 125,100 | 125,100 | 0 |
| top | 92,673 | 92,673 | 0 | | Time-shouldfail | 55,873 | 55,873 | 0 |
| Ai | 83,942 | 83,942 | 0 | | Algebra | 101,005 | 101,005 | 0 |
| Wide | 115,864 | 115,864 | 0 | | Algebra-shouldfail | 55,367 | 55,367 | 0 |
| Wide-shouldfail | 55,777 | 55,777 | 0 | | Lang | 90,694 | 90,694 | 0 |
| Present | 131,248 | 131,248 | 0 | | Lang-shouldfail | 58,779 | 58,779 | 0 |
| Present-shouldfail | 59,602 | 59,602 | 0 | | shouldfail | 56,030 | 56,030 | 0 |
| bugs | 54,235 | 54,235 | 0 | | guide | 54,244 | 54,244 | 0 |
| shouldfail-controls | 54,739 | 54,739 | 0 | | incomplete | 1,905,368 | 1,905,368 | 0 |

**18 of 18 groups, 3,201,992 of 3,201,992 segments, 0 skips.**  The `Flags.topNormalise = false`
path is the shipped model, segment for segment, across the whole corpus.


### 4.7 The OFF byte-identity gate — worktree compiler vs main-tree compiler, 18 groups

The same corpus, the same settings (`-Dermine.useInterface=false -Dermine.loadInSeries=true`,
`-Xmx2g -XX:ActiveProcessorCount=2`, one JVM per group, `incomplete/` per file), traced from the
MAIN tree at `4a9ed4b` and from the worktree with the flag at its default:

```
segments per group: identical in all 18 (3,201,992 total)
raw byte compare:   18 of 18 DIFFER
normalised:         18 of 18 IDENTICAL, 0 differ
```

**The raw difference is two things, neither of them behaviour**, and both are worth naming
because anyone repeating this gate will hit them:

1. the trace's `loc` field carries the **absolute path** of the stdlib module
   (`/home/…/ermine-scala/core/target/…/Monoid.e(3:17)` vs `…/ermine-scala-wt-s4/…`), because the
   loader resolves `core/target/scala-3.3.8/classes/modules` absolutely while the example files
   are named relatively;
2. the `rsound ok` record's **second-to-last** field is `micros` — the wall-clock the S2
   per-label decision spent (`664` vs `650`, `717` vs `649`, …).  The LAST field is the thread id
   `RowTrace.log` appends, so a normaliser masking `$NF` masks the wrong column (S4B review §3.1);
   mine masks field 8.  It is a timing, it differs between any two runs of the same bytes, and the
   corpus differential never sees it because `rsound` is not in `looptrace-diff.py`'s `KEEP`.

With the tree prefix folded and that one field masked, **every one of the 18 groups is byte for
byte the same trace** — 3.2 M segments, `sin`/`step`/`learn`/`in`/`inpart`/`sat`/`solve`/`rsound`
included.  `GenRules.topNormalise = false` makes `q` literally `q0`, so this is guaranteed by
construction and now measured.


### 4.8 The ON differential with the mirror — all 18 corpus groups

`looptrace-corpus.sh` in the worktree with `LOOPTRACE_JAVA=-Dermine.topNormalise=true
LOOPTRACE_FLAGS=--flags=topnorm`, replayed by the MAIN tree's model binary:

**18 of 18 groups, `agree = segments`, `skip = 0`, no diff class on any group.**

| group | segments ON | agree | | group | segments ON | agree |
|---|---|---|---|---|---|---|
| boot | 54,199 | 54,199 | | Time | 125,100 | 125,100 |
| top | 92,673 | 92,673 | | Time-shouldfail | 55,873 | 55,873 |
| Ai | 83,942 | 83,942 | | Algebra | 101,005 | 101,005 |
| Wide | 115,864 | 115,864 | | Algebra-shouldfail | 55,367 | 55,367 |
| Wide-shouldfail | 55,777 | 55,777 | | Lang | 90,694 | 90,694 |
| Present | 131,248 | 131,248 | | Lang-shouldfail | 58,779 | 58,779 |
| **Present-shouldfail** | **59,603** | 59,603 | | shouldfail | 56,030 | 56,030 |
| bugs | 54,235 | 54,235 | | guide | 54,244 | 54,244 |
| shouldfail-controls | 54,739 | 54,739 | | incomplete | 1,905,368 | 1,905,368 |

**`Present-shouldfail` is 59,603 ON against 59,602 OFF** — one extra segment, and it is
`proj01_seven_reads.e` compiling instead of dying at the budget.  That is the one expected
verdict move (§5) and it shows up as a segment count, exactly where it should.

**The rewrite fires 15 times on the whole corpus** (`tnorm` records in the ON traces), and the
sites are the 13 predicted in §5 plus the two in the new `WildChain.e`:

```
Present  8   ProjectionCost.e(1:1) x4, WildChain.e(144:8), WildChain.e(168:8),
             VarianceStyling.e(321:23), ValidationReport.e(214:14)
Lang     6   TextTables.e(141:13), (177:23), (191:9), RunningState.e(214:13),
             FreeReportDsl.e(153:17), ForeignJdk.e(328:3)
Present-shouldfail 1   proj01_seven_reads.e(1:1)
everything else    0
```

Every one of those 15 `tnorm` records matched the model's byte for byte — same left-hand side,
same carrier id, same `F`.

**And the solver gets faster where it fires.**  The MODEL's replay time for the two affected
groups, ON against OFF: `Present` **165.2 s → 60.2 s**, `Lang` **15.6 s → 7.0 s**.  Every other
group is unchanged to within noise.


### 4.9 `corpus-run.sh --batch`, and where the flag really changes a trace

Verdicts over the 152-file corpus, `corpus-verdicts.py`:

```
OFF   83 LOADED, 69 REJECTED, 0 UNKNOWN, 152 total
ON    84 LOADED, 68 REJECTED, 0 UNKNOWN, 152 total
```

**One verdict moves, and it is the one §5 predicts**: `Present/shouldfail/proj01_seven_reads.e`
stops being rejected, because the thing rejecting it was the resource limit.

Comparing the 152 per-file outputs with the progress bar, the wall clocks and the tree prefix
normalised away: **137 identical, 15 differ** — `proj01` itself, **nine `shouldfail/` modules
that report a DIFFERENT CLAUSE of the same refutation** at the same file and (in seven of nine)
the same position, and **five `sk0*` modules that print a different skolem variable id**
(`r^1517399S` → `r^1471319S`).

**Those nine ARE the batch artefact** — but the general rule is different and is stated in §3.5:
**where the rewrite fires on an unsatisfiable system, the diagnostic CLAUSE changes, and
sometimes the FIELD.**  The corpus does not show that because no `shouldfail` module has a
`k ≥ 3` incomparable family; the per-group traces prove the nine are id drift.  Comparing
the 18 full corpus traces OFF (main tree) against ON (worktree), one JVM per group, path and
`rsound micros` normalised:

```
identical OFF vs ON:  boot  top  Ai  Wide  Wide-shouldfail  Time  Time-shouldfail
                      Algebra  Algebra-shouldfail  Lang-shouldfail  shouldfail
                      bugs  guide  shouldfail-controls  incomplete      (15 of 18)
DIFFER   OFF vs ON:   Present (279,658 record lines)   Lang (101,875)
                      Present-shouldfail (31,854)                        (3 of 18)
```

**`shouldfail` is byte-identical ON vs OFF when it gets its own JVM.**  In `--batch` the whole
corpus shares one `Supply`, so `proj01` compiling instead of dying shifts every id after it, and
which clause an order-dependent refutation reports moves with them — the effect
`corpus-run.sh`'s own header documents ("seven modules print a DIFFERENT CLAUSE of the same
refutation") and S3's review recorded as K-2.  Nine modules, same verdict, same field in seven of
nine.  If the flag were ever adopted this is a thing to re-measure per file, not a defect in the
rule.


### 4.10 The `.ei` gate — RE-RUN with a deterministic loader on both sides, and a control

**Round 1's numbers are withdrawn** (S4B review H-10).  `ei-diff.sh` passes
`ERMINE_JAVA_OPTS="$flags"` and side A's `$flags` is empty, so NEITHER side got
`-Dermine.loadInSeries=true` and both loaded in parallel; the thread-timing churn that produces
is documented at `tracker/TICKET-substitution-gap.md:328` and by `g1-diff.sh`, and a
same-configuration control run that way differs on 4 of 225 interfaces all by itself.  Round 1
read 4 of 225 / 8 lines; the reviewer read 6 of 225 / 36 lines; neither isolated the flag.

Re-run with `-Dermine.loadInSeries=true` on **both** sides (a scratch copy of `ei-diff.sh` that
prefixes both `sweep` calls; the tool itself is unchanged), plus the same-configuration control
beside it:

| run | interfaces differing | binding lines | order-only | substantive |
|---|---|---|---|---|
| **same-configuration control** | **0 of 225** | 0 | 0 | 0 |
| **A/B, OFF vs `-Dermine.topNormalise=true`** | **2 of 225** (+1 on side B only) | **5** | **4** | **1** |

**The noise floor is now zero**, so every one of the five lines is the flag.  The four order-only
lines are `ProjectionCost.ei`'s `proj3`/`proj4` (the same top partition, different `Set` print
order) and `Signatures.ei`'s `chartOfSimple`/`unreconciledFull` (identical token multisets).  The
one on side B only is the new `Present/shouldfail/proj01_seven_reads.ei`, because that module
starts compiling.

**And with the noise gone, one SUBSTANTIVE line appears that the noisy runs hid — and it is an
improvement.**  `ProjectionCost.proj6`:

```
OFF  proj6 : forall a. (exists b c. a <- ((|pEpsilon,pBeta,pDelta,pAlpha,pZeta,pGamma|), c),
                                    a <- ((|pEpsilon,pBeta,pDelta,pAlpha,      pGamma|), b))
          => Record a -> String
ON   proj6 : forall a. (exists b.   a <- ((|pEpsilon,pBeta,pDelta,pAlpha,pZeta,pGamma|), b))
          => Record a -> String
```

The OFF residual carries TWO partitions and TWO existentials where one will do: with
`F5 ⊂ F6`, `a <- (F6, c)` already entails `∃b. a <- (F5, b)` (take `b = (F6 \ F5) ⊎ c`), so the
second conjunct is **redundant** — and the first is exactly what ON publishes.  The two
signatures are therefore **equivalent**, and the ON one is the OFF one minus a redundancy that
`mkSimplified` does not remove (it is not a permuted duplicate and not the `a <- (a)` tautology,
so S3's two deletions do not reach it; the Rose memo's rank-3 item, "no entailment test between
surviving partitions", is exactly this).

**So G-4's question is answered twice over.**  The `k` re-expressions `c_i <- (c, F \ F_i)` do NOT
reach an interface — `mkSimplified` collapses them, as it collapses the closure they replace —
and on the one binding where the published residual changes at all, it gets **shorter and
cleaner**: one partition and one existential instead of two.

### 4.11 `perf-bench.sh batch -n 3`, OFF vs ON

The measurement of record, same host, same JVM, `.ei` cleared before each side, load checked by
the harness itself:

| side | cold median in-process | min / max | spread |
|---|---|---|---|
| OFF (shipped defaults) | **12.36 s** | 12.13 / 12.43 | 0.30 |
| ON (`-Dermine.topNormalise=true`) | **12.33 s** | 12.26 / 12.55 | 0.29 |

**Unmoved** — the difference is a tenth of the run-to-run spread, and it is on the right side of
zero.  (S3's runs on this harness were 12.04 / 12.05 s, so the tree has not drifted either.)  The
110-file batch spends only 8,254 + 13,566 of its draws in the shapes the rewrite touches, so a
visible speed-up was never on the cards; where the rewrite fires, the effect is large and local —
`WildChain.e` imports in **0.32 s ON against 1.65 s OFF** (§4.2), and the model's replay of the
`Present` group is **60.2 s ON against 165.2 s OFF** (§4.8).

**One worktree wrinkle worth recording**: `perf-bench.sh` cross-checks the module tree it derives
from `tracker/repl-classpath.txt` against the one `g1-diff.sh` hardcodes, and that CHECKED-IN
classpath names the main tree, so in a fresh worktree it fails with `module tree disagreement`
before running anything.  Regenerating it (`cp target/ermine-classpath
tracker/repl-classpath.txt`) is all it needs; the file is reverted in the worktree so the diff
stays clean.  It also refuses to run at a 1-minute load above 1.5, which is right and which
costs two restarts when the corpus sweeps have just finished.


---

## 5. What adoption would change, and what it would not

**Would not change.**  Any solve with fewer than three pairwise-incomparable lone-abstract
premises at one left-hand side — which is **3,201,961 of the corpus's 3,201,992 segments**.  The
stdlib boot: zero hits.  `Ai/`, `Wide/`, `Time/`, `Algebra/`, `top/`, `bugs/`, `guide/`,
`shouldfail*/`, `incomplete/`: zero hits.  Any left-hand side with a concrete row (`resRow`'s
case).  Any `k = 2` (the binary `resolution`'s case).  The `Supply` sequence outside the
rewritten solves, the blame `Loc`s, `esp`, and the four input-reading checks' order.

**Would change, and these are the 13 solves.**

```
Pinc=7  Present/shouldfail/proj01_seven_reads.e(1:1)   budget-rejected -> WOULD COMPILE
Pinc=6  Present/ProjectionCost.e(1:1)                  6,783 -> 0
Pinc=5  Lang/RunningState.e(210:13)                    1,230 -> 0
Pinc=5  Lang/TextTables.e(138:13)                      1,230 -> 0
Pinc=5  Lang/TextTables.e(174:23)                      1,230 -> 0
Pinc=5  Present/ProjectionCost.e(1:1)                  1,230 -> 0
Pinc=4  Present/ValidationReport.e(214:14)               213 -> 0
Pinc=4  Lang/FreeReportDsl.e(153:17)                     207 -> 0
Pinc=4  Lang/TextTables.e(188:9)                         207 -> 0
Pinc=4  Present/ProjectionCost.e(1:1)                    207 -> 0
Pinc=3  Lang/ForeignJdk.e(328:3)                          30 -> 0
Pinc=3  Present/ProjectionCost.e(1:1)                     30 -> 0
Pinc=3  Present/VarianceStyling.e(321:23)                 30 -> 0
```

plus the two in the new `Present/WildChain.e` (6,783 each) and the ladder probes.

**One negative module would stop failing.**  `Present/shouldfail/proj01_seven_reads.e` is a
`shouldfail` whose failure is a RESOURCE limit, not a type error — its own header says so.  With
the flag on it compiles, which is the point of the change and a verdict change the corpus gate
must therefore EXPECT rather than forbid.  If the flag is ever adopted, that module moves out of
`shouldfail/` (or gains seven more reads); until then it is a `shouldfail` that documents the
cliff, and the ON corpus run reports it as the one expected verdict move.

**What adoption does NOT license.**  The budget stays at 20,000.  With the rewrite on, the
corpus's largest solve stops being a projection cascade and the headroom over the largest
remaining solve (`Wide/ClaimsExperience.e(207:3)`, 385 draws) goes back to ~52×.  The change
removes the one known shape on which the budget rejects a valid program; it is not an argument
for a different budget.

---

## 6. What Part B did NOT do

* **No commit**, in either tree.  The worktree `~/research/ermine/ermine-scala-wt-s4` (branch
  `top-normalise`) holds the Scala; the main tree holds the model mirror, the Lean, the Part A
  corrections and the new example module, all uncommitted.
* **The flag is DEFAULT OFF and this report does not recommend flipping it today.**  It
  recommends the shape; the adoption decision is the user's, and the honest prerequisites are in
  §5 (`proj01_seven_reads.e` changes verdict) and §4.
* **No `LoopStrict` CONSTRUCTOR was added to `Loop/Strict.lean`.**  `S4Top.lean` proves the two
  steps' obligations (`topAdd_noLoss`, `ssat_rewrite_fwd`, `topDrop`, `topAdd_escapes`) and shows
  which constructors they are, but the inductive itself is untouched: adding a constructor
  re-opens every `LoopStrict` case analysis in `Loop/StrictStep.lean` and beyond, which is a
  stage of its own and is only worth doing if the flag is adopted.
* **`mkSimplified` was not changed** — and §4.10 shows it does not need to be: the k
  re-expressions never reach an interface.
* **No correspondence lemma** (S4B review H-9).  `S4Top.lean` is entirely about an abstract
  `System`, `topAdds`/`topReads` and a HYPOTHESISED family; nothing ties it to `Loop/Json.lean`'s
  executable `topFamilies` / `topNormalise` — not the trigger (`k ≥ 3` distinct pairwise-
  incomparable non-self reads, no concrete row), not `F = ⋃ F_i`, not "the carrier is fresh for
  the whole system", not the one-pass fold.  Every previously adopted default in this programme
  shipped that link (`KeyedSplit`'s correspondence lemma `d736bf9`, `K2ResStep.mint_toGRes`,
  `scalaEmptyRes_run`).  **S4's Lean licenses the RULE; it does not yet license the CODE.**
* **Two gates left open, both named.**  `slow/GU05MIN` on the budgeted path did not finish in
  over 30 minutes on either side and was killed to free the machine for `perf-bench` (`GU05`, the
  larger seed, did finish and is SAME); and `proj/PROJ8` on the budgeted path was killed for the
  same reason after `PROJ7` had already shown `REJECTED@20,009 → SOLVED@1`.
* **`corpus-run.sh` was run only in `--batch`** by this report.  The S4B reviewer ran the per-file
  sweep the round skipped — `Present/` + `Present/shouldfail/`, 20 modules — and got **19
  identical, 1 differing, and the one is `proj01_seven_reads`**.  That settles §4.9 directly: the
  14 non-`proj01` batch differences ARE id drift.

---

## 7. S4c — the adoption prerequisites (NOT this round)

Adoption is the user's, and the S4B reviewer's answer to "flip it ON by default?" is **not yet**,
with four conditions.  Two are closed by this fix round (the build, the four call sites) and two
are a stage of their own:

| | what | why it is not this round |
|---|---|---|
| **S4c-1** | **The correspondence lemma.**  Connect `Loop/Json.lean`'s `topFamilies`/`topNormalise` to `S4Top.lean`: that a family the code selects satisfies the theorems' hypotheses (`F = ⋃ F_i`, `F_i ⊆ F`, `fam ≠ []`, the carrier fresh for the WHOLE system, one pass over the original families), and that the queue it returns is `(G ∪ topAdds) \ topReads` | it is the shape of `KeyedSplit`'s `d736bf9` and `K2ResStep.mint_toGRes` — a stage, not a patch |
| **S4c-2** | **The S2 chain at `topNormalise = true`.**  Restate `solveSeed_rejects_of_refuted` / `solve_noFalseAccept` / `solve_accepted_faithful` (and the three policy twins) on the REWRITTEN queue and bridge back with `S4Top.reads_of_rewrite` (rewritten-`SSat` → original-`SSat`, no side condition) and `ssat_rewrite_fwd` (the converse, `c ∉ allVars G`) | today those six theorems carry `htn : fl.topNormalise = false` (§1); a flag that DELETES premises should not be adopted with the no-false-acceptance layer proved only for its OFF setting |
| S4c-3 | Add a `LoopStrict` CONSTRUCTOR for the additive mint, so the rewrite is a `LoopStrictRun` and not two shapes | re-opens every `LoopStrict` case analysis; only worth it if the flag is adopted |
| S4c-4 | The adoption commit itself: move `proj01_seven_reads.e` out of `shouldfail/`, and the "clear the `.ei` cache once" instruction (the cache is not keyed by the flag) | mechanical, but it is a verdict change and belongs with the flip |

---

## Fix round (S4B)

`tracker/loopmodel/S4B-REVIEW.md`, verdict **FIX-THEN-ADVANCE**, 860 lines, H-1…H-13.  Brief
`tracker/loopmodel/briefs/brief-S4-fix.md`.  Everything below is this round's work; §§0–7 above
carry the corrected numbers and prose, and each correction says what it replaced.  **Still no
commit, still DEFAULT OFF.**  H-13 is explained (the orchestrator committed the handoff as
`2862d14`) and is not a finding.

### FR-1 (H-1, the blocker) — `lake build` is GREEN and the audit prints again

The round-1 report ran `lake build looptrace`, whose import closure does not contain
`Loop/NoFalseAccept.lean`.  The library's DEFAULT target does, and it failed:

```
✖ [862/867] Building Rowpartition.Loop.NoFalseAccept
error: Rowpartition/Loop/NoFalseAccept.lean:946:76: unsolved goals
```

because `Seed.solveSeed` now interposes `topNormalise fl.topNormalise` between `buildQueue` and
the checks while `solveSeed_rejects_of_refuted` is stated about `buildQueue`'s queue.
`NoFalseAccept.olean` was missing and `lake env lean Audit.lean` could not run at all.

**The repair, the honest minimal one the reviewer verified** (`review-S4B/Repro2.lean`): six
theorems gain `htn : fl.topNormalise = false`.

| file | theorem | change |
|---|---|---|
| `Loop/NoFalseAccept.lean` | `solveSeed_rejects_of_refuted` | `+ (htn : fl.topNormalise = false)`; proof `simp only [solveSeed, hq, htn, topNormalise, Bool.not_false, if_true, hearly, hflag, href]` |
| | `solve_noFalseAccept` | `+ htn`, threaded into the `refuted` case |
| | `solve_accepted_faithful` | `+ htn`, threaded into `solve_noFalseAccept` |
| `Loop/PolicyStep.lean` | `solveSeedP_rejects_of_refuted` | the same three changes for the policy solve |
| | `solveP_noFalseAccept` | |
| | `solveP_accepted_faithful` | |

Each carries a doc-comment saying what the premise means, so the fact is in the source and not
only in a report.  **Gates:**

```
cd tracker/lean && lake build            Build completed successfully (867 jobs)
lake env lean Audit.lean                 Rowpartition theorems audited: 4118;
                                         declarations using a non-standard axiom: 0
                                         (4119 / 0 on the final bytes, after FR-5)
lake env lean ../loopmodel/S4Top.lean    18 audited / 22 declarations, 0 non-standard
#print axioms on all six touched theorems  [propext, Classical.choice, Quot.sound] x6
```

`S4-CHANGE.md` §1 item 2 is rewritten: **the S2 no-false-acceptance chain covers the flag-OFF
configuration — the shipped one — and only that.**  Covering ON is stage S4c (§7).  I did NOT
attempt the ON bridge in this round: both directions exist at the system level
(`reads_of_rewrite`, `ssat_rewrite_fwd`), but restating six theorems on the rewritten queue and
re-proving their downstream chain is a stage, and the brief's instruction was not to let the
attempt leave the build red.

### FR-2 (H-12) — the four unpatched replay call sites, and a full census

`buildQueueTop` was DEFINED at line 436 of `Loop/Main.lean`, after the four `--replay`
per-segment instruments at 156/172/191/236, so they could not have used it.  The definition
moved above them (now line 153) and all four are patched.  Measured on the reviewer's own
`Present/ProjectionCost.e(1:1)` segment (`review-S4B/one-proj.tsv`):

| instrument | OFF | ON before | ON after |
|---|---|---|---|
| `--replay … --depth` | `steps=686 drawn=6804` | 6804 (inert) | **`steps=7 drawn=1`** |
| `--replay … --mints` | `steps=686 drawn=6804` | 6804 (inert) | **`steps=7 drawn=1`** |
| `--replay … --cycle` | `steps=686 drawn=6804` | 6804 (inert) | **`steps=7 drawn=1`** |
| `--replay … --policy=smallcanon --budget=20000` | `steps=665 drawn=6783` | 6783 (inert) | **`steps=7 drawn=1`** |

**The census the reviewer asked for.**  `grep -n buildQueue tracker/lean/` — every occurrence,
with its disposition:

| disposition | where | count |
|---|---|---|
| **the definition** | `Loop/Json.lean:232` | 1 |
| **executable, applies `topNormalise` INLINE** (they also emit the `tnorm` records) | `Loop/Seed.lean:122` (`solveSeed`), `Loop/PolicyReplay.lean:78` (`solveSeedP`) | 2 |
| **executable, via `buildQueueTop fl`** — the `--replay` per-segment four | `Loop/Main.lean:171/187/206/251` (`replayCycleOne`/`replayDepthOne`/`replayPolicyOne`/`replayMintOne`) | 4 |
| **executable, via `buildQueueTop fl`** — the `json:`-seed four | `Loop/Main.lean:493/503/514/534` | 4 |
| inside `buildQueueTop` itself | `Loop/Main.lean:155` | 1 |
| **theorem PREMISE** `hq : buildQueue cs su = .ok (q, su')` | `Depth:503`, `Budget:211`, `Solve:90,117`, `NoFalseAccept:948,976,1039`, `PolicyTerm:1061`, `Wf:1234,1271,1328,1557`, `NoConc:1645,1660`, `VocFix:1506,1523`, `PolicyStep:2229,2245,2271` | 19 |
| **fixed-seed WITNESS in a proof** (`match … with` / `by rfl`) | `Depth:547,552,556`, `Solve:162,167,171`, `NoFalseAccept:1112,1117`, `Pump:273,421`, `NoConc:1683`, `VocFix:1598,1603,1607` | 14 |
| `simp only [buildQueue]` unfolding | `Wf:1235`, `NoConc:1646` | 2 |
| prose / comments | 17 sites | 17 |

**Eleven executable call sites, all eleven now honour the flag** (2 inline + 8 via
`buildQueueTop` + `buildQueueTop`'s own).  The round-1 report said "five"; the reviewer said
"nine"; the number that matters is that the grep is now exhaustive and its disposition is in this
table.

### FR-3 (H-2) — the SELF-READ is out of the family, in both implementations

The reviewer's `H8`/`H8c`/`H21`: a `k ≥ 3` family containing `v <- (v, C)`.  The self-read is
unsatisfiable and `selfSubstitution`'s occurs check killed it at once; the rewrite deleted it, and
the LOOP then SOLVED an unsatisfiable system on `--depth` and on `--policy`/`--budget`.  At the
shipped defaults the S2 layers still refuted — but with `-Dermine.labelCheck=false
-Dermine.rowSound=false` the compiler LOADED a module it used to reject.

**One clause on each side**, in the same place, `isRead`:

```scala
// Constraints.scala (worktree)
-  case Partition(_, RHS(Single(_), con), _) => con.nonEmpty
+  case Partition(v, RHS(Single(x), con), _) => con.nonEmpty && x != v
```
```lean
-- Loop/Json.lean (main tree)
-  let isRead := fun (p : LPart) => p.rhs.abstrSingle?.isSome && !p.rhs.conc.isEmpty
+  let isRead := fun (p : LPart) =>
+    (match p.rhs.abstrSingle? with | some x => x != p.lhs | none => false) && !p.rhs.conc.isEmpty
```

with the reason written into the Scala source (a 14-line comment: the rule is the first that
DELETES premises, `noloss_of_top` is semantic, the loop's deaths are syntactic).  A self-read is
now neither counted towards `k` nor deleted, so the loop still sees it and still dies on it.

**Re-measured after the fix:**

| | OFF | ON before | ON after |
|---|---|---|---|
| `H8` / `H8a` / `H8b` / `H8c` / `H21` / `H22`, `--depth` | REJECTED | 3 of them SOLVED | **all REJECTED** |
| the same six, `--policy=smallcanon --budget=20000` | REJECTED | 3 of them SOLVED | **all REJECTED** |
| `probes/AdvSelf3.e`, `-Dermine.labelCheck=false -Dermine.rowSound=false` | `AdvSelf3.e:16:7: Infinite row partition for 'r^579400'`, not loaded | **LOADED** | **not loaded — same position, same clause, same id** |
| `probes/AdvSelf3.e`, shipped defaults | rejected `16:7`, clause A | rejected `16:7`, clause B | **rejected `16:7`, clause A — and `tnorm = 0`** (with the self-read out the family is `k = 2` and the rule does not fire) |
| the whole seed set — 29 reviewer + 8 S4A + 3 report + 20 tracked + 7 `unsat/` | | | **64 seeds, 0 verdict changes** on the full `--verdict` path |
| the 15 `tnorm` corpus sites | | | **unchanged, 15** (no corpus family contains a self-read) |

`H8c` and `H21` keep a `k ≥ 3` family among their NON-self reads, so the rule still fires there
(`drawn 0 → 1`) and the self-read still kills the solve: verdict identical, which is the shape the
fix is meant to have.

**`S4Top.lean` needs no change, and the reason is worth stating.**  Its theorems quantify over a
HYPOTHESISED family and never mention the trigger, so narrowing the trigger cannot invalidate
them — and it was never their soundness at stake.  What the self-read cost was the LOOP's
refutation power, which no theorem in `S4Top.lean` is about.  §3.5 above says this in the report's
own voice, and the state file's offered block now carries it too.

### FR-4 (H-3) — the diagnostic text, documented rather than attributed

§3.5(b) states the general rule — where the rewrite fires on an unsatisfiable system the CLAUSE
changes and sometimes the FIELD, while the POSITION is preserved because `rowUnsat` searches the
un-rewritten `cs` — and §4.9 no longer implies the nine corpus clause moves are the general case:
they are `--batch` id drift, the corpus has no `shouldfail` module with a `k ≥ 3` family, and the
per-group traces prove it.

### FR-5 (H-4) — `topNormalise` rides on the `sin` record

`RowTrace.scala` appends it as `sin`'s eleventh column, beside `dequeuePolicy` and `solveBudget`
and for the same reason; `Loop/Replay.lean` parses it into `Segment.topNormalise` (positional,
after the budget, wildcard tail, so old traces keep parsing and read `false`, which is what they
were); `Loop/Main.lean`'s `flush` sets `fl.topNormalise` from the segment, with `--flags=topnorm`
still winning for the `json:` seed path.

```
sin  trySolveOn  …  0  smallcanon  20000  true  t0      (13 fields, was 12)
```

**Measured:** the worktree's ON `WildChain.e` trace replayed by the main tree's model with **no
`--flags=` at all** — `segments=56946 replayed=56946 skipped=0 hashdiff=0 eqdiff=0`, `AGREE
56946`, and the model emitted both `tnorm` records.  Before this change that replay needed the
flag on the command line or it diverged.

**Consequence for the OFF byte-identity gate, stated as the brief asks.**  A worktree trace now
has one more `sin` column than a main-tree trace, so the gate is "identical after masking the new
`sin` column" (together with the two masks round 1 already needed: the tree prefix in `loc`, and
`rsound ok`'s `micros` — which is field 8, the SECOND-to-last, not the last; the last is
`RowTrace.log`'s thread id).  With `sin` field 12 folded away:

```
MASKED-IDENTICAL: Present   593,667 record lines
MASKED-IDENTICAL: Lang      324,719 record lines
```

### FR-6 (H-10) — the `.ei` gate, re-run against a zero noise floor

§4.10 is rewritten and round 1's numbers are withdrawn.  With `-Dermine.loadInSeries=true` on
BOTH sides the same-configuration control is **0 of 225**, and the A/B is **2 of 225 interfaces,
5 binding lines, 4 order-only, 1 substantive** — and the substantive one is an IMPROVEMENT:
`ProjectionCost.proj6`'s published residual loses a redundant second partition and one
existential (`∃b c. a <- (F6,c) ∧ a <- (F5,b)` with `F5 ⊂ F6` becomes `∃b. a <- (F6,b)`;
equivalent, because the first conjunct already entails the second).  That is a stronger answer to
G-4 than round 1 could give, and it was invisible under the parallel-load churn.

### FR-7 (H-5/H-6/H-7/H-8) — the documentation corrections

| finding | file | was | now |
|---|---|---|---|
| H-5 | `core/examples/Present/WildChain.e` header table | `(140:8)` / `(164:8)` | **`(144:8)` / `(168:8)`**, matching the `tnorm` records and §4.8 |
| H-6 | `core/examples/Present/shouldfail/proj01_seven_reads.e:9-10` | "about **six times** … **3 / 30 / 212 / 1,232 / 6,804**" | "about **5.3–6x** … exactly `D(N) = (5^N − 3·3^N + 2·2^N)/2` … **3 / 30 / 207 / 1,230 / 6,783**", and "seven needs 35,910".  §7.2's sweep had missed the one module whose subject IS the ladder |
| H-7 | `S4-CHANGE.md` §2.3, the plan row, `ROW-CONSTRAINT-STATE.md` | "18 declarations" | **"22 declarations, 18 audited theorems"** (the four unaudited are the `def`s `topAdds`/`topReads` and the membership helpers) |
| H-8 | `ROW-CONSTRAINT-STATE.md`, the offered block | — | a new **"AT ADOPTION, TWO THINGS THAT ARE NOT OPTIONAL"** paragraph: clear the `.ei` cache once (nothing keys an interface by `GenRules.toString`, `Constraints.scala:1371`, and this flag demonstrably changes published bytes), and move `proj01_seven_reads.e` out of `shouldfail/` |

### FR-8 (§7 of the review) — the reviewer's closed gates, folded in

* `slow/GU05MIN` on the budgeted path **completes and is SAME**: `SOLVED steps=1138 drawn=256
  drawn0=0` both ways, **963 s OFF / 921 s ON**.  Round 1 killed it at 30 minutes and recorded it
  open; it needed longer, not fixing.
* `proj/PROJ8` budgeted: **`REJECTED@20,009` → `SOLVED steps=9 drawn=1`**, 93 s / <1 s.
* The compiler ladder OFF at **N = 9 and N = 10: both REJECTED at 20,009** — the two cells round
  1 left as "—".
* The **per-file** sweep round 1 skipped: `Present/` + `Present/shouldfail/`, 20 modules,
  **19 identical, 1 differs, and the one is `proj01_seven_reads`** — which settles §4.9's
  attribution directly.
* `rsound ok`'s `micros` is the **second-to-last** field, not the last; a normaliser masking `$NF`
  masks the thread id and leaves the timing in.  §4.7 corrected.

### FR-9 (H-9) — stage S4c

The correspondence lemma and the ON coverage of the S2 chain are written up as **§7** above and
as a plan row (NOT STARTED).  They are the two Lean prerequisites of adoption.

### The gate set, re-run after every change above

| gate | result |
|---|---|
| `lake build` (MAIN tree, default target) | **Build completed successfully (867 jobs)** |
| `lake env lean Audit.lean` | **4,119 theorems audited, 0 non-standard axioms** (4,118 at the FR-1 checkpoint; FR-5 adds one) |
| `lake env lean ../loopmodel/S4Top.lean` | 18 audited / 22 declarations, **0 non-standard**, unchanged by the self-read fix |
| `#print axioms` on the six touched S2 theorems | `[propext, Classical.choice, Quot.sound]` ×6 |
| `TestLoopTrace` (MAIN tree, `.ei` cleared) | **720 solves, 720 segments, 720 agree**, `hashdiff=0 eqdiff=0 skipped=0`, 9,160 ms; controls still fail at 46/720 and 58/720 |
| ON differential with the mirror, `Present` | **131,248 / 131,248**, skip 0 |
| ON differential, `Lang` | **90,694 / 90,694**, skip 0 |
| ON differential, `Present-shouldfail` | **59,603 / 59,603**, skip 0 (OFF is 59,602: `proj01`) |
| the 15 `tnorm` sites | **15, unchanged** by the self-read exclusion — 8 `Present`, 6 `Lang`, 1 `Present-shouldfail`, at the same twelve locations |
| OFF differential, `Present` / `Lang`, both trees | **131,248 / 131,248** and **90,694 / 90,694**, skip 0, from the main tree AND from the worktree |
| OFF byte-identity worktree vs main, masked | **MASKED-IDENTICAL**: `Present` 593,667 and `Lang` 324,719 record lines (masks: tree prefix, `rsound ok` field 8, `sin` field 12) |
| `corpus-run.sh --batch` | OFF **83 LOADED / 69 REJECTED**, ON **84 / 68**, 152 files — the one expected move |
| compiler ladder ON, N = 2…8 | all compile, 0.03–0.05 s each; loop draws **3 / 0 / 0 / 0 / 0 / 0 / 0** |
| the four `--replay` instruments ON | `--depth`/`--mints`/`--cycle` **6,804 → 1**, `--policy --budget` **6,783 → 1** |
| the `sin` round-trip | an ON trace replays byte-exactly with **no `--flags=` on the command line**: 56,946 / 56,946, `hashdiff=0 eqdiff=0`, both `tnorm` records |
| seeds, full `--verdict` path | **64 seeds (29 reviewer + 8 S4A + 3 report + 20 tracked + 7 `unsat/`), 0 verdict changes** |
| the H-2 seeds, `--depth` AND `--policy --budget` | `H8 H8a H8b H8c H21 H22` **all REJECTED both ways** (three of them SOLVED ON before the fix) |
| `probes/AdvSelf3.e`, S2 layers OFF | **rejected ON and OFF**, same position, same clause, same variable id |
| `.ei` control / A/B, deterministic loader | **0 of 225** / **2 of 225, 5 lines, 4 order-only, 1 substantive (an improvement)** |

### Diffs, in one place

```
MAIN tree (the model, the Lean, the docs, the examples, the tools)
  tracker/lean/Rowpartition/Loop/NoFalseAccept.lean   +htn on 3 theorems, 1 simp set, 1 doc block
  tracker/lean/Rowpartition/Loop/PolicyStep.lean      +htn on 3 theorems, 1 simp set
  tracker/lean/Rowpartition/Loop/Json.lean            isRead excludes the self-read
  tracker/lean/Rowpartition/Loop/Main.lean            buildQueueTop moved above the four replay
                                                      instruments; those four patched; the sin
                                                      column read into fl
  tracker/lean/Rowpartition/Loop/Replay.lean          Segment.topNormalise + the sin parser
  core/examples/Present/WildChain.e                   header sites (144:8)/(168:8)
  core/examples/Present/shouldfail/proj01_seven_reads.e   the measured ladder
  tracker/loopmodel/S4-CHANGE.md                      this section, §1 item 2, §3.5, §4.7, §4.9,
                                                      §4.10, §6, §7
  tracker/ROW-CONSTRAINT-STATE.md                     the adoption block, 22/18 declarations
  tracker/LOOP-MODEL-PLAN.md                          S4 row corrected, S4c row added

WORKTREE ~/research/ermine/ermine-scala-wt-s4 (branch top-normalise)
  core/src/.../Constraints.scala                      isRead excludes the self-read (+14-line why)
  core/src/.../RowTrace.scala                         topNormalise on the sin record (+ its block)
```

---

## Applied to the main tree (2026-09-07)

The worktree's Scala diff — `git diff 4a9ed4b -- core/src`, 261 lines over the three files — was
applied to `/home/dmitry/research/ermine/ermine-scala` with `git apply` (clean, no fuzz).  The
main tree's copies of `Constraints.scala`, `Subst.scala` and `RowTrace.scala` were byte-identical
to `4a9ed4b` before the apply and are **byte-identical to the worktree's** after it.  The Lean was
not touched (the mirror, the docs, the examples, the seeds and `looptrace-diff.py` were already in
main).  `git diff --stat` on main is the pre-existing set **plus exactly those three files**.

| gate, on MAIN | result |
|---|---|
| `sbt core/compile` | **rc 0, 0 errors**, 10 s |
| `sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'` | **720 solves, 720 segments, 720 agree**, `hashdiff=0 eqdiff=0 skipped=0`, 9,541 ms; controls still fail at 46/720 (base+1) and 58/720 (`--flags=nongen`) |
| OFF differential, `Present` | **131,248 / 131,248**, skip 0 |
| OFF differential, `Lang` | **90,694 / 90,694**, skip 0 |
| ON differential, `Present` | **131,248 / 131,248**, skip 0 (model replay 157.5 s OFF → **56.3 s** ON) |
| ON differential, `Lang` | **90,694 / 90,694**, skip 0 (15.1 s → **6.5 s**) |
| ON differential, `Present-shouldfail` | **59,603 / 59,603**, skip 0 |
| `tnorm` records ON | **15** — 8 `Present`, 6 `Lang`, 1 `Present-shouldfail`, at the same twelve sites |
| compiler ladder ON, N = 2…8 | all import in 0.02–0.04 s; loop draws **3 / 0 / 0 / 0 / 0 / 0 / 0**, 6 `tnorm` records |
| `corpus-run.sh --batch`, flag OFF | **83 LOADED / 69 REJECTED / 0 UNKNOWN**, 152 files |
| `.ei` afterwards | **0** under `core/examples` and **0** under `core/target/.../classes/modules` in BOTH trees.  The only `.ei` left anywhere are the **143 CHECKED-IN** files under `tracker/g1-baseline/` and `tracker/g1-oracle-tests/`, `git status` clean in both trees.  (The `.ei` A/B sweeps of FR-6 leave stdlib interfaces behind in the tree they run in — `ei-diff.sh` deletes before each side, not after the last — so the worktree's `core/target/.../modules` was swept explicitly.) |

No commit was made in either tree.
