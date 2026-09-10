# Review brief: LSP Stage 3 item 6.3 — references, document highlight, rename

You are reviewing item 6.3 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `2a9fde1`
plus the UNCOMMITTED deliverables: new `lsp/References.scala`; `lsp/Definitions.scala`, `Documents.scala`,
`Diagnostics.scala`, `Main.scala`, `Rpc.scala`, `Resident.scala`, `rename/NewPipeline.scala`;
`scalacheck-binding/src/main/scala/TestRenamer.scala`; `tracker/tools/lsp-client.py`; fixtures
`tracker/lsp-tests/Refs.e`, `RefsSib.e`; `docs/lsp.md`; report `tracker/loopmodel/LSP3-6.3-REFS.md`). Implementer's
brief `tracker/loopmodel/briefs/brief-LSP3-6.3.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.3 with the
STAGE-3 INVARIANTS and Decisions (c)(d); gates `tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.3/` and your
report `tracker/loopmodel/LSP3-6.3-REVIEW.md`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs, no lingering polling shells; `sbt core/compile
core/copyResources` before any `bin/ermine` gate; delete every `.ei` you cause (the boot writes 129 into the target
module tree); do not touch `tracker/lean/`; no commits. Source files are largely CRLF: check `git diff --stat` equals
`git diff --stat -w` (the implementer says it does).

1. **THE SHARED FILE.** `rename/NewPipeline.scala` changed: `NewPipeline.Read` gained a defaulted `scope` field, set at
   its one construction site and read only by the editor. Read the diff: is that ALL? Does the strict `readModule`
   path allocate or retain anything new (a `ModuleScope.Scope` held per module in batch memory — what does that cost
   on a 129-module load; is the field populated on the strict path at all)? Could the retained scope keep a large env
   alive per open document (memory growth over an editing session)? Batch frozen: `tracker/repl-tests/*.expected`
   untouched (`git status`), `TestReplDifferential` green, corpus verdicts identical.
2. **The references set.** Re-derive from `References.scala`: LocalKey = binder id within the document + def-site;
   GlobalKey = `ToGlobal.origin` across every open buffer + def-site (even if its file is not open) + signature and
   equation heads + declaration head + fixity mention + `import M using (n)` entries. Probe: (i) an alias import
   (`import M as A`; `A.n` and `n` through another path) — one set?; (ii) a name re-exported through a chain —
   origin resolves to the ORIGINAL module, and the intermediate module's re-export line: in the set or not, and is
   that right for RENAME (renaming the origin must rename the re-export list entry too, or the program breaks)?;
   (iii) a local shadowing a global of the same spelling — two keys, two sets, no bleed; (iv) a name used in a
   `where` block and as an equation argument in another equation of the same binding; (v) a multi-equation definition
   — the report says the def-site is the LAST equation: is every equation head in the references set (it must be for
   rename to be complete); (vi) operators: the report says operator import-list items are NOT indexed — so a
   references query on `(+)` misses its import-list mention; is rename REFUSED for operators (yes per Decision d), so
   is the gap only a references-completeness gap? State it.
3. **Rename, adversarially.** The refusal list: invalid identifier/case class via the Lexer; operator either side;
   capture three ways (`scopeAt` at every occurrence, `moduleTerms`+TyDef binders, canonical import maps via
   `Local(new, Idfix)`); stale index per document; Ambiguous; def-site in a non-open file; multi-spelling mention.
   Try to get a WRONG edit through: rename a local to a name that a NESTED inner binder already uses (the inner
   shadows the outer at some occurrences — captured?); rename a top-level to a name imported OPEN from the stdlib
   (`import Bool` then rename `f` → `not`); rename to a name that is a type constructor spelled the same as a term
   (data Color = Color) ; rename to a KEYWORD; rename where the new name appears in the file only inside a string
   or comment (allowed — confirm it is not falsely refused); rename a name whose occurrences include a
   fixity-declaration line (`infixl 5 f`?? — operators only, so maybe not applicable; check `infix` on a backtick
   name if the grammar has it); rename across two open buffers where the SIBLING's index is stale (edited, debounce
   not fired) — refused for the whole edit, not partially applied; a request during boot. The `nameLen` fix
   (spans ran to the next token): verify the replace ranges are exactly the name in all fixtures, including a
   line-final name and a name followed by `)` or `,`. Apply a rename edit in your scratch client and re-check the
   result through the server: clean, and hover on the renamed local unchanged.
4. **Coverage warning.** Decision (c): sent for every global references/rename request, never for locals. Confirm the
   wording states what was searched (N open files) and that it is one `window/showMessage` per request, not per
   occurrence.
5. **Table integrity property** (TestRenamer 18 → 23): 252 of 253 files renamed (Sample.e does not parse — is that a
   known corpus fact? check TestTolerantRead's exclusions), 71 248 occurrences, 0 bad ToBinder / overlapping /
   shared def-site / bad moduleTerms — re-run and confirm; are the four assertions real (a planted violation would
   fail — try one in scratch by reasoning or by a copied test)?
6. **Gates, re-run ONCE.** compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly *TestRenamer*
   *TestTolerantCheck *TestEditorBuffers* *TestTolerantRead *TestReplDifferential'` (implementer 55/55 for the first
   three); `corpus-run.sh --batch <outdir>` 85/69/0 over 154; `repl-smoke.sh` 8/66 goldens clean; `lsp-smoke.sh` 287
   (list the 50 new checks by fixture); boot 129; `.ei` 0 after cleanup; index build time on Report.e (implementer
   +2 to +7 ms warm, 7305 → 7980 occs) — one pair, and whether the round trip moved beyond the floor.
7. **The report and its gaps section (§6).** Accurate against your numbers? Are the three stated gaps (operator
   import-list items; multi-spelling refusal; last-equation def-site) the complete list?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), gate table
(implementer vs yours), verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why). Your numbers go into the trackers.
STOP after the report.
