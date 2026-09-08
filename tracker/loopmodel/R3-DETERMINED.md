# R3 — Rose's Definition 13 (the determinacy closure) as a criterion for `reduce`'s splice and for row-residual ambiguity

Stage R3 of `tracker/LOOP-MODEL-PLAN.md`, brief `tracker/loopmodel/briefs/brief-R3.md`, from
`ROSE-COMPARISON.md` §3 rank 4 ("ADOPT AS AN INVESTIGATION").  An INVESTIGATION stage: **no solver
behaviour changed, no diagnostic shipped**, and the only Scala is two trace-only records emitted
under `-Dermine.rowTrace`.

## 0. Outcome

**GREEN.**  R3.1–R3.4 delivered; every gate re-run and green; nothing in the solver changed.

The stage was asked to build Rose's Definition 13 as a criterion for two things and to measure
it.  The short answers:

* **The closure exists, is a closure, and means something.**  `Determined G U` and
  `RoseDetermined G U` are least fixed points, proved extensive / monotone / closed / least /
  idempotent, and `determined_unique` is the theorem that gives them content: two models of `G`
  that agree on `U` agree on everything `U` determines.  Ermine's cancellation clause is proved
  **strictly** larger than Rose's, and the corpus says why it has to be: `Has a b`, Ermine's
  spelling of Rose's primitive containment, is Rose-ambiguous and Ermine-determined, and 33 of
  the 37 example signatures Rose's criterion flags carry exactly one row existential — that shape.
* **(a) THE SPLICE GUARD IS REFUTED, in both directions, and the numbers agree.**
  Determinedness neither implies nor is implied by conservativity of `Subst.reduce`'s splice
  (`determined_splice_not_conservative` on `Splice.DroppedPartition`, where `v` is determined by
  **Rose's clause alone** and the splice still loses a consequence stated entirely in the
  universal vocabulary; `undetermined_splice_is_conservative` for the converse).  Measured:
  **Rose's closure and the withdrawn three-condition guard never once license the same splice —
  0 of 42,902 per file, 0 of 8,415 in batch mode.**  The condition that actually decides the
  splice is `splice_entails_iff`'s `hlhs`, which is SYNTACTIC, and no closure on models can see
  it.  **Recommendation: do not build the guard.**
* **(b) THE DELETION LICENCE IS REFUTED, twice.**  Definition 13 licenses the *value* and not the
  *definedness*: the row algebra is a PARTIAL monoid and a partition also asserts that its parts
  COMBINE.  What is proved instead is `dead_delete_of_pairwise`, and unconditionally
  `dead_delete_of_le_one_part`.
* **(c) THE AMBIGUITY CRITERION is stated, given its theorem, and MEASURED — and it is not ready
  to ship.**  `RowAmbiguous` with `witness_unique_of_not_rowAmbiguous`; sound, not complete.  On
  the 104 top-level published signatures of the corpus: **Rose's closure flags 88, Ermine's flags
  19, and none of Ermine's 19 is in `core/examples`.**  `PivotTest.pivotData` — the memo's
  flagship incoherent residual — **is not flagged by Ermine's criterion**, and the Lean says why
  and the compiler agrees to the record (`Pivot.criterion_split`, and the `ramb` line for
  `pivotData` reads `roseUndet = 2, ermUndet = 0`).  But the false-positive rate is high — 10 of
  the 19 flagged signatures are in fact determined — so **no warning should ship**.  One further
  clause, the solver's own `resolution`, clears eight of the ten; `Determined.lean` §13 has it
  with its uniqueness theorem.  **It is not enough, and the number is already in hand**: running
  all three clauses over the published `.ei` (§4.7, computed twice independently) leaves **11 of
  19** flagged, of which two are false positives pinned by a *disjointness obligation* that no
  clause of this family can reach.  **So the stage 2 an earlier draft recommended is CLOSED with
  a "no", not scheduled.**  What survives as actionable is one ticket, not a stage: the tautology
  deletion (`TICKET-stdlib-findings.md` C12).

**One correction to a figure in circulation**: "the guard fails on 90 % of splices" is a fact
about the STDLIB BOOT counted once per file.  On the corpus modules' own splices the withdrawn
guard licenses **64 %**.  §4.2.

## 1. What was built

| | |
|---|---|
| `tracker/lean/Rowpartition/Determined.lean` | **1,245 lines; 163 source declarations (115 `theorem`, 47 `def`, 1 `structure`); 197 non-internal constants of which 136 are theorems — exactly the Audit delta 4,582 − 4,446.  No `sorry`, no `axiom`, no `native_decide`.**  In the root import.  The closure, its closure properties, the uniqueness theorem, the three R3.2 statements, every witness, and (§13) the clause the measurement then asks for. |
| `tracker/lean/Rowpartition.lean` | one `import` line and one documentation bullet. |
| `core/.../RowTrace.scala` (worktree `ermine-scala-wt-r3`, branch `determined-closure`) | the two new records documented; `withBinding`, a thread-local that is a no-op when tracing is off. |
| `core/.../Subst.scala` (same worktree) | `Subst.Determinacy` (the two closures and a transcription of the three withdrawn side conditions), the `detm` emission in `reduce`, the `ramb` emission in `mkSimplified`, and one `withBinding` wrapper. **Every insertion is inside `if (RowTrace.enabled)` or a `RowTrace.log` by-name argument.** |
| `tracker/loopmodel/R3-DETERMINED.md` | this report. |

Nothing else was touched.  No commit was made.  `tracker/ROW-CONSTRAINT-STATE.md` is unchanged
because nothing solver-visible changed.

**A note on the tree this was measured in.**  The working tree carried uncommitted changes when
the stage started — `-Dermine.topNormalise` flipped to DEFAULT ON, and the `E5`/`E4` example
groups' edits.  The worktree was created at `HEAD` (`18f5357`) and those uncommitted changes were
applied into it verbatim (`git diff HEAD`, excluding `tracker/lean`), so **both sides of every
A/B below are the tree as it actually stands**, and the two sides differ by the instrument and by
nothing else.  Those changes were committed as `3a767b6` while this stage was running; the
worktree's `Constraints.scala` and `core/examples` are byte-identical to the main tree's now, so
nothing measured here is stale.

**One number that belongs to somebody else.**  `5bf83bf`'s handoff says a perf-bench re-measure
is pending for the `topNormalise` adoption.  §6's base figure IS that measurement, taken on the
adopted tree with no instrument: `perf-bench batch -n 5`, **cold median 10.97 s in-process**
(min 10.64, max 11.12, spread 0.48, `load_before` 0.02).  It is offered, not claimed: it was
taken in a worktree at `18f5357` plus the adoption patch rather than at `3a767b6`, and the two
have byte-identical Scala.

**One thing a reviewer must know about the worktree.**  `tracker/repl-classpath.txt` is TRACKED
and its committed content names the MAIN tree's `target` directories, so a `perf-bench` run
inside the worktree would silently have measured the main tree's compiler.  It was repointed at
the worktree (the one-line diff `git status` shows there) and must stay repointed for any re-run
of §6's perf figures.

## 2. R3.1 — the closure, in Lean

### 2.1 Definition 13, and the n-ary restatement

The paper's clause is binary:

> **Definition 13.**  We define `T⁺_Ψ` as the smallest set `U` such that • `T ⊆ U`; and, • if
> `ζ₁ ⊙ ζ₂ ∼ ζ₃ ∈ Ψ`, and `fv(ζ₁, ζ₂) ⊆ U`, then `fv(ζ₃) ⊆ U`.

Ermine's constraint is n-ary (`a <- (b, c, (|Foo|))`).  What licenses reading it as one
combination predicate is R2's `Rose.sat_iff_pfold`, carried into this file as `lhs_eq_pfold`:

```lean
theorem lhs_eq_pfold {rho : Assign} {c : Constraint} (h : Sat rho c) :
    Rose.labelAlgebra.pfold (parts rho c) = some (rho c.lhs)
```

The left-hand row is the value of the *partial fold* of the parts, hence a **function** of them
wherever the fold is defined.  So Definition 13's clause becomes, verbatim n-arily:

```lean
def roseAdd (G : System) (D : Finset Var) : Finset Var :=
  (G.filter (fun c => vset c ⊆ D)).image Constraint.lhs
```

### 2.2 Ermine's clause: cancellation

