/-
# Row-partition constraints: foundations

Ermine (an ML-family language with row-typed records/relations) has exactly one row
constraint, PARTITION, written `a <- (b, c, (|Foo|))`.  It says: the row `a` is the
DISJOINT UNION of the rows `b`, `c` and the concrete singleton `{Foo}` -- one relation
carrying concatenation, disjointness and completeness at once.

Rows are finite sets of field labels drawn from an OPEN (unbounded) universe.  A row
expression is either a variable or a fully concrete finite label set: no complement, no
intersection, no nesting.  A constraint system is a finite CONJUNCTION of partition
constraints (no negation, no disjunction at the constraint level).

The centrepiece of this file is `sat_iff_forall_label`: satisfaction is *pointwise in
the label*, so one row-partition problem is a family of independent Boolean problems,
one per label.  That is the justification for a per-label SAT encoding.  Section 7 adds
the two facts that make the encoding usable: a finite-support reconstruction theorem
(`satisfiable_iff_forall_label`) and, in section 8, the fact that ENTAILMENT decomposes
per label exactly when the hypothesis system is satisfiable -- with an explicit
counterexample showing the satisfiability hypothesis cannot be dropped.
-/
import Mathlib.Data.Finset.Basic
import Mathlib.Data.Finset.Lattice.Lemmas
import Mathlib.Data.Finset.Lattice.Fold
import Mathlib.Data.List.Pairwise

namespace Rowpartition

/-! ## 1. The object language -/

/-- Field labels, drawn from an open (unbounded) universe. -/
abbrev Label := Nat

/-- Row variables. -/
abbrev Var := Nat

/-- A row is a finite set of labels. -/
abbrev Row := Finset Label

/-- A single partition constraint `lhs <- (vars..., conc)`.
The right-hand side is a LIST of variables (order irrelevant, repeats meaningful)
together with one concrete label set. -/
structure Constraint where
  /-- The row variable being partitioned. -/
  lhs : Var
  /-- The variable parts of the right-hand side. -/
  vars : List Var
  /-- The concrete part of the right-hand side. -/
  conc : Finset Label
deriving DecidableEq

/-- An assignment of a concrete row to every row variable. -/
abbrev Assign := Var → Row

/-- The parts of a constraint's right-hand side, under an assignment. -/
def parts (rho : Assign) (c : Constraint) : List Row := c.conc :: c.vars.map rho

/-- `rho` satisfies `c`: the left-hand row is the union of the parts, and the parts are
pairwise disjoint. -/
def Sat (rho : Assign) (c : Constraint) : Prop :=
  rho c.lhs = (parts rho c).foldr (· ∪ ·) ∅ ∧ (parts rho c).Pairwise Disjoint

/-- `rho` satisfies every constraint of the system `G`. -/
def Models (rho : Assign) (G : List Constraint) : Prop := ∀ c ∈ G, Sat rho c

/-- Semantic entailment. -/
def Entails (G : List Constraint) (c : Constraint) : Prop :=
  ∀ rho, Models rho G → Sat rho c

/-! ## 2. Generic list / finset plumbing -/

section Plumbing

variable {α : Type*}

/-- Membership in a `foldr`-union of a list of finsets. -/
theorem mem_foldr_union [DecidableEq α] (L : List (Finset α)) (a : α) :
    a ∈ L.foldr (· ∪ ·) ∅ ↔ ∃ s ∈ L, a ∈ s := by
  induction L with
  | nil => simp
  | cons t L ih => simp [ih]

/-- A `foldr`-or of a list of booleans is `true` iff some entry is. -/
theorem foldr_or_eq_true (M : List Bool) :
    M.foldr (· || ·) false = true ↔ ∃ x ∈ M, x = true := by
  induction M with
  | nil => simp
  | cons x M ih => simp [ih]

