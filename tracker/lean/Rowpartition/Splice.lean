/-
# `Subst.reduce`: the residual the solver publishes, and what it forgets

`Subst.scala`, `def reduce(lc, csz, es, ps)`, folds over the SATURATED partition list
`ps` and rewrites the constraint list `cs` that `solve` actually publishes.  Its second
case fires on a partition whose left-hand side is AMBIGUOUS -- existentially bound, or
minted by a solver rule:

    case (Partition(v, RHS(abs, con), inf), cs) if v.ty.ambiguous || es.contains(v) =>
      cs map { case Part(loc, l, rs) => Part(loc, l, rs flatMap {
                 case VarT(v) => ConcreteRho(lc, con) :: abs.toList.map(VarT(_))
                 case x       => List(x) })
               case x => x }

So `v` is eliminated from RIGHT-hand sides by substituting the partition's own
right-hand side.  Two things it does NOT do, and both are load-bearing here:

* it never appends, so the partition it used is DISCARDED and never emitted;
* it never rewrites a LEFT-hand side.

`spliceC` / `spliceG` / `reduce2` below are that rewrite.  One modelling gap is worth
naming immediately: the implementation inserts `ConcreteRho(lc, con)` as a SEPARATE
block of the right-hand side, while `Constraint` carries a single concrete part, so
`spliceC` unions the two concrete parts.  `Rules.rsat_iff_flatten` measures the
difference exactly: the multi-block form additionally demands that the blocks be
disjoint, which is error condition 10 (duplicated field).  Section 6 shows what the
union forgets.

## Headline

* SOUND, with no side condition at all: every constraint the residual publishes is
  entailed by the input (`splice_sat`, `reduce2_models`, `reduce2_entails`).
* CONSERVATIVE, but only under three side conditions (`spliceG_backward`): a model of
  the spliced system extends -- by giving `v` the value its own definition demands -- to
  a model of the original system together with the discarded definition.  Two of the
  three conditions hold automatically at any model of the input system
  (`splice_conc_disjoint_of_models`, `splice_conc_empty_of_models`).  The third,
  "`v` is not a left-hand side of the list being rewritten", does not.
* The ticket's question -- can the DROPPED partition lose information? -- is answered by
  `dropped_loses_nothing` together with `DroppedPartition.dropped_can_lose`: under the
  three conditions, nothing is lost and the dropped partition is never needed (its
  hypotheses are literally unused in the proof); but the statement WITHOUT the
  left-hand-side condition is FALSE, and the counterexample is a satisfiable four
  variable system with no concrete labels at all.  The culprit is not the drop as such:
  it is that `reduce` discards the definition it substituted with while never rewriting
  a left-hand side, so an ambiguous `v` that still occurs as a left-hand side of the
  published list is left in the residual with nothing to tie it to the rest.
-/
import Rowpartition.Basic
import Rowpartition.Rules
import Rowpartition.Canonical

namespace Rowpartition

/-! ## 1. The rewrite

`spliceVars v ys xs` replaces every occurrence of `v` in the variable list `xs` by the
whole list `ys`; `spliceC` does that to a constraint's right-hand side and unions the
concrete parts; `spliceG` maps it over a system; `reduce2` is the fold of `Subst.reduce`,
with the guard `v.ty.ambiguous || es.contains(v)` abstracted to a decidable predicate
`E` on variables. -/

/-- Substitute the variable list `ys` for every occurrence of `v` in `xs`.  This is the
variable part of the Scala `rs flatMap { case VarT(v) => ... ; case x => List(x) }`. -/
def spliceVars (v : Var) (ys xs : List Var) : List Var :=
  xs.flatMap (fun w => if w = v then ys else [w])

/-- Splice the partition `p` (whose left-hand side is `v`) into the right-hand side of
`c`: every occurrence of `v` becomes `p`'s variable list, and, if `v` occurred at all,
`p`'s concrete part is unioned into `c`'s.  The left-hand side is untouched. -/
def spliceC (v : Var) (p c : Constraint) : Constraint :=
  ⟨c.lhs, c.vars.flatMap (fun w => if w = v then p.vars else [w]),
   if v ∈ c.vars then c.conc ∪ p.conc else c.conc⟩

/-- Splice `p` into every constraint of a system. -/
def spliceG (v : Var) (p : Constraint) (G : List Constraint) : List Constraint :=
  G.map (spliceC v p)

/-- `Subst.reduce`'s fold, second case only: for every partition of the saturated list
`S` whose left-hand side satisfies the ambiguity guard `E`, splice it into the
accumulated constraint list.  Note what the fold does with the partition afterwards:
nothing.  It is never appended to the result. -/
def reduce2 (E : Var → Prop) [DecidablePred E] (S G : List Constraint) : List Constraint :=
  S.foldr (fun p acc => if E p.lhs then spliceG p.lhs p acc else acc) G

/-- Membership in a spliced variable list: either `v` occurred and the member comes from
the substituted list, or the member is one of the original variables other than `v`. -/
theorem mem_spliceVars {v u : Var} {ys xs : List Var} :
    u ∈ spliceVars v ys xs ↔ (v ∈ xs ∧ u ∈ ys) ∨ (u ∈ xs ∧ u ≠ v) := by
  simp only [spliceVars, List.mem_flatMap]
  constructor
  · rintro ⟨w, hw, hu⟩
    by_cases hwv : w = v
    · rw [if_pos hwv] at hu
      refine Or.inl ⟨?_, hu⟩
      rw [← hwv]; exact hw
    · rw [if_neg hwv, List.mem_singleton] at hu
      subst hu
      exact Or.inr ⟨hw, hwv⟩
  · rintro (⟨hv, hu⟩ | ⟨hu, hne⟩)
    · exact ⟨v, hv, by rw [if_pos rfl]; exact hu⟩
    · exact ⟨u, hu, by rw [if_neg hne]; exact List.mem_singleton_self u⟩

