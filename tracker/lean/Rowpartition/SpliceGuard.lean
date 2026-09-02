/-
# Guarding `Subst.reduce`'s second case: the licence for the repair

`Rowpartition.Splice` models the second case of `Subst.reduce` (`Subst.scala`,
`def reduce(lc, csz, es, ps)`) as `spliceC` / `spliceG` / `reduce2`, and settles it in
two halves.  The rewrite is SOUND with no side condition at all (`splice_sat`,
`reduce2_models`).  It is CONSERVATIVE -- the residual entails every consequence of the
input that does not mention the eliminated variable -- under three side conditions
(`splice_entails_iff`).  And the statement WITHOUT those conditions is FALSE:
`DroppedPartition.dropped_can_lose` is a satisfiable three-constraint, four-variable
system, with no concrete labels anywhere, on which the published residual fails to
entail a consequence of the input.  The condition that fails there is `hlhs`: the
ambiguous variable `v` still occurs as a LEFT-hand side of the list being rewritten, and
`reduce` discards the definition it substituted WITH while never rewriting a left-hand
side, so the residual keeps a constraint about `v` and loses the equation that tied `v`
to the rest of the system.

This file is the LICENCE FOR A PROPOSED CHANGE to `Subst.reduce`: before splicing, TEST
the three side conditions and SKIP the splice when they do not hold.  All three are
syntactic -- they mention only left-hand sides, variable occurrences and concrete parts
-- so the test is implementable exactly as stated.  `SpliceOK` is that test, with a
`Decidable` instance; `reduce2G` is `reduce`'s fold with the test in front of the splice.

## Headline

* `reduce2G_models`, `reduce2G_entails`: the guard costs no soundness.  Every constraint
  the guarded residual publishes is still entailed by the saturated list together with
  the input list.
* `reduce2G_backward`: the guard BUYS conservativity, for the whole fold and with no
  hypothesis whatever on the input.  Every model of the guarded residual extends -- by
  changing only variables the ambiguity guard `E` admits -- to a model of the original
  input list.  The single-step lemma is `Splice.spliceG_backward_models`; the fold
  composes the successive undo-updates, and because each update touches a variable
  satisfying `E`, the composite still changes only `E`-variables.
* `reduce2G_preserves_entailment`: the corollary the compiler cares about, and it is
  UNCONDITIONAL.  A consequence of the input none of whose variables the ambiguity guard
  admits is still a consequence of the guarded residual -- for every input, satisfiable
  or not, saturated or not.  This is exactly what `Splice` could NOT prove for `reduce2`.
* `dropped_fixed`, `dropped_fixed_residual`, `dropped_fixed_entails`: on the known
  counterexample the guard fires, the splice is skipped, the residual is the input
  verbatim, and the lost consequence `x = y` survives.
* `spliceOK_fires`, `GuardFires.reduce2G_fires`: the guard is not the trivial repair
  "never splice" -- a small closed system passes it, and the splice then really does
  rewrite the system.
-/
import Rowpartition.Splice

namespace Rowpartition

/-! ## 1. The guard

The three side conditions of `Splice.splice_entails_iff`, packaged as one predicate on
the data the compiler has in hand at the splice: the variable `v` being eliminated, the
partition `p` whose right-hand side is substituted, and the constraint list `G` being
rewritten.  Nothing semantic appears -- no assignment, no satisfiability -- which is why
the predicate is decidable and the repair implementable. -/

/-- The three side conditions of `Splice.splice_entails_iff`, as one decidable predicate.

* `v` is not a left-hand side of `G`.  This is the condition that fails on
  `DroppedPartition`, and the only one of the three that can fail on satisfiable input.
* the concrete part of any constraint of `G` mentioning `v` is disjoint from `p`'s.  By
  `Splice.splice_conc_disjoint_of_models` this holds at every model of `p` and `G`; it
  can fail only when the input is already unsatisfiable.
* a right-hand side of `G` containing `v` twice forces `p`'s concrete part empty.  By
  `Splice.splice_conc_empty_of_models` this too holds at every model of `p` and `G`. -/
def SpliceOK (v : Var) (p : Constraint) (G : List Constraint) : Prop :=
  (∀ d ∈ G, d.lhs ≠ v) ∧
  (∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc) ∧
  (∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅)

/-- **The guard is decidable**, which is the whole point of stating it: a conjunction of
quantifiers bounded by the list `G`, over an equality of variables, a disjointness of two
finite label sets and a count of occurrences.  A compiler can run this test. -/
instance decidableSpliceOK (v : Var) (p : Constraint) (G : List Constraint) :
    Decidable (SpliceOK v p G) :=
  inferInstanceAs (Decidable ((∀ d ∈ G, d.lhs ≠ v) ∧
    (∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc) ∧
    (∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅)))

