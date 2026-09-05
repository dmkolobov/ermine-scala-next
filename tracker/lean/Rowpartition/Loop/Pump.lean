/-
# L5 round 5 (R5.1): the PUMP, instrumented

The round-4 review's T-9 names the one shape a divergence of `incorporateAll` would have to
have.  `splitConcrete`'s last branch mints a fresh `u` for the KEY `(v, K)` -- the dequeued
left-hand side and the concrete part of the dequeued right-hand side -- and emits, besides
the definition `u <- (A)` of the mint, the CARRIER `v <- (u, K)`, which is exactly what the
branch's own guard (`findResolvent`) looks for.  So a second mint at the same key is possible
only once that carrier is gone; and the cheapest way for it to go is to eliminate `u`, which
costs nothing, because `u` did not exist before the mint.  Each turn of

    mint a fresh `u` at `(v, K)`  ->  eliminate `u`  ->  the key is open again

spends one binding and produces one variable, so nothing external is consumed.  That is the
pump, and R5.1's question is whether it runs more than twice.

This module supplies the instrument.  `splitMintKey` is the minting decision made
OBSERVABLE: it re-runs `learnPartitions`' own call to `splitConcrete`, with the same
lookups, at the state's own dequeue, and reports the key when the supply advanced.  Because
`splitConcrete` draws an id in its last branch and only there (`Draws.splitConcrete_drawn`,
and `splitConcrete_mint_eq` below), "the supply advanced" IS "the mint branch was taken", so
the instrument is the rule itself rather than a re-implementation of it.

`pumpRun` then runs the loop with a per-key tally and reports the MAXIMUM number of mints at
any one key, which is the number R5.1 pushes.  `Loop/Main.lean`'s `--mints` prints it, so the
hunt runs on the compiled executable rather than under `#eval`.
-/
import Rowpartition.Loop.Mints

set_option maxRecDepth 100000
set_option maxHeartbeats 2000000

namespace Rowpartition.Loop

/-! ## 1. The minting decision, made observable -/

