/-
# The reverse-lookup guard does not restore termination

`ResGuard.lean` gives `resolution` (`Constraints.scala`, `def resolution`) the guard that
`splitConcrete` already has: before minting a fresh `z` for the resolvent
`v <- (z, C ∪ D)`, ask the reverse lookup whether the system already names `v \ (C ∪ D)`,
and reuse that name if it does.  Section 2 there proves the guard is not a semantic
change.  The companion question is whether it is a *termination* change.

The answer is no, and this file exhibits the obstruction.  Four constraints

```
a <- (p, (|l1|))     a <- (q, (|l2|))     b <- (p, (|l3|))     b <- (q, (|l4|))
```

on four distinct variables and four distinct labels admit a guarded mint on `a` and a
guarded mint on `b`; the six conclusions contain

```
p <- (z, (|l2|))     p <- (w, (|l4|))     q <- (z, (|l1|))     q <- (w, (|l3|))
```

which is **the same gadget again** — roots `p, q`, children `z, w`, labels permuted to
`(l2, l4, l1, l3)`.  So the configuration reproduces itself, two mints per round, forever
(`GInv.round`, `GInv.diverges`), and no `ℕ`-valued measure decreases on every guarded step
(`gres_no_decreasing_measure`).  This is the exact analogue, for the guarded rule, of
`Cut.res_no_decreasing_measure` for the unguarded one.

## Why the guard never fires here

The guard at the `a` step asks for a constraint `a <- (z', (|l1, l2|))`, whose concrete
part carries TWO labels.  Every constraint of the gadget carries ONE.  `NoTwo G v` — "no
constraint of `G` with left-hand side `v` carries more than one label" — is therefore a
sufficient reason for the guard to fail (`not_resolved_of_noTwo`), and it is preserved by
a round: a mint on `a` is the only conclusion with a two-label concrete part and its
left-hand side is `a`, while the next round's roots are `p` and `q` and its children `z`
and `w` are fresh, hence the left-hand side of nothing at all.

## Why this does not contradict termination on satisfiable systems

The seed has NO model (`gSeed_unsat`), so the divergence lives entirely inside the
unsatisfiable systems.  Section 6 makes that constructive: the per-label unit propagation
of `Rowpartition.LabelProp` refutes THIS seed at the single label `1` (`gSeed_refuted`),
so a solver that runs the label check on `gSeed` never enters the loop this file
constructs on `gSeed`.

That is all section 6 proves.  This header used to conclude "guarded resolution and the
label check are complementary defences"; that general claim -- every system on which the
shipped rules diverge is refuted by the check on its input -- is FALSE, and
`DefaultDiverge.lean` (`not_CRule`, 2026-09-02) exhibits the witness: `gSeed` hidden behind
two triples that propagation cannot see through and four non-generative steps unfold.
-/
import Rowpartition.ResGuard
import Rowpartition.LabelProp

namespace Rowpartition

/-! ## 1. Singletons, pairs, and the shape of a mint

Every constraint in the gadget has a singleton or a two-element concrete part, so the
whole development runs on these five facts. -/

/-- Deleting a DIFFERENT singleton leaves a singleton untouched. -/
theorem sdiff_lone {l m : Label} (h : l ≠ m) : ({l} : Row) \ {m} = {l} := by
  ext x
  simp only [Finset.mem_sdiff, Finset.mem_singleton]
  constructor
  · exact fun hx => hx.1
  · rintro rfl
    exact ⟨rfl, h⟩

/-- Two distinct singletons meet `resolution`'s guard: `tops` and `bots` are nonempty. -/
theorem sdiff_lone_ne {l m : Label} (h : l ≠ m) : ({l} : Row) \ {m} ≠ ∅ := by
  rw [sdiff_lone h]
  exact Finset.ne_empty_of_mem (Finset.mem_singleton_self l)

/-- The concrete part a mint emits from two singleton premises is their pair. -/
theorem union_lone (l m : Label) : ({l} : Row) ∪ {m} = {l, m} := by
  ext x; simp

/-- A pair of distinct labels really carries two labels — this is what the guard would
have to find, and what `NoTwo` forbids. -/
theorem two_le_card_pair {l m : Label} (h : l ≠ m) : 2 ≤ ({l, m} : Row).card := by
  by_contra hc
  have h1 : ({l, m} : Row).card ≤ 1 := by omega
  exact h (Finset.card_le_one.mp h1 l (by simp) m (by simp))

