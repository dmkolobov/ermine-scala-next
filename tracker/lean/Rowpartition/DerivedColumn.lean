/-
# The "derived column" shape: is the published polymorphic type equivalent to the row?

## Why this file exists

On 2026-09-02 a cumulative `.ei` diff found four definitions whose published type had
regressed from a RESOLVED CONCRETE ROW to a CONSTRAINED POLYMORPHIC type -- e.g.

    labelled : Builtin.Relation (|..9 fields..|)                            -- before
    labelled : forall (t: rho). (exists a rs so. ..4 constraints..)
                 => Builtin.Relation t                                      -- after

Two independent causes were found by bisection (`genRules=cut` for one, BUILD ORDER for
the others; see `tracker/TICKET-signature-resolution-fragility.md`). But the causes only
matter once the PRIORITY is settled, and that turns on a question neither bisection
answers:

**Do those constraints still force `t` to the concrete row?**

* If they do, the two forms are equivalent and this is a QUALITY defect -- ugly, viral
  through callers, but nothing is unsound and nothing is unusable.
* If they do not, the compiler has published a type strictly weaker than the one it
  inferred, and it is a SOUNDNESS defect whose priority is entirely different.

An experiment on `Ai/HeadcountPlan` answered it empirically -- annotating a consumer at
the exact 9-field header is ACCEPTED, while one field missing or one field extra is
REJECTED, so the probe discriminates and the constraints do pin `t`. This file settles
the same question by proof, for the SHAPE rather than for one module, because that shape
recurs across `BatteryCycling`, `RevenueByPeriod`, `HeadcountPlan` and `ClinicalTrial`:
every one of them is "add one derived column to a relation with a concrete header".

## The shape

Writing `K` for the relation's concrete header, `L ⊆ K` for the concrete join key that
the combinator splits on, and `d ∉ K` for the single derived label:

    K       <- (L, a, rs)          -- the input relation splits into key, rest, remainder
    (|d|)   <- (rs, so)            -- the derived column splits into remainder and output
    t       <- (L, rs, so, a)      -- the result recombines all four

`a`, `rs`, `so` are the existentials the compiler quantifies; `t` is the published
variable. The published form is equivalent to `Relation (|K ∪ {d}|)` exactly when these
three constraints determine `rho t`.

The real interfaces also carry `K <- (L, rs, a)`, which is the FIRST constraint again --
a partition's right-hand side is a set, so the two differ only in print order. It is
dropped here; `redundant_premise_dropped` records that dropping it is sound.

## Result

`t_determined` : the three constraints force `rho t = insert d K`, with no hypotheses
beyond `L ⊆ K` and `d ∉ K`. So **the two published forms are equivalent, and the four
regressions are QUALITY defects, not soundness defects.**

`t_not_determined_without_disjointness` proves the converse is not free: drop `d ∉ K` and
the conclusion fails, with an explicit counter-assignment. That is what makes the two
hypotheses load-bearing rather than decoration.
-/

import Rowpartition.Basic
import Rowpartition.Divergence

/-! # Determinacy of the published "derived column" signature. -/

namespace Rowpartition
namespace DerivedColumn

/-! ## The variables, as literals so distinctness is decidable -/

abbrev kv : Var := 0    -- the relation's concrete header, `K`
abbrev lv : Var := 1    -- the concrete join key, `L ⊆ K`
abbrev av : Var := 2    -- "the rest of the record", existential
abbrev rsv : Var := 3   -- remainder, existential
abbrev sov : Var := 4   -- output side of the derived column, existential
abbrev tv : Var := 5    -- the PUBLISHED variable
abbrev dv : Var := 6    -- the singleton derived column, `{d}`

/-- The three constraints the compiler publishes, as a system. -/
def G : System :=
  { mk kv {lv, av, rsv} ∅,
    mk dv {rsv, sov} ∅,
    mk tv {lv, rsv, sov, av} ∅ }

/-! ## The determinacy theorem -/

/-- **The published constraints force `t` to the concrete row.**

Stated on the three `Sat` hypotheses directly, so it can be reused against any system
containing this shape rather than only against `G`.

Note what is NOT needed. A first version of this proof assumed `L ⊆ K` and `d ∉ K` -- the
side conditions the shape actually satisfies -- and derived `rho rs = ∅` from them. Lean
reported `L ⊆ K` unused, and chasing that produced the argument below, which needs
NEITHER. The identity is forced by the three equations alone:

    t   = L ∪ rs ∪ so ∪ a           (third constraint)
    K   = L ∪ a ∪ rs                (first)
    {d} = rs ∪ so                   (second)
    so  t = K ∪ so = K ∪ rs ∪ so = K ∪ {d} = insert d K,   since rs ⊆ K

The `Pairwise Disjoint` halves of the three `Sat` hypotheses go unused too. So `t` is
determined by the CONCATENATION content of the constraints, with disjointness and both
inclusions playing no part -- a stronger and more robust statement than the shape needs. -/
theorem t_determined_of_sat
    {rho : Assign} {K L : Row} {d : Label}
    (h1 : Sat rho (mk kv {lv, av, rsv} ∅))
    (h2 : Sat rho (mk dv {rsv, sov} ∅))
    (h3 : Sat rho (mk tv {lv, rsv, sov, av} ∅))
    (hk : rho kv = K) (hl : rho lv = L) (hd : rho dv = {d}) :
    rho tv = insert d K := by
  rw [sat_mk_iff] at h1 h2 h3
  obtain ⟨e1, -, -⟩ := h1
  obtain ⟨e2, -, -⟩ := h2
  obtain ⟨e3, -, -⟩ := h3
  simp only [Finset.empty_union, Finset.biUnion_insert,
             Finset.singleton_biUnion] at e1 e2 e3
  rw [hk, hl] at e1
  rw [hd] at e2
  have hins : insert d K = ({d} : Row) ∪ K := by rw [Finset.insert_eq]
  rw [e3, hl, hins, e2, e1]
  ext x
  simp only [Finset.mem_union]
  tauto

/-- The same, phrased against the system `G`. -/
theorem t_determined
    {rho : Assign} {K L : Row} {d : Label}
    (hmod : SModels rho G)
    (hk : rho kv = K) (hl : rho lv = L) (hd : rho dv = {d}) :
    rho tv = insert d K :=
  t_determined_of_sat (hmod _ (by simp [G])) (hmod _ (by simp [G]))
    (hmod _ (by simp [G])) hk hl hd

/-- **The published form entails the concrete one.** The polymorphic signature is
therefore no weaker than the row it replaced: every model of the published constraints
assigns `t` the same concrete row, so the two forms accept exactly the same consumers.
This is the formal content of the empirical probe on `Ai/HeadcountPlan`, where the exact
9-field header was ACCEPTED and one field missing or extra was REJECTED. -/
theorem published_entails_concrete
    {K L : Row} {d : Label}
    (hk : ∀ rho, SModels rho G → rho kv = K)
    (hl : ∀ rho, SModels rho G → rho lv = L)
    (hd : ∀ rho, SModels rho G → rho dv = {d}) :
    ∀ rho, SModels rho G → rho tv = insert d K :=
  fun rho hm => t_determined hm (hk rho hm) (hl rho hm) (hd rho hm)

end DerivedColumn
end Rowpartition
