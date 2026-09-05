/-
# L5 (C3): ingredients of the loop-level bound

Three facts about `step` that any bound has to use, proved here about the real `step`:

* `step_su` — **only the `learn` branch draws an id.**  Every other branch leaves the supply
  alone, so the VOCABULARY can grow only at a step `learnChain_card` already pays for with a
  new processed constraint;
* `step_envNodup` / `env_len_le_allVars` — **a variable is bound at most once**, because
  `instantiate` and `makeEmpty` die on a variable the environment already holds
  (`Subst.scala:184`'s reinstantiation panic), so the number of bindings never exceeds the
  vocabulary;
* `step_env_len` / `instantiate_env_len` / `makeEmpty_env_len` — **each of the three
  environment branches adds exactly one binding**, so along a run that does not die those
  three branches are bounded by the vocabulary.

Together: the `common` (at distinct variables), `empty` and `unify` branches are bounded by
`(allVars (sys s)).card`, and the `learn` branch is bounded by the growth of `procSys`
(`Order.learnChain_card`).  The two branches that remain unbounded without a VOCABULARY bound
are `learn` (which mints) and `concrete` (which binds nothing); `L5-TERMINATION.md` §C3 says
exactly what is missing.
-/
import Rowpartition.Loop.StrictStep

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. Only `learn` draws an id -/

/-- **The supply moves only at a `learn` step.**  Since a fresh id is the only way a new
variable enters the system, the vocabulary can grow only at a step that `learnChain_card`
already charges a new processed constraint for. -/
theorem step_su {s s' : State} (h : step s = .continue s') :
    s'.su = s.su ∨ IsLearnStep s := by
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    split at h
    · rename_i u _
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact Or.inl rfl
    · rename_i hfr
      split at h
      · rename_i hem
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact Or.inl rfl
      · rename_i hem
        split at h
        · rename_i hab
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact Or.inl rfl
        · rename_i hab
          split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact Or.inl rfl
          · rename_i hsg
            exact Or.inr ⟨r, rest, hdq, hfr, by simpa using hem, by simpa using hab, hsg⟩

/-! ## 2. A variable is bound at most once -/

/-- The environment's bound variables are distinct.  `instantiate` and `makeEmpty` both die on
a variable the environment already holds, so this is an invariant, not an assumption. -/
def EnvNodup (s : State) : Prop := (s.env.binds.map Prod.fst).Nodup

theorem env_contains_false {e : Env} {v : Nat} (h : e.contains v = false) :
    ∀ b ∈ e.binds, b.1 ≠ v := by
  intro b hb hbv
  unfold Env.contains Env.lookup at h
  cases hfind : e.binds.find? (fun p => p.1 == v) with
  | none => exact (List.find?_eq_none.mp hfind) b hb (by simpa using hbv)
  | some y => rw [hfind] at h; simp at h

theorem env_instantiate_nodup {e : Env} {v : Nat} {val : EnvVal}
    (h : (e.binds.map Prod.fst).Nodup) (hv : e.contains v = false) :
    (((e.instantiate v val).binds).map Prod.fst).Nodup := by
  unfold Env.instantiate
  simp only [List.map_append, List.map_map, Function.comp_def]
  refine List.Nodup.append (by simpa using h) (by simp) ?_
  intro x hx hy
  simp only [List.mem_map] at hx
  obtain ⟨b, hb, hbx⟩ := hx
  have hxv : x = v := by simpa using hy
  exact env_contains_false hv b hb (hbx.trans hxv)

theorem instantiate_env_len {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    e.binds.length = env.binds.length + 1 ∧ env.contains v = false ∧
      e = env.instantiate v (.alias u) := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rename_i hc
    rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨-, -, rfl⟩ := h
    refine ⟨by simp [Env.instantiate], by simpa using hc, rfl⟩

theorem makeEmpty_env_len {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    e.binds.length = env.binds.length + 1 ∧ env.contains v = false ∧
      e = env.instantiate v .emptyRow := by
  simp only [makeEmpty] at h
  obtain ⟨nps, -, h2⟩ := except_bind_ok h
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rename_i hc
      rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨-, -, rfl⟩ := h2
      exact ⟨by simp [Env.instantiate], by simpa using hc, rfl⟩

theorem unifyVars_env {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : unifyVars ns v u incm proc env = .ok (ni, np, e)) :
    e = env ∨ (e.binds.length = env.binds.length + 1 ∧ env.contains v = false ∧
      e = env.instantiate v (.alias u)) := by
  simp only [unifyVars] at h
  split at h
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    exact Or.inl h.2.2.symm
  · exact Or.inr (instantiate_env_len h)

/-- **A variable is bound at most once**, along every run. -/
theorem step_envNodup {s s' : State} (h0 : EnvNodup s) (h : step s = .continue s') :
    EnvNodup s' := by
  unfold EnvNodup at h0 ⊢
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    split at h
    · rename_i u _
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        rcases unifyVars_env hres with rfl | ⟨-, hc, rfl⟩
        · exact h0
        · exact env_instantiate_nodup h0 hc
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨-, hc, rfl⟩ := makeEmpty_env_len hres
          exact env_instantiate_nodup h0 hc
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact h0
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              rcases unifyVars_env hres with rfl | ⟨-, hc, rfl⟩
              · exact h0
              · exact env_instantiate_nodup h0 hc
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              simpa [foldl_log_env] using h0

/-- The initial state of a solve has an empty environment. -/
theorem envNodup_initial {q p : PQueue} (fl : Flags) (ns : Names) (site : String) (su : Sup)
    (tr : List String) (su0 : Nat) :
    EnvNodup { incm := q, proc := p, env := ({} : Env), su := su, trace := tr, flags := fl,
               names := ns, site := site, su0 := su0 } := by
  simp [EnvNodup]

/-- **The environment never outgrows the vocabulary.**  Every binding names a variable of the
system the state denotes, and by `step_envNodup` no variable is named twice. -/
theorem env_len_le_allVars {s : State} (h : EnvNodup s) :
    s.env.binds.length ≤ (allVars (sys s)).card := by
  have hsub : (s.env.binds.map Prod.fst).toFinset ⊆ allVars (sys s) := by
    intro x hx
    obtain ⟨b, hb, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hx)
    have hlhs : (EnvVal.toConstraint b.1 b.2).lhs = b.1 := by
      obtain ⟨w, val⟩ := b; cases val <;> rfl
    exact hlhs ▸ lhs_mem_allVars (mem_sys_of_env hb)
  calc s.env.binds.length = (s.env.binds.map Prod.fst).length := by simp
    _ = (s.env.binds.map Prod.fst).toFinset.card := (List.toFinset_card_of_nodup h).symm
    _ ≤ (allVars (sys s)).card := Finset.card_le_card hsub

/-! ## 4. Round 2: `L5-REVIEW.md` §5b — the localisation, corrected and PROVED

`L5-TERMINATION.md` §C3.2 said the residual mint-guard mismatch over `qsys` is "a mint at a key
EQUAL to the parent's whole concrete row".  Both halves of that are wrong, and the two theorems
below are the corrections the reviewer machine-checked in his own scratch. -/

open Rowpartition.KeyedRow in
/-- **(i) `C \ K = ∅` is `C ⊆ K`, not `K = C`.**  A retained `z <- ()` carries the key `K` for
a parent with concrete row `C` whenever `C ⊆ K` -- so it carries `2^{|L \ C|}` keys, not one. -/
theorem concCarried_of_conc_subset {G : System} {v z : Var} {C K : Row}
    (hv : mk v ∅ C ∈ G) (hz : mk z ∅ (∅ : Row) ∈ G) (hCK : C ⊆ K) : ConcCarried G v K := by
  refine (concCarried_iff G v K).mpr ⟨C, z, hv, ?_⟩
  have : C \ K = ∅ := Finset.sdiff_eq_empty_iff_subset.mpr hCK
  rw [this]
  exact hz

open Rowpartition.KeyedRow in
/-- **(ii) the parent-already-empty case, which §C3.2 missed entirely.**  If the parent is
itself already empty then `C = ∅ ⊆ K` for EVERY `K`, so one retained fact carries every key at
once.  This case is vacuous exactly when `QueueHygiene` (below) holds. -/
theorem concCarried_parent_empty {G : System} {v : Var} (hv : mk v ∅ (∅ : Row) ∈ G) (K : Row) :
    ConcCarried G v K :=
  concCarried_of_conc_subset hv hv (Finset.empty_subset K)

/-- The environment's retained empty-row facts are in `qsys`. -/
theorem envEmpty_mem_qsys {s : State} {z : Nat} (h : (z, EnvVal.emptyRow) ∈ s.env.binds) :
    mk z ∅ (∅ : Row) ∈ qsys s := by
  refine Finset.mem_union_right _ ?_
  refine List.mem_toFinset.mpr (List.mem_filterMap.mpr ⟨(z, EnvVal.emptyRow), h, ?_⟩)
  rfl

open Rowpartition.KeyedRow in
/-- **The mismatch, over `qsys`, in its corrected form.**  As soon as the environment holds one
empty-row fact, every key `K ⊇ C` of every parent with concrete row `C` in the queue-visible
system is CARRIED -- while the loop's `findConcRow` (`Constraints.scala:1410-1418`, model
`Loop/Step.lean`'s `findConcRow`) scans the queues only and misses it.  That is the whole of
the residual (A)-gap of `L5-TERMINATION.md` §C3.2, and `-Dermine.emptyRow` is the flag that
closes it. -/
theorem qsys_concCarried_of_envEmpty {s : State} {v z : Nat} {C K : Row}
    (hv : mk v ∅ C ∈ qsys s) (hz : (z, EnvVal.emptyRow) ∈ s.env.binds) (hCK : C ⊆ K) :
    ConcCarried (qsys s) v K :=
  concCarried_of_conc_subset hv (envEmpty_mem_qsys hz) hCK

/-! ## 5. Round 2: the queue-hygiene invariant, and why it fails

`L5-REVIEW.md` §5e names this as the second step to T1: it kills §4's case (ii), it makes the
`qsys`/`sys` gap exactly the ALIAS facts, and it is what the compiler panic of
`L5-TERMINATION.md` §0 violates. -/

/-- **Queue hygiene**: no partition of either queue is headed by, or mentions, a variable the
environment has already bound. -/
def QueueHygiene (s : State) : Prop :=
  ∀ p ∈ s.parts, ∀ v : Nat, s.env.contains v = true → p.involves v = false

/-- **Under queue hygiene the reinstantiation panic is unreachable**: the dequeued partition's
left-hand side is unbound, which is exactly what `makeEmpty` and `instantiate` check before
`instantiateType`.  So `QueueHygiene` is the invariant whose failure `L5-TERMINATION.md` §0
exhibits on the compiler. -/
theorem queueHygiene_no_rebind {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) : s.env.contains r.lhs = false := by
  obtain ⟨hrMem, -⟩ := PQueue.dequeue_mem hdq
  cases hc : s.env.contains r.lhs with
  | false => rfl
  | true =>
    have := h r (List.mem_append_left _ hrMem) r.lhs hc
    simp only [LPart.involves, Bool.or_eq_false_iff, beq_eq_false_iff_ne] at this
    exact absurd rfl this.1

/-- `selfSubstitution` EXCLUDES the variable it substitutes: `(abstr - v)`
(`Constraints.scala:1157`). -/
theorem selfSubstitution_excludes_self {ns : Names} {v : Nat} {a : SSet Nat} {c : SSet Lbl}
    {S : SSet LPart} (h : selfSubstitution ns v a c = .ok S) : ∀ y ∈ S.elems, y.lhs ≠ v := by
  simp only [selfSubstitution] at h
  split at h
  · rw [Except.ok.injEq] at h
    subst h
    intro y hy
    obtain ⟨u, hu, rfl⟩ := SSet.mem_map hy
    intro hcon
    subst hcon
    unfold SSet.excl at hu
    split at hu
    · have hmem := SSet.mem_champ.mp hu
      have h2 := List.of_mem_filter hmem
      rw [show SVal.eq u u = (u == u) from rfl] at h2
      simp at h2
    · have h2 := List.of_mem_filter hu
      rw [show SVal.eq u u = (u == u) from rfl] at h2
      simp at h2
  · exact absurd h (by simp)

/-- **`makeEmpty`'s `aux` EXCLUDES `v`**, matching `selfSubstitution` twelve lines away
(`Constraints.scala`, `makeEmpty`'s `aux`, and `Loop/Step.lean`'s `makeEmpty` fold).

Until 2026-09-04 both mapped over ALL of `abstr`, so a self-referential all-variable definition
`v <- (v, ...)` in either queue made the propagation emit `v <- ()` for the very variable the
call was about to bind; re-enqueued, it made a later dequeue call `makeEmpty v` a second time,
which `instantiateType` refuses -- the reinstantiation panic of `L5-TERMINATION.md` §0, on a
SATISFIABLE input, at 11 of 100 id bases (`tracker/repro/satterm/seeds/PANIC3.json`).  Brief B1
changed both to `(abstr - v)` / `(abstr.excl v)`, and this lemma replaces the round-2
`makeEmpty_aux_emits_self`, which stated the OLD behaviour.  With it the `makeEmpty` case of a
`QueueHygiene` preservation proof is no longer contradicted -- the invariant is provable in
principle; the preservation proof itself is NOT attempted here (L5 round-3 work), so
`QueueHygiene` and `queueHygiene_no_rebind` above are left exactly as they were. -/
theorem makeEmpty_aux_excludes_self {v : Nat} {a : SSet Nat}
    {S : SSet LPart}
    (h : (a.excl v).map (fun w => (⟨w, RHS.empty, some Inference.partitionEmpty⟩ : LPart)) = S) :
    ∀ y ∈ S.elems, y.lhs ≠ v := by
  subst h
  intro y hy
  obtain ⟨u, hu, rfl⟩ := SSet.mem_map hy
  intro hcon
  subst hcon
  unfold SSet.excl at hu
  split at hu
  · have hmem := SSet.mem_champ.mp hu
    have h2 := List.of_mem_filter hmem
    rw [show SVal.eq u u = (u == u) from rfl] at h2
    simp at h2
  · have h2 := List.of_mem_filter hu
    rw [show SVal.eq u u = (u == u) from rfl] at h2
    simp at h2


end Rowpartition.Loop