The memo's observation, made precise.  In Ermine the concrete part of a partition is *always*
known — it is a literal — and the parts are disjoint and complete.  So a *part* is a function of
the whole and the other parts:

```lean
def cancelAdd (G : System) (D : Finset Var) : Finset Var :=
  G.biUnion (fun c => if c.lhs ∈ D then (vset c).filter (fun v => (vset c).erase v ⊆ D) else ∅)
```

and the semantic content is `Sat.eq_sdiff`, proved here:

```lean
theorem Sat.eq_sdiff (h : Sat rho c) (hv : v ∈ vset c) :
    rho v = rho c.lhs \ (c.conc ∪ ((vset c).erase v).biUnion rho)
```

which needs *both* halves of `Sat`: completeness for `⊇` and pairwise disjointness for `⊆`.
This clause is **not** in Rose.  Rose's `⊙` is a partial monoid with no cancellation axiom, and
in Rose's *simple* row algebra `⟨L ⇀ T, ⊔, ∅⟩` cancellation is available for the same reason —
but Definition 13 does not use it, and Definition 14 is stated over Definition 13.

### 2.3 The closure operators

`Determined G U` is `(detStep G)^[(allVars G).card] U` with
`detStep G D = D ∪ roseAdd G D ∪ cancelAdd G D`, and `RoseDetermined G U` the same with
`roseStep G D = D ∪ roseAdd G D`.  Iterating a fixed number of times is enough, and that is
proved rather than assumed: `iterate_fixed` is the pigeonhole (an extensive map on a finite
carrier either stabilises within `|W|` steps or its iterates outgrow `W`).  What comes out:

| property | theorem | for Rose's closure |
|---|---|---|
| EXTENSIVE `U ⊆ Determined G U` | `subset_determined` | `subset_roseDetermined` |
| MONOTONE in `U` | `determined_mono` | `roseDetermined_mono` |
| CLOSED (a genuine fixed point) | `determined_closed` | `roseDetermined_closed` |
| LEAST such set | `determined_least` | `roseDetermined_least` |
| IDEMPOTENT | `determined_idem` | `roseDetermined_idem` |
| Rose's ⊆ Ermine's | `roseDetermined_subset` | — |
| seed outside `G` is inert | `determined_union_disjoint` | — |

The last row is what licenses the instrument (§4.1) to read its seed off the partitions rather
than off `fv(τ)`: widening the seed by variables the system does not mention widens the closure
by exactly those variables and by nothing else, so the verdict on any variable the system *does*
mention is unchanged (`mem_determined_union_disjoint`).

`detStep_eq_iff_closed` is the bridge that makes "least fixed point" the same statement as
"smallest set closed under the two clauses", so `Determined` really is Definition 13's `T⁺_Ψ`
(plus cancellation) and not merely something that iterates it.

### 2.4 The theorem that gives the closure its meaning

```lean
theorem determined_unique {G : System} {U : Finset Var} {rho rho' : Assign}
    (hm : SModels rho G) (hm' : SModels rho' G) (hU : AgreeOn rho rho' U) :
    AgreeOn rho rho' (Determined G U)
```

Two models of `G` that agree on `U` agree on everything `U` determines.  It needs no fixed-point
property at all — only that each clause preserves agreement (`agree_roseAdd`, `agree_cancelAdd`)
— which is why it holds for both closures (`roseDetermined_unique`) and would hold for any
further clause with the same property.  **Rose's clause is where the partial monoid does the
work** (the whole is a function of the parts); **cancellation is where disjointness and
completeness together do it** (a part is a function of the whole and the rest).

### 2.5 Non-vacuity

* `RuleFires` — on `a <- (x, y)`: Rose's clause fires (`rose_fires`: `a ∈ RoseDetermined G {x,y}`),
  cancellation fires (`cancel_fires`: `y ∈ Determined G {a,x}`), and Rose's clause alone does
  **not** get there (`cancel_not_rose`).  `rose_lt_det` is the strict inclusion, by `decide`.
