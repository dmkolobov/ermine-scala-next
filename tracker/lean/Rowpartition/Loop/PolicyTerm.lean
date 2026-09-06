/-
# D1-T (second half): TERMINATION UNDER A BUDGET, transported to the policy loop

`Loop/PolicyStep.lean` carried S1 and S2 across to `stepP pol`.  This module carries the other
half of D1: `Loop/Budget.lean`'s **`budget_terminates`** — *every solve stops* — which is stated
for `run`/`runBud`, i.e. for the SHIPPED dequeue order.  D1 ships the budget TOGETHER with the
policy, so the guarantee has to hold for the order the flag actually selects.

WHY IT TRANSPORTS.  Round 7's argument (`Loop/VocFix.lean` §5–§11) measures the STATE — the
incoming queue's length, the processed set, the row set, the environment and the vocabulary —
and never the ORDER a partition was chosen in.  Per `D1-DESIGN.md` §5f the one order-dependent
lemma in the tree, `dequeue_prio_min`, is used once to prove a lemma used nowhere, and the
termination fragment uses exactly four facts about `pop`: `shape_mem`, `shape_mem_or`,
`shape_kdist` and the queue-length equation.  All four hold for every policy
(`Loop/Policy.lean` §5), so the whole chain is a copy with the substitutions of `PolicyStep`.

WHAT IS DIFFERENT FROM THE FIRST HALF: the reachability relations.  `Reaches`, `Runs`,
`Terminates` and `NoDrawB` are all defined in terms of `step`/`run`, and under a policy the loop
also threads the auxiliary state `Aux` (`fifo`'s arrival batches, `canon`'s cached priority).
So they get policy forms that thread it — `ReachesP pol a₀ s₀ b t` is "`t`, with auxiliary state
`b`, is reached from `s₀` with auxiliary state `a₀` by `continue` steps of `stepP pol`" — and
every statement quantified over `Reaches s t` gains ONE binder, for the auxiliary state at the
reached configuration.  That is the only shape change; no hypothesis is otherwise weakened and
no conclusion narrowed.  `reachesP_shipped`/`terminatesP_shipped` below recover the originals.

THE ONE REAL DIFFERENCE, stated and not hidden: `Budget.runBud` tests `d0 + b < s.su.drawn`
unconditionally, while `PolicyReplay.runSP` — the driver the replay actually runs — tests
`b != 0 && d0 + b < s.su.drawn`, so `b = 0` means THE BUDGET IS OFF.  `budgetP_terminates`
therefore carries `hb0 : b ≠ 0`, which `budget_terminates` does not need.  That is a property of
the driver, not of the policy: with `b = 0` no cap is being asked for.
-/
import Rowpartition.Loop.PolicyStep

namespace Rowpartition.Loop

variable {pol : Policy} {aux : Aux}

/-! ## 1. The one dequeue fact `Loop/Policy.lean` states only as an inequality

`shape_length_lt` gives `<`; `Dequeue.dequeue_length_lt` gives the EQUATION, and
`step_quadrichotomy`'s third case needs the equation. -/

/-- A dequeue removes exactly one partition. -/
theorem shape_length_eq {q : PQueue} {r : LPart} {rest : PQueue} (h : DequeueShape q r rest) :
    rest.elems.length + 1 = q.elems.length := by
  obtain ⟨i, hi, rfl⟩ := h
  have hlt : i < q.elems.length := (List.getElem?_eq_some_iff.mp hi).1
  simp only [List.length_eraseIdx, hlt, if_pos]
  omega

/-- `VocFix.IsConcStep` at the policy's dequeue: the `concrete` dispatch branch, with
everything the potential argument needs. -/
def IsConcStepP (pol : Policy) (aux : Aux) (s s' : State) : Prop :=
  ∃ (r : LPart) (rest : PQueue), dequeuePol pol aux s.incm = some (r, rest) ∧
    s.proc.findRHS r.rhs = none ∧ r.rhs.isEmpty = false ∧ r.rhs.abstr.isEmpty = true ∧
    makeConcrete r.lhs r.rhs.conc rest s.proc = .ok (s'.incm, s'.proc)

/-! ## 2. The step-level fragment: the four kinds of step and the measure they bound -/

/-- **The vocabulary does not grow at a step that draws no id.**  All five dispatch branches,
including `concrete`, which `NoConc.step_inVoc` discharged by `exfalso`: `makeConcrete` builds
`cancellation`s of the dequeued row against `v`'s own definitions and re-expresses the rest by
`destructiveSub`, and `Hygiene.makeConcrete_avoids` already covers it at any `B`. -/
theorem stepP_inVoc_noDraw {V : Finset Var} {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h0 : InVoc V s)
    (h : stepP pol aux s = .continue s') (hnd : s'.su.drawn = s.su.drawn) : InVoc V s' := by
  obtain ⟨h0p, h0e⟩ := h0
  have hi0 : ∀ x ∈ s.incm.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
    fun x hx => h0p x (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
    fun x hx => h0p x (List.mem_append_right _ hx)
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrMem : r ∈ s.incm.elems := (shape_mem (dequeuePol_shape hdq)).1
    have hrest : ∀ x ∈ rest.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
      fun x hx => hi0 x ((shape_mem (dequeuePol_shape hdq)).2 x hx)
    have hrA := avoids_toConstraint_iff.mp (hi0 r hrMem)
    have hfin : ∀ {ni np : PQueue} {e : Env},
        (∀ x ∈ ni.elems, Avoids (fun w => w ∉ V) x.toConstraint) →
        (∀ x ∈ np.elems, Avoids (fun w => w ∉ V) x.toConstraint) →
        (∀ b ∈ e.binds, Avoids (fun w => w ∉ V) (EnvVal.toConstraint b.1 b.2)) →
        InVoc V { incm := ni, proc := np, env := e, su := s.su, trace := s.trace,
                  flags := s.flags, names := s.names, site := s.site, su0 := s.su0 } := by
      intro ni np e h1 h2 h3
      refine ⟨fun p hp => ?_, h3⟩
      rcases List.mem_append.mp hp with hp' | hp'
      · exact h1 p hp'
      · exact h2 p hp'
    split at h
    · -- common
      rename_i u hu
      have huB : ¬ (u ∉ V) := findRHS_avoids hp0 hu
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        simp only [unifyVars] at hres
        split at hres
        · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
          obtain ⟨rfl, rfl, rfl⟩ := hres
          exact hfin hrest hp0 h0e
        · rename_i hne
          obtain ⟨hni, hnp⟩ := instantiate_avoids (by simpa using hne) huB hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs (.alias u) := (instantiate_env_len hres).2.2
          refine hfin (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hni x hx))
            (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hnp x hx)) ?_
          rw [henv]
          exact avoids_env_instantiate h0e hrA.1 (fun u0 hu0 => by
            rw [EnvVal.alias.injEq] at hu0; exact hu0 ▸ huB)
    · split at h
      · -- empty
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨hni, hnp⟩ := makeEmpty_avoids hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs .emptyRow := (makeEmpty_env_len hres).2.2
          refine hfin (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hni x hx))
            (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hnp x hx)) ?_
          rw [henv]
          exact avoids_env_instantiate h0e hrA.1 (by simp)
      · split at h
        · -- concrete
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨hni, hnp⟩ := makeConcrete_avoids hrA.1 hrest hp0 hres
            exact hfin hni hnp h0e
        · split at h
          · -- unify
            rename_i u hsg
            have huB : ¬ (u ∉ V) := by
              refine hrA.2 u ?_
              have : r.rhs.abstr.single? = some u := by
                unfold RHS.single? at hsg
                split at hsg
                · exact hsg
                · exact absurd hsg (by simp)
              exact mem_of_single? this
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              simp only [unifyVars] at hres
              split at hres
              · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                obtain ⟨rfl, rfl, rfl⟩ := hres
                exact hfin hrest hp0 h0e
              · rename_i hne
                obtain ⟨hni, hnp⟩ := instantiate_avoids (by simpa using hne) hrA.1 hrest hp0 hres
                have henv : e = s.env.instantiate u (.alias r.lhs) := (instantiate_env_len hres).2.2
                refine hfin (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hni x hx))
                  (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hnp x hx)) ?_
                rw [henv]
                exact avoids_env_instantiate h0e huB (fun u0 hu0 => by
                  rw [EnvVal.alias.injEq] at hu0; exact hu0 ▸ hrA.1)
          · -- learn
            cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              have hnd2 : su2.drawn = s.su.drawn := hnd
              have hlearn := learnPartitions_avoidsV_noDraw (B := fun w => w ∉ V) hdj hcse
                hrA.1 hrA.2 hrest hp0 hlp hnd2
              refine ⟨fun x hx => ?_, h0e⟩
              rcases List.mem_append.mp hx with hx' | hx'
              · exact concatP_avoids _ hrest
                  (fun d hd => hlearn d (SSet.mem_filter hd)) x hx'
              · exact insertNP_avoids hp0 (hi0 r hrMem) hx'

