# Stage 6 — `makeEmpty` as a DELETING step: does the mint bound survive it?

Date 2026-09-03, branch `scala3-migration`.  Stage 3 (the loop layer, outcome (W)) is
`tracker/satterm/KEYED-LOOP-STAGE3.md`; Stage 4 (the concrete-row reuse and the `Carried`
invariant) is `tracker/satterm/KEYED-ROW-STAGE4.md` / `Rowpartition/KeyedRow.lean`; Stage 5
(both branches implemented, measured, adopted) is `tracker/satterm/KEYED-ROW-STAGE5.md`.
This file is Stage 6.

LEAN ONLY.  No Scala edit, no `sbt`, no `bin/ermine` run, nothing committed.  Toolchain:

```
export PATH=$HOME/.elan/bin:$PATH                       # Lean 4.33.1, Mathlib v4.33.1
cd /home/dmitry/research/ermine/ermine-scala/tracker/lean
lake build Rowpartition        # Build completed successfully (819 jobs)      (818 before)
lake env lean Audit.lean       # 2329 theorems audited; non-standard axioms: 0 (2255 before)
```

Scratch (`#print axioms` for every headline, never inside a module):
`/home/dmitry/.claude/jobs/880c725d/tmp/PrintAxiomsStage6.lean`, output
`print-axioms-stage6.out` — all **46** are `[propext, Classical.choice, Quot.sound]`.

---

## 0. What was asked

Stage 5's COVERAGE sentence: `mintsBoundedOnSatKeyed2Star` bounds minting against the
CONCRETISATION deletion only.  The compiler has a second deleting step, `makeEmpty`, and it
deletes exactly the carrier of the EMPTY row; 74 of the corpus's 157 kept-definition mints
have an empty complement and are therefore OUTSIDE the bound, protected only by eager empty
propagation — the same empty-row loophole `DefaultSatDiverge.W2` ran on.  Stage 6 adds
`makeEmpty` to the Stage 4 relation as a faithful DELETING step and decides whether minting
stays bounded, with outcomes (T1) bounded with a bound, (T2) a partial bound with the missing
piece named exactly, (W) a satisfiable witness with unbounded vocabulary.

## 1. The answer: **(T2)** — and the missing piece is one constraint, named exactly

**Stage 4's invariant fails at `makeEmpty`, and it fails in exactly one way: the deleted
`v <- ()` is the carrier of the EMPTY row, and a key whose complement row is empty has no
other carrier.  Everything else survives.**

Three theorems say it:

* **The hole is real** (`carried_not_invariant`, `hmeas_increases`).  `Carried` is NOT an
  invariant of the faithful step, and Stage 4's potential `|allVars G| + hmeas L rho G`
  STRICTLY INCREASES across one step of a satisfiable three-constraint system.  So this is not
  a missing lemma in the Stage 4 proof: its measure is the wrong measure for this step.
* **(T2) the bound survives under an ORDER hypothesis on runs**
  (`mintsBoundedOnSat_emptyPersisting`).  If every `makeEmpty` step of a run leaves an
  empty-row carrier behind — `EmptyKnown (makeEmptyD v G)`, for which
  `emptyKnown_makeEmptyD` gives three necessary syntactic conditions and three matching
  sufficient ones, all decidable on the system at the step — then Stage 4's bound holds
  verbatim: `|allVars G₀| + hmeas (labelsOf G₀) rho G₀`, in every
  order, for the whole calculus `K3LoopStep = K2StarLoopStep ∪ makeEmptyD`.
* **(T1) for the one-line repair** (`mintsBoundedOnSatKeyed3E`).  RETAIN `v <- ()` — i.e. let
  the reverse lookup consult the substitution environment, where the compiler already keeps
  the fact — and the bound holds UNCONDITIONALLY, with no hypothesis on the run.  That is a
  Scala change of the same size as Stage 5's, and it is exactly what the 74-of-157 population
  needs.

**What is NOT proved: `MintsBoundedOnSatKeyed3` itself** — the statement over the faithful
step with no hypothesis — is neither proved nor refuted.  §7 says what was tried and where
each attempt at a witness dies; the honest summary is that the propagation appears to plug
every loop that was constructed, but no invariant covers the case where it does not fire.

