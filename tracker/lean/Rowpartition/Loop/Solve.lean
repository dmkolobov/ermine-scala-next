/-
# S1 (C): `solve_sound` — (A) and (B) packaged from `buildQueue` / `initState`

`Subst.solve` builds the queue (`PQueue.build`, modelled as `buildQueue`), runs the early
per-label refutation, starts the loop at `initState q su' …` and hands `q.expand` to
`Subst.reduce`.  This file packages the two halves of S1 for that initial state, with every
hypothesis discharged from the input, and instantiates it on two tracked seeds.

WHAT `Subst.solve` ACTUALLY PUBLISHES, and which theorem covers what (corrected after the S1
review, Z-7).  `solve` returns `Exists(l, [], reduce(l, cs map substType, es, ps))`
(`Subst.scala:1260`) — NOT `sys s'`.  The published constraint list is built from the ORIGINAL
input `cs` under the substitution the loop wrote, and the loop's residual `ps` is used only to
`instantiateType` bare-concrete partitions (`Subst.scala:1079`) and to splice ambiguous ones
(`:1080-1121`); everything else in `ps` is DROPPED (`case (_, cs) => cs`).

| artefact | modelled as | covered by |
|---|---|---|
| the substitution the loop wrote (`SubstEnv.types`) | part of `sys s'`, via `EnvVal.toConstraint` | `run_noLoss`, `run_models` |
| the residual partitions `ps` the loop leaves | part of `sys s'` | `run_noLoss`, `run_models` |
| what `reduce` then MAKES of `cs` and `ps` | not modelled | NOTHING here — see the scope limit below |
| a rejection message | `run … = .rejected m s'` | `run_rejects_unsat` |

`run_models` says every model of `sys s'` is a model of `sys s₀`, which is the licence for
applying the substitution; it says nothing about what `reduce` publishes, and in particular
nothing about a residual `cs`-constraint that `reduce` neither refutes nor drops.  That gap is
where the review's `MIN1` false acceptance lives.

THREE STATED SCOPE LIMITS, none of them proved here:

* `Subst.reduce` — runs AFTER the loop, over the saturated set, and is not modelled at all
  (L2 "Known scope limits").  `Rowpartition.Splice` studies its second case in the RELATIONAL
  setting and exhibits a residual WEAKER than the input; `Rowpartition.SpliceGuard` gives the
  repair's licence.  Nothing here says anything about it.  It is NOT inert, though: it is the
  last line of defence for `Loop/Sound.lean`'s bare-row hole, and the defence is a PANIC
  (`Subst.scala:1079 → :184`; `seeds/unsat/PANIC-1.json`, S1 review Z-5).
* `labelClash` / `labelCheckEarly` — runs BEFORE the loop, over the INPUT partitions only
  (`Subst.scala:1187`, and `:1259` at the other flag setting; both read `q.toList`, never
  `q.expand`).  Its SOUNDNESS is `Rowpartition.LabelAlgo`'s own theorem (every bit the fixpoint
  writes is `Forced`, so every clash it reports is genuine); it is not re-proved here, and
  `solve_sound` is about the loop that runs after it.  It is NOT complete: it is unit
  propagation, so any unsatisfiability needing a case split walks past it — which is how
  `seeds/unsat/MIN1.json` and `MIN2.json` reach the loop at all (S1 review Z-3).
* `Loc` / blame — which source position a death is reported at is outside the model entirely.
-/
import Rowpartition.Loop.Reject
import Rowpartition.Loop.Depth

namespace Rowpartition.Loop

open Rowpartition

set_option linter.unusedSimpArgs false

/-! ## 1. `SupFresh` at an initial state, as a decidable check on the queue -/