/-- What a mint emits when both premises carry a SINGLETON concrete part: the resolvent
gets the pair, and each lone variable gets the other premise's label.  This is the only
shape of mint the gadget below ever performs. -/
theorem resResult_lone (G : System) (v x y z : Var) {l m : Label} (h : l ≠ m) :
    resResult G v x y {l} {m} z
      = insert (mk v {z} {l, m}) (insert (mk x {z} {m}) (insert (mk y {z} {l}) G)) := by
  simp only [resResult, union_lone, sdiff_lone h, sdiff_lone h.symm]

/-- The lone variable of a canonical one-variable constraint is a right-hand variable. -/
theorem mem_vars_mk {a v : Var} {S : Finset Var} {k : Row} (h : v ∈ S) :
    v ∈ (mk a S k).vars := mem_slist.mpr h

/-- …and it is the only one. -/
theorem vars_mk_lone {a x v : Var} {k : Row} (h : v ∈ (mk a {x} k).vars) : v = x := by
  have h' : v ∈ ({x} : Finset Var) := mem_slist.mp h
  simpa using h'

/-! ## 2. The invariant that keeps the guard silent -/

/-- **No constraint of `G` with left-hand side `v` carries more than one label.**  A
system in this state cannot answer the reverse lookup for a two-label resolvent on `v`. -/
def NoTwo (G : System) (v : Var) : Prop := ∀ c ∈ G, c.lhs = v → c.conc.card ≤ 1

/-- **Why the guard cannot fire.**  `Resolved G v K` demands a constraint on `v` whose
concrete part is exactly `K`; if `K` carries two labels and every constraint on `v`
carries at most one, there is no such constraint. -/
theorem not_resolved_of_noTwo {G : System} {v : Var} {K : Row} (h : NoTwo G v)
    (hK : 2 ≤ K.card) : ¬ Resolved G v K := by
  rintro ⟨z, -, hz⟩
  have hc := h _ hz rfl
  simp only [conc_mk] at hc
  omega

/-- `NoTwo` is preserved by adding a constraint that is either about another variable or
carries at most one label itself. -/
theorem noTwo_insert {G : System} {v : Var} {c : Constraint}
    (hc : c.lhs = v → c.conc.card ≤ 1) (h : NoTwo G v) : NoTwo (insert c G) v := by
  intro d hd hdv
  rcases Finset.mem_insert.mp hd with rfl | hd'
  · exact hc hdv
  · exact h d hd' hdv

/-- A variable the system does not mention satisfies the bound vacuously — this is what
makes the FRESH children of a round eligible to be the next round's roots. -/
theorem noTwo_of_fresh {G : System} {z : Var} (hz : z ∉ allVars G) : NoTwo G z :=
  fun _ hc hcz => absurd (hcz ▸ lhs_mem_allVars hc) hz

/-! ## 3. The self-reproducing configuration -/

/-- **The gadget.**  Two roots `a, b`, two children `p, q`, four distinct labels, and the
four cross constraints; plus the bound of section 2 for each of the four variables, which
is what keeps the guard from firing on either root. -/
structure GInv (G : System) (a b p q : Var) (l1 l2 l3 l4 : Label) : Prop where
  -- the constructor is named `intro` rather than the default `mk`, so that inside the
  -- `GInv` namespace the canonical-constraint builder `Rowpartition.mk` stays visible
  intro ::
  /-- `a <- (p, (|l1|))` -/
  e1 : mk a {p} {l1} ∈ G
  /-- `a <- (q, (|l2|))` -/
  e2 : mk a {q} {l2} ∈ G
  /-- `b <- (p, (|l3|))` -/
  e3 : mk b {p} {l3} ∈ G
  /-- `b <- (q, (|l4|))` -/
  e4 : mk b {q} {l4} ∈ G
  /-- the two roots are different variables -/
  ab : a ≠ b
  /-- a root is not one of its own children -/
  ap : a ≠ p
  /-- a root is not one of its own children -/
  aq : a ≠ q
  /-- a root is not one of its own children -/
  bp : b ≠ p
  /-- a root is not one of its own children -/
  bq : b ≠ q
  /-- the two children are different variables -/
  pq : p ≠ q
  /-- the four labels are pairwise distinct -/
  l12 : l1 ≠ l2
  /-- the four labels are pairwise distinct -/
  l13 : l1 ≠ l3
  /-- the four labels are pairwise distinct -/
  l14 : l1 ≠ l4
  /-- the four labels are pairwise distinct -/
  l23 : l2 ≠ l3
  /-- the four labels are pairwise distinct -/
  l24 : l2 ≠ l4
  /-- the four labels are pairwise distinct -/
  l34 : l3 ≠ l4
  /-- nothing on `a` carries two labels, so the guard cannot answer for `a` -/
  na : NoTwo G a
  /-- nothing on `b` carries two labels, so the guard cannot answer for `b` -/
  nb : NoTwo G b
  /-- nothing on `p` carries two labels — needed one round later, when `p` is a root -/
  np : NoTwo G p
  /-- nothing on `q` carries two labels — needed one round later, when `q` is a root -/
  nq : NoTwo G q

