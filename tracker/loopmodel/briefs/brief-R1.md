# Brief: R1 — Rose and its successors versus Ermine's row solver: a comparison memo and adoptable ideas

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`. THIS IS A READING AND WRITING
STAGE: no Scala edits, no Lean module edits, no commits, no `lake build` of any kind (three other agents are
running the built `looptrace` binary on this machine and a relink breaks them); you MAY elaborate a SCRATCH Lean
file with `lake env lean <file>` from `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`, `LEAN_NUM_THREADS=2`)
to test a definition against the existing library. Deliverable: `tracker/ROSE-COMPARISON.md`. Scratch under
`/home/dmitry/.claude/jobs/880c725d/tmp/R1/`. Web access (`WebSearch`/`WebFetch`) is allowed and expected.

THE QUESTION (user, 2026-09-06): "are there further parallels between our work and that of Rose and successors?
Could we adopt any ideas? Is this something that could be explored by an agent?" — Ermine's row types are
partition constraints `a <- (b, c, (|k|))` (a row is the disjoint union of parts and a concrete field set),
solved by a saturation loop (`Constraints.incorporateAll`) that mints fresh row variables (splitConcrete,
resolution) and publishes the surviving constraints as the residual qualification of a signature. The loop-model
programme (`tracker/LOOP-MODEL-PLAN.md`, `tracker/ROW-CONSTRAINT-STATE.md`, reports under `tracker/loopmodel/`,
Lean library `tracker/lean/Rowpartition/` incl. `Loop/*`) proved on a trace-equal Lean model: soundness (S1:
`NoLoss`/`SEntails`/`Conserv` semantics; rejection soundness), no-false-acceptance with a complete per-label
decision (S2: `labelDecide_sat_ssat`, `solve_noFalseAccept`, `solve_accepted_faithful`), termination under a
draw budget for any dequeue policy (D1), and found that the loop is refutation-incomplete, that its published
residuals are order-dependent in form (`A1-REVIEW.md`: one binding strictly more general under another order;
`incomplete/Signatures.e` proves the redundant "noise" constraints away by hand), and that satisfiability of the
constraints is NP-complete (monotone 1-in-3-SAT encodes into `a <- (x,y,z)` + `a <- ((|l|))`).

READ: Morris & McKinna, "Abstracting Extensible Data Types: Or, Rows by Any Other Name" (POPL 2019) — the Rose
calculus: qualified types over a ROW THEORY with predicates `ρ1 ⊙ ρ2 ~ ρ3` (combination) and containment, records
`Π ρ`/variants `Σ ρ`, entailment axiomatised per theory, principal types with residual predicates; its
successors — Hubers & Morris, "Generic Programming with Extensible Data Types; or, Rows by Any Other Name Redux"
(ICFP 2023, the Rω calculus with row-indexed type functions) and any mechanisation of Rω (Agda) you can find;
plus the background the memo must place them in: Rémy's row polymorphism (polynomial, no concatenation), Wand's
record concatenation (1989/1991), Harper & Pierce's symmetric concatenation (1991), Palsberg & Zhao's
NP-completeness for concatenation with subtyping (2004 — VERIFY the exact statement), Leijen's scoped labels
(2005), Ur/Web's disjointness constraints (Chlipala), disjoint polymorphism (Alpuim/Oliveira/Shi 2017), and
GHC's constraint-solver iteration limit as the budget precedent. Then our side: `tracker/ROW-CONSTRAINT-STATE.md`
in full, `tracker/loopmodel/S1-SOUNDNESS.md` §S1.1–S1.4, `S2-DESIGN.md`, `A1-REVIEW.md` (the binding
classification), `core/examples/incomplete/Signatures.e`, `tracker/lean/Rowpartition/{Basic,Divergence}.lean`
(`Sat`, `Models`, `Entails`, `SModels`), `Loop/Strict.lean` (`NoLoss`, `Conserv`, `SEntails`), `Loop/Refine.lean`
(`LoopRel`'s constructors = the rule set), `Rowpartition/Cut.lean`/`KeyedSplit.lean` (the split guards), the
`Constraints.scala` rules (`splitConcrete`, `resolution`, `commonSubexpression`, `substitution`, `cancellation`,
`selfSubstitution`, `makeEmpty`, `makeConcrete`, `unify`).

## Deliverable: `tracker/ROSE-COMPARISON.md`, in this order

1. **The correspondence, rule by rule.** A table: Ermine's constraint forms and each loop rule ↔ the Rose
   predicate(s) and entailment axiom(s) they correspond to (and which row THEORY Ermine implements — simple
   rows, no duplicates, no scoping? say precisely, with the evidence: `RHS.merge`'s "Fields appear twice"
   refutation, `Partition.equals` ignoring tags, the label check). Rules on one side with no counterpart on the
   other are the interesting rows: say whether Rose's entailment derives them or whether Ermine's set is
   missing one (a rule Rose has that Ermine's saturation lacks is a candidate explanation for the
   refutation-incompleteness S1's review found).
2. **Verify or correct the recollections** in the orchestrator's summary to the user (quoted at the end of this
   brief): what Rose proves about entailment (soundness w.r.t. a semantic theory? completeness? decidability?
   any complexity statement?), whether principal types hold and under what restriction, what the successors add
   and whether a mechanisation exists, and the exact Palsberg–Zhao result.
3. **Adoptable ideas, ranked by payoff over cost**, each with: what it is in Rose's terms, what it would change
   in Ermine (which Scala function, which Lean definition), what it would fix (name the measured problem:
   order-dependent residual form `A1-REVIEW.md` §R-1/R-6; the noise constraints of `Signatures.e`; the `.ei`
   cache-key gap; the call-site cost cliff of `core/examples/Ai/README.md`; refutation incompleteness; pivot's
   partially-typed output row `Relation/Pivot.e`), the risk, and a cost estimate in agent-stages. The three the
   orchestrator named — (a) canonical simplification of residuals via entailment-equivalence, (b)
   entailment-based call-site checking with the S2 decision as oracle instead of re-saturation, (c) a formal
   correspondence theorem between Ermine's rule set and Rose's axioms — must each get a verdict; add others.
4. **A first specification of (a)** against our Lean definitions, in a SCRATCH file elaborated with `lake env
   lean` (not added to the library): `Canonical : System → System` with the properties it must have
   (`SEntails`-equivalence both ways with the input; order-independence: two entailment-equivalent systems map
   to the same canonical form, or state the weaker property that is achievable; minimality); say what Rose's
   simplification does that this needs, and whether the per-label decision procedure (`labelDecide`) can serve
   as the entailment oracle inside it. Do not prove; specify, and note what would be provable.
5. **Citations** with links, and a short "what I could not verify" list.

The orchestrator's recollections to check (verbatim): "Rose's row combination predicate ρ1 ⊙ ρ2 ~ ρ3 is
Ermine's ρ3 <- (ρ1, ρ2), and its containment predicates play the role of Has"; "Rose keeps unsolved row
predicates in the inferred type, which is what gives it principal types"; "Rose simplifies to a canonical set
via entailment; Ermine saturates, minting fresh row variables, and publishes whatever survives"; "Rose's core
algorithmic question is 'does this context entail that predicate', proved sound against a semantic
definition"; "Rose separates the calculus from the row theory and its axioms"; "the successor calculus adds
row-indexed type functions for generic programming over records and variants"; "Palsberg and Zhao established
NP-completeness for a calculus with concatenation and subtyping"; "GHC's constraint solver has an iteration
limit and gives up with an error".
