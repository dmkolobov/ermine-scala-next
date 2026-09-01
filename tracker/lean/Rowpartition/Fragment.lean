/-
# The definitional fragment

`Rowpartition.Basic` shows that row-partition satisfaction decomposes label by label, so
a general solver can be a per-label SAT encoding.  This file asks a different question:
what does the constraint language look like on REAL Ermine programs, and is *that*
fragment decidable by something cheaper than search?

Measured over the 129-module stdlib closure's inferred interfaces (199 constrained
signatures, 345 partition constraints):

* 135 of 199 signatures carry exactly one constraint; the maximum is 15;
* **no residual constraint anywhere contains a concrete label** -- all 345 are purely
  abstract, the concrete parts having been solved away;
* only 11 of 199 signatures constrain the same variable twice;
* right-hand sides are small: 10 unary, 220 binary, 77 ternary, 28 4-ary, 4 5-ary,
  4 6-ary, 2 7-ary.

The corpus therefore lives in what we call the **definitional fragment**: each variable
is the left-hand side of at most one constraint, and the dependency relation is acyclic.
Such a system is a system of *definitions*, and a definition system can be expanded.

What is proved here.

* `satisfiable_of_abstract` (F1): a purely abstract system is satisfied by the
  everywhere-empty assignment.  So a solver can never justify search by "checking
  satisfiability" on the corpus's residuals -- they are all satisfiable, trivially.
* `leaves` / `kern` and `sat_leaves` (F2): the leaf expansion, defined by STRUCTURAL
  recursion on the constraint list, and the fact that it is always semantically valid:
  `Entails G (a <- (leaves G a, (|kern G a|)))` for EVERY variable `a` and EVERY system
  `G`, definitional or not.  `IsDefList` (unique left-hand sides + acyclicity, presented
  in topological order) is what makes the expansion reach actual leaves
  (`leaf_of_mem_leaves`, `leaves_idem`) and satisfy the fixed-point equation
  `leaves_def`.
* `entails_of_test` (F3, soundness) and `test_of_entails` (F3, completeness): the
  syntactic multiset test `Test` decides entailment.  Completeness is proved with an
  explicit model, `canon`, which gives every leaf variable its own distinct label --
  possible with no freshness bookkeeping at all because `Label` and `Var` are both `ℕ`.
* `decidableEntails` (F4): `Decidable (Entails G c)` on the fragment.
* Two counterexamples (F5) delimiting the fragment: `NotDefinitional`, where two
  constraints share a left-hand side and the test is incomplete; and `NonLinear`, an
  honest surprise -- the test is incomplete *inside* the definitional fragment as well,
  as soon as some expansion repeats a leaf.  A repeated leaf forces a row to be empty
  (`Sat.eq_empty_of_dup`), and the syntactic test cannot see that.  Completeness
  therefore carries the extra hypothesis `Linear`.
-/
import Rowpartition.Basic
import Mathlib.Data.List.Nodup

namespace Rowpartition

/-! ## 1. Membership plumbing

Two `iff`s used everywhere below: membership in the `foldr`-union that `parts` builds,
and membership in a flattened list of blocks. -/

/-- Membership in the union of a concrete part and a family of variable parts. -/
theorem mem_foldr_cons_map (f : Var → Finset Label) (vs : List Var) (k : Finset Label)
    (l : Label) :
    l ∈ (k :: vs.map f).foldr (· ∪ ·) ∅ ↔ (l ∈ k ∨ ∃ v ∈ vs, l ∈ f v) := by
  rw [mem_foldr_union]
  constructor
  · rintro ⟨s, hs, hl⟩
    rcases List.mem_cons.mp hs with rfl | hs'
    · exact Or.inl hl
    · obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs'
      exact Or.inr ⟨v, hv, hl⟩
  · rintro (hl | ⟨v, hv, hl⟩)
    · exact ⟨k, by simp, hl⟩
    · refine ⟨f v, ?_, hl⟩
      simp only [List.mem_cons, List.mem_map]
      exact Or.inr ⟨v, hv, rfl⟩

/-- Membership in a flattened list of blocks. -/
theorem mem_flatten_map {ws : Var → List Var} {vs : List Var} {u : Var} :
    u ∈ (vs.map ws).flatten ↔ ∃ v ∈ vs, u ∈ ws v := by
  simp only [List.mem_flatten, List.mem_map]
  constructor
  · rintro ⟨l, ⟨v, hv, rfl⟩, hu⟩
    exact ⟨v, hv, hu⟩
  · rintro ⟨v, hv, hu⟩
    exact ⟨ws v, ⟨v, hv, rfl⟩, hu⟩

/-- Flattening a list of singletons is the identity. -/
theorem flatten_map_singleton {α : Type*} (l : List α) :
    (l.map (fun u => [u])).flatten = l := by
  induction l with
  | nil => rfl
  | cons x l ih => simp [ih]

/-! ## 2. `Sat` in component form, and substitution

`sat_iff'` is a workable unfolding of `Sat` for a constraint written out in components.
`sat_subst` is the engine of the whole file: it says that a satisfied constraint may
have each of its right-hand variables replaced by a satisfied expansion of that
variable, and the result is again satisfied.  Iterating it is exactly what the leaf
expansion does. -/

/-- Componentwise characterisation of `Sat`. -/
theorem sat_iff' (rho : Assign) (a : Var) (vs : List Var) (k : Finset Label) :
    Sat rho ⟨a, vs, k⟩ ↔
      (∀ l, l ∈ rho a ↔ (l ∈ k ∨ ∃ v ∈ vs, l ∈ rho v)) ∧
        (∀ v ∈ vs, Disjoint k (rho v)) ∧ (vs.map rho).Pairwise Disjoint := by
  constructor
  · intro h
    refine ⟨fun l => h.mem_lhs_iff l, fun v hv => h.disjoint_conc hv, ?_⟩
    have h2 := h.pairwise
    simp only [parts, List.pairwise_cons] at h2
    exact h2.2
  · rintro ⟨h1, h2, h3⟩
    constructor
    · refine Finset.ext fun l => ?_
      simp only [parts]
      rw [mem_foldr_cons_map]
      exact h1 l
    · simp only [parts, List.pairwise_cons]
      refine ⟨fun s hs => ?_, h3⟩
      obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs
      exact h2 v hv

