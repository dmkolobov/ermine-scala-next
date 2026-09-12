# Review brief: signature entailment, stage S3 -- the check, the flag, the differential test, the pins

You are reviewing S3 in `/home/dmitry/research/ermine/ermine-scala-wt-sig` (branch `sig-entail`, HEAD d01a219
plus the implementer's UNCOMMITTED deliverables -- `git status` lists them; report
`tracker/loopmodel/SIG-3-IMPL.md`). Implementer's brief `tracker/loopmodel/briefs/brief-SIG-3.md` (its scope was
CUT mid-run to items a, b, d, e, f: the 17 corrections are on branch `sig-fixes`, worktree `../ermine-scala-wt-fix`,
another agent); design `tracker/loopmodel/SIG-2-DESIGN.md` (§(a) definitions, §(b) procedure, §(d) sites and
blame, §(e) checklist); `SIG-2-REVIEW.md`. You edit nothing except your scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/review-S3/` and
your report `tracker/loopmodel/SIG-3-REVIEW.md`. No commits; never `git stash`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; parallel by
default (tracker/GATE-POLICY.md): parallel sbt invocations, corpus in `--batch`; read the implementer's logs in its
scratch `.../scratchpad/S3/` and re-run only what you dispute or what is targeted. Regenerate
`tracker/repl-classpath.txt` from this worktree before repl-smoke/lsp-smoke and `git checkout` it back. Delete every
`.ei` you cause. Budget 3 hours. Verdict ADVANCE / FIX-THEN-ADVANCE (exact edits) / BLOCK.

This is the check that will ship with DEFAULT `error`. Attack it:

1. **Faithfulness to §(a).** In `SigEntail.check` (:408-581) and the `Subst.scala:549-567` call: is F computed as
   `vars(W) ∩ pxs \ vars(Q)` exactly, R as the rest, and W as the closure of `rs` under shared F variables as a
   FIXPOINT? Is the check before `restrictTypes(tts)` so skolems are visible? Is `:553`'s return untouched under
   every mode? Does the App case (:918-924 old numbering) get a `Site`? Construct: (i) a nested signed binding whose
   inner body mentions the OUTER signature's skolem (foreign skolem -> NO VERDICT, not REJECT, not ACCEPT-silently);
   (ii) a signature whose givens are unsatisfiable (own diagnostic, body not blamed); (iii) the reviewer's F2
   witness `sk <- (f1,f2), f1 <- (f3), f2 <- (f3)` shape as a real program (must REJECT).
2. **The engine.** `Constraints.LabelSearch` (:2783-3047) vs the design's §(b) and Lean's `sigDecide`: same
   label-class construction (each literal label + one generic), same one-hot encoding, dedup on the projection to
   `vars(W) ∩ R`, budget per class AND per signature with REJECT outranking NO VERDICT. The Part-shape contract (§(e)
   2b): overlapping concrete parts and a concrete lhs -> what does `encode` do, and is the `(||) <- (...)`
   normalisation licensed by `Basic.Sat.eq_empty_of_dup` as claimed? The implementer says the differential caught
   two ORACLE bugs (closure fixpoint; empty-lhs normalisation): read both fixes in `tracker/tools/sigcheck.py` and
   say whether the Lean statement still matches the oracle (the Lean was not changed -- should it have been?).
3. **The differential test** (`TestSigEntailDiff.scala`): does it really drive the SHIPPED Scala engine (not a
   re-implementation) over the 310 committed records and 2,000 random systems against the oracle, and would it
   fail loudly if the Scala drifted? Check the record file provenance (`core/src/test/resources/sigentail/`): is it
   regenerable from a command, and is the 310 (not 309) explained?
4. **The flag.** Default `error`; read once per JVM, consulted per session; the fixture's session-option mechanism,
   NOT `System.setProperty` (TestErmine.scala:49-70); `interfaceKey` appended and `TestInterfaceKey` updated; the
   S1 global guards gone. Under `off`: `.ei` byte-identical to HEAD (g1-validate) and repl goldens identical --
   confirm from the logs, re-run g1-validate once. Under `warn`: exactly the 24 named signatures and no other, on
   the uncorrected corpus (19 + 5 pins) -- reproduce with `corpus-run.sh --batch` under `warn` and the
   aggregator. The two NEW ones (`Time/Signatures.e yearFrac365Full/Simple`): real holes? Why did the S2 oracle on
   `W = rs` miss them and the closure catch them?
5. **The message and blame.** Run sig01..sig05 and read every message: the wanted, the givens, the model
   sentence, TWO locations (the generating term; "declared at" the signature). Is the "declared at" position the
   signature line, and is the wanted's position the `!`/`modify`/annotation term? For sig05 (annotation) is the
   blame sensible? Is the prose readable by someone who has not read the design?
6. **Editor.** `TestTolerantCheck`'s two new properties and `tracker/lsp-tests/SigEntail.e` + `lsp-client.py`: does a
   too-weak signature show a diagnostic in the editor at the same position as batch, and does an honest one show
   nothing? lsp-smoke 546 under `off` -- and under the default it dies on the uncorrected stdlib: confirm that
   is the ONLY reason (the 5 failing TolerantCheck properties too) by running one of them with the S3 patch of
   corrections applied in your scratch, or by reasoning from the failure text.
7. **Landing readiness.** With `sig-fixes` merged, what must be true: stdlib boots under `error`; corpus verdicts
   under `error` = under `off` except the pins; `.ei` under `error` vs `off` (list movers). You cannot run that
   until the merge; write the exact checklist and commands the orchestrator runs at the merge.

Report `tracker/loopmodel/SIG-3-REVIEW.md`: verdict first, items 1-7 with evidence, the edit list. Under 350 lines.