/-- At an initial state the environment is empty, so the vocabulary is exactly the queue's:
`SupFresh` reduces to a check on the partitions, which is `decide`-able. -/
theorem supFresh_initState {q : PQueue} {su : Sup} {fl : Flags} {ns : Names} {site : String}
    {tr : List String} {z : Nat}
    (h : ∀ p ∈ q.elems, ¬ Sup.Reach su p.lhs ∧ ∀ w ∈ p.rhs.abstr.elems, ¬ Sup.Reach su w) :
    SupFresh su (sys (initState q su tr fl ns site z)) := by
  intro w hw hmem
  obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hmem
  rcases mem_sys.mp hc with ⟨p, hp, rfl⟩ | ⟨b, hb, -⟩
  · have hpq : p ∈ q.elems := by
      simpa [initState, State.parts, PQueue.empty] using hp
    obtain ⟨h1, h2⟩ := h p hpq
    rw [toConstraint_eq] at hwc
    rcases Finset.mem_insert.mp hwc with hwc' | hwc'
    · rw [lhs_mk] at hwc'; exact h1 (hwc' ▸ hw)
    · rw [vset_mk] at hwc'
      exact h2 w (SSet.mem_fs.mp hwc') hw
  · exact absurd hb (by simp [initState])

/-! ## 2. `solve_sound` -/

/-- **THE PACKAGED THEOREM.**  For a solve that starts at `initState` on the queue
`buildQueue` built, under the three shipped flags and the supply invariant:

* (A) if the loop finishes or runs out of fuel on a SATISFIABLE input, the output system —
  the residual partitions PLUS the substitution environment — entails every input constraint,
  every model of it is a model of the input, and it is still satisfiable;
* (B) if the loop rejects with a message that is not the skolem refusal, the input system has
  no model at all.

`Wf`, `EnvNodup` and `QueueHygiene` are free at an initial state (`env = {}`, `proc` empty);
`RunSupOk` is discharged from the seed's own `SupOk`/`SupFresh` by `Supply.runSupOk_of`. -/
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
        ¬ NonRefutation ns m → ¬ SSat (sys (initState q su' tr fl ns site z))) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  have hrun : RunSupOk n (initState (PQueue.ofList ps) su' tr fl ns site z) :=
    runSupOk_of hdj hcse hok hfr n
  have hyg : QueueHygiene (initState (PQueue.ofList ps) su' tr fl ns site z) :=
    queueHygiene_of_env_nil rfl
  refine ⟨fun s' hres hsat => ⟨run_noLoss n hw hem hdj hcse hrun hsat s' hres, ?_, ?_⟩,
    fun m s' hres hnr => run_rejects_unsat n hw hem hdj hcse hrun hyg m s' hres hnr⟩
  · exact run_models hw hem hdj hcse hrun hsat hres
  · exact run_sat_all n hw hem hdj hcse hrun hsat s' hres

/-- ... and with no exception list, on a solve whose variables carry no skolem. -/
theorem solve_sound_rejects {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat} (n : Nat)
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z)))
    (hsk : ∀ v, ns.isSkolem v = false)
    (m : String) (s' : State)
    (hres : run (initState q su' tr fl ns site z) n = .rejected m s') :
    ¬ SSat (sys (initState q su' tr fl ns site z)) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  exact run_rejects_unsat_noSkolem n hw hem hdj hcse (runSupOk_of hdj hcse hok hfr n)
    (queueHygiene_of_env_nil rfl) hsk m s' hres

/-! ## 3. Two tracked seeds

`tracker/repro/satterm/seeds/NP01.json` (accepted) and `.../REF.json` (rejected).  Both are
run at a COMPILER-shaped supply — `Sup.ofSeed`'s `blk = 0` fails `SupOk`, so `lo` is the
seed's own `supplyLo` at id base 300 and `blk = hi`, exactly as `Loop/Depth.lean` §9 does for
`npSeed`.  `npSeed` / `npSu` / `npS0` are reused from there. -/

section Seeds
set_option maxRecDepth 8000

/-! `SSet.Nodup`, `Sup.Reach` and `LblCoh` are plain `Prop`-valued definitions; these three
instances are what lets `decide` see through them at a concrete seed. -/

instance instDecidableSSetNodup {α : Type} [SVal α] [DecidableEq α] (s : SSet α) :
    Decidable s.Nodup := decidable_of_iff s.elems.Nodup Iff.rfl

instance instDecidableReach (su : Sup) (z : Nat) : Decidable (Sup.Reach su z) :=
  decidable_of_iff ((su.lo ≤ z ∧ z < su.hi) ∨ su.blk ≤ z) Iff.rfl

instance instDecidableLblCoh (L : List Lbl) : Decidable (LblCoh L) :=
  decidable_of_iff (∀ x ∈ L, ∀ y ∈ L, x.n = y.n → x = y) Iff.rfl

/-- `REF.json`: `v0 <- (v1, v2)` with `v1 <- ((|l1|))` and `v2 <- ((|l1|))` — two parts of one
partition both carrying the same label.  UNSATISFIABLE, and the loop dies on it. -/
def refSeed : Seed :=
  { name := "REF", cons := [⟨0, [1, 2], []⟩, ⟨1, [], [1]⟩, ⟨2, [], [1]⟩], rhoKeys := [0, 1, 2] }

def refSu : Sup := { lo := 303, hi := 1303, blk := 1303, bsz := 1024 }

def refNs : Names := (seedSystem refSeed 300).2

def refQ : PQueue :=
  match buildQueue (seedSystem refSeed 300).1 refSu with
  | .ok (q, _) => q
  | .error _ => PQueue.empty

def refSu2 : Sup :=
  match buildQueue (seedSystem refSeed 300).1 refSu with
  | .ok (_, su) => su
  | .error _ => refSu

theorem refBuild : buildQueue (seedSystem refSeed 300).1 refSu = .ok (refQ, refSu2) := by rfl

def refS0 : State := initState refQ refSu2 [] {} refNs "REF" 303

/-- Three input partitions, one per seed constraint. -/
theorem refS0_size : refS0.incm.elems.length = 3 := by rfl

theorem refWf : Wf refS0 := wf_of_nodup (by decide) (by decide) (by decide)

theorem refSupOk : SupOk refSu2 := ⟨by decide, by decide, by decide⟩

theorem refSupFresh : SupFresh refSu2 (sys refS0) := supFresh_initState (by decide)

/-- A seed carries no `svar` table, so no variable is a skolem. -/
theorem refNoSkolem : ∀ v, refNs.isSkolem v = false := fun _ => rfl

theorem npWf : Wf npS0 := wf_of_nodup (by decide) (by decide) (by decide)

theorem npSupOk : SupOk npSu2 := ⟨by decide, by decide, by decide⟩

theorem npSupFresh : SupFresh npSu2 (sys npS0) := supFresh_initState (by decide)

theorem npNoSkolem : ∀ v, npNs.isSkolem v = false := fun _ => rfl

/-- The verdict of a run, as the harness reports it. -/
def isSolvedB : RunResult → Bool
  | .solved _ => true
  | _ => false

def isRejectedB : RunResult → Bool
  | .rejected _ _ => true
  | _ => false

set_option maxHeartbeats 2000000 in
-- the `rfl` re-runs NP01's 98 dequeues in the KERNEL; `REF`'s three do not need this
/-- **`NP01` is ACCEPTED by the model** — and by the compiler (`looptrace --cycle`:
`SOLVED steps=98`). -/
theorem npS0_solved : isSolvedB (run npS0 200) = true := by rfl

/-- **`REF` is REJECTED by the model** — and by the compiler. -/
theorem refS0_rejected : isRejectedB (run refS0 200) = true := by rfl

/-- **S1 instantiated at `NP01`**: the accepted solve loses nothing. -/
theorem npS0_sound :
    (∀ s', (run npS0 200 = .solved s' ∨ run npS0 200 = .outOfFuel s') → SSat (sys npS0) →
        NoLoss (sys npS0) (sys s') ∧
        (∀ rho, SModels rho (sys s') → SModels rho (sys npS0)) ∧ SSat (sys s')) ∧
    (∀ (m : String) (s' : State), run npS0 200 = .rejected m s' →
        ¬ NonRefutation npNs m → ¬ SSat (sys npS0)) :=
  solve_sound 200 npBuild rfl rfl rfl npWf npSupOk npSupFresh

/-- **S1 instantiated at `REF`**: the rejection is a refutation — the seed's system has no
model, which is what the seed's own comment says (`l1` in two parts of one whole). -/
theorem refS0_refutes : ∀ (m : String) (s' : State), run refS0 200 = .rejected m s' →
    ¬ SSat (sys refS0) :=
  fun m s' hres =>
    solve_sound_rejects 200 refBuild rfl rfl rfl refWf refSupOk refSupFresh refNoSkolem m s' hres

end Seeds

end Rowpartition.Loop
