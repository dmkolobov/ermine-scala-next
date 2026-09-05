/-
# L3 (i): refinement — every `continue` step is a run of the relations

`sys : State → System` is the constraint system a loop state DENOTES: the two queues'
partitions, plus the facts the substitution environment holds.  `makeEmptyE`'s "retain
`v <- ()`" is the precedent for the second half: a fact the loop moves out of the queue into
the environment is still a fact of the system, and every reverse lookup that is allowed to
see the environment (`-Dermine.emptyRow`) reads it back.

`LoopRel` is assembled from the relations the development already has --
`NonGenStep` (CSE reuse and fold, `splitConcrete`'s syntactic reuse, cancellation,
substitution, self-substitution, common partition), `K2SplitStep` (`splitKey` / `splitRow`
reuse), `Cut.SplitStep` (`splitConcrete`'s mint) and `ResStep` / `K2ResStep` (`resolution`'s
mint and its `resGuard` / `resRow` reuse) -- plus FIVE constructors for what the loop does and
no relation had:

`KeyedEmpty.makeEmptyE` is deliberately NOT a constructor: `makeEmpty`'s effect is realized
here by finer steps (`SubstStep` per erased constraint, `emptyProp` per propagated one,
`weaken` for the deletions, and the RETAINED `v <- ()`, which `sys` keeps in the environment),
and a single `makeEmptyE` step could not be the whole branch anyway, because `Q.+!` may turn
one of the re-enqueued partitions into a `CommonPartition` redirect `w <- (a)`, which is in
neither `keepPart`, `erasePart` nor `propPart`.

* `weaken`   — the loop DELETES (`destructiveSub`, `makeEmpty`'s erasure, `instantiate`'s
               removal) and DROPS (`trim`, `++!`'s already-present test, `insertNP`'s
               self-unification test).  Sound because a subsystem has every model;
* `renameLhs` — `replace`'s `f p.lhs`: an alias rewrites the LEFT-hand side too;
* `linkSymm`  — `unify(u, v)` on `v <- (u)` instantiates `u := v`, i.e. it reads the link
               backwards;
* `emptyProp` — `makeEmpty`'s `aux`: an empty whole with an all-variable definition forces
               every part empty (`makeEmptyD`'s `propPart` as a single conclusion);
* `dedup`     — `RHS.merge`'s returned `es` and `replace`'s two-element queue: a variable
               that lands twice among the disjoint parts of one partition is empty.

Each new constructor has a soundness lemma, in the same one-directional form the deleting
steps of the library use.
-/
import Rowpartition.Loop.Wf
import Rowpartition.KeyedEmpty
import Rowpartition.SplitNecessary

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty

set_option linter.unusedSimpArgs false

/-! ## 1. `SSet` membership, both directions

`Wf.lean` needed only "every element of the result came from an argument".  The refinement
needs the converse as well, so that an `SSet` operation can be read as the corresponding
`Finset` operation.  Both directions need `LawfulSVal`, which holds of the two element types
that occur inside an `RHS` (row variables and labels) and deliberately not of `RHS`/`LPart`. -/

namespace SSet

variable {α : Type} [SVal α] [LawfulSVal α]

theorem mem_incl_iff {s : SSet α} {x y : α} : x ∈ (s.incl y).elems ↔ x ∈ s.elems ∨ x = y := by
  constructor
  · exact mem_incl
  · intro h
    unfold incl
    split
    · rename_i hc
      rcases h with h | rfl
      · exact h
      · exact (contains_iff s _).mp hc
    · rename_i hc
      have : x ∈ s.elems ++ [y] := by
        rcases h with h | rfl
        · exact List.mem_append_left _ h
        · exact List.mem_append_right _ (by simp)
      split
      · exact mem_champ.mpr this
      · exact this

omit [LawfulSVal α] in
theorem mem_filter_iff {s : SSet α} {p : α → Bool} {x : α} :
    x ∈ (s.filter p).elems ↔ x ∈ s.elems ∧ p x = true := by
  constructor
  · intro h
    unfold SSet.filter at h
    split at h
    · exact List.mem_filter.mp (mem_champ.mp h)
    · exact List.mem_filter.mp h
  · intro h
    unfold SSet.filter
    split
    · exact mem_champ.mpr (List.mem_filter.mpr h)
    · exact List.mem_filter.mpr h

theorem mem_excl_iff {s : SSet α} {x y : α} :
    x ∈ (s.excl y).elems ↔ x ∈ s.elems ∧ x ≠ y := by
  have key : ∀ z : α, (!SVal.eq y z) = true ↔ z ≠ y := by
    intro z
    cases hh : SVal.eq y z with
    | true => have hyz : y = z := (LawfulSVal.eq_iff y z).mp hh; simp [hyz]
    | false =>
      have hyz : y ≠ z := fun hz => by
        rw [(LawfulSVal.eq_iff y z).mpr hz] at hh; exact absurd hh (by simp)
      simp [Ne.symm hyz]
  constructor
  · intro h
    unfold excl at h
    have h' : x ∈ s.elems.filter (fun z => !SVal.eq y z) := by
      split at h
      · exact mem_champ.mp h
      · exact h
    obtain ⟨h1, h2⟩ := List.mem_filter.mp h'
    exact ⟨h1, (key x).mp h2⟩
  · rintro ⟨h1, h2⟩
    unfold excl
    have h' : x ∈ s.elems.filter (fun z => !SVal.eq y z) :=
      List.mem_filter.mpr ⟨h1, (key x).mpr h2⟩
    split
    · exact mem_champ.mpr h'
    · exact h'

theorem mem_concat_iff {s t : SSet α} {x : α} :
    x ∈ (s.concat t).elems ↔ x ∈ s.elems ∨ x ∈ t.elems := by
  constructor
  · exact mem_concat
  · intro h
    unfold concat
    split
    · have hid : ∀ y : α, pickRep s.elems t.elems y = y := by
        intro y
        unfold pickRep
        cases hf : s.elems.find? (fun z => SVal.eq z y) with
        | none => simp
        | some sy =>
          have hb : SVal.eq sy y = true := by have := List.find?_some hf; simpa using this
          simp [(LawfulSVal.eq_iff sy y).mp hb]
      have hmem : x ∈ (s.elems.filter (fun z => !t.contains z)) ++ t.elems := by
        rcases h with h | h
        · by_cases hc : t.contains x = true
          · exact List.mem_append_right _ ((contains_iff t x).mp hc)
          · exact List.mem_append_left _ (List.mem_filter.mpr ⟨h, by simpa using hc⟩)
        · exact List.mem_append_right _ h
      have : x ∈ champ ((s.elems.filter (fun z => !t.contains z)) ++ t.elems) :=
        mem_champ.mpr hmem
      simpa [hid] using List.mem_map.mpr ⟨x, this, hid x⟩
    · rcases h with h | h
      · have hgen : ∀ (l : List α) (u : SSet α), x ∈ u.elems → x ∈ (l.foldl incl u).elems := by
          intro l
          induction l with
          | nil => intro u hu; exact hu
          | cons y l ih => intro u hu; exact ih (u.incl y) (mem_incl_iff.mpr (Or.inl hu))
        exact hgen t.elems s h
      · have hgen : ∀ (l : List α) (u : SSet α), x ∈ l → x ∈ (l.foldl incl u).elems := by
          intro l
          induction l with
          | nil => intro u hu; cases hu
          | cons y l ih =>
            intro u hu
            rcases List.mem_cons.mp hu with rfl | hu'
            · have hstep : ∀ (m : List α) (w : SSet α), x ∈ w.elems →
                  x ∈ (m.foldl incl w).elems := by
                intro m
                induction m with
                | nil => intro w hw; exact hw
                | cons z m ihm => intro w hw; exact ihm (w.incl z) (mem_incl_iff.mpr (Or.inl hw))
              exact hstep l (u.incl x) (mem_incl_iff.mpr (Or.inr rfl))
            · exact ih (u.incl y) hu'
        exact hgen t.elems s h

theorem mem_removedAll_iff {s t : SSet α} {x : α} :
    x ∈ (s.removedAll t).elems ↔ x ∈ s.elems ∧ x ∉ t.elems := by
  unfold removedAll
  have hgen : ∀ (l : List α) (u : SSet α),
      x ∈ (l.foldl excl u).elems ↔ x ∈ u.elems ∧ x ∉ l := by
    intro l
    induction l with
    | nil => intro u; simp
    | cons y l ih =>
      intro u
      rw [List.foldl_cons, ih (u.excl y), mem_excl_iff]
      constructor
      · rintro ⟨⟨h1, h2⟩, h3⟩
        exact ⟨h1, by simp [h2, h3]⟩
      · rintro ⟨h1, h2⟩
        rw [List.mem_cons] at h2
        exact ⟨⟨h1, fun hh => h2 (Or.inl hh)⟩, fun hh => h2 (Or.inr hh)⟩
  exact hgen t.elems s

theorem mem_inter_iff {s t : SSet α} {x : α} :
    x ∈ (s.inter t).elems ↔ x ∈ s.elems ∧ x ∈ t.elems := by
  rw [inter, mem_filter_iff]
  exact and_congr Iff.rfl (contains_iff t x)

theorem mem_ofList_iff {xs : List α} {x : α} : x ∈ (ofList xs).elems ↔ x ∈ xs := by
  constructor
  · exact mem_ofList
  · intro h
    have : x ∈ ((empty : SSet α).concat ⟨false, xs⟩).elems := mem_concat_iff.mpr (Or.inr h)
    simpa [concat, empty, ofList] using this

omit [SVal α] [LawfulSVal α] in
theorem mem_map_iff {β : Type} [SVal β] [LawfulSVal β] {s : SSet α} {f : α → β} {y : β} :
    y ∈ (s.map f).elems ↔ ∃ x ∈ s.elems, f x = y := by
  constructor
  · exact mem_map
  · rintro ⟨x, hx, rfl⟩
    unfold SSet.map
    have hgen : ∀ (l : List α) (acc : SSet β), x ∈ l →
        f x ∈ ((l.foldl (fun a z => a.incl (f z)) acc).elems) := by
      intro l
      induction l with
      | nil => intro _ hu; cases hu
      | cons z l ih =>
        intro acc hu
        rcases List.mem_cons.mp hu with rfl | hu'
        · have hstep : ∀ (m : List α) (w : SSet β), f x ∈ w.elems →
              f x ∈ ((m.foldl (fun a z => a.incl (f z)) w).elems) := by
            intro m
            induction m with
            | nil => intro w hw; exact hw
            | cons z' m ihm => intro w hw; exact ihm (w.incl (f z')) (mem_incl_iff.mpr (Or.inl hw))
          exact hstep l (acc.incl (f x)) (mem_incl_iff.mpr (Or.inr rfl))
        · exact ih (acc.incl (f z)) hu'
    exact hgen s.elems ⟨s.hashed, []⟩ hx

