# S1 — SOUNDNESS of `Constraints.incorporateAll`, as a theorem about the loop model

2026-09-05.  Brief `tracker/loopmodel/briefs/brief-S1.md`; plan section
`tracker/LOOP-MODEL-PLAN.md` §S1.  Lean project `tracker/lean/`, branch `scala3-migration`,
from the clean tree at `fde996a`.  LEAN ONLY: no Scala edited, no sbt, nothing committed.

## OUTCOME: **(BUG)** — corrected 2026-09-06 after the S1 review

The original submission called this **P-** on the ground that no compiler-reproducible false
acceptance had been found.  The review's hunt found several, so the brief's own ladder applies:
**(BUG) a deletion or death that is not sound, with a compiler-reproduced seed.**

> **THE SHIPPED COMPILER ACCEPTS UNSATISFIABLE ROW SYSTEMS.**  Two independent mechanisms,
> both with minimal compiler-reproduced seeds now in `tracker/repro/satterm/seeds/unsat/`:
>
> * **`MIN2.json`** — five constraints, UNSAT at **`l17`**, passes `labelCheckEarly`, `SOLVED`
>   at **4 of 20** id bases — **through the `concrete` branch's unlicensed bare-row deletion**,
>   the very hole §S1.1 identifies.  The substitution binds `v1 = v2 = v3 = {l17,l38}` against
>   the input `v2 <- (v1, (|l17|))`, i.e. `l17` in two parts of one whole.
> * **`MIN1.json`** — five constraints, UNSAT at **`l35`**, passes `labelCheckEarly`, `SOLVED`
>   at **20 of 20** id bases.  NOT the bare-row hole: the loop reaches `.done` on a residual it
>   never refuted (saturation incompleteness), and publishes the violated constraint
>   `{l22} <- ({l35}, v4)` unchecked.
>
> Scale (review §2.6, §7): ~9 M generated systems, 11,048 UNSAT + label-check-passing seeds,
> ~27,000 model runs at the shipped flags, **1,166 model false acceptances over 665 seeds**,
> ten replayed on the shipped compiler, **ten accepted**.  Zero unsound REJECTIONS in ~23,000
> runs.

The Lean is unaffected and nothing in it changed: on all 1,166 model false acceptances the
OUTPUT system was itself unsatisfiable, so `NoLoss (sys s) (sys s')` holds vacuously and every
theorem below survives every witness.  What the witnesses refute is the informal reading of
(A) — *"an accepted program is well-typed"* — which is a refutation-COMPLETENESS statement the
loop does not have and S1 never proved.  See "post-review corrections" at the end for the
sentence-by-sentence diff.

With that said, the two halves stand as follows:

* **(B) REJECTION SOUNDNESS is COMPLETE.**  All seven messages `step` can die with are
  accounted for: four are extracted to `¬ SSat (sys s)` at the loop level (the extraction L3
  §2f left open for messages 1, 2 and 7 is written), two are proved UNREACHABLE using
  `QueueHygiene`, and one — the skolem refusal — is the whole of the `NonRefutation` list.  On
  a solve with no `Skolem` variable the exception list disappears entirely.
* **(A) OUTPUT SOUNDNESS is proved for all five branches ON SATISFIABLE INPUT, and only
  there.**  The `concrete` branch deletes a BARE concrete definition `v <- ((|C|))` with
  `C ⊆ fs` and puts NOTHING in its place (when `destructiveSub`'s `srs` is non-empty); with
  `C ≠ fs` that is a real loss.  So `step_noLoss_all` carries the proviso `BareAgree s`, whose
  ONLY discharge is `SSat (sys s)`, and the unconditional statement is the disjunction
  `NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)`.  `L5-TERMINATION.md` §C1.5 predicted exactly
  this; S1 proves it and localises it to that one shape.  **`solve_sound` says NOTHING when
  the input is unsatisfiable**, and that is exactly where the bug lives.
* **The proviso is not vacuous and it is not rare.**  `BareAgree` FAILS at states the shipped
  flags reach from `labelCheckEarly`-passing inputs: the review's instrument found the hole's
  SHAPE in **26.7 %** of 11,048 runs and the unlicensed DELETION firing in **1.6 %**.

## Figures

| | at start | at the end |
|---|---|---|
| `lake build Rowpartition` | 856 jobs, `Build completed successfully` | **859 jobs**, `Build completed successfully` |
| `lake env lean Audit.lean` | 3742 theorems, **0** non-standard axioms | **3804 theorems, 0** non-standard axioms |
| `lake build looptrace` | 1662 jobs | **1662 jobs**, `Build completed successfully` |

`#print axioms` over the new declarations:
`/home/dmitry/.claude/jobs/880c725d/tmp/S1/axioms.log` — **63 names censused, every one
`[propext, Classical.choice, Quot.sound]`, `non-standard axiom uses: 0`**.  The three modules
declare **77** top-level items; the 14 not in the census are pure data/notation defs
(`refSeed`, `refSu`, `refNs`, `refQ`, `refSu2`, `refS0`, `isSolvedB`, `isRejectedB`, the three
`instDecidable*` instances, and three `sys`-related names picked out of a doc comment) — every
THEOREM is covered, and `Audit.lean` covers all of them anyway (corrected, S1 review Z-11).
No `sorry` in any of the three modules (`grep -c sorry` = 0).

## Files changed

| file | lines | status |
|---|---|---|
| `tracker/lean/Rowpartition/Loop/Sound.lean` | 1,060 | NEW — (A), 27 theorems + 2 defs |
| `tracker/lean/Rowpartition/Loop/Reject.lean` | 633 | NEW — (B), 16 theorems + 1 def |
| `tracker/lean/Rowpartition/Loop/Solve.lean` | 215 | NEW — (C), 17 theorems + 11 defs/instances |
| `tracker/lean/Rowpartition.lean` | +23 | three imports and three doc bullets |
| `tracker/lean/README.md` | +23 | a `## SOUNDNESS of the loop (S1)` section |
| `tracker/repro/satterm/seeds/unsat/` | 6 seeds + README | NEW (post-review) — the compiler-reproduced witnesses |
| `tracker/lean/Rowpartition/Loop/{Step,Rules,State}.lean` | +13 / −9 | post-review, **DOC COMMENTS ONLY** (stale `Constraints.scala` / `Vars.scala` line numbers, Z-11e). `git diff -U0 \| grep '^[+-][^+-]'` shows nothing but comment lines |
| `tracker/ROW-CONSTRAINT-STATE.md` | +96 | a dated Soundness section |
| `tracker/LOOP-MODEL-PLAN.md` | +1 | the S1 status row, appended (the launch row untouched) |
| `tracker/loopmodel/S1-SOUNDNESS.md` | this file | NEW |

No Scala file was touched.

---

## S1.1 — `NoLoss` on the `concrete` branch (on SATISFIABLE input)

### What the branch deletes, and what licenses each deletion

`makeConcrete v fs incm proc` (`Loop/Step.lean:191`, `Constraints.scala:1610`) checks
`ensureSuperset r.conc fs` (`Constraints.scala:312` — it is `subsetOf`, CONTAINMENT, not
equality) at every definition `r` of `v` in either queue, emits `cancellation v ((|fs|)) r`
(`Constraints.scala:1677`) for each of them, calls `destructiveSub v ((|fs|))`
(`Constraints.scala:1632`) and records `v <- ((|fs|))` in `proc`.

**`destructiveSub` deletes nothing unless `srs` is non-empty** — `if ((srs isEmpty) && keep)
proc else procd filter p`, `Constraints.scala:1643-1644` = `Loop/Step.lean:175-177` — i.e.
unless something OTHER than `v`'s own definitions mentions `v`.  When it is non-empty, it
deletes every partition MENTIONING `v` (emitting its image under `v := ((|fs|))` in `srs`) and
every definition of `v` with FEWER THAN TWO abstract parts (`keepDefs`'s `defs` filter,
`Constraints.scala:1660-1662`, puts the rest back).  That guard is not a detail: it is exactly
what separates the review's `PANIC-1` (srs empty, nothing deleted, residual stays unsatisfiable,
`Subst.reduce` panics) from `MIN2` (srs non-empty, the row deleted, compiler accepts).