## 2. The definition, verbatim, and the decision about `v <- ()`

`Rowpartition/KeyedEmpty.lean` §1.  The Scala (`Constraints.scala`, `makeEmpty`, ≈1407–1445),
read as a system-to-system map:

```lean
def Involves (v : Var) (c : Constraint) : Prop := c.lhs = v ∨ v ∈ vset c

def keepPart (v : Var) (G : System) : System := G.filter (fun c => c.lhs ≠ v ∧ v ∉ vset c)

def erasePart (v : Var) (G : System) : System :=
  (G.filter (fun c => c.lhs ≠ v ∧ v ∈ vset c)).image
    (fun c => mk c.lhs ((vset c).erase v) c.conc)

def propPart (v : Var) (G : System) : System :=
  (G.filter (fun c => c.lhs = v ∧ c.conc = ∅)).biUnion
    (fun c => (vset c).image (fun x => mk x ∅ (∅ : Row)))

def makeEmptyD (v : Var) (G : System) : System :=
  keepPart v G ∪ erasePart v G ∪ propPart v G
```

with the membership lemma that everything below is proved through:

```lean
theorem mem_makeEmptyD {v : Var} {G : System} {c : Constraint} :
    c ∈ makeEmptyD v G ↔
      (c ∈ G ∧ c.lhs ≠ v ∧ v ∉ vset c) ∨
      (∃ d ∈ G, d.lhs ≠ v ∧ v ∈ vset d ∧ c = mk d.lhs ((vset d).erase v) d.conc) ∨
      (∃ d ∈ G, d.lhs = v ∧ d.conc = ∅ ∧ ∃ x ∈ vset d, c = mk x ∅ (∅ : Row))
```

Line by line against the Scala.  `val (pps, procd) = proc partition ruleInvolves(v)` and the
same for `incm`: partitions involving `v` leave BOTH queues, so `keepPart` is what remains
untouched.  The fold's `else` arm `s + Partition(u, rhs - v, inf)`: every MENTION is
re-emitted with `v` erased — `erasePart`.  The fold's `if (u == v) aux(s, rhs)` arm:
`RHSEmpty()` returns `s` (a definition `v <- ()` propagates nothing), `RHSAbstr(abstr)` adds
`Partition(x, RHSEmpty())` for every `x ∈ abstr` (a definition with ONLY abstract parts forces
its whole group empty) — together these are exactly `d.lhs = v ∧ d.conc = ∅`, i.e. `propPart`;
and the third arm `tml.die` is a definition of `v` with a nonempty concrete part, which
`makeEmptyD` simply DROPS.  Dropping is sound, and `makeEmpty_conc_unsat` says nothing is
hidden by it: such a system has no model at all.

**The decision: `v <- ()` is NOT kept.**  `makeEmptyD` does not contain `mk v ∅ ∅`.  Reasons,
in order:

1. **It is what the Scala does.**  `instantiateType(v, ConcreteRho(Loc.builtin, Set()))`
   writes the fact into the `SubstEnv`, and neither `nps` nor `procd` receives it back.
   `KEYED-ROW-STAGE5.md` §A.3 traced this before Stage 5's lookup was written and drew the
   consequence: the Scala `concRows` lookup is a LOWER bound on the Lean's `mk u ∅ R ∈ G`, and
   an emptied variable is precisely what it misses.
2. **Keeping it would assume away the whole question.**  §4 proves that retaining `v <- ()`
   makes `Carried` an unconditional invariant and restores the Stage 4 bound with no
   hypothesis (`carried_makeEmptyE`, `mintsBoundedOnSatKeyed3E`).  If the faithful step kept
   it, Stage 6 would be a restatement of Stage 4 and would say nothing about the 74 mints.
3. **Nothing below depends on retaining it.**  Every theorem about `makeEmptyD` is stated for
   `makeEmptyD`.  The retaining variant is a SEPARATE definition,
   `makeEmptyE v G := insert (mk v ∅ (∅ : Row)) (makeEmptyD v G)`, used only in §4's and §6's
   `E`-tagged results, and it is presented as a candidate REPAIR, not as the model of the
   compiler.

