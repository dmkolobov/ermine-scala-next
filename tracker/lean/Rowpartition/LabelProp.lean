/-
# Per-label unit propagation: the refutation rule, and why it is safe

`Basic.sat_iff_forall_label` says satisfaction is pointwise in the label: one
row-partition problem is a family of independent Boolean problems, one per label.
That theorem is a licence to REFUTE cheaply.  Fix a label `l`; every part bit
`[l ∈ ·]` is a Boolean unknown, a `ConcreteRho` pins its own bit, and the partition
`a <- (b, c, C)` says *at most one part bit is set, and `a`'s bit is their OR*.
Propagating those two facts without ever case-splitting is enough to refute the
programs the shipped solver wrongly accepts (`core/examples/incomplete/unsound0*.e`).

This file formalises that rule and proves the property that makes it adoptable
where `Constraints.disjunction` is not.

* §1  `Forced` -- the facts unit propagation derives, as an inductive relation.
* §2  `forced_sound` -- every derived bit is the bit of EVERY Boolean model.
* §3  `Refuted` and `refuted_unsat` -- a variable forced both ways means the whole
      system is unsatisfiable.  This is the rule's soundness: it never rejects a
      satisfiable program.
* §4  Monotonicity, and the fact that the rule adds no constraints.
* §5  The worked example: `unsound01_keyed_halves.e` refuted, and its sibling
      `good` exhibited as satisfiable, so soundness alone proves the rule keeps it.

WHAT IS NOT CLAIMED.  Propagation is deliberately incomplete: it never splits on an
unknown bit, so it decides only what is forced.  Deciding these Boolean systems in
general is Schaefer's one-in-three problem (ticket §1).  Refusing to search is what
makes the failure mode deterministic, and `not_complete` below exhibits an
unsatisfiable system that propagation does not refute.
-/
import Rowpartition.Basic

namespace Rowpartition

/-! ## 1. The facts unit propagation derives

`Forced l G v x` : at label `l`, the bit of variable `v` is pinned to `x` by the
system `G`.  Each constructor is one propagation step of the implementation
(`Constraints.checkLabel`).  Read `c.conc` as the merged concrete part, so
`l ∈ c.conc` is the statement "the concrete part carries this label". -/
inductive Forced (l : Label) (G : List Constraint) : Var → Bool → Prop
  /-- The concrete part carries `l`, so the whole does. -/
  | conc_lhs {c} (hc : c ∈ G) (hl : l ∈ c.conc) :
      Forced l G c.lhs true
  /-- The concrete part carries `l`, so no variable part may. -/
  | conc_var {c v} (hc : c ∈ G) (hl : l ∈ c.conc) (hv : v ∈ c.vars) :
      Forced l G v false
  /-- A variable part carries `l`, so the whole does. -/
  | var_lhs {c v} (hc : c ∈ G) (hv : v ∈ c.vars) (h : Forced l G v true) :
      Forced l G c.lhs true
  /-- A variable part carries `l`, so no OTHER part may. -/
  | var_other {c v w} (hc : c ∈ G) (hv : v ∈ c.vars) (hw : w ∈ c.vars) (hne : v ≠ w)
      (h : Forced l G v true) :
      Forced l G w false
  /-- The whole lacks `l`, so every part lacks it. -/
  | lhs_false {c v} (hc : c ∈ G) (hv : v ∈ c.vars) (h : Forced l G c.lhs false) :
      Forced l G v false
  /-- No part carries `l`, so the whole does not. -/
  | all_false {c} (hc : c ∈ G) (hl : l ∉ c.conc)
      (h : ∀ v ∈ c.vars, Forced l G v false) :
      Forced l G c.lhs false
  /-- The whole carries `l` and every part but one is ruled out: that one carries it. -/
  | last_one {c v₀} (hc : c ∈ G) (hl : l ∉ c.conc) (hv : v₀ ∈ c.vars)
      (hlhs : Forced l G c.lhs true)
      (h : ∀ w ∈ c.vars, w ≠ v₀ → Forced l G w false) :
      Forced l G v₀ true

