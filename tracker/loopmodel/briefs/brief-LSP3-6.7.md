# Brief: LSP Stage 3, item 6.7 — editor wiring, docs, demo, and the G3 gate evidence

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (6.6 is
committed; 6.0-6.6 are all in). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`); node/npm for the extension (`editor/vscode`, `npm install` already done —
`node_modules` exists; `npx @vscode/vsce package` builds the vsix). ONE JVM at a time, no background JVMs, no
lingering shells. No commits. Do not touch `tracker/lean/` or `tracker/LSP-ROADMAP.md` (the orchestrator writes the
gate evidence there from your report). Delete every `.ei` you cause (the LSP boot writes 129 into the target module
tree). Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.7/`.
Item of record: `tracker/LSP-ROADMAP.md` § Stage 3, item **6.7** and **GATE G3**; the STAGE-3 INVARIANTS and
Decisions (c)(d) (their staleness/coverage statements must appear in the docs); `tracker/GATE-POLICY.md`. Read every
Stage-3 report first: `tracker/loopmodel/LSP3-6.{0,1,2,3,4,5,6}-*.md` and their `-REVIEW.md` — the docs must describe
what SHIPPED (including the PARTIAL of 6.2, its 62.4% and the residual; 6.6's ship-bar outcome; every refusal and
gap the reviews recorded), not what the plan asked for.

## What to do

6.7.1 VS CODE (`editor/vscode`). The client library serves completion/rename/references/highlight/symbols/codeAction
      from the server's capabilities on its own — verify by reading `src/extension.js` that nothing filters them,
      add nothing the server does not need. Check the hover markdown's `ermine` fence still renders with the TextMate
      grammar (`syntaxes/`); run `npm run test:load` and `npm run test:grammar` (these are the extension's own
      tests — record pass/fail); rebuild the vsix (`npx @vscode/vsce package`, replacing `ermine-lang-0.1.0.vsix` —
      bump the patch version in `package.json` to 0.1.1 and say so); update `editor/vscode/README.md`'s feature list
      to what ships. The `package.json` `configuration`/`commands` need no change unless a report says otherwise.
6.7.2 EGLOT: verify over the scripted transcript only (no Emacs) — the eglot snippet in `docs/lsp.md` needs no
      change unless a new capability needs client-side config (completion trigger characters are server-advertised;
      rename/references are built in). Say so.
6.7.3 `docs/lsp.md` REWRITTEN (not appended): the feature list as shipped — diagnostics (incl. 6.1's import-failure
      rule and what it does NOT cover), navigation (incl. E9's build-output caveat, plainly), hover (6.2: what has a
      type and what does not, the letter-agreement note, kinds), references/highlight/rename (6.3: the set per key
      kind, every refusal with its message, the coverage warning, Decision (c)/(d) wording), symbols (6.4: the range
      rule and what a separated signature loses), completion (6.5: contexts, ranking, the staleness statement, the
      empty-prefix decision), quick fixes (6.6: both actions, the sweep's ship-bar outcome, filtered constructs if
      any); fast mode; the RE-MEASURED latency table — measure these yourself, one run each unless noted, load < 1.5:
      session boot; keystroke-to-diagnostics on Layout/Report.e (`perf-bench.sh editor -k 15`, the median);
      WORST-CASE REQUEST WAIT during a check (a hover sent while Report.e is being checked: time from send to answer,
      which is roughly one check — measure it with the scripted client, it is the number the parked worker-thread
      fork will be judged against); completion server time on Report.e (median of 10); workspace/symbol warm query;
      documentSymbol on Report.e; index build time. The regression-harness paragraph with the current counts
      (lsp-smoke, repl-smoke, the corpus run). Stale numbers (82, 233, 237 ...) must all go. Keep it readable: the
      user-facing doc, not a report.
6.7.4 THE G3 DEMO TRANSCRIPT: one scripted-client run (`lsp-client.py` or a dedicated demo script under
      `tracker/tools/`) exercising every capability in order against the fixtures — initialize (list the advertised
      capabilities), open a broken file → diagnostics, fix it via didChange → clear, definition, hover on a local and
      a top-level, references, rename (applied, re-checked clean), documentSymbol, workspace/symbol, completion,
      codeAction (add import applied → diagnostic clears) — saved as `tracker/lsp-tests/G3-demo.txt` (request /
      response pairs, trimmed to the essentials, with the timings), so the roadmap's "Gate evidence (G3)" can point
      at a file rather than reproduce it.
6.7.5 GATES — this is the item that produces the G3 numbers, so run the FULL tier once, in this order, one JVM at a
      time, nothing else on the machine: `sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'`
      720/720; `tracker/tools/corpus-run.sh --batch <scratch outdir>` 85/69/0 over 154; `tracker/tools/repl-smoke.sh`
      8 groups / 66 checks with `tracker/repl-tests/*.expected` unmodified; `tracker/tools/lsp-smoke.sh` (the 6.6
      count); `tracker/tools/g1-validate.sh` 9/9 (it has not been run since the stage opened — if it is red, STOP and
      report: it means a published signature moved); `bin/ermine-lsp` boot 129; then TIER 2: `sbt -batch -J-Xmx3g
      core/test` in full, ALONE on the tree (~25-30 min; 943 + every property Stage 3 added — say the total and
      that it is 0 failed 0 errors; the 6.0 determinism claim: if it is red, run it ONCE more and report both).
      `.ei` cleanup after; `git diff --stat` == `--stat -w`.
6.7.6 REPORT `tracker/loopmodel/LSP3-6.7-WIRING.md`: the extension changes and its test results; the docs rewrite
      summary (sections, the latency table with every number and how each was measured); the demo transcript path;
      EVERY gate number in a table with the GATE G3 line from the roadmap beside it (what G3 asks for → where it is
      checked → the number); anything G3 asks for that is NOT satisfied, stated plainly (e.g. 6.2 is PARTIAL; the
      6.6 ship bar if it was not met). Outcomes GREEN (every G3 line satisfied or its shortfall stated) / PARTIAL.
      STOP after the report — a reviewer re-runs the gates once, then the orchestrator writes the G3 evidence and
      stops for the user's sign-off.
