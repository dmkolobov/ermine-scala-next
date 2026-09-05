# L5 — `LoopStrict` and the loop-level mint bound

2026-09-04.  Brief: `tracker/loopmodel/briefs/brief-L5.md`.  Lean only; no Scala edit, no sbt,
no commit.  Every Lean statement quoted below is VERBATIM from the module named beside it.

**Outcome, in one line.**  C1 **PARTIAL** — `LoopStrict` exists, its three eliminations ARE the
library operators (`makeEmptyE`, `concretizeSrs`, `substOut`), the vocabulary along a run is
bounded by the initial vocabulary plus the number of minting steps
(`LoopStrictSteps.allVars_card_le`, `no_growth_without_mint`), and `step` is proved to refine
it on the three environment branches with **no dependency on `LoopRel.weaken`, transitive or
otherwise**; five of the six R2.5 rows are discharged (four as licensed deletions, one by
proving it is not a deletion at all), leaving row 6.  C2 **PARTIAL** — the pieces that do not
need the `learn` vocabulary.  C3 **(T2)** — no bound and no divergence witness, with the
obstacle localised further than `L3-REVIEW.md` §6d had it, and corrected in round 2.  C4
answered.  **Round 2 (after `L5-REVIEW.md`) is §R2 at the end; both major findings are fixed
and machine-checked with the reviewer's own instruments.**

**And one thing that is not part of any checkpoint and matters more than all of them: a
three-constraint SATISFIABLE row system on which the SHIPPED compiler throws an internal
panic, at 11 of 100 id bases.  §0.**

---

## 0. REPORTED AT ONCE: a compiler panic on satisfiable input, found by the C3 witness hunt

The C3 hunt (§C3.5) is 1,500 empty-biased systems that are satisfiable BY CONSTRUCTION.  It
found no divergence — and 29 runs in which the loop DIES with

    panic: reinstantiated type v to ConcreteRho(-,Set()) but it was already bound

which `L3-THEOREMS.md` §2f classifies as one of the three deaths that are NOT refutations.
Minimised (`tracker/loopmodel`-external scratch `.../tmp/L5/min/minimize.py`) and **replayed
through the real `Subst.solve`** with `tracker/repro/satterm/run.sh`:

```json
{"name":"PANIC3","rho":{},"cons":[[7,[4,6],[]],[6,[6,7],[]],[9,[5],[100]]]}
```

i.e. `v7 <- (v4, v6)`, `v6 <- (v6, v7)`, `v9 <- (v5, (|l100|))`, which is satisfiable
(`v4 = v5 = v6 = v7 = ()`, `v9 = (|l100|)`).

    tracker/repro/satterm/run.sh sweep json:.../panic3.json 0 99 10 200
    SUMMARY ... bases=0..99 n=100 SOLVED=89 REJECTED=11 HANG=0 OOM=0
      scalaparsers.Death: panic: reinstantiated type v6^34 to ConcreteRho(-,Set())
                          but it was already bound to ConcreteRho(-,Set())

* **11 of 100 id bases throw**; the other 89 solve.  So a valid program is accepted or
  rejected according to how many type variables the compiler happened to allocate before the
  solve — the same order-dependence class as the NameLoss ticket.
* The message says the variable was already bound **to the same value**
  (`ConcreteRho(-,Set())` on both sides): the panic refuses a NO-OP re-binding.
* Drop the third constraint and the panic disappears over 0..99 (`SOLVED=100`).
* **ROOT CAUSE (corrected in round 2 after `L5-REVIEW.md` F3, which traced it).**  Round 1 said
  "the queue's priority order puts two `makeEmpty` steps on the same variable".  That is only
  half of it: the priority order decides WHETHER the second step happens, but what
  MANUFACTURES it is `makeEmpty`'s `aux` (`Constraints.scala:1564`), which maps over ALL of
  `abstr` -- including the variable being emptied -- where `selfSubstitution` twelve lines away
  (`:1157`) uses `(abstr - v)`.  So a self-referential partition `v <- (v, ...)` in either
  queue makes `makeEmpty v` emit `v <- ()` for `v` itself, re-enqueue it, and a later dequeue
  call `makeEmpty v` a second time.  The asymmetry is now a pair of Lean theorems,
  `selfSubstitution_excludes_self` and `makeEmpty_aux_emits_self` (§R2.4).  It is not confined
  to self-referential INPUT: the reviewer traced `e00282`, where the loop DERIVES the
  self-reference.
* The Lean model reproduces it at exactly the same bases (base 6 and base 13 within 0..19),
  which is one more L1/L2 cross-check at an input no corpus contains.

**The fix, corrected in round 2 (`L5-REVIEW.md` F4).**  Round 1 recommended uncommenting
`Subst.scala:183`.  That stops the panic (both bindings are `ConcreteRho(-,Set())`, so
`e == t`), but it treats a symptom and it removes the only enforcement of the queue-hygiene
invariant -- and with it the justification for the `empty`/`common`/`unify` rows of §C3.4's
branch table (`makeEmpty_env_len` becomes false if an `empty` step may add no binding).  **The
right fix is `abstr.map` -> `(abstr - v).map` in `makeEmpty`'s `aux`**, matching
`selfSubstitution`: it is sound (`v <- ()` is recorded in the same call), it removes the
re-entry at its source, and it leaves `instantiateType`'s `die` in place as a genuine invariant
check, so `EnvNodup` / `makeEmpty_env_len` / §C3.4 survive unchanged.  If it is adopted, the
Lean model's `makeEmpty` (`Loop/Step.lean:126`) must change in lock-step or L2/L4's trace
equality breaks.  For the record, the tolerant case IS in the source, commented out --
`Subst.instantiateType` (`Subst.scala:182-184`) reads

```scala
def instantiateType(v: TypeVar, e: Type)(implicit hm: SubstEnv): Unit = hm.types.get(v) match {
  // case Some(t) if e == t => warn(e.report("warning: reinstantiated type " + v + " to the same type " + e))
  case Some(t)           => e.die("panic: reinstantiated type " + v + " to " + e + " but it was already bound to " + t)
  case None              => …
```

— the commented-out first case is exactly the case that fires here (`e == t`, both
`ConcreteRho(-,Set())`), and the `die` below it is what a satisfiable three-constraint program
gets instead.  I have made no Scala change, as instructed; whoever takes this should also
decide whether the ALIAS form of the same panic (`instantiate`'s
`"reinstantiated type v to u"`) needs the same treatment.  Scratch, including the minimiser and
the seed: `/home/dmitry/.claude/jobs/880c725d/tmp/L5/min/`.

---

## Build and audit (every figure re-run by me)

| | before me | after me |
|---|---|---|
| `lake build Rowpartition` | 838 jobs | **841 jobs**, success (unchanged by round 2) |
| `lake env lean Audit.lean` | `2935; 0` | round 1 `3003; 0`; **round 2 `Rowpartition theorems audited: 3058; declarations using a non-standard axiom: 0`** |
| `sorry` / `native_decide` / `axiom` / `partial` in my modules | — | **0** |

| new module | lines (round 1) | lines (round 2) |
|---|---|---|
| `Rowpartition/Loop/Strict.lean` | 225 | **612** |
| `Rowpartition/Loop/StrictStep.lean` | 1,268 | **1,962** |
| `Rowpartition/Loop/StrictBound.lean` | 230 | **339** |
| total | 1,723 | **2,913** |

All three are in the root import list; nothing else in the tree was touched except
`Rowpartition.lean` (three import lines of mine; the diff against HEAD is +8 because L3's five
were never staged — `L5-REVIEW.md` F8), `tracker/lean/README.md` (additive, **+146/-0**), the
plan's L5 row and this file.  `#print axioms` for the **57 headline theorems**:
`/home/dmitry/.claude/jobs/880c725d/tmp/L5/Axioms.lean` — 56 report
`[propext, Classical.choice, Quot.sound]` and 1 reports `[propext, Quot.sound]`; **no
non-standard axiom**.

---

## C1 — `LoopStrict`

### C1.1 The relation, VERBATIM (`Loop/Strict.lean`)