* `Derived` — the two derived predicates of `modules/Constraint.e`.  `Disj a b`
  (`exists c. c <- (a, b)`) is Rose's own clause and Rose's closure determines `c`
  (`disj_is_rose`).  `Has a b` (`exists c. a <- (b, c)`, Rose's containment `b ≼ a`) is
  determined **only by cancellation** (`has_needs_cancellation`: Rose-ambiguous, not
  Ermine-ambiguous).  That is the structural reason Ermine's closure has to be larger than
  Rose's: Rose keeps `≼` primitive, Ermine spells it out with a minted complement, and the
  complement is exactly a cancellation.

### 2.6 `PivotTest.pivotData`

The corpus's one known incoherent residual, modelled as
`(|Issue,Key,Value|) <- ((|Key|), i, v3)` together with `s <- ((|Sector,Price,MarketCap|), i)`,
with `s` universal, `i`/`v3` existential and a carrier variable for the concrete left-hand side
(which is what `PQueue.build` mints).  **The two closures disagree, and this is the sharpest
finding of R3.1:**

| | `i` | `v3` |
|---|---|---|
| on the BARE constraint, Rose's closure | undetermined | undetermined |
| on the BARE constraint, Ermine's closure | undetermined | undetermined |
| on the residual as PUBLISHED, Rose's closure | **undetermined** | **undetermined** |
| on the residual as PUBLISHED, Ermine's closure | **determined** | **determined** |

`Pivot.bare_genuinely_ambiguous` exhibits two models of the bare constraint that agree on the
whole universal vocabulary and differ at `i` — the four solutions are real.
`Pivot.full_unique` shows that on the residual the compiler actually publishes, the value of `s`
pins both: `i = s \ {Sector,Price,MarketCap}` by cancellation, then
`v3 = {Issue,Key,Value} \ ({Key} ∪ i)` by cancellation again.

`R2-REVIEW.md` K-9 read `pivotData` as incoherent by Definition 14, and that reading is correct
**for Rose's closure**, which is the one Definition 14 is stated over.  R3's larger closure —
which is sound, by `determined_unique` — says the opposite, and the models side with it.  The
ticket's "genuinely underdetermined — four solutions" is a true statement about the constraint
`TICKET-row-constraint-decision.md` §1.3 quotes, which is the bare one, in isolation.

### 2.7 A third clause, added because §4 asked for it

`Determined.lean` §13 adds `resAdd` — RESOLUTION, the solver's own rule 6 read as a determinacy
clause: if `c` is a *sub-partition* of `d` (`vset c ⊆ vset d` and `c.conc ⊆ d.conc`) and both
left-hand sides are known, then `d`'s remaining variable parts are determined once all but one of
them is.  It is sound for the same reason cancellation is, and by the same two facts:

```lean
theorem agree_resAdd (hm : SModels rho G) (hm' : SModels rho' G) (hD : AgreeOn rho rho' D) :
    AgreeOn rho rho' (resAdd G D)
```

so `determined3_unique` re-proves the uniqueness theorem for `Determined3 = ` the three-clause
closure, and `determined_subset_determined3` says it is larger.  This is **not** part of the
criterion R3 measures — §4 measures the two-clause closure the brief asked for — it is there
because §4.5's hand-check identifies this exact clause as the cause of seven of ten false
positives, and §5 recommends a stage 2 around it.  `NotEq.res_cures` is the smallest instance,
the stdlib `(!=)`, kernel-checked in both directions.

## 3. R3.2 — what determinacy licenses

### 3.1 (a) THE SPLICE — the candidate guard is REFUTED, in both directions

The candidate: `reduce` splices `v` only when `v ∈ Determined (residual) (vars \ es)`.

**It does not make the splice conservative.**  `SpliceGuard13.determined_splice_not_conservative`
takes `Splice.DroppedPartition`'s system — `b <- (v)`, `b <- (y)`, `v <- (x)`, with `v` the one
existential — and shows

* `v ∈ RoseDetermined Gs U₀` and `v ∈ Determined Gs U₀` with `U₀ = {x, y, b}` (kernel-checked by
  `decide`).  The witness is the constraint `v <- (x)` itself: `x` is universal, so **Rose's
  clause alone** already determines `v`;
* the input entails `x <- (y)` and the spliced residual does not (`Splice.entails_c`,
  `Splice.not_entails`, both pre-existing);
* and the lost consequence is stated **entirely in the universal vocabulary**
  (`insert c.lhs (vset c) ⊆ U₀`), so the refutation holds in the vocabulary-restricted reading
  as well as the plain one.

The condition that fails is `splice_entails_iff`'s `hlhs` — "`v` heads no constraint of the
emitted list".  That is a **syntactic** property of the residual and no closure on models can
see it.

**And it blocks splices that are conservative.**
`SpliceGuard13.undetermined_splice_is_conservative` takes `b <- (v, w)`, `b <- (x, w)` with `x`
the only universal, and the partition `v <- (x)` that the saturated set offers:

* `v ∉ RoseDetermined Hs {x}` and `v ∉ Determined Hs {x}` (`decide`);
* the input nevertheless entails `v <- (x)` (`entails_p`, by cancelling `w` out of both
  constraints — `Sat.eq_sdiff` twice);
* and `splice_entails_iff` applies, so for **every** `v`-free `c`,
  `Entails (spliceG v p G) c ↔ Entails G c`.

So determinedness is neither necessary nor sufficient for conservativity of the splice.

**The weaker TRUE statement, and it is not new.**  `splice_entails_iff` already gives
conservativity from `hlhs` alone, since the other two side conditions hold at any model of the
input (`splice_conc_disjoint_of_models`, `splice_conc_empty_of_models`).  Determinacy adds
nothing to it: the two properties are logically independent, and §4 measures how independent
they are on the corpus.

### 3.2 (b) THE DELETION — refuted twice; what IS licensed

`ROSE-COMPARISON.md` §4.5's `Goal_dead_existential_deletable` asks what Definition 13 licenses
about deleting an existential that is neither determined by nor determining the universals.
**Definition 13 licenses the VALUE and not the DEFINEDNESS**, and the gap is exactly the
partiality of the row algebra.

* `DeadTwoParts.two_parts_not_deletable` — `v <- (x, y)` with `v` a dead existential (it heads
  this constraint and occurs nowhere else).  Rose's clause **does** determine `v` here
  (`v_determined`).  The constraint is still not deletable: it also says `x` and `y` are
  **disjoint**, and that survives the existential quantification of `v`.  A caller with
  `x = y = {Foo}` satisfies the deleted residual and not the original.
* `DeadUndetermined.undetermined_not_deletable` — the brief's exact hypothesis.
  `a <- (v, w, (|Foo|))` with `a` the only universal.  `v` is in **neither** closure
  (`v_undetermined`) and adding `v` to the known set determines **no** universal
  (`v_determines_nothing`).  Deleting it is still not `REquiv`: the constraint says `Foo ∈ a`.

What is licensed, and proved — **sufficient, not necessary** (R3 review M-3):

```lean
theorem dead_delete_of_pairwise (h : DeadEx R v c)
    (hdisj : ∀ rho, SModels rho (R.sys.erase c) → (parts rho c).Pairwise Disjoint) :
    REquiv R ⟨R.ex, R.sys.erase c⟩
```

— a dead existential's defining constraint may be deleted **when** the remainder already forces
its right-hand side to **combine**.  `dead_delete_of_le_one_part` is the unconditional corollary:
at most one part (`v <- (u)`, `v <- ((|K|))`, `v <- ()`) and there is nothing to be disjoint from.
In Ermine's own surface syntax the side condition is the disjointness predicate
`a | b = exists c. c <- (a, b)` of `modules/Constraint.e`, which is exactly what §1.2 of
`ROSE-COMPARISON.md` records as expressible in both systems and primitive in neither.

**Two limits on that theorem, both from the R3 review (M-3), both accepted.**

1. **It is SUFFICIENT and not NECESSARY**, and the gap is structural rather than fiddly: `REquiv`
   lets the *other* existentials be re-chosen, so what is really needed is "every model of the
   remainder can be *adjusted on `R.ex`* to make the parts combine", not "every model of the
   remainder already has them disjoint".  The reviewer's kernel-checked witness
   (`RevCheck.pairwise_not_necessary`, scratch `review-R3/Check1.lean`, standard axioms) is
   `v <- (w, y)` with **`v` and `w` both existential**: `REquiv`-deletable, witness `w := ∅`,
   `v := y`, and the side condition fails.  That is not a corner: constraints whose parts are all
   existential are exactly where the corpus's genuine ambiguities live.
2. **Neither licensed form covers the shape R3's own measurement finds.**  Both are about a dead
   existential on the **left**.  The five true positives §4.5 finds are `exists t h. r <- (t, h)`
   with `r` **universal** and both parts existential — a tautology (`t := r`, `h := ∅`) and
   deletable, but by a theorem R3 does not have.  §5(iii) and the new ticket item say so.

### 3.3 (c) THE AMBIGUITY CRITERION

Ermine has no ambiguity criterion for row residuals at all: `mkSimplified` computes
`ambiguitiesIn(exts, complex)` with `complex = reduce(classes)`, and the row parts (`dumb`)
reach `pruned` without passing through it (`Subst.scala:1723-1726`); `ambiguitiesIn` itself is
`typeVars(p).exists(_ == v)` with **no closure** (`:371-372`).  The criterion:

```lean
def RowAmbiguous (R : Residual) : Prop :=
  ∃ v ∈ R.ex, v ∉ Determined R.sys (allVars R.sys \ R.ex)
```

`U₀` is `allVars sys \ ex`, and that is *exactly* `fv(τ) ∪ universals` as far as the closure can
tell: both clauses quantify over constraints, so a variable of `τ` occurring in no constraint can
never be used by either.  This matters for the instrument, because `mkSimplified` does not see
`τ`.

**What it buys** — `witness_unique_of_not_rowAmbiguous`: if no existential escapes the closure,
any two witnesses a call site could choose agree on every variable the system mentions.  That is
the row-level analogue of Rose's coherence conclusion.

**`∀T` versus `exists` (R2-REVIEW K-9(3)), said explicitly.**  Rose's Definition 14 is about
`∀T.Ψ ⇒ τ`, and Theorem 15's payoff is coherence of ELABORATION: two derivations of one term
produce βη-equal programs.  Ermine binds these variables EXISTENTIALLY, and `Holds` — the
call-site reading, from `ROSE-COMPARISON.md` §4.1 — makes the witness the callee's choice.  So
the criterion transfers as a statement about the **witness**, not about elaboration.  Two further
things follow, and both are reasons not to overclaim:

1. **Ermine's rows are erased.**  A row variable carries no dictionary; a `Row r` carries its
   field types as a *value* (`core/src/main/resources/modules/Relation/Row.e:21`).  An undetermined row existential
   therefore cannot change what the program computes.  The payoff of the criterion for Ermine is
   PRECISION of the published type, not soundness of elaboration.
2. **Theorem 15 is unavailable in any case.**  Definition 14 defines coherence of a *term*
   through its *principal* type scheme, and Ermine has no principality theorem
   (`ROSE-COMPARISON.md` §1.5, `A1-REVIEW.md` §R-6 is a measured counterexample to the naive
   version).  Definition 14 is therefore not merely unmet but **not well-defined** for Ermine.
   Definition 13 is imported as a CRITERION, which is all rank 4 ever claimed for it.

**The criterion is SOUND but not COMPLETE.**  `CriterionIncomplete` is `a <- (v, v, w)`: the
repeated part is forced empty (`Sat.eq_empty_of_dup`), so `v` has exactly one value in every
model, and neither closure sees it.  A syntactic closure cannot see a semantic forcing, and a
diagnostic built on this criterion would have to be a warning rather than an error for that
reason alone.

`roseRowAmbiguous_of_rowAmbiguous`: Rose's closure is smaller, so **Rose's criterion flags at
least as much as Ermine's**.  §4 measures the gap.

## 4. R3.3 — the instrument, and the measurement

### 4.1 The instrument

Two new trace records, and **no existing record is touched**.

```
detm   site  loc  var  rose  erm  hlhs  hdis  hdup  nU0  nVars  nParts
ramb   site  loc  binding  nEx  nRowEx  nRoseUndet  nErmUndet  nParts  roseUndet  ermUndet
```

`detm` is written by `Subst.reduce` at every splice, immediately after the `splice` record and
computed on the same state: `cs`, the residual the fold has accumulated — which is the system a
determinacy guard would consult — with

> **`U₀` = the variables the row constraints of `cs` mention that the splice's OWN guard does not
> count as existential**, i.e. `{u ∈ vars(cs) : ¬(u.ty.ambiguous ∨ es.contains(u))}`.

That is where the universals come from, and `reduce` does know them: `es` is
`unbindExists(Ambiguous(Free), csz)`'s output, threaded in from `solve`, and `v.ty.ambiguous` is
the other disjunct of the splice's own guard, so the instrument's notion of "existential" is
*exactly* `reduce`'s.  Variables of `cs` that occur in no row constraint cannot affect either
closure (both clauses quantify over partitions), so reading `U₀` off the partitions rather than
off `typeVars(cs)` gives the same answer and needs no extra traversal — and that is a theorem,
not an argument: `determined_union_disjoint` / `mem_determined_union_disjoint`.  (One exception,
in the safe direction, found by the R3 review and recorded as §7 item 7.)

`ramb` is written by `Subst.mkSimplified` for every signature it publishes that carries at least
one row constraint, on `pruned` (what is published) with the published existentials
`exts filterNot (v => iso(v) || am(v))`.  `U₀` is the row variables that are not published
existentials — which is *exactly* `fv(τ) ∪ universals` as far as the closure can tell, since a
variable of `τ` occurring in no constraint can never be used by either clause.  `mkSimplified`
does not see `τ`, and this is why it does not need to.  `binding` is the name of the binding
whose final type this is; it comes from `RowTrace.withBinding` around
`inferImplicitBindingTypes`'s per-binding `generalize`, which is the one call site that publishes
a binding's signature.  An empty `binding` means the call is not one — `subsumeType`'s
`mkSimplified`, or an intermediate `generalize` at an `App`/`Lam` node.

`Subst.Determinacy` computes the two closures.  It is called only from inside
`if (RowTrace.enabled)`; it reads a constraint list and returns sets; it draws no ids, touches
no `SubstEnv` and builds no `Type`.  A right-hand side carrying anything that is neither a
variable nor a concrete row is BLOCKED — neither clause fires through it — which is the
conservative reading and the same shape `mkSimplified.normalPart` calls "something we don't know
how to deal with".

**A note on two splice counts.**  §4.2 reads the DEFAULT (parallel-loader) traces and §6 reads
`-Dermine.loadInSeries` ones, and the splice counts differ — 6,624 against 6,525 on the 18-group
batch.  That is the loader, not the instrument: which module is elaborated in which session, and
therefore how many solves happen at all, depends on the loading order.  Both sides of the §6 gate
are serialized and both sides of §4.2's population are the same run, so neither comparison is
affected.

### 4.2 The splice: how many splices each guard licenses

`corpus-run.sh --batch`, one JVM per population, so every module is compiled exactly once.
"Licensed" is a FREQUENCY, not a safety claim: §3.1 refutes the theorem the determinacy guard
would rest on, and the withdrawn guard's conditions are `splice_entails_iff`'s.

| population | splices | ROSE's closure | ERMINE's closure | the WITHDRAWN guard |
|---|---:|---:|---:|---:|
| stdlib boot (129 modules) — **one draw, see below** | 193 | 34 (17.6 %) | 44 (22.8 %) | 7 (3.6 %) |
| `core/examples`, 18 groups (batch) | 6,624 | 225 (3.4 %) | 670 (10.1 %) | 4,237 (64.0 %) |
| `core/examples/incomplete/` (batch) | 1,598 | 81 (5.1 %) | 143 (8.9 %) | 742 (46.4 %) |

**The boot row is a lottery and should not be read as a measurement** (R3 review M-5, accepted).
Three runs of the same R3 binary under the default parallel loader gave **192 / 193 / 192**
splices and **41 / 34 / 41** Rose-licensed (21.4 % / 17.6 % / 21.4 %): the run-to-run spread on
the closure columns is the same order as the difference between the two closures.  The batch rows
above are exact — the reviewer reproduced every cell, including the cross-tab — and the per-file
row below is within 0.009 % (4 splices in 42,898), which is 153 boots' worth of the same noise
averaged down.  `Rose ∧ guard = 0` was zero in every draw.  The boot's `ramb` figures in §4.4 are
stable across the draws (1,658 / 1,302 / 1,117; `ermUndet` 365–367).

**The overlap is the headline, and it is a measured version of §3.1.**

| population | Rose ∧ guard | Ermine ∧ guard | Ermine ∧ ¬guard | ¬Ermine ∧ guard | neither |
|---|---:|---:|---:|---:|---:|
| stdlib boot | **0** | 3 | 41 | 4 | 145 |
| 18 groups | **0** | 269 | 401 | 3,968 | 1,986 |
| `incomplete/` | **0** | 22 | 121 | 720 | 735 |

**Rose's closure and the withdrawn guard never once license the same splice** — 0 of 8,415
splices across the three populations.  Ermine's closure and the guard disagree on 4,369 of the
6,624 corpus splices (66 %).  The two criteria are not merely different in strength; they are
close to independent, which is what a semantic closure and a syntactic side condition should be
expected to be.

**Per file** — `corpus-run.sh` with no `--batch`, 153 invocations, each a virgin JVM that re-boots
the stdlib.  This is the population the historical 90 % figure was computed on.

| | splices | ROSE | ERMINE | WITHDRAWN guard | Rose ∧ guard | Ermine ∧ guard |
|---|---:|---:|---:|---:|---:|---:|
| 18 groups, per file | **42,902** | 5,839 (13.6 %) | 7,972 (18.6 %) | 6,298 (14.7 %) | **0** | 799 |

Again **zero** — across 42,902 splices, Rose's closure and the withdrawn guard never both fire.

**Two corrections to figures in circulation.**

1. *`hdis` and `hdup` are 100 % everywhere.*  On all 8,415 splices the second and third side
   conditions hold, so **the withdrawn guard IS `hlhs`**, exactly as `Splice.lean` predicts
   (`splice_conc_disjoint_of_models`, `splice_conc_empty_of_models` say the other two hold at any
   model of the input).
2. *The "90 % of splices fail" figure is a fact about the STDLIB BOOT, counted once per file.*
   `TICKET-signature-resolution-fragility.md` quotes "21141 of 23410 over the example corpus"
   (9.7 % licensed) from a PER-FILE sweep of 110 files.  Per file, each of those 110 JVMs re-boots
   the stdlib and contributes its 193 splices at a 3.6 % pass rate; the corpus modules' own
   splices pass at 64 %.  The two numbers are consistent and describe different populations, and
   the per-file figure is dominated by the boot.  The per-file table above is this tree's version
   of that number: **6,298 of 42,902, 14.7 %**.

### 4.3 The `splice` / `detm` cross-check

`Subst.Determinacy.conds` is a transcription of the `splice` record's inline block, and the
measurement CHECKS it rather than assuming it: on every one of the 8,415 splices the two records'
`(hlhs, hdis, hdup)` triples agree, per site, location, variable and thread
(`splice/detm side-condition agreement: True` in all three populations), and the two records come
in equal numbers (193/193, 6,624/6,624, 1,598/1,598 in batch mode, and 42,902/42,902 per file).
That certifies the three side conditions, not the closures; §7 says so.

### 4.4 Row ambiguity: how many published signatures carry an undetermined row existential

A `ramb` record is written for every signature `mkSimplified` publishes that carries at least one
row constraint.  Most of those are intermediate — `subsumeType`'s call, and the `generalize` at
every `App` and `Lam` node — so the population that matters is the one with a BINDING NAME, and
within it the one whose location is column 1 (a top-level binding; a name at any other column is
`let`- or `where`-local and reaches no interface).

| population | `ramb` records | with ≥1 row existential | ≥1 ROSE-undetermined | ≥1 ERMINE-undetermined |
|---|---:|---:|---:|---:|
| stdlib boot | 1,658 | 1,302 | 1,117 | 367 |
| 18 groups (batch) | 86,320 | 10,526 | 10,141 | 3,468 |
| `incomplete/` (batch) | 3,878 | 2,041 | 1,855 | 925 |

Per file (153 virgin JVMs) the record counts are much larger — 357,367 `ramb` records, 222,546
with a row existential, 192,823 Rose-undetermined, 65,537 Ermine-undetermined — because every
stdlib signature is re-published in every one of the 153 sessions.  **The DISTINCT population is
identical to the batch one**, which is the check that matters: 64 named top-level stdlib
signatures (51 Rose-flagged, 19 Ermine-flagged) and 40 in `core/examples` (37, 0), the same
numbers both ways.  The census does not depend on the compilation mode.

Restricted to **named, top-level** bindings — the ones a user can see in an `.ei` — on the
18-group batch (which includes one stdlib boot):

| | named signatures | ROSE flags | ERMINE flags |
|---|---:|---:|---:|
| stdlib | 64 | 51 (80 %) | **19 (30 %)** |
| `core/examples` | 40 | 37 (93 %) | **0** |
| both | 104 | 88 (85 %) | 19 (18 %) |

**Rose's closure alone is unusable as a criterion for Ermine**: it flags 37 of the 40 published
example signatures, and 33 of those 37 carry exactly ONE row existential — the `Has` shape
(`exists c. a <- (f, c)`) that cancellation determines outright.  That is the measured reason
Ermine's closure has to be larger than Rose's — the memo's `Has` question, answered at corpus
scale, and `Derived.has_needs_cancellation` is the same fact as a theorem.

**Under Ermine's closure, not one signature in `core/examples` is flagged — `PivotTest.pivotData`
included.**  Its `ramb` record reads

```
ramb  ?  core/examples/PivotTest.e(36:1)  pivotData^579364  7  2  2  0  2  i^584372 v3^584370
```

— seven published existentials, two of them row existentials (`i`, `v3`), **two** undetermined
under Rose's closure and **zero** under Ermine's.  That is `Pivot.criterion_split` reproduced on
the compiler, on the residual the compiler actually publishes (`.ei` snapshot):

```
pivotData : forall (s: rho). (exists ... (v32: b2) (i: b3) ...
   s <- ((|Sector, Price, MarketCap|), i),
   (|Issue, Key, Value|) <- ((|Key|), v32, i), ...) => Builtin.Mem s
```

So `pivotData` is **not alone** in the corpus under Rose's criterion (37 signatures are flagged)
and it is **not flagged at all** under Ermine's.

The nineteen the Ermine criterion does flag, all of them stdlib:

| signature | module | row ex | flagged |
|---|---|---:|---:|
| `(>=)`, `(<=)` | `Relation/Predicate.e` 63, 64 | 11 | 11 |
| `(!=)` | `Relation/Predicate.e` 70 | 3 | 3 |
| `(**)`, `(&)`, `(&_Mem)` | `Syntax/Relation.e` 52, 55, 56 | 3 | 3 |
| `cons_Bracket`, `dateRange` | `Relation/Op.e` 133, 129 | 3 | 3 |
| `setColumn` | `Relation.e` 60 | 4 | 3 |
| `lookbackJoin` | `Relation.e` 206 | 11 | 9 |
| `level1` | `Relation/RTree.e` 26 | 5 | 3 |
| `sumBy`, `sumBy'`, `count`, `count'`, `avgBy'` | `Layout/Scan.e` 43–48 | 2 | 2 |
| `drilldownPivotTabular`, `drilldownPivotTabular'` | `Layout/Report.e` 781, 794 | 3 | 2 |
| `cutoffGroupedFldsPosNegRel'` | `Layout/Report/Relation.e` 38 | 34 | 33 |

### 4.5 The hand-judged sample of ten

Ten of the nineteen, judged by hand against the published `.ei` signature.  "Determined?" is a
pen-and-paper answer to the semantic question — *given the universals, is the existential's value
forced?* — not another run of the closure.

| # | signature | constraints (row parts only) | flagged | determined in fact? | verdict |
|---|---|---|---:|---|---|
| 1 | `Relation/Predicate.(!=)` | `b <- (f,e)`, `a1 <- (e,d)`, `c <- (f,e,d)` | 3/3 | **yes**: `d = c \ b`, `e = a1 \ d`, `f = b \ e` | FALSE POSITIVE |
| 2 | `Relation/Op.cons_Bracket` | `b <- (e,f)`, `c <- (d,e,f)`, `a <- (d,e)` | 3/3 | **yes**, same shape | FALSE POSITIVE |
| 3 | `Relation/Op.dateRange` | `r1 <- (e,f)`, `c <- (d,e,f)`, `r <- (d,e)` | 3/3 | **yes**, same shape | FALSE POSITIVE |
| 4 | `Syntax/Relation.(&)` | `a <- (e,d)`, `r <- (d,c)`, `b <- (e,d,c)` | 3/3 | **yes**: `c = b \ a`, `d = r \ c`, `e = a \ d` | FALSE POSITIVE |
| 5 | `Syntax/Relation.(**)` | `b <- (g,f)`, `c <- (f,e)`, `d <- (g,f,e)` | 3/3 | **yes**, same shape | FALSE POSITIVE |
| 6 | `Relation.setColumn` | `r <- (o,s)`, `c <- (rs,so)`, `t <- (rs,so,ro)`, `r <- (rs,ro)` | 3/4 | **yes**: `ro = t \ c`, `rs = r \ ro`, `so = c \ rs` | FALSE POSITIVE |
| 7 | `Relation/RTree.level1` | `d <- (g,h)`, `d <- (a,c1)`, `b <- (g,f)`, `e <- (f,g,h)`, `d <- (i,r)` | 3/5 | **yes**: `f = e \ d`, `g = b \ f`, `h = d \ g` | FALSE POSITIVE |
| 8 | `Layout/Scan.count` | `r <- (h,t)`, both parts existential | 2/2 | **no** — `2^{\|r\|}` splits | TRUE POSITIVE, but the constraint is a TAUTOLOGY |
| 9 | `Layout/Scan.sumBy` | `r <- (h,t)`, both parts existential | 2/2 | **no** | TRUE POSITIVE, tautology |
| 10 | `Relation.lookbackJoin` | eight partitions, `a <- (d,c)` and `r1 <- (e,h)` among them | 9/11 | **no** — `d`,`c` split a universal `a` freely, and so do `e`,`h` on `r1` | TRUE POSITIVE, genuinely ambiguous |

**Seven of ten are false positives, and in this sample all seven fail for the same reason.**  In
each, the residual holds a partition and a *sub-partition* of it, and eliminating the
sub-partition as a block determines what is left: from `c <- (f,e,d)` and `b <- (f,e)` follows
`c <- (b,d)`, hence `d = c \ b`.  That step is the solver's own `resolution` (rule 6,
`Rowpartition.rule6`), and the closure of §2 does not have it.