/-- First conjunct: `v` is no left-hand side of `G`. -/
theorem SpliceOK.lhs {v : Var} {p : Constraint} {G : List Constraint}
    (h : SpliceOK v p G) : ∀ d ∈ G, d.lhs ≠ v := h.1

/-- Second conjunct: concrete parts do not clash. -/
theorem SpliceOK.dis {v : Var} {p : Constraint} {G : List Constraint}
    (h : SpliceOK v p G) : ∀ d ∈ G, v ∈ d.vars → Disjoint d.conc p.conc := h.2.1

/-- Third conjunct: a repeated occurrence of `v` forces `p`'s concrete part empty. -/
theorem SpliceOK.dup {v : Var} {p : Constraint} {G : List Constraint}
    (h : SpliceOK v p G) : ∀ d ∈ G, 2 ≤ d.vars.count v → p.conc = ∅ := h.2.2

/-! ## 2. The guarded fold

`Splice.reduce2` is `Subst.reduce`'s fold over the saturated partition list: splice
whenever the left-hand side passes the ambiguity guard `E` (`v.ty.ambiguous ||
es.contains(v)`, abstracted to a decidable predicate).  `reduce2G` is the same fold with
`SpliceOK` tested against the CURRENT accumulator as well -- which is what an
implementation would do, since the accumulator is the list it is about to rewrite. -/

/-- `Subst.reduce` case 2 WITH the guard: splice only when it is conservative to.  Note
that the guard is evaluated against the accumulator `acc`, i.e. against the list as it
stands after the splices of the later partitions, not against the original input. -/
def reduce2G (E : Var → Prop) [DecidablePred E] (S G : List Constraint) : List Constraint :=
  S.foldr (fun p acc => if E p.lhs ∧ SpliceOK p.lhs p acc then spliceG p.lhs p acc else acc) G

/-- The fold on the empty partition list publishes the input unchanged. -/
theorem reduce2G_nil (E : Var → Prop) [DecidablePred E] (G : List Constraint) :
    reduce2G E [] G = G := rfl

/-- One step of the fold, with the accumulator named. -/
theorem reduce2G_cons (E : Var → Prop) [DecidablePred E] (p : Constraint)
    (S G : List Constraint) :
    reduce2G E (p :: S) G =
      if E p.lhs ∧ SpliceOK p.lhs p (reduce2G E S G) then
        spliceG p.lhs p (reduce2G E S G)
      else reduce2G E S G := rfl

/-! ## 3. Soundness: the guard costs nothing

Adding a test in front of a rewrite can only shrink the set of rewrites performed, and
soundness of the unguarded rewrite needs no side condition (`Splice.splice_sat`), so
this half is immediate.  It is stated anyway because a repair that broke soundness would
be no repair. -/

/-- **The guarded fold is sound.**  Any model of the saturated list together with the
input list is a model of the published residual.  Exactly `Splice.reduce2_models`, with
the extra conjunct in the test simply discarded. -/
theorem reduce2G_models (E : Var → Prop) [DecidablePred E] {rho : Assign}
    {S G : List Constraint} (hS : Models rho S) (hG : Models rho G) :
    Models rho (reduce2G E S G) := by
  induction S with
  | nil => exact hG
  | cons p S ih =>
    rw [models_cons] at hS
    have hrec := ih hS.2
    rw [reduce2G_cons]
    by_cases hg : E p.lhs ∧ SpliceOK p.lhs p (reduce2G E S G)
    · rw [if_pos hg]
      exact spliceG_models hS.1 rfl hrec
    · rw [if_neg hg]
      exact hrec

/-- **The guarded residual is entailed by the input.**  Every constraint it publishes
follows from the saturated list together with the input list. -/
theorem reduce2G_entails (E : Var → Prop) [DecidablePred E] {S G : List Constraint}
    {c : Constraint} (hc : c ∈ reduce2G E S G) : Entails (S ++ G) c := by
  intro rho hm
  rw [models_append] at hm
  exact reduce2G_models E hm.1 hm.2 c hc

/-! ## 4. Conservativity: what the guard buys

This is the half that licenses the repair, and it is the half that is FALSE without the
guard (`Splice.DroppedPartition.dropped_can_lose`).  The induction is over the partition
list; at each step the guard either held -- and `Splice.spliceG_backward_models` takes
exactly its three conjuncts and undoes the splice by one update of `v` -- or it did not,
and the accumulator is unchanged, so there is nothing to undo.

The successive undo-updates compose without interfering, and no separate idempotence
lemma is needed: the fold is a `foldr`, so peeling the head partition `p` off `p :: S`
undoes the OUTERMOST splice first, leaving a model of `reduce2G E S G` to which the
induction hypothesis applies directly.  A variable spliced twice therefore receives two
successive updates, applied in the right order, rather than two conflicting ones. -/

