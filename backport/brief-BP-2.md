# Brief: BP-2 -- the seven library signature corrections and the five pins, on Scala 2.11 (parallel with BP-1)

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-backport`, branch `backport-2.11` (HEAD 774daa1). No
commits; never `git stash`; never touch `../ermine-scala` except read-only `git show`. BP-1 is porting the
checker in this same worktree: you own ONLY `core/src/main/resources/modules/**/*.e`, `core/examples/shouldfail/`,
`core/examples/shouldfail-controls/` and `backport/CORRECTIONS.md`. No build is needed for your work; do not run
sbt. Budget 2 hours. Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/BP2/`.
FILES ARE CRLF: edit byte-wise (python `open(p,'rb')`), never text mode; verify `git diff` has no line-ending churn.

## The seven corrections
Source of truth: scala3-migration `5162945` (`git -C ../ermine-scala show 5162945:<path>`) and its rationale
`git -C ../ermine-scala show 5162945:tracker/loopmodel/SIG-3b-CORRECTIONS.md`. Apply to THIS branch's versions
of: `Relation/UnifyFields.e` (unify1), `Relation.e` (partialLookup), `DrilldownList.e` (cons_Bracket),
`Layout/Report/Keyed.e` (softRelation, keyValueTabular + the degeneracy comment), `Layout/Report/Relation.e`
(cutoffs, others, and the forced `cutoffDrilldownRel` change). Diff each 2.11 module against main's PRE-correction
version first (`git -C ../ermine-scala show cff6c42:<path>`): where the 2.11 text differs from main's, port the
correction by meaning, not by patch, and say so. Nothing else in those modules changes. The 12 example-corpus
corrections do not apply (those modules do not exist here).

## The pins
Create `core/examples/shouldfail/sig01_unconstrained_signature.e` .. `sig05_annotated_lambda.e` and
`core/examples/shouldfail-controls/control08_sig_declared.e` from 5162945, adapted: module names as on main;
the headers keep the mechanism text but the "expected message" block must say "TO BE MEASURED on 2.11 by BP-1"
(BP-1 fills it). Check each file's SYNTAX against this branch's parser (the fused Scala-2 grammar: no `\x ->`
lambdas, `(x -> ...)` is fine; explicit-forall annotations `(e : forall r. ...)` -- if the 2.11 grammar refuses
one, note it and keep the spelling that parses). Note in each header that on this branch sig03 (let-bound) is
NOT the LET-1 case: the fused pipeline honours let signatures, so sig03 is rejected by the entailment check
like sig01.

## Report
`backport/CORRECTIONS.md`: a table of the seven with before/after (2.11 text), any place the 2.11 module text
differed from main's and how you ported by meaning, and the pin list with any syntax adaptation.
