# Review brief: LSP Stage 4 item 7.5 — ticket triage (E8 tab columns, E9 build-output paths, E10(5) synonyms, E7 half)

You are reviewing item 7.5 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `775f1b4`
plus the UNCOMMITTED deliverables: `lsp/{Definitions,Symbols,Diagnostics,References,QuickFix,Resident,Completion}.scala`,
`session/TolerantCheck.scala`, `scalacheck-binding/src/main/scala/{TestRenamer,TestTolerantCheck}.scala`,
`tracker/tools/lsp-client.py`, `docs/lsp.md`, `tracker/TICKET-stdlib-findings.md` (the write-backs), new fixtures
`tracker/lsp-tests/{Tab,Syn,SynSrc,BadTy,UndefTy}.e`, report `tracker/loopmodel/LSP4-7.5-TICKETS.md`). Implementer's
brief `tracker/loopmodel/briefs/brief-LSP4-7.5.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 4, 7.5 (its
DISPOSITIONS); the tickets E5-E13; `tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-7.5/` and your
report `tracker/loopmodel/LSP4-7.5-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed. ONE JVM at a time, no background JVMs, no lingering polling shells; delete every `.ei` you cause (`find`);
do not touch `tracker/lean/`; no commits. Strict path: `Session.scala`, `NewPipeline.readModule`, `Pos`, `Subst.scala`,
`Type.scala` must not be in the diff (confirm); `TolerantCheck.scala` changed (editor path) — read it.

1. **E8 — the conversion.** One bidirectional parser-column ↔ LSP-character conversion on `Lines` (`character`/
   `column`; `Definitions.toCharacter`/`toColumn`; a `LineSource` for files no buffer has open), routed through
   diagnostics (`fromDiag`/`fromSpan`/`fromReport`/the Death catch), definition/hit-test, references (highlight,
   prepareRename, rename edits), symbols, completion's scopeAt. Grep for any remaining `± 1` on a column outside the
   helper; grep for any place a `Span`/`Pos` column reaches JSON without it (codeAction edits? the demo tool?
   `lsp-demo.py`?). The UTF-16 claim: `rawSatisfy` feeds `Pos.bump` a `Char`, so a non-BMP character is 2 parser
   columns and 2 LSP characters — verify against `Pos.bump` and one probe with an astral character in a string
   literal (hover/definition on the next token). `bump` sends column 1 to 8 on a tab (not 9) — confirm and confirm
   the helper matches. Both mitigations removed (6.3's tab rename refusal; QuickFix.BehindTab): rename a name behind
   a tab now WORKS — apply it via the client and re-check. GridExample.e's six occurrences at the stated characters.
   The two round-trip properties (71,248 columns; 132 characters of the 3 tabbed lines): are they asserting
   parser→LSP→parser identity AND LSP→parser→LSP identity (both directions, as claimed)? A tab in the MIDDLE of a
   line (not leading) — covered? A line with two tabs?
2. **E9 — the mapping.** Derived from the class-loader `modules` entry: walk up to the `target` owner,
   `src/main/resources/modules` beside it, existence-checked; rewrite in `Definitions.location` only; jar fallback
   returns the target path (reasoned, not pinned — say whether a jar-only module is constructible in ANY supported
   setup, e.g. the user's older fork that the LSP-FFI detour was for). Probe: definition on `not` → a uri under
   `core/src/main/resources/modules/Bool.e`; hover target; references' def-site; workspace/symbol — none contains
   `/target/`; a module in `core/examples` (not on the classpath) unaffected; a workspace sibling unaffected. Is the
   mapping computed once (cost) and does it survive `Decision 5`'s interface-free boot unchanged?
3. **E10(5) — the synonym map.** `TolerantCheck` publishes `ownTypes` (nullary `type X = C` synonyms resolved
   through the type-def phase's maps), out via Result→Checked→DocIndex; `inScope` resolves the printed spelling
   through it with the same `chase` identity test; ONLY nullary-of-bare-Con is published — the soundness argument.
   Attack: a synonym to an APPLIED type (`type Ints = List Int`) — correctly not published, and the signature
   refused or correct?; a synonym chain (`type A = B; type B = C`); a synonym shadowing an imported name; a synonym
   defined AFTER its use in the file. Re-run the 6.6 sweep (`-Dermine.sweep.quickfix=true`): offered 1166 → 1183,
   CLEAN 1164 → 1181, PARSE-FAIL 0, TYPE-FAIL 2, out-of-scope 117 → 100, own-synonym occurrences 33 → 0 —
   reproduce; and confirm the 17 newly offered signatures actually re-check clean (they are in CLEAN, so yes — spot
   check three by hand through the client).
4. **E7 — the half.** Shipped: `Note.undefinedType` flag set where the note is built (a `catch` replacing
   `guard(Error){assertTypeClosed}`), added to Resident's suppression predicate — the wholesale 6.1(b) rule applied
   to type notes. Check the catch does not swallow anything else `assertTypeClosed` could throw; `BadTy.e` +
   `UndefTy.e` pins. Deferred operator half — the three reasons (the read Diags have no payload and tagging them
   reaches Reassoc/Lower shared with the strict read; no failed-module export list exists; 6.1 keeps syntax
   diagnostics deliberately): are they right, and is the write-back honest about what a user still sees?
5. **Write-backs**: E8/E9/E10(5) FIXED with pins named; E7 half; E5 → rides with G4 (whose GREEN line runs the
   sweep and g1-validate — but E5 is a LOADER CODE change, one line in `loadModulesInSeries`; G4 is an evidence run,
   not a code change — is "rides with G4" a category error? It should say "the first Tier-2 code commit that is due",
   or be made its own tiny item); E6, E10(1)-(3), E10(4). Does the ticket file agree with the roadmap's dispositions?
6. **Gates, re-run ONCE:** compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly *TestRenamer*
   *TestQuickFix *TestEditorBuffers *TestTolerantRead *TestTolerantCheck *TestSurfaceCache'` (122/122 + SurfaceCache);
   the 6.6 sweep; `corpus-run.sh --batch <outdir>` 85/69/0 byte-identical; `repl-smoke.sh` 8/66 goldens clean;
   `lsp-smoke.sh` 542 (list the 32 new by fixture); boot 129; `.ei` 0; Report.e round trip one pair (implementer
   0.927 → 0.908, read 0.055 both); `git diff --stat` vs `--stat -w` (implementer: identical; `--histogram` differs by
   two blank lines in docs/lsp.md only — confirm). NOT Tier 2 (no adoption; behaviour changes are the fixes of
   user-visible bugs — say whether you agree that is not "adoption" under GATE-POLICY, or run it if you judge it is;
   the G4 run will run Tier 2 regardless).
7. **The report**: accurate against your numbers? Every 7.5 acceptance line met (each taken ticket closed with its
   own lsp-smoke fixture; each deferred one written back with disposition and tier)?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), the sweep table beside
theirs, the gate table, verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why). STOP after the report.