/-- Every variable is trivially its own expansion. -/
theorem sat_self (rho : Assign) (a : Var) : Sat rho ⟨a, [a], ∅⟩ := by
  rw [sat_one]
  exact ⟨by simp, by simp⟩

/-- **Substitution.**  If `a` partitions into `vs` (plus concrete `k`) and each `v ∈ vs`
partitions into `ws v` (plus concrete `kv v`), then `a` partitions into the concatenated
blocks (plus the union of the concrete parts).  Note that `ws` and `kv` are functions of
the variable, so a repeated variable is substituted by the same block twice; that is
harmless, because a repeated variable is forced to be empty. -/
theorem sat_subst {rho : Assign} {a : Var} {vs : List Var} {k : Finset Label}
    {ws : Var → List Var} {kv : Var → Finset Label}
    (hout : Sat rho ⟨a, vs, k⟩) (hin : ∀ v ∈ vs, Sat rho ⟨v, ws v, kv v⟩) :
    Sat rho ⟨a, (vs.map ws).flatten, (k :: vs.map kv).foldr (· ∪ ·) ∅⟩ := by
  have hsub : ∀ v ∈ vs, ∀ u ∈ ws v, rho u ⊆ rho v := fun v hv _ hu =>
    (hin v hv).subset_lhs hu
  have hkv : ∀ v ∈ vs, kv v ⊆ rho v := fun v hv => (hin v hv).conc_subset_lhs
  rw [sat_iff']
  refine ⟨?_, ?_, ?_⟩
  · intro l
    rw [hout.mem_lhs_iff l, mem_foldr_cons_map]
    constructor
    · rintro (hl | ⟨v, hv, hl⟩)
      · exact Or.inl (Or.inl hl)
      · rcases ((hin v hv).mem_lhs_iff l).mp hl with h | ⟨u, hu, hl'⟩
        · exact Or.inl (Or.inr ⟨v, hv, h⟩)
        · exact Or.inr ⟨u, mem_flatten_map.mpr ⟨v, hv, hu⟩, hl'⟩
    · rintro ((hl | ⟨v, hv, hl⟩) | ⟨u, hu, hl⟩)
      · exact Or.inl hl
      · exact Or.inr ⟨v, hv, ((hin v hv).mem_lhs_iff l).mpr (Or.inl hl)⟩
      · obtain ⟨v, hv, hu'⟩ := mem_flatten_map.mp hu
        exact Or.inr ⟨v, hv, ((hin v hv).mem_lhs_iff l).mpr (Or.inr ⟨u, hu', hl⟩)⟩
  · intro u hu
    obtain ⟨v, hv, hu'⟩ := mem_flatten_map.mp hu
    refine Finset.disjoint_left.mpr fun l hl hl' => ?_
    rw [mem_foldr_cons_map] at hl
    have hlv : l ∈ rho v := hsub v hv u hu' hl'
    rcases hl with h | ⟨w, hw, h⟩
    · exact Finset.disjoint_left.mp (hout.disjoint_conc hv) h hlv
    · by_cases hvw : w = v
      · subst hvw
        exact Finset.disjoint_left.mp ((hin w hw).disjoint_conc hu') h hl'
      · exact Finset.disjoint_left.mp (hout.disjoint_of_ne hw hv hvw) (hkv w hw h) hlv
  · rw [List.pairwise_map, List.pairwise_flatten]
    constructor
    · intro L hL
      obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hL
      exact (hin v hv).pairwise_vars
    · rw [List.pairwise_map]
      refine List.Pairwise.imp_of_mem ?_ hout.pairwise_vars
      intro v w hv hw hd u hu u' hu'
      exact Finset.disjoint_of_subset_left (hsub v hv u hu)
        (Finset.disjoint_of_subset_right (hsub w hw u' hu') hd)

/-! ## 3. (F1) Purely abstract systems are trivially satisfiable

Every residual constraint in the corpus is purely abstract.  The everywhere-empty
assignment models any such system, so satisfiability is never the interesting question
on real Ermine code -- entailment is. -/

/-- A system is ABSTRACT when no constraint mentions a concrete label. -/
def Abstract (G : List Constraint) : Prop := ∀ c ∈ G, c.conc = ∅

/-- The everywhere-empty assignment satisfies any abstract constraint. -/
theorem sat_empty {c : Constraint} (h : c.conc = ∅) : Sat (fun _ => (∅ : Row)) c := by
  have key : ∀ s ∈ parts (fun _ => (∅ : Row)) c, s = (∅ : Row) := by
    intro s hs
    simp only [parts, List.mem_cons, List.mem_map] at hs
    rcases hs with rfl | ⟨v, _, hv⟩
    · exact h
    · exact hv.symm
  constructor
  · refine (Finset.eq_empty_iff_forall_notMem.mpr fun l hl => ?_).trans
      (Finset.eq_empty_iff_forall_notMem.mpr fun l hl => ?_).symm
    · exact Finset.notMem_empty l hl
    · obtain ⟨s, hs, hls⟩ := mem_foldr_union _ _ |>.mp hl
      rw [key s hs] at hls
      exact Finset.notMem_empty l hls
  · refine pairwise_of_forall_mem fun s hs t ht => ?_
    rw [key s hs, key t ht]
    simp

/-- **(F1)** An abstract system is modelled by the everywhere-empty assignment. -/
theorem models_empty {G : List Constraint} (h : Abstract G) :
    Models (fun _ => (∅ : Row)) G := fun c hc => sat_empty (h c hc)

/-- **(F1)** An abstract system is satisfiable. -/
theorem satisfiable_of_abstract {G : List Constraint} (h : Abstract G) :
    ∃ rho, Models rho G := ⟨_, models_empty h⟩

/-- Consequently, for an abstract system entailment DOES decompose per label: the
satisfiability side condition of `Rowpartition.entails_iff_forall_label` is free. -/
theorem entails_iff_forall_label_of_abstract {G : List Constraint} {c : Constraint}
    (h : Abstract G) : Entails G c ↔ ∀ l b, BModels b l G → BSat b l c :=
  entails_iff_forall_label (satisfiable_of_abstract h)

/-! ## 4. (F2) The leaf expansion

`leaves G a` expands `a` by its definition in `G`, recursively.  It is defined by
STRUCTURAL recursion on the constraint list: when the head constraint defines `a`, its
right-hand variables are expanded using only the TAIL.  No well-founded recursion and no
termination side condition is needed -- termination is structural, and the acyclicity
hypothesis (`IsDefList` below) is needed only to know that the result consists of
genuine leaves and satisfies the expected fixed-point equation. -/

/-- The leaf expansion of a variable: a list of variables, with multiplicity. -/
def leaves : List Constraint → Var → List Var
  | [], a => [a]
  | c :: G, a =>
      if c.lhs = a then (c.vars.map (fun v => leaves G v)).flatten else leaves G a

/-- The concrete part of the leaf expansion of a variable. -/
def kern : List Constraint → Var → Finset Label
  | [], _ => ∅
  | c :: G, a =>
      if c.lhs = a then (c.conc :: c.vars.map (fun v => kern G v)).foldr (· ∪ ·) ∅
      else kern G a

@[simp] theorem leaves_nil (a : Var) : leaves [] a = [a] := rfl

@[simp] theorem kern_nil (a : Var) : kern [] a = ∅ := rfl

theorem leaves_cons (c : Constraint) (G : List Constraint) (a : Var) :
    leaves (c :: G) a =
      if c.lhs = a then (c.vars.map (leaves G)).flatten else leaves G a := rfl

theorem kern_cons (c : Constraint) (G : List Constraint) (a : Var) :
    kern (c :: G) a =
      if c.lhs = a then (c.conc :: c.vars.map (kern G)).foldr (· ∪ ·) ∅
      else kern G a := rfl

theorem leaves_cons_pos {c : Constraint} {a : Var} (G : List Constraint) (h : c.lhs = a) :
    leaves (c :: G) a = (c.vars.map (leaves G)).flatten := by rw [leaves_cons, if_pos h]

theorem leaves_cons_neg {c : Constraint} {a : Var} (G : List Constraint) (h : c.lhs ≠ a) :
    leaves (c :: G) a = leaves G a := by rw [leaves_cons, if_neg h]

theorem kern_cons_pos {c : Constraint} {a : Var} (G : List Constraint) (h : c.lhs = a) :
    kern (c :: G) a = (c.conc :: c.vars.map (kern G)).foldr (· ∪ ·) ∅ := by
  rw [kern_cons, if_pos h]

theorem kern_cons_neg {c : Constraint} {a : Var} (G : List Constraint) (h : c.lhs ≠ a) :
    kern (c :: G) a = kern G a := by rw [kern_cons, if_neg h]

/-- **(F2) Normal form.**  For EVERY system `G` and EVERY variable `a`, the leaf
expansion of `a` is an entailed constraint: any model of `G` partitions `rho a` into the
rows of the leaves plus `kern G a`.  No hypothesis on `G` whatsoever. -/
theorem sat_leaves (rho : Assign) :
    ∀ (G : List Constraint), Models rho G → ∀ a : Var, Sat rho ⟨a, leaves G a, kern G a⟩ := by
  intro G
  induction G with
  | nil => intro _ a; simpa using sat_self rho a
  | cons c G ih =>
    intro h a
    rw [models_cons] at h
    by_cases hca : c.lhs = a
    · subst hca
      rw [leaves_cons_pos G rfl, kern_cons_pos G rfl]
      exact sat_subst h.1 (fun v _ => ih h.2 v)
    · rw [leaves_cons_neg G hca, kern_cons_neg G hca]
      exact ih h.2 a

/-- The normal form, as an entailment. -/
theorem entails_leaves (G : List Constraint) (a : Var) :
    Entails G ⟨a, leaves G a, kern G a⟩ := fun rho h => sat_leaves rho G h a

/-! ## 5. Definitional systems

`IsDefList G` presents the definitional fragment as an ORDERED list: each constraint's
left-hand side is fresh for everything that follows it (so no variable is defined twice,
and dependencies point strictly forwards), and does not occur in its own right-hand side.
Any unique-left-hand-side acyclic system can be topologically sorted into this form; we
take the sorted presentation as the definition, and derive from it BOTH halves of the
informal condition: unique left-hand sides (`IsDefList.uniq`) and acyclicity of the
dependency relation (`wellFounded_dep`).  The converse -- that any unique-lhs acyclic
system can be permuted into a definition list -- is a topological-sort argument that is
NOT formalised here; it is the one gap between the informal fragment and `IsDefList`. -/

/-- `v` occurs on the right-hand side of a constraint defining `a`. -/
def Dep (G : List Constraint) (v a : Var) : Prop := ∃ c ∈ G, c.lhs = a ∧ v ∈ c.vars

/-- `v` has no defining constraint in `G`. -/
def Leaf (G : List Constraint) (v : Var) : Prop := ∀ c ∈ G, c.lhs ≠ v

/-- `G` is a definition list: left-hand sides are unique, do not occur in their own
right-hand sides, and dependencies point forwards. -/
def IsDefList : List Constraint → Prop
  | [] => True
  | c :: G => c.lhs ∉ c.vars ∧ (∀ d ∈ G, c.lhs ≠ d.lhs ∧ c.lhs ∉ d.vars) ∧ IsDefList G

theorem isDefList_cons {c : Constraint} {G : List Constraint} :
    IsDefList (c :: G) ↔
      c.lhs ∉ c.vars ∧ (∀ d ∈ G, c.lhs ≠ d.lhs ∧ c.lhs ∉ d.vars) ∧ IsDefList G := Iff.rfl

/-- A definition list has unique left-hand sides. -/
theorem IsDefList.uniq : ∀ {G : List Constraint}, IsDefList G →
    ∀ c ∈ G, ∀ d ∈ G, c.lhs = d.lhs → c = d := by
  intro G
  induction G with
  | nil => intro _ c hc; cases hc
  | cons e G ih =>
    rintro ⟨-, hfresh, htail⟩ c hc d hd hlhs
    rcases List.mem_cons.mp hc with rfl | hc' <;> rcases List.mem_cons.mp hd with rfl | hd'
    · rfl
    · exact absurd hlhs (hfresh d hd').1
    · exact absurd hlhs.symm (hfresh c hc').1
    · exact ih htail c hc' d hd' hlhs

/-- The dependency relation of a definition list is well-founded: no cycles. -/
theorem wellFounded_dep : ∀ {G : List Constraint}, IsDefList G → WellFounded (Dep G) := by
  intro G
  induction G with
  | nil =>
    intro _
    refine ⟨fun a => Acc.intro a fun v hv => ?_⟩
    obtain ⟨c, hc, -⟩ := hv
    cases hc
  | cons c G ih =>
    rintro ⟨hself, hfresh, htail⟩
    have hG := ih htail
    have hstep : ∀ v a : Var, Dep (c :: G) v a → (a = c.lhs ∧ v ∈ c.vars) ∨ Dep G v a := by
      rintro v a ⟨d, hd, hlhs, hv⟩
      rcases List.mem_cons.mp hd with rfl | hd'
      · exact Or.inl ⟨hlhs.symm, hv⟩
      · exact Or.inr ⟨d, hd', hlhs, hv⟩
    have hne : ∀ v a : Var, Dep G v a → v ≠ c.lhs := by
      rintro v a ⟨d, hd, -, hv⟩ rfl
      exact (hfresh d hd).2 hv
    have key : ∀ a : Var, a ≠ c.lhs → Acc (Dep G) a → Acc (Dep (c :: G)) a := by
      intro a ha hacc
      induction hacc with
      | intro x _ ihx =>
        refine Acc.intro _ fun v hv => ?_
        rcases hstep v x hv with ⟨rfl, -⟩ | hv'
        · exact absurd rfl ha
        · exact ihx v hv' (hne v x hv')
    refine ⟨fun a => ?_⟩
    by_cases ha : a = c.lhs
    · subst ha
      refine Acc.intro _ fun v hv => ?_
      rcases hstep v c.lhs hv with ⟨-, hvc⟩ | hv'
      · exact key v (fun h => hself (h ▸ hvc)) (hG.apply v)
      · exact key v (hne v c.lhs hv') (hG.apply v)
    · exact key a ha (hG.apply a)

/-- A leaf expands to itself. -/
theorem leaves_of_leaf : ∀ {G : List Constraint} {v : Var}, Leaf G v → leaves G v = [v] := by
  intro G
  induction G with
  | nil => intro v _; rfl
  | cons c G ih =>
    intro v hv
    rw [leaves_cons_neg G (hv c (by simp))]
    exact ih fun d hd => hv d (by simp [hd])

/-- Every variable in an expansion either is the expanded variable itself or occurs on
some right-hand side. -/
theorem mem_leaves_cases : ∀ {G : List Constraint} {a u : Var}, u ∈ leaves G a →
    u = a ∨ ∃ c ∈ G, u ∈ c.vars := by
  intro G
  induction G with
  | nil => intro a u hu; simpa using hu
  | cons c G ih =>
    intro a u hu
    by_cases hca : c.lhs = a
    · rw [leaves_cons_pos G hca] at hu
      obtain ⟨v, hv, hu'⟩ := mem_flatten_map.mp hu
      rcases ih hu' with rfl | ⟨d, hd, hud⟩
      · exact Or.inr ⟨c, by simp, hv⟩
      · exact Or.inr ⟨d, by simp [hd], hud⟩
    · rw [leaves_cons_neg G hca] at hu
      rcases ih hu with rfl | ⟨d, hd, hud⟩
      · exact Or.inl rfl
      · exact Or.inr ⟨d, by simp [hd], hud⟩

/-- **(F2)** In a definition list, the expansion of any variable consists of LEAVES. -/
theorem leaf_of_mem_leaves : ∀ {G : List Constraint}, IsDefList G → ∀ {a u : Var},
    u ∈ leaves G a → Leaf G u := by
  intro G
  induction G with
  | nil => intro _ a u _ d hd; cases hd
  | cons c G ih =>
    rintro ⟨hself, hfresh, htail⟩ a u hu
    have hmain : Leaf G u ∧ c.lhs ≠ u := by
      by_cases hca : c.lhs = a
      · rw [leaves_cons_pos G hca] at hu
        obtain ⟨v, hv, hu'⟩ := mem_flatten_map.mp hu
        refine ⟨ih htail hu', ?_⟩
        rcases mem_leaves_cases hu' with rfl | ⟨d, hd, hud⟩
        · exact fun h => hself (h ▸ hv)
        · exact fun h => (hfresh d hd).2 (h ▸ hud)
      · rw [leaves_cons_neg G hca] at hu
        refine ⟨ih htail hu, ?_⟩
        rcases mem_leaves_cases hu with rfl | ⟨d, hd, hud⟩
        · exact hca
        · exact fun h => (hfresh d hd).2 (h ▸ hud)
    intro d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · exact hmain.2
    · exact hmain.1 d hd'

/-- **(F2)** The expansion is a normal form: expanding it again changes nothing. -/
theorem leaves_idem {G : List Constraint} (hG : IsDefList G) (a : Var) :
    ((leaves G a).map (leaves G)).flatten = leaves G a := by
  rw [List.map_congr_left fun u hu => leaves_of_leaf (leaf_of_mem_leaves hG hu)]
  exact flatten_map_singleton _

/-- **The fixed-point equation.**  In a definition list, the expansion of a defined
variable is exactly the concatenation of the expansions of its right-hand variables.
(Without `IsDefList` this can fail: the definition of `leaves` expands a right-hand side
using only the constraints AFTER the defining one.) -/
theorem leaves_def : ∀ {G : List Constraint}, IsDefList G → ∀ {d : Constraint}, d ∈ G →
    leaves G d.lhs = (d.vars.map (leaves G)).flatten := by
  intro G
  induction G with
  | nil => intro _ d hd; cases hd
  | cons c G ih =>
    rintro ⟨hself, hfresh, htail⟩ d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · rw [leaves_cons_pos G rfl]
      exact congrArg List.flatten
        (List.map_congr_left fun v hv => (leaves_cons_neg G fun h => hself (h ▸ hv)).symm)
    · rw [leaves_cons_neg G (hfresh d hd').1, ih htail hd']
      exact congrArg List.flatten
        (List.map_congr_left fun v hv => (leaves_cons_neg G fun h => (hfresh d hd').2 (h ▸ hv)).symm)

/-- In an abstract system every expansion has empty concrete part. -/
theorem kern_eq_empty : ∀ {G : List Constraint}, Abstract G → ∀ a : Var, kern G a = ∅ := by
  intro G
  induction G with
  | nil => intro _ a; rfl
  | cons c G ih =>
    intro h a
    have hc : c.conc = ∅ := h c (by simp)
    have hG : Abstract G := fun d hd => h d (by simp [hd])
    by_cases hca : c.lhs = a
    · rw [kern_cons_pos G hca]
      refine Finset.eq_empty_iff_forall_notMem.mpr fun l hl => ?_
      rw [mem_foldr_cons_map] at hl
      rcases hl with hl | ⟨v, -, hl⟩
      · rw [hc] at hl; exact Finset.notMem_empty l hl
      · rw [ih hG v] at hl; exact Finset.notMem_empty l hl
    · rw [kern_cons_neg G hca]; exact ih hG a

/-! ## 6. (F3) The decision procedure -/

/-- The syntactic test.  `c` passes iff the leaf expansion of its left-hand side is a
PERMUTATION of the concatenated expansions of its right-hand variables, those expansions
are pairwise disjoint, and the concrete parts match up disjointly. -/
def Test (G : List Constraint) (c : Constraint) : Prop :=
  List.Perm (leaves G c.lhs) ((c.vars.map (leaves G)).flatten) ∧
    kern G c.lhs = (c.conc :: c.vars.map (kern G)).foldr (· ∪ ·) ∅ ∧
      (c.vars.map (leaves G)).Pairwise List.Disjoint ∧
        (c.conc :: c.vars.map (kern G)).Pairwise Disjoint

/-- **(F3, soundness).**  Passing the test implies entailment -- for ANY system `G`,
definitional or not, abstract or not. -/
theorem entails_of_test {G : List Constraint} {c : Constraint} (h : Test G c) :
    Entails G c := by
  obtain ⟨hperm, hkern, hdisj, hkdisj⟩ := h
  intro rho hm
  have hA : Sat rho ⟨c.lhs, leaves G c.lhs, kern G c.lhs⟩ := sat_leaves rho G hm c.lhs
  have hV : ∀ v : Var, Sat rho ⟨v, leaves G v, kern G v⟩ := fun v => sat_leaves rho G hm v
  have hmemLA : ∀ u : Var, u ∈ (c.vars.map (leaves G)).flatten → u ∈ leaves G c.lhs :=
    fun u hu => hperm.mem_iff.mpr hu
  have hkA : ∀ l : Label, (l ∈ c.conc ∨ ∃ v ∈ c.vars, l ∈ kern G v) → l ∈ kern G c.lhs := by
    intro l hl
    rw [hkern, mem_foldr_cons_map]
    exact hl
  -- the goal, with `c` written out in components
  show Sat rho ⟨c.lhs, c.vars, c.conc⟩
  rw [sat_iff']
  refine ⟨?_, ?_, ?_⟩
  · intro l
    rw [hA.mem_lhs_iff l]
    constructor
    · rintro (hl | ⟨u, hu, hlu⟩)
      · rw [hkern, mem_foldr_cons_map] at hl
        rcases hl with hl | ⟨v, hv, hl⟩
        · exact Or.inl hl
        · exact Or.inr ⟨v, hv, ((hV v).mem_lhs_iff l).mpr (Or.inl hl)⟩
      · obtain ⟨v, hv, hu'⟩ := mem_flatten_map.mp (hperm.mem_iff.mp hu)
        exact Or.inr ⟨v, hv, ((hV v).mem_lhs_iff l).mpr (Or.inr ⟨u, hu', hlu⟩)⟩
    · rintro (hl | ⟨v, hv, hl⟩)
      · exact Or.inl (hkA l (Or.inl hl))
      · rcases ((hV v).mem_lhs_iff l).mp hl with h | ⟨u, hu, hlu⟩
        · exact Or.inl (hkA l (Or.inr ⟨v, hv, h⟩))
        · exact Or.inr ⟨u, hmemLA u (mem_flatten_map.mpr ⟨v, hv, hu⟩), hlu⟩
  · intro v hv
    refine Finset.disjoint_left.mpr fun l hl hlv => ?_
    rcases ((hV v).mem_lhs_iff l).mp hlv with h | ⟨u, hu, hlu⟩
    · rw [List.pairwise_cons] at hkdisj
      exact Finset.disjoint_left.mp
        (hkdisj.1 (kern G v) (List.mem_map_of_mem hv)) hl h
    · exact Finset.disjoint_left.mp
        (hA.disjoint_conc (hmemLA u (mem_flatten_map.mpr ⟨v, hv, hu⟩)))
        (hkA l (Or.inl hl)) hlu
  · rw [List.pairwise_map, List.pairwise_iff_getElem]
    rw [List.pairwise_map, List.pairwise_iff_getElem] at hdisj
    rw [List.pairwise_cons] at hkdisj
    have hkd := hkdisj.2
    rw [List.pairwise_map, List.pairwise_iff_getElem] at hkd
    intro i j hi hj hij
    set v := c.vars[i] with hv
    set w := c.vars[j] with hw
    have hvm : v ∈ c.vars := List.getElem_mem hi
    have hwm : w ∈ c.vars := List.getElem_mem hj
    refine Finset.disjoint_left.mpr fun l hlv hlw => ?_
    rcases ((hV v).mem_lhs_iff l).mp hlv with h1 | ⟨u, hu, hlu⟩ <;>
      rcases ((hV w).mem_lhs_iff l).mp hlw with h2 | ⟨u', hu', hlu'⟩
    · exact Finset.disjoint_left.mp (hkd i j hi hj hij) h1 h2
    · exact Finset.disjoint_left.mp
        (hA.disjoint_conc (hmemLA u' (mem_flatten_map.mpr ⟨w, hwm, hu'⟩)))
        (hkA l (Or.inr ⟨v, hvm, h1⟩)) hlu'
    · exact Finset.disjoint_left.mp
        (hA.disjoint_conc (hmemLA u (mem_flatten_map.mpr ⟨v, hvm, hu⟩)))
        (hkA l (Or.inr ⟨w, hwm, h2⟩)) hlu
    · have hne : u ≠ u' := by
        rintro rfl
        exact hdisj i j hi hj hij hu hu'
      exact Finset.disjoint_left.mp
        (hA.disjoint_of_ne (hmemLA u (mem_flatten_map.mpr ⟨v, hvm, hu⟩))
          (hmemLA u' (mem_flatten_map.mpr ⟨w, hwm, hu'⟩)) hne) hlu hlu'

/-! ### The canonical model

Completeness needs a model that separates leaves: every leaf variable must get its own
label.  Because `Label` and `Var` are both `ℕ`, the identity is such a naming, and the
model is simply "every variable is the SET of its leaves". -/

/-- A system is LINEAR when no expansion repeats a leaf.  A repeat forces the repeated
row to be empty (`Sat.eq_empty_of_dup`), which the syntactic test cannot see; see
`NonLinear` below for why this hypothesis cannot be dropped. -/
def Linear (G : List Constraint) : Prop := ∀ a : Var, (leaves G a).Nodup

/-- The finite check corresponding to `Linear`: only the DEFINED variables can have a
repeating expansion, and there are finitely many of those. -/
def LinearCheck (G : List Constraint) : Prop := ∀ c ∈ G, (leaves G c.lhs).Nodup

/-- `Linear` is a finite, decidable condition. -/
theorem linear_iff {G : List Constraint} : Linear G ↔ LinearCheck G := by
  constructor
  · intro h c _
    exact h c.lhs
  · intro h a
    by_cases hL : Leaf G a
    · rw [leaves_of_leaf hL]
      simp
    · unfold Leaf at hL
      push Not at hL
      obtain ⟨c, hc, hca⟩ := hL
      subst hca
      exact h c hc

/-- The canonical model of a definition list: each variable is the set of its leaves,
each leaf standing for the label of the same number. -/
def canon (G : List Constraint) : Assign := fun a => (leaves G a).toFinset

theorem mem_canon {G : List Constraint} {a : Var} {l : Label} :
    l ∈ canon G a ↔ l ∈ leaves G a := List.mem_toFinset

/-- List disjointness of expansions transfers to the canonical model. -/
theorem canon_disjoint {G : List Constraint} {v w : Var}
    (h : List.Disjoint (leaves G v) (leaves G w)) : Disjoint (canon G v) (canon G w) :=
  Finset.disjoint_left.mpr fun _ hl hl' => h (mem_canon.mp hl) (mem_canon.mp hl')

/-- ... and back again. -/
theorem canon_disjoint' {G : List Constraint} {v w : Var}
    (h : Disjoint (canon G v) (canon G w)) : List.Disjoint (leaves G v) (leaves G w) :=
  fun _ hl hl' => Finset.disjoint_left.mp h (mem_canon.mpr hl) (mem_canon.mpr hl')

/-- **The canonical model really is a model.** -/
theorem models_canon {G : List Constraint} (hG : IsDefList G) (habs : Abstract G)
    (hlin : Linear G) : Models (canon G) G := by
  intro d hd
  have hconc : d.conc = ∅ := habs d hd
  have hdef := leaves_def hG hd
  have hnodup : ((d.vars.map (leaves G)).flatten).Nodup := hdef ▸ hlin d.lhs
  have hpair : (d.vars.map (leaves G)).Pairwise List.Disjoint :=
    (List.nodup_flatten.mp hnodup).2
  show Sat (canon G) ⟨d.lhs, d.vars, d.conc⟩
  rw [sat_iff']
  refine ⟨?_, ?_, ?_⟩
  · intro l
    rw [mem_canon, hdef, hconc]
    constructor
    · intro hl
      obtain ⟨v, hv, hlv⟩ := mem_flatten_map.mp hl
      exact Or.inr ⟨v, hv, mem_canon.mpr hlv⟩
    · rintro (hl | ⟨v, hv, hlv⟩)
      · exact absurd hl (Finset.notMem_empty l)
      · exact mem_flatten_map.mpr ⟨v, hv, mem_canon.mp hlv⟩
  · intro v _
    rw [hconc]
    simp
  · rw [List.pairwise_map]
    rw [List.pairwise_map] at hpair
    exact hpair.imp canon_disjoint

/-- Two `Nodup` lists with the same members are permutations of one another. -/
theorem perm_of_nodup {α : Type*} [DecidableEq α] {l₁ l₂ : List α} (h₁ : l₁.Nodup)
    (h₂ : l₂.Nodup) (h : ∀ a, a ∈ l₁ ↔ a ∈ l₂) : List.Perm l₁ l₂ := by
  rw [List.perm_iff_count]
  intro a
  by_cases ha : a ∈ l₁
  · rw [List.count_eq_one_of_mem h₁ ha, List.count_eq_one_of_mem h₂ ((h a).mp ha)]
  · rw [List.count_eq_zero_of_not_mem ha,
      List.count_eq_zero_of_not_mem fun hc => ha ((h a).mpr hc)]

/-- **(F3, completeness).**  On the definitional fragment -- abstract, a definition list,
and linear -- entailment of an abstract constraint implies the syntactic test.  The proof
is a single application of the canonical model. -/
theorem test_of_entails {G : List Constraint} {c : Constraint} (hG : IsDefList G)
    (habs : Abstract G) (hlin : Linear G) (hc : c.conc = ∅) (hent : Entails G c) :
    Test G c := by
  have hsat : Sat (canon G) c := hent (canon G) (models_canon hG habs hlin)
  have hmem : ∀ l : Label, l ∈ leaves G c.lhs ↔ l ∈ (c.vars.map (leaves G)).flatten := by
    intro l
    rw [← mem_canon, hsat.mem_lhs_iff l, hc]
    constructor
    · rintro (hl | ⟨v, hv, hlv⟩)
      · exact absurd hl (Finset.notMem_empty l)
      · exact mem_flatten_map.mpr ⟨v, hv, mem_canon.mp hlv⟩
    · intro hl
      obtain ⟨v, hv, hlv⟩ := mem_flatten_map.mp hl
      exact Or.inr ⟨v, hv, mem_canon.mpr hlv⟩
  have hpair : (c.vars.map (leaves G)).Pairwise List.Disjoint := by
    rw [List.pairwise_map]
    exact hsat.pairwise_vars.imp canon_disjoint'
  have hnodup : ((c.vars.map (leaves G)).flatten).Nodup := by
    refine List.nodup_flatten.mpr ⟨?_, hpair⟩
    intro L hL
    obtain ⟨v, -, rfl⟩ := List.mem_map.mp hL
    exact hlin v
  refine ⟨perm_of_nodup (hlin c.lhs) hnodup hmem, ?_, hpair, ?_⟩
  · rw [kern_eq_empty habs]
    refine (Finset.eq_empty_iff_forall_notMem.mpr fun l hl => ?_).symm
    rw [mem_foldr_cons_map] at hl
    rcases hl with hl | ⟨v, -, hl⟩
    · rw [hc] at hl; exact Finset.notMem_empty l hl
    · rw [kern_eq_empty habs] at hl; exact Finset.notMem_empty l hl
  · refine pairwise_of_forall_mem fun s hs t _ => ?_
    have hse : s = ∅ := by
      rcases List.mem_cons.mp hs with rfl | hs'
      · exact hc
      · obtain ⟨v, -, rfl⟩ := List.mem_map.mp hs'
        exact kern_eq_empty habs v
    rw [hse]
    simp

/-- **(F3).**  Entailment on the definitional fragment IS the syntactic test. -/
theorem entails_iff_test {G : List Constraint} {c : Constraint} (hG : IsDefList G)
    (habs : Abstract G) (hlin : Linear G) (hc : c.conc = ∅) :
    Entails G c ↔ Test G c :=
  ⟨test_of_entails hG habs hlin hc, entails_of_test⟩

/-! ## 7. (F4) Decidability -/

instance decidableListDisjoint (l₁ l₂ : List Var) : Decidable (List.Disjoint l₁ l₂) :=
  decidable_of_iff (∀ a ∈ l₁, a ∉ l₂)
    ⟨fun h _ ha ha' => h _ ha ha', fun h _ ha ha' => h ha ha'⟩

instance decidableTest (G : List Constraint) (c : Constraint) : Decidable (Test G c) := by
  unfold Test
  infer_instance

instance decidableAbstract (G : List Constraint) : Decidable (Abstract G) := by
  unfold Abstract
  infer_instance

instance decidableLinearCheck (G : List Constraint) : Decidable (LinearCheck G) := by
  unfold LinearCheck
  infer_instance

instance decidableIsDefList : ∀ G : List Constraint, Decidable (IsDefList G)
  | [] => isTrue trivial
  | _c :: G =>
      have : Decidable (IsDefList G) := decidableIsDefList G
      decidable_of_iff _ isDefList_cons.symm

/-- **(F4).**  Entailment is decidable on the definitional fragment. -/
def decidableEntails {G : List Constraint} {c : Constraint} (hG : IsDefList G)
    (habs : Abstract G) (hlin : Linear G) (hc : c.conc = ∅) : Decidable (Entails G c) :=
  decidable_of_iff (Test G c) (entails_iff_test hG habs hlin hc).symm

/-- **(F4).**  Nothing is left hanging: membership of the fragment is itself decidable,
so the whole procedure -- check the fragment, then run the test -- is an algorithm. -/
instance decidableInFragment (G : List Constraint) (c : Constraint) :
    Decidable (IsDefList G ∧ Abstract G ∧ LinearCheck G ∧ c.conc = ∅) := by
  infer_instance

/-- Every constraint of an in-fragment system passes its own test: the procedure is
reflexive, hence not vacuously refuting. -/
theorem test_of_mem {G : List Constraint} {d : Constraint} (hG : IsDefList G)
    (habs : Abstract G) (hlin : Linear G) (hd : d ∈ G) : Test G d :=
  test_of_entails hG habs hlin (habs d hd) (entails_of_mem hd)

/-! ## 8. (F5) The edges of the fragment

Two systems on which the test is INCOMPLETE.  The first is the expected one: two
constraints on the same left-hand side, i.e. outside the definitional fragment.  The
second is a genuine surprise -- it is a perfectly good definition list, but not linear,
and the test fails there too.  So `Linear` is not a convenience hypothesis. -/

namespace NotDefinitional

/-- `x <- (y)` and `x <- (z)`: definitional except that `x` is defined twice. -/
def G : List Constraint := [⟨0, [1], ∅⟩, ⟨0, [2], ∅⟩]

/-- `y <- (z)`. -/
def c : Constraint := ⟨1, [2], ∅⟩

theorem not_uniq : ¬ (∀ d ∈ G, ∀ e ∈ G, d.lhs = e.lhs → d = e) := by
  intro h
  have := h ⟨0, [1], ∅⟩ (by simp [G]) ⟨0, [2], ∅⟩ (by simp [G]) rfl
  simp at this

theorem abstract : Abstract G := by
  intro d hd
  simp only [G, List.mem_cons, List.not_mem_nil, or_false] at hd
  rcases hd with rfl | rfl <;> rfl

/-- Both constraints force `x` to be the whole of `y` and the whole of `z`, so `y` and
`z` are equal in every model and `y <- (z)` is entailed. -/
theorem entails : Entails G c := by
  intro rho hm
  have h1 : Sat rho ⟨0, [1], ∅⟩ := hm _ (by simp [G])
  have h2 : Sat rho ⟨0, [2], ∅⟩ := hm _ (by simp [G])
  rw [sat_one] at h1 h2
  have hyz : rho 1 = rho 2 := by
    have := h1.1.symm.trans h2.1
    simpa using this
  show Sat rho ⟨1, [2], ∅⟩
  rw [sat_one]
  exact ⟨by rw [hyz]; simp, by simp⟩

theorem leaves_lhs : leaves G c.lhs = [1] := by decide

theorem leaves_rhs : (c.vars.map (leaves G)).flatten = [2] := by decide

/-- ... but the test fails: `y` and `z` are distinct leaves. -/
theorem not_test : ¬ Test G c := by
  rintro ⟨hperm, -, -, -⟩
  rw [leaves_lhs, leaves_rhs] at hperm
  have : (1 : Var) ∈ [2] := hperm.mem_iff.mp (by simp)
  simp at this

/-- The test is incomplete outside the definitional fragment. -/
theorem entails_not_test : Entails G c ∧ ¬ Test G c := ⟨entails, not_test⟩

end NotDefinitional

namespace NonLinear

/-- `p <- (d, d)`: a bona fide definition list, but the expansion of `p` repeats `d`. -/
def G : List Constraint := [⟨0, [1, 1], ∅⟩]

/-- `p <- (d)`. -/
def c : Constraint := ⟨0, [1], ∅⟩

theorem isDefList : IsDefList G := by
  refine ⟨by decide, ?_, trivial⟩
  intro d hd
  simp at hd

theorem abstract : Abstract G := by
  intro d hd
  simp only [G, List.mem_cons, List.not_mem_nil, or_false] at hd
  rcases hd with rfl
  rfl

/-- The repeated variable is forced empty, hence so is `p`, hence `p <- (d)` holds. -/
theorem entails : Entails G c := by
  intro rho hm
  have h : Sat rho ⟨0, [1, 1], ∅⟩ := hm _ (by simp [G])
  have hd : rho 1 = ∅ := h.eq_empty_of_dup (v := 1) (by decide)
  have hp : rho 0 = ∅ := by
    rw [sat_two] at h
    rw [h.1, hd]
    simp
  show Sat rho ⟨0, [1], ∅⟩
  rw [sat_one, hp, hd]
  exact ⟨by simp, by simp⟩

theorem leaves_lhs : leaves G c.lhs = [1, 1] := by decide

theorem leaves_rhs : (c.vars.map (leaves G)).flatten = [1] := by decide

theorem not_linear : ¬ Linear G := by
  intro h
  have := h 0
  rw [show leaves G 0 = [1, 1] from leaves_lhs] at this
  simp at this

/-- The test fails, although `G` IS a definition list: the expansions have different
lengths.  So `Linear` is genuinely needed for completeness. -/
theorem not_test : ¬ Test G c := by
  rintro ⟨hperm, -, -, -⟩
  rw [leaves_lhs, leaves_rhs] at hperm
  have := hperm.length_eq
  simp at this

/-- Completeness fails inside the definitional fragment without linearity. -/
theorem entails_not_test : IsDefList G ∧ Abstract G ∧ Entails G c ∧ ¬ Test G c :=
  ⟨isDefList, abstract, entails, not_test⟩

end NonLinear

/-! ## 9. A worked instance of the procedure

`x <- (y, z)`, `y <- (u, v)`; the test proves `x <- (u, v, z)` with no search. -/

namespace Worked

/-- `x <- (y, z)` and `y <- (u, v)`. -/
def G : List Constraint := [⟨0, [1, 2], ∅⟩, ⟨1, [3, 4], ∅⟩]

/-- `x <- (u, v, z)`. -/
def c : Constraint := ⟨0, [3, 4, 2], ∅⟩

theorem isDefList : IsDefList G := by
  refine ⟨by decide, ?_, by decide, ?_, trivial⟩
  · intro d hd
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hd
    subst hd
    exact ⟨by decide, by decide⟩
  · intro d hd
    simp at hd

theorem abstract : Abstract G := by
  intro d hd
  simp only [G, List.mem_cons, List.not_mem_nil, or_false] at hd
  rcases hd with rfl | rfl <;> rfl

theorem linear : Linear G := linear_iff.mpr (by decide)

theorem test : Test G c := by decide

/-- Entailment, by the decision procedure alone. -/
theorem entails : Entails G c := entails_of_test test

/-- `x <- (u, v)`: NOT entailed, since `z` is missing. -/
def c' : Constraint := ⟨0, [3, 4], ∅⟩

theorem not_test' : ¬ Test G c' := by decide

/-- ... and the procedure REFUTES it, using completeness.  So the test is not a
one-sided heuristic on this system: it decides. -/
theorem not_entails' : ¬ Entails G c' := fun h =>
  not_test' (test_of_entails isDefList abstract linear rfl h)

end Worked

end Rowpartition

