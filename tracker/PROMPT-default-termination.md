# Do the shipped row defaults terminate? And can `keepDefs` mint?

Continue the Ermine row-solver work on branch `scala3-migration`. Two questions are
open, both narrow, both Lean-first. The working tree is clean and everything from
2026-09-02 is committed.

Question 1 is expected to come back **negative** — a counterexample, not a theorem.
Question 2 is expected to come back **positive**. Neither expectation is evidence;
both have been wrong before in this project.

## Method (unchanged, and it is the point)

Lean leads, code follows. Our own reasoning is not trustworthy here — several
confident claims on 2026-09-02 were wrong and were caught only by measurement or
by Lean. So: state the property, prove it in `tracker/lean/Rowpartition/`, and
only then touch Scala. If a property resists proof, that is evidence about the
design — report it and reconsider, rather than shipping and hoping. **Prefer
proving a negative (a counterexample, a non-existence) over asserting a
limitation.**

`tracker/lean/README.md` is the per-theorem authority for the existing
formalisation — **verify its claims rather than trusting them.** It carries at
least two known self-reported discrepancies (see its `NameLoss` section, final
paragraph) and this prompt's citations were checked on 2026-09-02 but should be
re-checked before you rely on one.

## Read this before stating either question: the rule set is not the loop

Every step relation in the development — `CutStep`/`CutSteps`, `ResStep`, `GResStep`,
`SplitStep`, `NonGenStep` — is **additive**: any applicable rule may fire, at any time,
on any member of `G`. `Constraints.incorporateAll` is **single-pass**: it dequeues a
partition once, scans all pairs against `proc` as it stands at that moment, and never
re-examines it.

This gap is not hypothetical and it has already bitten, in the one place the development
looked: after `makeConcrete` deletes a definition, `splitConcrete`'s guard is satisfied
again, so a re-mint is ENABLED (`NameLoss.orderB_remint_enabled`) — and the loop never
re-enqueues the partition, so nothing recovers (`NameLossClosed.orderB_stuck`). **The
additive calculus is complete on that input and the single-pass implementation of it is
not.** That is the shape of the whole substitution-gap episode: the defect was between
the rule set and the loop, not inside the rule set.

The implication runs one way. Every step `incorporateAll` takes is a legal rule step, so

    implementation diverges  ⇒  rule set diverges       (but NOT conversely)

Consequences you must respect in both questions below:

* A **positive** result over the additive relation is stronger than needed and transfers
  down to the compiler for free.
* A **counterexample** over the additive relation does NOT show the compiler hangs. It
  refutes the claim the four documents actually make — which is about the rule set — and
  that is worth having, but the compiler-level question then stays open and the write-up
  must say so rather than eliding it.
* The bridge, if you want one, exists: `tracker/repro/nameloss/run.sh` calls the real
  `Subst.solve` on an exact constraint list with exact variable ids and was verified to
  reproduce both regimes' trace summaries byte-for-byte. It is how the NameLoss work took
  a Lean witness down to the implementation, and it is the obvious instrument for taking
  one there again. (It is now a regression check — under the fixed solver every row pins.)

Precedent for stating this honestly rather than eliding it: `Cut.resSeed_diverges` is a
real divergence theorem, and the README pairs it with the admission that `resolution` and
`splitConcrete` fire **zero** times in a 129-module boot — "an empirical answer, and not a
termination theorem."

## The shipped configuration, verified 2026-09-02

`Constraints.scala`, `object GenRules`, all read once at class-init:

| property | default | line |
|---|---|---|
| `ermine.genRules` | `"cut"` — `cseMints=false`, `splitMints=true`, `resolves=true` | :715 |
| `ermine.labelCheck` | `true` | :726 |
| `ermine.resGuard` | `true` | :752 |
| `ermine.labelCheckEarly` | `true` | :773 |
| `ermine.disjunction` | `false` | :721 |
| `keepDefs` (no property — unconditional since `a4b62c0`) | on | :1133-1136 |

So the shipped rule set is: the non-generative rules, plus `splitConcrete`'s
guarded mint, plus **guarded** `resolution`, with a per-concrete-label refutation
run on the INPUT before saturation, and with `makeConcrete` keeping the
concretised variable's ≥2-abstract definitions.