## 3. Soundness, the `die` arm, and the bookkeeping

```lean
theorem sat_erase_of_empty {rho} {c} {v} (hc : Sat rho c) (hv : rho v = ∅) :
    Sat rho (mk c.lhs ((vset c).erase v) c.conc)

theorem sat_prop_of_empty {rho} {c} {v x} (hc : Sat rho c) (hlhs : c.lhs = v)
    (hconc : c.conc = ∅) (hv : rho v = ∅) (hx : x ∈ vset c) : Sat rho (mk x ∅ (∅ : Row))

theorem makeEmptyD_sound {v} {G} (he : mk v ∅ (∅ : Row) ∈ G) {rho} (hm : SModels rho G) :
    SModels rho (makeEmptyD v G)

theorem makeEmptyE_sound {v} {G} (he : mk v ∅ (∅ : Row) ∈ G) {rho} (hm : SModels rho G) :
    SModels rho (makeEmptyE v G)
```

ONE DIRECTION only, and deliberately: the step deletes, so the converse fails for the same
reason `Saturate.SatStep.weaken`'s does (`satStep_not_reflecting`).  The step's own side
condition supplies `rho v = ∅` through `NameLoss.denotes_of_conc`.

The `die` arm, as the brief asks, out of `Saturate.empty_conc_unsat`:

```lean
theorem makeEmpty_conc_unsat {G} {v} {c} (he : mk v ∅ (∅ : Row) ∈ G) (hc : c ∈ G)
    (hlhs : c.lhs = v) (hne : c.conc ≠ ∅) : ¬ ∃ rho, SModels rho G
```

(the one bridging step is `mk v ∅ ∅ = ⟨v, [], ∅⟩`, i.e. `slist ∅ = []`).

Bookkeeping:

```lean
theorem allVars_makeEmptyD_subset (v) (G) : allVars (makeEmptyD v G) ⊆ allVars G
theorem allVars_makeEmptyE_subset (he : mk v ∅ (∅:Row) ∈ G) :
    allVars (makeEmptyE v G) ⊆ allVars G
theorem makeEmptyD_concSub (hcs : ConcSub L G) : ConcSub L (makeEmptyD v G)
theorem makeEmptyE_concSub (hcs : ConcSub L G) : ConcSub L (makeEmptyE v G)

/-- the emptied variable leaves the vocabulary, unless it mentions ITSELF -/
theorem empty_of_mem_allVars (hv : v ∈ allVars (makeEmptyD v G)) :
    mk v ∅ (∅ : Row) ∈ makeEmptyD v G
```

`empty_of_mem_allVars` is the one edge case worth naming: the Scala's `aux` maps over ALL of
`abstr`, so a SELF-mention `v <- (v, …)` re-emits `v <- ()` into the queue.  That is the only
way `v` survives the step, and when it does, the fact the environment would have held is back
in the system — which §4 turns into a free case rather than a nuisance.

## 4. The invariant, and the hole

Stage 4's whole content was `carried_concretizeSrs`: `Carried` survives the concretisation.
Under `makeEmptyD v` there are exactly two ways `Carried G w K` can be lost at a `w ≠ v`, and
both ask for the SAME missing constraint:

* a lone witness `w <- (v, K)` — the abstract part is the emptied variable — is re-emitted as
  the bare CONCRETE definition `w <- ((|K|))`, so the key `(w, K)` is now carried iff something
  denotes `K \ K = ∅`;
* a concrete-row carrier at `z = v` (`v <- ((|C \ K|))`, so `C \ K = ∅` under a model) is
  deleted, and its replacement must again denote `∅`.

Hence:

