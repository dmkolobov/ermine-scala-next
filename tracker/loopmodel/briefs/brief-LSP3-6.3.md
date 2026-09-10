# Brief: LSP Stage 3, item 6.3 — references, document highlight, rename (from the renamer tables; no new analysis)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (6.2 is
committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs. No commits. Do not touch
`tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.3/`.
Item of record: `tracker/LSP-ROADMAP.md` § Stage 3, item **6.3**, with the STAGE-3 INVARIANTS and Stage-3 Decisions
(c) and (d) — read them first; gates `tracker/GATE-POLICY.md`; the fixture rule at the top of `TestErmine.scala`.
Read the 6.2 report `tracker/loopmodel/LSP3-6.2-LOCALS.md` for what the index now carries.

WHAT YOU BUILD ON (verify by reading; line numbers approximate): `Renamer.Result` (`rename/Renamer.scala` ~:61) —
`occurrences: List[Occurrence(span, spelling, resolution, typeLevel)]` with `ToBinder(id)` / `ToGlobal(g, importedAs,
origin)` / `Unresolved` / `Ambiguous`; `binders: Map[Int, BinderInfo(id, spelling, defSite: Span, kind)]`;
`frames: List[Frame(span, bindings: Map[String, Int])]`; `moduleTerms: Map[String, Int]`. `Span` is half-open,
1-based (`surface/Surface.scala` :22). `Definitions.index` (`lsp/Definitions.scala`) flattens occurrences to
`Occ(line, startCol, len, target, hover)` per document, stored in `Documents.Doc.index`; `Definitions.hit` is the
position hit-test. `Resident.Checked` carries `renamed: Renamer.Result` and `name` (module). Every open document has
a `Doc(uri, path, text, version, index, cache)` in `Documents` (`docs.valuesIterator` is private today — add an
accessor). A binder's def-site is NOT itself an occurrence for locals (check `occur` call sites — equation heads
ARE occurrences of their own binder per the 4.3 notes; local binder def-sites may not be): the references set must
include the def-site from `BinderInfo.defSite` explicitly when `includeDeclaration`.

HARD RULES: every request answers from the STORED index and renamer tables of the last check — no check, no parse,
no inference on a request path (Stage-3 invariant). Batch frozen (nothing here touches it; say so). Dispatch stays
single-threaded. The index must keep enough to answer these requests: extend `Occ`/`DocIndex` (e.g. keep the
`Resolution` key — binder id or origin Global — and the binder kind per Occ) rather than re-deriving from text.

## What to do

6.3.1 INDEX. Extend `Definitions.Occ` with a stable key: `Local(binderId)` | `GlobalKey(origin: Global, typeLevel)`
      | none, plus whether this Occ IS the def-site (write) or a use (read). Add def-site Occs for every local
      binder (from `binders`) so highlight/rename can hit them; make sure `hit` still prefers the same Occ it did
      before at every position lsp-smoke already checks (205+ checks are the tripwire). Keep `DocIndex` cheap to
      build: measure `Definitions.index` time on Layout/Report.e before/after (log line) — it is on the check path.
