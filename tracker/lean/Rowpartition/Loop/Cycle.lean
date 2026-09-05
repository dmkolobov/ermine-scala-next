/-
# L5 round 6 (R6.1): a STATE CYCLE, up to renaming of the minted ids

The round-5 review's V-13 names this as the decisive cheap experiment: a divergence of a
DETERMINISTIC loop can have only one shape, and that shape is a repeated state.  So instead
of hunting for a bigger `cmax` (round 5: 9; the reviewer: 10, and never plateauing), hunt for
a repeat.

Two halves, and they are not the same statement.

* §1-2 **the theorem.**  `SEq` is equality of everything `step` reads and writes -- the two
  queues, the environment, the supply, the flags and the name table -- and NOT the trace, the
  site or `su0`, which only decorate the records.  `step_congr` proves `step` is a function of
  that much (so the trace really is inert), `run_seq` lifts it to `run`, and
  `not_terminates_of_cycle` turns any run that returns to an `SEq`-equal state into
  `¬ Terminates`, in the two lines the review promised.  This is EXACT: no renaming.
* §3-4 **the instrument.**  `canonState` renders a state with every MINTED id (`id ≥ su0`)
  replaced by its index in the state's own first-occurrence traversal, so two states that
  differ only by a renaming of the ids the loop drew render the same string.  `cycleRun`
  hashes that string at every dequeue and reports the first repeat, and `rawState` does the
  same without the renaming (and with the supply) so that a hit closer to the theorem's `SEq`
  is reported separately.  `Loop/Main.lean`'s `--cycle` prints both -- on the `json:` seed path
  only; `replayMain` has no `--cycle`, so a corpus segment has to be transcoded into a seed
  first (round-6 review W-6g).

**What the quotient is and is not.**  Renaming minted ids is NOT a congruence for this loop:
`V.hashCode` IS the id, the queue is ordered by `(rhs.hashCode, lhs.hashCode)` and the
priority is a reverse-topological index computed from the hash-ordered node set, so a
permutation of the ids can change which partition is dequeued next.  A canonical repeat is
therefore a CANDIDATE that has to be replayed -- and so, for a different reason, is an exact
one: `rawState` omits the queue GRAPHS, `Sup.blk`/`bsz`, `flags` and `names`, all of which
`SEq` demands, so neither detector's hit is a proof by itself.  The negative direction is what
the search is for, and it is sound: an `SEq` repeat would force a `rawState` repeat would force
a canonical repeat, so no canonical repeat means no cycle.

**Why the supply must be quotiented away.**  `Sup.fresh` increments `drawn` and `lo` on both
of its arms, so ANY run that draws an id has a strictly increasing supply and can never
repeat a state exactly.  An exact cycle is possible only in a draw-free run; the divergence
this stage is hunting mints without bound, so the renaming quotient is not a convenience but
the only quotient under which the search can succeed at all.  `canonState` therefore drops
the supply and renames the mints; `rawState` keeps both.
-/
import Rowpartition.Loop.Fragment

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. `SEq`: everything `step` reads -/

/-- **The operative core of a state.**  `step` reads the two queues, the environment, the
supply, the flags and the name table, and writes the first four; `trace`, `site` and `su0`
are carried for the records and never inspected by a rule. -/
def SEq (s t : State) : Prop :=
  s.incm = t.incm ∧ s.proc = t.proc ∧ s.env = t.env ∧ s.su = t.su ∧
    s.flags = t.flags ∧ s.names = t.names

theorem SEq.refl (s : State) : SEq s s := ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem SEq.symm {s t : State} (h : SEq s t) : SEq t s :=
  ⟨h.1.symm, h.2.1.symm, h.2.2.1.symm, h.2.2.2.1.symm, h.2.2.2.2.1.symm, h.2.2.2.2.2.symm⟩

