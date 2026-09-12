# Brief: signature entailment, stage S3 -- implement the check, DEFAULT ERROR, and correct the 17 signatures

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-sig`, branch `sig-entail` (HEAD = the merge of
scala3-migration's LET-1 fix; `git log -1`). No commits; never `git stash`; this worktree only (read-only
peeks elsewhere). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt and `lake` allowed. PARALLEL BY DEFAULT (tracker/GATE-POLICY.md "Parallelism rules"): run suites in
parallel sbt invocations, corpus in `--batch`, never a whole-corpus per-file pass; only a timing runs alone.
Regenerate `tracker/repl-classpath.txt` from this worktree's `target/ermine-classpath` before repl-smoke /
lsp-smoke / g1 tools and `git checkout` it back. Delete every `.ei` you cause (never `tracker/g1-*`). Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S3/`.
Budget 8 hours wall clock; write up and stop at the budget with unfinished items marked.

READ FIRST, in order: `tracker/SIG-ENTAIL-PLAN.md` (S3 section + the log); `tracker/loopmodel/SIG-2-DESIGN.md`
ALL OF IT -- §(a) is the judgement you implement, §(b) the procedure, §(d) the code sites and blame, §(e)
the 13-item checklist which IS your task list; `tracker/loopmodel/SIG-2-REVIEW.md` (F1-F10 and why);
`tracker/lean/Rowpartition/SigEntail.lean` (`sigDecide` is the reference algorithm; the S2 scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S2/sigcheck.py`
and `sigcheck-closure.py` are its Python stand-ins -- COPY the closure one into `tracker/tools/sigcheck.py`
and commit-worthy it); `SigEntail.scala` + `Subst.scala:527-560` (the S1 probe and the site);
`tracker/loopmodel/SIG-1-SURVEY.md` §5 (the (c) items) and §8; `scalacheck-binding/src/main/scala/TestErmine.scala`
top (the fixture rule: never `System.setProperty` a per-call flag; use the session-option mechanism).

THE USER'S DECISIONS (2026-09-11): (1) FIX THE HOLES -- all 17 dishonest signatures get honest signatures in
this stage; (2) the DEFAULT IS `error`; (3) ROW-ONLY -- class constraints keep their current path
(`entails`/`bySuper`), untouched; after the stage, write a one-page recommendation on the class status quo
(what `entails`/`entail`/`bySuper` do today for class constraints at signatures, whether the same hole exists
for them, with a probe program, and what a fix would take) as `tracker/loopmodel/SIG-3-CLASS-STATUS.md`.

## (a) The check -- exactly §(e) of the design
Implement every item of SIG-2-DESIGN.md §(e). Non-negotiable points: the R/F/W definitions of §(a) verbatim
(F = vars(W) ∩ pxs \ vars(Q); R = the rest; W = closure of rs under shared F variables within ps); the check
runs inside `subsumeType` only when a `Site` is present (`sig`, `ann`), before `restrictTypes(tts)` erases
the skolems, and never on the App case; `:553`'s return is untouched; the `error | warn | off` flag with
DEFAULT `error`, read once per session through the session-option mechanism (the S1 global `SigEntail.warn`
guards at :547/:652/:670 are replaced, NOT joined); `error` rejects with the §(d) message -- the wanted
(pretty), "not entailed by the signature's constraints", the givens, and TWO locations: the term that
generated the wanted and "declared at" on the signature; `warn` prints the same and continues; `off` is
byte-identical to today. NO VERDICT (budget) = warn + accept, REJECT outranks; unsatisfiable Q = vacuous
accept + its own diagnostic. The Part-shape contract of §(e) 2b exactly as written (dup-normalisation with
its Lean licence; anything else = NO VERDICT). The interface key gets the flag appended (Session.scala:472
`contains`) and `TestInterfaceKey`'s `notInKey` list is updated.

## (b) The differential test -- §(e) 2a
`core/test` property: the Scala procedure vs `tracker/tools/sigcheck.py` (or a Scala port of `sigDecide`
-- your call, say which and why) on (i) all 309 corpus signatures from the S1 records (commit the record
file it reads, or regenerate it under `warn` in the test), (ii) 2,000 random systems from a generator with
the flavour split. Verdict-identical, or the test names the case.

## (c) The 17 signatures -- the user says FIX THEM
Stdlib (7): `Relation/UnifyFields.e unify1`, `Relation.e partialLookup`, `DrilldownList.e cons_Bracket`,
`Layout/Report/Keyed.e softRelation` + `keyValueTabular`, `Layout/Report/Relation.e cutoffs` + `others`.
Examples (10): `Wide/Helpers.e melt2/melt3/melt4`, `Wide/Signatures.e melt3Simple`,
`Algebra/Signatures.e runningTotalFullViaWritten`, `Time/Helpers.e dayCount/monthsBetween/monthsSince/
daysSince/daysUntil`. For each: the MINIMAL honest signature that the corrected checker accepts, preferring
the correction that preserves the body's behaviour (for `unify1` the orchestrator's recommendation is to keep
the body and declare `r2 <- (h,f1,f2,t)` with `r <- (h,f2,t)` -- `unify1` has no caller; say if you disagree
and why); where the BODY is what is wrong (`cutoffs`' declared result keeps a column the body removes) fix the
signature to the body and say so. `cons_Bracket` needs `import Constraint` or the explicit partition.
`runningTotalFullViaWritten`'s documented claim is false -- correct the module's prose too. Every
correction: a before/after block, the obligation it discharges, and whether any caller's inferred type or
any `.ei` moves (run `ei-diff.sh` vs a same-config control). NOTHING ELSE in those modules changes.

## (d) Flip the pins
sig01/sig02/sig03/sig04/sig05 headers to REJECTED with the measured message verbatim; RESULTS.md class 6
section; `TestSigEntail`'s KNOWN HOLE properties to `no(...)` (the annotation one from `Prop.throws` to a
rejection); `control08` and `control09` still load; `Lang/LetSignatures.e` still loads (it has a
row-constrained let signature). Add ONE positive corpus example that uses each correction (calls to the
corrected `unify1`, `partialLookup`, `cons_Bracket`, a melt) in `core/examples/Lang/` or the module's own
group, so the corrections are exercised, not just accepted.

## (e) Gates (Tier 1 + the landing's Tier 2 is the orchestrator's)
In parallel sbt invocations: `*TestSigEntail *TestLetSignatures *TestInterfaceKey`, `*TestLoopTrace`
(the main checkout's `looptrace` binary), `*TestTolerantCheck *TestTolerantRead *TestReplDifferential`,
the new differential property; corpus `--batch` under `error` (default) vs `off`: every module that MOVES
must be one of the 17 (now loading) or one of the pins (now rejected) -- anything else is a finding, stop
that item; `.ei` under `off` byte-identical to HEAD; `.ei` under `error` -- list every binding that moves;
`repl-smoke.sh`, `lsp-smoke.sh` (the editor path reaches `subsumeType` through `TolerantCheck`: a signed
binding with a too-weak context must show the diagnostic in the editor -- add the check to lsp-client.py
and a fixture); `g1-validate.sh`. `lake build` + audit if you touched Lean (you should not need to; the
`Rowpartition.lean` import line for `SigEntail` IS yours to add).

## (f) Report
`tracker/loopmodel/SIG-3-IMPL.md`: the diff by site, the flag semantics table, the message with a worked
example per rejection class, the differential test's design and counts, the 17 corrections with
before/after, the corpus/`.ei` movement tables, gate numbers with exact commands, and the S4 list (editor
parity items you could not finish, the ambient-meta measurement).