| deleted | what replaces it | entailed? |
|---|---|---|
| `a <- (S, K)` with `v ∈ S` | its image `a <- (S \ v, K ∪ fs)` in `srs`, and `v <- ((\|fs\|))` | YES — `sat_of_subst_image` |
| `v <- (a, (\|K\|))`, exactly ONE abstract part | `a <- ((\|fs \ K\|))` from `cancellation`, and `v <- ((\|fs\|))` | YES — `sat_of_cancel_image` |
| `v <- (S, (\|K\|))` with `\|S\| ≥ 2` | nothing: `keepDefs` puts it back | YES — it is still there |
| `v <- ((\|C\|))`, NO abstract part, `srs` non-empty | **NOTHING** | **only when `C = fs`** |
| anything, when `srs` IS empty | nothing is deleted at all | YES — vacuously |

The fourth row is the shipped compiler's behaviour, not an artifact of the model.
`ensureSuperset` permits `C ⊆ fs` (`Constraints.scala:312-321`); `cancellation`'s first branch
needs exactly one variable left over on the concrete-row side and its second needs exactly one
on the definition's side, and a bare row has none, so the fold emits nothing
(`Constraints.scala:1677-1697`; `StrictStep.cancellation_bare`, already in the library);
`keepDefs`'s `defs` filter keeps only definitions with two or more abstract parts
(`Constraints.scala:1660-1662`); and `C` is then recorded nowhere — `makeConcrete` never calls
`instantiateType` (`Constraints.scala:1245-1250` says so itself).

### Why it is not a `NoLoss` bug at a satisfiable state

```lean
theorem bare_refutes {G : System} {v : Var} {C F : Row}
    (h1 : mk v ∅ C ∈ G) (h2 : mk v ∅ F ∈ G) (hne : C ≠ F) : ¬ SSat G
```

so the proviso and its discharge:

```lean
/-- The `concrete` branch's proviso. -/
def BareAgree (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) → r.rhs.abstr.isEmpty = true →
    ∀ x ∈ rest.elems ++ s.proc.elems, x.lhs = r.lhs → x.rhs.abstr.isEmpty = true →
      cfs x.rhs.conc = cfs r.rhs.conc

theorem bareAgree_of_sat {s : State} (hsat : SSat (sys s)) : BareAgree s
```

### The statements, verbatim

```lean
theorem makeConcrete_noLoss {L : List Lbl} (hcoh : LblCoh L) {G' : System} {v : Nat}
    {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hiOk : QOk L incm) (hpOk : QOk L proc) (hfsOk : COk L fs)
    (hniG : ∀ x ∈ ni.elems, SEntails G' x.toConstraint)
    (hnpG : ∀ x ∈ np.elems, SEntails G' x.toConstraint)
    (hbare : ∀ x ∈ incm.elems ++ proc.elems, x.lhs = v → x.rhs.abstr.isEmpty = true →
      cfs x.rhs.conc = cfs fs)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    ∀ x ∈ incm.elems ++ proc.elems, SEntails G' x.toConstraint

theorem step_noLoss_concrete {s s' : State} (hw : Wf s) (hba : BareAgree s)
    {r : LPart} {rest : PQueue} (hdq : s.incm.dequeue = some (r, rest))
    (hfr : s.proc.findRHS r.rhs = none) (hem : r.rhs.isEmpty = false)
    (habs : r.rhs.abstr.isEmpty = true) (h : step s = .continue s') :
    NoLoss (sys s) (sys s')
```

and the five-branch theorem the brief asked for:

```lean
theorem step_noLoss_all {s s' : State} (hw : Wf s) (hba : BareAgree s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s')

theorem step_noLoss_sat {s s' : State} (hw : Wf s) (hsat : SSat (sys s))
    (h : step s = .continue s') : NoLoss (sys s) (sys s')

theorem step_noLoss_or {s s' : State} (hw : Wf s) (h : step s = .continue s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)
```