## Question 1 — is "complementary" a theorem or a hope?

### What four documents say

`TICKET-row-solver-8abc.md` (twice), `TICKET-editor-and-solver-followups.md` §8
and `tracker/lean/README.md` (twice) all say the guard and the label check are
**complementary defences**. The reasoning, everywhere, is:

* guarded `resolution` terminates on every SATISFIABLE system
  (`ResGuardTerm.guarded_terminates_of_satisfiable`, `ResGuardTerm.lean:493`);
* it does NOT terminate in general — `ResGuardDiverge.gSeed_diverges` (:362) and
  `gres_no_decreasing_measure` (:379) give four constraints admitting guarded
  chains of every length;
* but `gSeed` is unsatisfiable (`gSeed_unsat`, :395) and the label check kills it
  at one label in five steps (`gSeed_refuted`, :466).

### What is actually proved

That the label check refutes **`gSeed`**. One seed. Nobody has stated, let alone
proved, the general bridge:

> **(C-rule)** Every system on which the shipped default rule set admits chains of
> unbounded length is `Refuted` by per-label propagation on its INPUT.

Without (C-rule), the two proved halves cover *satisfiable* inputs and *some*
unsatisfiable ones, and nothing covers the rest. The shipped compiler would then
have **no termination guarantee on ill-typed input** — it could hang on a type
error instead of reporting it, which is the failure mode this entire line of work
began from.

The name is deliberate: (C-rule) is stated over the ADDITIVE relation, which is the
claim the four documents make and the only one the existing vocabulary can express.
See "the rule set is not the loop" above for what each answer to it buys, and expect
to report the compiler-level status separately rather than letting (C-rule) stand in
for it.

### Why (C-rule) is expected to be FALSE, and where both halves already live

The development already contains the two ingredients:

* `LabelProp.Incomplete.unsat_and_not_refuted` (`LabelProp.lean:508`) — a system
  with no model that propagation provably does not refute. `Incomplete.forced_char`
  (:427) characterises exactly what propagation can derive there, so the failure is
  pinned, not observed.
* The check "ranges only over labels occurring in a `ConcreteRho`, so a general
  helper signature with no concrete instance has no labels to check and is
  untouched" (README, `LabelProp` section). Label-free systems are ordinary in this
  language, not exotic: `Splice.DroppedPartition.dropped_can_lose`
  (`Splice.lean:618`) is a satisfiable four-variable system **with no concrete
  labels at all**.

So the target is a system that is simultaneously (a) unsatisfiable, (b) divergent
under the shipped rule set, and (c) not refuted — ideally by being label-blind
where it matters. `gSeed` is the divergence skeleton; `Incomplete`'s system is the
refutation-blindness skeleton. **Composing them is the work.**

Do not stop at "we could not build one." A failed search is not a proof of (C-rule).
If the composition resists, say precisely which of (a), (b), (c) obstructs it —
that is itself a result about why the defences interlock.

### The formal statement, and the vocabulary that exists

`SplitNecessary.lean:587-600` already defines the shipped rule set's shape:

    inductive NonGenStep  : System → System → Prop   -- cse | split | cancel | subst
                                                     -- | selfSubst | commonPart
    inductive CutRuleStep : System → System → Prop   -- nongen | mint (SplitStep)
                                                     --        | res  (ResStep)

`CutRuleStep` is the cut with UNGUARDED resolution. The shipped default replaces
`res` with the guarded rule, `GResStep` (`ResGuard.lean:127`, with `GResSteps` at
:375). Define `DefaultStep` as `CutRuleStep` with that substitution — that
definition does not exist yet and is the first thing to write. Then (C-rule) is

    ∀ G₀, (∀ n, ∃ G, DefaultSteps n G₀ G ∧ G₀.card + n ≤ G.card) → Refuted G₀.toList

with `Refuted : List Constraint → Prop` from `LabelProp.lean:167` — note the type
mismatch, `System = Finset Constraint` (`Divergence.lean:178`), so a `.toList`
bridge is needed; `gSeed_refuted` already does this.

Match `gSeed_diverges`'s formulation of divergence (a growth bound at every `n`)
rather than inventing a new one, so the counterexample composes with what exists.

