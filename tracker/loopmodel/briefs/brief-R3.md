# Brief: R3 — Rose's Definition 13 (determinacy closure) as a criterion for `reduce`'s splice and for row-residual ambiguity: build it, measure it, no behaviour change

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from commit `13c11a2` (R2 committed
`1c8017a`). Toolchains: Scala `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time, sbt allowed; Lean `export PATH=$HOME/.elan/bin:$PATH`
in `tracker/lean/`, `LEAN_NUM_THREADS=2`; you are the only agent, so `lake build` is allowed (one at a time, and never
while your own JVM runs the `looptrace` binary). Disk: never `lake exe cache get`, no `require`, no new Lean project,
never touch `~/research/leanwork`; `Rowpartition/CutSearch.lean` stays out of the root import. Long runs under `setsid
nohup` with a log; delete every `.ei` you cause; no commits. Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/R3/`.
This is an INVESTIGATION stage (memo verdict "ADOPT AS AN INVESTIGATION"): NO solver behaviour changes, NO diagnostic
shipped; the only Scala allowed is a TRACE-ONLY record emitted under `-Dermine.rowTrace`, in a fresh worktree
`~/research/ermine/ermine-scala-wt-r3` (branch `determined-closure`), applied to main only at commit.

ORIGIN, read first: `tracker/ROSE-COMPARISON.md` Rank 4 (§3) and §1.5; `tracker/loopmodel/R2-ROSE-THEORY.md` §5 "What R3
inherits" (`sat_iff_pfold`; `labelAlgebra` as a partial monoid; NOTHING from the entailment half; Definition 14 is not
well-defined for Ermine, so Definition 13 is imported as a CRITERION, not a guarantee); `R2-REVIEW.md` K-10;
`Subst.scala` `def reduce` (~:1071, the splice and its trace-only three-condition diagnostic), `mkSimplified`
(~:1624–1680: `ambiguitiesIn(exts, complex)` runs on CLASS constraints only, the row parts bypass it),
`ambiguitiesIn` (~:371); `tracker/lean/Rowpartition/Splice.lean` (`splice_entails_iff` and its three side conditions,
`DroppedPartition.dropped_can_lose`); `tracker/TICKET-signature-resolution-fragility.md` (why the three-condition
guard was withdrawn 2026-09-02: it failed on 90 % of splices and degraded published signatures);
`tracker/TICKET-row-constraint-decision.md` §1.3 (`PivotTest.pivotData`'s four-solution residual); the `splice`
record's fields in `RowTrace.scala`. The paper (Morris & McKinna, Rose, POPL 2019, Definitions 13/14, Theorem 15) is
readable via the Wayback Machine's 2025-07-21 snapshot of dl.acm.org/doi/pdf/10.1145/3290325 — read only.

## R3.1 — the closure, in Lean (`Rowpartition/Determined.lean`, root import)
State Definition 13 verbatim (docstring), then Ermine's n-ary restatement licensed by `sat_iff_pfold`: for a
partition `a <- (parts, K)`, if `fv(parts) ⊆ U` then `a ∈ U` (the whole is determined by the parts). Then Ermine's
STRICTLY LARGER closure the memo names: cancellation determines a PART from the whole and the other parts once the
concrete parts are known — `a ∈ U` and all other abstract parts in `U` ⟹ that part `∈ U`. Define
`Determined (G : System) (U : Finset Var) : Finset Var` (least fixed point; prove it is a closure: extensive,
monotone, idempotent) and the THEOREM that gives it meaning: if `v ∈ Determined G U` then any two models of `G`
that agree on `U` agree on `v` (uniqueness; the partial-monoid fact from R2 is what makes the whole a FUNCTION of the
parts, and disjointness+completeness make a part a function of the rest). Both rules separately, then the composite.
Non-vacuity: a kernel-checked instance for each rule and `PivotTest.pivotData`'s residual as the instance where
`i`, `v3` are NOT determined (its four solutions). Say what Rose's closure gives and what Ermine's adds, on that example.

## R3.2 — what determinacy licenses (state precisely; prove or refute)
(a) THE SPLICE. `reduce` splices `v` when `v.ty.ambiguous || es.contains(v)`. State the candidate guard "splice `v`
only when `v ∈ Determined (residual minus its own partition) (vars \ es)`" and the theorem it would rest on: does
determinedness of `v` make the splice CONSERVATIVE (in `Splice.lean`'s `splice_entails_iff` sense, or the
vocabulary-restricted `SEntails` sense R2 uses), independently of the three withdrawn side conditions? Prove it, or
give the counterexample and state the weaker true statement. (b) THE DELETION. The memo's §4
`Goal_dead_existential_deletable`: an existential NOT determined by and NOT determining anything in the universal
vocabulary — say exactly what Definition 13 licenses about deleting it, prove or refute. (c) THE AMBIGUITY CRITERION.
Definition 14 read as a criterion for Ermine: a published signature `exists es. cs => tau` is ROW-AMBIGUOUS iff some
`v ∈ es` is not in `Determined cs (fv(tau) ∪ universals)`. State it; explain the `∀T` vs `exists` reading (R2 K-9).

## R3.3 — the instrument (trace-only Scala, worktree) and the measurement
Add ONE new row-trace record `detm` (do NOT extend the existing `splice` record — every existing record must stay
byte-identical) emitted in `reduce` at each splice, carrying: site, loc, `v`, whether `v ∈ Determined` under Rose's
closure and under Ermine's larger closure (both computed on `cs` at the splice point with `U₀` = the non-existential
variables — say precisely how you obtain the universals/type vars at that call site, from `mkSimplified`'s
arguments if `reduce` alone does not know them), and the three withdrawn side conditions' verdict for comparison.
And ONE record `ramb` emitted from `mkSimplified` per published signature: how many existentials, how many
NOT determined (row-ambiguity candidates), with the binding name. Gates for the instrument: `-Dermine.rowTrace`
unset ⟹ zero behaviour change (`core/test` unchanged, `TestLoopTrace` 720/720, the 18-group corpus trace with
the new records filtered out BYTE-IDENTICAL to main, the `.ei` sweep byte-identical, perf-bench unmoved).
MEASURE over the stdlib boot + `core/examples` (the 18 groups + `incomplete/`, `corpus-run.sh --batch` and per
file): total splices; licensed by Rose's closure; by Ermine's closure; by the withdrawn three-condition guard
(expect ~10 %); the overlap; and for `ramb`: how many published signatures have ≥1 undetermined row existential —
list them (expect `PivotTest.pivotData`; is it alone?), and for a sample of ten, judge by hand whether the
signature is genuinely ambiguous or the criterion is too strict/too loose (a `Has`-style `exists c. a <- (f, c)` is
the key case: the memo §1.1 says `Has` IS an existential — is `c` determined by `a` and `f`? It should be, by
cancellation; if Rose's closure alone says no, that is the measured reason Ermine's larger closure exists).

## R3.4 — report and recommendation
`tracker/loopmodel/R3-DETERMINED.md`: the definitions, the theorems (statement by statement, `#print axioms`), the
counterexamples, the instrument, the numbers, the hand-judged sample, and a RECOMMENDATION for a stage 2 with its
acceptance criteria: (i) the splice guard — only if the licensed fraction beats the withdrawn guard's 10 % by a
margin AND the theorem in R3.2(a) holds; (ii) the row-ambiguity WARNING behind a flag default OFF — only if the
false-positive rate on the sample is near zero; or (iii) NEITHER, with the numbers that say so. Plan row R3; memo
Rank 4 dated note (additive); state file untouched unless something solver-visible changed (nothing should).
Gates: `lake build` green, Audit count / 0 non-standard, axioms saved; the Scala gates above. Outcomes: (GREEN)
R3.1–R3.4; (PARTIAL) which theorem or measurement is missing and why; (BLOCKED) why. No silent weakening; report
early; STOP after the report — a reviewer re-runs everything, and any stage 2 is the user's decision.
