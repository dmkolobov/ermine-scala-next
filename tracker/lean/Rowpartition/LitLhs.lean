/-
# A literal column set on the left of a partition

`(|K|) <- (p1, .., pk)` says that the literal row `K` is the disjoint union of the parts.
`Constraint.lhs` is a variable, so the model in `Basic.lean` cannot write this shape, and
until 2026-10 the signature check (`SigEntail.scala`) gave no verdict when one reached it.

The compiler now encodes it with a variable of its own.  For a fresh `z` it emits

    z <- (|K|)          -- `pin`:  z is exactly the literal
    z <- (p1, .., pk)   -- `body`: the partition, read at z

which is what the solver already does for the same shape (`Constraints.scala`,
`PQueue.build`, the branch "lhs is not a variable").

This file proves that the encoding does not change the judgement, in either direction:

* `wanted_enc_iff`: for an obligation, when the check may CHOOSE `z` (it joins `F`);
* `given_enc_iff`:  for a given, when `z` stays RIGID;
* `sigEntailsL_iff_encoded`: both, for whole lists, ending in the plain `SigEntails`
  that `sigDecide` decides.

The side matters.  Reading an obligation's `z` as rigid would let a model of the givens
put the wrong row in `z` and reject an honest signature; `Example.keep_accepted` is the
module that prompted this work.
-/
import Rowpartition.SigEntail

namespace Rowpartition
namespace SigEntail
namespace LitLhs

/-! ## 1. The shape and its encoding -/

/-- A partition whose whole is a literal column set: `(|whole|) <- (vars.., conc)`. -/
structure LitPart where
  whole : Finset Label
  vars : List Var
  conc : Finset Label

/-- `rho` satisfies it: the literal is the disjoint union of the parts.  This is `Sat`
with the literal in place of `rho c.lhs`. -/
def LSat (rho : Assign) (p : LitPart) : Prop :=
  p.whole = (p.conc :: p.vars.map rho).foldr (· ∪ ·) ∅ ∧
    (p.conc :: p.vars.map rho).Pairwise Disjoint

/-- `z <- (|K|)`: pins the encoder's variable to the literal. -/
def pin (z : Var) (K : Finset Label) : Constraint := ⟨z, [], K⟩

/-- `z <- (vars.., conc)`: the partition, read at the encoder's variable. -/
def body (z : Var) (p : LitPart) : Constraint := ⟨z, p.vars, p.conc⟩

/-- The two constraints the encoder emits for one literal-whole partition. -/
def enc (z : Var) (p : LitPart) : List Constraint := [pin z p.whole, body z p]

@[simp] theorem sat_pin (rho : Assign) (z : Var) (K : Finset Label) :
    Sat rho (pin z K) ↔ rho z = K := by
  simp [Sat, pin, parts]

theorem sat_body_iff {rho : Assign} {z : Var} {p : LitPart} (hz : rho z = p.whole) :
    Sat rho (body z p) ↔ LSat rho p := by
  simp [Sat, LSat, body, parts, hz]

