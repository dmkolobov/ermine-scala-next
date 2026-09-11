# Review brief: LSP Stage 4 GATE G4 — the SLIMMED evidence review (decided with the user 2026-09-11)

You are reviewing the G4 evidence run in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD
`d8fba0a` plus the UNCOMMITTED deliverables: `tracker/loopmodel/LSP4-G4-GATE.md` (the report — PHASE A measurements and
PHASE B gates), `docs/lsp.md`, `editor/vscode/{README.md,package.json}` (0.1.2), `tracker/tools/lsp-demo.{py,sh}`,
`tracker/lsp-tests/G4-demo.txt`). The G4 brief `tracker/loopmodel/briefs/brief-LSP4-G4.md`; the roadmap's GATE G4
line (`tracker/LSP-ROADMAP.md` § Stage 4); `tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-g4/` and your
report `tracker/loopmodel/LSP4-G4-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`.
ONE JVM of yours at a time; the user has a separate worktree with its own sbt — expect load; do not touch it. No
commits; delete every `.ei` you cause (`find`); do not touch `tracker/lean/` or `tracker/LSP-ROADMAP.md`.

WHY THIS REVIEW IS SLIM, so you spend the time where it counts: the trace differential, the interface sweep and the
full `core/test` are deterministic and were run by the implementer with recorded outputs; re-running them cannot
disagree unless the COMPARISON METHOD is wrong, and that is checked by reading, not by 40 minutes of replay. Every
adoption item already had its own reviewer's interleaved A/B. The one number on a DECISION THRESHOLD is the
worst-case request wait (544 ms median, n=5, one load) against 7.6's 500 ms unpark trigger — that gets a real
independent measurement. Everything else is a reader's job: numbers against their sources.

1. **THE WAIT, PROPERLY MEASURED (your one JVM-heavy task; needs a quiet-ish moment — wait for load < 2 and state
   it).** The 6.7 protocol: didChange on Layout/Report.e, a hover sent just past the debounce, timed send → answer.
   (a) n ≥ 10 at steady state (checks flat, no hover traffic before the block — the implementer found a probe order
   that degraded checks 0.59 → 0.95 s; avoid it and say so); report median, min, max. (b) the same at a deliberately
   later send offset (e.g. +600 ms — mid-check) to show the wait is "the remainder of the check", and at +100 ms
   (inside the debounce window — the request should be answered immediately, ~0.3 ms, since the window is idle
   time). (c) THE PRECONDITION PROBE for 7.6: with fast mode ON (`initializationOptions.fastMode: true` or the
   settings push), the check is read-only (~0.05 s): what is the worst-case wait then? That is the "fastMode-first"
   answer the roadmap owes before any thread. (d) Your verdict in one sentence: is 544 ms real, on which side of
   500 does it land with n ≥ 10, and does fast mode take it under? This is the number the user decides Stage 5 on.
2. **METHOD-CHECK THE IDENTITY GATES (read, do not replay):** the implementer's `trace-ab.py` invocation and the
   per-group outputs in its scratch (`g4/`) — all 16 record kinds compared, `sinmoved=0`, every group rc 0, the
   before-side genuinely built from `ed42f55` (how was that verified — a class inventory? a `ParseState` arity
   check as 7.1a's reviewer did?); the corpus byte-identity normalisation (progress frames, `(N.NN seconds)`, root
   path ONLY — read the normaliser and confirm it cannot hide a real difference); the interface sweep's
   classification (0 of 268 differ — read one chunk's raw diff). Spot-check ONE trace group yourself by replaying it
   (a small one, e.g. `boot`) on both builds if a build of `ed42f55` still exists in scratch; otherwise say so.
   Tier 2: read the implementer's log (total, failures, the E12/E13 rule applied?) — do NOT re-run.
3. **THE RECORD AGAINST ITS SOURCES (read):** every row of the docs' latency table against LSP4-G4-GATE.md PHASE A
   (and every stale number gone — grep 1.69, 1.86, 0.86, 0.84, 1.47, 480, 494, 510); the README's "three things";
   the report's G4 table: each GREEN and NUMBERS line of the roadmap's GATE G4 → where checked → the number, with the
   per-item A/B figures quoted from the RIGHT reviewer-of-record report (7.2: LSP4-7.2-REVIEW; 7.1a; 7.1b; 7.4 —
   open each and compare); "REVERTED items: none" true?; the not-satisfied list complete (7.3 handed off; 7.6 parked
   with the 544 ms finding; the 6.2 fork; the private-block cliff; E12/E13; the open tickets E5-E13 states)?
4. **THE DEMO:** run `tracker/tools/lsp-demo.sh` once (one JVM) and diff against `G4-demo.txt` modulo timings; every
   Stage-4 behaviour present (reuse line, top-insert reuse 115/154, the burst coalescing at 150 vs 300, Tab.e,
   the source-tree definition)?
5. **THE EXTENSION:** `npm run test:load` once (check for a leaked JVM after) — 0.1.2's changes are text; confirm the
   vsix exists and 0.1.1 is gone.

Report format: the wait table (yours, n ≥ 10, three offsets, fast-mode probe) with your one-sentence verdict FIRST;
then findings (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each); then a checklist of the roadmap's G4
lines with ✓/✗ and where you verified each; verdict ADVANCE (write the gate evidence) / FIX-THEN-ADVANCE (list) /
BLOCK (why). Budget: about 40 minutes of wall time. STOP after the report.
