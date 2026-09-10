# Review brief: LSP Stage 3 item 6.1 — diagnostics debt (do-anchor accepted, import-failure positions, 0:0 sweep pin)

You are reviewing item 6.1 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `f09e086`
plus the UNCOMMITTED deliverables: `lsp/Resident.scala`, `lsp/Diagnostics.scala`, `session/TolerantCheck.scala`,
`scalacheck-binding/src/main/scala/TestTolerantCheck.scala`, `tracker/tools/lsp-client.py`, new fixtures
`tracker/lsp-tests/{BadImport,BadSib,BadHeader,BadReq}.e`, report `tracker/loopmodel/LSP3-6.1-DIAGNOSTICS.md`).
Implementer's brief `tracker/loopmodel/briefs/brief-LSP3-6.1.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3,
6.1 (read the STAGE-3 INVARIANTS above the checklist); gates `tracker/GATE-POLICY.md`. You edit NOTHING except a
scratch directory `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.1/`
and your report `tracker/loopmodel/LSP3-6.1-REVIEW.md`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs; `sbt core/compile core/copyResources` before any
`bin/ermine` gate; delete every `.ei` you cause; do not touch `tracker/lean/`; no commits. Shipped code under
`core/src/main` DID change (Resident, Diagnostics, TolerantCheck) — all three are editor-path files, and the stage's
hard invariant is that BATCH semantics are frozen. That invariant is your first target.

1. **Batch frozen?** `git diff core/src/main/scala/com/clarifi/reporting/ermine/session/TolerantCheck.scala`: is
   every change confined to the editor path (`TolerantCheck` is only called from `Resident`/tests — confirm with
   grep), and does nothing in `Session.scala`/`NewPipeline.readModule` (strict) move? `tracker/repl-tests/*.expected`
   must be byte-identical (`git status`), `TestReplDifferential` green, `TestTolerantRead`'s 180-file agreement
   property green. The `Note` case class gained a field (`dependsOnBroken`): any other constructor site or pattern
   match on `Note` (`Diagnostics`, `Resident`, LSP-FFI's `ForeignNote` conversion) that this changes?
2. **(a) the acceptance.** The report says the continuation lambda is inferred bottom-up then subsumed, `Subst` has
   no checking mode, an intrinsic inner clash IS blamed inside (fixture `DoInner.e` 8:27), and the same anchoring
   happens for a plain `g (w -> w && True)`. Re-derive from `Subst.inferType`'s `App` case and `subsumeType`;
   reproduce the pin and the editor position; try to REFUTE the acceptance: is there an editor-only re-blame that
   does not amount to bidirectional checking (e.g. after the App-level clash, re-infer `mf`'s body under the
   unifier state with the argument type bound, and report the first inner Located whose unification fails)? If
   such a thing is feasible in under a day, say so with a sketch — that changes the verdict from ACCEPTED to
   "deferred with a design"; if not, confirm ACCEPTED. Is the drafted ticket (report §"Ticket draft") accurate?
3. **(b) the design.** The rule: while ANY import failed to load, drop every undefined-term note AND every
   "unchecked: depends on a broken definition" note wholesale; keep syntax diagnostics, surviving imports'
   requirements, and type errors of definitions that still checked. Probe it: (i) a file with one failed import
   and a genuinely undefined term unrelated to it — the real error is now hidden; is that the right trade, is it
   STATED in docs/report, and would the narrower rule (suppress only names the failed module exports, when it can
   be known from a sibling buffer or the loaded stdlib) have been cheap? (ii) a file whose only failed import is
   `import X (a, b)` with an explicit list — the narrowing IS available there; was it used? (iii) two failed
   imports — two diagnostics, each on its own module-name span (exact range check); (iv) fix the sibling through
   didChange — does the diagnostic clear on the importer's NEXT check without a save (the sibling-buffer path);
   (v) a failed import that is also the module's own name or a cyclic import — no hang, no crash; (vi) the
   fast path: an unbroken file still loads its imports in ONE `loadModules` call (measure Report.e's check time or
   read the code path) and the one-at-a-time re-load runs only on failure. Also: `BadHeader.e` — the position and
   END of a header-parse Death; `BadReq.e` — "does not export" now on the name span (exact range).
4. **(c) the pin.** Read the property: does it really drive `Resident.checkFile`/`Diagnostics.check` over the 180
   corpus files AND the fixtures, and assert "no 0:0 unless designed"? Which fixtures are exempted as designed-1:1,
   and is each exemption justified? The before count (1) — reproduce by reverting (b) in scratch or by reasoning
   from the diff; the "group-level refusals at `m.loc`" residual (`shouldfail/sk03`) — reproduce once and confirm
   it is outside the corpus by the standing rule and correctly ticketed rather than hidden.
5. **Gates, re-run ONCE.** `sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'` 720/720;
   `sbt 'core/testOnly *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestStage1Pins
   *TestReplDifferential'` (implementer: 69/69, TestTolerantCheck 14→17); `tracker/tools/corpus-run.sh --batch
   <scratch outdir>` 85 / 69 / 0 over 154; `tracker/tools/repl-smoke.sh` 8 groups / 66 checks; `tracker/tools/
   lsp-smoke.sh` 205 (was 185; list the 20 new checks by fixture); `bin/ermine-lsp` boot still 129 modules (the
   lsp-smoke log says); Report.e round trip: the implementer measured `perf-bench.sh editor -k 5` before 1.721 /
   after 1.808 and 1.723 and called the first after-run drift — run ONE interleaved pair yourself (before = a
   scratch build of HEAD f09e086 or `git stash`; after = the tree) with load < 1.5 and say whether the item moved
   the round trip by more than the ~50 ms floor. NOT the full `core/test` (Tier 2 is G3's).
6. **The report.** Accurate against your numbers, side by side? Anything the roadmap item's tick conditions ask
   for that is missing (6.1(a): pinned line flips OR the reason is written; (b): BadImport fixture, both import
   lines, other diagnostics still publish; (c): expected 0)?

Report format: findings table (id, severity blocker/medium/nit, CONFIRMED/PLAUSIBLE/REFUTED, one paragraph each),
gate table (implementer vs yours), verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why). Your numbers go into
the trackers. STOP after the report.
