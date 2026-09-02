/-
# The imperative label check, modelled and proved sound against `Forced`

`Rowpartition.Saturate` closes with a list of gaps, and the last of them reads:

> **THE WEAKEST LINK.**  Nothing anywhere relates the Scala `Constraints.checkLabel` --
> an imperative fixpoint over a `Map[TypeVar, Boolean]`, with a `while (changed)` loop
> and first-clash-wins reporting -- to the Lean inductive `LabelProp.Forced`.

This file closes it in the direction soundness needs.  The shipped compiler runs the
per-concrete-label refutation check BY DEFAULT (`-Dermine.labelCheck` defaults to true),
and `LabelProp` proves that a `Forced`-clash implies unsatisfiability.  What was missing
is that the bits the *code* writes are `Forced` bits.  That is exactly what is proved
here, and `checkLabel_clash_unsat` is the end-to-end statement the compiler needs:

    a run of the algorithm from the empty map that ends in a clash
      ==>  the constraint system has no model.

## What is modelled, and what is deliberately not

The Scala (`Constraints.scala`, `private def checkLabel`) is

    var bits = Map[TypeVar, Boolean](); var changed = true; var clash: Option[String] = None
    while (changed && clash.isEmpty) { changed = false
      for ((v, RHS(abstr, concr)) <- ps if clash.isEmpty) {
        val conBit = concr contains l; val absList = abstr.toList
        val known = absList.map(bits.get)
        val ones = known.count(_ == Some(true)) + (if (conBit) 1 else 0)
        val unknown = absList.filter(!bits.contains(_))
        if (ones > 1) note(..) else {
          if (ones == 1) { setVar(v, true, ..); for (u <- unknown) setVar(u, false, ..) }
          if (bits.get(v) == Some(false)) { if (conBit) note(..)
                                            for (u <- unknown) setVar(u, false, ..) }
          if (ones == 0 && unknown.isEmpty) setVar(v, false, ..)
          if (bits.get(v) == Some(true) && ones == 0) unknown match {
            case Nil => note(..); case u :: Nil => setVar(u, true, ..); case _ => () } } } }

The loop is NOT modelled: iteration order, the `changed` flag and first-clash-wins are
irrelevant to soundness.  What is modelled is ONE WRITE (`AlgoWrite`), guarded by exactly
the Scala condition on the current partial map, together with the invariant `Sound` that
every bit already in the map is `Forced`.  `AlgoRun` is the reflexive-transitive closure.

`AlgoWrite.onesOther` deliberately reproduces a STALENESS in the source: in the `ones == 1`
branch `unknown` is computed BEFORE `setVar(v, true, ..)`, so when `v` is itself a variable
part of its own partition it is still listed in `unknown` and is then written `false`.  The
constructor is therefore stated against the SAME `sigma`, not against `sigma` updated at
`c.lhs`.  `algo_selfPart_refuted` checks that `Forced` really does derive the resulting
contradiction, so the model does not have to be "fixed".

## ONE ADDED HYPOTHESIS -- `algo_ones_two_refuted` needs `c.vars.Nodup`

The statement "`2 <= onesOf` implies `RefutedAt`" is FALSE for a `vars` list with repeats:
if the SAME variable occupies two positions and is known true, `ones` is 2, but `Forced`
has no constructor that fires -- `var_other` requires two DISTINCT parts.  `DupNeeded`
below exhibits the counterexample and PROVES that the system is not `RefutedAt`, so the
hypothesis is not an artefact of the proof.  It is discharged by the source: in
`Constraints.scala` the right-hand side is `case class RHS(abstr: Set[TypeVar], ...)` and
the algorithm reads `abstr.toList`, so the variable-part list of a real partition is
duplicate-free by construction.  Nothing else in this file needs the hypothesis.

## Contents

* §1  `Bits`, `Sound`, `onesOf`, `unknownOf` -- the state of the loop and its guards.
* §2  counting plumbing.
* §3  `AlgoWrite` -- one write of `setVar`, and `algoWrite_forced`: every write is `Forced`.
* §4  `sound_update` -- the invariant is preserved.
* §5  the four clash sites, each proved `RefutedAt`.
* §6  `AlgoRun`, `algoRun_sound`, and the headline `checkLabel_clash_unsat`.
* §7  non-vacuity: two closed systems on which the modelled algorithm really clashes.
* §8  `DupNeeded`: the counterexample forcing the `Nodup` hypothesis of §5.
* §9  Summary: what is established, and what is still not.
-/
import Rowpartition.LabelProp

namespace Rowpartition

/-! ## 1. The state of the loop, and its guards

`Bits` is the Scala `Map[TypeVar, Boolean]`: a partial map from variables to bits, with
`none` standing for "absent".  `Sound` is the loop invariant we maintain, `onesOf` is the
Scala `ones` and `unknownOf` the Scala `unknown`, both read off the current map. -/

/-- The partial map `bits : Map[TypeVar, Boolean]` of `checkLabel`. -/
abbrev Bits := Var → Option Bool

/-- **The loop invariant.**  Every bit present in the map is a bit `Forced` by the system.
This is the only property of the map the soundness argument uses; in particular nothing
here says the map is a fixpoint, or complete, or reachable. -/
def Sound (l : Label) (G : List Constraint) (sigma : Bits) : Prop :=
  ∀ v b, sigma v = some b → Forced l G v b

/-- The Scala `ones`: how many parts of `c` are known to carry `l`.  The variable parts
known true, counted WITH MULTIPLICITY exactly as `known.count(_ == Some(true))` does, plus
one for the concrete part when it carries `l` (`conBit`). -/
def onesOf (l : Label) (sigma : Bits) (c : Constraint) : ℕ :=
  (c.vars.countP (fun u => sigma u = some true)) + (if l ∈ c.conc then 1 else 0)

