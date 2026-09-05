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