/-- **The guarded fold is conservative, for the whole fold and with no hypothesis on the
input.**  A model of the published residual extends -- changing only variables that the
ambiguity guard `E` admits -- to a model of the ORIGINAL input list `G`.

`rho` is universally quantified INSIDE the statement because the induction step applies
the hypothesis to an updated assignment, not to `rho`.

Two things this does not say, and cannot.  The extension need not model the saturated
list `S`: a later update may destroy a partition an earlier step used, and `S` is not
part of what `reduce` publishes.  And the variables changed are only known to satisfy
`E`; which variables those are is `v.ty.ambiguous || es.contains(v)`, which is not
modelled here. -/
theorem reduce2G_backward (E : Var → Prop) [DecidablePred E] {S G : List Constraint} :
    ∀ {rho : Assign}, Models rho (reduce2G E S G) →
      ∃ rho', (∀ w, ¬ E w → rho' w = rho w) ∧ Models rho' G := by
  induction S with
  | nil => exact fun {rho} hm => ⟨rho, fun _ _ => rfl, hm⟩
  | cons p S ih =>
    intro rho hm
    rw [reduce2G_cons] at hm
    by_cases hg : E p.lhs ∧ SpliceOK p.lhs p (reduce2G E S G)
    · rw [if_pos hg] at hm
      have hb := spliceG_backward_models hg.2.lhs hg.2.dis hg.2.dup hm
      obtain ⟨rho', hagree, hmG⟩ := ih hb
      refine ⟨rho', fun w hw => ?_, hmG⟩
      have hne : w ≠ p.lhs := by
        rintro rfl
        exact hw hg.1
      rw [hagree w hw, upd_ne rho _ hne]
    · rw [if_neg hg] at hm
      exact ih hm

/-! ## 5. The corollary the compiler cares about -/

/-- **The guarded residual keeps every consequence of the input that the ambiguity guard
does not touch** -- with NO further hypothesis: the input need not be satisfiable, the
partition list need not be saturated, and it need not be entailed by the input.  This is
the statement `Splice` refutes for the unguarded fold, and it is the licence for the
repair.

