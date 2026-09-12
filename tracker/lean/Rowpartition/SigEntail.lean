/-
# Signature entailment: the TWO-SORTED judgement, and its per-label decision

Stage S2 of `tracker/SIG-ENTAIL-PLAN.md` (design: `tracker/loopmodel/SIG-2-DESIGN.md`).

`Subst.subsumeType` checks a body against a DECLARED signature.  The signature's own
quantified row variables are RIGID (the caller instantiates them; the compiler mints
skolems for them), while the variables the solver minted while elaborating the body are
EXISTENTIAL -- the check may choose them.  Nothing in `Rowpartition.Basic` sees that
split: `Entails` (Basic.lean:64) quantifies one `rho` over every variable at once.

This module adds the split and the judgement

    SigEntails Q W F :  for every model rho of the givens Q there is a rho' agreeing with
                        rho OFF F such that rho' models the body's wanteds W

and proves it decidable by the per-label method of `entails_iff_forall_label`
(Basic.lean:525), with the existential over `F` chosen INDEPENDENTLY AT EVERY LABEL.

The crux is that the per-label choice is legitimate: rows are arbitrary finite label sets,
so per-label choices glue into one assignment (`sigEntails_of_lsig`) -- and the gluing must
stay FINITE, which is why the witness is built on the finite `span` of the input and is
all-false outside it.  Completeness needs `Q` satisfiable, exactly as
`entails_iff_forall_label` does, and for the same reason (Basic's `Counterexample`).

Contents
* §1  vocabulary and congruence: `Sat`/`Models`/`BSat`/`BModels` only read the variables
      and the concrete-label membership they mention
* §2  the judgement: `AgreeOff`, `SigEntails`, `BSigStep`, `LSigEntails`
* §3  `sigEntails_of_lsig` (SOUND, unconditional), `lsig_of_sigEntails` (COMPLETE, `Q`
      satisfiable), `sigEntails_iff_forall_label`
* §4  finitely many label CLASSES: `lsig_iff_classes` -- the mentioned labels one by one
      plus ONE generic label for all the others
* §5  the given's existentials and the dangling `Bound` binders: universal and existential
      readings AGREE when no wanted mentions them (`sigEntails_hidden_iff`)
* §6  bucket A (`sk <- ((|K|), f)`) and its dual (`X <- ((|K|), sk)`): closed forms, and the
      refutation trick proved a correct decision for them
* §7  the DECISION PROCEDURE, executable: `sigDecide`, sound and complete
* §8  the corpus instances by `decide`: sig01, sig02 and `Keyed.softRelation` REJECTED,
      control08's `healthWith`/`healthHas`/`bumpWith`/`tagged` and `ok5` ACCEPTED
-/
import Rowpartition.Basic
import Rowpartition.Rules
import Rowpartition.Divergence

namespace Rowpartition
namespace SigEntail

/-! ## 1. Vocabulary and congruence -/

/-- Every variable a list-shaped system mentions. -/
def voc (G : List Constraint) : Finset Var :=
  (G.map (fun c => insert c.lhs (vset c))).foldr (· ∪ ·) ∅

theorem mem_voc {G : List Constraint} {v : Var} :
    v ∈ voc G ↔ ∃ c ∈ G, v = c.lhs ∨ v ∈ vset c := by
  rw [voc, mem_foldr_union]
  constructor
  · rintro ⟨s, hs, hv⟩
    obtain ⟨c, hc, rfl⟩ := List.mem_map.mp hs
    rcases Finset.mem_insert.mp hv with rfl | hv
    · exact ⟨c, hc, Or.inl rfl⟩
    · exact ⟨c, hc, Or.inr hv⟩
  · rintro ⟨c, hc, hv⟩
    refine ⟨insert c.lhs (vset c), List.mem_map.mpr ⟨c, hc, rfl⟩, ?_⟩
    rcases hv with rfl | hv
    · exact Finset.mem_insert_self _ _
    · exact Finset.mem_insert_of_mem hv

theorem mem_voc_of_mem {G : List Constraint} {c : Constraint} (hc : c ∈ G) {v : Var}
    (hv : v = c.lhs ∨ v ∈ vset c) : v ∈ voc G := mem_voc.mpr ⟨c, hc, hv⟩

theorem voc_subset_append_left (G G' : List Constraint) : voc G ⊆ voc (G ++ G') := by
  intro v hv
  obtain ⟨c, hc, hv⟩ := mem_voc.mp hv
  exact mem_voc_of_mem (by simp [hc]) hv

theorem voc_subset_append_right (G G' : List Constraint) : voc G' ⊆ voc (G ++ G') := by
  intro v hv
  obtain ⟨c, hc, hv⟩ := mem_voc.mp hv
  exact mem_voc_of_mem (by simp [hc]) hv

/-- `Models` only reads the assignment at the system's own variables. -/
theorem models_congr {G : List Constraint} {rho rho' : Assign}
    (h : ∀ v ∈ voc G, rho v = rho' v) : Models rho G ↔ Models rho' G := by
  constructor
  · intro hm c hc
    exact (sat_congr_of_agree (fun v hv => h v (mem_voc_of_mem hc hv))).mp (hm c hc)
  · intro hm c hc
    exact (sat_congr_of_agree (fun v hv => h v (mem_voc_of_mem hc hv))).mpr (hm c hc)

/-- The Boolean shadow only reads the bits of the variables the constraint mentions. -/
theorem bsat_congr {b b' : Var → Bool} {l : Label} {c : Constraint}
    (h : ∀ v, v = c.lhs ∨ v ∈ vset c → b v = b' v) : BSat b l c ↔ BSat b' l c := by
  have hp : bparts b l c = bparts b' l c := by
    simp only [bparts, List.cons.injEq, true_and]
    exact List.map_congr_left fun v hv => h v (Or.inr (List.mem_toFinset.mpr hv))
  simp only [BSat, hp, h c.lhs (Or.inl rfl)]

theorem bmodels_congr {G : List Constraint} {b b' : Var → Bool} {l : Label}
    (h : ∀ v ∈ voc G, b v = b' v) : BModels b l G ↔ BModels b' l G := by
  constructor
  · intro hm c hc
    exact (bsat_congr (fun v hv => h v (mem_voc_of_mem hc hv))).mp (hm c hc)
  · intro hm c hc
    exact (bsat_congr (fun v hv => h v (mem_voc_of_mem hc hv))).mpr (hm c hc)

/-- The Boolean shadow reads the LABEL only through the concrete parts. -/
theorem bsat_label_congr {b : Var → Bool} {l l' : Label} {c : Constraint}
    (h : l ∈ c.conc ↔ l' ∈ c.conc) : BSat b l c ↔ BSat b l' c := by
  have : bparts b l c = bparts b l' c := by
    simp only [bparts, List.cons.injEq, and_true]
    exact decide_eq_decide.mpr h
  simp only [BSat, this]

/-- Two labels are in the same CLASS for `G` when they sit in the same concrete parts. -/
def SameClass (G : List Constraint) (l l' : Label) : Prop := ∀ c ∈ G, (l ∈ c.conc ↔ l' ∈ c.conc)

theorem bmodels_class_congr {G : List Constraint} {b : Var → Bool} {l l' : Label}
    (h : SameClass G l l') : BModels b l G ↔ BModels b l' G := by
  constructor
  · intro hm c hc; exact (bsat_label_congr (h c hc)).mp (hm c hc)
  · intro hm c hc; exact (bsat_label_congr (h c hc)).mpr (hm c hc)

/-- Outside `concLabels`, every label is in the same class as every other. -/
theorem sameClass_of_not_mem {G : List Constraint} {l l' : Label}
    (hl : l ∉ concLabels G) (hl' : l' ∉ concLabels G) : SameClass G l l' := by
  intro c hc
  constructor
  · intro hm; exact absurd (mem_concLabels.mpr ⟨c, hc, hm⟩) hl
  · intro hm; exact absurd (mem_concLabels.mpr ⟨c, hc, hm⟩) hl'


/-! ## 2. The two-sorted judgement

`F` is the set of EXISTENTIAL variables: the ones the solver minted while elaborating the
body, which the check may choose.  Everything else is RIGID -- the signature's own
skolems, the witnesses of the givens' own existentials (`unbindExists` at
Subst.scala:540), and the dangling `Bound` binders `Forall.mk` dropped (Type.scala:373).
§5 shows the last two may be read either way when no wanted mentions them, which is what
the corpus does. -/

/-- `rho'` is `rho` with only the `F`-variables moved. -/
def AgreeOff (F : Finset Var) (rho rho' : Assign) : Prop := ∀ v ∉ F, rho' v = rho v

/-- **The judgement.**  Every model of the givens extends, by moving only `F`, to a model
of the body's wanteds.  Compare `ConservativeExt` (Rules.lean:412), which is this
shape for ONE minted variable and a system that KEEPS its premises. -/
def SigEntails (Q W : List Constraint) (F : Finset Var) : Prop :=
  ∀ rho, Models rho Q → ∃ rho', AgreeOff F rho rho' ∧ Models rho' W

/-- The Boolean form of `AgreeOff`, at one label. -/
def BAgreeOff (F : Finset Var) (b b' : Var → Bool) : Prop := ∀ v ∉ F, b' v = b v

/-- The per-label problem: a 2QBF over the membership bits at one label. -/
def BSigStep (Q W : List Constraint) (F : Finset Var) (l : Label) : Prop :=
  ∀ b, BModels b l Q → ∃ b', BAgreeOff F b b' ∧ BModels b' l W

/-- The per-label reading of the judgement: the 2QBF at EVERY label. -/
def LSigEntails (Q W : List Constraint) (F : Finset Var) : Prop := ∀ l, BSigStep Q W F l

/-! ## 3. The judgement decomposes per label

Soundness is unconditional and is the crux: the per-label choices for `F` are glued into
ONE row assignment.  The gluing is finite because outside `span` -- the concrete labels of
the input together with the labels the given model actually uses on the input's vocabulary
-- the all-false choice already models `W`. -/

/-- The labels that can matter to `G` under `rho`. -/
def span (G : List Constraint) (rho : Assign) : Finset Label :=
  concLabels G ∪ (voc G).biUnion rho

theorem not_mem_conc_of_not_mem_span {G : List Constraint} {rho : Assign} {l : Label}
    (h : l ∉ span G rho) {c : Constraint} (hc : c ∈ G) : l ∉ c.conc := by
  intro hm
  exact h (Finset.mem_union_left _ (mem_concLabels.mpr ⟨c, hc, hm⟩))

theorem proj_false_of_not_mem_span {G : List Constraint} {rho : Assign} {l : Label}
    (h : l ∉ span G rho) {v : Var} (hv : v ∈ voc G) : proj rho l v = false := by
  simp only [proj, decide_eq_false_iff_not]
  intro hm
  exact h (Finset.mem_union_right _ (Finset.mem_biUnion.mpr ⟨v, hv, hm⟩))

/-- **SOUNDNESS OF THE PER-LABEL PROCEDURE, and the crux of the design.**  Choosing the
`F`-variables' membership label by label is legitimate: the choices glue into one finite
row assignment, which moves only `F`.  No satisfiability hypothesis. -/
theorem sigEntails_of_lsig {Q W : List Constraint} {F : Finset Var}
    (h : LSigEntails Q W F) : SigEntails Q W F := by
  classical
  intro rho hm
  have key : ∀ l, ∃ b', BAgreeOff F (proj rho l) b' ∧ BModels b' l W := fun l =>
    h l (proj rho l) ((models_iff_forall_label rho Q).mp hm l)
  choose β hag hmod using key
  set S : Finset Label := span (Q ++ W) rho with hS
  refine ⟨fun v => if v ∈ F then S.filter (fun l => β l v = true) else rho v, ?_, ?_⟩
  · intro v hv; simp [hv]
  · rw [models_iff_forall_label]
    intro l
    by_cases hl : l ∈ S
    · -- at a label of the span, the witness IS the per-label choice
      refine (bmodels_congr (b' := β l) ?_).mpr (hmod l)
      intro v hv
      by_cases hvF : v ∈ F
      · simp only [proj, hvF, if_true, Finset.mem_filter, hl, true_and]
        rw [bool_eq_iff]
        simp
      · have : β l v = proj rho l v := hag l v hvF
        simp only [proj, hvF, if_false]
        exact this.symm
    · -- outside the span nothing is in play: the all-false assignment models `W`
      refine (bmodels_congr (b' := fun _ => false) ?_).mpr ?_
      · intro v hv
        by_cases hvF : v ∈ F
        · simp only [proj, hvF, if_true, Finset.mem_filter, hl, false_and]
          simp
        · simp only [proj, hvF, if_false]
          exact proj_false_of_not_mem_span (G := Q ++ W) hl
            (voc_subset_append_right Q W hv)
      · refine bmodels_false_of_not_mem W l ?_
        intro hmem
        obtain ⟨c, hc, hlc⟩ := mem_concLabels.mp hmem
        exact not_mem_conc_of_not_mem_span (G := Q ++ W) hl (by simp [hc]) hlc

/-- **COMPLETENESS OF THE PER-LABEL PROCEDURE**, given that the givens have a model.  The
method is `entails_iff_forall_label`'s (Basic.lean:525): splice the Boolean assignment into
a model of `Q` at the one label, apply the judgement, and project back. -/
theorem lsig_of_sigEntails {Q W : List Constraint} {F : Finset Var}
    (hsat : ∃ rho, Models rho Q) (h : SigEntails Q W F) : LSigEntails Q W F := by
  intro l b hb
  obtain ⟨rho₀, hm₀⟩ := hsat
  obtain ⟨rho, hproj, hother⟩ := exists_splice rho₀ l b
  have hmod : Models rho Q := by
    rw [models_iff_forall_label]
    intro l'
    by_cases hl' : l' = l
    · subst hl'; rw [hproj]; exact hb
    · rw [hother l' hl']
      exact (models_iff_forall_label rho₀ Q).mp hm₀ l'
  obtain ⟨rho', hag, hm'⟩ := h rho hmod
  refine ⟨proj rho' l, ?_, (models_iff_forall_label rho' W).mp hm' l⟩
  intro v hv
  have h1 : proj rho' l v = proj rho l v := by simp only [proj, hag v hv]
  rw [h1, hproj]

/-- **The decomposition.**  Given satisfiable givens, the judgement IS its per-label
reading -- which is what makes it decidable. -/
theorem sigEntails_iff_forall_label {Q W : List Constraint} {F : Finset Var}
    (hsat : ∃ rho, Models rho Q) : SigEntails Q W F ↔ LSigEntails Q W F :=
  ⟨lsig_of_sigEntails hsat, sigEntails_of_lsig⟩

/-- The satisfiability hypothesis is needed for COMPLETENESS ONLY -- exactly as in
`entails_iff_forall_label`, and for the same reason.  Basic's `Counterexample` transfers:
with `F = ∅` the judgement is entailment of a one-constraint system. -/
theorem lsig_stronger_of_unsat :
    SigEntails Counterexample.G [Counterexample.c] ∅ ∧
      ¬ LSigEntails Counterexample.G [Counterexample.c] ∅ := by
  refine ⟨?_, ?_⟩
  · intro rho hm
    exact absurd hm (Counterexample.not_models rho)
  · intro h
    obtain ⟨b', hag, hm'⟩ := h 7 (fun _ => false) Counterexample.bmodels_false
    have hb : b' = fun _ => false := by
      funext v; exact hag v (by simp)
    rw [hb] at hm'
    exact Counterexample.not_bsat (hm' _ (by simp))

/-! ## 4. Finitely many label classes

The per-label problem reads the label only through the concrete parts, so there are at
most `|concLabels (Q ++ W)| + 1` distinct problems: one per mentioned label, and ONE for
every label mentioned nowhere.  On the corpus that last class is the whole check for 293
of the 309 signatures that carry a row obligation (`SIG-2-DESIGN.md` §3). -/

theorem bsigStep_class_congr {Q W : List Constraint} {F : Finset Var} {l l' : Label}
    (h : SameClass (Q ++ W) l l') : BSigStep Q W F l ↔ BSigStep Q W F l' := by
  have hQ : SameClass Q l l' := fun c hc => h c (by simp [hc])
  have hW : SameClass W l l' := fun c hc => h c (by simp [hc])
  constructor
  · intro hstep b hb
    obtain ⟨b', hag, hm⟩ := hstep b ((bmodels_class_congr hQ).mpr hb)
    exact ⟨b', hag, (bmodels_class_congr hW).mp hm⟩
  · intro hstep b hb
    obtain ⟨b', hag, hm⟩ := hstep b ((bmodels_class_congr hQ).mp hb)
    exact ⟨b', hag, (bmodels_class_congr hW).mpr hm⟩

/-- **The classes are enough.**  Checking the mentioned labels and one label outside them
decides the per-label judgement. -/
theorem lsig_iff_classes {Q W : List Constraint} {F : Finset Var} {l₀ : Label}
    (h₀ : l₀ ∉ concLabels (Q ++ W)) :
    LSigEntails Q W F ↔
      ((∀ l ∈ concLabels (Q ++ W), BSigStep Q W F l) ∧ BSigStep Q W F l₀) := by
  constructor
  · intro h; exact ⟨fun l _ => h l, h l₀⟩
  · rintro ⟨hin, hout⟩ l
    by_cases hl : l ∈ concLabels (Q ++ W)
    · exact hin l hl
    · exact (bsigStep_class_congr (sameClass_of_not_mem h₀ hl)).mp hout

/-! ## 5. The givens' existentials, and the dangling `Bound` binders

`Subst.subsumeType` opens the signature's constraint with `unbindExists(Free, q)` (:540),
minting one `Ambiguous(Free)` variable per existential of a given -- `Has r h`, which is
`exists c. r <- (h, c)`, arrives as `r <- (h, c)` with `c` fresh.  A dangling `Bound`
binder (`Forall.mk` keeps only the binders that occur in the BODY, Type.scala:373) arrives
the same way, as a variable bound by nothing.  Are they RIGID (the caller's instance chose
them; the body must work for the witness it is handed) or may the check CHOOSE them?

This says: it does not matter, as long as no WANTED mentions them.  The two readings are
then equivalent, so the implementation may take the cheap one (rigid: just another
universally quantified variable).  The corpus never mentions one: a wanted cannot, because
both existential openings mint fresh variables at the same point (Subst.scala:540-541), so
the given's witnesses are not in the wanteds' vocabulary by construction. -/

/-- The reading in which a hidden binder `X` is CHOSEN rather than handed over. -/
def SigEntailsEx (Q W : List Constraint) (F X : Finset Var) : Prop :=
  ∀ rho, (∃ rho₀, AgreeOff X rho rho₀ ∧ Models rho₀ Q) →
    ∃ rho', AgreeOff F rho rho' ∧ Models rho' W

/-- **The hidden binders may be read either way** when no wanted mentions them. -/
theorem sigEntails_hidden_iff {Q W : List Constraint} {F X : Finset Var}
    (hX : ∀ v ∈ X, v ∉ voc W) : SigEntails Q W F ↔ SigEntailsEx Q W F X := by
  classical
  constructor
  · intro h rho ⟨rho₀, hag₀, hm₀⟩
    obtain ⟨rho'₀, hag, hm⟩ := h rho₀ hm₀
    refine ⟨fun v => if v ∈ F then rho'₀ v else rho v, ?_, ?_⟩
    · intro v hv; simp [hv]
    · refine (models_congr (rho' := rho'₀) ?_).mpr hm
      intro v hv
      by_cases hvF : v ∈ F
      · simp [hvF]
      · simp only [hvF, if_false]
        by_cases hvX : v ∈ X
        · exact absurd hv (hX v hvX)
        · exact ((hag v hvF).trans (hag₀ v hvX)).symm
  · intro h rho hm
    exact h rho ⟨rho, fun _ _ => rfl, hm⟩


/-- `upd` at the updated variable.  `Rules` gives `upd_ne`/`upd_agrees` but not this. -/
theorem upd_self (rho : Assign) (u : Var) (s : Row) : upd rho u s u = s := by simp [upd]

/-! ## 6. The two decidable shapes the plan named, and the refutation trick

Bucket A is `sk <- ((|K|), f)` with `sk` rigid and `f` the one minted remainder: what every
`!`, `cons`, `\` and `modify` generates.  Bucket E is the dual `X <- ((|K|), sk)` with `X`
minted, which is where four of the eighteen stdlib holes live.  Both have closed forms, and
both reduce to a single-label REFUTATION the solver already performs. -/

/-- A model of `Q` sends the label into the rigid row, at every label of `K`. -/
def Holds (Q : List Constraint) (v : Var) (K : Finset Label) : Prop :=
  ∀ l ∈ K, ∀ rho, Models rho Q → l ∈ rho v

/-- ... and the dual: the label is kept OUT of the rigid row. -/
def Avoids (Q : List Constraint) (v : Var) (K : Finset Label) : Prop :=
  ∀ l ∈ K, ∀ rho, Models rho Q → l ∉ rho v

/-- **Bucket A in closed form.**  `sk <- ((|K|), f)` with `f` minted is entailed exactly
when the givens put every label of `K` inside `sk`.  No satisfiability hypothesis, and no
freshness hypothesis on `f` beyond `f ≠ sk`. -/
theorem sigEntails_bucketA_iff {Q : List Constraint} {sk f : Var} {K : Finset Label}
    (hfsk : f ≠ sk) : SigEntails Q [⟨sk, [f], K⟩] {f} ↔ Holds Q sk K := by
  classical
  constructor
  · intro h l hl rho hm
    obtain ⟨rho', hag, hm'⟩ := h rho hm
    have hs : Sat rho' ⟨sk, [f], K⟩ := hm' _ (by simp)
    have := hs.conc_subset_lhs (by simpa using hl)
    have hsk : rho' sk = rho sk := hag sk (by simpa using hfsk.symm)
    rwa [hsk] at this
  · intro h rho hm
    refine ⟨upd rho f (rho sk \ K), ?_, ?_⟩
    · intro v hv; exact upd_ne rho _ (by simpa using hv)
    · intro c hc
      simp only [List.mem_singleton] at hc
      subst hc
      have hsk : upd rho f (rho sk \ K) sk = rho sk :=
        upd_ne rho _ (by simpa using hfsk.symm)
      have hf : upd rho f (rho sk \ K) f = rho sk \ K := upd_self rho f _
      rw [sat_one]
      refine ⟨?_, ?_⟩
      · rw [hsk, hf]
        ext x
        simp only [Finset.mem_union, Finset.mem_sdiff]
        constructor
        · intro hx
          by_cases hxK : x ∈ K
          · exact Or.inl hxK
          · exact Or.inr ⟨hx, hxK⟩
        · rintro (hx | ⟨hx, -⟩)
          · exact h x hx rho hm
          · exact hx
      · rw [hf]
        exact Finset.disjoint_left.mpr fun x hx hx' => (Finset.mem_sdiff.mp hx').2 hx

/-- **Bucket E in closed form**, the dual.  `X <- ((|K|), sk)` with `X` minted is entailed
exactly when the givens keep every label of `K` out of `sk`. -/
theorem sigEntails_bucketE_iff {Q : List Constraint} {sk X : Var} {K : Finset Label}
    (hXsk : X ≠ sk) : SigEntails Q [⟨X, [sk], K⟩] {X} ↔ Avoids Q sk K := by
  classical
  constructor
  · intro h l hl rho hm hmem
    obtain ⟨rho', hag, hm'⟩ := h rho hm
    have hs : Sat rho' ⟨X, [sk], K⟩ := hm' _ (by simp)
    have hd : Disjoint K (rho' sk) := hs.disjoint_conc (by simp)
    have hsk : rho' sk = rho sk := hag sk (by simpa using hXsk.symm)
    rw [hsk] at hd
    exact Finset.disjoint_left.mp hd (by simpa using hl) hmem
  · intro h rho hm
    refine ⟨upd rho X (K ∪ rho sk), ?_, ?_⟩
    · intro v hv; exact upd_ne rho _ (by simpa using hv)
    · intro c hc
      simp only [List.mem_singleton] at hc
      subst hc
      have hsk : upd rho X (K ∪ rho sk) sk = rho sk :=
        upd_ne rho _ (by simpa using hXsk.symm)
      have hX : upd rho X (K ∪ rho sk) X = K ∪ rho sk := upd_self rho X _
      rw [sat_one, hsk, hX]
      exact ⟨rfl, Finset.disjoint_left.mpr fun x hx hx' => h x hx rho hm hx'⟩

/-! ### The refutation trick

`Holds` and `Avoids` are each a single-label satisfiability question about a system the
solver can already run: add ONE constraint over a FRESH variable and ask for a refutation.
The fresh variable makes the added system a conservative extension (`ConservativeExt`,
Rules.lean:412), which is why the answer is about `Q` alone. -/

/-- `Q` forces `l` into `v` iff `Q + {z <- (v, (|l|))}` has no model, for `z` fresh. -/
theorem holds_iff_unsat {Q : List Constraint} {v z : Var} {l : Label}
    (hz : Fresh z Q) (hzv : z ≠ v) :
    (∀ rho, Models rho Q → l ∈ rho v) ↔ ¬ (∃ rho, Models rho (⟨z, [v], {l}⟩ :: Q)) := by
  classical
  constructor
  · rintro h ⟨rho, hm⟩
    have hQ : Models rho Q := fun c hc => hm c (by simp [hc])
    have hs : Sat rho ⟨z, [v], {l}⟩ := hm _ (by simp)
    have hd : Disjoint ({l} : Finset Label) (rho v) := hs.disjoint_conc (by simp)
    exact Finset.disjoint_left.mp hd (by simp) (h rho hQ)
  · intro h rho hm
    by_contra hnot
    refine h ⟨upd rho z (insert l (rho v)), ?_⟩
    rw [models_cons]
    refine ⟨?_, models_of_agree hz (upd_agrees rho z _) hm⟩
    have hv : upd rho z (insert l (rho v)) v = rho v :=
      upd_ne rho _ (by simpa using hzv.symm)
    have hzz : upd rho z (insert l (rho v)) z = insert l (rho v) := upd_self rho z _
    rw [sat_one, hv, hzz]
    refine ⟨by ext x; simp, ?_⟩
    exact Finset.disjoint_left.mpr fun x hx hx' => by
      simp only [Finset.mem_singleton] at hx; subst hx; exact hnot hx'

/-- `Q` keeps `l` out of `v` iff `Q + {v <- (z, (|l|))}` has no model, for `z` fresh. -/
theorem avoids_iff_unsat {Q : List Constraint} {v z : Var} {l : Label}
    (hz : Fresh z Q) (hzv : z ≠ v) :
    (∀ rho, Models rho Q → l ∉ rho v) ↔ ¬ (∃ rho, Models rho (⟨v, [z], {l}⟩ :: Q)) := by
  classical
  constructor
  · rintro h ⟨rho, hm⟩
    have hQ : Models rho Q := fun c hc => hm c (by simp [hc])
    have hs : Sat rho ⟨v, [z], {l}⟩ := hm _ (by simp)
    exact h rho hQ (hs.conc_subset_lhs (by simp))
  · intro h rho hm hmem
    refine h ⟨upd rho z (rho v \ {l}), ?_⟩
    rw [models_cons]
    refine ⟨?_, models_of_agree hz (upd_agrees rho z _) hm⟩
    have hv : upd rho z (rho v \ {l}) v = rho v :=
      upd_ne rho _ (by simpa using hzv.symm)
    have hzz : upd rho z (rho v \ {l}) z = rho v \ {l} := upd_self rho z _
    rw [sat_one, hv, hzz]
    refine ⟨?_, ?_⟩
    · ext x
      simp only [Finset.mem_union, Finset.mem_sdiff, Finset.mem_singleton]
      constructor
      · intro hx
        by_cases hxl : x = l
        · exact Or.inl hxl
        · exact Or.inr ⟨hx, hxl⟩
      · rintro (rfl | ⟨hx, -⟩)
        · exact hmem
        · exact hx
    · exact Finset.disjoint_left.mpr fun x hx hx' =>
        (Finset.mem_sdiff.mp hx').2 (by simpa using hx)

/-- **The refutation trick is a correct decision for bucket A.**  The plan's rule, proved:
`sk <- ((|K|), f)` is entailed iff, for every label of `K`, the system `Q` extended by one
constraint over a fresh variable is unsatisfiable. -/
theorem sigEntails_bucketA_iff_refute {Q : List Constraint} {sk f : Var} {K : Finset Label}
    (hfsk : f ≠ sk) (z : Var) (hz : Fresh z Q) (hzsk : z ≠ sk) :
    SigEntails Q [⟨sk, [f], K⟩] {f} ↔
      ∀ l ∈ K, ¬ (∃ rho, Models rho (⟨z, [sk], {l}⟩ :: Q)) := by
  rw [sigEntails_bucketA_iff hfsk]
  exact ⟨fun h l hl => (holds_iff_unsat hz hzsk).mp (fun rho hm => h l hl rho hm),
         fun h l hl => (holds_iff_unsat hz hzsk).mpr (h l hl)⟩

/-- ... and for bucket E, the dual. -/
theorem sigEntails_bucketE_iff_refute {Q : List Constraint} {sk X : Var} {K : Finset Label}
    (hXsk : X ≠ sk) (z : Var) (hz : Fresh z Q) (hzsk : z ≠ sk) :
    SigEntails Q [⟨X, [sk], K⟩] {X} ↔
      ∀ l ∈ K, ¬ (∃ rho, Models rho (⟨sk, [z], {l}⟩ :: Q)) := by
  rw [sigEntails_bucketE_iff hXsk]
  exact ⟨fun h l hl => (avoids_iff_unsat hz hzsk).mp (fun rho hm => h l hl rho hm),
         fun h l hl => (avoids_iff_unsat hz hzsk).mpr (h l hl)⟩

/-! ## 7. The decision procedure, executable

The procedure of `SIG-2-DESIGN.md` §3, spelled out as a Boolean function so that the two
halves of the correctness statement are about something that RUNS: for each label class,
enumerate the assignments over the vocabulary, and for every one that models the givens,
look for an assignment of the `F`-bits that models the wanteds.  `vs` is any list covering
the vocabulary and `ls` any list of exactly the mentioned labels; `l₀` is the generic label,
standing for every label mentioned nowhere.

The enumeration is the SPECIFICATION, not the implementation S3 should ship: 2^|vs| is
hopeless at the corpus's tail (|vars| reaches 45, `SIG-2-DESIGN.md` §3), and the shipped
form is `Constraints.decideLabel`'s propagate-then-split search under a budget.  What is
proved here is the criterion those searches have to decide. -/

instance decBSat (b : Var → Bool) (l : Label) (c : Constraint) : Decidable (BSat b l c) := by
  unfold BSat; infer_instance

/-- `BModels`, as a Boolean. -/
def bmodelsB (b : Var → Bool) (l : Label) (G : List Constraint) : Bool :=
  G.all (fun c => decide (BSat b l c))

theorem bmodelsB_iff {b : Var → Bool} {l : Label} {G : List Constraint} :
    bmodelsB b l G = true ↔ BModels b l G := by
  simp [bmodelsB, BModels, List.all_eq_true]

/-- Set one bit. -/
def bset (b : Var → Bool) (v : Var) (x : Bool) : Var → Bool := fun w => if w = v then x else b w

/-- Every Boolean assignment over a variable list. -/
def bassigns : List Var → List (Var → Bool)
  | [] => [fun _ => false]
  | v :: vs => (bassigns vs).flatMap (fun b => [bset b v true, bset b v false])

/-- The enumeration is COMPLETE on its list: every assignment is matched on `vs` by one of
its members.  (It need not be sound in any sense: extra members can only be extra work.) -/
theorem exists_bassign (vs : List Var) (b : Var → Bool) :
    ∃ b' ∈ bassigns vs, ∀ v ∈ vs, b' v = b v := by
  induction vs with
  | nil => exact ⟨fun _ => false, by simp [bassigns], by simp⟩
  | cons v vs ih =>
    obtain ⟨b', hb', hag⟩ := ih
    refine ⟨bset b' v (b v), ?_, ?_⟩
    · simp only [bassigns, List.mem_flatMap]
      refine ⟨b', hb', ?_⟩
      cases hv : b v <;> simp [hv]
    · intro w hw
      by_cases hwv : w = v
      · subst hwv; simp [bset]
      · have hws : w ∈ vs := by
          rcases List.mem_cons.mp hw with rfl | h
          · exact absurd rfl hwv
          · exact h
        simp [bset, hwv, hag w hws]

/-- The `F`-bits of `bf` over the rigid bits of `b`. -/
def overlay (Fv : List Var) (bf b : Var → Bool) : Var → Bool :=
  fun v => if v ∈ Fv then bf v else b v

/-- The 2QBF at one label, by enumeration. -/
def stepOk (Q W : List Constraint) (Fv vs : List Var) (l : Label) : Bool :=
  (bassigns vs).all fun b =>
    !bmodelsB b l Q || (bassigns Fv).any fun bf => bmodelsB (overlay Fv bf b) l W

theorem stepOk_iff {Q W : List Constraint} {Fv vs : List Var} {l : Label}
    (hvs : voc (Q ++ W) ⊆ vs.toFinset) :
    stepOk Q W Fv vs l = true ↔ BSigStep Q W Fv.toFinset l := by
  have hvQ : ∀ v ∈ voc Q, v ∈ vs := fun v hv =>
    List.mem_toFinset.mp (hvs (voc_subset_append_left Q W hv))
  have hvW : ∀ v ∈ voc W, v ∈ vs := fun v hv =>
    List.mem_toFinset.mp (hvs (voc_subset_append_right Q W hv))
  constructor
  · intro h b hb
    obtain ⟨b₀, hmem, hag⟩ := exists_bassign vs b
    have hQ0 : BModels b₀ l Q :=
      (bmodels_congr (b := b) (b' := b₀) fun v hv => (hag v (hvQ v hv)).symm).mp hb
    have h1 := List.all_eq_true.mp h b₀ hmem
    rw [bmodelsB_iff.mpr hQ0] at h1
    simp only [Bool.not_true, Bool.false_or, List.any_eq_true] at h1
    obtain ⟨bf, hbf, hW⟩ := h1
    refine ⟨overlay Fv bf b, ?_, ?_⟩
    · intro v hv
      simp only [overlay, if_neg (by simpa using hv : ¬ (v ∈ Fv))]
    · refine (bmodels_congr (b' := overlay Fv bf b₀) ?_).mpr (bmodelsB_iff.mp hW)
      intro v hv
      by_cases hvF : v ∈ Fv
      · simp [overlay, hvF]
      · simp only [overlay, if_neg hvF]
        exact (hag v (hvW v hv)).symm
  · intro h
    refine List.all_eq_true.mpr fun b₀ hmem => ?_
    by_cases hQ : bmodelsB b₀ l Q = true
    · obtain ⟨b', hagb, hW⟩ := h b₀ (bmodelsB_iff.mp hQ)
      obtain ⟨bf, hbf, hagf⟩ := exists_bassign Fv b'
      rw [hQ]
      simp only [Bool.not_true, Bool.false_or, List.any_eq_true]
      refine ⟨bf, hbf, bmodelsB_iff.mpr ?_⟩
      refine (bmodels_congr (b' := b') ?_).mpr hW
      intro v hv
      by_cases hvF : v ∈ Fv
      · simp only [overlay, if_pos hvF]
        exact hagf v hvF
      · simp only [overlay, if_neg hvF]
        exact (hagb v (by simpa using hvF)).symm
    · simp only [Bool.not_eq_true] at hQ
      simp [hQ]

/-- **The procedure.**  The mentioned labels one by one, then the generic label. -/
def sigDecide (Q W : List Constraint) (Fv vs : List Var) (ls : List Label) (l₀ : Label) : Bool :=
  (ls.all fun l => stepOk Q W Fv vs l) && stepOk Q W Fv vs l₀

/-- **The procedure decides the per-label judgement.**  `vs` covers the vocabulary, `ls` is
exactly the mentioned labels, `l₀` is any label outside them. -/
theorem sigDecide_iff {Q W : List Constraint} {Fv vs : List Var} {ls : List Label}
    {l₀ : Label} (hvs : voc (Q ++ W) ⊆ vs.toFinset)
    (hls : concLabels (Q ++ W) = ls.toFinset) (h₀ : l₀ ∉ concLabels (Q ++ W)) :
    sigDecide Q W Fv vs ls l₀ = true ↔ LSigEntails Q W Fv.toFinset := by
  have hiff : ∀ l, l ∈ concLabels (Q ++ W) ↔ l ∈ ls := by
    intro l; rw [hls]; exact List.mem_toFinset
  rw [lsig_iff_classes h₀]
  simp only [sigDecide, Bool.and_eq_true, List.all_eq_true, stepOk_iff hvs]
  constructor
  · rintro ⟨h1, h2⟩
    exact ⟨fun l hl => h1 l ((hiff l).mp hl), h2⟩
  · rintro ⟨h1, h2⟩
    exact ⟨fun l hl => h1 l ((hiff l).mpr hl), h2⟩

/-- **ACCEPTANCE IS SOUND**, with no hypothesis on the givens: what the procedure accepts
really is entailed, so no unsound signature is let through by a `true`. -/
theorem sigEntails_of_sigDecide {Q W : List Constraint} {Fv vs : List Var} {ls : List Label}
    {l₀ : Label} (hvs : voc (Q ++ W) ⊆ vs.toFinset)
    (hls : concLabels (Q ++ W) = ls.toFinset) (h₀ : l₀ ∉ concLabels (Q ++ W))
    (h : sigDecide Q W Fv vs ls l₀ = true) : SigEntails Q W Fv.toFinset :=
  sigEntails_of_lsig ((sigDecide_iff hvs hls h₀).mp h)

/-- **REJECTION IS SOUND provided the givens have a model** -- the one hypothesis the whole
design turns on, and the reason the implementation must run a satisfiability check on the
givens before it reports "not entailed". -/
theorem not_sigEntails_of_sigDecide {Q W : List Constraint} {Fv vs : List Var}
    {ls : List Label} {l₀ : Label} (hsat : ∃ rho, Models rho Q)
    (hvs : voc (Q ++ W) ⊆ vs.toFinset)
    (hls : concLabels (Q ++ W) = ls.toFinset) (h₀ : l₀ ∉ concLabels (Q ++ W))
    (h : sigDecide Q W Fv vs ls l₀ = false) : ¬ SigEntails Q W Fv.toFinset := by
  intro hsig
  have := (sigDecide_iff hvs hls h₀).mpr (lsig_of_sigEntails hsat hsig)
  rw [h] at this
  exact Bool.noConfusion this


/-! ### The derivational alternative: a UNIFORM witness

The semantic judgement lets the witness for `F` depend on the caller's instantiation.  What
a solver-based (derivational) check would establish instead is a UNIFORM witness: one row
EXPRESSION per minted variable, in the vocabulary of the givens, good for every model at
once -- which is exactly what `Constraints.incorporateAll` computes when it discharges the
body's residual.  Ermine's row expressions are a concrete label set together with a finite
set of variables (`Divergence.mk`), so a uniform witness is a map into `Finset Var × Finset
Label`.

Uniform entailment implies the judgement, so a derivational check is SOUND.  It is not
complete for it: a residual can be satisfiable at every instantiation without one
expression working everywhere (the design note's open question 3). -/

/-- The assignment a uniform witness induces. -/
def subst (F : Finset Var) (w : Var → Finset Var × Finset Label) (rho : Assign) : Assign :=
  fun v => if v ∈ F then (w v).2 ∪ (w v).1.biUnion rho else rho v

/-- Entailment WITH a uniform witness: one row expression per minted variable. -/
def UniformSigEntails (Q W : List Constraint) (F : Finset Var) : Prop :=
  ∃ w : Var → Finset Var × Finset Label, ∀ rho, Models rho Q → Models (subst F w rho) W

/-- **A uniform witness is enough**: the derivational check is sound for the judgement. -/
theorem sigEntails_of_uniform {Q W : List Constraint} {F : Finset Var}
    (h : UniformSigEntails Q W F) : SigEntails Q W F := by
  obtain ⟨w, hw⟩ := h
  intro rho hm
  refine ⟨subst F w rho, ?_, hw rho hm⟩
  intro v hv
  simp [subst, hv]

/-! ## 8. The corpus instances

The systems are the ones the S1 probe printed, with the ids replaced by small numbers and
the field names by labels: `health = 0`, `mana = 1`.  Variables: `r = 1`, the given's
remainder `t = 2` (which the probe shows as a dangling `Bound`, §5), the body's minted
remainder `f = 3`.  Each verdict is `by decide` on `sigDecide`, and the judgement follows
by §7's two soundness theorems.

Records, for the record (`tracker/loopmodel/SIG-2-DESIGN.md` §4):

    sig01  healthOpt   W: r^S <- ((|health|), _^A)   Q: (none)
    sig02  wrongLabel  W: r^S <- ((|health|), _^A)   Q: r^S <- ((|mana|), t^B)
    c08    healthWith  W: r^S <- ((|health|), _^A)   Q: r^S <- ((|health|), t^B)
    c08    tagged      W: t^S <- ((|health|), r^S)   Q: t^S <- ((|health|), r^S)
    Keyed  softRelation W: o^A <- (k^S, v^S)         Q: (two class constraints only)
    SoftRelation joinKey W: t^A <- (v,i); r <- (k,t^A)  Q: r <- (i,k,v)
-/

namespace Corpus

/-- `sig01`: `healthOpt : forall r. {..r} -> Int` with body `r ! health`. -/
def sig01Q : List Constraint := []
def sig01W : List Constraint := [⟨1, [3], {0}⟩]

theorem sig01_rejected : sigDecide sig01Q sig01W [3] [1, 3] [0] 1 = false := by decide

/-- ... and the signature really is dishonest: NO row assignment is forced to have
`health`, so the body's obligation is not entailed. -/
theorem sig01_not_entailed : ¬ SigEntails sig01Q sig01W ({3} : Finset Var) := by
  have h : ¬ SigEntails sig01Q sig01W (([3] : List Var)).toFinset :=
    not_sigEntails_of_sigDecide (Q := sig01Q) (W := sig01W)
      ⟨fun _ => ∅, Models.nil _⟩ (by decide) (by decide) (by decide) sig01_rejected
  simpa using h

/-- `sig02`: the constraint is there but on the wrong label. -/
def sig02Q : List Constraint := [⟨1, [2], {1}⟩]
def sig02W : List Constraint := [⟨1, [3], {0}⟩]

theorem sig02_rejected : sigDecide sig02Q sig02W [3] [1, 2, 3] [0, 1] 2 = false := by decide

theorem sig02_sat : ∃ rho, Models rho sig02Q := by
  refine ⟨fun v => if v = 1 then {1} else ∅, ?_⟩
  intro c hc
  simp only [sig02Q, List.mem_singleton] at hc
  subst hc
  rw [sat_one]
  refine ⟨by decide, by decide⟩

theorem sig02_not_entailed : ¬ SigEntails sig02Q sig02W ({3} : Finset Var) := by
  have h : ¬ SigEntails sig02Q sig02W (([3] : List Var)).toFinset :=
    not_sigEntails_of_sigDecide (Q := sig02Q) (W := sig02W)
      sig02_sat (by decide) (by decide) (by decide) sig02_rejected
  simpa using h

/-- `control08.healthWith` -- and, by §5, `healthHas` (whose given remainder is the
existential of `Has`) and `bumpWith` (whose wanted remainder is named `t` rather than `_`)
are the SAME system. -/
def c08Q : List Constraint := [⟨1, [2], {0}⟩]
def c08W : List Constraint := [⟨1, [3], {0}⟩]

theorem c08_accepted : sigDecide c08Q c08W [3] [1, 2, 3] [0] 1 = true := by decide

theorem c08_entailed : SigEntails c08Q c08W ({3} : Finset Var) := by
  have h : SigEntails c08Q c08W (([3] : List Var)).toFinset :=
    sigEntails_of_sigDecide (Q := c08Q) (W := c08W)
      (by decide) (by decide) (by decide) c08_accepted
  simpa using h

/-- `control08.tagged`: two rigid variables, no minted variable at all -- the wanted IS the
given, and the procedure accepts with `F = ∅`. -/
def taggedQ : List Constraint := [⟨2, [1], {0}⟩]

theorem tagged_accepted : sigDecide taggedQ taggedQ [] [1, 2] [0] 1 = true := by decide

theorem tagged_entailed : SigEntails taggedQ taggedQ (∅ : Finset Var) := by
  have h : SigEntails taggedQ taggedQ (([] : List Var)).toFinset :=
    sigEntails_of_sigDecide (Q := taggedQ) (W := taggedQ)
      (by decide) (by decide) (by decide) tagged_accepted
  simpa using h

/-- `Layout.Report.Keyed.softRelation` (S1's (c4)): the wrapper declares only two CLASS
constraints, so the row givens are EMPTY, and the body needs the key columns disjoint from
the value columns.  There is no concrete label anywhere: the GENERIC label class rejects it,
which is the 95.3% of the corpus no refutation-shaped procedure reaches. -/
def keyedQ : List Constraint := []
def keyedW : List Constraint := [⟨3, [1, 2], ∅⟩]

theorem keyed_rejected : sigDecide keyedQ keyedW [3] [1, 2, 3] [] 0 = false := by decide

theorem keyed_not_entailed : ¬ SigEntails keyedQ keyedW ({3} : Finset Var) := by
  have h : ¬ SigEntails keyedQ keyedW (([3] : List Var)).toFinset :=
    not_sigEntails_of_sigDecide (Q := keyedQ) (W := keyedW)
      ⟨fun _ => ∅, Models.nil _⟩ (by decide) (by decide) (by decide) keyed_rejected
  simpa using h

/-- `Report.SoftRelation.joinKey` (S1's (b) sample 20): `r <- (i, k, v)` given; the body
wants `t' <- (v, i)` and `r <- (k, t')` with ONE shared minted variable.  Accepted, again in
the generic label class -- and the witness must be chosen once for both wanteds. -/
def joinKeyQ : List Constraint := [⟨1, [2, 3, 4], ∅⟩]
def joinKeyW : List Constraint := [⟨5, [4, 2], ∅⟩, ⟨1, [3, 5], ∅⟩]

theorem joinKey_accepted : sigDecide joinKeyQ joinKeyW [5] [1, 2, 3, 4, 5] [] 0 = true := by
  decide

theorem joinKey_entailed : SigEntails joinKeyQ joinKeyW ({5} : Finset Var) := by
  have h : SigEntails joinKeyQ joinKeyW (([5] : List Var)).toFinset :=
    sigEntails_of_sigDecide (Q := joinKeyQ) (W := joinKeyW)
      (by decide) (by decide) (by decide) joinKey_accepted
  simpa using h

end Corpus

end SigEntail
end Rowpartition
