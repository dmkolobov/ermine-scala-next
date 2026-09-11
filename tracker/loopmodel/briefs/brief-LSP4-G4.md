# Brief: LSP Stage 4 — the GATE G4 evidence run (no new feature; the numbers G4 asks for, docs, the demo transcript)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (7.0, 7.2, 7.1a,
7.1b, 7.4, 7.5 committed; 7.3 handed to PERF-ROADMAP; 7.6 parked). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`core/clean core/compile core/copyResources` if the E046 quirk bites); node for the extension tests.
ONE JVM at a time, no background JVMs, no lingering shells. No commits. Do not touch `tracker/lean/` or
`tracker/LSP-ROADMAP.md` (the orchestrator writes the gate evidence from your report). Delete every `.ei` you cause
(`find`). Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/g4/`.
Item of record: `tracker/LSP-ROADMAP.md` § "Stage 4", **GATE G4** (its GREEN list and its NUMBERS RECORDED list are
your checklist), the STAGE-4 INVARIANTS, and every Stage-4 report and review (`tracker/loopmodel/LSP4-7.*.md`) — the
docs must describe what SHIPPED, with every stated cost and gap (7.1a's editor residual; 7.1b's cold-open +30..70 ms
and ~1.6 MB per document; 7.2's cold check on edits inside operator/backtick/`_`/`'` definitions; 7.4's first-check
300 ms; 7.5's dispositions), not the plan. `tracker/GATE-POLICY.md` (Tier 2 alone; E12/E13 single re-run rule).

**TWO PHASES, AND A STOP BETWEEN THEM (the user wants the machine back for parallel work).** PHASE A is every
measurement that needs a QUIET machine (load < 1.3): G4.1 and G4.2 below, nothing else. Do them first, in one
sitting, then write a SHORT interim report (the two tables, with loads) to `tracker/loopmodel/LSP4-G4-GATE.md` under a
heading "PHASE A — measurements (machine quiet)", and STOP. The orchestrator will tell the user the quiet window is
over and resume you for PHASE B (G4.3-G4.6: the demo, the extension, Tier 1, Tier 2, the docs, the full report),
which needs ONE JVM of yours but tolerates other load on the machine — during PHASE B, expect another sbt in a
SEPARATE worktree (`ermine-scala-tc` or similar) and possibly a second Ermine JVM there: that is fine for byte-identity
gates and test runs; it is NOT fine for timings, which is why timings are in PHASE A. If any PHASE B step needs a
timing after all (it should not), say so in the report rather than measuring under load.

## What to do — PHASE A (quiet machine, load < 1.3 at the start of every measured run)
G4.1 **7.0's PHASE TABLE, AFTER THE STAGE** — the number G4 was written around. Re-run 7.0's instrumented
     measurement on the FINAL tree (`-Dermine.lsp.phases=true`, Layout/Report.e, 50 reps after 20 warm-ups, load <
     1.3, through the real server on a warm in-body edit) and put it beside 7.0's BEFORE table row for row: parse
     (844 → ?), rename, lower, header, extents (now twice — 7.1b R-4), keys, index, checkWith, check.total, and the
     debounce as the policy sets it. Also the small file (Control/Monad/Reader.e) the same way. State the
     reconciliation (phases sum vs check.total).
G4.2 **THE LATENCY TABLE, RE-MEASURED** for docs/lsp.md (load < 1.3 at every run, one JVM): boot; keystroke →
     diagnostics on Report.e (`perf-client.py` UNPINNED so the adaptive debounce is what a user gets, AND `perf-bench.sh
     editor -k 15` PINNED at 300 for the roadmap-comparable number — both, labelled); the same on Reader.e and
     Options.e; the WORST SITE (a keystroke inside Report.e's 10.7 KB private block, end to end); the COLD OPEN of
     Report.e; **the worst-case request wait DURING a check** (the 6.7 protocol: a hover sent just past the debounce,
     timed send → answer; G3's figure was 1.45 s — the check is now ~0.55 s warm, so expect ~0.5 s; this is the
     number 7.6's worker-thread trigger of 500 ms is judged against — say which side of it we land); completion,
     workspace/symbol, documentSymbol, code action, index build (spot-check that they are unchanged). Every stale
     number in docs/lsp.md and editor/vscode/README.md replaced (grep for 1.7, 1.69, 1.86, 0.86, 0.84, 1.47, 300 ms as
     a fixed debounce, 494, 510 etc.).
## PHASE B (after the orchestrator resumes you; one JVM of yours, other load tolerated)
G4.3 **THE DEMO TRANSCRIPT** — extend `tracker/tools/lsp-demo.sh`/`lsp-demo.py` with a Stage-4 section: an edit on
     Report.e showing the `check:` line with the reuse count and the read time; a top-of-file insertion showing the
     inference cache holding (7.2); a burst of keystrokes showing one check and the adaptive window (7.4); a
     tab-indented file's hover landing on the text (7.5 E8); a stdlib definition landing in `core/src/main/resources`
     (7.5 E9). Save as `tracker/lsp-tests/G4-demo.txt`, reproducible modulo timings.
G4.4 **THE EXTENSION**: `npm run test:grammar` and `npm run test:load` (check for a leaked JVM after); bump to 0.1.2 and
     rebuild the vsix if anything user-visible changed (the debounce option? E8/E9 behaviour) — say whether a bump is
     warranted; README's "three things that will surprise you" section updated (E8 and E9 are fixed; the 6.2 residual
     remains; add the cold-open cost and the per-document memory).
G4.5 **THE FULL GATE, in this order, one JVM at a time, nothing else on the machine**: `core/clean core/compile
     core/copyResources`; `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>` 85/69/0 over 154 and byte-identical
     to a build of the G3 commit `ed42f55` — the whole stage's batch identity in one comparison; `repl-smoke.sh` 8/66 goldens unmodified; `lsp-smoke.sh` (542 after 7.5);
     `g1-validate.sh` 9/9; boot 129; then TIER 1 ONCE FOR THE WHOLE STAGE (the parser library changed in 7.1a):
     `looptrace-corpus.sh` + `trace-ab.py` against the G3-commit build (all record kinds, IDENTICAL, sinmoved 0) and
     `ei-diff.sh --snapshot --batch` in series both sides (0 of 268 differ); then TIER 2: `sbt -batch -J-Xmx3g
     core/test` ALONE (expected 1026 plus 7.5's new properties — TestRenamer 32 -> 34 and TestTolerantCheck's additions — say the total; E12/E13 rule — report every run). `.ei` 0 by `find` after each.
G4.6 **REPORT `tracker/loopmodel/LSP4-G4-GATE.md`**: the phase table before/after; the latency table with methods;
     the demo path; the extension results; EVERY G4 line (GREEN list and NUMBERS list) → where checked → the number,
     including the per-item A/Bs (7.2, 7.1a both targets, 7.1b, 7.4 — quote each item's reviewer-of-record figure),
     the 7.1b differential with its seed, 7.2's reuse counts, the heap figure, and "REVERTED items: none" (or the
     list); anything G4 asks for that is NOT satisfied, stated plainly (7.6 parked; 7.3 handed off; the 6.2 fork still
     the user's). Outcomes GREEN / PARTIAL. STOP after the report — a reviewer re-runs the gates once, then the
     orchestrator writes "Gate evidence (G4)" and stops for the user's sign-off.