/-- At one assignment, the pair says "`z` is the literal, and the literal is partitioned".
No freshness is needed for this. -/
theorem models_enc_iff {rho : Assign} {z : Var} {p : LitPart} :
    Models rho (enc z p) ↔ rho z = p.whole ∧ LSat rho p := by
  constructor
  · intro h
    have h1 : rho z = p.whole := (sat_pin rho z p.whole).mp (h _ (by simp [enc]))
    exact ⟨h1, (sat_body_iff h1).mp (h _ (by simp [enc]))⟩
  · rintro ⟨h1, h2⟩ c hc
    simp only [enc, List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl
    · exact (sat_pin rho z p.whole).mpr h1
    · exact (sat_body_iff h1).mpr h2

/-- `LSat` reads the assignment only at the partition's variable parts. -/
theorem lsat_congr {rho rho' : Assign} {p : LitPart} (h : ∀ v ∈ p.vars, rho v = rho' v) :
    LSat rho p ↔ LSat rho' p := by
  have hp : p.vars.map rho = p.vars.map rho' := List.map_congr_left h
  simp [LSat, hp]

theorem lsat_upd {rho : Assign} {z : Var} {s : Row} {p : LitPart} (hz : z ∉ p.vars) :
    LSat (upd rho z s) p ↔ LSat rho p :=
  lsat_congr (fun _ hv => upd_ne rho s (fun h => hz (h ▸ hv)))

theorem models_upd {rho : Assign} {z : Var} {s : Row} {G : List Constraint} (hz : z ∉ voc G) :
    Models (upd rho z s) G ↔ Models rho G :=
  models_congr (fun _ hv => upd_ne rho s (fun h => hz (h ▸ hv)))

/-- A variable that is not `z`, not a part of `p` and not in `G` is not in the vocabulary
of `enc z p ++ G`.  The freshness step of both folds below. -/
theorem not_mem_voc_enc_append {G : List Constraint} {z z' : Var} {p : LitPart}
    (hne : z' ≠ z) (hp : z' ∉ p.vars) (hG : z' ∉ voc G) : z' ∉ voc (enc z p ++ G) := by
  intro h
  obtain ⟨c, hc, hv⟩ := mem_voc.mp h
  rcases List.mem_append.mp hc with hc | hc
  · simp only [enc, List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl
    · simp [pin, vset, hne] at hv
    · simp [body, vset, hne, hp] at hv
  · exact hG (mem_voc_of_mem hc hv)

/-! ## 2. The judgement with literal wholes, and one encoding step on each side -/

/-- `SigEntails` with literal-whole partitions among the givens (`LQ`) and among the
obligations (`LW`).  With both lists empty it is `SigEntails`. -/
def SigEntailsL (Q W : List Constraint) (LQ LW : List LitPart) (F : Finset Var) : Prop :=
  ∀ rho, Models rho Q → (∀ p ∈ LQ, LSat rho p) →
    ∃ rho', AgreeOff F rho rho' ∧ Models rho' W ∧ ∀ p ∈ LW, LSat rho' p

theorem sigEntailsL_nil {Q W : List Constraint} {F : Finset Var} :
    SigEntailsL Q W [] [] F ↔ SigEntails Q W F := by
  simp [SigEntailsL, SigEntails]

/-- **An obligation with a literal whole.**  Replace it by its encoding and let the check
choose `z`.  `z` must not occur in the other obligations. -/
theorem wanted_enc_iff {Q W : List Constraint} {LQ LW : List LitPart} {F : Finset Var}
    {z : Var} {p : LitPart}
    (hW : z ∉ voc W) (hp : z ∉ p.vars) (hLW : ∀ q ∈ LW, z ∉ q.vars) :
    SigEntailsL Q W LQ (p :: LW) F ↔ SigEntailsL Q (enc z p ++ W) LQ LW (insert z F) := by
  constructor
  · intro h rho hQ hLQ
    obtain ⟨rho', hag, hmW, hmL⟩ := h rho hQ hLQ
    refine ⟨upd rho' z p.whole, ?_, ?_, ?_⟩
    · intro v hv
      have hvz : v ≠ z := fun e => hv (e ▸ Finset.mem_insert_self _ _)
      have hvF : v ∉ F := fun e => hv (Finset.mem_insert_of_mem e)
      rw [upd_ne rho' _ hvz]; exact hag v hvF
    · intro c hc
      rcases List.mem_append.mp hc with hc | hc
      · exact (models_enc_iff.mpr ⟨upd_same _ _ _,
          (lsat_upd hp).mpr (hmL p (by simp))⟩) c hc
      · exact (models_upd hW).mpr hmW c hc
    · intro q hq
      exact (lsat_upd (hLW q hq)).mpr (hmL q (by simp [hq]))
  · intro h rho hQ hLQ
    obtain ⟨rho', hag, hm, hmL⟩ := h rho hQ hLQ
    have hmE : Models rho' (enc z p) := fun c hc => hm c (List.mem_append.mpr (Or.inl hc))
    have hmW : Models rho' W := fun c hc => hm c (List.mem_append.mpr (Or.inr hc))
    refine ⟨upd rho' z (rho z), ?_, (models_upd hW).mpr hmW, ?_⟩
    · intro v hv
      by_cases hvz : v = z
      · subst hvz; exact upd_same _ _ _
      · rw [upd_ne rho' _ hvz]
        exact hag v (fun e => (Finset.mem_insert.mp e).elim hvz hv)
    · intro q hq
      rcases List.mem_cons.mp hq with rfl | hq
      · exact (lsat_upd hp).mpr (models_enc_iff.mp hmE).2
      · exact (lsat_upd (hLW q hq)).mpr (hmL q hq)

/-- **A given with a literal whole.**  Replace it by its encoding and keep `z` rigid: it
is not added to `F`.  The pin leaves `z` one value, so quantifying over it universally
costs nothing.  `z` must be fresh for everything else. -/
theorem given_enc_iff {Q W : List Constraint} {LQ LW : List LitPart} {F : Finset Var}
    {z : Var} {p : LitPart}
    (hQ : z ∉ voc Q) (hW : z ∉ voc W) (hp : z ∉ p.vars)
    (hLQ : ∀ q ∈ LQ, z ∉ q.vars) (hLW : ∀ q ∈ LW, z ∉ q.vars) :
    SigEntailsL Q W (p :: LQ) LW F ↔ SigEntailsL (enc z p ++ Q) W LQ LW F := by
  constructor
  · intro h rho hm hL
    have hmE : Models rho (enc z p) := fun c hc => hm c (List.mem_append.mpr (Or.inl hc))
    have hmQ : Models rho Q := fun c hc => hm c (List.mem_append.mpr (Or.inr hc))
    refine h rho hmQ ?_
    intro q hq
    rcases List.mem_cons.mp hq with rfl | hq
    · exact (models_enc_iff.mp hmE).2
    · exact hL q hq
  · intro h rho hmQ hL
    have hE : Models (upd rho z p.whole) (enc z p ++ Q) := by
      intro c hc
      rcases List.mem_append.mp hc with hc | hc
      · exact (models_enc_iff.mpr ⟨upd_same _ _ _, (lsat_upd hp).mpr (hL p (by simp))⟩) c hc
      · exact (models_upd hQ).mpr hmQ c hc
    have hL' : ∀ q ∈ LQ, LSat (upd rho z p.whole) q := fun q hq =>
      (lsat_upd (hLQ q hq)).mpr (hL q (by simp [hq]))
    obtain ⟨rho', hag, hmW, hmL⟩ := h _ hE hL'
    refine ⟨upd rho' z (rho z), ?_, (models_upd hW).mpr hmW, ?_⟩
    · intro v hv
      by_cases hvz : v = z
      · subst hvz; exact upd_same _ _ _
      · rw [upd_ne rho' _ hvz, hag v hv, upd_ne rho _ hvz]
    · intro q hq
      exact (lsat_upd (hLW q hq)).mpr (hmL q hq)

/-! ## 3. Whole lists

`encAll zs L G` encodes the partitions of `L` with the variables `zs`, one each, in front
of `G`.  The two folds below apply the one-step lemmas down the lists. -/

/-- Encode each partition of the list with the matching variable, in front of `G`. -/
def encAll : List Var → List LitPart → List Constraint → List Constraint
  | z :: zs, p :: ps, G => encAll zs ps (enc z p ++ G)
  | _, _, G => G

/-- Every literal-whole obligation encoded, with all of `zs` chosen. -/
theorem wanted_encAll_iff {Q : List Constraint} {LQ : List LitPart} :
    ∀ (LW : List LitPart) (zs : List Var) (W : List Constraint) (F : Finset Var),
      zs.length = LW.length → zs.Nodup → (∀ z ∈ zs, z ∉ voc W) →
      (∀ z ∈ zs, ∀ q ∈ LW, z ∉ q.vars) →
      (SigEntailsL Q W LQ LW F ↔ SigEntailsL Q (encAll zs LW W) LQ [] (F ∪ zs.toFinset))
  | [], zs, W, F, hlen, _, _, _ => by
      have hz : zs = [] := List.length_eq_zero_iff.mp hlen
      subst hz
      simp [encAll]
  | p :: ps, [], _, _, hlen, _, _, _ => by simp at hlen
  | p :: ps, z :: zs, W, F, hlen, hnd, hW, hL => by
      have hnd' := List.nodup_cons.mp hnd
      rw [wanted_enc_iff (hW z (by simp)) (hL z (by simp) p (by simp))
            (fun q hq => hL z (by simp) q (by simp [hq]))]
      rw [wanted_encAll_iff ps zs (enc z p ++ W) (insert z F) (by simpa using hlen) hnd'.2
            (fun z' hz' => not_mem_voc_enc_append (fun e => hnd'.1 (e ▸ hz'))
              (hL z' (by simp [hz']) p (by simp)) (hW z' (by simp [hz'])))
            (fun z' hz' q hq => hL z' (by simp [hz']) q (by simp [hq]))]
      have hF : insert z F ∪ zs.toFinset = F ∪ (z :: zs).toFinset := by
        ext v; simp only [Finset.mem_union, Finset.mem_insert, List.toFinset_cons]; tauto
      simp only [encAll, hF]

