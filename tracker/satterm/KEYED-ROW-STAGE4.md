# Stage 4 — the CONCRETE-ROW reuse: does it bound minting under the loop's deletions?

Date 2026-09-03, branch `scala3-migration`.  Stage 1 (the additive keyed theorem) is
`tracker/satterm/KEYED-SPLIT.md` / `Rowpartition/KeyedSplit.lean`; Stage 2 (the flag, adopted
as the default the same day) is `tracker/satterm/KEYED-SPLIT-STAGE2.md`; Stage 3 (the loop
layer, outcome (W)) is `tracker/satterm/KEYED-LOOP-STAGE3.md`.  This file is Stage 4.

LEAN ONLY.  No Scala edit, no `sbt`, no `bin/ermine` run, nothing committed.  Toolchain:

```
export PATH=$HOME/.elan/bin:$PATH                       # Lean 4.33.1, Mathlib v4.33.1
cd /home/dmitry/research/ermine/ermine-scala/tracker/lean
lake build Rowpartition        # Build completed successfully (817 jobs)      (816 before)
lake env lean Audit.lean       # 2216 theorems audited; non-standard axioms: 0 (2086 before)
```

Scratch (`#print axioms` for every headline, never inside a module):
`/home/dmitry/.claude/jobs/880c725d/tmp/PrintAxiomsStage4.lean`, output
`print-axioms-stage4.out` — all 27 are `[propext, Classical.choice, Quot.sound]`.

---

## 0. What was asked

Stage 3 proved (W): the KEYED split guard does not survive `makeConcrete` / `destructiveSub`,
because the guard's witness `v <- (z, K)` is exactly what the concretisation destroys — as a
DEFINITION of the concretised variable (`notMem_lone_lhs`) or, the mode the engine runs on, as
a MENTION of it (`notMem_lone_mention`).  Stage 4 asks whether one more REUSE clause repairs
it, and repairs two ways in which Stage 3's model was LESS than the compiler:

