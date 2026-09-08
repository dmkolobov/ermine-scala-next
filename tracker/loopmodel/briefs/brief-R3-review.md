# Review brief: R3 — the determinacy closure (Rose Def. 13): the Lean, the three answers, the instrument and the measurement

You are reviewing stage R3 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `5bf83bf`
plus the UNCOMMITTED R3 deliverables). Implementer's brief `tracker/loopmodel/briefs/brief-R3.md`; report
`tracker/loopmodel/R3-DETERMINED.md` (GREEN; §0 outcome, §2 the Lean, §3 the three answers, §4 the instrument and
the numbers, §5 the recommendation, §6 gates, §7 scope limits); changes in MAIN: NEW `tracker/lean/Rowpartition/Determined.lean`
(1,245 lines, 124 declarations; namespaces `Rowpartition`, `.SpliceGuard13`, `.Pivot`, `.DeadTwoParts`,
`.DeadUndetermined`, `.CriterionIncomplete`, `.RuleFires`), `Rowpartition.lean` (root import), the R3 plan row, the memo
Rank 4 note; the TRACE-ONLY Scala in the worktree `~/research/ermine/ermine-scala-wt-r3` (branch `determined-closure`,
uncommitted working-tree diff of `RowTrace.scala` +51 and `Subst.scala` +153: records `detm` per splice and `ramb` per
published signature, `Subst.Determinacy`, a `withBinding` thread-local — every insertion under `if (RowTrace.enabled)`
or a by-name `log` argument). Context: `tracker/ROSE-COMPARISON.md` Rank 4; `R2-ROSE-THEORY.md` §5 (what R3 inherits);
`Rowpartition/Splice.lean` (`splice_entails_iff`, `DroppedPartition`); `Subst.reduce` and `mkSimplified`;
`tracker/TICKET-signature-resolution-fragility.md` (the withdrawn three-condition guard). You edit NOTHING except a
scratch directory `/home/dmitry/.claude/jobs/880c725d/tmp/review-R3/` and your report `tracker/loopmodel/R3-REVIEW.md`.
Lean via `lake env lean <scratch>` (library built; one confirming `lake build` fine); ONE JVM at a time
(`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, sbt allowed, in either tree); NEVER `lake build` while a
`looptrace` binary runs; delete every `.ei` you cause in BOTH trees; no commits; never `lake exe cache get`, never a
`require`, never touch `CutSearch.lean` or `~/research/leanwork`. A perf A/B script of the orchestrator's may run
`bin/ermine` in main when the load is low — that is not yours; do not kill it. The orchestrator re-ran: `lake build`
870 green, Audit 4,582 / 0, the six headline theorems on the standard axioms, `looptrace` not rebuilt.

1. **The closure and its theorem.** Read `Determined.lean` in full. Is Definition 13 restated faithfully (n-ary via
   R2's `sat_iff_pfold`) and is Ermine's cancellation clause (`cancelAdd`) exactly "a part is determined by the whole
   and the other parts once the concrete parts are known" — no more? Are the closure properties real (least fixed
   point: extensive, monotone, idempotent, LEAST)? Is `determined_unique` the right statement (two models agreeing on
   `U` agree on `Determined G U`) and does its proof use the partial-monoid facts it claims? The §13 addition — the
   `resolution` clause added after the hand-check — is its uniqueness theorem re-proved for the enlarged closure, and
   is the clause sound (a `resolution`-derived fact is entailed, so any determinacy it yields is real)? Try to state
   a hypothesis no real residual satisfies.
2. **The three answers.** (a) SPLICE: `SpliceGuard13.determined_splice_not_conservative` and
   `undetermined_splice_is_conservative` — re-elaborate both; is "REFUTED IN BOTH DIRECTIONS" the right reading, and
   is the deciding condition really `splice_entails_iff`'s syntactic `hlhs`? Is "never build it" justified by the
   theorems alone, by the measurement alone, or only by both? (b) DELETION: `dead_delete_of_pairwise` /
   `dead_delete_of_le_one_part` — is "Definition 13 gives the value, not the definedness" correct for a partial
   monoid, and are the two licensed forms the strongest true statements? (c) AMBIGUITY: `RoseRowAmbiguous` /
   `RowAmbiguous`, `Pivot.criterion_split` (pivotData is Rose-ambiguous and NOT Ermine-ambiguous) — is that the
   right verdict for the four-solution residual, or a sign the Ermine criterion is too loose? Check on the compiler
   (`ramb` record for `PivotTest.pivotData`).
3. **The instrument.** Diff the worktree (`git diff -- core/src`): confirm every insertion is dead when
   `-Dermine.rowTrace` is unset (`RowTrace.enabled` guards, by-name args; the thread-local's cost when disabled);
   confirm no existing record changed shape; re-run the byte-identity gate on two groups (trace with `detm`/`ramb`
   filtered vs main) and the `.ei` sweep claim on a sample; `TestLoopTrace` 720/720 in the worktree.
4. **The measurement.** Re-derive the headline numbers from the traces (regenerate one group per file and the
   stdlib boot yourself): splices total per file / in batch; licensed by Rose's closure / Ermine's / the withdrawn
   guard; the "0 of 42,902 / 0 of 8,415" overlap claim; the "64 % on corpus splices vs 90 % stdlib" correction;
   `ramb`: 104 top-level signatures, Rose flags 88, Ermine flags 19, none in `core/examples`. Hand-check FIVE of the
   nineteen yourself (different ones from the implementer's ten if it lists them) and say whether each is a genuine
   ambiguity or a false positive, and whether the added `resolution` clause would clear it. Anything the report
   counts that you cannot reproduce is a finding.
5. **Gates, re-run:** `lake build`; `Audit.lean`; `#print axioms` over all 124 declarations regenerated by you;
   `core/test` unchanged (922 / 1 documented / 921); `TestLoopTrace` 720/720; `git diff --stat` in main = module,
   root import, docs only; `looptrace` mtime; the plan row and memo note accurate.
6. **The recommendation (§5).** Judge it: (i) splice guard NEVER — agree? (ii) ambiguity warning NOT YET, re-measure
   with the `resolution` clause, acceptance criteria stated — are the criteria the right ones and is the false-
   positive threshold sensible? (iii) what, if anything, should be committed beyond the Lean and the instrument? Say
   plainly whether a stage 2 is worth the user's time, and what it would be.

Findings prefixed `M-`, ranked, CONFIRMED (you ran it) or PLAUSIBLE. Verdict: ADVANCE / FIX-THEN-ADVANCE / REDO.
Write the report early and keep it current.