**If the answer is a counterexample, one further step is owed.** A witness refuting
(C-rule) shows the RULE SET can diverge unrefuted; it does not show `incorporateAll`
does, because the loop takes only some of the available steps. Either

* replay the witness through `tracker/repro/nameloss/run.sh` against the real
  `Subst.solve` and report what the implementation actually does (hangs, terminates,
  or refutes) — this is the decisive version and is not expensive; or
* state plainly that the compiler-level question is open, and say which of the
  witness's steps the single-pass loop would have to take.

Do not report "the compiler has no termination guarantee" on the strength of
(C-rule) alone. Reporting "the claim four documents make is false, and here is what
the implementation does about it" is the honest and more useful result either way.

### What changes if (C-rule) is false

`TICKET-row-constraint-decision.md` §7 Stage 5 is a rule-application **work
budget** — a counter of `(u,rhs1) × (v,rhs2)` pairs examined plus one per `insert`,
`tml.die` on exhaustion — described there as "a last resort that never fires" and
currently unbuilt and unscheduled. If (C-rule) is false, nothing in the development
bounds the shipped rule set on unsatisfiable input, and that budget becomes the only
candidate for a guarantee. Whether it should be SCHEDULED depends on the second step
above: a rule-set counterexample that `incorporateAll` provably walks into makes it
urgent; one the loop cannot reach makes it insurance whose premium is now known. Say
which case you are in — that is the decision this question exists to inform.

Also retire the word "complementary" from the four documents above, replacing it
with what is actually proved (the guard covers satisfiable systems; the label check
covers `gSeed` and, in general, only what propagation can force).

## Question 2 — `keepDefs` shipped on a prose argument

`destructiveSub` (`Constraints.scala:1133-1136`) keeps the concretised variable's
definitions with two or more abstract parts. Adopted UNCONDITIONALLY on 2026-09-02
(`a4b62c0`) on soundness plus measurement. `TICKET-substitution-gap.md` §7 is
explicit about what was not established:

> What was NOT re-proved, and what stands in for it: **Termination.** The kept
> definitions re-enable only the reuse/fold branch of `commonSubexpression` and
> `substitution`, which mint nothing; `resolution` needs single-variable forms,
> which a two-abstract definition is not.

That is a checkable claim, and the model of the change already exists and is
faithful — `NameLoss.concretizeKeep` (`NameLoss.lean:98`) carries the same
`2 ≤ (vset c).card` predicate as the Scala:

    def concretizeKeep (u : Var) (C : Row) (G : System) : System :=
      concretize u C G ∪ G.filter (fun c => c.lhs = u ∧ 2 ≤ (vset c).card)

The statement to prove is that the kept constraints cannot enable a minting rule:
for every `c` in `concretizeKeep u C G \ concretize u C G`, no `SplitStep` and no
`GResStep` fires on `c` that did not fire before — so the delta is `NonGenStep`-only
and the change cannot introduce divergence. `resolvent_unique` and `Resolved`
(`ResGuard.lean:79, :343`) give the shape `GResStep` requires; `SplitStep`
(`Cut.lean:1026`) gives the other.

If the claim is false as stated, find the weakest true version — e.g. it may hold
only for the `srs`-nonempty branch that `keepDefs` actually guards
(`val keepDefs = !((srs isEmpty) && keep)`), which the prose does not mention.