/-! ## 2. Soundness of a single derived fact

Everything below rests on this: a `Forced` fact is not a guess, it holds in every
Boolean model of the system at that label. -/

/-- The part bits of `c` at `l`, under a Boolean assignment: the concrete bit, then
one bit per variable part.  This is `Basic.bparts`, restated for readability. -/
theorem bsat_lhs {b : Var → Bool} {l : Label} {c : Constraint} (h : BSat b l c) :
    b c.lhs = true ↔ (l ∈ c.conc ∨ ∃ v ∈ c.vars, b v = true) := by
  have h1 := h.1
  constructor
  · intro hb
    rw [hb] at h1
    have : (bparts b l c).foldr (· || ·) false = true := h1.symm
    rw [foldr_or_eq_true] at this
    simp only [bparts, List.mem_cons, List.mem_map] at this
    rcases this with ⟨x, hx, hxt⟩
    rcases hx with rfl | ⟨v, hv, rfl⟩
    · exact Or.inl (by simpa using hxt)
    · exact Or.inr ⟨v, hv, hxt⟩
  · intro hb
    rw [h1, foldr_or_eq_true]
    simp only [bparts, List.mem_cons, List.mem_map]
    rcases hb with hb | ⟨v, hv, hvt⟩
    · exact ⟨_, Or.inl rfl, by simpa using hb⟩
    · exact ⟨_, Or.inr ⟨v, hv, rfl⟩, hvt⟩

/-- At most one part bit is set: the concrete part excludes every variable part. -/
theorem bsat_conc_var {b : Var → Bool} {l : Label} {c : Constraint} (h : BSat b l c)
    (hl : l ∈ c.conc) {v : Var} (hv : v ∈ c.vars) : b v = false := by
  have hp := h.2
  simp only [bparts] at hp
  rw [List.pairwise_cons] at hp
  have := hp.1 (b v) (List.mem_map_of_mem hv)
  by_contra hbv
  exact this ⟨by simpa using hl, by simpa using hbv⟩

/-- At most one part bit is set: two DISTINCT variable parts exclude each other. -/
theorem bsat_var_var {b : Var → Bool} {l : Label} {c : Constraint} (h : BSat b l c)
    {v w : Var} (hv : v ∈ c.vars) (hw : w ∈ c.vars) (hne : v ≠ w) (hbv : b v = true) :
    b w = false := by
  have hp := h.2
  simp only [bparts] at hp
  have hp' : (c.vars.map b).Pairwise (fun x y => ¬(x = true ∧ y = true)) :=
    (List.pairwise_cons.mp hp).2
  rw [List.pairwise_map] at hp'
  have hsymm : ∀ {a d : Var}, (fun x y => ¬(b x = true ∧ b y = true)) a d →
      (fun x y => ¬(b x = true ∧ b y = true)) d a := by
    intro a d had hcon; exact had ⟨hcon.2, hcon.1⟩
  have := pairwise_ne_imp hsymm hp' hv hw hne
  by_contra hbw
  exact this ⟨hbv, by simpa using hbw⟩