1. **the `srs` re-expression** — `makeConcrete` cancels every ONE-abstract definition
   `u <- (z, K)` against `u <- ((|C|))` *before* `destructiveSub` drops it, leaving
   `z <- ((|C \ K|))` behind (`Constraints.scala`, `makeConcrete`'s `val can`,
   `destructiveSub`'s `val srs`, and the `keepDefs` comment).  `NameLoss.concretizeKeep`
   drops the definition and derives nothing;
2. **the syntactic-first lookup** — `splitConcrete` asks `rhss(RHSAbstr(abstr))` FIRST, and
   `KeyedSplit.KSplitApp` has no `¬ Named` premise (`KEYED-LOOP-STAGE3.md` §2.4).

and to answer, in this order of preference, (T1) minting is bounded on satisfiable input,
(T2) a partial bound with the missing piece named exactly, (W) a satisfiable witness with
unbounded vocabulary.

## 1. The answer: **(T2)** — and both halves of it are theorems

**The concrete-row reuse works, and it is not enough, and the reason is not the split.**

* **(T1) for the split.**  With the new clause and the faithful `srs`, the extended
  `splitConcrete` mints BOUNDEDLY on satisfiable input under the loop's deletions, in every
  run order — `mintsBoundedOnSat_splitFragment`, with the explicit bound
  `|allVars G₀| + hmeas L rho G₀`.  Read the scope exactly: the relation it bounds is
  `K2SplitLoopStep` = the non-generative rules + the extended `splitConcrete` + the faithful
  concretisation, i.e. **guarded `resolution` REMOVED from the calculus**, not merely
  restricted.  Stage 3's own witness dies: at the system the faithful
  `makeConcrete u` reaches, `W3`'s re-mint is REFUSED (`W3_not_mintable`) and the new branch
  emits `z <- (x, y)` instead (`W3_row_reuse`) — the very constraint the shipped loop reaches
  only afterwards, by `common`-unifying the re-minted name with `z` (measured at 55 of 55
  bases in Stage 3).
* **(W) for the calculus as a whole.**  `MintsBoundedOnSatKeyed2` — the statement the brief
  asks about, over the relation that also contains guarded `resolution` AS SHIPPED — is
  FALSE (`not_MintsBoundedOnSatKeyed2`).  The witness `W4` is three constraints, satisfiable,
  and contains **no split premise at all**: every right-hand side has at most one variable, so
  `splitConcrete`'s `abstr.size >= 2` guard never fires.  It is guarded RESOLUTION that mints
  for ever, by exactly Stage 3's failure mode 2: the resolvent `v <- (w, C ∪ D)` it installs
  is a MENTION of the fresh `w`, `makeConcrete w` absorbs it, the key re-opens, and the two
  premises `v <- (x, C)`, `v <- (y, D)` are untouched.
* **The missing piece, named exactly — and closed.**  `resolution`'s mint guard is still
  keyed on `Resolved`.  Key it on `Carried` too (the same widening, with the same
  concrete-row reuse branch) and the whole loop-extended calculus is bounded:
  `mintsBoundedOnSatKeyed2Star`.  `keyed2_star_vs_shipped_res` states the contrast in one
  line.

So: **no change to `splitConcrete` alone can make the loop-extended calculus terminate.**
That is new relative to Stage 3, which left the impression that the split was the engine.

## 2. The relation, verbatim (`Rowpartition/KeyedRow.lean` §5)

The guard, first.  A key `(v, K)` is CARRIED when the system names the row `v \ K` — either
as a lone witness, or as a pair of concrete definitions:

```lean
def ConcCarried (G : System) (v : Var) (K : Row) : Prop :=
  ∃ C ∈ G.image Constraint.conc, mk v ∅ C ∈ G ∧ ∃ z ∈ allVars G, mk z ∅ (C \ K) ∈ G

def Carried (G : System) (v : Var) (K : Row) : Prop := Resolved G v K ∨ ConcCarried G v K
```

(the existentials are bounded by `G` only to keep the predicate decidable, which the budget
needs; `concCarried_iff : ConcCarried G v K ↔ ∃ C z, mk v ∅ C ∈ G ∧ mk z ∅ (C \ K) ∈ G`.)

The four branches of `splitConcrete`, in the source's order.  **Every non-syntactic branch
carries `¬ Named G (vset c)`** — that is the §2.4 gap of Stage 3, closed for this relation:
a mint of `K2SplitStep` is a mint the shipped rule would take.

```lean
structure K2MintApp (G : System) (c : Constraint) (u : Var) : Prop where
  mem       : c ∈ G
  conc_ne   : c.conc ≠ ∅
  two_le    : 2 ≤ (vset c).card
  unnamed   : ¬ Named G (vset c)                 -- the SYNTACTIC lookup, asked FIRST
  uncarried : ¬ Carried G c.lhs c.conc           -- the KEYED lookup, WIDENED
  fresh     : u ∉ allVars G

structure K2KeyApp (G : System) (c : Constraint) (u : Var) : Prop where
  mem, conc_ne, two_le, unnamed  (as above)
  witness   : mk c.lhs {u} c.conc ∈ G

structure K2RowApp (G : System) (c : Constraint) (u : Var) (C : Row) : Prop where
  mem, conc_ne, two_le, unnamed  (as above)
  lhsConc   : mk c.lhs ∅ C ∈ G                   -- the premise's lhs is concrete
  carrier   : mk u ∅ (C \ c.conc) ∈ G            -- ... and `u` carries the complement row

inductive K2SplitStep : System → System → Prop
  | syn  {G c u}   : SplitReuseApp G c u   → K2SplitStep G (splitReuseResult G c u)
  | key  {G c u}   : K2KeyApp G c u        → K2SplitStep G (kSplitReuseResult G c u)
  | row  {G c u C} : K2RowApp G c u C      → K2SplitStep G (kSplitReuseResult G c u)
  | mint {G c u}   : K2MintApp G c u       → K2SplitStep G (splitResult G c u)
```

`K2MintApp.toSplitApp : K2MintApp G c u → SplitApp G c u ∧ KSplitApp G c u` is the §2.4 gap
closed, machine-checked: every mint of this relation passes BOTH of the shipped lookups.

`splitReuseResult G c u = insert (mk c.lhs {u} c.conc) G` (the shipped `SplitConcrete` reuse,
already a `NonGenStep`); `kSplitReuseResult G c u = insert (mk u (vset c) ∅) G` (the shipped
`SplitKeyed` reuse); `splitResult` is `Cut`'s, unchanged.  So the NEW branch emits the bare
`u <- (vset c)`, exactly as the keyed reuse does — a NAME, never silence, as the design rule
of `ROW-CONSTRAINT-STATE.md` requires.

**Soundness of the new branch**, proved in the style the brief asks for
(`ksplit_reuse_sat` / `KSplitStep.reuse_models_iff`):

```lean
theorem conc_lone_sat {rho} {v z} {C K}
    (hv : Sat rho (mk v ∅ C)) (hz : Sat rho (mk z ∅ (C \ K))) (hK : K ⊆ C) :
    Sat rho (mk v {z} K)

theorem concRow_reuse_sat {rho} {v z} {S} {C K}
    (hc : Sat rho (mk v S K)) (hv : Sat rho (mk v ∅ C)) (hz : Sat rho (mk z ∅ (C \ K))) :
    Sat rho (mk z S ∅)

theorem K2RowApp.models_iff (happ : K2RowApp G c u C) (rho) :
    SModels rho (kSplitReuseResult G c u) ↔ SModels rho G
```

`conc_lone_sat` is the one semantic fact the whole stage rests on: **a concrete definition of
`v` plus a concrete definition of the complement row IS a lone witness** `v <- (z, K)`.
`concRow_reuse_sat` is then literally `ksplit_reuse_sat` applied to it (the side condition
`K ⊆ C` comes from the split premise itself: `c.conc ⊆ rho c.lhs`).

The loop relations:

```lean
inductive K2DefaultStep : System → System → Prop     -- additive; resolution AS SHIPPED
  | nongen : NonGenStep G G' → K2DefaultStep G G'
  | split  : K2SplitStep G G' → K2DefaultStep G G'
  | gres   : GResStep G G' → K2DefaultStep G G'

inductive K2LoopStep : System → System → Prop
  | additive : K2DefaultStep G G' → K2LoopStep G G'
  | concrete : mk u ∅ C ∈ G → concretizeSrs u C G ≠ G → K2LoopStep G (concretizeSrs u C G)

inductive K2LoopRun : ℕ → System → System → Prop
  | refl (G) : K2LoopRun 0 G G
  | tail : K2LoopRun n G₀ G → K2LoopStep G G' → G ≠ G' → K2LoopRun (n + 1) G₀ G'

def MintsBoundedOnSatKeyed2 : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K2LoopRun n G₀ G → (allVars G).card ≤ N
```

and, with `resolution` rekeyed the same way,

```lean
inductive K2ResStep : System → System → Prop
  | mint  : ResPair G v x y C D → ¬ Carried G v (C ∪ D) → z ∉ allVars G →
            K2ResStep G (resResult G v x y C D z)
  | reuse : ResPair G v x y C D → mk v {z} (C ∪ D) ∈ G →
            K2ResStep G (resReuseResult G x y C D z)
  | row   : ResPair G v x y C D → mk v ∅ F ∈ G → mk z ∅ (F \ (C ∪ D)) ∈ G →
            K2ResStep G (resReuseResult G x y C D z)

inductive K2StarStep     -- nongen + K2SplitStep + K2ResStep
inductive K2StarLoopStep -- ... + the same `concrete` constructor
def MintsBoundedOnSatKeyed2Star : Prop := (as above, over K2StarLoopRun)
```

`K2ResStep.mint_toGRes` records that every rekeyed resolution mint is a shipped guarded mint
(`Carried` is weaker than `Resolved`, so the new guard refuses strictly more), and
`K2ResStep.row_models_iff` proves the new resolution branch entailed, again through
`conc_lone_sat` + the existing `ResGuard.reuse_sat`.

The split fragment on its own is `K2SplitLoopStep` (`nongen` + `split` + `concrete`), which
embeds in the star relation (`K2SplitLoopStep.toStar`, `K2SplitLoopRun.toStar`).

## 3. The deletion step, made faithful to `srs` (§3)

```lean
def srsOf (u : Var) (C : Row) (G : System) : System :=
  (allVars G).biUnion (fun z =>
    (G.filter (fun c => c = mk u {z} c.conc)).image (fun c => mk z ∅ (C \ c.conc)))

def concretizeSrs (u : Var) (C : Row) (G : System) : System :=
  concretizeKeep u C G ∪ srsOf u C G

theorem mem_srsOf : d ∈ srsOf u C G ↔ ∃ z K, mk u {z} K ∈ G ∧ d = mk z ∅ (C \ K)
theorem concretizeKeep_subset_srs (u C G) : concretizeKeep u C G ⊆ concretizeSrs u C G
theorem concretizeSrs_sound (hmem : mk u ∅ C ∈ G) :
    ∀ rho, SModels rho G → SModels rho (concretizeSrs u C G)
theorem allVars_concretizeSrs_subset (hmem : mk u ∅ C ∈ G) :
    allVars (concretizeSrs u C G) ⊆ allVars G
theorem concretizeSrs_concSub (hmem : mk u ∅ C ∈ G) (hcs : ConcSub L G) :
    ConcSub L (concretizeSrs u C G)
```

**The side condition, stated honestly rather than hidden.**  `srsOf` writes `C \ K`
unconditionally; the fact it stands for is cancellation, whose Scala guard is `con1 ⊆ con2`,
i.e. `K ⊆ C`.  Under a model that guard is automatic —

```lean
theorem key_subset_of_model (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (hw : mk u {z} K ∈ G) :
    K ⊆ C
```

— so nothing is lost, and soundness (`srs_sat`, `concretizeSrs_sound`) is stated for modelled
systems only, which is the only setting the whole stage lives in.  `concretizeSrs` is strictly
larger than `concretizeKeep`, so it is not a weakening of Stage 3's model in any direction:
it adds the facts the compiler really has.

**`concDef_persists`** — the persistence the brief asks for:

```lean
theorem concDef_persists_of_ne (h : mk p ∅ D ∈ G) (hpu : p ≠ u) :
    mk p ∅ D ∈ concretizeSrs u C G
theorem concDef_persists (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (h : mk p ∅ D ∈ G) :
    mk p ∅ D ∈ concretizeSrs u C G
```

A bare concrete definition mentions nothing, so `absorbC` leaves it alone and it is carried
into the image; and if it happens to define the variable being concretised, then under a model
`conc_unique_of_model` says the two rows agree and the concretisation re-inserts exactly it.

## 4. The invariant, verbatim: **once carried, always carried** (§4)

This is the whole content of the stage.  Stage 3's two failure modes are the two ways a lone
witness turns into a concrete-row carrier:

```lean
-- failure mode 1: the DELETED definition (`notMem_lone_lhs`).  No model needed.
theorem carried_of_deleted_def (hw : mk u {z} K ∈ G) : Carried (concretizeSrs u C G) u K

-- failure mode 2: the ABSORBED mention (`notMem_lone_mention`).  Needs `K ∩ C = ∅`,
-- which a model forces.
theorem carried_of_absorbed_mention (hm : SModels rho G) (hc : mk u ∅ C ∈ G)
    (hw : mk v {u} K ∈ G) (hvu : v ≠ u) : Carried (concretizeSrs u C G) v K

-- and therefore, in one statement:
theorem carried_concretizeSrs (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (h : Carried G v K) :
    Carried (concretizeSrs u C G) v K
```

`KeyedLoop.resolved_of_concretizeKeep` could only make this claim for the keys the
concretisation does not touch.  `Carried` — unlike `Resolved` — is an invariant of the
DELETING step, and that is exactly why the budget below survives it.

## 5. The measure, and the bound (§6–§7)

`ResGuardTerm.unfired` / `gmeas` verbatim, with `Carried` in place of `Resolved`:

```lean
def uncarried (L : Finset Label) (G : System) (v : Var) : ℕ :=
  (L.powerset.filter (fun K => ¬ Carried G v K)).card

def hmeas (L : Finset Label) (rho : Assign) (G : System) : ℕ :=
  ∑ v ∈ allVars G, uncarried L G v * (2 ^ L.card + 1) ^ (rho v).card
```

with `uncarried_le_pow`, `uncarried_le_of_carried`, `uncarried_le`, `uncarried_lt`,
`hmeas_congr`, and the two lemmas that carry the argument:

```lean
theorem hmeas_le_of_carried (rho) (hAV : allVars G' ⊆ allVars G)
    (hcar : ∀ v K, Carried G v K → Carried G' v K) : hmeas L rho G' ≤ hmeas L rho G

theorem hmeas_mint_lt (hsub : G ⊆ G') (hz : z ∉ allVars G)
    (hAV : allVars G' = insert z (allVars G)) (hv : v ∈ allVars G) (hKL : K ⊆ L)
    (hg : ¬ Carried G v K) (hc' : Carried G' v K) (hrank : (rho z).card < (rho v).card) :
    hmeas L rho G' < hmeas L rho G
```

`hmeas_mint_lt` is stated once and used by BOTH mints: the parent pays one unit of budget at
the key it just closed, the fresh name receives a whole budget but at a strictly smaller
exponent, and `ResGuardTerm.budget_mul_pow_lt` says a whole budget there is worth less than
the single unit given up.  `hmeas_le_of_carried` is what the CONCRETISATION needs, and
`carried_concretizeSrs` is its hypothesis.  Then:

```lean
theorem K2StarLoopStep.measure_step (h : K2StarLoopStep G G') (hcs : ConcSub L G)
    (hm : SModels rho G) :
    ∃ rho', SModels rho' G' ∧ (∀ v ∈ allVars G, rho' v = rho v) ∧
      (allVars G').card + hmeas L rho' G' ≤ (allVars G).card + hmeas L rho G

theorem K2StarLoopRun.invariant (h : K2StarLoopRun n G₀ G) :
    ∀ rho₀, SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧
        (allVars G).card + hmeas L rho G ≤ (allVars G₀).card + hmeas L rho₀ G₀

theorem K2StarLoopRun.allVars_card_le (h : K2StarLoopRun n G₀ G) (rho) (hm : SModels rho G₀)
    (hcs : ConcSub L G₀) : (allVars G).card ≤ (allVars G₀).card + hmeas L rho G₀
```

### 5.1 (T1), twice, with the explicit bound

```lean
theorem mintsBoundedOnSatKeyed2Star : MintsBoundedOnSatKeyed2Star :=
  fun G₀ rho hm =>
    ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀,
      fun _ _ h => h.allVars_card_le rho hm (labelsOf_concSub G₀)⟩

theorem mintsBoundedOnSat_splitFragment (G₀ : System) (rho : Assign) (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K2SplitLoopRun n G₀ G → (allVars G).card ≤ N :=
  ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀, ...⟩
```

**The bound is `|allVars G₀| + hmeas L rho G₀` with `L := labelsOf G₀`**, i.e.

    N  =  |allVars G₀|  +  Σ_{v ∈ allVars G₀} uncarried(L, G₀, v) · (2^|L| + 1)^|rho v|
       ≤  |allVars G₀| · (1 + 2^|L| · (2^|L| + 1)^|L|)

since every `rho v` is a subset of `L` along a run of a system whose labels are `L`.  Compare
Stage 1's `KRun.length_le : n ≤ M · 2^M · 2^|L|` with `M := |allVars G₀| + gmeas L rho G₀`:
Stage 4's bound is on the VOCABULARY, not on the run length, and it must be — the any-order
relation permits add/delete cycles, so length is not the right measure (the brief's point).

The reading is licensed by

```lean
theorem K2LoopStep.allVars_cases (h : K2LoopStep G G') :
    allVars G' ⊆ allVars G ∨ ∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G)
```

(and its `K2StarLoopStep` twin): every loop step keeps the vocabulary, shrinks it, or adds
exactly one fresh variable, and only the two MINTS do the last.  So a bound on
`(allVars G).card` is a bound on the number of mints.

## 6. (W): `W4`, the split-free witness (§8)

```
W4 :  v <- ((|a, b, c|)),   v <- (x, (|a|)),   v <- (y, (|b|))
      model  v = {a,b,c},   x = {b,c},   y = {a,c}
```

Three constraints, three variables (`v = 0`, `x = 1`, `y = 2`), three labels
(`a = 1`, `b = 2`, `c = 3`); `C = {a}`, `D = {b}`, `K = C ∪ D = {a,b}`, `E = {a,b,c}`,
`R = E \ K = {c}`.  `W4_models` : satisfiable.  `W4_inv` : the resolvent key `(v, K)` is OPEN
at the input.  **No constraint of `W4` is a split premise** — every right-hand side has at
most one variable, so `abstr.size >= 2` never holds, and `splitConcrete` (in ANY of its four
branches) never fires anywhere in the run.

The round (`W4Inv.round`), three productive `K2LoopStep`s from any system satisfying the
invariant, `w` any variable outside its vocabulary:

1. **guarded resolution MINTS** `w`: `v <- (w, (|a,b|))`, `x <- (w, (|b|))`, `y <- (w, (|a|))`.
   The guard `¬ Resolved G v (C ∪ D)` is open.
2. **CANCELLATION** of `v <- (w, (|a,b|))` against `v <- ((|a,b,c|))` — `K ⊆ E`, one variable
   left over — emits `w <- ((|c|))`.
3. **`makeConcrete w`** (`concretizeSrs w R _`): the resolvent `v <- (w, (|a,b|))` is a
   MENTION of `w`, so `absorbC` rewrites it to `v <- ((|a,b,c|))`, which is already present;
   `x <- (w, (|b|))` and `y <- (w, (|a|))` likewise become `x <- ((|b,c|))`, `y <- ((|a,c|))`.
   The key `(v, K)` is open again, the two premises `v <- (x, (|a|))`, `v <- (y, (|b|))` are
   untouched, and `w <- ((|c|))` is in the vocabulary for good.

`srsOf` contributes nothing here — the freshly minted `w` has no one-abstract definition to
re-express (`srsOf_eq_empty`, `concretizeSrs_eq_concretizeKeep`) — so the SAME three steps are
also steps of Stage 3's `KeyedLoop.KLoopStep`, and **`W4` refutes Stage 3's
`TerminatesOnSatKeyedLoop` as well, with no split step anywhere**, which Stage 3's `W3` does
not.  That is a theorem here, not an argument:

```lean
theorem W4_mints_unbounded (n : ℕ) :
    ∃ G, K2LoopRun (3 * n) W4 G ∧ n + 3 ≤ (allVars G).card
theorem not_MintsBoundedOnSatKeyed2 : ¬ MintsBoundedOnSatKeyed2
theorem keyed2_star_vs_shipped_res :
    MintsBoundedOnSatKeyed2Star ∧ ¬ MintsBoundedOnSatKeyed2
theorem W4_kloop_mints_unbounded (n : ℕ) :
    ∃ G, KeyedLoop.KLoopRun (3 * n) W4 G ∧ n + 3 ≤ (allVars G).card
theorem W4_not_TerminatesOnSatKeyedLoop : ¬ KeyedLoop.TerminatesOnSatKeyedLoop
```

**What the compiler's `common` would do to it** (argued, not run — no `bin/ermine` in this
stage).  Round 1's step 2 gives `w <- ((|c|))`; round 2's gives `w' <- ((|c|))`.  Two
partitions with the same right-hand side is exactly `incorporateAll`'s `common` trigger, so
the loop would `unify(w, w')` and the second round would collapse into the first — the same
fourth defence Stage 3 measured at 55 of 55 bases on `W3`.  There is a second, earlier
defence on this witness that `W3` did not have: `W4`'s `v` is CONCRETE at the input, so the
real loop would run `makeConcrete v` and `destructiveSub` would DELETE both premises
`v <- (x, (|a|))` and `v <- (y, (|b|))` (one abstract part each, `keepDefs` keeps only
`abs.size >= 2`), re-expressing them as `x <- ((|b,c|))` and `y <- ((|a,c|))` — after which no
`ResPair` exists and the engine cannot start.  So `W4`, like `W3`, is a statement about the
RELATION in every order, not a prediction about the shipped loop; and, like `W3`, it is
exactly the relation the termination theorems of this development quantify over.

**MEASUREMENT, added after the agent returned (the brief forbade it `bin/ermine`; session,
2026-09-03).** `W4` as a `json:` seed for `tracker/repro/satterm/` (`v = {l1,l2,l3}`,
`x = {l2,l3}`, `y = {l1,l3}`), 40 id bases, default flags: **SOLVED 40/40**, fresh ids drawn
0 at 37 bases, 1 at 2, 3 at 1. Traced at base 5 (3 draws, 1 of them a mint): the two
one-part premises are dequeued before the concrete definition, so `resolution` mints the
resolvent once (`v <- (w, l1 l2)`, `x <- (w, l2)`, `y <- (w, l1)`); then `v <- ((|l1,l2,l3|))`
is dequeued, `makeConcrete v` fires, and the cancellations make `w`, `x`, `y` concrete
(`w = {l3}`) — every variable is concrete and the solve ends. At the 37 bases where the
concrete definition is dequeued first, the one-part premises are absorbed and nothing mints.
So in the loop this engine never reaches its second round: the defence is `makeConcrete`'s
own order (concrete facts absorb the premises the next round would need), not `common` —
the agent's argument, confirmed. As with `W3`, that is a property of `incorporateAll`'s
single pass that no relation states.

## 7. The Stage 3 witness, re-run (§10)

```lean
theorem srsOf_W3 : srsOf u C W3 = {mk z ∅ D}
theorem W3srs_eq  : concretizeSrs u C W3 = insert (mk z ∅ D) W3sat
theorem W3_carried      : Carried (concretizeSrs u C W3) u K
theorem W3_not_mintable (w : Var) : ¬ K2MintApp (concretizeSrs u C W3) W3def w
theorem W3_row_reuse    : K2RowApp (concretizeSrs u C W3) W3def z C
```

Stage 3's `makeConcrete u` reaches `W3sat = {u <- ((|k,c|)), u <- (x, y, (|k|))}`, where BOTH
shipped lookups miss and the re-mint is enabled (`KeyedLoop.W3sat_remint_enabled`, measured in
the real loop at 55 of 100 id bases).  The FAITHFUL step reaches `W3sat` plus the cancellation
fact `z <- ((|c|))`, and there the key `(u, (|k|))` is CARRIED, the mint is refused, and the
`row` branch emits `z <- (x, y)` — the constraint the shipped loop obtains only afterwards, by
`common`-unifying the re-minted name with `z`.  **The rule does in every order what `common`
does in some.**

## 8. The mechanism notes of the brief, checked

* *"With faithful `srs`, concretising `u` leaves `z <- ((|C \ K|))` behind, so the premise
  `u <- (x, y, K)` finds carrier `z` and REUSES: no mint at all on `W3`."* — **TRUE**,
  `W3_row_reuse` / `W3_not_mintable`; generalised as `carried_of_deleted_def`.
* *"The mention-rewrite mode: `v <- (u, K')` becomes `v <- ((|K' ∪ C|))`; a premise
  `v <- (S', K')` now has complement `(K' ∪ C) \ K' = C` (if `K' ∩ C = ∅`, which a model
  forces) and carrier `u` itself."* — **TRUE**, `carried_of_absorbed_mention`, with the
  disjointness discharged from the model exactly as the note says.
* *"A mint on a concrete-lhs premise whose complement row `D` has no carrier yet ... In a bad
  order a SECOND premise with complement `D` but a different key may mint again before either
  exists.  Is the number of such mints per `D` bounded?  By what?  This is where T1 lives or
  dies."* — **The index is wrong, and that is why T1 lives.**  The budget is not per
  complement row `D` but per KEY `(v, K)`: a mint at `(v, K)` installs `v <- (w, K)`
  IMMEDIATELY, so `Carried G' v K` holds in the successor, and `uncarried_lt` charges it one
  unit of `v`'s budget of `2^|L|` keys.  A second premise with the same complement row and a
  different key is a different unit; under a model two different keys at the same `v` have
  different complements anyway (`rho v \ K ≠ rho v \ K'`), so "the same `D` with a different
  key" can only occur at a different left-hand side — again a different unit.  The count is
  therefore bounded by `hmeas`, and the weighting by `|rho v|` is what stops the fresh names'
  own budgets from re-inflating it.
* *"Mints beget premises ... Does this chain?  ... every carrier once present persists (prove
  `concDef_persists`)."* — `concDef_persists` is proved, and it is used, but the chain is
  closed by the MEASURE, not by counting rows: `hmeas` strictly decreases at every mint and
  never increases at anything else, deletions included.