**But "all seven for the same reason" must not be read as "all the false positives for the same
reason" — it over-generalises, and the R3 review (M-2) shows how.**  This sample was drawn from
the small-signature end of the nineteen and happens to exclude the two hardest cases.
`Relation/Predicate.(>=)` and `(<=)` (11 flagged row existentials each) are **false positives that
`resolution` does not clear**, and the reason is not a missing propagation step at all.  Their
residual carries `b = f ⊎ e`, `a1 = e ⊎ d` and `c = f ⊎ e ⊎ d`; the third says `f` and `d` are
**disjoint**, so `(a1 ∩ b) \ e = ∅`, and with `e ⊆ a1 ∩ b` that forces `e = a1 ∩ b` exactly, and
everything else follows.  The pin comes from a *disjointness obligation*, not from a value the
closure could propagate — which is `CriterionIncomplete.sound_not_complete`'s mechanism at corpus
scale.  No clause of the `roseAdd` / `cancelAdd` / `resAdd` family can reach it, and §4.7 confirms
by computation that the three-clause closure still flags both, 11 existentials each.

Of the three true positives, two (`count`, `sumBy`; and `count'`, `sumBy'`, `avgBy'` are the same
shape) are `exists h t. r <- (h, t)` with **both** parts existential and `r` **universal** — a
TAUTOLOGY, true of every row.  The criterion is right that they are undetermined and the right
response is deletion, not a warning; §3.2's second limit and the new ticket item say what that
would take.  Only `lookbackJoin` is a signature a user might actually want told about, and its
ambiguity is inherited from the `Has`-style `a <- (d, c)` with both parts existential.