/-- The Scala `unknown`: `absList.filter(!bits.contains(_))`, the variable parts whose bit
is still absent from the map. -/
def unknownOf (sigma : Bits) (c : Constraint) : List Var :=
  c.vars.filter (fun u => sigma u = none)

/-- Membership in `unknownOf`, unfolded. -/
theorem mem_unknownOf {sigma : Bits} {c : Constraint} {u : Var} :
    u ∈ unknownOf sigma c ↔ u ∈ c.vars ∧ sigma u = none := by
  simp [unknownOf]

/-- `onesOf` when the concrete part carries the label. -/
theorem onesOf_conc {l : Label} {sigma : Bits} {c : Constraint} (hl : l ∈ c.conc) :
    onesOf l sigma c = (c.vars.countP (fun u => sigma u = some true)) + 1 := by
  simp [onesOf, hl]

/-- `onesOf` when it does not. -/
theorem onesOf_not_conc {l : Label} {sigma : Bits} {c : Constraint} (hl : l ∉ c.conc) :
    onesOf l sigma c = c.vars.countP (fun u => sigma u = some true) := by
  simp [onesOf, hl]

/-! ## 2. Counting plumbing

Three facts about `List.countP`, in the exact shapes §3 and §5 consume them. -/

/-- `countP` across a cons whose head satisfies the predicate.  Stated without the `ite`
that `List.countP_cons` leaves behind, so that `omega` can use it. -/
theorem countP_cons_true {p : Var → Bool} {x : Var} (L : List Var) (hx : p x = true) :
    (x :: L).countP p = L.countP p + 1 := by
  rw [List.countP_cons, hx]
  simp

/-- `countP` across a cons whose head does not. -/
theorem countP_cons_false {p : Var → Bool} {x : Var} (L : List Var) (hx : p x = false) :
    (x :: L).countP p = L.countP p := by
  rw [List.countP_cons, hx]
  simp

/-- A positive count yields a witness. -/
theorem exists_of_countP_pos {p : Var → Bool} :
    ∀ {L : List Var}, 0 < L.countP p → ∃ a ∈ L, p a = true := by
  intro L
  induction L with
  | nil => intro h; simp at h
  | cons x L ih =>
      intro h
      cases hx : p x with
      | true => exact ⟨x, by simp, hx⟩
      | false =>
          rw [countP_cons_false L hx] at h
          obtain ⟨a, ha, hpa⟩ := ih h
          exact ⟨a, by simp [ha], hpa⟩

/-- A zero count rules every member out. -/
theorem not_of_countP_eq_zero {p : Var → Bool} {L : List Var} (h : L.countP p = 0)
    {a : Var} (ha : a ∈ L) : p a = false := by
  simpa using List.countP_eq_zero.mp h a ha

/-- A count of at least two, on a DUPLICATE-FREE list, yields two DISTINCT witnesses.
This is the step that fails without `Nodup`, and the reason §5's `algo_ones_two_refuted`
carries that hypothesis. -/
theorem exists_two_of_countP {p : Var → Bool} :
    ∀ {L : List Var}, L.Nodup → 2 ≤ L.countP p →
      ∃ a b, a ∈ L ∧ b ∈ L ∧ a ≠ b ∧ p a = true ∧ p b = true := by
  intro L
  induction L with
  | nil => intro _ h; simp at h
  | cons x L ih =>
      intro hnd h
      have hxL : x ∉ L := (List.nodup_cons.mp hnd).1
      cases hx : p x with
      | true =>
          rw [countP_cons_true L hx] at h
          have hpos : 0 < L.countP p := by omega
          obtain ⟨y, hy, hpy⟩ := exists_of_countP_pos hpos
          exact ⟨x, y, by simp, by simp [hy], fun hxy => hxL (hxy ▸ hy), hx, hpy⟩
      | false =>
          rw [countP_cons_false L hx] at h
          obtain ⟨a, b, ha, hb, hab, hpa, hpb⟩ := ih (List.nodup_cons.mp hnd).2 h
          exact ⟨a, b, by simp [ha], by simp [hb], hab, hpa, hpb⟩

/-! ### Reading `onesOf = 0` and `unknownOf` off the map -/

/-- `ones == 0` forces `conBit` to be false. -/
theorem not_conc_of_onesOf_zero {l : Label} {sigma : Bits} {c : Constraint}
    (h : onesOf l sigma c = 0) : l ∉ c.conc := by
  intro hl
  rw [onesOf_conc hl] at h
  omega

/-- `ones == 0` rules out every variable part being known true. -/
theorem ne_true_of_onesOf_zero {l : Label} {sigma : Bits} {c : Constraint}
    (h : onesOf l sigma c = 0) {u : Var} (hu : u ∈ c.vars) : sigma u ≠ some true := by
  rw [onesOf_not_conc (not_conc_of_onesOf_zero h)] at h
  intro hcon
  have := not_of_countP_eq_zero h hu
  simp [hcon] at this

/-- `ones == 0` together with `unknown.isEmpty`: every variable part is known FALSE.  This
is the premise `all_false` needs. -/
theorem eq_some_false_of_allKnown {l : Label} {sigma : Bits} {c : Constraint}
    (h0 : onesOf l sigma c = 0) (hu : unknownOf sigma c = []) {u : Var} (hmem : u ∈ c.vars) :
    sigma u = some false := by
  cases hs : sigma u with
  | none =>
      have hin : u ∈ unknownOf sigma c := mem_unknownOf.mpr ⟨hmem, hs⟩
      rw [hu] at hin
      simp at hin
  | some x =>
      cases x with
      | false => rfl
      | true => exact absurd hs (ne_true_of_onesOf_zero h0 hmem)