(the constructor lines are verbatim; only the per-constructor doc comments are elided)

```lean
/-- **`G'` loses nothing of `G`**: every constraint of `G` is a consequence of `G'`.  This is
the licence every deleting constructor of `LoopStrict` carries, and `LoopRel.weaken` does
not. -/
def NoLoss (G G' : System) : Prop := ∀ c ∈ G, SEntails G' c

inductive LoopStrict : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → LoopStrict G G'
  | split {G G' : System} : K2SplitStep G G' → LoopStrict G G'
  | res {G G' : System} : ResStep G G' → LoopStrict G G'
  | splitFree {G G' : System} : SplitStep G G' → LoopStrict G G'
  | kres {G G' : System} : K2ResStep G G' → LoopStrict G G'
  | renameLhs {G : System} {a b : Var} {S : Finset Var} {K : Row} :
      mk a S K ∈ G → mk a {b} (∅ : Row) ∈ G → LoopStrict G (insert (mk b S K) G)
  | linkSymm {G : System} {a b : Var} :
      mk a {b} (∅ : Row) ∈ G → LoopStrict G (insert (mk b {a} (∅ : Row)) G)
  | emptyProp {G : System} {a x : Var} {S : Finset Var} :
      mk a S (∅ : Row) ∈ G → mk a ∅ (∅ : Row) ∈ G → x ∈ S →
      LoopStrict G (insert (mk x ∅ (∅ : Row)) G)
  | dedup {G : System} {c v x : Var} {S S' : Finset Var} {K K' : Row} :
      mk c S K ∈ G → mk v S' K' ∈ G → v ∈ S → x ∈ S.erase v → x ∈ S' →
      LoopStrict G (insert (mk x ∅ (∅ : Row)) G)
  | drop {G G' : System} : G' ⊆ G → NoLoss G G' → LoopStrict G G'
  | instRemove {G : System} {v u : Var} :
      mk v {u} (∅ : Row) ∈ G → NoLoss G (substOut v u G) →
      LoopStrict G (substOut v u G)
  | emptyRemove {G : System} {v : Var} :
      mk v ∅ (∅ : Row) ∈ G → NoLoss G (makeEmptyE v G) →
      LoopStrict G (makeEmptyE v G)
  | concRemove {G : System} {v : Var} {C : Row} :
      mk v ∅ C ∈ G → NoLoss G (concretizeSrs v C G) →
      LoopStrict G (concretizeSrs v C G)
  | requeue {G G' : System} :
      allVars G' ⊆ allVars G → Conserv G G' → NoLoss G G' → LoopStrict G G'
abbrev LoopStrictRun : System → System → Prop := Relation.ReflTransGen LoopStrict
```

The first nine constructors are `LoopRel`'s nine RULE constructors, verbatim (same premises,
same guards, including `K2MintApp.uncarried` and `Cut.SplitApp`'s `¬ Named`).  `weaken` is
gone.  The four that replace it are R2.5's deletions:

| R2.5 row | the Scala | constructor | `G'` |
|---|---|---|---|
| 2, 7 | the dequeued partition leaving `incm`; `trim`'s `Partition.equals` filter; `++!`'s already-present test; `Q.insert`'s self-unification test | `drop` | any `G' ⊆ G` that loses nothing |
| 3 and 5 | `instantiate`'s removal, at BOTH argument orders | `instRemove` | `substOut v u G` |
| 4 | `makeEmpty`'s `procd` / `incmg` erasure, with `v <- ()` retained | `emptyRemove` | `KeyedEmpty.makeEmptyE v G` |
| 6 | `destructiveSub`'s `filter pred`, with `keepDefs` and `can` | `concRemove` | `KeyedRow.concretizeSrs v C G` |
| — | `Q.+!`'s `CommonPartition` redirect, which is in none of those images | `requeue` | any `G'` logically EQUIVALENT to `G` over `G`'s vocabulary |

(the shapes above are ROUND 2's; round 1 had the three eliminations as existentially
constrained `G'`, which `L5-REVIEW.md` F1 refuted — see §R2.1)

### C1.2 Soundness of each, and the theorem that makes "no arbitrary deletion" precise

```lean
theorem LoopStrict.sat {G G' : System} (h : LoopStrict G G') : SSat G → SSat G'
theorem LoopStrict.no_loss {G G' : System} (h : LoopStrict G G') : NoLoss G G'
theorem LoopStrictRun.sat {G G' : System} (h : LoopStrictRun G G') : SSat G → SSat G'
theorem LoopStrictRun.no_loss {G G' : System} (h : LoopStrictRun G G') : NoLoss G G'
```

`sat` is the one-directional soundness the library's deleting steps have.  `no_loss` is the
new one and it is what the whole checkpoint is for: **no `LoopStrict` step, and no run of
them, ever loses a fact**; equivalently every model of the system a step reaches is a model of
the system it left (`NoLoss.models`).  `LoopRel.weaken` fails it, and that is a theorem, not
an assertion:

```lean
theorem weaken_not_strict : ∃ G G' : System, LoopRel G G' ∧ ¬ NoLoss G G'
theorem weaken_not_strict' : ¬ LoopStrict {mk 0 ∅ ({1} : Row)} ∅
```

The two relations are compared in both directions:

```lean
/-- **Every ADDITIVE `LoopRel` step is a `LoopStrict` step.** -/
theorem LoopStrict.of_rel {G G' : System} (h : LoopRel G G') (hsub : G ⊆ G') :
    LoopStrictRun G G'
theorem LoopStrict.toRel_of_subset {G G' : System} (hsub : G' ⊆ G) : LoopRel G G'
```

`of_rel` says exactly that `LoopStrict` restricts `LoopRel` **in its deletions and nowhere
else**, and it is what makes the nine rule constructors live.

**Constructor liveness, counted mechanically** (`grep -o "LoopStrict\.<ctor>"` over my three
modules): `nongen` 1, `split` 1, `res` 1, `splitFree` 1, `kres` 1, `renameLhs` 1, `linkSymm`
1, `emptyProp` 1, `dedup` 1, `drop` 1, `instRemove` 2, `emptyRemove` 1, **`concRemove` 0**
(round 1 said `split` 2; `L5-REVIEW.md` F8 counted 1, and 1 is right).  `concRemove` is
declared for R2.5 row 6 and is NOT yet applied; §C1.5 says why and what its licence will have
to become.  **Round 2 changes all of this — see §R2.**

### C1.3 The refinement, VERBATIM (`Loop/StrictStep.lean`)

```lean
/-- **Refinement against `LoopStrict` for the `common`, `empty` and `unify` branches** -- the
analogue of L3's `Refine.step_refines`, with every use of `LoopRel.weaken` replaced by one of
the licensed deletions of R2.5 rows 2-5. -/
theorem step_refines_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : LoopStrictRun (sys s) (sys s')

theorem step_noLoss_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s')
```

(round 2 adds `step_strict`, `step_steps_strict`, `step_conserv_strict`, `step_models_iff`,
`step_sat_strict` and `step_allVars_strict` beside them — see §R2.2.)

branch by branch:

```lean
/-- R2.5 row 2.  `unify` at equal variables returns the queues and the environment untouched,
and the dequeued partition is `Partition.equals` to the processed one the lookup found, so the
system does not change AT ALL: row 2 is not a deletion. -/
theorem common_eq_sys {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some r.lhs)
    (h : step s = .continue s') : sys s' = sys s

theorem step_strict_common_eq {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some r.lhs)
    (h : step s = .continue s') : LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s)

/-- R2.5 rows 2 and 3. -/
theorem step_strict_common {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue} {u : Nat}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some u)
    (h : step s = .continue s') : LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s)

/-- R2.5 row 4. -/
theorem step_strict_empty {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hem : r.rhs.isEmpty = true) (h : step s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s)

/-- R2.5 row 5 -- the SWAPPED arguments: `unify(u, v)` on a dequeued `v <- (u)` binds `u`. -/
theorem step_strict_unify {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue} {u : Nat}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hsg : r.rhs.single? = some u) (h : step s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s)
```

**R2.5 row 7 is not a deletion either, and that is now proved:**

