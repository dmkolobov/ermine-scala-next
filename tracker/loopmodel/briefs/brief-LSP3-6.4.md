# Brief: LSP Stage 3, item 6.4 — document symbols and workspace symbols

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (6.3 is
committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs. No commits. Do not touch
`tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.4/`.
Item of record: `tracker/LSP-ROADMAP.md` § Stage 3, item **6.4**, with the STAGE-3 INVARIANTS and Decision (c);
gates `tracker/GATE-POLICY.md`. Read the 6.2 and 6.3 reports (`tracker/loopmodel/LSP3-6.2-LOCALS.md`,
`LSP3-6.3-REFS.md`) for what `Resident.Checked` / `Definitions.DocIndex` now carry.

HARD RULES: requests answer from the STORED results of the last check (`Documents.Doc`: the surface `SModule`, the
`TolerantCheck` types, the index) — no check, parse or inference on a request path. Batch frozen (nothing here
touches it). Single-threaded dispatch. Decision (c): the workspace is the open buffers + the resident session's
loaded modules; no persistent index.

WHAT YOU BUILD ON: `Resident.Checked` has `module: SModule` (surface tree; statements listed in
`surface/Surface.scala` :188-244 — `SEquation`, `SSigStatement`, `SDataStatement`(+`SConDef`), `STypeAlias`,
`SClassStatement`, `SFieldStatement`, `STableStatement`, `SForeignBlock`(+`SForeign*`), `SFixity`, `SPrivateBlock`,
`SDatabaseBlock`, `SErrorStatement`) with `SLoc` spans and `SName.span` for heads; `SHeader.imports: List[SImport]`
with `moduleSpan`; `types: Map[String, Type]` (spelling -> checked type); the session env's `termNames`/`cons`
(navigation already reads their `V.loc`/`con.loc`). Keep `Checked.module` (or a derived symbol list) in
`Documents.Doc` — check what 5.3/6.3 already store and add the least.

## What to do

6.4.1 `textDocument/documentSymbol`, HIERARCHICAL (`DocumentSymbol[]`, not the flat `SymbolInformation[]`). One
      symbol per TOP-LEVEL GROUP: a spelling's signature and equations MERGE into one symbol (kind Function 12, or
      Variable 13 for a nullary equation with no args — say the rule) whose `range` spans from the first statement
      of the group to the end of the last, `selectionRange` = the head `SName.span` of the first equation (or the
      sig if no equation), `detail` = the checked type rendered as hover renders it (`Pretty.prettyType`) when
      `types` has it. `data` → Struct 23 (or Enum 10 when every constructor is nullary — say the rule) with
      constructors as children (Constructor 9; `detail` = the constructor's type from the env when the check ran);
      `type` alias → TypeParameter 26 or Class 5 (pick, state, stay consistent); `class` → Interface 11; `field` →
      Field 8 (one per name in the statement); `table` → Object 19 (one per name); `foreign` block → Module 2 named
      "foreign" with children per declaration (Function/Property/Class by kind; the class name string in `detail`);
      `import` → Module 2 (name = module, range = the import statement); fixity declarations → none (they are
      properties of the operator's symbol — put the fixity in that symbol's `detail` if cheap); `private` and
      `database` blocks → Namespace 3 with their statements as children (recursively, the same rules); an
      `SErrorStatement` → no symbol (its diagnostic is enough) — but the healthy statements around it MUST still
      list. Ranges: `Span` is 1-based half-open → LSP 0-based; a group's range must CONTAIN its selectionRange
      (the spec requires it; assert it in the test). Sort by position.
6.4.2 `workspace/symbol` (`SymbolInformation[]`): case-insensitive SUBSTRING of `query` over (a) every open
      document's own declarations (from 6.4.1's symbol list, flattened, with `containerName` = module) and (b) the
      resident session's globals that have a real file `Loc` — `env.termNames` (kind by what it is: the `V.loc`'s
      file exists → Function/Variable; constructors → Constructor if you can tell, else Function) and `env.cons`
      (Struct/Class) — `location` = the file `Loc` the definition request would answer (`Definitions.location` /
      `positionOf`, reuse them); Scala-installed builtins (`Loc.builtin`) are NOT listed. Dedupe (a) over (b) by
      (module, name). Cap at 200 results, ranked: exact match, then prefix, then substring; say the order. An empty
      query returns the open documents' symbols only (not 2000 stdlib names). Measure the cost of one query over
      the booted 129-module session (log line): it must be well under 50 ms; if the env walk is slow, build the
      stdlib name list ONCE after boot (it does not change — Decision 5, interface-free resident session) and say so.
6.4.3 Capabilities: `documentSymbolProvider`, `workspaceSymbolProvider` in `initialize`; `lsp-client.py`'s
      initialize checks assert them. Requests during boot: documentSymbol answers from the stored module if there is
      one (there is not, before the first check) else `[]`; workspaceSymbol answers `[]` (never null, never waits).
6.4.4 TESTS. `TestTolerantRead`-style property over the 180 corpus files: the symbol list is built (no exception)
      for every file, every symbol's `range` contains its `selectionRange`, children are inside their parent,
      names are non-empty, and the count of Function/Variable symbols equals the number of distinct top-level term
      groups the renamer's `moduleTerms` knows (the cross-check that groups merge correctly) — report the totals.
      lsp-smoke: `Decls.e`'s full symbol tree PINNED (names, kinds, ranges, nesting — as an exact expected structure
      in the client script, so a change in any of them is visible); a broken file (`Broken.e`) lists its healthy
      symbols and no symbol for the broken statements; `workspace/symbol "twice"` finds `Nav.twice` at its
      Location; `"Relation"` finds the stdlib TYPE in its SOURCE `.e` file (Decision 5 makes this true; assert the
      uri ends in `Relation.e` under the modules tree); `"just"` (lower-case query) finds constructors named `Just`
      only if they have source — the builtin `Just` is NOT in the list (assert absence); the empty query lists only
      open-document symbols; a query during boot answers `[]`. Count grows from 6.3's figure.
6.4.5 GATES (Tier 0 + targeted): `sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'`
      720/720; `sbt 'core/testOnly *TestTolerantRead *TestTolerantCheck *TestEditorBuffers'` green with counts;
      `tracker/tools/corpus-run.sh --batch <scratch outdir>` 85 / 69 / 0 over 154; `tracker/tools/repl-smoke.sh`
      8 groups / 66 checks, goldens unmodified; `tracker/tools/lsp-smoke.sh` (6.3's count + yours); boot 129. Report.e
      check time before/after from the log (a symbol list built on the check path must not move it beyond the
      floor; if you build it lazily on first request instead, say so and measure THAT).
6.4.6 REPORT `tracker/loopmodel/LSP3-6.4-SYMBOLS.md`: the kind mapping table (statement → SymbolKind, with the
      rules), the workspace-symbol source/ranking/cost, the corpus property totals, the pinned Decls.e tree, the
      diff summary, every gate number. Outcomes GREEN / PARTIAL. No silent weakening; STOP after the report — a
      reviewer re-runs the gates once.