6.3.2 `textDocument/references` (with `context.includeDeclaration`) and `textDocument/documentHighlight` (kind 3
      Write at the def-site, 2 Read at uses). Local key: every Occ in THIS document with the same binder id (+ the
      def-site when asked). Global key: every Occ in EVERY OPEN document whose `GlobalKey.origin` matches (origin,
      not `g`: an alias-imported name and its canonical name are the same thing), plus the def-site — which for an
      own top-level is `binders(moduleTerms(spelling)).defSite` in the defining document and for an imported name is
      the `Target` the definition request answers (the session's V loc; it may be a file that is NOT open — include
      it as a Location anyway, it is a real position). DECISION (c) COVERAGE WARNING: whenever the key is global and
      some importer might not be open — i.e. always for globals unless every module that imports the defining
      module is an open buffer (you cannot know that; so: always for globals, worded "references searched in N open
      files; unopened importers are not searched") — send `window/showMessage` type 2 ONCE per request. Locals get
      no warning. Highlight is per-document only, no warning.
6.3.3 `textDocument/prepareRename` and `textDocument/rename` (Decision d). prepareRename answers the Occ's range and
      placeholder spelling, or null when the position is not on a renameable Occ. rename produces ONE
      `WorkspaceEdit` with `changes: { uri -> [TextEdit] }` over exactly the references set (def-site included),
      only for OPEN documents; if the def-site is in a non-open file (a stdlib name), REFUSE with a ResponseError
      (code -32803 RequestFailed or InvalidParams; say which and why) "cannot rename a name defined in a file that
      is not open" — never a partial edit. REFUSALS, each a ResponseError with a message the user can read:
      (i) new name not a valid Ermine identifier of the SAME CASE CLASS (term/binder stays lower-initial,
      constructor/type stays upper-initial; use the surface `Lexer`'s classification, not a regex of your own);
      (ii) old or new spelling is an operator (`Lexer.isOpChar` head) — refused both ways; (iii) CAPTURE: the new
      name is already bound in any renamer `Frame` that contains any occurrence in the set (shadowing the renamed
      binder or being shadowed by it), or resolves to a global in the file's scope (`moduleTerms` or the check
      env's `termNames` by canonical import scope — use what the index/Checked already has; do not re-run the
      renamer) at any occurrence; (iv) STALE INDEX: the document's `version` differs from the version the index
      was built from (record the version in `DocIndex` at index time) for ANY document in the edit — "check
      pending; retry after diagnostics update". Also refuse when any occurrence in the set is `Ambiguous`.
      For a global rename across open documents the edit touches: the def-site, every use in every open document,
      AND any `import M (name)` explicit-list mention and fixity-declaration mention of that name (they are Occs
      already if 4.3/post-G2 made them so — check; if not, add them to the index in 6.3.1, else state the gap).
      Send the coverage warning here too.
6.3.4 Capabilities: advertise `referencesProvider`, `documentHighlightProvider`, `renameProvider: { prepareProvider:
      true }` in `initialize`; `lsp-client.py`'s initialize checks assert them.
6.3.5 TESTS. `TestRenamer` (or a new `TestRenamerTables`): table-integrity properties over the 180 corpus files —
      every `ToBinder` occurrence's binder exists and its `defSite` is inside the file; no two occurrence spans
      overlap; def-sites are unique per binder id; every `moduleTerms` id is a `TopLevel` binder. These are what
      references/rename stand on; report counts. lsp-smoke, fixtures `tracker/lsp-tests/Refs.e` + `RefsSib.e`
      (importing Refs.e): references on a local (def + 3 uses, exact ranges, with and without includeDeclaration);
      references on a Refs.e top-level from RefsSib.e (both files, both counts) and the coverage warning arrives
      (assert the showMessage); highlight kinds (one Write, N Read); rename a local → edits at every site and none
      elsewhere, then APPLY the edits in the client and didChange the result: the file re-checks clean and the
      renamed local hovers with the same type; rename to a capturing name → ResponseError; rename to/from an
      operator → ResponseError; rename to a wrong-case name → ResponseError; rename with a stale index (didChange,
      then rename before the debounce fires) → "check pending" ResponseError; rename a top-level across two open
      buffers → edits in both plus the warning; rename of a stdlib name → refused; prepareRename off a name → null.
      Count grows from the 6.2 figure; report the number.
6.3.6 GATES (Tier 0 + targeted): `sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'`
      720/720; `sbt 'core/testOnly *TestRenamer* *TestTolerantCheck *TestEditorBuffers'` green with counts;
      `tracker/tools/corpus-run.sh --batch <scratch outdir>` 85 / 69 / 0 over 154; `tracker/tools/repl-smoke.sh`
      8 groups / 66 checks, goldens unmodified; `tracker/tools/lsp-smoke.sh` (6.2's count + yours); boot 129.
      Report.e check time before/after from the LSP log (the index build is on the check path — it must not move
      the round trip beyond the ~50 ms floor; one pair is enough, say the numbers).
6.3.7 REPORT `tracker/loopmodel/LSP3-6.3-REFS.md`: the index extension and its cost; the references/highlight
      semantics (what "the set" is for each key kind); every rename refusal and how it is detected; the coverage
      warning wording; gaps stated (e.g. import-list mentions not indexed); table-integrity counts; the diff
      summary; every gate number. Outcomes GREEN / PARTIAL (which, why). No silent weakening; STOP after the report
      — a reviewer re-runs the gates once.