`step_noLoss_all` needs NO flag hypotheses and NO supply hypotheses — stronger than the brief
asked for on that axis.  The four non-`concrete` branches come from `StrictStep.step_noLoss`
(`Wf s` only) and the fifth from `step_noLoss_concrete` (`Wf s` plus the proviso).

### The supporting lemmas, and what they say about the Scala

* `subPartitions_mem` — **every mention of `v` in either queue leaves its image in `srs`**.
  This is the converse of `RefineConcrete.subPartitions_run` (which says everything derived is
  sound); nothing that should be derived is missing.
* `cancellation_singleton` — at a definition of `v` with exactly one abstract part,
  `cancellation v ((|fs|)) r` really does fire, and what it emits is `y <- ((|fs \ K|))`.
* `destructiveSub_noLoss` — everything in either queue either survives (possibly rewritten,
  possibly as an `equals`-equal copy the `Set` kept instead) or is a definition of `v` with
  fewer than two abstract parts.
* `makeConcrete_records` — the fact the branch writes, `v <- ((|fs|))`, is a consequence of the
  output; this is what carries the dequeued partition itself across the step.
* `val_mem_foldl_incl` / `val_mem_map` / `val_mem_concat` — `StrictStep`'s "a `Set` operation
  keeps every CONSTRAINT it was given" one type up, for `makeConcrete`'s `SSet RHS`.
* `foldl_concat_covers`, `ensureSuperset_fold_all` — the two fold shapes read backwards.

---

## S1.2 — output soundness along a run (on SATISFIABLE input)

```lean
theorem run_noLoss : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → NoLoss (sys s) (sys s')

theorem run_models {n : Nat} {s s' : State} (hw : Wf s) (hem : s.flags.emptyRow = false)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false) (hb : RunSupOk n s)
    (hsat : SSat (sys s)) (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    ∀ rho, SModels rho (sys s') → SModels rho (sys s)

theorem run_ssat_iff {n : Nat} {s s' : State} (hw : Wf s) (hem : s.flags.emptyRow = false)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false) (hb : RunSupOk n s)
    (hsat : SSat (sys s)) (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    SSat (sys s) ↔ SSat (sys s')

theorem run_noLoss_or {n : Nat} {s s' : State} (hw : Wf s) (hem : s.flags.emptyRow = false)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false) (hb : RunSupOk n s)
    (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)
```

**What the OUTPUT system is, and why the substitution is inside it.**  `sys s'` is the two
queues' partitions PLUS the environment read as constraints (`Loop/Refine.lean:285`, verbatim):

```lean
def EnvVal.toConstraint (v : Nat) : EnvVal → Constraint
  | .emptyRow => mk v ∅ (∅ : Row)
  | .alias u => mk v {u} (∅ : Row)

def Env.sys (e : Env) : System :=
  (e.binds.map (fun p => EnvVal.toConstraint p.1 p.2)).toFinset

def sys (s : State) : System := (s.parts.map LPart.toConstraint).toFinset ∪ s.env.sys
```

So `v := ConcreteRho(-, Set())` is the constraint `v <- ()`, `v := VarT(u)` is `v <- (u)`, and
`run_models` says: **every model of (residual partitions + the substitution the type checker is
about to apply) is a model of the input system.**  That is (A).

---

## S1.3 — rejection soundness, every death site

`step` can die with exactly seven messages.  (`rhsBuild`'s two errors and `labelClash` are
raised by `buildQueue` / `Subst.solve` AROUND the loop, not by `step`.)

| # | message | raised by | branch | verdict | theorem |
|---|---|---|---|---|---|
| 1 | `Fields appear twice in row: …` | `RHS.merge` (`Rules.lean:43`) | `concrete` (via `subPartitions`), `learn` (via `substitution`) | REFUTATION | `subPartitions_died_refutes`, `destructiveSub_died_refutes`, `substitution_died_refutes` → `merge_refutes` |
| 2 | `Infinite row partition for 'v'` | `selfSubstitution` (`Rules.lean:56`) | `learn` | REFUTATION | `learnPartitions_died` → `selfSubst_refutes` |
| 3 | `panic: reinstantiated type v to u but it was already bound` | `instantiate` (`Step.lean:89`) | `common`, `unify` | **UNREACHABLE** | `Hygiene.step_link_no_death`, used inside `step_died_refutes` |
| 4 | `Incompatible instantiations of 'v'` | `makeEmpty` (`Step.lean:132`) | `empty` | REFUTATION | `makeEmpty_died_hyg` → `incompatible_refutes` |
| 5 | `Cannot unify skolem variable with empty relation v` | `makeEmpty` (`Step.lean:136`) | `empty` | **NON-REFUTATION** | the whole of `NonRefutation` |
| 6 | `panic: reinstantiated type v to ConcreteRho(-,Set()) …` | `makeEmpty` (`Step.lean:138`) | `empty` | **UNREACHABLE** | `queueHygiene_binds_unbound`, used inside `makeEmpty_died_hyg` |
| 7 | `Row types failed to unify: R1 = … R2 = …` | `ensureSuperset` (`Step.lean:187`) | `concrete` | REFUTATION | `makeConcrete_died` → `ensureSuperset_refutes` |

### Notes on the table (added after the S1 review)

* **It is a census of `Death`s, not of crashes (Z-10).**  `Constraints.scala:463-464`'s
  `graph.sort(lhs)` is a `Map.apply` that would raise `NoSuchElementException`; the model
  totalises it (`Loop/Queue.lean:73`, `(g.prioOf? v).getD 0`) and the Scala invariant that it
  cannot fire (`Constraints.scala:407-425`) is argued in a comment, not proved.
  `Constraints.scala:648`'s `PQueue.build(v,t)` has a `die` in it and is dead code.