**The reviewer's five, for the other end of the distribution.**  The R3 review hand-checked five
signatures this sample did not, with an exact per-label decision procedure rather than by hand:

| signature | row ex | flagged | genuinely undetermined | verdict | does `resolution` clear it? |
|---|---:|---:|---:|---|---|
| `Relation/Predicate.(>=)` :63 | 11 | 11 | **0** | FALSE POSITIVE | **NO** |
| `Syntax/Relation.(&_Mem)` :56 | 3 | 3 | **0** | FALSE POSITIVE | yes |
| `Layout/Report.drilldownPivotTabular` :781 | 3 | 2 | **2** | TRUE POSITIVE | not needed |
| `Layout/Scan.avgBy'` :45 | 2 | 2 | **2** | TRUE POSITIVE, a TAUTOLOGY | not needed |
| `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` :38 | 34 | 33 | **16** | TRUE POSITIVE at the SIGNATURE level; the criterion over-flags 17 of the 34 variables | partly (33 → 31) |

Two of five, against seven of ten here — and the last row is the one that matters for how a
warning would have to be worded: the signature really is row-ambiguous, but a warning that named
the flagged variables would name seventeen that are in fact pinned.  **Any warning must be
signature-level and must never name variables.**

### 4.6 What the numbers say about a warning

