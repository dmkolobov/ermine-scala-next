# Review brief: LSP Stage 3 item 6.7 — wiring, docs, demo, and the G3 gate numbers

You are reviewing item 6.7 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `9dbab71`
plus the UNCOMMITTED deliverables: `docs/lsp.md` (rewritten), `editor/vscode/{package.json,README.md,test/load-test.js,
ermine-lang-0.1.1.vsix}` (+ the old 0.1.0 vsix removed?), new `tracker/tools/lsp-demo.py`, `lsp-demo.sh`,
`tracker/lsp-tests/G3-demo.txt`, report `tracker/loopmodel/LSP3-6.7-WIRING.md`). Implementer's brief
`tracker/loopmodel/briefs/brief-LSP3-6.7.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.7 and **GATE G3**;
`tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.7/` and your
report `tracker/loopmodel/LSP3-6.7-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt and node allowed. ONE JVM at a time, no background JVMs, no lingering polling shells (the extension load test
leaked a server JVM before the implementer's fix — check for one after you run it); delete every `.ei` you cause; do
not touch `tracker/lean/`; no commits. This item is where G3's numbers come from, so your job is to make them yours.

1. **`git diff -- core/src` must be EMPTY** (6.7 ships no server change). Confirm. Then the docs: read `docs/lsp.md`
   whole, against the seven Stage-3 reports and their reviews (`tracker/loopmodel/LSP3-6.*-*.md`) — is every shipped
   feature described as SHIPPED (6.2's 62.4% and named residual; every 6.3 refusal; 6.4's range rule; 6.5's staleness
   and empty-prefix decision; 6.6's sweep and refusal classes and staleness-refused; 6.1's import rule and E7's
   uncovered cascade; E8 and E9 stated where a user hits them)? Any claim in the doc that a report or review
   contradicts? Any stale number (grep for 82, 98, 185, 207, 233, 237, 306, 344, 386, 407 and check each)?
   `editor/vscode/README.md` likewise.
2. **The extension.** `npm run test:grammar` and `npm run test:load` (run from `editor/vscode`; check
   `pgrep -af ermine-lsp` after for a leaked JVM — the implementer says the RED-on-arrival test leaked one, cause a
   `vscode` stub returning `0` for `CodeActionKind.Empty`, fixed test-side). Was the fix to the STUB the right call, or
   does it hide a real client failure (does the real VS Code `CodeActionKind.Empty.append` exist — yes; so the stub
   was wrong; confirm from the vscode-languageclient source or docs). The new assertions (9 providers, `.` trigger,
   `quickfix,source` kinds): do they test what they claim? `ermine-lang-0.1.1.vsix`: unpack it (`unzip -l`) and check
   it contains the grammar, the extension, no `node_modules` bloat beyond what 0.1.0 had; is 0.1.0 removed or kept?
3. **The latency table — RE-MEASURE the two numbers G3 and Stage 4 depend on**, load < 1.5 at start:
   (a) keystroke-to-diagnostics on Layout/Report.e via `tracker/tools/perf-bench.sh editor -k 15` (implementer 1.859 s
   = 0.935 + 0.600 + 0.300 + 0.028, 97/154 reused). The G2-era figure was 1.57 s (0.80 + 0.45 + 0.30); Stage 3's
   per-item pairs each showed no move. Is 1.86 vs 1.57 machine drift, the index/symbol build now on the check path
   (12-23 ms — cannot be 300 ms), or something real? Do ONE interleaved pair against a scratch worktree of the
   Stage-3-opening commit `78d860f` (before any Stage-3 code) — before/after/before/after — and say. (b) the
   worst-case request wait during a check (implementer: hover sent 352 ms after the keystroke answered 1.82 s later,
   1468 ms median wait; the server does not read the request until the check ends) — reproduce with the scripted
   client. The rest of the table (completion 6.5 ms, workspace/symbol 1.58 ms warm, documentSymbol 32 ms, index
   13-23 ms warm, codeAction 52 ms first / ~1 ms after): spot-check two.
4. **The demo transcript** `tracker/lsp-tests/G3-demo.txt`: re-run `lsp-demo.sh`; the transcript must be reproducible
   modulo timings; every G3 capability appears (list them against the roadmap's GATE G3 line and the Stage-3 items).
5. **Gates, re-run ONCE — this is G3's evidence:** `sbt core/compile core/copyResources`; `TestLoopTrace` 720/720;
   `corpus-run.sh --batch <outdir>` 85/69/0 over 154; `repl-smoke.sh` 8 groups / 66 checks with `git status
   tracker/repl-tests` clean; `lsp-smoke.sh` 454; `g1-validate.sh` 9/9 (implementer: no drift); boot 129; then TIER 2:
   `sbt -batch -J-Xmx3g core/test` ALONE on the tree — implementer **988 passed, 0 failed, 0 errors, 25m56s**. Yours
   is the second run of the final tree (the 6.0 determinism claim: three consecutive greens were shown at 6.0; this
   pair on the final tree is the G3 evidence). If red: run once more, report both. `.ei` 0 after.
6. **The G3 table in the report** (§ what G3 asks → where checked → number): complete? Does it state plainly what is
   NOT satisfied (6.2 PARTIAL; E8/E9 open; E7 and the group-level 0:0 residual)? Anything G3 asks for that is missing?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), the re-measured
latency numbers beside the implementer's, the full gate table (implementer vs yours), verdict ADVANCE /
FIX-THEN-ADVANCE (list) / BLOCK (why). Your numbers are the ones that go into "Gate evidence (G3)". STOP after the report.