Here the additive/single-pass direction is favourable and needs only a sentence in the
write-up: a rule-set no-minting property implies the loop's, because the loop's steps
are a subset. So unlike Question 1, a positive answer settles the shipped behaviour
outright. Note also that the worry the prose is answering ("could keeping these
definitions introduce divergence?") is exactly a rule-set worry, so the statement and
the claim line up.

Soundness is already done and does not need redoing: `NameLoss.concretizeKeep_sound`
(:150), `keep_recovers_fact` (:437), `NameLossClosed.keep_vs_delete` (:285).

## What a good answer looks like

1. **Question 1 decided**, in Lean, in one direction: either (C-rule) proved, or a
   witness system with the three properties and the theorems that establish each,
   plus the compiler-level step the counterexample branch owes.
   Evidence, not argument.
2. **Question 2 decided**, in Lean: the no-minting property, or the weakest true
   version of it with the hypothesis the prose omits made explicit.
3. **Every result labelled with which claim it settles** — the additive rule set or
   `incorporateAll`. The development has no vocabulary for the second, so a result
   about it is a measurement, not a theorem; say which you have. This is the single
   easiest way for this session to produce something subtly wrong.
4. A `#print axioms` line for every headline theorem added, and an `Audit.lean`
   run after integration. The current figure to beat is **1625 theorems audited,
   0 using a non-standard axiom** — re-measure it, do not inherit it.
5. The four "complementary" sentences corrected, and a one-paragraph verdict in
   `tracker/ROW-CONSTRAINT-STATE.md` on whether §7 Stage 5 becomes scheduled work.
6. No Scala change is expected from either question. If one turns out to be
   licensed and small, propose it behind a flag defaulting OFF, with measurements —
   do not adopt it.

## Documents that will mislead you

* **`TICKET-signature-resolution-fragility.md` is STALE.** Its headline "CONFIRMED
  DEFECT: build order decides a published type" was fixed by `a4b62c0` and the
  ticket was never updated. Re-verified 2026-09-02: clean-disk and
  interfaces-on-disk regimes now produce byte-identical `.ei` for
  `Ai/HeadcountPlan`, and all four SHAPE regressions (`HeadcountPlan.{labelled,
  withUnitCost}`, `BatteryCycling.withHealth`, `RevenueByPeriod.labelled`)
  publish concrete rows.
* **`TICKET-row-solver-8abc.md` §"The signature surface"** still reports those four
  as an open regression and concludes 8b's repair needs re-examination. That
  inference is dead — the mechanism was the id race in `incorporateAll`, not the
  8b splice.
* **`TICKET-editor-and-solver-followups.md` §9** says the fragility claim is
  "UNSUPPORTED". It was later reinstated, then fixed. Both that section and the
  ticket it points at are wrong, in opposite directions.
* **`TICKET-row-constraint-decision.md`'s status line** ("No Scala changed") predates
  four shipped defaults.
* `ROW-CONSTRAINT-STATE.md` does not mention `a4b62c0` at all, though it was
  updated after it.

## Traps that cost time on 2026-09-02

* **`decide` cannot see through `mk`, `slist` or `vset (mk ..)`** — `slist` is
  `Finset.sort`, well-founded recursion the kernel does not unfold. Rewrite with
  `simp` (`vset_mk`, `conc_mk`, `lhs_mk`, `NameLoss.mk_eq_iff`) first, then `decide`
  on the residual literal-`Finset ℕ` goals. The `nl_decide` / `nlc_decide` /
  `nld_decide` macros package this.
* **Constant collisions across modules are real.** The root has already hit three
  (`Steps`, `exists_fresh`, `models_append`); two were latent because nothing had
  imported both modules together. Build `Rowpartition` from the root, not just your
  file, before claiming a result.
* **A zero is suspect until the instrument is shown capable of a non-zero.** If you
  measure anything in Scala, run a positive control:
  `core/examples/incomplete/unsound0[1-4]*.e` flip LOADED → REJECTED under
  `-Dermine.labelCheck`.
* **Always run the EXAMPLES, not just the stdlib**, if you measure at all:
  `resolution` fires on 18 example modules and ZERO stdlib ones.
* `bin/ermine` on a single `core/examples/Ai/*.e` reports `Module not found:
  'Ai.Common'` — put `Common.e` first on the command line. (Known defect, tracker
  follow-ups §2.)

## Constraints

* **Disk is tight.** `tracker/lean/.lake` is already 7.6 GB. Never run
  `lake exe cache get`, never add a Lean `require`, never create another Lean
  project, never touch `~/research/leanwork`. `Rowpartition/CutSearch.lean` OOMs at
  15 GB and is deliberately NOT in the root import list or the axiom audit — leave
  it out.
* Toolchain: `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`
  for anything Scala; `~/.elan/bin` for Lean.
* Baselines, measured 2026-09-02 and green: `sbt core/test` 903/904 (the known
  `Constraints.disjunction sound` generator starvation, 271s), `repl-smoke` 4/4,
  `lsp-smoke` 98/98, 129 stdlib modules load. Never commit red.
* **Do not commit or merge without asking.**
* Re-measure rather than inherit any figure in this prompt.
