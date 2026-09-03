/-
# DefaultDiverge -- the label check does NOT catch every divergent seed of the shipped rules

`ResGuardDiverge.lean` closes with the sentence "guarded resolution and the label check are
complementary defences": the guard bounds the search on satisfiable systems
(`ResGuardTerm`), and the per-label unit propagation of `LabelProp` refutes the unsatisfiable
seed `gSeed` on which the guard diverges.  Four documents downstream repeat that sentence as
if it were a theorem.  The theorem they would need is

  (C-rule)  `∀ G₀, Diverges G₀ → Refuted G₀.toList`

where `Diverges G₀` says the SHIPPED rule set -- `Rowpartition.DefaultStep`, the additive
calculus `NonGenStep` + `splitConcrete`'s mint + GUARDED resolution, i.e.
`ermine.genRules=cut` with `ermine.resGuard=true` -- admits, from `G₀`, chains of EVERY
length that grow the working set by one constraint per step.  What `ResGuardDiverge` proves
is only that `gSeed` in particular is refuted.  This file proves that (C-rule) is FALSE
(`not_CRule`), with an explicit eight-constraint witness `CRule.W` that is unsatisfiable,
divergent under the shipped rules, and not refuted by the label check on its input
(`CRule.W_witness`).

## Why the gadget must be hidden

Every constraint of `gSeed` has a SINGLE variable part, `v <- (x, (|k|))`.  At a label `l`
such a constraint is either a pin (`l ∈ k`: `v` carries `l`, `x` does not) or an equation
(`l ∉ k`: `v` and `x` carry `l` together or not at all).  Unit propagation is complete for
pins and equations -- it is union-find -- so no system of single-variable constraints can be
unsatisfiable and escape the check.  (This remark is context, not a theorem of this file.)
A witness therefore needs a constraint with two or more variable parts that the rules can
UNFOLD into a gadget edge but that propagation cannot SEE THROUGH.

## The hiding triple

The edge `a <- (q, (|2|))` is replaced by three constraints on a fresh `w2`, with a slack
variable `s2` and the pair `q <- (q1, q2)`:

    w2 <- (a, s2)                    top2
    w2 <- (q1, q2, s2, (|2|))        bot2
    q  <- (q1, q2)                   nameQ

Semantically `a = q ⊔ (|2|)`, exactly the hidden edge.  But propagation is blind to it in
BOTH polarities at every label `l ≠ 2`: from `a` carrying `l` it learns `w2` does and `s2`
does not, and then `bot2` leaves TWO candidates `q1, q2`, so `last_one` never fires and `q`
is never reached; from `a` NOT carrying `l` it learns nothing about `w2` at all, because the
slack `s2` may carry it.  Symmetrically from `q` (its lhs, `nameQ`, has two parts; its
negation reaches `q1, q2` but `bot2` still has the unknown `s2`).  The proof is the closure
tables `F₁ .. F₄` of §4: each is closed under the seven propagation rules and clash-free.

## The four-step derivation

The rules are not blind.  `commonSubexpression`'s FOLD branch (`Cut.CutStep.fold`) folds
`nameQ` into `bot2`, giving `w2 <- (q, s2, (|2|))`; cancellation (`CancelStep`) of `top2`
against it gives back the edge `a <- (q, (|2|))`.  The same two steps on the mirror triple
give `b <- (p, (|3|))`.  With the two plain edges `a <- (p, (|1|))` and `b <- (q, (|4|))`
that is `ResGuardDiverge`'s gadget `GInv` on `(a, b, p, q)`, and `GInv.diverges_exact` (§5,
the exact-length strengthening of `GInv.diverges`) runs it forever.  So `Diverges W`, while
`¬ Refuted W.toList`.  The derived system `G₄` IS refuted (`G₄_refuted`): the label check
would catch this on the saturated set, which the shipped `Subst.solve` does not consult.

## SCOPE

This refutes (C-rule) over the ADDITIVE rule set `DefaultStep`: from `W` the shipped rules
CAN take a chain of every length.  It does NOT show that `incorporateAll` hangs on `W`: the
loop takes only some of the available steps, in a queue order this model does not fix, and
whether it takes these is answered by measurement (`tracker/repro/crule`), not here.
-/
import Rowpartition.ResGuardDiverge
import Rowpartition.SplitNecessary
import Rowpartition.NameLoss

namespace Rowpartition

/-! ## 1. The shipped rule set as a step relation -/

/-- **The shipped default** -- `ermine.genRules=cut` together with `ermine.resGuard=true`:
every non-generative rule (`NonGenStep`: CSE reuse and fold, `splitConcrete`'s reuse
branch, cancellation, substitution, self-substitution, common partition), plus
`splitConcrete`'s MINT branch (`SplitStep`), plus GUARDED resolution (`GResStep`, both its
`mint` and its `reuse` branch).  This is `SplitNecessary.CutRuleStep` with the unguarded
`ResStep` replaced by the guarded rule.

