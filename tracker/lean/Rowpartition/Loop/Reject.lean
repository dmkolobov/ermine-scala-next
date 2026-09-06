/-
# S1 (B): REJECTION SOUNDNESS — a rejected program is ill-typed

`RefineLearn.run_refutes_all` is contraposed satisfiability-preservation: it takes
`¬ SSat (sys s')` as a HYPOTHESIS and carries it back to the input.  Only the `empty` branch
discharges that hypothesis (`Order.step_died_empty`).  This file discharges it at every other
death site, by extracting the premises of the refutation from the internals of `makeConcrete`
and `learnPartitions` down to "these constraints are members of `sys s`".

`step` can raise exactly seven `Death` messages (`Loop/{Step,Rules}.lean`; `rhsBuild`'s two
errors and `labelClash` are raised by `buildQueue` / `Subst.solve` AROUND the loop, not by
`step`).  The census is about `Death`s, not about crashes: `Constraints.scala:463-464`'s
`graph.sort(lhs)` is a `Map.apply` that would raise `NoSuchElementException`, and the model
totalises it (`Loop/Queue.lean:73`); the Scala invariant that it cannot fire is argued at
`Constraints.scala:407-425` and is not proved here (S1 review Z-10).

| # | message | raised by | branch | verdict |
|---|---|---|---|---|
| 1 | `Fields appear twice in row: …` | `RHS.merge` | `concrete`, `learn` | REFUTATION (`merge_refutes`) |
| 2 | `Infinite row partition for 'v'` | `selfSubstitution` | `learn` | REFUTATION (`selfSubst_refutes`) |
| 3 | `panic: reinstantiated type v to u …` | `instantiate` | `common`, `unify` | UNREACHABLE (`QueueHygiene`) |
| 4 | `Incompatible instantiations of 'v'` | `makeEmpty` | `empty` | REFUTATION (`incompatible_refutes`) |
| 5 | `Cannot unify skolem variable …` | `makeEmpty` | `empty` | NON-REFUTATION (a kinding error) |
| 6 | `panic: reinstantiated type v to ConcreteRho …` | `makeEmpty` | `empty` | UNREACHABLE (`QueueHygiene`) |
| 7 | `Row types failed to unify: …` | `ensureSuperset` | `concrete` | REFUTATION (`ensureSuperset_refutes`) |

Messages 3 and 6 are `instantiateType`'s `die`; `Loop/Hygiene.lean`'s B1 certification proves
they have no path from a hygienic state, and every state `Seed.solve` builds is hygienic.
**SIDE CONDITION for the transfer to the compiler (S1 review Z-6):** hygiene is free at an
initial state only because the MODEL sets `env := {}` (`Loop/Seed.lean:135`).  In the compiler
`SubstEnv.types` is a long-lived mutable map shared across the whole type checker
(`Subst.scala:182-188`) and `Subst.solve` does NOT `substType` its input before `PQueue.build`
(`Subst.scala:1135`; `substType` is applied only at `:1260`), so at the real entry to
`incorporateAll` the environment is generally NOT empty.  "3 and 6 are unreachable" therefore
transfers to the compiler only under the unproved side condition **no input partition mentions
an already-bound variable**.

An EIGHTH `instantiateType` `die` site exists OUTSIDE the loop and outside this census:
`Subst.reduce`'s `instantiateType(v, ConcreteRho(lc, fs))` (`Subst.scala:1079`, dying at
`:184`).  It is the last line of defence for the very shape `Loop/Sound.lean` names as its
hole — `tracker/repro/satterm/seeds/unsat/PANIC-1.json` reaches it at 3/3 id bases — and it is
a PANIC with no source location, not a diagnosable type error (S1 review Z-5).
Message 5 stays: a skolem row variable forced empty is a genuine type error, but the
constraint semantics here treats every row variable as flexible, so the SYSTEM is satisfiable
and the death is not a refutation of it.  `NonRefutation` below is therefore the single
skolem message.
-/
import Rowpartition.Loop.Sound

namespace Rowpartition.Loop

open Rowpartition

set_option linter.unusedSimpArgs false

/-! ## 1. Label-set plumbing for the two failure conditions -/

