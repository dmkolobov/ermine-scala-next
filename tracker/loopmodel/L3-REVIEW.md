# L3 review — theorems about the loop model

Reviewer agent, 2026-09-04. Target: `tracker/loopmodel/L3-THEOREMS.md` against
`tracker/LOOP-MODEL-PLAN.md` §L3 and `tracker/loopmodel/briefs/brief-L3.md`.
Pre-existing = the staged L2 state (`git diff --cached`). Under review = the unstaged/untracked
`tracker/lean/Rowpartition/Loop/{Wf,Order,Refine,RefineConcrete}.lean`, the four import lines in
`tracker/lean/Rowpartition.lean`, the additive README block, the plan's L3 row, and the report.
Nothing was edited except this file and `/home/dmitry/.claude/jobs/880c725d/tmp/review-L3/`.

**Verdict: FIX-THEN-ADVANCE.** No unsound theorem, no `sorry`, no non-standard axiom, no
misquoted statement: everything the report says is proved IS proved, and I found no theorem made
vacuous by a hidden hypothesis. (iv) is genuinely PROVED and is the strongest part of the stage.
But two of the plan's four acceptance criteria are not met — (i) is missing the branch that
matters most (and four of `LoopRel`'s ten constructors, including every relation the plan
NAMED, are never used by any theorem about `step`), and (ii) is not proved at all — and the
report over-claims in four places. Findings are ranked in §8, the required fixes are in §9,
and the second-round specification the orchestrator asked for is in §6c/§6d. Along the way I
built a seed that exercises (iii)'s second escape and replayed it through the compiler (§5a),
which CONFIRMS the report's classification of it.

---

## 1. Rebuild and re-audit (all re-run by the reviewer)