/-- **One round.**  Two guarded MINT steps — one on each root — turn a gadget into a
gadget on its own children, with two fresh grandchildren and the four labels permuted,
and add at least two constraints.  Neither step can take the `reuse` branch: the
resolvent it would look up carries two labels and, by `NoTwo`, nothing on that root
does. -/
theorem GInv.round {G : System} {a b p q : Var} {l1 l2 l3 l4 : Label}
    (h : GInv G a b p q l1 l2 l3 l4) :
    ∃ (G' : System) (z w : Var),
      GResSteps 2 G G' ∧ GInv G' p q z w l2 l4 l1 l3 ∧ G.card + 2 ≤ G'.card := by
  obtain ⟨z, hz⟩ := exists_fresh (allVars G)
  -- the four variables of the gadget are in the vocabulary, so `z` differs from each
  have haG : a ∈ allVars G := lhs_mem_allVars h.e1
  have hbG : b ∈ allVars G := lhs_mem_allVars h.e3
  have hpG : p ∈ allVars G := mem_allVars h.e1 (Or.inr (by simp))
  have hqG : q ∈ allVars G := mem_allVars h.e2 (Or.inr (by simp))
  have haz : a ≠ z := fun hh => hz (hh ▸ haG)
  have hbz : b ≠ z := fun hh => hz (hh ▸ hbG)
  have hpz : p ≠ z := fun hh => hz (hh ▸ hpG)
  have hqz : q ≠ z := fun hh => hz (hh ▸ hqG)
  -- the first mint, on the root `a`
  obtain ⟨G₁, hG₁⟩ : ∃ G₁ : System,
      G₁ = insert (mk a {z} {l1, l2}) (insert (mk p {z} {l2}) (insert (mk q {z} {l1}) G)) :=
    ⟨_, rfl⟩
  have hp₁ : ResPair G a p q ({l1} : Row) ({l2} : Row) :=
    ⟨h.e1, h.e2, sdiff_lone_ne h.l12, sdiff_lone_ne h.l12.symm⟩
  have hg₁ : ¬ Resolved G a (({l1} : Row) ∪ {l2}) := by
    rw [union_lone]
    exact not_resolved_of_noTwo h.na (two_le_card_pair h.l12)
  have hstep₁ : GResStep G G₁ := by
    rw [hG₁, ← resResult_lone G a p q z h.l12]
    exact GResStep.mint hp₁ hg₁ hz
  have hcard₁ : G.card < G₁.card := by
    rw [hG₁, ← resResult_lone G a p q z h.l12]
    exact (GResStep.mint_toResStep hp₁ hz).card_lt
  have hsub₁ : G ⊆ G₁ := hstep₁.subset
  -- the second mint, on the root `b`, with a second fresh name
  obtain ⟨w, hw⟩ := exists_fresh (allVars G₁)
  have hbG₁ : b ∈ allVars G₁ := allVars_mono hsub₁ hbG
  have hpG₁ : p ∈ allVars G₁ := allVars_mono hsub₁ hpG
  have hqG₁ : q ∈ allVars G₁ := allVars_mono hsub₁ hqG
  have hzG₁ : z ∈ allVars G₁ := by
    refine mem_allVars (c := mk a {z} {l1, l2}) ?_ (Or.inr (by simp))
    rw [hG₁]; exact Finset.mem_insert_self _ _
  have hbw : b ≠ w := fun hh => hw (hh ▸ hbG₁)
  have hpw : p ≠ w := fun hh => hw (hh ▸ hpG₁)
  have hqw : q ≠ w := fun hh => hw (hh ▸ hqG₁)
  have hzw : z ≠ w := fun hh => hw (hh ▸ hzG₁)
  obtain ⟨G₂, hG₂⟩ : ∃ G₂ : System,
      G₂ = insert (mk b {w} {l3, l4}) (insert (mk p {w} {l4}) (insert (mk q {w} {l3}) G₁)) :=
    ⟨_, rfl⟩
  have hp₂ : ResPair G₁ b p q ({l3} : Row) ({l4} : Row) :=
    ⟨hsub₁ h.e3, hsub₁ h.e4, sdiff_lone_ne h.l34, sdiff_lone_ne h.l34.symm⟩
  have hnb₁ : NoTwo G₁ b := by
    rw [hG₁]
    exact noTwo_insert (fun hh => absurd (show a = b from hh) h.ab)
      (noTwo_insert (fun hh => absurd (show p = b from hh) h.bp.symm)
        (noTwo_insert (fun hh => absurd (show q = b from hh) h.bq.symm) h.nb))
  have hg₂ : ¬ Resolved G₁ b (({l3} : Row) ∪ {l4}) := by
    rw [union_lone]
    exact not_resolved_of_noTwo hnb₁ (two_le_card_pair h.l34)
  have hstep₂ : GResStep G₁ G₂ := by
    rw [hG₂, ← resResult_lone G₁ b p q w h.l34]
    exact GResStep.mint hp₂ hg₂ hw
  have hcard₂ : G₁.card < G₂.card := by
    rw [hG₂, ← resResult_lone G₁ b p q w h.l34]
    exact (GResStep.mint_toResStep hp₂ hw).card_lt
  have hsub₂ : G₁ ⊆ G₂ := hstep₂.subset
  refine ⟨G₂, z, w, GResSteps.tail (GResSteps.tail (GResSteps.refl G) hstep₁) hstep₂, ?_,
    by omega⟩
  refine ⟨?_, ?_, ?_, ?_, h.pq, hpz, hpw, hqz, hqw, hzw,
    h.l24, h.l12.symm, h.l23, h.l14.symm, h.l34.symm, h.l13, ?_, ?_, ?_, ?_⟩
  · exact hsub₂ (by rw [hG₁]; exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))
  · rw [hG₂]; exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
  · refine hsub₂ ?_
    rw [hG₁]
    exact Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))
  · rw [hG₂]
    exact Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))
  · -- `NoTwo` for the new root `p`
    rw [hG₂, hG₁]
    refine noTwo_insert (fun hh => absurd (show b = p from hh) h.bp) ?_
    refine noTwo_insert (fun _ => by simp) ?_
    refine noTwo_insert (fun hh => absurd (show q = p from hh) h.pq.symm) ?_
    refine noTwo_insert (fun hh => absurd (show a = p from hh) h.ap) ?_
    refine noTwo_insert (fun _ => by simp) ?_
    exact noTwo_insert (fun hh => absurd (show q = p from hh) h.pq.symm) h.np
  · -- `NoTwo` for the new root `q`
    rw [hG₂, hG₁]
    refine noTwo_insert (fun hh => absurd (show b = q from hh) h.bq) ?_
    refine noTwo_insert (fun hh => absurd (show p = q from hh) h.pq) ?_
    refine noTwo_insert (fun _ => by simp) ?_
    refine noTwo_insert (fun hh => absurd (show a = q from hh) h.aq) ?_
    refine noTwo_insert (fun hh => absurd (show p = q from hh) h.pq) ?_
    exact noTwo_insert (fun _ => by simp) h.nq
  · -- `NoTwo` for the new child `z`: it is the left-hand side of nothing
    rw [hG₂, hG₁]
    refine noTwo_insert (fun hh => absurd (show b = z from hh) hbz) ?_
    refine noTwo_insert (fun hh => absurd (show p = z from hh) hpz) ?_
    refine noTwo_insert (fun hh => absurd (show q = z from hh) hqz) ?_
    refine noTwo_insert (fun hh => absurd (show a = z from hh) haz) ?_
    refine noTwo_insert (fun hh => absurd (show p = z from hh) hpz) ?_
    exact noTwo_insert (fun hh => absurd (show q = z from hh) hqz) (noTwo_of_fresh hz)
  · -- `NoTwo` for the new child `w`: likewise
    rw [hG₂]
    refine noTwo_insert (fun hh => absurd (show b = w from hh) hbw) ?_
    refine noTwo_insert (fun hh => absurd (show p = w from hh) hpw) ?_
    exact noTwo_insert (fun hh => absurd (show q = w from hh) hqw) (noTwo_of_fresh hw)