/-- Splicing a variable that does not occur changes nothing. -/
theorem spliceVars_of_not_mem {v : Var} {ys : List Var} :
    ∀ {xs : List Var}, v ∉ xs → spliceVars v ys xs = xs := by
  intro xs
  induction xs with
  | nil => intro _; rfl
  | cons w xs ih =>
    intro h
    have hw : w ≠ v := by rintro rfl; exact h (List.mem_cons_self ..)
    have hxs : v ∉ xs := fun hh => h (List.mem_cons_of_mem _ hh)
    have hrec := ih hxs
    simp only [spliceVars, List.flatMap_cons, if_neg hw] at hrec ⊢
    rw [hrec]
    rfl

/-- The constraint-level form of `spliceVars`, when `v` does occur. -/
theorem spliceC_eq_of_mem {v : Var} {p c : Constraint} (h : v ∈ c.vars) :
    spliceC v p c = ⟨c.lhs, spliceVars v p.vars c.vars, c.conc ∪ p.conc⟩ := by
  simp only [spliceC, spliceVars, if_pos h]

/-- A constraint whose right-hand side does not mention `v` is left alone. -/
theorem spliceC_of_not_mem {v : Var} {p c : Constraint} (h : v ∉ c.vars) :
    spliceC v p c = c := by
  have h1 : spliceVars v p.vars c.vars = c.vars := spliceVars_of_not_mem h
  simp only [spliceVars] at h1
  calc spliceC v p c = ⟨c.lhs, c.vars, c.conc⟩ := by simp only [spliceC, if_neg h, h1]
    _ = c := rfl

/-- Splicing never touches a left-hand side. -/
theorem spliceC_lhs {v : Var} {p c : Constraint} : (spliceC v p c).lhs = c.lhs := rfl

/-! ## 2. Soundness: the residual is entailed by the input

`splice_sat` needs no side condition whatever.  Two subtleties are discharged rather
than assumed.  The concrete parts: if `v` occurs in `c` then `Sat rho c` gives
`Disjoint c.conc (rho v)` and `Sat rho p` gives `p.conc ⊆ rho v`, so
`Disjoint c.conc p.conc` FOLLOWS.  Duplicates: if some `w` occurs both in `p.vars` and
in `c.vars` outside the `v` position then the flatMap lists it twice, and pairwise
disjointness then forces `rho w = ∅` -- which is true, because `rho w ⊆ rho v` and
`rho w` is disjoint from `rho v`.  Both are handled by the positional form of
`List.pairwise_flatMap`, which compares two positions rather than two variables. -/

/-- **One splice is sound.**  If `rho` satisfies the partition `p` (with left-hand side
`v`) and the constraint `c`, it satisfies the spliced constraint.  No linearity, no
disjointness, no freshness hypothesis. -/
theorem splice_sat {rho : Assign} {v : Var} {p c : Constraint}
    (hp : Sat rho p) (hc : Sat rho c) (hpl : p.lhs = v) : Sat rho (spliceC v p c) := by
  classical
  by_cases hv : v ∈ c.vars
  · have hconcp : p.conc ⊆ rho v := by
      have h := hp.conc_subset_lhs; rwa [hpl] at h
    have hsubv : ∀ u ∈ p.vars, rho u ⊆ rho v := by
      intro u hu
      have h := hp.subset_lhs hu; rwa [hpl] at h
    have hmemp : ∀ l, l ∈ rho v ↔ (l ∈ p.conc ∨ ∃ u ∈ p.vars, l ∈ rho u) := by
      intro l
      have h := hp.mem_lhs_iff l; rwa [hpl] at h
    have hsub : ∀ w u, u ∈ (if w = v then p.vars else [w]) → rho u ⊆ rho w := by
      intro w u hu
      by_cases hwv : w = v
      · rw [if_pos hwv] at hu
        rw [hwv]
        exact hsubv u hu
      · rw [if_neg hwv, List.mem_singleton] at hu
        subst hu
        exact Finset.Subset.refl _
    rw [spliceC_eq_of_mem hv]
    refine sat_mk ?_ ?_ ?_
    · intro l
      rw [hc.mem_lhs_iff l]
      constructor
      · rintro (hl | ⟨w, hw, hlw⟩)
        · exact Or.inl (Finset.mem_union_left _ hl)
        · by_cases hwv : w = v
          · rw [hwv] at hlw
            rcases (hmemp l).mp hlw with h1 | ⟨u, hu, hlu⟩
            · exact Or.inl (Finset.mem_union_right _ h1)
            · exact Or.inr ⟨u, mem_spliceVars.mpr (Or.inl ⟨hv, hu⟩), hlu⟩
          · exact Or.inr ⟨w, mem_spliceVars.mpr (Or.inr ⟨hw, hwv⟩), hlw⟩
      · rintro (hl | ⟨u, hu, hlu⟩)
        · rcases Finset.mem_union.mp hl with h1 | h2
          · exact Or.inl h1
          · exact Or.inr ⟨v, hv, (hmemp l).mpr (Or.inl h2)⟩
        · rcases mem_spliceVars.mp hu with ⟨_, hup⟩ | ⟨huc, _⟩
          · exact Or.inr ⟨v, hv, (hmemp l).mpr (Or.inr ⟨u, hup, hlu⟩)⟩
          · exact Or.inr ⟨u, huc, hlu⟩
    · intro u hu
      rw [Finset.disjoint_union_left]
      rcases mem_spliceVars.mp hu with ⟨_, hup⟩ | ⟨huc, hune⟩
      · exact ⟨disjoint_of_subset_right (hc.disjoint_conc hv) (hsubv u hup),
               hp.disjoint_conc hup⟩
      · exact ⟨hc.disjoint_conc huc,
               disjoint_of_subset_left (hc.disjoint_of_ne hv huc (Ne.symm hune)) hconcp⟩
    · rw [spliceVars, List.pairwise_flatMap]
      constructor
      · intro w _
        by_cases hwv : w = v
        · rw [if_pos hwv]; exact hp.pairwise_vars
        · rw [if_neg hwv]; exact List.pairwise_singleton _ _
      · refine hc.pairwise_vars.imp ?_
        intro a b hab x hx y hy
        exact disjoint_of_subset_left (disjoint_of_subset_right hab (hsub b y hy))
          (hsub a x hx)
  · rw [spliceC_of_not_mem hv]
    exact hc

