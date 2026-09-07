/-
# S3: the two deletions `Subst.mkSimplified` makes are entailment-preserving

`mkSimplified` is the POST-LOOP simplifier that turns a solved system into the
qualification of a published signature.  Stage S3 makes it delete two things it was
already trying to delete and failing to:

* a **permuted duplicate** -- a constraint with the same left-hand side, the same
  concrete part, and the same MULTISET of variable parts as one already kept
  (`NormalPart.equals` was already up to permutation; `hashCode` was not, so
  `List.distinct` never compared them);
* the **tautology** `a <- (a)` -- one part, itself.

Both deletions must leave the published residual EQUIVALENT to what it was.  That is
what this file proves, in the `SEntails` vocabulary of `Rowpartition/Divergence.lean`.

Nothing here is new mathematics: `Rowpartition/Canonical.lean` already implements both
rules (`Step.dedup`, "duplicate constraints, RECOGNISED UP TO PERMUTATION of the RHS",
and `Step.occurs`, which "also deletes the vacuous `r <- (r)`") and already proves
`Step.preserves`.  The point of this file is to state the two facts in the exact form
the S3 report's soundness argument uses, with no reference to a `State` or a rule
system: for a raw `System`, deleting either kind of member is a two-way entailment.
-/
import Rowpartition.Divergence

namespace Rowpartition
namespace S3

/-! ## 1. Permutation of the variable parts is invisible to `Sat` -/

/-- `Sat` sees the variable parts only through `parts`, and `parts` through a `foldr`
union and a `Pairwise Disjoint`, both of which are permutation-invariant. -/
theorem sat_congr_of_perm {rho : Assign} {c c' : Constraint}
    (hl : c.lhs = c'.lhs) (hk : c.conc = c'.conc) (hp : c.vars.Perm c'.vars) :
    Sat rho c ↔ Sat rho c' := by
  have : LeftCommutative (fun s t : Finset Label => s ∪ t) :=
    ⟨fun s t u => Finset.union_left_comm s t u⟩
  have hparts : (parts rho c).Perm (parts rho c') := by
    simp only [parts, hk]
    exact (hp.map rho).cons _
  have hsym : ∀ {x y : Row}, Disjoint x y → Disjoint y x := fun h => h.symm
  constructor
  · rintro ⟨he, hd⟩
    exact ⟨by rw [← hl, he]; exact hparts.foldr_eq _, hparts.pairwise hd hsym⟩
  · rintro ⟨he, hd⟩
    exact ⟨by rw [hl, he]; exact hparts.symm.foldr_eq _, hparts.symm.pairwise hd hsym⟩

/-- A permuted duplicate is entailed by the copy that is kept. -/
theorem sEntails_of_perm {G : System} {c c' : Constraint} (hc : c ∈ G)
    (hl : c.lhs = c'.lhs) (hk : c.conc = c'.conc) (hp : c.vars.Perm c'.vars) :
    SEntails G c' :=
  fun rho hm => (sat_congr_of_perm hl hk hp).mp (hm c hc)

/-! ## 2. `a <- (a)` is a tautology -/

/-- The constraint `a <- (a)`: one variable part, the left-hand variable itself, and an
empty concrete part. -/
def taut (a : Var) : Constraint := ⟨a, [a], ∅⟩

/-- Every assignment satisfies `a <- (a)`. -/
theorem sat_taut (rho : Assign) (a : Var) : Sat rho (taut a) := by
  constructor
  · simp [taut, parts]
  · simp [taut, parts]

/-- Hence it is entailed by every system, the empty one included. -/
theorem sEntails_taut (_G : System) (a : Var) : SEntails _G (taut a) :=
  fun rho _ => sat_taut rho a

/-! ## 3. The two deletions preserve equivalence -/

/-- Two systems are equivalent when each entails every member of the other. -/
def SEquiv (G G' : System) : Prop :=
  (∀ c ∈ G, SEntails G' c) ∧ (∀ c ∈ G', SEntails G c)

/-- Deleting is never a loss of the OTHER direction: a subset is entailed by its
superset, member by member.  (`Conserv`, in `Loop/Strict.lean`'s vocabulary.) -/
theorem sEntails_of_mem_subset {G G' : System} (hsub : G ⊆ G') {c : Constraint}
    (hc : c ∈ G) : SEntails G' c :=
  fun _ hm => hm c (hsub hc)

/-- **Deleting a permuted duplicate preserves equivalence.**  If `G` holds both `c` and
`c'` and they differ only by a permutation of the variable parts, then `G` and
`G.erase c'` say exactly the same thing. -/
theorem erase_perm_dup_equiv {G : System} {c c' : Constraint}
    (hc : c ∈ G) (hne : c ≠ c')
    (hl : c.lhs = c'.lhs) (hk : c.conc = c'.conc) (hp : c.vars.Perm c'.vars) :
    SEquiv G (G.erase c') := by
  refine ⟨fun d hd rho hm => ?_, fun d hd => sEntails_of_mem_subset (Finset.erase_subset _ _) hd⟩
  by_cases h : d = c'
  · subst h
    exact sEntails_of_perm (Finset.mem_erase.mpr ⟨hne, hc⟩) hl hk hp rho hm
  · exact hm d (Finset.mem_erase.mpr ⟨h, hd⟩)

/-- **Deleting the tautology `a <- (a)` preserves equivalence.**  No hypothesis about
what else is in `G` is needed: `a <- (a)` is entailed by anything. -/
theorem erase_taut_equiv (G : System) (a : Var) :
    SEquiv G (G.erase (taut a)) := by
  refine ⟨fun d hd rho hm => ?_, fun d hd => sEntails_of_mem_subset (Finset.erase_subset _ _) hd⟩
  by_cases h : d = taut a
  · subst h; exact sat_taut rho a
  · exact hm d (Finset.mem_erase.mpr ⟨h, hd⟩)

/-! ## 4. The corollary the report quotes: satisfiability is unchanged

`mkSimplified` runs the constraints it drops as ISOLATED through `solve` first, "to
ensure failure for unsatisfiable sets".  The two S3 deletions bypass that check, so it
matters that neither can hide a refutation. -/

/-- An equivalent system is satisfiable exactly when the original is. -/
theorem SEquiv.sat_iff {G G' : System} (h : SEquiv G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  constructor
  · rintro ⟨rho, hm⟩; exact ⟨rho, fun c hc => h.2 c hc rho hm⟩
  · rintro ⟨rho, hm⟩; exact ⟨rho, fun c hc => h.1 c hc rho hm⟩

end S3
end Rowpartition

/-! ## 5. Nothing is assumed beyond Lean's own axioms. -/

#print axioms Rowpartition.S3.sat_congr_of_perm
#print axioms Rowpartition.S3.sEntails_of_perm
#print axioms Rowpartition.S3.sat_taut
#print axioms Rowpartition.S3.sEntails_taut
#print axioms Rowpartition.S3.sEntails_of_mem_subset
#print axioms Rowpartition.S3.erase_perm_dup_equiv
#print axioms Rowpartition.S3.erase_taut_equiv
#print axioms Rowpartition.S3.SEquiv.sat_iff