/-- **The `concrete` branch strictly grows the potential.** -/
theorem rowSetP_lt_concrete {V : Finset Var} {L : Finset Label} {s s' : State}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s)) {r : LPart} {rest : PQueue}
    (hdq : dequeuePol pol aux s.incm = some (r, rest))
    (hfind : s.proc.findRHS r.rhs = none)
    (hne : r.rhs.isEmpty = false) (hab : r.rhs.abstr.isEmpty = true)
    (hmk : makeConcrete r.lhs r.rhs.conc rest s.proc = .ok (s'.incm, s'.proc)) :
    (rowSet V L s).card < (rowSet V L s').card := by
  have hrMem : r ∈ s.incm.elems := (shape_mem (dequeuePol_shape hdq)).1
  have hrPart : r ∈ s.parts := List.mem_append_left _ hrMem
  have habN : r.rhs.abstr.elems = [] := by simpa [SSet.isEmpty] using hab
  have hfs : r.rhs.conc.isEmpty = false := by
    simp only [RHS.isEmpty, Bool.and_eq_false_iff, hab] at hne
    rcases hne with h | h
    · exact absurd h (by simp)
    · exact h
  -- no processed partition has the dequeued right-hand side, hence none is a bare `((|fs|))`
  have hnofind : ∀ y ∈ s.proc.elems, y.rhs.eqv r.rhs = false := by
    intro y hy
    cases hf : (s.proc.elems.find? (fun x => x.rhs.eqv r.rhs)) with
    | some z => rw [PQueue.findRHS, hf] at hfind; exact absurd hfind (by simp)
    | none => simpa using List.find?_eq_none.mp hf y hy
  have hno : ∀ y ∈ s.proc.elems, y.rhs.eqv (RHS.ofConcr r.rhs.conc) = false := by
    intro y hy
    cases hyy : y.rhs.eqv (RHS.ofConcr r.rhs.conc) with
    | false => rfl
    | true =>
      exfalso
      simp only [RHS.eqv, RHS.ofConcr, Bool.and_eq_true] at hyy
      have hya : y.rhs.abstr.elems = [] := by
        have := hyy.1
        simp only [SSet.eqv, SSet.size, SSet.empty, Bool.and_eq_true, beq_iff_eq,
          List.length_nil] at this
        exact List.eq_nil_of_length_eq_zero this.1
      have : y.rhs.eqv r.rhs = true := by
        simp only [RHS.eqv, Bool.and_eq_true]
        exact ⟨eqv_empty_abstr hya habN, hyy.2⟩
      rw [hnofind y hy] at this; exact absurd this (by simp)
  have hrow : (⟨r.lhs, RHS.ofConcr r.rhs.conc, none⟩ : LPart) ∈ s'.proc.elems :=
    makeConcrete_row_mem hmk hfs hno
  have hcncp : ∀ q ∈ s.proc.elems, q.rhs.conc.Nodup :=
    fun q hq => (hw.nodup (List.mem_append_right _ hq)).2
  have hcnci : ∀ q ∈ rest.elems, q.rhs.conc.Nodup :=
    fun q hq => (hw.nodup (List.mem_append_left _ ((shape_mem (dequeuePol_shape hdq)).2 q hq))).2
  have hsup := makeConcrete_superset hcncp hcnci hmk
  -- every recorded row of `r.lhs` is inside the new one
  have hsupN : ∀ p ∈ s.proc.elems, p.lhs = r.lhs →
      p.toConstraint.conc ⊆ r.toConstraint.conc := by
    intro p hp hl x hx
    simp only [LPart.conc_toConstraint, List.mem_toFinset, List.mem_map] at hx ⊢
    obtain ⟨y, hy, rfl⟩ := hx
    exact ⟨y, subsetOfL_iff.mp (hsup p hp hl) y hy, rfl⟩
  have hsub : rowSet V L s ⊆ rowSet V L s' := by
    intro q hq
    obtain ⟨h1, p, hp, hl, ha, hc⟩ := mem_rowSet_iff.mp hq
    by_cases hlv : p.lhs = r.lhs
    · refine mem_rowSet_iff.mpr ⟨h1, ⟨r.lhs, RHS.ofConcr r.rhs.conc, none⟩, hrow, ?_, ?_, ?_⟩
      · rw [← hl, hlv]
      · simp [RHS.ofConcr, SSet.empty]
      · refine subset_trans hc ?_
        have := hsupN p hp hlv
        simpa [LPart.conc_toConstraint, RHS.ofConcr] using this
    · refine mem_rowSet_iff.mpr ⟨h1, p, ?_, hl, ha, hc⟩
      refine makeConcrete_proc_keep hmk hp (by simpa using hlv) ?_
      simp [RHS.contains, SSet.contains, ha]
  refine Finset.card_lt_card (Finset.ssubset_iff_of_subset hsub |>.mpr ?_)
  refine ⟨(r.lhs, r.toConstraint.conc), ?_, ?_⟩
  · refine mem_rowSet_iff.mpr ⟨⟨?_, ?_⟩, ⟨r.lhs, RHS.ofConcr r.rhs.conc, none⟩, hrow, rfl,
      by simp [RHS.ofConcr, SSet.empty], by simp [LPart.conc_toConstraint, RHS.ofConcr]⟩
    · exact not_not.mp (avoids_toConstraint_iff.mp (hv.1 r hrPart)).1
    · exact hcs _ (mem_sys_of_part hrPart)
  · intro hbad
    obtain ⟨-, p, hp, hl, ha, hc⟩ := mem_rowSet_iff.mp hbad
    have hEq : p.toConstraint.conc = r.toConstraint.conc :=
      Finset.Subset.antisymm (hsupN p hp hl) hc
    have hcoh : LblCoh (p.rhs.conc.elems ++ r.rhs.conc.elems) := by
      refine hw.coh.mono ?_
      intro x hx
      rcases List.mem_append.mp hx with hx' | hx'
      · exact State.mem_labels (List.mem_append_right _ hp) hx'
      · exact State.mem_labels hrPart hx'
    have hfin : p.rhs.conc.elems.toFinset = r.rhs.conc.elems.toFinset :=
      (toFinset_map_n_iff hcoh).mp (by simpa [LPart.conc_toConstraint] using hEq)
    have hce : p.rhs.conc.eqv r.rhs.conc = true :=
      (SSet.eqv_iff_toFinset (hcncp p hp) (hw.nodup hrPart).2).mpr hfin
    have : p.rhs.eqv r.rhs = true := by
      simp only [RHS.eqv, Bool.and_eq_true]
      exact ⟨eqv_empty_abstr ha habN, hce⟩
    rw [hnofind p hp] at this; exact absurd this (by simp)

/-- **Every `learn` step adds a genuinely new constraint to the processed queue.**  The
dequeued partition is not `Partition.equals` to anything already processed -- otherwise the
dispatch would have taken the COMMON branch -- so `procSys` strictly grows. -/
theorem learnP_procSys_lt {s s' : State} {r : LPart} {rest : PQueue} (hw : Wf s)
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : stepP pol aux s = .continue s') :
    (procSys s).card < (procSys s').card := by
  obtain ⟨hproc, -⟩ := stepP_learn_shape hd h1 h2 h3 h4 h
  obtain ⟨hrMem, -⟩ := shape_mem (dequeuePol_shape hd)
  have hfindnone : s.proc.elems.find? (fun x => x.rhs.eqv r.rhs) = none := by
    unfold PQueue.findRHS at h1
    cases hh : s.proc.elems.find? (fun x => x.rhs.eqv r.rhs) with
    | none => rfl
    | some z => rw [hh] at h1; exact absurd h1 (by simp)
  have hnew : r.toConstraint ∉ procSys s := by
    intro hc
    obtain ⟨y, hy, hyr⟩ := List.mem_map.mp (List.mem_toFinset.mp hc)
    have heq : y.eqv r = true :=
      (LPart.eqv_iff_toConstraint_of_wf hw (List.mem_append_right _ hy)
        (List.mem_append_left _ hrMem)).mpr hyr
    unfold LPart.eqv at heq
    rw [Bool.and_eq_true] at heq
    exact (List.find?_eq_none.mp hfindnone y hy) (by simpa using heq.2)
  have hset : procSys s' = insert r.toConstraint (procSys s) := by
    unfold procSys
    rw [hproc]
    ext c
    simp only [List.mem_toFinset, List.mem_map, Finset.mem_insert]
    constructor
    · rintro ⟨y, hy, rfl⟩
      rcases mem_insertNP hy with hy' | rfl
      · exact Or.inr ⟨y, hy', rfl⟩
      · exact Or.inl rfl
    · rintro (rfl | ⟨y, hy, rfl⟩)
      · exact ⟨r, learn_insertNP_self h1 h4, rfl⟩
      · exact ⟨y, mem_insertNP_of_mem hy, rfl⟩
  rw [hset, Finset.card_insert_of_notMem hnew]
  omega

/-- **The quadrichotomy.**  Every `continue` step either
* is a `learn` step -- the processed set strictly grows and nothing is deleted from it;
* is a `concrete` step -- the environment is unchanged and §4's potential strictly grows;
* binds a variable -- the environment grows by exactly one;
* or is a `common`/`unify` at EQUAL variables -- nothing changes but the queue's length. -/
theorem stepP_quadrichotomy {s s' : State} (h : stepP pol aux s = .continue s') :
    (IsLearnStepP pol aux s ∧ s'.env = s.env ∧ ∀ p ∈ s.proc.elems, p ∈ s'.proc.elems) ∨
    (s'.env.binds.length = s.env.binds.length + 1) ∨
    (s'.env = s.env ∧ s'.proc = s.proc ∧ s'.incm.elems.length + 1 = s.incm.elems.length) ∨
    (IsConcStepP pol aux s s' ∧ s'.env = s.env) := by
  simp only [stepP, State.log] at h
  cases hd : dequeuePol pol aux s.incm with
  | none => rw [hd] at h; exact absurd h (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at h
    dsimp only at h
    have hlen : rest.elems.length + 1 = s.incm.elems.length :=
      shape_length_eq (dequeuePol_shape hd)
    split at h
    · -- common
      rename_i u hfind
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hu] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        by_cases hvu : r.lhs = u
        · rw [unifyVars, if_pos (by simp [hvu])] at hu
          simp only [Except.ok.injEq, Prod.mk.injEq] at hu
          obtain ⟨h1, h2, h3⟩ := hu
          exact Or.inr (Or.inr (Or.inl ⟨h3.symm, h2.symm, by rw [← h1]; exact hlen⟩))
        · rw [unifyVars, if_neg (by simpa using hvu)] at hu
          exact Or.inr (Or.inl (instantiate_env_len hu).1)
    · rename_i hfind
      split at h
      · -- empty
        cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hu] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hu] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact Or.inr (Or.inl (makeEmpty_env_len hu).1)
      · rename_i hne
        split at h
        · -- concrete
          rename_i hab
          cases hu : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hu] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hu] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact Or.inr (Or.inr (Or.inr
              ⟨⟨r, rest, hd, by simpa using hfind, by simpa using hne, hab, hu⟩, rfl⟩))
        · rename_i hab
          split at h
          · -- unify
            rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hu] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              by_cases hvu : u = r.lhs
              · rw [unifyVars, if_pos (by simp [hvu])] at hu
                simp only [Except.ok.injEq, Prod.mk.injEq] at hu
                obtain ⟨h1, h2, h3⟩ := hu
                exact Or.inr (Or.inr (Or.inl ⟨h3.symm, h2.symm, by rw [← h1]; exact hlen⟩))
              · rw [unifyVars, if_neg (by simpa using hvu)] at hu
                exact Or.inr (Or.inl (instantiate_env_len hu).1)
          · -- learn
            rename_i hsingle
            cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hu] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact Or.inl ⟨⟨r, rest, hd, hfind, by simpa using hne, by simpa using hab,
                hsingle⟩, rfl, fun p hp => mem_insertNP_of_mem hp⟩