/-- **Soundness of propagation.**  Every fact the rule derives is the value that
every Boolean model of the system already assigns.  Induction on the derivation;
each case is the corresponding half of `BSat`. -/
theorem forced_sound {l : Label} {G : List Constraint} {v : Var} {x : Bool}
    (hf : Forced l G v x) : ∀ b, BModels b l G → b v = x := by
  induction hf with
  | @conc_lhs c hc hl =>
      intro b hb; exact (bsat_lhs (hb c hc)).mpr (Or.inl hl)
  | @conc_var c v hc hl hv =>
      intro b hb; exact bsat_conc_var (hb c hc) hl hv
  | @var_lhs c v hc hv _ ih =>
      intro b hb; exact (bsat_lhs (hb c hc)).mpr (Or.inr ⟨v, hv, ih b hb⟩)
  | @var_other c v w hc hv hw hne _ ih =>
      intro b hb; exact bsat_var_var (hb c hc) hv hw hne (ih b hb)
  | @lhs_false c v hc hv _ ih =>
      intro b hb
      by_contra hbv
      have hbv' : b v = true := by simpa using hbv
      have hlt := (bsat_lhs (hb c hc)).mpr (Or.inr ⟨v, hv, hbv'⟩)
      rw [ih b hb] at hlt; exact Bool.noConfusion hlt
  | @all_false c hc hl _ ih =>
      intro b hb
      by_contra hlhs
      have hlhs' : b c.lhs = true := by simpa using hlhs
      rcases (bsat_lhs (hb c hc)).mp hlhs' with h | ⟨w, hw, hbw⟩
      · exact hl h
      · have := ih w hw b hb; rw [this] at hbw; exact Bool.noConfusion hbw
  | @last_one c v₀ hc hl hv _ _ ihlhs ih =>
      intro b hb
      rcases (bsat_lhs (hb c hc)).mp (ihlhs b hb) with h | ⟨w, hw, hbw⟩
      · exact absurd h hl
      · by_cases hwv : w = v₀
        · subst hwv; exact hbw
        · have := ih w hw hwv b hb; rw [this] at hbw; exact Bool.noConfusion hbw

/-! ## 3. Refutation

Every clash the implementation can report reduces to one variable forced both ways.
(Two parts both carrying `l` gives it via `var_other`; a concrete part meeting a
variable part gives it via `conc_var`; a whole carrying `l` with no part able to,
via `all_false`.  So this single shape is the whole refutation condition.) -/

/-- The system is refuted at label `l`: some variable is forced to both values. -/
def RefutedAt (l : Label) (G : List Constraint) : Prop :=
  ∃ v, Forced l G v true ∧ Forced l G v false

/-- The system is refuted: at some label, propagation clashes. -/
def Refuted (G : List Constraint) : Prop := ∃ l, RefutedAt l G

/-- **The rule is sound.**  A refuted system has no model, so the check can never
reject a program whose row constraints are satisfiable. -/
theorem refuted_unsat {G : List Constraint} (h : Refuted G) : ¬ ∃ rho, Models rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨l, v, htrue, hfalse⟩ := h
  have hb : BModels (proj rho l) l G := (models_iff_forall_label rho G).mp hm l
  have h1 : proj rho l v = true := forced_sound htrue _ hb
  have h2 : proj rho l v = false := forced_sound hfalse _ hb
  rw [h1] at h2; exact Bool.noConfusion h2

/-- Contrapositive, the form the compiler relies on: a satisfiable system is never
refuted.  This is exactly "no false rejections". -/
theorem not_refuted_of_sat {G : List Constraint} (h : ∃ rho, Models rho G) : ¬ Refuted G :=
  fun hr => refuted_unsat hr h

/-! ## 4. The rule is monotone, and it adds nothing

Two structural properties that separate this rule from `Constraints.disjunction`. -/

/-- Propagation only gains power as the system GROWS: derived facts survive weakening.

CORRECTED 2026-09-01 (ticket item 8a).  This docstring used to read "so running the check
on the SATURATED set, as the implementation does, is at least as strong as running it on
the input".  Both halves were wrong.  `Subst.solve` runs `labelClash` on the INPUT
partitions (`q.toList.map(_.tup)`), not on `q.expand`; and even if it did, the conclusion
would not follow from this theorem, because the saturated set is not a SUPERSET of the
input — `makeEmpty`, `makeConcrete`, `destructiveSub` and `instantiate` all delete
partitions and rename variables, so `G ⊆ G'` simply does not hold between the two.  What
would license reading the saturated set is "input satisfiable ⇒ saturated set satisfiable"
(`Rowpartition.Saturate`), which is a different statement about a different set of rules. -/
theorem forced_mono {l : Label} {G G' : List Constraint} (hsub : G ⊆ G')
    {v : Var} {x : Bool} (hf : Forced l G v x) : Forced l G' v x := by
  induction hf with
  | conc_lhs hc hl => exact .conc_lhs (hsub hc) hl
  | conc_var hc hl hv => exact .conc_var (hsub hc) hl hv
  | var_lhs hc hv _ ih => exact .var_lhs (hsub hc) hv ih
  | var_other hc hv hw hne _ ih => exact .var_other (hsub hc) hv hw hne ih
  | lhs_false hc hv _ ih => exact .lhs_false (hsub hc) hv ih
  | all_false hc hl _ ih => exact .all_false (hsub hc) hl ih
  | last_one hc hl hv _ _ ihlhs ih => exact .last_one (hsub hc) hl hv ihlhs ih

theorem refuted_mono {G G' : List Constraint} (hsub : G ⊆ G') (h : Refuted G) :
    Refuted G' := by
  obtain ⟨l, v, ht, hf⟩ := h
  exact ⟨l, v, forced_mono hsub ht, forced_mono hsub hf⟩

/-- **The rule is not generative** -- recorded, not proved.

READ THIS BEFORE CITING IT (corrected 2026-09-01, ticket item 8a).  The statement below is
`Models rho G ↔ Models rho G`, discharged by `Iff.rfl`.  It is a TAUTOLOGY.  It carries no
mathematical content and it is not evidence for anything; it exists only to write down, in
the vocabulary of this file, the observation that the rule's verdict is a proposition ABOUT
`G` and that no constructor of `Forced` produces a constraint.  The substantive form of
"non-generative" is the SHAPE of the rule -- `Forced : Label → List Constraint → Var → Bool
→ Prop` has no `List Constraint` in its conclusion -- and that is visible from the
declaration, not from this theorem.

The contrast with `Constraints.disjunction` (which mints a fresh variable on every emission
path and feeds the result back into saturation, ticket §7.12) is real, but it is an
observation about the two rules' types, not a consequence of the line below. -/
theorem models_unchanged (G : List Constraint) (rho : Assign) :
    Models rho G ↔ Models rho G := Iff.rfl

/-! ## 5. The worked example

`core/examples/incomplete/unsound01_keyed_halves.e`.  Vertical sharding: a ledger's
columns split into two groups, each written to its own table with the account key
stamped on.  Label 0 is `accountId`, label 1 is `regionCode`; variables 0..4 are
`t`, `l`, `s`, `lt`, `rt`.

    t  <- (l, s)                 -- the columns divide in two
    lt <- ((|accountId|), l)     -- group l plus the key is a legal header
    rt <- ((|accountId|), s)     -- group s plus the key is a legal header
    t  <- (|accountId, regionCode|)   -- the ledger ALREADY carries the key

The shipped solver accepts this.  It has no model. -/
namespace Unsound01

def t : Var := 0
def lv : Var := 1
def sv : Var := 2
def lt : Var := 3
def rt : Var := 4
def accountId : Label := 0
def regionCode : Label := 1

/-- `t <- (l, s)` -/
def cSplit : Constraint := ⟨t, [lv, sv], ∅⟩
/-- `lt <- ((|accountId|), l)` -/
def cLeft : Constraint := ⟨lt, [lv], {accountId}⟩
/-- `rt <- ((|accountId|), s)` -/
def cRight : Constraint := ⟨rt, [sv], {accountId}⟩
/-- `t <- (|accountId, regionCode|)`: the ledger, pinned. -/
def cPin : Constraint := ⟨t, [], {accountId, regionCode}⟩

def G : List Constraint := [cSplit, cLeft, cRight, cPin]

/-- The key is not in the left group: `lt <- ((|accountId|), l)` forbids it. -/
theorem l_false : Forced accountId G lv false :=
  .conc_var (c := cLeft) (by simp [G]) (by decide) (by decide)

/-- Nor in the right group, by the mirror-image constraint. -/
theorem s_false : Forced accountId G sv false :=
  .conc_var (c := cRight) (by simp [G]) (by decide) (by decide)

/-- But the ledger carries it, because it is pinned to a concrete row that does. -/
theorem t_true : Forced accountId G t true :=
  .conc_lhs (c := cPin) (by simp [G]) (by decide)

/-- And `t <- (l, s)` then says it must be in one of the two groups -- which the
first two facts have just ruled out.  `all_false` closes it. -/
theorem t_false : Forced accountId G t false := by
  refine .all_false (c := cSplit) (by simp [G]) (by decide) ?_
  intro v hv
  have : v = lv ∨ v = sv := by
    simpa [cSplit] using hv
  rcases this with rfl | rfl
  · exact l_false
  · exact s_false

/-- **The rule refutes it**, at the single label `accountId`. -/
theorem refuted : Refuted G := ⟨accountId, t, t_true, t_false⟩

/-- **And it really is unsatisfiable** -- so the refutation is not a false alarm.
This is `refuted_unsat` applied to the derivation above; it is the statement the
shipped compiler gets wrong. -/
theorem unsat : ¬ ∃ rho, Models rho G := refuted_unsat refuted

end Unsound01

/-! ### The sibling that must keep working

The same helper applied to a ledger WITHOUT the key is satisfiable, and the rule
leaves it alone.  We exhibit a model; `not_refuted_of_sat` does the rest.  This is
the formal counterpart of the `CONTROL good` row in `DisjProbe`, and of the fact
that a general helper signature -- which has no concrete instance at all -- is
untouched by a check that ranges only over labels of concrete rows. -/
namespace Good

open Unsound01 (t lv sv lt rt accountId regionCode)

def amount : Label := 2

/-- `t <- (|regionCode, amount|)`: this ledger does not carry the key. -/
def cPin : Constraint := ⟨t, [], {regionCode, amount}⟩

def G : List Constraint := [Unsound01.cSplit, Unsound01.cLeft, Unsound01.cRight, cPin]

/-- The witness: split the ledger as `l = {regionCode}`, `s = {amount}`, and let the
two shard headers carry the key alongside. -/
def rho : Assign := fun v =>
  if v = t then {regionCode, amount}
  else if v = lv then {regionCode}
  else if v = sv then {amount}
  else if v = lt then {accountId, regionCode}
  else if v = rt then {accountId, amount}
  else ∅

theorem models : Models rho G := by
  intro c hc
  have : c = Unsound01.cSplit ∨ c = Unsound01.cLeft ∨ c = Unsound01.cRight ∨ c = cPin := by
    simpa [G] using hc
  rcases this with rfl | rfl | rfl | rfl
  · exact ⟨by decide, by decide⟩
  · exact ⟨by decide, by decide⟩
  · exact ⟨by decide, by decide⟩
  · exact ⟨by decide, by decide⟩

/-- **The rule keeps it.**  A satisfiable system is never refuted, so the helper
remains usable exactly where it was usable before. -/
theorem not_refuted : ¬ Refuted G := not_refuted_of_sat ⟨rho, models⟩

end Good

/-! ## 6. The rule is incomplete, on purpose

Propagation never splits on an unknown bit, so it decides only what is forced.  Here
is an unsatisfiable system it does NOT refute, and the incompleteness is proved, not
asserted: the derivable facts are characterised exactly, and the clash is not among
them.

    a <- (b, c)          -- the label sits in exactly one of b, c
    x <- (b)             -- x is b
    x <- (c)             -- x is c, hence b and c agree at every label
    a <- (|0|)           -- and a carries the label

`b` and `c` agree because both equal `x`, so they cannot split a label between them;
but seeing that needs a case split on which of them carries it, and propagation does
not case split.  Deciding this class in general is Schaefer's one-in-three problem
(ticket §1), so no polynomial propagation can be complete unless P = NP.  The check
is deliberately the cheap half. -/
namespace Incomplete

def a : Var := 0
def b : Var := 1
def cv : Var := 2
def x : Var := 3

def cA : Constraint := ⟨a, [b, cv], ∅⟩
def cX1 : Constraint := ⟨x, [b], ∅⟩
def cX2 : Constraint := ⟨x, [cv], ∅⟩
def cPin : Constraint := ⟨a, [], {0}⟩

def G : List Constraint := [cA, cX1, cX2, cPin]

/-- **It has no model.**  `x` forces `b` and `c` to agree at label 0, while
`a <- (b, c)` with `a` carrying the label forces them to differ. -/
theorem unsat : ¬ ∃ rho, Models rho G := by
  rintro ⟨rho, hm⟩
  have hb : BModels (proj rho 0) 0 G := (models_iff_forall_label rho G).mp hm 0
  have hA := hb cA (by simp [G])
  have hX1 := hb cX1 (by simp [G])
  have hX2 := hb cX2 (by simp [G])
  have hPin := hb cPin (by simp [G])
  -- a carries the label
  have ha : proj rho 0 a = true := (bsat_lhs hPin).mpr (Or.inl (by decide))
  -- so one of b, c does
  rcases (bsat_lhs hA).mp ha with h | ⟨w, hw, hbw⟩
  · exact absurd h (by decide)
  · -- b and c agree, because each equals x
    have hbx : proj rho 0 b = proj rho 0 x := by
      have h1 : proj rho 0 x = true ↔ (0 ∈ cX1.conc ∨ ∃ v ∈ cX1.vars, proj rho 0 v = true) :=
        bsat_lhs hX1
      simp only [cX1] at h1
      cases hbb : proj rho 0 b
      · cases hxx : proj rho 0 x
        · rfl
        · rcases h1.mp hxx with h' | ⟨v, hv, hv'⟩
          · exact absurd h' (by decide)
          · have : v = b := by simpa using hv
            subst this; rw [hbb] at hv'; exact Bool.noConfusion hv'
      · rw [h1.mpr (Or.inr ⟨b, by simp, hbb⟩)]
    have hcx : proj rho 0 cv = proj rho 0 x := by
      have h1 : proj rho 0 x = true ↔ (0 ∈ cX2.conc ∨ ∃ v ∈ cX2.vars, proj rho 0 v = true) :=
        bsat_lhs hX2
      simp only [cX2] at h1
      cases hcc : proj rho 0 cv
      · cases hxx : proj rho 0 x
        · rfl
        · rcases h1.mp hxx with h' | ⟨v, hv, hv'⟩
          · exact absurd h' (by decide)
          · have : v = cv := by simpa using hv
            subst this; rw [hcc] at hv'; exact Bool.noConfusion hv'
      · rw [h1.mpr (Or.inr ⟨cv, by simp, hcc⟩)]
    have hbc : proj rho 0 b = proj rho 0 cv := by rw [hbx, hcx]
    -- but a <- (b, c) makes them exclusive, and one of them is true
    have hwbc : w = b ∨ w = cv := by simpa [cA] using hw
    have hboth : proj rho 0 b = true ∧ proj rho 0 cv = true := by
      rcases hwbc with rfl | rfl
      · exact ⟨hbw, hbc ▸ hbw⟩
      · exact ⟨hbc ▸ hbw, hbw⟩
    have := bsat_var_var hA (v := b) (w := cv) (by simp [cA]) (by simp [cA])
      (by decide) hboth.1
    rw [hboth.2] at this; exact Bool.noConfusion this

/-- The only fact propagation can derive here is that `a` carries the label.
Proved by induction on the derivation: every other constructor needs a premise
that is not derivable. -/
theorem forced_char {v : Var} {y : Bool} (h : Forced 0 G v y) : v = a ∧ y = true := by
  induction h with
  | @conc_lhs c hc hl =>
      have : c = cA ∨ c = cX1 ∨ c = cX2 ∨ c = cPin := by simpa [G] using hc
      rcases this with rfl | rfl | rfl | rfl
      · exact absurd hl (by decide)
      · exact absurd hl (by decide)
      · exact absurd hl (by decide)
      · exact ⟨rfl, rfl⟩
  | @conc_var c v hc hl hv =>
      have : c = cA ∨ c = cX1 ∨ c = cX2 ∨ c = cPin := by simpa [G] using hc
      rcases this with rfl | rfl | rfl | rfl
      · exact absurd hl (by decide)
      · exact absurd hl (by decide)
      · exact absurd hl (by decide)
      · exact absurd hv (by simp [cPin])
  | @var_lhs c v hc hv _ ih =>
      exfalso
      have hva : v = a := ih.1
      subst hva
      have : c = cA ∨ c = cX1 ∨ c = cX2 ∨ c = cPin := by simpa [G] using hc
      rcases this with rfl | rfl | rfl | rfl <;> revert hv <;> decide
  | @var_other c v w hc hv hw hne _ ih =>
      exfalso
      have hva : v = a := ih.1
      subst hva
      have : c = cA ∨ c = cX1 ∨ c = cX2 ∨ c = cPin := by simpa [G] using hc
      rcases this with rfl | rfl | rfl | rfl <;> revert hv <;> decide
  | @lhs_false c v hc hv _ ih =>
      exact absurd ih.2 (by decide)
  | @all_false c hc hl _ ih =>
      exfalso
      have : c = cA ∨ c = cX1 ∨ c = cX2 ∨ c = cPin := by simpa [G] using hc
      rcases this with rfl | rfl | rfl | rfl
      · exact absurd (ih b (by simp [cA])).2 (by decide)
      · exact absurd (ih b (by simp [cX1])).2 (by decide)
      · exact absurd (ih cv (by simp [cX2])).2 (by decide)
      · exact absurd hl (by decide)
  | @last_one c v₀ hc hl hv _ _ ihlhs ih =>
      exfalso
      have hlhsa : c.lhs = a := ihlhs.1
      have : c = cA ∨ c = cX1 ∨ c = cX2 ∨ c = cPin := by simpa [G] using hc
      rcases this with rfl | rfl | rfl | rfl
      · -- c = cA: vars are [b, cv]; whichever is v₀, the other is forced false
        have hv' : v₀ = b ∨ v₀ = cv := by simpa [cA] using hv
        rcases hv' with rfl | rfl
        · exact absurd (ih cv (by simp [cA]) (by decide)).2 (by decide)
        · exact absurd (ih b (by simp [cA]) (by decide)).2 (by decide)
      · exact absurd hlhsa (by decide)
      · exact absurd hlhsa (by decide)
      · exact absurd hl (by decide)

/-- At any label but `0` no constraint has a concrete part to seed a positive fact,
so every derivable bit is `false` -- and in particular nothing is forced both ways. -/
theorem forced_false_of_ne {l : Label} (hl : l ≠ 0) {v : Var} {y : Bool}
    (h : Forced l G v y) : y = false := by
  induction h with
  | @conc_lhs c hc hcl =>
      exfalso
      have : c = cA ∨ c = cX1 ∨ c = cX2 ∨ c = cPin := by simpa [G] using hc
      rcases this with rfl | rfl | rfl | rfl
      · simp [cA] at hcl
      · simp [cX1] at hcl
      · simp [cX2] at hcl
      · exact hl (by simpa [cPin] using hcl)
  | @conc_var c v hc hcl hv => rfl
  | @var_lhs c v hc hv _ ih => exact ih
  | @var_other c v w hc hv hw hne _ ih => rfl
  | @lhs_false c v hc hv _ ih => rfl
  | @all_false c hc hcl _ ih => rfl
  | @last_one c v₀ hc hcl hv _ _ ihlhs ih => exact ihlhs

/-- **Propagation does not refute it**, though it is unsatisfiable: the rule is
incomplete, by design, and this is the shape of what it misses. -/
theorem not_refuted : ¬ Refuted G := by
  rintro ⟨l, v, ht, hf⟩
  by_cases hl : l = 0
  · subst hl; exact Bool.noConfusion (forced_char hf).2
  · exact Bool.noConfusion (forced_false_of_ne hl ht)

/-- The pair of facts, side by side: unsatisfiable, and not refuted. -/
theorem unsat_and_not_refuted : (¬ ∃ rho, Models rho G) ∧ ¬ Refuted G :=
  ⟨unsat, not_refuted⟩

end Incomplete

end Rowpartition
