# Review brief: LSP Stage 4 item 7.4 — adaptive debounce (ADOPTION: Tier 2 owed)

You are reviewing item 7.4 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `85eb150`
plus the UNCOMMITTED deliverables: `core/.../lsp/{Diagnostics,Documents,Rpc,Main}.scala`; `scalacheck-binding/src/main/
scala/TestEditorBuffers.scala`; `tracker/tools/{lsp-client.py,perf-client.py,perf-bench.sh}`; `docs/lsp.md`; fixture
`tracker/lsp-tests/Burst.e`; report `tracker/loopmodel/LSP4-7.4-DEBOUNCE.md`). Implementer's brief
`tracker/loopmodel/briefs/brief-LSP4-7.4.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 4, 7.4 and Decision (e);
`tracker/loopmodel/STAGE4-PRIOR-ART.md` §5(f); `tracker/GATE-POLICY.md` (adoption: you run Tier 2 — the two known
intermittents E12/E13 each get ONE re-run if exactly they are red). You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-7.4/` and your
report `tracker/loopmodel/LSP4-7.4-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed. ONE JVM at a time, no background JVMs, no lingering polling shells; delete every `.ei` you cause
(`find`); do not touch `tracker/lean/`; no commits. The orchestrator's liveness monitor no longer matches
`perf-bench.sh`'s preflight; if the preflight still refuses, report what it saw rather than working around it.

1. **THE POLICY.** `D(C) = clamp(150, 1 × C, 300)` ms, C = median of the last 5 check times of THAT document, no
   history → 300. Read `Diagnostics.Debounce` and its scaladoc. Check: the median is per-uri (a slow file cannot
   inflate a fast one's wait); the window survives an edit (carried on `Documents.Doc.checkMillis`) and is dropped on
   didClose; the first check of a new document is unchanged (300). ATTACK the argument: (a) Min 150 — the claim is
   that below the inter-keystroke interval coalescing stops; with D=150 and a typist at 120 ms/char, does a burst
   still coalesce (the queue-replace semantics: does a keystroke arriving at 140 ms RESET the quiet timer, or does
   the timer run from the first keystroke)? Read `Server.onIdle`/the queue and say exactly what "quiet for D" means;
   construct the case; (b) Max 300 not 500 — the argument is that single-threaded dispatch plus one queue entry per
   uri means checks cannot pile up; confirm from `Diagnostics.install` (queued map, versioned drop) and say whether
   TWO open documents both edited can still make the dispatch thread run back-to-back checks with no quiet gap
   (that is not pile-up, but it is the request-wait hazard: with D=150 the thread is busier — quantify the duty
   cycle on Report.e: check 0.58 s, D 0.30 → 66%? and on the small file 31 ms / 150 → 17%); (c) Ratio 1 — the ratio is
   live only in 150..300: confirm the output table (§1.2) from the function; (d) a hover sent during the debounce
   window is answered immediately (the window is idle time) — confirm nothing in this item changed request handling.
2. **OSCILLATION.** Reproduce the D series over 15 rounds for Options.e (implementer: 199→170 tracking C within ±8%)
   and List.e (300 260 150…); check the cold-open forgetting (2329 ms outvoted at 2 warm samples, gone at 5 — is a
   median of 5 with ONE cold sample robust to a second cold sample, e.g. a 7.2 scope-key drop on an import edit?
   what D results and for how many rounds?). Is there any input sequence that makes D alternate 150/300 on
   consecutive rounds? (A file whose check hovers around 150 or 300 ms.)
3. **THE BURST PIN.** JVM-local through `Server`/`Wire`: 8 messages 20 ms apart → exactly 1 check at D=150 and 300; 3
   arriving during a 200 ms check → exactly 2. Through the client: `Burst.e` 8+8 → 3 `check:` lines (open + 2),
   `waited == policy` asserted on 41 debounce lines. Re-run both; then PLANT: set Min to 10 ms in scratch and show
   the burst pin fails (bursts split) — i.e. the pin has teeth; restore, hash-check.
4. **THE A/B — re-measure the acceptance file and the large file yourself**, interleaved, load < 1.3: Reader.e
   0.3204 → 0.1719 s (−149 ms); Report.e 0.8955 → 0.9063 (+11 ms, inside spread). Confirm the read and typecheck
   segments are unmoved (controls) and reuse identical. One pair each is enough.
5. **BENCH COMPARABILITY.** `perf-bench.sh editor` now pins D=300 via `initializationOptions.debounce`
   (`--pin-debounce 300`) so its numbers stay comparable with P1/G3/7.1b; `perf-client.py` harvests the window from
   the server's `debounce:` log line (fallback 0.300 with a note on a pre-7.4 server). Verify: run `perf-bench.sh
   editor -k 5` once and confirm the debounce column reads 0.300 and the round trip matches 7.1b's ~0.90 s on
   Report.e; run `perf-client.py` unpinned once and confirm the harvested window. Is the `debounce` option documented
   (docs/lsp.md; the vscode README if a setting)? Does pinning via initializationOptions leak into the real editor
   (it must default to adaptive)?
6. **Gates, re-run ONCE, plus Tier 2:** compile+copyResources; `TestLoopTrace` 720/720; `*TestEditorBuffers
   *TestTolerantCheck *TestSurfaceCache` 64/64; `corpus-run.sh --batch <outdir>` 85/69/0; `repl-smoke.sh` 8/66 goldens
   clean; `lsp-smoke.sh` 510 (list the 16 new); boot 129; `.ei` 0 by `find`; `git diff --stat` == `--stat -w
   --histogram`; line endings; then `sbt -batch -J-Xmx3g core/test` ALONE (expected 1026 = 1020 + 6; E12/E13 rule).
7. **docs/lsp.md**: the rule as a function, the constants, the reason, the three files' round trips; the Latency
   table's debounce row. Accurate against your numbers?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), your A/B beside theirs,
the gate table with the Tier 2 total, verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why). STOP after the report.
