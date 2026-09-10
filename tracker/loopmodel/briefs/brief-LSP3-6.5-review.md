# Review brief: LSP Stage 3 item 6.5 — completion

You are reviewing item 6.5 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `46f88e1`
plus the UNCOMMITTED deliverables: new `lsp/Completion.scala`; `lsp/Definitions.scala`, `Resident.scala`, `Main.scala`;
`rename/Renamer.scala` (SHARED FILE — two fixes to `scopeAt` and the do-binder frame); `scalacheck-binding/src/main/
scala/TestRenamer.scala`; `tracker/tools/lsp-client.py`; fixtures `tracker/lsp-tests/Complete.e`, `CompleteSib.e`;
`docs/lsp.md`; report `tracker/loopmodel/LSP3-6.5-COMPLETION.md`). Implementer's brief
`tracker/loopmodel/briefs/brief-LSP3-6.5.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.5 with the STAGE-3
INVARIANTS and Decision (c); gates `tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.5/` and your
report `tracker/loopmodel/LSP3-6.5-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs, no lingering polling shells; `sbt
core/compile core/copyResources` before any `bin/ermine` gate; delete every `.ei` you cause; do not touch
`tracker/lean/`; no commits. `git diff --stat` must equal `--stat -w`.

1. **THE SHARED FILE FIRST.** `rename/Renamer.scala` changed: (a) `Result.scopeAt` folded the wrong way (outermost
   binding won; 88 corpus disagreements) and (b) a `do` binder's `Frame` covered only its own bind statement (33
   more). Establish from the code whether `frames` and `scopeAt` are consumed by ANYTHING other than the editor:
   the renamer's own resolution uses its `Env` (`lookup(env, spelling)`), not `frames` — confirm; grep every
   `frames`/`scopeAt` reader in `core/src/main` and the tests. If the batch path never reads them, batch is frozen by
   construction and the corpus verdicts / REPL goldens / TestLoopTrace agreement are confirmation, not proof —
   say which. If anything on the strict path DOES read them, the tier is Tier 1 and you say so at the top. Then check
   the two fixes themselves: is innermost-first now right for EVERY frame shape (nested `let` in `where` in a `case`
   alt in a lambda; two sibling frames at the same nesting; a frame whose span equals its parent's)? Is the new
   do-binder frame span exactly "from the bind statement to the end of the do block" and not one statement too far
   (the binder must NOT be visible in its own rhs — `x <- f x` refers to an outer x)? The scope-agreement property
   (0 of 6643 value-local occurrences disagree; 55 shadowed as anti-vacuity) — re-run, and check that the property
   compares `scopeAt(occurrence start)` to the occurrence's resolved binder id, not to a spelling.
2. **Context rules.** `import`/`export` line → module context; `.` after an upper-initial dotted path → qualified;
   else name; `--` / same-line `{- -}` / string → `[]`; operators not completed. Probe: cursor right after `import `
   (empty prefix → all modules, capped?); `import Layout.` (the `Layout.*` set and nothing else); `import X (a, b|`
   (the report says an import LIST is treated as a name context — so it offers locals and keywords inside an import
   list: wrong but harmless? or should it offer X's exports? decide, state); `Bool.n|` → Bool's `not` (and the
   report's note that a dotted TERM reference does not parse unless every segment is upper-initial — so inserting
   `Bool.not` produces code the checker rejects: is qualified completion offering terms at all right? types and
   constructors yes; terms should perhaps be offered as the bare name plus an `import Bool (not)` additionalTextEdit,
   or not offered — assess and state); a cursor inside a multi-line string or block comment (known miss, stated —
   confirm it is stated in docs); a prefix that is a keyword prefix (`whe` → `where`); a prefix in TYPE position
   (`f : Bo|`) — types offered? type variables never offered (they are in no frame; stated).
3. **Items, ranking, payload.** Tiers locals < own < imported < keywords, case-insensitive matches below exact in
   tier, one item per label; detail types via `prettyTypeIn`. Empty prefix: locals + own only, cap 300,
   `isIncomplete: true` — confirm the flag is set exactly when the list is truncated or import-suppressed, and that a
   prefixed answer is `isIncomplete: false`. Unfiltered payload 1332 items / 181 KB / 34 ms — plausible. Duplicates:
   a local that shadows an own top-level, an own top-level re-exported through an import (Prelude `not` when the
   file also imports Bool) — one item, which tier? Timing: re-measure the median of 10 for prefix `f` on Report.e
   line 1504 (implementer 2.5 ms) and empty (1.8 ms); the module-context cold walk (5.3 ms) — what does it walk, is
   it cached per document or per server, and does a new `.e` file appearing on disk get seen?
4. **Staleness.** The docs state that a binder typed since the last debounced check is not offered until it lands;
   the smoke check exercises it deterministically (request immediately after didChange, then after diagnostics).
   Confirm the request DURING boot answers `[]` (not null, no wait beyond dispatch).
5. **Gates, re-run ONCE.** compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly *TestRenamer*
   *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestReplDifferential'` (implementer: four suites 74/74,
   TestRenamer 28 → 31); `corpus-run.sh --batch <outdir>` 85/69/0 over 154 (REQUIRED this time: Renamer.scala
   changed); `repl-smoke.sh` 8/66 goldens clean; `lsp-smoke.sh` 386 (list the 42 new checks by fixture); boot 129;
   `.ei` 0; Report.e round trip one pair.
6. **The report.** Accurate against your numbers? Are the two grammar findings (§4/§11: dotted term references;
   import list as name context) right, and correctly left as stated gaps rather than fixed here?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), gate table
(implementer vs yours), verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why). STOP after the report.