| command | result |
|---|---|
| `cd tracker/lean && lake build Rowpartition` | **Build completed successfully (837 jobs)**, exit 0. Only style-linter warnings (copyright header, module doc-string position, one long line in `Rowpartition.lean`). No `declaration uses sorry` anywhere in the 10,264-line log. |
| `lake env lean Audit.lean` | `Rowpartition theorems audited: 2834; declarations using a non-standard axiom: 0`, exit 0 |
| `grep -nE '\bsorry\b|\baxiom\b|\bpartial\b|native_decide|implemented_by|\bunsafe\b|\bopaque\b|Classical|extern'` over `Wf.lean Order.lean Refine.lean RefineConcrete.lean` | **zero hits in all four files** |
| `#print axioms` on 48 headline theorems, my own scratch file `review-L3/RevAxioms.lean` (a superset of the implementer's 33) | 48/48 report exactly `[propext, Classical.choice, Quot.sound]`; no other axiom line, no elaboration error |

The report's build (837) and audit (2834 / 0) figures are exact. `Classical.choice` here is the
Mathlib-standard axiom, not `Classical` reasoning inside the model: the model's definitions are
all computable and `lake exe looptrace` runs.

## 2. Re-run of the report's evidence, plus more

| population | report | reviewer's re-run |
|---|---|---|
| tracked seeds `W2 W3 W4 G7 H2 NE6 CHAIN COLL LBL RR RE` × bases 0/3/7, fuel 2000 | 33/33 `SOLVED`, 0 `FUEL` | **33/33 `SOLVED`, 0 `FUEL`** — identical |
| 400 generated satisfiable systems × bases 0, 5 | 800/800 `SOLVED` | **800/800 `SOLVED`** |
| the same 400 at `--flags=emptyrow`, `--flags=all`, `--flags=nongen` (base 0) | 1200/1200 `SOLVED` | **1200/1200 `SOLVED`** |
| NEW (not run by the implementer): the 400 at **bases 11 and 23**, and at `--flags=all` base 5, `--flags=emptyrow` base 11, `--flags=disj` base 0 | — | **2000/2000 `SOLVED`, 0 `FUEL`, 0 `REJECTED`** |

So the empirical half of (ii) reproduces and extends: 4,033 runs, no fuel exhaustion.
`(scratch: review-L3/fuzz.txt, review-L3/fuzzrun.sh)`

## 3. (iv) Well-formedness — PROVED, and I could not weaken it

Checked side by side against `Loop/Bridge.lean`:

* `Bridge.LPart.eqv_iff_toConstraint` (Bridge.lean:390-393) takes exactly `hpa hqa hpc hqc`
  (four `Nodup`s) and `hcoh : LblCoh (p.rhs.conc.elems ++ q.rhs.conc.elems)`. `Wf` (Wf.lean:1021)
  supplies the first four through `POk` and the fifth through `LblCoh.mono` from
  `LblCoh s.labels` — legitimate, because `COk.sub` puts every partition's labels in
  `s.labels`. **`Wf` is neither weaker nor stronger than what the bridge needs.**
* `step_wf` (Wf.lean:1049) is about the REAL `step`; it goes through `step_qok` (Wf.lean:943),
  which I read in full: it splits on all five dispatch branches of `Step.lean:314` — `common`,
  `empty`, `concrete`, `unify`, `learn` — and discharges each with the corresponding
  `*_ok` lemma. The `learn` branch is covered here (unlike in (i)). The pool-shrinking argument
  (`s'.labels ⊆ s.labels`, then `wf_of_nodup`) is correct and is what makes the fixed-pool
  `step_qok` enough.
* `wf_seed` / `wf_replay` build the state `Seed.lean:134-136`'s `st0` verbatim, with `su0`
  generalised from `su0.lo` to an arbitrary `lo` (a strengthening, not a hole).
* `LPart.eqv_iff_toConstraint_of_wf` (Wf.lean:1102) really has no side hypotheses beyond `Wf s`
  and membership in `s.parts`. **L1 review F6 and L2 review F5 are discharged.**

Non-defect worth recording: `wf_replay` carries the extra hypothesis
`∀ c ∈ g.cons, CsItem.SetsOk c` (report F1). I confirm the diagnosis — `Replay.parseTerm` keeps
a repeated label index in an `scon` payload, and `RowTrace` prints that payload from a Scala
`Set`, so no real trace can contain one. It is a one-line decidable check the model does not
perform. The plan's wording is "every initial state `Seed`/`Replay` builds"; strictly this is
`Replay` initial states *that satisfy a decidable side condition*. I score (iv) **PASS** and
list the check as a cheap follow-up (§8 F5).

## 4. (i) Refinement — the statements are honest; the gap is where the report says it is

### 4a. `sys` does not drop anything
`sys s = (s.parts.map LPart.toConstraint).toFinset ∪ s.env.sys` with
`s.parts = incm.elems ++ proc.elems` (Refine.lean:287, Wf.lean:1008). Both queues and the whole
environment are in it. Against the Scala: the only places a solve's facts live are the two
`PQueue`s and `hm.types`, and `hm.types` receives exactly two shapes from inside the loop —
`VarT(u)` from `instantiate` (`Constraints.scala:1537`) and `ConcreteRho(Loc.builtin, Set())`
from `makeEmpty` (`Constraints.scala:1579`); `makeConcrete` deliberately writes nothing
(`Constraints.scala:1392-1393`). `EnvVal.toConstraint` covers precisely those two. **There is no
"`sys` drops constraints so soundness is easy" problem**: a bigger `sys s` makes the hypothesis
of `step_sat` harder, not easier, and `sys` is complete.

### 4b. The new `LoopRel` constructors — each checked against the Scala
| constructor | Scala it stands for | verdict |
|---|---|---|
| `renameLhs` | `replace`, `Constraints.scala:1526` — `Partition(f(z), RHS(abs.map(f), con), inf)` rewrites the LEFT-hand side too | sound (`renameLhs_sat`, Refine.lean:374); `a = b` and `a = ⊎S ⊎ K` gives `b = ⊎S ⊎ K`. Genuinely absent from the calculus — `SubstStep` only rewrites the right. Correct new constructor. |
| `linkSymm` | `incorporateAll`'s lone-variable branch, `Constraints.scala:1130`: `case RHSAbstr(Single(u)) => unify(u, v, ...)` — the ARGUMENTS ARE SWAPPED relative to the common branch, so a dequeued `v <- (u)` kills `u`, i.e. the link is read backwards | sound (`linkSymm_sat`); correct, and it is a real asymmetry of the Scala the relations do not have |
| `emptyProp` | `makeEmpty`'s `aux`, `Constraints.scala:1564`: `RHSAbstr(abstr) => abstr.map(v => Partition(v, RHSEmpty(), PartitionEmpty))` | sound (`emptyProp_sat`); one conclusion at a time where `makeEmptyD.propPart` does all of them — a weaker constructor, therefore safe |
| `dedup` | two sites: `RHS.merge`'s returned `aint` (`Constraints.scala:337,340`) via `subPartitions` (`:1592`), and `replace`'s two-element queue (`:1527-1528`) | sound (`dedup_sat`); I checked it covers BOTH sites — for `replace` the second premise is the link `mk v {u} ∅` itself, which is how `replace_run` (Refine.lean:735) instantiates it. Correct. |
| `weaken : G' ⊆ G → LoopRel G G'` | every deletion: `instantiate`'s `partition`+drop, `makeEmpty`'s `procd`, `destructiveSub`'s `filter p`, and every `trim` / `++!` / self-unification drop | sound (`SModels.mono`), but see F1 below |

The two candidates the report says need no new constructor check out: `Q.insert`'s redirect
(`Constraints.scala:513-518`) really is `SplitNecessary.CommonPartStep` (`insertP_run`), and
`replace`'s right-hand rewrite really is `SubstStep` at `d = mk a {b} ∅`.

### 4c. What `step_refines_nonlearn` actually says
`NonLearnStep s` (RefineConcrete.lean:598) is exactly the negation of the `learn` guard of
`Step.lean:314` — `findRHS` hit, or `isEmpty`, or `abstr.isEmpty`, or `single?` — so the theorem
covers `common`, `empty`, `concrete`, `unify` and nothing else, as claimed. I read the proof: it
is not vacuous, it ends in a real `LoopRun` witness (`makeConcrete_run` gives an intermediate
`H` with `sys s ⊆ H`, then one `weaken` down to `sys s'`), and `step` is the real `step`.

**No hidden hypothesis makes any of this trivial.** `Wf` is not stronger than `Seed`/`Replay`
establish (§3), `LoopRel` has no "add anything" constructor, and the `died` lemmas are real
semantic refutations (I checked all four proofs; e.g. `merge_refutes` needs
`(K ∩ K').Nonempty`, which is exactly `cint.nonEmpty` at `Constraints.scala:339`).

---

## 5. (iii) The Stage 7b question — the answer is right; one escape is proved only under a hypothesis

Read side by side: `Constraints.scala:1084-1085` (`trim`) ≡ `Loop/Queue.lean:222`;
`Constraints.scala:1138` (`rest ++! trim(learned, proc), proc + r`) ≡ `Step.lean:353-356`;
`Constraints.scala:491-519` (`Q.insert`, the redirect at 513-518) ≡ `Queue.lean:163-181`
(`insertNP`/`insertP`). Every detail the (iii) argument leans on checks out:

* `trim` filters on `PQueue.contains` = `Partition.equals` (which ignores the `Inference` tag,
  `Constraints.scala:1062-1067`) — so `trim_refuses` is the right lemma;
* `trim(learned, proc)` really uses the OLD `proc` and `proc + r` really happens afterwards,
  so the dequeued partition really is the first escape;
* the redirect really recurses with `process = false` (`Constraints.scala:516`) and really
  refuses `RHSEmpty()`/`RHSAbstr(Single(_))` (`:483-484`), and really produces
  `Partition(v, RHSAbstr(Set(p._1)), CommonPartition)` — a lone-variable RHS, which
  `incorporateAll`'s dispatch (`:1130`) sends to `unify`, never to `learnPartitions`. So
  escape 2 is correctly classified as benign, by a syntactic argument I can check on both
  sides. **PASS.**

### F3 (MODERATE, CONFIRMED by reading) — escape 1's "self-cancelling" is proved only when the lookup returns the SAME left-hand side
`common_self_drops` (Order.lean:515) takes the hypothesis
`s.proc.findRHS x.rhs = some x.lhs`. The report's prose (§3, escape 1) asserts the stronger
"at its next dequeue `proc.findRHS` finds `r`, the COMMON branch fires at `u = r.lhs`", and the
README repeats it. That is **not proved and is not always true**: `findRHS` returns the lhs of
the FIRST queue element with an equal RHS, and `proc` can acquire a SECOND partition with an
RHS equal to `r`'s after `r` joined it, because two of the four writers of `proc` use the
NON-processing insert — `makeConcrete`'s `nproc + Partition(v, RHSConcr(fs))`
(`Constraints.scala:1614`) and `destructiveSub`'s `nproc0 ++ pps.filter(defs)` (`:1651`),
neither of which does the `rhsLookup` de-duplication that `+!` does. When that happens the
re-derived copy takes the COMMON branch at some `u ≠ r.lhs`, which is a real `unify` — still
not a `resolution` re-examination (so the (iii) ANSWER survives), but the step is not the
identity and `common_self_drops` does not apply to it.
**Fix:** either strengthen `common_self_drops` to the true statement —
`findRHS x.rhs = some u → step s = .continue s' ∧ (u = x.lhs → s' drops x)` plus the
observation that `u ≠ x.lhs` is an elimination step — or soften the report and the README to
what is proved. The second is a five-minute edit and is what I recommend for round 2.

### Empirical probe of the two escapes (mine, not the implementer's)
I instrumented the model in my scratch (`review-L3/Escapes.lean`: at every `learn` step,
does `trim learned s.proc` contain a partition `eqv` to the dequeued `r` (escape 1), and does
replaying the `++!` fold over `rest` create a `CommonPartition` redirect (escape 2)?).
Result on the 17 tracked seeds × bases 0/5/11 (136 `learn` steps): `selfRederive=0
redirects=0`. On five of the implementer's own generated seeds x the same three bases
(228 `learn` steps): `selfRederive=0 redirects=3` -- so escape 2 DOES occur in the generated
population and escape 1 does not. (A 60-seed sweep was abandoned: `#eval` in the interpreter
costs roughly 0.15 s per `learn` step, which makes the full 400 impractical inside a review.)

---

## 5a. A constructed seed for escape 2, replayed through the COMPILER — CONFIRMED benign

No tracked seed reaches either escape, so I built one.
`review-L3/cand/c012.json`:

```json
{"name": "cand12", "rho": {}, "cons": [[1, [0], [100]], [1, [2], [100, 101]], [3, [2], [101]]]}
```

i.e. `v1 <- (v0, l100)`, `v1 <- (v2, l100 l101)`, `v3 <- (v2, l101)`. The second dequeue is a
`learn` at `v1` whose `cancellation` derives `v0 <- (v2, l101)`, whose RHS is already the RHS
of `v3 <- (v2, l101)` still sitting in the incoming queue — so `++!` redirects. 96 of the 144
variable-numbering/constraint-order permutations I generated fire it (288 redirects in 432
model runs); none of the 144 fires escape 1.

Model (`lake exe looptrace cand/c012.json 0 500`) and compiler
(`ERMINE_JAVA_OPTS="-Dermine.rowTrace=… -Dermine.useInterface=false" tracker/repro/satterm/run.sh
trace json:…/c012.json 0 20 40`) agree line for line:

```
step   learn      ^free1 <- (^free0,l100)              incm=2  proc=0
step   learn      ^free1 <- (^free2,l100 l101)         incm=1  proc=1
learn  new        Cancellation: ^free0 <- (^free2,l101)
step   unify:0    CommonPartition: ^free3 <- (^free0,) incm=1  proc=2      <-- the redirect
step   learn      ^free3 <- (^free2,l101)              incm=1  proc=1
step   learn      ^free1 <- (^free3,l100)              incm=0  proc=2
learn  seen       Substitution: ^free1 <- (^free2,l100 l101)
learn  seen       Cancellation: ^free3 <- (^free2,l101)
```

Compiler verdict `SOLVED`, `TRACE records=28 steps=5 (learn=4 unify=1)`, and the `solve` /
`sat` / `inpart` population records are identical to the model's. **So escape 2 is real,
reachable, reproduced by the compiler, and dispatched to `unify:0` — never to
`learnPartitions`, hence never a `resolution` premise. The report's classification is
CONFIRMED on the compiler.** No `.ei` files were created.

### F4 (MODERATE, PLAUSIBLE — and it makes (iii) STRONGER than the report claims) — escape 1 looks UNREACHABLE, not merely self-cancelling
Working case by case through `Rules.lean` against `Constraints.scala`, I could not find any
rule that can emit a partition `Partition.equals` to the DEQUEUED `r`, and I believe it is
provable that none can. At a `learn` step `v ∉ rhs1.abstr` (otherwise `learnPartitions`
short-circuits into `selfSubstitution`, `Constraints.scala:1357`), and then:

* `cancellation` emits `⟨x, (ys,gs)⟩` / `⟨y, (xs,fs)⟩` with `x ∈ abstr1 \ absInt` (so `x ≠ v`)
  and `y ∈ abstr2 \ absInt`; `y = v` with the emitted RHS equal to `rhs1` forces
  `rhs2 = ({v}, ∅)`, which is `Partition.isSelfUnification` and therefore **can never be in
  `proc`** (`Constraints.scala:492` drops it at every insert);
* `substitution`'s `subBody u rhs2 v rhs1` emits `⟨v, (rhs1 - u) ⊎ rhs2⟩`; equality with
  `rhs1` forces `abstr2 = {u}` and `conc2 ⊆ conc1`, i.e. `rhs2 = ({u}, C)` — `C = ∅` is again
  a self-unification, and `C ≠ ∅` is `u <- (u, C)`, which dies in `selfSubstitution` the
  moment it is dequeued and so cannot be in `proc` either;
* `commonSubexpression`'s three non-minting branches emit `⟨v, (abstr1 \ int) ∪ {z}, conc1⟩`,
  and equality with `rhs1` forces `int ⊆ {z}`, contradicting the branch's own `2 ≤ |int|`;
* `splitConcrete`'s branches all contradict their own guards (`|abstr| ≥ 2` vs a
  single-variable result; `concr ≠ ∅` vs an abstract-only result);