/-- A non-empty `Set` intersection of label sets is a non-empty intersection of index sets. -/
theorem cfs_inter_nonempty {s t : SSet Lbl} (h : (s.inter t).isEmpty = false) :
    (cfs s ∩ cfs t).Nonempty := by
  have hnil : (s.inter t).elems ≠ [] := by
    intro hh; rw [SSet.isEmpty, hh] at h; exact absurd h (by simp)
  obtain ⟨z, hz⟩ := List.exists_mem_of_ne_nil _ hnil
  obtain ⟨hzs, hzt⟩ := SSet.mem_filter_iff.mp hz
  obtain ⟨w, hw, hzw⟩ := List.any_eq_true.mp hzt
  have hzweq : z = w := by simpa [SVal.eq] using hzw
  exact ⟨z.n, Finset.mem_inter.mpr ⟨mem_cfs.mpr ⟨z, hzs, rfl⟩,
    mem_cfs.mpr ⟨w, hw, by rw [← hzweq]⟩⟩⟩

/-- `Set.subsetOf` failing on a COHERENT pool is failure of the index sets to be included. -/
theorem not_cfs_subset {L : List Lbl} (hcoh : LblCoh L) {s t : SSet Lbl}
    (hs : ∀ x ∈ s.elems, x ∈ L) (ht : ∀ x ∈ t.elems, x ∈ L)
    (h : s.subsetOf t = false) : ¬ cfs s ⊆ cfs t := by
  have : ¬ ∀ x ∈ s.elems, t.contains x = true := by
    intro hall
    rw [SSet.subsetOf, List.all_eq_true.mpr hall] at h
    exact absurd h (by simp)
  push Not at this
  obtain ⟨z, hz, hzt⟩ := this
  intro hsub
  obtain ⟨w, hw, hzw⟩ := mem_cfs.mp (hsub (mem_cfs.mpr ⟨z, hz, rfl⟩))
  have : w = z := hcoh w (ht w hw) z (hs z hz) hzw
  exact hzt (List.any_eq_true.mpr ⟨w, hw, by simp [SVal.eq, this]⟩)

/-! ## 2. `RHS.merge` and `ensureSuperset`, as refutations -/

/-- **What `rhsSubstitute` dying MEANS**: the substituted variable really is a part, and the
two concrete parts really do overlap. -/
theorem rhsSubstitute_died {r t : RHS} {v : Nat} {m : String}
    (h : rhsSubstitute r v t = .error m) :
    v ∈ r.abstr.fs ∧ (cfs r.conc ∩ cfs t.conc).Nonempty := by
  simp only [rhsSubstitute, rhsMerge] at h
  split at h
  · rename_i hcv
    refine ⟨SSet.mem_fs.mpr (contains_nat_iff.mp hcv), ?_⟩
    split at h
    · exact absurd h (by simp)
    · rename_i hne
      have hne0 : ((r.erase v).conc.inter t.conc).isEmpty = false := by simpa using hne
      exact cfs_inter_nonempty hne0
  · exact absurd h (by simp)

/-- **Message 1 is a refutation**, at the loop's own terms: the partition being rewritten and
the definition it is rewritten through are both in the system. -/
theorem subst_died_refutes {G : System} {a v : Var} {r t : RHS}
    (h1 : mk a r.abstr.fs (cfs r.conc) ∈ G) (h2 : mk v t.abstr.fs (cfs t.conc) ∈ G)
    (hv : v ∈ r.abstr.fs) (hne : (cfs r.conc ∩ cfs t.conc).Nonempty) : ¬ SSat G :=
  merge_refutes h1 h2 hv hne

/-- **Message 7 is a refutation**: `ensureSuperset` fails exactly when a definition of `v`
carries a label the row `v` is about to be pinned to does not have. -/
theorem ensureSuperset_died {L : List Lbl} (hcoh : LblCoh L) {G : System} {v : Nat}
    {sub sup : SSet Lbl} {S : Finset Var} {m : String}
    (hsubL : ∀ x ∈ sub.elems, x ∈ L) (hsupL : ∀ x ∈ sup.elems, x ∈ L)
    (h1 : mk v ∅ (cfs sup) ∈ G) (h2 : mk v S (cfs sub) ∈ G)
    (h : ensureSuperset sub sup = .error m) : ¬ SSat G := by
  simp only [ensureSuperset] at h
  split at h
  · exact absurd h (by simp)
  · rename_i hns
    exact ensureSuperset_refutes h1 h2
      (not_cfs_subset hcoh hsubL hsupL (by simpa using hns))

/-! ## 3. Message 1 in the `concrete` branch: from `subPartitions` up to `step` -/

