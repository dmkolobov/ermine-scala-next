# Brief: S3b -- correct the 17 dishonest signatures, verified against the oracle (parallel with S3)

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-fix`, branch `sig-fixes` from d01a219 (S2 + LET-1
merged). No commits; never `git stash`; this worktree only. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed;
parallel by default (tracker/GATE-POLICY.md). `bin/ermine` builds its classpath on first run. Regenerate
`tracker/repl-classpath.txt` from THIS worktree before repl-smoke and `git checkout` it back. Delete every
`.ei` you cause. Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S3b/`.
Budget 4 hours.

The entailment CHECK is being implemented by another agent on `sig-entail`; you do not have it. You have
two things that decide honesty without it: the S1 probe (`-Dermine.sigEntail=warn` prints every dropped
obligation of a signature with its givens; see `SigEntail.scala` and SIG-1-SURVEY.md §2-3 for the record
format) and the S2 oracle `sigcheck-closure.py` in
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S2/`
(copy it to `tracker/tools/sigcheck.py`, make it read the probe's record format, commit-worthy). A
signature is honest iff the oracle ACCEPTS every obligation the probe prints for it. Read
SIG-2-DESIGN.md §(a) (the judgement) and §(b5) (the 21 rejections), SIG-1-SURVEY.md §5 (the (c) items with
the mechanism of each), and SIG-2-REVIEW.md (the five Time/Helpers holes and why S1 missed them).

## The 17
Stdlib (7): `Relation/UnifyFields.e unify1`; `Relation.e partialLookup`; `DrilldownList.e cons_Bracket`;
`Layout/Report/Keyed.e softRelation`, `keyValueTabular`; `Layout/Report/Relation.e cutoffs`, `others`.
Examples (10): `Wide/Helpers.e melt2`, `melt3`, `melt4`; `Wide/Signatures.e melt3Simple`;
`Algebra/Signatures.e runningTotalFullViaWritten`; `Time/Helpers.e dayCount`, `monthsBetween`,
`monthsSince`, `daysSince`, `daysUntil`.

For each: the MINIMAL honest signature, preferring the correction that preserves the body's behaviour.
`unify1`: keep the body and declare `r2 <- (h,f1,f2,t)` with `r <- (h,f2,t)` (the orchestrator's
recommendation, no caller exists; say if you disagree and why). `cutoffs`: the body removes the value
column the declared result keeps -- fix the signature to the body. `cons_Bracket`: `import Constraint` is
NOT enough (`Has` gives membership, not disjointness) -- the explicit partition `rout <- (f1, f2, r)`.
`keyValueTabular`/`softRelation`: restore the originals' row constraints from `Layout/Report.e:635-642`
and `:683-687`. `runningTotalFullViaWritten`: the module's prose claims the 21 imply the 2 -- correct the
claim. `Time/Helpers.e:287-293` names its own fix (`RUnion2 out r r1`). NOTHING ELSE in those modules
changes. Procedure per module: edit -> `bin/ermine` the module under `warn` -> feed the records to the
oracle -> ACCEPT on every obligation of the corrected binding, AND the module still loads, AND every
corpus module that imports it still loads (`corpus-run.sh --batch` once at the end, all 160 must be
LOADED/REJECTED exactly as before except that nothing new is rejected).

## Exercise the corrections
One positive corpus module per group that CALLS the corrected functions at rows that satisfy the new
signatures: `core/examples/Lang/Corrected.e` (or in each group's Helpers if the house style prefers) --
`unify1` on two tables, `partialLookup`, a `cons_Bracket` drilldown, `melt2`, a `dayCount`. It must load,
and its header must say which correction each call exercises. Add to the group README.

## Gates
`.ei` per corrected stdlib module vs a same-config control (`tracker/tools/ei-diff.sh`): list every
binding that moves (callers whose inferred types change). Corpus `--batch` as above. `repl-smoke.sh`.
`sbt 'core/testOnly *TestErmine* *TestSigEntail *TestLetSignatures *TestInterfaceConcreteRow *TestTolerantRead'`
(in parallel invocations).

## Report
`tracker/loopmodel/SIG-3b-CORRECTIONS.md`: a table of the 17 with before/after signatures, the obligation
each discharges, the oracle's verdict on the corrected binding, callers affected, `.ei` movement; the
exercising module; gate numbers with commands. The S3 agent will run the real checker over your
corrections when the branches merge -- state anything you could not verify with the oracle.
