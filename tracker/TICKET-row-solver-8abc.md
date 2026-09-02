# Row-solver follow-ups 8a, 8b, 8c — results (2026-09-01)

Answers the three open bullets of `TICKET-editor-and-solver-followups.md` §8. Method: a
proof in Lean licenses the change; a measurement decides whether to take it. Nothing below
is asserted from a reading of the code alone unless it says so.

**Two changes are ADOPTED as defaults: `-Dermine.resGuard=true` (item 8c) and, on 2026-09-02,
`-Dermine.labelCheckEarly=true` (8c's side-finding, once follow-up item 1 was fixed; see the
end of that section).** Everything else
is behind a flag that defaults OFF, so apart from the guard and one diagnostic-message fix the
shipped compiler's behaviour is unchanged. The rest of what changed is documentation that was
wrong; it is listed under "Defects found and fixed".

| flag | default | item |
|---|---|---|
| `ermine.resGuard` | **`true` — ADOPTED 2026-09-02** | 8c |
| `ermine.labelCheckSaturated` | `false` — measured, buys nothing | 8a |
| `ermine.labelCheckEarly` | **`true` — ADOPTED 2026-09-02**, after follow-up item 1 | 8c side-finding |
| `ermine.spliceGuard` | `false` — measured, do not adopt | 8b |

---

## 8c — guard `resolution`, and make the cut terminate

### The problem, as `Cut.lean` §5 left it

`splitConcrete` consults the reverse lookup `findRHS` before minting and therefore admits
a strictly decreasing measure (`Cut.SplitStep.cands_lt`, `Cut.split_terminates`).
`resolution` consults nothing, mints on every match, and is the sole obstruction:
`Cut.resSeed_diverges`, `Cut.cut_no_decreasing_measure`. The obvious repair is to give
`resolution` the same guard. This item does that and settles what it buys.

### The guard

`resolution`'s minted `z` has no defining partition — unlike `splitConcrete`'s `u`, which
is defined by `u <- x++`, `z` occurs only on right-hand sides. So `Cut.Named` is the wrong
lookup. What names `z` is the rule's FIRST conclusion: `v <- (z, C ∪ D)` says exactly
`z = v \ (C ∪ D)`. Hence

    Resolved G v K  :=  ∃ z, (v <- (z, K)) ∈ G

`Rowpartition/ResGuard.lean` defines it, and `GResStep` has two constructors: `mint` (the
guard fails, `z` fresh — this is `Cut.resResult` verbatim) and `reuse` (the guard holds;
emit only the two conclusions about the lone variables, named by the resolvent already
present).

Implemented in `Constraints.resolution` plus a
`lazy val resolvents` reverse index built at most once per `learnPartitions` call and never
forced when the flag is off. **ADOPTED as the default on 2026-09-02**; `-Dermine.resGuard=false`
restores the previous behaviour exactly, verified in both directions on `gu05` (new default
13.6s, flag off 24.4s, both LOADED). `fresh` is still called at the same point in both modes, so a
guarded and an unguarded run consume the `Supply` identically and differ only in the
partitions they derive — variable numbering is not perturbed at all.

### (a) The guard is not a semantic change — PROVED

`Rowpartition/ResGuard.lean` (20 theorems):

| theorem | what it says |
|---|---|
| `res_reuse_entails` | both reuse conclusions are entailed by the system |
| `GResStep.reuse_models_iff` | a reuse step does not move the model set AT ALL |
| `mint_extend` | the mint branch is a conservative extension; the minted row is forced to `rho v \ (C ∪ D)` |
| `GResStep.satisfiable_iff`, `GResStep.entails_iff` | a guarded step is equisatisfiable with its input and entails the same constraints over the input's own vocabulary |
| `GResSteps.satisfiable_iff`, `GResSteps.entails_iff` | …and so is a whole guarded run |
| `resolvent_unique` | two names for the same resolvent denote the same row in every model |
| `guard_loses_nothing` | when reuse fires, the system ALREADY entails all three conclusions the unguarded rule would have drawn, with the reused name in place of the fresh one |

So the guard is not an approximation. The variable it declines to mint is *provably equal*
to the one it reuses.

### (b) Termination — a dichotomy, both halves proved

**Positive.** `Rowpartition/ResGuardTerm.lean`:

    theorem guarded_terminates_of_satisfiable (G₀ : System) (rho : Assign)
        (hm : SModels rho G₀) :
        ∃ N : ℕ, ∀ (n : ℕ) (G : System), GRun n G₀ G → n ≤ N

with `N = ((allVars G₀).card + gmeas L rho G₀)^2 * 2^L.card` for `L := labelsOf G₀`. The
measure is

    gmeas L rho G = ∑ v ∈ allVars G, unfired L G v * (2 ^ L.card + 1) ^ (rho v).card

Two ingredients, and NEITHER suffices alone. The guard makes each pair (left-hand side,
resolvent key) fire at most once, and every key lives in the fixed finite `L.powerset`
because the rule only ever forms `C ∪ D`, `D \ C`, `C \ D` from concrete parts already
present — that is `unfired`, which `unfired_lt` shows a mint strictly lowers. But minting
CREATES variables, each with a fresh budget, so counting keys bounds nothing. The MODEL
closes the gap: `mint_rank_lt` shows the minted variable denotes a strictly smaller row
than the variable it splits, so the weighting makes a mint strictly decreasing
(`GResStep.mint_gmeas_lt`) and a reuse non-increasing (`GResStep.reuse_gmeas_le`).

This is exactly what the unguarded rule lacks: `Cut.resSeed_diverges` runs on a system that
HAS a model (`Compare.resSeed_satisfiable`), and `guarded_bound_for_resSeed` states the
contrast on that very system. `gRun_one_resSeed` checks the bound is not vacuous.