/-- **The measure strictly decreases at every step**, given the four bounds -- with NO
fragment hypothesis on the step itself.  What the hypotheses buy is the potential: `InVoc`
and `ConcSub` are what make `rowSet` the right thing to count. -/
theorem measureP4_lt {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {s s' : State}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s))
    (hR' : (rowSet V L s').card ≤ R) (hP' : (procSys s').card ≤ P)
    (hQ' : s'.incm.elems.length ≤ Q) (hE' : s'.env.binds.length ≤ E)
    (h : stepP pol aux s = .continue s') :
    measure4 P Q E R V L s' < measure4 P Q E R V L s := by
  simp only [measure4]
  refine measure4_arith hR' hP' hQ' hE' ?_
  rcases stepP_quadrichotomy h with
    ⟨⟨r, rest, hd, h1, h2, h3, h4⟩, henv, hpr⟩ | henv | ⟨he, hp, hc⟩ |
      ⟨⟨r, rest, hd, h1, h2, h3, hmk⟩, henv⟩
  · exact Or.inl ⟨by rw [henv],
      Finset.card_le_card (rowSet_subset_of (fun p hp' _ => hpr p hp')),
      learnP_procSys_lt hw hd h1 h2 h3 h4 h⟩
  · exact Or.inr (Or.inl henv)
  · exact Or.inr (Or.inr (Or.inl ⟨by rw [he],
      Finset.card_le_card (rowSet_subset_of (fun p hp' _ => by rw [hp]; exact hp')),
      by rw [procSys, procSys, hp], hc⟩))
  · exact Or.inr (Or.inr (Or.inr ⟨by rw [henv],
      rowSetP_lt_concrete hw hv hcs hd h1 h2 h3 hmk⟩))

/-- **The queue invariant, off the no-labels fragment.**  `NoConc.step_kdist` with the
`concrete` branch proved rather than excluded. -/
theorem stepP_kdist' {s s' : State} (hi : KDist s.incm.elems)
    (hp : KDist s.proc.elems) (h : stepP pol aux s = .continue s') :
    KDist s'.incm.elems ∧ KDist s'.proc.elems := by
  simp only [stepP, State.log] at h
  cases hd : dequeuePol pol aux s.incm with
  | none => rw [hd] at h; exact absurd h (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at h
    dsimp only at h
    have hrest : KDist rest.elems := shape_kdist (dequeuePol_shape hd) hi
    split at h
    · rename_i u _
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hu] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact kdist_unifyVars hrest hp hu
    · split at h
      · cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hu] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hu] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact kdist_makeEmpty hrest hp hu
      · split at h
        · cases hu : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hu] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hu] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact kdist_makeConcrete hrest hp hu
        · split at h
          · rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hu] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact kdist_unifyVars hrest hp hu
          · cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hu] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨kdist_concatP _ hrest, kdist_insertNP hp⟩