* every minting branch of `splitConcrete`, `resolution`, `commonSubexpression` and
  `disjunction` puts a FRESHLY DRAWN variable in the emitted RHS, which `rhs1` cannot contain;
* the `DeDuplication` and `SelfSubstitution` facts have an EMPTY RHS, and `r.rhs.isEmpty` is
  false in the `learn` branch.

The supporting invariant is worth having on its own: **no partition of either queue is a
self-unification**, because `Q.insert` drops one (`:492`) and the four writers of `proc`
(`proc + r`; `makeConcrete`'s `nproc + Partition(v, RHSConcr(fs))`; `destructiveSub`'s
`nproc0 ++ pps.filter(defs)` at `|abs| ≥ 2`; `nproc0` a filter of the old `proc`) all go
through it or preserve it.

**Round-2 item:** prove `learn_no_self_rederive : … → ∀ p ∈ learned.elems, p.eqv r = false`
plus `proc_no_self_unification : Wf s → ∀ p ∈ s.proc.elems, p.isSelfUnification = false`.
Then `learn_single_pass`'s third clause becomes "everything enqueued differs from every
partition of `proc` AND from `r`", escape 1 disappears, `common_self_drops` is no longer
load-bearing, and F3 evaporates. (iii) then reads: **`trim` plus the redirect's shape mean a
`resolution` premise pair is examined exactly once per solve unless an elimination removes one
of the premises from `proc`** — a clean statement with ONE escape, and that one benign.
I mark this PLAUSIBLE rather than CONFIRMED because I checked it by case analysis, not in Lean;
the empirical side (432 model runs on seeds designed to provoke re-derivation, 0 hits) is
consistent with it.

---

## 6. The two PARTIAL checkpoints — what is missing, and the round-2 specification

### 6a. (i) the `learn` branch: what is missing
Precisely: `LoopRun (sys s) (sys s')` is proved for `Wf s → NonLearnStep s → step s = .continue s'`.
The uncovered case is `step_learn_shape`'s: `incm.dequeue = some (r, rest)`,
`proc.findRHS r.rhs = none`, `¬r.rhs.isEmpty`, `¬r.rhs.abstr.isEmpty`, `r.rhs.single? = none`,
`learnPartitions … = .ok (learned, su)`, and
`s' = { incm := rest.concatP (trim learned s.proc).elems, proc := s.proc.insertNP r, su := su }`.
`sys s'` adds `(trim learned s.proc)`'s constraints and keeps everything else, so what is
needed is: every partition `learnPartitions` derives is a `LoopRel`-consequence of `sys s`.
Nothing else — the deletions are none (`learn` deletes nothing) and the re-insertion of `r`
into `proc` does not change `sys` at all (`r` was already in `s.parts`).

### 6b. The implementer's diagnosis: ONE of the two blockers is real; the other is not
**Blocker (2), the `Sup.ofSeed` freshness placeholder — CONFIRMED as an obstacle, but
MISDIAGNOSED as a model defect.** `Sup.ofSeed lo = ⟨lo, lo + 100000, 0, 1024⟩`
(`State.lean:201`) and `Sup.fresh` (`:194-198`) hands out `blk` once `lo = hi`, so from
`ofSeed` the 100 001st draw is `0` and the supply is not injective. That really does make the
invariant "every id the supply can still produce is outside `allVars (sys s)`" FALSE at the
seed's initial state, so the `SplitApp.fresh`/`ResApp.fresh` premises cannot be discharged
unconditionally. But `blk = 0` is **faithful**, not a placeholder: the harness's supply is
`Replay.scala:16-20`'s `new Supply(lo, lo + 100000)` and `scalaparsers.Supply.block` is a
process-global `private var block: Int = 0` (`parsers/.../Supply.scala:6`) that only
`Supply.create`/`getBlock` advances. So "fix `ofSeed`" is the wrong move — it would make the
model LESS faithful unless the harness's actual block value is read. The right move is to
carry the freshness as a hypothesis; and note that the REPLAY path already satisfies it,
because `Segment.sup` (`Replay.lean:98-99`) takes `blk`/`bsz` from the trace's `sin` record
(`RowTrace.scala:202`), i.e. the compiler's real global counter, which is always ahead.

**Blocker (3), the mint-guard mismatch — NOT a blocker for (i).** I checked the relations:

* `Cut.ResApp` (`Cut.lean:871-882`) has **no `Carried` guard at all** — only the two premises,
  `tops`/`bots` nonempty and `z ∉ allVars G`. `LoopRel.res` already carries `Cut.ResStep`. So
  `resolution`'s minting branch needs NO guard translation whatsoever.