```lean
/-- **The `learn` branch adds and never removes.** -/
theorem step_learn_sys_mono {s s' : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') : sys s ⊆ sys s'

theorem step_learn_noLoss … : NoLoss (sys s) (sys s')

/-- Every dispatch branch except `concrete`. -/
def NonConcreteStep (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨ r.rhs.abstr.isEmpty = false

/-- **The loop loses information at most at the `concrete` branch.** -/
theorem step_noLoss {s s' : State} (hw : Wf s) (hb : NonConcreteStep s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s')
```

So of R2.5's six residual `weaken` sites: **rows 2, 3, 4, 5 are discharged as LICENSED
deletions; row 7 is discharged by proving it deletes nothing; row 6 is open.**  L3's `weaken`
at row 7 was an artifact of building the derived system `H` first and cutting down to `sys s'`
afterwards, not a deletion the loop performs.

**Acceptance criterion.**  `grep -n "LoopRel.weaken" Rowpartition/Loop/Strict*.lean` returns
two proof occurrences, both deliberate and neither in a refinement: `toRel_of_subset` (the
comparison theorem) and `weaken_not_strict` (the separation).  `step_refines_strict`,
`step_noLoss`, and every lemma they use are free of it.

### C1.4 The licences, proved once (`Loop/StrictStep.lean`)

Names only (the full signatures are in the module):

* `insertNP_noLoss`, `insertP_noLoss` — `Q.insert` and `Q.+!` lose nothing: a self-unification
  is satisfied by every assignment; a partition the queue already holds is still there; and the
  redirect `w <- (a)` together with the `a <- (S, K)` that triggered it entails the
  `w <- (S, K)` it replaced;
* `concatP_noLoss`, `concatNP_noLoss`, `ofListQ_noLoss` — the folds of those;
* `trim_noLoss` — `trim` refuses exactly what the processed queue already holds;
* `makeEmpty_noLoss` — R2.5 row 4's licence;
* `instantiate_noLoss` — R2.5 rows 3 and 5's licence, at both argument orders.

Underneath them, the facts about the CHAMP writers the `sys` level needs — `SSet` membership is
not preserved on the nose (`pickRep` may swap a representative, `ofList` deduplicates), but the
CONSTRAINT is: `toConstraint_mem_foldl_incl`, `toConstraint_mem_ofList`,
`toConstraint_mem_concat`, `toConstraint_mem_map`.

and the two ways of reading a constraint back through an elimination:

```lean
theorem sat_of_erase {rho : Assign} {a v : Var} {S : Finset Var} {K : Row}
    (hv : rho v = ∅) (h : Sat rho (mk a (S.erase v) K)) : Sat rho (mk a S K)
theorem sat_of_replace {rho : Assign} {a v u : Var} {S : Finset Var} {K : Row}
    (hlink : rho v = rho u) (hdedup : v ∈ S → u ∈ S → rho u = ∅)
    (h : Sat rho (mk a (S.image (fun w => if w == v then u else w)) K)) :
    Sat rho (mk a S K)
```

`sat_of_replace` is the exact statement of why `replace`'s de-duplication fact `u <- ()` is
needed: the substitution `v := u` is invertible under a model of the link EXCEPT when it
collapses two parts into one, which is precisely the case `replace` emits `u <- ()` for.

### C1.5 What C1 does NOT do, stated plainly

| asked for | delivered | why not more |
|---|---|---|
| `LoopStrict` with no arbitrary-deletion constructor | **yes**, and `LoopStrict.no_loss` proves the restriction is real | — |
| the six R2.5 deletions as sound constructors | four constructors covering rows 2, 3, 4, 5, 7 (row 7 shown not to be a deletion); `concRemove` declared for row 6, not applied | row 6 needs `subPartitions` / `destructiveSub` / `makeConcrete` in the BACKWARD direction, and its licence has to change (below) |
| `step_refines_all` re-proved against `LoopStrict` | `step_refines_strict` under `LinkOrEmptyStep` (the `common`, `empty`, `unify` branches) — the analogue of L3's `step_refines`, not of `step_refines_nonlearn` or `step_refines_all` | the `concrete` branch needs row 6; the `learn` branch needs `learnPartitions_run` re-proved against `LoopStrict`, and the brief forbids editing `Loop/RefineLearn.lean`, so that is a 1,558-line duplication rather than a one-line generalisation |

**Row 6's licence cannot be the unconditional `NoLoss`, and here is why, in Lean:**

```lean
/-- **`cancellation` says nothing about two bare concrete rows.**  This is the gap R2.5 row 6's
licence has to work around: `makeConcrete v fs` deletes a definition `v <- ((|C|))` and the
`can` fold contributes nothing in its place. -/
theorem cancellation_bare (v : Nat) (fs cs : SSet Lbl) :
    cancellation v (RHS.ofConcr fs) (RHS.ofConcr cs) = SSet.empty
```

`cancellation`'s first branch needs `xs.size == 1` and a bare concrete row has no variable
parts at all; its second needs `ys.size == 1`.  So against a definition `v <- ((|C|))` with
`C ⊆ fs` (which `ensureSuperset` permits) it emits NOTHING, `destructiveSub` deletes the
definition (fewer than two abstract parts, so `keepDefs` does not save it), and `C = fs` is
recorded nowhere.  On SATISFIABLE input that costs nothing, because a model forces `C = fs`;
on unsatisfiable input it is a genuine loss.  So `concRemove`'s third field will have to read
`(SSat G → NoLoss G G')`, and `LoopStrict.no_loss` will weaken to `SSat G → NoLoss G G'` when
row 6 lands.  Two facts soften it:

* the singleton case DOES work — `cancellation v ((|fs|)) (a, (|C|))` emits `a <- ((|fs \ C|))`,
  which I confirmed on the model (`conc2` probe: the trace line
  `step … concrete Cancellation: ^free1 <- (,Repro.l101)`);
* the only shape where the unconditional licence fails is refuted EARLIER by `labelCheck`:
  `v <- ((|C|))` with `C ⊊ fs` is rejected before any `step` runs (`conc1` probe:
  `REJECTED Row partitions are unsatisfiable at field 'Repro.l101': a part contains it but the
  whole does not`).  Round 1 attributed the message *"the whole contains it but no part does"*
  to this probe; that is `conc3`'s message, and `L5-REVIEW.md` F7 caught the misquote.  The
  substance is unaffected: the row-level information loss is real but masked by the per-label
  defence at the shipped flags.

---

## C2 — the supply invariant, preserved

**Not closed.**  What the brief asks — `SupOk`/`SupFresh` preserved by `step`, so that
`RunSupOk` becomes a theorem from the initial state — needs the vocabulary lemma

> `∀ w ∈ allVars (sys s'), w ∈ allVars (sys s) ∨ w is one of the ids the step drew`

for EVERY branch, and for the `learn` branch that is a statement about every conclusion of
every rule in `learnPartitions`' fold, i.e. the forward twin of `RefineLearn.lean` — the same
1,558-line obstacle as C1's `learn`.  It was not attempted.

What IS proved, and it is the part of C2 that does not need the `learn` vocabulary
(`Loop/StrictBound.lean`):

```lean
/-- **The supply moves only at a `learn` step.** -/
theorem step_su {s s' : State} (h : step s = .continue s') :
    s'.su = s.su ∨ IsLearnStep s
```

so `SupOk s'.su = SupOk s.su` and `SupFresh s'.su = SupFresh s.su` outside `learn`, and the
vocabulary can grow ONLY at a step `Order.learnChain_card` already charges a new processed
constraint for.  How many ids a `learn` step may draw, as the brief asks: **more than one** —
`splitConcrete` draws one in its mint branch and `resolution` draws one per call that reaches
the lone-variable pattern *even when it emits nothing*, and `learnPartitions` folds over all
of `proc`, so a single `learn` step can draw `1 + |proc|` ids.  The invariant therefore has to
be iterated over the fold, not applied once, which is exactly what `RefineLearn`'s `RuleRun`
threading does for freshness and what the vocabulary clause would have to do too.

---

## C3 — the loop-level mint bound: **(T2)**