```lean
def EmptyKnown (G : System) : Prop := ∃ e : Var, mk e ∅ (∅ : Row) ∈ G

/-- stated for any SUPERSET of the image, so `makeEmptyE` can use its own retained fact -/
theorem carried_of_makeEmptyD_subset {G G'} {v w e} {K} {rho}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) (hsub : makeEmptyD v G ⊆ G')
    (hE : mk e ∅ (∅ : Row) ∈ G') (hwv : w ≠ v) (h : Carried G w K) : Carried G' w K

theorem carried_self_of_mem_allVars (hv : v ∈ allVars (makeEmptyD v G)) :
    Carried (makeEmptyD v G) v K

theorem carried_makeEmptyD {G} {v w} {K} {rho}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) (hE : EmptyKnown (makeEmptyD v G))
    (hw : w ∈ allVars (makeEmptyD v G)) (h : Carried G w K) : Carried (makeEmptyD v G) w K

/-- the REPAIR: retaining `v <- ()` supplies the missing constraint everywhere -/
theorem carried_makeEmptyE {G} {v w} {K} {rho}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) (h : Carried G w K) :
    Carried (makeEmptyE v G) w K
```

Note the shape of `carried_makeEmptyD`: the conclusion is asked only at variables the IMAGE
still has (`hw`).  That is what lets the emptied variable's own keys go: `hmeas` sums over
`allVars`, and `v` is normally not there any more.  The restricted form of Stage 4's monotone
lemma is proved here:

```lean
theorem hmeas_le_of_carried_on {L} {G G'} (rho) (hAV : allVars G' ⊆ allVars G)
    (hcar : ∀ w ∈ allVars G', ∀ K, Carried G w K → Carried G' w K) :
    hmeas L rho G' ≤ hmeas L rho G
```

### 4.1 The hole, as a theorem — and `hmeas` really does go UP

Three constraints, no minting, a model:

```lean
def EE6 : Row := {l1, l2}
def G6 : System := {mk v0 ∅ (∅ : Row), mk v1 ∅ EE6, mk v1 {v0} EE6}
def rho6 : Assign := fun v => if v = v1 then EE6 else ∅       -- v0 ↦ ∅, v1 ↦ {l1,l2}

theorem G6_models : SModels rho6 G6
theorem makeEmptyD_G6 : makeEmptyD v0 G6 = {mk v1 ∅ EE6}
theorem carried_G6 : Carried G6 v1 EE6                        -- the lone witness v1 <- (v0, EE6)
theorem not_carried_G6 : ¬ Carried (makeEmptyD v0 G6) v1 EE6

theorem carried_not_invariant :
    ∃ (G : System) (v w : Var) (K : Row) (rho : Assign),
      SModels rho G ∧ mk v ∅ (∅ : Row) ∈ G ∧
        Carried G w K ∧ ¬ Carried (makeEmptyD v G) w K
```

Both surviving constraints collapse onto the same bare `v1 <- ((|l1,l2|))`, and `v0`'s only
definition is `v0 <- ()` itself — the `RHSEmpty` arm of `aux`, which derives nothing.  So no
propagation fires, and after the step the key `(v1, EE6)` asks for a carrier of
`EE6 \ EE6 = ∅` that no longer exists.

And the measure, with `L6 = {l1,l2}` (so the budget base is `2² + 1 = 5`):

```lean
theorem uncarried_G6_v0 : uncarried L6 G6 v0 = 0
theorem uncarried_G6_v1_lt : uncarried L6 G6 v1 < uncarried L6 (makeEmptyD v0 G6) v1
theorem hmeas_increases :
    (allVars G6).card + hmeas L6 rho6 G6
      < (allVars (makeEmptyD v0 G6)).card + hmeas L6 rho6 (makeEmptyD v0 G6)
```

The argument for `uncarried_G6_v1_lt` needs no computation of either number: the image is a
SUBSET of `G6`, so by `Carried.mono` it carries no key `G6` did not, and it fails to carry
`(v1, EE6)`, which `G6` did — a strict subset of open keys, so a strictly larger count.  The
emptied variable contributes nothing on the other side (`uncarried_G6_v0 = 0`: `v0 <- ()`
carries every key at `v0`), so the whole loss is a real loss.  Concretely `2 + 2·25 = 52`
before, `1 + 3·25 = 76` after.

**Reading.**  Stage 4's proof does not fail for want of a lemma.  `|allVars G| + hmeas L rho G`
is not a valid potential for the faithful `makeEmpty`, so (T1) cannot be obtained by extending
`K2StarLoopStep.measure_step` with a fourth case.

## 5. Where the missing carrier comes from — the order hypothesis, made checkable