/-- **A step never gives an id back.** -/
theorem stepP_drawn_ge {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : stepP pol aux s = .continue s') :
    s.su.drawn ≤ s'.su.drawn := by
  simp only [stepP, State.log] at h
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
        exact Nat.le_refl _
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact Nat.le_refl _
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact Nat.le_refl _
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact Nat.le_refl _
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact (learnPartitions_drawn_ge hdj hcse hlp : s.su.drawn ≤ su2.drawn)

/-- **The step invents no label.**  `stepP_refines_all`'s hypotheses are the shipped flags and
L3's supply invariant, both of which travel along a run (`reaches_invariants`). -/
theorem stepP_concSub {L : Finset Label} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (hcs : ConcSub L (sys s)) (h : stepP pol aux s = .continue s') : ConcSub L (sys s') :=
  LoopRun.concSub (stepP_refines_all hw hem hdj hcse hok hfr h) hcs

/-! ## 3. The RUN under a policy: reachability, runs, termination

`Reaches`, `Runs` and `Terminates` are defined in terms of `step`/`run`.  Their policy forms
thread the auxiliary state, because `stepP` reads it: `ReachesP pol a₀ s₀ b t` says `t`, with
auxiliary state `b`, is reached from `s₀` with auxiliary state `a₀`.  Everything downstream is
the original with ONE extra binder, for the auxiliary state at the reached configuration. -/

/-- `Refuted.Reaches` under a policy: `t` is reached from `s0` by `continue` steps of
`stepP pol`, with the auxiliary state threaded exactly as `runP` threads it. -/
inductive ReachesP (pol : Policy) (a0 : Aux) (s0 : State) : Aux → State → Prop
  | refl : ReachesP pol a0 s0 a0 s0
  | tail {b : Aux} {t u : State} : ReachesP pol a0 s0 b t → stepP pol b t = .continue u →
      ReachesP pol a0 s0 (b.next pol u) u

/-- `NoConc.reaches_trans` for the policy relation. -/
theorem reachesP_trans {a b c : Aux} {s t u : State}
    (h1 : ReachesP pol a s b t) (h2 : ReachesP pol b t c u) : ReachesP pol a s c u := by
  induction h2 with
  | refl => exact h1
  | tail _ hstep ih => exact ih.tail hstep

/-- `Cycle.Runs` under a policy: `n` `continue` steps of `stepP pol`. -/
def RunsP (pol : Policy) : Nat → Aux → State → Aux → State → Prop
  | 0, a, s, b, t => a = b ∧ s = t
  | n + 1, a, s, b, t => ∃ u, stepP pol a s = .continue u ∧ RunsP pol n (a.next pol u) u b t

/-- `Order.Terminates` under a policy. -/
def TerminatesP (pol : Policy) (a : Aux) (s : State) : Prop := ∃ n : Nat, Finished (runP pol a s n)

/-- `Budget.TerminatesB` for the driver the replay runs. -/
def TerminatesBP (pol : Policy) (d0 b : Nat) (a : Aux) (s : State) : Prop :=
  ∃ n : Nat, Finished (runSP pol d0 b a s n)

/-- `Cycle.Runs.run_eq` for the policy run. -/
theorem RunsP.run_eq : ∀ (n : Nat) {a : Aux} {s : State} {b : Aux} {t : State},
    RunsP pol n a s b t → ∀ m, runP pol a s (n + m) = runP pol b t m
  | 0, a, s, b, t, h, m => by
    simp only [RunsP] at h
    obtain ⟨rfl, rfl⟩ := h
    simp
  | n + 1, a, s, b, t, h, m => by
    obtain ⟨u, hstep, hrest⟩ := h
    have hnm : n + 1 + m = (n + m) + 1 := by omega
    rw [hnm]
    simp only [runP, hstep]
    exact RunsP.run_eq n hrest m

/-- `VocFix.runs_snoc` for the policy run. -/
theorem runsP_snoc : ∀ {n : Nat} {a b : Aux} {s t u : State},
    RunsP pol n a s b t → stepP pol b t = .continue u → RunsP pol (n + 1) a s (b.next pol u) u
  | 0, a, b, s, t, u, h, hst => by
    simp only [RunsP] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨u, hst, rfl, rfl⟩
  | n + 1, a, b, s, t, u, h, hst => by
    obtain ⟨w, hstep, hrest⟩ := h
    exact ⟨w, hstep, runsP_snoc hrest hst⟩

/-- `VocFix.runs_of_reaches` for the policy run. -/
theorem runsP_of_reachesP {a b : Aux} {s t : State} (h : ReachesP pol a s b t) :
    ∃ n, RunsP pol n a s b t := by
  induction h with
  | refl => exact ⟨0, rfl, rfl⟩
  | @tail b0 t0 u0 _ hstep ih =>
    obtain ⟨n, hn⟩ := ih
    exact ⟨n + 1, runsP_snoc hn hstep⟩

/-- `VocFix.terminates_of_runs` for the policy run. -/
theorem terminatesP_of_runsP {n : Nat} {a b : Aux} {s t : State} (h : RunsP pol n a s b t)
    (ht : TerminatesP pol b t) : TerminatesP pol a s := by
  obtain ⟨m, hm⟩ := ht
  exact ⟨n + m, by rw [h.run_eq n m]; exact hm⟩

/-- **Termination transports backwards along `ReachesP`.** -/
theorem terminatesP_of_reachesP {a b : Aux} {s t : State} (h : ReachesP pol a s b t)
    (ht : TerminatesP pol b t) : TerminatesP pol a s := by
  obtain ⟨n, hn⟩ := runsP_of_reachesP h
  exact terminatesP_of_runsP hn ht

/-! ## 4. The invariants along a policy run -/

/-- `NoConc.reaches_wf` for the policy relation. -/
theorem reachesP_wf {a b : Aux} {s t : State} (hw : Wf s) (hr : ReachesP pol a s b t) : Wf t := by
  induction hr with
  | refl => exact hw
  | tail _ hstep ih => exact stepP_wf ih hstep

/-- `NoConc.reaches_envNodup` for the policy relation. -/
theorem reachesP_envNodup {a b : Aux} {s t : State} (hn : EnvNodup s)
    (hr : ReachesP pol a s b t) : EnvNodup t := by
  induction hr with
  | refl => exact hn
  | tail _ hstep ih => exact stepP_envNodup ih hstep

/-- `VocFix.reaches_flags_eq` for the policy relation. -/
theorem reachesP_flags_eq {a b : Aux} {s t : State} (hr : ReachesP pol a s b t) :
    t.flags = s.flags := by
  induction hr with
  | refl => rfl
  | tail _ hstep ih => rw [stepP_flags hstep, ih]

/-- `Supply.reaches_invariants` for the policy relation. -/
theorem reachesP_invariants {a b : Aux} {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hr : ReachesP pol a s b t) :
    t.flags.disjRule = false ∧ t.flags.cseMints = false ∧ SupOk t.su ∧
      SupFresh t.su (sys t) ∧ QueueHygiene t := by
  induction hr with
  | refl => exact ⟨hdj, hcse, hok, hfr, h0⟩
  | tail hr hst ih =>
    obtain ⟨hdj1, hcse1, hok1, hfr1, hh1⟩ := ih
    obtain ⟨hok2, -, hfr2⟩ := stepP_supFresh hdj1 hcse1 hok1 hfr1 hst
    have hfl := stepP_flags hst
    exact ⟨by rw [hfl]; exact hdj1, by rw [hfl]; exact hcse1, hok2, hfr2,
      stepP_queueHygiene hdj1 hok1 hfr1 hh1 hst⟩

/-- `VocFix.reaches_concSub` for the policy relation. -/
theorem reachesP_concSub {L : Finset Label} {a b : Aux} {s t : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hcs : ConcSub L (sys s)) (hr : ReachesP pol a s b t) :
    ConcSub L (sys t) := by
  induction hr with
  | refl => exact hcs
  | @tail b0 t0 u0 hr0 hstep ih =>
    obtain ⟨hdj0, hcse0, hok0, hfr0, -⟩ := reachesP_invariants hdj hcse hok hfr h0 hr0
    have hem0 : t0.flags.emptyRow = false := by
      rw [reachesP_flags_eq hr0]; exact hem
    exact stepP_concSub (reachesP_wf hw hr0) hem0 hdj0 hcse0 hok0 hfr0 ih hstep

/-- `VocFix.reaches_kdist` for the policy relation. -/
theorem reachesP_kdist {a b : Aux} {s t : State} (hi : KDist s.incm.elems)
    (hp : KDist s.proc.elems) (hr : ReachesP pol a s b t) :
    KDist t.incm.elems ∧ KDist t.proc.elems := by
  induction hr with
  | refl => exact ⟨hi, hp⟩
  | tail _ hstep ih => exact stepP_kdist' ih.1 ih.2 hstep

/-- `VocFix.reaches_drawn_ge` for the policy relation. -/
theorem reachesP_drawn_ge {a b : Aux} {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hr : ReachesP pol a s b t) : s.su.drawn ≤ t.su.drawn := by
  induction hr with
  | refl => exact Nat.le_refl _
  | @tail b0 t0 u0 hr0 hstep ih =>
    have hfl := reachesP_flags_eq hr0
    exact le_trans ih (stepP_drawn_ge (by rw [hfl]; exact hdj) (by rw [hfl]; exact hcse) hstep)

/-! ## 5. Termination reduced to the four bounds -/

/-- `VocFix.terminates_of_bounds4_aux` for the policy run. -/
theorem terminatesP_of_bounds4_aux {P Q E R : Nat} {V : Finset Var} {L : Finset Label} :
    ∀ (n : Nat) (a : Aux) (s : State), measure4 P Q E R V L s ≤ n →
    (∀ b t, ReachesP pol a s b t → Wf t) → (∀ b t, ReachesP pol a s b t → InVoc V t) →
    (∀ b t, ReachesP pol a s b t → ConcSub L (sys t)) →
    (∀ b t, ReachesP pol a s b t → (rowSet V L t).card ≤ R) →
    (∀ b t, ReachesP pol a s b t → (procSys t).card ≤ P) →
    (∀ b t, ReachesP pol a s b t → t.incm.elems.length ≤ Q) →
    (∀ b t, ReachesP pol a s b t → t.env.binds.length ≤ E) →
    Finished (runP pol a s (n + 1))
  | 0, a, s, hm, hw, hv, hcs, hr, hp, hq, he => by
    simp only [runP]
    cases hst : stepP pol a s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      exfalso
      have := measureP4_lt (hw a s ReachesP.refl) (hv a s ReachesP.refl)
        (hcs a s ReachesP.refl) (hr _ s' (ReachesP.refl.tail hst))
        (hp _ s' (ReachesP.refl.tail hst)) (hq _ s' (ReachesP.refl.tail hst))
        (he _ s' (ReachesP.refl.tail hst)) hst
      omega
  | n + 1, a, s, hm, hw, hv, hcs, hr, hp, hq, he => by
    simp only [runP]
    cases hst : stepP pol a s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      have hlt := measureP4_lt (hw a s ReachesP.refl) (hv a s ReachesP.refl)
        (hcs a s ReachesP.refl) (hr _ s' (ReachesP.refl.tail hst))
        (hp _ s' (ReachesP.refl.tail hst)) (hq _ s' (ReachesP.refl.tail hst))
        (he _ s' (ReachesP.refl.tail hst)) hst
      refine terminatesP_of_bounds4_aux n (a.next pol s') s' (by omega)
        (fun b t ht => hw b t (reachesP_trans (ReachesP.refl.tail hst) ht))
        (fun b t ht => hv b t (reachesP_trans (ReachesP.refl.tail hst) ht))
        (fun b t ht => hcs b t (reachesP_trans (ReachesP.refl.tail hst) ht))
        (fun b t ht => hr b t (reachesP_trans (ReachesP.refl.tail hst) ht))
        (fun b t ht => hp b t (reachesP_trans (ReachesP.refl.tail hst) ht))
        (fun b t ht => hq b t (reachesP_trans (ReachesP.refl.tail hst) ht))
        (fun b t ht => he b t (reachesP_trans (ReachesP.refl.tail hst) ht))

/-- `VocFix.terminates_of_bounds4` for the policy run. -/
theorem terminatesP_of_bounds4 {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {a : Aux}
    {s : State}
    (hw : ∀ b t, ReachesP pol a s b t → Wf t) (hv : ∀ b t, ReachesP pol a s b t → InVoc V t)
    (hcs : ∀ b t, ReachesP pol a s b t → ConcSub L (sys t))
    (hr : ∀ b t, ReachesP pol a s b t → (rowSet V L t).card ≤ R)
    (hp : ∀ b t, ReachesP pol a s b t → (procSys t).card ≤ P)
    (hq : ∀ b t, ReachesP pol a s b t → t.incm.elems.length ≤ Q)
    (he : ∀ b t, ReachesP pol a s b t → t.env.binds.length ≤ E) : TerminatesP pol a s :=
  ⟨measure4 P Q E R V L s + 1,
    terminatesP_of_bounds4_aux (measure4 P Q E R V L s) a s (le_refl _) hw hv hcs hr hp hq he⟩

/-! ## 6. The vocabulary-fixed fragment, under a policy -/

/-- `VocFix.VocFixed` under a policy. -/
def VocFixedP (pol : Policy) (V : Finset Var) (a : Aux) (s : State) : Prop :=
  ∀ b t, ReachesP pol a s b t → InVoc V t

/-- `VocFix.NoDraw` under a policy. -/
def NoDrawP (pol : Policy) (a : Aux) (s : State) : Prop :=
  ∀ b t t', ReachesP pol a s b t → stepP pol b t = .continue t' → t'.su.drawn = t.su.drawn

/-- `VocFix.vocFixed_of_noDraw` under a policy. -/
theorem vocFixedP_of_noDraw {a : Aux} {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : NoDrawP pol a s) :
    VocFixedP pol (allVars (sys s)) a s := by
  intro b t ht
  induction ht with
  | refl => exact inVoc_self s
  | @tail b0 t0 u0 hr0 hstep ih =>
    have hfl := reachesP_flags_eq hr0
    exact stepP_inVoc_noDraw (by rw [hfl]; exact hdj) (by rw [hfl]; exact hcse) ih hstep
      (h b0 t0 u0 hr0 hstep)

/-- **`Terminates` ON THE VOCABULARY-FIXED FRAGMENT, UNDER ANY POLICY**, with an explicit
bound.  `VocFix.vocFixed_terminates` for `runP`. -/
theorem vocFixedP_terminates {V : Finset Var} {L : Finset Label} {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixedP pol V a s) : TerminatesP pol a s := by
  have hcsr : ∀ b t, ReachesP pol a s b t → ConcSub L (sys t) :=
    fun b t ht => reachesP_concSub hw hem hdj hcse hok hfr hqh hcs ht
  exact terminatesP_of_bounds4
    (P := V.card * 2 ^ V.card * 2 ^ L.card) (Q := V.card * 2 ^ V.card * 2 ^ L.card)
    (E := V.card) (R := V.card * 2 ^ L.card)
    (fun b t ht => reachesP_wf hw ht) hvf hcsr
    (fun _ _ _ => rowSet_card_le)
    (fun b t ht => procSys_card_leL (hvf b t ht) (hcsr b t ht))
    (fun b t ht => kdist_length_leL (reachesP_wf hw ht) (hvf b t ht) (hcsr b t ht)
      (fun p hp => List.mem_append_left _ hp) (reachesP_kdist hki hkp ht).1)
    (fun b t ht => env_len_le_card (hvf b t ht) (reachesP_envNodup hnd ht))

/-- The same, as the explicit FUEL. -/
theorem vocFixedP_run {V : Finset Var} {L : Finset Label} {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixedP pol V a s) :
    Finished (runP pol a s (measure4 (V.card * 2 ^ V.card * 2 ^ L.card)
      (V.card * 2 ^ V.card * 2 ^ L.card) V.card (V.card * 2 ^ L.card) V L s + 1)) := by
  have hcsr : ∀ b t, ReachesP pol a s b t → ConcSub L (sys t) :=
    fun b t ht => reachesP_concSub hw hem hdj hcse hok hfr hqh hcs ht
  exact terminatesP_of_bounds4_aux _ a s (le_refl _)
    (fun b t ht => reachesP_wf hw ht) hvf hcsr
    (fun _ _ _ => rowSet_card_le)
    (fun b t ht => procSys_card_leL (hvf b t ht) (hcsr b t ht))
    (fun b t ht => kdist_length_leL (reachesP_wf hw ht) (hvf b t ht) (hcsr b t ht)
      (fun p hp => List.mem_append_left _ hp) (reachesP_kdist hki hkp ht).1)
    (fun b t ht => env_len_le_card (hvf b t ht) (reachesP_envNodup hnd ht))

/-- **A solve on which the policy loop draws no id TERMINATES.** -/
theorem noDrawP_terminates {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) (h : NoDrawP pol a s) :
    TerminatesP pol a s :=
  vocFixedP_terminates (L := labelsOf (sys s)) hem hdj hcse hw hnd hok hfr hqh
    (concSub_self s) hki hkp (vocFixedP_of_noDraw hdj hcse h)

/-! ## 7. The tail condition, and the CARDINAL one -/

/-- `VocFix.EventuallyNoDraw` under a policy. -/
def EventuallyNoDrawP (pol : Policy) (a : Aux) (s : State) : Prop :=
  ∃ b t, ReachesP pol a s b t ∧ NoDrawP pol b t

/-- **A policy solve that stops drawing TERMINATES.** -/
theorem terminatesP_of_eventuallyNoDrawP {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : EventuallyNoDrawP pol a s) : TerminatesP pol a s := by
  obtain ⟨b, t, hr, hnd0⟩ := h
  obtain ⟨hdj', hcse', hok', hfr', hqh'⟩ := reachesP_invariants hdj hcse hok hfr hqh hr
  obtain ⟨hki', hkp'⟩ := reachesP_kdist hki hkp hr
  have hfl := reachesP_flags_eq hr
  exact terminatesP_of_reachesP hr
    (noDrawP_terminates (by rw [hfl]; exact hem) hdj' hcse' (reachesP_wf hw hr)
      (reachesP_envNodup hnd hr) hok' hfr' hqh' hki' hkp' hnd0)

/-- **A DIVERGENT policy solve draws at cofinally many steps.** -/
theorem drawsP_cofinally_of_not_terminatesP {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ TerminatesP pol a s) : ∀ b t, ReachesP pol a s b t → ¬ NoDrawP pol b t :=
  fun b t hr hnd0 =>
    h (terminatesP_of_eventuallyNoDrawP hem hdj hcse hw hnd hok hfr hqh hki hkp ⟨b, t, hr, hnd0⟩)

/-- ...and it has no fixed vocabulary. -/
theorem not_vocFixedP_of_not_terminatesP {L : Finset Label} {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ TerminatesP pol a s) : ∀ V : Finset Var, ¬ VocFixedP pol V a s :=
  fun _V hvf => h (vocFixedP_terminates hem hdj hcse hw hnd hok hfr hqh hcs hki hkp hvf)

/-- **A divergent policy solve draws UNBOUNDEDLY many ids.** -/
theorem drawnP_unbounded_of_not_terminatesP {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ TerminatesP pol a s) :
    ∀ n : Nat, ∃ b t, ReachesP pol a s b t ∧ s.su.drawn + n ≤ t.su.drawn := by
  intro n
  induction n with
  | zero => exact ⟨a, s, ReachesP.refl, by omega⟩
  | succ k ih =>
    obtain ⟨b, t, hrt, hdt⟩ := ih
    obtain ⟨hdj', hcse', hok', hfr', hqh'⟩ := reachesP_invariants hdj hcse hok hfr hqh hrt
    have hfl := reachesP_flags_eq hrt
    obtain ⟨hki', hkp'⟩ := reachesP_kdist hki hkp hrt
    have hnt : ¬ TerminatesP pol b t := fun ht => h (terminatesP_of_reachesP hrt ht)
    have hcof := drawsP_cofinally_of_not_terminatesP (by rw [hfl]; exact hem) hdj' hcse'
      (reachesP_wf hw hrt) (reachesP_envNodup hnd hrt) hok' hfr' hqh' hki' hkp' hnt b t
      ReachesP.refl
    simp only [NoDrawP, not_forall] at hcof
    obtain ⟨c, u, u', hru, hstep, hne⟩ := hcof
    have h1 : t.su.drawn ≤ u.su.drawn := reachesP_drawn_ge hdj' hcse' hru
    have hflu := reachesP_flags_eq hru
    have h2 : u.su.drawn ≤ u'.su.drawn := stepP_drawn_ge
      (by rw [hflu, hfl]; exact hdj) (by rw [hflu, hfl]; exact hcse) hstep
    exact ⟨c.next pol u', u', reachesP_trans hrt (hru.tail hstep), by omega⟩

/-- **A policy solve that draws BOUNDEDLY many ids terminates.**  `VocFix
.terminates_of_drawsAtMost` for `runP`, and the theorem the draw budget converts into
termination. -/
theorem terminatesP_of_drawsAtMost {k : Nat} {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ∀ b t, ReachesP pol a s b t → t.su.drawn ≤ s.su.drawn + k) : TerminatesP pol a s := by
  by_contra hnt
  obtain ⟨b, t, hrt, hdt⟩ := drawnP_unbounded_of_not_terminatesP hem hdj hcse hw hnd hok hfr hqh
    hki hkp hnt (k + 1)
  have := h b t hrt
  omega

/-! ## 8. The DECIDABLE per-solve check -/

/-- `VocFix.NoDrawB` under a policy: run the policy loop for `n` dequeues, checking at each
that the supply did not move. -/
def NoDrawBP (pol : Policy) : Nat → Aux → State → Bool
  | 0, a, s => match stepP pol a s with
    | .continue _ => false
    | _ => true
  | n + 1, a, s => match stepP pol a s with
    | .continue s' => (s'.su.drawn == s.su.drawn) && NoDrawBP pol n (a.next pol s') s'
    | _ => true

theorem noDrawBP_reaches : ∀ {n : Nat} {a b : Aux} {s t : State}, NoDrawBP pol n a s = true →
    ReachesP pol a s b t → ∃ m, NoDrawBP pol m b t = true := by
  intro n a b s t h hr
  induction hr with
  | refl => exact ⟨n, h⟩
  | @tail b0 t0 u0 _ hstep ih =>
    obtain ⟨m, hm⟩ := ih
    cases m with
    | zero => rw [NoDrawBP, hstep] at hm; exact absurd hm (by simp)
    | succ k =>
      rw [NoDrawBP, hstep] at hm
      simp only [Bool.and_eq_true] at hm
      exact ⟨k, hm.2⟩

/-- **The check is sound.** -/
theorem noDrawP_of_noDrawBP {n : Nat} {a : Aux} {s : State} (h : NoDrawBP pol n a s = true) :
    NoDrawP pol a s := by
  intro b t t' hr hst
  obtain ⟨m, hm⟩ := noDrawBP_reaches h hr
  cases m with
  | zero => rw [NoDrawBP, hst] at hm; exact absurd hm (by simp)
  | succ k =>
    rw [NoDrawBP, hst] at hm
    simp only [Bool.and_eq_true, beq_iff_eq] at hm
    exact hm.1

/-! ## 9. THE BUDGET, under a policy: every solve stops

`Budget.budget_terminates` for the driver the replay actually runs.  Two reductions, the
analogues of `Budget.terminatesB_of_finished` and `terminatesB_of_over`, and then the same
`by_cases` on whether the cap is ever exceeded.

ONE DIFFERENCE, stated: `runBud` tests `d0 + b < s.su.drawn`, while `runSP` tests
`b != 0 && d0 + b < s.su.drawn` — `b = 0` is the budget OFF.  So `budgetP_terminates` carries
`hb0 : b ≠ 0`, which `budget_terminates` does not need.  That is a property of the driver, not
of the policy: at `b = 0` no cap is being asked for. -/

/-- A policy run that finishes makes the budgeted driver finish, in no more dequeues. -/
theorem terminatesBP_of_finished {d0 b : Nat} : ∀ (n : Nat) (a : Aux) (s : State),
    s.flags.rowSoundBare = false → Finished (runP pol a s n) → Finished (runSP pol d0 b a s n)
  | 0, a, s, _, h => by simp only [runP, Finished] at h
  | n + 1, a, s, hrs, h => by
    simp only [runP] at h
    by_cases hb : b != 0 && d0 + b < s.su.drawn
    · rw [runSP, if_pos hb]; trivial
    · rw [runSP, if_neg hb, stepSP_of_rowSound_off hrs]
      cases hst : stepP pol a s with
      | done s0 => rw [hst] at h; exact h
      | died m s0 => rw [hst] at h; exact h
      | «continue» s0 =>
        rw [hst] at h
        exact terminatesBP_of_finished n _ s0 (by rw [stepP_flags hst]; exact hrs) h

/-- ...and a policy run that reaches a state over the cap makes the budgeted driver DIE. -/
theorem terminatesBP_of_over {d0 b : Nat} (hb0 : b ≠ 0) :
    ∀ (k : Nat) {a c : Aux} {s t : State}, s.flags.rowSoundBare = false →
    RunsP pol k a s c t → d0 + b < t.su.drawn → TerminatesBP pol d0 b a s
  | 0, a, c, s, t, _, hr, hd => by
    simp only [RunsP] at hr
    obtain ⟨rfl, rfl⟩ := hr
    exact ⟨1, by rw [runSP, if_pos (by simp [hb0, hd])]; trivial⟩
  | k + 1, a, c, s, t, hrs, hr, hd => by
    obtain ⟨s0, hstep, hrest⟩ := hr
    by_cases hb : b != 0 && d0 + b < s.su.drawn
    · exact ⟨1, by rw [runSP, if_pos hb]; trivial⟩
    · obtain ⟨n, hn⟩ := terminatesBP_of_over hb0 k (by rw [stepP_flags hstep]; exact hrs) hrest hd
      exact ⟨n + 1, by
        rw [runSP, if_neg hb, stepSP_of_rowSound_off hrs, hstep]
        exact hn⟩

/-- **`budgetP_terminates`: under a draw budget EVERY solve stops, UNDER ANY POLICY.**  The
hypotheses are `terminatesP_of_drawsAtMost`'s — the three shipped flag settings and the
invariants L3/L5 discharge at an initial state — plus S2's layer (i) off and a nonzero cap.
The two cases are the two ways a budget can end a run:

* the policy loop never exceeds the cap, so it draws boundedly many ids, so it TERMINATES
  (`terminatesP_of_drawsAtMost` with `k := b`), and the budgeted driver follows it;
* some reachable configuration exceeds the cap, and then the check fires at or before it. -/
theorem budgetP_terminates {b : Nat} {a : Aux} {s : State} (hb0 : b ≠ 0)
    (hrs : s.flags.rowSoundBare = false)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) :
    TerminatesBP pol s.su.drawn b a s := by
  by_cases hbd : ∀ c t, ReachesP pol a s c t → t.su.drawn ≤ s.su.drawn + b
  · obtain ⟨n, hn⟩ := terminatesP_of_drawsAtMost hem hdj hcse hw hnd hok hfr hqh hki hkp hbd
    exact ⟨n, terminatesBP_of_finished n a s hrs hn⟩
  · push Not at hbd
    obtain ⟨c, t, hrt, hgt⟩ := hbd
    obtain ⟨k, hk⟩ := runsP_of_reachesP hrt
    exact terminatesBP_of_over hb0 k hrs hk hgt

/-- The corollary at a solve's own initial state, where `EnvNodup`, both `KDist`s and
`QueueHygiene` are free: **every solve run under a policy AND a draw budget stops.** -/
theorem budgetP_terminates_of_buildQueue {b : Nat} {a : Aux} {cs : List CsItem} {su : Sup}
    {q : PQueue} {su' : Sup} {fl : Flags} {ns : Names} {site : String} {tr : List String}
    {z : Nat} (hb0 : b ≠ 0) (hq : buildQueue cs su = .ok (q, su'))
    (hrs : fl.rowSoundBare = false)
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z))) :
    TerminatesBP pol su'.drawn b a (initState q su' tr fl ns site z) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  exact budgetP_terminates hb0 hrs hem hdj hcse hw (envNodup_initial fl ns site su' tr z) hok hfr
    (queueHygiene_of_env_nil rfl) (kdist_ofList ps) (by simp [initState, PQueue.empty, KDist])

/-! ## 10. NO SILENT WEAKENING: the shipped instances recover the originals -/

/-- At the shipped policy the reachability relation is `Refuted.Reaches`. -/
theorem reachesP_shipped {a b : Aux} {s t : State} (h : ReachesP .shipped a s b t) :
    Reaches s t := by
  induction h with
  | refl => exact Reaches.refl s
  | tail _ hstep ih => exact ih.tail hstep

/-- ...and back, threading any auxiliary state. -/
theorem reachesP_of_reaches (a : Aux) {s t : State} (h : Reaches s t) :
    ∃ b, ReachesP .shipped a s b t := by
  induction h with
  | refl => exact ⟨a, ReachesP.refl⟩
  | @tail t0 u0 _ hstep ih =>
    obtain ⟨b, hb⟩ := ih
    exact ⟨b.next .shipped u0, hb.tail hstep⟩

/-- At the shipped policy termination is `Order.Terminates`. -/
theorem terminatesP_shipped (a : Aux) (s : State) : TerminatesP .shipped a s ↔ Terminates s := by
  constructor
  · rintro ⟨n, hn⟩; exact ⟨n, by rw [← runP_shipped a s n]; exact hn⟩
  · rintro ⟨n, hn⟩; exact ⟨n, by rw [runP_shipped a s n]; exact hn⟩

/-- **`terminates_of_drawsAtMost` RECOVERED**: the policy theorem at `pol := .shipped` is the
original, with no bridging lemma but the two above. -/
theorem terminatesP_of_drawsAtMost_recovers {k : Nat} (a : Aux) {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ∀ t, Reaches s t → t.su.drawn ≤ s.su.drawn + k) : Terminates s :=
  (terminatesP_shipped a s).mp
    (terminatesP_of_drawsAtMost hem hdj hcse hw hnd hok hfr hqh hki hkp
      (fun _b t ht => h t (reachesP_shipped ht)))

/-- **`vocFixed_terminates` RECOVERED** the same way. -/
theorem vocFixedP_terminates_recovers {V : Finset Var} {L : Finset Label} (a : Aux) {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixed V s) : Terminates s :=
  (terminatesP_shipped a s).mp
    (vocFixedP_terminates hem hdj hcse hw hnd hok hfr hqh hcs hki hkp
      (fun _b t ht => hvf t (reachesP_shipped ht)))

/-- **`step_quadrichotomy` RECOVERED**: the shipped instance is the original statement. -/
theorem stepP_quadrichotomy_recovers (aux : Aux) {s s' : State} (h : step s = .continue s') :
    (IsLearnStepP .shipped aux s ∧ s'.env = s.env ∧ ∀ p ∈ s.proc.elems, p ∈ s'.proc.elems) ∨
    (s'.env.binds.length = s.env.binds.length + 1) ∨
    (s'.env = s.env ∧ s'.proc = s.proc ∧ s'.incm.elems.length + 1 = s.incm.elems.length) ∨
    (IsConcStepP .shipped aux s s' ∧ s'.env = s.env) :=
  stepP_quadrichotomy (pol := .shipped) (aux := aux) h

end Rowpartition.Loop