### C3.1 Which system the measure is taken over — the choice `L3-REVIEW.md` §6d did not make

The relation-level bound is `KeyedRow.mintsBoundedOnSatKeyed2Star`: along `K2StarLoopRun`,
`(allVars G).card ≤ (allVars G₀).card + hmeas (labelsOf G₀) rho G₀`, with

    hmeas L rho G     = Σ_{v ∈ allVars G} uncarried L G v * (2^|L| + 1)^|rho v|
    uncarried L G v   = |{K ⊆ L : ¬ Carried G v K}|

driven by `hmeas_le_of_carried` (non-increase when `allVars` does not grow and `Carried` is
preserved) and `hmeas_mint_lt` (strict decrease at a guarded mint).  Transporting it needs, at
every `step`:

* **(A)** every loop MINT is a `K2SplitStep.mint` / `K2ResStep.mint` of the system the measure
  is taken over — i.e. `¬ Carried <that system> v K` from the loop's own guard;
* **(B)** every other step preserves `Carried` and adds no variable.

There are three candidate systems and **only one of them can satisfy (B)**:

| system | (B) at `instantiate` | (B) at `makeEmpty` | (B) at `makeConcrete` |
|---|---|---|---|
| `sys s` (queues + ALL environment facts) | **FAILS** | ok | ok |
| the queues alone | ok | **FAILS** | ok |
| `qsys s` = queues + the environment's EMPTY-ROW facts, NOT the aliases | ok | ok | ok |

The first row is new here.  `L3-REVIEW.md` §6d discusses only (A) and only for `sys s`; but
(B) fails for `sys s` too, and for a different reason: after `unify(v, u)` the environment
retains `v <- (u)`, so `v` is still in `allVars (sys s')`, while every partition that carried a
key for `v` has been rewritten to `u` — `Resolved (sys s') v K` and `ConcCarried (sys s') v K`
both fail where they held, `uncarried v` jumps, and `hmeas` INCREASES.  The second row is
`KeyedEmpty.carried_not_invariant` / `hmeas_increases`, already in the library.

`qsys` is therefore the notion the loop-level measure has to use, and it is now in Lean:

```lean
/-- The empty-row facts the environment retains. -/
def envEmptySys (e : Env) : System :=
  (e.binds.filterMap (fun b => match b.2 with
    | .emptyRow => some (Rowpartition.mk b.1 ∅ (∅ : Row))
    | .alias _ => none)).toFinset

/-- **The queue-visible system.** -/
def qsys (s : State) : System :=
  (s.parts.map LPart.toConstraint).toFinset ∪ envEmptySys s.env

theorem qsys_subset_sys (s : State) : qsys s ⊆ sys s
```

with the three (B) arguments.  **All three are PROSE, not theorems** (`L5-REVIEW.md` F6 asked
for this to be said row by row): `qsys` carries exactly one theorem, `qsys_subset_sys`, plus
round 2's `qsys_concCarried_of_envEmpty`.  And one of the three needs more than a table cell:
at `makeEmpty` a singleton link `mk u {v} K` becomes `mk u ∅ K`, which DESTROYS a
`Resolved (qsys s) u K` witness rather than preserving it; `KeyedEmpty`'s
`mintsBoundedOnSat_emptyPersisting` is what has to absorb that, and it is not applied here.
The sketches:
* alias elimination: `v` leaves `qsys` entirely, `allVars (qsys s') ⊆ allVars (qsys s)`, and a
  witness `mk w {v} K` becomes `mk w {u} K` while a concrete carrier `mk v ∅ (C \ K)` becomes
  `mk u ∅ (C \ K)` — so `Carried` survives for every surviving variable;
* `makeEmpty`: `v <- ()` is RETAINED in `qsys`, which is exactly the hypothesis
  `KeyedEmpty.mintsBoundedOnSatKeyed3E` needs;
* `makeConcrete`: `KeyedRow.carried_concretizeSrs`.

### C3.2 The obstacle, LOCALISED

With `qsys`, (A) fails in one precise place and no other.  The loop's concrete-row guard is
`findConcRow l k = none`: "`v` has a row `C` in the QUEUES and no queue variable has row
`C \ k`".  `qsys` additionally counts the retained empties, so as soon as the solve has
emptied ANY variable, `ConcCarried (qsys s) v K` holds for every `K` with `C \ K = ∅`, i.e.
`K = C` — while the loop's lookup misses it and MINTS.