**Negative.** `Rowpartition/ResGuardDiverge.lean`. The guard does NOT restore termination
in general. Four constraints on four variables and four labels,

    a <- (p, (|f0|))   a <- (q, (|f1|))   b <- (p, (|f2|))   b <- (q, (|f3|))

admit guarded chains of EVERY length (`gSeed_diverges`), hence
`gres_no_decreasing_measure`. Each round's two mints are for a different left-hand side and
a different two-label key than anything the system carries, and the round's fresh children
are the next round's roots. The invariant that makes the lookup miss forever is `NoTwo`: at
the moment of each mint, every constraint with that left-hand side still has a SINGLETON
concrete part while the key has two labels.

**The two halves are complementary, not in conflict.** `gSeed_unsat` proves the divergent
seed has no model, and `gSeed_path_unsat` that every system on the divergent path is
unsatisfiable too — the solver would be searching a problem decided before the first step.
And `gSeed_refuted` proves that the per-label unit propagation of `LabelProp` refutes it at
the single label `f0`, in five propagation steps and with no case split. **Guarded
resolution and the label check are complementary defences, and this gadget is precisely the
shape that needs both.**

### (c) What the compiler does — MEASURED

Where the measurement can be taken at all: ticket §7.9 measured that `resolution` never
fires once in a 129-module stdlib boot, reconfirmed here — **0 `Resolution` derivations
anywhere in the stdlib**. But that is a fact about the STDLIB, not about real code, and
treating it as the latter was an error. Traced over all 110 example modules, `resolution`
fires on **18 of them**: every one of the ten `Ai/` modules, and `gu05`, `gu08`, `np01`, `np02`,
`np03`, `np05`, `RevenueShare`, `RunCalibration` in `incomplete/` — 224 derivations, 159 reaching
committed output. The examples are the population; the stdlib is structurally incapable of
showing this rule at all.

`tracker/tools/gen-res-star.py` builds the population that can. `ResStar<m>` is
`a <- (x_i, (|f_i|))` for `m` distinct labels — SATISFIABLE (take `a = {f_0..f_{m-1}}`,
`x_i = a \ {f_i}`), and the ordinary shape "m single-column projections of one relation".
One JVM per module, nothing else running, `tracker/tools/res-guard-bench.sh`:

| module | guard | wall (s) | solve (s, wall − 12.4s boot) | saturated | derived | Resolution |
|---|---|---:|---:|---:|---:|---:|
| ResStar2 | off | 12.5 | 0.1 | 7 | 3 | 3 |
| ResStar2 | on | 12.6 | 0.2 | 7 | 3 | 3 |
| ResStar3 | off | 12.6 | 0.2 | 22 | 16 | 14 |
| ResStar3 | on | 12.4 | 0.0 | 22 | 16 | 12 |
| ResStar4 | off | 13.5 | 1.1 | 69 | 61 | 38 |
| ResStar4 | on | 12.9 | 0.5 | 69 | 61 | 44 |
| ResStar5 | off | **TIMEOUT (>240)** | — | — | — | — |
| ResStar5 | on | 12.6 | 0.2 | 216 | 206 | 117 |
| ResStar6 | off | **TIMEOUT (>240)** | — | — | — | — |
| ResStar6 | on | 12.8 | 0.4 | 671 | 659 | 335 |

**There is a second cliff, driven by `resolution` rather than `commonSubexpression`, on a
well-typed program, and the guard removes it.** That is what
`guarded_terminates_of_satisfiable` predicts, and §7.9 explains why nobody had seen it.

### (d) Mined from the corpus, not from a probe — and the probe understated it

Running the flags against the corpus's OWN known-hard cases (`tracker/tools/corpus-experiments.sh`
Part 2: the six `.slow` divergers plus the two cheap-end cases, four configurations, one JVM each):

| module | default | `+resGuard` | `genRules=all` | `all +resGuard` |
|---|---:|---:|---:|---:|
| `gu02`, `gu03`, `gu07`, `gu09`, `np05a`, `np05c` (`.slow`) | ~12s LOADED | ~12s LOADED | TIMEOUT | TIMEOUT |
| `gu01_star_join_6dim_inferred` | 11.8s | 11.7s | 22.6s | 23.1s |
| **`gu05_star_join_4dim_concrete_signature`** | **23.9s** | **13.0s** | **24.3s** | **13.1s** |

Two results, one expected and one not.

**Expected:** the six divergers are CSE-driven, so the resolution guard does nothing for them —
they load in ~12s under today's `genRules=cut` and time out under `genRules=all` with the guard
on OR off. That is also the regression check: all six still run fast with everything in this
session's tree.

**NOT expected, and it is the strongest evidence in this ticket.** `gu05` — a REAL corpus
module, not a probe — goes from **~12.0s of solve time to ~1.1s**, an ~11x reduction, in BOTH
rule modes. It is exactly the predicted shape: a star join with a CONCRETE signature, and
Part 1's trace confirms `resolution` fires there (7 derivations, alongside CSE 53, SplitConcrete
37, Substitution 153). The synthetic `ResStar` family found the cliff; the corpus had a case
sitting on it the whole time.

This is what moves `resGuard` from "proved correct, insurance against a shape nobody writes" to
"measured win on a module already in the repository".

Two honest qualifications:

* On the sizes that complete both ways the guard reaches the SAME saturated set (ResStar4:
  69 partitions, 61 derived, either way) and the output is byte-identical. The guard
  changes the work, not the fixpoint — which is `guard_loses_nothing` observed rather than
  proved again.
