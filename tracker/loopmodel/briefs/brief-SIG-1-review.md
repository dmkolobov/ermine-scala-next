# Review brief: signature entailment, stage S1 -- the warn-mode survey

You are reviewing S1 in `/home/dmitry/research/ermine/ermine-scala-wt-sig` (branch `sig-entail`, HEAD
ba29389 plus the UNCOMMITTED deliverables: `core/src/main/scala/com/clarifi/reporting/ermine/SigEntail.scala`
(new), `Subst.scala` (+18/-3), `tracker/tools/sigentail-agg.py`, `tracker/tools/sigentail-entail.py`,
report `tracker/loopmodel/SIG-1-SURVEY.md`). Implementer's brief `tracker/loopmodel/briefs/brief-SIG-1.md`;
plan of record `tracker/SIG-ENTAIL-PLAN.md`; gates `tracker/GATE-POLICY.md`. You edit NOTHING except your
scratch directory (named in your launch message) and your report `tracker/loopmodel/SIG-1-REVIEW.md`.
This is a git worktree: work only here; never `cd` into `../ermine-scala` (read-only peeks allowed); never
`git stash`; no commits. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, none in the background; check
`pgrep -af sbt-launch | grep -v shell-snapshots` is empty first. Delete every `.ei` you cause. You may
`lake build` under `tracker/lean/` to get the `looptrace` binary (the implementer's TestLoopTrace skipped
two properties for lack of it) but edit nothing there.

The stage MEASURES. Shipped behaviour with the flag off must be byte-identical. Your verdict is one of
ADVANCE / FIX-THEN-ADVANCE (list the exact edits) / BLOCK (why, and what a fix round must do).

1. **Byte-identical under `off`.** Read the `Subst.scala` diff line by line: the new `sig: Option[Site]`
   parameter on `subsumeType` defaults to `None` at every caller it says is not a signature check; nothing
   else in the function's control flow moved; no allocation or ordering change reaches `mkSimplified`/the
   substitution when the flag is off. `SigEntail` reads its flag once at class init and is NOT part of
   `Constraints.GenRules`/`Session.interfaceKey` -- confirm the `.ei` bytes are unchanged: run
   `tracker/tools/ei-diff.sh` (or the equivalent the tools offer) between ba29389 and the working tree
   with the flag off, for the stdlib boot at least. Confirm `typeCheckPattern` really is dead code
   (grep the whole tree incl. `editor/`, `session/`, `lsp/`).
2. **The seven stdlib (c) items -- each one, by hand.** For every item in the report's NOT-entailed list
   (`Relation/UnifyFields.e unify1`, `Relation.e partialLookup`, `DrilldownList.e cons_Bracket`,
   `Layout/Report/Keyed.e softRelation` and `keyValueTabular`, `Layout/Report/Relation.e cutoffs` and
   `others`): read the signature and the body yourself; state in one line whether the wanted is really not
   entailed by the givens, or whether the classifier (`sigentail-entail.py`) missed an entailment (aliases
   not expanded? a `Has` alias? set-level entailment through a shared existential?). Run the implementer's
   four-line reproducers and ALSO push each to a runtime witness: does a call that type-checks actually
   fail at runtime (`key not found` or a wrong-shaped record), as `shouldfail/sig01`'s `crash` does? A
   reproducer that merely LOADS is not evidence of a hole; a crash or a record outside its printed type is.
   Same for the five example-corpus items (`Wide/Helpers.e melt2/3/4`, `Wide/Signatures.e melt3Simple`,
   `Algebra/Signatures.e runningTotalFullViaWritten`). Produce a table: item | really not entailed? |
   runtime witness? | severity.
3. **The sig03 finding = a SECOND bug.** The report says `rename/Lower.scala:185-187`'s `SLet` case discards
   explicit (signed) let bindings, so a let-bound signature never reaches the checker, and
   `let g : Int -> Int; g x = x in g "hello"` LOADS while the `where` twin is rejected. Confirm by reading
   `Lower.scala` and by running P7/P8. Then answer: was this true of the FUSED pipeline before the LSP
   Stage-1 rewrite deleted it (commit 856ee7d removed the fused term grammar; `git show 856ee7d^:...` the
   old `Term`/`LocalBlocks` parser, or the G1 goldens under `tracker/g1-*`) -- i.e. is this a REGRESSION
   of the new pipeline or upstream behaviour? Does the fused pipeline's `Let` carry explicit bindings (the
   `Let(pos, implicits, explicits, body)` shape has an `explicits` slot -- who filled it before)? Is the
   `where` path (`SWhere`?) different because it goes through `bindings` with both halves? State the answer
   with line numbers and the commit that introduced the drop, if any. This is a finding the user sees;
   do not soften it. It also affects the LSP loop (same `Lower.scala`), so say whether any LSP test pins
   let-signature behaviour.
4. **The shape taxonomy.** `concrete-ext` is 20 of 914 row obligations and the plan's refutation trick
   covers only that shape. Sample 15 records across `multi-skolem`, `other-row`, `skolem-in-parts` by hand
   from the sweep output: is the tag right? Is `other-row` (411) really outside the trick, or is a large
   part of it `concrete-ext` in disguise (e.g. the lhs is a skolem and the parts are concrete labels plus
   TWO fresh variables, or plus an alias)? Report what fraction the trick would cover after the obvious
   generalisations; this decides S2's scope.
5. **Zero `ann` hits.** Is `typeCheck` :651 (expression annotations `(e : T)`) ever reached with a
   skolem-mentioning wanted in the corpus, or are annotations monomorphic in practice? One probe program
   with `(r ! health : Int)` under an annotated lambda, and a look at where `ann` is constructed.
6. **Gates, re-run ONCE.** `sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'`
   (with the looptrace binary if you built it); `sbt 'core/testOnly *TestSigEntail *TestStage1Pins
   *TestReplDifferential'`; `tracker/tools/repl-smoke.sh`; corpus batch under off vs warn with
   `corpus-verdicts.py` (0 differ). Your numbers go into your report; note that `shouldfail/sig03`'s
   header says the refusal is at 20:12 and the report says 32:12 -- confirm the line and list the header
   fix as a FIX-THEN-ADVANCE edit.
7. **The report as a document.** Is §8 ("what S2 must decide") complete and each item backed by a
   record from the sweep? Anything the implementer saw but did not write down (grep its scratch
   directory `/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S1/`)?
   Are the exact commands reproducible from a clean shell?

Report `tracker/loopmodel/SIG-1-REVIEW.md`: verdict first, then the (c) table, the sig03/Lower answer,
the taxonomy fraction, the gate numbers, and the edit list. Keep it under 400 lines.