* **An EIGHTH `instantiateType` `die` site exists outside the loop (Z-5).**  `Subst.reduce`'s
  `instantiateType(v, ConcreteRho(lc, fs))` (`Subst.scala:1079`, dying at `:184`) is not in
  this census because it is not in `step` — but it is the LAST LINE OF DEFENCE for the very
  shape §S1.1 names as its hole, and it is a PANIC with no source location, not a diagnosable
  type error.  `tracker/repro/satterm/seeds/unsat/PANIC-1.json` reaches it at 3/3 id bases:
  `panic: reinstantiated type v1^301 to ConcreteRho(-,Set(l3, l4)) but it was already bound to
  ConcreteRho(-,Set(l3))`.  A user meeting that shape gets an internal error.
* **The two UNREACHABLE verdicts carry a side condition on the compiler (Z-6).**  Messages 3
  and 6 are unreachable because `QueueHygiene` holds, and `QueueHygiene` is FREE at an initial
  state only because the MODEL sets `env := {}` (`Loop/Seed.lean:135`,
  `queueHygiene_of_env_nil`).  In the compiler `SubstEnv.types` is a long-lived mutable map
  shared across the whole type checker (`Subst.scala:182-188`), and `Subst.solve` does NOT
  `substType` its input before `PQueue.build` (`Subst.scala:1135`; `substType` is applied only
  at `:1260`), so at the real entry to `incorporateAll` the environment is generally NOT empty
  and the input partitions may mention already-bound variables.  **"Messages 3 and 6 are
  unreachable" therefore transfers to the compiler only under the unproved side condition: no
  input partition mentions an already-bound variable.**  The Lean statement is about the model
  and is exact; this is what it costs to read it as a statement about the compiler.

### Why message 5 stays on the list

`Constraints.makeEmpty` refuses to bind a `Skolem` row variable to the empty row.  That is a
KINDING error and the compiler is right to reject; but `Rowpartition`'s constraint semantics
treats every row variable as flexible (`Assign := Var → Row`, no rigidity), so the SYSTEM the
loop dies on can perfectly well have a model, and the death is not a refutation OF IT.  It is
the only such message.

### The statements, verbatim

```lean
def NonRefutation (ns : Names) (m : String) : Prop :=
  ∃ v : Nat, ns.isSkolem v = true ∧
    m = "Cannot unify skolem variable with empty relation " ++ varStr ns v

theorem step_died_refutes {s s' : State} {m : String} (hw : Wf s) (hq : QueueHygiene s)
    (h : step s = .died m s') : ¬ SSat (sys s) ∨ NonRefutation s.names m

theorem run_rejects_unsat : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → QueueHygiene s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' →
      ¬ NonRefutation s.names m → ¬ SSat (sys s)

theorem run_rejects_unsat_noSkolem (n : Nat) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hq : QueueHygiene s)
    (hsk : ∀ v, s.names.isSkolem v = false)
    (m : String) (s' : State) (hres : run s n = .rejected m s') : ¬ SSat (sys s)
```

`NonRefutation` carries `ns.isSkolem v = true` rather than only the string, which is what makes
the exception list checkable at a concrete solve: a `json:` seed has an empty `svar` table, so
`isSkolem` is constantly `false` and the list is empty (`refNoSkolem`, `npNoSkolem`, both
`fun _ => rfl`).

`makeEmpty_died_hyg` is `Refine.makeEmpty_died` with the panic arm closed by
`env.contains v = false`.  Its fold-error case repeats `makeEmpty_died`'s argument rather than
citing it, because the disjunction `makeEmpty_died` returns cannot say WHICH arm produced the
message — the message alone does not distinguish a fold error from a panic without reasoning
about string inequality.  That duplication (≈35 lines) is deliberate and noted here so a
reviewer does not read it as an oversight.

---

## S1.4 — `solve_sound`, and two seeds

```lean
theorem solve_sound {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat} (n : Nat)
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z))) :
    (∀ s', (run (initState q su' tr fl ns site z) n = .solved s' ∨
        run (initState q su' tr fl ns site z) n = .outOfFuel s') →
        SSat (sys (initState q su' tr fl ns site z)) →
        NoLoss (sys (initState q su' tr fl ns site z)) (sys s') ∧
        (∀ rho, SModels rho (sys s') → SModels rho (sys (initState q su' tr fl ns site z))) ∧
        SSat (sys s')) ∧
    (∀ (m : String) (s' : State),
        run (initState q su' tr fl ns site z) n = .rejected m s' →
        ¬ NonRefutation ns m → ¬ SSat (sys (initState q su' tr fl ns site z)))
```

`EnvNodup` and `QueueHygiene` are free at an initial state (`env := {}`), `RunSupOk` is
discharged by `Supply.runSupOk_of` from `SupOk su'` and `SupFresh su'`, and `SupFresh` itself
is made `decide`-able by

```lean
theorem supFresh_initState {q : PQueue} {su : Sup} {fl : Flags} {ns : Names} {site : String}
    {tr : List String} {z : Nat}
    (h : ∀ p ∈ q.elems, ¬ Sup.Reach su p.lhs ∧ ∀ w ∈ p.rhs.abstr.elems, ¬ Sup.Reach su w) :
    SupFresh su (sys (initState q su tr fl ns site z))
```

`Wf` is a hypothesis (as it is in `VocFix.vocFixed_terminates_of_buildQueue`), discharged at
each seed by `wf_of_nodup (by decide) (by decide) (by decide)`.

### The two instantiations

Both at a COMPILER-shaped supply — `Sup.ofSeed`'s `blk = 0` fails `SupOk`, so `lo` is the
seed's own `supplyLo` at id base 300 and `blk = hi`, exactly as `Loop/Depth.lean` §9 does.

| seed | constraints | supply | model verdict | Lean |
|---|---|---|---|---|
| `seeds/NP01.json` (`np01_add_or_recompute.e(134:15)`) | 12 | `{lo := 311, hi := 1311, blk := 1311, bsz := 1024}` | SOLVED, 98 dequeues, drawn 18 | `npWf`, `npSupOk`, `npSupFresh`, `npS0_solved`, **`npS0_sound`** |
| `seeds/REF.json` (`v0 <- (v1,v2)`, `v1 <- ((\|l1\|))`, `v2 <- ((\|l1\|))`) | 3 | `{lo := 303, hi := 1303, blk := 1303, bsz := 1024}` | REJECTED at the THIRD dequeue (`concrete`, `common`, then `learn` dies), `Fields appear twice in row: Set(Repro.l1)` | `refWf`, `refSupOk`, `refSupFresh`, `refS0_rejected`, **`refS0_refutes`** |