theorem SEq.trans {s t u : State} (h : SEq s t) (h' : SEq t u) : SEq s u :=
  ⟨h.1.trans h'.1, h.2.1.trans h'.2.1, h.2.2.1.trans h'.2.2.1,
   h.2.2.2.1.trans h'.2.2.2.1, h.2.2.2.2.1.trans h'.2.2.2.2.1,
   h.2.2.2.2.2.trans h'.2.2.2.2.2⟩

/-- Two `SEq` states differ only in the three decorative fields. -/
theorem seq_eta {s t : State} (h : SEq s t) :
    t = { s with trace := t.trace, site := t.site, su0 := t.su0 } := by
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := h
  cases s; cases t
  simp_all

/-- The `learn` branch's record fold touches the TRACE and nothing else.  `RefineLearn.lean`
has the `env` and `flags` projections of this; the general form is what `SEq` needs. -/
theorem foldl_log_state (f : State → LPart → String) :
    ∀ (l : List LPart) (st : State),
      ∃ tr, (l.foldl (fun a p => ({ a with trace := f a p :: a.trace } : State)) st)
              = { st with trace := tr }
  | [], st => ⟨st.trace, by cases st; rfl⟩
  | p :: l, st => by
    obtain ⟨tr, h⟩ := foldl_log_state f l { st with trace := f st p :: st.trace }
    refine ⟨tr, ?_⟩
    simp only [List.foldl_cons]
    rw [h]

/-- **`step` is a function of the core.**  Changing only `trace`, `site` and `su0` changes
only `trace`, `site` and `su0` of the answer: the branch taken, the queues, the environment
and the supply are the same.  The `died` and `done` cases follow from this one, because a
state whose decorations are changed back is the original state (`decor_decor`). -/
theorem step_decor (s : State) (tr : List String) (si : String) (z : Nat) :
    ∀ s', step s = .continue s' →
      ∃ t', step { s with trace := tr, site := si, su0 := z } = .continue t' ∧ SEq s' t' := by
  simp only [step, State.log]
  cases hd : s.incm.dequeue with
  | none => intro s' h; exact absurd h (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    dsimp only
    split
    · -- common
      rename_i u _
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => intro s' h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        intro s' h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
    · split
      · -- empty
        cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => intro s' h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          intro s' h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
      · split
        · -- concrete
          cases hu : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => intro s' h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            intro s' h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
        · split
          · -- unify
            rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => intro s' h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              intro s' h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
          · -- learn
            cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => intro s' h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              intro s' h
              dsimp only at h ⊢
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              obtain ⟨tr2, hf2⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ si ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: tr, site := si, su0 := z }
              rw [hf1] at h
              rw [hf2]
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- Re-decorating a re-decorated state is the original. -/
theorem decor_decor (s : State) (tr : List String) (si : String) (z : Nat) :
    { ({ s with trace := tr, site := si, su0 := z } : State) with
        trace := s.trace, site := s.site, su0 := s.su0 } = s := by
  cases s; rfl

/-- **The congruence, forwards.** -/
theorem step_congr {s t : State} (h : SEq s t) {s' : State} (hs : step s = .continue s') :
    ∃ t', step t = .continue t' ∧ SEq s' t' := by
  rw [seq_eta h]
  exact step_decor s t.trace t.site t.su0 s' hs

/-- **The congruence, as a two-way test of the branch taken.** -/
theorem step_congr_iff {s t : State} (h : SEq s t) :
    (∃ s', step s = .continue s') ↔ (∃ t', step t = .continue t') :=
  ⟨fun ⟨s', hs⟩ => ⟨_, (step_congr h hs).choose_spec.1⟩,
   fun ⟨t', ht⟩ => ⟨_, (step_congr h.symm ht).choose_spec.1⟩⟩

/-! ## 2. A repeated state is a divergence -/

/-- More fuel at an `SEq`-equal state answers the same. -/
theorem run_seq : ∀ (n : Nat) {s t : State}, SEq s t → Finished (run s n) → Finished (run t n)
  | 0, s, t, _, h => by simp only [run, Finished] at h
  | n + 1, s, t, hst, h => by
    simp only [run] at h ⊢
    cases hs : step s with
    | done s0 =>
      have hnc : ¬ ∃ t', step t = .continue t' := by
        intro hc
        obtain ⟨s1, hs1⟩ := (step_congr_iff hst).mpr hc
        rw [hs] at hs1; exact absurd hs1 (by simp)
      cases ht : step t with
      | done t0 => trivial
      | died m t0 => trivial
      | «continue» t0 => exact absurd ⟨t0, ht⟩ hnc
    | died m s0 =>
      have hnc : ¬ ∃ t', step t = .continue t' := by
        intro hc
        obtain ⟨s1, hs1⟩ := (step_congr_iff hst).mpr hc
        rw [hs] at hs1; exact absurd hs1 (by simp)
      cases ht : step t with
      | done t0 => trivial
      | died m' t0 => trivial
      | «continue» t0 => exact absurd ⟨t0, ht⟩ hnc
    | «continue» s0 =>
      obtain ⟨t0, ht, hq⟩ := step_congr hst hs
      rw [ht]
      rw [hs] at h
      exact run_seq n hq h

/-- `n` `continue` steps from `s` to `t`. -/
def Runs : Nat → State → State → Prop
  | 0, s, t => s = t
  | n + 1, s, t => ∃ s', step s = .continue s' ∧ Runs n s' t