/-- `ones == 0` together with `unknown == [u]`: every variable part OTHER than `u` is known
false.  This is the premise `last_one` needs. -/
theorem eq_some_false_of_last {l : Label} {sigma : Bits} {c : Constraint} {u : Var}
    (h0 : onesOf l sigma c = 0) (hu : unknownOf sigma c = [u]) {w : Var} (hmem : w ∈ c.vars)
    (hne : w ≠ u) : sigma w = some false := by
  cases hs : sigma w with
  | none =>
      have hin : w ∈ unknownOf sigma c := mem_unknownOf.mpr ⟨hmem, hs⟩
      rw [hu] at hin
      simp at hin
      exact absurd hin hne
  | some x =>
      cases x with
      | false => rfl
      | true => exact absurd hs (ne_true_of_onesOf_zero h0 hmem)

/-! ## 3. One write of `setVar`, and its soundness

`AlgoWrite l G sigma v b` : the Scala loop body, at the current map `sigma`, is in a state
where it calls `setVar(v, b, ..)`.  There are exactly five such call sites; each
constructor is one of them, guarded by exactly the source's condition. -/

/-- The five `setVar` calls of `checkLabel`, as a relation on the current map.

* `onesLhs`   -- `if (ones == 1) setVar(v, true, ..)`.
* `onesOther` -- `if (ones == 1) for (u <- unknown) setVar(u, false, ..)`.  Stated against
  the SAME `sigma`, because the source computes `unknown` BEFORE the `setVar(v, true, ..)`
  above it; see the module header.
* `lhsFalse`  -- `if (bits.get(v) == Some(false)) for (u <- unknown) setVar(u, false, ..)`.
* `allKnown`  -- `if (ones == 0 && unknown.isEmpty) setVar(v, false, ..)`.
* `lastOne`   -- `if (bits.get(v) == Some(true) && ones == 0) unknown match { case u :: Nil
  => setVar(u, true, ..) }`. -/
inductive AlgoWrite (l : Label) (G : List Constraint) (sigma : Bits) : Var → Bool → Prop
  /-- Exactly one part carries `l`, so the whole does. -/
  | onesLhs {c} : c ∈ G → onesOf l sigma c = 1 → AlgoWrite l G sigma c.lhs true
  /-- Exactly one part carries `l`, so no still-unknown part does. -/
  | onesOther {c u} : c ∈ G → onesOf l sigma c = 1 → u ∈ unknownOf sigma c →
      AlgoWrite l G sigma u false
  /-- The whole is known not to carry `l`, so no part does. -/
  | lhsFalse {c u} : c ∈ G → sigma c.lhs = some false → u ∈ unknownOf sigma c →
      AlgoWrite l G sigma u false
  /-- No part carries `l` and none is unknown, so the whole does not. -/
  | allKnown {c} : c ∈ G → onesOf l sigma c = 0 → unknownOf sigma c = [] →
      AlgoWrite l G sigma c.lhs false
  /-- The whole carries `l` and exactly one part is still unknown: that part carries it. -/
  | lastOne {c u} : c ∈ G → sigma c.lhs = some true → onesOf l sigma c = 0 →
      unknownOf sigma c = [u] → AlgoWrite l G sigma u true

/-- **Every bit the algorithm writes is a bit unit propagation forces.**  Constructor by
constructor against `LabelProp.Forced`; the only input is the loop invariant, so this holds
at every point of every run, whatever the iteration order.

This is the statement `Saturate`'s "weakest link" bullet says is missing. -/
theorem algoWrite_forced {l : Label} {G : List Constraint} {sigma : Bits} {v : Var}
    {b : Bool} (h : Sound l G sigma) (hw : AlgoWrite l G sigma v b) : Forced l G v b := by
  cases hw with
  | @onesLhs c hc h1 =>
      -- the single part carrying `l` is either the concrete one or a variable known true
      by_cases hl : l ∈ c.conc
      · exact .conc_lhs hc hl
      · rw [onesOf_not_conc hl] at h1
        have hpos : 0 < c.vars.countP (fun u => sigma u = some true) := by omega
        obtain ⟨u, hu, hpu⟩ := exists_of_countP_pos hpos
        simp only [decide_eq_true_eq] at hpu
        exact .var_lhs hc hu (h u true hpu)
  | @onesOther c _u hc h1 hu =>
      obtain ⟨humem, hun⟩ := mem_unknownOf.mp hu
      by_cases hl : l ∈ c.conc
      · exact .conc_var hc hl humem
      · rw [onesOf_not_conc hl] at h1
        have hpos : 0 < c.vars.countP (fun x => sigma x = some true) := by omega
        obtain ⟨w, hw, hpw⟩ := exists_of_countP_pos hpos
        simp only [decide_eq_true_eq] at hpw
        -- `u` is unknown and `w` is known true, so they are genuinely different parts
        have hne : w ≠ v := by
          intro hwu
          rw [hwu, hun] at hpw
          simp at hpw
        exact .var_other hc hw humem hne (h w true hpw)
  | @lhsFalse c _u hc hv hu =>
      exact .lhs_false hc (mem_unknownOf.mp hu).1 (h c.lhs false hv)
  | @allKnown c hc h0 hu =>
      refine .all_false hc (not_conc_of_onesOf_zero h0) ?_
      intro w hw
      exact h w false (eq_some_false_of_allKnown h0 hu hw)
  | @lastOne c _u hc hlhs h0 hu =>
      have humem : v ∈ c.vars := (mem_unknownOf.mp (by rw [hu]; simp)).1
      refine .last_one hc (not_conc_of_onesOf_zero h0) humem (h c.lhs true hlhs) ?_
      intro w hw hne
      exact h w false (eq_some_false_of_last h0 hu hw hne)

/-! ## 4. The invariant is preserved -/

/-- The empty map -- `var bits = Map[TypeVar, Boolean]()` -- satisfies the invariant. -/
theorem sound_empty {l : Label} {G : List Constraint} : Sound l G (fun _ => none) := by
  intro v b hb
  exact absurd hb (by simp)