The hypothesis on `c` is the obvious one and cannot be dropped: a consequence that
mentions a variable the fold is free to reassign is not preserved by anything that
reassigns it. -/
theorem reduce2G_preserves_entailment (E : Var → Prop) [DecidablePred E]
    {S G : List Constraint} {c : Constraint}
    (hcE : ∀ u, u = c.lhs ∨ u ∈ c.vars → ¬ E u) (h : Entails G c) :
    Entails (reduce2G E S G) c := by
  intro rho hm
  obtain ⟨rho', hagree, hmG⟩ := reduce2G_backward E hm
  refine (sat_congr ?_ ?_).mp (h rho' hmG)
  · exact hagree c.lhs (hcE c.lhs (Or.inl rfl))
  · exact fun w hw => hagree w (hcE w (Or.inr hw))

/-! ## 6. The payoff: the known counterexample is repaired

`Splice.DroppedPartition` is the system

    b <- (v)        with `v` ambiguous
    b <- (y)
    v <- (x)

on which the unguarded fold, splicing with the entailed partition `p = v <- (y)`,
publishes a residual that no longer entails `x = y`.  The guard rejects that splice, for
the right reason: `v` is the left-hand side of the third constraint. -/

/-- **The guard blocks the splice that lost `x = y`.**  `SpliceOK` fails on the
counterexample -- its first conjunct fails, because `v <- (x)` is a constraint of the
input with left-hand side `v`. -/
theorem dropped_fixed :
    ¬ SpliceOK DroppedPartition.v DroppedPartition.p DroppedPartition.G := by decide

/-- **So the guarded residual is the input, verbatim.**  No splice fires. -/
theorem dropped_fixed_residual :
    reduce2G (· = DroppedPartition.v) [DroppedPartition.p] DroppedPartition.G
      = DroppedPartition.G := by decide

/-- **And the consequence survives.**  `x = y` is entailed by the guarded residual,
where `Splice.DroppedPartition.not_entails` says it is NOT entailed by the unguarded
one.  This is the repair, on the case that motivated it. -/
theorem dropped_fixed_entails :
    Entails (reduce2G (· = DroppedPartition.v) [DroppedPartition.p] DroppedPartition.G)
      DroppedPartition.c := by
  rw [dropped_fixed_residual]
  exact DroppedPartition.entails_c

/-! ## 7. Non-vacuity: the guard is not "never splice"

A guard that always failed would satisfy everything in sections 4 to 6 and be useless.
The system below passes it: `v` heads no constraint of `G`, there are no concrete labels
to clash, and `v` occurs once.  The splice fires and rewrites the system. -/

namespace GuardFires

/-- The variable eliminated: `v = 0`. -/
def v : Var := 0

/-- The partition substituted in: `v <- (x)`, with `x = 1`. -/
def p : Constraint := ⟨0, [1], ∅⟩

/-- The list rewritten: `b <- (v)`, with `b = 2`.  `v` occurs on the right, once, and on
no left-hand side. -/
def G : List Constraint := [⟨2, [0], ∅⟩]

/-- The guard passes. -/
theorem ok : SpliceOK v p G := by decide

/-- The splice fires and changes the system: `b <- (v)` becomes `b <- (x)`. -/
theorem changed : spliceG v p G ≠ G := by decide

/-- ...and the guarded FOLD performs it, so the guard is not vacuous on `reduce2G`
either. -/
theorem reduce2G_fires : reduce2G (· = v) [p] G = [⟨2, [1], ∅⟩] := by decide

end GuardFires

/-- **The guard really does fire.**  There is a system on which `SpliceOK` holds and the
splice therefore runs and changes the system, so sections 4 to 6 are not about a rewrite
that never happens. -/
theorem spliceOK_fires : ∃ (v : Var) (p : Constraint) (G : List Constraint),
    SpliceOK v p G ∧ spliceG v p G ≠ G :=
  ⟨GuardFires.v, GuardFires.p, GuardFires.G, GuardFires.ok, GuardFires.changed⟩

/-! ## 8. Summary

WHAT IS ESTABLISHED.

* `SpliceOK` and `decidableSpliceOK`.  The three side conditions of
  `Splice.splice_entails_iff` are a single DECIDABLE predicate on the data the compiler
  holds at the splice: the variable being eliminated, the partition being substituted,
  and the list being rewritten.  No semantic notion occurs in it, so the test the repair
  proposes is implementable exactly as stated.
* `reduce2G_models`, `reduce2G_entails`.  Guarding costs no soundness: every constraint
  the guarded residual publishes is still entailed by the saturated list together with
  the input list.
* `reduce2G_backward`.  Guarding buys conservativity for the WHOLE fold, with no
  hypothesis on the input at all: every model of the guarded residual extends, changing
  only variables the ambiguity guard admits, to a model of the original input list.
* `reduce2G_preserves_entailment`.  Hence, unconditionally, a consequence of the input
  none of whose variables the ambiguity guard admits is still a consequence of the
  guarded residual.  For the UNGUARDED fold this is false, and
  `Splice.DroppedPartition.dropped_can_lose` is the counterexample.
* `dropped_fixed`, `dropped_fixed_residual`, `dropped_fixed_entails`.  On that
  counterexample the guard fires, no splice is performed, the residual is the input
  verbatim, and the consequence `x = y` that the unguarded fold lost is entailed.
* `spliceOK_fires`, `GuardFires.reduce2G_fires`.  The guard is not the trivial repair:
  a small closed system passes it and is genuinely rewritten.

WHAT IS NOT ESTABLISHED.

* NOTHING HERE IS ABOUT `reduce`'s FIRST CASE.  `case (Partition(v, RHSConcr(fs), _),
  cs)` has no ambiguity guard and does not rewrite `cs` at all: it calls
  `instantiateType`, committing `v` globally in the substitution.  That is outside this
  vocabulary entirely -- `Assign` gives every variable a row, so there is no unification
  variable versus skolem variable here -- and the guard defined in this file says
  nothing about it.
* NOTHING HERE SAYS WHICH VARIABLES THE AMBIGUITY GUARD SELECTS.  `E` is an arbitrary
  decidable predicate; `v.ty.ambiguous` and `es.contains(v)` are not modelled.  In
  particular `reduce2G_preserves_entailment` protects exactly the consequences whose
  variables fail `E`, and which consequences those are depends on a fact about the type
  checker's variable discipline that is not proved here.
* NOTHING HERE IS ABOUT THE ORDER OF THE FOLD.  `reduce2G` is a `foldr`, the guard is
  tested against the accumulator, and both the residual and the set of splices performed
  can differ if the partition list is permuted.  The results above hold for every order,
  but they do not say that two orders agree.
* The guard is SUFFICIENT, not necessary: nothing here says a splice it rejects would
  actually have lost something.  On `DroppedPartition` one did; in general a rejected
  splice may have been harmless.
* Nothing here is about what the residual COSTS -- the alternative repair named in
  `Splice`, emitting the partition that was substituted with, is not modelled, and the
  two repairs are not compared.  Termination, the size of the residual and the
  interaction with `csz` are likewise not modelled.
-/

end Rowpartition