`makeEmptyD v G` names the empty row for one of three reasons.  The three sufficient
conditions are proved separately from the necessary one (they differ only in that the
necessary form allows a `d.vars` LIST with repeats, which `mk` cannot express); all six are
decidable on the system at the step:

```lean
theorem emptyKnown_of_other (hne : e ≠ v) (h : mk e ∅ (∅:Row) ∈ G) :
    EmptyKnown (makeEmptyD v G)                       -- another variable already known empty
theorem emptyKnown_of_bare_mention (hne : e ≠ v) (h : mk e {v} (∅:Row) ∈ G) :
    EmptyKnown (makeEmptyD v G)                       -- a BARE lone mention `e <- (v)`
theorem emptyKnown_of_bare_abstr (hd : mk v S (∅:Row) ∈ G) (hx : x ∈ S) :
    EmptyKnown (makeEmptyD v G)                       -- the PROPAGATION, `aux`'s RHSAbstr arm

theorem emptyKnown_makeEmptyD (h : EmptyKnown (makeEmptyD v G)) :
    (∃ e, e ≠ v ∧ mk e ∅ (∅ : Row) ∈ G) ∨
    (∃ d ∈ G, d.lhs ≠ v ∧ v ∈ vset d ∧ (vset d).erase v = ∅ ∧ d.conc = ∅) ∨
    (∃ d ∈ G, d.lhs = v ∧ d.conc = ∅ ∧ (vset d).Nonempty)
```

The third is the one the brief's sketch points at and the one the split rule cares about: the
name a split mint emits is `mk u (vset c) ∅`, a bare abstract definition with `2 ≤ |vset c|`,
so `makeEmptyD u` ALWAYS propagates, and always supplies a carrier for the very key the mint
had just closed.  That is why the obvious divergence loops die (§7).

## 6. The relations and the two bounds

```lean
inductive K3LoopStep : System → System → Prop
  | star  {G G'} : K2StarLoopStep G G' → K3LoopStep G G'
  | empty {G v}  : mk v ∅ (∅:Row) ∈ G → makeEmptyD v G ≠ G → K3LoopStep G (makeEmptyD v G)

inductive K3LoopRun : ℕ → System → System → Prop
  | refl (G) : K3LoopRun 0 G G
  | tail : K3LoopRun n G₀ G → K3LoopStep G G' → G ≠ G' → K3LoopRun (n + 1) G₀ G'

def MintsBoundedOnSatKeyed3 : Prop :=            -- the Stage 4 statement for K3 runs
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K3LoopRun n G₀ G → (allVars G).card ≤ N
```

