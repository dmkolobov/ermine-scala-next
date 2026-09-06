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

> **SUPERSEDED BY R4.1 and R4.3 (2026-09-05).**  The choice this section makes — take the
> measure over `qsys` — is refuted: ingredient (B) FAILS there, at an initial state
> (`qStepDichotomy_false`), and the potential rises (`qstep_pot_increases`).  So is the
> monotone alternative, where (B) is free and ingredient (A) fails
> (`histDichotomy_false`), and so is the intermediate carrier `sys` this section starts from
> (§R4.5, row "the carriers").  **All three natural carriers are refuted**; the table below
> should be read as a record of what was tried, not as a live choice.

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

> **PARTLY SUPERSEDED (2026-09-05).**  Row "C2 `SupOk`/`SupFresh` preserved" is now DONE
> (R4.2, `step_supFresh` / `runSupOk_of`).  Row "C3 `Terminates` with a bound" is still (T2),
> but its stated route — the measure over `qsys` — is refuted by R4.1, as is the monotone
> alternative by R4.3.

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

> **SUPERSEDED (2026-09-05).**  Row (3) below says `QueueHygiene` preservation "is FALSE for
> the model as it stands"; that was true of the UNFIXED `makeEmpty` and was superseded by
> round 3's `step_queueHygiene` after the B1 fix.  Round 4 removes the last hypothesis from
> its run-level form (`run_queueHygiene_of`, R4.2).  The round-3 review's S-9 item 5 asked
> for this note.

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

---

# Round 3 — 2026-09-05, after `L5-REVIEW.md`'s round-2 priority list