/-! ### The `Finset` view -/

variable [DecidableEq α]

/-- The finite set an `SSet` denotes. -/
def fs (s : SSet α) : Finset α := s.elems.toFinset

omit [SVal α] [LawfulSVal α] in
@[simp] theorem mem_fs {s : SSet α} {x : α} : x ∈ s.fs ↔ x ∈ s.elems := List.mem_toFinset

omit [SVal α] [LawfulSVal α] in
@[simp] theorem fs_empty : (empty : SSet α).fs = ∅ := rfl

@[simp] theorem fs_concat (s t : SSet α) : (s.concat t).fs = s.fs ∪ t.fs := by
  ext x; simp [mem_concat_iff]

@[simp] theorem fs_removedAll (s t : SSet α) : (s.removedAll t).fs = s.fs \ t.fs := by
  ext x; simp [mem_removedAll_iff]

@[simp] theorem fs_inter (s t : SSet α) : (s.inter t).fs = s.fs ∩ t.fs := by
  ext x; simp [mem_inter_iff]

@[simp] theorem fs_excl (s : SSet α) (y : α) : (s.excl y).fs = s.fs.erase y := by
  ext x; simp [mem_excl_iff, Finset.mem_erase, and_comm]

@[simp] theorem fs_incl (s : SSet α) (y : α) : (s.incl y).fs = insert y s.fs := by
  ext x; simp [mem_incl_iff, or_comm]

@[simp] theorem fs_ofList (xs : List α) : (ofList xs).fs = xs.toFinset := by
  ext x; simp [mem_ofList_iff]

omit [SVal α] [LawfulSVal α] in
@[simp] theorem fs_map {β : Type} [SVal β] [LawfulSVal β] [DecidableEq β] (s : SSet α)
    (f : α → β) : (s.map f).fs = s.fs.image f := by
  ext y; simp [mem_map_iff]

omit [SVal α] [LawfulSVal α] in
theorem isEmpty_iff_fs {s : SSet α} : s.isEmpty = true ↔ s.fs = ∅ := by
  constructor
  · intro h
    have : s.elems = [] := by simpa [isEmpty] using h
    simp [fs, this]
  · intro h
    have : ∀ x, x ∉ s.elems := by
      intro x hx
      have : x ∈ s.fs := mem_fs.mpr hx
      rw [h] at this
      exact absurd this (Finset.notMem_empty x)
    cases hh : s.elems with
    | nil => simp [isEmpty, hh]
    | cons y l => exact absurd (hh ▸ List.mem_cons_self ..) (this y)

end SSet


/-! ## 2. `sys`: the system a loop state denotes -/

/-- The fact an environment binding records.  `instantiateType(v, ConcreteRho(∅))` is
`v <- ()` -- exactly the constraint `makeEmptyE` RETAINS -- and `instantiateType(v, VarT(u))`
is `v <- (u)`, which is what "`v` is now a name for `u`" means as a partition. -/
def EnvVal.toConstraint (v : Nat) : EnvVal → Constraint
  | .emptyRow => mk v ∅ (∅ : Row)
  | .alias u => mk v {u} (∅ : Row)

/-- The facts the substitution environment holds. -/
def Env.sys (e : Env) : System :=
  (e.binds.map (fun p => EnvVal.toConstraint p.1 p.2)).toFinset

/-- **The system a loop state denotes**: the two queues' partitions and the environment's
facts. -/
def sys (s : State) : System := (s.parts.map LPart.toConstraint).toFinset ∪ s.env.sys

theorem mem_sys_of_part {s : State} {p : LPart} (hp : p ∈ s.parts) :
    p.toConstraint ∈ sys s :=
  Finset.mem_union_left _ (List.mem_toFinset.mpr (List.mem_map.mpr ⟨p, hp, rfl⟩))

theorem mem_sys_of_incm {s : State} {p : LPart} (hp : p ∈ s.incm.elems) :
    p.toConstraint ∈ sys s := mem_sys_of_part (List.mem_append_left _ hp)

theorem mem_sys_of_proc {s : State} {p : LPart} (hp : p ∈ s.proc.elems) :
    p.toConstraint ∈ sys s := mem_sys_of_part (List.mem_append_right _ hp)

theorem mem_sys_of_env {s : State} {v : Nat} {val : EnvVal} (h : (v, val) ∈ s.env.binds) :
    EnvVal.toConstraint v val ∈ sys s :=
  Finset.mem_union_right _ (List.mem_toFinset.mpr (List.mem_map.mpr ⟨(v, val), h, rfl⟩))

theorem mem_sys {s : State} {c : Constraint} :
    c ∈ sys s ↔ (∃ p ∈ s.parts, p.toConstraint = c) ∨
      (∃ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 = c) := by
  simp only [sys, Env.sys, Finset.mem_union, List.mem_toFinset, List.mem_map]

/-! ## 3. Two shapes of constraint, read semantically -/

/-- A system with a model. -/
def SSat (G : System) : Prop := ∃ rho, SModels rho G

theorem sat_link_iff {rho : Assign} {a b : Var} :
    Sat rho (mk a {b} (∅ : Row)) ↔ rho a = rho b := by
  rw [sat_mk_iff]
  constructor
  · rintro ⟨he, -, -⟩; simpa using he
  · intro he
    refine ⟨by simpa using he, ?_, ?_⟩
    · intro v hv; simp
    · intro v hv w hw hvw
      rw [Finset.mem_singleton] at hv hw
      exact absurd (hv.trans hw.symm) hvw

theorem sat_empty_iff {rho : Assign} {a : Var} :
    Sat rho (mk a ∅ (∅ : Row)) ↔ rho a = ∅ := by
  rw [sat_mk_iff]
  constructor
  · rintro ⟨he, -, -⟩; simpa using he
  · intro he; exact ⟨by simpa using he, by simp, by simp⟩

/-! ## 4. `LoopRel` -/