/-- Boolean equality is equality of the two `= true` propositions. -/
theorem bool_eq_iff (x y : Bool) : x = y ↔ (x = true ↔ y = true) := by
  cases x <;> cases y <;> simp

/-- `Pairwise` respects pointwise equivalence of relations. -/
theorem pairwise_congr {R S : α → α → Prop} {l : List α} (h : ∀ a b, R a b ↔ S a b) :
    l.Pairwise R ↔ l.Pairwise S := by
  induction l with
  | nil => simp
  | cons x l ih =>
    simp only [List.pairwise_cons, ih]
    refine and_congr ?_ Iff.rfl
    constructor
    · intro H y hy; exact (h x y).mp (H y hy)
    · intro H y hy; exact (h x y).mpr (H y hy)

/-- A universally quantified relation is pairwise iff it is pairwise at every index. -/
theorem pairwise_forall_comm {ι : Type*} (L : List α) (R : ι → α → α → Prop) :
    L.Pairwise (fun x y => ∀ i, R i x y) ↔ ∀ i, L.Pairwise (R i) := by
  induction L with
  | nil => simp
  | cons x L ih =>
    simp only [List.pairwise_cons, ih]
    constructor
    · rintro ⟨h1, h2⟩ i
      exact ⟨fun y hy => h1 y hy i, h2 i⟩
    · intro h
      exact ⟨fun y hy i => (h i).1 y hy, fun i => (h i).2⟩

/-- A relation holding between all pairs of members holds pairwise. -/
theorem pairwise_of_forall_mem {R : α → α → Prop} :
    ∀ {l : List α}, (∀ a ∈ l, ∀ b ∈ l, R a b) → l.Pairwise R := by
  intro l
  induction l with
  | nil => intro _; exact List.Pairwise.nil
  | cons x l ih =>
    intro h
    refine List.pairwise_cons.mpr ⟨fun y hy => h x (by simp) y (by simp [hy]), ih ?_⟩
    intro a ha b hb
    exact h a (by simp [ha]) b (by simp [hb])