Fresh implementer, starting from the clean commit `52da5b8` in which the compiler bug that made
`QueueHygiene` false is fixed on both sides (`B1-FIX.md`).  Work order is the reviewer's round-2
priority list, R-4 first.  Five NEW modules,
`Rowpartition/Loop/{Carried,Hygiene,Factor,Draws,Residual}.lean`;
`Loop/{Strict,StrictStep,StrictBound}.lean` are **not edited**, so nothing rounds 1 and 2
proved is weakened or removed.  **Every Lean SIGNATURE quoted below is
byte-for-byte verbatim** (70 of 70, checked mechanically against the five modules — the
round-3 reviewer's own script agrees on 70); only the doc comments are shortened, and where one
is, the elision is marked.

| | before round 3 | after round 3 |
|---|---|---|
| `lake build Rowpartition` | 841 jobs | **846 jobs**, success |
| `lake env lean Audit.lean` | `3058; 0` | **`Rowpartition theorems audited: 3186; declarations using a non-standard axiom: 0`** |
| new-module lines | — | `Carried.lean` 413 + `Hygiene.lean` 1,505 + `Factor.lean` 466 + `Draws.lean` 275 + `Residual.lean` 262 = **2,921** |
| `sorry` / `axiom` / `partial` / `native_decide` / `Classical` / `unsafe` / `opaque` / `admit` | — | **0 in all five new modules** |
| `#print axioms`, 49 headlines (`tmp/L5r3/Axioms.lean`) | — | 49 × `[propext, Classical.choice, Quot.sound]`; **no non-standard axiom** |
| files touched | — | five NEW `Loop/` modules; `Rowpartition.lean` +5 import lines; `tracker/lean/README.md` +34/−0 (additive); the plan's L5 row; this report |

## R3.1 — R-4: a `Carried`-preserving licence, `carried_step`, and what it buys

**Outcome: `carried_step` is PROVED for the seven constructors that can have it (four more close
vacuously under `¬ IsMint`, three are passed through as hypotheses); the loop's `common`/`unify`
re-emissions provably CANNOT be given the conjunct over `sys`, which is a new negative result and
the reason the measure has to move to `qsys`.  What the conjunct then buys along the new relation
is a VOCABULARY SNAPSHOT bound, not a mint count — see the correction in R3.1.4.**

### R3.1.1 The predicate, and what it buys (`Loop/Carried.lean` §1)

```lean
/-- **`G'` keeps every key `G` carries.** -/
def CarrPres (G G' : System) : Prop := ∀ w K, Carried G w K → Carried G' w K

/-- The relativised form: only the variables the successor still HAS need keep their keys. -/
def CarrPresOn (G G' : System) : Prop :=
  ∀ w ∈ allVars G', ∀ K, Carried G w K → Carried G' w K

/-- Preservation at every variable BUT `v`. -/
def CarrPresOff (v : Var) (G G' : System) : Prop :=
  ∀ w, w ≠ v → ∀ K, Carried G w K → Carried G' w K

theorem CarrPresOn.hmeas_le {L : Finset Label} {G G' : System} (rho : Assign)
    (hAV : allVars G' ⊆ allVars G) (h : CarrPresOn G G') :
    hmeas L rho G' ≤ hmeas L rho G
```

### R3.1.2 `substOut`, the operator the library had no `Carried` lemma for

`KeyedEmpty.carried_makeEmptyE` and `KeyedRow.carried_concretizeSrs` are the library's; round 2's
`substOut` had none.  This is the FULL truth about it — preservation off the eliminated variable,
and failure at it:

```lean
/-- **`substOut` preserves `Carried` at every variable but the one it eliminates.** -/
theorem carried_substOut_of_ne {G : System} {v u w : Var} {K : Row} (hw : w ≠ v)
    (h : Carried G w K) : Carried (substOut v u G) w K

theorem carrPresOff_substOut (v u : Var) (G : System) : CarrPresOff v G (substOut v u G)

/-- **After an elimination, the eliminated variable carries only the empty key.** -/
theorem carried_iff_of_link_only {G : System} {v u : Var} {K : Row}
    (h : ∀ c ∈ G, c.lhs = v → c = mk v {u} (∅ : Row)) (hc : Carried G v K) : K = ∅

/-- **`substOut` does NOT preserve `Carried` at the variable it eliminates.** -/
theorem substOut_breaks_carried :
    ∃ (G : System) (v u : Var) (K : Row), mk v {u} (∅ : Row) ∈ G ∧
      Carried G v K ∧ ¬ Carried (substOut v u G) v K

/-- **`Carried` is not monotone under deletion**, so `drop` needs the licence too. -/
theorem carried_not_monotone_under_deletion :
    ∃ (G G' : System) (w : Var) (K : Row), G' ⊆ G ∧ Carried G w K ∧ ¬ Carried G' w K
```

`substOut_breaks_carried`'s witness is `GA = {v0 <- (v1), v0 <- ((|l5|)), v2 <- ()}` at the key
`(v0, {l5})`: before the step `v0`'s own concrete definition and `v2 <- ()` carry it; after
`instantiate(v0 := v1)` the definition reads `v1 <- ((|l5|))` and the ONLY constraint left about
`v0` is the retained link, which `carried_iff_of_link_only` shows carries `∅` and nothing else.
**This is `§C3.1`'s table row 1 — "(B) fails for `sys s` at `instantiate`" — as a theorem rather
than as prose, and it settles R-4's first half NEGATIVELY**: no `Carried`-preserving conjunct can
be discharged at the loop's `common` and `unify` branches over `sys`, because after those steps
`sys s'` contains exactly one constraint about the eliminated variable and it is the alias link.

### R3.1.3 `carried_step` — the ingredient (B) of §C3.1, and exactly what it covers

```lean
/-- **`carried_step`.**  (doc comment elided; it now tabulates the fourteen cases -- seven
proved, four vacuous, three passed through.) -/
theorem LoopStrict.carried_step {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : LoopStrict G G') (hmint : ¬ IsMint G G')
    (hdrop : G' ⊆ G → CarrPres G G')
    (hinst : (∃ v u : Var, G' = substOut v u G) → CarrPres G G')
    (hreq : allVars G' ⊆ allVars G → Conserv G G' → NoLoss G G' → CarrPres G G') :
    CarrPres G G'

/-- **A non-minting `LoopStrict` step keeps the model it started with.** -/
theorem LoopStrict.models_of_notMint {G G' : System} {rho : Assign} (h : LoopStrict G G')
    (hmint : ¬ IsMint G G') (hmod : SModels rho G) : SModels rho G'
```

**How the fourteen cases divide** (corrected after the round-3 review's F-1, which counted them
against the proof — the first draft of this paragraph said "nine … by additivity" and "the other
ten need nothing beyond a model", and both were wrong):

| how discharged | constructors | count |
|---|---|---|
| additivity (`CarrPres.of_subset`) | `nongen`, `renameLhs`, `linkSymm`, `emptyProp`, `dedup` | 5 |
| a library `Carried` lemma | `emptyRemove` (`KeyedEmpty.carried_makeEmptyE`), `concRemove` (`KeyedRow.carried_concretizeSrs`) | 2 |
| **vacuous** — `absurd … hmint`, since these four ARE `IsMint` | `split`, `res`, `splitFree`, `kres` | 4 |
| **licence assumed** (`hdrop`, `hinst`, `hreq`) | `drop`, `instRemove`, `requeue` | 3 |

So `carried_step` proves something at **seven** constructors, closes four VACUOUSLY under
`¬ IsMint`, and passes three through as hypotheses.  The two library lemmas are the only reason
it needs a MODEL rather than `SSat`.  For the three passed through, `substOut_breaks_carried`,
`carried_not_monotone_under_deletion` and `L5-REVIEW.md`'s `requeue_breaks_carried` show that
none of them can be discharged — which is the point of isolating them.

### R3.1.4 What (B) buys: a VOCABULARY SNAPSHOT bound (NOT a mint count)

```lean
/-- The potential `KeyedRow`'s bound is stated with. -/
def Pot (L : Finset Label) (rho : Assign) (G : System) : ℕ :=
  (allVars G).card + hmeas L rho G

/-- **A run of carried-preserving `LoopStrict` steps and keyed mints, with the mints counted.** -/
inductive LoopStrictKRun (L : Finset Label) : ℕ → System → System → Prop
  | refl (G : System) : LoopStrictKRun L 0 G G
  | keep {n : ℕ} {G₀ G G' : System} :
      LoopStrictKRun L n G₀ G → LoopStrict G G' → ¬ IsMint G G' →
      allVars G' ⊆ allVars G → ConcSub L G' → CarrPresOn G G' →
      LoopStrictKRun L n G₀ G'
  | mint {n : ℕ} {G₀ G G' : System} :
      LoopStrictKRun L n G₀ G → K2StarStep G G' → LoopStrictKRun L (n + 1) G₀ G'

theorem LoopStrictKRun.toRun {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : LoopStrictKRun L n G₀ G) : LoopStrictRun G₀ G

/-- **The invariant that drives the bound.** -/
theorem LoopStrictKRun.invariant {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : LoopStrictKRun L n G₀ G) :
    ∀ rho₀ : Assign, SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧ ConcSub L G ∧ Pot L rho G ≤ Pot L rho₀ G₀

/-- **THE VOCABULARY SNAPSHOT BOUND for the carried-preserving fragment.** -/
theorem LoopStrictKRun.allVars_card_le {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : LoopStrictKRun L n G₀ G) (rho : Assign) (hm : SModels rho G₀) (hcs : ConcSub L G₀) :
    (allVars G).card ≤ (allVars G₀).card + hmeas L rho G₀

theorem LoopStrictKRun.vocab_snapshot_bound {G₀ : System} (rho : Assign) (hm : SModels rho G₀) :
    ∀ (n : ℕ) (G : System), LoopStrictKRun (labelsOf G₀) n G₀ G →
      (allVars G).card ≤ (allVars G₀).card + hmeas (labelsOf G₀) rho G₀
```

This is `KeyedRow.mintsBoundedOnSatKeyed2Star` extended to arbitrary `LoopStrict` steps that keep
every carried key and name no new variable or label — i.e. it is exactly what ingredient (B) is
for.  The mints it interleaves are the KEYED ones (`K2StarStep` = `NonGenStep` ∪ `K2SplitStep` ∪
`K2ResStep`), which is what the shipped `splitKey`/`splitRow`/`resGuard`/`resRow` select;
`Cut.ResStep` and `Cut.SplitStep`, the unguarded mints `LoopStrict` also carries, are
deliberately outside it.

> **CORRECTED after the round-3 review (F-2, machine-checked).**  The first draft of this
> section called these theorems "THE MINT BOUND" and said they "bound the number of mints as
> well".  **They do not.**  `n` does not occur in either conclusion, and the reviewer proved
> `mints_not_bounded`: from a fixed satisfiable `G₀`, `LoopStrictKRun` reaches every `n` with
> the vocabulary bound holding.  Two reasons, both structural: `LoopStrictKRun.mint` carries no
> productivity side condition where the library's `K2StarLoopRun.tail` carries `G ≠ G'` (and
> `K2StarStep` contains the NON-generative `NonGenStep`, so a counted step need not change
> anything); and `LoopStrictKRun.keep` permits `allVars G' ⊊ allVars G`, so a minted variable
> can leave again.  The library's card bound bounds its mint count only because its systems grow
> monotonically; this relation's do not.  **What is proved is a bound on the vocabulary HELD AT
> ONE STATE, not on the number of minting steps** — and bounding the latter is an explicit open
> item (R3.5.4), not a corollary of this.  I have not weakened the theorems: they are correct as
> written, and only the surrounding claims were wrong.

**Where the reviewer's acceptance stands.**  R-4 asked that `requeue_breaks_carried` become
unprovable.  For `LoopStrictKRun`'s `keep` steps it IS unprovable, by construction.  It could not
be made unprovable for `LoopStrict` itself without either weakening or deleting
`step_strict_common`, `step_strict_empty` and `step_strict_unify` — all three go through
`requeue`, and R3.1.2 shows two of them cannot be given the conjunct at all.  I did not weaken
them; `LoopStrict` is byte-identical to round 2.

## R3.2 — `step_empty_makeEmptyE` load-bearing, and `instRemove` live

**Outcome: BOTH DONE, without editing `Loop/Strict.lean`.**  (`Loop/Factor.lean`.)  The pattern
is the same in each case: the operator's output `H` sits between `sys s` and `sys s'`,
`LoopStrict (sys s) H` is the operator constructor, and `LoopStrict H (sys s')` is one
`requeue` whose three clauses are COMPOSED out of what round 2 already proved
(`step_noLoss_strict`, `step_conserv_strict`, `step_allVars_strict`) with the operator's own
soundness.  The one genuinely new ingredient is the operators' vocabulary EQUALITIES — the
library and round 2 had only the ⊆ direction, and the composition needs ⊇:

```lean
/-- **Under a model, `v <- ()` forces every definition of `v` to be label-free.** -/
theorem defs_conc_empty_of_sat {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hsat : SSat G) : ∀ c ∈ G, c.lhs = v → c.conc = ∅

/-- **`makeEmptyE` keeps every variable.** -/
theorem allVars_makeEmptyE_supset {G : System} {v : Var} (_hshape : MkShaped G)
    (_hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    allVars G ⊆ allVars (makeEmptyE v G)

theorem allVars_makeEmptyE_eq {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    allVars (makeEmptyE v G) = allVars G

/-- **`substOut` keeps every variable too.** -/
theorem allVars_substOut_supset {G : System} {v u : Var} (_hlink : mk v {u} (∅ : Row) ∈ G) :
    allVars G ⊆ allVars (substOut v u G)

theorem allVars_substOut_eq {G : System} {v u : Var} (hlink : mk v {u} (∅ : Row) ∈ G) :
    allVars (substOut v u G) = allVars G
```

`defs_conc_empty_of_sat` replaces a re-run of `makeEmpty_defs_conc_empty`'s fold: under a model,
`v <- ()` forces every definition of `v` to have an empty concrete part, which is the `die` arm
read semantically, and satisfiability is the hypothesis a termination argument has anyway.

### R3.2(a) the `empty` branch

```lean
/-- **`step_empty_makeEmptyE`, made LOAD-BEARING.** -/
theorem step_empty_via_makeEmptyE {s s' : State} (hw : Wf s) (hsat : SSat (sys s))
    {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hem : r.rhs.isEmpty = true) (h : step s = .continue s') :
    LoopStrict (sys s) (makeEmptyE r.lhs (sys s)) ∧
      LoopStrict (makeEmptyE r.lhs (sys s)) (sys s') ∧
      LoopStrictRun (sys s) (sys s')
```

`step_empty_makeEmptyE` is no longer a leaf: it is the first conjunct, and the third conjunct
composes it with the `requeue` that reaches `sys s'`.  One premise is new relative to round 2's
`step_empty_makeEmptyE`: `hsat : SSat (sys s)`, needed for `allVars_makeEmptyE_eq` through
`defs_conc_empty_of_sat`.  It is harmless — satisfiability is the setting of the whole C3
argument — but it is a strengthening and is flagged here (round-3 review, N-3).  The factoring
also does not REMOVE the trailing `requeue`: `LoopStrict H (sys s')` is still one
semantically-licensed requeue, and `step_refines_strict`, the acceptance criterion, still runs
through the bare one.

### R3.2(b) `replace`'s de-duplication fact, and `instRemove` LIVE

`substOut` collapses the parts `v` and `u` of a constraint that mentions both, so it loses a
fact — unless the system also knows `u <- ()`, which is exactly the partition
`Constraints.replace` emits in that case.  Two observations make `instRemove` live WITHOUT
touching `Loop/Strict.lean` (so round 2's `LoopStrict` is byte-identical):

```lean
/-- Some constraint mentions both `v` and `u`: the case `replace` de-duplicates. -/
def NeedsDedup (v u : Var) (G : System) : Prop := ∃ c ∈ G, v ∈ vset c ∧ u ∈ vset c

/-- **`instantiate`'s removal WITH `replace`'s de-duplication fact.** -/
def substOutD (v u : Var) (G : System) : System := substOut v u (insert (mk u ∅ (∅ : Row)) G)

/-- **The de-duplication fact is a CONSEQUENCE.** -/
theorem dedup_entailed {G : System} {v u : Var} (hshape : MkShaped G) (hvu : v ≠ u)
    (hlink : mk v {u} (∅ : Row) ∈ G) (hnd : NeedsDedup v u G) :
    SEntails G (mk u ∅ (∅ : Row))

/-- **When nothing collapses, `substOut` loses nothing.** -/
theorem substOut_noLoss_of_disjoint {G : System} {v u : Var} (hshape : MkShaped G)
    (_hlink : mk v {u} (∅ : Row) ∈ G) (hnd : ¬ NeedsDedup v u G) :
    NoLoss G (substOut v u G)

/-- **With the de-duplication fact present, `substOut` loses nothing.** -/
theorem substOut_noLoss_of_dedup {G : System} {v u : Var} (hshape : MkShaped G)
    (_hlink : mk v {u} (∅ : Row) ∈ G) (hdd : mk u ∅ (∅ : Row) ∈ G) (hvu : v ≠ u) :
    NoLoss G (substOut v u G)

/-- **`instRemove` is LIVE**, in the case where nothing collapses. -/
theorem instRemove_step {G : System} {v u : Var} (hshape : MkShaped G)
    (hlink : mk v {u} (∅ : Row) ∈ G) (hnd : ¬ NeedsDedup v u G) :
    LoopStrict G (substOut v u G)

/-- **`instRemove` is LIVE**, in the case where the de-duplication fact is needed. -/
theorem instRemove_step_dedup {G : System} {v u : Var} (hshape : MkShaped G) (hvu : v ≠ u)
    (hlink : mk v {u} (∅ : Row) ∈ G) (hnd : NeedsDedup v u G) :
    LoopStrictRun G (substOutD v u G)
```

The second is the point: the missing `u <- ()` is not an extra axiom, it is a CONSEQUENCE of
the link and the disjointness of the constraint that mentions both, so the run adds it with
`LoopStrict.dedup` — the constructor that stands for `RHS.merge`'s returned `es` and
`replace`'s two-element queue — and then `instRemove` applies.  And at the loop:

```lean
/-- **The `unify` branch's transition, factored.** -/
theorem step_unify_via_substOut {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    {u : Nat} (hdq : s.incm.dequeue = some (r, rest)) (_hfr : s.proc.findRHS r.rhs = none)
    (hsg : r.rhs.single? = some u) (hur : u ≠ r.lhs) (h : step s = .continue s') :
    ∃ H : System, LoopStrictRun (sys s) H ∧ LoopStrict H (sys s') ∧
      allVars H = allVars (sys s) ∧
      (H = substOut u r.lhs (insert (mk u {r.lhs} (∅ : Row)) (sys s)) ∨
        H = substOutD u r.lhs (insert (mk u {r.lhs} (∅ : Row)) (sys s)))
```

The `common` branch is factored the same way, with one extra step at the front: there the link
`r.lhs <- (u)` is not in `sys s` (it is only ENTAILED, from `r` and the `proc` partition with
the same right-hand side), so the run takes a `NonGenStep.commonPart` step first —
`step_common_via_substOut`, stated with the constructor table below.

### The constructor-use table

Counted mechanically (`grep -o "LoopStrict\.<ctor>"` per file):

| constructor | Strict | StrictStep | Carried | Factor | total | round 2 |
|---|---|---|---|---|---|---|
| `nongen` | 1 | | 1 | 1 | 3 | 1 |
| `split` | 1 | | 1 | | 2 | 2 |
| `res` | 1 | | | | 1 | 1 |
| `splitFree` | 1 | | | | 1 | 1 |
| `kres` | 1 | | 1 | | 2 | 1 |
| `renameLhs` | 1 | | | | 1 | 1 |
| `linkSymm` | 1 | | | 1 | 2 | 1 |
| `emptyProp` | 1 | | | | 1 | 1 |
| `dedup` | 1 | | | 3 | 4 | 1 |
| `drop` | | 2 | | | 2 | 2 |
| **`instRemove`** | | | | **2** | **2** | **0** |
| `emptyRemove` | 1 | | | | 1 | 1 |
| **`concRemove`** | | | | | **0** | **0** |
| `requeue` | | 4 | | 4 | 8 | 4 |

**13 of 14 live** (round 2: 12 of 14).  `concRemove` is the only one still declared and never
applied, for the reason round 1 gave and round 3 does not change: its `NoLoss` premise is the
`cancellation_bare` gap, and the `concrete` branch is not refined at all.

`instRemove` is applied inside `instRemove_step` and `instRemove_step_dedup`, and those two are
used at BOTH link branches of the loop — `step_unify_via_substOut` and
`step_common_via_substOut`.  The `common` branch needed one extra step, which is the third
`nongen` above: the link `r.lhs <- (u)` is not in `sys s` there, it is what
`NonGenStep.commonPart` derives from the dequeued `r` and the `proc` partition `findRHS`
matched (`step_common_via_substOut`, added after the first draft of this section):

```lean
/-- **The `common` branch's transition, factored.** -/
theorem step_common_via_substOut {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    {u : Nat} (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some u)
    (hru : r.lhs ≠ u) (h : step s = .continue s') :
    ∃ H : System, LoopStrictRun (sys s) H ∧ LoopStrict H (sys s') ∧
      allVars H = allVars (sys s) ∧
      (H = substOut r.lhs u (insert (mk r.lhs {u} (∅ : Row)) (sys s)) ∨
        H = substOutD r.lhs u (insert (mk r.lhs {u} (∅ : Row)) (sys s)))
```

**So all three of `step_refines_strict`'s branches are now factored through the LIBRARY
OPERATORS**: `empty` through `makeEmptyE`, `common` and `unify` through `substOut`/`substOutD`.
Round 2's bare `requeue`s are still there — they are the shorter statement of the same step —
but they are no longer the only route.

## R3.3 — `QueueHygiene` preserved by `step`, and the panic unreachable

**Outcome: PROVED, for all five dispatch branches, with `disjunction` (shipped OFF) excluded at
the `learn` branch exactly as `RefineLearn.step_refines_all` excludes it.  This is the theorem
that certifies the B1 fix.**  (`Loop/Hygiene.lean`; taken before R3.2 and R3.4 because it is the
lemma `L5-REVIEW.md` §5e names as the second step to T1 and the one `B1-FIX.md` §5a leaves open.)

The mechanism is one predicate run through round 2's own forward machinery:

```lean
/-- **`c` mentions no variable of `B`.** -/
def Avoids (B : Var → Prop) (c : Constraint) : Prop :=
  ¬ B c.lhs ∧ ∀ w ∈ vset c, ¬ B w

theorem redClosed_avoids (B : Var → Prop) : RedClosed (Avoids B)

/-- **The bridge to `QueueHygiene`'s `involves`.** -/
theorem notInvolves_iff_avoids {p : LPart} {v : Nat} :
    p.involves v = false ↔ Avoids (fun w => w = v) p.toConstraint

/-- The predicate `QueueHygiene` is stated at. -/
def Bound (e : Env) (v : Var) : Prop := e.contains v = true

theorem queueHygiene_iff {s : State} :
    QueueHygiene s ↔ ∀ p ∈ s.parts, Avoids (Bound s.env) p.toConstraint
```

with `Env.contains_iff` and `Env.contains_instantiate` (`(e.instantiate v val).contains w = true
↔ e.contains w = true ∨ w = v`) as the environment's side.

### The five branches, as separate theorems

```lean
/-- `Q.+!`, INCLUDING its `CommonPartition` redirect. -/
theorem insertP_avoids {B : Var → Prop} {q : PQueue} {p x : LPart}
    (hq : ∀ y ∈ q.elems, Avoids B y.toConstraint) (hp : Avoids B p.toConstraint)
    (h : x ∈ (q.insertP p).elems) : Avoids B x.toConstraint

theorem makeEmpty_avoids {B : Var → Prop} {ns : Names} {v : Nat} {incm proc : PQueue}
    {env : Env} {ni np : PQueue} {e : Env}
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint) ∧
      (∀ x ∈ np.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint)

theorem instantiate_avoids {B : Var → Prop} {ns : Names} {v u : Nat} {incm proc : PQueue}
    {env : Env} {ni np : PQueue} {e : Env} (hvu : v ≠ u) (hu : ¬ B u)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint) ∧
      (∀ x ∈ np.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint)

theorem makeConcrete_avoids {B : Var → Prop} {v : Nat} {fs : SSet Lbl} {incm proc : PQueue}
    {ni np : PQueue} (hv : ¬ B v)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    (∀ x ∈ ni.elems, Avoids B x.toConstraint) ∧ (∀ x ∈ np.elems, Avoids B x.toConstraint)

theorem learnPartitions_avoids {B : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false)
    (hok : SupOk su) (hsu : SupAvoids B su) (hv : ¬ B v)
    (hr1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint
```

with a per-rule lemma for each of the seven rules (`selfSubstitution_avoids`,
`splitConcrete_avoids`, `cancellation_avoids`, `resolution_avoids`, `subBody_avoids`,
`substitution_avoids`, `commonSubexpression_avoids`, `disjunction_avoids`), a lemma for each
reverse lookup (`findRHS_avoids`, `findRHS3_avoids`, `findResolvent_avoids`,
`findConcRow_avoids`, `mkLookups_avoids`), and the supply side:

```lean
/-- No id the supply can still hand out is bound. -/
def SupAvoids (B : Var → Prop) (su : Sup) : Prop := ∀ z, Sup.Reach su z → ¬ B z

theorem supAvoids_of_supFresh {su : Sup} {G : System} (h : SupFresh su G) {B : Var → Prop}
    (hB : ∀ v, B v → v ∈ allVars G) : SupAvoids B su
```

### The headline

```lean
/-- **`QueueHygiene` is preserved by every `continue` step.** -/
theorem step_queueHygiene {s s' : State} (hdj : s.flags.disjRule = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (h : step s = .continue s') : QueueHygiene s'

/-- The brief's name for the theorem above. -/
theorem QueueHygiene.step {s s' : State} (hdj : s.flags.disjRule = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (h : Rowpartition.Loop.step s = .continue s') : QueueHygiene s'

/-- **Every initial state is hygienic**: `Seed`/`Replay` start with an EMPTY environment. -/
theorem queueHygiene_of_env_nil {s : State} (h : s.env.binds = []) : QueueHygiene s

theorem queueHygiene_initial {q : PQueue} (fl : Flags) (ns : Names) (site : String) (su : Sup)
    (lo : Nat) (t : List String) :
    QueueHygiene { incm := q, proc := PQueue.empty, env := {}, su := su, trace := t,
                   flags := fl, names := ns, site := site, su0 := lo }

/-- **Hygiene holds at every state a run reaches.** -/
theorem run_queueHygiene : ∀ (n : Nat) {s : State}, s.flags.disjRule = false → RunSupOk n s →
    QueueHygiene s → ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → QueueHygiene s'

/-- A `died` step changes nothing but the trace, so hygiene survives a REFUTATION too. -/
theorem step_died_parts {s s' : State} {m : String} (h : Rowpartition.Loop.step s = .died m s') :
    s'.parts = s.parts ∧ s'.env = s.env

/-- **Hygiene holds at every state a run reaches, refutations included.** -/
theorem run_queueHygiene' : ∀ (n : Nat) {s : State}, s.flags.disjRule = false → RunSupOk n s →
    QueueHygiene s → ∀ s' m, run s n = .rejected m s' → QueueHygiene s'

/-- **The reinstantiation panic is unreachable from a hygienic state.** -/
theorem queueHygiene_binds_unbound {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) :
    s.env.contains r.lhs = false ∧
      (∀ u, r.rhs.abstr.contains u = true → s.env.contains u = false) ∧
      (∀ u, s.proc.findRHS r.rhs = some u → s.env.contains u = false)
```

The three conjuncts of `queueHygiene_binds_unbound` are exactly the three variables a `step` can
bind — the dequeued left-hand side (`makeEmpty` at `empty`, `instantiate` at `common`), its lone
variable part (`instantiate` at `unify`) and the `common` partner — which is the condition
`Subst.instantiateType`'s `die` tests.  Together with `queueHygiene_initial` and
`run_queueHygiene` this closes `B1-FIX.md`'s open item — **conditionally, and the condition is
worth stating plainly (round-3 review, Q-1):**

> `run_queueHygiene` and `run_queueHygiene'` carry `RunSupOk n s`, which
> `RefineLearn.lean:1499` defines as `SupOk` and `SupFresh` AT EVERY STATE of the run.  L3's own
> row records that this is a per-state HYPOTHESIS, not an invariant, and round 3 does not
> discharge it (R3.4: that needs C2's sharp vocabulary clause, which is exactly what
> `learnPartitions_vocab` does not give).  So **"the reinstantiation panic has no path from an
> initial state" is conditional on `RunSupOk` and on `disjRule = false`.**  The single-step
> theorem `step_queueHygiene` carries only the single-state `SupOk`/`SupFresh`, which every
> replay state satisfies; it is the RUN-level statement that needs the unproved per-state form.
> Q-2, also worth recording: `queueHygiene_initial` is stated for the state literal
> `Seed.solve` builds (`env := {}`), which is "every state the seed loader builds", not "every
> `Wf` initial state" — `Wf` is `QOk` plus `LblCoh` and says nothing about `env`; and there is
> no single assembled corollary of the shape `run st0 n ≠ .rejected (panic …) s'`, the reader
> composes `queueHygiene_initial` + `step_queueHygiene` + `queueHygiene_binds_unbound`.

Before B1 the invariant was false outright (round 2, §R2.4), so this is still the theorem that
certifies the fix; what is conditional is only its run-level reach.  In its sharpest form:

```lean
/-- `instantiate`'s ONLY error is the reinstantiation panic. -/
theorem instantiate_ok_of_unbound {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    (h : env.contains v = false) :
    ∃ ni np, instantiate ns v u incm proc env
      = .ok (ni, np, env.instantiate v (.alias u))

/-- **At a hygienic state neither link branch can die.** -/
theorem step_link_no_death {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) :
    (∀ u, s.proc.findRHS r.rhs = some u →
        ∃ w, unifyVars s.names r.lhs u rest s.proc s.env = .ok w) ∧
      (∀ u, r.rhs.single? = some u →
        ∃ w, unifyVars s.names u r.lhs rest s.proc s.env = .ok w)
```

**Where the B1 fix is load-bearing, exactly.**  In `makeEmpty_avoids`'s propagation case the
emitted `w` must satisfy `w ≠ v`, and the only reason it does is that the fold ranges over
`p.rhs.abstr.excl v` — the `(abstr - v)` of `B1-FIX.md` §5.  With `abstr` in its place that case
is false, and with it `makeEmpty_avoids`, `step_queueHygiene`, `run_queueHygiene` and the
corollary.  Nothing else in the proof changes between the two versions.

**Scope.**  `learnPartitions_avoids` carries `fl.disjRule = false`.  The RULE is fine —
`disjunction_avoids` is proved — but its two call sites are inner folds over `proc` whose
plumbing would roughly double the proof for a branch the plan's "Known scope limits" already
scopes to seeds, and which `RefineLearn.step_refines_all` excludes by the same hypothesis.  No
other flag is assumed: `emptyRow` and `cseMints` are handled in both settings.

## R3.4 — the `concrete` and `learn` branches, and C2

**Outcome: NOT DONE for the two branches; the quantitative half of C2 is PROVED.**

### The two branches: what stops them, stated plainly

* **`learn`.**  `step_learn_sys_mono` gives `sys s ⊆ sys s'`, so the step is purely additive on
  `sys`, and `LoopStrict.of_rel` converts every ADDITIVE `LoopRel` step into a `LoopStrictRun`.
  So the transfer is mechanical IF the learn branch's `LoopRun` is presented as a chain of
  `Adds`-steps.  It is not: `RefineLearn.lean` threads it through `RuleRun`, whose first
  component is a bare `LoopRun`, and whose producers (`subst_one_run`, `subBody_run`, the five
  minting-rule runs) build that `LoopRun` from lemmas that do not record additivity.  Making
  the transfer would mean changing `RuleRun` to carry both runs and re-proving its 20-odd
  producers — a 1,558-line edit that I judged not worth doing before `qsys` is settled, since
  the `learn` branch is where the MINTS are and the mint side of the bound is the `qsys`
  question, not the refinement question.  Recorded as NOT DONE, not attempted.
* **`concrete`.**  Unchanged from rounds 1 and 2: `concRemove`'s `NoLoss` premise is the
  `cancellation_bare` gap (§C1.5), so the constructor cannot be applied to `sys s` at all, and
  the backwards reading through `subPartitions`/`destructiveSub`/`makeConcrete` was not written.

So `step_refines_strict` still covers three of five branches, and the plan's acceptance clause
"every `step` refines it under the same hypotheses as `step_refines_all`" still FAILS.

### C2's question, answered: how many ids a `learn` step draws (`Loop/Draws.lean`)

```lean
theorem fresh_drawn (su : Sup) : (su.fresh).2.drawn = su.drawn + 1

/-- `splitConcrete` draws at most one id, in its final branch. -/
theorem splitConcrete_drawn {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2.drawn
      ≤ su.drawn + 1

/-- `resolution` draws at most one id -- taken BEFORE the guards, so a reuse costs one too. -/
theorem resolution_drawn {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2.drawn ≤ su.drawn + 1

/-- Under `genRules=cut` -- the shipped setting -- `commonSubexpression` draws NOTHING. -/
theorem commonSubexpression_no_draw {fl : Flags} {v : Nat} {rhs1 : RHS} {u : Nat} {rhs2 : RHS}
    {rhss : RHS → Option Nat} {su : Sup} (hcse : fl.cseMints = false) :
    (commonSubexpression fl v rhs1 u rhs2 rhss su).2 = su

/-- **How many ids a `learn` step draws.** -/
theorem learnPartitions_drawn {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    su'.drawn ≤ su.drawn + 1 + proc.elems.length
```

**The answer: at most `1 + |proc|` ids per `learn` step under the shipped flags** — one for
`splitConcrete` at the top, and at most one per PROCESSED partition, only through `resolution`,
whose `fresh` is drawn BEFORE its guards (so a reuse costs an id too; that is what makes the
`e00346` seed draw 1,033 ids from twelve constraints).  With `-Dermine.disjunction` on the
bound is false: each `disjunction` call draws one or two more and there are two nested folds
over `proc` per step.  `selfSubstitution` draws nothing (the whole branch returns `su`).

**C2's vocabulary clause itself is NOT delivered** (round-3 review, F-4).  What is proved is
`learnPartitions_vocab`, whose conclusion is `x.lhs ∈ V ∨ Sup.Reach su x.lhs` — "in the old
vocabulary, or ANY id the supply can ever hand out".  C2 needs "…, or one of the ids THIS step
actually drew"; the weaker clause cannot preserve `SupFresh`, since `Sup.Reach su` is the whole
tail of the supply and not just the consumed prefix.  `learnPartitions_drawn` counts the drawn
ids, so the two halves exist and the strengthening that intersects them is one lemma away — but
it is not written, and therefore:

> **`SupOk`/`SupFresh` preserved by `step` — so that `RunSupOk` becomes a theorem rather than a
> per-state hypothesis — is NOT delivered by round 3.**  This is the same gap that makes
> R3.3's run-level statement conditional (Q-1), and the round-3 review makes it the
> highest-value-per-line item left.  `Loop/Hygiene.lean` does prove the
predicate-level half of that clause for every rule (`splitConcrete_avoids`,
`resolution_avoids`, `commonSubexpression_avoids`, `substitution_avoids`,
`disjunction_avoids`, `selfSubstitution_avoids`, `cancellation_avoids`), so the ingredients
exist; assembling them into `SupFresh` was not done.

## R3.5 — the bound: **(T2) with the exact remaining lemma**

> **SUPERSEDED BY R4.1 (2026-09-05).**  The "exact remaining lemma" this section nominates,
> `QStepDichotomy`, is **FALSE** — `Refuted.qStepDichotomy_false`, at an INITIAL state of a
> satisfiable three-constraint input, and `qStepDichotomy_labelsOf_false` at the very pool
> `run_qsys_bound` is stated with.  Everything proved below remains true as written
> (`run_qsys_invariant`, `run_qsys_allVars_card_le`, `run_qsys_bound` are theorems), but their
> hypothesis is now known to be unsatisfiable, so they bound nothing.  R4.1 also proves the
> POTENTIAL this section propagates strictly increases at that step
> (`qstep_pot_increases`), so no repair of the dichotomy that keeps `Pot` over `qsys` can
> hold, and the relativisation to reachable states is refuted too (`qStepDichotomy'_false`).
> Read §R4.1 before relying on anything in §R3.5.

**Outcome: T2.**  Not T1 — the remaining lemma is named below and is not proved, and even with
it what follows is a SNAPSHOT bound on the queue-visible vocabulary, not a mint count (R3.5.4)
and not `Terminates`.  Not W — the new witness hunt is 20,720 runs with 0 `FUEL`, 20,000 of them
aimed at exactly the two configurations this round proves destroy the syntactic guard (R3.5.3).

### R3.5.1 What round 3 changes about the shape of the obstacle

Round 2 left "(A) fails at the parent-concrete keys; (B) is unavailable because `requeue`'s
licence is semantic".  Round 3 replaces both halves with something sharper:

* **(B) is now AVAILABLE as a relation-level result.**  `LoopStrict.carried_step` proves
  `Carried`-preservation for every constructor that can have it, and
  `LoopStrictKRun.allVars_card_le` turns that into the vocabulary SNAPSHOT bound
  `|allVars G| ≤ |allVars G₀| + hmeas L rho G₀` at every state of any run of carried-preserving
  steps and KEYED mints.  So the relation side of ingredient (B) is done — but the snapshot is
  not a mint count (R3.5.4).
* **(B) is now provably UNAVAILABLE for the loop over `sys`, and the reason is exact.**  There
  are three distinct destroyers of the syntactic guard, each machine-checked:
  `substOut_breaks_carried` (the alias elimination retains `v <- (u)`, and
  `carried_iff_of_link_only` says a variable whose only constraint is its alias link carries
  the key `∅` and no other); `carried_not_monotone_under_deletion` (any `drop`); and
  `redirect_breaks_carried` (`Q.+!`'s `CommonPartition` redirect replaces the insertion of
  `w <- (S,K)` by `w <- (a)` when `a <- (S,K)` is already queued, which destroys a
  `ConcCarried` PARENT even though the two systems have the same models).
* **The first destroyer disappears over `qsys`** — `qsys` drops the environment's alias facts,
  so the eliminated variable leaves the vocabulary and `carried_substOut_of_ne` covers every
  variable that remains.  **The third does not**: the redirect is a queue operation, and `qsys`
  is the queues.  One precision the round-3 review asks for (N-1): `redirect_breaks_carried`
  compares two hypothetical SUCCESSORS of one system — what the queue would hold if the
  insertion went through, against what it holds when the redirect fires — so it is an obstacle
  to the covering-lemma route of R3.5.2b, not by itself a counterexample to
  `CarrPresOn (qsys s) (qsys s')`.  That refutation is round 4's item (1).

### R3.5.2 The exact remaining lemma, and the bound it yields (`Loop/Residual.lean`)

```lean
/-- **A dequeued partition with a nonempty concrete part forbids `v <- ()`.** -/
theorem dequeued_not_empty_of_sat {s : State} (hsat : SSat (sys s)) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hconc : r.rhs.conc.isEmpty = false) :
    mk r.lhs ∅ (∅ : Row) ∉ sys s

/-- **§C3.2's localisation, sharpened.** -/
theorem concCarried_parent_nonempty {s : State} (hsat : SSat (sys s)) {r : LPart}
    {rest : PQueue} (hdq : s.incm.dequeue = some (r, rest)) (hconc : r.rhs.conc.isEmpty = false)
    {K : Row} (h : ConcCarried (qsys s) r.lhs K) :
    ∃ C : Row, C ≠ ∅ ∧ mk r.lhs ∅ C ∈ qsys s ∧ ∃ z, mk z ∅ (C \ K) ∈ qsys s

/-- **THE REMAINING LEMMA.** -/
def QStepDichotomy (L : Finset Label) : Prop :=
  ∀ (s s' : State) (rho : Assign), Wf s → SModels rho (qsys s) → ConcSub L (qsys s) →
    step s = .continue s' →
    K2StarStep (qsys s) (qsys s') ∨
      (allVars (qsys s') ⊆ allVars (qsys s) ∧ ConcSub L (qsys s') ∧
        CarrPresOn (qsys s) (qsys s') ∧ SModels rho (qsys s'))

/-- One step, under the remaining lemma: the potential does not grow. -/
theorem qstep_pot_le {L : Finset Label} (h : QStepDichotomy L) {s s' : State} {rho : Assign}
    (hw : Wf s) (hm : SModels rho (qsys s)) (hcs : ConcSub L (qsys s))
    (hst : step s = .continue s') :
    ∃ rho', SModels rho' (qsys s') ∧ ConcSub L (qsys s') ∧
      Pot L rho' (qsys s') ≤ Pot L rho (qsys s)

/-- **The loop-level bound, conditional on the remaining lemma.** -/
theorem run_qsys_invariant {L : Finset Label} (h : QStepDichotomy L) :
    ∀ (n : Nat) (s : State), Wf s → ∀ rho : Assign, SModels rho (qsys s) → ConcSub L (qsys s) →
      ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') →
        ∃ rho', SModels rho' (qsys s') ∧ Pot L rho' (qsys s') ≤ Pot L rho (qsys s)

/-- **THE LOOP-LEVEL VOCABULARY SNAPSHOT BOUND, conditional on the remaining lemma.** -/
theorem run_qsys_allVars_card_le {L : Finset Label} (h : QStepDichotomy L) (n : Nat)
    (s : State) (hw : Wf s) (rho : Assign) (hm : SModels rho (qsys s)) (hcs : ConcSub L (qsys s))
    (s' : State) (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    (allVars (qsys s')).card ≤ (allVars (qsys s)).card + hmeas L rho (qsys s)

/-- The bound at the labels the input carries, so that it depends on the input alone. -/
theorem run_qsys_bound {s0 : State} (h : QStepDichotomy (labelsOf (qsys s0))) (n : Nat)
    (hw : Wf s0) (rho : Assign) (hm : SModels rho (qsys s0)) (s' : State)
    (hres : run s0 n = .solved s' ∨ run s0 n = .outOfFuel s') :
    (allVars (qsys s')).card
      ≤ (allVars (qsys s0)).card + hmeas (labelsOf (qsys s0)) rho (qsys s0)
```

So the residual is ONE `Prop`, and it is proved SUFFICIENT for the explicit bound
`|allVars (qsys s₀)| + hmeas (labelsOf (qsys s₀)) rho (qsys s₀)` on the number of queue-visible
variables HELD AT ANY ONE STATE.

> **CORRECTED after the round-3 review (F-2).**  This paragraph originally continued "hence on
> the number of mints, since only a mint enlarges the vocabulary".  That is false here, and for
> a reason specific to `qsys`: the loop's queue-visible vocabulary SHRINKS at an elimination — a
> `common`/`unify` step writes the alias into `env`, and `qsys` excludes aliases, so the
> eliminated variable leaves `allVars (qsys ·)`.  A mint(+1)/elimination(−1) alternation
> therefore keeps the snapshot flat while minting without limit, and `QStepDichotomy`'s second
> disjunct (`allVars (qsys s') ⊆ allVars (qsys s)`) permits exactly that.  **No statement in the
> tree bounds how many times the loop mints.**  See R3.5.4.

**What `QStepDichotomy` still needs, clause by clause.**

| clause | status |
|---|---|
| `K2StarStep (qsys s) (qsys s')` at a minting step — ingredient (A) | OPEN, but its WORSE HALF is now closed. §C3.2 localises the gap to two cases; the dangerous one — the parent already empty, which carries EVERY key at once — is PROVED VACUOUS at a mint on satisfiable input (`dequeued_not_empty_of_sat`, `concCarried_parent_nonempty`): a mint's parent is the dequeued left-hand side, whose right-hand side has a nonempty concrete part, so the system cannot also hold `v <- ()`. What is left is the `C ⊆ K` half with `C` the parent's own NONEMPTY row, i.e. `2^{\|L \\ C\|}` keys per parent. |
| `allVars (qsys s') ⊆ allVars (qsys s)` at a non-minting step | plausible, unproved; the `sys` analogue is `step_allVars_strict` for three branches. |
| `ConcSub L (qsys s')` | plausible, unproved; no rule invents a label. |
| `CarrPresOn (qsys s) (qsys s')` — ingredient (B) | OPEN, and `redirect_breaks_carried` is the sharpened obstacle. The alias half is closed by `carried_substOut_of_ne` (over `qsys`), the `makeEmpty` half by `KeyedEmpty.carried_makeEmptyE`, the `makeConcrete` half by `KeyedRow.carried_concretizeSrs`. |
| `SModels rho (qsys s')` | plausible, unproved; `step_models_iff` is the `sys` analogue for three branches. |

**And note what `QStepDichotomy` does NOT give**, in two independent ways.

*It does not bound the mint count.*  The bound is a snapshot on the queue-visible vocabulary,
and `qsys` shrinks at an elimination, so mints and eliminations can alternate for ever inside
it (F-2 above).

*It does not give `Terminates s₀`.*  Even a genuine mint count would bound names, not dequeues;
termination needs it TOGETHER with §C3.4's progress table, whose last row — the `concrete`
branch count — is still open (L3 §4c(2)'s `ensureSuperset`-monotonicity sketch).

Both are stated here so no reader mistakes the conditional bound for a conditional termination
proof, or for a mint budget.

### R3.5.2b The next step, named

The shortest route to the `CarrPresOn` clause of `QStepDichotomy` is a syntactic COVERING lemma
for the queue writer, the mirror of round 2's `MECover`:

> `insertP_covers`: for every `p`, either `q.insertP p` contains a partition `eqv` to `p`, or
> `p` is a self-unification, or `q.rhsLookup p.rhs` hit — and in the last case the queue holds
> `a <- (S,K)` and gains `p.lhs <- (a)`.

`StrictStep.lean` already has `MECover` (what `makeEmpty`'s fold leaves behind, partition by
partition) but only as an internal `def` consumed inside `makeEmpty_noLoss`.  The QUEUE half is
now written and is exportable:

```lean
theorem sset_eqv_refl {α : Type} [SVal α] [LawfulSVal α] (s : SSet α) : s.eqv s = true

theorem rhs_eqv_refl (r : RHS) : r.eqv r = true

theorem insertP_covers {q : PQueue} {p : LPart} :
    (∃ x ∈ (q.insertP p).elems, x.rhs.eqv p.rhs = true) ∨ p.isSelfUnification = true

theorem concatP_covers : ∀ (ps : List LPart) (q : PQueue) (p : LPart), p ∈ ps →
    (∃ x ∈ (q.concatP ps).elems, x.rhs.eqv p.rhs = true) ∨ p.isSelfUnification = true
```

— after `Q.+!` the queue holds SOMETHING with the inserted partition's right-hand side: the
partition itself, or the `CommonPartition` redirect's match, which is precisely the case in
which the insertion is logically redundant and syntactically invisible.  (The only escape is a
self-unification, which `Q.insert` refuses and `Order.NoSelfUnif` excludes from every reachable
state.)  What is still missing is the `makeEmpty` half — exporting `MECover` — after which
`makeEmptyD r.lhs (qsys s)` is covered by `qsys s'` up to redirect victims, and
`KeyedEmpty.carried_of_makeEmptyD_subset` finishes the `empty` branch modulo exactly the
redirect.  The `common`/`unify` clauses would follow the same way from `replace`'s image.
`redirect_breaks_carried` says what the residue after all of that would be.

### R3.5.3 The witness hunt — 20,720 runs, 0 divergences

**New populations, aimed at the three places round 3 PROVES the guard is destroyed.**  Generator
`tmp/L5r3/hunt/gen.py`: a valuation is built first and every constraint is emitted as
`whole <- (pairwise-disjoint parts ⊎ disjoint concrete)` over it, so every system is satisfiable
by construction; an independent Python checker re-verifies each emitted system against its own
`rho` before it is written (0 of 4,240 rejected).  Five labels, four empty-row variables.

| population | what it is biased for | seeds × bases | runs | result |
|---|---|---|---|---|
| `redirect` | with probability 0.6 every constraint gets a TWIN with the SAME right-hand side and a different left-hand side — the `Q.+!` `CommonPartition` redirect's premise, i.e. exactly the configuration `redirect_breaks_carried` shows destroys a `ConcCarried` parent | 2,000 × 5 (0, 1, 5, 13, 97) | 10,000 | **SOLVED 10,000, FUEL 0, REJECTED 0** |
| `alias` | with probability 0.6 every constraint gets a companion singleton link `a <- (b)` between variables of equal row — the `unify` branch's premise, i.e. the configuration `substOut_breaks_carried` shows destroys `Carried` at the eliminated variable | 2,000 × 5 | 10,000 | **SOLVED 10,000, FUEL 0, REJECTED 0** |
| `scale18/20/22/24` | the constraint count pushed past round 2's 16 | 4 × 60 × 3 | 720 | **SOLVED 720, FUEL 0, REJECTED 0** |

Fuel 400,000, 180 s per-run cap, shipped flags; runs are of `lake exe looptrace`, the L1/L2
model executable.  **20,720 runs, no `FUEL`, no `REJECTED`, no timeout.**

| population | mean ids drawn | median | max |
|---|---|---|---|
| `redirect` | 8.93 | 2 | **669** |
| `alias` | 6.84 | 2 | **281** |
| `scale18` | 6.34 | 2 | 71 |
| `scale20` | 7.93 | 3 | 71 |
| `scale22` | 8.89 | 5 | 70 |
| `scale24` | 10.00 | 5 | 72 |

The scaling family here grows only the CONSTRAINT count, at a fixed five-label budget, so it is
NOT comparable with round 2's family (which grew the label set too): the mean grows roughly
linearly, 6.3 → 10.0 over 18 → 24 constraints, and the maximum does not move.  It is a
divergence check, not a growth measurement.

**Model against the compiler, on the new populations.**  The trace agreement of L2/L4 is about
the corpus and the tracked seeds, not about these; so 21 seeds spread across both populations
were replayed through the REAL `Subst.solve` at bases 0–9, and the two extremes at bases 0–99:
**410 comparisons of verdict AND ids drawn, 410 identical, 0 differing.**

**The two extremes, on the compiler, at 100 id bases.**

| seed | shape | compiler | `DRAWN` |
|---|---|---|---|
| `redirect00032` | 30 variables, 23 constraints, 5 labels | **SOLVED 100/100**, median 41 ms, max 530 ms | min 206, median 668, max **688**, in three clusters (206–207 ×10, 464–471 ×15, 666–688 ×75) |
| `alias01349` | 38 variables, 20 constraints, 5 labels | **SOLVED 100/100**, median 71 ms, max 643 ms | min 173, median 275, max 287, in two clusters (173–177 ×44, 273–287 ×56) |

The clustering is the point: the id base decides which of two or three regimes the queue order
falls into, and the draw count jumps by a factor of three between them — the same phenomenon as
round 2's 553-to-1,033 spread on `e00346`, on a fresh population.  Every base terminates, on
both sides, in milliseconds.

**Verdict: no witness.**  Round 3 therefore has no `W`, and combined with round 2's 7,500 +
480 runs the evidence against divergence at the shipped flags now stands at **28,700 runs with
0 `FUEL`**, including 20,000 aimed specifically at the two configurations this round proves
destroy the syntactic guard.  That is evidence that the guard's fragility is not the loop's
fragility — which is the honest reading of (T2) here: the bound is missing, not the property.

**What the hunt does NOT establish, stated plainly** (round-3 review, S-7).  It is a WHOLE-RUN
divergence check.  It is not evidence for `QStepDichotomy`, which is a PER-STEP `Prop`: a run
can terminate while individual steps violate the dichotomy.  The review's round-4 item (1) —
try to REFUTE the dichotomy at a single `Wf` state, which `Wf` does not constrain much (it is
`QOk` plus `LblCoh`, with no `QueueHygiene`, `NoSelfUnif` or reachability) — is a different and
much cheaper experiment, and round 3 did not run it.

Artefacts: `tmp/L5r3/hunt/{gen.py,run.py,cmp.sh}`, `tmp/L5r3/hunt/seeds/`,
`tmp/L5r3/hunt/logs/{redirect,alias,scale18,scale20,scale22,scale24}.txt`.

### R3.5.4 The mint COUNT, as an explicit open item

> **SUPERSEDED BY R4.3 (2026-09-05).**  The open item is answered for the CALCULUS —
> `Mints.KMintRun.mints_le` bounds the number of generative steps of `K2StarStep` by
> `hmeas L rho G₀` for every satisfiable `G₀`, with the productivity condition this section
> asks for — and answered NEGATIVELY for the LOOP: both of the two routes named below are
> refuted.  The first (a productivity condition on the counted step over the queue-visible
> carrier) dies with `qStepDichotomy_false`; the second (a monotone carrier) is built as
> `Mints.Trail`, gives ingredient (B) for free, and needs one lemma `HistDichotomy`, which is
> **FALSE** (`Mints.histDichotomy_false`, and `histDichotomyR_false` over real run histories).
> Read §R4.3.

Round 2 and the first draft of round 3 both used "mint bound" for a bound on
`|allVars ·|`.  For the library's `K2StarLoopRun` the two coincide, because its systems grow
monotonically and every mint adds a fresh variable that never leaves.  For the loop they do NOT
coincide, and round 3's review made that precise.  So, stated as an open item in its own right:

> **OPEN.**  No theorem in the tree bounds the number of minting `step`s of a solve.  What is
> proved is (i) `LoopStrictKRun.allVars_card_le` — a snapshot bound on the relation, and
> (ii) `run_qsys_allVars_card_le` — the same on the loop, conditional on `QStepDichotomy`.
> Closing the gap needs one of two things, neither of which is written:
>
> * a PRODUCTIVITY condition on the counted step (the library's `G ≠ G'`, plus "a mint adds a
>   variable that no later step removes"), which for the loop means proving that an eliminated
>   variable is never a variable minted later — plausible from `step_envNodup` plus
>   `SupFresh`, and not attempted; or
> * a MONOTONE carrier (the union of everything ever derived), for which ingredient (B) is free
>   — `Carried` is monotone under addition — but ingredient (A) breaks, because the loop's mint
>   guard is a lookup over the QUEUES and a bigger carrier carries more keys.
>
> That is a genuine dilemma between the two horns, not an oversight; the round-3 review's §S-11
> states it the same way, and it is the thing round 4 should attack.

## R3.6 — what round 3 could NOT prove, side by side

| asked for | what is proved | what is not, and why |
|---|---|---|
| **R3.1** (reviewer's R-4 acceptance) "add a syntactic conjunct to `requeue` that preserves `Carried` (and prove the loop's actual re-emissions satisfy it), or dissolve `requeue`; then `carried_step` for every non-minting step" | `carried_step` = `LoopStrict.carried_step`: **seven** constructors proved outright (five by additivity, two by the library's `Carried` lemmas), four closed VACUOUSLY under `¬ IsMint`, three passed through as hypotheses — F-1; `CarrPresOn.hmeas_le`; the conjunct SUPPLIED in `LoopStrictKRun`, for which `requeue_breaks_carried` is unprovable; and along such runs a VOCABULARY SNAPSHOT bound (`LoopStrictKRun.allVars_card_le`), **not** a mint count — F-2 | The conjunct CANNOT be put on `LoopStrict.requeue` itself: `substOut_breaks_carried` + `carried_iff_of_link_only` show the loop's `common`/`unify` re-emissions violate it over `sys`, and `redirect_breaks_carried` shows the shape `Q.+!`'s redirect produces destroys a `ConcCarried` parent over `qsys` too — strictly, it compares two hypothetical successors (plain insertion versus redirect), so it blocks the covering-lemma route of R3.5.2b rather than refuting `CarrPresOn (qsys s) (qsys s')` outright. Putting it on the constructor would have forced deleting `step_strict_common`, `step_strict_empty` and `step_strict_unify`; I did not weaken them, and `Loop/Strict.lean` is byte-identical to round 2. |
| **R3.2** "make `step_empty_makeEmptyE` load-bearing, and widen `substOut` with `replace`'s de-duplication fact so `instRemove` goes live" | both, and for BOTH link branches: `step_empty_via_makeEmptyE`; `substOutD` + `dedup_entailed` + `instRemove_step` + `instRemove_step_dedup` + `step_unify_via_substOut` + `step_common_via_substOut`. 13 of 14 constructors live | `concRemove` is still dead: its `NoLoss` premise is the `cancellation_bare` gap, so the `concrete` branch is not factored at all. |
| **R3.3** "`QueueHygiene` preserved by `step`, then `queueHygiene_run` from the initial states, and the corollary that the reinstantiation panic is unreachable from any `Wf` initial state" | all three: `step_queueHygiene` / `QueueHygiene.step` (unconditional, hypotheses strictly weaker than `step_refines_all`'s), `queueHygiene_initial` + `run_queueHygiene` + `run_queueHygiene'`, `queueHygiene_binds_unbound` + `step_link_no_death` | `learnPartitions_avoids` carries `fl.disjRule = false` (as `RefineLearn.step_refines_all` does). `disjunction_avoids` is proved, so the RULE is not the obstacle — only its two inner folds over `proc`.  **The RUN-level statements are conditional on `RunSupOk`, an unproved per-state hypothesis (Q-1)**, so "the panic has no path" holds modulo it and modulo `disjRule = false`; the single-step theorem is unconditional.  `queueHygiene_initial` covers "every state `Seed.solve` builds", not literally "every `Wf` initial state" (Q-2), and the `run … ≠ .rejected (panic …)` corollary is composed by the reader rather than assembled into one theorem. |
| **R3.4** "the `concrete` branch and the `learn` branch of the strict refinement, so `step_refines_strict` covers all five branches; and C2's vocabulary lemma for `learn`" | C2's quantitative half (`learnPartitions_drawn`: at most `1 + \|proc\|` ids) and a vocabulary clause that is **weaker than C2's** (`learnPartitions_vocab`: "old vocabulary or ANY reachable supply id") — F-4 | Neither branch of the refinement. `learn` needs `RefineLearn`'s `RuleRun` changed to carry a `LoopStrictRun` alongside its `LoopRun` and its ~20 producers re-proved (1,558 lines); `concrete` needs `concRemove`'s licence, i.e. `cancellation_bare`. `SupOk`/`SupFresh` preservation (the rest of C2) needs the SHARPER vocabulary clause "or one of the ids this step actually drew", which `learnPartitions_vocab` does not give. |
| **R3.5** "`Terminates s₀` for every satisfiable `Wf s₀` with an explicit bound, or the exact remaining lemma plus a witness hunt" | the exact remaining lemma `QStepDichotomy`, PROVED SUFFICIENT for the explicit SNAPSHOT bound `\|allVars (qsys s₀)\| + hmeas (labelsOf (qsys s₀)) rho (qsys s₀)` on the queue-visible vocabulary held at one state (`run_qsys_bound`); a new witness hunt (R3.5.3) | `QStepDichotomy` itself; the MINT COUNT (R3.5.4 — the snapshot is not a budget, F-2); and `Terminates`, which needs a count TOGETHER with §C3.4's progress table, whose `concrete` row is still open. |

## R3.7 — what a reviewer should re-run

1. `cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH && lake build Rowpartition` (846 jobs)
   and `lake env lean Audit.lean` (3186 / 0).
2. `grep -nE '\bsorry\b|\baxiom\b|\bpartial\b|native_decide|implemented_by|\bunsafe\b|\bopaque\b|Classical|\badmit\b|#exit' Rowpartition/Loop/{Carried,Hygiene,Factor,Draws,Residual}.lean`
   — 0 hits in all five.
3. `lake env lean tmp/L5r3/Axioms.lean` — 49 headlines, all `[propext, Classical.choice,
   Quot.sound]`.
4. The verbatim check: every ```lean block of this section, doc comments removed, must occur
   byte-for-byte in the five modules (71 of 71).
5. `git diff` scope: five NEW modules, `Rowpartition.lean` +5/−0, `tracker/lean/README.md`
   +34/−0, the plan's L5 row, this report.  `Loop/{Strict,StrictStep,StrictBound}.lean`,
   `Loop/{Refine,RefineConcrete,RefineLearn,Order,Wf,Step}.lean` and every Scala file
   UNCHANGED.
6. The counterexamples are the load-bearing negative results and are cheap to re-check:
   `substOut_breaks_carried`, `carried_not_monotone_under_deletion`, `redirect_breaks_carried`.
   Each is a closed term over a three-constraint system.
7. The hunt: `python3 tmp/L5r3/hunt/gen.py redirect 2000 <dir> 5 4 14` reproduces the seeds
   bit-for-bit (fixed `random.Random(i)` per seed), and `tmp/L5r3/hunt/cmp.sh <seed> 0 9`
   re-runs one seed on both sides.

# Round 4 — 2026-09-05, after `L5-REVIEW.md`'s "Round-3 review" (F-5, S-11, S-12)

Fresh implementer, starting from the clean commit `9060fbf` (rounds 1–3 committed).  Work
order is the brief's four checkpoints, R4.1 first: *attack `QStepDichotomy` before relying on
it*.  **The attack succeeded: the residual round 3 nominated is FALSE**, and false at an
INITIAL state of a satisfiable three-constraint input whose whole solve the compiler and the
model both finish in three dequeues.  R4.2 then discharges `RunSupOk`, and R4.3 proves a real
mint count for the calculus and refutes the OTHER horn of the review's §S-11 dilemma as well.
Three NEW modules, `Rowpartition/Loop/{Refuted,Supply,Mints}.lean`; **no earlier module is
edited**, so nothing rounds 1-3 proved is weakened or removed.

| | before round 4 | after round 4 |
|---|---|---|
| `lake build Rowpartition` | 846 jobs | **849 jobs**, success |
| `lake env lean Audit.lean` | `3186; 0` | **`Rowpartition theorems audited: 3376; declarations using a non-standard axiom: 0`** |
| new-module lines | — | `Refuted.lean` 574 + `Supply.lean` 820 + `Mints.lean` 786 = **2,180** |
| `sorry` / `axiom` / `partial` / `native_decide` / `Classical` / `unsafe` / `opaque` / `admit` | — | **0 in all three new modules** |
| `#print axioms`, all 165 new theorems (`tmp/L5r4/Axioms.lean`) | — | 157 × `[propext, Classical.choice, Quot.sound]`, 4 × `[propext, Quot.sound]`, 4 depend on no axioms; **no non-standard axiom** |
| verbatim | every ```lean block of this section, doc comments stripped, checked mechanically against the three modules | **89 of 89 statements byte-for-byte**; 95 declarations are quoted, six of them with an explicit `…` elision (marked in the text) |
| files touched | — | three NEW `Loop/` modules; `Rowpartition.lean` +3 import lines; `tracker/lean/README.md` additive; the plan's L5 row; this report.  No earlier module and no Scala file is edited. |

## R4.1 — `QStepDichotomy` is FALSE, at an initial state (review F-5, item 1)

**Outcome: REFUTED, in Lean, over `Wf` states AND over reachable states AND with every
invariant round 3 supplies assumed.  Not (b) — it is not provable as stated, because it is
not true.**

### R4.1.1 The witness

Three constraints, satisfiable by `rho v0 = {}`, `rho v1 = rho v2 = {l0}`:

```
  v2 <- (v0, (|l0|))        v0 <- ()        v1 <- ((|l0|))
```

as the state `wS` (`Refuted.lean` §1) — `incm` the three partitions, **`proc` empty, `env`
empty**, a coherent supply well clear of `{0,1,2}`, shipped flags.  That is exactly the
literal shape `Hygiene.queueHygiene_initial` is stated for, i.e. the shape `Seed.solve`
builds.

```lean
def wS : State :=
  { incm := PQueue.ofList [wW, wV, wA], proc := PQueue.empty, env := {},
    su := wSup, trace := [], flags := {}, names := wNames, site := "t0", su0 := 100 }

def wS' : State :=
  match step wS with
  | .continue t => t
  | .done t => t
  | .died _ t => t

theorem wS_step : step wS = .continue wS' := rfl
```

`v0` is the deepest variable of the graph, so the queue dequeues `v0 <- ()` first and the
`empty` branch runs.  `makeEmpty v0` erases `v0` from `v2 <- (v0, (|l0|))`, leaving the bare
concrete definition `v2 <- ((|l0|))`, and re-inserts it with `Q.++!` — into a queue that
already holds `v1 <- ((|l0|))`.  **The `CommonPartition` redirect fires and inserts
`v1 <- (v2)` instead.**

```lean
theorem qsys_wS :
    qsys wS = ({mk 0 ∅ (∅ : Row), mk 1 ∅ ({0} : Row), mk 2 {0} ({0} : Row)} : System)

theorem qsys_wS' :
    qsys wS' = ({mk 1 ∅ ({0} : Row), mk 1 {2} (∅ : Row), mk 0 ∅ (∅ : Row)} : System)
```

The key `(v2, {l0})` is carried before the step by the lone witness `v2 <- (v0, (|l0|))`
(`Resolved`), and by nothing after it — `v2` has no constraint left with `v2` on the left —
while `v2` is still in the queue-visible vocabulary, as the part of `v1 <- (v2)`.

```lean
theorem wS_carried2 : Carried (qsys wS) 2 ({0} : Row)
theorem wS'_notCarried2 : ¬ Carried (qsys wS') 2 ({0} : Row)
theorem wS'_mem2 : (2 : Var) ∈ allVars (qsys wS')
theorem wS_memW : mk 2 {0} ({0} : Row) ∈ qsys wS
theorem wS'_notMemW : mk 2 {0} ({0} : Row) ∉ qsys wS'
```

So neither disjunct survives: the first fails because every `K2StarStep` is additive
(`K2StarStep.subset`) and the premise `mk 2 {0} {0}` is gone; the second fails at
`CarrPresOn`.

```lean
/-- **THE RESIDUAL IS FALSE.** -/
theorem qStepDichotomy_false {L : Finset Label} (hL : (0 : Label) ∈ L) :
    ¬ QStepDichotomy L

theorem qStepDichotomy_labelsOf_false : ¬ QStepDichotomy (labelsOf (qsys wS))
```

The second is the pool `run_qsys_bound` is stated at, so the round-3 bound is conditional on
a hypothesis that is false at its own label pool.

### R4.1.2 Why no relativisation rescues it (the review's item 2)

The witness is INITIAL, so it is reachable in zero steps, and every invariant round 3
supplies holds at it — proved, not asserted:

```lean
theorem wS_invariants :
    Initial wS ∧ Wf wS ∧ QueueHygiene wS ∧ NoSelfUnif wS ∧ NoInfRow wS ∧
      SupOk wS.su ∧ SupFresh wS.su (sys wS) ∧ SSat (sys wS) ∧
      wS.flags.disjRule = false ∧ wS.flags.emptyRow = false ∧ wS.flags.cseMints = false
```

The brief asks for the relativised statement and for `run_qsys_bound` re-proved from it.  Both
are delivered — the route is sound, reachability threads through the fuel induction exactly as
`Wf` does — and then the relativised statement is refuted by the same step:

```lean
def Initial (s : State) : Prop := s.proc = PQueue.empty ∧ s.env.binds = []

inductive Reaches : State → State → Prop
  | refl (s : State) : Reaches s s
  | tail {s t u : State} : Reaches s t → step t = .continue u → Reaches s u

def QStepDichotomy' (L : Finset Label) : Prop :=
  ∀ (s0 s s' : State) (rho : Assign), Initial s0 → Reaches s0 s →
    Wf s → SModels rho (qsys s) → ConcSub L (qsys s) → step s = .continue s' →
    K2StarStep (qsys s) (qsys s') ∨
      (allVars (qsys s') ⊆ allVars (qsys s) ∧ ConcSub L (qsys s') ∧
        CarrPresOn (qsys s) (qsys s') ∧ SModels rho (qsys s'))

theorem run_qsys_bound' {L : Finset Label} (h : QStepDichotomy' L) {s0 : State}
    (hi : Initial s0) (n : Nat) (hw : Wf s0) (rho : Assign) (hm : SModels rho (qsys s0))
    (hcs : ConcSub L (qsys s0)) (s' : State)
    (hres : run s0 n = .solved s' ∨ run s0 n = .outOfFuel s') :
    (allVars (qsys s')).card ≤ (allVars (qsys s0)).card + hmeas L rho (qsys s0)

theorem qStepDichotomy'_false {L : Finset Label} (hL : (0 : Label) ∈ L) :
    ¬ QStepDichotomy' L
```

with `qstep_pot_le'` and `run_qsys_invariant'` in between, mirroring round 3's chain.

### R4.1.3 The POTENTIAL itself increases — so no repair of the dichotomy can work

This is the part that decides where round 4 goes next.  At the same step, and for **every**
model of the successor, the potential `Pot L rho G = |allVars G| + hmeas L rho G` — the
quantity `qstep_pot_le` and `run_qsys_invariant` propagate — strictly GROWS:

```lean
abbrev wL : Finset Label := {0}

theorem allVars_qsys_wS : allVars (qsys wS) = ({0, 1, 2} : Finset Var)
theorem allVars_qsys_wS' : allVars (qsys wS') = ({0, 1, 2} : Finset Var)

theorem uncarried_wS_2 : uncarried wL (qsys wS) 2 = 1
theorem uncarried_wS'_2 : uncarried wL (qsys wS') 2 = 2
theorem hmeas_wS : hmeas wL wRho (qsys wS) = 3
theorem hmeas_wS' {rho : Assign} (h : SModels rho (qsys wS')) :
    hmeas wL rho (qsys wS') = 6

/-- **The potential STRICTLY INCREASES at the witness step**, for every model of the
successor. -/
theorem qstep_pot_increases {rho : Assign} (h : SModels rho (qsys wS')) :
    Pot wL wRho (qsys wS) < Pot wL rho (qsys wS')

/-- ... so the CONCLUSION of `qstep_pot_le` is false at this step. -/
theorem qstep_pot_le_false :
    ¬ (∃ rho', SModels rho' (qsys wS') ∧ ConcSub wL (qsys wS') ∧
        Pot wL rho' (qsys wS') ≤ Pot wL wRho (qsys wS))
```

`6 < 9`: the vocabulary card is 3 on both sides, `hmeas` goes 3 → 6 because `v2`'s budget
`uncarried` goes 1 → 2 and `|rho v2| = 1`.  `wS'_model_pinned` proves every model of the
successor agrees with `wRho` on all three variables, so the increase is not an artefact of
choosing a bad `rho'`.

**Reading.**  The failure is not slack in how the dichotomy was phrased.  Over `qsys`, with
`Carried` as the guard, the round-3 measure is simply not monotone along the loop's steps —
the `Q.++!` redirect deletes a carrier from the queues at an `empty` step, on satisfiable
input, at step one.  `L5-REVIEW.md` §S-11's second horn ("over the queue-visible carrier
`qsys`, (A) is within reach and (B) is what `redirect_breaks_carried` blocks") is now closed
NEGATIVELY: (B) is not merely blocked, it is false, and so is the potential that depends on
it.  What survives of round 3's R3.5 is the *implication* `QStepDichotomy L → run_qsys_bound`
— a true theorem with a false hypothesis.

### R4.1.4 The witness on the SHIPPED compiler

Not only reachable in the model: the compiler takes the same step.  With
`tracker/repro/satterm/run.sh sweep json:.../redir.json 0 4 20 10` under
`-Dermine.useInterface=false -Dermine.rowTrace=…`, all five id bases give `SOLVED`, `drawn=0`,
`v0 := ConcreteRho(-,Set()); v1 := ConcreteRho(-,Set(l0)); v2 := ConcreteRho(-,Set(l0))`, and
the trace at base 0 is three `step` records:

```
step  …  empty     ^free0 <- (,)                          incm=2  proc=0
step  …  unify:2   CommonPartition: ^free1 <- (^free2,)   incm=1  proc=0
step  …  concrete  ^free1 <- (,Repro.l0)                  incm=0  proc=0
```

The model's own trace for `wS` is those three records — branch, partition, `incm=`, `proc=`
— as a theorem.  (The compiler's records carry two extra columns the model's `site` field
stands in for: the seed's file name with its id base, and the JVM thread; those are per-run
metadata, and they are the only difference.)

```lean
theorem wS_trace :
    (match run wS 20 with
      | .solved s => s.trace.reverse
      | .rejected _ s => s.trace.reverse
      | .outOfFuel s => s.trace.reverse) =
      ["step\tt0\tempty\t^free0 <- (,)\tincm=2\tproc=0",
       "step\tt0\tunify:2\tCommonPartition: ^free1 <- (^free2,)\tincm=1\tproc=0",
       "step\tt0\tconcrete\t^free1 <- (,Repro.l0)\tincm=0\tproc=0"] := rfl

theorem wS_solved : ∃ s, run wS 20 = .solved s
```

So the counterexample is a benign, terminating, three-dequeue solve of a satisfiable input,
and the second `step` record IS the redirect: the compiler dequeues the partition
`^free1 <- (^free2,)` that `Q.++!` manufactured in place of `^free2 <- (,Repro.l0)`.
Seed: `tmp/L5r4/seeds/redir.json`.

## R4.2 — `RunSupOk` DISCHARGED: `SupOk`/`SupFresh` are preserved by `step`

**Outcome: DONE.**  `Loop/Supply.lean` (820 lines).  The per-state hypothesis that gated
round 3's run-level queue hygiene — and with it the B1 certification — is now a theorem.

### R4.2.1 Why the existing machinery could not give it, and what replaces it

`Hygiene.lean`'s `learnPartitions_avoids` is parametric in a FIXED predicate `B` and needs
`SupAvoids B su` — *no id the supply can still hand out is `B`*.  A freshness clause cannot
assume that of itself: the ids a step DRAWS are ids the supply could hand out, so with `B`
read as "still drawable at the END of the step" the hypothesis is false, for every rule.
That is the exact reason `learnPartitions_vocab` came out as "in the old vocabulary or ANY
reachable id" (round-3 review F-4) — the fixed-`B` shape cannot express "or one of the ids
THIS step drew".

The repair is to let the predicate move with the supply:

```lean
/-- **`w` is not an old name, and the supply `su` can still hand it out.** -/
def New (Old : Var → Prop) (su : Sup) (w : Var) : Prop := ¬ Old w ∧ Sup.Reach su w

theorem not_new_of_old {Old : Var → Prop} {su : Sup} {w : Var} (h : Old w) :
    ¬ New Old su w

/-- Drawing only shrinks the reachable set, so `New` only shrinks. -/
theorem New.mono {Old : Var → Prop} {su su' : Sup}
    (hm : ∀ z, Sup.Reach su' z → Sup.Reach su z) {w : Var} (h : New Old su' w) :
    New Old su w

/-- **The drawn id is not `New` at the supply that drew it.** -/
theorem not_new_fresh {Old : Var → Prop} {su : Sup} (hok : SupOk su) :
    ¬ New Old (su.fresh).2 (su.fresh).1

/-- A supply that is either untouched or drawn from once. -/
def SupStep (su su' : Sup) : Prop := su' = su ∨ su' = (su.fresh).2
```

`New` SHRINKS along a draw, so "every name accumulated so far avoids `New Old (the current
supply)`" is a genuine FORWARD invariant, and `Wf.foldl_except_inv` carries it through
`learnPartitions`' fold with no future-referring hypothesis.

### R4.2.2 The three drawing rules, re-proved with the sharp conclusion

Each rule's conclusion avoids `New Old` **at the rule's own output supply**, and none of the
three needs a `SupAvoids` hypothesis:

```lean
theorem splitConcrete_su {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    SupStep su (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2
theorem resolution_su {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    SupStep su (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2

theorem splitConcrete_new {Old : Var → Prop} … (hok : SupOk su)
    (hv : ¬ New Old su v) (ha : ∀ w ∈ abstr.elems, ¬ New Old su w)
    (hr : ∀ r w, rhss r = some w → ¬ New Old su w)
    (hres : ∀ k w, resolvent k = some w → ¬ New Old su w)
    (hcr : ∀ k w, concRow k = some w → ¬ New Old su w) :
    ∀ x ∈ (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).1.elems,
      Avoids (New Old (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2)
        x.toConstraint

theorem resolution_new … (analogous)
theorem commonSubexpression_new … (hcse : fl.cseMints = false) … (analogous)
```

The hypotheses are `¬ New Old su ·` rather than `Old ·` on purpose: a reverse lookup may return
a name from the CURRENT BATCH, which can be an id the step has already drawn, and that is
exactly a name which is not old and no longer `New`.

### R4.2.3 C2's sharp vocabulary clause

```lean
/-- Every name of `p` is an old one. -/
def OldPart (Old : Var → Prop) (p : LPart) : Prop :=
  Old p.lhs ∧ ∀ w ∈ p.rhs.abstr.elems, Old w

/-- **C2's sharp vocabulary clause.**  Every name a `learn` step writes is an OLD name or an
id the step has already SPENT -- so no name it writes is one the supply can still hand out. -/
theorem learnPartitions_new {Old : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hok : SupOk su) (hv : Old v)
    (hr1 : ∀ w ∈ rhs1.abstr.elems, Old w)
    (hi : ∀ x ∈ incm.elems, OldPart Old x)
    (hp : ∀ x ∈ proc.elems, OldPart Old x)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    SupOk su' ∧ (∀ z, Sup.Reach su' z → Sup.Reach su z) ∧
      ∀ x ∈ S.elems, Avoids (New Old su') x.toConstraint
```

This IS the clause round 3 said was "one strengthening away" and did not write.

### R4.2.4 The step, all five branches

```lean
/-- **`SupOk` and `SupFresh` are preserved by every `continue` step**, under the shipped
flags.  This is the rest of C2. -/
theorem step_supFresh {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') :
    SupOk s'.su ∧ (∀ z, Sup.Reach s'.su z → Sup.Reach s.su z) ∧ SupFresh s'.su (sys s')
```

Taking `Old := (· ∈ allVars (sys s))`, the four non-`learn` branches reuse `Hygiene.lean`'s
own `makeEmpty_avoids` / `instantiate_avoids` / `makeConcrete_avoids` at `B := New Old s.su`
(they draw nothing, so the supply is fixed and every name they write is old), and the `learn`
branch is `learnPartitions_new`.  The environment side is new — `SupFresh` is about all of
`sys s`, not only the queues — and needs `instantiateType`'s rewriting:

```lean
theorem avoids_env_instantiate {B : Var → Prop} {e : Env} {v : Nat} {val : EnvVal}
    (he : ∀ b ∈ e.binds, Avoids B (EnvVal.toConstraint b.1 b.2))
    (hv : ¬ B v) (hval : ∀ u, val = EnvVal.alias u → ¬ B u) :
    ∀ b ∈ (e.instantiate v val).binds, Avoids B (EnvVal.toConstraint b.1 b.2)
```

### R4.2.5 `RunSupOk` is a theorem, and B1's certification is hypothesis-free

```lean
/-- **The supply invariant is an INVARIANT**, not a per-state hypothesis. -/
theorem runSupOk_of {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) :
    ∀ n : Nat, RunSupOk n s

/-- **Queue hygiene at every state a run reaches -- UNCONDITIONALLY.** -/
theorem run_queueHygiene_of (n : Nat) {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) :
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → QueueHygiene s'

theorem run_queueHygiene'_of (n : Nat) {s : State} … : ∀ s' m, run s n = .rejected m s' → QueueHygiene s'

/-- Hygiene, the supply invariant and the flags all travel along `Reaches`. -/
theorem reaches_invariants {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hr : Reaches s t) :
    t.flags.disjRule = false ∧ t.flags.cseMints = false ∧ SupOk t.su ∧
      SupFresh t.su (sys t) ∧ QueueHygiene t

/-- **THE PANIC IS UNREACHABLE.**  At every state reachable from a hygienic one the three
variables a step can bind are UNBOUND -- exactly the condition `Subst.instantiateType`'s `die`
tests. -/
theorem reaches_binds_unbound {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hr : Reaches s t) {r : LPart} {rest : PQueue}
    (hdq : t.incm.dequeue = some (r, rest)) :
    t.env.contains r.lhs = false ∧
      (∀ u, r.rhs.abstr.contains u = true → t.env.contains u = false) ∧
      (∀ u, t.proc.findRHS r.rhs = some u → t.env.contains u = false)

theorem reaches_link_no_death … : (neither link branch can die)

/-- **The certification, from an INITIAL state.** -/
theorem initial_binds_unbound {s t : State} (hi : Initial s)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hr : Reaches s t)
    {r : LPart} {rest : PQueue} (hdq : t.incm.dequeue = some (r, rest)) :
    t.env.contains r.lhs = false ∧
      (∀ u, r.rhs.abstr.contains u = true → t.env.contains u = false) ∧
      (∀ u, t.proc.findRHS r.rhs = some u → t.env.contains u = false)
```

**What is left as a hypothesis, stated plainly.**  `SupOk s.su` and `SupFresh s.su (sys s)`
at the INITIAL state, and the two shipped flags `disjRule = false`, `cseMints = false`.  The
first two are properties of the input, not of the loop: a seed is free to name a variable
inside its own supply's range, and `Seed.solveSeed` does not check it.  Round 3's per-state
`RunSupOk` is gone; the assembled corollary the review's Q-2 asked for is
`reaches_binds_unbound` / `initial_binds_unbound`, stated semantically (the `die` test never
fires) rather than as a string non-equality on the panic message.

**Scope of the certification, exactly** (round-4 review U-2).  The two input hypotheses hold of
every supply the COMPILER hands `Subst.solve` — that is what a `scalaparsers.Supply` is, and the
trace's `sin` record carries `lo`, `hi` and the global block counter, which is how `Loop.Replay`
gets them.  They do **not** hold of the model's own `json:` seed driver: `Sup.ofSeed` sets
`blk = 0` (`Loop/State.lean`, and `RefineLearn.lean`'s own note on `SupOk` says so), so
`SupOk`'s `hi ≤ blk` is false for it, and `Loop/Main.lean`'s `looptrace` seed runs are outside
the theorem.  So the hypothesis-free reading is: **`Replay` of a real compiler trace, and
hand-built states with a realistic supply** (R4.1's `wS` is one) — not the seed driver.  Nothing
here is a defect of the loop; `Sup.ofSeed`'s `blk = 0` is the repro harness's real, process-global
starting counter, and the panic-freedom argument simply does not quantify over it.

**One asymmetry, unflagged until now** (round-4 review N-1).  `step_link_no_death` assembles
"`instantiate` returns `.ok`" for the two link branches, but nothing assembles the same for
`makeEmpty`'s own panic arm, although `reaches_binds_unbound`'s FIRST conjunct
(`t.env.contains r.lhs = false`) is exactly that arm's guard (`Loop/Step.lean`, the
`env.contains v` test before `instantiateType`).  The composition is one line and is not
written; the fact is available, the corollary is not.

## R4.3 — a REAL mint count, and the carrier dilemma settled on BOTH horns

**Outcome: the mint count is PROVED for the relation, unconditionally; the loop-level
transport is (T2) with the exact remaining lemma, and the hunt aimed at that lemma FOUND
violations.**  `Loop/Mints.lean` (786 lines).

### R4.3.1 The count itself (review F-2, and the brief's "productivity condition")

Round 3's `LoopStrictKRun` counted steps that need not change anything and permitted the
vocabulary to shrink, which is why its `n` was unbounded (the review's `mints_not_bounded`).
Both defects are fixed by making the counted step exactly a step that ADDS A VARIABLE —
`K2StarStep.allVars_cases` says there is no third case, so this is not a restriction of the
calculus but a bookkeeping of it:

```lean
/-- **A run of the additive keyed calculus with the GENERATIVE steps counted.** -/
inductive KMintRun (L : Finset Label) : ℕ → System → System → Prop
  | refl (G : System) : KMintRun L 0 G G
  | keep {n : ℕ} {G₀ G G' : System} :
      KMintRun L n G₀ G → K2StarStep G G' → allVars G' = allVars G → KMintRun L n G₀ G'
  | mint {n : ℕ} {G₀ G G' : System} :
      KMintRun L n G₀ G → K2StarStep G G' →
      (∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G)) → KMintRun L (n + 1) G₀ G'

theorem KMintRun.step {L : Finset Label} {n : ℕ} {G₀ G G' : System}
    (h : KMintRun L n G₀ G) (hs : K2StarStep G G') :
    KMintRun L n G₀ G' ∨ KMintRun L (n + 1) G₀ G'

/-- **The count IS the vocabulary growth.** -/
theorem KMintRun.card_eq {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : KMintRun L n G₀ G) : (allVars G).card = (allVars G₀).card + n

theorem KMintRun.pot_le {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : KMintRun L n G₀ G) : ConcSub L G₀ → ∀ rho : Assign, SModels rho G₀ →
      ∃ rho', SModels rho' G ∧ Pot L rho' G ≤ Pot L rho G₀

/-- **THE MINT COUNT.**  From a satisfiable `G₀`, the additive keyed calculus takes at most
`hmeas L rho G₀` GENERATIVE steps — an explicit bound in the input alone. -/
theorem KMintRun.mints_le {L : Finset Label} {n : ℕ} {G₀ G : System} {rho : Assign}
    (h : KMintRun L n G₀ G) (hcs : ConcSub L G₀) (hm : SModels rho G₀) :
    n ≤ hmeas L rho G₀

theorem KMintRun.mints_le_labelsOf {n : ℕ} {G₀ G : System} {rho : Assign}
    (h : KMintRun (labelsOf G₀) n G₀ G) (hm : SModels rho G₀) :
    n ≤ hmeas (labelsOf G₀) rho G₀

theorem KMintRun.trans {L : Finset Label} {m n : ℕ} {G₀ G G' : System}
    (h' : KMintRun L n G G') : KMintRun L m G₀ G → KMintRun L (m + n) G₀ G'

/-- The round-3 review's `mints_not_bounded` is UNPROVABLE for this relation. -/
theorem kmint_bounded (G₀ : System) (rho : Assign) (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), KMintRun (labelsOf G₀) n G₀ G → n ≤ N
```

This is the statement round 2 and round 3 both reached for and did not have: **a bound on the
NUMBER OF MINTING STEPS, not on the vocabulary held at one state.**

### R4.3.2 The carrier, and ingredient (B) for free

R4.1 kills the queue-visible horn of the review's §S-11 dilemma outright, so this round takes
the monotone one.  `Trail s H t` is "the run from `s` has reached `t`, and `H` is everything it
has ever held":

```lean
inductive Trail : State → System → State → Prop
  | refl (s : State) : Trail s (sys s) s
  | tail {s t u : State} {H : System} :
      Trail s H t → step t = .continue u → Trail s (H ∪ sys u) u

theorem Trail.start_subset {s t : State} {H : System} (h : Trail s H t) : sys s ⊆ H
theorem Trail.cur_subset {s t : State} {H : System} (h : Trail s H t) : sys t ⊆ H
theorem Trail.reaches {s t : State} {H : System} (h : Trail s H t) : Reaches s t
theorem Trail.wf {s t : State} {H : System} (hw : Wf s) (h : Trail s H t) : Wf t

/-- **Ingredient (B), free.** -/
theorem Trail.carrPres {H : System} (u : State) : CarrPres H (H ∪ sys u) :=
  CarrPres.of_subset Finset.subset_union_left
```

One line, where over `sys` it took `substOut_breaks_carried` and over `qsys` it is FALSE.
That is the whole content of the monotone horn, and it is now used rather than discussed.

### R4.3.3 The remaining lemma, and the loop-level mint bound it gives

```lean
/-- **THE REMAINING LEMMA, over the monotone carrier.** -/
def HistDichotomy (L : Finset Label) : Prop :=
  ∀ (s s' : State) (H : System) (rho : Assign), Wf s → sys s ⊆ H → SModels rho H →
    ConcSub L H → step s = .continue s' → ∃ n, KMintRun L n H (H ∪ sys s')

theorem trail_kmintRun {L : Finset Label} (h : HistDichotomy L) {s0 t : State} {H : System}
    (hw : Wf s0) (hcs : ConcSub L (sys s0)) (rho : Assign) (hm : SModels rho (sys s0))
    (ht : Trail s0 H t) : ∃ n, KMintRun L n (sys s0) H

/-- **THE LOOP-LEVEL MINT COUNT, conditional on the remaining lemma.** -/
theorem run_hist_mints_le {L : Finset Label} (h : HistDichotomy L) {s0 t : State} {H : System}
    (hw : Wf s0) (hcs : ConcSub L (sys s0)) (rho : Assign) (hm : SModels rho (sys s0))
    (ht : Trail s0 H t) :
    (allVars H).card ≤ (allVars (sys s0)).card + hmeas L rho (sys s0)

theorem run_sys_allVars_le … : (allVars (sys t)).card ≤ (allVars (sys s0)).card + hmeas L rho (sys s0)
```

Unlike round 3's `run_qsys_allVars_card_le` this **is** a count of minting steps, because
`KMintRun.card_eq` makes the count and the growth of the history's vocabulary the same number,
and the history never shrinks.

`HistDichotomy` contains ingredient (A) and nothing else — (B) is `Trail.carrPres`.  What (A)
asks is that the loop's own guard, a lookup over the QUEUES, imply the relation's guard over
the whole HISTORY.  Those are different predicates, and R4.1's witness proves it:

```lean
/-- **The two guards ARE different predicates**, at step one of a three-constraint solve. -/
theorem hist_qsys_disagree :
    Carried (sys wS ∪ sys wS') 2 ({0} : Row) ∧ ¬ Carried (qsys wS') 2 ({0} : Row)

theorem mint_needs_uncarried {G : System} {c : Constraint} {u : Var} (h : K2MintApp G c u) :
    ¬ Carried G c.lhs c.conc

/-- **The necessary condition** — a step at which the potential over the history grows refutes
the remaining lemma. -/
theorem histDichotomy_pot_le {L : Finset Label} (h : HistDichotomy L) {s s' : State}
    {H : System} {rho : Assign} (hw : Wf s) (hsub : sys s ⊆ H) (hm : SModels rho H)
    (hcs : ConcSub L H) (hst : step s = .continue s') :
    ∃ rho', SModels rho' (H ∪ sys s') ∧ Pot L rho' (H ∪ sys s') ≤ Pot L rho H
```

### R4.3.4 `drawn` is NOT the mint count, and cannot be made one

```lean
/-- **`resolution` always draws when its two premises have a lone variable part** — before the
intersection test and before all three reuse lookups. -/
theorem resolution_draws {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS} {x y : Nat}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (hres : fl.resolves = true) (hx : rhs1.abstrSingle? = some x)
    (hy : rhs2.abstrSingle? = some y) :
    (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2 = (su.fresh).2

/-- **How many ids one `step` can draw.** -/
theorem step_drawn_le {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : step s = .continue s') :
    s'.su.drawn ≤ s.su.drawn + 1 + s.proc.elems.length
```

`Sup.drawn` is the number the harness reports and L2/L4 match against the compiler, and it is
NOT a mint count: a `resolution` REUSE costs an id too, which is the mechanism behind
`e00346`'s 1,033 draws from twelve constraints.  So no carrier-based bound can bound `drawn`;
the bound above is over the vocabulary of the history, and bounding `drawn` needs the number
of dequeues, i.e. termination itself.  Recording this explicitly because "the mint count"
could otherwise be read as "the draw count", and they are different quantities.

### R4.3.5 The remaining lemma is FALSE too — the second horn refuted, in Lean

The hunt (R4.3.6) found the loop minting at a key the history already carried, and the shape
it found is small enough to hand-build and prove.  **Four constraints, satisfiable**
(`rho v0 = rho v3 = rho v4 = {}`, `rho v1 = rho v2 = {l0}`):

```
  v1 <- (v0, (|l0|))     v0 <- ()     v2 <- ((|l0|))     v1 <- (v3, v4, (|l0|))
```

Step 1 is R4.1's redirect: `makeEmpty v0` erases `v0` from `v1 <- (v0, (|l0|))`, the bare
`v1 <- ((|l0|))` is re-inserted with `Q.++!`, the twin `v2 <- ((|l0|))` catches it, and the
queue gains `v2 <- (v1)` instead.  Step 2 dequeues `v1 <- (v3, v4, (|l0|))`; all three of
`splitConcrete`'s lookups miss over the QUEUES, and it MINTS — at the key `(v1, {l0})`, which
the history has carried since the input.

```lean
def mS0 : State :=
  { incm := PQueue.ofList [mA, mB, mC, mD], proc := PQueue.empty, env := {},
    su := wSup, trace := [], flags := {}, names := wNames, site := "t0", su0 := 100 }
def mS1 : State := mNext mS0
def mS2 : State := mNext mS1

theorem mS0_step : step mS0 = .continue mS1 := rfl
theorem mS1_step : step mS1 = .continue mS2 := rfl
theorem mS2_drawn : mS2.su.drawn = 1 := rfl

def mH1 : System :=
  {mk 0 ∅ (∅ : Row), mk 1 {0} ({0} : Row), mk 1 {3, 4} ({0} : Row), mk 2 ∅ ({0} : Row),
   mk 2 {1} (∅ : Row)}
def mH2 : System :=
  {mk 0 ∅ (∅ : Row), mk 1 {0} ({0} : Row), mk 1 {3, 4} ({0} : Row), mk 2 ∅ ({0} : Row),
   mk 2 {1} (∅ : Row), mk 100 {3, 4} (∅ : Row), mk 1 {100} ({0} : Row)}

theorem mH1_eq : sys mS0 ∪ sys mS1 = mH1
theorem mH2_eq : mH1 ∪ sys mS2 = mH2
theorem mH1_carries_the_key : Carried mH1 1 ({0} : Row)
theorem hmeas_mH1 : hmeas wL mRho mH1 = 7
theorem hmeas_mH2_mRho : hmeas wL mRho mH2 = 9
theorem allVars_mH1 : allVars mH1 = ({0, 1, 2, 3, 4} : Finset Var)
theorem allVars_mH2 : allVars mH2 = ({0, 1, 2, 3, 4, 100} : Finset Var)

/-- Every model of the history after the mint agrees with `mRho` on its whole vocabulary. -/
theorem mH2_pinned {rho : Assign} (h : SModels rho mH2) : ∀ v ∈ allVars mH2, rho v = mRho v

/-- **The history the refutation uses is a real run history**, not an arbitrary superset. -/
theorem mS1_trail : Trail mS0 mH1 mS1

/-- The arithmetic both refutations share: `5 + 7 = 12` before the mint, `6 + 9 = 15` after. -/
theorem pot_mH2_gt {rho : Assign} (h : SModels rho mH2) :
    Pot wL mRho mH1 < Pot wL rho mH2

/-- **THE REMAINING LEMMA IS FALSE.** -/
theorem histDichotomy_false : ¬ HistDichotomy wL

/-- The remaining lemma RELATIVISED to the histories the loop actually builds. -/
def HistDichotomyR (L : Finset Label) : Prop :=
  ∀ (s0 s s' : State) (H : System) (rho : Assign), Trail s0 H s → Wf s0 → SModels rho H →
    ConcSub L H → step s = .continue s' → ∃ n, KMintRun L n H (H ∪ sys s')

/-- **... and it is false too**, by the same witness, because `mH1` is a `Trail` history. -/
theorem histDichotomyR_false : ¬ HistDichotomyR wL

theorem labelsOf_mH1 : labelsOf mH1 = wL
```

As in R4.1, the relativisation does not help: `mH1` is literally what `Trail` accumulates over
the witness's first step (`mS1_trail`), so restricting the quantifier to real run histories
leaves the same counterexample.

The potential over the monotone carrier goes from `5 + 7 = 12` to `6 + 9 = 15`: the mint costs
a variable and buys nothing, because the key's budget was already spent.  `mH2_pinned` closes
the choice of model — every model of the successor history gives the same `hmeas`.

**So both horns of the dilemma are refuted, in Lean**: `qStepDichotomy_false` (queue-visible
carrier, (B) fails, at an INITIAL state) and `histDichotomy_false` (monotone carrier, (B) is
free and (A) fails, at the SECOND step of a four-constraint solve).  The bound the library
supplies — `KMintRun.mints_le`, which is real and unconditional for the calculus — does not
transport to the loop along either carrier.

### R4.3.6 The hunt, and the compiler

The hunt is a per-STEP check, not a whole-run divergence check, which is what
`L5-REVIEW.md` §S-7 says round 3's hunt was missing.  Generator
`tmp/L5r4/hunt/gen.py`: a valuation is fixed first and every constraint is emitted as
`whole <- (pairwise-disjoint parts ⊎ disjoint concrete)` over it, so every system is
satisfiable by construction and an independent checker re-verifies it; 8 variables, 5 labels,
10 constraints, biased toward `splitConcrete`'s minting shape (≥ 2 abstract parts AND a
nonempty concrete part).  The analyser (`tmp/L5r4/hunt/Hunt.lean`, run under `#eval` against
the model itself) replays each seed step by step, accumulates the history `H`, and at every
step that puts a NEW variable into play checks whether the minted key — the dequeued
left-hand side with the concrete part of the constraint the fresh id appears in — is already
`Carried H`, and whether the split premise is already `Named H`.

| population | seeds | steps | steps that mint | mints at an already-CARRIED key | mints at an already-NAMED premise | FUEL / died |
|---|---|---|---|---|---|---|
| 8 vars, 5 labels, 10 constraints (seeds 0–59) | 60 | 2,027 | 216 | **2** | 0 | 0 / 0 |
| the same, seeds 60–139 | 80 | 2,696 | 297 | **13** | **1** | 0 / 0 |
| **total** | **140** | **4,723** | **513** | **15** | **1** | **0 / 0** |

So the mismatch is not rare: **15 of 513 minting steps mint at a key the history already
carries**, in 6 of 140 seeds, and one mints on a premise the history already `Named`.  Several
of the hits are at variables the loop itself minted earlier (`v106`, `v102`, `v103`), i.e. the
re-minting compounds.  Every seed still SOLVES — this is a per-step property, not divergence.

The first two hits are seeds 44 (step 19, key `(v5, {l0,l2,l3,l4})`) and 52 (step 39, key
`(v3, {l0,l1,l2,l3,l4})`).  **Both replay on the SHIPPED compiler**
(`tracker/repro/satterm/run.sh sweep json:.../hist44.json 0 9`): `SOLVED 10/10` each, and the
model reproduces the compiler's verdict AND draw count exactly at bases 0, 1, 2 — 5/4/4 for
`hist44` and 12/15/11 for `hist52`, identical on both sides.  The hand-built witness of
R4.3.5 does too: `SOLVED 5/5`, `drawn = 1` at every base on the compiler, and the model's
`mS2.su.drawn = 1` is a theorem.  Its trace is the compiler's:

```
step  …  empty  ^free0 <- (,)                              incm=3  proc=0
step  …  learn  ^free1 <- (^free3 ^free4,Repro.l0)         incm=2  proc=0
learn …  new    SplitConcrete: ^ambiguous(free)5 <- (^free3 ^free4,)
learn …  new    SplitConcrete: ^free1 <- (^ambiguous(free)5,Repro.l0)
```

So the mint that refutes the remaining lemma is a mint the compiler really takes, on a
satisfiable input it really solves.

## R4.4 — `Terminates`: **(T2)**, and the residual is now REFUTED rather than open

**Outcome: T2.**  Not T1: no bound on the loop's vocabulary follows, because the two
statements that would have delivered one are both false (R4.1, R4.3.5).  Not W: no divergence
was found — round 4 adds 140 seeds × 300-step replays (4,723 steps) and five compiler sweeps to
round 3's 28,700 runs, all terminating.

What is missing is no longer a lemma nobody had tried; it is a measure.  Stating the position
exactly:

* **The pieces that exist.**  `KMintRun.mints_le` bounds the mints of the keyed calculus by
  `hmeas L rho G₀`, unconditionally, for satisfiable input.  `Order.learnChain_card` bounds a
  chain of consecutive `learn` steps by the number of distinct constraints the processed queue
  can hold.  `StrictBound`'s `step_envNodup` / `env_len_le_allVars` bound the `empty`,
  `common` and `unify` steps by `|allVars (sys s)|`.  R4.2's `step_supFresh` bounds the
  vocabulary by the ids drawn.  Every one of these is a bound in the VOCABULARY.
* **The circle.**  The vocabulary is bounded by the mint count; the mint count needs the
  keyed guard to transport; the guard transports only along a carrier; and both carriers are
  now refuted.  So the vocabulary is the free variable of the whole system of bounds, and
  nothing in the tree pins it.
* **What round 4 removes from the search space.**  Any argument of the form "take a carrier
  `C(s)`, prove `Carried (C s)` preserved at non-minting steps and implied-by-the-guard at
  minting ones" fails for `C = qsys` (R4.1, at an initial state), for `C = ` the monotone
  history (R4.3.5, at the second step of a four-constraint solve), and — the round-4 review's
  U-3, checked by the reviewer with the SAME two witnesses — for the intermediate carrier
  `C = sys`, the one `LoopStrict` and `step_refines_all` are stated over:
  `Carried (sys wS) 2 {l0}` is true and `Carried (sys wS') 2 {l0}` is false, with `Pot` going
  6 → 9, and `Carried (sys mS0) 1 {l0}` is true and `Carried (sys mS1) 1 {l0}` is false.  So
  **all three natural carriers are refuted**, and the two that fail on (B) fail at the same
  step — the `Q.++!` redirect.  The two failure modes are dual: a carrier small enough to
  match the loop's guard is too small to be preserved, and one big enough to be preserved is
  too big for the guard.
* **The direction that is NOT left** (round-4 review U-4 / T-9; I named this one and the
  reviewer refutes it, correctly).  "Charge each RE-MINT to a DELETION" does not close, for
  the reason §C3.3 already gives and for two more:

  1. `env_len_le_allVars` bounds eliminations only by `|allVars (sys s)| = V₀ + M`, so a
     charge `M ≤ hmeas₀ + c·#eliminations` reads `M ≤ hmeas₀ + c·(V₀ + M)`, which bounds
     nothing for `c ≥ 1`.  Sharpening WHAT is charged only changes `c`.
  2. The per-(lost carrier, key) reading makes `c` bigger, not smaller: one elimination
     removes every queue partition mentioning the eliminated variable, and withdrawing one
     `ConcCarried` parent `mk v ∅ C` withdraws carrying for a whole slice of `L.powerset`, so
     the pairs per elimination are `O(|queue| · 2^{|L|})`.
  3. The per-key reading is already refuted by this round's own hunt data, which I did not
     read closely enough: seed 74 hits at `(step 97, v4, {l0,l1,l2})` **and**
     `(step 100, v4, {l0,l1,l2})`, and seed 139 at `(70, v102, {l0,l1,l3})` and
     `(80, v102, {l0,l1,l3})` — **the same `(v, K)` re-minted twice**, four times over.  So
     "at most one re-mint per key" is false in the measured data.
* **And the loop supplies its own fuel — the PUMP.**  The reviewer's structural reading, which
  I accept: the loop mints a fresh `w` for a key `(v, K)`; the mint installs the carrier
  `v <- (w, K)`; eliminating `w` — a FREE elimination, since `w` did not exist before the mint
  — withdraws that carrier; and the loop may then mint at `(v, K)` again.  Each turn spends one
  binding and produces one variable, so nothing external is consumed, and no counting argument
  of the shape above can close while it runs.  **That is what a divergence witness would have
  to look like**, and the hunt has already measured a second turn.  The evidence against a
  third is empirical (0 `FUEL` in ~29,000 runs across rounds 3 and 4, plus the corpus), not
  structural.
* **Round 5, therefore.**  The specification is the round-4 review's T-9, four checkpoints, and
  it replaces the direction I had named: **R5.1** drive the pump — build a family `P(k)` that
  repeats mint → eliminate → re-mint at one `(v, K)` and push `k` from 2 (measured) to 3 and 4,
  instrumenting the hunt to report the maximum number of mints at one `(v, K)` and scaling the
  generator, with the compiled `looptrace` rather than `#eval`; acceptance is either a family
  whose draw count grows without bound at fixed input size, replayed on the shipped compiler —
  which **meets the plan's L5 acceptance by a WITNESS** — or the measurement that the maximum
  is bounded.  **R5.2** state the charging lemma so that it can be refuted ("between two mints
  at the same `(v, K)` the loop binds a variable occurring in a carrier of `(v, K)` present at
  the first mint", then the clause that matters: "and that variable is not one the loop minted
  for `(v, K)`") — refuting the second clause IS R5.1's pump, so the two run together.
  **R5.3** use the dequeue ORDER, which no L5 measure has used: in R4.1's witness the link
  `v1 <- (v2)` the redirect manufactures is dequeued immediately, so the carrier loss is
  transient, and if the graph priority guarantees that, the redirect's damage can be excluded
  by evaluating the potential only at quiescent states (`Loop/Queue.lean`'s `dequeue`,
  `Loop/Order.lean`).  **R5.4** if neither closes, deliver `Terminates` for a stated FRAGMENT
  (`|L| ≤ 1`, or `Q.++` in place of `Q.++!`) with a measurement of how far it is from the
  corpus, turning (T2) into a theorem with a scope.

## R4.5 — what round 4 could NOT prove, side by side

| asked for | what is proved | what is not, and why |
|---|---|---|
| **R4.1** "refute `QStepDichotomy` over all `Wf` states and relativise it to reachable states, or prove it" | REFUTED: `qStepDichotomy_false` (for every `L ∋ l0`), `qStepDichotomy_labelsOf_false`, at an INITIAL state of a satisfiable input the compiler solves in three dequeues (`wS_trace`, `wS_solved` — the same three `step` records as the compiler's, in every field but the trace's own site/location/thread columns); the relativisation IS delivered (`QStepDichotomy'`, `qstep_pot_le'`, `run_qsys_invariant'`, `run_qsys_bound'`) and then refuted too (`qStepDichotomy'_false`); and the potential itself is proved to GROW (`qstep_pot_increases`, `qstep_pot_le_false`) | Nothing is left of the positive reading: the residual round 3 nominated is false, and `run_qsys_bound` is a true theorem with a false hypothesis. Round 3's modules are untouched, so nothing it proved is weakened. |
| **R4.2** "prove `SupOk`/`SupFresh` preserved by `step` so `RunSupOk` is discharged and B1's certification is hypothesis-free" | DONE: `New`/`SupStep` and the three drawing rules re-proved (`splitConcrete_new`, `resolution_new`, `commonSubexpression_new`), C2's sharp clause `learnPartitions_new`, `step_supFresh` for all five branches, `runSupOk_of`, `run_queueHygiene_of`, `run_queueHygiene'_of`, `reaches_invariants`, `reaches_binds_unbound`, `reaches_link_no_death`, `initial_binds_unbound` | Two hypotheses remain and are properties of the INPUT, not of the loop: `SupOk s.su` and `SupFresh s.su (sys s)` at the initial state, plus the two shipped flags `disjRule = false`, `cseMints = false` (the same flags `step_refines_all` and `learnPartitions_avoids` carry). The panic corollary is stated semantically (`env.contains` is false at the three variables a step can bind), not as a string non-equality on the panic message. |
| **R4.3** "a carrier monotone along the loop's steps, a productivity condition on the minting constructor, `mints ≤ f(s₀)` — or the exact blocking lemma with a witness hunt replayed through the compiler" | BOTH: the count is PROVED for the calculus (`KMintRun` with the productivity condition, `card_eq`, `pot_le`, `mints_le`, `kmint_bounded`), the monotone carrier is built and ingredient (B) is free (`Trail`, `Trail.carrPres`), the loop-level bound is proved from the exact remaining lemma (`HistDichotomy`, `trail_kmintRun`, `run_hist_mints_le`, `run_sys_allVars_le`) — and then the remaining lemma is REFUTED (`histDichotomy_false`), with the hunt that found the shape and the compiler replay | `mints ≤ f(s₀)` for the LOOP is therefore not obtained, and cannot be by this route. Also recorded: `Sup.drawn` is not a mint count and no carrier bound can make it one (`resolution_draws`, `step_drawn_le`). |
| **the carriers** (not a brief item; recorded because it is what round 4 removes from the search space) | ALL THREE natural carriers are refuted, two of them in Lean and the third by the round-4 reviewer with the same two witnesses: `qsys` fails ingredient (B) at an initial state (`qStepDichotomy_false`, `qstep_pot_increases`); the monotone history fails ingredient (A) (`histDichotomy_false`, `histDichotomyR_false`); and the intermediate `sys` — the carrier `LoopStrict` and `step_refines_all` are stated over — fails (B) at the SAME step as `qsys`, the `Q.++!` redirect (`Carried (sys wS) 2 {l0}` true → false, `Pot` 6 → 9; `Carried (sys mS0) 1 {l0}` true → false) | So no carrier-and-guard argument of the round-3 shape survives, and §C3.1's choice of measure carrier is closed rather than open. What is NOT ruled out is an argument that is not carrier-shaped — the dequeue order (round-5 R5.3) is the untried one. |
| **R4.4** "assemble `Terminates` with the explicit bound" | not assembled — (T2) | The vocabulary is unbounded in the tree, and R4.1/R4.3 show why the available carrier routes to bounding it fail. The counting-over-deletions direction I first named does NOT close (round-4 review U-4/T-9: the elimination bound is not input-sized, the per-pair reading enlarges the constant, and the per-key reading is refuted by this round's own hit list); the loop may PUMP, and round 5's job is to decide whether it does — the four-checkpoint specification is in §R4.4. |

## R4.6 — what a reviewer should re-run

1. `cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH && lake build Rowpartition` (849 jobs)
   and `lake env lean Audit.lean` (3376 / 0).
2. `grep -nE '\bsorry\b|\baxiom\b|\bpartial\b|native_decide|implemented_by|\bunsafe\b|\bopaque\b|Classical|\badmit\b|#exit' Rowpartition/Loop/{Refuted,Supply,Mints}.lean`
   — 0 hits in all three.
3. `#print axioms` over every theorem of the three modules (`tmp/L5r4/Axioms.lean`) — all
   standard.
4. The two refutations are the load-bearing negative results and are cheap to re-check:
   `qStepDichotomy_false` (three constraints, one step) and `histDichotomy_false` (four
   constraints, two steps).  Both are closed terms; `wS_step`, `mS0_step`, `mS1_step`,
   `wS_trace`, `mS2_drawn` are all `rfl`.
5. `git diff` scope: three NEW modules, `Rowpartition.lean` +3/−0, the plan's L5 row,
   `tracker/lean/README.md` additive, this report.  Every earlier module — `Loop/{Strict,
   StrictStep,StrictBound,Carried,Hygiene,Factor,Draws,Residual,Refine,RefineConcrete,
   RefineLearn,Order,Wf,Step}.lean` — and every Scala file UNCHANGED.
6. The compiler replays: `tracker/repro/satterm/run.sh sweep json:<seed> 0 4` on
   `tmp/L5r4/seeds/redir.json` (R4.1's witness, 3 records), `tmp/L5r4/hunt/mint.json`
   (R4.3.5's witness, `drawn=1`), and `tmp/L5r4/hunt/hist{44,52}.json` (the hunt's two hits).
7. The hunt: `python3 tmp/L5r4/hunt/gen.py 200 8 5 10 > Seeds.lean` reproduces the seeds
   bit-for-bit (a fixed `random.Random(i)` per seed), and `tmp/L5r4/hunt/Hunt.lean` re-runs the
   per-step check under `#eval`.

# Round 5 — 2026-09-05, after `L5-REVIEW.md`'s "Round-4 review" (U-4 / T-9: drive the pump)

Round 4 closed with the reviewer's structural reading of why no counting argument of the
round-3/4 shape can close: **the loop supplies its own fuel.**  A mint at key `(v, K)`
installs the carrier `v <- (w, K)` at that very key; eliminating `w` — a FREE elimination,
since `w` did not exist before the mint — withdraws the carrier; and the key is open again.
Each turn spends one binding and produces one variable, so nothing external is consumed.
Round 5's first job was to decide whether that pump runs.

**Outcome: (T2), with the pump measured at NINE turns and both of R5.2's and R5.3's repairs
refuted in Lean.**  No divergence was found — ~100,000 model solves aimed at the pump, and
3,840 solves of the deepest candidates on the shipped compiler, all terminate — so this is
not (W).  What round 5 adds to round 4's (T2) is:

* an INSTRUMENT (`Loop/Pump.lean`) that reads the minting decision off `splitConcrete`'s own
  supply and tallies it per key, compiled into `lake exe looptrace --mints`, so "how many
  times does the loop mint at one key" is now a measurement anyone can re-run;
* the measurement itself: the maximum is **9**, up from round 4's 2, on a 16-constraint
  satisfiable input the compiler solves at all ten id bases; and the pump's ENGINE, which round 4 had guessed
  wrong — the carrier is withdrawn by `cancellation` + `makeEmpty`, or, more cheaply still,
  by `makeConcrete`, which withdraws it **without binding anything at all**;
* R5.2's charging lemma stated over `Reaches` and refuted in **both** clauses
  (`chargeI_false`, `chargeII_false`), each on a satisfiable input the compiler solves;
* R5.3's dequeue-order repair stated and refuted (`repairBeforeExam_false`), with the
  structural reason: `Q.++!` puts the repairing link at the swallowed variable's PARENT, and
  `Q.pop` serves children first, so the repair is scheduled last;
* and R5.4's fragment: `Terminates` for the equational fragment, with an explicit bound
  (`linkOnly_terminates`, `linkOnly_run`), plus the residual stated exactly.

New modules: `Loop/Pump.lean`, `Loop/Dequeue.lean`, `Loop/Fragment.lean`.  Audit after:
**3494 theorems / 0 non-standard axioms, 852 jobs** (3376 / 849 before).  No Scala file is
touched; no earlier Lean module is touched except `Loop/Main.lean`, which gains the `--mints`
mode, and `Rowpartition.lean`, which gains three imports.

## R5.1 — driving the pump: the instrument, the hunt, and the compiler

### R5.1.1 The instrument (`Loop/Pump.lean` §1-2)

Round 4's hunt ran under `#eval` and asked a per-step question ("does this mint fire at a key
the history already carries?").  Round 5 asks the question R5.1 names — *how many times does
the loop mint at ONE key in one solve* — and asks it of the compiled model.

Two counters, both computed by re-running the rule rather than re-implementing it.

* `splitMintKey s` re-runs `learnPartitions`' own call to `splitConcrete`, with the same four
  lookups over the same queues, at the state's own dequeue, and reports the key
  `(dequeued lhs, concrete part)` **when the supply advanced**.  That is exact, because
  `splitConcrete` draws in its last branch and only there — `Draws.splitConcrete_drawn` bounds
  the draw by one, and round 5 adds the converse:

  > `splitConcrete_cases` — either `(splitConcrete …).2 = su`, or the whole result is
  > `(SSet.ofList [⟨(su.fresh).1, RHS.ofAbstr abstr, .splitConcrete⟩,
  > ⟨v, ⟨SSet.ofList [(su.fresh).1], concr⟩, .splitConcrete⟩], (su.fresh).2)`.
  >
  > `splitConcrete_mint_eq` — a call whose supply advanced took the mint branch, and the set it
  > returned is exactly that pair.

  **So the mint installs the carrier of its own key.**  That is link one of the pump, as a
  theorem rather than as a reading of the code.

* `carrierKeys s s'` is the wider count, and the one the hit tables use: every partition of
  the state AFTER the step whose left-hand side is the DEQUEUED variable and whose right-hand
  side is a lone variable that did not exist before the step.  `splitConcrete`'s mint
  contributes `v <- (u, K)` at its guard key and `resolution`'s contributes
  `v <- (z, C₁ ∪ C₂)` at its guard key `resolvent (C₁ ∪ C₂)`, so this counts the guard keys of
  BOTH generative rules.  It is round 4's own detector (`tmp/L5r4/hunt/Hunt.lean`), which is
  why the two rounds' numbers are comparable — and re-running round 4's own 199 seeds through
  it at base 0 gives `cmax = 2` at exactly two seeds, **74 and 139**, which are exactly the two
  the round-4 review's T-9 names as re-minting at the same `(v, K)` twice, and at no other seed
  of that population.

`pumpRun` runs the loop with both tallies plus, for the charge audit, the key's carriers after
each mint and the variable each step binds.  `lake exe looptrace <seed.json> <base> <fuel>
--mints` prints them:

```
mints  SOLVED  steps=69  drawn=30  max=1  remint=0  cmax=5  cremint=1
ckey   2  2,4,5,1  5          -- five mints at the key (v2, {l1,l2,l4,l5})
carrier 10  2  2,4,5,1        -- at dequeues 10, 44, 56, 63 and 66
bind   28  15                 -- and the eliminations in between
v0     5,10,6,9,13,2,12,7,3,11,8,4
```

`max` is the `splitConcrete`-only count and `cmax` the two-rule count.  **`max` reaches 2 in
exactly two of the ~100,000 solves** — `popH2/H2003470.json` at base 3 and
`popH2/H2006001.json` at base 2, both `SOLVED 10/10` on the compiler — and is at most 1
everywhere else.  So `splitConcrete` does re-mint at one key, but only just: essentially every
re-mint measured in rounds 4 and 5 is `resolution`'s, and every deep pump is.

### R5.1.2 The generator (`tmp/L5r5/hunt/gen5.py`, `climb.py`)

Satisfiable by construction, as in round 4: a valuation `rho` is fixed first and every
constraint is emitted as `whole <- (pairwise-disjoint parts ⊎ disjoint concrete)` over it; an
independent checker re-verifies each system.  The bias is new, and is what R5.1 asks for —
shapes where the freshly minted variable is immediately eliminated:

| knob | why |
|---|---|
| **hubs** — one or two variables carry a large row, most other rows are subsets of a hub's | both generative rules are keyed on `(lhs, concrete set)`, so concentrating the left-hand sides concentrates the KEYS, which is what a re-mint needs |
| **lone definitions at a hub**, `h <- (x, C)` with `C = rho h \ rho x` | two of these with INCOMPARABLE `C`s are `resolution`'s firing shape, and its mint installs the carrier `h <- (z, C₁ ∪ C₂)` |
| **bare concrete rows** `u <- ((|rho u|))`, empty ones included | the mint's own cancellation partner (W2/W3/G7's shape): `cancellation` turns `h <- (z, K)` against `h <- ((|rho h|))` into `z <- ((|…|))`, and `makeEmpty` / `makeConcrete` then withdraw the carrier for nothing |
| **id bases** | the dequeue order is a function of the ids; four to six bases per seed |

`climb.py` is the same generator under hill-climbing at FIXED input size: a mutation replaces
one constraint by a freshly drawn one, and the fitness is
`(max over bases of cmax, then drawn, then steps)`.  That is the direct search for R5.1's
acceptance — "a family whose draw count grows without bound at fixed input size".

### R5.1.3 The hit table

Every run at fuel 3,000 (5,000 for the climbers); every population 12-16 variables, 4-8
labels, 12-28 constraints; `cmax` is the largest number of mints at one key in that solve.

| population | vars/labels/cons | seeds | bases | solves | `cmax` 2 | 3 | 4 | 5 | 6 | 7 | 8 | FUEL | REJECTED |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| round 4's own, re-run (`g4seeds`, `g4-full.tsv`) | 8/5/10 | 199 | 12 | 2,388 | 26 | 6 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| A-H, parameter scan (`popA…popH`) | 8-14/4-7/12-20 | 1,600 | 4 | 6,400 | 103 | 22 | 12 | 1 | 0 | 0 | 0 | 0 | 0 |
| H2 (`popH2`) | 12/6/16 | 8,000 | 6 | 48,000 | 718 | 230 | 58 | 13 | 2 | 0 | 0 | 0 | 0 |
| I (`popI`) | 14/6/24 | 3,000 | 4 | 12,000 | 454 | 156 | 47 | 12 | 2 | 2 | 0 | 0 | 0 |
| J (`popJ`) | 16/8/28 | 3,000 | 4 | 12,000 | 154 | 42 | 25 | 4 | 3 | 3 | **1** | 0 | 0 |
| climbers, 4 runs, fitness = `cmax` at FIXED input size (one completed its 1,200 iterations; the other three were stopped once the maximum had been found and re-checked) | 12/6/16 | — | 4 | ≈19,000 | — | — | — | — | — | 7 × 2 | — | 0 | 0 |
| **total** | | | | **≈100,000** | | | | | | | **`cmax = 9`** | **0** | **0** |

**The maximum found is 9**, by the hill-climber (`tmp/L5r5/hunt/climb9.json` at base 0: 213
dequeues, 188 ids drawn, nine mints at one key; the same input at bases 1-3 gives 2, 3, 3, so
the depth is a property of the ORDER as much as of the system).  Round 4 measured 2.  Random
search alone reaches 8 (`popJ/J002680.json` at base 3: **75 dequeues and 24 ids drawn for eight
mints at one key** — the most efficient pump found) and 7 five times.

**0 `FUEL` and 0 `REJECTED` in every run**, at fuel 3,000 (5,000 for the climbers, 20,000 for
the re-check of the deepest witnesses) — no hang candidate arose in the model at any point, so
there was nothing to escalate to a longer cap.  Nor at any point on the compiler (§R5.1.5).

### R5.1.4 What the pump actually looks like

The reduced witness `tmp/L5r5/hunt/min2.json` (six constraints, 18 dequeues, base 2) is the
mechanism with nothing else in it, and is `Loop/Pump.lean`'s `pS0`:

```
learn  ^free2 <- (^free6,Repro.l1 Repro.l5)
new    Resolution:   ^free2 <- (^ambiguous(free)8,Repro.l1 l5 l2 l4)    -- the MINT, and its carrier
new    Cancellation: ^ambiguous(free)8 <- (,)                           -- against the bare row in the INPUT
empty  Cancellation: ^ambiguous(free)8 <- (,)                           -- makeEmpty withdraws the carrier
learn  ^free2 <- (^free7,Repro.l2 Repro.l4)
new    Resolution:   ^free2 <- (^ambiguous(free)11,Repro.l2 l4 l1 l5)   -- MINTS AGAIN, same key
```

The turn is free exactly as the reviewer predicted: the variable whose elimination re-opens
the key is the id the mint itself drew, and the fact that empties it is `cancellation` against
the bare concrete row `v2 <- ((|l1,l2,l4,l5|))` that the input already contains.  In Lean:

* `pCarrier5` / `pCarrier12` — a fresh carrier at `(v2, pKey)` is installed at the steps out of
  `pAt 5` and `pAt 12`;
* `pCarriersOf : carriersOf (pAt 6) 2 pKey = [8]` — the key's only carrier after the first
  mint is the minted id;
* `pFresh : (stateVars pS0).contains 8 = false` — which is not an input variable;
* `pBound6 = [3]`, `pBound12 = [3, 8, 5]` — and it is bound in between;
* `pSolved : Finished (run pS0 40)` — and the run SOLVES.

**And there is a cheaper turn still.**  `tmp/L5r5/hunt/minC1.json` (eight constraints, base 3,
`Loop/Pump.lean`'s `cS0`) mints twice at `(v4, {l0..l4})` four dequeues apart and binds
NOTHING in between: `cancellation` gives the mint a bare row, and `makeConcrete`'s
`destructiveSub` deletes every partition mentioning the concretised variable — the carrier
included — while writing no `SubstEnv` entry at all (`cBound5 = cBound8 = [8]`).  So a turn of
the pump need not even spend a binding.

### R5.1.5 The compiler

Every candidate with `cmax ≥ 3` — 186 distinct seeds from the random populations, plus 149
more from the `I` population, the four climbers' best inputs and the two reduced witnesses —
replayed on the SHIPPED compiler at ten id bases each:

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false" \
  tracker/repro/satterm/run.sh sweep json:<seed>.json 0 9 10 20
```

(`tmp/L5r5/hunt/replay.sh cand-all.txt replay-all.tsv 10` and `… cand-deep.txt
replay-deep.tsv 20` drive it; `replay-all.tsv` / `replay-deep.tsv` hold every `SUMMARY` and
`DRAWN` line.)

| batch | file | seeds | solves | SOLVED | REJECTED | HANG | OOM | max `drawn` |
|---|---|---|---|---|---|---|---|---|
| `cmax ≥ 3`, populations A-H2 | `replay-all.tsv` | 186 | 1,860 | 1,860 | 0 | 0 | 0 | 306 |
| `cmax ≥ 3` of `I`, the climbers' bests, `min2`, `minC1` | `replay-deep.tsv` | 149 | 1,490 | 1,490 | 0 | 0 | 0 | 444 |
| `cmax ≥ 3` of `J`, and the `cmax = 9` witness `climb9.json` | `replay-J.tsv` | 48 | 480 | 480 | 0 | 0 | 0 | 326 |
| the `splitConcrete` double-mint `H2003470` (`max = 2`) | `replay-sc.tsv` | 1 | 10 | 10 | 0 | 0 | 0 | — |
| **total (distinct seeds)** | | **384** | **3,840** | **3,840** | **0** | **0** | **0** | **444** |

**0 HANG at the 10- and 20-second caps**, so no candidate had to be confirmed under a longer
cap.  The two reduced witnesses solve on the compiler too — `min2.json` gives `SOLVED 10/10`
with `drawn` 1-5, and the model's `drawn = 4` at base 2 is the compiler's `drawn = 4` at base 2
— and so does the deepest one: `climb9.json` gives `SOLVED 10/10` in 12-538 ms, with the
compiler's own draw histogram containing 188 at base 0, exactly the model's count.

**So R5.1's answer is negative: the pump runs, it runs four and a half times deeper than round
4 measured, and it still stops.**  The evidence against a divergence is now ~130,000 model runs
across rounds 3-5 plus 3,840 compiler solves of inputs SELECTED for the pump, which is a much
sharper negative than round 4's, but it is still empirical.

## R5.2 — the charging lemma, stated so that it can be refuted, and REFUTED

### The statements, verbatim (`Loop/Pump.lean` §4)

```lean
/-- A step MINTS at the key `(v, K)` when it installs a fresh carrier of `(v, K)` at the
dequeued left-hand side. -/
def MintsAt (s s' : State) (v : Nat) (K : SSet Lbl) : Prop :=
  ∃ k ∈ carrierKeys s s', mkeyEq k (v, K) = true

/-- **The charging lemma, clause I**: between two minting steps at the SAME key `(v, K)` the
loop ELIMINATES a variable that carried the key at the first mint. -/
def ChargeI : Prop :=
  ∀ (s s' t t' : State) (v : Nat) (K : SSet Lbl),
    step s = .continue s' → MintsAt s s' v K →
    Reaches s' t → step t = .continue t' → MintsAt t t' v K →
    ∃ w ∈ carriersOf s' v K, w ∉ boundVars s' ∧ w ∈ boundVars t

/-- **Clause II** — the clause that would make the charge INPUT-SIZED, and the only one that
would close the count: the variable charged is one the loop did NOT mint. -/
def ChargeII : Prop :=
  ∀ (s0 s s' t t' : State) (v : Nat) (K : SSet Lbl),
    Reaches s0 s → step s = .continue s' → MintsAt s s' v K →
    Reaches s' t → step t = .continue t' → MintsAt t t' v K →
    ∃ w ∈ carriersOf s' v K,
      (stateVars s0).contains w = true ∧ w ∉ boundVars s' ∧ w ∈ boundVars t
```

### Both clauses are FALSE

| theorem | witness | why |
|---|---|---|
| `chargeII_false : ¬ ChargeII` | `pS0`, six constraints, base 2, mints at `(v2, pKey)` out of `pAt 5` and out of `pAt 12` | the key's ONLY carrier after the first mint is `8`, the id that mint drew (`pCarriersOf`), and `8` is not in the input's vocabulary (`pFresh`).  **The elimination the re-mint is charged to is one the loop paid for itself** — the pump |
| `chargeI_false : ¬ ChargeI` | `cS0`, eight constraints, base 3, mints at `(v4, cKey)` out of `cAt 4` and out of `cAt 8` | between the two the loop binds NOTHING (`cBound5 = cBound8 = [8]`): `makeConcrete`'s `destructiveSub` withdrew the carrier and wrote no `SubstEnv` entry.  **There is nothing for the charge to be charged to** |

Clause I's failure is the sharper of the two, and it was not anticipated by any round: the
review's reading assumed a carrier can only leave by an ELIMINATION.  It can also leave by
`makeConcrete` — which binds nothing — and by the `Q.++!` redirect (R5.3), which binds nothing
either.  So the charge cannot be repaired by charging differently; there is no event to charge.

### The audit behind the two witnesses

`tmp/L5r5/hunt/charge.py` / `chargeall.py` run the audit over every solve of the hunt whose
`cmax ≥ 2`: for each consecutive pair of mints at one key it prints the key's carriers just
after the earlier mint, the variables bound strictly between, their intersection (clause I's
charge) and the part of that intersection present in the input (clause II's charge).

| solves audited (`cmax ≥ 2`) | consecutive re-mint pairs | clause I FAILS (nothing bound in between that carried the key) | clause II HOLDS (an INPUT variable is charged) |
|---|---|---|---|
| 1,692 | 2,743 | **68** | **10** |

So clause II fails on 2,733 of 2,743 pairs and clause I on 68 — neither is a rare accident.
The two Lean witnesses are the smallest instance of each mode, reduced by
`tmp/L5r5/hunt/reduce.py` (greedy constraint dropping, satisfiability re-checked at each step)
until no further constraint can go.

### What clause II would have bought, and what survives

If clause II held, the count would follow: `Env.instantiate` rewrites the values of the
existing bindings and APPENDS the new one, so no key ever leaves the environment
(`env_instantiate_boundVars : boundVars_of (e.instantiate v val) = boundVars_of e ++ [v]`),
and `StrictBound.step_envNodup` makes the bindings distinct; so the input variables charged by
successive re-mints at one key would be pairwise distinct, and the mints at one key would be at
most `|V₀| + 1`.  Composing that with `KMintRun.mints_le` — which bounds the ADDITIVE keyed
calculus's mints by `hmeas L rho G₀` — would bound the loop's mints by
`(|V₀| + 1) · #keys`.  **That derivation is now dead at its first step**, and `#keys` is
`|allVars| · 2^{|L|}`, which is itself a function of the vocabulary the argument is trying to
bound.  What survives of it is the monotonicity fact above, which is proved.

## R5.3 — the dequeue order, and why it does not repair the redirect

The round-4 review named this "the cheapest untried lever": no measure of rounds 1-4 uses the
order, and in R4.1's witness the link `Q.++!` manufactures is dequeued at once, so the carrier
the redirect destroys is only transiently lost.  `Loop/Dequeue.lean` states the lever and
refutes it.

### What is proved about the order

```lean
/-- **`Q.pop` returns a partition of MINIMAL priority.** -/
theorem dequeue_prio_min {q : PQueue} {r : LPart} {rest : PQueue}
    (h : q.dequeue = some (r, rest)) :
    ∀ p ∈ q.elems, q.graph.prio r.lhs ≤ q.graph.prio p.lhs

/-- **The order is served strictly.** -/
theorem dequeue_not_of_lt {q : PQueue} {r : LPart} {rest : PQueue} {p : LPart}
    (h : q.dequeue = some (r, rest)) (hp : p ∈ q.elems)
    (hlt : q.graph.prio p.lhs < q.graph.prio r.lhs) : False
```

plus `dequeue_mem`, `dequeue_length_lt`, `dequeue_sub` (the dequeue removes exactly one
partition and adds none), and the redirect's own equations:

```lean
/-- **`Q.++!`'s redirect, as an equation.** -/
theorem insertP_redirect {q : PQueue} {p : LPart} {u : Nat}
    (h1 : p.isSelfUnification = false)
    (h2 : q.elems.any (fun x => PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf p) && x.eqv p)
            = false)
    (h3 : q.rhsLookup p.rhs = some u) :
    q.insertP p =
      q.insertNP ⟨u, RHS.ofAbstr (SSet.ofList [p.lhs]), some .commonPartition⟩

/-- **`PQueue.+` extends the graph with the partition's own edges.** -/
theorem insertNP_graph {q : PQueue} {p : LPart} (h1 : p.isSelfUnification = false)
    (h2 : q.elems.any (fun x => PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf p) && x.eqv p)
            = false) :
    (q.insertNP p).graph = (q.graph.addPart p).1
```

### The repair claim, and its refutation

```lean
/-- **R5.3, stated.**  "Between a carrier's loss and the next examination of its key, the
carrier is re-established." -/
def RepairBeforeExam : Prop :=
  ∀ (s s' t : State) (v : Nat) (K : SSet Lbl) (r : LPart) (rest : PQueue),
    step s = .continue s' → carriersOf s v K ≠ [] → carriersOf s' v K = [] →
    Reaches s' t → t.incm.dequeue = some (r, rest) → r.lhs = v →
    carriersOf t v K ≠ []

theorem repairBeforeExam_false : ¬ RepairBeforeExam
```

The witness is R4.1's own four-constraint satisfiable input, already in `Loop/Mints.lean`, and
the refutation needs no new run: at `mS0` the key `(v1, {l0})` is carried by `v1 <- (v0, (|l0|))`
(`rCarried : carriersOf mS0 1 rKey = [0]`); the first step empties `v0`, the erased partition
becomes the bare `v1 <- ((|l0|))`, and `Q.++!` redirects it onto the twin `v2 <- ((|l0|))`, so
every carrier is gone (`rLost : carriersOf mS1 1 rKey = []`).  The link `v2 <- (v1)` is in the
queue (`rLink : mS1.incm.elems = [mR, mD, mC]`) — and the **very next dequeue is at `v1`**
(`rNext`), and it MINTS at the uncarried key (`rMints : splitMintKey mS1 = some (1, rKey)`).

**And the order is the reason, not an accident.**  `Q.++!` inserts the link at `u`, the
variable that already held the right-hand side, and `PQueue.+` adds the edge `u → p.lhs`; so
the swallowed variable is a CHILD of the link's left-hand side, and `reverseTopSort` puts
children first.  On the witness that is `rPrio : mS1.incm.graph.prio 1 < mS1.incm.graph.prio 2`,
and with `dequeue_prio_min` it says every partition of the swallowed variable is served before
the link.  **The repair is scheduled last, exactly when it is needed first.**  What does
re-establish the carrier is the mint itself, one step later
(`rReCarried : carriersOf mS2 1 rKey = [100]`): the loop pays for the redirect's damage with a
fresh id.

So the round-4 review's "the link is dequeued immediately" holds of `wS` (R4.1's redirect
witness, where the link's endpoint is the deepest variable) and fails of `mS0`; the general
claim is false, and the graph direction says it will fail whenever the swallowed variable has
any other partition in the queue.

## R5.4 — `Terminates` for a stated fragment (`Loop/Fragment.lean`)

### The fragment, verbatim

```lean
/-- **The equational fragment.**  Every partition in either queue is a LINK `a <- (b)`: a
lone abstract part and no concrete labels.  Nothing in the state partitions anything. -/
def LinkOnly (s : State) : Prop :=
  ∀ p ∈ s.parts, p.rhs.conc.elems = [] ∧ p.rhs.abstr.elems.length = 1

/-- The measure: how many partitions the two queues hold. -/
def qsize (s : State) : Nat := s.incm.elems.length + s.proc.elems.length
```

### The theorems

```lean
/-- **The step.**  On the fragment `step` can only unify, the fragment is preserved, and the
two queues lose at least one partition. -/
theorem step_linkOnly {s s' : State} (h : LinkOnly s) (hst : step s = .continue s') :
    LinkOnly s' ∧ qsize s' < qsize s

/-- **The fragment terminates**, within `|incm| + |proc|` dequeues. -/
theorem linkOnly_terminates {s : State} (h : LinkOnly s) : Terminates s

theorem linkOnly_run {s : State} (h : LinkOnly s) : Finished (run s (qsize s + 1))
```

Three facts do the work, and each is proved rather than assumed.

1. **Only two branches are reachable.**  A right-hand side with one abstract part and no
   labels is `single?` (`single_of_link`) and is not empty (`not_isEmpty_of_link`), so
   `makeEmpty`'s branch, `makeConcrete`'s branch and `learnPartitions` are all unreachable —
   and therefore **no id is ever drawn on the fragment**.
2. **The fragment is preserved.**  `Constraints.replace`'s de-duplication arm needs the same
   right-hand side to mention BOTH variables, which a lone abstract part cannot do unless they
   are equal, and `instantiate` is only called at distinct variables
   (`replace_length_le_one`, `replace_link`).  The one partition the machinery invents on its
   own — the `Q.++!` redirect's link `u <- (p.lhs)` — is itself a link
   (`link_commonPartition`), which is why the preservation survives the redirect.
3. **The queues shrink.**  `instantiate` re-inserts at most one partition for each one it
   removed (`instantiate_link`), and the dequeued premise is gone (`dequeue_length_lt`).

The supporting size and membership lemmas are stated for the library operators, not for the
fragment, and are reusable: `incl_length_le`, `ofList_length_le`, `concat_length_le`,
`insertSorted_length`, `insertNP_length_le`, `insertP_length_le`, `concatP_length_le`,
`concatNP_length_le`, `partition_length_le`, and their membership counterparts
`sset_incl_mem`, `sset_ofList_mem`, `sset_concat_mem`, `sset_map_mem`, `insertSorted_mem`,
`insertNP_mem`, `insertP_mem`, `concatP_mem`, `concatNP_mem`, `partition_fst_mem`,
`partition_snd_mem`.  `instantiate_eq` spells `Constraints.instantiate` out with its two
pattern-`let`s expanded, which is what makes it usable in a proof at all.

### The residual, exactly

`LinkOnly` is the fragment in which the two generative rules are **syntactically
unreachable**: `splitConcrete` needs two or more abstract parts and a nonempty concrete part,
`resolution` needs two lone-variable premises whose concrete parts are incomparable.  So the
theorem says nothing about any state holding a partition with a real right-hand side.  The
distance, measured over every seed this round generated: of **15,799** seeds, **0** are
`LinkOnly`, and **0** contain even a single link constraint `a <- (b)` — the generator emits a
nonempty concrete part or two or more parts in every constraint by construction, which is what
makes those seeds able to mint at all.  The fragment is a theorem with a scope, and the scope
is small; it is offered as what R5.4 asks for, and not as progress on the general case.

What is missing for the general case is unchanged from round 4 and is now sharper: the
vocabulary is the free variable of the whole system of bounds; all three natural carriers are
refuted (round 4); the charge over eliminations is refuted in both clauses (R5.2); and the
dequeue order does not repair the redirect (R5.3).  What has NOT been ruled out is a measure
that is neither carrier-shaped nor a charge — for instance one that reads the CONCRETE-LABEL
structure of a key (every key measured in rounds 4 and 5 is a subset of the input's label pool,
which never grows, and the deepest pumps all sit at the hub's FULL row), or an argument that
bounds the supply of premise PAIRS a key can be resolved on.  Both are stated here as
directions, not as results.

## R5.5 — what round 5 could NOT prove, side by side

| asked for | what is proved | what is not, and why |
|---|---|---|
| **R5.1** "drive the pump; a generator biased to immediate elimination of the fresh variable, the model as fast oracle, every candidate with ≥3 re-mints replayed at ten bases, hangs reported at once, a divergence proved as `not_Terminates`" | the instrument (`splitMintKey`, `carrierKeys`, `pumpRun`, `looptrace --mints`) with `splitConcrete_mint_eq` proving it reads the rule itself; the generator and the hill-climber; **9 mints at one key** (round 4: 2); ~100,000 model solves, 0 `FUEL`; 384 candidate seeds × 10 bases on the compiler, 3,840 solves, 0 `HANG`; the mechanism reduced to a six-constraint and an eight-constraint witness, both in Lean and both replayed | **no divergence**, so no `not_Terminates`.  The pump turns and stops, and why it stops is not proved — the empirical reason is that each turn consumes a PAIR of lone-variable premises at the key and produces premises at OTHER variables, but that is an observation, not a lemma |
| **R5.2** "the charging lemma stated in refutable form over `Reaches`/`Trail`, and refuted or proved" | `ChargeI`, `ChargeII` stated over `Reaches`; **both refuted** (`chargeI_false`, `chargeII_false`) on satisfiable inputs the compiler solves; the monotonicity ingredient (`env_instantiate_boundVars`) proved | the count it would have bought is not obtained, and cannot be by this route: clause I fails because a carrier can leave without any binding at all |
| **R5.3** "a lemma using the real dequeue order that a carrier lost at the redirect is re-established before its key is examined again, or a seed showing it is not" | `dequeue_prio_min`, `dequeue_not_of_lt`, `dequeue_mem`, `dequeue_length_lt`, `dequeue_sub`, `insertP_redirect`, `insertNP_graph`; `RepairBeforeExam` stated and **refuted** on R4.1's own witness, with the graph-direction reason (`rPrio`) | the positive lemma is false, so no potential can be rescued by evaluating it at quiescent states.  The order is now used by L5 — but as a refutation, not as a measure |
| **R5.4** "otherwise `Terminates` for an explicitly stated fragment with the exact residual" | `LinkOnly` + `step_linkOnly` + `linkOnly_terminates` + `linkOnly_run`, with the bound `qsize s + 1`, and 21 reusable size/membership lemmas for the queue and set operators | the fragment is small, and measurably so: 0 of the 15,799 seeds this round generated are in it, and none contains even one link constraint.  Nothing is claimed beyond it |

## R5.6 — what a reviewer should re-run

1. `cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH && lake build Rowpartition` (852 jobs)
   and `lake env lean Audit.lean` (**3494 / 0**).  `lake build Rowpartition.Loop.Pump` takes
   about 95 s on this machine: the two witnesses are 13- and 9-step `rfl`s.
2. `grep -nE '\bsorry\b|\baxiom\b|\bpartial\b|native_decide|implemented_by|\bunsafe\b|\bopaque\b|Classical|\badmit\b|#exit' Rowpartition/Loop/{Pump,Dequeue,Fragment}.lean`
   — 0 hits in all three.
3. `#print axioms` over every theorem of the three modules
   (`tmp/L5r5/scratch/Axioms.lean`, output `axioms.txt`): 105 standard, 2 axiom-free.
4. The four load-bearing negatives are closed terms and cheap to re-check:
   `chargeII_false` (six constraints, 13 steps), `chargeI_false` (eight constraints, 9 steps),
   `repairBeforeExam_false` (four constraints, one step, no new run), and — the positive —
   `linkOnly_terminates`.
5. The instrument, against round 4: `python3 tmp/L5r5/hunt/genjson.py 200 8 5 10 g4seeds`
   re-emits round 4's own seeds as JSON, and
   `.lake/build/bin/looptrace g4seeds/s0074.json 0 3000 --mints` reproduces round 4's hit
   (`cmax=2`) at seeds 74 and 139 and at no other seed of that population.
6. The hunt: `python3 tmp/L5r5/hunt/gen5.py 8000 12 6 16 popH2 --hubs 1 --w 0.30,0.30,0.30,0.10 --tag H2 --start 1000`
   then `tmp/L5r5/hunt/hunt.sh popH2 6 3000 popH2.tsv 6` (a fixed `random.Random(i)` per seed,
   so the seeds reproduce bit for bit; `bighunt.sh` runs the three big populations);
   `python3 tmp/L5r5/hunt/climb.py --seed 1 --nv 12 --nl 6 --nc 16 --hubs 1 --bases 4
   --fuel 5000 --iters 1200 --out climbA` for the climber that reached 9 — its best input is
   kept as `tmp/L5r5/hunt/climb9.json`, and
   `.lake/build/bin/looptrace tmp/L5r5/hunt/climb9.json 0 20000 --mints` prints `cmax=9`
   directly.  `popJ/J002680.json` at base 3 gives `cmax=8` in 75 dequeues.
7. The charge audit: `python3 tmp/L5r5/hunt/charge.py tmp/L5r5/hunt/min2.json 2` and
   `… minC1.json 3` print the two Lean witnesses' pairs; `chargeall.py` runs it over the whole
   hunt.
8. The compiler: `tmp/L5r5/hunt/replay.sh cand-all.txt replay-all.tsv 10` (186 seeds × 10
   bases), `… cand-deep.txt replay-deep.tsv 20`, `… cand-J.txt replay-J.tsv 20` and
   `… cand-sc.txt replay-sc.tsv 20`, all with
   `ERMINE_JAVA_OPTS="-Dermine.useInterface=false"`; each `.tsv` line is one seed's `SUMMARY`
   and `DRAWN` lines.  The single deepest replay on its own:
   `ERMINE_JAVA_OPTS="-Dermine.useInterface=false" tracker/repro/satterm/run.sh sweep
   json:tmp/L5r5/hunt/climb9.json 0 9 30 20` — `SOLVED=10 HANG=0`, `DRAWN … max=208`, with
   188 at base 0, which is the model's own count.
9. `git diff` scope: three NEW Lean modules (`Loop/{Pump,Dequeue,Fragment}.lean`),
   `Rowpartition.lean` +3/−0, `Loop/Main.lean` (the `--mints` mode only), the plan's L5 row,
   `tracker/lean/README.md` additive, and this report.  Every other Lean module and every
   Scala file UNCHANGED.

# Round 6 — 2026-09-05, after `L5-REVIEW.md`'s "Round-5 review" (V-13: R6.1–R6.3)

The round-5 reviewer's judgement is that the question is **open**, and that five rounds of
*measures* have gone as far as measures can go.  His three-item specification replaces the
report's own directions, and this round follows it in his order of expected value:

* **R6.3** the fragment the corpus actually lives in — inputs with **no concrete labels**;
* **R6.1** a search for a **state cycle** (up to renaming of the minted ids), which is the
  only shape a divergence of a deterministic loop can have;
* **R6.2** the recast of termination as "**`incm` empties**", i.e. as saturation of the
  derived set rather than as any measure.

**Outcome in one line.**  **R6.3 lands, and it is the first unconditional `Terminates` of this
stage that covers real input**: `noConc_terminates` proves termination on the whole
no-concrete-labels fragment with the explicit fuel `measure3 … + 1`, and the corpus
measurement confirms the review's claim exactly — **every one of the 373 row-carrying solves
of the 129-module standard-library boot is in the fragment**, as is a quarter of the example
corpus.  Stated exactly, and this is the round's headline:

> **`Subst.solve` terminates on every row-constraint solve the Ermine standard library
> performs** — booting alone, or while any corpus program is loaded: **15,377 of 15,377**
> stdlib-located row-carrying solves across all 41 traces (373 of 373 in the bare boot) —
> because every one of them presents an input with no concrete label, and on such an input
> **the LOOP** is non-generative (`splitConcrete` and `resolution` are both refused before
> their `fresh`, so `incorporateAll` draws no id and the vocabulary is fixed) and the three
> quantities that can move — the environment, the processed set and the incoming queue — are
> each bounded by that vocabulary.

Two qualifiers on that sentence, both from the round-6 review and both applied throughout what
follows.  **The corpus-wide figure is the reviewer's** (W-6e, W-7): this round measured the bare
boot's 373 and the six example groups, and he added the `incomplete/` group and re-derived the
whole thing, getting 15,377 of 15,377 stdlib-located row-carrying solves `NoConc`, 0 with a
label.  And **"draws no id" is a statement about the LOOP, not about the whole solve** (W-6b):
`PQueue.build`'s `aux` mints a name for a `Part` whose left-hand side is not a variable
(`Constraints.scala:661–662`, modelled at `Json.lean:155–167`), and **8 of the 373 boot inputs
have exactly that shape** — a `ConcreteRho` with an EMPTY field set on the left, in
`Relation/Op.e` and `Relation.e`.  The theorem is unaffected and still covers those 8:
`noConc_terminates_of_buildQueue` starts the state at the supply `buildQueue` returns, and
`hconc` is a condition on the BUILT queue.  It is the word "solve" that has to be read as "the
loop `Subst.solve` runs", which is what `Terminates` is about.

R6.1's instrument is built, the theorem it needs is proved, and the search is a **quantified
negative: no canonical repeat in 134,674 solves and 3,082,009 canonical states** (round 5's
whole population re-run, 183 deep candidates at ten id bases, and a fresh 50,000-solve hunt),
with 0 `FUEL` and 0 `REJECTED`.  R6.2 is **(T1) for the recast** and **(T2)** for the residual, with its strong form
(`GuardComplete`) refuted by round 5's own witnesses — and the residual is FRAGMENT-RELATIVE
(review W-6d): `terminates_of_bounds` carries `NoConc` along the run, so off the fragment it is
no sharper than round 4's or round 5's.

New modules: `Loop/Cycle.lean` (375 lines, 13 theorems), `Loop/NoConc.lean` (1,722 lines,
88 theorems).  `Loop/Main.lean`
gains a `--cycle` mode; `Rowpartition.lean` gains two imports.  No other Lean module and no
Scala file is touched.  Audit after: **3611 theorems / 0 non-standard axioms, 854 jobs**
(3494 / 852 before).

## R6.3 — the NO-CONCRETE-LABELS fragment (`Loop/NoConc.lean`)

### R6.3.1 The fragment, verbatim

```lean
/-- **The no-concrete-labels fragment.**  No partition of either queue carries a field label.
The state is a system of pure decompositions `a <- (b, c, ...)` over row variables. -/
def NoConc (s : State) : Prop := ∀ p ∈ s.parts, p.rhs.conc.elems = []
```

`State.parts` is `s.incm.elems ++ s.proc.elems` (`Loop/Wf.lean:1008`), so `NoConc s₀` at an
initial state — where `proc` is empty — is exactly "every INPUT partition has an empty
concrete part", which is what the corpus measurement below tests.

### R6.3.2 Both generative rules are unreachable, and the LOOP draws no id

```lean
/-- **`splitConcrete` is unreachable**: its first guard refuses an empty concrete part, so it
returns nothing and does not draw. -/
theorem splitConcrete_noConc {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (h : concr.elems = []) :
    splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su = (SSet.empty, su)

/-- **`resolution` is unreachable** at a premise with two or more abstract parts: the
lone-variable pattern fails before the `fresh`, so nothing is emitted AND no id is drawn. -/
theorem resolution_noConc {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (h : rhs1.abstrSingle? = none) :
    resolution fl v rhs1 rhs2 resolvent concRow emptyRow su = (SSet.empty, su)
```

The second is **stronger than the review's R6.3 predicts**.  V-13 says "`resolution` still
draws an id before its guards — round 4's `resolution_draws` — so the theorem is *no fresh
variable enters a partition*, not *no id is drawn*."  That is right about `resolution` in
general and wrong about it on this fragment, and the reason is one line of
`Constraints.scala`: `resolution` (`:1768`) is
`if (!GenRules.resolves) Set() else (rhs1, rhs2) match { case (RHS(Single(x), concr1),
RHS(Single(y), concr2)) => val z = fresh(…)` — the draw sits INSIDE the lone-variable arm, not
before the match.  On the fragment the
dequeued premise of a `learn` step has an empty concrete part and is not `single?` (or the
dispatch would have unified), so `RHS.single?` and `RHS.abstrSingle?` coincide
(`single_eq_abstrSingle`) and the premise has **two or more abstract parts** — the pattern
fails, and the rule returns before the draw.  The consequence is recorded in the step lemma:

```lean
/-- **The step, on the fragment.**  `NoConc` is an invariant of `step`, the `concrete`
dispatch branch is unreachable, and the supply does not move: the fragment is closed under
the loop and the loop is non-generative on it. -/
theorem step_noConc {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : NoConc s) (hst : step s = .continue s') :
    NoConc s' ∧ s'.su = s.su ∧ s'.flags = s.flags

/-- ...and therefore along a whole run. -/
theorem run_noConc : ∀ (n : Nat) {s s' : State}, s.flags.disjRule = false →
    s.flags.cseMints = false → NoConc s → Runs n s s' →
    NoConc s' ∧ s'.su = s.su ∧ s'.flags = s.flags
```

**Scope of "no id is drawn" (round-6 review W-6b).**  `step_noConc`'s `s'.su = s.su` is about
`step`, i.e. about `incorporateAll`.  It says nothing about `PQueue.build`, which runs BEFORE
the loop and does draw when a `Part`'s left-hand side is not a variable
(`Constraints.scala:661–662`); on the stdlib boot that happens on 8 of the 373 solves, whose
left-hand side is a `ConcreteRho` with an empty field set.  Those 8 are still inside the
fragment and still covered by the theorem — an empty concrete row contributes no label, so
`NoConc` holds of the built queue, and `noConc_terminates_of_buildQueue` takes the state at the
post-build supply.  Everywhere below, "no id is drawn" means "the loop draws no id".

The two flag hypotheses are the SHIPPED defaults (`GenRules` reads `genRules=cut`, so
`cseMints = false`, and `-Dermine.disjunction` ships off); they are the same two
`Loop/Supply.lean`'s `learnPartitions_new` and `Loop/Hygiene.lean`'s `step_queueHygiene`
carry.  `splitRow`, `resRow`, `resGuard`, `splitKey`, `labelCheck` are NOT restricted.

What the preservation costs, rule by rule — every one of these is proved, none assumed:
`rhsMerge_conc`, `rhsSubstitute_conc`, `selfSubstitution_conc`, `cancellation_conc`,
`subBody_conc`, `substitution_conc`, `commonSubexpression_conc` (all five of its branches,
including the mint it does not take), `commonSubexpression_su_of_cut`, then
`learnPartitions_noConc` for the fold, `replace_conc` / `instantiate_conc` / `unifyVars_conc`
for the two link branches, `makeEmpty_conc` for the empty branch, and — the one branch that
simply cannot fire — `makeConcrete`, whose dispatch needs `RHSConcr`, i.e. an empty ABSTRACT
part; with an empty concrete part too the right-hand side is `RHSEmpty` and the previous
branch has already taken it.

```lean
/-- **The `learn` step, on the fragment.**  With no labels in the dequeued premise or in the
processed queue, `learnPartitions` derives only label-free partitions and draws no id. -/
theorem learnPartitions_noConc {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hc1 : rhs1.conc.elems = []) (hsg : rhs1.abstrSingle? = none)
    (hp : ∀ x ∈ proc.elems, x.rhs.conc.elems = [])
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    su' = su ∧ ∀ x ∈ S.elems, x.rhs.conc.elems = []
```

### R6.3.3 Termination on the fragment, with an explicit bound — PROVED

Every `continue` step of the fragment is one of three kinds, and each moves one of three
quantities:

```lean
/-- The trichotomy.  On the fragment the `concrete` branch is unreachable, so these three
cases are exhaustive. -/
theorem step_trichotomy {s s' : State} (hnc : NoConc s) (h : step s = .continue s') :
    (IsLearnStep s ∧ s'.env = s.env) ∨
    (s'.env.binds.length = s.env.binds.length + 1) ∨
    (s'.env = s.env ∧ s'.proc = s.proc ∧ s'.incm.elems.length + 1 = s.incm.elems.length)
```

* a `learn` step strictly GROWS the processed set — `Order.learn_procSys_lt`, round 3: the
  dequeued premise is `Partition.equals`-new, or the COMMON branch would have fired — and
  leaves the environment alone;
* a `common` / `unify` / `empty` step at DISTINCT variables strictly grows the environment
  (`StrictBound.instantiate_env_len`, `makeEmpty_env_len`: `instantiateType` panics on a
  variable already bound, so each of these branches adds exactly one binding);
* a `common` / `unify` step at EQUAL variables changes nothing at all except that the
  dequeued partition is gone — `unify` at equal variables is the identity, which is
  `Order.common_self_drops`'s observation — so the incoming queue strictly shrinks.

Flattening that lexicographic order gives an explicit fuel, from three BOUNDS:

```lean
/-- The lexicographic measure, flattened: the environment's room to grow weighs most, then
the processed set's, then the incoming queue's own length. -/
def measure3 (P Q E : Nat) (s : State) : Nat :=
  (E - s.env.binds.length) * ((P + 1) * (Q + 1)) +
    (P - (procSys s).card) * (Q + 1) + s.incm.elems.length

/-- **The measure strictly decreases at every step of the fragment**, given the three
bounds. -/
theorem measure3_lt {P Q E : Nat} {s s' : State} (hw : Wf s) (hnc : NoConc s)
    (hP' : (procSys s').card ≤ P) (hQ' : s'.incm.elems.length ≤ Q)
    (hE' : s'.env.binds.length ≤ E) (h : step s = .continue s') :
    measure3 P Q E s' < measure3 P Q E s

theorem terminates_of_bounds {P Q E : Nat} {s : State}
    (hw : ∀ t, Reaches s t → Wf t) (hnc : ∀ t, Reaches s t → NoConc t)
    (hp : ∀ t, Reaches s t → (procSys t).card ≤ P)
    (hq : ∀ t, Reaches s t → t.incm.elems.length ≤ Q)
    (he : ∀ t, Reaches s t → t.env.binds.length ≤ E) : Terminates s
```

and all three bounds are then DISCHARGED, at `V := allVars (sys s)`, the initial state's own
vocabulary.

**The vocabulary, first.**  This is what round 5 left open, and on the fragment it closes.
`Loop/Hygiene.lean`'s `Avoids B` machinery is parametric in `B`, and at `B := (· ∉ V)` the
statement "every variable of `p` is in `V`" IS `Avoids B p.toConstraint`
(`avoids_toConstraint_iff`).  Every rule lemma there is usable at that `B` except
`commonSubexpression_avoids`, which carries a `SupAvoids B su` hypothesis it needs only for the
minting branch `genRules=cut` closes; `commonSubexpression_avoids_cut` supplies the variant.
The `learn` fold and the step then go through:

```lean
/-- **The vocabulary clause for the `learn` branch, on the fragment.**  Every partition
`learnPartitions` derives mentions only variables the premises already mention.  This is the
clause `Loop/Supply.lean`'s `learnPartitions_new` could not give: its conclusion is
`Avoids (New Old su')`, i.e. "old OR unreachable", and the second disjunct is what a
vocabulary bound cannot afford.  On the fragment it can be dropped, because neither generative
rule fires. -/
theorem learnPartitions_avoidsV {B : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hc1 : rhs1.conc.elems = []) (hsg : rhs1.abstrSingle? = none)
    (hv : ¬ B v) (hr1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint

/-- **Every variable of the state is in `V`** -- in either queue and in the environment. -/
def InVoc (V : Finset Var) (s : State) : Prop :=
  (∀ p ∈ s.parts, Avoids (fun w => w ∉ V) p.toConstraint) ∧
    (∀ b ∈ s.env.binds, Avoids (fun w => w ∉ V) (EnvVal.toConstraint b.1 b.2))

/-- **The vocabulary does not grow, on the fragment.** -/
theorem step_inVoc {V : Finset Var} {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hnc : NoConc s) (h0 : InVoc V s)
    (h : step s = .continue s') : InVoc V s'

/-- Every state is `InVoc` at its OWN vocabulary, so the `V` of the bounds is not an
assumption: it is `allVars (sys s)` of the initial state. -/
theorem inVoc_self (s : State) : InVoc (allVars (sys s)) s
```

**Then the three bounds.**

```lean
/-- **Bound one: the environment.** -/
theorem env_len_le_card {V : Finset Var} {s : State} (h : InVoc V s) (hnd : EnvNodup s) :
    s.env.binds.length ≤ V.card

/-- **Bound two: the processed set.**  Every processed partition is a `mk`-shaped constraint
over `V` with an empty concrete part, so it is one of `DefaultTerm.forms V ∅`. -/
theorem procSys_card_le {V : Finset Var} {s : State} (h : InVoc V s) (hnc : NoConc s) :
    (procSys s).card ≤ V.card * 2 ^ V.card
```

**Bound three is the queue, and it needed a fact nothing in the development had.**  The queue
bounds itself: `Q.insert` refuses a partition already present AT THE SAME SEARCH KEY
`(rhs.hashCode, lhs.hashCode)`, and its test is one-directional (`x.eqv p` against the elements
already there), so what an insertion establishes for a PAIR is that at least one of the two
directions fails — which is symmetric, hence a `List.Pairwise` invariant:

```lean
/-- The queue's own de-duplication test, symmetrised. -/
def KRel (a b : LPart) : Prop :=
  (PQueue.keyEq (PQueue.keyOf a) (PQueue.keyOf b) && a.eqv b) = false ∨
    (PQueue.keyEq (PQueue.keyOf b) (PQueue.keyOf a) && b.eqv a) = false

def KDist (l : List LPart) : Prop := l.Pairwise KRel
```

Turning it into a length bound needs `Partition.equals` to imply equality of the SEARCH KEY,
i.e. `RHS.hashCode` not to depend on a set's iteration order.  It does not, and the reason is
arithmetic — **`MurmurHash3.unorderedHash` folds a sum, an exclusive-or and a product, all
commutative and associative on a Java `int`**:

```lean
theorem unorderedHash_perm {l1 l2 : List I32} (h : l1.Perm l2) (seed : I32) :
    Murmur.unorderedHash l1 seed = Murmur.unorderedHash l2 seed

theorem keyEq_of_eqv {p q : LPart} (hpa : p.rhs.abstr.Nodup) (hpc : p.rhs.conc.Nodup)
    (hqa : q.rhs.abstr.Nodup) (hqc : q.rhs.conc.Nodup) (h : p.eqv q = true) :
    PQueue.keyEq (PQueue.keyOf p) (PQueue.keyOf q) = true

/-- The separating map: on the fragment a partition is determined, up to `Partition.equals`,
by its left-hand side and the SET of its abstract parts. -/
def sepMap (p : LPart) : Nat × Finset Nat := (p.lhs, p.rhs.abstr.elems.toFinset)

theorem kdist_length_le {V : Finset Var} {s : State} {l : List LPart}
    (hw : Wf s) (hnc : NoConc s) (hv : InVoc V s)
    (hsub : ∀ p ∈ l, p ∈ s.parts) (hk : KDist l) :
    l.length ≤ V.card * 2 ^ V.card
```

(The `Nodup` side conditions are `Wf`'s four, which `Loop/Wf.lean`'s `step_wf` has carried
since L3; `SSet.eqv_iff_toFinset` and `List.perm_of_nodup_nodup_toFinset_eq` do the rest.)

**And the theorem:**

```lean
/-- **`Terminates` ON THE FRAGMENT, with an explicit bound.** -/
theorem noConc_terminates {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s) (hnc : NoConc s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) : Terminates s

/-- The same, as the explicit FUEL. -/
theorem noConc_run {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s) (hnc : NoConc s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) :
    Finished (run s
      (measure3 ((allVars (sys s)).card * 2 ^ (allVars (sys s)).card)
        ((allVars (sys s)).card * 2 ^ (allVars (sys s)).card) (allVars (sys s)).card s + 1))

/-- **The corollary for a real solve.**  An INITIAL state -- `proc` and `env` empty and the
incoming queue built by `Json.buildQueue`, which is the shape both `Seed.solve` and
`Replay.replay` construct -- whose INPUT partitions carry no concrete label TERMINATES. -/
theorem noConc_terminates_of_input {ps : List LPart} {fl : Flags} {ns : Names} {site : String}
    {su : Sup} {tr : List String} {z : Nat}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hconc : ∀ p ∈ (PQueue.ofList ps).elems, p.rhs.conc.elems = [])
    (hw : Wf { incm := PQueue.ofList ps, proc := PQueue.empty, env := {}, su := su,
               trace := tr, flags := fl, names := ns, site := site, su0 := z }) :
    Terminates { incm := PQueue.ofList ps, proc := PQueue.empty, env := {}, su := su,
                 trace := tr, flags := fl, names := ns, site := site, su0 := z }
```

**The bound, written out.**  With `n := |allVars (sys s₀)|` the fuel is
`measure3 (n·2ⁿ) (n·2ⁿ) n s₀ + 1`, i.e. at most
`n · (n·2ⁿ + 1)² + (n·2ⁿ) · (n·2ⁿ + 1) + |incm₀| + 1` dequeues — a bound of order `n²·4ⁿ`.  It
is not tight and is not meant to be: the three factors are (the number of variables that can
be eliminated) × (the number of distinct label-free constraints over them) × (the queue's own
capacity), and every one of the three is the crude combinatorial count.  On the stdlib boot
`n` is at most 13 partitions' worth of variables and the loop finishes in at most a few dozen
dequeues; the theorem's job is to be finite, not small.

```lean
/-- **The theorem a reviewer applies to a real solve.**  Both `Seed.solve` and
`Replay.replay` build `{ incm := q, proc := empty, env := {}, ... }` with
`buildQueue cs su = .ok (q, su')`; `Wf` of that state is `Wf.wf_initial` / `Wf.wf_seed` /
`Wf.wf_replay`.  If the built queue carries no concrete label -- which is what the corpus
measurement tests, and what all 373 row-carrying stdlib-boot solves satisfy -- the solve
TERMINATES. -/
theorem noConc_terminates_of_buildQueue {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hconc : ∀ p ∈ q.elems, p.rhs.conc.elems = [])
    (hw : Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := tr,
               flags := fl, names := ns, site := site, su0 := z }) :
    Terminates { incm := q, proc := PQueue.empty, env := {}, su := su', trace := tr,
                 flags := fl, names := ns, site := site, su0 := z }
```

**Hypotheses, and why none of them is a weakening.**  `disjRule = false` and `cseMints = false`
are the SHIPPED defaults and are the same two `RefineLearn.step_refines_all`,
`Supply.step_supFresh` and `Hygiene.step_queueHygiene` carry.  `Wf` is L3's invariant, proved
for every initial state (`Wf.lean` §8) and preserved (`step_wf`).  `EnvNodup` and the two
`KDist`s are DISCHARGED at an initial state by `noConc_terminates_of_input`
(`envNodup_initial`, `kdist_ofList`, and `PQueue.empty`), which is the shape `Seed.solve` and
`Replay.replay` build.  So the corollary's only real hypothesis is the fragment itself.
(`Wf.wf_replay`'s own side condition `CsItem.SetsOk` — "every concrete row really is a set" —
is vacuous on the fragment: a `concRho fs` with a nonempty `fs` would put a label into the
built partition, so on a `NoConc` input every `concRho` is empty and `[].Nodup` holds.)

**And what the certification is a certification OF.**  The theorem is about the LOOP MODEL,
`Rowpartition.Loop.step`.  The bridge to the compiler is stage L2's, and it is the strongest
one this project has: the model reproduces `Constraints.incorporateAll`'s own
`-Dermine.rowTrace` records — branch, partition, `incm=`, `proc=`, every `learn` line, the
saturated set — on **2,355,430 corpus segments with 0 mismatches and 0 skips**
(`L2-CORPUS.md` §4a), including all 54,199 of the boot's.  So "the standard library boot
terminates" is proved of the model and verified of the compiler on exactly those solves; it is
not a claim about `Subst.solve`'s Scala source read directly.
### R6.3.4 The corpus measurement — every row-carrying stdlib-boot solve is in the fragment

Traces regenerated from scratch for this round (not the round-5 reviewer's), one JVM per
corpus group, serialised loader, interfaces off:

```
ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx3000m -Dermine.useInterface=false \
  -Dermine.loadInSeries=true -Dermine.rowTrace=<out>/<group>.tsv" bin/ermine <group's files>
```

(`tmp/L5r6/gentrace.sh`; the seven groups `boot top Ai shouldfail bugs guide
shouldfail-controls` = 75 of the 110 example files.  `incomplete/` — the remaining 35, run
one JVM per file because several are non-terminating by design — is NOT included; see the
caveat below.)  The census reads the `inpart` records (`Subst.scala:1215`, fields
`prov / lhs / abstr / conc`), segmenting per THREAD at `sin` boundaries:
`python3 tmp/L5r6/fragcensus.py tmp/L5r6/traces/*.tsv.gz`.

| group | solves | with a row constraint | building ≥1 partition | **`NoConc`** | with a concrete label | `LinkOnly` (R5.4) |
|---|---|---|---|---|---|---|
| `boot` (129-module stdlib) | 54,199 | 383 | **373** | **373 (100 %)** | **0** | 4 |
| `top` | 92,673 | 5,424 | 5,412 | 1,670 | 3,742 | 5 |
| `Ai` | 83,942 | 4,494 | 4,484 | 1,461 | 3,023 | 5 |
| `shouldfail` | 56,032 | 647 | 605 | 442 | 163 | 4 |
| `bugs` | 54,235 | 383 | 373 | 373 | 0 | 4 |
| `guide` | 54,244 | 383 | 373 | 373 | 0 | 4 |
| `shouldfail-controls` | 54,739 | 447 | 437 | 391 | 46 | 4 |

`bugs` and `guide` reproduce `boot` exactly, which is L2-CORPUS §4a's point that those two
groups raise no row constraint of their own.  The per-group figures therefore double-count the
boot; de-duplicated by `loc`, the EXAMPLE corpus proper is
(`python3 tmp/L5r6/excensus.py tmp/L5r6/traces/{top,Ai,shouldfail,bugs,guide,shouldfail-controls}.tsv.gz`):

| population | solves | building ≥1 partition | **`NoConc`** | with a concrete label | `LinkOnly` |
|---|---|---|---|---|---|
| solves whose `loc` is under `core/examples` | 48,583 | **9,362** | **2,388 (25.5 %)** | 6,974 | **0** |

Three readings, and the first is the round's headline measurement:

* **The whole stdlib boot is in the fragment.**  All 383 row-carrying boot segments are
  `NoConc`; 373 of them build at least one partition and 10 build none at all (`nRows > 0`
  but every row constraint is discharged before `PQueue.build` — those are trivially finished
  in one dequeue).  **0** boot solves carry a concrete label anywhere in their input.  The
  round-5 review's "373 row-carrying boot solves" and L2-CORPUS §4a's "383" are the same
  population counted with and without those 10.
* **The step census bears it out.**  Over the whole `boot` trace the derived-partition
  provenance histogram is `CommonSubexpression 221, Substitution 114, Cancellation 9` and the
  dispatch histogram is `learn 1056, unify 38, empty 30, common 19` — **zero `Resolution`,
  zero `SplitConcrete`, zero `SplitKeyed`, zero `concrete` steps**, which is exactly what
  `splitConcrete_noConc`, `resolution_noConc` and the unreachability of the `concrete` branch
  predict.  On the examples the two generative rules DO fire: `SplitConcrete 422`,
  `Resolution 106`, `SplitKeyed 23`, `SplitRow 1`, `ResolutionRow 6`.
* **`LinkOnly` (round 5's fragment) is 4 of 373 on the boot and 0 of 9,362 on the examples**,
  which reproduces the round-5 review's W-1 (his 4 and 5) and shows how much the widening is
  worth: from 4 solves to all 373.  (His fifth is `Layout/Scan.e(1:1)`, a stdlib module the
  bare boot does not load but every example group does; it is a `core/target/…/modules/` `loc`,
  so this table counts it under the group and the examples-only table does not count it at
  all.)
* **And the residual holds empirically where the proof is missing.**  Of the 373 boot solves,
  361 write a saturated set; in **361 of 361** that set is concrete-free (which
  `run_noConc` proves) **and mentions no variable absent from the input** (which is exactly
  the vocabulary clause R6.3.3 names as missing).  On the examples the second figure is 1,843
  of 1,878 for the round-5 reviewer's ten-module set — the 35 exceptions are solves where the
  generative rules fired, i.e. precisely outside the fragment.

**What the measurement certifies, stated exactly.**  Combining it with R6.3.3:

> Termination is proved for every solve of the Ermine standard library that raises a row
> constraint — 373 of 373 in the bare boot, and **15,377 of 15,377 stdlib-located row-carrying
> solves across all 41 traces** (round-6 review W-6e, W-7) — and with it non-generativity: on
> those solves the loop draws no id, invents no variable, and both minting rules are refused
> before their `fresh`.

The stronger figure is the reviewer's, and it is worth stating separately because it is a
different claim: not "the boot's own 373, repeated in every group", but every solve any stdlib
module performs while any corpus program is loaded.  He counted **2,322 row-carrying solves
with a stdlib `loc` across the six example groups, 2,322 of 2,322 `NoConc`, 0 with a label**,
and — closing the caveat this round recorded — traced all 34 `.e` modules of `incomplete/`
(1,851,131 segments, all finishing inside a 90 s cap) and found its stdlib half **12,682 of
12,682 `NoConc`**, with the group's OWN solves the thinnest part of the corpus (425 of 1,283,
33 %) and its labelled inputs concentrated in exactly the label-heavy modules it exists for.

The step census is the independent check on the last clause: **0 `Resolution` and 0
`SplitConcrete` records in 54,199 boot segments**.  On the examples the fragment covers 2,388
of 9,362 row-carrying solves (25.5 %), so a quarter of the example corpus is certified too and
the rest is not.  The one population this round did not measure was the 35 `incomplete/` files — skipped because
they are non-terminating by design and a rowTrace of one writes ~8 MB/s.  **The round-6 reviewer
measured them (W-7) and the caveat is closed**: all 34 `.e` modules of the group finish inside a
90 s cap, and of their 13,965 partition-building row-carrying solves, the 12,682 with a stdlib
`loc` are 12,682 `NoConc` and the 1,283 of the group's own are 425 `NoConc` / 858 labelled.

### R6.3.4a How much further the fragment could go — a measurement for round 7

`NoConc` is proved and covers 100 % of the boot and 25.5 % of the examples.  The obvious
question is what the next fragment should be, and the traces answer it
(`python3 tmp/L5r6/nextcensus.py tmp/L5r6/traces/{top,Ai,shouldfail,bugs,guide,shouldfail-controls}.tsv.gz`):

| of the 9,362 row-carrying EXAMPLE solves | count | share |
|---|---|---|
| `NoConc` — the proved fragment | 2,388 | 25.5 % |
| `splitConcrete` cannot fire on the INPUT (no partition has a nonempty concrete part AND ≥2 abstract parts) | 9,256 | 98.9 % |
| `resolution` cannot fire on the INPUT (no two lone-abstract premises at one variable with incomparable concrete parts) | **9,362** | **100 %** |
| NEITHER can fire on the input | 9,256 | 98.9 % |
| the run in fact derived nothing by any generative rule (measured from the `sat` provenances) | 9,146 | 97.7 % |
| **…blocked at the input yet a generative rule FIRED anyway** (reviewer, W-9) | **111** | **1.2 %** |
| the saturated set introduces a variable absent from the input (reviewer, W-9) | 220 of 9,340 | 2.4 % |
| **the vocabulary demonstrably NOT grown — the honest ceiling** (reviewer, W-9) | **9,120** | **97.6 %** |

So the corpus is overwhelmingly non-generative, and the gap between 25.5 % and 98.9 % is
entirely a PRESERVATION question: on 9,256 of the 9,362 the two rules are blocked at the input,
and on 9,146 they never fire at all, but "blocked at the input" is not an invariant — a step
can create a partition with a nonempty concrete part and two abstract parts (that is what
`substitution` and `commonSubexpression` do), and `NoConc` is the largest condition this round
could prove closed under `step`.

**And the round-6 reviewer put a number on that, which REFUTES the naive widening (W-9).**  Of
the 9,256 example solves where neither generative rule can fire on the input, **111 fire one
anyway during the run** — `SplitConcrete` 230 firings, `Resolution` 106, `SplitKeyed` 23,
`ResolutionRow` 6, `SplitRow` 1 — and the partitions that unblock `splitConcrete` are derived by
`Substitution` (164) and `CommonSubexpression` (37).  So the input-only condition is **not an
invariant, and the corpus exhibits its failure 111 times**: a round 7 cannot simply widen
`NoConc` to it.  The reviewer also measured the honest ceiling for the property
`noConc_terminates` actually uses — the vocabulary being fixed: of the 9,340 example solves with
a saturated set, **220 (2.4 %) introduce a variable absent from the input** and **9,120 (97.6 %)
demonstrably do not**.  **97.6 %, not 98.9 %, is the target**, and the missing 2.4 % is where
the whole open problem lives.  A round 7 aiming at "no id is ever DRAWN into a partition" would
certify that, and much of this round's
machinery transfers unchanged — `measure3_arith`, `env_len_le_card`, every `KDist` preservation
lemma, `unorderedHash_perm` and `keyEq_of_eqv` are stated for arbitrary states.  Three things
would have to be redone, and they are exactly where `NoConc` is used beyond fixing the
vocabulary: `step_trichotomy` uses it to make the `concrete` dispatch branch unreachable (a
wider fragment must either kill that branch too or find something that decreases on it — the
one branch `StrictBound.lean` already flags as unbounded), and `procSys_card_le` and
`kdist_length_le` use `conc = ∅` to make `(lhs, the set of abstract parts)` a separating map
(with labels the map has to carry the concrete part, and the bound picks up the `2^{|L|}`
factor `DefaultTerm.card_forms_le` already has).

### R6.3.4b The fragment is inhabited, and it is entirely inside the satisfiable class

Two small facts that a reviewer will want and that the round-5 review asked for about
`LinkOnly` (its V-7 item 5):

```lean
/-- **The fragment is inhabited by a state that runs.**  Three label-free constraints over
five variables, at id base 5. -/
def nS0 : State := …   -- `buildQueue` of the three constraints, `proc` and `env` empty
theorem nS0_size : nS0.incm.elems.length = 3 := rfl
theorem nS0_noConc : NoConc nS0
theorem nS0_solved : Finished (run nS0 40) := trivial
theorem nS0_nodraw : (match run nS0 40 with | .solved s => s.su.drawn | _ => 99) = 0 := rfl

/-- **The fragment is entirely inside the SATISFIABLE class**, so the plan's acceptance
criterion ("for every satisfiable `Wf s₀`") costs nothing here: a system with no concrete
label is satisfied by sending every variable to the EMPTY row. -/
theorem ssat_of_no_conc {G : System} (h : ∀ c ∈ G, c.conc = (∅ : Finset Label)) : SSat G
```

The second matters for the plan's L5 row: the acceptance criterion quantifies over
*satisfiable* `Wf s₀`, and on this fragment satisfiability is free — every label-free partition
system has the all-empty model — so `noConc_terminates` needs no satisfiability hypothesis and
loses nothing by not having one.

### R6.3.5 The theorem checked against the model and against the compiler

Three independent checks, because a termination theorem whose fragment is empty in practice is
worth nothing and one whose hypotheses are subtly wrong is worse.

| check | command | result |
|---|---|---|
| the model on the WHOLE corpus | `looptrace --replay <group>.tsv` on the four traces this round generated | `boot` **54,199 replayed, 0 skipped, 0 hashdiff, 0 eqdiff, 0 rejected, 0 FUEL**; `top` 92,673 / 0 / 0; `Ai` 83,942 / 0 / 0; `shouldfail` 56,032, 0 fuel, 32 rejected (those modules are meant to fail) |
| the model on 5,244 SYNTHETIC label-free solves | `tmp/L5r6/hunt/gennoconc.py 1500 10 5 14 popNC` then `huntc.sh popNC 4 3000 popNC.tsv 6` | 1,311 seeds × 4 id bases = **5,244 solves, all SOLVED, 0 FUEL, and 0 ids drawn in total** — `step_noConc`'s `s'.su = s.su`, measured |
| the SHIPPED COMPILER on ten of those seeds at ten id bases | `ERMINE_JAVA_OPTS=-Dermine.useInterface=false tracker/repro/satterm/run.sh sweep json:<seed> 0 9 30 20` | **100 solves, `SOLVED=10 REJECTED=0 HANG=0 OOM=0` on every seed, and `DRAWN min=0 median=0 max=0 histogram 0:x10` on every seed** — the compiler draws no id either.  (These seeds' left-hand sides are all variables, so `PQueue.build` draws nothing on them and the 0 is the whole solve's, not only the loop's — see W-6b above) |

The generator (`gennoconc.py`) fixes a valuation first and emits only `w <- (v₁ … v_k)` with the
parts' rows pairwise disjoint and their union `rho w` and NO labels anywhere, so every seed is
satisfiable by construction and every seed is in the fragment; a checker re-verifies the label
count is zero.

## R6.1 — a STATE CYCLE, up to renaming of the minted ids (`Loop/Cycle.lean`)

### R6.1.1 The theorem: a repeat is `not_Terminates`

The review promised this in "one line (`run` is deterministic)".  It is one line once `step`
is known to be a function of the state's OPERATIVE part — which had never been stated, because
`State` also carries the trace, the site and `su0`, and the trace grows at every step, so
literal state equality never recurs and the naive statement is vacuous.

```lean
/-- **The operative core of a state.**  `step` reads the two queues, the environment, the
supply, the flags and the name table, and writes the first four; `trace`, `site` and `su0`
are carried for the records and never inspected by a rule. -/
def SEq (s t : State) : Prop :=
  s.incm = t.incm ∧ s.proc = t.proc ∧ s.env = t.env ∧ s.su = t.su ∧
    s.flags = t.flags ∧ s.names = t.names

/-- **`step` is a function of the core.** -/
theorem step_decor (s : State) (tr : List String) (si : String) (z : Nat) :
    ∀ s', step s = .continue s' →
      ∃ t', step { s with trace := tr, site := si, su0 := z } = .continue t' ∧ SEq s' t'

/-- **The congruence, forwards.** -/
theorem step_congr {s t : State} (h : SEq s t) {s' : State} (hs : step s = .continue s') :
    ∃ t', step t = .continue t' ∧ SEq s' t'

/-- `n` `continue` steps from `s` to `t`. -/
def Runs : Nat → State → State → Prop
  | 0, s, t => s = t
  | n + 1, s, t => ∃ s', step s = .continue s' ∧ Runs n s' t

/-- **A CYCLE IS A DIVERGENCE.**  If a run of `n ≥ 1` `continue` steps returns to a state
`SEq`-equal to where it started, the loop does not terminate.  `run` is a function of `step`
and `step` is a function of `SEq`, so nothing more is needed. -/
theorem not_terminates_of_cycle {s t : State} {n : Nat} (hn : 0 < n) (hr : Runs n s t)
    (heq : SEq t s) : ¬ Terminates s
```

`step_decor` is the whole content: five dispatch branches, each showing that changing the
three decorative fields changes only the three decorative fields of the answer, plus
`foldl_log_state` for the `learn` branch's record fold (`RefineLearn.lean` had the `env` and
`flags` projections of that; the general form is what `SEq` needs).  `run_seq` lifts it to
`run`, and `not_terminates_of_cycle` is a strong induction on the fuel: an answer at fuel `m`
gives one at `m − n`, and `Runs.not_finished` says there is none below `n`.

### R6.1.2 The canonical form, and what the quotient is NOT

```lean
/-- The minted ids of a state, in FIRST-OCCURRENCE order: the incoming queue then the
processed queue, each in its own order, each partition's left-hand side then its abstract
parts in iteration order, then the environment's bindings.  An id below `su0` is an INPUT
variable and is not renamed. -/
def mintOrder (s : State) : List Nat

/-- **The canonical state**: the two queues in order and the environment, with every minted
id renamed.  The supply is deliberately absent. -/
def canonState (s : State) : String

/-- **The exact state**: no renaming, and the supply included. -/
def rawState (s : State) : String
```

Two things have to be said plainly about this quotient, and neither is in the review.

**(a) Why the supply must be quotiented away.**  `Sup.fresh` increments `drawn` and `lo` on
BOTH of its arms, so any run that draws an id has a strictly increasing supply and can never
repeat a state exactly.  An exact cycle is possible only in a draw-free run; the divergence
this stage is hunting mints without bound.  So the renaming quotient is not a convenience —
it is the only quotient under which the search can succeed at all, and the exact detector
(`rawState`) is reported alongside only because it is the one the theorem applies to.

**(b) NEITHER detector's hit would have been a proof — both are candidates.**  Two separate
reasons, and the round-6 review (W-6a) caught the second, which this report previously got
wrong.

*The canonical detector*: `V.hashCode` IS the id; the queue is ordered by
`(rhs.hashCode, lhs.hashCode)` and the dequeue priority is a reverse-topological index computed
over a hash-ordered node set.  A permutation of the minted ids can therefore change which
partition is dequeued next, so `SEq` is not implied by `canonState` equality.

*The exact detector*: `rawState` renders `incm.elems`, `proc.elems`, `env.binds` and
`su.{lo,hi,drawn}` — but `SEq` demands `s.incm = t.incm` for the whole `PQueue`, which is
`⟨elems, graph⟩`, and the `Graph` is not a decoration (`PQueue.dequeue` reads `graph.sort`, and
the graph keeps nodes and edges that removals from `elems` do not), plus `Sup.blk`/`bsz`,
`flags` and `names`.  So two states can share a `rawState` and fail `SEq`, and **an exact hit is
a candidate whose graphs, supply block and flags would have to be compared** — not, as this
report said in its first draft, "a proof by `not_terminates_of_cycle`".

**The direction the search is used in is sound in both readings.**  `canonState` and `rawState`
are functions of the state, so an `SEq` repeat forces a `rawState` repeat forces a `canonState`
repeat: **no canonical repeat means no `SEq` cycle**, which is exactly what R6.1.3 reports.  Any
hit would have been replayed through the compiler, and its `SEq` checked, before being claimed.

### R6.1.3 The search, and its cross-check

**No repeat, in 134,674 solves and 3,082,009 canonical states.**  That is the strongest negative
this stage can produce, because it rules out the only shape a divergence of a deterministic
loop can have.

`tmp/L5r6/hunt/bighuntc.sh` (under `setsid nohup`, log `bighuntc.log`) runs three things: round
5's whole population re-run under `--cycle`, 183 deep candidates collected into `deep/` (the
round's four climbers' bests, the round-5 reviewer's ten climbs `L3`/`L4`/`L6`/`L8`/`L10`/
`D21`–`D25`, both Lean witnesses `min2`/`minC1`, `climb9`, and every seed of round 5's
`cand-deep.txt`), and a FRESH 50,000-solve hunt biased exactly as round 5's (`gen5.py`, one hub,
weights `0.30,0.30,0.30,0.10`, `--start` 500000/600000/700000 so no seed is a repeat of round
5's).  `tmp/L5r6/hunt/cycsum.py` tabulates it:

| population | shape | solves | canonical states | max dequeues | ids drawn | verdicts |
|---|---|---|---|---|---|---|
| `r5-popA` … `r5-popG` | round 5's seven 200-seed populations × 4 bases | 5,600 | 124,632 | 197 | 56,857 | 5,600 SOLVED |
| `r5-deep` | 183 deep candidates × 10 bases | 1,830 | 93,457 | **340** | 54,383 | 1,830 SOLVED |
| `r5-popH2` | 8,000 seeds (12 vars, 6 labels, 16 cons) × 6 bases | 48,000 | 1,020,195 | 324 | 366,664 | 48,000 SOLVED |
| `r5-popI` | 3,000 seeds (14/6/24) × 4 bases | 12,000 | 319,501 | 284 | 113,404 | 12,000 SOLVED |
| `r5-popJ` | 3,000 seeds (16/8/28) × 4 bases | 12,000 | 301,358 | 227 | 108,813 | 12,000 SOLVED |
| **`popK`** (fresh) | 6,000 seeds (12/6/16) × 4 bases | **24,000** | 512,570 | 236 | 188,957 | 24,000 SOLVED |
| **`popL`** (fresh) | 4,000 seeds (14/6/24) × 4 bases | **16,000** | 426,249 | 197 | 153,027 | 16,000 SOLVED |
| **`popM`** (fresh) | 2,500 seeds (16/8/28) × 4 bases | **10,000** | 253,268 | 289 | 86,448 | 10,000 SOLVED |
| `popNC` | 1,311 LABEL-FREE seeds × 4 bases (R6.3's fragment) | 5,244 | 30,779 | 18 | **0** | 5,244 SOLVED |
| **total** | | **134,674** | **3,082,009** | 340 | 1,128,553 | **134,674 SOLVED, 0 REJECTED, 0 FUEL** |

* **Canonical repeats: 0.  Exact repeats: 0.**  (The fresh hunt alone is 50,000 solves and
  1,192,087 canonical states.)
* **An independent cross-check of the detector.**  `cycleRun` reports both the number of
  dequeues and the number of DISTINCT canonical states it saw.  If a state ever repeated, the
  second would be smaller than the first plus one.  Across all **134,674** runs,
  `states = steps + 1` holds in **every single one** — computed from a different column of the
  `.tsv` than the `canon=`/`exact=` fields, so the negative is not resting on one code path:
  `zcat *.tsv.gz | awk -F'\t' '$3=="cycle"{gsub("steps=","",$5); gsub("states=","",$6); n++;
  if($6+0 != $5+0+1) bad++} END {print n, bad+0}'` prints `134674 0`.
* **And the fragment's own population confirms the theorem's headline clause**: on the 5,244
  label-free solves the total number of ids drawn is **0**, which is `step_noConc`'s
  `s'.su = s.su` measured rather than proved.
* No compiler replay was owed, because there was nothing to replay: a hit would have been
  replayed at ten id bases before being claimed (that is what §R6.5 item 9 does for round 5's
  deepest witness, which still `SOLVED=10 HANG=0`).

**What this does and does not settle.**  It does not prove termination; it rules out the one
shape a divergence could take *and be detected by a finite run*, over the largest and most
directed population the stage has searched.  Round 5's own directed search (hill-climbing on
mints-at-one-key) plateaued at 9, the round-5 reviewer reached 10, and this round adds 134,674
runs with a detector aimed at the divergence itself rather than at a proxy for it — still 0
`FUEL`, still no repeat.  Against that, the honest caveat of R6.1.2(b) stands: the quotient is
not a congruence, so the search could in principle miss a divergence that revisits a state only
up to a renaming the queue order distinguishes.

## R6.2 — "`incm` empties": termination as saturation of the derived set (`Loop/NoConc.lean` §8)

### R6.2.1 The recast, proved

```lean
/-- A state the loop cannot step from. -/
def Stuck (t : State) : Prop := ∀ t', step t ≠ .continue t'

/-- **`done` IS the empty incoming queue.**  `step`'s only `done` is its first branch. -/
theorem step_done_dequeue {t u : State} (h : step t = .done u) : t.incm.dequeue = none

/-- **Termination is reaching a stuck state.** -/
theorem terminates_iff_stuck {s : State} :
    Terminates s ↔ ∃ (n : Nat) (t : State), Runs n s t ∧ Stuck t

/-- **"`incm` empties" is the recast R6.2 asks for.**  On a run that does not DIE -- which is
what round 3's `run_refutes_all` gives on a satisfiable input, every death of the loop being a
refutation of the system it was handed -- `Terminates` is exactly "the incoming queue
empties". -/
theorem terminates_iff_incm_empties {s : State}
    (hnd : ∀ (n : Nat) (t : State), Runs n s t → ∀ m u, step t ≠ .died m u) :
    Terminates s ↔ ∃ (n : Nat) (t : State), Runs n s t ∧ t.incm.dequeue = none
```

The death hypothesis is not a fudge: it is exactly what rounds 3 and 4 already deliver on a
satisfiable input (`run_refutes_all`, `reaches_link_no_death`, `queueHygiene_binds_unbound`),
where every death of the loop is a refutation of the system it was handed and therefore
impossible.  Stated this way `Terminates` is a statement about `trim` and the dispatch, with
no measure anywhere in it.

### R6.2.2 What would make the derived set saturate, and the exact gap

Saturation has two halves.

**Half one is PROVED, and has been since round 3.**  `trim` refuses everything the processed
queue already holds (`Order.trim_refuses`, restated as `trim_notContains`), and the dequeued
premise itself is `Partition.equals`-new or the COMMON branch would have fired
(`Order.learn_procSys_lt`).  So every `learn` step moves the processed set strictly forward
and enqueues nothing the processed set has already seen.

**Half two is GUARD COMPLETENESS, and it is FALSE.**

```lean
/-- **Half two, the one that is missing: GUARD COMPLETENESS.**  Once the loop has minted at a
key, the reuse guards refuse every later mint at that key. -/
def GuardComplete : Prop :=
  ∀ (s s' t t' : State) (v : Nat) (K : SSet Lbl),
    step s = .continue s' → MintsAt s s' v K → Reaches s' t → step t = .continue t' →
    ¬ MintsAt t t' v K

theorem guardComplete_false : ¬ GuardComplete := fun h =>
  h (pAt 5) (pAt 6) (pAt 12) (pAt 13) 2 pKey pStep5 pMint5 pReach6_12 pStep12 pMint12
```

This is the brief's "exact gap", and it is the pump: the re-mints of round 5 are derivations
the guard permits AGAIN once a carrier is lost.  Round 5's own two witnesses refute it
(`pS0`, where `cancellation` + `makeEmpty` withdraw the carrier; `cS0`, where `makeConcrete`
does it without binding anything), and the round-5 reviewer's `climb/L4/best11.json` refutes
it **ten times over at a single key** while the whole label pool in play has three labels.
So `KMintRun.mints_le`'s additive bound cannot be transported: what it bounds is the number of
mints the ADDITIVE calculus permits at a key that is never uncarried, and the loop uncarries
keys — with `makeEmpty`, with `makeConcrete`'s `destructiveSub`, and with `Q.++!`'s redirect
(round 4's R4.1) — after which the same guard permits the same mint again.

**The residual that survives, stated as one lemma, and its status.**

```lean
/-- The positive residual that survives the refutation, and the one `terminates_of_bounds`
consumes: the derived set is bounded along the run. -/
def ProcSaturates (s : State) : Prop := ∃ P : Nat, ∀ t, Reaches s t → (procSys t).card ≤ P

/-- **The residual, assembled.**  On the fragment, saturation of the derived set together with
the two bounds it does not itself give -- on the queue and on the environment -- IS
termination. -/
theorem terminates_of_saturation {s : State} {Q E : Nat}
    (hw : ∀ t, Reaches s t → Wf t) (hnc : ∀ t, Reaches s t → NoConc t)
    (hsat : ProcSaturates s)
    (hq : ∀ t, Reaches s t → t.incm.elems.length ≤ Q)
    (he : ∀ t, Reaches s t → t.env.binds.length ≤ E) : Terminates s
```

**Outcome: (T1) for the recast, (T2), and the residual is FRAGMENT-RELATIVE** — the round-6
review's W-6d, and the correction matters.  `ProcSaturates` is not proved in general and it is
not refuted.  What the round adds is that it is SUFFICIENT *together with the two other bounds*,
that its natural strengthening `GuardComplete` is FALSE, and that ON THE FRAGMENT it is PROVED
(`procSys_card_le` gives `P := |V|·2^|V|` once the vocabulary is fixed).  But
`terminates_of_saturation` and `terminates_of_bounds` both carry
`hnc : ∀ t, Reaches s t → NoConc t`, and they cannot be dropped: `measure3_lt` needs
`step_trichotomy` needs `NoConc` to discharge the `concrete` dispatch branch by `exfalso`
(`NoConc.lean` §7).  **So off the fragment neither lemma applies, and this residual is no
sharper than round 4's or round 5's.**  On the fragment it adds nothing either, because
`ProcSaturates` is already a theorem there.  Its value is as a factorisation: it names the three
quantities a general proof would have to bound, and says which of the three the `concrete`
branch is the obstacle for.  The general case is open for exactly one reason: off the fragment
the vocabulary is not fixed, because `splitConcrete` and `resolution` mint.  What the ten-turn pump does to it is precise: it does
not touch `ProcSaturates` at all — the reviewer's own V-9 instrumentation shows `proc` growing
monotonically 6 → 23 while `incm` DRAINS 10 → 2 → 0 across the ten turns, so on every witness
ever measured the derived set does saturate — but it kills `GuardComplete`, which was the only
route to `ProcSaturates` that did not go through a vocabulary bound.

## R6.4 — what round 6 could NOT prove, side by side

| asked for | what is proved | what is not, and why |
|---|---|---|
| **R6.3** "define `NoConc`, prove it preserved and terminating with an explicit bound, and measure which stdlib-boot and example-corpus solves are in it" | `NoConc` + `step_noConc` + `run_noConc`; both generative rules unreachable AND no id drawn (`splitConcrete_noConc`, `resolution_noConc`); `makeConcrete`'s branch unreachable; the vocabulary fixed (`learnPartitions_avoidsV`, `step_inVoc`, `inVoc_self`); the three bounds (`env_len_le_card`, `procSys_card_le`, `kdist_length_le`, the last via `unorderedHash_perm`); **`noConc_terminates` / `noConc_run` / `noConc_terminates_of_buildQueue`** with the fuel `measure3 (n·2ⁿ) (n·2ⁿ) n s + 1`; the corpus measured on fresh traces (373/373 boot, 2,388/9,362 examples; the reviewer's corpus-wide figure is 15,377/15,377 stdlib-located) | the bound is not tight (order `n²·4ⁿ` against a few dozen dequeues in practice) and nothing is claimed about the 6,974 example solves that DO carry a label.  "No id is drawn" is a statement about the LOOP: `PQueue.build` mints for a `Part` with a non-variable left-hand side, and 8 of the 373 boot inputs have one (review W-6b) — the theorem still covers them.  The `incomplete/` corpus group was not measured here; the reviewer measured it (W-7) and it does not disturb the claim |
| **R6.1** "a canonical form up to renaming of minted ids, a cycle detector, the lemma that a repeat implies non-termination, and a search over round 5's populations plus a fresh 50,000-solve hunt" | `SEq`, `step_decor`, `step_congr`, `run_seq`, `Runs`, **`not_terminates_of_cycle`**; `mintOrder` / `canonId` / `canonState` / `rawState` / `cycleRun` and `looptrace --cycle`; the search — **134,674 solves, 3,082,009 canonical states, 0 repeats, 0 `FUEL`, 0 `REJECTED`**, including a fresh 50,000-solve hunt (R6.1.3) | **no repeat found**, so the lemma is insurance and the outcome is a quantified negative.  And NEITHER detector's hit would have been a proof: the renaming quotient is not a congruence (the queue is ordered by `V.hashCode`, which IS the id), and — review W-6a, a claim this report had wrong — `rawState` omits the queue GRAPHS, `Sup.blk`/`bsz`, `flags` and `names`, all of which `SEq` demands, so an "exact" hit is a candidate too.  Sound in the direction used: an `SEq` repeat forces a `rawState` repeat forces a canonical repeat, so 0 canonical hits ⇒ 0 cycles |
| **R6.2** "recast termination as `incm` emptying, state what would make the derived set saturate, find the exact gap, state the residual as one lemma, attempt it" | `Stuck`, `step_done_dequeue`, `terminates_iff_stuck`, **`terminates_iff_incm_empties`**; half one of saturation (`trim_notContains`, with `Order.learn_procSys_lt`); the gap named and **refuted** (`GuardComplete`, `guardComplete_false`); the surviving residual `ProcSaturates` stated and proved SUFFICIENT (`terminates_of_saturation`, `terminates_of_bounds`) and proved outright on the fragment (`procSys_card_le`) | `ProcSaturates` is neither proved nor refuted in general, and the residual is **fragment-relative** (review W-6d): `terminates_of_saturation` and `terminates_of_bounds` both carry `NoConc` along the run, because `step_trichotomy` needs it to kill the `concrete` branch — so off the fragment neither applies and this is no sharper than round 4's or round 5's residual.  What the ten-turn pump does to it is precise and is recorded in R6.2.2: it leaves `ProcSaturates` untouched (the reviewer's own V-9 shows `proc` growing monotonically and `incm` draining across all ten turns) and kills `GuardComplete`, which was the only route to `ProcSaturates` that did not go through a vocabulary bound |

**And what the round does not touch.**  The plan's L5 acceptance has four criteria; this round
moves the third from FAIL to PARTIAL and leaves the second where round 5 left it:

| criterion | round 5 | round 6 |
|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | PASS | **PASS, unchanged** — `Strict.lean` is not touched |
| every `step` refines it under `step_refines_all`'s hypotheses | FAIL | **FAIL, unchanged** — `concrete` and `learn` are still outside `LinkOrEmptyStep`; this round does not touch the strict refinement |
| `Terminates s₀` for every satisfiable `Wf s₀` with an explicit bound, **or** a compiler-reproduced witness | FAIL (T2) | **PARTIAL** — proved, with an explicit bound, for the `NoConc` fragment, which is 100 % of the stdlib boot's row-carrying solves and 25.5 % of the examples'.  Still open in general; still no witness (this round adds 134,674 model solves under a cycle detector and 100 compiler solves, all terminating) |
| audit green | PASS | **PASS** — 854 jobs, `3611 / 0`, 0 `sorry` |

## R6.5 — what a reviewer should re-run

1. **Build and audit.**  `cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH && lake build
   Rowpartition` → `Build completed successfully (854 jobs)`; `lake env lean Audit.lean` →
   `Rowpartition theorems audited: 3611; declarations using a non-standard axiom: 0`
   (3494 / 852 before).  `lake build looptrace` for the executable.
2. **Hygiene.**  `grep -nE '\bsorry\b|\baxiom\b|\bpartial\b|native_decide|implemented_by|\bunsafe\b|\bopaque\b|Classical|\badmit\b|#exit'
   Rowpartition/Loop/{Cycle,NoConc}.lean` — 0 hits.  (`Loop/Main.lean` has one `partial`
   hit: the word inside a doc comment saying nothing under `Loop/` may be `partial`.)
   `#print axioms` over all **128** declarations of the two modules — 101 `theorem`s (88 in
   `NoConc.lean`, 13 in `Cycle.lean`), 25 `def`s, 1 `abbrev` and 1 `structure`
   (`tmp/L5r6/scratch/{names.txt,Axioms.lean,axioms.txt}`, corrected per review W-6c): 99 ×
   `[propext, Classical.choice, Quot.sound]`, 4 × `[propext, Quot.sound]`, 8 × `[propext]`,
   **17** axiom-free.  **No non-standard axiom.**
3. **`git diff` scope.**  Two NEW modules (`Loop/{Cycle,NoConc}.lean` — 375 and **1,722** lines), `Rowpartition.lean`
   +2/−0, `Loop/Main.lean` (the `--cycle` mode and its doc paragraph only), the plan's L5 row,
   `tracker/lean/README.md` additive, `tracker/ROW-CONSTRAINT-STATE.md` +1 section, and this
   report.  Every other Lean module and every Scala file UNCHANGED.
4. **The load-bearing statements are cheap to re-check.**  `noConc_terminates_of_buildQueue`
   is the theorem the corpus claim rests on; `guardComplete_false` is a one-line application of
   round 5's own `pMint5`/`pMint12`; `not_terminates_of_cycle` is a strong induction on the
   fuel; `unorderedHash_perm` is `List.Perm.foldl_eq'` plus `UInt32.{add,xor,mul}_{comm,assoc}`.
5. **The corpus traces.**  `tmp/L5r6/gentrace.sh` regenerates all seven groups from scratch
   (~3 minutes total); the census is `python3 tmp/L5r6/fragcensus.py tmp/L5r6/traces/*.tsv.gz`
   and `python3 tmp/L5r6/excensus.py tmp/L5r6/traces/{top,Ai,shouldfail,bugs,guide,shouldfail-controls}.tsv.gz`.
   The segment counts must match L2-CORPUS §4a exactly (54,199 / 92,673 / 83,942 / 56,032 /
   54,235 / 54,244 / 54,739); they did.
6. **The model on the corpus.**  `zcat tmp/L5r6/traces/boot.tsv.gz > /tmp/boot.tsv &&
   tracker/lean/.lake/build/bin/looptrace --replay /tmp/boot.tsv | tail -1` →
   `segments=54199 replayed=54199 skipped=0 hashdiff=0 eqdiff=0 rejected=0 fuel=0`.
7. **The fragment, synthetically.**  `python3 tmp/L5r6/hunt/gennoconc.py 1500 10 5 14 popNC`
   (1,311 seeds, `random.Random(i)` per seed so they reproduce bit for bit) then
   `tmp/L5r6/hunt/huntc.sh popNC 4 3000 popNC.tsv 6` → 5,244 solves, all `SOLVED`, **0 ids
   drawn in total**, 0 canonical repeats.  Ten of them on the shipped compiler:
   `ERMINE_JAVA_OPTS="-Dermine.useInterface=false" tracker/repro/satterm/run.sh sweep
   json:<abs path> 0 9 30 20` → `SOLVED=10 HANG=0` and `DRAWN … histogram 0:x10` on each.
8. **The cycle search.**  Note first (review W-6g) that `--cycle` and `--mints` exist only on
   the `json:` seed path (`Main.lean:199–202`); `replayMain` has neither, so a corpus segment
   cannot be cycle-searched or draw-counted without transcoding it into a seed.  Wiring
   `cycleRun` into `replayMain` is the cheapest thing a round 7 could do first — it would put
   the detector over all 2,355,430 corpus segments instead of over synthetic seeds.
   `tmp/L5r6/hunt/bighuntc.sh` runs the whole thing: round 5's
   populations (`popA`…`popG`, `popH2`, `popI`, `popJ` and 183 deep candidates collected into
   `deep/`) re-run under `--cycle`, then the fresh `popK`/`popL`/`popM`.  `looptrace
   <seed.json> <base> <fuel> --cycle` on any one seed prints the line directly; on round 5's
   deepest witness, `looptrace tmp/L5r5/hunt/climb9.json 0 20000 --cycle` prints
   `cycle SOLVED steps=213 states=214 drawn=188 canon=- exact=-`.
9. **The compiler, on round 5's deepest witness, unchanged:**
   `ERMINE_JAVA_OPTS="-Dermine.useInterface=false" tracker/repro/satterm/run.sh sweep
   json:tmp/L5r5/hunt/climb9.json 0 9 30 20` → `SOLVED=10 REJECTED=0 HANG=0 OOM=0`,
   `DRAWN min=19 median=86 max=208`.

# Round 7 — 2026-09-05, after `L5-REVIEW.md`'s "Round-6 review" (W-9: the vocabulary-fixed target)

The framing is the user's: Ermine is a reporting language, its users always end with concrete
fields, and the standard library's certification (round 6: **every** stdlib row solve is in the
no-concrete-labels fragment) is therefore a FLOOR.  This round is about the solves USER
PROGRAMS produce.

The round-6 reviewer put the target and the ceiling on it (W-9).  He refuted the naive
widening — of the 9,256 example solves on which neither generative rule can fire ON THE INPUT,
**111 fire one anyway**, because `substitution` and `commonSubexpression` manufacture partitions
of exactly `splitConcrete`'s firing shape — so "no generative rule can fire" is *not* an
invariant and cannot be the fragment.  What he named instead is the VOCABULARY-FIXED
condition, "no id ever enters a partition", and he measured its ceiling at 97.6 % of the
example corpus.

**Outcome in one line.**  The vocabulary-fixed fragment is proved to terminate, with an
explicit bound, and it holds on **9,118 of 9,362 example solves (97.4 %)** and on **2,695 of
2,695 stdlib solves (100 %)** — measured by running the MODEL over every corpus solve, not by
a proxy.  Three things that `NoConc` did for free had to be replaced, and the third is the
one that matters: the `concrete` dispatch branch, which round 6 discharged by `exfalso`, is
now *paid for* — `makeConcrete` strictly grows a bounded potential (§R7.1c), which is what
takes the certified fraction from 72.2 % (vocabulary fixed **and** no `concrete` step) to
97.4 %.

Stated exactly, and this is the round's headline:

> **A row-constraint solve on which `incorporateAll` never draws an id TERMINATES**
> (`noDraw_terminates`), and so does one whose reachable states merely stay inside a fixed
> finite vocabulary (`vocFixed_terminates`), at the explicit fuel
> `measure4 (n·2ⁿ·2ᵐ) (n·2ⁿ·2ᵐ) n (n·2ᵐ) V L s + 1` with `n = |V|`, `m = |L|`.  Contrapositively
> (`draws_cofinally_of_not_terminates`): **a divergent solve must draw ids at cofinally many
> steps** — non-termination lives entirely in `splitConcrete` and `resolution` and nowhere
> else in the loop.

Two honesty clauses, both required by the round-6 review's own logic and both carried
throughout:

* **The condition is RUN-LEVEL, not input-checkable.**  W-9's 111 witnesses close the obvious
  input predicate, and this round found no other; the brief anticipates this ("if only the
  run-level version is provable, say so").  So the certification is *"every solve on which the
  model's trace shows no mint"*, checkable per solve — `looptrace --replay <trace> --cycle`
  now prints `drawn=` and `grew=` for every solve of a corpus trace (round-6 review W-6g,
  implemented here).  It is **weaker than round 6's** in exactly this sense: `NoConc` is
  decidable from the input alone, and this is not.
* **What the theorem buys, precisely.**  For a solve whose replay the model already ran to
  completion, `Terminates` is witnessed by the replay itself; the theorem's content is (i) that
  the whole CLASS terminates, at a stated bound, at any id base and any label pool, and (ii)
  the contrapositive, which localises divergence in the two minting rules.  It is not a
  prediction about an input nobody has run.

New module: `Loop/VocFix.lean` (1,938 lines, 86 theorems, 14 defs = 100 declarations).
`Loop/Cycle.lean` gains five `CycleRep` fields (`mint0`, `grew`, `maxMint`, `nconc`, `drawn0`)
and `isConcDispatch`; `Loop/Main.lean` gains `--cycle` and `--mints` over `--replay`
(`replayCycleOne`, `replayMintOne`); `Rowpartition.lean` gains one import.  No other Lean
module and no Scala file is touched.  Audit after: **3706 theorems / 0 non-standard axioms,
855 jobs** (3611 / 854 before); `lake build looptrace` 1,656 jobs.

## R7.1 — the fragment, and why it needs three new pieces

`NoConc.lean` used "no concrete labels" for three separate jobs.  Only the first is about the
vocabulary; the other two are what round 6's §R6.3.4a flagged, and each needed its own
replacement.

### R7.1a The label bound — free, from L3's refinement

`procSys_card_le` and `kdist_length_le` used `conc = []` to land in `forms V ∅` and to make
`(lhs, abstract parts)` a separating map.  With labels the ambient set is `forms V L` and the
`2^|L|` factor comes back — which needs the loop not to INVENT a label.  That is free:
`RefineLearn.step_refines_all` gives `LoopRun (sys s) (sys s')` for every dispatch branch, and
every one of `LoopRel`'s eleven constructors preserves `ConcSub`.

```lean
theorem LoopRel.concSub {L : Finset Label} {G G' : System} (h : LoopRel G G')
    (hcs : ConcSub L G) : ConcSub L G'

theorem LoopRun.concSub {L : Finset Label} {G G' : System} (h : LoopRun G G')
    (hcs : ConcSub L G) : ConcSub L G'

theorem step_concSub {L : Finset Label} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (hcs : ConcSub L (sys s)) (h : step s = .continue s') : ConcSub L (sys s')

theorem reaches_concSub {L : Finset Label} {s t : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hcs : ConcSub L (sys s)) (hr : Reaches s t) : ConcSub L (sys t)

theorem concSub_self (s : State) : ConcSub (labelsOf (sys s)) (sys s) := labelsOf_concSub _
```

Only `Cut.ResStep` needed a `concSub` lemma of its own (it is `ResGuardTerm.GResStep.concSub`'s
mint branch at the unguarded rule); `NonGenStep`, `K2SplitStep`, `SplitStep` and `K2ResStep`
already had theirs, `weaken` is deletion, and the five loop-specific constructors
(`renameLhs`, `linkSymm`, `emptyProp`, `dedup`) emit `mk _ _ K` with `K` a premise's row or
`∅`.  `L` is not an assumption either: `concSub_self` takes the input's own label pool.

The two bounds then go through with `LPart.toConstraint` itself as the separating map —
`Wf.LPart.eqv_iff_toConstraint_of_wf` says `Partition.equals` IS equality of the constraint,
with no side conditions, for two partitions of a well-formed state, which is *simpler* than
round 6's `sepMap`:

```lean
theorem procSys_card_leL {V : Finset Var} {L : Finset Label} {s : State}
    (hv : InVoc V s) (hcs : ConcSub L (sys s)) :
    (procSys s).card ≤ V.card * 2 ^ V.card * 2 ^ L.card

theorem kdist_length_leL {V : Finset Var} {L : Finset Label} {s : State} {l : List LPart}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s))
    (hsub : ∀ p ∈ l, p ∈ s.parts) (hk : KDist l) :
    l.length ≤ V.card * 2 ^ V.card * 2 ^ L.card
```

### R7.1b The vocabulary clause for `learn` — traded for "the step drew nothing"

`learnPartitions_avoidsV` killed `splitConcrete` by `concr.isEmpty` and `resolution` by
`rhs1.abstrSingle? = none`.  Neither survives labels: the dequeued premise of a `learn` step
may be `v <- (x, (|C|))`, which is not `single?` and IS `abstrSingle?` — exactly the shape
W-9's 111 solves have.  What replaces both is the hypothesis that the call DREW NO ID.
`resolution` draws inside the lone-variable arm and BEFORE its guards, so "it did not draw"
already says "it returned nothing"; `splitConcrete` draws only in its last branch, so "it did
not draw" says "it took a reuse branch", and every reuse branch names a variable one of the
three lookups produced.

```lean
theorem resolution_noDraw {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (h : (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2.drawn = su.drawn) :
    (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).1 = SSet.empty

theorem splitConcrete_avoidsV {B : Var → Prop} {fl : Flags} {v : Nat} {abstr : SSet Nat}
    {concr : SSet Lbl} {rhss : RHS → Option Nat}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (hv : ¬ B v) (ha : ∀ w ∈ abstr.elems, ¬ B w)
    (hr : ∀ r w, rhss r = some w → ¬ B w)
    (hres : ∀ k w, resolvent k = some w → ¬ B w)
    (hcr : ∀ k w, concRow k = some w → ¬ B w)
    (hnd : (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2.drawn
             = su.drawn) :
    ∀ x ∈ (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).1.elems,
      Avoids B x.toConstraint
```

The fold carries two facts at once — the supply's `drawn` never goes down, and *while it has
not moved* every partition derived so far is over the old vocabulary — so the hypothesis
"the whole call drew nothing" propagates backwards to every one of its rule applications.
That is one application of `foldl_except_inv`, not a restatement of the fold:

```lean
theorem learnPartitions_avoidsV_noDraw {B : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hv : ¬ B v) (hr1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su'))
    (hnd : su'.drawn = su.drawn) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint

theorem step_inVoc_noDraw {V : Finset Var} {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h0 : InVoc V s)
    (h : step s = .continue s') (hnd : s'.su.drawn = s.su.drawn) : InVoc V s'
```

`step_inVoc_noDraw` covers all FIVE dispatch branches, `concrete` included:
`Hygiene.makeConcrete_avoids` was already general and round 6 simply never reached it.

### R7.1c The `concrete` branch — what it pays with

This is the piece round 6 named as the obstacle ("a wider fragment must either kill that
branch too or find something that decreases on it — the one branch `StrictBound.lean` already
flags as unbounded"), and it is the reason the round is worth anything: the branch fires on
**2,500 of the 9,362 example solves**, and excluding it costs 25 points of coverage.

`makeConcrete` binds no variable and does not grow the processed set — `destructiveSub`
DELETES.  What it does do is install `v <- ((|fs|))`, and three facts make that a measure:

* `ensureSuperset` (`Constraints.scala:1608`) fails the whole step unless every concrete row
  already recorded for `v` is a SUBSET of `fs`;
* the dispatch reached `makeConcrete` only because `proc.findRHS r.rhs` MISSED, so no
  processed partition has right-hand side `((|fs|))` — the subset is PROPER;
* `destructiveSub` deletes only partitions that mention `v`, and a bare concrete row mentions
  no variable, so every OTHER variable's rows survive.

So the DOWNWARD-CLOSED set of `(variable, concrete row it is known to contain)` pairs that the
processed queue carries strictly grows, and it lives inside `V ×ˢ L.powerset`:

```lean
def rowSet (V : Finset Var) (L : Finset Label) (s : State) : Finset (Var × Finset Label) :=
  (V ×ˢ L.powerset).filter (fun q =>
    s.proc.elems.any (fun p => p.lhs == q.1 && p.rhs.abstr.elems.isEmpty &&
      decide (q.2 ⊆ p.toConstraint.conc)))

theorem rowSet_card_le {V : Finset Var} {L : Finset Label} {s : State} :
    (rowSet V L s).card ≤ V.card * 2 ^ L.card

theorem rowSet_subset_of {V : Finset Var} {L : Finset Label} {s t : State}
    (h : ∀ p ∈ s.proc.elems, p.rhs.abstr.elems = [] → p ∈ t.proc.elems) :
    rowSet V L s ⊆ rowSet V L t

theorem rowSet_lt_concrete {V : Finset Var} {L : Finset Label} {s s' : State}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s)) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest))
    (hfind : s.proc.findRHS r.rhs = none)
    (hne : r.rhs.isEmpty = false) (hab : r.rhs.abstr.isEmpty = true)
    (hmk : makeConcrete r.lhs r.rhs.conc rest s.proc = .ok (s'.incm, s'.proc)) :
    (rowSet V L s).card < (rowSet V L s').card
```

Downward closure is exactly what makes it monotone: a `concrete` step at `u` DELETES `u`'s old
rows, but `ensureSuperset` has already forced each of them inside the new one, so no pair is
lost.  Reading `ensureSuperset` out of the Scala's two `Set` layers is the fiddly half —
`SVal RHS` is `RHS.eqv`, not structural equality, so `p.rhs` need not be an ELEMENT of the set
`makeConcrete` checks; §4.0 of the module proves a representative is always there and that a
`subsetOf` on the concrete part survives `SSet.ofList`, `filter`, `map` and the CHAMP `concat`
(whose `pickRep` may keep the LEFT operand's copy, which is why duplicate-freeness is needed
there and nowhere else).  The three facts about the queues are

```lean
theorem makeConcrete_superset {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hcp : ∀ q ∈ proc.elems, q.rhs.conc.Nodup) (hci : ∀ q ∈ incm.elems, q.rhs.conc.Nodup)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    ∀ p ∈ proc.elems, p.lhs = v → p.rhs.conc.subsetOf fs = true

theorem makeConcrete_row_mem {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (h : makeConcrete v fs incm proc = .ok (ni, np)) (hfs : fs.isEmpty = false)
    (hno : ∀ y ∈ proc.elems, y.rhs.eqv (RHS.ofConcr fs) = false) :
    (⟨v, RHS.ofConcr fs, none⟩ : LPart) ∈ np.elems

theorem destructiveSub_proc_keep {v : Nat} {rhs : RHS} {incm proc : PQueue} {ni np : PQueue}
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) {x : LPart} (hx : x ∈ proc.elems)
    (hl : (x.lhs == v) = false) (hc : x.rhs.contains v = false) : x ∈ np.elems
```

`makeConcrete_row_mem` is where the dispatch's own `findRHS` miss is spent: `Q.insert` refuses
a self-unification (impossible for a bare concrete row) and a partition already present at the
same search key (which `findRHS` would have found), so the row really lands.

### R7.1d The measure, and `Terminates`

Round 6's three kinds of step become four.

```lean
def IsConcStep (s s' : State) : Prop :=
  ∃ (r : LPart) (rest : PQueue), s.incm.dequeue = some (r, rest) ∧
    s.proc.findRHS r.rhs = none ∧ r.rhs.isEmpty = false ∧ r.rhs.abstr.isEmpty = true ∧
    makeConcrete r.lhs r.rhs.conc rest s.proc = .ok (s'.incm, s'.proc)

theorem step_quadrichotomy {s s' : State} (h : step s = .continue s') :
    (IsLearnStep s ∧ s'.env = s.env ∧ ∀ p ∈ s.proc.elems, p ∈ s'.proc.elems) ∨
    (s'.env.binds.length = s.env.binds.length + 1) ∨
    (s'.env = s.env ∧ s'.proc = s.proc ∧ s'.incm.elems.length + 1 = s.incm.elems.length) ∨
    (IsConcStep s s' ∧ s'.env = s.env)
```

Note what `step_quadrichotomy` does NOT have: a fragment hypothesis.  It is a statement about
the real `step` at any state.  Flattening the four-way lexicographic order gives

```lean
def measure4 (P Q E R : Nat) (V : Finset Var) (L : Finset Label) (s : State) : Nat :=
  (E - s.env.binds.length) * ((R + 1) * ((P + 1) * (Q + 1))) +
    (R - (rowSet V L s).card) * ((P + 1) * (Q + 1)) +
    (P - (procSys s).card) * (Q + 1) + s.incm.elems.length

theorem measure4_lt {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {s s' : State}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s))
    (hR' : (rowSet V L s').card ≤ R) (hP' : (procSys s').card ≤ P)
    (hQ' : s'.incm.elems.length ≤ Q) (hE' : s'.env.binds.length ≤ E)
    (h : step s = .continue s') :
    measure4 P Q E R V L s' < measure4 P Q E R V L s

theorem terminates_of_bounds4 {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {s : State}
    (hw : ∀ t, Reaches s t → Wf t) (hv : ∀ t, Reaches s t → InVoc V t)
    (hcs : ∀ t, Reaches s t → ConcSub L (sys t))
    (hr : ∀ t, Reaches s t → (rowSet V L t).card ≤ R)
    (hp : ∀ t, Reaches s t → (procSys t).card ≤ P)
    (hq : ∀ t, Reaches s t → t.incm.elems.length ≤ Q)
    (he : ∀ t, Reaches s t → t.env.binds.length ≤ E) : Terminates s
```

The queue invariant also had to be re-proved on the `concrete` branch (`NoConc.step_kdist`
discharges it by `exfalso` too); it is mechanical, because `destructiveSub` and `makeConcrete`
build their queues out of `filter`, `partition`, `concatP`, `concatNP` and `insertNP` and
`KDist` survives each:

```lean
theorem kdist_makeConcrete {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hi : KDist incm.elems) (hp : KDist proc.elems)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    KDist ni.elems ∧ KDist np.elems

theorem step_kdist' {s s' : State} (hi : KDist s.incm.elems)
    (hp : KDist s.proc.elems) (h : step s = .continue s') :
    KDist s'.incm.elems ∧ KDist s'.proc.elems
```

And the fragment and the theorem:

```lean
def VocFixed (V : Finset Var) (s : State) : Prop := ∀ t, Reaches s t → InVoc V t

def NoDraw (s : State) : Prop :=
  ∀ t t', Reaches s t → step t = .continue t' → t'.su.drawn = t.su.drawn

theorem vocFixed_of_noDraw {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : NoDraw s) : VocFixed (allVars (sys s)) s

theorem vocFixed_terminates {V : Finset Var} {L : Finset Label} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixed V s) : Terminates s

theorem vocFixed_run {V : Finset Var} {L : Finset Label} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixed V s) :
    Finished (run s (measure4 (V.card * 2 ^ V.card * 2 ^ L.card)
      (V.card * 2 ^ V.card * 2 ^ L.card) V.card (V.card * 2 ^ L.card) V L s + 1))

theorem noDraw_terminates {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) (h : NoDraw s) : Terminates s
```

**The bound, written out.**  With `n = |V|` and `m = |L|`, at `E = n`, `R = n·2ᵐ` and
`P = Q = n·2ⁿ·2ᵐ`, the fuel `measure4 P Q E R V L s + 1` is at most
`n·(n·2ᵐ + 1)·(n·2ⁿ·2ᵐ + 1)² + (n·2ᵐ)·(n·2ⁿ·2ᵐ + 1)² + (n·2ⁿ·2ᵐ)·(n·2ⁿ·2ᵐ + 1) + |incm₀| + 1`,
i.e. of order `n⁴·2^{2n+3m}` — worse than round 6's `n²·4ⁿ` by the label factor `2^{3m}` and by
one factor of the potential the `concrete` branch lowers, which is itself of size `n·2ᵐ`.  It
is not tight and is not meant to be: the four factors are (variables that can be eliminated) ×
(concrete rows that can be recorded) × (distinct constraints over `V` and `L`) × (the queue's
own capacity), every one of them the crude combinatorial count.  On the corpus the deepest run
is **140 dequeues**.

**Hypotheses, and which of them are new.**  `emptyRow`, `disjRule` and `cseMints` are the
SHIPPED defaults (`Constraints.scala:768–774`; `-Dermine.emptyRow` ships off, as
`RefineLearn.step_refines_all` already required).  `EnvNodup`, the two `KDist`s and
`QueueHygiene` are discharged outright by the `_of_buildQueue` corollaries; **`Wf` is kept as a
hypothesis there**, exactly as round 6's corollary keeps it, and is discharged per solve by
`Wf.wf_seed` / `Wf.wf_replay` (round-7 review X-8f).  `SupOk` and `SupFresh` are L3's supply
invariant and are NEW relative to round 6, because the label bound goes through
`step_refines_all`; **`SupOk` is four `sin` fields, `SupFresh` is not a field at all** — it is
`∀ z, Sup.Reach su z → z ∉ allVars G` (`RefineLearn.lean:39,54`) — so the two are checked
differently and §R7.1d's original sentence, which put them in one breath as things "a corpus
replay reads out of its `sin` record", was wrong about the second.  `V` and `L` are the input's
own (`inVoc_self`, `concSub_self`), so neither is an assumption.

`SupOk` is worth checking rather than assuming, since it is the one hypothesis round 6 did not
carry: `SupOk su` is `su.lo ≤ su.hi ≤ su.blk` and `2 ≤ su.bsz`, and the `sin` record carries
all four fields.  Over the whole corpus — **450,064 `sin` records, 450,064 satisfy it, 0
violations** — so it costs nothing on real compiler input.  (It is FALSE of the repro
harness's `Sup.ofSeed`, whose `blk = 0` is the harness's real process-global counter; that is
why §R7.1e's witness uses a supply of the compiler's shape.)

**`SupFresh` too** (added after the round-7 review, which measured it first — X-3b).  It is
not a `sin` field, so it has to be simulated: replay `PQueue.build`'s draws (one per `part`
with a non-variable left-hand side, `Constraints.scala:661`) to get `su'`, then test every
input variable of the `svar` table and every id the build minted against `Sup.Reach su'`
(`tmp/L5r7/supfresh.py`).  **450,064 segments, 450,064 satisfy it, 0 violations** — my own
run, and it agrees with the reviewer's.  So both of the hypotheses round 6 did not carry are
discharged on real compiler input, not merely assumed.

```lean
def initState (q : PQueue) (su : Sup) (tr : List String) (fl : Flags) (ns : Names)
    (site : String) (z : Nat) : State :=
  { incm := q, proc := PQueue.empty, env := {}, su := su, trace := tr, flags := fl,
    names := ns, site := site, su0 := z }

theorem vocFixed_terminates_of_buildQueue {V : Finset Var} {L : Finset Label}
    {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z)))
    (hcs : ConcSub L (sys (initState q su' tr fl ns site z)))
    (hvf : VocFixed V (initState q su' tr fl ns site z)) :
    Terminates (initState q su' tr fl ns site z)

theorem noDraw_terminates_of_buildQueue {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z)))
    (h : NoDraw (initState q su' tr fl ns site z)) :
    Terminates (initState q su' tr fl ns site z)
```

### R7.1e The condition is DECIDABLE per solve, and the fragment is inhabited outside round 6's

`NoDraw` quantifies over `Reaches`, which is not decidable; on a run that FINISHES it is a
finite check, and that check is discharged inside Lean by `rfl`, not only measured by the
harness:

```lean
def NoDrawB : Nat → State → Bool
  | 0, s => match step s with
    | .continue _ => false
    | _ => true
  | n + 1, s => match step s with
    | .continue s' => (s'.su.drawn == s.su.drawn) && NoDrawB n s'
    | _ => true

theorem noDraw_of_noDrawB {n : Nat} {s : State} (h : NoDrawB n s = true) : NoDraw s
```

The witness is a four-constraint labelled input at a REAL supply (`blk` ahead of `hi`; the
repro harness's `Sup.ofSeed` has `blk = 0`, which makes `SupFresh` false):

```lean
def vSeed : Seed :=
  { name := "vocfix",
    cons := [⟨0, [], [0, 1]⟩, ⟨1, [0, 2], []⟩, ⟨2, [3], []⟩, ⟨4, [1], []⟩],
    rhoKeys := [] }

theorem vS0_size : vS0.incm.elems.length = 4 := by rfl
theorem vS0_notNoConc : ¬ NoConc vS0
theorem vS0_concrete : isConcDispatch vS0 = true := by rfl
theorem vS0_noDrawB : NoDrawB 20 vS0 = true := by rfl
theorem vS0_terminates : Terminates vS0
```

`vS0_notNoConc` and `vS0_concrete` are the point: the input carries labels and the run takes
the `concrete` dispatch branch, so **round 6's theorem does not apply to it and this one
does**.  The SHIPPED COMPILER agrees on the same seed at ten id bases
(`ERMINE_JAVA_OPTS=-Dermine.useInterface=false tracker/repro/satterm/run.sh sweep
json:<seeds/D.json> 0 9 30 20`): `SOLVED=10 REJECTED=0 HANG=0 OOM=0`,
`DRAWN min=0 median=0 max=0 histogram 0:x10`.

### R7.1f Termination is a TAIL property of the draws

It is enough that the loop STOPS drawing, because termination transports backwards along
`Runs`:

```lean
theorem terminates_of_reaches {s t : State} (h : Reaches s t) (ht : Terminates t) :
    Terminates s

def EventuallyNoDraw (s : State) : Prop := ∃ t, Reaches s t ∧ NoDraw t

theorem terminates_of_eventuallyNoDraw {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : EventuallyNoDraw s) : Terminates s

theorem draws_cofinally_of_not_terminates {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ Terminates s) : ∀ t, Reaches s t → ¬ NoDraw t

theorem not_vocFixed_of_not_terminates {L : Finset Label} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ Terminates s) : ∀ V : Finset Var, ¬ VocFixed V s
```

`draws_cofinally_of_not_terminates` is the sharpest thing this stage has said: a divergent run
draws at cofinally many steps, so the four non-generative dispatch branches and the whole of
`learnPartitions`' folding half (`substitution`, `commonSubexpression`, `cancellation`,
`selfSubstitution`) cannot cause non-termination on their own.  **A caveat that must be
stated with it**: `EventuallyNoDraw` is a *tail* condition, so for a solve whose run has been
observed to finish it is witnessed by the observation and certifies nothing new about that
solve.  Its content is the contrapositive and the class-level statement, not a per-solve
prediction.

## R7.2 — the census, solve by solve

Traces regenerated from scratch for this round (`tmp/L5r7/gentrace.sh`, the round-6 script
with a new output directory), one JVM per corpus group, serialised loader, interfaces off:

```
ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx3000m -Dermine.useInterface=false \
  -Dermine.loadInSeries=true -Dermine.rowTrace=<out>/<group>.tsv" bin/ermine <group's files>
```

Segment counts reproduce round 6's and L2-CORPUS §4a's exactly (54,199 / 92,673 / 83,942 /
56,032 / 54,235 / 54,244 / 54,739).

**The instrument is new, and it is the round-6 review's W-6g.**  `--cycle` and `--mints` were
seed-mode only; `replayMain` now has both, so the cycle detector, the draw counter and round
5's per-key mint tally run over corpus replays directly instead of over transcoded seeds
(`Loop/Main.lean`: `replayCycleOne`, `replayMintOne`; `Loop/Cycle.lean`: `CycleRep.mint0`,
`.grew`, `.maxMint`, `.nconc`, `.drawn0`, and `isConcDispatch`).  One line per solve:

```
lake exe looptrace --replay <group>.tsv --cycle
cycle <i> <site> <loc> SOLVED steps=N states=M drawn=D grew=B mint0=K maxmint=X conc=C
      drawn0=D0 nrows=R canon=- exact=-
lake exe looptrace --replay <group>.tsv --mints
mints <i> <site> <loc> SOLVED steps=N drawn=D max=A remint=B cmax=A' cremint=B' keys=K
```

**The population predicate, and its bias (round-7 review X-8b).**  The census population is
"the solve wrote at least one `inpart` record", and `Subst.scala:1215` writes those only AFTER
`var ps = q.expand.toList` has SUCCEEDED — so a solve the row solver REJECTS is invisible to
it.  Measured: **19 example-`loc` solves the model builds a queue for and runs are dropped by
that predicate, all 19 `REJECTED`, three of them residue** (§R7.2d rows 245–247).  Every table
below therefore carries two populations: **P1**, the `inpart` one the round measured (9,362),
and **P2**, every solve the MODEL ran (9,381 = P1 + 19).  A `BUILD` verdict — `PQueue.build`
itself failed, so `cycleRun` never ran and every field is the structure's default — is excluded
from both; there is exactly one in the seven groups
(`shouldfail/dup01_partition_literal.e(25:7)`), it has no `inpart` record either, and the
instrument now prints `grew=?` for it rather than the default `false` (X-8g).  That one segment
is also the whole of the `rejected=31` (`--cycle`) versus `rejected=32` (plain `--replay`)
difference on `shouldfail`.

`grew` is the vocabulary test: whether some state of the run mentions a minted id (`id ≥ su0`)
absent at the first dequeue.  `drawn − drawn0` is the LOOP's own draw count — `Sup.drawn`
accumulates across `PQueue.build`, which mints for a `Part` whose left-hand side is not a
variable (round-6 review W-6b), and 145 of the 244 residue solves have such a build mint.

```
python3 tmp/L5r7/r7census.py <group> traces/<group>.tsv.gz cyc/<group>.tsv.gz
python3 tmp/L5r7/stdcens.py
```

### R7.2a The example corpus

| group | ex-loc solves | building ≥1 partition | `NoConc` | loop drew NO id | **vocabulary fixed** | …and no `concrete` step | residue |
|---|---|---|---|---|---|---|---|
| `top` | 26,338 | 4,997 | 1,255 | 4,948 | **4,949** | 3,694 | 48 |
| `Ai` | 20,393 | 4,069 | 1,046 | 3,885 | **3,885** | 2,852 | 184 |
| `shouldfail` | 1,380 | 232 | 69 | 224 | **224** | 175 | 8 |
| `bugs` | 36 | 0 | 0 | 0 | 0 | 0 | 0 |
| `guide` | 32 | 0 | 0 | 0 | 0 | 0 | 0 |
| `shouldfail-controls` | 404 | 64 | 18 | 60 | **60** | 42 | 4 |
| **all six, P1 (`inpart`)** | **48,583** | **9,362** | **2,388 (25.5 %)** | **9,117 (97.38 %)** | **9,118 (97.39 %)** | **6,763 (72.2 %)** | **244 (2.61 %)** |
| **all six, P2 (every solve the model ran)** | — | **9,381** | 2,388 (25.5 %) | **9,133 (97.36 %)** | **9,134 (97.37 %)** | 6,763 (72.1 %) | **247 (2.63 %)** |

The per-group rows are P1's, which is what the round originally measured; P2 adds the 19
`REJECTED` solves the `inpart` predicate cannot see, all of them in `shouldfail` (16 of the 19
keep a fixed vocabulary, 3 do not).  **The headline moves by 0.02 points either way; the
population is stated because a termination census that silently drops the solves the solver
REJECTS is exactly backwards for this question, not because the number changes.**

The 9,362 and the 2,388 reproduce round 6's headline numbers exactly, from a census written
against the record format and a model run, not reused.  Three readings:

* **The target is met**, on P2 outright and on P1 within two solves.  The review's ceiling was
  97.6 % measured on a PROXY (whether the SATURATED SET introduces a variable absent from the
  input, over the 9,340 solves that write one); the direct measurement over the model's whole
  run is **97.39 %** on P1 and **97.37 %** on P2.  The 97.64 → 97.39 gap is **two terms of
  opposite sign, not one** (round-7 review X-8d; recomputed here by
  `tmp/L5r7/proxy.py`, diffing the proxy against the model solve by solve):

  ```
  with a saturated set 9,340: proxy fixed 9,120 (97.64 %), proxy grew 220
    (proxy fixed, model fixed) 9,096   (proxy grew, model grew) 220
    (proxy fixed, model GREW)    24    (proxy grew, model fixed) 0
    the 24 are ALL class D -- and class D has 32, so the proxy CATCHES 8 of them
  with NO saturated set at all: 22 -- outside the proxy's population, all model-fixed
  9,120 + 22 - 24 = 9,118
  ```

  So the mechanism named originally (a variable minted and then deleted before `ps` is
  written) is right, the count was not: it is **24 of the 32**, and there is an omitted
  **+22** — solves that write no saturated set at all, which the proxy never counted and which
  are all vocabulary-fixed.
* **The `concrete` branch is worth 25 points.**  Vocabulary fixed AND no `concrete` step is
  **6,763 (72.2 %)**; with the branch paid for it is **9,118 (97.4 %)**.  That is the whole
  return on §R7.1c.
* **`drawn = 0` and "vocabulary fixed" differ by exactly ONE solve**, `core/examples/Accumulate.e(35:13)`:
  the loop draws one id which never enters a partition, because `resolution` takes its `fresh`
  before the guards and then discards it.  So `noDraw_terminates` covers 9,117 and
  `vocFixed_terminates` covers 9,118 — the second theorem earns its keep on one real solve,
  and would earn much more on a corpus with more `resolution` traffic.

### R7.2b The standard library, through the model

| group | stdlib-`loc` solves building ≥1 partition | vocabulary fixed | loop drew no id | with a `concrete` step |
|---|---|---|---|---|
| `boot` | 373 | 373 | 373 | 0 |
| `top` | 415 | 415 | 415 | 0 |
| `Ai` | 415 | 415 | 415 | 0 |
| `shouldfail` | 373 | 373 | 373 | 0 |
| `bugs` | 373 | 373 | 373 | 0 |
| `guide` | 373 | 373 | 373 | 0 |
| `shouldfail-controls` | 373 | 373 | 373 | 0 |
| **all seven** | **2,695** | **2,695 (100 %)** | **2,695 (100 %)** | **0** |

2,695 = the boot's 373 plus the reviewer's 2,322 stdlib-located solves across the six example
groups (W-6e), and this is the same population measured a different way — by running the model
rather than by reading the input's labels.  It agrees: **the standard library never draws an
id, never grows its vocabulary, and never takes the `concrete` branch.**

### R7.2c The cycle detector over the whole corpus

```
lake exe looptrace --replay <group>.tsv --cycle      (all seven groups)
```

| | |
|---|---|
| corpus segments replayed | **450,064** |
| skipped | **0** |
| canonical state repeats | **0** |
| exact state repeats | **0** |
| `FUEL` | **0** |
| deepest run | **140 dequeues**, `core/examples/Ai/IncidentSeverity.e(69:15)` |

This is round 6's search (134,674 synthetic solves) extended to the corpus itself, which is
what W-6g asked for: **no canonical or exact state repeat in any of the 450,064 solves the
compiler performs while loading the corpus**.

**The `hashdiff` / `eqdiff` counters are NOT computed in this mode** (round-7 review X-8c):
in `--cycle` / `--mints` mode `replayMain` never calls `replay`, so the two columns of its
`#summary` line are the literal zeros of `return (1, 0, 0, 0, …)` and nothing is compared.
Only `skipped` is real.  The round's original text claimed those two as evidence that "the
model is running the compiler's own solves"; that claim is **withdrawn from the `--cycle` run**
and re-established by the genuine differential, which is plain `--replay`
(`tmp/L5r7/runreplay.sh`, my own run over all seven groups):

```
boot                 segments=54199 replayed=54199 skipped=0 hashdiff=0 eqdiff=0 rejected=0  fuel=0
top                  segments=92673 replayed=92673 skipped=0 hashdiff=0 eqdiff=0 rejected=0  fuel=0
Ai                   segments=83942 replayed=83942 skipped=0 hashdiff=0 eqdiff=0 rejected=0  fuel=0
shouldfail           segments=56032 replayed=56032 skipped=0 hashdiff=0 eqdiff=0 rejected=32 fuel=0
bugs                 segments=54235 replayed=54235 skipped=0 hashdiff=0 eqdiff=0 rejected=0  fuel=0
guide                segments=54244 replayed=54244 skipped=0 hashdiff=0 eqdiff=0 rejected=0  fuel=0
shouldfail-controls  segments=54739 replayed=54739 skipped=0 hashdiff=0 eqdiff=0 rejected=0  fuel=0
incomplete/np01_add_or_recompute      segments=55015 replayed=55015 skipped=0 hashdiff=0 eqdiff=0
incomplete/gu05_star_join_4dim…       segments=54235 replayed=54235 skipped=0 hashdiff=0 eqdiff=0
```

**450,064 segments, 0 `hashdiff`, 0 `eqdiff`, 0 skipped** — so the differential does hold, and
now it has been run.  (`rejected=32` here against the `--cycle` run's 31 is the one `BUILD`
segment of X-8g, not a disagreement.)

### R7.2d The residue, one row per solve

Every one of the 244 example solves outside the fragment, with what the brief asks for: the
module and location, the generative rules that appear in the saturated set, the ids the LOOP
drew, how many NEW names entered a state (`maxmint − mint0`), the largest number of fresh
carriers installed at ONE key `(lhs, concrete part)` (round 5's pump counter, `--mints`'
`cmax`), the input's key shape, the number of input partitions, the dequeue count, and how
many dequeues took the `concrete` branch.

Key shape legend: `join` = some input partition has ≥ 2 abstract parts AND a nonempty concrete
part (`splitConcrete`'s firing shape); `lone` = some input partition has exactly one abstract
part and a nonempty concrete part (`resolution`'s premise shape); `bare` = some input partition
is a whole concrete row `v <- ((|C|))` (the `concrete` dispatch's shape).  `SC`/`SK`/`SR`/`Res`/`ResR`
are `SplitConcrete`, `SplitKeyed`, `SplitRow`, `Resolution`, `ResolutionRow`.

Rows 1–244 are population P1's residue.  **Rows 245–247, marked †, are the three solves the
`inpart` predicate cannot see** (round-7 review X-8b): the row solver REJECTS them, so
`Subst.scala:1215` writes no `inpart` and no `sat` record, and their input key shape and
partition count are read off the `scon` payloads (which `RowTrace.solveInput` writes BEFORE
the solve) instead.  All three are in `shouldfail/`, all three draw one id, take two
`concrete` steps and reach `cmax = 1`.

Every one of rows 1–244 is `SOLVED` by the model; rows 245–247 are `REJECTED` by it, as by the
compiler.  None of the 247 has a canonical or an exact state repeat.

| # | module(location) | generative rules in the saturated set | ids drawn | new names | max at one key | input key shape | parts | dequeues | `concrete` steps |
|---:|---|---|---:|---:|---:|---|---:|---:|---:|
| 1 | `Accumulate.e(32:3)` | SC1 | 6 | 3 | 1 | bare | 5 | 30 | 6 |
| 2 | `Accumulate.e(35:13)` | SC2 | 1 | 1 | 1 | join | 3 | 5 | 0 |
| 3 | `Accumulate.e(36:13)` | SC1 | 4 | 3 | 1 | bare | 5 | 33 | 7 |
| 4 | `Accumulate.e(37:16)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 5 | `Accumulate.e(37:16)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 6 | `Ai/BatteryCycling.e(61:19)` | SC1 | 4 | 3 | 1 | bare | 5 | 34 | 7 |
| 7 | `Ai/BatteryCycling.e(61:27)` | ResR2 | 7 | 4 | 1 | bare | 5 | 38 | 7 |
| 8 | `Ai/BatteryCycling.e(64:14)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 9 | `Ai/BatteryCycling.e(64:14)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 10 | `Ai/BatteryCycling.e(64:14)` | SC1 | 9 | 6 | 2 | join/bare | 5 | 46 | 5 |
| 11 | `Ai/BatteryCycling.e(69:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 12 | `Ai/BatteryCycling.e(69:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 13 | `Ai/BatteryCycling.e(69:3)` | SC1 | 9 | 6 | 2 | join/bare | 5 | 47 | 5 |
| 14 | `Ai/BatteryCycling.e(70:6)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 15 | `Ai/BatteryCycling.e(70:6)` | SC4+Res3 | 7 | 3 | 1 | bare | 6 | 46 | 2 |
| 16 | `Ai/BatteryCycling.e(71:29)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 17 | `Ai/BatteryCycling.e(72:29)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 18 | `Ai/BatteryCycling.e(84:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 19 | `Ai/BatteryCycling.e(84:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 20 | `Ai/BatteryCycling.e(88:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 21 | `Ai/BatteryCycling.e(88:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 22 | `Ai/ClinicalTrial.e(109:12)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 23 | `Ai/ClinicalTrial.e(109:12)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 24 | `Ai/ClinicalTrial.e(67:24)` | SC1 | 6 | 3 | 1 | bare | 5 | 35 | 6 |
| 25 | `Ai/ClinicalTrial.e(72:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 26 | `Ai/ClinicalTrial.e(72:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 27 | `Ai/ClinicalTrial.e(72:3)` | SC1 | 9 | 6 | 2 | join/bare | 5 | 46 | 5 |
| 28 | `Ai/ClinicalTrial.e(73:6)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 29 | `Ai/ClinicalTrial.e(73:6)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 45 | 2 |
| 30 | `Ai/ClinicalTrial.e(73:6)` | (none in `sat`) | 2 | 1 | 1 | bare | 7 | 24 | 3 |
| 31 | `Ai/ClinicalTrial.e(74:31)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 32 | `Ai/ClinicalTrial.e(75:31)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 33 | `Ai/FiscalCalendar.e(135:31)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 34 | `Ai/FiscalCalendar.e(76:15)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 35 | `Ai/FiscalCalendar.e(76:15)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 47 | 2 |
| 36 | `Ai/FiscalCalendar.e(76:15)` | SC1 | 13 | 7 | 1 | bare | 7 | 64 | 7 |
| 37 | `Ai/FiscalCalendar.e(76:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 38 | `Ai/FiscalCalendar.e(76:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 39 | `Ai/FiscalCalendar.e(76:3)` | SC2 | 9 | 6 | 2 | join/bare | 5 | 44 | 5 |
| 40 | `Ai/FiscalCalendar.e(78:41)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 41 | `Ai/FiscalCalendar.e(83:16)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 42 | `Ai/FiscalCalendar.e(83:16)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 43 | `Ai/GridTelemetry.e(100:16)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 44 | `Ai/GridTelemetry.e(100:16)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 45 | `Ai/GridTelemetry.e(110:15)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 46 | `Ai/GridTelemetry.e(110:15)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 47 | `Ai/GridTelemetry.e(115:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 48 | `Ai/GridTelemetry.e(115:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 49 | `Ai/GridTelemetry.e(78:22)` | SC1 | 6 | 3 | 1 | bare | 5 | 32 | 6 |
| 50 | `Ai/GridTelemetry.e(78:34)` | (none in `sat`) | 4 | 3 | 1 | bare | 5 | 33 | 7 |
| 51 | `Ai/GridTelemetry.e(79:22)` | SC1 | 6 | 3 | 1 | bare | 5 | 32 | 6 |
| 52 | `Ai/GridTelemetry.e(83:15)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 53 | `Ai/GridTelemetry.e(83:15)` | SC4+Res3 | 7 | 3 | 1 | bare | 6 | 47 | 2 |
| 54 | `Ai/GridTelemetry.e(83:15)` | (none in `sat`) | 5 | 2 | 1 | bare | 7 | 40 | 4 |
| 55 | `Ai/GridTelemetry.e(83:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 56 | `Ai/GridTelemetry.e(83:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 57 | `Ai/GridTelemetry.e(83:3)` | SC2 | 8 | 6 | 2 | join/bare | 7 | 42 | 5 |
| 58 | `Ai/GridTelemetry.e(85:22)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 59 | `Ai/GridTelemetry.e(85:22)` | SC4+SK1+Res3 | 7 | 3 | 1 | bare | 6 | 48 | 2 |
| 60 | `Ai/GridTelemetry.e(85:22)` | (none in `sat`) | 1 | 1 | 1 | bare | 7 | 22 | 3 |
| 61 | `Ai/GridTelemetry.e(94:15)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 62 | `Ai/GridTelemetry.e(94:15)` | SC4+SK1+Res3 | 5 | 3 | 1 | bare | 6 | 47 | 2 |
| 63 | `Ai/GridTelemetry.e(94:15)` | SC3 | 12 | 7 | 1 | bare | 7 | 65 | 7 |
| 64 | `Ai/GridTelemetry.e(94:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 65 | `Ai/GridTelemetry.e(94:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 66 | `Ai/GridTelemetry.e(94:3)` | SC2 | 8 | 6 | 2 | join/bare | 5 | 41 | 5 |
| 67 | `Ai/GridTelemetry.e(96:41)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 68 | `Ai/HeadcountPlan.e(59:16)` | SC1 | 5 | 3 | 1 | bare | 5 | 30 | 7 |
| 69 | `Ai/HeadcountPlan.e(59:29)` | SC1 | 6 | 3 | 1 | bare | 5 | 35 | 7 |
| 70 | `Ai/HeadcountPlan.e(62:16)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 71 | `Ai/HeadcountPlan.e(62:16)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 72 | `Ai/HeadcountPlan.e(62:16)` | SC2 | 8 | 6 | 2 | join/bare | 7 | 43 | 5 |
| 73 | `Ai/HeadcountPlan.e(62:46)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 24 | 3 |
| 74 | `Ai/HeadcountPlan.e(67:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 75 | `Ai/HeadcountPlan.e(67:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 76 | `Ai/HeadcountPlan.e(67:3)` | SC2 | 9 | 7 | 3 | join/bare | 7 | 47 | 5 |
| 77 | `Ai/HeadcountPlan.e(68:6)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 78 | `Ai/HeadcountPlan.e(68:6)` | SC4+Res3 | 7 | 3 | 1 | bare | 6 | 47 | 2 |
| 79 | `Ai/HeadcountPlan.e(68:6)` | SC1 | 9 | 6 | 1 | bare | 7 | 56 | 7 |
| 80 | `Ai/HeadcountPlan.e(70:13)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 81 | `Ai/HeadcountPlan.e(70:13)` | SC4+Res3 | 7 | 3 | 1 | bare | 6 | 47 | 2 |
| 82 | `Ai/HeadcountPlan.e(70:13)` | SC1 | 20 | 9 | 2 | bare | 7 | 84 | 8 |
| 83 | `Ai/HeadcountPlan.e(72:65)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 84 | `Ai/HeadcountPlan.e(87:11)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 85 | `Ai/HeadcountPlan.e(87:11)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 86 | `Ai/HeadcountPlan.e(90:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 87 | `Ai/HeadcountPlan.e(90:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 88 | `Ai/IncidentSeverity.e(103:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 89 | `Ai/IncidentSeverity.e(103:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 90 | `Ai/IncidentSeverity.e(108:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 91 | `Ai/IncidentSeverity.e(108:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 92 | `Ai/IncidentSeverity.e(61:18)` | ResR2 | 8 | 4 | 1 | bare | 5 | 41 | 7 |
| 93 | `Ai/IncidentSeverity.e(61:37)` | SC1 | 3 | 3 | 1 | bare | 5 | 28 | 7 |
| 94 | `Ai/IncidentSeverity.e(64:10)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 95 | `Ai/IncidentSeverity.e(64:10)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 96 | `Ai/IncidentSeverity.e(64:10)` | SC1 | 9 | 6 | 2 | join/bare | 5 | 44 | 5 |
| 97 | `Ai/IncidentSeverity.e(64:38)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 98 | `Ai/IncidentSeverity.e(69:15)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 99 | `Ai/IncidentSeverity.e(69:15)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 45 | 2 |
| 100 | `Ai/IncidentSeverity.e(69:15)` | SC4+SR1 | 73 | 16 | 3 | bare | 7 | 140 | 12 |
| 101 | `Ai/IncidentSeverity.e(69:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 102 | `Ai/IncidentSeverity.e(69:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 103 | `Ai/IncidentSeverity.e(69:3)` | SC2 | 10 | 7 | 3 | join/bare | 7 | 49 | 6 |
| 104 | `Ai/IncidentSeverity.e(70:36)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 105 | `Ai/IncidentSeverity.e(71:36)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 106 | `Ai/IncidentSeverity.e(98:15)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 107 | `Ai/IncidentSeverity.e(98:15)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 108 | `Ai/RevenueByPeriod.e(71:20)` | SC1 | 6 | 3 | 1 | bare | 5 | 32 | 6 |
| 109 | `Ai/RevenueByPeriod.e(71:35)` | SC1 | 4 | 3 | 1 | bare | 5 | 34 | 7 |
| 110 | `Ai/RevenueByPeriod.e(76:15)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 111 | `Ai/RevenueByPeriod.e(76:15)` | SC4+SK1+Res3 | 5 | 3 | 1 | bare | 6 | 47 | 2 |
| 112 | `Ai/RevenueByPeriod.e(76:15)` | SC1 | 11 | 6 | 1 | bare | 7 | 60 | 7 |
| 113 | `Ai/RevenueByPeriod.e(76:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 114 | `Ai/RevenueByPeriod.e(76:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 115 | `Ai/RevenueByPeriod.e(76:3)` | SC1 | 10 | 7 | 3 | join/bare | 7 | 50 | 5 |
| 116 | `Ai/RevenueByPeriod.e(77:42)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 117 | `Ai/RevenueByPeriod.e(84:15)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 118 | `Ai/RevenueByPeriod.e(84:15)` | SC4+SK1+Res3 | 5 | 3 | 1 | bare | 6 | 47 | 2 |
| 119 | `Ai/RevenueByPeriod.e(84:15)` | SC1 | 13 | 7 | 3 | bare | 7 | 72 | 6 |
| 120 | `Ai/RevenueByPeriod.e(84:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 121 | `Ai/RevenueByPeriod.e(84:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 122 | `Ai/RevenueByPeriod.e(84:3)` | SC1 | 9 | 6 | 2 | join/bare | 7 | 47 | 5 |
| 123 | `Ai/RevenueByPeriod.e(86:41)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 124 | `Ai/RevenueByPeriod.e(90:16)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 125 | `Ai/RevenueByPeriod.e(90:16)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 126 | `Ai/RevenueByPeriod.e(95:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 127 | `Ai/RevenueByPeriod.e(95:12)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 128 | `Ai/SalesByRegion.e(63:16)` | (none in `sat`) | 4 | 3 | 1 | bare | 5 | 33 | 7 |
| 129 | `Ai/SalesByRegion.e(63:30)` | SC1 | 3 | 3 | 1 | bare | 5 | 31 | 7 |
| 130 | `Ai/SalesByRegion.e(63:43)` | ResR2 | 9 | 4 | 1 | bare | 5 | 38 | 7 |
| 131 | `Ai/SalesByRegion.e(65:15)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 132 | `Ai/SalesByRegion.e(65:15)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 133 | `Ai/SalesByRegion.e(65:15)` | SC1 | 9 | 6 | 2 | join/bare | 7 | 47 | 5 |
| 134 | `Ai/SalesByRegion.e(65:40)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 135 | `Ai/SalesByRegion.e(71:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 136 | `Ai/SalesByRegion.e(71:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 137 | `Ai/SalesByRegion.e(71:3)` | SC1 | 8 | 6 | 2 | join/bare | 5 | 42 | 5 |
| 138 | `Ai/SalesByRegion.e(72:6)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 139 | `Ai/SalesByRegion.e(72:6)` | SC4+SK1+Res3 | 7 | 3 | 1 | bare | 6 | 48 | 2 |
| 140 | `Ai/SalesByRegion.e(72:6)` | (none in `sat`) | 8 | 3 | 1 | bare | 7 | 53 | 7 |
| 141 | `Ai/SalesByRegion.e(74:32)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 142 | `Ai/SalesByRegion.e(92:17)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 143 | `Ai/SalesByRegion.e(92:17)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 144 | `Ai/SalesByRegion.e(95:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 145 | `Ai/SalesByRegion.e(95:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 146 | `Ai/SupplyChainInventory.e(62:19)` | (none in `sat`) | 4 | 3 | 1 | bare | 5 | 32 | 7 |
| 147 | `Ai/SupplyChainInventory.e(62:30)` | (none in `sat`) | 4 | 3 | 1 | bare | 5 | 34 | 7 |
| 148 | `Ai/SupplyChainInventory.e(64:14)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 149 | `Ai/SupplyChainInventory.e(64:14)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 150 | `Ai/SupplyChainInventory.e(64:14)` | SC1 | 9 | 6 | 2 | join/bare | 7 | 46 | 5 |
| 151 | `Ai/SupplyChainInventory.e(64:43)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 152 | `Ai/SupplyChainInventory.e(69:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 153 | `Ai/SupplyChainInventory.e(69:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 154 | `Ai/SupplyChainInventory.e(69:3)` | SC1 | 8 | 6 | 2 | join/bare | 5 | 41 | 5 |
| 155 | `Ai/SupplyChainInventory.e(70:6)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 156 | `Ai/SupplyChainInventory.e(70:6)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 45 | 2 |
| 157 | `Ai/SupplyChainInventory.e(70:6)` | SC2 | 18 | 11 | 2 | bare | 7 | 80 | 7 |
| 158 | `Ai/SupplyChainInventory.e(71:50)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 159 | `Ai/SupplyChainInventory.e(72:13)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 160 | `Ai/SupplyChainInventory.e(72:13)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 46 | 2 |
| 161 | `Ai/SupplyChainInventory.e(72:13)` | SC1 | 8 | 5 | 1 | bare | 7 | 51 | 7 |
| 162 | `Ai/SupplyChainInventory.e(74:20)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 163 | `Ai/SupplyChainInventory.e(74:20)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 46 | 2 |
| 164 | `Ai/SupplyChainInventory.e(74:20)` | SC2+Res1 | 24 | 14 | 4 | bare | 7 | 105 | 7 |
| 165 | `Ai/SupplyChainInventory.e(96:15)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 166 | `Ai/SupplyChainInventory.e(96:15)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 167 | `Ai/SupplyChainInventory.e(99:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 168 | `Ai/SupplyChainInventory.e(99:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 169 | `Ai/TelescopeTime.e(101:38)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 27 | 3 |
| 170 | `Ai/TelescopeTime.e(126:15)` | SC2 | 1 | 1 | 1 | lone | 2 | 5 | 0 |
| 171 | `Ai/TelescopeTime.e(126:15)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 172 | `Ai/TelescopeTime.e(129:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 173 | `Ai/TelescopeTime.e(129:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 174 | `Ai/TelescopeTime.e(85:21)` | (none in `sat`) | 5 | 4 | 1 | bare | 5 | 35 | 8 |
| 175 | `Ai/TelescopeTime.e(85:35)` | SC1 | 6 | 3 | 1 | bare | 5 | 33 | 6 |
| 176 | `Ai/TelescopeTime.e(85:45)` | SC1 | 8 | 3 | 1 | bare | 5 | 35 | 6 |
| 177 | `Ai/TelescopeTime.e(90:13)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 178 | `Ai/TelescopeTime.e(90:13)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 179 | `Ai/TelescopeTime.e(90:13)` | SC2 | 8 | 6 | 2 | join/bare | 5 | 40 | 5 |
| 180 | `Ai/TelescopeTime.e(90:41)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 181 | `Ai/TelescopeTime.e(96:3)` | SC2 | 1 | 1 | 1 | lone | 4 | 9 | 0 |
| 182 | `Ai/TelescopeTime.e(96:3)` | SC2+SK1+Res3 | 4 | 2 | 1 | lone/bare | 5 | 20 | 1 |
| 183 | `Ai/TelescopeTime.e(96:3)` | SC2 | 9 | 6 | 2 | join/bare | 5 | 44 | 5 |
| 184 | `Ai/TelescopeTime.e(97:6)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 185 | `Ai/TelescopeTime.e(97:6)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 46 | 2 |
| 186 | `Ai/TelescopeTime.e(97:6)` | SC1 | 13 | 7 | 1 | bare | 7 | 64 | 7 |
| 187 | `Ai/TelescopeTime.e(99:13)` | SC2 | 1 | 1 | 1 | bare | 5 | 13 | 1 |
| 188 | `Ai/TelescopeTime.e(99:13)` | SC4+Res3 | 5 | 3 | 1 | bare | 6 | 44 | 2 |
| 189 | `Ai/TelescopeTime.e(99:13)` | SC2 | 10 | 8 | 2 | bare | 7 | 64 | 7 |
| 190 | `ChartsExample.e(370:4)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 191 | `ChartsExample.e(370:4)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 192 | `ChartsExample.e(383:6)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 193 | `ChartsExample.e(383:6)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 194 | `ChartsExample.e(402:6)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 195 | `ChartsExample.e(402:6)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 196 | `ChartsExample.e(411:6)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 197 | `ChartsExample.e(411:6)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 198 | `ChartsExample.e(440:4)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 199 | `ChartsExample.e(440:4)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 200 | `ChartsExample.e(445:4)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 201 | `ChartsExample.e(445:4)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 202 | `ChartsExample.e(445:4)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 203 | `ChartsExample.e(450:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 204 | `ChartsExample.e(450:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 205 | `ChartsExample.e(450:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 206 | `ChartsExample.e(450:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 207 | `ChartsExample.e(478:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 208 | `ChartsExample.e(478:3)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 209 | `ChartsExample.e(498:3)` | SC4 | 2 | 2 | 1 | join | 2 | 6 | 0 |
| 210 | `ChartsExample.e(498:3)` | SC4 | 2 | 2 | 1 | join | 2 | 6 | 0 |
| 211 | `ChartsExample.e(69:20)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 212 | `ChartsExample.e(70:29)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 213 | `ChartsExample.e(70:29)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 214 | `ChartsExample.e(71:29)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 215 | `ChartsExample.e(71:29)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 216 | `ChartsExample.e(75:21)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 217 | `GridExample.e(109:3)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 26 | 3 |
| 218 | `GridExample.e(111:3)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 219 | `PieChartLegendExample.e(11:7)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 220 | `PivotTest.e(1:1)` | SC1 | 1 | 1 | 1 | join/lone/bare | 3 | 6 | 2 |
| 221 | `PivotTest.e(1:1)` | SC1 | 1 | 1 | 1 | join/lone/bare | 3 | 6 | 2 |
| 222 | `PivotTest.e(36:13)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 223 | `PivotTest.e(36:13)` | SC1 | 1 | 1 | 1 | join/lone/bare | 3 | 6 | 2 |
| 224 | `PivotTest.e(57:14)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 225 | `PivotTest.e(57:14)` | SC1 | 1 | 1 | 1 | join/lone/bare | 3 | 6 | 2 |
| 226 | `SoftRelation.e(56:3)` | (none in `sat`) | 3 | 3 | 2 | bare | 5 | 25 | 3 |
| 227 | `SoftRelation.e(84:20)` | SC1 | 1 | 1 | 1 | join/bare | 2 | 5 | 2 |
| 228 | `SoftRelation.e(88:25)` | SC1 | 1 | 1 | 1 | join/bare | 2 | 5 | 2 |
| 229 | `SoftRelation.e(90:25)` | SC1 | 1 | 1 | 1 | join/bare | 2 | 5 | 2 |
| 230 | `SoftRelation.e(92:25)` | SC2 | 1 | 1 | 1 | join | 2 | 6 | 0 |
| 231 | `SoftRelation.e(92:25)` | SC2 | 1 | 1 | 1 | join/bare | 3 | 5 | 1 |
| 232 | `SoftRelation.e(92:25)` | SC2 | 1 | 1 | 1 | join | 1 | 3 | 0 |
| 233 | `shouldfail-controls/control01_vocabulary.e(24:10)` | SC1 | 6 | 3 | 1 | bare | 5 | 32 | 6 |
| 234 | `shouldfail-controls/control04_step2_satisfiable.e(29:6)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 235 | `shouldfail-controls/control07_pair.e(22:6)` | SC1 | 1 | 1 | 1 | join/bare | 3 | 8 | 3 |
| 236 | `shouldfail-controls/control07_pair.e(22:6)` | SC2 | 1 | 1 | 1 | join/bare | 4 | 9 | 3 |
| 237 | `shouldfail/der02_copy_column_onto_existing.e(39:7)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 238 | `shouldfail/dup03_join1_shared_column.e(30:7)` | SC2 | 1 | 1 | 1 | join/lone | 3 | 5 | 0 |
| 239 | `shouldfail/dup03_join1_shared_column.e(30:7)` | SC2 | 2 | 1 | 1 | join/lone/bare | 4 | 9 | 2 |
| 240 | `shouldfail/dup04_joinby_shared_column.e(30:7)` | SC2 | 1 | 1 | 1 | join/lone | 3 | 5 | 0 |
| 241 | `shouldfail/dup04_joinby_shared_column.e(30:7)` | SC2 | 2 | 1 | 1 | join/lone/bare | 4 | 9 | 2 |
| 242 | `shouldfail/dup08_copy_column_onto_itself.e(24:7)` | SC2 | 1 | 1 | 1 | join/lone | 2 | 4 | 0 |
| 243 | `shouldfail/inc08_project_absent_from_join_result.e(47:19)` | SC1 | 6 | 3 | 1 | bare | 5 | 30 | 6 |
| 244 | `shouldfail/mis02_join_result_annotation.e(42:16)` | (none in `sat`) | 4 | 3 | 1 | bare | 5 | 34 | 7 |
| 245 | `shouldfail/der06_shared_two_var_remainder.e(66:7)` † | (none in `sat`) | 1 | 1 | 1 | join | 2 | 6 | 2 |
| 246 | `shouldfail/der07_shared_three_var_remainder.e(44:7)` † | (none in `sat`) | 1 | 1 | 1 | join | 2 | 7 | 2 |
| 247 | `shouldfail/der08_shared_remainder_relations.e(42:7)` † | (none in `sat`) | 1 | 1 | 1 | join | 2 | 6 | 2 |

† `REJECTED` by the row solver, so invisible to the `inpart` census predicate; the shape
columns come from `scon`.  Their `(none in `sat`)` is for a different reason from class D's:
there is no saturated set at all, rather than one that has lost the provenance.

## R7.3 — the residue's shape, and a per-class lemma

### R7.3a The four classes

| class | count | what it is |
|---|---|---|
| **A** `split-only` | 173 | the saturated set records only `SplitConcrete`/`SplitKeyed`/`SplitRow` derivations |
| **B** `split+resolution` | 36 | both minting rules appear |
| **C** `resolution-only` | 3 | only `Resolution`/`ResolutionRow` appears |
| **D** no generative provenance in `sat` | 32 | the model minted, but **no** generative provenance survives into the saturated set |

Class **D** is the round's one genuinely new empirical finding, and it is the NameLoss shape
(`Rowpartition/NameLoss.lean`, ticket 2026-09-02) seen in the corpus: **every one of the 32
takes at least three `concrete` dispatch steps** (3 on 24 of them, 4 on one, 7 on six, 8 on
one) and draws between 1 and 8 ids, and the minted partitions are consumed by
`makeConcrete`/`destructiveSub` before `Subst.solve` writes `ps`.  It is also why the
round-6 review's saturated-set proxy read 97.6 % where the direct measurement reads 97.39 %:
a solve can mint and lose the evidence.  The 32 are concentrated in
`Ai/{GridTelemetry,SalesByRegion,SupplyChainInventory,ClinicalTrial,IncidentSeverity,TelescopeTime,…}.e`
and `GridExample.e` / `SoftRelation.e` / `shouldfail/mis02_join_result_annotation.e`.

Sub-classing **A** by what the loop actually adds:

| sub-class | count | shape |
|---|---|---|
| A1: one new name, **no** `concrete` step | **97** | exactly ONE id drawn, 3–9 dequeues, 1–4 input partitions; input key shape `join` 47, `lone` 28, `join/lone` 22.  (The round originally called this "the B1 shape"; that was wrong twice — the brief's gloss of the phrase, "single mints immediately concretised", is A2 below, and `B1` in this tracker already names the `makeEmpty` propagation fix, `B1-FIX.md`.  Round-7 review X-8e.) |
| A2: one new name, with `concrete` steps | 29 | one mint, then the row is concretised; every one has a `bare` input partition and `cmax = 1` |
| A3: more than one new name | 47 | 45 of them have 5 or 7 input partitions and all but two carry a `bare` whole row; `cmax` 1 on 24, 2 on 18, 3 on 5 |

### R7.3b What the round-5 pump needs, and what the corpus lacks

Round 5's pump is REPEATED MINTING AT ONE KEY — the same `(lhs, concrete part)` key minted
turn after turn (`Loop/Pump.lean`; the round-5 hunt drove it to ten turns, the round-6
reviewer to 443 dequeues and 1,382 draws).  **Which key matters, and the round originally got
it wrong** (round-7 review X-8a(2)): round 5's refutation witnesses `cMint4`/`cMint8` are
`MintsAt … 4 cKey` with `cKey` from `carrierKeys`, so the pump is defined on the **CARRIER**
key — every fresh carrier installed at the dequeued left-hand side, `resolution`'s mint
included — and the instrument for it is `cmax`/`cremint`, not the `splitConcrete` GUARD key's
`max`/`remint`.  Both counters are reported below; the guard key is the flat one.  The
instrument is now runnable over the corpus (`--replay --mints`), and on the guard key the
answer is flat **within the seven groups**:

```
lake exe looptrace --replay <group>.tsv --mints        (all seven groups)
```

| population | solves | largest `splitConcrete` GUARD-key mints (`max`) | keys minted more than once (`remint`) |
|---|---|---|---|
| stdlib-`loc`, all seven groups | 2,695 | **0** (nothing minted at all) | 0 |
| example-`loc`, seven groups | 9,362 | **1** | **0** |
| `core/examples/incomplete/`, the group's own solves | 1,283 | **2** | **1 solve** |

**Corrected (round-7 review X-8a(1)).**  The round originally concluded from the first two
rows that "no `splitConcrete` key is ever minted twice, anywhere in the corpus — the pump shape
does not occur in real code even once".  That is **false**: `core/examples/incomplete/` is
inside `core/examples`, the round did not measure it, and it holds a counter-witness.  I traced
the file myself:

```
mints 54291 trySolveOn core/examples/incomplete/np01_add_or_recompute.e(134:15) SOLVED
      steps=98 drawn=22 max=2 remint=1 cmax=3 cremint=3 keys=5
cycle 54291 … SOLVED steps=98 states=99 drawn=22 grew=true mint0=4 maxmint=17 conc=8
      drawn0=4 nrows=8 canon=- exact=-
looptrace --replay <that file> : segments=55015 replayed=55015 skipped=0 hashdiff=0 eqdiff=0
```

98 dequeues, **18 loop draws, one `splitConcrete` guard key minted TWICE**, three carrier keys
re-minted — and the plain-`--replay` differential on the same file is clean, so it is the
SHIPPED COMPILER's solve, not a model artefact.  The honest statement is: **no `splitConcrete`
guard key is minted twice in the seven groups; `core/examples/incomplete/` has exactly one
solve that does.**

And the CARRIER counter — the one round 5's pump is actually defined on — repeats already in
the seven groups:

| `cmax` (fresh carriers at one key) | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| example solves, seven groups | 9,118 | 198 | 40 | 5 | 1 | 0 | 0 |
| stdlib solves, seven groups | 2,695 | 0 | 0 | 0 | 0 | 0 | 0 |
| `incomplete/`, the group's own (review X-7) | 1,188 | 66 | 19 | 5 | 2 | 2 | 1 |

**46 of the seven groups' own 9,362 solves have `cremint ≥ 1`** — a carrier key minted more
than once — with three distinct re-minted keys on `Ai/SupplyChainInventory.e(74:20)`; the
review's `incomplete/` census adds 29 more, reaching `cmax = 6` at
`gu05_star_join_4dim_concrete_signature.e(62:1)` (281 dequeues, 149 loop draws — 155 counting
`PQueue.build`'s six — which I re-derived from my own trace of that file; the review quotes 145
at X-7 and 149 at X-9(9)).  So **round 5's pump shape does occur in real code**, up to four
turns in the seven groups and six in `incomplete/`; what does not occur, outside that one
`np01` solve, is a repeat at the `splitConcrete` GUARD key.

`cmax = 0` is exactly the 9,118 vocabulary-fixed solves — an independent cross-check of the
census from a different instrument.  The deepest are
`Ai/SupplyChainInventory.e(74:20)` (`cmax = 4`, 24 draws, 105 dequeues) and
`Ai/IncidentSeverity.e(69:15)` (`cmax = 3`, 73 draws, 140 dequeues).

So, class by class, what the pump needs and the class lacks:

* **A1 (97 solves)** lacks the pump's *second turn* outright: **exactly one id drawn, at one
  key** (`drawn = 1` and `cmax = 1` in all 97), and the minted name survives into the
  saturated set — class A is defined by a `SplitConcrete` provenance being there.  There is no
  second mint, at that key or any other.
* **A2 (29)** draws once on 27 of them and twice on two, all at `cmax = 1`: the mint is
  followed by a `concrete` step that closes the variable off.  **A3 (47)** and **D (32)** are
  where the loop mints repeatedly (A3 up to 73 draws, D 3 on 22 of the 32), and never at the
  same `splitConcrete` GUARD key — but the round's original "the repeats are at *different*
  keys" was **true only of the guard key and false of the carrier key its own `cmax` column
  shows** (review X-8a(2)): 18 of A3 and 22 of D reach `cmax = 2`, and five of A3 reach 3, so
  on round 5's own key these solves DO re-mint.  What they do not do is re-mint enough times
  for the count to be unbounded: four turns is the seven groups' maximum.  The round-5 pump needs the SAME key's carrier to
  be withdrawn and re-minted (`destructiveSub` removing the witness, `L5-TERMINATION.md` R4.3.5);
  in the corpus the carrier that would be withdrawn is instead consumed by a `concrete` step
  that closes the variable off for good — which is precisely what §R7.1c's potential counts.
* **B/C (39)** are the only classes where `resolution` mints, and they are the smallest.
  `resolution`'s mint needs two lone-abstract premises at one variable with incomparable
  concrete parts; over all 9,362 example solves the saturated sets record **106** `Resolution`
  and 6 `ResolutionRow` derivations in total, all of them inside these 39 solves.

**A cross-check worth stating, because it looks like an inconsistency and is not.**  Round 6's
census of the example corpus records `SplitConcrete 422, Resolution 106, SplitKeyed 23,
SplitRow 1, ResolutionRow 6`; summed over the 244 residue solves this round finds
`SplitConcrete 418` and all four others in full.  The four missing `SplitConcrete`
derivations are in VOCABULARY-FIXED solves, and they are exactly the rule's REUSE branches:
`splitConcrete`'s syntactic, keyed and concrete-row arms all tag their conclusion
`.splitConcrete` / `.splitKeyed` / `.splitRow` without calling `fresh`.  So a `SplitConcrete`
provenance is not evidence of a mint — which is the same distinction §R7.2a's one-solve gap
makes on `resolution`'s side, in the opposite direction.

### R7.3c The per-class lemma: a mint BOUND is enough

The classes have no separate proofs, and they do not need one: what all of them satisfy is a
CARDINAL bound on the draws, and that is enough.

```lean
theorem step_drawn_ge {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : step s = .continue s') :
    s.su.drawn ≤ s'.su.drawn

theorem drawn_unbounded_of_not_terminates {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ Terminates s) : ∀ n : Nat, ∃ t, Reaches s t ∧ s.su.drawn + n ≤ t.su.drawn

theorem terminates_of_drawsAtMost {k : Nat} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ∀ t, Reaches s t → t.su.drawn ≤ s.su.drawn + k) : Terminates s
```

`terminates_of_drawsAtMost` is the shape every earlier round was reaching for and none could
state: **`k` is not required to be zero, only to EXIST.**  Whatever mint bound a later round
proves — round 4's carrier budget, round 5's charging lemma, KeyedRow's
`mintsBoundedOnSatKeyed2Star` transported to the loop — plugs straight into it and delivers
`Terminates` with no further measure work.  Its contrapositive
(`drawn_unbounded_of_not_terminates`) is the sharpest negative statement of the stage:
**a divergent solve draws unboundedly many ids.**

On the corpus every residue solve draws at most **73** ids (149 in `incomplete/`), so
`terminates_of_drawsAtMost` covers all 247 at `k = 73`.  **The epistemic status of that must be
stated plainly**: the bound is read off the observed run, so the lemma certifies the residue
only in the sense "given a mint bound, termination follows"; it does not supply the bound a
priori.  That is the open problem, and §R7.4 states it.

**And the same is true of the shape-specific lemma the brief hints at for A1**, which is worth
attaching to the table explicitly (round-7 review X-11).  "One mint, then `NoConc`" is
`terminates_of_eventuallyNoDraw` (§R7.1f), and A1's `drawn = 1` makes its hypothesis a finite
check: run to the state just after the single mint and discharge `NoDraw` from there with
`NoDrawB`.  So A1 has its per-class lemma and it is already proved — and it buys nothing, for
exactly the reason above: certifying A1 that way requires running A1 to completion, and a run
that completes already witnesses `Terminates`.  The structural lemma that WOULD have bought
something — "a `splitConcrete` key is minted at most once" — is refuted by
`incomplete/np01_add_or_recompute.e(134:15)` (§R7.3b).

### R7.3d The certified fractions, four ways

| condition | how it is checked | example solves, P1 (`inpart`) | example solves, P2 (model ran) | stdlib solves |
|---|---|---|---|---|
| `NoConc` (round 6) | **from the INPUT alone** | 2,388 / 9,362 = **25.5 %** | 2,388 / 9,381 = 25.5 % | 2,695 / 2,695 = **100 %** |
| `NoDraw` (`noDraw_terminates`) | the model's run: `drawn − drawn0 = 0` | 9,117 / 9,362 = **97.38 %** | 9,133 / 9,381 = **97.36 %** | 2,695 / 2,695 = **100 %** |
| `VocFixed` (`vocFixed_terminates`) | the model's run: `grew = false` | **9,118 / 9,362 = 97.39 %** | **9,134 / 9,381 = 97.37 %** | 2,695 / 2,695 = **100 %** |
| `DrawsAtMost k` (`terminates_of_drawsAtMost`) | a mint bound — the corpus supplies `k ≤ 73` | 9,362 / 9,362 (at the observed `k`) | 9,381 / 9,381 (same) | 2,695 / 2,695 (at `k = 0`) |

(`incomplete/`, which the round did not measure and the round-7 review did: its own solves are
**1,188 / 1,283 = 92.6 %** vocabulary-fixed and 425 / 1,283 `NoConc`, and its stdlib half is
12,682 / 12,682 on every one of the four conditions — X-7.)

Only the first row is a prediction about an unseen input.  Rows two and three are the round's
result: the class is proved to terminate at an explicit bound, and 97.4 % of the example
corpus is measured to be in it.  Row four is the reduction, not a certification.

## R7.4 — the open problem, stated

**Certified population.**  Standard library: **100 %** — 2,695 of 2,695 row-carrying solves
across the seven traces by this round's model run, and 12,682 of 12,682 in `incomplete/` by the
round-7 review's (X-7), which with the boot's own 373 is the round-6 reviewer's 15,377 of
15,377 across all 41 traces — input-checkably, by round 6's `NoConc`.  User programs, run-level:
**97.39 %** of the 9,362 solves the `inpart` census predicate can see (9,118 vocabulary-fixed,
9,117 draw-free) and **97.37 %** of the 9,381 the model actually runs (9,134 / 9,133), the
difference being the 19 `REJECTED` solves that predicate drops (§R7.2, review X-8b).  In
`core/examples/incomplete/`, which this round did not measure, the group's own solves are
**1,188 of 1,283 = 92.6 %** vocabulary-fixed (review X-7).

**The residue, as a named list of shapes.**

| shape | count | what a divergence inside it would have to look like |
|---|---|---|
| **A1** exactly one id drawn, no `concrete` step | 97 | a second mint at the SAME key; the corpus has none, and A1's minted name survives into `sat`, so the carrier `splitConcrete`'s lookup would have to miss is still there |
| **A2** one mint, then the row is concretised | 29 | the concretised variable would have to be re-opened; `makeConcrete` installs `v <- ((|fs|))` and `ensureSuperset` forces every later row of `v` to contain `fs`, which is the potential §R7.1c counts — so a divergence here needs a variable whose concrete row grows without bound, i.e. an unbounded LABEL pool |
| **A3** ≥ 2 new names, `join`/`bare` inputs of 5–7 partitions | 47 | mints at unboundedly many DISTINCT keys; each key is a `(lhs, concrete part)` pair over the input's vocabulary and label pool, so this needs the VOCABULARY to grow — which is what round 4's `hmeas_increases` and round 5's redirect show is possible in principle and what no corpus solve does |
| **B/C** `resolution` mints (36 + 3) | 39 | unboundedly many pairs of lone-abstract premises at one variable with incomparable concrete parts; `resGuard` and `resRow` reuse close the ones the corpus produces |
| **D** mints whose provenance is consumed before `sat` | 32 | the NameLoss race (`destructiveSub` withdrawing the carrier `splitConcrete` would reuse) driven cofinally — round 4's `mS0`/`mH2` witness is exactly one turn of it, and the corpus reaches at most `cmax = 2` |

**What a divergence would have to look like, in one sentence.**  By
`drawn_unbounded_of_not_terminates` it must draw unboundedly many ids, and by
`not_vocFixed_of_not_terminates` it must therefore leave every finite vocabulary — so it must
mint at unboundedly many distinct left-hand sides, each key being a `(lhs, concrete part)`
pair over a label pool `reaches_concSub` proves FIXED.  **Whether it must do so at distinct
keys is exactly what the round originally over-claimed** (review X-8a).  Corrected: at the
`splitConcrete` GUARD key the corpus re-mints once, at
`core/examples/incomplete/np01_add_or_recompute.e(134:15)`, on a solve the shipped compiler
performs; at the CARRIER key round 5's refutation is defined on, 46 of the seven groups' own
9,362 solves re-mint, up to four times, and `incomplete/` reaches six.  So a divergence need
not invent a new key at every turn — it needs the re-minting to be UNBOUNDED, and the largest
depth anyone has measured in real code is six.  The other half of the shape is unchanged and is
the strongest negative on record: the pump's deep witnesses are walks, not cycles — round 6's 0
repeats in 3,082,009 canonical states, and now 0 in 450,064 corpus solves and, by the review,
0 in `incomplete/`'s further 1,851,131 segments.

**The open problem, precisely.**  Is `drawn` bounded along every run from a satisfiable
initial state?  Equivalently, since `terminates_of_drawsAtMost` closes the gap: *does the loop
mint boundedly often?*  Round 4 refuted the two natural charging arguments
(`ChargeI`/`ChargeII`), round 5 refuted the dequeue-order repair, and round 6 and this round
have found no divergence in 134,674 + 450,064 solves.  The question is now a single
quantitative one about `Sup.drawn`, with the whole measure apparatus discharged behind it.

## R7.5 — what round 7 could NOT prove, side by side

| wanted | got | why not more |
|---|---|---|
| an INPUT-checkable condition wider than `NoConc` | **NOT FOUND** | W-9's 111 corpus witnesses refute the obvious one; `substitution` and `commonSubexpression` manufacture `splitConcrete`'s firing shape out of inputs on which it cannot fire, and nothing weaker than "no labels" was found closed under `step` |
| `Terminates` for every satisfiable `Wf s₀` | **NO** | still the plan's open criterion; what is proved is `Terminates` for a class defined by the RUN, which contains 97.4 % of the example corpus and all of the standard library |
| a mint bound | **NO** | round 4's two charging lemmas and round 5's order repair are refuted; this round did not attempt a third and states the reduction instead (`terminates_of_drawsAtMost`) |
| per-class termination lemmas for the five residue shapes | **ONE, cardinal not structural** | `terminates_of_drawsAtMost` covers all five at once given a draw bound; no shape-specific argument was found that supplies the bound |
| the `incomplete/` corpus | **NOT MEASURED THIS ROUND — and it held a counter-witness** | the round-7 reviewer ran both new instruments over all 34 modules (X-7): 1,851,131 segments, **0 canonical and 0 exact repeats, 0 `FUEL`**, deepest run **281 dequeues** at `gu05_star_join_4dim_concrete_signature.e(62:1)`; stdlib-`loc` **12,682 / 12,682** `NoConc`, vocabulary-fixed, draw-free and `concrete`-free; the group's own solves **1,283 built, 425 `NoConc`, 1,188 (92.6 %) vocabulary-fixed, 95 residue** (A/B/C/D = 44/30/1/20).  It is also where the round's `splitConcrete`-guard-key sentence was refuted (X-8a).  **`incomplete/` is inside `core/examples` and should be a first-class group from round 8 on** |

## R7.6 — what a reviewer should re-run

```bash
export PATH=$HOME/.elan/bin:$PATH
cd tracker/lean && lake build Rowpartition          # 855 jobs
lake env lean Audit.lean                            # 3706 theorems / 0 non-standard axioms
grep -nE '\bsorry\b|\baxiom\b|\bpartial\b|native_decide|implemented_by|\bunsafe\b|\bopaque\b|Classical|\badmit\b|#exit' \
  Rowpartition/Loop/{VocFix,Cycle,Main}.lean        # one hit: the word `partial` in Main's doc comment
lake build looptrace                                # 1656 jobs

# the corpus, from scratch (~12 min, ~5 MB of gzipped trace)
tmp/L5r7/gentrace.sh
tmp/L5r7/runcycle.sh          # --replay --cycle over all seven groups
tmp/L5r7/runmints.sh          # --replay --mints over all seven groups
python3 tmp/L5r7/r7census.py <group> traces/<group>.tsv.gz cyc/<group>.tsv.gz
python3 tmp/L5r7/stdcens.py
python3 tmp/L5r7/agg.py       # the residue classification
python3 tmp/L5r7/supok.py     # SupOk on all 450,064 `sin` records
python3 tmp/L5r7/supfresh.py  # SupFresh    on all 450,064 `sin` records  (review X-3b)
python3 tmp/L5r7/verbatim.py  # every quoted Lean declaration against its module

# added after the round-7 review
tmp/L5r7/runreplay.sh         # the GENUINE L2 differential: plain `--replay`, seven groups
python3 tmp/L5r7/r7census2.py # both census populations (9,362 / 9,381) and residue2.json
python3 tmp/L5r7/proxy.py     # the round-6 proxy diffed against the model, solve by solve

# the shipped compiler on the Lean witness, ten id bases
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS=-Dermine.useInterface=false tracker/repro/satterm/run.sh \
  sweep json:tmp/L5r7/seeds/D.json 0 9 30 20        # SOLVED=10, DRAWN 0:x10
```

(`tmp/L5r7` is this round's scratch directory,
`/home/dmitry/.claude/jobs/880c725d/tmp/L5r7/`, the same convention round 6 used for
`tmp/L5r6`; it holds the scripts, the gzipped traces, the two per-solve reports, the residue
JSON and the axiom census.)

`#print axioms` for all 100 declarations of `Loop/VocFix.lean` plus `isConcDispatch` and
`cycleRun` (102 in all): 97 × `[propext, Classical.choice, Quot.sound]`, 2 × `[propext, Quot.sound]`,
3 axiom-free, **0 `sorryAx`** (`tmp/L5r7/{decls.txt,Axioms.lean,axioms.txt}`).

Every Lean declaration quoted in this section was checked against its module mechanically
(`tmp/L5r7/verbatim.py`: extract each `theorem`/`def` block from the Round-7 section,
normalise whitespace, look it up in `Loop/{VocFix,Cycle}.lean`): **50 quoted declarations, 0
differences.**

## R7.7 — Round 7, post-review corrections (2026-09-05, after `L5-REVIEW.md` "Round-7 review", verdict FIX-THEN-ADVANCE)

The reviewer reproduced every theorem, every verbatim quotation and every number on the
population the round measured — 855 jobs, 3706/0, 50/50 verbatim, all 244 residue rows × 9
fields with zero differences — and refuted or qualified **three sentences**.  All three are
corrected in place above; this section records what they said and what they now say, so the
change is not silent.  **No theorem, bound or Lean statement changed**; the certified fraction
moves by at most 0.02 points.

| # | where | OLD (wrong or vacuous) | NEW |
|---|---|---|---|
| **X-8a** | state file, plan L5 row, §R7.3b, §R7.4 | "**no `splitConcrete` key is minted more than once anywhere in the corpus** — the pump shape the last three rounds hunted does not occur in real code even once" | "no `splitConcrete` **GUARD** key is minted twice **in the seven groups**; `core/examples/incomplete/` — which the round did not measure and which is inside `core/examples` — has exactly one solve that does, `np01_add_or_recompute.e(134:15)`.  And round 5's pump is defined on the **CARRIER** key, on which **46 of the seven groups' own 9,362 solves already re-mint**, up to four times (six in `incomplete/`).  So the pump shape DOES occur in real code; what is bounded, at four and six, is how often" |
| **X-8b** | §R7.2, §R7.2a, §R7.2d, §R7.3d, §R7.4, state file, plan row | the census population was "≥ 1 `inpart` record", stated nowhere; "Every one of the 244 is `SOLVED` by the model" | the predicate and its bias are stated: `Subst.scala:1215` writes `inpart` only after `q.expand` SUCCEEDS, so the 19 example solves the row solver REJECTS are invisible.  Both populations are now reported everywhere — **P1 9,362 / 9,118 (97.39 %) / 244** and **P2 9,381 / 9,134 (97.37 %) / 247** — and §R7.2d gains rows 245–247, the three dropped residue solves |
| **X-8c** | §R7.2c, state file, plan row | "skipped / `hashdiff` / `eqdiff` \| **0 / 0 / 0**", glossed as "so the model is running the compiler's own solves" | in `--cycle`/`--mints` mode `replayMain` never calls `replay`; those two counters are the literal zeros of `return (1, 0, 0, 0, …)` and **nothing is compared**.  The row now claims only `skipped`, and the differential is re-established by a plain `--replay` over all seven groups plus the two `incomplete/` files: **450,064 replayed, 0 skipped, 0 `hashdiff`, 0 `eqdiff`** |
| **X-8d** | §R7.2a | the 97.64 → 97.39 gap is "precisely the 32-solve class §R7.3 names" | it is TWO terms: **24 of those 32** (the proxy catches the other 8) **minus** an omitted **+22** — solves that write no saturated set at all, outside the proxy's population, all vocabulary-fixed.  `9,120 + 22 − 24 = 9,118` |
| **X-8e** | §R7.3a | sub-class A1 labelled "the B1 shape" | label dropped: the brief's gloss of that phrase ("single mints immediately concretised") is **A2**, and `B1` in this tracker already names the `makeEmpty` propagation fix |
| **X-8f** | §R7.1d | "`Wf`, `EnvNodup`, the two `KDist`s and `QueueHygiene` are all free at an initial state"; "`SupOk` and `SupFresh` … a corpus replay reads out of its `sin` record" | `Wf` is **kept as a hypothesis** by the `_of_buildQueue` corollaries (dischargeable by `wf_seed`/`wf_replay`); `SupOk` is four `sin` fields but **`SupFresh` is not a field at all**, and the round measured only the first.  It is now measured too: **450,064 / 450,064, 0 violations** |
| **X-8g** | `Loop/Main.lean` | a `buildQueue` failure printed the `CycleRep` DEFAULTS, so a `BUILD` segment scored `grew=false`, i.e. "vocabulary fixed" | the cycle line prints **`grew=?`** on a `BUILD` verdict.  One such segment exists in the seven groups, `shouldfail/dup01_partition_literal.e(25:7)`; it has no `inpart` record, so no number moved, and it is the whole of the `rejected=31` vs `32` difference on `shouldfail` |
| **X-8h** | `Loop/Main.lean` | the five new `CycleRep` fields and `--mints`' `keys` printed only on the `--replay` path | the `json:` seed path prints them too, so a hand-built seed can be scored for `grew`, `conc`, `mint0`, `drawn0` and `keys` without going through a trace |

**Everything in the corrections was re-measured here, not copied.**  My own runs, from my own
traces: the 19 dropped solves and the three residue ones among them (`tmp/L5r7/r7census2.py`,
`dropped.json`); the proxy diff `9,120 / 220 / 24 / +22` (`proxy.py`); `SupFresh`
450,064/450,064 (`supfresh.py`); the plain-`--replay` differential over all seven groups
(`runreplay.sh`); and the `np01_add_or_recompute.e(134:15)` and
`gu05_star_join_4dim_concrete_signature.e(62:1)` witnesses, traced from source with
`-Dermine.rowTrace` and run through both instruments (`tmp/L5r7/inc/`).  The `incomplete/`
group's aggregate figures (12,682 / 1,283 / 1,188 / 95 and the class split) are the reviewer's
X-7 and are attributed as such; I re-derived only the two witness files.  Where my figure and
the review's differ I use mine and say so: `gu05…(62:1)` draws **149** ids in the loop (155
counting `PQueue.build`'s six), which is X-9(9)'s number, not X-7's 145.

`Loop/Main.lean` is the only Lean file touched by these corrections and it carries no theorem.
After them: `lake build Rowpartition` **855 jobs**, `lake env lean Audit.lean` **3706 theorems /
0 non-standard axioms**, `lake build looptrace` **1656 jobs** — unchanged.

**What the reviewer added in the round's favour**, and which is now folded in above: `SupFresh`
holds corpus-wide (X-3b); the theorem instantiated at a witness taking the `concrete` branch
**five times in a row**, with `rowSet`'s strict growth `decide`d at each (X-4); the shipped
compiler at 12 further id bases on this round's witness and 12 on the reviewer's (X-5); a
line-by-line reading of `ensureSuperset` / `makeConcrete` / `destructiveSub` / `findRHS`
against §R7.1c, which confirms all three facts the potential rests on (X-6); and the
`incomplete/` census (X-7).  The round-8 pointer the review leaves — **instrument the MINT
CHAIN DEPTH**, since `227 of 230` `splitConcrete` mint sites in the six example groups are
INPUT variables while `resolution` chains on about half its conclusions (X-9(8)) — is the
first quantity anyone has proposed that a mint bound could plausibly bound.