/-- Guarded runs compose. -/
theorem GResSteps.trans {m n : ℕ} {G G' G'' : System} (h₁ : GResSteps m G G')
    (h₂ : GResSteps n G' G'') : GResSteps (m + n) G G'' := by
  induction h₂ with
  | refl => exact h₁
  | @tail k Ga Gb Gc _ hstep ih => exact GResSteps.tail (ih h₁) hstep

/-- The induction behind `GInv.diverges`, with the gadget's variables and labels
generalised: each round hands the next one a DIFFERENT gadget. -/
theorem gInv_diverges_aux : ∀ (n : ℕ) (G : System) (a b p q : Var) (l1 l2 l3 l4 : Label),
    GInv G a b p q l1 l2 l3 l4 → ∃ G', GResSteps (2 * n) G G' ∧ G.card + 2 * n ≤ G'.card := by
  intro n
  induction n with
  | zero =>
    intro G _ _ _ _ _ _ _ _ _
    exact ⟨G, GResSteps.refl G, by omega⟩
  | succ n ih =>
    intro G a b p q l1 l2 l3 l4 h
    obtain ⟨G₁, z, w, hsteps, hinv, hcard⟩ := h.round
    obtain ⟨G₂, hsteps', hcard'⟩ := ih G₁ p q z w l2 l4 l1 l3 hinv
    refine ⟨G₂, ?_, by omega⟩
    have he : 2 * (n + 1) = 2 + 2 * n := by omega
    rw [he]
    exact GResSteps.trans hsteps hsteps'

/-- **Chains of every length.**  From a gadget the guarded rule admits `2 * n` steps for
every `n`, each round adding at least two constraints.  The guard has not made the search
space finite; it has only renamed the variables the search invents. -/
theorem GInv.diverges {G : System} {a b p q : Var} {l1 l2 l3 l4 : Label}
    (h : GInv G a b p q l1 l2 l3 l4) (n : ℕ) :
    ∃ G', GResSteps (2 * n) G G' ∧ G.card + 2 * n ≤ G'.card :=
  gInv_diverges_aux n G a b p q l1 l2 l3 l4 h

/-! ## 4. The concrete seed -/

/-- **The four-constraint witness.**  Variables `a = 0`, `b = 1`, `p = 2`, `q = 3`;
labels `1, 2, 3, 4`:

```
0 <- (2, (|1|))     0 <- (3, (|2|))     1 <- (2, (|3|))     1 <- (3, (|4|))
```
-/
def gSeed : System := {mk 0 {2} {1}, mk 0 {3} {2}, mk 1 {2} {3}, mk 1 {3} {4}}

theorem gSeed_e1 : mk 0 {2} {1} ∈ gSeed := Finset.mem_insert_self _ _

theorem gSeed_e2 : mk 0 {3} {2} ∈ gSeed :=
  Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)