/-- **Splicing a whole system is sound.** -/
theorem spliceG_models {rho : Assign} {v : Var} {p : Constraint} {G : List Constraint}
    (hp : Sat rho p) (hpl : p.lhs = v) (hm : Models rho G) :
    Models rho (spliceG v p G) := by
  intro d hd
  simp only [spliceG] at hd
  obtain ⟨e, he, rfl⟩ := List.mem_map.mp hd
  exact splice_sat hp (hm e he) hpl

/-- **`reduce`'s fold is sound.**  Any model of the saturated list together with the
input list is a model of the published residual. -/
theorem reduce2_models {rho : Assign} (E : Var → Prop) [DecidablePred E]
    {S G : List Constraint} (hS : Models rho S) (hG : Models rho G) :
    Models rho (reduce2 E S G) := by
  have key : ∀ T : List Constraint, Models rho T → Models rho (reduce2 E T G) := by
    intro T
    induction T with
    | nil => intro _; exact hG
    | cons p T ih =>
      intro hT
      rw [models_cons] at hT
      have hrec := ih hT.2
      simp only [reduce2, List.foldr_cons] at hrec ⊢
      by_cases hE : E p.lhs
      · rw [if_pos hE]
        exact spliceG_models hT.1 rfl hrec
      · rw [if_neg hE]
        exact hrec
  exact key S hS

/-- **The residual is entailed by the input.**  Every constraint `reduce` publishes
follows from the saturated list together with the input list. -/
theorem reduce2_entails (E : Var → Prop) [DecidablePred E] {S G : List Constraint}
    {c : Constraint} (hc : c ∈ reduce2 E S G) : Entails (S ++ G) c := by
  intro rho hm
  rw [models_append] at hm
  exact reduce2_models E hm.1 hm.2 c hc

/-! ## 3. What the union of the concrete parts forgets

`spliceC` unions `c.conc` and `p.conc`, so the residual no longer records that they were
disjoint; and if `v` occurs TWICE in one right-hand side, the two copies of `p`'s
concrete part collapse into one, so the residual no longer records that `p.conc` was
forced empty.  Both facts are recovered from any model of the ORIGINAL system, which is
why the two side conditions of section 4 are free on satisfiable input. -/

/-- At a model of `p` and of `G`, the concrete part of any constraint that mentions `v`
is disjoint from `p`'s concrete part.  (In the implementation this is exactly what
`RHS.merge` checks when it dies with "Fields appear twice in row".) -/
theorem splice_conc_disjoint_of_models {rho : Assign} {v : Var} {p : Constraint}
    {G : List Constraint} (hp : Sat rho p) (hpl : p.lhs = v) (hm : Models rho G) :
    ∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc := by
  intro d hd hv
  refine disjoint_of_subset_right ((hm d hd).disjoint_conc hv) ?_
  have h := hp.conc_subset_lhs
  rwa [hpl] at h

/-- At a model of `p` and of `G`, a right-hand side containing `v` twice forces `p`'s
concrete part to be empty. -/
theorem splice_conc_empty_of_models {rho : Assign} {v : Var} {p : Constraint}
    {G : List Constraint} (hp : Sat rho p) (hpl : p.lhs = v) (hm : Models rho G) :
    ∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅ := by
  intro d hd hcount
  have hv : rho v = ∅ := (hm d hd).eq_empty_of_dup hcount
  have h := hp.conc_subset_lhs
  rw [hpl, hv] at h
  exact Finset.subset_empty.mp h

/-! ## 4. The converse for one splice

This is the load-bearing half: a model of the spliced system extends, by giving `v` the
value its own definition demands, to a model of the original system TOGETHER with the
definition that was discarded.  Three side conditions are needed, and each is necessary:

* `hlhs`, `v` is not a left-hand side of `G`.  Splicing rewrites right-hand sides only,
  so a constraint `v <- ...` in `G` survives with its left-hand side intact and pins
  `rho v` to something the extension is free to contradict.  Section 7 turns this into a
  counterexample.