/-- Every literal-whole given encoded, with all of `zs` rigid. -/
theorem given_encAll_iff {W : List Constraint} {LW : List LitPart} {F : Finset Var} :
    ∀ (LQ : List LitPart) (zs : List Var) (Q : List Constraint),
      zs.length = LQ.length → zs.Nodup → (∀ z ∈ zs, z ∉ voc Q) → (∀ z ∈ zs, z ∉ voc W) →
      (∀ z ∈ zs, ∀ q ∈ LQ, z ∉ q.vars) → (∀ z ∈ zs, ∀ q ∈ LW, z ∉ q.vars) →
      (SigEntailsL Q W LQ LW F ↔ SigEntailsL (encAll zs LQ Q) W [] LW F)
  | [], zs, Q, hlen, _, _, _, _, _ => by
      have hz : zs = [] := List.length_eq_zero_iff.mp hlen
      subst hz
      simp [encAll]
  | p :: ps, [], _, hlen, _, _, _, _, _ => by simp at hlen
  | p :: ps, z :: zs, Q, hlen, hnd, hQ, hW, hLQ, hLW => by
      have hnd' := List.nodup_cons.mp hnd
      rw [given_enc_iff (hQ z (by simp)) (hW z (by simp)) (hLQ z (by simp) p (by simp))
            (fun q hq => hLQ z (by simp) q (by simp [hq])) (hLW z (by simp))]
      rw [given_encAll_iff ps zs (enc z p ++ Q) (by simpa using hlen) hnd'.2
            (fun z' hz' => not_mem_voc_enc_append (fun e => hnd'.1 (e ▸ hz'))
              (hLQ z' (by simp [hz']) p (by simp)) (hQ z' (by simp [hz'])))
            (fun z' hz' => hW z' (by simp [hz']))
            (fun z' hz' q hq => hLQ z' (by simp [hz']) q (by simp [hq]))
            (fun z' hz' => hLW z' (by simp [hz']))]
      simp only [encAll]