```lean
theorem npS0_sound :
    (∀ s', (run npS0 200 = .solved s' ∨ run npS0 200 = .outOfFuel s') → SSat (sys npS0) →
        NoLoss (sys npS0) (sys s') ∧
        (∀ rho, SModels rho (sys s') → SModels rho (sys npS0)) ∧ SSat (sys s')) ∧
    (∀ (m : String) (s' : State), run npS0 200 = .rejected m s' →
        ¬ NonRefutation npNs m → ¬ SSat (sys npS0))

theorem refS0_refutes : ∀ (m : String) (s' : State), run refS0 200 = .rejected m s' →
    ¬ SSat (sys refS0)
```

`refS0_refutes` has no exception hypothesis at all: it goes through
`solve_sound_rejects` with `refNoSkolem`.

**`npS0_sound` is CONDITIONAL and its antecedent is not discharged (S1 review Z-8).**  Its
first conjunct reads `… → SSat (sys npS0) → …`, and nothing in Lean proves `SSat (sys npS0)`,
so the flagship accepted-seed instantiation states nothing unconditional about NP01.  The
antecedent is true — the review's oracle exhibits the model
`{0:{l0..l5}, 1:∅, 2:{l3}, 3:{l4,l5}, 4:∅, 5:{l0..l6}, 6:{l6}, 7:{l3}, 8:{l0,l1,l2,l4,l5},
9:{l6}, 10:{l0,l1,l2,l4,l5}}`, identical variable for variable to the substitution the compiler
prints — and turning it into `theorem npS0_sat : SSat (sys npS0)` would make `npS0_sound`
unconditional.  That is a small, high-value addition and is left to S2; the brief's
"no silent weakening" rule is why it is stated here rather than glossed.

### The compiler agrees on the same two seeds

`tracker/repro/satterm/run.sh sweep json:<seed> 300 300`, with
`ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2"`:

| seed | flags | compiler | model (`looptrace`) |
|---|---|---|---|
| `NP01.json` | shipped | `SOLVED in 349 ms … drawn=18` | `cycle SOLVED steps=98 drawn=18` |
| `REF.json` | shipped | `REJECTED … Row partitions are unsatisfiable at field 'l1': two parts of one partition both contain it` | `# REJECTED Row partitions are unsatisfiable at field 'Repro.l1': …` |
| `REF.json` | `-Dermine.labelCheck=false` | `REJECTED … Fields appear twice in row: Set(l1)` | `--flags=nolabel`: `# REJECTED Fields appear twice in row: Set(Repro.l1)` |

The Lean theorem is about the LOOP, which starts at `initState` — i.e. after `labelCheckEarly`
has already run and passed.  At the shipped flags `labelClash` rejects `REF` first, with a
different message and the same verdict; with `labelCheck=false` the loop is the one that
rejects, and the two messages agree up to the model's label rendering: the compiler says
`Fields appear twice in row: Set(l1)` and the model `… Set(Repro.l1)`, because `Lbl.toStr`
prefixes the module (`Loop/State.lean:53`).  Death-site 1, `learn` branch, `substitution` →
`RHS.merge`.  (The original "character for character" was wrong and is withdrawn — S1 review
Z-9.  The model also truncates both panic messages, which end `… but it was already bound to
<t>` in the Scala (`Subst.scala:184`) and at `already bound` in the Lean, and drops `V.toString`'s
`"S"` suffix for a skolem (`Vars.scala:110-112`).  None of it touches soundness: `NonRefutation`
carries `isSkolem v = true`, not just the string.)

### What `Subst.solve` ACTUALLY publishes, and which theorem covers what

**Corrected (S1 review Z-7): `solve` does not return `sys s'`.**  It returns
`Exists(l, [], reduce(l, cs map substType, es, ps))` (`Subst.scala:1260`): the published
constraint list is built from the ORIGINAL input `cs` under the substitution the loop wrote,
and the loop's residual `ps` is used only to `instantiateType` bare-concrete partitions
(`Subst.scala:1079`) and to splice ambiguous/existential ones (`:1080-1121`); everything else
in `ps` is DROPPED (`case (_, cs) => cs`).

| artefact | modelled as | covered by |
|---|---|---|
| the substitution the loop wrote (`SubstEnv.types`) | part of `sys s'`, via `EnvVal.toConstraint` | `run_noLoss`, `run_models` |
| the residual partitions `ps` the loop leaves | part of `sys s'` | `run_noLoss`, `run_models` |
| what `reduce` then MAKES of `cs` and `ps`, and publishes | NOT modelled | **nothing here** — the `Subst.reduce` scope limit below |
| a rejection message | `run … = .rejected m s'` | `run_rejects_unsat` |

`run_models` licenses APPLYING the substitution — every model of `sys s'` is a model of
`sys s₀`.  It says nothing about what `reduce` publishes, and in particular nothing about a
residual `cs`-constraint that `reduce` neither refutes nor drops.  That gap is exactly where
`MIN1`'s false acceptance lives: the published third residual is `{l22} <- ({l35}, v4)`, false
for every `v4`, and nothing downstream looks at it.

### The three stated scope limits

* **`Subst.reduce`** — runs AFTER the loop over the saturated set, and is not modelled at all
  (L2 "Known scope limits").  `Rowpartition.Splice` studies its second case in the RELATIONAL
  setting and exhibits a residual strictly WEAKER than the input;
  `Rowpartition.SpliceGuard` gives the repair's licence.  Nothing in S1 says anything about it.
  **It is not inert, and declaring it out of scope has a price (Z-5):** it is the last defence
  for §S1.1's hole, it publishes what the type checker actually consumes (Z-7 above), and it
  drops every residual partition it cannot `instantiateType` or splice
  (`Subst.scala:1122`, `case (_, cs) => cs`) — which is how `MIN1`'s violated residual reaches
  the caller unchecked.