* *"Do NOT model `common`/`unify`."* — not modelled.  Nothing in `KeyedRow.lean` identifies
  two variables.

One more thing the notes did not anticipate, and it is the finding of the stage: the mechanism
they describe is not specific to `splitConcrete`.  Guarded `resolution` installs its resolvent
`v <- (z, C ∪ D)` as a MENTION of the fresh `z` in exactly the same way, so `makeConcrete z`
absorbs it in exactly the same way, and `resolution`'s guard has no concrete-row clause.  That
is `W4`, and it is why the split fix alone yields (T2) rather than (T1).

## 9. If (T1): the Scala change the rule would need — UNIMPLEMENTED

For the SPLIT (the Stage 4 clause proper).  In `Constraints.scala`, `def splitConcrete`
currently reads `rhss(RHSAbstr(abstr))`, then — under `GenRules.splitKey` —
`resolvent(concr)`, then mints.  The change adds a THIRD lookup between the second and the
mint, behind its own flag (say `GenRules.splitRow`, default OFF until measured):
`learnPartitions` already builds `resolvents : Map[Fields, TypeVar]` from the lone-variable
partitions of `v`; alongside it, build `concRows : Map[Fields, TypeVar]` from the BARE
concrete partitions of the whole system — `case Partition(u, RHS(abs, con), _) if abs.isEmpty
=> m + (con -> u)` folded over `incm` and `proc`, the same one-pass fold, and a
`concreteOf(v) : Option[Fields]` reading `v`'s own bare concrete partition out of the same
map's inverse.  Then the new branch is: `for { cv <- concreteOf(v); w <- concRows.get(cv --
concr) } yield Set(Partition(w, RHSAbstr(abstr), SplitRow))`, with a new
`case object SplitRow extends Inference` (a REUSE tag, alongside `SplitKeyed`), taken before
the `fresh(...)` mint.  It is entailed by the environment — `Rowpartition.KeyedRow.
concRow_reuse_sat` / `K2RowApp.models_iff` — so it is a pure name-for-mint substitution, and
the erase-insensitivity argument of `KeyedSplitScala.named_erase_iff` applies verbatim to it
(its witnesses are BARE partitions and the rule runs only when `concr` is nonempty, so the
dequeued premise can never be its own witness).  **Stage 4 says this is not enough on its
own**: the matching change to `resolution` — `findResolvent`'s miss falling through to the
same `concRows` lookup, guard `¬ Carried` in place of `¬ Resolved`, emitting the same two
conclusions `x <- (w, D \ C)`, `y <- (w, C \ D)` (`K2ResStep.row`, entailed by
`K2ResStep.row_models_iff`) — is what the termination theorem needs.  Neither is implemented;
nothing under `core/src` was touched.

## 10. What is still open

1. **The shipped compiler is not this relation.**  Everything here quantifies over all orders
   of an additive relation extended with a deleting step.  `incorporateAll` examines each
   partition once, at its dequeue, and unifies duplicate right-hand sides (`common`).  Neither
   property is stated by any relation in this development — `TICKET-sat-termination.md` §4
   items 1–3, and `KEYED-LOOP-STAGE3.md` §4 item 2, unchanged.
2. **No measurement.**  Stage 4 is Lean only: the corpus effect of the new branch (how often
   `concRows` would hit, and on which of the 157 kept-definition mints of §3e) is not measured,
   and neither flag exists.  That is the natural Stage 5.
3. **Unsatisfiable input is untouched.**  `hmeas` needs a model; `not_CRule` and
   `ResGuardDiverge.gSeed` are unaffected.
4. **`common`/`unify` is still unmodelled.**  It remains the only defence of the four that no
   relation states, and it is the one that actually stops `W3` and would stop `W4`.
5. **The bound is crude.**  `|allVars G₀| + hmeas L rho G₀` is `2^|L| · (2^|L|+1)^|L|`-shaped
   per variable, as Stage 1's is; nothing here tries to sharpen it.

## 11. Files touched

| file | what | size |
|---|---|---|
| `tracker/lean/Rowpartition/KeyedRow.lean` | NEW.  `ConcCarried` / `Carried`, `conc_lone_sat`, `concRow_reuse_sat`; `srsOf` / `concretizeSrs` and its soundness, `concDef_persists`; `carried_of_deleted_def`, `carried_of_absorbed_mention`, `carried_concretizeSrs`; `K2SplitStep` (four branches) with `K2MintApp.toSplitApp`, `K2DefaultStep`, `K2LoopStep`, `K2LoopRun`, `MintsBoundedOnSatKeyed2`; `K2ResStep`, `K2StarStep`, `K2StarLoopStep`, `MintsBoundedOnSatKeyed2Star`; `uncarried` / `hmeas`, `hmeas_mint_lt`, `hmeas_le_of_carried`, the invariant and `mintsBoundedOnSatKeyed2Star`, `mintsBoundedOnSat_splitFragment`; the witness `W4`, `W4Inv.round`, `W4_mints_unbounded`, `not_MintsBoundedOnSatKeyed2`, `keyed2_star_vs_shipped_res`, `W4_kloop_mints_unbounded`, `W4_not_TerminatesOnSatKeyedLoop`; the Stage 3 re-run `srsOf_W3`, `W3srs_eq`, `W3_carried`, `W3_not_mintable`, `W3_row_reuse` | 1481 lines, 94 theorems |
| `tracker/satterm/KEYED-ROW-STAGE4.md` | NEW.  This report | 507 lines |
| `tracker/lean/Rowpartition.lean` | the import and its module-map bullet | +11 |
| `tracker/lean/README.md` | headline figures (34 files, 1816 source theorems, audit 2216), build-status row, module-map row, the 2026-09-03 `KeyedRow` bullet, the headline `#print axioms` list | +49/−11 |
| `tracker/TICKET-sat-termination.md` | new §3f, §4 item 0 update, two §5 rows | +94/−5 |
| `tracker/ROW-CONSTRAINT-STATE.md` | one paragraph after the "Design rule" paragraph | +32 |

Nothing under `core/src` was touched, `sbt` and `bin/ermine` were not run, and nothing was
committed.