/-- **The encoding is exact.**  A judgement with literal wholes on either side holds iff
the plain judgement holds on the encoded lists, with the obligations' variables `zw`
chosen and the givens' variables `zq` rigid.  The right-hand side is what the compiler
hands to the decision procedure. -/
theorem sigEntailsL_iff_encoded {Q W : List Constraint} {LQ LW : List LitPart}
    {F : Finset Var} {zq zw : List Var}
    (hqlen : zq.length = LQ.length) (hqnd : zq.Nodup)
    (hqQ : ∀ z ∈ zq, z ∉ voc Q) (hqW : ∀ z ∈ zq, z ∉ voc W)
    (hqLQ : ∀ z ∈ zq, ∀ q ∈ LQ, z ∉ q.vars) (hqLW : ∀ z ∈ zq, ∀ q ∈ LW, z ∉ q.vars)
    (hwlen : zw.length = LW.length) (hwnd : zw.Nodup)
    (hwW : ∀ z ∈ zw, z ∉ voc W) (hwLW : ∀ z ∈ zw, ∀ q ∈ LW, z ∉ q.vars) :
    SigEntailsL Q W LQ LW F ↔
      SigEntails (encAll zq LQ Q) (encAll zw LW W) (F ∪ zw.toFinset) := by
  rw [given_encAll_iff LQ zq Q hqlen hqnd hqQ hqW hqLQ hqLW,
      wanted_encAll_iff LW zw W F hwlen hwnd hwW hwLW, sigEntailsL_nil]

/-! ## 4. Two modules, decided

The honest module that prompted this work, and a dishonest one that only the literal-whole
partition refutes. -/

namespace Example

/-  keepKey : Has inputRow (|demoKey|) => Relation inputRow -> Relation inputRow
    keepKey rows = join rows (project {demoKey} rows)

    label 0 = demoKey.  Rigid: 1 = inputRow, 2 = the given's remainder.
    Chosen: 3 = t1, 4 = k, 5 = t2, 6 = the obligation's remainder, 7 = z. -/
def keepQ : List Constraint := [⟨1, [2], {0}⟩]
def keepW : List Constraint :=
  enc 7 ⟨{0}, [4, 5], ∅⟩ ++ [⟨1, [3, 4], ∅⟩, ⟨1, [3, 4, 5], ∅⟩, ⟨1, [6], {0}⟩]

theorem keep_accepted :
    sigDecide keepQ keepW [3, 4, 5, 6, 7] [1, 2, 3, 4, 5, 6, 7] [0] 1 = true := by decide

/-  joinLit : Relation r1 -> Relation r2 -> Relation (|a, b|)
    joinLit x y = join x y

    labels 0 = a, 1 = b.  Rigid: 1 = r1, 2 = r2.  Chosen: 3 = k, 4 = t1, 5 = t2, 6 = z.
    The two obligations that mention r1 and r2 hold for every r1, r2 (take k empty).
    Only the literal-whole partition refutes the signature. -/
def joinLitW₀ : List Constraint := [⟨1, [3, 4], ∅⟩, ⟨2, [3, 5], ∅⟩]
def joinLitW : List Constraint := enc 6 ⟨{0, 1}, [3, 4, 5], ∅⟩ ++ joinLitW₀

/-- Without the literal-whole partition the signature is accepted: the old behaviour. -/
theorem joinLit_dropped_accepts :
    sigDecide [] joinLitW₀ [3, 4, 5] [1, 2, 3, 4, 5] [] 0 = true := by decide

/-- With it, the signature is rejected. -/
theorem joinLit_rejected :
    sigDecide [] joinLitW [3, 4, 5, 6] [1, 2, 3, 4, 5, 6] [0, 1] 2 = false := by decide

end Example

end LitLhs
end SigEntail
end Rowpartition