* `hdis` and `hdup`, the two facts of section 3, which the union of concrete parts
  forgets.  Both hold at every model of the input system.

The internal coherence of `p` itself (`hpd`) is needed only for `Sat` of `p`, so the
`G`-part is stated separately without it. -/

/-- A variable occurring at most once is never paired with itself. -/
theorem pairwise_not_both_eq {v : Var} :
    ∀ {xs : List Var}, xs.count v ≤ 1 → xs.Pairwise (fun a b => ¬(a = v ∧ b = v)) := by
  intro xs
  induction xs with
  | nil => intro _; exact List.Pairwise.nil
  | cons w xs ih =>
    intro h
    by_cases hw : w = v
    · rw [List.count_cons, if_pos (by simpa using hw)] at h
      have hc0 : xs.count v = 0 := by omega
      have hnm : v ∉ xs := List.count_eq_zero.mp hc0
      refine List.pairwise_cons.mpr ⟨?_, ih (by omega)⟩
      rintro b hb ⟨-, rfl⟩
      exact hnm hb
    · rw [List.count_cons, if_neg (by simpa using hw)] at h
      refine List.pairwise_cons.mpr ⟨?_, ih (by omega)⟩
      rintro b _ ⟨h1, -⟩
      exact hw h1

/-- Either `v` is never paired with itself, or the escape clause `P` holds outright. -/
theorem pairwise_dup_or {v : Var} {P : Prop} (xs : List Var) (h : 2 ≤ xs.count v → P) :
    xs.Pairwise (fun a b => ¬(a = v ∧ b = v) ∨ P) := by
  by_cases hc : 2 ≤ xs.count v
  · exact pairwise_of_forall_mem fun _ _ _ _ => Or.inr (h hc)
  · exact (pairwise_not_both_eq (by omega)).imp Or.inl

/-- **The converse, for the rewritten system.**  A model of `spliceG v p G` becomes a
model of `G` once `v` is given the value `p`'s right-hand side has.  Note that `p.lhs`
never enters: only `p`'s right-hand side is used. -/
theorem spliceG_backward_models {rho : Assign} {v : Var} {p : Constraint}
    {G : List Constraint}
    (hlhs : ∀ d ∈ G, d.lhs ≠ v)
    (hdis : ∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc)
    (hdup : ∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅)
    (hm : Models rho (spliceG v p G)) :
    Models (upd rho v (rowSum rho p.vars ∪ p.conc)) G := by
  classical
  intro d hd
  have hdl : d.lhs ≠ v := hlhs d hd
  have hsp : Sat rho (spliceC v p d) := by
    refine hm _ ?_
    simp only [spliceG]
    exact List.mem_map_of_mem hd
  have hagree : ∀ w, w ≠ v → upd rho v (rowSum rho p.vars ∪ p.conc) w = rho w :=
    fun w hw => upd_ne rho _ hw
  by_cases hv : v ∈ d.vars
  · rw [spliceC_eq_of_mem hv] at hsp
    have hcd : ∀ u ∈ spliceVars v p.vars d.vars, Disjoint (d.conc ∪ p.conc) (rho u) :=
      fun u hu => hsp.disjoint_conc hu
    refine sat_of ?_ ?_ ?_
    · intro l
      rw [hagree d.lhs hdl, hsp.mem_lhs_iff l]
      constructor
      · rintro (hl | ⟨u, hu, hlu⟩)
        · rcases Finset.mem_union.mp hl with h1 | h2
          · exact Or.inl h1
          · refine Or.inr ⟨v, hv, ?_⟩
            rw [upd_same]
            exact Finset.mem_union_right _ h2
        · rcases mem_spliceVars.mp hu with ⟨_, hup⟩ | ⟨hud, hune⟩
          · refine Or.inr ⟨v, hv, ?_⟩
            rw [upd_same]
            exact Finset.mem_union_left _ (mem_rowSum.mpr ⟨u, hup, hlu⟩)
          · refine Or.inr ⟨u, hud, ?_⟩
            rw [hagree u hune]
            exact hlu
      · rintro (hl | ⟨w, hw, hlw⟩)
        · exact Or.inl (Finset.mem_union_left _ hl)
        · by_cases hwv : w = v
          · rw [hwv, upd_same] at hlw
            rcases Finset.mem_union.mp hlw with h1 | h2
            · obtain ⟨u, hu, hlu⟩ := mem_rowSum.mp h1
              exact Or.inr ⟨u, mem_spliceVars.mpr (Or.inl ⟨hv, hu⟩), hlu⟩
            · exact Or.inl (Finset.mem_union_right _ h2)
          · rw [hagree w hwv] at hlw
            exact Or.inr ⟨w, mem_spliceVars.mpr (Or.inr ⟨hw, hwv⟩), hlw⟩
    · intro w hw
      by_cases hwv : w = v
      · rw [hwv, upd_same, Finset.disjoint_union_right]
        refine ⟨disjoint_rowSum_right ?_, hdis d hd hv⟩
        intro u hu
        exact (Finset.disjoint_union_left.mp
          (hcd u (mem_spliceVars.mpr (Or.inl ⟨hv, hu⟩)))).1
      · rw [hagree w hwv]
        exact (Finset.disjoint_union_left.mp
          (hcd w (mem_spliceVars.mpr (Or.inr ⟨hw, hwv⟩)))).1
    · have hpw := hsp.pairwise_vars
      simp only [spliceVars] at hpw
      rw [List.pairwise_flatMap] at hpw
      refine (hpw.2.and (pairwise_dup_or d.vars (hdup d hd))).imp_of_mem ?_
      rintro a b ha hb ⟨hH, hD⟩
      by_cases hav : a = v
      · by_cases hbv : b = v
        · rcases hD with hne | hemp
          · exact absurd ⟨hav, hbv⟩ hne
          · have hall : ∀ x ∈ p.vars, rho x = ∅ := by
              intro x hx
              refine eq_empty_of_disjoint_self (hH x ?_ x ?_)
              · show x ∈ (if a = v then p.vars else [a]); rw [if_pos hav]; exact hx
              · show x ∈ (if b = v then p.vars else [b]); rw [if_pos hbv]; exact hx
            have hrs : rowSum rho p.vars = ∅ := by
              refine Finset.subset_empty.mp fun l hl => ?_
              obtain ⟨x, hx, hlx⟩ := mem_rowSum.mp hl
              rw [hall x hx] at hlx
              simp at hlx
            rw [hav, hbv, upd_same, hrs, hemp]
            simp
        · rw [hav, upd_same, hagree b hbv, Finset.disjoint_union_left]
          refine ⟨disjoint_rowSum_left ?_, ?_⟩
          · intro u hu
            refine hH u ?_ b ?_
            · show u ∈ (if a = v then p.vars else [a]); rw [if_pos hav]; exact hu
            · show b ∈ (if b = v then p.vars else [b]); rw [if_neg hbv]
              exact List.mem_singleton_self b
          · exact (Finset.disjoint_union_left.mp
              (hcd b (mem_spliceVars.mpr (Or.inr ⟨hb, hbv⟩)))).2
      · by_cases hbv : b = v
        · rw [hbv, upd_same, hagree a hav, Finset.disjoint_union_right]
          refine ⟨disjoint_rowSum_right ?_, ?_⟩
          · intro u hu
            refine hH a ?_ u ?_
            · show a ∈ (if a = v then p.vars else [a]); rw [if_neg hav]
              exact List.mem_singleton_self a
            · show u ∈ (if b = v then p.vars else [b]); rw [if_pos hbv]; exact hu
          · exact ((Finset.disjoint_union_left.mp
              (hcd a (mem_spliceVars.mpr (Or.inr ⟨ha, hav⟩)))).2).symm
        · rw [hagree a hav, hagree b hbv]
          refine hH a ?_ b ?_
          · show a ∈ (if a = v then p.vars else [a]); rw [if_neg hav]
            exact List.mem_singleton_self a
          · show b ∈ (if b = v then p.vars else [b]); rw [if_neg hbv]
            exact List.mem_singleton_self b
  · rw [spliceC_of_not_mem hv] at hsp
    refine (sat_congr ?_ ?_).mp hsp
    · exact (hagree d.lhs hdl).symm
    · intro w hw
      refine (hagree w ?_).symm
      intro hh
      exact hv (hh ▸ hw)