* **`labelClash` / `labelCheckEarly`** — runs BEFORE the loop, over the INPUT partitions only
  (`Subst.scala:1187`, and `Subst.scala:1259` at the other flag setting; both read
  `q.toList`, never `q.expand`, so it never sees a derived constraint).  Its soundness is
  `Rowpartition.LabelAlgo`'s own theorem — every bit the fixpoint writes is `Forced`, so every
  clash it reports is genuine — and is CITED here, not re-proved.  It is SOUNDNESS, not
  COMPLETENESS: the check is unit propagation, so an unsatisfiability needing a case split
  walks past it, and 0.1 % of random unsatisfiable systems (and a much larger fraction of
  deliberately built ones) do exactly that.  That is the door `MIN1` and `MIN2` come through.
* **`Loc` / blame** — which source position a death is reported at is outside the model.

---

## Is the bare-row deletion reachable?  **YES** (answered by the S1 review, 2026-09-05)

### The answer

`tracker/repro/satterm/seeds/unsat/MIN2.json` — five constraints,

```
v2 <- (v3, v0)     v3 <- (v0, v1)     v2 <- (v1, (|l17|))
v2 <- ((|l17,l38|))                   v5 <- (v2, v8)
```

is UNSATISFIABLE at `l17`, PASSES `labelCheckEarly`, and the loop at the SHIPPED flags reaches
the hole at step 9: `v2` and `v3` have been folded into `v1` by `common`/`unify`, so `v1`
carries BOTH the input's bare row `((|l17,l38|))` and the `cancellation`-derived
`v1 <- ((|l38|))`; `makeConcrete v1 {l17,l38}` finds `ensureSuperset {l38} {l17,l38}`
satisfied, `srs` is NON-empty (`v5 <- (v2,v8)` mentions the variable), `keepDefs`'s `defs`
filter drops the bare row, `cancellation` emits nothing for it, and `{l38}` is gone.  The
SHIPPED COMPILER then returns

```
SOLVED  v0 := ConcreteRho(-,Set()); v1 := ConcreteRho(-,Set(l17, l38));
        v2 := ConcreteRho(-,Set(l17, l38)); v3 := ConcreteRho(-,Set(l17, l38));
        v5 := unbound; v8 := unbound
```

at 4 of the 20 bases 300–319 (300, 303, 307, 315 — re-run here from the copied seed), and that
substitution makes the input constraint `v2 <- (v1, (|l17|))` read
`{l17,l38} = {l17,l38} ⊎ {l17}`: `l17` in two parts of one whole.

**Neither defence the original submission relied on holds.**  `ensureSuperset` is
`subsetOf` — CONTAINMENT, `Constraints.scala:312` — so it waves through exactly the `C ⊊ fs`
the deletion then loses; and `labelCheckEarly` is unit propagation over the INPUT
(`Subst.scala:1187`, reading `q.toList`), so any unsatisfiability that needs a CASE SPLIT — as
`MIN1` and `MIN2` both do — walks past it.  The original claim that the loop's derivation of a
bare row is followed label by label by `labelClash` is true of the DERIVATION and false of the
REFUTATION, which is the half that matters.

`ensureSuperset` does still refuse at the OTHER dequeue order, which is why the acceptance is
order-dependent (4/20 bases): which of the two bare rows is dequeued first is `rhs.hashCode`.

### The original probes, kept for the record

Two hand seeds, in `/home/dmitry/.claude/jobs/880c725d/tmp/S1/seeds/`, run through
`looptrace` at the shipped flags and at `--flags=nolabel`:

| seed | shape | shipped flags | `--flags=nolabel` (the loop alone) |
|---|---|---|---|
| `BARE1` | `v <- ((\|l1\|))`, `v <- ((\|l1,l2\|))` — both bare rows in the INPUT | REJECTED by `labelClash` at `l2` | REJECTED by the LOOP: `Row types failed to unify: R1 = Set(l1,l2) R2 = Set(l1)` |
| `BARE2` | two rows `v <- ((\|l2\|))` / `v <- ((\|l2,l4\|))` DERIVED by `cancellation` from `a <- (v,(\|l1\|))`, `a <- ((\|l1,l2\|))`, `b <- (v,(\|l3\|))`, `b <- ((\|l2,l3,l4\|))` | REJECTED by `labelClash` at `l4` | REJECTED by the LOOP: `Row types failed to unify: R1 = Set(l2,l3,l4) R2 = Set(l3,l2)` |

Both were caught, and the original submission concluded from that that the two defences hold in
general.  **That conclusion was wrong** — see the answer above.  Two hand seeds are not a hunt;
the review's ~9 M-system hunt with an UNSAT + label-check-passing pre-filter is, and it found
the hole's SHAPE in 26.7 % of 11,048 runs and the DELETION firing in 1.6 %.

---

## Side by side: everything weaker than the brief asked for

| brief | delivered | why |
|---|---|---|
| `step_noLoss_all : Wf s → (shipped flags) → SupOk/SupFresh → step s = .continue s' → NoLoss (sys s) (sys s')` | `step_noLoss_all : Wf s → BareAgree s → step s = .continue s' → NoLoss (sys s) (sys s')`; unconditionally `step_noLoss_or : Wf s → step s = .continue s' → NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)` | the unconditional form is FALSE: `makeConcrete` deletes a bare concrete `v <- ((\|C\|))` with `C ⊊ fs` and emits nothing. The flags and supply hypotheses turned out NOT to be needed, so the delivered statement is stronger on that axis and weaker on this one |
| `run_noLoss : … → NoLoss (sys s) (sys s')` | `run_noLoss` with `SSat (sys s)` added; `run_noLoss_or` without it | the same one shape, carried along the run |
| `SSat (sys s) ↔ SSat (sys s')` | `run_ssat_iff` under `SSat (sys s)` | the `←` direction needs `NoLoss`, which needs the proviso. Unconditionally only `→` holds (`run_sat_all`); `←` is exactly what the bare-row deletion can break |
| `run_rejects_unsat : … → m ∉ NonRefutation → ¬ SSat (sys s₀)` | delivered as asked, plus `run_rejects_unsat_noSkolem` with no exception at all | — |
| `solve_sound` with every hypothesis discharged from the input | `Wf` is still a hypothesis (discharged by `decide` at each seed) | `buildQueue` is not known to produce `Nodup` partitions; `VocFix.vocFixed_terminates_of_buildQueue` carries `Wf` the same way. Discharging it in general is a small separate lemma about `partToPartitions`, not attempted |

