# Review brief: LSP Stage 4 item 7.1b — the statement-extent surface cache (ADOPTION: Tier 2 owed)

You are reviewing item 7.1b in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `9180d28`
plus the UNCOMMITTED deliverables: new `core/.../surface/SurfaceCache.scala`, `scalacheck-binding/src/main/scala/
TestSurfaceCache.scala`, fixture `tracker/lsp-tests/Splice.e`; modified `core/.../surface/SurfaceParsers.scala`
(158 insertions / 0 deletions — the strict `module` is claimed untouched in behaviour), `core/.../rename/NewPipeline.scala`,
`core/.../lsp/Documents.scala`, `core/.../lsp/Resident.scala`, `tracker/tools/lsp-client.py`; report
`tracker/loopmodel/LSP4-7.1b-CACHE.md`). Implementer's brief `tracker/loopmodel/briefs/brief-LSP4-7.1b.md`; item of
record `tracker/LSP-ROADMAP.md` § Stage 4, 7.1b, the STAGE-4 INVARIANTS ("A REUSED SURFACE TREE MUST BE BYTE-FOR-BYTE
WHAT A FRESH PARSE WOULD GIVE"; "REUSE METADATA SURVIVES REUSE"; "NO IDENTITY IN A CACHE KEY"), Decisions (a)(g), the
7.1a review's obligations (§7: relative `examinedLength`; forward-only guard so start column and layout depth stay in
the condition; join marks by position; header extents and slices carry no mark); `tracker/GATE-POLICY.md` (ADOPTION:
you run Tier 2, the full `core/test` alone). You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-7.1b/` and your
report `tracker/loopmodel/LSP4-7.1b-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`core/clean core/compile` if the E046 quirk bites). ONE JVM at a time, no background JVMs, no lingering
polling shells; delete every `.ei` you cause (`find`); do not touch `tracker/lean/`; no commits.

1. **STRICT PATH FROZEN — first.** `SurfaceParsers.scala` has 158 insertions and 0 deletions, and the implementer says
   `moduleP` "runs unchanged" and the cache is "the real driver" that skips statement BODIES. Read the diff: is the
   strict `SurfaceParsers.module` (and `readModule`, the REPL, the interface reader) byte-for-byte the same BEHAVIOUR —
   same combinators, same order, no new parameter with a default that could be non-identity, no shared mutable state
   the strict path now touches? `Session.scala` untouched (confirm). Corpus outputs 154/154 identical to the pre-change
   class tree (reproduce with your own pre-change build, normalising only progress frames, timings, classpath prefix);
   REPL goldens byte-clean; `TestReplDifferential` and `TestTolerantRead`'s agreement property green.
2. **THE DIFFERENTIAL — re-run it, then attack it.** Seed 71, 253 files × up to 12 steps = 2,613 steps, 54,274 hits /
   19,374 misses, 0 SModule mismatches (structural equality incl. every Span), 0 diagnostic mismatches over 2,601
   two-tree steps (12 refusal steps agreed). Re-run with the SAME seed (must reproduce exactly) and with TWO OTHER
   seeds (report both). Then attack: (a) the equality — is `SModule` structural equality really total (case classes
   all the way down? any `Array`, function, or `Loc` with reference equality? `SErrorStatement` messages compared?);
   (b) the guard is evaluated "directly on the bytes" (`examinedUnchanged`) — construct an edit INSIDE a statement's
   guard region but OUTSIDE its extent that changes the preceding statement's parse (the 7.0 §4.3 shape, the Lean
   `private def` shape, the 7.1a F1 `-x`/`--` shape at a statement boundary) and confirm a MISS, not a stale hit;
   (c) the END-SPAN finding: the whole-file parse ends a statement at its extent end for 59,167 corpus statements and
   at the next extent's start for 3,502 (laid-out blocks where `virtualRightBrace`'s trivia skip is not rolled back) —
   the brief's blanket re-derivation was wrong and the implementer parses misses IN SITU instead; verify the 3,502
   claim on a sample and that a HIT's shifted end-span equals what a fresh parse gives in both classes; (d) the
   header: re-parsed every check, "8 ms of 844" — confirm; and the `module ... where` line edited (a new import)
   drops everything? (e) an edit that changes a statement's START COLUMN or its layout DEPTH with identical text (the
   forward-only-guard obligation) — miss?; (f) a byte-identical statement MOVED past another (ordinal changes) — hit
   with a correct splice, or miss? (g) two byte-identical statements (duplicate definitions, a refusal) — which entry
   serves which, and is the refusal reproduced?; (h) unreachable items keyed by the scanner's head word — collision
   only costs a hit (they claim): confirm the reuse condition (text + start col + depth + guard) makes a wrong tree
   impossible; (i) a file that does not parse at all (header failure) — the cache state after it, and the next check.
3. **THE A/B — re-run one interleaved pair yourself** (`perf-client.py -k 15` on Report.e, load < 1.3): implementer
   pooled read 0.8425 → 0.0525 s (−790 ms), round trip 1.681 → 0.896 s, typecheck control +3 ms, reuse 97/154. Then
   the MISS distribution (their 7.0-protocol harness): body edit 29.2 ms (528/529), private-block edit 125.8 ms, EOF
   append 124.8 ms, pure line shift 26.5 ms, cold +2.8 ms. Re-measure two. Then the WORST case for a user: what does
   a keystroke inside the 10.7 KB private block cost end to end now (read + typecheck + debounce)? And the cold open?
4. **RETENTION:** 1,630 KB per open document for Report.e (surface tree 1,578 KB + entries 53 KB) plus a ~76 KB
   previous buffer; dropped on didClose. Reproduce the figure once; is anything else retained (the previous
   `Checked`? the marks?); with ten open stdlib files, what is the bound?
5. **The 7.1a coupling.** 7.1a's editor cost (+20..48 ms read) was accepted as this item's precondition: with both
   in, the read is 0.05 s — state the NET against the Stage-3-opening baseline (G3's 0.86 read / 1.69 round trip).
   And the roadmap's REVERT rule (if 7.1b is reverted, 7.1a comes out): not triggered — say so.
6. **GATES, RE-RUN ONCE, plus TIER 2:** compile+copyResources; `TestLoopTrace` 720/720; seven targeted suites +
   `*TestSurfaceCache` (112 properties); `corpus-run.sh --batch <outdir>` 85/69/0 over 154 + byte-identity; `repl-smoke.sh`
   8/66 goldens clean; `lsp-smoke.sh` 494 (list the 14 new); boot 129; `.ei` by `find`; `git diff --stat` == `--stat -w
   --histogram` (294/8); line endings; then `sbt -batch -J-Xmx3g core/test` ALONE on the tree (7.2 was 1008; expect
   1008 + TestSurfaceCache's properties; say the total, 0 failed 0 errors). Also `g1-validate.sh` 9/9 (SurfaceParsers
   changed).
7. **The report and what a user now sees**: keystroke-to-diagnostics before/after; is `docs/lsp.md`'s latency table
   updated (or is that 7.7/G4's job — say)? The item's tick conditions: differential recorded with its seed; A/B
   pooled Δ ≥ 200 ms on the read; heap figure; Tier 2 — all present?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), your differential and
A/B beside the implementer's, the gate table with the Tier 2 total, verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK
(why). Your numbers enter the roadmap and G4. STOP after the report.