/-- **Eliminating an existential variable by its own definition is conservative.**  A
model of the spliced system extends -- changing only `v` -- to a model of the original
system TOGETHER with the definition that `reduce` discarded.

`hpd` says `p`'s own right-hand side is internally disjoint under `rho`; it is exactly
the disjointness half of `Sat rho p`, and (since `v ∉ p.vars`) exactly what the
conclusion asserts about `p`, so it cannot be weakened.  `hlhs`, `hdis`, `hdup` are
discussed above. -/
theorem spliceG_backward {rho : Assign} {v : Var} {p : Constraint} {G : List Constraint}
    (hpl : p.lhs = v) (hpv : v ∉ p.vars)
    (hpd : (parts rho p).Pairwise Disjoint)
    (hlhs : ∀ d ∈ G, d.lhs ≠ v)
    (hdis : ∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc)
    (hdup : ∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅)
    (hm : Models rho (spliceG v p G)) :
    Models (upd rho v (rowSum rho p.vars ∪ p.conc)) (p :: G) := by
  rw [models_cons]
  refine ⟨?_, spliceG_backward_models hlhs hdis hdup hm⟩
  have hagree : ∀ w ∈ p.vars, upd rho v (rowSum rho p.vars ∪ p.conc) w = rho w :=
    upd_of_not_mem rho v _ hpv
  have hpd' := hpd
  simp only [parts, List.pairwise_cons] at hpd'
  refine sat_of ?_ ?_ ?_
  · intro l
    rw [hpl, upd_same]
    constructor
    · intro hl
      rcases Finset.mem_union.mp hl with h1 | h2
      · obtain ⟨w, hw, hlw⟩ := mem_rowSum.mp h1
        refine Or.inr ⟨w, hw, ?_⟩
        rw [hagree w hw]
        exact hlw
      · exact Or.inl h2
    · rintro (h | ⟨w, hw, hlw⟩)
      · exact Finset.mem_union_right _ h
      · rw [hagree w hw] at hlw
        exact Finset.mem_union_left _ (mem_rowSum.mpr ⟨w, hw, hlw⟩)
  · intro w hw
    rw [hagree w hw]
    exact hpd'.1 _ (List.mem_map_of_mem hw)
  · exact pairwise_disj_congr (fun w hw => (hagree w hw).symm)
      (List.pairwise_map.mp hpd'.2)

/-! ## 5. Exact conservativity, and the partition `reduce` drops -/

/-- **The residual entails exactly the `v`-free consequences of the input.**  Left to
right needs nothing but soundness of the splice; right to left is `spliceG_backward`.
This is the precise sense in which eliminating an ambiguous variable by its own
definition loses nothing. -/
theorem splice_entails_iff {v : Var} {p : Constraint} {G : List Constraint}
    {c : Constraint} (hpl : p.lhs = v) (hGp : Entails G p)
    (hlhs : ∀ d ∈ G, d.lhs ≠ v)
    (hdis : ∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc)
    (hdup : ∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅)
    (hc : v ≠ c.lhs ∧ v ∉ c.vars) :
    Entails (spliceG v p G) c ↔ Entails G c := by
  constructor
  · intro hent rho hm
    exact hent rho (spliceG_models (hGp rho hm) hpl hm)
  · intro hent rho hm
    have hb := spliceG_backward_models hlhs hdis hdup hm
    have hsat := hent _ hb
    refine (sat_congr ?_ ?_).mpr hsat
    · exact (upd_ne rho _ (Ne.symm hc.1)).symm
    · intro w hw
      refine (upd_ne rho _ ?_).symm
      intro hh
      exact hc.2 (hh ▸ hw)

/-- **The dropped partition loses nothing.**  When the saturated set holds two
partitions `p` and `q` with the same ambiguous left-hand side `v`, the first splice
removes every right-hand occurrence of `v`, so the second is a no-op and its content is
emitted nowhere.  Under the three side conditions of `spliceG_backward_models` that
costs nothing: every `v`-free consequence of the input survives in the residual.

Note that `q`, `_hq` and `_hG2` are not used anywhere in the proof -- which is the point
(they are underscore-prefixed only to silence the unused-variable linter).
`q` is entailed by `G`, so it says nothing about the other variables that `G` did not
already say, and the residual keeps all of `G` modulo `v`.

The three extra hypotheses are NOT decoration: `DroppedPartition` below refutes the
statement without `hlhs`, on a satisfiable system with no concrete labels at all. -/
theorem dropped_loses_nothing {v : Var} (G : List Constraint) (p q : Constraint)
    (hp : p.lhs = v) (_hq : q.lhs = v)
    (hG : Entails G p) (_hG2 : Entails G q) (c : Constraint)
    (hc : v ≠ c.lhs ∧ v ∉ c.vars)
    (hlhs : ∀ d ∈ G, d.lhs ≠ v)
    (hdis : ∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc)
    (hdup : ∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅)
    (h : Entails G c) : Entails (spliceG v p G) c :=
  (splice_entails_iff hp hG hlhs hdis hdup hc).mpr h

/-! ## 6. The counterexample that decides the ticket

The statement of `dropped_loses_nothing` WITHOUT the left-hand-side condition -- the
statement the ticket asks about -- is false.  The system below is satisfiable, uses no
concrete labels at all, and satisfies every other hypothesis of `dropped_loses_nothing`
(`v ∉ p.vars`, `hdis` and `hdup` are vacuous when nothing is concrete).

    b <- (v)        the input list, with `v` ambiguous (existential, or minted)
    b <- (y)
    v <- (x)

`G` entails `v <- (y)`, because `v = b = y`; that is the partition `p` the saturated set
offers, and it is the one `reduce` splices with.  `q = v <- (x)` is the second partition
with left-hand side `v` -- after the first splice it has nothing left to rewrite, so it
is a no-op and is never emitted.  The residual is

    b <- (y)        b <- (v) rewritten
    b <- (y)
    v <- (x)        untouched: `reduce` never rewrites a LEFT-hand side

and it no longer entails `x <- (y)`, which the input did.  The information did not
disappear because `q` was dropped -- `q` is still there, verbatim.  It disappeared
because the definition `p` that the splice CONSUMED was discarded while `v` still occurs
in the residual, on the left. -/

namespace DroppedPartition

/-- The ambiguous variable.  The others are `x = 1`, `y = 2`, `b = 3`. -/
def v : Var := 0

/-- The input constraint list: `b <- (v)`, `b <- (y)`, `v <- (x)`. -/
def G : List Constraint := [⟨3, [0], ∅⟩, ⟨3, [2], ∅⟩, ⟨0, [1], ∅⟩]

/-- The partition `reduce` splices with: `v <- (y)`. -/
def p : Constraint := ⟨0, [2], ∅⟩

/-- The partition it drops: `v <- (x)`, the second one with left-hand side `v`. -/
def q : Constraint := ⟨0, [1], ∅⟩

/-- The `v`-free consequence that gets lost: `x <- (y)`, i.e. `x = y`. -/
def c : Constraint := ⟨1, [2], ∅⟩

/-- The refuting assignment: `v` and `x` get `{1}`, `y` and `b` get `∅`. -/
def rhoCE : Assign := fun w => if w ≤ 1 then {1} else ∅

/-- The input is satisfiable -- this is not the degenerate contradictory case. -/
theorem models_empty : Models (fun _ => (∅ : Row)) G :=
  models_of_three ((sat_eqc _ 3 0).mpr rfl) ((sat_eqc _ 3 2).mpr rfl)
    ((sat_eqc _ 0 1).mpr rfl)

/-- The input entails the partition that is spliced in: `v = b = y`. -/
theorem entails_p : Entails G p := by
  intro rho hm
  have h1 : rho 3 = rho 0 := (sat_eqc rho 3 0).mp (hm _ (by simp [G]))
  have h2 : rho 3 = rho 2 := (sat_eqc rho 3 2).mp (hm _ (by simp [G]))
  exact (sat_eqc rho 0 2).mpr (by rw [← h1, h2])

/-- The input entails the partition that is dropped: it is one of the inputs. -/
theorem entails_q : Entails G q := entails_of_mem (by simp [G, q])

/-- The input entails `x = y`, which mentions neither `v` nor anything ambiguous. -/
theorem entails_c : Entails G c := by
  intro rho hm
  have h1 : rho 3 = rho 0 := (sat_eqc rho 3 0).mp (hm _ (by simp [G]))
  have h2 : rho 3 = rho 2 := (sat_eqc rho 3 2).mp (hm _ (by simp [G]))
  have h3 : rho 0 = rho 1 := (sat_eqc rho 0 1).mp (hm _ (by simp [G]))
  exact (sat_eqc rho 1 2).mpr (by rw [← h3, ← h1, h2])

/-- The residual: the occurrence of `v` on the right is gone, the one on the left is
not. -/
theorem splice_eq : spliceG v p G = [⟨3, [2], ∅⟩, ⟨3, [2], ∅⟩, ⟨0, [1], ∅⟩] := by decide

/-- `rhoCE` models the residual: it satisfies `b = y` and `v = x`. -/
theorem models_rhoCE : Models rhoCE (spliceG v p G) := by
  rw [splice_eq]
  exact models_of_three ((sat_eqc rhoCE 3 2).mpr (by decide))
    ((sat_eqc rhoCE 3 2).mpr (by decide)) ((sat_eqc rhoCE 0 1).mpr (by decide))

/-- ...but it does not satisfy `x = y`. -/
theorem not_entails : ¬ Entails (spliceG v p G) c := by
  intro hent
  have h : Sat rhoCE (⟨1, [2], ∅⟩ : Constraint) := hent rhoCE models_rhoCE
  exact absurd ((sat_eqc rhoCE 1 2).mp h) (by decide)

/-- **The ticket's statement 4 is FALSE.**  Every hypothesis of `dropped_loses_nothing`
except `hlhs` holds -- the input is satisfiable, both partitions have left-hand side `v`
and are entailed by the input, `v` occurs in neither `p`'s nor `c`'s right-hand side,
and the two concrete-part conditions are vacuous -- and still the residual fails to
entail a `v`-free consequence of the input.  `hlhs` is exactly what fails: `v` is the
left-hand side of the input constraint `v <- (x)`, which `reduce` copies through
untouched. -/
theorem dropped_can_lose :
    (∃ rho, Models rho G) ∧ p.lhs = v ∧ q.lhs = v ∧ Entails G p ∧ Entails G q ∧
      v ∉ p.vars ∧ (v ≠ c.lhs ∧ v ∉ c.vars) ∧
      (∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc) ∧
      (∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅) ∧
      ¬ (∀ d ∈ G, d.lhs ≠ v) ∧
      Entails G c ∧ ¬ Entails (spliceG v p G) c := by
  refine ⟨⟨_, models_empty⟩, rfl, rfl, entails_p, entails_q, by decide, ⟨by decide, by decide⟩,
    ?_, ?_, ?_, entails_c, not_entails⟩
  · intro d _ _
    show Disjoint d.conc (∅ : Finset Label)
    simp
  · intro d _ _
    rfl
  · intro h
    exact h ⟨0, [1], ∅⟩ (by simp [G]) rfl

end DroppedPartition

/-! ### The other information the rewrite can drop

Independently of the left-hand-side problem, `spliceC` unions the two concrete parts,
and a union does not record that its two halves were disjoint.  The implementation does
not union: it emits `ConcreteRho(lc, con) :: abs.toList.map(VarT(_))`, a right-hand side
with two concrete BLOCKS, and `Rules.rsat_iff_flatten` says the multi-block form asserts
exactly the flattened form PLUS the disjointness of the blocks.  So the following
counterexample is charged to the model, not to `Subst.scala` -- but it is charged to
`Subst.scala` the moment the residual is flattened, which is what `RHS.merge` does, and
`RHS.merge` is where the "Fields appear twice in row" error is raised. -/

namespace ConcreteMerge

/-- `a <- (v, (|1|))` and `v <- ((|1|))`.  Unsatisfiable: `{1}` would have to be
disjoint from `rho v = {1}`. -/
def G : List Constraint := [⟨0, [2], {1}⟩, ⟨2, [], {1}⟩]

/-- The partition spliced in: `v <- ((|1|))`. -/
def p : Constraint := ⟨2, [], {1}⟩

/-- The input has no model at all. -/
theorem G_unsat : ¬ ∃ rho, Models rho G := by
  rintro ⟨rho, hm⟩
  have h1 : Sat rho (⟨0, [2], ({1} : Finset Label)⟩ : Constraint) := hm _ (by simp [G])
  have h2 : rho 2 = ({1} : Finset Label) :=
    (sat_zero rho 2 _).mp (hm _ (by simp [G]))
  have hd : Disjoint ({1} : Finset Label) (rho 2) := h1.disj_one
  rw [h2] at hd
  have he : ({1} : Finset Label) = ∅ := eq_empty_of_disjoint_self hd
  simp at he

/-- The residual: the two concrete parts have merged into one. -/
theorem splice_eq : spliceG 2 p G = [⟨0, [], {1}⟩, ⟨2, [], {1}⟩] := by decide

/-- The residual, unlike the input, has a model. -/
theorem residual_sat : Models (fun _ => ({1} : Finset Label)) (spliceG 2 p G) := by
  rw [splice_eq]
  exact models_of_two ((sat_zero _ 0 _).mpr rfl) ((sat_zero _ 2 _).mpr rfl)

/-- **Merging the concrete parts can mask a contradiction**, and therefore drop
arbitrary consequences: the unsatisfiable input entails `z <- ((|7|))`, the residual does
not.  This is the failure of `hdis`, and by `splice_conc_disjoint_of_models` it can only
happen when the input is already unsatisfiable. -/
theorem merge_masks_contradiction :
    (¬ ∃ rho, Models rho G) ∧ Entails G ⟨1, [], {7}⟩ ∧
      ¬ Entails (spliceG 2 p G) ⟨1, [], {7}⟩ := by
  refine ⟨G_unsat, fun rho hm => absurd ⟨rho, hm⟩ G_unsat, ?_⟩
  intro hent
  have h := (sat_zero _ 1 _).mp (hent _ residual_sat)
  exact absurd h (by decide)

end ConcreteMerge

/-! ## 7. Summary

WHAT IS ESTABLISHED.

* `splice_sat`, `spliceG_models`, `reduce2_models`, `reduce2_entails`.  The rewrite of
  `Subst.reduce`'s second case is SOUND with no side condition: every constraint the
  residual publishes is entailed by the saturated list together with the input list.
  In particular no hypothesis of linearity is needed (a variable occurring both in the
  partition's right-hand side and elsewhere in the constraint is forced empty, and that
  is provable, not assumable), and no hypothesis of concrete disjointness is needed (it
  follows from the two premises).
* `spliceG_backward_models` and `spliceG_backward`.  The exact converse for one splice,
  under three side conditions: `v` is not a left-hand side of the list being rewritten;
  the concrete part of any constraint mentioning `v` is disjoint from the partition's;
  and a right-hand side containing `v` twice forces that concrete part empty.  A model
  of the spliced system then extends -- changing only `v`, to the value the partition's
  own right-hand side has -- to a model of the original system TOGETHER with the
  discarded partition.  `splice_conc_disjoint_of_models` and
  `splice_conc_empty_of_models` show the last two conditions hold at every model of the
  input, so they are free whenever the input is satisfiable.
* `splice_entails_iff`.  Under those conditions the residual entails exactly the
  `v`-free consequences of the input: eliminating an ambiguous variable by its own
  definition is conservative, not merely sound.
* `dropped_loses_nothing`.  Under those conditions the DROPPED partition costs nothing,
  and the proof does not mention it: `q` is entailed by the input, so it constrains the
  other variables no further than the input already does.
* `DroppedPartition.dropped_can_lose`.  WITHOUT the left-hand-side condition the ticket's
  statement is FALSE, on a satisfiable three-constraint system with no concrete labels.
  The diagnosis is sharper than "the dropped partition": `reduce` discards the partition
  it substituted WITH, and never rewrites a left-hand side, so when the ambiguous `v`
  still occurs as a left-hand side of the published list the residual keeps a constraint
  about `v` while losing the equation that tied `v` to everything else.  A `v`-free
  consequence of the input is then no longer entailed.  Two cheap repairs are visible
  from the proof: emit the partition that was used (then `p` is back and
  `splice_entails_iff` applies with `G` replaced by `p :: G`), or apply the guard only
  when `v` occurs in no left-hand side of `cs`.
* `ConcreteMerge.merge_masks_contradiction`.  The union of the concrete parts can turn an
  unsatisfiable input into a satisfiable residual.  In the implementation the two blocks
  are emitted separately, so this is charged to the model (`Rules.rsat_iff_flatten`
  measures the difference exactly) -- until the residual is flattened by `RHS.merge`,
  which is precisely where "Fields appear twice in row" is raised.

WHAT IS NOT ESTABLISHED, AND WHY IT MATTERS.

* THE FIRST CASE OF `reduce` IS OUTSIDE THIS MODEL.  `case (Partition(v, RHSConcr(fs),
  _), cs)` has NO ambiguity guard: it fires for EVERY partition with a fully concrete
  right-hand side, and instead of rewriting `cs` it calls `instantiateType`, which
  commits `v` globally in the substitution.  Nothing in this vocabulary can express
  that.  `Assign` assigns a row to every variable already, so there is no distinction
  here between a variable that may be instantiated and one that may not: no unification
  variable versus skolem (rigid) variable, no `TypeVar.ty`, no reference cells, no
  ambiguity flag.  The distinction is exactly what `Constraints.makeEmpty` guards when
  it refuses with "Cannot unify skolem variable with empty relation", and the first case
  of `reduce` has no such guard on its face.  Whether it is reachable with a skolem `v`
  is a question about the type checker's variable discipline, not about row partitions,
  and it cannot be settled -- in either direction -- by anything in this file.
* The ambiguity guard itself is abstracted to an arbitrary decidable predicate `E` on
  variables; `v.ty.ambiguous` and `es.contains(v)` are not modelled, so nothing here says
  which variables the second case actually fires on.
* Nothing here is about the ORDER of the fold, and the counterexample of section 6 is
  order-sensitive in one direction only: whichever of the two partitions with left-hand
  side `v` is used first, the other becomes a no-op, and the consequence `x = y` is lost
  either way -- but a rewrite that also touched left-hand sides would behave differently,
  and that rewrite is not this one.
* Termination, the size of the residual, and the interaction with `csz` are not modelled.
-/

end Rowpartition