/-- **One abstract step of the loop.**  The first four constructors are the development's
own relations, imported unchanged; the last five are what the loop does and no relation
had. -/
inductive LoopRel : System → System → Prop
  /-- CSE reuse and fold, `splitConcrete`'s syntactic reuse, cancellation, substitution,
  self-substitution, common partition -- `SplitNecessary.NonGenStep`. -/
  | nongen {G G' : System} : NonGenStep G G' → LoopRel G G'
  /-- `splitConcrete`: syntactic, keyed (`splitKey`) and concrete-row (`splitRow`) reuse and
  the mint -- `KeyedRow.K2SplitStep`. -/
  | split {G G' : System} : K2SplitStep G G' → LoopRel G G'
  /-- `resolution`'s mint -- `Cut.ResStep` (the guard is `K2ResStep`'s, not needed for
  soundness). -/
  | res {G G' : System} : ResStep G G' → LoopRel G G'
  /-- `splitConcrete`'s MINT with `Cut.SplitApp`'s SYNTACTIC guard -- which is exactly what
  the loop's `findRHS3` lookup missing gives, and which needs none of `Carried`. -/
  | splitFree {G G' : System} : SplitStep G G' → LoopRel G G'
  /-- `resolution`'s guarded (`resGuard`) and concrete-row (`resRow`) reuse --
  `KeyedRow.K2ResStep`. -/
  | kres {G G' : System} : K2ResStep G G' → LoopRel G G'
  /-- NEW: the loop DELETES and DROPS.  `destructiveSub` and `makeEmpty` erase; `trim`,
  `++!`'s already-present test and `insertNP`'s self-unification test drop. -/
  | weaken {G G' : System} : G' ⊆ G → LoopRel G G'
  /-- NEW: `replace`'s `f p.lhs` -- an alias rewrites the LEFT-hand side. -/
  | renameLhs {G : System} {a b : Var} {S : Finset Var} {K : Row} :
      mk a S K ∈ G → mk a {b} (∅ : Row) ∈ G → LoopRel G (insert (mk b S K) G)
  /-- NEW: `unify(u, v)` on `v <- (u)` instantiates `u := v`: the link read backwards. -/
  | linkSymm {G : System} {a b : Var} :
      mk a {b} (∅ : Row) ∈ G → LoopRel G (insert (mk b {a} (∅ : Row)) G)
  /-- NEW: `makeEmpty`'s `aux` -- an empty whole with an all-variable definition forces every
  part empty.  `makeEmptyD`'s `propPart`, as a single conclusion. -/
  | emptyProp {G : System} {a x : Var} {S : Finset Var} :
      mk a S (∅ : Row) ∈ G → mk a ∅ (∅ : Row) ∈ G → x ∈ S →
      LoopRel G (insert (mk x ∅ (∅ : Row)) G)
  /-- NEW: `RHS.merge`'s returned `es` and `replace`'s two-element queue -- a variable that
  lands twice among the disjoint parts of one partition is empty. -/
  | dedup {G : System} {c v x : Var} {S S' : Finset Var} {K K' : Row} :
      mk c S K ∈ G → mk v S' K' ∈ G → v ∈ S → x ∈ S.erase v → x ∈ S' →
      LoopRel G (insert (mk x ∅ (∅ : Row)) G)

/-! ### Soundness, one constructor at a time -/

theorem renameLhs_sat {rho : Assign} {a b : Var} {S : Finset Var} {K : Row}
    (h1 : Sat rho (mk a S K)) (h2 : Sat rho (mk a {b} (∅ : Row))) : Sat rho (mk b S K) := by
  have hab : rho a = rho b := sat_link_iff.mp h2
  rw [sat_mk_iff] at h1 ⊢
  exact ⟨hab ▸ h1.1, h1.2.1, h1.2.2⟩

theorem linkSymm_sat {rho : Assign} {a b : Var} (h : Sat rho (mk a {b} (∅ : Row))) :
    Sat rho (mk b {a} (∅ : Row)) := sat_link_iff.mpr (sat_link_iff.mp h).symm

theorem emptyProp_sat {rho : Assign} {a x : Var} {S : Finset Var}
    (h1 : Sat rho (mk a S (∅ : Row))) (h2 : Sat rho (mk a ∅ (∅ : Row))) (hx : x ∈ S) :
    Sat rho (mk x ∅ (∅ : Row)) := by
  refine sat_empty_iff.mpr (Finset.eq_empty_of_forall_notMem (fun l hl => ?_))
  have hsub : rho x ⊆ rho a := by
    rw [(sat_mk_iff rho a S ∅).mp h1 |>.1]
    intro m hm
    exact Finset.mem_union_right _ (Finset.mem_biUnion.mpr ⟨x, hx, hm⟩)
  have : l ∈ rho a := hsub hl
  rw [sat_empty_iff.mp h2] at this
  exact absurd this (Finset.notMem_empty l)

theorem dedup_sat {rho : Assign} {c v x : Var} {S S' : Finset Var} {K K' : Row}
    (h1 : Sat rho (mk c S K)) (h2 : Sat rho (mk v S' K')) (hv : v ∈ S)
    (hx : x ∈ S.erase v) (hx' : x ∈ S') : Sat rho (mk x ∅ (∅ : Row)) := by
  obtain ⟨hxv, hxS⟩ := Finset.mem_erase.mp hx
  have hsub : rho x ⊆ rho v := by
    rw [(sat_mk_iff rho v S' K').mp h2 |>.1]
    intro m hm
    exact Finset.mem_union_right _ (Finset.mem_biUnion.mpr ⟨x, hx', hm⟩)
  have hdisj : Disjoint (rho x) (rho v) := (sat_mk_iff rho c S K).mp h1 |>.2.2 x hxS v hv hxv
  exact sat_empty_iff.mpr (eq_empty_of_disjoint_self (hdisj.mono_right hsub))

/-- **Every constructor of `LoopRel` preserves satisfiability**, in the one direction the
deleting steps of the library have. -/
theorem LoopRel.sat {G G' : System} (h : LoopRel G G') : SSat G → SSat G' := by
  rintro ⟨rho, hm⟩
  cases h with
  | nongen h => exact ⟨rho, (h.models_iff rho).mp hm⟩
  | split h => obtain ⟨rho', hm', -⟩ := K2SplitStep.extend hm h; exact ⟨rho', hm'⟩
  | res h => exact h.satisfiable_iff.mp ⟨rho, hm⟩
  | splitFree h => exact h.satisfiable_iff.mp ⟨rho, hm⟩
  | kres h => obtain ⟨rho', hm', -⟩ := K2ResStep.extend hm h; exact ⟨rho', hm'⟩
  | weaken hsub => exact ⟨rho, SModels.mono hsub hm⟩
  | renameLhs h1 h2 =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact renameLhs_sat (hm _ h1) (hm _ h2)
    · exact hm c hc'
  | linkSymm h1 =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact linkSymm_sat (hm _ h1)
    · exact hm c hc'
  | emptyProp h1 h2 hx =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact emptyProp_sat (hm _ h1) (hm _ h2) hx
    · exact hm c hc'
  | dedup h1 h2 hv hx hx' =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact dedup_sat (hm _ h1) (hm _ h2) hv hx hx'
    · exact hm c hc'

/-- A run of the abstract relation. -/
abbrev LoopRun : System → System → Prop := Relation.ReflTransGen LoopRel

theorem LoopRun.sat {G G' : System} (h : LoopRun G G') : SSat G → SSat G' := by
  induction h with
  | refl => exact id
  | tail _ hstep ih => exact fun hs => hstep.sat (ih hs)


/-! ## 5. Building a run one conclusion at a time -/

/-- A constraint the relation can add to ANY system reachable from `G` that still contains
`G`.  Every conclusion of every rule is of this shape, because the premises stay present. -/
def Adds (G : System) (c : Constraint) : Prop := ∀ H : System, G ⊆ H → LoopRel H (insert c H)

theorem adds_list {G : System} : ∀ (L : List Constraint), (∀ c ∈ L, Adds G c) →
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ ∀ c ∈ L, c ∈ H := by
  intro L
  induction L with
  | nil => exact fun _ => ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, by simp⟩
  | cons c L ih =>
    intro h
    obtain ⟨H, hrun, hsub, hmem⟩ := ih (fun d hd => h d (by simp [hd]))
    refine ⟨insert c H, hrun.tail (h c (by simp) H hsub), ?_, ?_⟩
    · exact hsub.trans (Finset.subset_insert c H)
    · intro d hd
      rcases List.mem_cons.mp hd with rfl | hd'
      · exact Finset.mem_insert_self _ H
      · exact Finset.mem_insert_of_mem (hmem d hd')

/-- The vocabulary of a system with one constraint added. -/
theorem allVars_insert (c : Constraint) (G : System) :
    allVars (insert c G) = insert c.lhs (vset c) ∪ allVars G := by
  simp only [allVars, Finset.biUnion_insert]

theorem allVars_insert_subset {c : Constraint} {G : System} (h1 : c.lhs ∈ allVars G)
    (h2 : vset c ⊆ allVars G) : allVars (insert c G) ⊆ allVars G := by
  rw [allVars_insert]
  refine Finset.union_subset ?_ (Finset.Subset.refl _)
  intro w hw
  rcases Finset.mem_insert.mp hw with rfl | hw'
  · exact h1
  · exact h2 hw'

/-- `adds_list` with the vocabulary clause: if every added constraint is over variables the
system already has, the run adds no variable. -/
theorem adds_list_vars {G : System} : ∀ (L : List Constraint), (∀ c ∈ L, Adds G c) →
    (∀ c ∈ L, c.lhs ∈ allVars G) → (∀ c ∈ L, vset c ⊆ allVars G) →
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ (∀ c ∈ L, c ∈ H) ∧ allVars H ⊆ allVars G := by
  intro L
  induction L with
  | nil =>
    exact fun _ _ _ => ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, by simp,
      Finset.Subset.refl _⟩
  | cons c L ih =>
    intro h h1 h2
    obtain ⟨H, hrun, hsub, hmem, hv⟩ := ih (fun d hd => h d (by simp [hd]))
      (fun d hd => h1 d (by simp [hd])) (fun d hd => h2 d (by simp [hd]))
    have hGH : allVars G ⊆ allVars H := allVars_mono hsub
    refine ⟨insert c H, hrun.tail (h c (by simp) H hsub), ?_, ?_, ?_⟩
    · exact hsub.trans (Finset.subset_insert c H)
    · intro d hd
      rcases List.mem_cons.mp hd with rfl | hd'
      · exact Finset.mem_insert_self _ _
      · exact Finset.mem_insert_of_mem (hmem d hd')
    · exact (allVars_insert_subset (hGH (h1 c (by simp)))
        ((h2 c (by simp)).trans hGH)).trans hv

/-! ## 6. Reading a partition's right-hand side as a constraint -/

/-- Two partitions whose right-hand sides are `RHS.equals`-equal denote constraints that
differ only in the left-hand variable.  This is `Bridge.lean`'s `eqv_iff_toConstraint` in the
form the queue's reverse lookups need. -/
theorem toConstraint_congr {L : List Lbl} (hcoh : LblCoh L) {p q : LPart}
    (hp : POk L p) (hq : POk L q) (h : p.rhs.eqv q.rhs = true) :
    p.toConstraint = (⟨p.lhs, q.rhs, none⟩ : LPart).toConstraint := by
  have hpq : (⟨p.lhs, p.rhs, none⟩ : LPart).eqv ⟨p.lhs, q.rhs, none⟩ = true := by
    simp only [LPart.eqv, beq_self_eq_true, Bool.true_and]
    exact h
  exact (LPart.eqv_iff_toConstraint (p := ⟨p.lhs, p.rhs, none⟩) (q := ⟨p.lhs, q.rhs, none⟩)
    hp.abstr hq.abstr hp.conc.nodup hq.conc.nodup
    (hcoh.mono (by
      intro x hx
      rcases List.mem_append.mp hx with hx' | hx'
      · exact hp.conc.sub x hx'
      · exact hq.conc.sub x hx'))).mp hpq

/-! ## 7. The queue insertions -/

theorem mem_insertNP {q : PQueue} {p x : LPart} (h : x ∈ (q.insertNP p).elems) :
    x ∈ q.elems ∨ x = p := by
  unfold PQueue.insertNP at h
  split at h
  · exact Or.inl h
  · split at h
    · exact Or.inl h
    · rcases mem_insertSorted h with rfl | h'
      · exact Or.inr rfl
      · exact Or.inl h'

theorem mem_concatNP : ∀ (ps : List LPart) (q : PQueue) {x : LPart},
    x ∈ (q.concatNP ps).elems → x ∈ q.elems ∨ x ∈ ps
  | [], _, _, h => Or.inl h
  | p :: ps, q, x, h => by
    rcases mem_concatNP ps (q.insertNP p) h with h' | h'
    · rcases mem_insertNP h' with h'' | rfl
      · exact Or.inl h''
      · exact Or.inr (by simp)
    · exact Or.inr (by simp [h'])

theorem rhsLookup_witness {q : PQueue} {r : RHS} {w : Nat} (h : q.rhsLookup r = some w) :
    ∃ x ∈ q.elems, x.rhs.eqv r = true ∧ x.lhs = w := by
  unfold PQueue.rhsLookup at h
  split at h
  · exact absurd h (by simp)
  · split at h
    · exact absurd h (by simp)
    · cases hf : q.elems.find? (fun x => x.rhs.eqv r) with
      | none => rw [hf] at h; exact absurd h (by simp)
      | some x =>
        rw [hf] at h
        simp only [Option.map_some, Option.some.injEq] at h
        exact ⟨x, List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf, h⟩

/-- `SSet.ofList` of a single element. -/
theorem ofList_singleton {α : Type} [SVal α] (a : α) : (SSet.ofList [a]).elems = [a] := rfl

/-- The redirect partition `Q.+!` inserts denotes the naming constraint `w <- (a)`. -/
theorem redirect_toConstraint (w a : Nat) (i : Option Inference) :
    (⟨w, RHS.ofAbstr (SSet.ofList [a]), i⟩ : LPart).toConstraint = mk w {a} (∅ : Row) := by
  have h1 : (SSet.ofList [a]).elems.toFinset = ({a} : Finset Nat) := by
    rw [ofList_singleton]; simp
  unfold LPart.toConstraint
  show mk w ((SSet.ofList [a]).elems.toFinset) _ = _
  rw [h1]
  rfl

/-- **`Q.insert(process = true)`**: an insertion whose right-hand side is already in the
queue becomes a COMMON PARTITION unification instead of an insertion.  Every partition the
result carries has its constraint in a system the relation reaches -- the redirect included,
and the redirect is exactly `CommonPartStep`. -/
theorem insertP_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {q : PQueue} {p : LPart}
    (hq : QOk L q) (hp : POk L p)
    (hqG : ∀ x ∈ q.elems, x.toConstraint ∈ G) (hpG : p.toConstraint ∈ G) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ ∀ x ∈ (q.insertP p).elems, x.toConstraint ∈ H := by
  unfold PQueue.insertP
  split
  · exact ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, hqG⟩
  · split
    · exact ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, hqG⟩
    · split
      · rename_i w hw
        obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := rhsLookup_witness hw
        by_cases hwp : w = p.lhs
        · refine ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, ?_⟩
          intro x hx
          have hself : (⟨w, RHS.ofAbstr (SSet.ofList [p.lhs]),
              some Inference.commonPartition⟩ : LPart).isSelfUnification = true := by
            subst hwp
            simp [LPart.isSelfUnification, RHS.single?, RHS.ofAbstr, SSet.single?,
              ofList_singleton, SSet.isEmpty, SSet.empty]
          rw [PQueue.insertNP, if_pos hself] at hx
          exact hqG x hx
        · have hc0 : x0.toConstraint = (⟨w, p.rhs, none⟩ : LPart).toConstraint := by
            rw [← hx0lhs]
            exact toConstraint_congr hcoh (hq x0 hx0) hp hx0eq
          have happ : CommonPartApp G x0.toConstraint p.toConstraint := by
            refine ⟨hqG x0 hx0, hpG, ?_, ?_, ?_⟩
            · rw [hc0]; simpa using fun hh => hwp hh
            · rw [hc0]; rfl
            · rw [hc0]; rfl
          refine ⟨insert (mk w {p.lhs} (∅ : Row)) G, ?_, Finset.subset_insert _ _, ?_⟩
          · refine Relation.ReflTransGen.single (LoopRel.nongen (NonGenStep.commonPart ?_))
            have := CommonPartStep.intro happ
            unfold commonPartResult at this
            rw [hc0] at this
            exact this
          · intro x hx
            rcases mem_insertNP hx with h' | rfl
            · exact Finset.mem_insert_of_mem (hqG x h')
            · rw [redirect_toConstraint]
              exact Finset.mem_insert_self _ _
      · refine ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, ?_⟩
        intro x hx
        rcases mem_insertSorted hx with rfl | h'
        · exact hpG
        · exact hqG x h'


theorem concatP_run {L : List Lbl} (hcoh : LblCoh L) :
    ∀ (ps : List LPart) {G : System} {q : PQueue}, QOk L q → (∀ p ∈ ps, POk L p) →
      (∀ x ∈ q.elems, x.toConstraint ∈ G) → (∀ p ∈ ps, p.toConstraint ∈ G) →
      ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ ∀ x ∈ (q.concatP ps).elems, x.toConstraint ∈ H
  | [], G, _, _, _, hqG, _ => ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, hqG⟩
  | p :: ps, G, q, hq, hps, hqG, hpsG => by
    obtain ⟨H1, hrun1, hsub1, hq1⟩ :=
      insertP_run hcoh hq (hps p (by simp)) hqG (hpsG p (by simp))
    obtain ⟨H2, hrun2, hsub2, hq2⟩ := concatP_run hcoh ps
      (QOk.insertP hq (hps p (by simp))) (fun r hr => hps r (by simp [hr])) hq1
      (fun r hr => hsub1 (hpsG r (by simp [hr])))
    exact ⟨H2, hrun1.trans hrun2, hsub1.trans hsub2, hq2⟩

/-! ## 8. `unify`: `replace`, `instantiate` -/

theorem image_subst_mem {v u : Nat} (hvu : v ≠ u) {S : Finset Var} (hv : v ∈ S) :
    S.image (fun w => if w == v then u else w) = insert u (S.erase v) := by
  ext x
  simp only [Finset.mem_image, Finset.mem_insert, Finset.mem_erase, beq_iff_eq]
  constructor
  · rintro ⟨y, hy, rfl⟩
    by_cases hyv : y = v
    · subst hyv; simp
    · rw [if_neg hyv]; exact Or.inr ⟨hyv, hy⟩
  · rintro (rfl | ⟨hxv, hx⟩)
    · exact ⟨v, hv, by simp⟩
    · exact ⟨x, hx, by rw [if_neg hxv]⟩

theorem image_subst_notMem {v u : Nat} {S : Finset Var} (hv : v ∉ S) :
    S.image (fun w => if w == v then u else w) = S := by
  ext x
  simp only [Finset.mem_image, beq_iff_eq]
  constructor
  · rintro ⟨y, hy, rfl⟩
    by_cases hyv : y = v
    · exact absurd (hyv ▸ hy) hv
    · rwa [if_neg hyv]
  · intro hx
    refine ⟨x, hx, ?_⟩
    by_cases hxv : x = v
    · exact absurd (hxv ▸ hx) hv
    · rw [if_neg hxv]

/-- The constraint of a partition with a substituted right-hand side. -/
theorem replace_partp_toConstraint (v u : Nat) (p : LPart) :
    (⟨(if p.lhs == v then u else p.lhs),
      ⟨p.rhs.abstr.map (fun w => if w == v then u else w), p.rhs.conc⟩, p.inf⟩
      : LPart).toConstraint
      = mk (if p.lhs == v then u else p.lhs)
          ((vset p.toConstraint).image (fun w => if w == v then u else w))
          p.toConstraint.conc := by
  have hmap : (p.rhs.abstr.map (fun w => if w == v then u else w)).elems.toFinset
      = (p.rhs.abstr.elems.toFinset).image (fun w => if w == v then u else w) :=
    SSet.fs_map (α := Nat) (β := Nat) p.rhs.abstr _
  unfold LPart.toConstraint
  dsimp only
  simp only [vset_mk, conc_mk]
  rw [hmap]

theorem mem_ofList_queue {ps : List LPart} {x : LPart} (h : x ∈ (PQueue.ofList ps).elems) :
    x ∈ ps := by
  rcases mem_concatNP ps PQueue.empty h with h' | h'
  · cases h'
  · exact h'

/-- **`Constraints.replace`**: rewriting one partition through the link `v <- (u)` is a
substitution on the right (`SubstStep`), a rename on the left (`renameLhs`) and -- when both
`v` and `u` occur on the right -- the de-duplication fact `u <- ()` (`dedup`). -/
theorem replace_run {G : System} {v u : Nat} {p : LPart}
    (hpG : p.toConstraint ∈ G) (hlink : mk v {u} (∅ : Row) ∈ G) (hvu : v ≠ u) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ ∀ x ∈ (replace v u p).elems, x.toConstraint ∈ H := by
  set S := vset p.toConstraint with hS
  set K := p.toConstraint.conc with hK
  set f : Var → Var := fun w => if w == v then u else w with hf
  have hpc : p.toConstraint = mk p.lhs S K := by
    rw [hS, hK]
    unfold LPart.toConstraint
    simp only [vset_mk, conc_mk]
  -- Phase 1: the right-hand side.
  obtain ⟨H1, hrun1, hsub1, hc1⟩ :
      ∃ H1 : System, LoopRun G H1 ∧ G ⊆ H1 ∧ mk p.lhs (S.image f) K ∈ H1 := by
    by_cases hv : v ∈ S
    · refine ⟨insert (mk p.lhs ((S.erase v) ∪ {u}) (K ∪ ∅)) G,
        Relation.ReflTransGen.single (LoopRel.nongen (NonGenStep.subst ?_)),
        Finset.subset_insert _ _, ?_⟩
      · have happ : SubstApp G (mk p.lhs S K) (mk v {u} (∅ : Row)) :=
          ⟨hpc ▸ hpG, hlink, by rw [lhs_mk, vset_mk]; exact hv⟩
        have hst := SubstStep.intro happ
        simpa only [substResult, lhs_mk, vset_mk, conc_mk] using hst
      · have hrw : (S.erase v) ∪ {u} = S.image f := by
          rw [hf, image_subst_mem hvu hv]
          ext x
          simp only [Finset.mem_union, Finset.mem_singleton, Finset.mem_insert]
          tauto
        rw [hrw, Finset.union_empty]
        exact Finset.mem_insert_self _ _
    · refine ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, ?_⟩
      rw [hf, image_subst_notMem hv, ← hpc]
      exact hpG
  -- Phase 2: the left-hand side.
  obtain ⟨H2, hrun2, hsub2, hc2⟩ :
      ∃ H2 : System, LoopRun G H2 ∧ G ⊆ H2 ∧
        mk (if p.lhs == v then u else p.lhs) (S.image f) K ∈ H2 := by
    by_cases hl : p.lhs = v
    · subst hl
      refine ⟨insert (mk u (S.image f) K) H1,
        hrun1.tail (LoopRel.renameLhs (a := p.lhs) (b := u) hc1 (hsub1 hlink)),
        hsub1.trans (Finset.subset_insert _ _), ?_⟩
      · rw [if_pos (by simp)]
        exact Finset.mem_insert_self _ _
    · refine ⟨H1, hrun1, hsub1, ?_⟩
      rw [if_neg (by simpa using hl)]
      exact hc1
  have hpartp : (⟨(if p.lhs == v then u else p.lhs),
      ⟨p.rhs.abstr.map f, p.rhs.conc⟩, p.inf⟩ : LPart).toConstraint ∈ H2 := by
    rw [replace_partp_toConstraint]
    exact hc2
  -- Phase 3: the de-duplication fact, when `replace` emits it.
  unfold replace
  split
  · rename_i hdd
    rw [Bool.and_eq_true] at hdd
    have hvS : v ∈ S := by
      rw [hS, LPart.vset_toConstraint]
      exact List.mem_toFinset.mpr ((SSet.contains_iff p.rhs.abstr v).mp hdd.1)
    have huS : u ∈ S := by
      rw [hS, LPart.vset_toConstraint]
      exact List.mem_toFinset.mpr ((SSet.contains_iff p.rhs.abstr u).mp hdd.2)
    refine ⟨insert (mk u ∅ (∅ : Row)) H2, hrun2.tail ?_,
      hsub2.trans (Finset.subset_insert _ _), ?_⟩
    · refine LoopRel.dedup (hsub2 (hpc ▸ hpG)) (hsub2 hlink) hvS ?_ ?_
      · exact Finset.mem_erase.mpr ⟨fun hh => hvu hh.symm, huS⟩
      · exact Finset.mem_singleton_self u
    · intro x hx
      rcases List.mem_cons.mp (mem_ofList_queue hx) with rfl | hx'
      · exact Finset.mem_insert_of_mem hpartp
      · rw [List.mem_singleton] at hx'
        subst hx'
        have : (⟨u, RHS.empty, some Inference.deDuplication⟩ : LPart).toConstraint
            = mk u ∅ (∅ : Row) := rfl
        rw [this]
        exact Finset.mem_insert_self _ _
  · refine ⟨H2, hrun2, hsub2, ?_⟩
    intro x hx
    rw [List.mem_singleton.mp (mem_ofList_queue hx)]
    exact hpartp


theorem instantiate_fold_run {L : List Lbl} (hcoh : LblCoh L) {v u : Nat} (hvu : v ≠ u) :
    ∀ (ps : List LPart) {G : System} {q : PQueue}, QOk L q → (∀ p ∈ ps, POk L p) →
      (∀ x ∈ q.elems, x.toConstraint ∈ G) → (∀ p ∈ ps, p.toConstraint ∈ G) →
      mk v {u} (∅ : Row) ∈ G →
      ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
        ∀ x ∈ (ps.foldl (fun nq p => nq.concatP (replace v u p).elems) q).elems,
          x.toConstraint ∈ H
  | [], G, _, _, _, hqG, _, _ => ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, hqG⟩
  | p :: ps, G, q, hq, hps, hqG, hpsG, hlink => by
    obtain ⟨H1, hrun1, hsub1, hr1⟩ := replace_run (hpsG p (by simp)) hlink hvu
    obtain ⟨H2, hrun2, hsub2, hq2⟩ := concatP_run hcoh (replace v u p).elems hq
      (fun x hx => replace_ok (hps p (by simp)) x hx)
      (fun x hx => hsub1 (hqG x hx)) hr1
    obtain ⟨H3, hrun3, hsub3, hq3⟩ := instantiate_fold_run hcoh hvu ps
      (QOk.concatP _ _ hq (fun x hx => replace_ok (hps p (by simp)) x hx))
      (fun r hr => hps r (by simp [hr])) hq2
      (fun r hr => hsub2 (hsub1 (hpsG r (by simp [hr])))) (hsub2 (hsub1 hlink))
    exact ⟨H3, (hrun1.trans hrun2).trans hrun3,
      (hsub1.trans hsub2).trans hsub3, hq3⟩

/-- The constraint an environment binding denotes after `instantiateType(v, VarT(u))` has
rewritten it. -/
theorem env_instantiate_alias_run {G : System} {v u w : Nat} (hlink : mk v {u} (∅ : Row) ∈ G)
    (hw : mk w {v} (∅ : Row) ∈ G) : LoopRel G (insert (mk w {u} (∅ : Row)) G) := by
  refine LoopRel.nongen (NonGenStep.subst ?_)
  have happ : SubstApp G (mk w {v} (∅ : Row)) (mk v {u} (∅ : Row)) :=
    ⟨hw, hlink, by rw [lhs_mk, vset_mk]; exact Finset.mem_singleton_self v⟩
  have hst := SubstStep.intro happ
  have hrw : ({v} : Finset Var).erase v ∪ {u} = ({u} : Finset Var) := by
    rw [Finset.erase_singleton]; simp
  simpa only [substResult, lhs_mk, vset_mk, conc_mk, hrw, Finset.union_empty] using hst

/-- **`Constraints.instantiate`**: the environment records `v <- (u)`, every partition
mentioning `v` is rewritten through it and REMOVED from both queues, and every alias that
pointed at `v` is redirected. -/
theorem instantiate_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {ns : Names} {v u : Nat}
    {incm proc : PQueue} {env : Env} {ni np : PQueue} {e : Env}
    (hi : QOk L incm) (hp : QOk L proc)
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (heG : ∀ b ∈ env.binds, EnvVal.toConstraint b.1 b.2 ∈ G)
    (hlink : mk v {u} (∅ : Row) ∈ G) (hvu : v ≠ u)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      (∀ x ∈ ni.elems, x.toConstraint ∈ H) ∧ (∀ x ∈ np.elems, x.toConstraint ∈ H) ∧
      (∀ b ∈ e.binds, EnvVal.toConstraint b.1 b.2 ∈ H) := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    -- Phase A: redirect every alias that pointed at `v`.
    obtain ⟨H1, hrun1, hsub1, hA⟩ :=
      adds_list (G := G)
        (env.binds.filterMap (fun b => match b.2 with
          | .alias z => if z = v then some (mk b.1 {u} (∅ : Row)) else none
          | .emptyRow => none))
        (by
          intro c hc
          obtain ⟨b, hb, hbc⟩ := List.mem_filterMap.mp hc
          obtain ⟨w0, val0⟩ := b
          cases val0 with
          | emptyRow => exact absurd hbc (by simp)
          | «alias» z =>
            dsimp only at hbc
            split at hbc
            · rename_i hzv
              subst hzv
              rw [Option.some.injEq] at hbc
              subst hbc
              intro H hGH
              exact env_instantiate_alias_run (hGH hlink) (hGH (heG _ hb))
            · exact absurd hbc (by simp))
    -- Phase B: the rewritten partitions.
    obtain ⟨H2, hrun2, hsub2, hq2⟩ := instantiate_fold_run hcoh hvu
      ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1).elems
      (hi.partition_snd _)
      (fun x hx => SOk.concat (hp.partition_fst _) (hi.partition_fst _) x hx)
      (fun x hx => hsub1 (hiG x (List.mem_of_mem_filter hx)))
      (fun x hx => hsub1 (by
        rcases SSet.mem_concat hx with hx' | hx'
        · exact hpG x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))
        · exact hiG x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))))
      (hsub1 hlink)
    refine ⟨H2, hrun1.trans hrun2, hsub1.trans hsub2, hq2, ?_, ?_⟩
    · intro x hx
      exact hsub2 (hsub1 (hpG x (List.mem_of_mem_filter hx)))
    · intro b hb
      simp only [Env.instantiate, List.mem_append, List.mem_map, List.mem_singleton] at hb
      rcases hb with ⟨b0, hb0, rfl⟩ | hb
      · obtain ⟨w0, val0⟩ := b0
        cases val0 with
        | emptyRow => exact hsub2 (hsub1 (heG _ hb0))
        | «alias» z =>
          dsimp only
          by_cases hzv : z = v
          · subst hzv
            rw [if_pos (by simp)]
            refine hsub2 (hA (mk w0 {u} (∅ : Row)) ?_)
            exact List.mem_filterMap.mpr ⟨(w0, EnvVal.alias z), hb0, by simp⟩
          · rw [if_neg (by simpa using hzv)]
            exact hsub2 (hsub1 (heG _ hb0))
      · subst hb
        exact hsub2 (hsub1 hlink)


theorem unifyVars_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {ns : Names} {v u : Nat}
    {incm proc : PQueue} {env : Env} {ni np : PQueue} {e : Env}
    (hi : QOk L incm) (hp : QOk L proc)
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (heG : ∀ b ∈ env.binds, EnvVal.toConstraint b.1 b.2 ∈ G)
    (hlink : mk v {u} (∅ : Row) ∈ G)
    (h : unifyVars ns v u incm proc env = .ok (ni, np, e)) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      (∀ x ∈ ni.elems, x.toConstraint ∈ H) ∧ (∀ x ∈ np.elems, x.toConstraint ∈ H) ∧
      (∀ b ∈ e.binds, EnvVal.toConstraint b.1 b.2 ∈ H) := by
  simp only [unifyVars] at h
  split at h
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, hiG, hpG, heG⟩
  · rename_i hvu
    exact instantiate_run hcoh hi hp hiG hpG heG hlink (by simpa using hvu) h

/-! ## 9. `makeEmpty` -/

theorem env_instantiate_empty_run {G : System} {v w : Nat} (hv : mk v ∅ (∅ : Row) ∈ G)
    (hw : mk w {v} (∅ : Row) ∈ G) : LoopRel G (insert (mk w ∅ (∅ : Row)) G) := by
  refine LoopRel.nongen (NonGenStep.subst ?_)
  have happ : SubstApp G (mk w {v} (∅ : Row)) (mk v ∅ (∅ : Row)) :=
    ⟨hw, hv, by rw [lhs_mk, vset_mk]; exact Finset.mem_singleton_self v⟩
  have hst := SubstStep.intro happ
  have hrw : ({v} : Finset Var).erase v ∪ ∅ = (∅ : Finset Var) := by
    rw [Finset.erase_singleton]; simp
  simpa only [substResult, lhs_mk, vset_mk, conc_mk, hrw, Finset.union_empty] using hst

/-- A partition whose concrete part is empty denotes a constraint with no labels. -/
theorem toConstraint_conc_empty {p : LPart} (h : p.rhs.conc.isEmpty = true) :
    p.toConstraint = mk p.lhs (vset p.toConstraint) (∅ : Row) := by
  have hnil : p.rhs.conc.elems = [] := by simpa [SSet.isEmpty] using h
  unfold LPart.toConstraint
  simp only [vset_mk, hnil, List.map_nil, List.toFinset_nil]

/-- The constraint of a partition with `v` erased from its right-hand side. -/
theorem toConstraint_erase (p : LPart) (v : Nat) (i : Option Inference) :
    (⟨p.lhs, p.rhs.erase v, i⟩ : LPart).toConstraint
      = mk p.lhs ((vset p.toConstraint).erase v) p.toConstraint.conc := by
  have hex : (p.rhs.abstr.excl v).elems.toFinset = (p.rhs.abstr.elems.toFinset).erase v :=
    SSet.fs_excl (α := Nat) p.rhs.abstr v
  unfold LPart.toConstraint RHS.erase
  dsimp only
  simp only [vset_mk, conc_mk]
  rw [hex]

/-- **`Constraints.makeEmpty`**: every partition mentioning `v` is erased through `v <- ()`
(`SubstStep`), an all-variable definition of `v` forces its parts empty (`emptyProp`), and
`v <- ()` itself is retained -- in the environment, which is where `makeEmptyE` puts it. -/
theorem makeEmpty_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {ns : Names} {v : Nat}
    {incm proc : PQueue} {env : Env} {ni np : PQueue} {e : Env}
    (hi : QOk L incm) (hp : QOk L proc)
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (heG : ∀ b ∈ env.binds, EnvVal.toConstraint b.1 b.2 ∈ G)
    (hv : mk v ∅ (∅ : Row) ∈ G)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      (∀ x ∈ ni.elems, x.toConstraint ∈ H) ∧ (∀ x ∈ np.elems, x.toConstraint ∈ H) ∧
      (∀ b ∈ e.binds, EnvVal.toConstraint b.1 b.2 ∈ H) := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, h2⟩ := except_bind_ok h
  have hderived : SOk L nps ∧ ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      ∀ x ∈ nps.elems, x.toConstraint ∈ H := by
    refine foldl_except_inv
      (P := fun (S : SSet LPart) => SOk L S ∧ ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
        ∀ x ∈ S.elems, x.toConstraint ∈ H)
      (Q := fun (x : LPart) => POk L x ∧ x.toConstraint ∈ G) ?_ _ ?_ _ ?_ _ hnps
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨haOk, H, hrun, hsub, ha⟩ := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · rename_i hlhs
          have hxv : x.lhs = v := by simpa using hlhs
          split at hb
          · simp only [pure, Except.pure, Except.ok.injEq] at hb
            subst hb; exact ⟨haOk, H, hrun, hsub, ha⟩
          · split at hb
            · rename_i hconc
              simp only [pure, Except.pure, Except.ok.injEq] at hb
              subst hb
              obtain ⟨H2, hrun2, hsub2, hmem2⟩ := adds_list (G := H)
                ((x.rhs.abstr.elems.map (fun w => mk w ∅ (∅ : Row))))
                (by
                  intro c hc
                  obtain ⟨w, hw, rfl⟩ := List.mem_map.mp hc
                  intro Hx hHx
                  have h1 : x.toConstraint ∈ Hx := hHx (hsub hx.2)
                  rw [toConstraint_conc_empty hconc] at h1
                  have h3 : mk x.lhs ∅ (∅ : Row) ∈ Hx := by rw [hxv]; exact hHx (hsub hv)
                  exact LoopRel.emptyProp h1 h3
                    (by rw [LPart.vset_toConstraint]; exact List.mem_toFinset.mpr hw))
              refine ⟨haOk.concat (SOk.map (fun _ => POk.ofEmpty _ _)),
                H2, hrun.trans hrun2, hsub.trans hsub2, ?_⟩
              intro y hy
              rcases SSet.mem_concat hy with hy' | hy'
              · exact hsub2 (ha y hy')
              · obtain ⟨w, hw, rfl⟩ := SSet.mem_map hy'
                exact hmem2 _ (List.mem_map.mpr ⟨w, hw, rfl⟩)
            · exact absurd hb (by simp)
        · simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          have hxc : x.toConstraint = mk x.lhs (vset x.toConstraint) x.toConstraint.conc := by
            unfold LPart.toConstraint; simp only [vset_mk, conc_mk]
          refine ⟨haOk.incl (POk.mk' (SSet.nodup_excl hx.1.abstr v) hx.1.conc), ?_⟩
          by_cases hvS : v ∈ vset x.toConstraint
          · refine ⟨insert ((⟨x.lhs, x.rhs.erase v, x.inf⟩ : LPart).toConstraint) H,
              hrun.tail ?_, hsub.trans (Finset.subset_insert _ _), ?_⟩
            · rw [toConstraint_erase]
              refine LoopRel.nongen (NonGenStep.subst ?_)
              have happ : SubstApp H (mk x.lhs (vset x.toConstraint) x.toConstraint.conc)
                  (mk v ∅ (∅ : Row)) :=
                ⟨hxc ▸ hsub hx.2, hsub hv, by rw [lhs_mk, vset_mk]; exact hvS⟩
              have hst := SubstStep.intro happ
              simpa only [substResult, lhs_mk, vset_mk, conc_mk, Finset.union_empty] using hst
            · intro y hy
              rcases SSet.mem_incl hy with hy' | rfl
              · exact Finset.mem_insert_of_mem (ha y hy')
              · exact Finset.mem_insert_self _ _
          · -- `v` does not occur: the erasure is the IDENTITY, so no step at all
            refine ⟨H, hrun, hsub, ?_⟩
            intro y hy
            rcases SSet.mem_incl hy with hy' | rfl
            · exact ha y hy'
            · rw [toConstraint_erase, Finset.erase_eq_of_notMem hvS, ← hxc]
              exact hsub hx.2
    · intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact ⟨hi.partition_fst _ x hx', hiG x
          (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))⟩
      · exact ⟨hp.partition_fst _ x hx', hpG x
          (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))⟩
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      exact ⟨SOk.empty, G, Relation.ReflTransGen.refl, Finset.Subset.refl G,
        by intro y hy; cases hy⟩
  obtain ⟨hnpsOk, H, hrun, hsub, hnpsH⟩ := hderived
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨rfl, rfl, rfl⟩ := h2
      obtain ⟨H1, hrun1, hsub1, hA⟩ :=
        adds_list (G := H)
          (env.binds.filterMap (fun b => match b.2 with
            | .alias z => if z = v then some (mk b.1 ∅ (∅ : Row)) else none
            | .emptyRow => none))
          (by
            intro c hc
            obtain ⟨b, hb, hbc⟩ := List.mem_filterMap.mp hc
            obtain ⟨w0, val0⟩ := b
            cases val0 with
            | emptyRow => exact absurd hbc (by simp)
            | «alias» z =>
              dsimp only at hbc
              split at hbc
              · rename_i hzv
                subst hzv
                rw [Option.some.injEq] at hbc
                subst hbc
                intro Hx hHx
                exact env_instantiate_empty_run (hHx (hsub hv)) (hHx (hsub (heG _ hb)))
              · exact absurd hbc (by simp))
      obtain ⟨H2, hrun2, hsub2, hq2⟩ := concatP_run hcoh
        (trim nps (proc.partition (fun p => p.involves v)).2).elems (hi.partition_snd _)
        (fun x hx => hnpsOk x (SSet.mem_filter hx))
        (fun x hx => hsub1 (hsub (hiG x (List.mem_of_mem_filter hx))))
        (fun x hx => hsub1 (hnpsH x (SSet.mem_filter hx)))
      refine ⟨H2, (hrun.trans hrun1).trans hrun2, (hsub.trans hsub1).trans hsub2, hq2, ?_, ?_⟩
      · intro x hx
        exact hsub2 (hsub1 (hsub (hpG x (List.mem_of_mem_filter hx))))
      · intro b hb
        simp only [Env.instantiate, List.mem_append, List.mem_map, List.mem_singleton] at hb
        rcases hb with ⟨b0, hb0, rfl⟩ | hb
        · obtain ⟨w0, val0⟩ := b0
          cases val0 with
          | emptyRow => exact hsub2 (hsub1 (hsub (heG _ hb0)))
          | «alias» z =>
            dsimp only
            by_cases hzv : z = v
            · subst hzv
              rw [if_pos (by simp)]
              refine hsub2 (hA (mk w0 ∅ (∅ : Row)) ?_)
              exact List.mem_filterMap.mpr ⟨(w0, EnvVal.alias z), hb0, by simp⟩
            · rw [if_neg (by simpa using hzv)]
              exact hsub2 (hsub1 (hsub (heG _ hb0)))
        · subst hb
          exact hsub2 (hsub1 (hsub hv))


/-! ## 10. The dispatch -/

theorem findRHS_witness {q : PQueue} {r : RHS} {w : Nat} (h : q.findRHS r = some w) :
    ∃ x ∈ q.elems, x.rhs.eqv r = true ∧ x.lhs = w := by
  unfold PQueue.findRHS at h
  cases hf : q.elems.find? (fun x => x.rhs.eqv r) with
  | none => rw [hf] at h; exact absurd h (by simp)
  | some x =>
    rw [hf] at h
    simp only [Option.map_some, Option.some.injEq] at h
    exact ⟨x, List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf, h⟩

theorem toConstraint_of_isEmpty {p : LPart} (h : p.rhs.isEmpty = true) :
    p.toConstraint = mk p.lhs ∅ (∅ : Row) := by
  rw [RHS.isEmpty, Bool.and_eq_true] at h
  have h1 : p.rhs.abstr.elems = [] := by simpa [SSet.isEmpty] using h.1
  have h2 : p.rhs.conc.elems = [] := by simpa [SSet.isEmpty] using h.2
  unfold LPart.toConstraint
  simp only [h1, h2, List.map_nil, List.toFinset_nil]

theorem toConstraint_of_single {p : LPart} {u : Nat} (h : p.rhs.single? = some u) :
    p.toConstraint = mk p.lhs {u} (∅ : Row) := by
  unfold RHS.single? at h
  split at h
  · rename_i hc
    have h2 : p.rhs.conc.elems = [] := by simpa [SSet.isEmpty] using hc
    unfold SSet.single? at h
    split at h
    · rename_i y hy
      rw [Option.some.injEq] at h
      subst h
      unfold LPart.toConstraint
      simp only [hy, h2, List.map_nil, List.toFinset_nil, List.toFinset_cons]
      rfl
    · exact absurd h (by simp)
  · exact absurd h (by simp)

theorem sys_subset {s : State} {H : System}
    (hpart : ∀ x ∈ s.parts, x.toConstraint ∈ H)
    (henv : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ H) : sys s ⊆ H := by
  intro c hc
  rcases mem_sys.mp hc with ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
  · exact hpart p hp
  · exact henv b hb

/-- The three dispatch branches whose refinement is proved here: the COMMON-partition
unification, `makeEmpty`, and the singleton `unify`.  They are exactly the branches that
manipulate the substitution environment, and exactly the ones no relation of the development
had.  The `concrete` and `learn` branches are excluded -- see `L3-THEOREMS.md`. -/
def LinkOrEmptyStep (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨ (r.rhs.single?).isSome = true

/-- **Refinement for the three environment branches.**  Every `continue` step the loop takes
through `common`, `empty` or `unify` is a run of `LoopRel` between the systems the two states
denote. -/
theorem step_refines {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : LoopRun (sys s) (sys s') := by
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    obtain ⟨hrOk, hrestOk⟩ := QOk.dequeue hw.incm hdq
    obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
    have hrestG : ∀ x ∈ rest.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_incm (hrestMem x hx)
    have hprocG : ∀ x ∈ s.proc.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_proc hx
    have henvG : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ sys s :=
      fun b hb' => mem_sys_of_env hb'
    have hrG : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
    cases hfr : s.proc.findRHS r.rhs with
    | some u =>
      rw [hfr] at h
      dsimp only at h
      obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := findRHS_witness hfr
      by_cases hru : r.lhs = u
      · rw [unifyVars, if_pos (by simpa using hru)] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact Relation.ReflTransGen.single (LoopRel.weaken
          (sys_subset (fun x hx => by
            rcases List.mem_append.mp hx with hx' | hx'
            · exact hrestG x hx'
            · exact hprocG x hx') henvG))
      · have hc0 : x0.toConstraint = (⟨u, r.rhs, none⟩ : LPart).toConstraint := by
          rw [← hx0lhs]
          exact toConstraint_congr hw.coh (hw.proc x0 hx0) hrOk hx0eq
        have hlinkStep : LoopRel (sys s) (insert (mk r.lhs {u} (∅ : Row)) (sys s)) := by
          refine LoopRel.nongen (NonGenStep.commonPart ?_)
          have happ : CommonPartApp (sys s) r.toConstraint x0.toConstraint := by
            refine ⟨hrG, hprocG x0 hx0, ?_, ?_, ?_⟩
            · rw [hc0]; simpa using hru
            · rw [hc0]; rfl
            · rw [hc0]; rfl
          have hst := CommonPartStep.intro happ
          unfold commonPartResult at hst
          rw [hc0] at hst
          exact hst
        have hsubG1 : sys s ⊆ insert (mk r.lhs {u} (∅ : Row)) (sys s) :=
          Finset.subset_insert _ _
        cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨H, hrun, hsub, hni, hnp, he⟩ := unifyVars_run hw.coh hrestOk hw.proc
            (fun x hx => hsubG1 (hrestG x hx)) (fun x hx => hsubG1 (hprocG x hx))
            (fun b hb' => hsubG1 (henvG b hb')) (Finset.mem_insert_self _ _) hres
          exact (Relation.ReflTransGen.single hlinkStep).trans
            (hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
              rcases List.mem_append.mp hx with hx' | hx'
              · exact hni x hx'
              · exact hnp x hx') he)))
    | none =>
      rw [hfr] at h
      dsimp only at h
      by_cases hempty : r.rhs.isEmpty = true
      · rw [if_pos hempty] at h
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨H, hrun, hsub, hni, hnp, he⟩ := makeEmpty_run hw.coh hrestOk hw.proc
            hrestG hprocG henvG (by rw [← toConstraint_of_isEmpty hempty]; exact hrG) hres
          exact hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
            rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx') he))
      · rw [if_neg hempty] at h
        have hsing : (r.rhs.single?).isSome = true := by
          rcases hb r rest hdq with hh | hh | hh
          · rw [hfr] at hh; exact absurd hh (by simp)
          · exact absurd hh hempty
          · exact hh
        obtain ⟨u, hu⟩ := Option.isSome_iff_exists.mp hsing
        have habs : ¬(r.rhs.abstr.isEmpty = true) := by
          intro hc
          have hnil : r.rhs.abstr.elems = [] := by simpa [SSet.isEmpty] using hc
          unfold RHS.single? at hu
          split at hu
          · unfold SSet.single? at hu
            rw [hnil] at hu
            exact absurd hu (by simp)
          · exact absurd hu (by simp)
        rw [if_neg habs, hu] at h
        dsimp only at h
        have hlinkStep : LoopRel (sys s) (insert (mk u {r.lhs} (∅ : Row)) (sys s)) := by
          refine LoopRel.linkSymm (a := r.lhs) (b := u) ?_
          rw [← toConstraint_of_single hu]; exact hrG
        have hsubG1 : sys s ⊆ insert (mk u {r.lhs} (∅ : Row)) (sys s) :=
          Finset.subset_insert _ _
        cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨H, hrun, hsub, hni, hnp, he⟩ := unifyVars_run hw.coh hrestOk hw.proc
            (fun x hx => hsubG1 (hrestG x hx)) (fun x hx => hsubG1 (hprocG x hx))
            (fun b hb' => hsubG1 (henvG b hb')) (Finset.mem_insert_self _ _) hres
          exact (Relation.ReflTransGen.single hlinkStep).trans
            (hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
              rcases List.mem_append.mp hx with hx' | hx'
              · exact hni x hx'
              · exact hnp x hx') he)))

/-- **Satisfiability is preserved along every `continue` step of the three branches.** -/
theorem step_sat {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s') :=
  (step_refines hw hb h).sat


/-! ## 11. The `died` paths: which of them are refutations

Four of the seven messages `step` can die with are REFUTATIONS -- the system the state
denotes has no model, so (with satisfiability preserved along the `continue` steps) neither
does the input.  Three are not: the skolem refusal is a KINDING error, and the two
reinstantiation panics are internal-invariant failures. -/

/-- **`selfSubstitution`'s "Infinite row partition"** is a refutation: a variable that is one
of its own parts must contribute nothing, so a nonempty concrete part is a contradiction. -/
theorem selfSubst_refutes {G : System} {v : Var} {S : Finset Var} {K : Row}
    (hmem : mk v S K ∈ G) (hself : v ∈ S) (hK : K ≠ ∅) : ¬ SSat G := by
  rintro ⟨rho, hm⟩
  have hs := (sat_mk_iff rho v S K).mp (hm _ hmem)
  have hsub : K ⊆ rho v := by rw [hs.1]; exact Finset.subset_union_left
  exact hK (eq_empty_of_disjoint_self ((hs.2.1 v hself).mono_right hsub))

/-- **`RHS.merge`'s "Fields appear twice in row"** is a refutation: the two concrete parts
belong to a whole and one of its parts, so they are disjoint. -/
theorem merge_refutes {G : System} {c v : Var} {S S' : Finset Var} {K K' : Row}
    (h1 : mk c S K ∈ G) (h2 : mk v S' K' ∈ G) (hv : v ∈ S) (hne : (K ∩ K').Nonempty) :
    ¬ SSat G := by
  rintro ⟨rho, hm⟩
  have hs1 := (sat_mk_iff rho c S K).mp (hm _ h1)
  have hs2 := (sat_mk_iff rho v S' K').mp (hm _ h2)
  have hK' : K' ⊆ rho v := by rw [hs2.1]; exact Finset.subset_union_left
  have hdis : Disjoint K K' := (hs1.2.1 v hv).mono_right hK'
  obtain ⟨l, hl⟩ := hne
  rw [Finset.mem_inter] at hl
  exact Finset.disjoint_left.mp hdis hl.1 hl.2

/-- **`makeEmpty`'s "Incompatible instantiations"** is a refutation: `v` is empty and one of
its definitions carries a label. -/
theorem incompatible_refutes {G : System} {v : Var} {S : Finset Var} {K : Row}
    (h1 : mk v ∅ (∅ : Row) ∈ G) (h2 : mk v S K ∈ G) (hK : K ≠ ∅) : ¬ SSat G := by
  rintro ⟨rho, hm⟩
  have he : rho v = ∅ := sat_empty_iff.mp (hm _ h1)
  have hs := (sat_mk_iff rho v S K).mp (hm _ h2)
  have hsub : K ⊆ rho v := by rw [hs.1]; exact Finset.subset_union_left
  rw [he] at hsub
  exact hK (Finset.subset_empty.mp hsub)

/-- **`ensureSuperset`'s "Row types failed to unify"** is a refutation: every definition of a
variable whose row is `C` may only carry labels of `C`. -/
theorem ensureSuperset_refutes {G : System} {v : Var} {S : Finset Var} {K C : Row}
    (h1 : mk v ∅ C ∈ G) (h2 : mk v S K ∈ G) (hnsub : ¬ K ⊆ C) : ¬ SSat G := by
  rintro ⟨rho, hm⟩
  have hC : rho v = C := by
    have := (sat_mk_iff rho v ∅ C).mp (hm _ h1)
    simpa using this.1
  have hs := (sat_mk_iff rho v S K).mp (hm _ h2)
  have hsub : K ⊆ rho v := by rw [hs.1]; exact Finset.subset_union_left
  rw [hC] at hsub
  exact hnsub hsub

/-! ### From the message to the refutation -/

theorem foldl_except_ok_of_all {α β : Type} {Q : α → Prop}
    {f : Except String β → α → Except String β}
    (hf : ∀ (acc : Except String β) (x : α), Q x → (∃ b, acc = .ok b) → ∃ b, f acc x = .ok b) :
    ∀ (l : List α), (∀ x ∈ l, Q x) → ∀ (acc : Except String β), (∃ b, acc = .ok b) →
      ∃ b, l.foldl f acc = .ok b := by
  intro l
  induction l with
  | nil => intro _ acc hacc; exact hacc
  | cons x l ih =>
    intro hQ acc hacc
    exact ih (fun y hy => hQ y (by simp [hy])) (f acc x) (hf acc x (hQ x (by simp)) hacc)

/-- A partition with a nonempty concrete part denotes a constraint with a nonempty label
set. -/
theorem conc_ne_of_not_isEmpty {p : LPart} (h : ¬ p.rhs.conc.isEmpty = true) :
    p.toConstraint.conc ≠ ∅ := by
  intro hc
  have hnil : p.rhs.conc.elems ≠ [] := by
    intro hh; exact h (by simp [SSet.isEmpty, hh])
  obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil _ hnil
  have : y.n ∈ p.toConstraint.conc :=
    List.mem_toFinset.mpr (List.mem_map.mpr ⟨y, hy, rfl⟩)
  rw [hc] at this
  exact absurd this (Finset.notMem_empty _)

/-- **Every death of `makeEmpty` is a refutation**, except the two the model itself names:
the SKOLEM refusal, which is a kinding error, and the reinstantiation panic, which is an
internal-invariant failure. -/
theorem makeEmpty_died {G : System} {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {m : String}
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hv : mk v ∅ (∅ : Row) ∈ G)
    (h : makeEmpty ns v incm proc env = .error m) :
    ¬ SSat G ∨
      m = "Cannot unify skolem variable with empty relation " ++ varStr ns v ∨
      m = "panic: reinstantiated type " ++ varStr ns v ++ " to ConcreteRho(-,Set())" ++
          " but it was already bound" := by
  simp only [makeEmpty] at h
  set F : Except String (SSet LPart) → LPart → Except String (SSet LPart) :=
    (fun (acc : Except String (SSet LPart)) (p : LPart) => do
        let s ← acc
        if p.lhs == v then
          if p.rhs.isEmpty then pure s
          else if p.rhs.conc.isEmpty then
            pure (s.concat (p.rhs.abstr.map
              (fun w => (⟨w, RHS.empty, some Inference.partitionEmpty⟩ : LPart))))
          else .error ("Incompatible instantiations of '" ++ varStr ns v ++ "'")
        else pure (s.incl ⟨p.lhs, p.rhs.erase v, p.inf⟩)) with hF
  cases hnps : ((incm.partition (fun p => p.involves v)).1.concat
      (proc.partition (fun p => p.involves v)).1).elems.foldl F (.ok SSet.empty) with
  | ok nps =>
    rw [hnps] at h
    simp only [bind, Except.bind] at h
    split at h
    · exact Or.inr (Or.inl (by rw [Except.error.injEq] at h; exact h.symm))
    · split at h
      · exact Or.inr (Or.inr (by rw [Except.error.injEq] at h; exact h.symm))
      · exact absurd h (by simp)
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


/-! ## 12. Along a run -/

/-- A `died` state denotes the system its predecessor denoted: the death is raised before
either queue or the environment is written. -/
theorem step_died_sys {s s' : State} {m : String} (h : step s = .died m s') : sys s' = sys s := by
  simp only [step, State.log] at h
  repeat' split at h
  all_goals (cases h <;> rfl)

/-- Every state of a run takes one of the three refined branches. -/
def RunLinkOrEmpty : Nat → State → Prop
  | 0, _ => True
  | n + 1, s => LinkOrEmptyStep s ∧ ∀ s', step s = .continue s' → RunLinkOrEmpty n s'

/-- **Satisfiability along a run.** -/
theorem run_sat : ∀ (n : Nat) {s : State}, Wf s → RunLinkOrEmpty n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → SSat (sys s')
  | 0, s, _, _, hsat, s', hres => by
    simp only [run] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres; subst hres; exact hsat
  | n + 1, s, hw, hb, hsat, s', hres => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [step_done hst]
        exact hsat
      · exact absurd hres (by simp)
    | died m0 s0 => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s0 =>
      rw [hst] at hres
      exact run_sat n (step_wf hw hst) (hb.2 s0 hst) (step_sat hw hb.1 hst hsat) s' hres

/-- **A refuting death refutes the INPUT.**  If a run ends in a `died` whose state denotes an
unsatisfiable system -- which §11 shows is the case for the `Incompatible instantiations`
death, and for the three other refuting messages -- then the system the run STARTED from has
no model either. -/
theorem run_refutes : ∀ (n : Nat) {s : State}, Wf s → RunLinkOrEmpty n s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' → ¬ SSat (sys s') → ¬ SSat (sys s)
  | 0, s, _, _, m, s', hres, _ => by simp only [run] at hres; exact absurd hres (by simp)
  | n + 1, s, hw, hb, m, s', hres, hns => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 => rw [hst] at hres; exact absurd hres (by simp)
    | died m0 s0 =>
      rw [hst] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨-, rfl⟩ := hres
      rw [step_died_sys hst] at hns
      exact hns
    | «continue» s0 =>
      rw [hst] at hres
      exact fun hsat => run_refutes n (step_wf hw hst) (hb.2 s0 hst) m s' hres hns
        (step_sat hw hb.1 hst hsat)

end Rowpartition.Loop