* The `Gadget` module — the Ermine transcription of `gSeed` — is REJECTED by the shipped
  compiler in 0.03s, identically with and without the guard, with
  `Fields appear twice in row: Set(Gadget.f1)`. That is a sound rejection (the module is
  unsatisfiable) reached by rules the Lean divergence model does not include. So
  `gSeed_diverges` is a statement about the RULE SET, exactly as `Cut.resSeed_diverges` is,
  and **it is not a reproducible compiler hang**. Whether a seed exists that defeats the
  guard AND survives the other rules is open.

  There is a second reason no rule-set divergence transfers directly to the engine, and it
  is worth writing down because no module here models it: `learnPartitions` folds the
  INCOMING partition over `proc` only, so a fixed PAIR of premises is examined exactly once
  — when the later of the two is incorporated — whereas every step relation in this
  development lets a matching pair fire forever. That incoming/processed split is the
  engine discipline `tracker/lean/README.md` item 4 calls "not proved", and it remains not
  proved; what is new is that it is now stated precisely enough to be modelled by whoever
  wants to.

### A second, free change found on the way — and it is NOT free

`Subst.solve` runs `q.expand` — the entire saturation — BEFORE `labelClash`, even though
the check reads only the input partitions. Running it first costs nothing in time and
refutes an unsatisfiable input before the saturation can diverge on it.
`-Dermine.labelCheckEarly=true`, DEFAULT OFF.

Measured over the 66-file corpus, and the reason it stays off is not what I expected.
**Verdicts are identical** — 23 LOADED / 43 REJECTED, `shouldfail` 40/40 — but **26 of 66
error messages change**, all in `shouldfail/`. The trade is two-sided:

* **All 26 get better TEXT.** Every one goes from an internal-variable message to one that
  names a user-visible field and gives the reason, e.g.
  `Infinite row partition for 'r2^579383'` becomes
  `Row partitions are unsatisfiable at field 'Shouldfail.Inf03.a': two parts of one
  partition both contain it`. The messages replaced were `Fields appear twice in row:
  Set(..)` (9), `Infinite row partition for ..` (7), `Incompatible instantiations of ..` (2)
  and other locations (8) — several of which quote a raw `Supply` id at the module header.
* **11 of the 26 get a worse LOCATION**, moving the blame from the user's file into the
  stdlib (`Relation/Row.e`, `Syntax/Relation.e`). That is the same defect as item 1 of the
  follow-ups ticket: the check blames wherever the offending constraint is, and reaching it
  through a stdlib helper points at the helper.

So the honest verdict: this is the right direction and the wrong time. It should go on once
item 1 (blame the call site, not the module) is fixed, and not before — the message text is
a clear win and the location is a clear regression, and the second currently outweighs the
first for anyone reading an error.

**ADOPTED 2026-09-02, DEFAULT ON.** Follow-up item 1 is fixed
(`TICKET-editor-and-solver-followups.md` §1 has the mechanism: a scheme's constraints are
now located at the occurrence that instantiates them, `Term.sub` keeps occurrence
positions, and `solve` reads "the file being compiled" off `tml`). Re-measured from
snapshotted class directories, base vs early with the fix: verdicts identical (23 LOADED /
43 REJECTED, `shouldfail` 40/40), **26 messages change and all 26 are in the user's file
at the call site** -- zero in the stdlib, where before 11 were. The location fixes alone
also move 16 pre-existing messages (10 definition -> call site, 4 stdlib -> user file,
`dup06` gains a position), verdicts unchanged. `incomplete/` 34 files: verdicts identical,
16 messages move to call sites. Per-case before/after: `core/examples/shouldfail/RESULTS.md`.
`-Dermine.labelCheckEarly=false` restores the late position exactly.

---

## 8a — let the label check read the saturated set

### The question

`Subst.solve` runs `labelClash` on the INPUT partitions. Reading the saturated set is sound
iff **input satisfiable ⇒ saturated set satisfiable** (the check only refutes).

### The old justification was wrong, in two ways

The code comment said "propagation is monotone (`forced_mono`), so the saturated set would
be strictly stronger". `forced_mono` is monotone in the SYSTEM (`G ⊆ G'`), and `q.expand`
is not a superset of `q` — `makeEmpty`, `makeConcrete`, `destructiveSub` and `instantiate`
all delete partitions and rename variables. The same wrong sentence was in
`LabelProp.lean`'s docstring for `forced_mono`, where it also claimed the implementation
already reads the saturated set. Both are corrected in place.

### The licence — PROVED

`Rowpartition/Saturate.lean` (25 theorems). `SatStep` is one relation covering, in the
shipped default configuration:

* the whole cut calculus, via `SplitNecessary.CutRuleStep` — CSE reuse and fold,
  `splitConcrete` reuse and mint, cancellation, substitution, self-substitution, common
  partition, resolution (this part was already proved);
* `makeEmpty`, both halves (`empty` propagation and `eraseEmpty`);
* `makeConcrete` / `destructiveSub` (`concrete`);
* `replace`'s rename and its de-duplication emission (`rename`, `dedup`);
* **DELETION** (`weaken`) — which no previous step relation modelled at all: every one
  carries `.subset : G ⊆ G'`, while the solver deletes on at least five paths.

    theorem SatSteps.sat_mono : SatSteps n G₀ G → (∃ rho, SModels rho G₀) → ∃ rho, SModels rho G
    theorem refute_saturated_sound (h : SatSteps n G₀ G) (hr : Refuted G.toList) :
        ¬ ∃ rho, SModels rho G₀
    theorem saturated_not_refuted_of_sat (h : SatSteps n G₀ G) (hsat : ∃ rho, SModels rho G₀) :
        ¬ Refuted G.toList

`satStep_not_reflecting` proves the implication is STRICT: deletion can turn an
unsatisfiable system into a satisfiable one, so **a refutation-only check may move to the
saturated set and an acceptance check may not**. Two refutations the saturation performs
itself are proved sound on the way (`empty_conc_unsat` = "Incompatible instantiations",
`concrete_superset_unsat` = `ensureSuperset`).

Implemented as `-Dermine.labelCheckSaturated=true`, DEFAULT OFF.

### What it buys — MEASURED

See the **Gates** section below for the shared baseline; the 8a-specific numbers are
there too.

**ZERO additional programs are refuted.** On both corpora, and the second one is the
population built to hold exactly the cases this check exists to catch:

