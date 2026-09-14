# Brief: E11b probe — does the PROVED non-generative canonicaliser collapse the E11 set class? (measurement only, 2 h)

Repo `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD `b3da015e` (item E11a landed). You
change NO source and NO tracker file except your report `tracker/loopmodel/E11b-PROBE.md`; scratch under
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/e11b/`. Lean toolchain:
`export PATH=$HOME/.elan/bin:$PATH; cd tracker/lean` (`lake env lean --run <file>` or `lake env lean <file>` with
`#eval`; the library is built — do NOT run `lake build` of the whole library, and do not add files under
`tracker/lean/Rowpartition/`; put your script in scratch and import `Rowpartition.Canonical`). No JVM needed. Budget
2 hours; at the budget, write up what you have.

## The question

Item E11a (report `tracker/loopmodel/E11a-CANON.md` §4, §15 R-3; review `E11a-REVIEW.md`) left 6-8 published bindings
whose constraint SET differs between two cold checks of one unchanged file: the solver keeps an entailed constraint in
one run and drops it in another. Example (`Relation.e:lookbackJoin`, from the review §"The 47"): AFTER = BEFORE minus
one conjunct, and that conjunct "follows from three survivors by substitution".

`tracker/lean/Rowpartition/Canonical.lean` implements the six NON-generative row rules (`occurs`, `selfDedup`, `absorb`,
`dedup` up to RHS permutation, `common`, `unify`) with proofs that every step preserves the model set exactly
(`Step.preserves`, `canonN_preserves`) and terminates (`Step.decreasing`, `exists_fuel`). The driver is
`canonN : Nat → State → State` over `State := {solved : List (Var × Var), cs : List Constraint}` with
`Constraint := {lhs : Var, vars : List Var, conc : Finset Label}` (`Basic.lean`). Read the file's header and §11 for
what is NOT implemented (cancellation, definitional substitution).

**Does `canonN` map the two observed variants of each set-class binding to the SAME normal form?** If yes for all,
E11b is a port of a proved algorithm. If no for some, say exactly which rule is missing (by exhibiting the leftover
difference) and whether it is one of the two unimplemented rules or needs entailment.

## Inputs

`<scratch>/e11a/set-pairs.txt`: tab-separated `SET`, file, binding, then the observed renderings (inspect the
format — the renderings are Ermine's printed schemes with `(exists (c: rho) ... . r1 <- (r, c), ...) => body`;
a concrete row prints `(|l1, l2|)`; kind annotations `(x: rho)` mark row variables; class constraints like
`RelationalComb rel` are NOT row constraints and are dropped from the Lean system). Nine lines cover
`Relation.e:lookbackJoin`, `Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'`, `Present/WriterOutputs.e:reportFor`,
`Yahoo.e:investmentTableData`, `joinCumRet`, `joinTotalValue`. Add the review's extra members if you can get their
two forms cheaply from the implementer's `<scratch>/e11a/logs/ttc2.log` or the review's `<scratch>/review-e11a/`
(`Layout/Report.drilldownKeyValueTable2`, `incomplete/RevenueShare.shareOfGroup`, `incomplete/np01.inferredRestate`);
if not, say so.

## Method

1. Write a converter (Python or Lean) from a rendered scheme's row-constraint part to a Lean `State` — one `Nat` per
   variable (universals and existentials both; note which are which), labels as `Label` values, `a <- (X, b, c)` with
   `X = (|...|)` → `⟨a, [b, c], {…}⟩` and a variable-only rhs → `conc = ∅`. Check the `Label` type in `Basic.lean`.
   Print the converted systems back so a reader can check the conversion against the rendering.
2. Run `canonN` with ample fuel on each variant; print the normal forms (`State.toSystem`) in a readable form, and
   compare the two variants of each binding UP TO a bijective renaming of EXISTENTIALS only (universals are shared
   names across the two variants — map them by name). Say for each binding: SAME / DIFFERENT, and for DIFFERENT the
   leftover constraint(s) and which rule would be needed.
3. For at least `lookbackJoin`, show the derivation by hand: which rule fires on which constraint, in order, from
   the larger variant to the smaller — so the report reads as an argument, not a printout.
4. Control: run the two variants of one binding that E11a's FORM sweep now renders identically (any binding from
   the sweep's "identical" majority, taken from `<scratch>/e11a/logs/sweep-after3.tsv`) and confirm SAME.

## Report `tracker/loopmodel/E11b-PROBE.md`

Answer first: how many of the bindings collapse, how many do not, and for the ones that do not, what is missing.
Then, per binding: the two renderings, the two converted systems, the two normal forms, the verdict. Then the
`lookbackJoin` derivation. Then what a Scala port would consist of (which rules, where — `mkSimplified` at
`publishing`, before or after the tautology deletion — and what the Lean proofs cover vs what a port would have to
re-establish: the conversion between Ermine's `Part` types and `Constraint`, the treatment of class constraints and
of non-row constraints, the fuel bound). Every claim from a command whose output is in a named log. Plain language;
a reader who has not seen the Lean should follow it.