## What I could not prove, stated plainly

1. **The unconditional `NoLoss` at the `concrete` branch.**  It is false.  What is true is
   `NoLoss ∨ ¬ SSat`, and the one shape responsible is named above.
2. **~~Whether the shipped compiler can be made to ACCEPT an ill-typed program through that
   hole.~~  ANSWERED BY THE REVIEW: YES.**  The original text said "not settled either way",
   offered route (a) "a seed in which the larger bare row is dequeued first AND the rest of the
   system stays satisfiable AND the per-label propagation on the INPUT misses it" and route (b)
   "a theorem that `labelClash` refutes every input on which the loop reaches the shape", and
   guessed (b) looked approachable.  Both are settled: **(a) is `MIN2`, found; (b) is FALSE**,
   with `MIN2` step 9 as the counter-state — reachable at the shipped flags from a
   `labelCheckEarly`-passing `buildQueue` input, `Wf` and `QueueHygiene` both holding
   (`step_wf`, `step_queueHygiene`), `¬ BareAgree s` with `C = {l38} ≠ fs`, `srs` non-empty.
   The guess behind (b) was the mistake: `labelClash` follows the DERIVATION of a bare row
   label by label, but REFUTING the resulting disagreement needs a case split, which unit
   propagation never makes.
3. **`SSat (sys npS0)`** — not proved, so `npS0_sound` is conditional (Z-8 above).  A witness
   exists; producing it in Lean is an S2 item.
4. **`Wf` from `buildQueue`** — see the table above.
5. **Everything about `Subst.reduce`** — out of scope by construction, and the review shows the
   price of that: it is where `MIN1`'s violated residual is published and where the hole's
   panic defence lives (§S1.4 notes, Z-5/Z-7).
6. **Refutation COMPLETENESS of the loop.**  Never claimed and never tested by S1, and FALSE:
   `MIN1` is a five-constraint unsatisfiable system the loop saturates without refuting.  That
   is the property "an accepted program is well-typed" actually needs, and it is what S2 is
   about.

## Where this goes next: stage S2 (the fix)

The orchestrator is opening a fix stage.  Three items, in the order their soundness is already
available in this repository:

1. **`makeConcrete` refuses `C ⊊ fs` at a BARE definition** instead of merely
   `ensureSuperset`-ing it.  At a bare `v <- ((|C|))` and a concrete instantiation
   `v := ((|fs|))`, `C = fs` is FORCED, so
   `if (concr.isEmpty || abs.nonEmpty) ensureSuperset(...) else require(concr == fs)` is sound —
   it is `bare_refutes`, already proved in `Loop/Sound.lean` — and it converts `MIN2` into
   death-site 7, which `Loop/Reject.lean` has already shown is a refutation.  This closes the
   hole itself rather than papering over it.
2. **`checkLabels` on the SATURATED set `ps`, not only on the input queue `q`.**  Sound by
   `Rowpartition.refute_saturated_sound` (`tracker/lean/Rowpartition/Saturate.lean`) — the
   compiler's own comment at `Subst.scala:1247-1258` already says so, and records that the
   check was removed again because it measured "ZERO additional refutations" on both corpora.
   That is a fact about the corpora, not about the algorithm: it catches ALL SIX
   compiler-confirmed witnesses (`MIN1` at `l35`, `MIN2` at `l17`, and the four others) and
   **1,146 of the 1,166** model false acceptances.
3. **A COMPLETE per-label decision — unit propagation PLUS a case split.**  Ten seeds (20 runs)
   survive (2), all of them real compiler acceptances rather than panics;
   `tracker/repro/satterm/seeds/unsat/SURV1.json` is one, verified `SOLVED` on the shipped
   compiler at bases 300 and 301 with an eight-partition unsatisfiable residual on which unit
   propagation still finds nothing.  Refuting those needs a case split, which no propagation
   makes.  `Rowpartition.Basic`'s `satisfiable_iff_forall_label` is the licence for deciding
   the problem label by label; the realistic target is "refute everything a bounded search
   refutes".

The theorem that would close the programme is the one the review names: **the loop's `.done`
state, plus the `reduce` that follows it, refutes every unsatisfiable input.**  It is FALSE as
the code stands (`MIN1`), and becomes approachable after (2), because `labelClash` on the
saturated set is `LabelAlgo`'s fixpoint on a system in which every bare row is a unit —
precisely the fragment where unit propagation IS complete.

---

## Post-review corrections (2026-09-06)