| corpus | files | A vs D (`-Dermine.labelCheckSaturated=true`) |
|---|---|---|
| examples + `Ai/` + `shouldfail/` | 66 | **0 differ**, verdicts identical |
| `incomplete/` — 5 `unsound*`, 8 `witness*`, 21 others | 34 | **0 differ**, verdicts identical |

That is the ticket's own stopping condition — *"if it is zero on the corpus, say so and
leave the input version in place."* **Recommendation: leave the check reading the input,
and leave the flag off.**

What `Saturate.lean` is still worth is not nothing: it establishes that the move WOULD be
sound, which nobody had established, and it is what let the wrong justification in the code
(`forced_mono`, "the saturated set would be strictly stronger") be replaced by a correct one
rather than merely deleted. The strengthening is available if a future corpus ever needs it.

### What is still NOT licensed, stated plainly

* `Constraints.disjunction` has no Lean theorem of any kind. It is off by default; with it
  on, nothing above applies.
* `commonSubexpression`'s MINT branch is not a constructor of `SatStep` (it is off under
  `genRules=cut`). `cseMint_sat_mono` records that the missing case would go through.
* `Q.PQueue.build` — the passage from source text to the input partition set — is modelled
  nowhere, and it MINTS for a `Part` whose left-hand side is not a variable. So even the
  "input" system is already a conservative extension of what the user wrote.
* **The weakest link — closed in the direction that matters.** Nothing related the Scala
  `checkLabel`, an imperative fixpoint over a `Map[TypeVar, Boolean]`, to the inductive
  `Forced`. Something does now — with one caveat stated up front: `AlgoWrite` was written
  by transcribing `checkLabel` BY HAND, so this is a model read from the source, not an
  extraction of it, and an edit to that method silently invalidates the correspondence.
  Neither the loop's termination nor its completeness is proved, and `AlgoRun` is
  deliberately LARGER than the real control flow (any order; it even permits overwriting a
  key that `setVar` would only insert) — which is the safe direction for soundness and
  useless for anything else.

`Rowpartition/LabelAlgo.lean` closes it. Rather than model the imperative loop (iteration
order, the `changed` flag, first-clash-wins — none of which bears on soundness), it models
ONE WRITE, guarded by exactly the Scala's condition on the current partial map:

    inductive AlgoWrite (l) (G) (sigma : Var → Option Bool) : Var → Bool → Prop
      | onesLhs | onesOther | lhsFalse | allKnown | lastOne

    theorem algoWrite_forced : Sound l G sigma → AlgoWrite l G sigma v b → Forced l G v b
    theorem checkLabel_clash_unsat (hr : AlgoRun l G (fun _ => none) sigma)
        (hw : AlgoWrite l G sigma v b) (hold : sigma v = some (!b)) : ¬ ∃ rho, Models rho G

plus the three `note` sites that are not `setVar` (`algo_ones_two_refuted`,
`algo_lhs_false_conc_refuted`, `algo_last_none_refuted`) and, for non-vacuity, two closed
runs of the modelled fixpoint — including one on `LabelProp.Unsound01.G`, the compiler's
own soundness bug, refuted by RUNNING the model rather than by hand-picking a derivation.

The deliberate staleness is modelled, not fixed: the Scala computes `unknown` before
`setVar(v, true, …)` writes to `bits`, so a variable that is a part of its own partition is
written `true` and then `false`. `algo_selfPart_refuted` proves that contradiction genuine.

**And it found something.** `algo_ones_two_refuted` needs a hypothesis the specification did
not have: `c.vars.Nodup`. `DupNeeded.nodup_needed` is the counterexample — with
`a <- (b, b)` and `b` known to carry the label, `onesOf = 2` and the Scala reports "two
parts of one partition both contain it", but `Forced` derives nothing false, because
`var_other` requires two DISTINCT variable parts. **The `ones > 1` branch is sound only
because `RHS.abstr` is a `Set[TypeVar]`, so `abstr.toList` is duplicate-free by
construction** — a duplicate is instead removed by `RHS.build` and turned into an explicit
`u <- ()`. Change that representation to a list and the branch reports a clash the model
cannot justify. Worth knowing before anyone "fixes" the RHS representation to match the
`Constraint.vars : List Var` the formalisation uses.

---

## 8b — reconcile what is checked with what is emitted

### The question

`Subst.reduce`'s second case folds over the SATURATED partition list and rewrites the
INPUT constraint list that `solve` publishes: for every partition whose left-hand side is
AMBIGUOUS (existentially bound, or minted by a solver rule) it replaces every right-hand
occurrence of that variable by the partition's own right-hand side. Two things it does not
do, and both matter: it never APPENDS, so the partition it used is discarded and never
emitted; and it never rewrites a LEFT-hand side.

Roughly 121 derived partitions per boot reach committed output this way (ticket §7.9), so
the compiler validates the input and publishes something derived. Is the published residual
entailed by the input?

### The answer: sound, but NOT conservative — with a counterexample

`Rowpartition/Splice.lean` (757 lines) models the case as `spliceC` / `spliceG` / `reduce2`.

**The positive half.**

    theorem splice_sat : Sat rho p → Sat rho c → p.lhs = v → Sat rho (spliceC v p c)

with NO side condition — and getting there is the content. Two subtleties resolve
themselves rather than needing hypotheses: the concrete parts are automatically disjoint
(`Sat rho c` gives `Disjoint c.conc (rho v)` and `Sat rho p` gives `p.conc ⊆ rho v`), and a
variable occurring in both `p.vars` and `c.vars \ {v}` produces a DUPLICATE in the spliced
right-hand side, which `Sat`'s `Pairwise Disjoint` forces empty — and it really is empty,
because that row is inside `rho v` and disjoint from it. Hence `spliceG_models`,
`reduce2_models` and `reduce2_entails`: **every constraint the compiler publishes is
entailed by input ∪ saturated set.** The splice is sound.