/-- Installing a `Forced` bit preserves the invariant.  (`Function.update` is the Scala
`bits = bits + (v -> b)`.) -/
theorem sound_update {l : Label} {G : List Constraint} {sigma : Bits} {v : Var} {b : Bool}
    (h : Sound l G sigma) (hf : Forced l G v b) :
    Sound l G (Function.update sigma v (some b)) := by
  intro w x hw
  rw [Function.update_apply] at hw
  by_cases hwv : w = v
  · subst hwv
    rw [if_pos rfl] at hw
    have : b = x := Option.some_inj.mp hw
    exact this ▸ hf
  · rw [if_neg hwv] at hw
    exact h w x hw

/-- The two together: performing one write of the algorithm preserves the invariant.  This
is the induction step of every run. -/
theorem algoWrite_sound_update {l : Label} {G : List Constraint} {sigma : Bits} {v : Var}
    {b : Bool} (h : Sound l G sigma) (hw : AlgoWrite l G sigma v b) :
    Sound l G (Function.update sigma v (some b)) :=
  sound_update h (algoWrite_forced h hw)

/-! ## 5. The clash sites

`checkLabel` reports a contradiction in four places: `setVar` finding a DIFFERENT value
already present, and the three `note(..)` calls that are not `setVar`.  Each is proved to
imply `LabelProp.RefutedAt`, hence (via `refuted_unsat`) unsatisfiability. -/

/-- A variable forced both ways is a refutation, whichever way round the bit is. -/
theorem refutedAt_of_forced_both {l : Label} {G : List Constraint} {v : Var} {b : Bool}
    (h1 : Forced l G v b) (h2 : Forced l G v (!b)) : RefutedAt l G := by
  cases b with
  | false => exact ⟨v, h2, h1⟩
  | true => exact ⟨v, h1, h2⟩