theorem gSeed_e3 : mk 1 {2} {3} ∈ gSeed :=
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))

theorem gSeed_e4 : mk 1 {3} {4} ∈ gSeed :=
  Finset.mem_insert_of_mem
    (Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (Finset.mem_singleton_self _)))

/-- Every concrete part of the seed is a singleton, so the bound of section 2 holds for
every variable at once. -/
theorem gSeed_noTwo (v : Var) : NoTwo gSeed v := by
  intro c hc _
  simp only [gSeed, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl | rfl <;> simp

/-- The seed is a gadget. -/
theorem gSeed_inv : GInv gSeed 0 1 2 3 1 2 3 4 :=
  ⟨gSeed_e1, gSeed_e2, gSeed_e3, gSeed_e4,
    by decide, by decide, by decide, by decide, by decide, by decide,
    by decide, by decide, by decide, by decide, by decide, by decide,
    gSeed_noTwo 0, gSeed_noTwo 1, gSeed_noTwo 2, gSeed_noTwo 3⟩

/-- **The guarded rule does not terminate.**  From four constraints there are guarded
chains of every even length, and the working set grows by at least one constraint per
step.  Compare `Cut.resSeed_diverges` for the unguarded rule: adding the reverse-lookup
guard removes the two-constraint witness, not the phenomenon. -/
theorem gSeed_diverges (n : ℕ) :
    ∃ G, GResSteps (2 * n) gSeed G ∧ gSeed.card + 2 * n ≤ G.card :=
  gSeed_inv.diverges n

/-- A measure that decreases on every guarded step bounds the length of every guarded
run.  (`Cut.res_steps_measure`, transported to `GResSteps`.) -/
theorem gres_steps_measure {μ : System → ℕ} (hμ : ∀ G G', GResStep G G' → μ G' < μ G)
    {n : ℕ} {G G' : System} (h : GResSteps n G G') : μ G' + n ≤ μ G := by
  induction h with
  | refl => omega
  | @tail n G G' G'' _ hstep ih =>
    have := hμ G' G'' hstep
    omega

/-- **No measure into `ℕ` decreases on every guarded resolution step** — exactly the
negative result `Cut.res_no_decreasing_measure` states for the unguarded rule.  So the
guard buys no termination argument of this shape. -/
theorem gres_no_decreasing_measure :
    ¬ ∃ μ : System → ℕ, ∀ G G', GResStep G G' → μ G' < μ G := by
  rintro ⟨μ, hμ⟩
  obtain ⟨G, hsteps, -⟩ := gSeed_diverges (μ gSeed + 1)
  have := gres_steps_measure hμ hsteps
  omega

/-! ## 5. The seed has no model

This is what confines the divergence: the guarded rule terminates on satisfiable systems,
and the witness above is unsatisfiable.  The two results are complementary, not in
conflict. -/

/-- **The seed is unsatisfiable.**  Label `4` is in `rho 1` by the fourth constraint, so
by the third it is in `rho 2`, so by the first it is in `rho 0`, so by the second it is in
`rho 3` — which the fourth constraint forbids. -/
theorem gSeed_unsat : ¬ ∃ rho, SModels rho gSeed := by
  rintro ⟨rho, hm⟩
  have h1 := (sat_lone_iff rho 0 2 {1}).mp (hm _ gSeed_e1)
  have h2 := (sat_lone_iff rho 0 3 {2}).mp (hm _ gSeed_e2)
  have h3 := (sat_lone_iff rho 1 2 {3}).mp (hm _ gSeed_e3)
  have h4 := (sat_lone_iff rho 1 3 {4}).mp (hm _ gSeed_e4)
  have m1 : (4 : Label) ∈ rho 1 := by
    rw [h4.1]; exact Finset.mem_union_left _ (Finset.mem_singleton_self 4)
  have m2 : (4 : Label) ∈ rho 2 := by
    rw [h3.1] at m1
    rcases Finset.mem_union.mp m1 with hh | hh
    · exact absurd (Finset.mem_singleton.mp hh) (by decide)
    · exact hh
  have m3 : (4 : Label) ∈ rho 0 := by
    rw [h1.1]; exact Finset.mem_union_right _ m2
  have m4 : (4 : Label) ∈ rho 3 := by
    rw [h2.1] at m3
    rcases Finset.mem_union.mp m3 with hh | hh
    · exact absurd (Finset.mem_singleton.mp hh) (by decide)
    · exact hh
  exact Finset.disjoint_left.mp h4.2 (Finset.mem_singleton_self 4) m4

/-- **Every system on the divergent path is unsatisfiable too.**  A guarded run is
equisatisfiable with its input, so the whole infinite chain of section 4 is a search
through systems whose answer was already fixed before the first step. -/
theorem gSeed_path_unsat {n : ℕ} {G : System} (h : GResSteps n gSeed G) :
    ¬ ∃ rho, SModels rho G := fun hs => gSeed_unsat (h.satisfiable_iff.mp hs)

/-! ## 6. The label check refutes the seed

`LabelProp.Forced` is per-label unit propagation: no case split, no minting, a verdict
about `G` rather than a new system.  It refutes the seed at the single label `1`, and it
does so in five propagation steps — which is the design point.  The gadget defeats the
reverse-lookup guard, but it does not defeat the label check. -/

/-- Membership in the seed, as `LabelProp` wants it. -/
theorem gSeed_mem_toList {c : Constraint} (h : c ∈ gSeed) : c ∈ gSeed.toList :=
  Finset.mem_toList.mpr h

/-- `0 <- (2, (|1|))` pins label `1` into variable `0`. -/
theorem gSeed_forced_zero_true : Forced 1 gSeed.toList 0 true :=
  Forced.conc_lhs (c := mk 0 {2} {1}) (gSeed_mem_toList gSeed_e1) (by decide)

/-- …and out of variable `2`, its other part. -/
theorem gSeed_forced_two_false : Forced 1 gSeed.toList 2 false :=
  Forced.conc_var (c := mk 0 {2} {1}) (gSeed_mem_toList gSeed_e1) (by decide)
    (mem_vars_mk (by simp))

/-- `0 <- (3, (|2|))` must account for label `1` somewhere, and its concrete part cannot,
so its lone variable `3` carries it. -/
theorem gSeed_forced_three_true : Forced 1 gSeed.toList 3 true := by
  refine Forced.last_one (c := mk 0 {3} {2}) (gSeed_mem_toList gSeed_e2) (by decide)
    (mem_vars_mk (by simp)) gSeed_forced_zero_true ?_
  intro w hw hne
  exact absurd (vars_mk_lone hw) hne

/-- `1 <- (2, (|3|))` has no part able to carry label `1`, so variable `1` does not. -/
theorem gSeed_forced_one_false : Forced 1 gSeed.toList 1 false := by
  refine Forced.all_false (c := mk 1 {2} {3}) (gSeed_mem_toList gSeed_e3) (by decide) ?_
  intro v hv
  have hv2 : v = 2 := vars_mk_lone hv
  subst hv2
  exact gSeed_forced_two_false

/-- …but `1 <- (3, (|4|))` says it does, because variable `3` does. -/
theorem gSeed_forced_one_true : Forced 1 gSeed.toList 1 true :=
  Forced.var_lhs (c := mk 1 {3} {4}) (gSeed_mem_toList gSeed_e4) (mem_vars_mk (by simp))
    gSeed_forced_three_true

/-- **Per-label unit propagation refutes the seed**, at the single label `1` and without
a case split. -/
theorem gSeed_refuted : Refuted gSeed.toList :=
  ⟨1, 1, gSeed_forced_one_true, gSeed_forced_one_false⟩

/-- The label check alone already establishes `gSeed_unsat`: the two proofs of
unsatisfiability in this file are independent, one semantic and one by propagation. -/
theorem gSeed_unsat_of_refuted : ¬ ∃ rho, SModels rho gSeed := by
  rintro ⟨rho, hm⟩
  exact refuted_unsat gSeed_refuted ⟨rho, (sModels_iff_models rho gSeed).mp hm⟩

/-! ## Summary

* The reverse-lookup guard is a real gain for `resolution`: `ResGuard` section 2 proves
  it is not a semantic change, and the positive termination result is the business of the
  companion module, not of this file — nothing below is evidence for it.  Informally, on
  `Cut.resSeed` the guard has something to find, because every application there mints the
  resolvent of the SAME `v` at the SAME `C ∪ D`, so the lookup hits on the second one.
* It does NOT restore termination.  `gSeed_diverges` and `gres_no_decreasing_measure`:
  four constraints on four variables and four labels admit guarded chains of every
  length, because each round's mints are for a DIFFERENT left-hand side and a DIFFERENT
  two-label concrete part than anything the system carries, and the round's fresh
  children are the next round's roots.  The guard is a lookup, not a bound, and the
  gadget makes the lookup miss forever.
* The obstruction is now confined to systems with NO model.  `gSeed_unsat` is the other
  half of the dichotomy: the divergent witness constructed here is unsatisfiable, which
  is exactly why it does not contradict termination of the guarded rule on satisfiable
  systems.  A guarded run is equisatisfiable with its input (`GResSteps.satisfiable_iff`),
  so every system on the divergent path is unsatisfiable too (`gSeed_path_unsat`) — the
  solver is burning time on a problem that was already decided before the first step.
* And it was decidable cheaply.  `gSeed_refuted`: the per-label unit propagation of
  `Rowpartition.LabelProp` refutes this witness at the single label `1`, in five
  propagation steps and without a case split.  The guard bounds the search on the
  satisfiable systems; the label check removes THIS unsatisfiable seed.  It does not
  remove every unsatisfiable seed the guard cannot bound: the check refutes only what
  propagation can force (`LabelProp.Incomplete`), and `DefaultDiverge.not_CRule` gives an
  unsatisfiable input on which the shipped rule set diverges unrefuted.  (This bullet used
  to say the two were "complementary defences"; retired 2026-09-02.)
-/

end Rowpartition