/-- **`subPartitions` dies only at a real overlap.**  The partition whose rewriting failed is
in one of the two queues, `v` really is one of its parts, and its concrete part really does
meet the substituted one — which is `merge_refutes`' premise set. -/
theorem subPartitions_died_refutes {G : System} {v : Nat} {sub : RHS} {proc incm : PQueue}
    {m : String}
    (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G) (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G)
    (hsubG : mk v sub.abstr.fs (cfs sub.conc) ∈ G)
    (h : subPartitions v sub proc incm = .error m) : ¬ SSat G := by
  simp only [subPartitions] at h
  set F : Except String (SSet LPart) → LPart → Except String (SSet LPart) := fun acc r => do
    let s ← acc
    if r.rhs.contains v then
      let (nrhs, es) ← rhsSubstitute r.rhs v sub
      let s := s.concat (es.map (fun w => (⟨w, RHS.empty, some .deDuplication⟩ : LPart)))
      pure (s.incl ⟨r.lhs, nrhs, r.inf⟩)
    else pure s with hF
  have hf : ∀ (acc : Except String (SSet LPart)) (x : LPart),
      (∀ m', rhsSubstitute x.rhs v sub ≠ .error m') → (∃ b, acc = .ok b) →
      ∃ b, F acc x = .ok b := by
    intro acc x hx hacc
    obtain ⟨a, rfl⟩ := hacc
    rw [hF]
    simp only [bind, Except.bind]
    split
    · cases hrs : rhsSubstitute x.rhs v sub with
      | error m' => exact absurd hrs (hx m')
      | ok w => exact ⟨_, rfl⟩
    · exact ⟨a, rfl⟩
  by_cases hall : ∀ x ∈ proc.elems ++ (incm.filter (fun p => p.lhs != v)).elems,
      ∀ m', rhsSubstitute x.rhs v sub ≠ .error m'
  · exfalso
    obtain ⟨b0, hb0⟩ := foldl_except_ok_of_all hf proc.elems
      (fun x hx => hall x (List.mem_append_left _ hx)) (.ok SSet.empty) ⟨SSet.empty, rfl⟩
    obtain ⟨b1, hb1⟩ := foldl_except_ok_of_all hf (incm.filter (fun p => p.lhs != v)).elems
      (fun x hx => hall x (List.mem_append_right _ hx)) _ ⟨b0, hb0⟩
    rw [hb1] at h
    exact absurd h (by simp)
  · push Not at hall
    obtain ⟨x, hx, m', hm'⟩ := hall
    obtain ⟨hvx, hne⟩ := rhsSubstitute_died hm'
    have hxG : x.toConstraint ∈ G := by
      rcases List.mem_append.mp hx with hx' | hx'
      · exact hpG x hx'
      · exact hiG x (List.mem_of_mem_filter hx')
    rw [toConstraint_eq] at hxG
    exact subst_died_refutes hxG hsubG hvx hne

/-- **`destructiveSub` dies only at a real overlap**: either rewriting through the substitution
it was given, or through one of `v`'s own definitions. -/
theorem destructiveSub_died_refutes {G : System} {v : Nat} {rhs : RHS} {incm proc : PQueue}
    {m : String}
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hrhsG : mk v rhs.abstr.fs (cfs rhs.conc) ∈ G)
    (h : destructiveSub v rhs incm proc = .error m) : ¬ SSat G := by
  simp only [destructiveSub] at h
  set pps := (proc.partition (fun p => p.lhs == v)).1 with hpps
  set procd := (proc.partition (fun p => p.lhs == v)).2 with hprocd
  set qps := (incm.partition (fun p => p.lhs == v)).1 with hqps
  set incmg := (incm.partition (fun p => p.lhs == v)).2 with hincmg
  have hprocdG : ∀ x ∈ procd.elems, x.toConstraint ∈ G := fun x hx => hpG x
    (List.mem_of_mem_filter hx)
  have hincmgG : ∀ x ∈ incmg.elems, x.toConstraint ∈ G := fun x hx => hiG x
    (List.mem_of_mem_filter hx)
  have hdefG : ∀ r' ∈ ((pps.concat qps).map (fun p => p.rhs)).elems,
      mk v r'.abstr.fs (cfs r'.conc) ∈ G := by
    intro r' hr'
    obtain ⟨p, hp, rfl⟩ := SSet.mem_map hr'
    rcases SSet.mem_concat hp with hp' | hp'
    · have hmem := List.mem_filter.mp (List.mem_reverse.mp (SSet.mem_ofList hp'))
      have := hpG p hmem.1
      rw [toConstraint_eq, (by simpa using hmem.2 : p.lhs = v)] at this
      exact this
    · have hmem := List.mem_filter.mp (List.mem_reverse.mp (SSet.mem_ofList hp'))
      have := hiG p hmem.1
      rw [toConstraint_eq, (by simpa using hmem.2 : p.lhs = v)] at this
      exact this
  set F : Except String (SSet LPart) → RHS → Except String (SSet LPart) := fun acc r => do
    let s ← acc
    pure (s.concat (← subPartitions v r procd incmg)) with hF
  have hf : ∀ (acc : Except String (SSet LPart)) (x : RHS),
      (∀ m', subPartitions v x procd incmg ≠ .error m') → (∃ b, acc = .ok b) →
      ∃ b, F acc x = .ok b := by
    intro acc x hx hacc
    obtain ⟨a, rfl⟩ := hacc
    rw [hF]
    simp only [bind, Except.bind]
    cases hsp : subPartitions v x procd incmg with
    | error m' => exact absurd hsp (hx m')
    | ok T => exact ⟨_, rfl⟩
  cases hbase : subPartitions v rhs procd incmg with
  | error m' =>
    exact subPartitions_died_refutes hprocdG hincmgG hrhsG hbase
  | ok base =>
    by_cases hall : ∀ x ∈ ((pps.concat qps).map (fun p => p.rhs)).elems,
        ∀ m', subPartitions v x procd incmg ≠ .error m'
    · exfalso
      obtain ⟨b1, hb1⟩ := foldl_except_ok_of_all hf
        ((pps.concat qps).map (fun p => p.rhs)).elems hall _ ⟨base, hbase⟩
      rw [hb1] at h
      simp only [bind, Except.bind] at h
      exact absurd h (by simp)
    · push Not at hall
      obtain ⟨x, hx, m', hm'⟩ := hall
      exact subPartitions_died_refutes hprocdG hincmgG (hdefG x hx) hm'

/-- **Every death of `makeConcrete` is a refutation**: message 7 from `ensureSuperset`, message
1 from `destructiveSub`. -/
theorem makeConcrete_died {L : List Lbl} (hcoh : LblCoh L) {G : System} {v : Nat}
    {fs : SSet Lbl} {incm proc : PQueue} {m : String}
    (hiOk : QOk L incm) (hpOk : QOk L proc) (hfsOk : COk L fs)
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hconG : mk v ∅ (cfs fs) ∈ G)
    (h : makeConcrete v fs incm proc = .error m) : ¬ SSat G := by
  simp only [makeConcrete] at h
  set rhss := (((SSet.ofList proc.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)).concat
      (((SSet.ofList incm.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)) with hrhss
  have hrhssWit : ∀ r ∈ rhss.elems, ∃ p, (p ∈ proc.elems ∨ p ∈ incm.elems) ∧
      p.lhs = v ∧ p.rhs = r := by
    intro r hr
    rcases SSet.mem_concat hr with hr' | hr'
    · obtain ⟨p, hp, rfl⟩ := SSet.mem_map hr'
      exact ⟨p, Or.inl (SSet.mem_ofList (SSet.mem_filter hp)),
        by simpa using (SSet.mem_filter_iff.mp hp).2, rfl⟩
    · obtain ⟨p, hp, rfl⟩ := SSet.mem_map hr'
      exact ⟨p, Or.inr (SSet.mem_ofList (SSet.mem_filter hp)),
        by simpa using (SSet.mem_filter_iff.mp hp).2, rfl⟩
  have hrhssG : ∀ r ∈ rhss.elems, mk v r.abstr.fs (cfs r.conc) ∈ G := by
    intro r hr
    obtain ⟨p, hp, hlhs, rfl⟩ := hrhssWit r hr
    rcases hp with hp' | hp'
    · have := hpG p hp'; rwa [toConstraint_eq, hlhs] at this
    · have := hiG p hp'; rwa [toConstraint_eq, hlhs] at this
  have hrhssOk : ∀ r ∈ rhss.elems, ROk L r := by
    intro r hr
    obtain ⟨p, hp, -, rfl⟩ := hrhssWit r hr
    rcases hp with hp' | hp'
    · exact (hpOk p hp').rhsOk
    · exact (hiOk p hp').rhsOk
  have hf : ∀ (acc : Except String Unit) (r : RHS),
      (∀ m', ensureSuperset r.conc fs ≠ .error m') → (∃ b, acc = .ok b) →
      ∃ b, (do let _ ← acc; ensureSuperset r.conc fs) = .ok b := by
    intro acc r hr hacc
    obtain ⟨a, rfl⟩ := hacc
    simp only [bind, Except.bind]
    cases hes : ensureSuperset r.conc fs with
    | error m' => exact absurd hes (hr m')
    | ok u => exact ⟨u, rfl⟩
  by_cases hall : ∀ r ∈ rhss.elems, ∀ m', ensureSuperset r.conc fs ≠ .error m'
  · obtain ⟨b0, hb0⟩ := foldl_except_ok_of_all hf rhss.elems hall (.ok ()) ⟨(), rfl⟩
    rw [hb0] at h
    simp only [bind, Except.bind] at h
    cases hds : destructiveSub v (RHS.ofConcr fs) incm proc with
    | error m' =>
      refine destructiveSub_died_refutes hiG hpG ?_ hds
      exact hconG
    | ok w =>
      obtain ⟨ni, np⟩ := w
      rw [hds] at h
      simp only [bind, Except.bind, pure, Except.pure] at h
      exact absurd h (by simp)
  · push Not at hall
    obtain ⟨r, hr, m', hm'⟩ := hall
    exact ensureSuperset_died hcoh (fun x hx => (hrhssOk r hr).conc.sub x hx)
      (fun x hx => hfsOk.sub x hx) hconG (hrhssG r hr) hm'

/-! ## 4. Message 6 removed: `makeEmpty` at a HYGIENIC state

`Refine.makeEmpty_died` leaves three possibilities — a refutation, the skolem refusal, or the
reinstantiation panic.  `Loop/Hygiene.lean`'s `queueHygiene_binds_unbound` says the dequeued
left-hand side is UNBOUND at a hygienic state, and the panic arm tests exactly that, so at a
hygienic state only two remain.  (The proof is `makeEmpty_died`'s with the panic arm closed by
`hnb`; the fold-error case is repeated because the disjunction `makeEmpty_died` returns cannot
say WHICH arm produced the message.) -/

theorem makeEmpty_died_hyg {G : System} {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {m : String}
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hnb : env.contains v = false)
    (h : makeEmpty ns v incm proc env = .error m) :
    ¬ SSat G ∨ (ns.isSkolem v = true ∧
      m = "Cannot unify skolem variable with empty relation " ++ varStr ns v) := by
  simp only [makeEmpty] at h
  set F : Except String (SSet LPart) → LPart → Except String (SSet LPart) :=
    (fun (acc : Except String (SSet LPart)) (p : LPart) => do
        let s ← acc
        if p.lhs == v then
          if p.rhs.isEmpty then pure s
          else if p.rhs.conc.isEmpty then
            pure (s.concat ((p.rhs.abstr.excl v).map
              (fun w => (⟨w, RHS.empty, some Inference.partitionEmpty⟩ : LPart))))
          else .error ("Incompatible instantiations of '" ++ varStr ns v ++ "'")
        else pure (s.incl ⟨p.lhs, p.rhs.erase v, p.inf⟩)) with hF
  cases hnps : ((incm.partition (fun p => p.involves v)).1.concat
      (proc.partition (fun p => p.involves v)).1).elems.foldl F (.ok SSet.empty) with
  | ok nps =>
    rw [hnps] at h
    simp only [bind, Except.bind] at h
    split at h
    · rename_i hsk
      exact Or.inr ⟨hsk, by rw [Except.error.injEq] at h; exact h.symm⟩
    · rw [if_neg (by simp [hnb])] at h
      exact absurd h (by simp)
  | error m0 =>
    refine Or.inl ?_
    have hnotall : ¬ (∀ x ∈ ((incm.partition (fun p => p.involves v)).1.concat
        (proc.partition (fun p => p.involves v)).1).elems,
        (x.lhs = v → x.rhs.isEmpty = true ∨ x.rhs.conc.isEmpty = true)) := by
      intro hall
      obtain ⟨b, hb⟩ := foldl_except_ok_of_all (f := F)
        (Q := fun (x : LPart) => x.lhs = v → x.rhs.isEmpty = true ∨ x.rhs.conc.isEmpty = true)
        (by
          intro acc x hx hacc
          obtain ⟨a, rfl⟩ := hacc
          rw [hF]
          simp only [bind, Except.bind, pure, Except.pure]
          split
          · rename_i hlhs
            by_cases hie : x.rhs.isEmpty = true
            · rw [if_pos hie]; exact ⟨a, rfl⟩
            · rw [if_neg hie]
              rcases hx (by simpa using hlhs) with hh | hh
              · exact absurd hh hie
              · rw [if_pos hh]; exact ⟨_, rfl⟩
          · exact ⟨_, rfl⟩)
        _ hall (.ok SSet.empty) ⟨SSet.empty, rfl⟩
      rw [hnps] at hb
      exact absurd hb (by simp)
    push Not at hnotall
    obtain ⟨x, hx, hxv, hne1, hne2⟩ := hnotall
    have hxG : x.toConstraint ∈ G := by
      rcases SSet.mem_concat hx with hx' | hx'
      · exact hiG x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))
      · exact hpG x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))
    have hxc : x.toConstraint = mk v (vset x.toConstraint) x.toConstraint.conc := by
      rw [← hxv]
      unfold LPart.toConstraint; simp only [vset_mk, conc_mk]
    exact incompatible_refutes hv (hxc ▸ hxG) (conc_ne_of_not_isEmpty (by simpa using hne2))

/-! ## 5. Message 1 and 2 in the `learn` branch -/

/-- **`substitution` dies only at a real overlap**, at either argument order. -/
theorem substitution_died_refutes {G : System} {v u : Nat} {r1 r2 : RHS} {m : String}
    (h1 : mk v r1.abstr.fs (cfs r1.conc) ∈ G) (h2 : mk u r2.abstr.fs (cfs r2.conc) ∈ G)
    (h : substitution v r1 u r2 = .error m) : ¬ SSat G := by
  simp only [substitution] at h
  cases hb1 : subBody v r1 u r2 with
  | error m1 =>
    simp only [subBody] at hb1
    split at hb1
    · cases hrs : rhsSubstitute r2 v r1 with
      | ok w =>
        rw [hrs] at hb1
        simp only [bind, Except.bind, pure, Except.pure] at hb1
        exact absurd hb1 (by simp)
      | error m2 =>
        obtain ⟨hv, hne⟩ := rhsSubstitute_died hrs
        exact merge_refutes h2 h1 hv hne
    · simp only [pure, Except.pure] at hb1
      exact absurd hb1 (by simp)
  | ok S1 =>
    cases hb2 : subBody u r2 v r1 with
    | error m2 =>
      simp only [subBody] at hb2
      split at hb2
      · cases hrs : rhsSubstitute r1 u r2 with
        | ok w =>
          rw [hrs] at hb2
          simp only [bind, Except.bind, pure, Except.pure] at hb2
          exact absurd hb2 (by simp)
        | error m3 =>
          obtain ⟨hu, hne⟩ := rhsSubstitute_died hrs
          exact merge_refutes h1 h2 hu hne
      · simp only [pure, Except.pure] at hb2
        exact absurd hb2 (by simp)
    | ok S2 =>
      rw [hb1, hb2] at h
      simp only [bind, Except.bind, pure, Except.pure] at h
      exact absurd h (by simp)

/-- **Every death of `learnPartitions` is a refutation**: message 2 from `selfSubstitution`,
message 1 from `substitution`. -/
theorem learnPartitions_died {G : System} {fl : Flags} {ns : Names} {env : Env} {v : Nat}
    {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {m : String}
    (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hrG : mk v rhs1.abstr.fs (cfs rhs1.conc) ∈ G)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .error m) : ¬ SSat G := by
  simp only [learnPartitions] at h
  split at h
  · rename_i hself
    cases hss : selfSubstitution ns v rhs1.abstr rhs1.conc with
    | ok T =>
      rw [hss] at h
      simp only [bind, Except.bind, pure, Except.pure] at h
      exact absurd h (by simp)
    | error m' =>
      refine selfSubst_refutes hrG (SSet.mem_fs.mpr (contains_nat_iff.mp hself)) ?_
      simp only [selfSubstitution] at hss
      split at hss
      · exact absurd hss (by simp)
      · rename_i hne
        intro hh
        exact hne (cfs_eq_empty_iff.mpr hh)
  · set F := (fun (acc : Except String (SSet LPart × Sup)) (p2 : LPart) => do
      let (s, su) ← acc
      if p2.lhs == v then
        let (rps, su) := resolution fl v rhs1 p2.rhs
          (fun k => findResolvent v (mkLookups v incm proc) s k)
          (fun k => if fl.splitRow || fl.resRow then findConcRow (mkLookups v incm proc) k
                    else none)
          (fun k => if fl.emptyRow then findEmptyRow env (mkLookups v incm proc) k else none) su
        let cps := cancellation v rhs1 p2.rhs
        let dps :=
          if !fl.disjRule then (SSet.empty, su)
          else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
            if p3.lhs != v then
              let (d1, s1) := disjunction p3.rhs rhs1 p2.rhs a.2
              let (d2, s2) := disjunction p3.rhs p2.rhs rhs1 s1
              (a.1.concat (d1.concat d2), s2)
            else a) (SSet.empty, su)
        pure ((s.concat rps).concat cps |>.concat dps.1, dps.2)
      else
        let (csps, su) := commonSubexpression fl v rhs1 p2.lhs p2.rhs
          (fun r => findRHS3 incm proc s r) su
        let sps ← substitution v rhs1 p2.lhs p2.rhs
        let dps :=
          if !fl.disjRule then (SSet.empty, su)
          else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
            if p3.lhs == p2.lhs && !(p2.rhs.eqv p3.rhs) then
              let (d1, s1) := disjunction rhs1 p2.rhs p3.rhs a.2
              let (d2, s2) := disjunction rhs1 p3.rhs p2.rhs s1
              (a.1.concat (d1.concat d2), s2)
            else if p3.lhs == v && !(rhs1.eqv p3.rhs) then
              let (d1, s1) := disjunction p2.rhs rhs1 p3.rhs a.2
              let (d2, s2) := disjunction p2.rhs p3.rhs rhs1 s1
              (a.1.concat (d1.concat d2), s2)
            else a) (SSet.empty, su)
        pure ((s.concat csps).concat sps |>.concat dps.1, dps.2)) with hF
    have hf : ∀ (acc : Except String (SSet LPart × Sup)) (x : LPart),
        (x.lhs == v) = true ∨ (∀ m', substitution v rhs1 x.lhs x.rhs ≠ .error m') →
        (∃ b, acc = .ok b) → ∃ b, F acc x = .ok b := by
      intro acc x hx hacc
      obtain ⟨a, rfl⟩ := hacc
      rw [hF]
      simp only [bind, Except.bind]
      split
      · exact ⟨_, rfl⟩
      · rename_i hne
        cases hsp : substitution v rhs1 x.lhs x.rhs with
        | error m' =>
          rcases hx with hx' | hx'
          · exact absurd hx' hne
          · exact absurd hsp (hx' m')
        | ok S => exact ⟨_, rfl⟩
    by_cases hall : ∀ x ∈ proc.elems,
        (x.lhs == v) = true ∨ (∀ m', substitution v rhs1 x.lhs x.rhs ≠ .error m')
    · exfalso
      obtain ⟨b, hb⟩ := foldl_except_ok_of_all hf proc.elems hall _ ⟨_, rfl⟩
      rw [hb] at h
      exact absurd h (by simp)
    · push Not at hall
      obtain ⟨x, hx, -, m', hm'⟩ := hall
      have hxG : mk x.lhs x.rhs.abstr.fs (cfs x.rhs.conc) ∈ G := by
        have := hpG x hx; rwa [toConstraint_eq] at this
      exact substitution_died_refutes hrG hxG hm'