theorem Runs.run_eq : ∀ (n : Nat) {s t : State}, Runs n s t → ∀ m, run s (n + m) = run t m
  | 0, s, t, h, m => by simp only [Runs] at h; subst h; simp
  | n + 1, s, t, h, m => by
    obtain ⟨s', hstep, hrest⟩ := h
    have : n + 1 + m = (n + m) + 1 := by omega
    rw [this]
    simp only [run, hstep]
    exact Runs.run_eq n hrest m

/-- A run of `n` `continue` steps has no answer before `n`. -/
theorem Runs.not_finished : ∀ (n : Nat) {s t : State}, Runs n s t → ∀ m, m < n →
    ¬ Finished (run s m)
  | 0, s, t, _, m, hm => by omega
  | n + 1, s, t, h, m, hm => by
    obtain ⟨s', hstep, hrest⟩ := h
    cases m with
    | zero => simp [run, Finished]
    | succ k =>
      simp only [run, hstep]
      exact Runs.not_finished n hrest k (by omega)

/-- **A CYCLE IS A DIVERGENCE.**  If a run of `n ≥ 1` `continue` steps returns to a state
`SEq`-equal to where it started, the loop does not terminate.  `run` is a function of `step`
and `step` is a function of `SEq`, so nothing more is needed. -/
theorem not_terminates_of_cycle {s t : State} {n : Nat} (hn : 0 < n) (hr : Runs n s t)
    (heq : SEq t s) : ¬ Terminates s := by
  rintro ⟨m, hm⟩
  -- strong induction: an answer at fuel `m` gives one at fuel `m - n`, down below `n`.
  induction m using Nat.strong_induction_on with
  | _ m ih =>
    rcases Nat.lt_or_ge m n with hlt | hge
    · exact hr.not_finished n m hlt hm
    · obtain ⟨k, rfl⟩ : ∃ k, m = n + k := ⟨m - n, by omega⟩
      rw [hr.run_eq n k] at hm
      exact ih k (by omega) (run_seq k heq hm)

/-! ## 3. The canonical form, up to renaming of the minted ids -/

/-- The minted ids of a state, in FIRST-OCCURRENCE order: the incoming queue then the
processed queue, each in its own order, each partition's left-hand side then its abstract
parts in iteration order, then the environment's bindings.  An id below `su0` is an INPUT
variable and is not renamed. -/
def mintOrder (s : State) : List Nat :=
  let bump : List Nat → Nat → List Nat :=
    fun acc w => if w < s.su0 || acc.contains w then acc else acc ++ [w]
  let ofPart : List Nat → LPart → List Nat :=
    fun acc p => p.rhs.abstr.elems.foldl bump (bump acc p.lhs)
  let a := s.parts.foldl ofPart []
  s.env.binds.foldl (fun acc b =>
    match b.2 with
    | .emptyRow => bump acc b.1
    | .alias u => bump (bump acc b.1) u) a

/-- The canonical name of a variable: an input variable keeps its id, a minted one becomes
`su0 + its index in `mintOrder``.  The order is passed in rather than recomputed, so a state
is canonicalised in one pass. -/
def canonIdOf (su0 : Nat) (ord : List Nat) (w : Nat) : Nat :=
  if w < su0 then w
  else match ord.findIdx? (fun x => x == w) with
    | some i => su0 + i
    | none => su0 + ord.length

def canonId (s : State) (w : Nat) : Nat := canonIdOf s.su0 (mintOrder s) w

/-- One partition, canonically: `lhs<abstract;concrete`, with the abstract parts in their
ITERATION order (which is part of the state -- it decides the hash and hence the queue) and
the labels by their table index. -/
def canonPartOf (su0 : Nat) (ord : List Nat) (p : LPart) : String :=
  toString (canonIdOf su0 ord p.lhs) ++ "<" ++
    String.intercalate ","
      (p.rhs.abstr.elems.map (fun w => toString (canonIdOf su0 ord w))) ++ ";" ++
    String.intercalate "," (p.rhs.conc.elems.map (fun l => toString l.n))

def canonPart (s : State) (p : LPart) : String := canonPartOf s.su0 (mintOrder s) p

/-- The same without the renaming. -/
def rawPart (p : LPart) : String :=
  toString p.lhs ++ "<" ++
    String.intercalate "," (p.rhs.abstr.elems.map toString) ++ ";" ++
    String.intercalate "," (p.rhs.conc.elems.map (fun l => toString l.n))

