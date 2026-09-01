/-
# Label classes: why per-label reasoning does not scale with schema width

`Rowpartition.Basic` proves that row-partition satisfaction decomposes label by label
(`sat_iff_forall_label`).  Read naively that is a *decision procedure schema*: run one
Boolean problem per label.  For Ermine that reading is alarming, because a real Ermine
project binds database tables, and a table's column set is its concrete block: a single
`select` over a 500-column table puts 500 labels into the constraint system.  A procedure
that is linear in the number of labels is linear in the schema width.

Pottier's answer (LICS 2003) is *filters*: a constraint carries a whole label SET as one
annotation and the solver never enumerates its members.  This file proves the fact that
makes that sound, in Ermine's equality-only, field-type-free setting, and then counts how
many genuinely different labels a system can have.

## The observation

Look at the Boolean shadow of a constraint,

    bparts b l c = decide (l ∈ c.conc) :: c.vars.map b

The label `l` occurs exactly once, inside `decide (l ∈ c.conc)`.  The variable part
`c.vars.map b` does not mention `l` at all.  So the Boolean instance at `l` is a function
of the single bit `decide (l ∈ c.conc)` -- and, for a whole system `G`, of the bit VECTOR
`sig G l = G.map (fun c => decide (l ∈ c.conc))`, which we call the label's *signature*.

## What is proved

* **§1-2 (the core).**  `BSatBit` / `BModelsSig` are the label-free Boolean instances --
  their input is a bit vector, not a label -- and `bmodels_iff_bmodelsSig` says the
  per-label instance IS the label-free instance at the label's signature.  Hence
  `bmodels_congr` : `sig G l = sig G l' → (∀ b, BModels b l G ↔ BModels b l' G)`.
  Labels with equal signatures are interchangeable.