It is the ADDITIVE rule set -- the relation "one rule can fire on `G` and add its
conclusions" -- and NOT the single-pass `incorporateAll` loop, which examines each partition
once at dequeue and takes only some of the steps this relation admits. -/
inductive DefaultStep : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → DefaultStep G G'
  | mint {G G' : System} : SplitStep G G' → DefaultStep G G'
  | gres {G G' : System} : GResStep G G' → DefaultStep G G'

theorem DefaultStep.subset {G G' : System} (h : DefaultStep G G') : G ⊆ G' := by
  cases h with
  | nongen h => exact h.subset
  | mint h => exact h.subset
  | gres h => exact h.subset

/-- Every shipped rule preserves satisfiability in both directions. -/
theorem DefaultStep.satisfiable_iff {G G' : System} (h : DefaultStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | nongen h => exact exists_congr h.models_iff
  | mint h => exact h.satisfiable_iff
  | gres h => exact h.satisfiable_iff.symm

/-- `DefaultSteps n G G'`: `G'` is reachable from `G` by exactly `n` shipped-rule steps. -/
inductive DefaultSteps : ℕ → System → System → Prop
  | refl (G : System) : DefaultSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      DefaultSteps n G G' → DefaultStep G' G'' → DefaultSteps (n + 1) G G''

theorem DefaultSteps.subset {n : ℕ} {G G' : System} (h : DefaultSteps n G G') : G ⊆ G' := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep ih => exact ih.trans hstep.subset

theorem DefaultSteps.satisfiable_iff {n : ℕ} {G₀ G : System} (h : DefaultSteps n G₀ G) :
    (∃ rho, SModels rho G₀) ↔ (∃ rho, SModels rho G) := by
  induction h with
  | refl => exact Iff.rfl
  | tail _ hstep ih => exact ih.trans hstep.satisfiable_iff

theorem DefaultSteps.trans {m n : ℕ} {G G' G'' : System} (h₁ : DefaultSteps m G G')
    (h₂ : DefaultSteps n G' G'') : DefaultSteps (m + n) G G'' := by
  induction h₂ with
  | refl => exact h₁
  | @tail k Ga Gb Gc _ hstep ih => exact DefaultSteps.tail (ih h₁) hstep

/-- Every guarded-resolution run is a run of the shipped rules. -/
theorem DefaultSteps.of_gres {n : ℕ} {G G' : System} (h : GResSteps n G G') :
    DefaultSteps n G G' := by
  induction h with
  | refl G => exact DefaultSteps.refl G
  | tail _ hstep ih => exact DefaultSteps.tail ih (DefaultStep.gres hstep)

/-! ## 2. The claim -/

/-- The shipped rules admit chains of every length from `G₀`, each growing the working set
by (at least) one constraint per step. -/
def Diverges (G₀ : System) : Prop :=
  ∀ n, ∃ G, DefaultSteps n G₀ G ∧ G₀.card + n ≤ G.card

/-- **(C-rule)**: every divergent seed is refuted by the per-label check on its input.  This
is the statement the "complementary defences" gloss needs, and it is false (`not_CRule`). -/
def CRule : Prop := ∀ G₀ : System, Diverges G₀ → Refuted G₀.toList

/-! ## 3. A generic closure argument for `LabelProp.Forced`

`Forced l G.toList v x` is the least relation closed under seven rules.  Any table `F` of
`(variable, bit)` pairs closed under the same seven rules therefore contains every forced
pair; if the table is clash-free, nothing is forced both ways. -/

/-- `F` is closed under the seven propagation rules of `LabelProp.Forced` at label `l` over
the system `G`.  The fields mirror the constructors one for one, with the variable list
`c.vars` replaced by its finset `vset c`. -/
structure ForcedClosed (l : Label) (G : System) (F : Finset (Var × Bool)) : Prop where
  conc_lhs : ∀ c ∈ G, l ∈ c.conc → (c.lhs, true) ∈ F
  conc_var : ∀ c ∈ G, l ∈ c.conc → ∀ v ∈ vset c, (v, false) ∈ F
  var_lhs : ∀ c ∈ G, ∀ v ∈ vset c, (v, true) ∈ F → (c.lhs, true) ∈ F
  var_other : ∀ c ∈ G, ∀ v ∈ vset c, ∀ w ∈ vset c, v ≠ w → (v, true) ∈ F → (w, false) ∈ F
  lhs_false : ∀ c ∈ G, (c.lhs, false) ∈ F → ∀ v ∈ vset c, (v, false) ∈ F
  all_false : ∀ c ∈ G, l ∉ c.conc → (∀ v ∈ vset c, (v, false) ∈ F) → (c.lhs, false) ∈ F
  last_one : ∀ c ∈ G, l ∉ c.conc → ∀ v₀ ∈ vset c, (c.lhs, true) ∈ F →
    (∀ w ∈ vset c, w ≠ v₀ → (w, false) ∈ F) → (v₀, true) ∈ F

theorem mem_vset_iff {c : Constraint} {v : Var} : v ∈ vset c ↔ v ∈ c.vars :=
  List.mem_toFinset

/-- **Every forced pair is in every closed table.**  Induction on the derivation. -/
theorem forced_of_forcedClosed {l : Label} {G : System} {F : Finset (Var × Bool)}
    (h : ForcedClosed l G F) {v : Var} {x : Bool} (hf : Forced l G.toList v x) :
    (v, x) ∈ F := by
  induction hf with
  | @conc_lhs c hc hl =>
      exact h.conc_lhs c (Finset.mem_toList.mp hc) hl
  | @conc_var c v hc hl hv =>
      exact h.conc_var c (Finset.mem_toList.mp hc) hl v (mem_vset_iff.mpr hv)
  | @var_lhs c v hc hv _ ih =>
      exact h.var_lhs c (Finset.mem_toList.mp hc) v (mem_vset_iff.mpr hv) ih
  | @var_other c v w hc hv hw hne _ ih =>
      exact h.var_other c (Finset.mem_toList.mp hc) v (mem_vset_iff.mpr hv) w
        (mem_vset_iff.mpr hw) hne ih
  | @lhs_false c v hc hv _ ih =>
      exact h.lhs_false c (Finset.mem_toList.mp hc) ih v (mem_vset_iff.mpr hv)
  | @all_false c hc hl _ ih =>
      exact h.all_false c (Finset.mem_toList.mp hc) hl
        (fun v hv => ih v (mem_vset_iff.mp hv))
  | @last_one c v₀ hc hl hv _ _ ihlhs ih =>
      exact h.last_one c (Finset.mem_toList.mp hc) hl v₀ (mem_vset_iff.mpr hv) ihlhs
        (fun w hw hne => ih w (mem_vset_iff.mp hw) hne)

/-- A clash-free closed table means the label check cannot fire at that label. -/
theorem not_refutedAt_of_forcedClosed {l : Label} {G : System} {F : Finset (Var × Bool)}
    (h : ForcedClosed l G F) (hF : ∀ pr ∈ F, (pr.1, !pr.2) ∉ F) :
    ¬ RefutedAt l G.toList := by
  rintro ⟨v, ht, hf⟩
  exact hF (v, true) (forced_of_forcedClosed h ht) (forced_of_forcedClosed h hf)

/-- At a label no concrete part carries, the all-false assignment is a Boolean model, so
nothing is forced `true` and the check cannot fire. -/
theorem not_refutedAt_of_no_concLabel {l : Label} {G : System} (h : ∀ c ∈ G, l ∉ c.conc) :
    ¬ RefutedAt l G.toList := by
  rintro ⟨v, ht, -⟩
  have hl : l ∉ concLabels G.toList := by
    rw [mem_concLabels]
    rintro ⟨c, hc, hlc⟩
    exact h c (Finset.mem_toList.mp hc) hlc
  have hb := bmodels_false_of_not_mem G.toList l hl
  have := forced_sound ht _ hb
  exact Bool.noConfusion this

/-! ## 4. The witness -/

namespace CRule

/-- root `a` -/
abbrev a : Var := 0
/-- root `b` -/
abbrev b : Var := 1
/-- child `p` -/
abbrev p : Var := 2
/-- child `q` -/
abbrev q : Var := 3
/-- half of `p` -/
abbrev p1 : Var := 4
/-- half of `p` -/
abbrev p2 : Var := 5
/-- half of `q` -/
abbrev q1 : Var := 6
/-- half of `q` -/
abbrev q2 : Var := 7
/-- the hiding variable of the triple for label `2` -/
abbrev w2 : Var := 8
/-- the slack of the triple for label `2` -/
abbrev s2 : Var := 9
/-- the hiding variable of the triple for label `3` -/
abbrev w3 : Var := 10
/-- the slack of the triple for label `3` -/
abbrev s3 : Var := 11

/-- `a <- (p, (|1|))` -- gadget edge, in the clear. -/
def e1 : Constraint := mk a {p} {1}
/-- `b <- (q, (|4|))` -- gadget edge, in the clear. -/
def e4 : Constraint := mk b {q} {4}
/-- `w2 <- (a, s2)` -/
def top2 : Constraint := mk w2 {a, s2} ∅
/-- `w2 <- (q1, q2, s2, (|2|))` -/
def bot2 : Constraint := mk w2 {q1, q2, s2} {2}
/-- `q <- (q1, q2)` -/
def nameQ : Constraint := mk q {q1, q2} ∅
/-- `w3 <- (b, s3)` -/
def top3 : Constraint := mk w3 {b, s3} ∅
/-- `w3 <- (p1, p2, s3, (|3|))` -/
def bot3 : Constraint := mk w3 {p1, p2, s3} {3}
/-- `p <- (p1, p2)` -/
def nameP : Constraint := mk p {p1, p2} ∅

/-- **The witness.**  Two gadget edges in the clear, two hidden behind a triple each. -/
def W : System := {e1, e4, top2, bot2, nameQ, top3, bot3, nameP}

/-- `w2 <- (q, s2, (|2|))`: the fold of `nameQ` into `bot2`. -/
def mid2 : Constraint := mk w2 {q, s2} {2}
/-- `a <- (q, (|2|))`: the hidden gadget edge, recovered by cancelling `top2` against
`mid2`. -/
def e2 : Constraint := mk a {q} {2}
/-- `w3 <- (p, s3, (|3|))`: the fold of `nameP` into `bot3`. -/
def mid3 : Constraint := mk w3 {p, s3} {3}
/-- `b <- (p, (|3|))`: the other hidden gadget edge. -/
def e3 : Constraint := mk b {p} {3}

/-- After the first fold. -/
def G₁ : System := insert mid2 W
/-- After the first cancellation. -/
def G₂ : System := insert e2 G₁
/-- After the second fold. -/
def G₃ : System := insert mid3 G₂
/-- After the second cancellation: the gadget is in the clear. -/
def G₄ : System := insert e3 G₃

/-- The closed-term recipe (cf. `NameLoss.nl_decide`): unfold the witness down to
`mk`-shaped constraints over literal finsets, split `mk = mk` into component equations, and
let `decide` settle the residual closed propositions about literal finsets of naturals. -/
macro "cr_decide" : tactic => `(tactic|
  ((try simp only [a, b, p, q, p1, p2, q1, q2, w2, s2, w3, s3, W, G₁, G₂, G₃, G₄,
      e1, e2, e3, e4, top2, bot2, nameQ, top3, bot3, nameP, mid2, mid3,
      reduce, shared, vset_mk, conc_mk, lhs_mk,
      Finset.forall_mem_insert, Finset.mem_singleton, forall_eq])
   <;> (try simp only [NameLoss.mk_eq_iff, Finset.mem_insert, Finset.mem_singleton])
   <;> decide))

/-! ### 4.1 The label check does not fire on `W` -/

/-- Closed table at label `1`. -/
def F₁ : Finset (Var × Bool) :=
  {(a, true), (p, false), (p1, false), (p2, false), (s2, false), (w2, true)}
/-- Closed table at label `2`. -/
def F₂ : Finset (Var × Bool) :=
  {(a, true), (b, false), (p, true), (q, false), (q1, false), (q2, false), (s2, false),
    (w2, true)}
/-- Closed table at label `3`. -/
def F₃ : Finset (Var × Bool) :=
  {(a, false), (b, true), (p, false), (p1, false), (p2, false), (q, true), (s3, false),
    (w3, true)}
/-- Closed table at label `4`. -/
def F₄ : Finset (Var × Bool) :=
  {(b, true), (q, false), (q1, false), (q2, false), (s3, false), (w3, true)}

/-- The closure tables are checked by normalisation: unfold the witness and the table,
split the bounded quantifiers over the eight constraints and their literal variable sets,
and let `simp` evaluate the residual literal memberships and equalities. -/
macro "cr_closed" : tactic => `(tactic|
  (simp only [F₁, F₂, F₃, F₄, a, b, p, q, p1, p2, q1, q2, w2, s2, w3, s3, W,
      e1, e4, top2, bot2, nameQ, top3, bot3, nameP, vset_mk, conc_mk, lhs_mk,
      Finset.forall_mem_insert, Finset.mem_singleton, forall_eq]
   <;> simp))

theorem closed₁ : ForcedClosed 1 W F₁ := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> cr_closed

theorem closed₂ : ForcedClosed 2 W F₂ := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> cr_closed

theorem closed₃ : ForcedClosed 3 W F₃ := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> cr_closed

theorem closed₄ : ForcedClosed 4 W F₄ := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> cr_closed

theorem clashFree₁ : ∀ pr ∈ F₁, (pr.1, !pr.2) ∉ F₁ := by simp only [F₁]; decide
theorem clashFree₂ : ∀ pr ∈ F₂, (pr.1, !pr.2) ∉ F₂ := by simp only [F₂]; decide
theorem clashFree₃ : ∀ pr ∈ F₃, (pr.1, !pr.2) ∉ F₃ := by simp only [F₃]; decide
theorem clashFree₄ : ∀ pr ∈ F₄, (pr.1, !pr.2) ∉ F₄ := by simp only [F₄]; decide

/-- Outside `{1, 2, 3, 4}` no concrete part of `W` carries the label. -/
theorem W_no_concLabel {l : Label} (h1 : l ≠ 1) (h2 : l ≠ 2) (h3 : l ≠ 3) (h4 : l ≠ 4) :
    ∀ c ∈ W, l ∉ c.conc := by
  simp only [W, e1, e4, top2, bot2, nameQ, top3, bot3, nameP, Finset.forall_mem_insert,
    Finset.mem_singleton, forall_eq, conc_mk, Finset.notMem_empty,
    not_false_eq_true, true_and, and_true]
  exact ⟨h1, h4, h2, h3⟩

/-- **The label check does not refute `W`.** -/
theorem W_not_refuted : ¬ Refuted W.toList := by
  rintro ⟨l, hl⟩
  by_cases h1 : l = 1
  · subst h1; exact not_refutedAt_of_forcedClosed closed₁ clashFree₁ hl
  by_cases h2 : l = 2
  · subst h2; exact not_refutedAt_of_forcedClosed closed₂ clashFree₂ hl
  by_cases h3 : l = 3
  · subst h3; exact not_refutedAt_of_forcedClosed closed₃ clashFree₃ hl
  by_cases h4 : l = 4
  · subst h4; exact not_refutedAt_of_forcedClosed closed₄ clashFree₄ hl
  exact not_refutedAt_of_no_concLabel (W_no_concLabel h1 h2 h3 h4) hl

/-! ### 4.2 The derivation: four shipped steps recover the gadget -/

theorem e1_mem : e1 ∈ W := by simp [W]
theorem e4_mem : e4 ∈ W := by simp [W]
theorem top2_mem : top2 ∈ W := by simp [W]
theorem bot2_mem : bot2 ∈ W := by simp [W]
theorem nameQ_mem : nameQ ∈ W := by simp [W]
theorem top3_mem : top3 ∈ W := by simp [W]
theorem bot3_mem : bot3 ∈ W := by simp [W]
theorem nameP_mem : nameP ∈ W := by simp [W]

/-- The fold of `nameQ` into `bot2` is enabled: the two share `{q1, q2}`, which is all of
`nameQ`'s right-hand side, and `nameQ` has no concrete part. -/
theorem fold2_pair : CsePair W nameQ bot2 :=
  ⟨nameQ_mem, bot2_mem, by cr_decide, by cr_decide⟩

theorem fold2_vset : vset nameQ = shared nameQ bot2 := by cr_decide

theorem reduce2_eq : reduce bot2 (shared nameQ bot2) nameQ.lhs = mid2 := by cr_decide

theorem fold2_eq : foldResult W nameQ bot2 = G₁ := by
  rw [foldResult, reduce2_eq]; rfl

/-- **Step 1** -- FOLD, a non-generative shipped rule. -/
theorem step1 : DefaultStep W G₁ :=
  fold2_eq ▸ DefaultStep.nongen (NonGenStep.cse (CutStep.fold fold2_pair fold2_vset rfl))

theorem mid2_mem₁ : mid2 ∈ G₁ := Finset.mem_insert_self _ _
theorem top2_mem₁ : top2 ∈ G₁ := Finset.mem_insert_of_mem top2_mem

/-- Cancellation of `top2` against `mid2` is enabled: same left-hand side `w2`, the empty
concrete part is below `(|2|)`, and the lone leftover of `top2` is `a`. -/
theorem cancel2_app : CancelApp G₁ top2 mid2 a :=
  ⟨top2_mem₁, mid2_mem₁, rfl, by cr_decide, by cr_decide⟩

theorem cancel2_conc : mk a (vset mid2 \ vset top2) (mid2.conc \ top2.conc) = e2 := by
  cr_decide

theorem cancel2_eq : cancelResult G₁ top2 mid2 a = G₂ := by
  rw [cancelResult, cancel2_conc]; rfl

/-- **Step 2** -- CANCEL, a non-generative shipped rule: the hidden edge `a <- (q, (|2|))`
is back. -/
theorem step2 : DefaultStep G₁ G₂ :=
  cancel2_eq ▸ DefaultStep.nongen (NonGenStep.cancel (CancelStep.intro cancel2_app))

theorem nameP_mem₂ : nameP ∈ G₂ :=
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem nameP_mem)
theorem bot3_mem₂ : bot3 ∈ G₂ :=
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem bot3_mem)

theorem fold3_pair : CsePair G₂ nameP bot3 :=
  ⟨nameP_mem₂, bot3_mem₂, by cr_decide, by cr_decide⟩

theorem fold3_vset : vset nameP = shared nameP bot3 := by cr_decide

theorem reduce3_eq : reduce bot3 (shared nameP bot3) nameP.lhs = mid3 := by cr_decide

theorem fold3_eq : foldResult G₂ nameP bot3 = G₃ := by
  rw [foldResult, reduce3_eq]; rfl

/-- **Step 3** -- FOLD on the mirror triple. -/
theorem step3 : DefaultStep G₂ G₃ :=
  fold3_eq ▸ DefaultStep.nongen (NonGenStep.cse (CutStep.fold fold3_pair fold3_vset rfl))

theorem mid3_mem₃ : mid3 ∈ G₃ := Finset.mem_insert_self _ _
theorem top3_mem₃ : top3 ∈ G₃ :=
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (Finset.mem_insert_of_mem top3_mem))

theorem cancel3_app : CancelApp G₃ top3 mid3 b :=
  ⟨top3_mem₃, mid3_mem₃, rfl, by cr_decide, by cr_decide⟩

theorem cancel3_conc : mk b (vset mid3 \ vset top3) (mid3.conc \ top3.conc) = e3 := by
  cr_decide

theorem cancel3_eq : cancelResult G₃ top3 mid3 b = G₄ := by
  rw [cancelResult, cancel3_conc]; rfl

/-- **Step 4** -- CANCEL on the mirror triple: `b <- (p, (|3|))` is back. -/
theorem step4 : DefaultStep G₃ G₄ :=
  cancel3_eq ▸ DefaultStep.nongen (NonGenStep.cancel (CancelStep.intro cancel3_app))

/-! Each step inserts a constraint that was NOT there, so the working set grows by exactly
one per step. -/

theorem mid2_notMem : mid2 ∉ W := by cr_decide
theorem e2_notMem : e2 ∉ G₁ := by cr_decide
theorem mid3_notMem : mid3 ∉ G₂ := by cr_decide
theorem e3_notMem : e3 ∉ G₃ := by cr_decide

theorem card₁ : G₁.card = W.card + 1 := Finset.card_insert_of_notMem mid2_notMem
theorem card₂ : G₂.card = W.card + 2 := by
  rw [G₂, Finset.card_insert_of_notMem e2_notMem, card₁]
theorem card₃ : G₃.card = W.card + 3 := by
  rw [G₃, Finset.card_insert_of_notMem mid3_notMem, card₂]
theorem card₄ : G₄.card = W.card + 4 := by
  rw [G₄, Finset.card_insert_of_notMem e3_notMem, card₃]

theorem W_to_G₁ : DefaultSteps 1 W G₁ ∧ W.card + 1 ≤ G₁.card :=
  ⟨(DefaultSteps.refl W).tail step1, by rw [card₁]⟩

theorem W_to_G₂ : DefaultSteps 2 W G₂ ∧ W.card + 2 ≤ G₂.card :=
  ⟨W_to_G₁.1.tail step2, by rw [card₂]⟩

theorem W_to_G₃ : DefaultSteps 3 W G₃ ∧ W.card + 3 ≤ G₃.card :=
  ⟨W_to_G₂.1.tail step3, by rw [card₃]⟩

/-- **Four shipped steps, four new constraints.** -/
theorem W_to_G₄ : DefaultSteps 4 W G₄ ∧ W.card + 4 ≤ G₄.card :=
  ⟨W_to_G₃.1.tail step4, by rw [card₄]⟩

/-- The gadget is DERIVED, not present: neither hidden edge is in the input. -/
theorem e2_notMem_W : e2 ∉ W := by cr_decide
theorem e3_notMem_W : e3 ∉ W := by cr_decide

/-! ### 4.3 The derived system is `ResGuardDiverge`'s gadget -/

theorem W_subset_G₄ : W ⊆ G₄ := W_to_G₄.1.subset

theorem e1_mem₄ : e1 ∈ G₄ := W_subset_G₄ e1_mem
theorem e4_mem₄ : e4 ∈ G₄ := W_subset_G₄ e4_mem
theorem e2_mem₄ : e2 ∈ G₄ :=
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))
theorem e3_mem₄ : e3 ∈ G₄ := Finset.mem_insert_self _ _