/-- From a symmetric pairwise relation, any two DISTINCT members are related. -/
theorem pairwise_ne_imp {R : α → α → Prop} (hsymm : ∀ {a b : α}, R a b → R b a) :
    ∀ {l : List α}, l.Pairwise R → ∀ {a b : α}, a ∈ l → b ∈ l → a ≠ b → R a b := by
  intro l
  induction l with
  | nil => intro _ a b ha; cases ha
  | cons x l ih =>
    intro hp a b ha hb hab
    rw [List.pairwise_cons] at hp
    rcases List.mem_cons.mp ha with rfl | ha'
    · rcases List.mem_cons.mp hb with rfl | hb'
      · exact absurd rfl hab
      · exact hp.1 b hb'
    · rcases List.mem_cons.mp hb with rfl | hb'
      · exact hsymm (hp.1 a ha')
      · exact ih hp.2 ha' hb' hab

/-- A value occurring at least twice in a pairwise list is related to ITSELF. -/
theorem pairwise_self_of_two_le_count [DecidableEq α] {R : α → α → Prop} {a : α} :
    ∀ {l : List α}, l.Pairwise R → 2 ≤ l.count a → R a a := by
  intro l
  induction l with
  | nil => intro _ h; simp at h
  | cons x l ih =>
    intro hp hc
    rw [List.pairwise_cons] at hp
    by_cases hx : x = a
    · subst hx
      have hmem : x ∈ l := by
        by_contra hnot
        rw [List.count_cons] at hc
        rw [List.count_eq_zero.mpr hnot] at hc
        simp at hc
      exact hp.1 x hmem
    · rw [List.count_cons, if_neg (by simpa using hx)] at hc
      exact ih hp.2 (by omega)

end Plumbing

/-! ## 3. Basic API for `Sat` -/

section SatAPI

variable {rho : Assign} {c : Constraint}

theorem Sat.eq_union (h : Sat rho c) : rho c.lhs = (parts rho c).foldr (· ∪ ·) ∅ := h.1

theorem Sat.pairwise (h : Sat rho c) : (parts rho c).Pairwise Disjoint := h.2

theorem mem_parts_conc : c.conc ∈ parts rho c := by simp [parts]

theorem mem_parts_of_mem_vars {v : Var} (hv : v ∈ c.vars) : rho v ∈ parts rho c := by
  simp only [parts, List.mem_cons]
  exact Or.inr (List.mem_map.mpr ⟨v, hv, rfl⟩)

/-- Membership characterisation of the left-hand row. -/
theorem Sat.mem_lhs_iff (h : Sat rho c) (l : Label) :
    l ∈ rho c.lhs ↔ l ∈ c.conc ∨ ∃ v ∈ c.vars, l ∈ rho v := by
  rw [h.eq_union, mem_foldr_union]
  simp [parts]

/-- Every variable part is contained in the left-hand row. -/
theorem Sat.subset_lhs (h : Sat rho c) {v : Var} (hv : v ∈ c.vars) : rho v ⊆ rho c.lhs :=
  fun _ hl => (h.mem_lhs_iff _).mpr (Or.inr ⟨v, hv, hl⟩)

/-- The concrete part is contained in the left-hand row. -/
theorem Sat.conc_subset_lhs (h : Sat rho c) : c.conc ⊆ rho c.lhs :=
  fun _ hl => (h.mem_lhs_iff _).mpr (Or.inl hl)

/-- The variable parts are pairwise disjoint (as a `Pairwise` on the variable list). -/
theorem Sat.pairwise_vars (h : Sat rho c) :
    c.vars.Pairwise (fun v w => Disjoint (rho v) (rho w)) := by
  have h2 := h.pairwise
  simp only [parts, List.pairwise_cons] at h2
  exact List.pairwise_map.mp h2.2

/-- The concrete part is disjoint from every variable part. -/
theorem Sat.disjoint_conc (h : Sat rho c) {v : Var} (hv : v ∈ c.vars) :
    Disjoint c.conc (rho v) := by
  have h2 := h.pairwise
  simp only [parts, List.pairwise_cons] at h2
  exact h2.1 _ (List.mem_map.mpr ⟨v, hv, rfl⟩)

/-- DISTINCT variables of a constraint get disjoint rows. -/
theorem Sat.disjoint_of_ne (h : Sat rho c) {v w : Var} (hv : v ∈ c.vars) (hw : w ∈ c.vars)
    (hvw : v ≠ w) : Disjoint (rho v) (rho w) :=
  pairwise_ne_imp (fun hd => hd.symm) h.pairwise_vars hv hw hvw

/-- Distinct POSITIONS of the variable list get disjoint rows (this is the sharp form:
it applies even when the two positions carry the same variable). -/
theorem Sat.disjoint_getElem (h : Sat rho c) {i j : ℕ} (hi : i < c.vars.length)
    (hj : j < c.vars.length) (hij : i ≠ j) :
    Disjoint (rho c.vars[i]) (rho c.vars[j]) := by
  rcases lt_or_gt_of_ne hij with hlt | hlt
  · exact List.pairwise_iff_getElem.mp h.pairwise_vars i j hi hj hlt
  · exact (List.pairwise_iff_getElem.mp h.pairwise_vars j i hj hi hlt).symm

/-- A REPEATED variable is forced to be empty. -/
theorem Sat.eq_empty_of_dup (h : Sat rho c) {v : Var} (hv : 2 ≤ c.vars.count v) :
    rho v = ∅ := by
  have hd := pairwise_self_of_two_le_count h.pairwise_vars hv
  simpa using disjoint_self.mp hd

/-- Exclusivity: at most one part of a satisfied constraint contains any given label. -/
theorem Sat.exclusive (h : Sat rho c) (l : Label) :
    (parts rho c).Pairwise (fun s t => ¬(l ∈ s ∧ l ∈ t)) := by
  refine h.pairwise.imp ?_
  intro s t hst hmem
  exact Finset.disjoint_left.mp hst hmem.1 hmem.2

/-- A label of the concrete part lies in no variable part. -/
theorem Sat.not_mem_of_mem_conc (h : Sat rho c) {l : Label} {v : Var} (hl : l ∈ c.conc)
    (hv : v ∈ c.vars) : l ∉ rho v :=
  Finset.disjoint_left.mp (h.disjoint_conc hv) hl

/-- A label of one variable part lies in no other variable part. -/
theorem Sat.not_mem_of_mem_var (h : Sat rho c) {l : Label} {v w : Var} (hv : v ∈ c.vars)
    (hw : w ∈ c.vars) (hvw : v ≠ w) (hl : l ∈ rho v) : l ∉ rho w :=
  Finset.disjoint_left.mp (h.disjoint_of_ne hv hw hvw) hl

/-- `Models` distributes over list concatenation.  Shared plumbing: `Rules` needs it for
the resolution toolkit and `Canonical` for `State.toSystem`, which is a concatenation. -/
theorem models_append {G G' : List Constraint} :
    Models rho (G ++ G') ↔ Models rho G ∧ Models rho G' := by
  constructor
  · intro h
    exact ⟨fun c hc => h c (by simp [hc]), fun c hc => h c (by simp [hc])⟩
  · rintro ⟨h1, h2⟩ c hc
    rcases List.mem_append.mp hc with hc' | hc'
    · exact h1 c hc'
    · exact h2 c hc'

/-- There is always a name outside a finite set: `Var = Label = ℕ` is infinite.  Shared
plumbing: `Divergence` needs a fresh VARIABLE, `Berthomieu` a fresh LABEL, and both are
`Finset ℕ`. -/
theorem exists_fresh (S : Finset Nat) : ∃ z, z ∉ S := by
  refine ⟨S.sup (fun x => x) + 1, fun hmem => ?_⟩
  have h : S.sup (fun x => x) + 1 ≤ S.sup (fun x => x) :=
    Finset.le_sup (f := fun x => x) hmem
  exact Nat.not_succ_le_self _ h

end SatAPI

/-! ## 4. Unfolding `Sat` at small arities -/

section SmallArity

variable (rho : Assign) (a b b₁ b₂ b₃ : Var) (k : Finset Label)

/-- `a <- ((|k|))`. -/
@[simp] theorem sat_zero : Sat rho ⟨a, [], k⟩ ↔ rho a = k := by
  simp [Sat, parts]

/-- `a <- (b, (|k|))`. -/
theorem sat_one : Sat rho ⟨a, [b], k⟩ ↔ rho a = k ∪ rho b ∧ Disjoint k (rho b) := by
  simp [Sat, parts]

/-- `a <- (b₁, b₂, (|k|))`. -/
theorem sat_two : Sat rho ⟨a, [b₁, b₂], k⟩ ↔
    rho a = k ∪ (rho b₁ ∪ rho b₂) ∧
      Disjoint k (rho b₁) ∧ Disjoint k (rho b₂) ∧ Disjoint (rho b₁) (rho b₂) := by
  simp [Sat, parts, and_assoc]

/-- `a <- (b₁, b₂, b₃, (|k|))`. -/
theorem sat_three : Sat rho ⟨a, [b₁, b₂, b₃], k⟩ ↔
    rho a = k ∪ (rho b₁ ∪ (rho b₂ ∪ rho b₃)) ∧
      Disjoint k (rho b₁) ∧ Disjoint k (rho b₂) ∧ Disjoint k (rho b₃) ∧
      Disjoint (rho b₁) (rho b₂) ∧ Disjoint (rho b₁) (rho b₃) ∧
      Disjoint (rho b₂) (rho b₃) := by
  simp [Sat, parts, and_assoc]

end SmallArity

/-! ## 5. `Models` and `Entails` -/

theorem Models.sat {rho : Assign} {G : List Constraint} (h : Models rho G) {c : Constraint}
    (hc : c ∈ G) : Sat rho c := h c hc

theorem Models.mono {rho : Assign} {G G' : List Constraint} (hsub : G ⊆ G')
    (h : Models rho G') : Models rho G := fun c hc => h c (hsub hc)

theorem Models.nil (rho : Assign) : Models rho [] := by intro c hc; cases hc

theorem models_cons {rho : Assign} {c : Constraint} {G : List Constraint} :
    Models rho (c :: G) ↔ Sat rho c ∧ Models rho G := by
  constructor
  · intro h; exact ⟨h c (by simp), fun d hd => h d (by simp [hd])⟩
  · rintro ⟨hc, hG⟩ d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · exact hc
    · exact hG d hd'

/-- Anything in the system is entailed by it. -/
theorem entails_of_mem {G : List Constraint} {c : Constraint} (h : c ∈ G) : Entails G c :=
  fun _ hm => hm c h

/-- Reflexivity. -/
theorem entails_self (c : Constraint) : Entails [c] c := entails_of_mem (by simp)

/-- Monotonicity under list extension. -/
theorem Entails.mono {G G' : List Constraint} {c : Constraint} (hsub : G ⊆ G')
    (h : Entails G c) : Entails G' c := fun rho hm => h rho (Models.mono hsub hm)

/-- Weakening by one extra hypothesis. -/
theorem Entails.cons {G : List Constraint} {c d : Constraint} (h : Entails G c) :
    Entails (d :: G) c := h.mono (List.subset_cons_self _ _)

/-- Cut / transitivity through a list of entailed constraints. -/
theorem Entails.trans {G G' : List Constraint} {c : Constraint}
    (h : ∀ d ∈ G', Entails G d) (hc : Entails G' c) : Entails G c :=
  fun rho hm => hc rho fun d hd => h d hd rho hm

/-! ## 6. The label-decomposition theorem

This is the theoretical centrepiece.  Satisfaction is pointwise in the label: a row
assignment is a *family* of Boolean assignments indexed by labels, and a constraint is
satisfied iff every one of those Boolean assignments satisfies the Boolean shadow of
the constraint. -/

/-- The Boolean projection of an assignment at a single label. -/
def proj (rho : Assign) (l : Label) : Var → Bool := fun v => decide (l ∈ rho v)

/-- The Boolean shadow of `parts`, at a label. -/
def bparts (b : Var → Bool) (l : Label) (c : Constraint) : List Bool :=
  decide (l ∈ c.conc) :: c.vars.map b

/-- Boolean satisfaction at a single label: the left-hand bit is the OR of the part
bits, and at most one part bit is set. -/
def BSat (b : Var → Bool) (l : Label) (c : Constraint) : Prop :=
  b c.lhs = (bparts b l c).foldr (· || ·) false ∧
    (bparts b l c).Pairwise (fun x y => ¬(x = true ∧ y = true))

/-- Boolean satisfaction of a whole system at a single label. -/
def BModels (b : Var → Bool) (l : Label) (G : List Constraint) : Prop :=
  ∀ c ∈ G, BSat b l c

theorem bparts_proj (rho : Assign) (l : Label) (c : Constraint) :
    bparts (proj rho l) l c = (parts rho c).map (fun s => decide (l ∈ s)) := by
  simp only [bparts, parts, List.map_cons, List.map_map]
  rfl

/-- Half of the decomposition: the union equation is pointwise. -/
theorem eq_foldr_union_iff (s : Row) (L : List Row) :
    s = L.foldr (· ∪ ·) ∅ ↔
      ∀ l, decide (l ∈ s) = (L.map (fun t => decide (l ∈ t))).foldr (· || ·) false := by
  rw [Finset.ext_iff]
  refine forall_congr' fun l => ?_
  rw [bool_eq_iff, foldr_or_eq_true, mem_foldr_union]
  simp

/-- The other half: pairwise disjointness is pointwise. -/
theorem pairwise_disjoint_iff (L : List Row) :
    L.Pairwise Disjoint ↔
      ∀ l, (L.map (fun t => decide (l ∈ t))).Pairwise
        (fun x y => ¬(x = true ∧ y = true)) := by
  have h1 : ∀ l : Label,
      ((L.map (fun t => decide (l ∈ t))).Pairwise (fun x y => ¬(x = true ∧ y = true)))
        ↔ L.Pairwise (fun s t => ¬(l ∈ s ∧ l ∈ t)) := by
    intro l
    rw [List.pairwise_map]
    simp
  rw [forall_congr' h1, ← pairwise_forall_comm]
  exact pairwise_congr fun s t => by
    rw [Finset.disjoint_left]
    exact ⟨fun hd l hl => hd hl.1 hl.2, fun hd _ ha hb => hd _ ⟨ha, hb⟩⟩

/-- **Label decomposition.**  A constraint is satisfied by `rho` iff, at EVERY label,
the Boolean projection of `rho` satisfies the Boolean shadow of the constraint.
Both directions; no finiteness side condition is needed, because `Sat` compares two
already-finite rows. -/
theorem sat_iff_forall_label (rho : Assign) (c : Constraint) :
    Sat rho c ↔ ∀ l, BSat (proj rho l) l c := by
  simp only [Sat, BSat, bparts_proj]
  rw [forall_and]
  exact and_congr (eq_foldr_union_iff _ _) (pairwise_disjoint_iff _)

/-- System-level corollary. -/
theorem models_iff_forall_label (rho : Assign) (G : List Constraint) :
    Models rho G ↔ ∀ l, BModels (proj rho l) l G := by
  constructor
  · intro h l c hc
    exact (sat_iff_forall_label rho c).mp (h c hc) l
  · intro h c hc
    exact (sat_iff_forall_label rho c).mpr fun l => h l c hc

/-! ## 7. Reconstruction: from a per-label Boolean family back to an assignment -/

/-- If a family of Boolean assignments is supported inside a finite label set `S`, then
it IS the projection family of an actual row assignment. -/
theorem proj_filter (S : Finset Label) (β : Label → Var → Bool)
    (hsupp : ∀ l v, β l v = true → l ∈ S) (l : Label) :
    proj (fun v => S.filter (fun l => β l v = true)) l = β l := by
  funext v
  simp only [proj, Finset.mem_filter]
  rw [bool_eq_iff]
  simp only [decide_eq_true_eq]
  exact ⟨And.right, fun h => ⟨hsupp l v h, h⟩⟩

/-- Reconstruction of an assignment from a finitely-supported Boolean family. -/
theorem exists_assign_of_bmodels (S : Finset Label) (β : Label → Var → Bool)
    (hsupp : ∀ l v, β l v = true → l ∈ S) (G : List Constraint)
    (h : ∀ l, BModels (β l) l G) :
    ∃ rho : Assign, Models rho G ∧ ∀ l, proj rho l = β l := by
  refine ⟨fun v => S.filter (fun l => β l v = true), ?_, proj_filter S β hsupp⟩
  rw [models_iff_forall_label]
  intro l
  rw [proj_filter S β hsupp l]
  exact h l

/-- All concrete labels mentioned by a system: the only labels at which the all-false
Boolean assignment can fail. -/
def concLabels (G : List Constraint) : Finset Label :=
  (G.map Constraint.conc).foldr (· ∪ ·) ∅

theorem mem_concLabels {G : List Constraint} {l : Label} :
    l ∈ concLabels G ↔ ∃ c ∈ G, l ∈ c.conc := by
  rw [concLabels, mem_foldr_union]
  simp

/-- Outside the (finite) set of concrete labels, the all-false Boolean assignment is a
model of every system. -/
theorem bmodels_false_of_not_mem (G : List Constraint) (l : Label)
    (hl : l ∉ concLabels G) : BModels (fun _ => false) l G := by
  intro c hc
  have hlc : l ∉ c.conc := fun hmem => hl (mem_concLabels.mpr ⟨c, hc, hmem⟩)
  constructor
  · symm
    rw [← Bool.not_eq_true, foldr_or_eq_true]
    rintro ⟨x, hx, rfl⟩
    simp only [bparts, List.mem_cons, List.mem_map] at hx
    rcases hx with h1 | ⟨v, _, hv⟩
    · simp [hlc] at h1
    · exact Bool.noConfusion hv
  · refine pairwise_of_forall_mem ?_
    intro x hx y hy hxy
    simp only [bparts, List.mem_cons, List.mem_map] at hx
    rcases hx with h1 | ⟨v, _, hv⟩
    · rw [h1] at hxy; simp [hlc] at hxy
    · rw [← hv] at hxy; exact Bool.noConfusion hxy.1

/-- **Satisfiability decomposes per label.**  A system has a row model iff it has a
Boolean model at every individual label.  (The `←` direction uses that only the finitely
many labels in `concLabels G` can constrain anything, so the reconstructed rows are
finite.) -/
theorem satisfiable_iff_forall_label (G : List Constraint) :
    (∃ rho, Models rho G) ↔ ∀ l, ∃ b, BModels b l G := by
  constructor
  · rintro ⟨rho, hm⟩ l
    exact ⟨proj rho l, (models_iff_forall_label rho G).mp hm l⟩
  · intro h
    choose f hf using h
    classical
    set S := concLabels G with hS
    set β : Label → Var → Bool := fun l => if l ∈ S then f l else fun _ => false with hβ
    have hsupp : ∀ l v, β l v = true → l ∈ S := by
      intro l v hv
      by_contra hnot
      simp only [hβ, hnot, if_false] at hv
      exact Bool.noConfusion hv
    have hmod : ∀ l, BModels (β l) l G := by
      intro l
      by_cases hl : l ∈ S
      · simpa only [hβ, hl, if_true] using hf l
      · have : β l = fun _ => false := by simp only [hβ, hl, if_false]
        rw [this]
        exact bmodels_false_of_not_mem G l (by rw [← hS]; exact hl)
    obtain ⟨rho, hm, _⟩ := exists_assign_of_bmodels S β hsupp G hmod
    exact ⟨rho, hm⟩

/-! ## 8. Entailment decomposes per label -- exactly when `G` is satisfiable -/

/-- Splicing: any Boolean assignment can be installed at a single label of an existing
row assignment, leaving all other labels untouched. -/
theorem exists_splice (rho₀ : Assign) (l : Label) (b : Var → Bool) :
    ∃ rho : Assign, proj rho l = b ∧ ∀ l', l' ≠ l → proj rho l' = proj rho₀ l' := by
  classical
  refine ⟨fun v => if b v = true then insert l (rho₀ v) else (rho₀ v).erase l, ?_, ?_⟩
  · funext v
    by_cases hb : b v = true <;> simp [proj, hb]
  · intro l' hl'
    funext v
    by_cases hb : b v = true <;> simp [proj, hb, hl', Finset.mem_erase]

/-- The easy direction: per-label validity always implies entailment. -/
theorem entails_of_forall_label {G : List Constraint} {c : Constraint}
    (h : ∀ l b, BModels b l G → BSat b l c) : Entails G c := by
  intro rho hm
  rw [sat_iff_forall_label]
  intro l
  exact h l (proj rho l) ((models_iff_forall_label rho G).mp hm l)

/-- **Entailment decomposes per label, given satisfiability.**  If `G` has at least one
row model then `Entails G c` is equivalent to the per-label Boolean statement.  The
satisfiability hypothesis is genuinely needed: see `Counterexample` below. -/
theorem entails_iff_forall_label {G : List Constraint} {c : Constraint}
    (hsat : ∃ rho, Models rho G) :
    Entails G c ↔ ∀ l b, BModels b l G → BSat b l c := by
  refine ⟨?_, entails_of_forall_label⟩
  rintro hent l b hb
  obtain ⟨rho₀, hm₀⟩ := hsat
  obtain ⟨rho, hproj, hother⟩ := exists_splice rho₀ l b
  have hmod : Models rho G := by
    rw [models_iff_forall_label]
    intro l'
    by_cases hl' : l' = l
    · subst hl'; rw [hproj]; exact hb
    · rw [hother l' hl']
      exact (models_iff_forall_label rho₀ G).mp hm₀ l'
  have := (sat_iff_forall_label rho c).mp (hent rho hmod) l
  rwa [hproj] at this

/-! ### A genuine counterexample: entailment does NOT decompose without satisfiability

`G` says `x = {5}` and `x = {6}` at once, so `G` is unsatisfiable and entails
everything.  But at the label `7` the all-false Boolean assignment IS a Boolean model
of `G` (neither `5` nor `6` is `7`), and it refutes the Boolean shadow of `y = {7}`.
So the naive per-label reading of entailment is strictly stronger than entailment. -/

namespace Counterexample

/-- `x = {5}` and `x = {6}`: unsatisfiable. -/
def G : List Constraint := [⟨0, [], {5}⟩, ⟨0, [], {6}⟩]

/-- `y = {7}`. -/
def c : Constraint := ⟨1, [], {7}⟩

theorem not_models (rho : Assign) : ¬ Models rho G := by
  intro hm
  have h5 : rho 0 = ({5} : Finset Label) := (sat_zero rho 0 _).mp (hm _ (by simp [G]))
  have h6 : rho 0 = ({6} : Finset Label) := (sat_zero rho 0 _).mp (hm _ (by simp [G]))
  rw [h5] at h6
  have : (5 : Label) ∈ ({6} : Finset Label) := by rw [← h6]; simp
  simp at this

theorem entails_G_c : Entails G c := fun rho hm => absurd hm (not_models rho)

theorem bmodels_false : BModels (fun _ => false) 7 G := by
  intro d hd
  simp only [G, List.mem_cons, List.not_mem_nil, or_false] at hd
  rcases hd with rfl | rfl <;>
    exact ⟨by simp [bparts], by simp [bparts]⟩

theorem not_bsat : ¬ BSat (fun _ => false) 7 c := by
  rintro ⟨h, -⟩
  simp [bparts, c] at h

/-- The per-label reading of entailment is strictly stronger than entailment. -/
theorem entails_not_pointwise :
    Entails G c ∧ ¬ (∀ l b, BModels b l G → BSat b l c) :=
  ⟨entails_G_c, fun h => not_bsat (h 7 (fun _ => false) bmodels_false)⟩

end Counterexample


/-! ## 9. Non-vacuity checks

Two concrete instances, to certify that `Sat` really does bite in both directions. -/

section Sanity

/-- `x <- (y, z)` with `y = {1}`, `z = {2}`, `x = {1,2}` really is satisfied. -/
example : Sat (fun v => if v = 0 then {1, 2} else if v = 1 then {1} else {2})
    ⟨0, [1, 2], ∅⟩ := by
  rw [sat_two]
  refine ⟨by decide, by decide, by decide, by decide⟩

/-- `x <- (y, y)` with `y = {1}` is NOT satisfied: a repeated variable forces `y = ∅`. -/
example : ¬ Sat (fun _ => ({1} : Finset Label)) ⟨0, [1, 1], ∅⟩ := by
  intro h
  have hy := h.eq_empty_of_dup (v := 1) (by decide)
  simp at hy

end Sanity

end Rowpartition