* **§3 (the corollaries an implementer wants).**  A `Transversal` is a set of labels
  meeting every signature class.  `satisfiable_iff_transversal` decides satisfiability by
  checking only the transversal; `entails_iff_transversal` does the same for entailment
  (with `Basic`'s satisfiability side condition, and with the transversal taken for
  `c :: G`, since the goal's own concrete block is part of the data).  For an `Abstract`
  system -- no concrete labels at all, which is what every one of the 345 residual
  constraints in the measured stdlib corpus looks like -- ONE label suffices
  (`entails_iff_abstract`) -- and that corollary needs NO side condition at all, because
  `Fragment`'s F1 supplies the satisfiability hypothesis for free.
* **§4-5 (how many classes).**  `sigs G` is the finite set of realised signatures
  (`mem_sigs_iff` : it is exactly the realised ones, neither more nor fewer), and
  `satisfiable_iff_sigs` is the literal reading of "once per distinct signature": one
  label-free Boolean solve per element of `sigs G`.  Two bounds,
  `card_sigs_le_two_pow` : `≤ 2 ^ k` with `k` the number of constraints, equivalently the
  number of concrete blocks (`card_sigs_le_two_pow_of_blocks`), and `card_sigs_le_labels`
  : `≤ L + 1` with `L` the number of labels mentioned -- the `+1` being the all-false
  class of every unmentioned label.  `card_sigs_le` takes their min; `reps` /
  `satisfiable_decided_by_reps` turn the count into an actual set of representatives and
  a decision procedure of that size.
* **§6 (the practical corollary).**  `Laminar G` says the concrete blocks are pairwise
  DISJOINT OR EQUAL -- exactly the shape produced when each block is one table's column
  set.  `card_sigs_le_blocks` : then the number of classes is at most
  (number of distinct blocks) + 1, **with no dependence on how wide the blocks are**.
  `card_sigs_le_nonempty_blocks` sharpens this to nonempty blocks.
  `transversal_of_blocks` says which labels to pick -- one column out of each table plus
  one label outside every table -- and `satisfiable_by_one_label_per_block` /
  `satisfiable_decided_by_blocks` are the decision-procedure forms.
* **§7 (a 500-column table costs the same as a 1-column table).**  `wideSchema w` is a
  three-constraint system over two tables, one of width `w` and one of width 1.
  `wideSchema_width_independent`: it mentions `w + 1` labels but realises at most `3`
  signatures, for EVERY `w`.  The naive procedure does `w + 1` Boolean solves; the
  signature procedure does `3`.
* **§8 (the bound is tight).**  `genSys k` puts `k` blocks in general position -- block
  `i` is the set of labels below `2 ^ k` whose `i`-th bit is set.  `card_sigs_genSys` :
  it realises exactly `2 ^ k` signatures, and `genSys_bounds_tight` shows the OTHER
  bound of §4 is simultaneously attained there (`genSys k` mentions `2 ^ k - 1` labels).
  So without a hypothesis on the shape of the blocks, such as `Laminar`, neither bound of
  §4 can be improved.  `genSys_not_laminar` confirms that this
  witness is outside the laminar fragment, i.e. §6 is not vacuously escaping it.
* **§9 (non-vacuity).**  Four computations by `decide`: a single block already forces two
  classes, so the `+ 1` in the laminar bound is not slack; and `wideSchema 2` really does
  realise all three of its classes.

## The engineering reading

The number of Boolean solves is the number of signature CLASSES, never the number of
labels.  Under the laminar hypothesis -- one block per table, tables disjoint -- that is
one solve per table plus one, and a table's width is invisible to the solver.  Ermine's
concrete blocks should therefore be carried as opaque `Finset`s and compared with
`= / Disjoint`, never enumerated: that is Pottier's filter discipline, and §6 is its
correctness argument in an equality-only setting.
-/
import Rowpartition.Basic
import Rowpartition.Fragment
import Mathlib.Data.Finset.Card

namespace Rowpartition

/-! ## 0. Plumbing -/

/-- Two maps that agree as lists agree pointwise on the members. -/
theorem map_eq_map_forall {α β : Type*} {f g : α → β} :
    ∀ {L : List α}, L.map f = L.map g → ∀ a ∈ L, f a = g a := by
  intro L
  induction L with
  | nil => intro _ a ha; cases ha
  | cons x L ih =>
    intro h a ha
    rw [List.map_cons, List.map_cons, List.cons.injEq] at h
    rcases List.mem_cons.mp ha with rfl | ha'
    · exact h.1
    · exact ih h.2 a ha'

/-- `Label = ℕ` is infinite, so a system's finitely many mentioned labels never exhaust
it.  This is what makes the all-false signature always realised. -/
theorem exists_unmentioned_label (s : Finset Label) : ∃ n, n ∉ s := by
  by_contra hcon
  have h : ∀ n, n ∈ s := by
    intro n
    by_contra hn
    exact hcon ⟨n, hn⟩
  have hsub : Finset.range (s.card + 1) ⊆ s := fun x _ => h x
  have hcard := Finset.card_le_card hsub
  rw [Finset.card_range] at hcard
  omega

/-! ## 1. The label-free Boolean instance

The Boolean shadow of a constraint mentions its label only through the single bit
`decide (l ∈ c.conc)`.  `BSatBit` is that shadow with the bit taken as a parameter. -/

/-- The Boolean shadow of one constraint, as a function of the concrete-membership BIT
rather than of a label. -/
def BSatBit (b : Var → Bool) (k : Bool) (c : Constraint) : Prop :=
  b c.lhs = (k :: c.vars.map b).foldr (· || ·) false ∧
    (k :: c.vars.map b).Pairwise (fun x y => ¬(x = true ∧ y = true))

/-- **The variable part is label-independent.**  `BSat` at a label is `BSatBit` at that
label's concrete-membership bit -- definitionally. -/
theorem bsat_iff_bsatBit (b : Var → Bool) (l : Label) (c : Constraint) :
    BSat b l c ↔ BSatBit b (decide (l ∈ c.conc)) c := Iff.rfl

/-- Two labels with the same bit give literally the same Boolean problem. -/
theorem bsat_congr {b : Var → Bool} {l l' : Label} {c : Constraint}
    (h : decide (l ∈ c.conc) = decide (l' ∈ c.conc)) : BSat b l c ↔ BSat b l' c := by
  rw [bsat_iff_bsatBit, bsat_iff_bsatBit, h]

/-- **The signature of a label in a system**: one bit per constraint, saying whether the
label lies in that constraint's concrete block.  This is the only thing about a label
that a row-partition system can see. -/
def sig (G : List Constraint) (l : Label) : List Bool :=
  G.map (fun c => decide (l ∈ c.conc))

@[simp] theorem sig_nil (l : Label) : sig [] l = [] := rfl

@[simp] theorem sig_cons (c : Constraint) (G : List Constraint) (l : Label) :
    sig (c :: G) l = decide (l ∈ c.conc) :: sig G l := rfl

@[simp] theorem sig_length (G : List Constraint) (l : Label) :
    (sig G l).length = G.length := List.length_map ..

/-- The Boolean system determined by a bit vector: one `BSatBit` per constraint.  Note
that no label appears -- this is the problem a solver actually has to solve. -/
def BModelsSig (b : Var → Bool) (σ : List Bool) (G : List Constraint) : Prop :=
  List.Forall₂ (fun k c => BSatBit b k c) σ G

/-- **The per-label instance is the label-free instance at the label's signature.** -/
theorem bmodels_iff_bmodelsSig (b : Var → Bool) (l : Label) (G : List Constraint) :
    BModels b l G ↔ BModelsSig b (sig G l) G := by
  rw [BModelsSig, sig, List.forall₂_map_left_iff, List.forall₂_same]
  rfl

/-! ## 2. The core lemma: equal signatures are interchangeable -/

/-- **Labels with equal signatures are interchangeable.**  This is the formal content of
Pottier's filters: a solver may handle a whole label set as one unit, because every label
in the set poses the identical Boolean problem. -/
theorem bmodels_congr {G : List Constraint} {l l' : Label} (h : sig G l = sig G l')
    (b : Var → Bool) : BModels b l G ↔ BModels b l' G := by
  have hbit : ∀ c ∈ G, decide (l ∈ c.conc) = decide (l' ∈ c.conc) := map_eq_map_forall h
  constructor
  · intro hm c hc; exact (bsat_congr (hbit c hc)).mp (hm c hc)
  · intro hm c hc; exact (bsat_congr (hbit c hc)).mpr (hm c hc)

/-- The sharper form: equal signatures transfer the whole SOLUTION SET at the label, not
merely satisfiability.  (The converse fails -- two labels can pose different but equally
unsatisfiable Boolean problems -- so signature equality is a sufficient, not a necessary,
condition for interchangeability.) -/
theorem bmodels_ext {G : List Constraint} {l l' : Label} (h : sig G l = sig G l') :
    {b | BModels b l G} = {b | BModels b l' G} := by
  ext b; exact bmodels_congr h b

/-! ## 3. Transversals: checking one label per class -/

/-- `R` meets every signature class of `G`. -/
def Transversal (G : List Constraint) (R : Finset Label) : Prop :=
  ∀ l : Label, ∃ r ∈ R, sig G r = sig G l

/-- **Satisfiability needs only one label per signature class.** -/
theorem satisfiable_iff_transversal {G : List Constraint} {R : Finset Label}
    (hR : Transversal G R) :
    (∃ rho, Models rho G) ↔ ∀ r ∈ R, ∃ b, BModels b r G := by
  rw [satisfiable_iff_forall_label]
  constructor
  · intro h r _; exact h r
  · intro h l
    obtain ⟨r, hr, hsig⟩ := hR l
    obtain ⟨b, hb⟩ := h r hr
    exact ⟨b, (bmodels_congr hsig b).mp hb⟩

/-- **Entailment needs only one label per signature class of `c :: G`.**  The goal's own
concrete block must be part of the signature: `c` can distinguish labels that `G` cannot.
The satisfiability side condition is inherited from `Basic.entails_iff_forall_label`, and
is genuinely needed there (see `Basic.Counterexample`). -/
theorem entails_iff_transversal {G : List Constraint} {c : Constraint}
    (hsat : ∃ rho, Models rho G) {R : Finset Label} (hR : Transversal (c :: G) R) :
    Entails G c ↔ ∀ r ∈ R, ∀ b, BModels b r G → BSat b r c := by
  rw [entails_iff_forall_label hsat]
  constructor
  · intro h r _ b; exact h r b
  · intro h l b hb
    obtain ⟨r, hr, hsig⟩ := hR l
    rw [sig_cons, sig_cons, List.cons.injEq] at hsig
    have hG : BModels b r G := (bmodels_congr hsig.2.symm b).mp hb
    exact (bsat_congr hsig.1).mp (h r hr b hG)

/-- An abstract system -- `Rowpartition.Abstract` of `Fragment`, i.e. no constraint
mentions a concrete label, the shape of all 345 residual constraints in the measured
stdlib corpus -- has a single signature class. -/
theorem sig_const_of_abstract {G : List Constraint} (h : Abstract G) (l l' : Label) :
    sig G l = sig G l' := by
  refine List.map_congr_left fun c hc => ?_
  rw [h c hc]
  simp

/-- Hence any single label is a transversal. -/
theorem transversal_of_abstract {G : List Constraint} (h : Abstract G) (l₀ : Label) :
    Transversal G {l₀} :=
  fun l => ⟨l₀, Finset.mem_singleton_self l₀, sig_const_of_abstract h l₀ l⟩

/-- **Entailment between abstract constraints is decided at ONE label, with no side
condition at all.**  Satisfiability of `G` -- the side condition of
`Basic.entails_iff_forall_label`, and genuinely necessary there -- is free for an
abstract system (`Fragment.satisfiable_of_abstract`), and abstractness collapses the
label axis to a point.  So `Entails G c`, on the shape every residual constraint in the
corpus actually has, is ONE Boolean implication check, whatever the schema.
(Satisfiability needs no corollary here: for an abstract system it is outright true.) -/
theorem entails_iff_abstract {G : List Constraint} {c : Constraint}
    (h : Abstract (c :: G)) (l₀ : Label) :
    Entails G c ↔ ∀ b, BModels b l₀ G → BSat b l₀ c := by
  have hG : Abstract G := fun d hd => h d (List.mem_cons_of_mem _ hd)
  rw [entails_iff_transversal (satisfiable_of_abstract hG) (transversal_of_abstract h l₀)]
  simp

/-! ## 4. Counting the classes -/

/-- The signature of an unmentioned label is all-false. -/
theorem sig_eq_replicate {G : List Constraint} {l : Label} (hl : l ∉ concLabels G) :
    sig G l = List.replicate G.length false := by
  have h : G.map (fun c => decide (l ∈ c.conc)) = G.map (fun _ => false) := by
    refine List.map_congr_left fun c hc => ?_
    have : l ∉ c.conc := fun hmem => hl (mem_concLabels.mpr ⟨c, hc, hmem⟩)
    simp [this]
  rw [sig, h, List.map_const']

/-- The finite set of signatures a system realises. -/
def sigs (G : List Constraint) : Finset (List Bool) :=
  insert (List.replicate G.length false) ((concLabels G).image (sig G))

theorem mem_sigs (G : List Constraint) (l : Label) : sig G l ∈ sigs G := by
  by_cases h : l ∈ concLabels G
  · exact Finset.mem_insert_of_mem (Finset.mem_image_of_mem _ h)
  · rw [sig_eq_replicate h]; exact Finset.mem_insert_self _ _

/-- `sigs G` is EXACTLY the set of realised signatures: nothing is counted twice and
nothing spurious is counted.  (The all-false vector is always realised, by any label the
system does not mention -- there always is one, since labels are drawn from `ℕ`.) -/
theorem mem_sigs_iff {G : List Constraint} {s : List Bool} :
    s ∈ sigs G ↔ ∃ l, sig G l = s := by
  constructor
  · intro hs
    rcases Finset.mem_insert.mp hs with rfl | hs'
    · obtain ⟨l, hl⟩ := exists_unmentioned_label (concLabels G)
      exact ⟨l, sig_eq_replicate hl⟩
    · obtain ⟨l, _, hl⟩ := Finset.mem_image.mp hs'
      exact ⟨l, hl⟩
  · rintro ⟨l, rfl⟩; exact mem_sigs G l

theorem sigs_length {G : List Constraint} {s : List Bool} (hs : s ∈ sigs G) :
    s.length = G.length := by
  obtain ⟨l, rfl⟩ := mem_sigs_iff.mp hs
  exact sig_length G l

/-- **Once per distinct signature**, literally.  Satisfiability of the whole system is
decided by solving the LABEL-FREE Boolean instance `BModelsSig` once for each realised
signature -- and `sigs G` is a `Finset`, whose cardinality is bounded below without any
reference to the number of labels. -/
theorem satisfiable_iff_sigs (G : List Constraint) :
    (∃ rho, Models rho G) ↔ ∀ σ ∈ sigs G, ∃ b, BModelsSig b σ G := by
  rw [satisfiable_iff_forall_label]
  constructor
  · intro h σ hσ
    obtain ⟨l, rfl⟩ := mem_sigs_iff.mp hσ
    obtain ⟨b, hb⟩ := h l
    exact ⟨b, (bmodels_iff_bmodelsSig b l G).mp hb⟩
  · intro h l
    obtain ⟨b, hb⟩ := h (sig G l) (mem_sigs G l)
    exact ⟨b, (bmodels_iff_bmodelsSig b l G).mpr hb⟩

/-! ### Bound 1: `2 ^ k`, where `k` is the number of constraints -/

/-- All bit vectors of a given length. -/
def bitVectors : Nat → Finset (List Bool)
  | 0 => {[]}
  | n + 1 =>
      (bitVectors n).image (fun s => false :: s) ∪ (bitVectors n).image (fun s => true :: s)

theorem mem_bitVectors : ∀ s : List Bool, s ∈ bitVectors s.length := by
  intro s
  induction s with
  | nil => simp [bitVectors]
  | cons x xs ih =>
    simp only [List.length_cons, bitVectors, Finset.mem_union]
    cases x
    · exact Or.inl (Finset.mem_image_of_mem _ ih)
    · exact Or.inr (Finset.mem_image_of_mem _ ih)

theorem card_bitVectors : ∀ n : Nat, (bitVectors n).card ≤ 2 ^ n := by
  intro n
  induction n with
  | zero => simp [bitVectors]
  | succ n ih =>
    refine le_trans (Finset.card_union_le _ _) ?_
    have h1 : ((bitVectors n).image (fun s => false :: s)).card ≤ 2 ^ n :=
      le_trans Finset.card_image_le ih
    have h2 : ((bitVectors n).image (fun s => true :: s)).card ≤ 2 ^ n :=
      le_trans Finset.card_image_le ih
    have hpow : (2 : Nat) ^ (n + 1) = 2 ^ n + 2 ^ n := by rw [Nat.pow_succ]; omega
    omega

/-- **Bound 1.**  A system of `k` constraints realises at most `2 ^ k` signatures. -/
theorem card_sigs_le_two_pow (G : List Constraint) : (sigs G).card ≤ 2 ^ G.length := by
  refine le_trans (Finset.card_le_card ?_) (card_bitVectors G.length)
  intro s hs
  have hlen := sigs_length hs
  rw [← hlen]
  exact mem_bitVectors s

/-- The same bound in the form the input data suggests: `k` is the number of concrete
blocks, i.e. the length of the block list `G.map Constraint.conc`. -/
theorem card_sigs_le_two_pow_of_blocks {G : List Constraint} {k : Nat}
    (hk : (G.map Constraint.conc).length = k) : (sigs G).card ≤ 2 ^ k := by
  rw [List.length_map] at hk
  rw [← hk]
  exact card_sigs_le_two_pow G

/-! ### Bound 2: `L + 1`, where `L` is the number of labels mentioned -/

/-- **Bound 2.**  A system mentioning `L` labels realises at most `L + 1` signatures --
the `+1` being the all-false class shared by every unmentioned label, no matter how many
of those there are. -/
theorem card_sigs_le_labels (G : List Constraint) :
    (sigs G).card ≤ (concLabels G).card + 1 :=
  le_trans (Finset.card_insert_le _ _) (Nat.add_le_add_right Finset.card_image_le 1)

/-- **Both bounds at once.**  Neither dominates the other: on `wideSchema w` (§7) the
first bound gives `8` and the second `w + 2`, while on `genSys k` (§8) the two coincide
at `2 ^ k` and are both attained (`genSys_bounds_tight`). -/
theorem card_sigs_le (G : List Constraint) :
    (sigs G).card ≤ min (2 ^ G.length) ((concLabels G).card + 1) :=
  le_min (card_sigs_le_two_pow G) (card_sigs_le_labels G)

/-! ## 5. From the count to an actual set of representatives -/

/-- A representative label for a signature. -/
noncomputable def rep (G : List Constraint) (s : List Bool) : Label :=
  open Classical in
  if h : ∃ l, sig G l = s then h.choose else 0

theorem sig_rep {G : List Constraint} {s : List Bool} (hs : s ∈ sigs G) :
    sig G (rep G s) = s := by
  have h : ∃ l, sig G l = s := mem_sigs_iff.mp hs
  rw [rep]
  classical
  rw [dif_pos h]
  exact h.choose_spec

/-- The canonical transversal: one representative per realised signature. -/
noncomputable def reps (G : List Constraint) : Finset Label := (sigs G).image (rep G)

theorem transversal_reps (G : List Constraint) : Transversal G (reps G) := by
  intro l
  refine ⟨rep G (sig G l), Finset.mem_image_of_mem _ (mem_sigs G l), ?_⟩
  exact sig_rep (mem_sigs G l)

theorem card_reps_le (G : List Constraint) : (reps G).card ≤ (sigs G).card :=
  Finset.card_image_le

/-- **The scaling theorem for satisfiability.**  There is a set of at most
`min (2 ^ k) (L + 1)` labels -- `k` constraints, `L` labels mentioned -- whose Boolean
instances decide satisfiability of the whole system. -/
theorem satisfiable_decided_by_reps (G : List Constraint) :
    (reps G).card ≤ min (2 ^ G.length) ((concLabels G).card + 1) ∧
      ((∃ rho, Models rho G) ↔ ∀ r ∈ reps G, ∃ b, BModels b r G) :=
  ⟨le_trans (card_reps_le G) (card_sigs_le G),
   satisfiable_iff_transversal (transversal_reps G)⟩

/-- **The scaling theorem for entailment.**  Same, for `Entails G c`, with the
representatives taken for `c :: G`. -/
theorem entails_decided_by_reps {G : List Constraint} {c : Constraint}
    (hsat : ∃ rho, Models rho G) :
    (reps (c :: G)).card ≤ min (2 ^ (G.length + 1)) ((concLabels (c :: G)).card + 1) ∧
      (Entails G c ↔ ∀ r ∈ reps (c :: G), ∀ b, BModels b r G → BSat b r c) := by
  refine ⟨?_, entails_iff_transversal hsat (transversal_reps (c :: G))⟩
  have h := le_trans (card_reps_le (c :: G)) (card_sigs_le (c :: G))
  simpa using h

/-! ## 6. The practical corollary: laminar blocks, width-independent cost -/

/-- The concrete blocks of a system, in order. -/
def blocks (G : List Constraint) : List Row := G.map Constraint.conc

@[simp] theorem mem_blocks {G : List Constraint} {s : Row} :
    s ∈ blocks G ↔ ∃ c ∈ G, c.conc = s := by
  simp [blocks, eq_comm]

/-- The concrete blocks are pairwise DISJOINT OR EQUAL.  This is exactly the shape a
schema produces: each block is one table's column set, two occurrences of the same table
give the same block, two different tables give disjoint blocks. -/
def Laminar (G : List Constraint) : Prop :=
  ∀ s ∈ blocks G, ∀ t ∈ blocks G, s = t ∨ Disjoint s t

/-- The signature determined by a block: which constraints carry exactly that block. -/
def bsig (G : List Constraint) (s : Row) : List Bool :=
  G.map (fun c => decide (c.conc = s))

/-- **Under laminarity a label's signature is determined by its block.**  Membership in a
block is the same as equality to that block, so the label itself drops out. -/
theorem sig_eq_bsig {G : List Constraint} (h : Laminar G) {l : Label} {s : Row}
    (hs : s ∈ blocks G) (hl : l ∈ s) : sig G l = bsig G s := by
  refine List.map_congr_left fun c hc => ?_
  have hcb : c.conc ∈ blocks G := mem_blocks.mpr ⟨c, hc, rfl⟩
  refine decide_eq_decide.mpr ⟨fun hmem => ?_, fun heq => heq ▸ hl⟩
  rcases h c.conc hcb s hs with heq | hd
  · exact heq
  · exact absurd hl (Finset.disjoint_left.mp hd hmem)

/-- **What the solver should actually do.**  On a laminar system it is enough to take
one label out of each nonempty block -- one column per table -- together with one label
outside every block.  No block is ever enumerated. -/
theorem transversal_of_blocks {G : List Constraint} (h : Laminar G) {R : Finset Label}
    (hfresh : ∃ r ∈ R, r ∉ concLabels G)
    (hpick : ∀ s ∈ blocks G, s.Nonempty → ∃ r ∈ R, r ∈ s) : Transversal G R := by
  intro l
  by_cases hl : l ∈ concLabels G
  · obtain ⟨c, hc, hlc⟩ := mem_concLabels.mp hl
    have hcb : c.conc ∈ blocks G := mem_blocks.mpr ⟨c, hc, rfl⟩
    obtain ⟨r, hr, hrc⟩ := hpick c.conc hcb ⟨l, hlc⟩
    exact ⟨r, hr, by rw [sig_eq_bsig h hcb hrc, sig_eq_bsig h hcb hlc]⟩
  · obtain ⟨r, hr, hrn⟩ := hfresh
    exact ⟨r, hr, by rw [sig_eq_replicate hrn, sig_eq_replicate hl]⟩

/-- The decision procedure that statement licenses. -/
theorem satisfiable_by_one_label_per_block {G : List Constraint} (h : Laminar G)
    {R : Finset Label} (hfresh : ∃ r ∈ R, r ∉ concLabels G)
    (hpick : ∀ s ∈ blocks G, s.Nonempty → ∃ r ∈ R, r ∈ s) :
    (∃ rho, Models rho G) ↔ ∀ r ∈ R, ∃ b, BModels b r G :=
  satisfiable_iff_transversal (transversal_of_blocks h hfresh hpick)

/-- **The practically important corollary.**  If the concrete blocks are pairwise
disjoint or equal, the number of signature classes is at most (number of DISTINCT blocks)
plus one -- with no dependence whatsoever on how many labels those blocks contain. -/
theorem card_sigs_le_blocks {G : List Constraint} (h : Laminar G) :
    (sigs G).card ≤ (blocks G).toFinset.card + 1 := by
  refine le_trans (Finset.card_insert_le _ _) (Nat.add_le_add_right ?_ 1)
  have hsub : (concLabels G).image (sig G) ⊆ (blocks G).toFinset.image (bsig G) := by
    intro s hs
    obtain ⟨l, hl, rfl⟩ := Finset.mem_image.mp hs
    obtain ⟨c, hc, hlc⟩ := mem_concLabels.mp hl
    have hcb : c.conc ∈ blocks G := mem_blocks.mpr ⟨c, hc, rfl⟩
    exact Finset.mem_image.mpr
      ⟨c.conc, List.mem_toFinset.mpr hcb, (sig_eq_bsig h hcb hlc).symm⟩
  exact le_trans (Finset.card_le_card hsub) Finset.card_image_le

/-- Sharpened: empty blocks contain no label, so they cost nothing. -/
theorem card_sigs_le_nonempty_blocks {G : List Constraint} (h : Laminar G) :
    (sigs G).card ≤ ((blocks G).toFinset.filter (fun s => s ≠ ∅)).card + 1 := by
  classical
  refine le_trans (Finset.card_insert_le _ _) (Nat.add_le_add_right ?_ 1)
  have hsub : (concLabels G).image (sig G) ⊆
      ((blocks G).toFinset.filter (fun s => s ≠ ∅)).image (bsig G) := by
    intro s hs
    obtain ⟨l, hl, rfl⟩ := Finset.mem_image.mp hs
    obtain ⟨c, hc, hlc⟩ := mem_concLabels.mp hl
    have hcb : c.conc ∈ blocks G := mem_blocks.mpr ⟨c, hc, rfl⟩
    have hne : c.conc ≠ ∅ := fun hz => by rw [hz] at hlc; exact absurd hlc (by simp)
    exact Finset.mem_image.mpr
      ⟨c.conc, Finset.mem_filter.mpr ⟨List.mem_toFinset.mpr hcb, hne⟩,
        (sig_eq_bsig h hcb hlc).symm⟩
  exact le_trans (Finset.card_le_card hsub) Finset.card_image_le

/-- **The scaling theorem for schemas.**  On a laminar system, satisfiability is decided
by one Boolean solve per distinct table, plus one -- whatever the tables' widths. -/
theorem satisfiable_decided_by_blocks {G : List Constraint} (h : Laminar G) :
    (reps G).card ≤ (blocks G).toFinset.card + 1 ∧
      ((∃ rho, Models rho G) ↔ ∀ r ∈ reps G, ∃ b, BModels b r G) :=
  ⟨le_trans (card_reps_le G) (card_sigs_le_blocks h),
   satisfiable_iff_transversal (transversal_reps G)⟩

/-! ## 7. A 500-column table costs the same as a 1-column table -/

/-- Two tables: one of width `w` (columns `0, …, w-1`) and one of width 1 (column `w`).
Three constraints, two of them over the wide table. -/
def wideSchema (w : Nat) : List Constraint :=
  [⟨0, [1], Finset.range w⟩, ⟨2, [3], {w}⟩, ⟨4, [5], Finset.range w⟩]

theorem wideSchema_blocks (w : Nat) :
    blocks (wideSchema w) = [Finset.range w, {w}, Finset.range w] := rfl

theorem wideSchema_laminar (w : Nat) : Laminar (wideSchema w) := by
  have hd : Disjoint (Finset.range w) ({w} : Finset Label) :=
    Finset.disjoint_singleton_right.mpr (by simp)
  intro s hs t ht
  rw [wideSchema_blocks] at hs ht
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hs ht
  rcases hs with rfl | rfl | rfl <;> rcases ht with rfl | rfl | rfl <;>
    first
      | exact Or.inl rfl
      | exact Or.inr hd
      | exact Or.inr hd.symm

theorem wideSchema_card_blocks (w : Nat) : (blocks (wideSchema w)).toFinset.card ≤ 2 := by
  have hsub : (blocks (wideSchema w)).toFinset ⊆ {Finset.range w, {w}} := by
    intro s hs
    rw [List.mem_toFinset, wideSchema_blocks] at hs
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hs
    rcases hs with rfl | rfl | rfl <;> simp
  refine le_trans (Finset.card_le_card hsub) ?_
  exact le_trans (Finset.card_insert_le _ _) (by simp)

/-- At most three signature classes, for every width. -/
theorem wideSchema_card_sigs (w : Nat) : (sigs (wideSchema w)).card ≤ 3 :=
  le_trans (card_sigs_le_blocks (wideSchema_laminar w))
    (by have := wideSchema_card_blocks w; omega)

theorem wideSchema_concLabels (w : Nat) :
    concLabels (wideSchema w) = Finset.range (w + 1) := by
  ext l
  rw [mem_concLabels, Finset.mem_range]
  constructor
  · rintro ⟨c, hc, hlc⟩
    simp only [wideSchema, List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl | rfl <;>
      simp only [Finset.mem_range, Finset.mem_singleton] at hlc
    · exact Nat.lt_succ_of_lt hlc
    · rw [hlc]; exact Nat.lt_succ_self w
    · exact Nat.lt_succ_of_lt hlc
  · intro hl
    rcases Nat.lt_or_ge l w with h | h
    · exact ⟨⟨0, [1], Finset.range w⟩, by simp [wideSchema], Finset.mem_range.mpr h⟩
    · have hlw : l = w := Nat.le_antisymm (Nat.lt_succ_iff.mp hl) h
      exact ⟨⟨2, [3], {w}⟩, by simp [wideSchema], Finset.mem_singleton.mpr hlw⟩

/-- **The headline.**  The system mentions `w + 1` labels but has at most `3` signature
classes -- so a naive per-label procedure does `w + 1` Boolean solves where the
signature procedure does `3`, for every width `w`.  A 500-column table costs the same as
a 1-column table. -/
theorem wideSchema_width_independent (w : Nat) :
    (concLabels (wideSchema w)).card = w + 1 ∧ (sigs (wideSchema w)).card ≤ 3 :=
  ⟨by rw [wideSchema_concLabels, Finset.card_range], wideSchema_card_sigs w⟩

/-! ## 8. The bound `2 ^ k` is tight: `k` blocks in general position -/

/-- Block `i`: the labels below `2 ^ k` whose `i`-th bit is set. -/
def genBlock (k i : Nat) : Row := (Finset.range (2 ^ k)).filter (fun l => l.testBit i)

/-- `k` constraints whose blocks are in general position. -/
def genSys (k : Nat) : List Constraint :=
  (List.range k).map (fun i => ⟨i, [], genBlock k i⟩)

@[simp] theorem genSys_length (k : Nat) : (genSys k).length = k := by simp [genSys]

theorem sig_genSys {k l : Nat} (hl : l < 2 ^ k) :
    sig (genSys k) l = (List.range k).map (fun i => l.testBit i) := by
  rw [sig, genSys, List.map_map]
  refine List.map_congr_left fun i _ => ?_
  have hiff : (l ∈ genBlock k i) ↔ (l.testBit i = true) := by
    simp [genBlock, hl]
  simp [Function.comp, hiff]

theorem sig_genSys_inj {k l l' : Nat} (hl : l < 2 ^ k) (hl' : l' < 2 ^ k)
    (h : sig (genSys k) l = sig (genSys k) l') : l = l' := by
  rw [sig_genSys hl, sig_genSys hl'] at h
  refine Nat.eq_of_testBit_eq fun i => ?_
  rcases Nat.lt_or_ge i k with hik | hik
  · exact map_eq_map_forall h i (List.mem_range.mpr hik)
  · have hp : (2 : Nat) ^ k ≤ 2 ^ i := Nat.pow_le_pow_right (by omega) hik
    rw [Nat.testBit_lt_two_pow (lt_of_lt_of_le hl hp),
      Nat.testBit_lt_two_pow (lt_of_lt_of_le hl' hp)]

/-- **Tightness.**  `k` blocks in general position realise ALL `2 ^ k` signatures, so the
bound of §4 cannot be improved without a hypothesis on the blocks. -/
theorem card_sigs_genSys (k : Nat) : (sigs (genSys k)).card = 2 ^ k := by
  refine le_antisymm ?_ ?_
  · simpa using card_sigs_le_two_pow (genSys k)
  · rw [← Finset.card_range (2 ^ k)]
    refine Finset.card_le_card_of_injOn (sig (genSys k)) (fun l _ => mem_sigs _ l) ?_
    intro l hl l' hl' h
    exact sig_genSys_inj (Finset.mem_range.mp (Finset.mem_coe.mp hl))
      (Finset.mem_range.mp (Finset.mem_coe.mp hl')) h

/-- The blocks of `genSys k` together mention every nonzero label below `2 ^ k`. -/
theorem mem_concLabels_genSys {k l : Nat} :
    l ∈ concLabels (genSys k) ↔ (l < 2 ^ k ∧ l ≠ 0) := by
  rw [mem_concLabels]
  constructor
  · rintro ⟨c, hc, hlc⟩
    rw [genSys, List.mem_map] at hc
    obtain ⟨i, _, rfl⟩ := hc
    simp only [genBlock, Finset.mem_filter, Finset.mem_range] at hlc
    refine ⟨hlc.1, ?_⟩
    rintro rfl
    rw [Nat.zero_testBit] at hlc
    exact Bool.noConfusion hlc.2
  · rintro ⟨hlt, hne⟩
    have hex : ∃ i, l.testBit i = true := by
      by_contra hcon
      refine hne (Nat.eq_of_testBit_eq fun i => ?_)
      have hb : l.testBit i = false := by
        cases h : l.testBit i
        · rfl
        · exact absurd ⟨i, h⟩ hcon
      rw [hb, Nat.zero_testBit]
    obtain ⟨i, hi⟩ := hex
    have hik : i < k := by
      by_contra hik
      have hle : k ≤ i := Nat.le_of_not_lt hik
      have hfalse : l.testBit i = false :=
        Nat.testBit_lt_two_pow (lt_of_lt_of_le hlt (Nat.pow_le_pow_right (by omega) hle))
      rw [hfalse] at hi
      exact Bool.noConfusion hi
    refine ⟨⟨i, [], genBlock k i⟩, ?_, ?_⟩
    · rw [genSys]; exact List.mem_map_of_mem (List.mem_range.mpr hik)
    · simp only [genBlock, Finset.mem_filter, Finset.mem_range]
      exact ⟨hlt, hi⟩

theorem concLabels_genSys (k : Nat) :
    concLabels (genSys k) = (Finset.range (2 ^ k)).erase 0 := by
  ext l
  rw [mem_concLabels_genSys, Finset.mem_erase, Finset.mem_range]
  exact ⟨fun h => ⟨h.2, h.1⟩, fun h => ⟨h.2, h.1⟩⟩

theorem card_concLabels_genSys (k : Nat) :
    (concLabels (genSys k)).card = 2 ^ k - 1 := by
  rw [concLabels_genSys,
    Finset.card_erase_of_mem (Finset.mem_range.mpr (Nat.two_pow_pos k)), Finset.card_range]

/-- **Neither general bound is slack.**  On `genSys k` the constraint-count bound and the
label-count bound COINCIDE at `2 ^ k`, and the true number of classes is `2 ^ k`.  So no
combination of the two bounds of §4 improves on either: only a hypothesis on the SHAPE of
the blocks, such as `Laminar`, can. -/
theorem genSys_bounds_tight (k : Nat) :
    min (2 ^ (genSys k).length) ((concLabels (genSys k)).card + 1) = 2 ^ k ∧
      (sigs (genSys k)).card = 2 ^ k := by
  have h1 : (0 : Nat) < 2 ^ k := Nat.two_pow_pos k
  refine ⟨?_, card_sigs_genSys k⟩
  rw [genSys_length, card_concLabels_genSys]
  omega

/-- The tight witness is genuinely outside the laminar fragment: blocks `0` and `1` of
`genSys 2` are neither equal nor disjoint (they share the label `3`). -/
theorem genSys_not_laminar : ¬ Laminar (genSys 2) := by
  intro h
  have h0 : genBlock 2 0 ∈ blocks (genSys 2) := by
    rw [blocks, genSys, List.map_map]; exact List.mem_map_of_mem (by decide)
  have h1 : genBlock 2 1 ∈ blocks (genSys 2) := by
    rw [blocks, genSys, List.map_map]; exact List.mem_map_of_mem (by decide)
  rcases h _ h0 _ h1 with heq | hd
  · have : (1 : Label) ∈ genBlock 2 1 := by rw [← heq]; decide
    revert this; decide
  · exact (Finset.disjoint_left.mp hd (by decide : (3 : Label) ∈ genBlock 2 0))
      (by decide : (3 : Label) ∈ genBlock 2 1)

/-! ## 9. Non-vacuity

Three computations, to certify that the counts above are real numbers and that the `+ 1`
in the laminar bound is not slack. -/

section Sanity

/-- One block already forces TWO classes: inside it and outside it.  So the `+ 1` in
`card_sigs_le_blocks` cannot be dropped. -/
example : (sigs [⟨0, [], {0}⟩]).card = 2 := by decide

/-- `(blocks G).toFinset.card = 1` for that system, so the bound `1 + 1 = 2` is attained. -/
example : (blocks [⟨0, [], ({0} : Finset Label)⟩]).toFinset.card = 1 := by decide

/-- The two-table schema really does realise all three classes, so
`wideSchema_card_sigs` is tight as well. -/
example : (sigs (wideSchema 2)).card = 3 := by decide

/-- ... while it mentions three labels.  For `w = 500` the same system mentions 501
labels and still realises 3 classes. -/
example : (concLabels (wideSchema 2)).card = 3 := by decide

end Sanity

end Rowpartition