/-- Every constraint of `G₄` carries at most one label, so `NoTwo` holds for every
variable at once. -/
theorem G₄_noTwo (v : Var) : NoTwo G₄ v := by
  intro c hc _
  simp only [G₄, G₃, G₂, G₁, W, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    cr_decide

/-- **The derived system is a gadget** on `(a, b, p, q)` with labels `(1, 2, 3, 4)`. -/
theorem G₄_inv : GInv G₄ a b p q 1 2 3 4 :=
  ⟨e1_mem₄, e2_mem₄, e3_mem₄, e4_mem₄,
    by decide, by decide, by decide, by decide, by decide, by decide,
    by decide, by decide, by decide, by decide, by decide, by decide,
    G₄_noTwo a, G₄_noTwo b, G₄_noTwo p, G₄_noTwo q⟩

end CRule

/-! ## 5. Exact-length divergence of a gadget

`GInv.diverges` gives chains of every EVEN length.  `Diverges` quantifies over every `n`,
so the odd lengths are needed too: one more mint on the root `a` of the gadget the last
round hands back. -/

/-- **One mint.**  The first half of `GInv.round`: the guarded mint on the root `a`. -/
theorem GInv.mint_step {G : System} {a b p q : Var} {l1 l2 l3 l4 : Label}
    (h : GInv G a b p q l1 l2 l3 l4) : ∃ G', GResStep G G' ∧ G.card + 1 ≤ G'.card := by
  obtain ⟨z, hz⟩ := exists_fresh (allVars G)
  have hp₁ : ResPair G a p q ({l1} : Row) ({l2} : Row) :=
    ⟨h.e1, h.e2, sdiff_lone_ne h.l12, sdiff_lone_ne h.l12.symm⟩
  have hg₁ : ¬ Resolved G a (({l1} : Row) ∪ {l2}) := by
    rw [union_lone]
    exact not_resolved_of_noTwo h.na (two_le_card_pair h.l12)
  refine ⟨_, GResStep.mint hp₁ hg₁ hz, ?_⟩
  have := (GResStep.mint_toResStep hp₁ hz).card_lt
  omega

/-- The induction behind `GInv.diverges_exact`: `m` rounds, and the gadget handed back. -/
theorem gInv_round_aux : ∀ (m : ℕ) (G : System) (a b p q : Var) (l1 l2 l3 l4 : Label),
    GInv G a b p q l1 l2 l3 l4 →
      ∃ (G' : System) (a' b' p' q' : Var) (l1' l2' l3' l4' : Label),
        GResSteps (2 * m) G G' ∧ G.card + 2 * m ≤ G'.card ∧
          GInv G' a' b' p' q' l1' l2' l3' l4' := by
  intro m
  induction m with
  | zero =>
    intro G a b p q l1 l2 l3 l4 h
    exact ⟨G, a, b, p, q, l1, l2, l3, l4, GResSteps.refl G, by omega, h⟩
  | succ m ih =>
    intro G a b p q l1 l2 l3 l4 h
    obtain ⟨G₁, z, w, hsteps, hinv, hcard⟩ := h.round
    obtain ⟨G₂, a', b', p', q', l1', l2', l3', l4', hsteps', hcard', hinv'⟩ :=
      ih G₁ p q z w l2 l4 l1 l3 hinv
    refine ⟨G₂, a', b', p', q', l1', l2', l3', l4', ?_, by omega, hinv'⟩
    have he : 2 * (m + 1) = 2 + 2 * m := by omega
    rw [he]
    exact GResSteps.trans hsteps hsteps'

/-- **Guarded chains of EVERY length from a gadget**, each step adding a constraint. -/
theorem GInv.diverges_exact {G : System} {a b p q : Var} {l1 l2 l3 l4 : Label}
    (h : GInv G a b p q l1 l2 l3 l4) (n : ℕ) :
    ∃ G', GResSteps n G G' ∧ G.card + n ≤ G'.card := by
  obtain ⟨k, hk | hk⟩ : ∃ k, n = 2 * k ∨ n = 2 * k + 1 := ⟨n / 2, by omega⟩
  · obtain ⟨G', _, _, _, _, _, _, _, _, hsteps, hcard, -⟩ :=
      gInv_round_aux k G a b p q l1 l2 l3 l4 h
    exact ⟨G', hk ▸ hsteps, by omega⟩
  · obtain ⟨G', a', b', p', q', l1', l2', l3', l4', hsteps, hcard, hinv⟩ :=
      gInv_round_aux k G a b p q l1 l2 l3 l4 h
    obtain ⟨G'', hstep, hcard'⟩ := hinv.mint_step
    exact ⟨G'', hk ▸ GResSteps.tail hsteps hstep, by omega⟩

/-- **A gadget has no model.**  `gSeed_unsat` with the variables and labels generalised:
`l4` is in `b` by `e4`, hence in `p` by `e3` (`l4 ≠ l3`), hence in `a` by `e1`, hence in `q`
by `e2` (`l4 ≠ l2`) -- which `e4` forbids. -/
theorem GInv.unsat {G : System} {a b p q : Var} {l1 l2 l3 l4 : Label}
    (h : GInv G a b p q l1 l2 l3 l4) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  have h1 := (sat_lone_iff rho a p {l1}).mp (hm _ h.e1)
  have h2 := (sat_lone_iff rho a q {l2}).mp (hm _ h.e2)
  have h3 := (sat_lone_iff rho b p {l3}).mp (hm _ h.e3)
  have h4 := (sat_lone_iff rho b q {l4}).mp (hm _ h.e4)
  have m1 : l4 ∈ rho b := by
    rw [h4.1]; exact Finset.mem_union_left _ (Finset.mem_singleton_self l4)
  have m2 : l4 ∈ rho p := by
    rw [h3.1] at m1
    rcases Finset.mem_union.mp m1 with hh | hh
    · exact absurd (Finset.mem_singleton.mp hh) h.l34.symm
    · exact hh
  have m3 : l4 ∈ rho a := by
    rw [h1.1]; exact Finset.mem_union_right _ m2
  have m4 : l4 ∈ rho q := by
    rw [h2.1] at m3
    rcases Finset.mem_union.mp m3 with hh | hh
    · exact absurd (Finset.mem_singleton.mp hh) h.l24.symm
    · exact hh
  exact Finset.disjoint_left.mp h4.2 (Finset.mem_singleton_self l4) m4

namespace CRule

/-! ## 6. The witness diverges, is unsatisfiable, and is refuted only AFTER saturation -/

/-- **`W` diverges under the shipped rules**: four derivation steps to the gadget, then the
gadget forever. -/
theorem W_diverges : Diverges W := by
  intro n
  obtain _ | _ | _ | _ | k := n
  · exact ⟨W, DefaultSteps.refl W, le_refl _⟩
  · exact ⟨G₁, W_to_G₁.1, W_to_G₁.2⟩
  · exact ⟨G₂, W_to_G₂.1, W_to_G₂.2⟩
  · exact ⟨G₃, W_to_G₃.1, W_to_G₃.2⟩
  · obtain ⟨G', hsteps, hcard⟩ := G₄_inv.diverges_exact k
    refine ⟨G', ?_, ?_⟩
    · have := DefaultSteps.trans W_to_G₄.1 (DefaultSteps.of_gres hsteps)
      rwa [show 4 + k = k + 1 + 1 + 1 + 1 by omega] at this
    · have := W_to_G₄.2
      omega

/-- **`W` has no model.**  It reaches the gadget by satisfiability-preserving steps, and the
gadget has none. -/
theorem W_unsat : ¬ ∃ rho, SModels rho W :=
  fun hs => G₄_inv.unsat (W_to_G₄.1.satisfiable_iff.mp hs)

/-- Membership in `G₄`, as `LabelProp` wants it. -/
theorem mem_toList₄ {c : Constraint} (h : c ∈ G₄) : c ∈ G₄.toList :=
  Finset.mem_toList.mpr h

/-- `a <- (p, (|1|))` pins label `1` into `a` ... -/
theorem forced₄_a_true : Forced 1 G₄.toList a true :=
  Forced.conc_lhs (c := e1) (mem_toList₄ e1_mem₄) (by decide)

/-- ... and out of `p`. -/
theorem forced₄_p_false : Forced 1 G₄.toList p false :=
  Forced.conc_var (c := e1) (mem_toList₄ e1_mem₄) (by decide) (mem_vars_mk (by simp))

/-- `a <- (q, (|2|))` must then put it into `q`. -/
theorem forced₄_q_true : Forced 1 G₄.toList q true := by
  refine Forced.last_one (c := e2) (mem_toList₄ e2_mem₄) (by decide)
    (mem_vars_mk (by simp)) forced₄_a_true ?_
  intro w hw hne
  exact absurd (vars_mk_lone hw) hne

/-- `b <- (p, (|3|))` has no part able to carry it, so `b` does not ... -/
theorem forced₄_b_false : Forced 1 G₄.toList b false := by
  refine Forced.all_false (c := e3) (mem_toList₄ e3_mem₄) (by decide) ?_
  intro v hv
  have hv2 : v = p := vars_mk_lone hv
  subst hv2
  exact forced₄_p_false

/-- ... but `b <- (q, (|4|))` says it does. -/
theorem forced₄_b_true : Forced 1 G₄.toList b true :=
  Forced.var_lhs (c := e4) (mem_toList₄ e4_mem₄) (mem_vars_mk (by simp)) forced₄_q_true

/-- **The DERIVED system is refuted** at label `1`.  A label check on the SATURATED set
would catch `W`; the shipped `Subst.solve` runs the check on the input partitions, and
`W_not_refuted` says that is too early. -/
theorem G₄_refuted : Refuted G₄.toList := ⟨1, b, forced₄_b_true, forced₄_b_false⟩

/-! ## 7. Headline -/

/-- **`W` is the witness**: unsatisfiable, divergent under the shipped rules, and not
refuted by the per-label check on its input. -/
theorem W_witness : (¬ ∃ rho, SModels rho W) ∧ Diverges W ∧ ¬ Refuted W.toList :=
  ⟨W_unsat, W_diverges, W_not_refuted⟩

end CRule

/-- **(C-rule) is false.**  The guard and the label check are NOT complementary in the sense
the gloss needs: there is a seed on which the shipped rules diverge and the label check on
the input is silent. -/
theorem not_CRule : ¬ CRule := fun h => CRule.W_not_refuted (h CRule.W CRule.W_diverges)

end Rowpartition