/-- **What `splitConcrete` emits when it mints.**  Its last branch is the only one that
draws, so either the supply is untouched or the whole result is pinned: the definition of the
fresh id and the CARRIER of the key the branch fired on. -/
theorem splitConcrete_cases {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2 = su ∨
    splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su
      = (SSet.ofList
           [⟨(su.fresh).1, RHS.ofAbstr abstr, some .splitConcrete⟩,
            ⟨v, ⟨SSet.ofList [(su.fresh).1], concr⟩, some .splitConcrete⟩],
         (su.fresh).2) := by
  unfold splitConcrete
  repeat' split
  all_goals first
    | exact Or.inl rfl
    | (right; rename_i hf; rw [hf])

/-- **The mint's emission, from the supply alone.**  A `splitConcrete` call whose supply
advanced took the mint branch, and the set it returned is the pair `u <- (A)`,
`v <- (u, K)`: the mint installs the CARRIER of its own key. -/
theorem splitConcrete_mint_eq {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (h : (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2.drawn
          ≠ su.drawn) :
    splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su
      = (SSet.ofList
           [⟨(su.fresh).1, RHS.ofAbstr abstr, some .splitConcrete⟩,
            ⟨v, ⟨SSet.ofList [(su.fresh).1], concr⟩, some .splitConcrete⟩],
         (su.fresh).2) := by
  rcases splitConcrete_cases (fl := fl) (v := v) (abstr := abstr) (concr := concr)
      (rhss := rhss) (resolvent := resolvent) (concRow := concRow) (emptyRow := emptyRow)
      (su := su) with hc | hc
  · exact absurd (by rw [hc]) h
  · exact hc

/-- `splitConcrete` as `learnPartitions` calls it: the same lookups, over the queue MINUS the
dequeued premise (`rest`) and the processed queue, with the current batch still empty. -/
def splitAt (s : State) (r : LPart) (rest : PQueue) : SSet LPart × Sup :=
  let l := mkLookups r.lhs rest s.proc
  splitConcrete s.flags r.lhs r.rhs.abstr r.rhs.conc
    (fun rr => findRHS3 rest s.proc SSet.empty rr)
    (fun k => findResolvent r.lhs l SSet.empty k)
    (fun k => if s.flags.splitRow || s.flags.resRow then findConcRow l k else none)
    (fun k => if s.flags.emptyRow then findEmptyRow s.env l k else none)
    s.su

/-- **The key this state mints at**, if it mints at all: `step`'s dispatch down to the
`learn` branch, `learnPartitions`' own guard on self-substitution, then `splitConcrete`'s
supply.  The key is `(dequeued left-hand side, concrete part)`. -/
def splitMintKey (s : State) : Option (Nat × SSet Lbl) :=
  match s.incm.dequeue with
  | none => none
  | some (r, rest) =>
    match s.proc.findRHS r.rhs with
    | some _ => none
    | none =>
      if r.rhs.isEmpty then none
      else if r.rhs.abstr.isEmpty then none
      else match r.rhs.single? with
        | some _ => none
        | none =>
          if r.rhs.abstr.contains r.lhs then none
          else if (splitAt s r rest).2.drawn == s.su.drawn then none
          else some (r.lhs, r.rhs.conc)

/-- The key is the dequeued partition's own left-hand side and concrete part. -/
theorem splitMintKey_key {s : State} {r : LPart} {rest : PQueue} {v : Nat} {K : SSet Lbl}
    (hq : s.incm.dequeue = some (r, rest)) (h : splitMintKey s = some (v, K)) :
    v = r.lhs ∧ K = r.rhs.conc := by
  unfold splitMintKey at h
  rw [hq] at h
  simp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · simp at h
      · split at h
        · simp at h
        · split at h
          · simp at h
          · split at h
            · simp at h
            · simp only [Option.some.injEq, Prod.mk.injEq] at h
              exact ⟨h.1.symm, h.2.symm⟩

/-! ## 2. The per-key tally -/

/-- A key: the left-hand variable and the concrete part the guard is keyed on. -/
abbrev MKey := Nat × SSet Lbl

/-- Key equality, as the guard sees it (`SSet.eqv` on the label set). -/
def mkeyEq (a b : MKey) : Bool := a.1 == b.1 && a.2.eqv b.2

/-- Bump a key's counter in an association list. -/
def bumpKey (t : List (MKey × Nat)) (k : MKey) : List (MKey × Nat) :=
  if t.any (fun p => mkeyEq p.1 k) then
    t.map (fun p => if mkeyEq p.1 k then (p.1, p.2 + 1) else p)
  else t ++ [(k, 1)]

/-- Every variable the state mentions: the two queues' partitions and the environment. -/
def stateVars (s : State) : SSet Nat :=
  let fromParts := s.parts.foldl (fun acc p => (acc.incl p.lhs).concat p.rhs.abstr) SSet.empty
  s.env.binds.foldl (fun acc b =>
    match b.2 with
    | .emptyRow => acc.incl b.1
    | .alias u => (acc.incl b.1).incl u) fromParts

/-- **The carrier keys one step installs.**  A partition of the state AFTER the step whose
left-hand side is the DEQUEUED variable and whose right-hand side is a LONE variable that did
not exist before the step is a fresh carrier: `splitConcrete`'s mint contributes
`v <- (u, K)` at its own guard key, and `resolution`'s contributes `v <- (z, C₁ ∪ C₂)` at
its guard key `resolvent (C₁ ∪ C₂)`.  This is the round-4 hunt's detector
(`tmp/L5r4/hunt/Hunt.lean`), which is why the two rounds' hit lists are comparable. -/
def carrierKeys (s s' : State) : List MKey :=
  match s.incm.dequeue with
  | none => []
  | some (r, _) =>
    let old := stateVars s
    (s'.parts.filterMap (fun p =>
      if p.lhs == r.lhs then
        match p.rhs.abstrSingle? with
        | some z => if old.contains z then none else some (p.lhs, p.rhs.conc)
        | none => none
      else none)).foldl (fun acc k => if acc.any (fun a => mkeyEq a k) then acc else acc ++ [k]) []

/-- The carriers of the key `(v, K)` a state holds: the lone abstract variable of every
partition `v <- (w, K)`.  This is what `splitConcrete`'s and `resolution`'s shared guard
(`findResolvent`, through `mkLookups.resolvents`) looks up, read off the state rather than
off the two queues separately. -/
def carriersOf (s : State) (v : Nat) (K : SSet Lbl) : List Nat :=
  s.parts.filterMap (fun p =>
    if p.lhs == v && p.rhs.conc.eqv K then p.rhs.abstrSingle? else none)

/-- The variables an environment has bound. -/
def boundVars_of (e : Env) : List Nat := e.binds.map (·.1)

/-- The variables the state's environment has bound -- the loop's ELIMINATIONS. -/
def boundVars (s : State) : List Nat := boundVars_of s.env

/-- What one instrumented solve reports. -/
structure PumpRep where
  /-- Dequeues taken. -/
  steps : Nat := 0
  /-- `splitConcrete` mints, by guard key. -/
  tally : List (MKey × Nat) := []
  /-- Fresh CARRIERS installed at the dequeued left-hand side, by key -- `splitConcrete`'s
  and `resolution`'s together. -/
  ctally : List (MKey × Nat) := []
  /-- Ids drawn from the supply (`splitConcrete` and `resolution` together). -/
  drawn : Nat := 0
  /-- `SOLVED`, `REJECTED` or `FUEL`. -/
  verdict : String := "SOLVED"
  /-- `(step index, lhs, key)` of every `splitConcrete` mint, in order. -/
  mints : List (Nat × Nat × List Nat) := []
  /-- `(step index, lhs, key)` of every fresh carrier installed at the dequeued left-hand
  side, in order. -/
  carriers : List (Nat × Nat × List Nat) := []
  /-- `(step index, lhs, key, the key's carriers in the state AFTER the step)` -- the charge
  audit's left-hand side (R5.2). -/
  carrAt : List (Nat × Nat × List Nat × List Nat) := []
  /-- `(step index, variable)` of every ELIMINATION: a variable the step bound. -/
  binds : List (Nat × Nat) := []

/-- The largest number of `splitConcrete` mints at any one guard key. -/
def PumpRep.maxAtKey (r : PumpRep) : Nat := r.tally.foldl (fun a p => max a p.2) 0

/-- The largest number of fresh carriers installed at any one key. -/
def PumpRep.maxAtCKey (r : PumpRep) : Nat := r.ctally.foldl (fun a p => max a p.2) 0

/-- The number of distinct keys minted at more than once. -/
def PumpRep.remintKeys (r : PumpRep) : Nat := (r.tally.filter (fun p => p.2 ≥ 2)).length

/-- The number of distinct keys re-carried. -/
def PumpRep.remintCKeys (r : PumpRep) : Nat := (r.ctally.filter (fun p => p.2 ≥ 2)).length

/-- Run the loop with the tally.  The fuel is the same bound `run` uses. -/
def pumpRun : Nat → State → PumpRep → PumpRep
  | 0, s, rep => { rep with verdict := "FUEL", drawn := s.su.drawn }
  | n + 1, s, rep =>
    let rep :=
      match splitMintKey s with
      | none => rep
      | some k =>
        { rep with tally := bumpKey rep.tally k,
                   mints := rep.mints ++ [(rep.steps, k.1, k.2.toList.map Lbl.n)] }
    match step s with
    | .done s' => { rep with verdict := "SOLVED", drawn := s'.su.drawn }
    | .died _ s' => { rep with verdict := "REJECTED", drawn := s'.su.drawn }
    | .continue s' =>
      let ck := carrierKeys s s'
      let nb := (boundVars s').filter (fun w => !(boundVars s).contains w)
      let rep := { rep with ctally := ck.foldl bumpKey rep.ctally,
                            carriers := rep.carriers ++
                              ck.map (fun (k : MKey) => (rep.steps, k.1, k.2.toList.map Lbl.n)),
                            carrAt := rep.carrAt ++
                              ck.map (fun (k : MKey) =>
                                (rep.steps, k.1, k.2.toList.map Lbl.n, carriersOf s' k.1 k.2)),
                            binds := rep.binds ++ nb.map (fun w => (rep.steps, w)) }
      pumpRun n s' { rep with steps := rep.steps + 1 }


/-! ## 3. The pump, as a witness

`tmp/L5r5/hunt/min2.json` at id base 2 — six constraints, satisfiable by construction (the
generator fixes a valuation first and every constraint is a disjoint decomposition over it),
which the compiler solves.  The loop mints TWICE at the key `(v2, {l1,l2,l4,l5})`, and what
happens in between is the pump, in four lines of its own trace:

```
learn  ^free2 <- (^free6,Repro.l1 Repro.l5)
new    Resolution:   ^free2 <- (^ambiguous(free)8,Repro.l1 Repro.l5 Repro.l2 Repro.l4)   -- the MINT, and its carrier
new    Cancellation: ^ambiguous(free)8 <- (,)                                            -- against the bare row already present
empty  Cancellation: ^ambiguous(free)8 <- (,)                                            -- makeEmpty withdraws the carrier
learn  ^free2 <- (^free7,Repro.l2 Repro.l4)
new    Resolution:   ^free2 <- (^ambiguous(free)11,Repro.l2 Repro.l4 Repro.l1 Repro.l5)  -- MINTS AGAIN, same key
```

The turn is FREE: the variable whose elimination re-opens the key is `^ambiguous(free)8`,
the id the mint itself drew, and the fact that empties it is `cancellation` against the bare
concrete row `v2 <- ((|l1,l2,l4,l5|))` that the input already contains. -/

/-- The reduced witness, as the repro harness's seed. -/
def pSeed : Seed :=
  { name := "pump",
    cons := [⟨11, [], [1, 5]⟩, ⟨0, [5], [2, 4]⟩, ⟨0, [1], [1, 2, 4, 5]⟩,
             ⟨0, [1, 7], [1, 5]⟩, ⟨4, [], [2, 4]⟩, ⟨0, [7], [1, 5]⟩],
    rhoKeys := [0, 1, 4, 5, 7, 11] }

/-- Its display names and supply, at id base 2. -/
def pNs : Names := (seedSystem pSeed 2).2

/-- The initial state `Subst.solve` builds from it — through `buildQueue`, so the queue's
order is the compiler's. -/
def pS0 : State :=
  match buildQueue (seedSystem pSeed 2).1 (Sup.ofSeed pNs.supplyLo) with
  | .error _ =>
    { incm := PQueue.empty, proc := PQueue.empty, env := {}, su := Sup.ofSeed 0,
      trace := [], flags := {}, names := pNs, site := "pump", su0 := 0 }
  | .ok (q, su1) =>
    { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := {},
      names := pNs, site := "pump", su0 := (Sup.ofSeed pNs.supplyLo).lo }

/-- The error branch is not taken: the queue holds the six input partitions. -/
theorem pS0_size : pS0.incm.elems.length = 6 := rfl

/-- The supply starts after the six input variables. -/
theorem pS0_supply : pS0.su.lo = 8 := rfl

/-- The state after `n` dequeues. -/
def pAt : Nat → State
  | 0 => pS0
  | n + 1 => match step (pAt n) with
             | .continue s => s
             | .done s => s
             | .died _ s => s

/-- The key both mints fire at: `v2`'s whole row. -/
def pKey : SSet Lbl := SSet.ofList [Lbl.repro 1, Lbl.repro 5, Lbl.repro 2, Lbl.repro 4]

theorem pStep0 : step (pAt 0) = .continue (pAt 1) := rfl
theorem pStep1 : step (pAt 1) = .continue (pAt 2) := rfl
theorem pStep2 : step (pAt 2) = .continue (pAt 3) := rfl
theorem pStep3 : step (pAt 3) = .continue (pAt 4) := rfl
theorem pStep4 : step (pAt 4) = .continue (pAt 5) := rfl
theorem pStep5 : step (pAt 5) = .continue (pAt 6) := rfl
theorem pStep6 : step (pAt 6) = .continue (pAt 7) := rfl
theorem pStep7 : step (pAt 7) = .continue (pAt 8) := rfl
theorem pStep8 : step (pAt 8) = .continue (pAt 9) := rfl
theorem pStep9 : step (pAt 9) = .continue (pAt 10) := rfl
theorem pStep10 : step (pAt 10) = .continue (pAt 11) := rfl
theorem pStep11 : step (pAt 11) = .continue (pAt 12) := rfl
theorem pStep12 : step (pAt 12) = .continue (pAt 13) := rfl

theorem pReach5 : Reaches pS0 (pAt 5) :=
  ((((Reaches.refl pS0).tail pStep0).tail pStep1).tail pStep2).tail pStep3 |>.tail pStep4

theorem pReach6_12 : Reaches (pAt 6) (pAt 12) :=
  (((((Reaches.refl (pAt 6)).tail pStep6).tail pStep7).tail pStep8).tail pStep9).tail pStep10
    |>.tail pStep11

/-- **The first mint**: the step out of `pAt 5` installs a fresh carrier at `(v2, pKey)`.
(The label set is compared with `mkeyEq`, the guard's own `SSet.eqv`, because the two mints
build the key's `Set` in different insertion orders.) -/
theorem pCarrier5 :
    (carrierKeys (pAt 5) (pAt 6)).any (fun k => mkeyEq k (2, pKey)) = true := rfl

/-- **The second mint, at the SAME key.** -/
theorem pCarrier12 :
    (carrierKeys (pAt 12) (pAt 13)).any (fun k => mkeyEq k (2, pKey)) = true := rfl

/-- The key's only carrier after the first mint is the id the mint drew. -/
theorem pCarriersOf : carriersOf (pAt 6) 2 pKey = [8] := rfl

/-- ...and that id is NOT in the input's vocabulary: the loop minted it. -/
theorem pFresh : (stateVars pS0).contains 8 = false := rfl

/-- It is unbound at the first mint... -/
theorem pBound6 : boundVars (pAt 6) = [3] := rfl

/-- ...and bound by the time of the second: `makeEmpty` withdrew the carrier. -/
theorem pBound12 : boundVars (pAt 12) = [3, 8, 5] := rfl

/-- The run SOLVES: the pump is not a divergence, it is a satisfiable input's own history. -/
theorem pSolved : Finished (run pS0 40) := trivial

/-! ## 4. The charging lemma (R5.2), stated so that it can be refuted -/

/-- **A minting step at a key.**  The step installs a fresh carrier of `(v, K)` at the
dequeued left-hand side — `splitConcrete`'s `v <- (u, K)` or `resolution`'s
`v <- (z, C₁ ∪ C₂)`, both of them at the key their own guard is keyed on. -/
def MintsAt (s s' : State) (v : Nat) (K : SSet Lbl) : Prop :=
  ∃ k ∈ carrierKeys s s', mkeyEq k (v, K) = true

instance (s s' : State) (v : Nat) (K : SSet Lbl) : Decidable (MintsAt s s' v K) :=
  inferInstanceAs (Decidable (∃ _ ∈ _, _))

/-- **The charging lemma, clause I** (`L5-REVIEW.md` T-9): between two minting steps at the
SAME key `(v, K)` the loop ELIMINATES a variable that carried the key at the first mint. -/
def ChargeI : Prop :=
  ∀ (s s' t t' : State) (v : Nat) (K : SSet Lbl),
    step s = .continue s' → MintsAt s s' v K →
    Reaches s' t → step t = .continue t' → MintsAt t t' v K →
    ∃ w ∈ carriersOf s' v K, w ∉ boundVars s' ∧ w ∈ boundVars t

/-- **Clause II** — the clause that would make the charge INPUT-SIZED, and the only one that
would close the count: the variable charged is one the loop did NOT mint, i.e. one the run
started with. -/
def ChargeII : Prop :=
  ∀ (s0 s s' t t' : State) (v : Nat) (K : SSet Lbl),
    Reaches s0 s → step s = .continue s' → MintsAt s s' v K →
    Reaches s' t → step t = .continue t' → MintsAt t t' v K →
    ∃ w ∈ carriersOf s' v K,
      (stateVars s0).contains w = true ∧ w ∉ boundVars s' ∧ w ∈ boundVars t

theorem pMint5 : MintsAt (pAt 5) (pAt 6) 2 pKey := List.any_eq_true.mp pCarrier5

theorem pMint12 : MintsAt (pAt 12) (pAt 13) 2 pKey := List.any_eq_true.mp pCarrier12

/-- **CLAUSE II IS FALSE — the pump runs.**  The witness re-mints at `(v2, pKey)` and the
only variable that carried the key at the first mint is `8`, the id THAT MINT DREW.  So the
elimination the re-mint is charged to is one the loop paid for itself, and no charge of this
shape is bounded by the input. -/
theorem chargeII_false : ¬ ChargeII := by
  intro h
  obtain ⟨w, hw, hin, -, -⟩ :=
    h pS0 (pAt 5) (pAt 6) (pAt 12) (pAt 13) 2 pKey pReach5 pStep5 pMint5 pReach6_12 pStep12
      pMint12
  rw [pCarriersOf, List.mem_singleton] at hw
  subst hw
  rw [pFresh] at hin
  exact Bool.noConfusion hin

/-! ## 4b. Clause I is false too, and for a cheaper reason

`tmp/L5r5/hunt/minC1.json` at id base 3 — eight constraints, satisfiable, solved.  The loop
mints twice at the key `(v4, {l0,l1,l2,l3,l4})`, four dequeues apart, and between the two it
binds NOTHING: the carrier the first mint installed is withdrawn by `makeConcrete`, whose
`destructiveSub` deletes every partition mentioning the concretised variable and writes no
`SubstEnv` entry at all.

```
learn      ^free4 <- (^free9,Repro.l1 Repro.l2 Repro.l3 Repro.l4)
new        Resolution:   ^free4 <- (^ambiguous(free)10,Repro.l3 l0 l2 l1 l4)  -- the MINT and its carrier
new        Cancellation: ^ambiguous(free)10 <- (,Repro.l6)                    -- a bare row for the mint
concrete   Cancellation: ^ambiguous(free)10 <- (,Repro.l6)                    -- makeConcrete DELETES the carrier
learn      ^free4 <- (^free7,Repro.l1 Repro.l2 Repro.l4)
new        Resolution:   ^free4 <- (^ambiguous(free)11,Repro.l3 l0 l2 l1 l4)  -- MINTS AGAIN, same key
```

So a turn of the pump need not spend a binding either. -/

/-- The eight-constraint witness. -/
def cSeed : Seed :=
  { name := "charge",
    cons := [⟨9, [], [1, 2, 6]⟩, ⟨3, [], [2, 3, 4]⟩, ⟨1, [11], [1, 2, 3, 4]⟩,
             ⟨1, [8], [1, 2, 4]⟩, ⟨0, [3], [0, 1, 6]⟩, ⟨7, [], [1, 2, 6]⟩,
             ⟨1, [3], [0, 1, 6]⟩, ⟨1, [9], [0, 3, 4]⟩],
    rhoKeys := [0, 1, 3, 7, 8, 9, 11] }

def cNs : Names := (seedSystem cSeed 3).2

def cS0 : State :=
  match buildQueue (seedSystem cSeed 3).1 (Sup.ofSeed cNs.supplyLo) with
  | .error _ =>
    { incm := PQueue.empty, proc := PQueue.empty, env := {}, su := Sup.ofSeed 0,
      trace := [], flags := {}, names := cNs, site := "charge", su0 := 0 }
  | .ok (q, su1) =>
    { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := {},
      names := cNs, site := "charge", su0 := (Sup.ofSeed cNs.supplyLo).lo }

theorem cS0_size : cS0.incm.elems.length = 8 := rfl

def cAt : Nat → State
  | 0 => cS0
  | n + 1 => match step (cAt n) with
             | .continue s => s
             | .done s => s
             | .died _ s => s

/-- The key both mints fire at. -/
def cKey : SSet Lbl :=
  SSet.ofList [Lbl.repro 0, Lbl.repro 1, Lbl.repro 2, Lbl.repro 3, Lbl.repro 4]

theorem cStep4 : step (cAt 4) = .continue (cAt 5) := rfl
theorem cStep5 : step (cAt 5) = .continue (cAt 6) := rfl
theorem cStep6 : step (cAt 6) = .continue (cAt 7) := rfl
theorem cStep7 : step (cAt 7) = .continue (cAt 8) := rfl
theorem cStep8 : step (cAt 8) = .continue (cAt 9) := rfl

theorem cReach5_8 : Reaches (cAt 5) (cAt 8) :=
  ((Reaches.refl (cAt 5)).tail cStep5).tail cStep6 |>.tail cStep7

theorem cCarrier4 :
    (carrierKeys (cAt 4) (cAt 5)).any (fun k => mkeyEq k (4, cKey)) = true := rfl

theorem cCarrier8 :
    (carrierKeys (cAt 8) (cAt 9)).any (fun k => mkeyEq k (4, cKey)) = true := rfl

/-- The key's only carrier after the first mint is the id the mint drew. -/
theorem cCarriersOf : carriersOf (cAt 5) 4 cKey = [10] := rfl

/-- And between the two mints the loop binds NOTHING. -/
theorem cBound5 : boundVars (cAt 5) = [8] := rfl
theorem cBound8 : boundVars (cAt 8) = [8] := rfl

theorem cMint4 : MintsAt (cAt 4) (cAt 5) 4 cKey := List.any_eq_true.mp cCarrier4
theorem cMint8 : MintsAt (cAt 8) (cAt 9) 4 cKey := List.any_eq_true.mp cCarrier8

/-- **CLAUSE I IS FALSE.**  Two mints at one key with no elimination at all in between:
`makeConcrete`'s `destructiveSub` withdrew the carrier and wrote nothing to the
`SubstEnv`.  So there is nothing for the charge to be charged to, and the count cannot be
recovered by counting eliminations, however they are charged. -/
theorem chargeI_false : ¬ ChargeI := by
  intro h
  obtain ⟨w, hw, -, hb⟩ :=
    h (cAt 4) (cAt 5) (cAt 8) (cAt 9) 4 cKey cStep4 cMint4 cReach5_8 cStep8 cMint8
  rw [cCarriersOf, List.mem_singleton] at hw
  subst hw
  rw [cBound8] at hb
  simp at hb

/-! ## 5. What clause II would have bought, and the ingredient that survives -/

/-- The loop's bindings only GROW: `instantiateType` rewrites the values of the existing
bindings and appends the new one, so no key ever leaves the environment. -/
theorem env_instantiate_boundVars (e : Env) (v : Nat) (val : EnvVal) :
    boundVars_of (e.instantiate v val) = boundVars_of e ++ [v] := by
  simp [boundVars_of, Env.instantiate]

end Rowpartition.Loop