> **CORRECTED IN ROUND 2** (`L5-REVIEW.md` F5; round 1 wrote "a mint at a key EQUAL to the
> parent's whole concrete row", and both halves of that were wrong).  `C \ K = ∅` is
> **`C ⊆ K`**, not `K = C`, so a single retained `z <- ()` carries EVERY key `K ⊇ C` —
> `2^{|L \ C|}` of them, not one; and if the PARENT is itself already empty (`C = ∅`) it
> carries **every key at once**, a case round 1 missed entirely.  Both are now theorems,
> `concCarried_of_conc_subset` and `concCarried_parent_empty` (§R2.3).

That is still the branch `-Dermine.emptyRow` (`findEmptyRow`) exists to close, and it ships
OFF.  Compare `L3-REVIEW.md` §6d, which says the mismatch is "`Carried (sys s) v K` can hold
where the loop's lookup misses" without saying WHICH `K`; the answer is "every `K ⊇ C`, and
every `K` at all when the parent is already empty".  The parent-already-empty case is vacuous
exactly when the queue-hygiene invariant of §R2.4 holds — which is the invariant the compiler
panic of §0 violates.  **The localisation and the bug are the same object.**

Two ways out, neither taken here:
1. turn `emptyRow` ON in the model and use `KeyedEmpty.mintsBoundedOnSatKeyed3E`, for which
   (A) then holds by construction — which makes C4's question load-bearing;
2. bound the exceptional mints separately.  Each is at a pair `(v, C)` with `mk v ∅ C` in the
   queues, so at most one per (variable, concrete row) pair, i.e. `|V| · 2^{|L|}` of them —
   circular in `|V|` again.

### C3.3 The brief's approach (a), and why the charging does not close

Approach (a) asks to bound the damage the deletions do to the measure by charging a minted
variable's later loss to its own mint.  Written out: let `M` be the number of mints, `V₀` the
initial vocabulary, so `V = V₀ + M`; eliminations are at most `V` (a variable is bound once —
`step_envNodup` below); each elimination can raise `hmeas` by at most
`Δ ≤ V · 2^{|L|} · (2^{|L|}+1)^{|L|}`, because it can cost every variable every key; each mint
lowers it by at least 1.  Then

    M ≤ hmeas₀ + (#eliminations) · Δ ≤ c + c·(V₀ + M)²

which is quadratic in `M` on the right and bounds nothing.  **The charging fails because the
damage per elimination is itself proportional to the vocabulary**, and no per-mint charge
fixes that.  Making it work needs the damage per elimination to be bounded independently of
`|V|` — i.e. a bound on how many variables can carry a key through the eliminated one — which
is not available.  With `qsys` the damage is ZERO (that is the point of §C3.1), and the whole
difficulty moves to (A), i.e. to §C3.2.

### C3.4 The brief's approach (b): what IS proved of the count (`Loop/StrictBound.lean`)

```lean
/-- The environment's bound variables are distinct. -/
def EnvNodup (s : State) : Prop := (s.env.binds.map Prod.fst).Nodup

theorem instantiate_env_len {…} (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    e.binds.length = env.binds.length + 1 ∧ env.contains v = false ∧
      e = env.instantiate v (.alias u)
theorem makeEmpty_env_len {…} (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    e.binds.length = env.binds.length + 1 ∧ env.contains v = false ∧
      e = env.instantiate v .emptyRow
theorem unifyVars_env {…} : e = env ∨ (e.binds.length = env.binds.length + 1 ∧ …)

/-- **A variable is bound at most once**, along every run. -/
theorem step_envNodup {s s' : State} (h0 : EnvNodup s) (h : step s = .continue s') :
    EnvNodup s'
theorem envNodup_initial …

/-- **The environment never outgrows the vocabulary.** -/
theorem env_len_le_allVars {s : State} (h : EnvNodup s) :
    s.env.binds.length ≤ (allVars (sys s)).card
```

Putting it together, branch by branch, for a run that does not die:

| branch | bounded by | by what |
|---|---|---|
| `common` at equal variables | the number of enqueues | `common_eq_sys`: the step is the identity on `sys` and removes one partition from `incm` |
| `common` at distinct variables | `(allVars (sys s)).card` | one new binding each (`instantiate_env_len`), no variable bound twice (`step_envNodup`), bindings ≤ vocabulary (`env_len_le_allVars`) |
| `empty` | same | `makeEmpty_env_len` |
| `unify` at distinct variables | same | `instantiate_env_len` |
| `learn` | the growth of `procSys` | `Order.learn_procSys_lt`, `Order.learnChain_card` (L3) |
| `concrete` | **not bounded** | binds nothing; L3 §4c(2)'s `ensureSuperset`-monotonicity sketch (a repeat at `v` needs `C ⊊ C'`, so at most `|labels|` times per variable) needs `v <- ((|C|))` to survive in `proc`, and was not written |

So the residual is exactly two items: **the vocabulary bound** (§C3.2) and **the `concrete`
count**.  Everything else in approach (b) is now a theorem about the real `step`.

### C3.5 The witness hunt

All runs are of the L1/L2 model executable (`lake exe looptrace`), whose agreement with the
compiler is L2's and L4's result; the interesting individuals were then replayed through the
REAL `Subst.solve` (`tracker/repro/satterm/run.sh`).

**Population 1 — empty-biased satisfiable-by-construction systems.**  1,500 seeds from a
generator that gives each system 1-5 labels and 2-6 EMPTY-row variables (the L3 generator used
0-2), so that `makeEmpty` fires often and the W2/W3/G7 empty-row engines are in scope; every
system has a model by construction (verified independently in Python for the seeds that
mattered).  5 id bases each (0, 1, 5, 13, 97), fuel 4,000, shipped flags, 60 s cap.

| result | count |
|---|---|
| `SOLVED` | 7,468 |
| `FUEL` (a divergence witness) | **0** |
| `REJECTED` | 29, all the reinstantiation panic — §0 |
| capped at 60 s | 3 (all `e00346`; it SOLVES in 93 s) |

**Population 2 — a scaling family**, 6/8/10/12/14/16 constraints x 40 seeds x 2 bases, 4
labels, 4 empty-row variables, fuel 200,000, 90 s cap:

| constraints | mean ids drawn | max | not solved |
|---|---|---|---|
| 6 | 7.7 | 34 | 0 |
| 8 | 13.9 | 104 | 0 |
| 10 | 23.2 | 116 | 0 |
| 12 | 30.6 | 142 | 0 |
| 14 | 47.1 | 224 | 0 |
| 16 | 59.9 | 357 | 1 (90 s cap) |

Mean minting grows about QUADRATICALLY in the number of constraints (`7.7·(16/6)² = 54.7`
against a measured 59.9); the maximum grows faster.  No run diverged.

**The extreme individual, replayed through the compiler.**  `e00346` — 12 constraints, 5
labels, 15 variables, satisfiable — at id base 1:

    tracker/repro/satterm/run.sh sweep json:.../e00346.json 0 5 60 6
    base=1 … SOLVED in 655 ms … [bound=164 residual=6 drawn=1033 …]
    DRAWN min=553 median=690 max=1033

**1,033 fresh ids from a twelve-constraint system**, and the Lean model draws exactly 1,033 at
the same base.  This is the strongest evidence I have on the size of any bound: it is not
small, it is very sensitive to the id base (553 to 1,033 across six bases), and it terminates
every time.

**Verdict: (T2).**  Not (T1): there is no bound, for the reason §C3.2 states.  Not (W): no
witness, and the shape of the evidence (quadratic growth, 7,500 + 480 terminating runs, and a
compiler that reproduces the worst case in 655 ms) says none is expected at the shipped flags.

### C3.6 Unsatisfiable input, as the brief asks

Out of scope for the bound, and it stays undecided — but this round adds two things:

* the relations DO diverge on it (`DefaultDiverge`, `ResGuardDiverge`, and `not_CRule` stands),
  and nothing proved here rules the loop out;
* the loop's `concrete` branch **loses information on unsatisfiable input** — that is
  `cancellation_bare` (§C1.5).  So on unsatisfiable input a run is not even `NoLoss`-monotone,
  which is a second, independent reason to state the bound for satisfiable input only.

---

## C4 — `emptyRow` and the Stage 7b variant

C3 is (T2), not (T1), so the brief's C4 is answered conditionally; here is what is known.

**Would the bound hold with `emptyRow = true`?**  It would be EASIER, not harder, and that is
the whole point of §C3.2: `-Dermine.emptyRow` makes `findEmptyRow` read the retained `v <- ()`
facts back, which is exactly the lookup `qsys` counts.  With the flag on, the residual
mismatch of §C3.2 disappears — a mint at `K = C` while some variable is empty is refused by
the loop, so the guard `¬ Carried (qsys s) v K` becomes available at every mint, and
`KeyedEmpty.mintsBoundedOnSatKeyed3E` (which is stated for exactly the relation that RETAINS
`v <- ()`) is the bound to transport rather than
`KeyedRow.mintsBoundedOnSatKeyed2Star`.  So: **if T1 is provable at all, the `emptyRow = true`
variant is the case to prove FIRST**, and the shipped `emptyRow = false` variant needs the
extra argument that bounds the exceptional mints.

Measured, not just argued: the same 1,500 seeds at bases 0 and 5 (3,000 runs each), fuel
4,000, at `--flags=emptyrow` against the shipped flags — **2,986 SOLVED on each side, 0 FUEL on
each side**, mean ids drawn **10.262** with `emptyRow` on against **10.270** off (0.08%), the
same maximum (623) and the same 14 rejections/caps.  So turning the flag on costs nothing in mints on this population
and (per the argument above) buys the guard.  It does NOT contradict Stage 7b's finding that
`emptyRow` is 1.9x slower in the compiler: that is wall time on the real corpus, where the
mint `emptyRow` suppresses was the queue's only garbage collector, and this population's
queues are tiny.

**Would the Stage 7b variant need a new guard case?**  Yes, one.  Stage 7b's variant is
"reuse if it adds a fact, else the shipped mint", so a reuse that adds nothing FALLS THROUGH
to the mint — and that fall-through is a mint taken while `Carried (qsys s) v K` holds, i.e.
exactly the shape §C3.2 identifies as not being a relation mint.  A bound for the variant
therefore needs a guard case saying that a fall-through mint is taken at most once per
`(v, K)`, which is what L3's (iii) answer supplies at the control-flow level (`trim` refuses
what `proc` holds, with the two escapes, one self-cancelling and one benign) but not as a
measure argument.  No Scala change; the variant is still not in the model.

---

## Summary of everything not proved

| asked for | delivered | why not more |
|---|---|---|
| C1 `LoopStrict`, no arbitrary deletion | **done**, with `no_loss` as a theorem and `weaken_not_strict` as its separation | — |
| C1 the six R2.5 deletions as constructors | rows 2, 3, 4, 5 licensed and live; row 7 proved NOT to be a deletion; row 6's constructor declared, not live | row 6 needs `subPartitions`/`destructiveSub`/`makeConcrete` backwards, and a licence conditioned on `SSat` (`cancellation_bare`) |
| C1 `step_refines_all` against `LoopStrict` | `step_refines_strict` for `common`/`empty`/`unify`; `step_noLoss` for those three plus `learn` | `concrete` needs row 6; `learn` needs `RefineLearn.lean` re-proved against `LoopStrict`, which the no-edit constraint turns into a 1,558-line duplication |
| C2 `SupOk`/`SupFresh` preserved | `step_su` (only `learn` draws), the environment-counting theorems | the vocabulary lemma for the `learn` branch is the forward twin of `RefineLearn.lean` |
| C3 `Terminates` with a bound | **(T2)**: five of the six branch counts, the measure's carrier (`qsys`), and the obstacle localised to one guard case | the vocabulary bound; see C3.2 |
| C3 a witness | none found; 7,500 + 480 runs, the worst case replayed on the compiler | — |
| C4 | answered, with a measurement | — |


---

# Round 2 — 2026-09-04, after `tracker/loopmodel/L5-REVIEW.md` (FIX-THEN-ADVANCE)

The review's two major findings are both fixed, both machine-checked, and both by the
reviewer's own instruments.  Round-1 text above is corrected in place where it was wrong, and
each correction says so.

| | before round 2 | after round 2 |
|---|---|---|
| `lake build Rowpartition` | 841 jobs | **841 jobs**, success |
| `lake env lean Audit.lean` | `3003; 0` | **`Rowpartition theorems audited: 3058; declarations using a non-standard axiom: 0`** |
| new-module lines | 1,723 | **2,913** |
| `sorry` / `axiom` / `partial` / `native_decide` | 0 | **0** |
| `#print axioms`, 57 headlines | — | 56 `[propext, Classical.choice, Quot.sound]`, 1 `[propext, Quot.sound]`; **no non-standard axiom** |

## R2.1 — F1: the three deletion constructors are now the LIBRARY OPERATORS

The reviewer's `Growth.lean` builds a `LoopStrictRun` of unbounded vocabulary out of the fixed
satisfiable `{0 <- ()}` using `emptyRemove` alone, because round 1's `emptyRemove` constrained
`G'` only by `mk v ∅ ∅ ∈ G'`, `SSat G → SSat G'` and `NoLoss G G'` — which licenses arbitrary
satisfiability-preserving ADDITION.  `LoopStrict` is now, VERBATIM (constructor lines verbatim; per-constructor doc comments
elided):

```lean
inductive LoopStrict : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → LoopStrict G G'
  | split {G G' : System} : K2SplitStep G G' → LoopStrict G G'
  | res {G G' : System} : ResStep G G' → LoopStrict G G'
  | splitFree {G G' : System} : SplitStep G G' → LoopStrict G G'
  | kres {G G' : System} : K2ResStep G G' → LoopStrict G G'
  | renameLhs {G : System} {a b : Var} {S : Finset Var} {K : Row} :
      mk a S K ∈ G → mk a {b} (∅ : Row) ∈ G → LoopStrict G (insert (mk b S K) G)
  | linkSymm {G : System} {a b : Var} :
      mk a {b} (∅ : Row) ∈ G → LoopStrict G (insert (mk b {a} (∅ : Row)) G)
  | emptyProp {G : System} {a x : Var} {S : Finset Var} :
      mk a S (∅ : Row) ∈ G → mk a ∅ (∅ : Row) ∈ G → x ∈ S →
      LoopStrict G (insert (mk x ∅ (∅ : Row)) G)
  | dedup {G : System} {c v x : Var} {S S' : Finset Var} {K K' : Row} :
      mk c S K ∈ G → mk v S' K' ∈ G → v ∈ S → x ∈ S.erase v → x ∈ S' →
      LoopStrict G (insert (mk x ∅ (∅ : Row)) G)
  | drop {G G' : System} : G' ⊆ G → NoLoss G G' → LoopStrict G G'
  | instRemove {G : System} {v u : Var} :
      mk v {u} (∅ : Row) ∈ G → NoLoss G (substOut v u G) →
      LoopStrict G (substOut v u G)
  | emptyRemove {G : System} {v : Var} :
      mk v ∅ (∅ : Row) ∈ G → NoLoss G (makeEmptyE v G) →
      LoopStrict G (makeEmptyE v G)
  | concRemove {G : System} {v : Var} {C : Row} :
      mk v ∅ C ∈ G → NoLoss G (concretizeSrs v C G) →
      LoopStrict G (concretizeSrs v C G)
  | requeue {G G' : System} :
      allVars G' ⊆ allVars G → Conserv G G' → NoLoss G G' → LoopStrict G G'
```

with

```lean
/-- `G'` invents nothing: every constraint of `G'` is a consequence of `G`. -/
def Conserv (G G' : System) : Prop := ∀ c ∈ G', SEntails G c

/-- One constraint under the substitution `v := u`. -/
def substC (v u : Var) (c : Constraint) : Constraint :=
  mk (if c.lhs == v then u else c.lhs)
    ((vset c).image (fun w => if w == v then u else w)) c.conc

/-- `instantiate`'s removal, as one function on systems. -/
def substOut (v u : Var) (G : System) : System :=
  insert (mk v {u} (∅ : Row))
    ((G.filter (fun c => c.lhs ≠ v ∧ v ∉ vset c)) ∪
      (G.filter (fun c => c.lhs = v ∨ v ∈ vset c)).image (substC v u))
```

so `emptyRemove` IS `KeyedEmpty.makeEmptyE`, `concRemove` IS `KeyedRow.concretizeSrs`, and
`instRemove` is the operator `substOut` (the library has no name for it), each a function of
`G`.  `NoLoss` stays as their licence — `makeEmptyE` and `concretizeSrs` both lose a fact on
UNSATISFIABLE input (`makeEmptyE` at the `die` arm, `concretizeSrs` at `cancellation_bare`'s
bare concrete definition), so it cannot be dropped.  `requeue` is the one remaining
existentially-quantified constructor and it is TIGHT: `Conserv` and `NoLoss` together are
model-set EQUALITY, and `allVars G' ⊆ allVars G` forbids naming a variable `G` does not.  It
exists because `Q.+!`'s `CommonPartition` redirect is in NONE of the three operators' images
(R2.2 of `L3-THEOREMS.md`).

New soundness and vocabulary lemmas for the new operator, VERBATIM:

```lean
theorem sat_substC {rho : Assign} {v u : Var} {c : Constraint} (hvu : rho v = rho u)
    (h : Sat rho c) : Sat rho (substC v u c)
theorem substOut_sound {v u : Var} {G : System} (hlink : mk v {u} (∅ : Row) ∈ G) :
    ∀ rho, SModels rho G → SModels rho (substOut v u G)
theorem allVars_substOut_subset {v u : Var} {G : System} (hlink : mk v {u} (∅ : Row) ∈ G) :
    allVars (substOut v u G) ⊆ allVars G
```

(`makeEmptyE_sound`, `allVars_makeEmptyE_subset`, `concretizeSrs_sound` and
`allVars_concretizeSrs_subset` are the library's, used as they stand.)

### The acceptance: the vocabulary bound, VERBATIM

```lean
/-- A step built on one of the library's MINTING relations. -/
def IsMint (G G' : System) : Prop :=
  K2SplitStep G G' ∨ ResStep G G' ∨ SplitStep G G' ∨ K2ResStep G G'

/-- **A `LoopStrict` step that is not built on a minting relation adds no variable.** -/
theorem LoopStrict.allVars_subset_of_notMint {G G' : System} (h : LoopStrict G G')
    (hm : ¬ IsMint G G') : allVars G' ⊆ allVars G

/-- **Every `LoopStrict` step adds at most one variable.** -/
theorem LoopStrict.allVars_card_le {G G' : System} (h : LoopStrict G G') :
    (allVars G').card ≤ (allVars G).card + 1

/-- A run of `LoopStrict` in which exactly `m` steps enlarge the vocabulary. -/
inductive LoopStrictSteps : Nat → System → System → Prop
  | refl (G : System) : LoopStrictSteps 0 G G
  | keep {m : Nat} {G G' G'' : System} :
      LoopStrictSteps m G G' → LoopStrict G' G'' → allVars G'' ⊆ allVars G' →
      LoopStrictSteps m G G''
  | mint {m : Nat} {G G' G'' : System} :
      LoopStrictSteps m G G' → LoopStrict G' G'' → LoopStrictSteps (m + 1) G G''

theorem LoopStrictRun.toSteps {G G' : System} (h : LoopStrictRun G G') :
    ∃ m, LoopStrictSteps m G G'

/-- **THE VOCABULARY BOUND.** -/
theorem LoopStrictSteps.allVars_card_le {m : Nat} {G G' : System}
    (h : LoopStrictSteps m G G') : (allVars G').card ≤ (allVars G).card + m

theorem LoopStrictSteps.allVars_subset {m : Nat} {G G' : System} (h : LoopStrictSteps m G G') :
    m = 0 → allVars G' ⊆ allVars G

/-- A run none of whose steps is built on one of the library's MINTING relations. -/
inductive MintFreeRun : System → System → Prop
  | refl (G : System) : MintFreeRun G G
  | tail {G G' G'' : System} :
      MintFreeRun G G' → LoopStrict G' G'' → ¬ IsMint G' G'' → MintFreeRun G G''

theorem MintFreeRun.toSteps {G G' : System} (h : MintFreeRun G G') : LoopStrictSteps 0 G G'
theorem MintFreeRun.allVars_subset {G G' : System} (h : MintFreeRun G G') :
    allVars G' ⊆ allVars G

/-- **The refutation of `L5-REVIEW.md`'s `no_mint_bound_along_strict`.** -/
theorem no_growth_without_mint {G' : System}
    (h : MintFreeRun {mk 0 ∅ (∅ : Row)} G') : (allVars G').card ≤ 1
```

**Checked as the reviewer asked:** his `Growth.lean`, copied unchanged into
`/home/dmitry/.claude/jobs/880c725d/tmp/L5/Growth-check.lean`, **no longer elaborates** —
`strict_grows` (line 34) fails because `LoopStrict.emptyRemove` now demands
`G' = makeEmptyE v G`.  And the positive statement is proved, not merely the negative one:
along any run the vocabulary is bounded by the initial vocabulary plus the number of steps that
enlarge it, and only the four minting constructors can be such a step.

### The loop's real step, connected to the operator (`L5-REVIEW.md` §10(1), second half)

For R2.5 row 4 the connection is made:

```lean
/-- Systems all of whose constraints are `mk`-shaped. -/
def MkShaped (G : System) : Prop := ∀ c ∈ G, c = mk c.lhs (vset c) c.conc

theorem mkShaped_sys (s : State) : MkShaped (sys s)

/-- **`makeEmptyE` loses nothing** on a `mk`-shaped system in which no constraint defines `v`
with a concrete part -- which is exactly the `die` arm `makeEmpty` rejects. -/
theorem makeEmptyE_noLoss {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    NoLoss G (makeEmptyE v G)

/-- **`makeEmptyE` IS a `LoopStrict` step.** -/
theorem emptyRemove_step {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    LoopStrict G (makeEmptyE v G)

/-- **A successful `makeEmpty` means no queue definition of `v` carries a label.** -/
theorem makeEmpty_defs_conc_empty {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    ∀ x ∈ ((incm.partition (fun p => p.involves v)).1.concat
           (proc.partition (fun p => p.involves v)).1).elems,
      x.lhs = v → x.rhs.conc.isEmpty = true

/-- **R2.5 row 4, connected to the library operator**: at the `empty` branch the first step of
the loop's transition is literally `KeyedEmpty.makeEmptyE`. -/
theorem step_empty_makeEmptyE {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hem : r.rhs.isEmpty = true) (h : step s = .continue s') :
    LoopStrict (sys s) (Rowpartition.KeyedEmpty.makeEmptyE r.lhs (sys s))
```

**Constructor liveness after round 2**, counted mechanically over the three modules
(`grep -o "LoopStrict\.<ctor>"`): `nongen` 1, `split` 2, `res` 1, `splitFree` 1, `kres` 1,
`renameLhs` 1, `linkSymm` 1, `emptyProp` 1, `dedup` 1, `drop` 2, `emptyRemove` 1, `requeue` 4 —
**12 of 14 live**.  The two that are not, stated plainly:

* **`instRemove` (R2.5 rows 3 and 5)** — `substOut` does NOT include `replace`'s
  de-duplication fact `u <- ()`, which is what makes the substitution invertible when `v` and
  `u` are BOTH parts of the same constraint (`sat_of_replace`'s `hdedup`).  So
  `NoLoss G (substOut v u G)` is not dischargeable in general and the constructor is not
  applied; the loop's `common`/`unify` steps go through `requeue` instead.  Adding the
  de-duplication facts to `substOut` is the fix, and it is not written;
* **`concRemove` (R2.5 row 6)** — unchanged from round 1: its `NoLoss` premise is the
  `cancellation_bare` gap, and the `concrete` branch is not refined at all.

## R2.2 — F2: the strict refinement no longer touches `LoopRel.weaken`

Round 1 discharged the `SSat` premises with L3's `Refine.step_sat = (step_refines _).sat`.
Round 2 proves the FORWARD direction here instead, with one generic analysis per operation run
at two predicates, VERBATIM:

```lean
/-- The closure both forward predicates need: `Q.+!`'s `CommonPartition` redirect. -/
def RedClosed (P : Constraint → Prop) : Prop :=
  ∀ (w a : Var) (S : Finset Var) (K : Row),
    P (mk w S K) → P (mk a S K) → P (mk w {a} (∅ : Row))

/-- Every variable of the constraint is in `V`. -/
def VocIn (V : Finset Var) (c : Constraint) : Prop := insert c.lhs (vset c) ⊆ V

theorem redClosed_voc (V : Finset Var) : RedClosed (VocIn V)
theorem redClosed_sent (G : System) : RedClosed (SEntails G)
theorem insertP_forward / concatP_forward / foldl_concatP_forward
theorem makeEmpty_forward / instantiate_forward
theorem replace_forward_sent / replace_forward_voc
theorem sat_erase_of_empty
```

and then, at the loop level:

```lean
theorem step_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s)

theorem step_refines_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : LoopStrictRun (sys s) (sys s')

/-- ... and the step is counted as MINT-FREE, so `LoopStrictSteps.allVars_card_le` charges it
nothing.  This is the form the loop-level bound needs. -/
theorem step_steps_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : LoopStrictSteps 0 (sys s) (sys s')

theorem step_noLoss_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s')

theorem step_conserv_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : Conserv (sys s) (sys s')

/-- **The three environment branches do not move the model set at all.** -/
theorem step_models_iff {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') (rho : Assign) :
    SModels rho (sys s) ↔ SModels rho (sys s')

/-- **`Refine.step_sat` without `LoopRel`.** -/
theorem step_sat_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s')

/-- **The vocabulary does not grow at an environment branch.** -/
theorem step_allVars_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : allVars (sys s') ⊆ allVars (sys s)
```

`step_models_iff` is strictly more than round 1 claimed: the `common`, `empty` and `unify`
branches do not move the model set AT ALL.

**Verified with the reviewer's own metaprogram**, `tmp/review-L5/Deps.lean`, extended to the
new names and re-run (`tmp/L5/Deps.lean`):

```
step_strict:             LoopRel.weaken=false  step_refines=false
step_refines_strict:     LoopRel.weaken=false  step_refines=false
step_steps_strict:       LoopRel.weaken=false  step_refines=false
step_noLoss:             LoopRel.weaken=false  step_refines=false
step_strict_empty:       LoopRel.weaken=false  step_refines=false
step_strict_unify:       LoopRel.weaken=false  step_refines=false
step_strict_common:      LoopRel.weaken=false  step_refines=false
step_noLoss_strict:      LoopRel.weaken=false  step_refines=false
step_conserv_strict:     LoopRel.weaken=false  step_refines=false
step_models_iff:         LoopRel.weaken=false  step_refines=false
step_sat_strict:         LoopRel.weaken=false  step_refines=false
step_allVars_strict:     LoopRel.weaken=false  step_refines=false
step_learn_sys_mono:     LoopRel.weaken=false  step_refines=false
step_strict_common_eq:   LoopRel.weaken=false  step_refines=false
common_eq_sys:           LoopRel.weaken=false  step_refines=false
LoopStrict.sat:          LoopRel.weaken=false  step_refines=false
LoopStrict.no_loss:      LoopRel.weaken=false  step_refines=false
LoopStrictSteps.allVars_card_le: LoopRel.weaken=false  step_refines=false
MintFreeRun.allVars_subset:      LoopRel.weaken=false  step_refines=false
no_growth_without_mint:  LoopRel.weaken=false  step_refines=false
```

(re-run after the operator connection: **22 roots, every one `false`**, including
`step_empty_makeEmptyE` and `emptyRemove_step`.)

**Every one false**, against round 1's `true` for six of the seven the reviewer tested.  The
brief's C1 acceptance ("`LoopRel.weaken` used nowhere in the `step` refinement") is now met in
the transitive sense, not the textual one.

## R2.3 — F5: §C3.2's localisation, corrected and PROVED

```lean
/-- **(i) `C \ K = ∅` is `C ⊆ K`, not `K = C`.** -/
theorem concCarried_of_conc_subset {G : System} {v z : Var} {C K : Row}
    (hv : mk v ∅ C ∈ G) (hz : mk z ∅ (∅ : Row) ∈ G) (hCK : C ⊆ K) : ConcCarried G v K

/-- **(ii) the parent-already-empty case, which round 1 missed entirely.** -/
theorem concCarried_parent_empty {G : System} {v : Var} (hv : mk v ∅ (∅ : Row) ∈ G) (K : Row) :
    ConcCarried G v K

theorem envEmpty_mem_qsys {s : State} {z : Nat} (h : (z, EnvVal.emptyRow) ∈ s.env.binds) :
    mk z ∅ (∅ : Row) ∈ qsys s

/-- **The mismatch, over `qsys`, in its corrected form.** -/
theorem qsys_concCarried_of_envEmpty {s : State} {v z : Nat} {C K : Row}
    (hv : mk v ∅ C ∈ qsys s) (hz : (z, EnvVal.emptyRow) ∈ s.env.binds) (hCK : C ⊆ K) :
    ConcCarried (qsys s) v K
```

So the residual (A)-gap over `qsys` is: **every key `K ⊇ C`** of every queue-visible parent
with concrete row `C`, once the environment holds one empty-row fact — and **every key at
all** when the parent is itself already empty.  C4's answer (that `-Dermine.emptyRow` closes
the gap) is unchanged in direction — the flag's `findEmptyRow` reads exactly those retained
facts — but it now rests on the corrected statement, and the second case is closed only by the
queue-hygiene invariant below.

## R2.4 — the queue-hygiene invariant, and why it is FALSE for the model as it stands

`L5-REVIEW.md` §5e names this as the second step to T1.  Stated, and with the two halves that
are provable proved:

```lean
/-- **Queue hygiene**: no partition of either queue is headed by, or mentions, a variable the
environment has already bound. -/
def QueueHygiene (s : State) : Prop :=
  ∀ p ∈ s.parts, ∀ v : Nat, s.env.contains v = true → p.involves v = false

/-- **Under queue hygiene the reinstantiation panic is unreachable.** -/
theorem queueHygiene_no_rebind {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) : s.env.contains r.lhs = false

/-- `selfSubstitution` EXCLUDES the variable it substitutes. -/
theorem selfSubstitution_excludes_self {ns : Names} {v : Nat} {a : SSet Nat} {c : SSet Lbl}
    {S : SSet LPart} (h : selfSubstitution ns v a c = .ok S) : ∀ y ∈ S.elems, y.lhs ≠ v

/-- **`makeEmpty`'s `aux` does NOT.** -/
theorem makeEmpty_aux_emits_self {L : List Lbl} (hcoh : LblCoh L) {v : Nat} {a : SSet Nat}
    (hself : a.contains v = true) :
    ∃ z ∈ (a.map (fun w => (⟨w, RHS.empty, some Inference.partitionEmpty⟩ : LPart))).elems,
      z.toConstraint = mk v ∅ (∅ : Row)
```

**`QueueHygiene` is FALSE for the model as it is**, and I did not change the model or any Scala,
as instructed.  The proof that it is false is §0's witness read through
`queueHygiene_no_rebind`: at base 6 the model (and the compiler) reaches a state whose dequeued
partition's left-hand side IS bound — that is what the panic reports — so `QueueHygiene` cannot
hold at that state.  `makeEmpty_aux_emits_self` and `selfSubstitution_excludes_self` are the
mechanism, side by side: the propagation emits `v <- ()` for the very variable being bound,
where the sister rule excludes it.

**Which lemma needs the compiler fix.**  `QueueHygiene` preserved by `step` is provable for
`instantiate` and `makeConcrete` (both filter every mention of the bound variable out of both
queues) and fails only at `makeEmpty`, and only through `aux`'s propagation.  With
`abstr.map` replaced by `(abstr - v).map` — the fix `L5-REVIEW.md` §6.4 recommends —
`makeEmpty_aux_emits_self` becomes unprovable and the `makeEmpty` case of `QueueHygiene.step`
goes through the same way as the other two.  **Under the hypothesis that no partition of either
queue is self-referential at `v` at the time of its `makeEmpty` — i.e. `¬ p.rhs.abstr.contains
p.lhs` for the dequeued `p` — the invariant is preserved for the model as it stands too**, and
that hypothesis is exactly what the fix would make unnecessary.  Neither preservation statement
is proved here; the two mechanism lemmas are.

## R2.5 — the smaller findings

* **F3 / F4** — §0 rewritten: the root cause is `makeEmpty`'s `aux`, not queue order, and the
  recommendation is the `aux` fix rather than uncommenting `Subst.scala:183`.  §5d's coupling
  (uncommenting invalidates `makeEmpty_env_len` and the `empty`/`common`/`unify` rows of
  §C3.4) is recorded there.
* **F6** — §C3.1's (B) table is now marked prose row by row, with the `makeEmpty` row's
  specific gap (`mk u {v} K ↦ mk u ∅ K` destroys a `Resolved` witness) spelled out.
* **F7** — the `conc1` probe's message is corrected in §C1.5.
* **F8** — README diff is +146/-0; the `Rowpartition.lean` diff is +8 because L3's five import
  lines were never staged; `split` liveness is 1.  All three corrected above.  The three
  `linter.style.header` warnings on `StrictBound.lean` remain (cosmetic, pre-existing style of
  the whole `Loop/` tree).
* **F9**, added as the reviewer asks: **the Lean model reproduces the panic at the IDENTICAL
  bases** — over 0..19 the model rejects at bases 6 and 13 and the compiler rejects at exactly
  those two; over 0..99 the compiler rejects at 11 bases.  That is a conformance data point at
  an input no corpus contains and belongs in L4's population notes.

## R2.6 — what round 2 does NOT do

| asked for (§10) | delivered | why not more |
|---|---|---|
| (1) constructors as the library operators; the vocabulary bound | **done**, and `Growth.lean` no longer elaborates; the `empty` branch is connected to `makeEmptyE` (`step_empty_makeEmptyE`) | the `common`/`unify` and `concrete` connections are not: `substOut` omits `replace`'s de-duplication fact and `concretizeSrs` has the `cancellation_bare` gap, so `instRemove` and `concRemove` stay declared-but-unapplied |
| (2) the strict refinement without `LoopRel.weaken` | **done**, verified with the reviewer's `Deps.lean` | — |
| (3) the queue-hygiene invariant proved, or its failure quantified | stated; the two mechanism lemmas proved; the failure demonstrated by §0's witness; PRESERVATION not proved, and it is FALSE for the model as it stands | it needs either the Scala fix or the stated non-self-reference hypothesis; both are recorded, neither is a model change, which the brief forbids |
| (4) §C3.2's localisation as a theorem over `qsys` | **done** (`qsys_concCarried_of_envEmpty`), in the corrected form | the (B) table's three rows are still prose, now marked as such |
| (5) F5-F9 in the report and the plan row | **done** | — |
| (6) the compiler bug handed over with the right root cause | **done** in §0 | no Scala change, as instructed |
| C1's `concrete` and `learn` branches | still open | unchanged from round 1: row 6 needs `subPartitions`/`destructiveSub`/`makeConcrete` backwards; the `learn` branch needs `RefineLearn.lean` re-proved against `LoopStrict`, which the no-edit rule turns into a 1,558-line duplication |
| C2, C3 (T1) | unchanged: C2 PARTIAL, C3 (T2) | round 2 was spent on F1 and F2, as specified |