/-- **The canonical state**: the two queues in order and the environment, with every minted
id renamed.  The supply is deliberately absent -- see the module note. -/
def canonState (s : State) : String :=
  let ord := mintOrder s
  let cid := canonIdOf s.su0 ord
  String.intercalate "|" (s.incm.elems.map (canonPartOf s.su0 ord)) ++ "#" ++
  String.intercalate "|" (s.proc.elems.map (canonPartOf s.su0 ord)) ++ "#" ++
  String.intercalate "|" (s.env.binds.map (fun b =>
    toString (cid b.1) ++ "=" ++
      (match b.2 with | .emptyRow => "()" | .alias u => toString (cid u))))

/-- **The exact state**: no renaming, and the supply's `lo`/`hi`/`drawn` included.

**A `rawState` hit is a CANDIDATE, not a proof** (round-6 review W-6a).  `rawState` renders
`incm.elems`, `proc.elems`, `env.binds` and three fields of `Sup`, while `SEq` -- which
`not_terminates_of_cycle` needs -- demands `s.incm = t.incm` for the WHOLE `PQueue`, i.e. the
type-variable `Graph` as well (`Queue.lean`'s `PQueue = ⟨elems, graph⟩`), plus `Sup.blk`/`bsz`,
`flags` and `names`.  The graph is not a decoration: `PQueue.dequeue` reads `graph.sort` for the
priority, and the graph keeps nodes and edges that removals from `elems` do not, so two states
can share a `rawState` and differ as `SEq`.  The direction the SEARCH uses is the sound one --
`canonState` and `rawState` are functions of the state, so an `SEq` repeat forces a `rawState`
repeat forces a `canonState` repeat, and **no hit means no `SEq` cycle** -- but a hit would have
to have its graphs, supply block and flags compared before `not_terminates_of_cycle` applied. -/
def rawState (s : State) : String :=
  String.intercalate "|" (s.incm.elems.map rawPart) ++ "#" ++
  String.intercalate "|" (s.proc.elems.map rawPart) ++ "#" ++
  String.intercalate "|" (s.env.binds.map (fun b =>
    toString b.1 ++ "=" ++ (match b.2 with | .emptyRow => "()" | .alias u => toString u))) ++
  "@" ++ toString s.su.lo ++ "/" ++ toString s.su.hi ++ "/" ++ toString s.su.drawn

/-! ## 4. The search -/

/-- What one cycle-instrumented solve reports. -/
structure CycleRep where
  /-- Dequeues taken. -/
  steps : Nat := 0
  /-- `SOLVED`, `REJECTED` or `FUEL`. -/
  verdict : String := "SOLVED"
  /-- The first canonical repeat found, as `(earlier index, later index)`. -/
  canonHit : Option (Nat × Nat) := none
  /-- The first exact repeat found. -/
  rawHit : Option (Nat × Nat) := none
  /-- The canonical string that repeated. -/
  witness : String := ""
  /-- How many distinct canonical states the run visited. -/
  distinct : Nat := 0
  /-- Ids drawn. -/
  drawn : Nat := 0

/-- A seen-set: the hash first, then the string, with the index it was first seen at. -/
abbrev SeenSet := List (UInt64 × String × Nat)

def seenFind (m : SeenSet) (h : UInt64) (x : String) : Option Nat :=
  (m.find? (fun e => e.1 == h && e.2.1 == x)).map (·.2.2)

/-- Run the loop, hashing the canonical and the exact rendering of the state at every
dequeue and reporting the first repeat of each. -/
def cycleRun : Nat → State → SeenSet → SeenSet → CycleRep → CycleRep
  | 0, s, _, _, rep => { rep with verdict := "FUEL", drawn := s.su.drawn }
  | n + 1, s, cs, rs, rep =>
    let c := canonState s
    let r := rawState s
    let ch := c.hash
    let rh := r.hash
    let rep :=
      match rep.canonHit, seenFind cs ch c with
      | none, some i => { rep with canonHit := some (i, rep.steps), witness := c }
      | _, _ => rep
    let rep :=
      match rep.rawHit, seenFind rs rh r with
      | none, some i => { rep with rawHit := some (i, rep.steps) }
      | _, _ => rep
    let cs := if (seenFind cs ch c).isSome then cs else (ch, c, rep.steps) :: cs
    let rs := if (seenFind rs rh r).isSome then rs else (rh, r, rep.steps) :: rs
    let rep := { rep with distinct := cs.length }
    match step s with
    | .done s' => { rep with verdict := "SOLVED", drawn := s'.su.drawn }
    | .died _ s' => { rep with verdict := "REJECTED", drawn := s'.su.drawn }
    | .continue s' => cycleRun n s' cs rs { rep with steps := rep.steps + 1 }

end Rowpartition.Loop