**Exactly conservative, for one splice.** `spliceG_backward`: a model of the spliced system
extends, by giving `v` the value its definition demands, to a model of the ORIGINAL system
together with the definition that was discarded. Eliminating an existential variable by its
own definition loses nothing — *when it is really eliminated*. It carries four side
conditions (`v ∉ p.vars`, the parts of `p` pairwise disjoint, and two about concrete parts
and duplicates), and one more that turns out to be the whole story: `hlhs`, that `v` heads
no constraint of `G`.

**And that is the catch.** `DroppedPartition.dropped_can_lose` exhibits a **satisfiable**
three-constraint, four-variable system with **no concrete labels at all**:

    input      G = [ b <- (v),  b <- (y),  v <- (x) ]        v ambiguous
    spliced    p = v <- (y)                                  entailed by G (v = b = y)
    dropped    q = v <- (x)                                  entailed by G (it IS an input)
    residual   spliceG v p G = [ b <- (y),  b <- (y),  v <- (x) ]

`G` entails `x <- (y)`, i.e. `x = y`. The residual does not: take `v = x = {1}` and
`y = b = ∅`. **The published signature admits an assignment of the user-visible row
variables that the input forbids.**

Every hypothesis of the positive theorem holds here except one. `dropped_loses_nothing` is
the positive half —

    theorem dropped_loses_nothing (G) (p q) (hp : p.lhs = v) (_hq : q.lhs = v)
        (hG : Entails G p) (_hG2 : Entails G q) (c) (hc : v ≠ c.lhs ∧ v ∉ c.vars)
        (hlhs : ∀ d ∈ G, d.lhs ≠ v)  ...  (h : Entails G c) : Entails (spliceG v p G) c

— and `hlhs` is what fails. Note `q` and its hypotheses are literally unused in the proof:
under `hlhs` the dropped partition is never needed, because it is a consequence of `G` and
the residual is equivalent to `G` modulo `v`. **The defect is not the drop. It is that
`reduce` discards the definition it substituted with while never rewriting a left-hand
side, so an ambiguous variable that still HEADS a constraint in the published list is left
there with nothing tying it to the rest.**

**A second, independent finding.** `ConcreteMerge.merge_masks_contradiction`: unioning the
two concrete parts, as `spliceC` does, can turn an UNSATISFIABLE input into a SATISFIABLE
residual. In the implementation the two blocks are emitted separately rather than unioned,
so this one is charged to the model — `Rules.rsat_iff_flatten` measures the difference
exactly — until the residual is flattened by `RHS.merge`, which is precisely where "Fields
appear twice in row" is raised. Worth knowing before anyone "simplifies" the emitted
residual by merging its concrete blocks.

### Is it live?  Measured: YES, on 90% of all splices

A correction, recorded because the way it went wrong is instructive. This section first
said "not live", on the strength of **0 dropped-splice instances over a 129-module stdlib
boot**. That figure was wrong twice over:

* **wrong predicate.** The counter had been written to the pre-proof framing of this item
  ("two partitions on one ambiguous variable, the second a silent no-op"). The proof then
  moved the diagnosis — `dropped_loses_nothing` shows the dropped partition is harmless,
  its `q` hypotheses unused — and the operative condition is `hlhs`. The prose above was
  updated to say so; the instrument was not.
* **wrong corpus.** A stdlib boot, where zero of 383 solve inputs carry a concrete label.

Re-measured with the three conditions emitted directly, over all 110 example modules
(`tracker/tools/corpus-experiments.sh`):

| | |
|---|---:|
| splice firings | 23,410 |
| **non-conservative (`hlhs` fails)** | **21,141 — 90%** |
| ...all with `changed=true`, i.e. they really rewrote the published output | 21,141 |
| dropped-splice shape (the old, wrong metric) | 150 |

and not only in user code: the top sites are `Relation/Predicate.e`, `Relation.e`,
`Layout/Report.e`, `Relation/Op.e` and `Tree.e` in the STANDARD LIBRARY, plus
`incomplete/RevenueShare.e`.

**What this does and does not mean.** `hlhs` failing means conservativity is NOT PROVEN for
that splice, not that information IS lost — `DroppedPartition` shows loss is possible under
that condition, not that it is universal. So this is 21,141 splices the compiler cannot
justify, not 21,141 defects.

**What it changes.** `-Dermine.spliceGuard=true` is nowhere near a no-op: it would suppress
90% of splices and move a great many published signatures. Describing it as a surgical fix
was an error that depended on the "latent" finding. The alternative repair set aside below —
emit the partition that was substituted with, keeping the residual equivalent
unconditionally and suppressing nothing — is now the better-looking design, not the heavier
one.

### VERDICT, after measuring the published signatures: DO NOT ADOPT EITHER REPAIR

