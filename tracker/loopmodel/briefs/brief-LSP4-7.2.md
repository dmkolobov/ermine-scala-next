# Brief: LSP Stage 4, item 7.2 — anchored positions: the inference cache survives an edit that shifts lines

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (7.0 is
committed; its report `tracker/loopmodel/LSP4-7.0-READ.md` is the measured premise for this stage). Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs, no lingering polling shells when you stop. No
commits. Do not touch `tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.2/`.
Item of record: `tracker/LSP-ROADMAP.md` § "Stage 4", item **7.2**, with the STAGE-4 INVARIANTS (especially "NO
IDENTITY IN A CACHE KEY, AND NO ID IN A CACHED VALUE THAT ESCAPES" and "NO NEW BUDGET FOR THE READ WITHOUT 7.0")
and Decisions (a)(b); `tracker/GATE-POLICY.md`; the Stage-3 item 5.5 design notes (roadmap § Stage 2, 5.5, and the
2026-08-31 5.5 log entry: START LINES were put in the key so a reused entry could never carry drifted positions —
that is the argument this item replaces, not ignores); Stage 3 item 6.2's Decision (b) and its report
`tracker/loopmodel/LSP3-6.2-LOCALS.md` §3 plus review `LSP3-6.2-REVIEW.md` R-7 (the five attacks on the drift
invariant, which must be RE-RUN against the anchored form); `session/TolerantCheck.scala` (`keys`, `Cache`,
`Cache.Entry`, `checkWith`, `collectLocals`), `lsp/Definitions.scala` (how `locals` is joined by def-site),
`lsp/Documents.scala`.

THE MEASURED PREMISE (7.0, do not re-derive): a body edit on Layout/Report.e keeps 97 of 154 components and
typechecks in 0.53-0.64 s; ONE BLANK LINE INSERTED AT THE TOP drops reuse to 0 of 154, typecheck 1.07 s, round trip
2.29 s vs 1.79 — a +0.52 s cliff for an edit that changed no definition. Cause (CODE-DERIVED, roadmap 7.2):
`TolerantCheck.keys` builds each group's text as `x.startLine + ":" + off.text(x)`, so every key moves when lines
shift; and `Cache.Entry.locals` is keyed by ABSOLUTE def-site `(line, col)`.

## What to do

7.2.1 MEASURE FIRST, as the before-number: the cliff on Report.e through the real server (didOpen; an in-body edit;
      a blank line inserted at the top; an in-body edit after it; a line DELETED at the top; a line inserted in the
      MIDDLE — before and after some groups) — reuse count and typecheck time per step (the `phases` timers from
      7.0 are there: `-Dermine.lsp.phases=true`). Also a small file. Load < 1.3 at start.
7.2.2 THE FIX — no identity scheme, one span helper: (a) drop the start line from the group key: the key becomes the
      group's text with positions RELATIVE to the group's own start (the text is already start-anchored; what
      remains is to stop prepending the absolute line); (b) store `Entry.locals` def-sites RELATIVE to the group's
      start line (a `(Δline, col)` map, or the absolute map plus the start line it was recorded at — say which and
      why), and re-anchor at LOOKUP by adding the group's CURRENT start line, so a reused entry's positions are
      right for the buffer as it is now; (c) the head-type/`types` values carry no positions that escape (the class
      comment says note-bearing components are never cached — VERIFY that statement against `collectLocals` and
      the `LocalTy(ty, scope)` values: do any `Loc`s inside a cached `Type` reach the client? hover renders types
      without positions; but `Definitions.index`/`References` may read a `V.loc` — enumerate); (d) put the span
      arithmetic in ONE helper that 7.1b will reuse (a group's start line now vs then; Δ applied to a `Span` or a
      `(line, col)`), with a unit test.
7.2.3 THE DRIFT INVARIANT, RESTATED AND RE-ATTACKED. Stage 3 Decision (b) said: a reused entry cannot carry drifted
      positions because start lines are in the key and top-level statements start at column 1. The new invariant:
      a reused entry's positions are correct because they are RELATIVE to a group whose text is byte-identical and
      whose current start line is known. Re-run the 6.2 reviewer's five attacks (trailing whitespace; a comment
      line inside a `where`; a comment between statements; a blank line at the top; one space before a head-line
      `let` binder) against the anchored form, and ADD the line-shifting ones this item exists for: insert/delete a
      line above a group; insert a line INSIDE a group (the group text changes — the entry must MISS, not be
      re-anchored wrongly); move a whole group down past another (the ordinal changes? the key is text-only, so it
      should HIT — and its locals must land on the new lines); duplicate a group verbatim (two identical keys —
      which entry serves which, and are both positions right? this is the case text-only keys are weakest on:
      state the rule, e.g. key = text + ordinal-among-identical-texts, or accept a miss).
7.2.4 CACHE INVISIBILITY holds: warm == cold, byte-identical notes AND types AND `locals` positions, over the 5.5
      edit set (TestTolerantCheck "reuse is invisible" ×4, the 6.2 extension) EXTENDED with the line-shifting edits
      above. Every `Loc` that ESCAPES to the client is re-anchored — enumerate the escape routes and pin each in
      lsp-smoke with a fixture asserting a position AFTER a line-shifting `didChange` without a save: hover (a
      local's def-site join — 6.2's `locals` keys specifically), definition (a local binder's def-site), references
      and highlight ranges, a rename edit range, documentSymbol ranges, a codeAction edit range; plus the reuse
      COUNT after a top-of-file insertion asserted through the phases line or the check log (the acceptance
      number: 0/154 → N).
7.2.5 GATES: Tier 0 (`core/compile core/copyResources`; `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>`
      85/69/0 over 154; `repl-smoke.sh` 8 groups / 66 checks, goldens unmodified; `lsp-smoke.sh` 456 + yours; boot
      129; `.ei` 0); the seven targeted suites (`*TestTolerantCheck *TestTolerantRead *TestEditorBuffers
      *TestStage1Pins *TestReplDifferential *TestRenamer* *TestLower`); TIER 2 at adoption is the reviewer's/
      orchestrator's — you run the INTERLEAVED A/B this item's gate needs: before/after/before/after on Report.e
      with `perf-bench.sh editor -k 15` (load < 1.3), reporting the pooled Δ on the steady-state in-body edit (it
      should be ~0: this item does not speed up the common case, it removes a cliff) AND the cliff scenario before/
      after (the number that matters: typecheck 1.07 s → ~0.5 s on a top-of-file insertion). `git diff --stat` ==
      `--stat -w`; CRLF preserved; strict path untouched (`git diff -- .../session/Session.scala .../rename/
      NewPipeline.scala` empty or inert).
7.2.6 REPORT `tracker/loopmodel/LSP4-7.2-ANCHORS.md`: the before/after cliff table (reuse counts and times per
      step), the key and value design with the identity-invariant argument, the drift attacks (old five + new)
      and their results, the escape-route enumeration and pins, the A/B numbers, the diff summary, every gate
      number. Outcomes: GREEN (cliff removed: top-of-file insertion reuses ≥ the in-body count, positions right on
      every escape route) / PARTIAL (which route or attack fails, why). No silent weakening; STOP after the report —
      a reviewer re-runs the gates and the A/B once.
