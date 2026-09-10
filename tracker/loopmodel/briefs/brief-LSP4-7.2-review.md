# Review brief: LSP Stage 4 item 7.2 — anchored positions (the inference cache survives line shifts)

You are reviewing item 7.2 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `6db2c3a`
plus the UNCOMMITTED deliverables: new `surface/Anchors.scala`; `session/TolerantCheck.scala`; `lsp/Resident.scala`;
new `scalacheck-binding/src/main/scala/AlphaEq.scala` (the 6.6 sweep's comparator, moved); `TestTolerantCheck.scala`
(+17 properties); fixture `tracker/lsp-tests/Anchor.e`; `tracker/tools/lsp-client.py`; `docs/lsp.md`; report
`tracker/loopmodel/LSP4-7.2-ANCHORS.md`). Implementer's brief `tracker/loopmodel/briefs/brief-LSP4-7.2.md`; item of
record `tracker/LSP-ROADMAP.md` § Stage 4, 7.2, the STAGE-4 INVARIANTS ("NO IDENTITY IN A CACHE KEY, AND NO ID IN A
CACHED VALUE THAT ESCAPES") and Decision (b); Stage 3 Decision (b) and the 6.2 review's R-7 (the five drift attacks);
`tracker/GATE-POLICY.md` (this is an ADOPTION item: shipped editor behaviour changes → Tier 2 is owed once; you run
it). You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-7.2/` and your
report `tracker/loopmodel/LSP4-7.2-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed. ONE JVM at a time, no background JVMs, no lingering polling shells; delete every `.ei` you cause; do not
touch `tracker/lean/`; no commits. Strict path: `git diff -- core/src/main/scala/com/clarifi/reporting/ermine/session/
Session.scala .../rename/NewPipeline.scala` must be empty; `git diff --stat` vs `--stat -w` (the implementer notes a
Myers-vs-histogram artifact — check with `--histogram`).

1. **THE INVARIANT.** Keys: a group's text with statements tagged by offset from the group's first line; component key
   = group texts + each group's offset from the component's first line; `Entry.locals` def-sites as `(line − anchor,
   col)`, re-anchored at lookup by the component's CURRENT first line. Attack it: (a) two groups with byte-identical
   BODIES and different heads (pinned, they say) — and two groups with identical heads? impossible (a head word IS a
   group) — confirm; (b) a component of TWO mutually recursive groups whose relative offset changes because a line
   is inserted BETWEEN them — the component key must miss (the offset is in the key) — verify it misses rather than
   re-anchoring the second group wrongly; (c) a group whose FIRST line is a comment or blank (does the anchor start
   at the head token or the extent start, and does `StatementExtents` agree with what `collectLocals` recorded?);
   (d) a def-site on the group's first line (Δ = 0) and on its last; (e) a `where`-local whose def-site is in a
   CONTINUATION line of a multi-line equation; (f) CRLF buffer (line arithmetic only — fine? confirm the fixture);
   (g) the "duplicate rule" claim that no ordinal is needed — construct the near-miss they pinned and one they did
   not (same head word inside `private` AND at top level — legal? the renamer treats them as one group or two?).
2. **NO CACHED POSITION ESCAPES.** The report claims every reply's position comes from the current run (renamer,
   surface tree, env) and `locals` keys are only a join key; the residue: a cached `Type`'s `Loc` could reach a note
   BODY via `unifyType`/`occursFail` on a shift+break edit — tested 0 differences on 249 modules. Read `collectLocals`,
   `Definitions.index`'s locals join, `References`, `Symbols`, `QuickFix`, `Completion` for any read of a cached
   value's position; sabotage `Anchors.absPos` yourself (+1) and list which lsp-smoke checks fail (implementer: the
   where-local pin, the unsigned-let pin, one 6.2 pin) — are the routes that do NOT fail genuinely position-free, or
   unpinned?
3. **THE CLIFF, RE-MEASURED.** Implementer: top-insert 0/154 → 115/154 (`checkWith` 1001 → 489 ms), top-delete 0 →
   115 (984 → 429), mid-insert 83 → 115 (712 → 424), top-insert+body 0 → 97 (1023 → 578). Reproduce top-insert and
   mid-insert once each through the real server with `-Dermine.lsp.phases=true`. Why 115 and not 154 on a pure
   top-insert — which 39 components still miss, and is it the same 57 that miss on any body edit (97/154)? Explain
   the 154−115 residue from the keys (a group whose text legitimately contains an absolute line? a scope-key
   component — imports, fixity — moving?). Steady-state A/B: 1.7640 → 1.7625 s (Δ −1.5 ms) — run ONE interleaved pair
   yourself (load < 1.3) to confirm the steady state is unmoved.
4. **THE TWO PRE-EXISTING FINDINGS** (not caused by 7.2; confirm and assess for tickets): (i) 16 of 249 modules render a
   published type differently on a reuse with NO edit — ids differ between runs and the printer's order follows
   id-keyed sets, so a rendered-string comparison is not a sound invisibility oracle (which is why the comparator
   moved to `AlphaEq.scala` with four controls); (ii) 2-3 of 249 publish DIFFERENT ROW CONSTRAINTS on two cold checks
   in the same JVM (`WriterOutputs.e` `reportFor`, one simplified and one not) — the simplifier's queue is id-hash
   ordered. Reproduce (ii) once: is it the documented solver-order sensitivity (the reason `-Dermine.loadInSeries`
   exists; G1's lookbackJoin delta) surfacing on the editor path, and does the 6.2 hover show a different type for
   the same unchanged definition across checks? If yes, that is a user-visible nondeterminism worth a ticket — say
   what the ticket should ask for. Are the four controls in the comparator each justified by a real count, or do
   any of them hide a 7.2 regression?
5. **The comparator move**: `AlphaEq.scala` is the 6.6 sweep's comparator relocated; is the 6.6 sweep byte-identical
   in behaviour (they re-ran it: 1/1 green) — confirm nothing about alpha-equivalence changed in the move.
6. **Gates, re-run ONCE, plus Tier 2 (adoption):** compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly
   *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestStage1Pins *TestReplDifferential *TestRenamer*
   *TestLower'` (156 properties, TolerantCheck 44); `corpus-run.sh --batch <outdir>` 85/69/0; `repl-smoke.sh` 8/66
   goldens clean; `lsp-smoke.sh` 480 (list the 24 new); boot 129; `.ei` 0; then `sbt -batch -J-Xmx3g core/test` ALONE
   on the tree (G3 was 988; +17 properties expected ≈ 1005; say the total, 0 failed 0 errors).
7. **The report** (663 lines): accurate against your numbers? Anything the roadmap item's tick conditions ask for
   that is missing (before/after reuse count both MEASURED; Decision (b) restated and re-attacked; invisibility over
   the extended edit set; every escape route pinned after a line-shifting didChange; 6.2's locals keys pinned)?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), the re-measured cliff
and A/B beside the implementer's, the gate table with the Tier 2 total, verdict ADVANCE / FIX-THEN-ADVANCE (list) /
BLOCK (why), and your ticket recommendation for finding 4(ii). STOP after the report.