* **Under Rose's closure**: 88 of 104 published signatures flagged, 37 of 40 in `core/examples`.
  A warning on this criterion would fire on nearly every row-polymorphic signature in the corpus.
  Unusable.
* **Under Ermine's closure**: 19 of 104, none in `core/examples`.  Better by a factor of five, and
  it gets the corpus's own flagship case right in both directions (`pivotData` not flagged; the
  bare constraint of `TICKET-row-constraint-decision.md` §1.3 flagged, and genuinely ambiguous).
* **But the false-positive rate is high**: 7 of 10 on this report's sample, 2 of 5 on the
  reviewer's, and 10 of 19 taken over all nineteen with the exact procedure.  The brief's
  acceptance criterion for shipping a warning is "near zero".  It is not met.
* **One clause — RESOLUTION — removes most of them, and §4.7 says exactly how many.**
  `Determined.lean` §13 has it, with the uniqueness theorem re-proved (`resAdd`, `Determined3`,
  `determined3_unique`) and the smallest of the eight it clears as a kernel-checked instance
  (`NotEq.res_cures`).  It is **not** enough: two false positives survive it for a reason no
  clause of this family can reach (M-2 above), so "near zero" is not reachable by clauses.

### 4.7 The stage-2 number, computed — the third clause does NOT rescue the criterion

**The R3 review computed the number the recommended stage 2 would go and get, and it fails this
report's own acceptance criteria** (M-1).  The criterion is a closure over the *published*
residual, so the three-clause answer can be had without touching the compiler at all: reimplement
`roseAdd` / `cancelAdd` / `resAdd` from `Determined.lean` and run them on the `.ei`
qualifications.  The reviewer did that; **this report has since re-derived it independently**,
from its own serialized `.ei` snapshot (the 268 interfaces of §6) with its own transcription, and
gets the same table cell for cell.

| signature | row ex | 1 clause (Rose) | 2 clauses | **3 clauses** | genuinely undetermined |
|---|---:|---:|---:|---:|---:|
| `Predicate.(>=)` | 11 | 11 | 11 | **11** | 0 ← false positive SURVIVES |
| `Predicate.(<=)` | 11 | 11 | 11 | **11** | 0 ← false positive SURVIVES |
| `Predicate.(!=)` | 3 | 3 | 3 | **0** | 0 |
| `Syntax/Relation.(**)`, `(&)`, `(&_Mem)` | 3 each | 3 | 3 | **0** | 0 |
| `Relation/Op.cons_Bracket`, `dateRange` | 3 each | 3 | 3 | **0** | 0 |
| `Relation.setColumn` | 4 | 4 | 3 | **0** | 0 |
| `Relation/RTree.level1` | 5 | 5 | 3 | **0** | 0 |
| `Relation.lookbackJoin` | 11 | 11 | 9 | **8** | 8 |
| `Layout/Scan.sumBy`, `sumBy'`, `count`, `count'`, `avgBy'` | 2 each | 2 | 2 | **2** | 2 |
| `Layout/Report.drilldownPivotTabular`, `…'` | 3 each | 3 | 2 | **2** | 2 |
| `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` | 34 | 34 | 33 | **31** | 16 |
| **signatures still flagged, of 19** | | **19** | **19** | **11** | **9** |

**Against §5's own acceptance criteria, as they were written:**

* criterion 3 — "`core/examples` stays at zero **and** the stdlib count drops from 19 to at most
  six": it drops to **11**.  The six the report named are all still there and correctly so; the
  five it did not anticipate are `(>=)`, `(<=)` (false positives that no clause reaches) and
  `drilldownPivotTabular`, `drilldownPivotTabular'`, `cutoffGroupedFldsPosNegRel'` (genuine).
  **FAILS.**
* criterion 4 — "a second hand-judged sample of ten has at most one false positive in ten": only
  eleven remain and **two are false positives**, so a sample of ten expects 1.8.  **FAILS**, and
  not by a margin another clause could close.
* criteria 1 and 2 are met (the theorem is in the library; the byte-identity gate is the one this
  stage already passed).

**Two things that are genuinely good, and one that decides it.**  The eight signatures the clause
does clear it clears *completely* (3 → 0, not 3 → 1), and precision over the nineteen goes from
9 genuine of 19 flagged (47 %) to 9 of 11 (82 %).  It is a large improvement.  What decides the
question is that the remaining two false positives are pinned by a **disjointness obligation**
(§4.5), which is `CriterionIncomplete`'s mechanism: a *semantic* forcing that a syntactic closure
cannot see, whatever clauses it is given.  So "near zero false positives" is not a threshold this
family of criteria can be pushed to.

**Independent-implementation check, and a wider population.**  The re-derivation is over the
published `.ei` rather than over `pruned`, and it is a second implementation of the same clauses,
so the agreement is also the correspondence evidence §7 item 4 used to say it lacked.  Over the
whole published population it reads — 255 interface signatures carrying at least one row
existential, **248 flagged by Rose's clause, 77 by two clauses, 27 by three**.  That population is
not the §4.4 census (it includes signatures the user wrote out, and `incomplete/`), so the two
sets of numbers are not comparable cell for cell; the direction is the same and the nineteen agree
exactly.

## 5. R3.4 — recommendation

### (i) The splice guard — **NO.**  The theorem it would rest on is false.

The brief's acceptance criterion for a stage 2 on the splice is *"only if the licensed fraction
beats the withdrawn guard's 10 % by a margin **AND** the theorem in R3.2(a) holds"*.  The
theorem does **not** hold, and it fails in both directions on satisfiable four- and
five-variable systems with no concrete labels at all
(`SpliceGuard13.determined_splice_not_conservative`,
`SpliceGuard13.undetermined_splice_is_conservative`).  The frequency numbers are therefore not
the deciding factor, and they are reported above as a description of the corpus rather than as
evidence for a change.

The reason the idea cannot work is worth recording, because it is structural rather than
accidental: **the condition that actually decides conservativity of `reduce`'s splice is
syntactic.**  `hlhs` — "`v` heads no constraint of the emitted list" — is a property of what
`reduce` chooses to rewrite (right-hand sides only) and what it chooses to discard (the
partition it spliced with).  No closure on *models* can see it, because two systems with the
same models can differ on it.  Anything that fixes the splice has to change `reduce`, not guard
it: either append the partition it consumed (so that `splice_entails_iff` applies with `G`
replaced by `p :: G`), or rewrite left-hand sides too.  That is `Splice.lean`'s own §7 closing
note and R3 has not improved on it.

### (ii) The row-ambiguity warning — **NO, and the stage 2 is CLOSED, not pending.**

The brief's acceptance criterion is *"only if the false-positive rate on the sample is near
zero"*.  It is not met — 7 of 10 on this report's sample, 2 of 5 on the reviewer's, 10 of 19 over
the whole flagged set with an exact procedure — **so no warning should ship.**

An earlier draft of this section recommended a stage 2 (add `resAdd` to `Subst.Determinacy`,
re-measure) with four acceptance criteria.  **That stage's answer is now known and it is a "no"**:
§4.7 computes the three-clause number without touching the compiler, criteria 3 and 4 both fail,
and the two false positives that survive do so by a *semantic disjointness forcing* that no clause
of this family can reach.  The recommendation is therefore **do not run it**, and the stage is
recorded here as closed rather than scheduled.

**What the numbers say, once and for all.**