**The ORDER hypothesis on runs**, precisely (this is (T2)'s "extra hypothesis"):

```lean
inductive K3LoopRunEP : ℕ → System → System → Prop
  | refl (G) : K3LoopRunEP 0 G G
  | star  : K3LoopRunEP n G₀ G → K2StarLoopStep G G' → G ≠ G' → K3LoopRunEP (n + 1) G₀ G'
  | empty : K3LoopRunEP n G₀ G → mk v ∅ (∅:Row) ∈ G → EmptyKnown (makeEmptyD v G) →
            makeEmptyD v G ≠ G → K3LoopRunEP (n + 1) G₀ (makeEmptyD v G)

theorem K3LoopRunEP.toK3 (h : K3LoopRunEP n G₀ G) : K3LoopRun n G₀ G
```

It is a hypothesis on the STEPS of the run, not on their order relative to one another: every
`makeEmpty` taken must leave an empty-row carrier in the system.  §5 says when that holds.
Read as a statement about the compiler it is exactly "eager empty propagation, and the derived
`x <- ()` facts are still in the queues when the split's reverse lookup runs" — the defence
`ROW-CONSTRAINT-STATE.md` names for the 74 mints, now formalised.

The repaired relation, and the two headlines:

```lean
inductive K3ELoopStep : System → System → Prop
  | star  {G G'} : K2StarLoopStep G G' → K3ELoopStep G G'
  | empty {G v}  : mk v ∅ (∅:Row) ∈ G → makeEmptyE v G ≠ G → K3ELoopStep G (makeEmptyE v G)

def MintsBoundedOnSatKeyed3E : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K3ELoopRun n G₀ G → (allVars G).card ≤ N

/-- (T2) -/
theorem mintsBoundedOnSat_emptyPersisting (G₀ : System) (rho : Assign) (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K3LoopRunEP n G₀ G → (allVars G).card ≤ N :=
  ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀, …⟩

/-- (T1) for the repaired step -/
theorem mintsBoundedOnSatKeyed3E : MintsBoundedOnSatKeyed3E :=
  fun G₀ rho hm => ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀, …⟩
```

Both bounds are Stage 4's, verbatim and unchanged: `|allVars G₀| + hmeas (labelsOf G₀) rho G₀`.
The supporting run lemmas are `K3LoopRunEP.concSub`, `K3ELoopRun.concSub`,
`K3LoopRunEP.invariant`, `K3ELoopRun.invariant`, and the one-step lemmas
`makeEmptyD_measure_step` / `makeEmptyE_measure_step`.

## 7. The mechanism notes, checked (not trusted)

**Note 1 — "the Scala erases `v` from mentions but does NOT re-express `u <- (v, K)` as
`u <- ((|K|))`-plus-anything; after erasure it becomes `u <- (K)` with NO abstract part.  Is
that a CARRIER of `K` for other keys, and does it make `u` concrete so the row branch fires?"**
CONFIRMED, both halves:

```lean
theorem emptied_mention_conc (hu : mk u {v} K ∈ G) (huv : u ≠ v) : mk u ∅ K ∈ makeEmptyD v G
theorem carrier_of_emptied_mention (hw : mk w ∅ C ∈ G) (hwv : w ≠ v) (hu : mk u {v} K ∈ G)
    (huv : u ≠ v) (hCJ : C \ J = K) : Carried (makeEmptyD v G) w J
```

The residue IS a bare concrete definition of `u`, so `K2RowApp.lhsConc` — the premise the
concrete-row split branch needs at `u` — becomes available, and it IS a carrier for any key
whose complement row is exactly `K`.  The step is therefore not uniformly destructive.

**Note 2 — "the witness `u <- (z, K)` for key `(u, K)` where `z` is emptied becomes
`u <- ((|K|))`, which is `ConcCarried` for nothing (`K \ K = ∅` needs a carrier of `∅`, which
is exactly what was deleted).  That is the hole."**  CONFIRMED, and it is the ONLY hole:

```lean
theorem carried_emptied_key_of_emptyKnown (hu : mk u {v} K ∈ G) (huv : u ≠ v)
    (hE : mk e ∅ (∅:Row) ∈ makeEmptyD v G) : Carried (makeEmptyD v G) u K
```

— i.e. one carrier of `∅`, anywhere in the image, closes the key; and `carried_not_invariant`
shows nothing supplies it in general.

**Note 3 — "whether a premise `u <- (S, K)` with `2 ≤ |S|` can still exist at that point under
a model (`rho u = K` forces `rho S = ∅`, so every `x ∈ S` is forced empty — but is `x <- ()`
DERIVED before the premise is dequeued?  In the any-order relation, no) is exactly the
question."**  CONFIRMED on both counts, and this is §8's population:

```lean
theorem group_forced_empty (hm : SModels rho G) (hconc : mk u ∅ K ∈ G) (hc : c ∈ G)
    (hlhs : c.lhs = u) (hK : c.conc = K) (hx : x ∈ vset c) : rho x = ∅
```

is the semantic half — the group IS forced empty — and `G7_mints` below is the syntactic half:
a satisfiable system in which the premise survives with `2 ≤ |S|`, nothing denotes `∅`, and
every premise of the Stage 4 MINT holds.  The brief's T1 sketch ("…so it is no longer a
`2 ≤ |S|` premise after erasure") is WRONG as stated: the erasure removes `v` from right-hand
sides, and `v` is not in the premise's group at all, so the premise keeps its two variables.
What actually blocks the mint, when anything does, is not the premise's shape but the
PROPAGATION's `x <- ()` acting as the carrier of `∅` (§5, third source) — a different
mechanism reaching the same conclusion.  Stage 3's sketch was wrong in one step; so was this
one.

**Note 4 — "if the measure `hmeas` can go UP … find what bounds the number of `makeEmptyD`
steps (a variable is emptied at most once under a model … and emptied variables are never
re-mentioned — is that enough to amortise?)".**  It is NOT enough, and the reason is stated
plainly rather than papered over:

* `hmeas` can go up: `hmeas_increases`.
* An emptied variable does leave the vocabulary (`empty_of_mem_allVars`: the only way `v`
  survives is as `v <- ()`, from a self-mention) — so a `makeEmptyD` step consumes one
  variable.
* But "emptied at most once" does not bound the number of steps, because the mint's freshness
  condition is `z ∉ allVars G` at the CURRENT system: a name removed by an earlier
  `makeEmptyD` is available again, and more importantly each mint adds a variable that can
  itself be emptied later.  So the count of `makeEmptyD` steps is bounded by
  (initial variables + mints), and the mints are what was to be bounded.  The amortisation is
  circular as it stands, and no non-circular potential was found.

## 8. The 74-of-157 population, formalised

`KEYED-ROW-STAGE5.md` §B7-2 counted it on the corpus: at 74 of the 157 kept-definition mints
the premise's concrete part equals the left-hand side's row (`K = C`), so the complement is the
EMPTY row and "the carrier would have to be a variable already known to denote `∅` — and that
is precisely the variable `makeEmpty` has DELETED from both queues".  Two constraints suffice
to reproduce that as a theorem:

```lean
def K7 : Row := {k7}
def G7 : System := {mk p7 ∅ K7, mk p7 {x7, y7} K7}     -- p <- ((|k|)),  p <- (x, y, (|k|))
def rho7 : Assign := fun v => if v = p7 then K7 else ∅

theorem G7_models : SModels rho7 G7
theorem G7_not_emptyKnown : ¬ EmptyKnown G7
theorem G7_group_empty (w) (hw : w ∈ ({x7, y7} : Finset Var)) : rho7 w = ∅
theorem G7_not_named : ¬ Named G7 (vset (mk p7 {x7, y7} K7))
theorem G7_not_carried : ¬ Carried G7 p7 K7
theorem G7_mints : KeyedRow.K2MintApp G7 (mk p7 {x7, y7} K7) u7
theorem G7_blocked (e : Var) : Carried (insert (mk e ∅ (∅ : Row)) G7) p7 K7
```

`G7_mints` is the statement in full: on a SATISFIABLE system whose split group is FORCED
EMPTY, the syntactic lookup misses, the keyed lookup misses, and the concrete-row lookup
misses — because the only carrier it could use is a variable denoting `∅`, which the queues no
longer hold.  `G7_blocked` is the counterpart: ONE bare `e <- ()`, anywhere, turns that mint
into a `K2RowApp` reuse.  Together they say what the repair buys, on the exact shape the
corpus produces 74 times.

## 9. What the repair would be, in Scala (UNIMPLEMENTED, unmeasured)

Not written and not measured — this stage is Lean only — but the Lean says precisely what it
is.  `mintsBoundedOnSatKeyed3E` needs the reverse lookup to see emptied variables.  In
`learnPartitions`, the `concRows` fold currently collects bare concrete partitions from
`proc ++ incm`; `makeEmpty` has removed the emptied variable from both.  The shipped compiler
still HAS the fact — `instantiateType(v, ConcreteRho(Loc.builtin, Set()))` put it in the
`SubstEnv` — so the change is to let the empty row be found there (equivalently: have
`makeEmpty` return `Partition(v, RHSEmpty())` to `incm`, or seed `concRows` with the
environment's empty instantiations).  Cost and risk are unassessed here; note only that
`G7_blocked` shows the effect is to REPLACE 74 mints by reuses, which is the same class of
change as Stage 5's `SplitRow`, and that Stage 5's population evidence says such reuses change
the trajectory (§B7-4, §B7-6: the branches are not additive), so it would need the same gate
set.

## 10. Where a witness (W) was hunted, and why none was produced

Recorded so the next stage does not repeat it.  A divergence needs a round that mints, then
re-opens the key by a DELETING step without leaving an empty-row carrier, then restores the
shape.

* **Split-driven.**  The mint emits `u <- (S)` with `2 ≤ |S|`, which makes `Named G S` true, so
  the same premise cannot re-mint until that constraint dies.  Only `makeEmptyD` deletes it
  (the concretisation KEEPS definitions with two or more abstract parts), and `makeEmptyD u`
  hits `aux`'s `RHSAbstr` arm on exactly that constraint, propagating `x <- ()` for every
  `x ∈ S` — which is a carrier of `∅` and closes the key again (§5, third source).  Every
  variant tried (larger groups, emptying group members first, concretising the premise's
  left-hand side to manufacture `u <- ()` through `srsOf`) ended at the same propagation.
* **Resolution-driven**, the `W4` engine.  This one gets further: `makeEmptyD z` on the
  resolvent's fresh name `z` deletes `v <- (z, C ∪ D)` as a MENTION (re-emitting
  `v <- ((|C ∪ D|))`), propagates NOTHING (all three resolution conclusions have nonempty
  concrete parts, so `z` has no bare abstract definition), and leaves the two `ResPair`
  premises untouched — the key is genuinely re-opened and the engine is intact.  What was not
  produced is `z <- ()` itself, round after round: `rho z = rho v \ (C ∪ D)`, so it needs
  `rho v = C ∪ D`, and the only routes to the constraint `z <- ()` are `srsOf` at one of
  `v`, `x`, `y` — each of which requires concretising a variable whose absorption destroys one
  of the two premises — or a propagation, which needs a bare constraint mentioning `z`, and
  resolution emits none.
* Neither line is closed.  A witness may exist through a rule combination not tried (the
  non-generative fold, `common`, or a split whose group contains a resolution's fresh name);
  the negative result here is only that the two obvious engines do not run.

## 11. Files touched

| file | lines | note |
|---|---|---|
| `tracker/lean/Rowpartition/KeyedEmpty.lean` | 916 (NEW) | 65 theorems/instances, 30 definitions |
| `tracker/lean/Rowpartition.lean` | +1 | `import Rowpartition.KeyedEmpty`, the import line ONLY |
| `tracker/satterm/KEYED-EMPTY-STAGE6.md` | this file (NEW) | |

Nothing else was written.  No Scala file, no ticket, no state file, no README — those are
mid-commit in the main session and are meant to be integrated FROM this report.  A one-line
header entry for `Rowpartition.lean`'s module list, if the main session wants one:

```
* `Rowpartition.KeyedEmpty` -- ...and Stage 6: the SECOND deleting step.  `makeEmpty` added
                               faithfully (`makeEmptyD`; `v <- ()` goes to the SubstEnv, NOT
                               back into the system).  `Carried` is NOT an invariant of it
                               (`carried_not_invariant`) and Stage 4's potential strictly
                               INCREASES (`hmeas_increases`); the missing piece is a carrier
                               of the EMPTY row.  (T2): the Stage 4 bound survives verbatim
                               under the order hypothesis that each `makeEmpty` leaves one
                               behind (`mintsBoundedOnSat_emptyPersisting`), and
                               unconditionally if `v <- ()` is retained
                               (`mintsBoundedOnSatKeyed3E`).  `G7_mints` is the 74-of-157
                               population as a theorem
```

## 12. What is open, stated plainly

1. **`MintsBoundedOnSatKeyed3` is not decided.**  Neither proved nor refuted.  §10 says where
   the two witness constructions die and §7's Note 4 says why the amortisation is circular.
2. **The order hypothesis is not shown to hold on real runs.**  `emptyKnown_makeEmptyD` makes
   it checkable, and §5's third source makes it plausible for split-minted names, but nothing
   here measures it against the compiler, and no relation models `incorporateAll`'s single
   pass, `common`, or `unify` — `unify` is the OTHER deletion `KEYED-ROW-STAGE5.md` §A.3
   flags, and it is untouched by this stage.
3. **The repair is unimplemented and unmeasured** (§9).
4. Unsatisfiable input is untouched, as in Stages 4 and 5: every bound needs a model
   (`hmeas`), and `DefaultDiverge.not_CRule` still lives.