* `Cut.SplitApp` (`Cut.lean:1009-1019`) has `unnamed : ¬ Named G (vset c)` with
  `Named G S := ∃ d ∈ G, vset d = S ∧ d.conc = ∅` (`Cut.lean:98`). The loop's guard is
  `rhss (RHS.ofAbstr abstr)` = `findRHS(incm, proc, ∅)`, and `SplitApp.two_le` gives
  `2 ≤ |S|`, while every environment constraint has `|vset| ≤ 1` and the dequeued `r` has
  `conc ≠ ∅` (the branch's own guard). So the queue lookup missing IS `¬ Named (sys s) S` —
  the report says this itself. The only obstacle is that `LoopRel` imports
  `K2SplitStep` and not `Cut.SplitStep`; adding `| splitFree : SplitStep G G' → LoopRel G G'`
  with `SplitNecessary.SplitStep.satisfiable_iff` (`SplitNecessary.lean:204`) is two lines.
* Every REUSE branch of both rules uses its witness POSITIVELY: `K2ResStep.reuse` wants
  `mk v {z} (C ∪ D) ∈ G`, `K2ResStep.row` wants `mk v ∅ F ∈ G ∧ mk z ∅ (F \ (C∪D)) ∈ G`
  (`KeyedRow.lean:587-596`), and the loop's `resolvents`/`concRows` maps
  (`Constraints.scala:1373-1379`, `:1410-1418`) are built by scanning `proc ++ incm`, whose
  every element is in `sys s`. A found witness is therefore a member; the lookup being a LOWER
  bound (which `KeyedRowScala`'s header states) is the SAFE direction here.

So `¬ Carried` — the predicate `KeyedRowScala.concRow_none_uncarried` closes under a model —
is needed only for the KEYED mint (`K2MintApp`), which is only needed for the (ii) BOUND. The
report presents it as a blocker for (i) as well; that is an overstatement, and it matters,
because it makes the remaining (i) work look larger than it is.

### 6c. Round-2 specification for (i)-`learn`, in the order to attempt it
1. **`LoopRel` gains one constructor.**
   `| splitFree {G G'} : SplitStep G G' → LoopRel G G'`, soundness case
   `exact (SplitStep.satisfiable_iff h).mp ⟨rho, hm⟩`. (Optionally also
   `| cse {G G'} : CseStep G G' → LoopRel G G'` for `-Dermine.genRules=all`; the shipped
   `cut` mode has `cseMints = false`, so the CSE mint is unreachable by default and can be
   excluded with a flag hypothesis instead.)
2. **The supply invariant.** In `Refine.lean` (not `State.lean`):
   ```lean
   def Sup.Reach (su : Sup) (z : Nat) : Prop := (su.lo ≤ z ∧ z < su.hi) ∨ su.blk ≤ z
   structure SupOk (su : Sup) : Prop where
     lohi : su.lo ≤ su.hi
     ahead : su.hi ≤ su.blk
     bsz : 2 ≤ su.bsz
   def SupFresh (su : Sup) (G : System) : Prop := ∀ z, Sup.Reach su z → z ∉ allVars G
   ```
   with, in this order:
   `fresh_reach : SupOk su → Sup.Reach su (su.fresh).1`;
   `fresh_supOk : SupOk su → SupOk (su.fresh).2`;
   `fresh_reach_mono : SupOk su → ∀ z, Sup.Reach (su.fresh).2 z → Sup.Reach su z ∧ z ≠ (su.fresh).1`
   (this is where the two branches of `fresh` are checked: `lo+1 ≤ z < hi` and
   `blk+bsz ≤ z` both exclude the drawn id);
   `SupFresh.mono : G' ⊆ G → SupFresh su G → SupFresh su G'`;
   `SupFresh.step : SupOk su → SupFresh su G → (∀ w ∈ allVars G', w ∈ allVars G ∨ w = (su.fresh).1) → SupFresh (su.fresh).2 G'`.
   Then `SupFresh su (sys s) → (su.fresh).1 ∉ allVars (sys s)`, which is exactly
   `SplitApp.fresh` / `ResApp.fresh`.
   **Do NOT touch `Sup.ofSeed`.** State the `learn` theorem as
   `Wf s → SupOk s.su → SupFresh s.su (sys s) → step s = .continue s' → LoopRun (sys s) (sys s')`,
   and record (with `Replay.lean:98`, `RowTrace.scala:202`) that every REPLAY state satisfies
   the two supply hypotheses while a seed state does not, because the repro harness's supply
   really is non-injective past 100 000 draws.
3. **The rules, in increasing difficulty** — each as
   `∀ p ∈ <rule> …, ∃ H, LoopRun G H ∧ G ⊆ H ∧ p.toConstraint ∈ H`, exactly the shape
   `replace_run`/`subPartitions_run`/`cancellation_run` already have, so they compose with
   `concatP_run` the way the `concrete` branch does:
   `selfSubstitution_run` (`SelfSubstStep`; the `concr ≠ ∅` case is `selfSubst_refutes`) →
   `cancellation_run` (RefineConcrete.lean:442 proves the SPECIALISED form
   `rhs1 = RHS.ofConcr fs`, where only `cancellation`'s second branch can fire; the learn
   branch needs the general `cancellation v rhs1 rhs2`, i.e. the first branch as well — the
   symmetric `CancelStep`, a short extension of the same proof) →
   `substitution_run` (= `subBody_run` twice; `SubstStep` + `dedup`, and `subPartitions_run`
   at RefineConcrete.lean:209 is the same proof) →
   `commonSubexpression_run` (reuse and the two fold branches are `NonGenStep`/`CutStep`;
   `findRHS3`'s three-source lookup needs `rhsLookup_witness`, already proved) →
   `splitConcrete_run` (syntactic reuse = `SplitReuseStep`; `splitKey` = `K2SplitStep.key`;
   `splitRow` = `K2SplitStep.row`; mint = the new `splitFree`; `emptyRow` excluded by a
   `s.flags.emptyRow = false` hypothesis, which the plan's Known-scope-limits already scope
   out as M4) →
   `resolution_run` (reuse = `K2ResStep.reuse`, `resRow` = `K2ResStep.row`, mint =
   `LoopRel.res` with `ResApp`; same `emptyRow` exclusion) →
   `disjunction_run` or a `s.flags.disjRule = false` hypothesis.
4. **`learnPartitions_run`**: fold the above over `proc` with `foldl_except_inv` (Wf.lean:603,
   already there), threading `G ⊆ H` and the supply invariant; then
   `step_refines_learn`, then drop `NonLearnStep` from `step_refines` and re-derive
   `step_sat`, `run_sat`, `run_refutes` unconditionally.
   `learnPartitions`' one subtlety to keep: `findResolvent(s)` and `findRHS(incm, proc, s)`
   consult the ACCUMULATOR (`Constraints.scala:1471`, `:1480`), so the invariant must be
   `∀ p ∈ s, p.toConstraint ∈ H` alongside `G ⊆ H`, not `∈ G`.

**Estimated shape:** items 1, 2 and the first three of item 3 are mechanical given what
Wf.lean/RefineConcrete.lean already prove; `splitConcrete_run` and `resolution_run` are the
new work, and neither needs `KeyedRowScala`. I do not believe the gap is fundamental.

### 6d. (ii) the mint bound: what is missing, and whether it is fundamental
`Terminates` (Order.lean:30) is the right statement — `∃ n, Finished (run s n)`, with
`Finished (.outOfFuel _) = False`, so it is genuinely "reaches `done` or `died` at SOME fuel",
not "does not exhaust this fuel"; `run_mono` (`:33`) makes it monotone. But the ONLY
`Terminates` theorem proved is `terminates_of_empty` (`:43`), the empty queue. So (ii) is
neither proved nor refuted; what is proved is one INGREDIENT, `learnChain_card` (`:543`).

The report's naming of the missing lemma —
`∀ n t, LoopReach n s t → (allVars (sys t)).card ≤ N` for satisfiable `sys s` — is correct,
and its diagnosis of why it resists is correct **for this checkpoint** (unlike for (i)):
`KeyedRow.mintsBoundedOnSatKeyed2Star` bounds mints along `K2StarLoopRun`, whose minting
constructor `K2SplitStep.mint`/`K2ResStep.mint` carry `¬ Carried G v K`, and the loop's
guards are queue lookups that MISS where `sys s` hits (the `SubstEnv` holds facts
`makeEmpty`/`instantiate` deleted from both queues). `KeyedRowScala` already proves the Scala's
branches are `K2SplitStep`/`K2ResStep` steps of a MODELLED `G` and names
`concRow_none_uncarried` as the place the model is used, so the missing work is the
identification `G := sys s` plus the `G.erase c` bookkeeping `KeyedRowScala` §2 already has —
NOT a new mathematical idea. So: the implementer's diagnosis is right here.

Concretely, here is the mismatch, so round 2 does not have to rediscover it.
`Carried G v K := Resolved G v K ∨ ConcCarried G v K` and
`ConcCarried G v K ↔ ∃ C z, mk v ∅ C ∈ G ∧ mk z ∅ (C \ K) ∈ G` (`KeyedRow.lean:88`, `:95`).
The loop's `concRows` fold (`Constraints.scala:1410-1418`) scans `proc ++ incm` only, while
`sys s` also contains the environment — and `makeEmpty` writes `v := ConcreteRho(∅)` into the
environment **and deletes every partition mentioning `v` from both queues**
(`Constraints.scala:1568-1580`). So two variables emptied earlier in the solve give
`mk v ∅ ∅ ∈ sys s` and `mk z ∅ ∅ ∈ sys s`, i.e. `ConcCarried (sys s) v K` for EVERY `K`,
while the queue lookup sees nothing. That is exactly why `emptyRow` (the flag that makes the
compiler read the environment back, `Constraints.scala:1456-1464`) exists, and it is why
`¬ Carried (sys s) v K` is NOT implied by the loop's guard missing. `conc_unique_of_model` is
the right tool — under a model `v` has one concrete row, so the `C` in `ConcCarried` is pinned
— but the empty-row case above is precisely the one where the queues have nothing to pin it
against, and `KeyedEmptyScala`/`makeEmptyE` (the `v <- ()` RETAINED step, which `sys` already
models via `Env.sys`) is where that has to be closed.

**But there is a second obstacle the report does not name, and it is the deeper one.**
`LoopRel` contains `weaken : G' ⊆ G → LoopRel G G'`, i.e. an ARBITRARY deletion. That is fine
for soundness (§4b) and it is what the plan's (i) asks for ("which transfers soundness"), but
it means **no measure is monotone along `LoopRun`**, so the relation-level bounds cannot be
transported through the refinement at all: `mintsBoundedOnSatKeyed2Star` is about
`K2StarLoopRun`, and a `LoopRun` is not one. Transporting the bound needs a SECOND, tighter
relation for the loop — deletions restricted to the ones the loop actually performs
(`concretizeSrs`, `makeEmptyD`'s erasure, `instantiate`'s removal) rather than `⊆` — or a
measure defined directly on `State` that ignores `sys`. I would specify round 2 for (ii) as:
1. prove `learn` refinement (§6c) — without it nothing about mints can be said at all;
2. define `LoopStrict` = `LoopRel` with `weaken` replaced by the three named deletions, prove
   `step` refines `LoopStrict` (the same proofs, with the `weaken` steps re-justified), and
   `LoopStrict G G' → K2StarLoopStep G G' ∨ G' ⊆ G ∧ <the deleted constraints are entailed>`;
3. only then transport `mintsBoundedOnSatKeyed2Star`.
Step 2 is real work and may be where (ii) genuinely resists. **I do not think (ii) is
reachable in one more implementer round**, and I would not make L4 wait on it.

---

## 7. The plan's L3 acceptance criteria, one by one

The plan (`tracker/LOOP-MODEL-PLAN.md`, §L3) says: *"Acceptance: (i) and (ii) proved or refuted
with a witness the compiler reproduces; (iii) decided; (iv) proved; audit green."*
Note that the BRIEF loosened this — it offers `(T2) proved under a stated extra hypothesis, or
a partial bound` as an outcome for (ii). I score against the PLAN and note the tension.

| criterion | verdict | evidence |
|---|---|---|
| **(iv)** the bridge's `Nodup`s and `LblCoh` proved preserved by `step` from every initial state | **PASS** | `Wf` (Wf.lean:1021) = exactly the bridge's five hypotheses (§3); `step_wf` (:1049) covers all five branches through `step_qok` (:943); `wf_initial`/`wf_seed`/`wf_replay` (:1269, :1327, :1555) are `Seed.lean:134`'s state; `LPart.eqv_iff_toConstraint_of_wf` (:1102) has no side hypotheses. `wf_replay` carries a decidable `SetsOk` side condition that no real trace violates (report F1) — noted, not a fail. |
| **(i)** every `step` is a run of the relations, transferring soundness | **FAIL as stated / PARTIAL in substance** | proved with the extra hypothesis `NonLearnStep s`, i.e. for 4 of 5 branches; the `learn` branch — the only one that MINTS and the only one where the interesting relations (`SplitStep`, `ResStep`, `K2SplitStep`, `K2ResStep`) would be USED — is not covered, so `LoopRel`'s `split`/`res`/`kres` constructors are declared and proved sound but **never actually applied by any theorem about `step`**. The run-level corollaries `run_sat`/`run_refutes` and `run_sat_nonlearn`/`run_refutes_nonlearn` require the WHOLE run to avoid `learn` (`RunLinkOrEmpty`/`RunNonLearn`, Refine.lean:1377, RefineConcrete.lean:676), which no real solve does. See F1, F2, §6a-6c. |
| **(i)** the `died` paths classified, refuting ones proved to refute | **PARTIAL** | the four system-level refutation lemmas (Refine.lean:1225-1268) are correct and non-vacuous; the classification of the three non-refutations is right (skolem = kinding, `Constraints.scala:1577`; the two panics are one `Subst.scala:184` reached with two `e`s). But the loop-level extraction exists only for `makeEmpty_died` (:1300), and even that is **not composed with `run_refutes`** — `run_refutes` takes `¬ SSat (sys s')` as a HYPOTHESIS, so it is contraposed satisfiability-preservation, not "a death refutes". See F2. |
| **(ii)** `Terminates` proved or refuted with a compiler-reproducible witness | **FAIL** | the only `Terminates` theorem is `terminates_of_empty` (Order.lean:43). No bound, no witness. `learnChain_card` (:543) is a genuine ingredient; the four "order properties" (:60, :79, :116) are dispatch-unfolding lemmas rather than order theorems, and none of them is used by any bound. The empirical evidence is real and I extended it (§2), but the plan asks for proof or refutation. The brief's `(T2)` category is met. See §6d. |
| **(iii)** the Stage 7b question decided | **PASS** | `trim_refuses`, `learn_single_pass`, `res_pair_single_pass`, `step_proc_mono` are real theorems about the real `step`, and I verified the Scala they encode line by line; escape 2 is confirmed reachable and benign ON THE COMPILER (§5a). Two caveats: F3 (escape 1's self-cancelling proved only under a hypothesis) and F4 (escape 1 looks unreachable, which would make the answer cleaner). |
| audit green | **PASS** | 837 jobs, `2834; 0`, 48/48 headline theorems on standard axioms (§1) |

Scope items the plan already carries are respected: `emptyRow` (M4) is off by default and the
model carries the flag; `Disjunction` is off; the parallel loader is untouched.

---

## 8. Findings, ranked

| # | severity | status | one line |
|---|---|---|---|
| **F1** | **HIGH** | CONFIRMED | (i) is proved only for the four non-minting branches, so no theorem about `step` ever uses `LoopRel`'s `split`/`res`/`kres`; and the report's diagnosis of WHY overstates the obstacle (§6b: `ResApp` has no guard, `SplitApp`'s translates, the reuse branches use their witness positively). Round-2 spec in §6c. |
| **F2** | **MODERATE** | CONFIRMED | Three loop-level claims are stronger than the Lean. (a) the report's §2f table says "refutation? YES" for messages 1, 2 and 7 where only the SYSTEM-level lemma exists; (b) "Composed with `run_refutes_nonlearn`, that gives the adequacy statement" — that composition is not in Lean, and `makeEmpty_died` is stated about `makeEmpty`, not about a `step` death; (c) `run_sat`/`run_refutes` are advertised as run-level soundness but hold only for runs that never take the `learn` branch. The README repeats (a). **Fix:** state (a) as "system-level refutation proved; loop-level extraction only for message 4", drop the word "composed" in (b), and add the `RunNonLearn` caveat to (c). |
| **F3** | **MODERATE** | CONFIRMED (by reading both sides) | escape 1's "self-cancelling" is proved only under `findRHS x.rhs = some x.lhs`; `proc` CAN hold two partitions with the same RHS because `makeConcrete` (`Constraints.scala:1614`) and `destructiveSub` (`:1651`) write it with the NON-processing insert. §5. |
| **F4** | **MODERATE** | PLAUSIBLE | escape 1 is very likely UNREACHABLE, not merely self-cancelling — every rule's output either has `lhs ≠ v`, or contains a freshly drawn variable, or contradicts its own branch guard, or would need a self-unification in `proc` which `Q.insert` never admits. Proving it makes (iii) strictly stronger and retires F3. §5a. |
| **F5** | **LOW** | CONFIRMED | `wf_replay`'s `CsItem.SetsOk` hypothesis (report F1) is right; the one-line decidable check inside `replay` would remove it and make (iv) unconditional for the replay path too. |
| **F6** | **LOW** | CONFIRMED | The report calls `Sup.ofSeed`'s `blk = 0` a "PLACEHOLDER" and "a finding about the model". It is FAITHFUL: `Replay.scala:16-20` builds `new Supply(lo, lo+100000)` and `scalaparsers.Supply.block` starts at `0`. The real statement is "the repro harness's supply is not globally injective past 100 000 draws, so a freshness invariant must be a hypothesis, and the REPLAY path satisfies it because `Segment.sup` reads the compiler's real block from the `sin` record". Correct the report; do NOT change `ofSeed`. §6b. |
| **F7** | **LOW** | CONFIRMED | The report calls `step_empty_branch`/`step_unify_branch`/`step_common_branch` "the four order properties as lemmas". They are dispatch-unfolding lemmas (each proof is `simp only [step]; rw [hd, h1]; rfl`), true and useful as plumbing, but they carry no order content beyond the definition of `step` and are not used by any bound. Worth saying so, since the plan promised "the four order properties are now lemmas about `step`, not hypotheses" as an input to (ii). |
| **F8** | **INFO** | CONFIRMED | `LoopRel.weaken` admits an ARBITRARY deletion. Correct for the plan's (i) ("transfers soundness") but it means no measure is monotone along `LoopRun`, so the relation library's mint bounds cannot be transported through this refinement at all — a structural reason (ii) is stuck that the report does not name. §6d. |

Nothing in this list is an unsoundness. Every theorem I checked says what the report says it
says, and the two PARTIAL checkpoints are declared PARTIAL by the implementer.

### F1, sharpened: four of the ten `LoopRel` constructors are dead

I counted every use of a `LoopRel` constructor in a proof across `Refine.lean` and
`RefineConcrete.lean`:

| constructor | uses in proofs |
|---|---|
| `nongen` | 9 |
| `weaken` | 6 |
| `dedup` | 2 |
| `renameLhs`, `linkSymm`, `emptyProp` | 1 each |
| **`split` (`K2SplitStep`)** | **0** |
| **`res` (`Cut.ResStep`)** | **0** |
| **`kres` (`K2ResStep`)** | **0** |
| **`emptyE` (`KeyedEmpty.makeEmptyE`)** | **0** |

They appear only in the `inductive` and in `LoopRel.sat`'s case analysis. The plan's (i) is
worded *"the systems are related by a run of `K2StarLoopStep ∪ makeEmptyD ∪ unify-step`"* —
and **not one of those relations is used by any theorem about `step`.** What is actually
proved is a refinement into `NonGenStep + weaken + {renameLhs, linkSymm, emptyProp, dedup}`.
That is a correct and useful result, but it is not the connection the plan asked for, and it
is why I score (i) FAIL-as-stated rather than PARTIAL-and-nearly-there. (`makeEmpty_run` uses
`emptyProp` and `weaken` rather than `emptyE`, so even the `empty` branch — which IS
refined — does not go through `makeEmptyD`/`makeEmptyE`.)

One internal inconsistency worth fixing while you are there: `Refine.lean:344-345`'s own
docstring says of `res` that "the guard is `K2ResStep`'s, **not needed for soundness**", which
is exactly my §6b point; the report's §2e blocker (3) nonetheless presents the guard mismatch
as an obstacle to the `learn` refinement. The module is right and the report is wrong.

---

## 9. Verdict — FIX-THEN-ADVANCE

**Required before L3 advances** (all cheap; none needs new mathematics):

1. **F2 — correct the three over-claims in the report and the README.** (a) §2f's table must
   distinguish "system-level refutation proved" from "loop-level extraction proved"; only
   message 4 has the latter, and even it is not composed with `run_refutes`. (b) delete
   "Composed with `run_refutes_nonlearn`, that gives the adequacy statement" or prove the
   composition (it is short: instantiate `makeEmpty_died` at `G := sys s`, use
   `step_died_sys`). (c) say plainly that `run_sat`/`run_refutes` and their `nonlearn`
   variants apply only to runs that never take the `learn` branch, which no real solve is.
   The README's "the four refuting `died` paths proved to refute" needs the same fix.
2. **F3 — fix the escape-1 claim** in the report §3 and the README: `common_self_drops`
   assumes the lookup returns the SAME left-hand side, and `proc` can hold two partitions
   with equal RHS (`Constraints.scala:1614`, `:1651`). Either soften the prose or prove the
   general case.
3. **F6 — correct the `Sup.ofSeed` finding**: `blk = 0` is faithful to
   `tracker/repro/nameloss/Replay.scala:16-20` + `scalaparsers/Supply.scala:6`, not a
   placeholder; the real statement is that the harness's supply is not injective past
   100 000 draws, and that the REPLAY path carries the compiler's real block
   (`Replay.lean:98`, `RowTrace.scala:202`). Do not change `Sup.ofSeed`.
4. **F1 — correct §2e's blocker (3)** to match `Refine.lean:344-345`'s own docstring: the
   mint-guard mismatch does not block (i); it blocks the (ii) BOUND. And record in the report
   that `split`/`res`/`kres`/`emptyE` are currently unused.
5. **Plan/report bookkeeping**: the plan's L3 acceptance is "(i) and (ii) proved or refuted".
   Neither is. Either the orchestrator accepts the brief's looser `(T2)` wording and records
   (i)-`learn` + (ii) as **carried forward to L4 as declared scope** in the plan's
   "Known scope limits" section — my recommendation — or L3 goes back for the round-2 work
   in §6c. I would not hold L4 for (ii) (§6d): it needs a tighter relation than `LoopRel`
   and is not one round's work.

**Recommended but not required** (they make the stage strictly better and are bounded):

6. **F4 / round-2 (iii)**: prove `proc_no_self_unification` and `learn_no_self_rederive`.
   Escape 1 then disappears and (iii)'s answer becomes a clean one-escape statement.
7. **§6c items 1-2 and the first three of item 3** (`splitFree` constructor, the `SupOk` /
   `SupFresh` invariant, `selfSubstitution_run` / `substitution_run` /
   `commonSubexpression_run`). These alone would take (i) from "4 of 5 branches" to "the
   `learn` branch modulo `splitConcrete_run` and `resolution_run`", and would make
   `LoopRel.split`/`res` live.
8. **F5**: the one-line `SetsOk` check inside `replay`.

**What I am NOT asking for**: no theorem needs to be withdrawn, no proof is wrong, `Wf` needs
no weakening, `sys` needs no change, and the five new `LoopRel` constructors are all correctly
matched to the Scala and correctly proved sound. (iv) is finished work of good quality and
closes L1 F6 and L2 F5 as promised; (iii) is decided and I confirmed its key claim on the
compiler with a seed of my own.

---

## 10. Reviewer's scratch inventory

`/home/dmitry/.claude/jobs/880c725d/tmp/review-L3/`:
`build.log`, `audit.log` (§1); `RevAxioms.lean` + `axioms.out` (48 `#print axioms`);
`fuzzrun.sh` + `fuzz.txt` (4,033 `looptrace` runs, §2);
`Escapes.lean` / `EscBody.lean` / `EscCand.lean` / `EscFz*.lean` + outputs (the escape
instrumentation, §5/§5a); `cand/` (144 constructed seeds, 96 of which fire escape 2);
`c012.tsv` (the compiler trace of the constructed seed).
Nothing outside that directory and this file was written. No commits. No `.ei` files created
(checked). No `lake exe cache get`.

---
---

# Round-2 re-review — 2026-09-04

Targeted re-review of the implementer's Round 2 (`L3-THEOREMS.md` §§R2.1–R2.6, new module
`Loop/RefineLearn.lean`). Same constraints: nothing edited except this file and
`/home/dmitry/.claude/jobs/880c725d/tmp/review-L3/`; no commits, no Lean/Scala edits, no
`lake exe cache get`.

## R.1 Verdict

**ADVANCE**, with (ii) carried forward as its own stage.

Everything I was told to distrust, I re-ran or re-read, and it holds up. `step_refines_all` is
exactly the theorem I specified in §6c — no hidden weakening, no smuggled constructor, and its
three flag hypotheses exclude only OFF-by-default features while leaving BOTH minting rules
live. The plan's criterion (i) is now met. Two small documentation slips (§R.8) and one
correction to the implementer's own pessimism (§R.7) are worth an editing pass but do not
block; I do not require another round.

## R.2 Rebuild, re-audit, greps, axioms — all re-run by me

| check | result |
|---|---|
| `lake build Rowpartition` | **838 jobs**, success, exit 0; zero `declaration uses sorry` in the log |
| `lake env lean Audit.lean` | `Rowpartition theorems audited: 2921; declarations using a non-standard axiom: 0`, exit 0 |
| grep `sorry axiom partial native_decide implemented_by unsafe opaque Classical extern` over `Wf/Order/Refine/RefineConcrete/RefineLearn.lean` | **0 hits in all five** |
| my own `#print axioms` on **36** declarations (`review-L3/RevAxioms2.lean`), covering every Round-2 headline plus the Round-1 ones | 36/36 resolved, exit 0, **no non-standard axiom**. 32 give `[propext, Classical.choice, Quot.sound]`; `fresh_reach`, `fresh_supOk`, `fresh_reach_mono` give `[propext, Quot.sound]` and `proc_no_self_unification` gives `[propext]` — strict subsets, which is better, not worse |
| executable model unchanged? | `git status --porcelain` shows `M ` (staged, clean worktree) for `State/Step/Rules/Queue/SSet.lean` and an EMPTY unstaged diff — Round 2 is proof-only. My Round-1 behavioural evidence (4,033 `looptrace` runs; the `c012` compiler replay) therefore still stands unaltered. Spot-checked anyway: `lake build looptrace` green, `W2`/`G7`/`NE6` still `SOLVED`, `c012` still emits its `CommonPartition` redirect |

The report's figures (838 / 2921 / 0) are exact.

## R.3 `step_refines_all` — verbatim, and no hidden weakening

```lean
theorem step_refines_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') : LoopRun (sys s) (sys s')
```
(`RefineLearn.lean:1479`; the proof is `by_cases NonLearnStep` → `step_refines_nonlearn` /
`step_refines_learn`, so it really is all five branches of `Step.lean:314`.)

* **The three flag hypotheses are exactly the shipped defaults**, and only those:
  `Constraints.scala:768-774` gives `mode = "cut"` ⇒ `cseMints = false`, `disjRule = false`
  (`:774`), `emptyRow = false` (`:1026`). Critically, `splitMints`, `resolves`, `resGuard`,
  `splitKey`, `splitRow`, `resRow` are all `true` by default and are **not** constrained — I
  checked `splitConcrete_run` (`RefineLearn.lean:537`) and `resolution_run` (`:677`) and each
  carries `fl.emptyRow = false` as its ONLY flag hypothesis. So both MINTING branches are
  inside the theorem. This is the opposite of a vacuity dodge.
* **The two supply hypotheses are exactly what I specified.** `Sup.Reach`, `SupOk`
  (`lohi`/`ahead`/`bsz`), `SupFresh` at `RefineLearn.lean:39-54` are my §6c definitions
  verbatim, and `fresh_reach`/`fresh_supOk`/`fresh_reach_mono`/`SupFresh.mono_allVars`/
  `SupFresh.step` are my five lemmas. I checked the arithmetic in both branches of
  `Sup.fresh`: at `lo ≠ hi` the drawn `lo` is excluded from `Reach su'` only because
  `hi ≤ blk` (`SupOk.ahead`), and at `lo = hi` `SupOk` survives only because `2 ≤ bsz` — both
  clauses earn their place. The docstring at `:41-44` now states the F6 correction correctly
  ("false of `Sup.ofSeed`, whose `blk = 0` is the repro harness's real, process-global
  starting counter"), and `Sup.ofSeed` was NOT changed. Exactly right.
* **`LoopRun` is the same relation.** `LoopRel` (`Refine.lean:344-378`) now has ten
  constructors: the Round-1 nine minus `emptyE` plus `splitFree : SplitStep G G' → LoopRel G G'`.
  `SplitStep` is `Cut.SplitStep` via `Cut.SplitApp`, which carries `unnamed` and `fresh` — a
  library relation with its guards intact, not a permissive escape hatch. `LoopRel.sat`
  (`:417-445`) discharges it with `SplitStep.satisfiable_iff` (`SplitNecessary.lean:204`).
  **No new permissive constructor.** Net: the relation is strictly SMALLER than Round 1's
  (one constructor removed, one added that is a subrelation of nothing else), so the
  refinement theorem is strictly stronger.
* **The `¬ Named` discharge is not assumed.** `learnPartitions_run` takes `hunnamed` as a
  hypothesis, but `step_refines_learn` (`:1414-1447`) DISCHARGES it, by exactly the argument I
  gave in §6b: a `Named (sys s)` witness is either a queue partition — excluded by
  `findRHS3_none`, with the dequeued `r` excluded separately because `r.conc ≠ ∅` — or an
  environment fact, excluded because `|vset| ≤ 1 < 2 ≤ |S|`. I read the whole discharge; it is
  correct and complete.
* **The three reverse-lookup soundness lemmas carry no model hypothesis.**
  `findRHS3_names` (`:1003`), `findResolvent_sound` (`:1025`), `findConcRow_sound` (`:1066`)
  are all the POSITIVE direction (lookup found it ⇒ it is a member of `H`), with no `SModels`
  anywhere — as §6b predicted, and the accumulator `S` is threaded (`hS`), which is the
  subtlety §6c item 4 flagged.

## R.4 Constructor uses — counted by me

`grep -oh "LoopRel\.<ctor>"` over `Refine.lean RefineConcrete.lean RefineLearn.lean Order.lean Wf.lean`:

| ctor | nongen | weaken | split | kres | dedup | splitFree | res | renameLhs | linkSymm | emptyProp |
|---|---|---|---|---|---|---|---|---|---|---|
| uses | 16 | 6 | 2 | 2 | 2 | 1 | 1 | 1 | 1 | 1 |

**All ten are live.** (The report's table says `split` = 3; I count 2 occurrences of the token
`LoopRel.split` — the third is presumably `splitFree`, which my regex counts separately. A
one-cell arithmetic slip, not a substantive one: the claim "every constructor is used" is TRUE
either way.) `emptyE` is gone from the declaration entirely. Round 1's finding that the plan's
named relations were dead is fully answered: `K2SplitStep`, `K2ResStep` and `Cut.ResStep` are
now applied by real theorems about `step`.

## R.5 The `emptyE` removal argument — verified against the Scala

`makeEmptyE v G = insert (mk v ∅ ∅) (keepPart v G ∪ erasePart v G ∪ propPart v G)`
(`KeyedEmpty.lean:83-103`). The `empty` branch is `Constraints.scala:1561-1581`, and it returns
`(incmg ++! trim(nps, procd), procd)` — the re-insertion goes through `++!`, i.e.
`Q.insert(…, process = true)`, whose redirect (`Constraints.scala:513-518`) can replace an
insertion by a NAMING constraint `mk w {a} ∅`. That constraint is in none of `keepPart`
(it is new), `erasePart` (not a `rhs - v` rewrite of anything) or `propPart` (not
`mk x ∅ ∅`). **So `sys s' ⊆ makeEmptyE v (sys s)` genuinely fails and the removal is
justified.** I also checked the one thing the argument needs and the report does not mention:
`Env.instantiate` (`State.lean:340-345`) rewrites existing bindings through `v ↦ val`, matching
`Subst.scala:186`'s `subType(Map(v -> e), hm.types)` — so an old alias `w := VarT(v)` becomes
`w <- ()`, which IS in `erasePart`'s image. Without that the "almost `makeEmptyE`" claim of
R2.5 row 4 would have a second hole. It does not.

Removing an unused constructor also strictly strengthens `LoopRun`, so nothing is lost.

## R.6 The six residual `weaken` uses — read against the Scala

Sites: `Refine.lean:1168`, `:1200`, `:1218`, `:1256`, `RefineConcrete.lean:697`,
`RefineLearn.lean:1458`. For each I re-read the Scala it stands for:

| site | branch | what is dropped | genuinely not a library deletion? |
|---|---|---|---|
| `Refine:1168` | `common`, `r.lhs = u` | `unify(v,u)` at `v == u` returns the queues unchanged (`Constraints.scala:1521`), so the DEQUEUED partition is simply gone | **confirmed** — a dequeue-drop; every library step is `insert`-shaped |
| `Refine:1200` | `common`, `r.lhs ≠ u` | `instantiate` (`:1533-1539`) pulls every `ruleInvolves(v)` partition out of BOTH queues (`nproc` loses them for good) and re-adds rewritten copies to `incm` through `++!` | **confirmed** — `NameLoss.concretizeKeep` deletes definitions and rewrites mentions; this deletes mentions and re-adds them rewritten, and `++!` may substitute a redirect |
| `Refine:1218` | `empty` | `makeEmpty`'s `procd`/`incmg` plus `trim` | **confirmed**, and it is the "almost `makeEmptyE`" case of §R.5 |
| `Refine:1256` | `unify` (lone variable) | the same `instantiate` removal, at swapped arguments (`Constraints.scala:1130` calls `unify(u, v, …)`) | **confirmed** — same category as `:1200` |
| `RefineConcrete:697` | `concrete` | `destructiveSub`'s `filter p` (`:1632-1634`) | **confirmed** — `concretizeSrs` matches the deletion and the `srs` re-expression, but the loop also re-adds `pps.filter(abs.size ≥ 2)` (`:1651`, the `keepDefs` repair) and `makeConcrete` adds `can` and `v <- ((|C|))` (`:1610-1614`), none of which is in `concretizeSrs`'s image |
| `RefineLearn:1458` | `learn` | nothing deleted; `trim` and `++!` DROP derived partitions (`:1138`) | **confirmed** — "the relation derives it, the loop declines to enqueue it" has no library counterpart |

So all six are honestly residual. **As a specification for a `LoopStrict` stage, R2.5 is
sufficient**: its five replacement operations (dequeue-drop; queue drops incl. the redirect;
`instantiate`'s removal; `makeEmptyD`'s erasure; `concretizeSrs` + `keepDefs` + `can`) cover
every one of the six sites, each is stated with the exact Scala it must model, and it correctly
identifies that only (4) and (5) have partial library support. That is what a next stage needs
to start from. It also confirms my §6d judgement independently: three of the five operations
have no counterpart at all, so (ii) is not one round's work.

**Finding R-A (LOW, CONFIRMED).** The R2.5 table says "Six remain" but tabulates only five live
rows (2–6); the `unify`-branch site (`Refine.lean:1256`) is missing. It belongs to the same
category as row 3 and changes nothing in the specification — add a row.

## R.7 Escape 1 (F3/F4) — and where the implementer is too pessimistic

`NoSelfUnif` (`Order.lean:603`), `step_NoSelfUnif` (`:780`), `proc_no_self_unification`
(`:791`) and `noSelfUnif_initial` (`:798`) are proved, on standard axioms, and are exactly the
invariant my F4 asked for. `common_self_drops` is unchanged and the prose in §3 and the README
is now softened to what is proved — **F3 is discharged.**

`learn_no_self_rederive` is not proved, and R2.4 says the blocker is a second invariant
("`proc` holds no `u <- (u, C)`") that "is not preserved by inspection alone — it is
`selfSubstitution`'s death that removes such a partition, and connecting 'it would die when
dequeued' to 'it is not in `proc`' needs the order argument".

**Finding R-B (LOW, CONFIRMED by reading) — that diagnosis is wrong; the second invariant needs
no order argument.** Define `NoInfRow s := ∀ p ∈ s.proc.elems, ¬(p.lhs ∈ p.rhs.abstr.elems ∧
p.rhs.conc.isEmpty = false)`. `proc` starts empty and has exactly four writers, and each is
immediate:

1. `Step.lean:355`, `s.proc.insertNP r` — reached only when
   `learnPartitions … = .ok (learned, su)`, and `learnPartitions` (`Step.lean:261-263`) begins
   `if rhs1.abstr.contains v then selfSubstitution ns v rhs1.abstr rhs1.conc >>= …`, while
   `selfSubstitution` (`Rules.lean:52-56`) returns `.error` exactly when `concr` is nonempty.
   So `.ok` **already implies** `r.rhs.abstr.contains r.lhs = false ∨ r.rhs.conc.isEmpty = true`
   — the invariant clause for `r`, with no reasoning about dequeue order at all;
2. `unifyVars`/`instantiate` — `nproc` is `proc.partition ruleInvolves(v) |>.2`, a filter;
3. `makeEmpty` — `procd` is a filter;
4. `makeConcrete`/`destructiveSub` — `nproc0` is `proc` or a filter of it, `+ Partition(v, RHSConcr fs)`
   has empty `abstr`, and `pps.filter(defs)` draws from `proc` itself at `|abs| ≥ 2`
   (`Constraints.scala:1650-1651`). Nothing rewritten ever enters `proc`: `instantiate`,
   `makeEmpty` and `destructiveSub` all send their rewrites to `incm`.

So `NoInfRow` is provable by the same induction as `NoSelfUnif` plus that one-line fact about
`learnPartitions`, and with it the `substitution` case of `learn_no_self_rederive` closes and
escape 1 becomes provably unreachable. This is a recommendation for whoever next touches
`Order.lean`, not a condition on advancing — (iii) was already DECIDED and its answer is
unaffected either way.

## R.8 F2's corrections — confirmed

* **(a)** §2f's "refutation? YES" cells are unchanged, but the paragraph immediately below them
  now states plainly that the four lemmas are SYSTEM-level and that only message 4 has a
  loop-level extraction. The over-claim is gone in substance. (Cosmetic: putting
  "(system-level)" in the cells themselves would make the table readable on its own.)
* **(b)** the word "composed" is gone and the composition is now a theorem:
  `step_died_empty` (`Order.lean:561`) — about a `step` death, concluding on `sys s'`, which is
  precisely the hypothesis `run_refutes_all` takes. I read the proof: it goes through
  `step_empty_branch`, `makeEmpty_died` at `G := sys s` and `step_died_sys`. Correct, and it is
  the short proof I said it would be.
* **(c)** the scope note at §2d and the README both now say `run_sat`/`run_refutes` and the
  `nonlearn` variants hold only for learn-free runs, and that `run_sat_all`/`run_refutes_all`
  lift that. Confirmed in both files.

**Finding R-C (LOW, CONFIRMED).** One residual over-claim of the same family, newly introduced:
`RunSupOk` (`RefineLearn.lean:1499`) carries `SupOk`/`SupFresh` as a PER-STATE hypothesis, not
as an invariant, so `run_sat_all`/`run_refutes_all` require the caller to supply freshness at
every state of the run. The module docstring and R2.6 both say so, honestly — but the summary
table at the top of the report (line 27) says (i) is "PROVED for all five … under the supply
invariant", which reads as though it were established rather than assumed. The fix is one
sentence in that row. The underlying gap is real but shallow: preservation needs
`allVars H ⊆ allVars G` on the eight non-minting `*_run` lemmas, and all of them already
produce an `H` built by `insert`s of constraints over existing variables.

## R.9 The plan's acceptance criteria, re-scored

| criterion | Round 1 | Round 2 |
|---|---|---|
| (iv) `Wf` proved and preserved | PASS | **PASS** (unchanged) |
| (i) every `step` is a run of the relations, transferring soundness | FAIL-as-stated | **PASS.** `step_refines_all` covers all five branches at the shipped flags; the relations the plan NAMED (`K2SplitStep`, `Cut.ResStep`, `K2ResStep`) are now applied; `run_sat_all`/`run_refutes_all` are no longer learn-free. The two supply hypotheses and the three OFF-by-default flag hypotheses are declared scope, not weakening — R-C asks only that the summary say so |
| (i) `died` paths classified | PARTIAL | **PARTIAL, correctly labelled** — `step_died_empty` adds the loop-level extraction for message 4; 1, 2 and 7 remain, and the report says so |
| (ii) `Terminates` proved or refuted | FAIL | **FAIL, as expected and as instructed** — not attempted; R2.5 is the specification for the stage that would attempt it, and it is sufficient (§R.6) |
| (iii) Stage 7b decided | PASS | **PASS**, with F3 discharged and half of F4 proved (`NoSelfUnif`) |
| audit green | PASS | **PASS** — 838 / `2921; 0` / 36-of-36 standard axioms |

## R.10 What I ask for (none of it blocking)

1. R-C: one sentence in the report's summary row for (i) saying `SupOk`/`SupFresh` are carried
   as per-state hypotheses (`RunSupOk`), not proved preserved.
2. R-A: add the missing sixth row (`Refine.lean:1256`, the `unify` branch) to the R2.5 table.
3. R-B: replace R2.4's "needs the order argument" with the four-writer argument above, or
   simply prove `NoInfRow` — it is a copy of the `NoSelfUnif` proof plus one `learnPartitions`
   case.
4. Cosmetic: mark §2f's table cells "(system-level)"; fix the `split` count in R2.2 (2, not 3).

**Recommendation to the orchestrator:** advance L3, and open (ii) as its own stage with R2.5's
five operations as its brief. Round 2 did what §6c asked, in the order it asked, and did not
overstate it.

### Reviewer's Round-2 scratch
`review-L3/build2.log`, `audit2.log`, `RevAxioms2.lean`, `axioms2.out`. No other files written;
no commits; no `.ei` files created.