| criterion | `core/examples` flagged | stdlib flagged | of those, genuine | precision |
|---|---:|---:|---:|---:|
| Rose's clause alone | 37 of 40 | 51 of 64 | — | unusable |
| Ermine's two clauses (what R3 measured) | **0** | 19 | 9 | 47 % |
| three clauses (what stage 2 would have got) | **0** | 11 | 9 | 82 % |

The `core/examples` zero is the genuinely good result and it holds under both closures: **the
population a user writes is not flagged at all.**  What is left is eleven stdlib signatures of
which nine are genuine, and of those nine, **five are the tautology** `exists t h. r <- (t, h)`
with `r` universal, where the right response is to delete the constraint, not to warn about it
(and R3 has no theorem for that deletion — §3.2's second limit).  Strip those and the whole corpus
has **four** signatures a warning could usefully name, all in the stdlib.  Four is not enough to
justify a diagnostic, a flag, and a closure maintained inside `mkSimplified`.

**If anyone ever does write one**, two constraints fall out of the measurement and should be
recorded now:

1. **Signature-level, never per-variable.**  `cutoffGroupedFldsPosNegRel'` is flagged on 33 of its
   34 row existentials and 16 are genuinely undetermined: the signature verdict is right and the
   variable verdict names seventeen pinned variables.  A warning that named variables would be
   wrong more often than right on the largest signature in the corpus.
2. **A warning, never an error.**  `CriterionIncomplete.sound_not_complete` (§3.3) is the reason,
   and §4.5 shows it is not a curiosity: it is the mechanism behind the two surviving false
   positives.  The criterion is sound for "determined ⟹ unique" and one-sided in the other
   direction; nothing here licenses rejecting a program.

### (iii) What IS licensed — and the shape the corpus actually has is NOT it

`dead_delete_of_le_one_part` is a proved deletion licence with no side condition: a dead
existential whose defining constraint has at most one part (`v <- (u)`, `v <- ((|K|))`,
`v <- ()`) may be deleted from a published residual.  It is a theorem rather than a hope, and it
is the shape `mkSimplified`'s `isolated` pass is already reaching for.

**But R3 does not show the corpus to have that shape, and the shape it does have has no theorem
here** (R3 review M-3, accepted).  Both licensed forms are about a dead existential on the
**left**.  The five true positives §4.5 and §4.7 find are `exists t h. r <- (t, h)` with `r`
**universal** and both parts existential — a tautology (`t := r`, `h := ∅`), deletable, and
covered by neither `dead_delete_of_pairwise` nor `dead_delete_of_le_one_part`.  A stage built on
this subsection would be measuring a shape nothing here shows the corpus to have.

**So the one actionable item R3 leaves is the TAUTOLOGY DELETION, and it is a ticket, not a
stage.**  `tracker/TICKET-stdlib-findings.md` **C12** carries it: the statement, the two-line
proof it needs (a witness of the same kind as the reviewer's `RevCheck.pairwise_not_necessary`),
the five stdlib signatures it would shorten, and `ei-diff.sh` as the measurement — which is the
question §7 says the splice measurement could not answer, how many published interfaces actually
change.

## 6. Gates

### Lean

| gate | result |
|---|---|
| `lake build` | **green**, 870 jobs |
| `lake env lean Audit.lean` | **4,582 theorems audited, 0 declarations using a non-standard axiom.**  Baseline **re-derived, not quoted**, by removing the import and rebuilding: **4,446 / 0** (the R2 figure) |
| `sorry` / `axiom` / `native_decide` in `Determined.lean` | **0 / 0 / 0** |
| `#print axioms` on the 34 headline theorems | every one `[propext, Classical.choice, Quot.sound]`; saved in scratch as `axioms.txt` |

### Scala (worktree `ermine-scala-wt-r3`, branch `determined-closure`)

| gate | base | R3 | verdict |
|---|---|---|---|
| `sbt compile` | green | green | — |
| `sbt test` | 922 total, **1 failed**, 921 passed | 922 total, **1 failed**, 921 passed | **UNCHANGED** |
| the one failure | `Constraints.disjunction sound: Gave up after only 0 passed tests. 501 discarded` | the same | pre-existing, a generator gap, not a solver failure |
| `TestLoopTrace` | 720 solves, 720 segments, **720 agree** | **720 agree** | **720/720** |
| corpus `--batch`, tracing OFF (153 files) | — | — | **identical** |
| corpus `--incomplete --batch`, tracing OFF (34) | — | — | **identical** |
| corpus `--batch` / `--incomplete --batch`, tracing ON | — | — | **identical** |
| corpus PER FILE (153 files): base tracing OFF vs R3 tracing ON | — | — | **identical** |
| row trace minus `detm`/`ramb`, `loadInSeries` | 172,290 / 1,957,394 / 239,859 lines | same after filtering | **BYTE-IDENTICAL** |
| ...same-binary CONTROL | two base runs | — | **byte-identical**, so the comparison bites |
| `.ei` sweep, per file, interfaces ENABLED, `loadInSeries` | 268 interfaces | 268 interfaces | **BYTE-IDENTICAL** |
| `perf-bench batch -n 5` cold median | **10.97 s** (min 10.64, max 11.12, spread 0.48) | **10.95 s** (min 10.79, max 10.97, spread 0.18) | **unmoved** (−0.2 %, inside the base run's own spread) |

**Three normalisations, and why each is legitimate.**

1. *The loader's progress bar and every wall-clock figure the compiler prints.*  `\r` frames and
   `Loaded 129 modules (12.22 seconds)` differ between two runs of the same binary.  Removed from
   both sides before diffing corpus outputs.
2. *The row trace's ONE nondeterministic field*: the elapsed microseconds on an `rsound ok`
   record (`<#labels> <#partitions> <nodes> <micros>`).  Blanked on both sides.  The same-binary
   control in the table above is what establishes that this is the ONLY such field: with it
   blanked, two runs of the base binary agree on all 2.37 M records.
3. *The loader in SERIES* (`-Dermine.loadInSeries=true`) for the trace and `.ei` comparisons.
   With it, the `.ei` sweep needs **no** normalisation at all: 268 interfaces, byte for byte.
   Without it the two sides differ on 104 lines — every one of them a permuted constraint list
   inside an `exists`, or an alpha-renaming (`lookbackJoin`'s `h`/`c2`) — not something the
   instrument could have caused.  The default parallel loader hands out `Supply` ids in a nondeterministic order, and `Exists.apply`
   puts the published constraint list through `p.toSet.toList`, whose order is a function of those
   ids — so two runs of the SAME binary publish the same constraints in different orders and with
   different variable names.  That is the difference `A1-REVIEW.md` §4b classifies as ISO, and it
   is not something an instrument can be asked to preserve.  Serialising the loader removes it.

**Two honest notes on the run.**

* *Another agent was using the machine.*  Throughout the stage a second JVM was compiling in the
  MAIN checkout.  Everything above was measured in the worktree, whose `target/` is its own, so
  no comparison is affected — except `perf-bench`, which refuses to run beside another ermine
  JVM; both sides were taken in windows it accepted (`load_before` 0.02 and 1.23).
* *The first R3 `sbt test` run showed a second failure*, `TestInterfaceRoundTrip.new-pipeline cold
  write, fresh warm read` ("warm method `Some(Full)`").  It passes 3 of 3 in isolation and the
  suite came back to 1 failure on a full re-run.  Its own source comments name the cause: the
  dep cache is process-global and other suites' sessions bake `useInterface` into it.  A
  cross-suite flake, not a regression — and worth a ticket of its own.

## 7. Scope limits and open questions

1. **`Determined` is a closure on syntax, not a decision procedure for functional dependency.**
   `CriterionIncomplete` is the standing witness: `a <- (v, v, w)` forces `v` empty in every
   model and neither closure sees it.  Every "undetermined" count in §4 is an upper bound on
   genuine ambiguity.
2. **Nothing here is an entailment result.**  R2's PARTIAL (the mint-free fragment `MFStep`, and
   `nd_derives_not_entails`) is untouched and, as `R2-REVIEW.md` K-10 says, is not needed:
   Definition 13 mentions neither `⇒` nor models.
3. **`Holds` is the callee-chooses reading.**  Rose's Definition 14 quantifies universally.  The
   two are not identified anywhere in `Determined.lean`, and Theorem 15 is not transferred —
   Definition 14 is not well-defined for Ermine while there is no principality theorem.
4. **The Scala closure is a transcription, not a certified mirror — but it is now corroborated.**
   `Subst.Determinacy` computes the same two clauses as `roseAdd`/`cancelAdd` on the residual
   `reduce` and `mkSimplified` see, and its treatment of a concrete left-hand side
   (`whole = None`, "known outright") is the Lean carrier constraint `p <- ((|K|))` after one step
   of Rose's clause.  There is still no correspondence *theorem* of the `KeyedSplitScala.lean`
   kind.  What there is (R3 review M-7, and §4.7's re-derivation here) is evidence at corpus
   scale: **two further implementations written from the Lean — the reviewer's and this report's,
   both outside the compiler, both reading the published `.ei` rather than `pruned` — agree with
   `Subst.Determinacy` existential for existential on all nineteen flagged signatures**, and the
   reviewer's also reproduces seven kernel-checked Lean instances (`Has`, `Disj`, `Pivot.bare`,
   `Pivot.full`, `CriterionIncomplete`, `NotEq.res_cures`, the tautology).  That is three
   independent implementations agreeing; it is not a proof, and it says nothing about the `detm`
   half, which reads `cs` and not a published interface.  The `splice`/`detm` side-condition
   agreement in §4.3 certifies the three side conditions and not the closures.
5. **The third clause is PROVED in the compiler's absence.**  `resAdd` / `Determined3` /
   `determined3_unique` are in the library and `NotEq.res_cures` checks one instance in the
   kernel, but `Subst.Determinacy` computes the TWO-clause closure only, so every `ramb` number in
   §4.2–§4.6 is the two-clause criterion's.  §4.7's three-clause figures come from running the
   clauses over the published `.ei` outside the compiler, twice and independently — which is why
   no stage 2 is needed to obtain them.  One small gap for anyone who ever does put the third
   clause in the compiler: `Determined.lean` §13 defines `Determined3` but no `Row3Ambiguous`, so
   the criterion itself is still stated only over the two-clause closure.  Trivial to add, and it
   would have to be added first.
6. **The measurement counts splices, not consequences lost.**  `ei-diff.sh`'s question — how many
   published interfaces actually change — is the one a user can see, and the `.ei` gate in §6
   answers it for the instrument (zero) and not for any hypothetical guard.
7. **`U₀` has one unnamed exception, in the safe direction** (R3 review M-6, PLAUSIBLE, not
   observed).  §4.1 says `U₀` is exactly `fv(τ) ∪ universals` as far as the closure can tell.
   An existential dropped from `pubExts` by `am` — `ambiguitiesIn` on the CLASS constraints — can
   still occur in a row part of `pruned`, and the instrument would then count it in `U₀` as a
   universal.  `iso` cannot do this (it filters `dumb` too); `am` is not filtered out of `dumb`.
   The direction is **under**-flagging, so it cannot manufacture a false positive, and it was not
   observed: the reviewer's independent recomputation matched the instrument on every one of the
   nineteen.  A stage that turned the criterion into a diagnostic would have to close it.

## 8. Fix round (R3 review)

`tracker/loopmodel/R3-REVIEW.md`, 622 lines, verdict **FIX-THEN-ADVANCE**: nothing in the Lean or
the instrument changes, three documents do.  Every finding is applied below; **`Determined.lean`,
`RowTrace.scala` and `Subst.scala` are untouched by this round**, so no Lean or Scala gate needed
re-running.

| finding | rank | what it said | what changed |
|---|---|---|---|
| **M-1** | HIGH | The recommended stage 2 fails this report's own acceptance criteria: the three-clause closure flags **11 of the 19**, not "at most 6", and 2 of the 11 are provable false positives, so criterion 4 fails too.  The plan row and memo note schedule work whose answer is known. | New **§4.7** carries the table, and this report **re-derived it independently** from its own serialized `.ei` snapshot with its own transcription of `roseAdd`/`cancelAdd`/`resAdd` — same 19 rows, cell for cell, 11 still flagged.  **§5(ii) rewritten**: the stage 2 is CLOSED with a "no", not recommended.  §0, the plan row and the memo note follow. |
| **M-2** | MED | "Seven false positives, all for the SAME reason" over-generalises from a sample that excludes the two hardest.  `Predicate.(>=)` and `(<=)` are false positives `resolution` does **not** clear: they are pinned by a *disjointness obligation* (`f ⊥ d` forces `e = a1 ∩ b`), which is `CriterionIncomplete`'s mechanism. | **§4.5** sentence corrected and the mechanism spelt out; the reviewer's five hand-checked signatures added as a second table, including `cutoffGroupedFldsPosNegRel'` (33 flagged, 16 genuine) and the rule it implies — **any warning must be signature-level and must never name variables**.  §4.6 and §0 follow. |
| **M-3** | MED | `dead_delete_of_pairwise` is sufficient, **not necessary** (kernel-checked counterexample: `v <- (w, y)` with `v` and `w` both existential is `REquiv`-deletable and the side condition fails); and neither licensed form covers the shape that dominates R3's own true positives — the tautology `exists t h. r <- (t, h)` with `r` **universal**. | **§3.2** now states it as sufficient, carries the counterexample, and names the uncovered shape.  **§5(iii)** rewritten: what R3 licensed is not what the corpus has, and the actionable item is the tautology deletion as a **ticket**. |
| **M-4** | LOW | "1,245 lines, **124 theorems**" is wrong in three places.  Real: **163 source declarations** (115 `theorem`, 47 `def`, 1 `structure`), **197 non-internal constants of which 136 are theorems** — exactly the Audit delta 4,582 − 4,446. | Corrected in **§1**, the plan row and the memo note.  Re-derived here: `grep -cE '^theorem '` = 115, `^def ` = 47, `^structure ` = 1.  The module docstring carries no counts, so `Determined.lean` did not change. |
| **M-5** | LOW | The stdlib-boot row of §4.2 is a lottery: three runs of one binary gave 192/193/192 splices and 41/34/41 Rose-licensed.  Batch is exact; per file within 0.009 %. | **§4.2** now labels the boot row "one draw" and carries the spread, the batch/per-file contrast, and the fact that `Rose ∧ guard = 0` held in every draw. |
| **M-6** | LOW, PLAUSIBLE | An existential dropped from `pubExts` by `am` can still occur in a row part of `pruned` and be counted in `U₀` as universal.  Direction: **under**-flagging.  Not observed. | Recorded as **§7 item 7**, with the direction and the fact that the reviewer's independent recomputation matched the instrument on all nineteen; **§4.1** points at it. |
| **M-7** | INFO | §7 item 4's "no correspondence check" now has evidence: an independent implementation matches `Subst.Determinacy` on all 19 flag counts and reproduces seven kernel-checked Lean instances. | **§7 item 4** rewritten to cite it — three independent implementations now agree — while keeping the honest part: it is not a proof, and it says nothing about the `detm` half, which reads `cs` rather than a published interface. |
| reviewer's action item | — | Open a ticket for the TAUTOLOGY DELETION rather than a stage. | **`tracker/TICKET-stdlib-findings.md` C12** (section **C, "Wrong, misleading or missing API"** — the file has no solver section, and a published signature carrying a vacuous constraint is an API defect).  It carries the statement, the theorem it needs, the five stdlib signatures, `ei-diff.sh` as the measurement, and the acceptance criteria. |

**Findings NOT accepted: none.**  Every one is applied as written.  Two places where this round
went further than the review asked, both because the review's own evidence made it cheap:

* **M-1's number was re-derived here rather than quoted.**  §4.7's table is this report's own
  computation over its own `.ei` snapshot (`eiclosure.py` in scratch, ~90 lines, written from
  `Determined.lean`), and it agrees with the reviewer's cell for cell.  That also turns M-7's
  "an independent implementation" into "two", which is what §7 item 4 now says.
* **The wider population.**  The same run over all 268 published interfaces gives 255 signatures
  with a row existential, 248 / 77 / 27 flagged by one / two / three clauses.  It is a different
  population from §4.4's census and is labelled as such.

**Not re-run, and why.**  This is a documents-only round.  `lake build`, `Audit.lean`, `core/test`,
`TestLoopTrace`, the trace and `.ei` byte-identity gates and `perf-bench` are unchanged from §6
because no Lean or Scala file was touched; `git diff --stat` in the main tree is documents plus
the untracked report and module, exactly as before.  The reviewer independently re-ran all of them
(their §5) and reproduced every one.
