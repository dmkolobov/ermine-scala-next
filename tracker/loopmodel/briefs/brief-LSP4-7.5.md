# Brief: LSP Stage 4, item 7.5 — ticket triage: take E8, E9, E10(5), E7 if cheap; write back the dispositions of E5, E6, E10(1)-(3)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`; after edits under `parsers/` or to `SurfaceParsers.scala`, `sbt core/clean core/compile
core/copyResources` — the E046 quirk). ONE JVM at a time, no background JVMs, no lingering polling shells when you
stop. No commits. Do not touch `tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause (`find`).
Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.5/`.
Item of record: `tracker/LSP-ROADMAP.md` § "Stage 4", item **7.5** (its DISPOSITIONS are the plan; the STAGE-4
INVARIANTS apply — batch frozen, no request-path work); the tickets in `tracker/TICKET-stdlib-findings.md`: E7 (:550),
E8 (:565), E9 (:578), E10 (:592), E5, E6; `tracker/GATE-POLICY.md`. The Stage-3 reports these tickets came from:
`tracker/loopmodel/LSP3-6.3-REFS.md` §12 (E8: `Lines.locate`, `nameExtent`'s tab class, the `±1` conversions), the
6.3 review S5 (E8's scope: diagnostics, location, hit/siteAt, the UTF-16 rule), `LSP3-6.4-SYMBOLS.md` §7d (E9),
`LSP3-6.1-DIAGNOSTICS.md` and its review R2/R3 (E7), `LSP3-6.6-QUICKFIX.md` §7 item (5) and its review R-1 (E10(5):
`inScope` cannot see through the file's own type synonyms — 33 name occurrences / 31 groups; the alias-to-Con map
`TolerantCheck` builds and discards).

## What to do — in this order; each taken ticket is its own commit-sized unit inside the item
7.5.1 **E8 — TAKE: one bidirectional parser-column ↔ LSP-character conversion at the LSP boundary.** Parser columns
      are TAB-EXPANDED to 8-column stops (`Pos.bump`); LSP positions count UTF-16 code units. Today the server converts
      by `±1` in BOTH directions across the whole model: `Diagnostics` ranges, `Definitions.location` targets,
      `hit`/`siteAt` hit-tests, highlight/rename ranges, symbols, code-action edits, completion's word scan. Build ONE
      helper (extend the `Lines` that 6.3 wrote) that maps parser (line, column) → LSP (line, character) and back,
      given the line's text — tabs to 8-stops in one direction, un-expanded in the other; the same helper also
      handles the UTF-16 rule (a non-BMP character is one parser column and two LSP characters — say whether Ermine
      source can contain one; if `Pos.bump` counts chars, the rule is the same class of bug). Route EVERY range and
      every incoming position through it — enumerate the sites (the 6.3 review listed them) and grep for any
      remaining `- 1`/`+ 1` on a column. NOT the `Pos` fix (Tier 2 + goldens). PIN: `core/examples/GridExample.e`
      (tab-indented, 6 occurrences) in lsp-smoke — hover/definition at the REAL character column hits; a diagnostic
      on a tabbed line squiggles the text, not 7 columns right; rename of a name behind a tab now WORKS (6.3 refused
      it — remove that refusal and its pin, or keep the refusal only for names whose extent is not exact for another
      reason; say which); the 6.3 extent classification's "6 behind a tab" class becomes exact (re-run that property
      and report the new histogram). Also a corpus property: for every occurrence, round-trip parser→LSP→parser is
      the identity.
7.5.2 **E9 — TAKE: stdlib locations point at the SOURCE tree.** The resident session loads the 129 modules from the
      classpath copy (`core/target/scala-3.3.8/classes/modules/*.e`), so `V.loc`/`Con.loc` carry that path and
      `Definitions.location`/`workspace/symbol` send it. Map the target module tree back to
      `core/src/main/resources/modules` at the LSP boundary — one place (`Definitions.location`, and wherever
      `workspace/symbol` builds its Location), given the mapping (derive it: the classpath entry that contains
      `modules/` ↔ the resources directory; do NOT hard-code the scala version; if the source file does not exist —
      a module that lives only in a jar — fall back to the target path and say so). Decision 5 unchanged (the session
      still boots from the classpath). PIN: the existing `endswith("/Bool.e")` pins cannot see the bug — make the
      stdlib-target pins assert the path is under `core/src/main/resources/modules` (absolute or `resources`-anchored)
      for definition, hover-target-if-any, references' def-site, and workspace/symbol; add the jar-fallback case if
      constructible. Also `docs/lsp.md`: remove the E9 caveat.
7.5.3 **E10(5) — TAKE if it fits: the quick fix's scope test sees through the file's OWN type synonyms.**
      `QuickFix`'s `inScope`/`OutOfScope` test refused 33 name occurrences (31 groups, 29 of them `Scan` in
      `Layout/Scan.e` via `type Scan = Scan_S`) that the file CAN write. Keep the alias-to-Con map `TolerantCheck`
      builds (a `Checked`/`DocIndex` field) and resolve the printer's spelling through it before refusing. PIN: the
      6.6 sweep (`-Dermine.sweep.quickfix=true`) — re-run and report the table: OutOfScope 117 → ≤ 84, CLEAN
      insertions up by the recovered groups, still 0 PARSE-FAIL; an lsp-smoke fixture with a synonym-typed unsigned
      binding now offered a signature that re-checks clean.
7.5.4 **E7 — TAKE IF CHEAP, else state and defer.** The import-failure suppression withholds undefined-TERM and
      "unchecked" notes while an import failed, but an operator the failed module would supply still cascades three
      READ diagnostics per use (`unknown operator` / `ill-formed expression` / `error node`) and a type name one
      `undefined type` note. The hard part is POLICY: the same three diagnostics are right for a genuinely mistyped
      operator. Spend at most a quarter of the item: is there a flag-based tag (the read diagnostics for an operator
      whose spelling appears in a failed module's known exports — the resident session knows the module's origin
      names when the module exists but failed to load; it knows nothing when the module does not exist) that
      distinguishes the two cases honestly? If yes for the "module exists but failed" half, ship it with a fixture;
      if not, write the reason into the ticket and defer.
7.5.5 **WRITE BACK the dispositions** into `tracker/TICKET-stdlib-findings.md` in the same round: E8/E9/E10(5)
      "FIXED in <this item>" with the pin named; E7 fixed-or-deferred with the reason; E5 "not this stage — rides
      with the next Tier-2 commit that is due anyway (say which item that is)"; E6 "not this stage — Tier 2 +
      goldens, its own item"; E10(1)-(3) "not this stage — Tier 1, the interface sweep and a re-cut g1-baseline".
7.5.6 GATES: Tier 0 (`core/compile core/copyResources`; `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>`
      85/69/0 over 154; `repl-smoke.sh` 8/66 goldens unmodified; `lsp-smoke.sh` at the current count + yours; boot 129;
      `.ei` 0 by `find`); the targeted suites (`*TestRenamer* *TestTolerantCheck *TestQuickFix *TestEditorBuffers
      *TestTolerantRead`); the 6.6 sweep for E10(5); strict path untouched (`Session.scala`, `NewPipeline.readModule`,
      `Pos`); `git diff --stat` == `--stat -w --histogram`; line endings preserved. Report.e round trip one pair (the
      column helper is on the check path for diagnostics ranges — it must not move the round trip beyond the floor).
7.5.7 REPORT `tracker/loopmodel/LSP4-7.5-TICKETS.md`: per ticket — the change, the pin, the number (E8's new extent
      histogram; E9's path assertions; E10(5)'s sweep table before/after; E7's decision and reason); the write-back
      diff; every gate number. Outcomes: GREEN (E8, E9, E10(5) closed; E7 decided) / PARTIAL (which). No silent
      weakening; STOP after the report — a reviewer re-runs the gates once.