/-- **Clash site 1, in its general form.**  `setVar(v, b, ..)` finds `b0 != b` already in
the map.  The write may have been computed against a STALE map `sigma` while the old value
is read from a later map `tau`; both need only satisfy the invariant.  This generality is
what makes the staleness of `onesOther` harmless. -/
theorem algo_clash_refuted_of_sound {l : Label} {G : List Constraint} {sigma tau : Bits}
    {v : Var} {b : Bool} (h : Sound l G sigma) (h' : Sound l G tau)
    (hw : AlgoWrite l G sigma v b) (hold : tau v = some (!b)) : RefutedAt l G :=
  refutedAt_of_forced_both (algoWrite_forced h hw) (h' v (!b) hold)

/-- **Clash site 1.**  `setVar` finds the opposite bit already recorded. -/
theorem algo_clash_refuted {l : Label} {G : List Constraint} {sigma : Bits} {v : Var}
    {b : Bool} (h : Sound l G sigma) (hw : AlgoWrite l G sigma v b)
    (hold : sigma v = some (!b)) : RefutedAt l G :=
  algo_clash_refuted_of_sound h h hw hold

/-- **Clash site 2.**  `if (ones > 1) note("two parts of one partition both contain it")`.

Two parts carry `l`: one of them is forced true, and the same variable is forced false by
`conc_var` (if the other is the concrete part) or `var_other` (if it is a variable part).

REQUIRES `c.vars.Nodup`, and genuinely so: see `DupNeeded` in §8.  In the source the
variable parts come from `RHS(abstr: Set[TypeVar], ..)` via `abstr.toList`, so the list is
duplicate-free by construction. -/
theorem algo_ones_two_refuted {l : Label} {G : List Constraint} {sigma : Bits}
    (h : Sound l G sigma) {c : Constraint} (hc : c ∈ G) (hnd : c.vars.Nodup)
    (h2 : 2 ≤ onesOf l sigma c) : RefutedAt l G := by
  by_cases hl : l ∈ c.conc
  · -- the concrete part is one of them, so some variable part is the other
    rw [onesOf_conc hl] at h2
    have hpos : 0 < c.vars.countP (fun u => sigma u = some true) := by omega
    obtain ⟨u, hu, hpu⟩ := exists_of_countP_pos hpos
    simp only [decide_eq_true_eq] at hpu
    exact ⟨u, h u true hpu, .conc_var hc hl hu⟩
  · -- two DISTINCT variable parts are known true, and each excludes the other
    rw [onesOf_not_conc hl] at h2
    obtain ⟨a, b, ha, hb, hab, hpa, hpb⟩ := exists_two_of_countP hnd h2
    simp only [decide_eq_true_eq] at hpa hpb
    exact ⟨a, h a true hpa, .var_other hc hb ha (Ne.symm hab) (h b true hpb)⟩

/-- **Clash site 3.**  `if (bits.get(v) == Some(false)) if (conBit) note(..)`: the whole is
known not to carry `l`, but the concrete part does. -/
theorem algo_lhs_false_conc_refuted {l : Label} {G : List Constraint} {sigma : Bits}
    (h : Sound l G sigma) {c : Constraint} (hc : c ∈ G) (hv : sigma c.lhs = some false)
    (hl : l ∈ c.conc) : RefutedAt l G :=
  ⟨c.lhs, .conc_lhs hc hl, h c.lhs false hv⟩

/-- **Clash site 4.**  `if (bits.get(v) == Some(true) && ones == 0) unknown match { case Nil
=> note("the whole contains it but no part can") }`: the whole carries `l`, every part is
known, and none of them carries it. -/
theorem algo_last_none_refuted {l : Label} {G : List Constraint} {sigma : Bits}
    (h : Sound l G sigma) {c : Constraint} (hc : c ∈ G) (hv : sigma c.lhs = some true)
    (h0 : onesOf l sigma c = 0) (hu : unknownOf sigma c = []) : RefutedAt l G := by
  refine ⟨c.lhs, h c.lhs true hv, .all_false hc (not_conc_of_onesOf_zero h0) ?_⟩
  intro w hw
  exact h w false (eq_some_false_of_allKnown h0 hu hw)

/-- **The staleness is sound.**  When `c.lhs` is a variable part of `c`'s own right-hand
side and is still unknown, the `ones == 1` branch writes it `true` and then -- because
`unknown` was computed one line earlier -- writes it `false`.  `Forced` derives BOTH, so
the clash the algorithm reports there is a genuine refutation, not an artefact of the
stale read.  (Semantically: a variable that is a part of its own partition is forced
empty, so it cannot also carry `l`.) -/
theorem algo_selfPart_refuted {l : Label} {G : List Constraint} {sigma : Bits}
    (h : Sound l G sigma) {c : Constraint} (hc : c ∈ G) (h1 : onesOf l sigma c = 1)
    (hself : c.lhs ∈ unknownOf sigma c) : RefutedAt l G :=
  ⟨c.lhs, algoWrite_forced h (.onesLhs hc h1),
    algoWrite_forced h (.onesOther hc h1 hself)⟩

/-! ## 6. The chain: a whole run, and the theorem the compiler needs -/

/-- The reflexive-transitive closure of `AlgoWrite`: a sequence of `setVar` calls, each
guarded by the source's condition on the map it actually sees.

Note this relation is deliberately LARGER than the source's control flow: it imposes no
iteration order, and it does not require the written key to be absent (`setVar` only
inserts when `bits.get(v)` is `None`).  A larger run relation makes every theorem below
cover MORE states, which is the safe direction for a soundness claim. -/
inductive AlgoRun (l : Label) (G : List Constraint) : Bits → Bits → Prop
  /-- Zero writes. -/
  | refl (sigma : Bits) : AlgoRun l G sigma sigma
  /-- One write, then the rest of the run. -/
  | step {sigma tau : Bits} {v : Var} {b : Bool} (hw : AlgoWrite l G sigma v b)
      (hr : AlgoRun l G (Function.update sigma v (some b)) tau) : AlgoRun l G sigma tau

/-- A convenience form of `AlgoRun.step` that lets the successor map be given by an
explicit table together with a proof that it is the update.  Used in §7. -/
theorem AlgoRun.step' {l : Label} {G : List Constraint} {sigma tau rho : Bits} {v : Var}
    {b : Bool} (hw : AlgoWrite l G sigma v b) (heq : Function.update sigma v (some b) = tau)
    (hr : AlgoRun l G tau rho) : AlgoRun l G sigma rho :=
  .step hw (heq ▸ hr)

/-- The invariant survives a whole run.  Stated as an implication so the induction on the
run does not have to generalise the invariant by hand. -/
theorem algoRun_sound_aux {l : Label} {G : List Constraint} {sigma tau : Bits}
    (hr : AlgoRun l G sigma tau) : Sound l G sigma → Sound l G tau := by
  induction hr with
  | refl _ => exact id
  | step hw _ ih => exact fun h => ih (algoWrite_sound_update h hw)

/-- **The invariant survives a whole run.** -/
theorem algoRun_sound {l : Label} {G : List Constraint} {sigma sigma2 : Bits}
    (h : Sound l G sigma) (hr : AlgoRun l G sigma sigma2) : Sound l G sigma2 :=
  algoRun_sound_aux hr h

/-- **THE HEADLINE.**  If the algorithm, started from the empty map as `checkLabel` starts
it, reaches a state where `setVar` clashes, then the constraint system has no model.

This is the chain the shipped compiler relies on and did not have:

    empty map is Sound            (`sound_empty`)
      -> every write is Forced    (`algoWrite_forced`)
      -> Sound is an invariant    (`algoRun_sound`)
      -> a clash is RefutedAt     (`algo_clash_refuted`)
      -> Refuted implies unsat    (`LabelProp.refuted_unsat`).

Contrapositive: a SATISFIABLE system never reaches a clash, so `-Dermine.labelCheck=true`
cannot reject a program whose row constraints are satisfiable. -/
theorem checkLabel_clash_unsat {l : Label} {G : List Constraint} {sigma : Bits} {v : Var}
    {b : Bool} (hr : AlgoRun l G (fun _ => none) sigma) (hw : AlgoWrite l G sigma v b)
    (hold : sigma v = some (!b)) : ¬ ∃ rho, Models rho G :=
  refuted_unsat ⟨l, algo_clash_refuted (algoRun_sound sound_empty hr) hw hold⟩

/-- The same statement in the form the check is actually used in: no false rejections. -/
theorem checkLabel_no_clash_of_sat {l : Label} {G : List Constraint} {sigma : Bits}
    {v : Var} {b : Bool} (hsat : ∃ rho, Models rho G)
    (hr : AlgoRun l G (fun _ => none) sigma) (hw : AlgoWrite l G sigma v b) :
    sigma v ≠ some (!b) :=
  fun hold => checkLabel_clash_unsat hr hw hold hsat

/-- The other three clash sites, reached from the empty map, are unsatisfiability too. -/
theorem checkLabel_ones_two_unsat {l : Label} {G : List Constraint} {sigma : Bits}
    (hr : AlgoRun l G (fun _ => none) sigma) {c : Constraint} (hc : c ∈ G)
    (hnd : c.vars.Nodup) (h2 : 2 ≤ onesOf l sigma c) : ¬ ∃ rho, Models rho G :=
  refuted_unsat ⟨l, algo_ones_two_refuted (algoRun_sound sound_empty hr) hc hnd h2⟩

/-- `if (bits.get(v) == Some(false)) if (conBit) note(..)`, from the empty map. -/
theorem checkLabel_lhs_false_conc_unsat {l : Label} {G : List Constraint} {sigma : Bits}
    (hr : AlgoRun l G (fun _ => none) sigma) {c : Constraint} (hc : c ∈ G)
    (hv : sigma c.lhs = some false) (hl : l ∈ c.conc) : ¬ ∃ rho, Models rho G :=
  refuted_unsat ⟨l, algo_lhs_false_conc_refuted (algoRun_sound sound_empty hr) hc hv hl⟩

/-- `unknown match { case Nil => note(..) }`, from the empty map. -/
theorem checkLabel_last_none_unsat {l : Label} {G : List Constraint} {sigma : Bits}
    (hr : AlgoRun l G (fun _ => none) sigma) {c : Constraint} (hc : c ∈ G)
    (hv : sigma c.lhs = some true) (h0 : onesOf l sigma c = 0)
    (hu : unknownOf sigma c = []) : ¬ ∃ rho, Models rho G :=
  refuted_unsat ⟨l, algo_last_none_refuted (algoRun_sound sound_empty hr) hc hv h0 hu⟩

/-! ## 7. Non-vacuity: systems on which the modelled algorithm really clashes

`checkLabel_clash_unsat` would be worth nothing if `AlgoRun` reached no clashing state.
Two closed witnesses follow.  Every guard is discharged by `decide`, so these are
executions of the modelled algorithm, not re-derivations by hand. -/

/-! ### 7.1 The minimal clash: two constraints, two writes, then the clash

    a <- (b, (|0|))     -- the whole carries label 0 via its concrete part, so `b` may not
    b <- (|0|)          -- but `b` is pinned to a row that does

The loop, at label `0`, starting from the empty map:
`cA` has `ones == 1` (the concrete part), so it writes `a := true` and then `b := false`;
`cB` has `ones == 1` as well and calls `setVar(b, true, ..)`, which finds `false`. -/
namespace MinClash

/-- `a <- (b, (|0|))`, with `a = 0` and `b = 1`. -/
def cA : Constraint := ⟨0, [1], {0}⟩
/-- `b <- (|0|)`. -/
def cB : Constraint := ⟨1, [], {0}⟩
/-- The system. -/
def G : List Constraint := [cA, cB]

/-- The empty map, `var bits = Map()`. -/
def s0 : Bits := fun _ => none
/-- After `setVar(a, true, ..)`. -/
def s1 : Bits := fun v => if v = 0 then some true else none
/-- After `setVar(b, false, ..)`. -/
def s2 : Bits := fun v => if v = 0 then some true else if v = 1 then some false else none

/-- The first write really does produce `s1`. -/
theorem upd01 : Function.update s0 0 (some true) = s1 := by
  funext v
  by_cases h : v = 0 <;> simp [s0, s1, h]

/-- The second write really does produce `s2`. -/
theorem upd12 : Function.update s1 1 (some false) = s2 := by
  funext v
  by_cases h : v = 1 <;> simp [s1, s2, h]

/-- Write 1: `ones == 1` on `cA` (its concrete part carries the label), so `a := true`. -/
theorem w1 : AlgoWrite 0 G s0 0 true := .onesLhs (c := cA) (by simp [G]) (by decide)

/-- Write 2: the same branch's `for (u <- unknown) setVar(u, false, ..)`, so `b := false`. -/
theorem w2 : AlgoWrite 0 G s1 1 false :=
  .onesOther (c := cA) (by simp [G]) (by decide) (by decide)

/-- The clashing write: `cB` also has `ones == 1`, so it calls `setVar(b, true, ..)`. -/
theorem wc : AlgoWrite 0 G s2 1 true := .onesLhs (c := cB) (by simp [G]) (by decide)

/-- The two-step run from the empty map. -/
theorem run : AlgoRun 0 G s0 s2 :=
  .step' w1 upd01 (.step' w2 upd12 (.refl _))

/-- **The algorithm clashes here**, and the clash is genuine: `checkLabel_clash_unsat`
turns this run into a proof that the system has no model. -/
theorem unsat : ¬ ∃ rho, Models rho G :=
  checkLabel_clash_unsat run wc (by decide)

end MinClash

/-! ### 7.2 The shipped compiler's own example, run end to end

`LabelProp.Unsound01` is `core/examples/incomplete/unsound01_keyed_halves.e`, the program
the shipped solver wrongly accepts.  `LabelProp` refutes it by exhibiting a `Forced`
derivation.  Here the SAME refutation is obtained by running the modelled algorithm from
the empty map: five writes, and then `allKnown` on `t <- (l, s)` calls `setVar(t, false)`
against a map that already holds `t = true`.

    lt := true   (cLeft has ones == 1)      l := false   (same branch, `unknown`)
    rt := true   (cRight has ones == 1)     s := false   (same branch, `unknown`)
    t  := true   (cPin has ones == 1)
    -- second pass: cSplit now has ones == 0 and unknown == [], so setVar(t, false) -- clash
-/
namespace Unsound01Run

open Unsound01 (cSplit cLeft cRight cPin)

/-- The empty map. -/
def r0 : Bits := fun _ => none
/-- After `setVar(lt, true, ..)`. -/
def r1 : Bits := fun v => if v = 3 then some true else none
/-- After `setVar(l, false, ..)`. -/
def r2 : Bits := fun v => if v = 3 then some true else if v = 1 then some false else none
/-- After `setVar(rt, true, ..)`. -/
def r3 : Bits := fun v =>
  if v = 3 then some true else if v = 1 then some false else
  if v = 4 then some true else none
/-- After `setVar(s, false, ..)`. -/
def r4 : Bits := fun v =>
  if v = 3 then some true else if v = 1 then some false else
  if v = 4 then some true else if v = 2 then some false else none
/-- After `setVar(t, true, ..)`: the state in which the second pass clashes. -/
def r5 : Bits := fun v =>
  if v = 3 then some true else if v = 1 then some false else
  if v = 4 then some true else if v = 2 then some false else
  if v = 0 then some true else none

/-- `lt := true`. -/
theorem upd01 : Function.update r0 3 (some true) = r1 := by
  funext v
  by_cases h : v = 3 <;> simp [r0, r1, h]

/-- `l := false`. -/
theorem upd12 : Function.update r1 1 (some false) = r2 := by
  funext v
  by_cases h : v = 1 <;> simp [r1, r2, h]

/-- `rt := true`. -/
theorem upd23 : Function.update r2 4 (some true) = r3 := by
  funext v
  by_cases h : v = 4 <;> simp [r2, r3, h]

/-- `s := false`. -/
theorem upd34 : Function.update r3 2 (some false) = r4 := by
  funext v
  by_cases h : v = 2 <;> simp [r3, r4, h]

/-- `t := true`. -/
theorem upd45 : Function.update r4 0 (some true) = r5 := by
  funext v
  by_cases h : v = 0 <;> simp [r4, r5, h]

/-- `cLeft` has `ones == 1`: its concrete part is the key. -/
theorem v1 : AlgoWrite 0 Unsound01.G r0 3 true :=
  .onesLhs (c := cLeft) (by simp [Unsound01.G]) (by decide)

/-- ...so the left group cannot carry the key. -/
theorem v2 : AlgoWrite 0 Unsound01.G r1 1 false :=
  .onesOther (c := cLeft) (by simp [Unsound01.G]) (by decide) (by decide)

/-- `cRight`, the mirror image. -/
theorem v3 : AlgoWrite 0 Unsound01.G r2 4 true :=
  .onesLhs (c := cRight) (by simp [Unsound01.G]) (by decide)

/-- ...so the right group cannot either. -/
theorem v4 : AlgoWrite 0 Unsound01.G r3 2 false :=
  .onesOther (c := cRight) (by simp [Unsound01.G]) (by decide) (by decide)

/-- `cPin` pins the ledger to a row that carries the key. -/
theorem v5 : AlgoWrite 0 Unsound01.G r4 0 true :=
  .onesLhs (c := cPin) (by simp [Unsound01.G]) (by decide)

/-- The clashing write: on the second pass `t <- (l, s)` has `ones == 0` and nothing
unknown, so `setVar(t, false, ..)` fires against a map that already holds `t = true`. -/
theorem vc : AlgoWrite 0 Unsound01.G r5 0 false :=
  .allKnown (c := cSplit) (by simp [Unsound01.G]) (by decide) (by decide)

/-- The five-write run from the empty map. -/
theorem run : AlgoRun 0 Unsound01.G r0 r5 :=
  .step' v1 upd01 (.step' v2 upd12 (.step' v3 upd23 (.step' v4 upd34
    (.step' v5 upd45 (.refl _)))))

/-- **The modelled algorithm refutes the shipped compiler's own counterexample.**  Same
conclusion as `Unsound01.unsat`, but reached by running the code's fixpoint rather than by
hand-picking a `Forced` derivation. -/
theorem unsat : ¬ ∃ rho, Models rho Unsound01.G :=
  checkLabel_clash_unsat run vc (by decide)

end Unsound01Run

/-! ## 8. Why `algo_ones_two_refuted` needs `Nodup`

The `ones > 1` guard counts POSITIONS, as `known.count(_ == Some(true))` does.  If one
variable occupies two positions of the same right-hand side and is known true, the count
is 2 while there is only one part, and `Forced` cannot fire: `var_other` demands two
DISTINCT parts and `conc_var` demands a concrete part carrying the label.

    a <- (b, b)      -- one variable, twice
    b <- (|0|)       -- and it carries the label

is exactly that.  The map `{b |-> true}` satisfies the invariant, `onesOf` is 2 on the
first constraint -- and the system is NOT `RefutedAt`, proved below by characterising every
derivable fact.  So the hypothesis is not slack in the proof; it is a real side condition,
discharged by the source's `RHS(abstr: Set[TypeVar], ..)` / `abstr.toList`.

(The system here IS unsatisfiable -- a repeated part is forced empty, `Basic`'s
`Sat.eq_empty_of_dup` -- which is precisely the reasoning `Forced` does not do.) -/
namespace DupNeeded

/-- `a <- (b, b)`, with `a = 0` and `b = 1`: one variable in two positions. -/
def cDup : Constraint := ⟨0, [1, 1], ∅⟩
/-- `b <- (|0|)`. -/
def cPin : Constraint := ⟨1, [], {0}⟩
/-- The system. -/
def G : List Constraint := [cDup, cPin]

/-- The map the loop reaches: `b` is known true. -/
def sigma : Bits := fun v => if v = 1 then some true else none

/-- It satisfies the invariant. -/
theorem sound : Sound 0 G sigma := by
  intro v b hvb
  by_cases hv : v = 1
  · subst hv
    cases b with
    | true => exact .conc_lhs (c := cPin) (by simp [G]) (by decide)
    | false => simp [sigma] at hvb
  · simp [sigma, hv] at hvb

/-- And the `ones > 1` guard fires on `cDup`: two POSITIONS are known true. -/
theorem ones_two : 2 ≤ onesOf 0 sigma cDup := by decide

/-- But `cDup.vars` is not duplicate-free. -/
theorem not_nodup : ¬ cDup.vars.Nodup := by decide

/-- Every fact `Forced` can derive here is positive.  Induction on the derivation: the
three constructors with a `false` conclusion each need a premise that is not available --
`conc_var` a concrete part over a nonempty variable list, `var_other` two DISTINCT
variable parts, `all_false` and `lhs_false` a `false` fact already in hand. -/
theorem forced_true {v : Var} {y : Bool} (h : Forced 0 G v y) : y = true := by
  induction h with
  | @conc_lhs c hc hl => rfl
  | @conc_var c v hc hl hv =>
      exfalso
      have hcc : c = cDup ∨ c = cPin := by simpa [G] using hc
      rcases hcc with rfl | rfl
      · simp [cDup] at hl
      · simp [cPin] at hv
  | @var_lhs c v hc hv _ ih => rfl
  | @var_other c v w hc hv hw hne _ ih =>
      exfalso
      have hcc : c = cDup ∨ c = cPin := by simpa [G] using hc
      rcases hcc with rfl | rfl
      · have h1 : v = 1 := by simpa [cDup] using hv
        have h2 : w = 1 := by simpa [cDup] using hw
        exact hne (h1.trans h2.symm)
      · simp [cPin] at hv
  | @lhs_false c v hc hv _ ih => exact absurd ih (by simp)
  | @all_false c hc hl _ ih =>
      exfalso
      have hcc : c = cDup ∨ c = cPin := by simpa [G] using hc
      rcases hcc with rfl | rfl
      · exact absurd (ih 1 (by simp [cDup])) (by simp)
      · simp [cPin] at hl
  | @last_one c v₀ hc hl hv _ _ ihlhs ih => rfl

/-- **So the system is not refuted**, although `ones > 1` fires: `algo_ones_two_refuted`
without `Nodup` would be false, with this as the counterexample. -/
theorem not_refutedAt : ¬ RefutedAt 0 G := by
  rintro ⟨v, -, hf⟩
  exact Bool.noConfusion (forced_true hf)

/-- The counterexample, assembled: the invariant holds, the guard fires, and there is no
refutation. -/
theorem nodup_needed :
    Sound 0 G sigma ∧ cDup ∈ G ∧ 2 ≤ onesOf 0 sigma cDup ∧ ¬ RefutedAt 0 G :=
  ⟨sound, by simp [G], ones_two, not_refutedAt⟩

end DupNeeded

/-! ## 9. Summary

### What this module establishes

* `algoWrite_forced` -- every bit `Constraints.checkLabel` writes with `setVar` is a bit
  `LabelProp.Forced` derives, given only that the bits already in `bits` are.  All five
  `setVar` call sites, each guarded by exactly the source's condition.
* `sound_empty`, `sound_update`, `algoWrite_sound_update`, `algoRun_sound` -- "every bit in
  the map is `Forced`" is an invariant of the whole fixpoint, from the initial empty map.
* The four clash sites are each a genuine refutation: `algo_clash_refuted` (a `setVar`
  meeting the opposite bit), `algo_ones_two_refuted` (`ones > 1`),
  `algo_lhs_false_conc_refuted` (`bits.get(v) == Some(false)` with `conBit`) and
  `algo_last_none_refuted` (`bits.get(v) == Some(true)`, `ones == 0`, `unknown == Nil`).
* `algo_selfPart_refuted` -- the deliberate STALENESS of the `ones == 1` branch (it
  computes `unknown` before `setVar(v, true, ..)`, so a self-referential partition writes
  its own left-hand side both ways) yields a contradiction `Forced` really does derive.
* `checkLabel_clash_unsat` -- THE CHAIN: a run from the empty map ending in a clash proves
  the constraint system has no model.  `checkLabel_no_clash_of_sat` is the contrapositive
  the compiler depends on: with `-Dermine.labelCheck` on, a SATISFIABLE system is never
  rejected.  Companion forms for the other three sites are stated alongside.
* `MinClash` and `Unsound01Run` -- the theorem is not vacuous: two closed systems on which
  the modelled algorithm reaches a clash, all guards discharged by `decide`.  The second is
  `core/examples/incomplete/unsound01_keyed_halves.e`, refuted here by RUNNING the model.

### One hypothesis added to the requested statements

`algo_ones_two_refuted` carries `hnd : c.vars.Nodup`.  Without it the statement is FALSE;
`DupNeeded.nodup_needed` is the counterexample -- a system with a repeated variable part
where the invariant holds, `2 <= onesOf` holds, and `RefutedAt` provably does not.  The
hypothesis is discharged in the real compiler by `case class RHS(abstr: Set[TypeVar], ..)`
and the algorithm's `abstr.toList`, which cannot repeat.  No other result here needs it.

### What is NOT established

* **Termination is not proved.**  Nothing here says the `while (changed && clash.isEmpty)`
  loop halts, or bounds the number of writes.  (It does, by a trivial measure -- the map
  only grows and the variable set is finite -- but that argument is not formalised, and
  the surrounding saturation may not terminate at all: see `Divergence`,
  `ResGuardDiverge`.)
* **COMPLETENESS is not proved, in either of two senses.**  (i) The algorithm stops at the
  first clash and its iteration order is fixed, so a `Forced` clash may exist that no
  `AlgoRun` reaches; nothing here says the fixpoint derives every `Forced` fact.  (ii)
  `Forced` itself is incomplete for unsatisfiability by design --
  `LabelProp.Incomplete.unsat_and_not_refuted` exhibits an unsatisfiable system it does not
  refute.  So "no clash" means nothing, and this module claims nothing about it.
* **This is a model READ FROM THE SOURCE, not an extraction of it.**  `AlgoWrite` was
  written by transcribing `Constraints.checkLabel` by hand.  Nothing mechanically checks
  that the Scala still matches; an edit to that method silently invalidates the
  correspondence.
* **The control flow is not modelled** -- `changed`, the iteration order over `ps`, the
  `if (clash.isEmpty)` guards, first-clash-wins, and WHICH `note(..)` message is produced.
  `AlgoRun` is deliberately LARGER than the real control flow (any order, and it permits
  rewriting a key `setVar` would only insert), which is the safe direction for soundness
  and useless for anything else.
* **The passage from the compiler's data to `G` is not modelled**: neither `checkLabels`'s
  outer loop over concrete labels, nor `Q.PQueue.build`'s construction of the partition
  list (`Saturate` records that it mints variables), nor the `TypeVar`-to-`Var` naming.
* Nothing here licenses running the check on the SATURATED set rather than the input; that
  is `Saturate.refute_saturated_sound`, a separate statement about a different set.
-/

end Rowpartition