/-! ## 6. The death-site theorem, and along a run -/

/-- `step` never renames a variable. -/
theorem foldl_log_names (f : State → LPart → String) :
    ∀ (l : List LPart) (st : State),
      (l.foldl (fun a p => ({ a with trace := f a p :: a.trace } : State)) st).names = st.names
  | [], _ => rfl
  | p :: l, st => foldl_log_names f l { st with trace := f st p :: st.trace }

theorem step_names {s s' : State} (h : step s = .continue s') : s'.names = s.names := by
  simp only [step, State.log] at h
  repeat' split at h
  all_goals (cases h <;> simp only [foldl_log_names])

/-- **The exceptions**: the ONE message shape a death can carry that is not a refutation of the
constraint system.  A skolem row variable forced empty is a genuine type error — the compiler
is right to reject — but `Rowpartition`'s semantics treats EVERY row variable as flexible, so
the system it dies on can still have a model and the death is not a refutation OF IT.  The two
reinstantiation panics are not on this list because `QueueHygiene` proves they are
unreachable. -/
def NonRefutation (ns : Names) (m : String) : Prop :=
  ∃ v : Nat, ns.isSkolem v = true ∧
    m = "Cannot unify skolem variable with empty relation " ++ varStr ns v

/-- **REJECTION SOUNDNESS, one step.**  Every message `step` can die with, at a well-formed
hygienic state, either refutes the system the state denotes or is the skolem refusal. -/
theorem step_died_refutes {s s' : State} {m : String} (hw : Wf s) (hq : QueueHygiene s)
    (h : step s = .died m s') : ¬ SSat (sys s) ∨ NonRefutation s.names m := by
  cases hdq : s.incm.dequeue with
  | none =>
    exfalso
    simp only [step] at h
    rw [hdq] at h
    exact absurd h (by simp)
  | some w =>
    obtain ⟨r, rest⟩ := w
    obtain ⟨hrOk, hrestOk⟩ := QOk.dequeue hw.incm hdq
    obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
    have hrestG : ∀ x ∈ rest.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_incm (hrestMem x hx)
    have hprocG : ∀ x ∈ s.proc.elems, x.toConstraint ∈ sys s := fun x hx => mem_sys_of_proc hx
    have hrG : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
    cases hfr : s.proc.findRHS r.rhs with
    | some u =>
      exfalso
      obtain ⟨w2, hw2⟩ := (step_link_no_death hq hdq).1 u hfr
      obtain ⟨ni, np, e⟩ := w2
      simp only [step, State.log] at h
      rw [hdq] at h
      dsimp only at h
      rw [hfr] at h
      dsimp only at h
      rw [hw2] at h
      exact absurd h (by simp)
    | none =>
      by_cases hem : r.rhs.isEmpty = true
      · obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := step_empty_branch hdq hfr hem
        rw [hstep] at h
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | ok w2 =>
          obtain ⟨ni, np, e⟩ := w2
          rw [hres] at h
          exact absurd h (by simp)
        | error m0 =>
          rw [hres] at h
          simp only [StepResult.died.injEq] at h
          obtain ⟨rfl, -⟩ := h
          rcases makeEmpty_died_hyg hrestG hprocG
            (by rw [← toConstraint_of_isEmpty hem]; exact hrG)
            (queueHygiene_binds_unbound hq hdq).1 hres with hh | hh
          · exact Or.inl hh
          · exact Or.inr ⟨r.lhs, hh.1, hh.2⟩
      · by_cases habs : r.rhs.abstr.isEmpty = true
        · refine Or.inl ?_
          simp only [step, State.log] at h
          rw [hdq] at h
          dsimp only at h
          rw [hfr] at h
          dsimp only at h
          rw [if_neg hem, if_pos habs] at h
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | ok w2 =>
            obtain ⟨ni, np⟩ := w2
            rw [hres] at h
            exact absurd h (by simp)
          | error m0 =>
            exact makeConcrete_died hw.coh hrestOk hw.proc hrOk.conc hrestG hprocG
              (by rw [← abstr_isEmpty_toConstraint habs]; exact hrG) hres
        · cases hsg : r.rhs.single? with
          | some u =>
            exfalso
            obtain ⟨w2, hw2⟩ := (step_link_no_death hq hdq).2 u hsg
            obtain ⟨ni, np, e⟩ := w2
            simp only [step, State.log] at h
            rw [hdq] at h
            dsimp only at h
            rw [hfr] at h
            dsimp only at h
            rw [if_neg hem, if_neg habs, hsg] at h
            dsimp only at h
            rw [hw2] at h
            exact absurd h (by simp)
          | none =>
            refine Or.inl ?_
            simp only [step, State.log] at h
            rw [hdq] at h
            dsimp only at h
            rw [hfr] at h
            dsimp only at h
            rw [if_neg hem, if_neg habs, hsg] at h
            dsimp only at h
            cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | ok w2 =>
              obtain ⟨learned, su⟩ := w2
              rw [hlp] at h
              exact absurd h (by simp)
            | error m0 =>
              exact learnPartitions_died hprocG (by rw [← toConstraint_eq]; exact hrG) hlp

/-- **REJECTION SOUNDNESS, along a run.**  A run that rejects with a message that is not the
skolem refusal proves the INPUT system has no model. -/
theorem run_rejects_unsat : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → QueueHygiene s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' →
      ¬ NonRefutation s.names m → ¬ SSat (sys s)
  | 0, s, _, _, _, _, _, _, m, s', hres, _ => by
    simp only [run] at hres; exact absurd hres (by simp)
  | n + 1, s, hw, hem, hdj, hcse, hb, hq, m, s', hres, hnr => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 => rw [hst] at hres; exact absurd hres (by simp)
    | died m0 s0 =>
      rw [hst] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨rfl, -⟩ := hres
      rcases step_died_refutes hw hq hst with hh | hh
      · exact hh
      · exact absurd hh hnr
    | «continue» s0 =>
      rw [hst] at hres
      intro hsat
      refine run_rejects_unsat n (step_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
        (step_queueHygiene hdj hb.1 hb.2.1 hq hst) m s' hres ?_
        (step_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat)
      · rw [step_flags hst]; exact hem
      · rw [step_flags hst]; exact hdj
      · rw [step_flags hst]; exact hcse
      · rw [step_names hst]; exact hnr

/-- ... and on a solve whose variables carry NO skolem, with no exception list at all.  Every
`json:` seed is such a solve (`Names.tys` is empty, so `isSkolem` is constantly false), and so
is every corpus solve whose `svar` table has no `Skolem` entry. -/
theorem run_rejects_unsat_noSkolem (n : Nat) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hq : QueueHygiene s)
    (hsk : ∀ v, s.names.isSkolem v = false)
    (m : String) (s' : State) (hres : run s n = .rejected m s') : ¬ SSat (sys s) :=
  run_rejects_unsat n hw hem hdj hcse hb hq m s' hres
    (by rintro ⟨v, hv, -⟩; rw [hsk v] at hv; exact absurd hv (by simp))

end Rowpartition.Loop