Applied after `tracker/loopmodel/S1-REVIEW.md` (verdict FIX-THEN-ADVANCE, "nothing in the
Lean").  **No theorem, proof or statement changed**; the Lean edits are doc comments only, and
the build and audit figures are unchanged.  Sentence by sentence:

| # | old | new |
|---|---|---|
| Z-3a | "**OUTCOME: P-** … with the deficit on (A), not on (B)" | "**OUTCOME: (BUG)**", with `MIN1`/`MIN2` quoted and the violated label named |
| Z-3b | "**NOT escalated to BUG.**  A BUG in the brief's sense needs a compiler-reproduced seed … neither probe got through." | deleted; replaced by the two witnesses and the hunt's numbers (1,166 false acceptances / 665 seeds / 10 compiler-confirmed) |
| Z-3c | "So there are **TWO defences and both held**" (§Probes) | "**Neither defence holds.**  `ensureSuperset` is `subsetOf`, CONTAINMENT (`Constraints.scala:312`); `labelCheckEarly` is unit propagation over the INPUT and any unsatisfiability needing a case split walks past it" |
| Z-3d | "no input on which the shipped compiler ACCEPTS through this hole was found" (state file) | "`MIN2.json`: SOLVED at 4/20 bases, substitution violates the input at `l17`" |
| Z-3e | "(b) looks approachable" (What I could not prove, item 2) | "(b) is FALSE, and `MIN2` step 9 is the counter-state" |
| Z-4 | "`destructiveSub` … DELETES every partition that mentions `v` …"; README "`makeConcrete` deletes `v <- ((\|C\|))` for every `C ⊆ fs`" | the deletion is GATED on `srs` being non-empty (`Constraints.scala:1643-1644`, `Loop/Step.lean:175-177`); when `srs` is empty nothing is deleted, which is what separates `PANIC-1` from `MIN2`. A fifth table row was added |
| Z-5 | "`Subst.reduce` … Nothing in S1 says anything about it." | kept, plus: it is the LAST DEFENCE for this very hole, its defence is a PANIC (`Subst.scala:1079 → :184`, `PANIC-1.json` at 3/3 bases), and it is an eighth message site outside the census |
| Z-6 | "`QueueHygiene` … free at an initial state (`env := {}`)" with no caveat | plus the side condition for the compiler: `SubstEnv.types` is long-lived (`Subst.scala:182-188`) and `solve` does not `substType` its input (`:1135`), so "3 and 6 unreachable" transfers only under "no input partition mentions an already-bound variable" |
| Z-7 | "What the type checker consumes … the residual partitions / the substitution environment / covered by `run_noLoss`" | `solve` returns `Exists(l, [], reduce(l, cs map substType, es, ps))` (`Subst.scala:1260`), NOT `sys s'`; a four-row table now separates what the theorems cover from what `reduce` publishes, which nothing here covers |
| Z-8 | `npS0_sound` presented without comment | stated as CONDITIONAL on the undischarged `SSat (sys npS0)`, with the review's witness model recorded and `npS0_sat` named as an S2 item |
| Z-9 | "the compiler's message is the model's message **character for character**" | withdrawn: the model prints `Set(Repro.l1)` against the compiler's `Set(l1)`; both panics are truncated and the skolem `"S"` suffix is dropped |
| Z-11a | "all **63** new declarations" | 63 censused of **77** top-level items, the other 14 being pure data/notation defs |
| Z-11b | `Sound.lean` "27 theorems + **5** defs"; `Rowpartition.lean` **+27**; `README.md` **+19** | 27 + **2**; **+23**; **+23** |
| Z-11c | "`Loop/Step.lean:190`" | `Loop/Step.lean:191` (190 is the doc comment), and `Constraints.scala` citations added throughout §S1.1 |
| Z-11d | §Probes "BARE2 … the same two rows" as BARE1 | BARE2's rows are `((\|l2\|))` / `((\|l2,l4\|))`, not BARE1's |
| Z-11e | stale Scala line numbers inside the Lean doc comments (`Loop/Step.lean:4-6`, `:109`; `Loop/Rules.lean:3-6`, `:25`; `Loop/State.lean:208`, `:272`) | re-checked against `Constraints.scala` / `Vars.scala` and corrected (`subPartitions` 1588→1598, `makeConcrete` 1600→1610, `destructiveSub` 1622→1632, skolem 1577→1587, `cancellation` 1667→1677, `resolution` 1758→1768, `subBody`/`substitution` 1807/1821→1817/1831, `commonSubexpression` 1834→1844, `disjunction` 1867→1877, `V.toString` 111→110, `Partition.equals` 1064-1071→1062-1067) |
| — | headings "S1.1 `NoLoss` on the `concrete` branch", "S1.2 output soundness along a run" | now carry "(on SATISFIABLE input)" |

Files added: `tracker/repro/satterm/seeds/unsat/{MIN1,MIN2,FALSE-ACCEPT-1,FALSE-ACCEPT-2,PANIC-1,SURV1}.json`
plus a `README.md`, each seed's `name` field saying what it witnesses.  They are in a
SUBDIRECTORY on purpose: `TestLoopTrace` enumerates `seeds/*.json` non-recursively, and these
are gate material for S2, not conformance seeds.

**What did NOT change, and why.**  No Lean statement, proof or hypothesis.  The only edits to
pre-existing modules are the stale-line-number fixes in `Loop/{Step,Rules,State}.lean`, which
are doc comments; the review's "no pre-existing module touched" check therefore now reads
"three touched, comments only", and `git diff -U0 -- tracker/lean/Rowpartition/Loop/{Step,Rules,State}.lean`
verifies it.  Build 859 jobs and audit 3,804 / 0 are unchanged after them.  Every S1 theorem
survives every witness in the review: on all 1,166 model false acceptances the OUTPUT system
was itself unsatisfiable, so `NoLoss (sys s) (sys s')` holds vacuously and `run_noLoss` is
never violated.  The theorems are right; they are not the property the type checker needs.

---

## How a reviewer re-runs everything

```bash
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition            # 859 jobs
lake env lean Audit.lean           # 3804 theorems, 0 non-standard axioms
lake build looptrace               # 1662 jobs
grep -c sorry Rowpartition/Loop/{Sound,Reject,Solve}.lean    # 0 0 0
./.lake/build/bin/looptrace ../repro/satterm/seeds/NP01.json 300 2000 --cycle
./.lake/build/bin/looptrace ../repro/satterm/seeds/REF.json  300 2000 --flags=nolabel | head -1
```

and, for the compiler side (one JVM at a time):

```bash
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:tracker/repro/satterm/seeds/NP01.json 300 300
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.labelCheck=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:tracker/repro/satterm/seeds/REF.json 300 300
```

and, for the two BUGS (both re-run here from the copied seeds, one JVM at a time):

```bash
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:tracker/repro/satterm/seeds/unsat/MIN1.json 300 302
  # SUMMARY n=3 SOLVED=3 REJECTED=0 — residual Part(ConcreteRho(Set(l22)), List(ConcreteRho(Set(l35)), v4))
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:tracker/repro/satterm/seeds/unsat/MIN2.json 300 319
  # SUMMARY n=20 SOLVED=4 REJECTED=16 — SOLVED at bases 300, 303, 307, 315
```