`.ei` interface files ARE the published signatures, so the decisive experiment is to diff them
with and without the guard (`tracker/tools/ei-diff.sh`, 187 interfaces captured per side, every
`.ei` deleted before each side so neither reads the other's). Result: **18 of 187 differ**, and
inspecting them kills the repair rather than supporting it.

* Most differences are **constraint ORDER** — the known `abs.toList` / `Exists.apply`
  `toSet.toList` hash-order nondeterminism, not semantics. `Relation` (83/83), `Relation.Op`
  (62/62) and `Relation.Predicate` (32/32) publish the same constraints permuted.
* Where content really differs, the guard **degrades** the signature. Five `Ai/` modules go from
  a fully RESOLVED concrete row to an unresolved constrained polymorphic type:

      A (default)     labelled : Relation (|displayName, subjectId, siteId, subjectRef, armName, siteName|)
      B (spliceGuard) labelled : forall t. (exists a rs so. ..4 constraints..) => Relation t

  The splice is doing real work — eliminating existentials and resolving types — and suppressing
  90% of it leaves residue. The `+14` net constraints are NOT recovered information.
* **And the effect is not even consistent.** `Ai/HeadcountPlan` goes the OTHER way: the DEFAULT
  leaves `withUnitCost` unresolved and the guard resolves it to a concrete 9-field row. Its
  constraint set is structurally identical to `ClinicalTrial`'s:

      ClinicalTrial (unresolved under B):  (|X|) <- (rs, so), R <- (K, a, rs), R <- (K, rs, a), t <- (K, rs, so, a)
      HeadcountPlan (unresolved under A):  (|Y|) <- (rs, so), S <- (L, a, rs), S <- (L, rs, a), t <- (L, rs, so, a)

  Same shape, opposite outcomes. So the diff is largely measuring ORDER-SENSITIVITY that the flag
  perturbs, not the guard's semantics.

**No case was found in which the default compiler publishes a demonstrably weaker signature.**
The `A = 0 constraints` cases are the STRONGEST possible output — a concrete row.

So: keep the flag and the proof, adopt neither repair, and record the caveat. What
`Splice.lean` establishes remains true and worth having — the splice is sound
unconditionally, exactly conservative under three conditions, and there EXISTS a system where
dropping those conditions loses a consequence. What the corpus says is that no such system is in
it, and that the conditions fail so often that acting on them costs more than it buys.

**A separate finding, arguably larger than 8b, falls out of this.** Whether a published signature
is FULLY RESOLVED is order-dependent: the same source, with a flag that should not matter, decides
between `Relation (|..9 fields..|)` and `forall t. (..4 constraints..) => Relation t`. That is a
determinism defect in what the compiler publishes and deserves its own ticket item; ticket
§ determinism site (6) (`reduce`'s `abs.toList`) and `Exists.apply`'s `p.toSet.toList` are the
places to start.

### The mechanism, for whoever picks this up — `-Dermine.spliceGuard=true`, DEFAULT OFF

The three hypotheses of `splice_entails_iff` are all **syntactically decidable**, which is what
makes the repair implementable: the compiler can test them and skip the splice when they fail.
`Rowpartition/SpliceGuard.lean` is the licence.

    def SpliceOK (v : Var) (p : Constraint) (G : List Constraint) : Prop :=
      (∀ d ∈ G, d.lhs ≠ v) ∧                                     -- hlhs
      (∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc) ∧           -- hdis
      (∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅)                 -- hdup

    def reduce2G (E) [DecidablePred E] (S G : List Constraint) : List Constraint :=
      S.foldr (fun p acc => if E p.lhs ∧ SpliceOK p.lhs p acc then spliceG p.lhs p acc else acc) G

| theorem | what it says |
|---|---|
| `decidableSpliceOK` | the guard is decidable — the point of the whole definition |
| `reduce2G_models` | soundness: a model of input ∪ saturated models the guarded residual |
| `reduce2G_backward` | **conservativity**: a model of the guarded residual extends, changing only ambiguous variables, to a model of the INPUT |
| `reduce2G_preserves_entailment` | every consequence of the input over non-ambiguous variables survives — and this needs NO hypothesis about the saturated set, not even that its partitions are entailed |
| `dropped_fixed`, `dropped_fixed_residual`, `dropped_fixed_entails` | the guard blocks exactly the splice that lost `x = y`, and the consequence survives |
| `GuardFires.*`, `spliceOK_fires` | it is not "never splice": a closed system where the guard holds, the splice fires and changes the system |

Skipping is sound in the safe direction: the residual keeps `v` and its constraints, so it gets
STRONGER, never weaker, and is still entailed by the input. It does change published signatures,
hence default off and a corpus measurement.

The guard is **sufficient, not necessary** — a splice it rejects is not shown to have been
harmful, only unproven-conservative. And it says nothing about `reduce`'s first case, about which
variables the ambiguity guard actually selects, or about the fold order.

The alternative repair the proof also suggests — emit the partition that was substituted with,
so the residual is equivalent unconditionally — is NOT modelled and NOT implemented. It was set
aside as having the larger blast radius; the measurement above inverts that judgement. Skipping
touches 90% of splices, whereas emitting the definition touches all of them but SUPPRESSES none
and needs no side conditions at all. Whoever picks this up should model and measure that one
before adopting the guard.

For the record, the two options as the proof presents them:

1. **Emit the partition that was used.** Then `p` is back in the residual and
   `splice_entails_iff` applies with `G` replaced by `p :: G`. This requires `reduce` to
   append, which it currently never does.
2. **Skip the splice when the ambiguous variable also heads a `Part` in the accumulator**,
   leaving it and its input constraints in the residual, where it is existentially
   quantified anyway.

Both are sound in the safe direction — the residual gets stronger, never weaker, and stays
entailed by the input — but both change published signatures, so each needs its own flag and
its own corpus measurement. Item 8b asked for the proof or the counterexample; this is the
counterexample, the precise condition, and two repairs, not the repair itself.

### What this file deliberately cannot say

`reduce`'s FIRST case is outside the model. `case (Partition(v, RHSConcr(fs), _), cs)` has
NO ambiguity guard — it fires for every fully concrete partition — and instead of rewriting
`cs` it calls `instantiateType`, committing `v` globally. `Assign` in this vocabulary maps
every variable to a row, so there is no unification-versus-skolem distinction to express:
exactly the distinction `Constraints.makeEmpty` guards with "Cannot unify skolem variable
with empty relation", and which the first case of `reduce` does not guard on its face.
Whether it is reachable with a rigid `v` is a question about the type checker's variable
discipline and cannot be settled in either direction from row partitions alone.

---

## Gates

### The baseline (all sides, `-Dermine.useInterface=false`, per file, one JVM each)

    23 LOADED, 43 REJECTED, 0 UNKNOWN, 66 total

The 43 are the 40 `shouldfail/` modules — **40/40 rejected**, the adoption gate — plus three
pre-existing failures unrelated to any of this work:

| file | why |
|---|---|
| `Interp.e` | parser: `unknown operator ==` |
| `Sample.e` | parser: `panic: trailing virtual semicolon` |
| `Yahoo.e` | `Module not found: 'YahooExtras'` — the CLI sibling-import limitation, which is item 2 of the follow-ups ticket, NOT the unrelated working-tree edit to that file |

### Results

| gate | result |
|---|---|
| `Audit.lean` | **1469 theorems, 0 non-standard axioms**; no `sorry`, `native_decide` or custom axiom anywhere |
| 66-file corpus, `-Dermine.resGuard=true` | **0 of 66 differ** (V+M), verdicts identical, `shouldfail` 40/40 rejected |
| 66-file corpus, `-Dermine.labelCheckSaturated=true` | **0 of 66 differ** (V+M) |
| 66-file corpus, `-Dermine.labelCheckEarly=true` | verdicts identical, but **26 of 66 messages change** (V+M) — see 8c's "second change" above |
| **2026-09-02**, same, after follow-up item 1 | verdicts identical, 26 messages change, **0 blame the stdlib** (was 11); location fixes alone move 16 more, verdicts identical; `incomplete/` 34 files verdicts identical, 16 messages move to call sites |
| 34-file `incomplete/`, `-Dermine.resGuard=true` | **0 of 34 differ** (V+M) |
| 34-file `incomplete/`, `-Dermine.labelCheckSaturated=true` | **0 of 34 differ** (V+M) |
| **cumulative**: 66-file corpus, today's defaults vs pre-work compiler | **0 of 66 differ** (V+M) — 23 LOADED / 43 REJECTED on both sides, every message byte-identical. See below. |
| **cumulative SIGNATURES**: `ei-diff.sh`, same two configs | **13 of 188 interfaces differ**, 40 definitions. Two interfaces exist on one side only, both WINS. **4 definitions REGRESS** — see below and `TICKET-signature-resolution-fragility.md`. |
| `lsp-smoke.sh` | **PASS, 82 checks** |
| `core/test` | **903/904**, the single failure being the pre-existing `Constraints.disjunction sound` generator (`Gave up after only 0 passed tests, 501 discarded`). `Constraints.resolution sound` still passes 100 tests with the guarded signature. |

### What a corpus comparison does and does NOT cover

Comparisons are modulo progress bars and per-run timings, which differ between any two runs.
Nothing else is normalised — but that is not the same as covering everything, and an earlier
version of this line claimed it was.

**(V+M) marks the rows above that compare VERDICTS and ERROR MESSAGES.** That is all a corpus
sweep can compare. A module that loads prints exactly one line, `Importing module 'X'`; it
never prints a signature. Measured, not assumed — across all 66 outputs:

    grep -lE 'forall|rho|<-' cum-new/*.out   ->   0 files

So a fresh-variable id shift or a field print order **cannot show up in these rows**, and a
`0` in them is not evidence about published types. Signatures live in `.ei` files, which
`-Dermine.useInterface=false` suppresses; the instrument for them is `tracker/tools/ei-diff.sh`,
and it is a SEPARATE measurement.

This mattered concretely. `HANDOFF-cumulative-check.md` predicted the cumulative row would
show **15 differing line-pairs** — 14 fresh-variable ids and one field order. It showed 0.
The prediction was wrong, not the measurement: those 15 came from an `.ei` diff and were
chained into an expectation for an instrument that cannot see them. **Two different surfaces,
never comparable.** The adoption of `resGuard` does not rest on this — its signature evidence
was always the separate `.ei` diff — but the table should not imply coverage it never had.

**The cumulative zero was proved live, not assumed.** The standing rule in this work is that a
zero is suspect until the instrument is shown capable of a non-zero; three times on 2026-09-02
a "0 differ" meant "measured nothing". Positive control, through the identical normalisation
and the identical classifier, on four modules `labelCheck` is known to flip:

    VERDICT LOADED -> REJECTED   unsound01_keyed_halves.e      24 differing lines
    VERDICT LOADED -> REJECTED   unsound02_three_way_shard.e   4 of 4 files differ
    VERDICT LOADED -> REJECTED   unsound03_inferred_headers.e
    VERDICT LOADED -> REJECTED   unsound04_dead_helper.e

Also note `corpus-verdicts.py` reads a live directory: the file currently being written
classifies as UNKNOWN until its last line lands, so a sweep in flight always shows exactly one
UNKNOWN tracking the write head. That is not a timeout and not a finding.

### The signature surface, which the corpus rows do NOT cover

Run separately, for exactly that reason. `ei-diff.sh`, today's defaults (side A) against
`-Dermine.genRules=all -Dermine.labelCheck=false -Dermine.resGuard=false` (side B).
**13 of 188 published interfaces differ, across 40 definitions.** Unlike the corpus rows,
this is not a zero, and it does not all point the same way.

**Present on one side only — both are the adopted work behaving as designed:**

| interface | side | why |
|---|---|---|
| `incomplete/gu05_star_join_4dim_concrete_signature.ei` | NEW only | the pre-work compiler does not finish it; `resGuard` does (measured 12.0s -> 1.1s). The cliff, visible as a published interface that simply did not exist before. |
| `incomplete/unsound0{1,2,3,4}.ei` | OLD only | `labelCheck` now REJECTS these four, so no interface is written. Refusing to publish a signature for an unsatisfiable program is the point of the check. |

**Content differences, classified by what actually changed:**

| class | count | reading |
|---|---|---|
| REORDER — same constraint count, same shape | 34 defs | the known cosmetic class from the ten-site determinism inventory in `TICKET-row-constraint-decision.md`. Not new. |
| COUNT — fewer constraints on the new side | 2 defs | `Relation.lookbackJoin` 9 vs 15, `RunCalibration.valueAsOf` 10 vs 14. Not yet examined; fewer is not automatically better. |
| **SHAPE — resolved concrete row becomes constrained polymorphic** | **4 defs** | **a regression.** `Ai_BatteryCycling.withHealth`, `Ai_HeadcountPlan.{labelled,withUnitCost}`, `Ai_RevenueByPeriod.labelled`. |

The four SHAPE regressions have **two independent causes**, established by bisection:

* `BatteryCycling.withHealth` bisects cleanly to **`genRules=cut`** from a clean `.ei` state —
  not `labelCheck`, not `resGuard`. A previously unrecorded cost of a decision already taken.
* `HeadcountPlan.labelled` does not reproduce in isolation under ANY flag setting. It flips on
  **build order**: compiling against a dependency's published `.ei` yields a less resolved type
  than compiling against its source. That is item **8b's proven defect
  (`Splice.lean : DroppedPartition.dropped_can_lose`) reaching a user-visible signature** — so
  8b is NOT latent, and the decision to decline its repair needs re-examination.

Both are written up in `TICKET-signature-resolution-fragility.md`, which is REINSTATED as a
confirmed defect report on this evidence.

**They are QUALITY defects, not soundness defects — settled, not assumed.** Empirically, a
consumer annotated at the exact 9-field header is ACCEPTED while one field missing or one
field extra is REJECTED, so the probe discriminates and the published constraints really do
pin `t`. Then proved for the whole shape in `Rowpartition/DerivedColumn.lean`
(`t_determined_of_sat`), which needs neither `L ⊆ K` nor `d ∉ K` nor the disjointness halves
of its hypotheses: the three constraints' concatenation content alone forces
`rho t = insert d K`. So nothing is unsound and nothing is unusable; what is lost is
signature quality, and the constraints travel to every caller.

Note `ei-diff.sh`'s closing line still reads "0 = the splice loses nothing that reaches an
interface" — that legend belongs to its original 8b use and is misleading for any other
comparison.

## Defects found and fixed (none behind a flag)

One of these changes compiler output (2); the others are documentation that asserted things
that are not so.

1. **The file-header resolution diagram in `Constraints.scala` was the UNSOUND rule.** It
   paired each lone variable with the concrete part of its OWN premise; premise 1 forces
   `x` disjoint from `C` while `x <- C* z` forces `C` inside `x`, so together they force
   `C` empty and the rule reports a type error on a program that has none. Mechanised as
   `Rule6Header.header_not_conservative` / `header_makes_unsat`. The prose above the diagram
   and `def resolution` itself always had the correct crossed form — verified this session
   by two independent readings, which is the discharge of README item 3 under "proved on
   paper only". Diagram corrected, with the reason recorded in place.
2. **`checkLabel` could report an EMPTY explanation.** `unknown` is computed before
   `setVar(v, true, …)` writes to `bits`, so when a variable is a part of its own partition
   it is still listed in `unknown` and is then written `false` — a correct conclusion
   reported as "Row partitions are unsatisfiable at field 'x': " with nothing after the
   colon. All three `""` messages replaced by the real reasons.
3. **Three Lean/Scala comments asserted a false justification.** `Subst.solve` said the
   saturated set "would be strictly stronger" by `forced_mono` — but `forced_mono` is
   monotone in the SYSTEM and `q.expand` is not a superset of `q`. `LabelProp.forced_mono`'s
   docstring said the same AND that the implementation already reads the saturated set,
   which it does not. `LabelProp.models_unchanged` was presented as establishing
   non-generativity; it is literally `Models rho G ↔ Models rho G := Iff.rfl`, a tautology
   with no content. All three corrected in place, each with the reason.
4. **`tracker/lean/README.md` claimed `Rowpartition.lean` imports every module and that the
   axiom audit covers them all.** It did not import `CutSearch`, whose 125 theorems were
   therefore outside the audit — and `CutSearch` cannot be built on this machine at all
   (OOM-killed at 15 GB, twice). Root and README both corrected; the gap is now documented
   rather than denied. The audit itself now reports **1339 theorems, 0 non-standard
   axioms**, up from 1197. The headline count "15 modules, 960 named theorems" and four of
   the fifteen per-module counts matched no reproducible count either; all recounted, with
   the counting command written down.
5. **The corpus harness was measuring nothing on its second side.** `bin/ermine` WRITES
   `.ei` interface files and `ermine.useInterface` defaults to true, so an A/B comparison
   has side B read what side A just wrote. Caught mid-run by the type-hole report vanishing
   from `Holes.e`; `tracker/tools/corpus-run.sh` now deletes them and forces
   `-Dermine.useInterface=false`, and the trap is in `ROW-CONSTRAINT-STATE.md`.

## Files

    core/.../Constraints.scala   GenRules.resGuard / .labelCheckEarly / .labelCheckSaturated;
                                 guarded `resolution`; `learnPartitions`' resolvent index;
                                 corrected header diagram; three clash messages
    core/.../Subst.scala         `checkLabels` extracted; early and saturated-set variants
    tracker/lean/Rowpartition/ResGuard.lean         20 thms   the guard is sound
    tracker/lean/Rowpartition/ResGuardTerm.lean     30 thms   terminates on satisfiable input
    tracker/lean/Rowpartition/ResGuardDiverge.lean  33 thms   and not in general
    tracker/lean/Rowpartition/Saturate.lean         25 thms   the licence for 8a
    tracker/lean/Rowpartition/Splice.lean           29 thms   8b: sound, and a counterexample
    tracker/lean/Rowpartition/LabelAlgo.lean       57 thms   checkLabel's writes are all Forced
    tracker/tools/gen-res-star.py       the probe family on which `resolution` fires
    tracker/tools/res-guard-bench.sh    times it both ways, one JVM per module
    tracker/tools/corpus-run.sh         per-file corpus runner (never batch-load)
    tracker/tools/corpus-verdicts.py    LOADED/REJECTED per file, and a two-run diff
    tracker/tools/rowtrace-summary.py   `-Dermine.rowTrace` summary, incl. dropped splices
