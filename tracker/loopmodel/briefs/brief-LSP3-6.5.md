# Brief: LSP Stage 3, item 6.5 — completion (the consumer the scope-at-position layer has waited for since 4.2)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (6.4 is
committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs. No commits. Do not touch
`tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.5/`.
Item of record: `tracker/LSP-ROADMAP.md` § Stage 3, item **6.5**, with the STAGE-3 INVARIANTS and Decision (c); gates
`tracker/GATE-POLICY.md`. Read the 6.2-6.4 reports for what `Documents.Doc` now stores per document.

HARD RULES: completion answers from the LAST CHECK'S TABLES and the CURRENT BUFFER TEXT (for the word prefix and the
`import`/qualified context) — never a check, parse (beyond a lexical scan of the current line/word), or inference.
Batch frozen. Single-threaded dispatch. LATENCY: a completion on Layout/Report.e answers in < 50 ms server-side
(log the time on every completion); over that is a bug in this item, not a budget to negotiate. STALENESS ACCEPTED
AND STATED: a binder typed since the last debounced check is not offered until that check lands (docs/lsp.md must
say so — add the paragraph now, 6.7 will fold it in).

WHAT YOU BUILD ON: `Renamer.Result.scopeAt(line, col): Map[String, Int]` (innermost-first names visible at a
position, from `frames`; `rename/Renamer.scala` ~:75) with `binders(id).kind` for the item kind and 6.2's
`locals` for the detail type; `moduleTerms` (own top-levels) with `TolerantCheck.types` for detail; the check's
`ModuleScope.Scope` (`canonicalTerms: Map[Local, List[Name]]`, `canonicalTypes`, `termNames: Map[Name, V[Type]]`;
built in `NewPipeline.readModuleTolerant` ~:137 via `ModuleScope.importing(mh.name, ...)`) — it is the exact set of
names the file's imports put in scope, with types on the V; it is NOT kept on `Checked` today — keep it (or a
flattened `Map[String, (Global, Type)]` derived from it) per document. Module names: `env.loadedModules.keySet` of
the resident session plus the `.e` files under the checked file's module root (`Resident.checkFile` computes
`root`; `SourceFile.filesystem(root)` is the loader shape — a directory walk for `*.e` gives the candidate module
names). A module's exports for `Module.` completion: the resident env's `termNames`/`cons` filtered by
`g.module == Module` (plus an open sibling's `moduleTerms` when the module is an open buffer). Keywords:
`SurfaceParsers.keywords` (`surface/SurfaceParsers.scala` :28).

## What to do

6.5.1 CONTEXT from the buffer text at the request position (lexical only): the word prefix (identifier chars
      backwards from the cursor; operators are NOT completed — say so), and which of these applies: (A) the line
      starts with `import ` (or `export `) → module-name context, prefix = the dotted text after it; (B) the prefix
      is preceded by `Module.` where Module is Capitalised and dotted → qualified context; (C) otherwise → name
      context. Handle a cursor inside a comment or string by answering `[]` (use the surface `Lexer`'s notion if
      cheap, else a line-local heuristic and say so).
6.5.2 ITEMS, name context, PREFIX-FILTERED SERVER-SIDE (case-sensitive prefix; say whether you also offer
      case-insensitive matches lower in the ranking), each a `CompletionItem` with `label`, `kind`, `detail`
      (the type, hover-rendered), `sortText` encoding the rank: (1) locals visible at the position via `scopeAt`
      — `BinderKind` → `CompletionItemKind` (Arg/Let/Where/Do/Case → Variable 6; type-level kinds → TypeParameter
      25, offered only in type context — do you know you are in a type? if not, say so and offer them anyway or not,
      consistently); detail from 6.2 `locals` by def-site; (2) own top-levels (`moduleTerms`; detail from `types`;
      kind Function 3 / Variable 6 by arity of the type, or just Function — state it); own constructors / types /
      fields from the surface tree (6.4's symbol list is the ready-made source); (3) imported names in the file's
      scope (the kept `ModuleScope`; detail from the V's type; constructors → Constructor 4, types → Class 7, terms →
      Function 3); (4) keywords (Keyword 14) when the prefix is non-empty and matches. `sortText`: locals < own <
      imported < keywords, then alphabetical. `isIncomplete: false`.
6.5.3 ITEMS, module context (A): module names (Module 9) from the resident's `loadedModules` ∪ the `.e` files under
      the module root ∪ the open buffers' module names, prefix-matched on the dotted text (`La` → `Layout`,
      `Layout.Sc...`; `Layout.` → the `Layout.*` modules). Qualified context (B): the named module's exports
      (terms, constructors, types), prefix-filtered; an unknown module → `[]`.
6.5.4 Capability: `completionProvider: { triggerCharacters: ["."], resolveProvider: false }`. During boot: `[]`
      (an empty list, never null — the roadmap says so). No `completionItem/resolve`.
6.5.5 MEASURE the unfiltered payload ONCE (a Prelude-importing file, empty prefix): number of items and JSON bytes —
      record it — then confirm the shipped behaviour with an empty prefix in name context: either (i) locals + own
      only, or (ii) everything capped at N with `isIncomplete: true`; pick, justify, state. Per-request server time
      on Layout/Report.e at a position deep in the file: report the median of 10 (must be < 50 ms).
6.5.6 TESTS. `TestRenamer`-style property over the 180 corpus files: for every `ToBinder` occurrence of a LOCAL
      binder, `scopeAt(occurrence start)` contains its spelling mapped to its id (scope-at-position agrees with
      resolution at every real occurrence — the 4.2 note said this layer was subsumed by G1Resolution; this pins
      it directly); report the count. lsp-smoke, fixture `tracker/lsp-tests/Complete.e` (+ it imports a sibling):
      an arg offered inside its function and NOT outside; a where-bound offered in the body only; a let-bound
      inside its `in` only; an own top-level with its type in `detail`; an imported name with its type; a sibling's
      export; `import La` offers `Layout` and `Layout.*` modules; `Bool.` offers Bool's exports and not others;
      `n` offers `not` (imported) ranked after a local `n1`; a keyword; a broken file completes from its healthy
      part; a request during boot answers `[]`; a cursor inside a string answers `[]`; the staleness statement is
      exercised: didChange adding `zzz = 1`, completion for `zz` BEFORE the debounce answers without it (or with it
      if the check already ran — assert whichever the timing gives, deterministically, by requesting immediately
      after the didChange), and after diagnostics arrive it is offered. Count grows from 6.4's figure.
6.5.7 GATES (Tier 0 + targeted): compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly *TestRenamer*
      *TestTolerantCheck *TestTolerantRead *TestEditorBuffers'` green with counts; `corpus-run.sh --batch <outdir>`
      85 / 69 / 0 over 154; `repl-smoke.sh` 8 groups / 66 checks, goldens unmodified; `lsp-smoke.sh` (6.4's count +
      yours); boot 129; Report.e check time unmoved (the kept scope is on the check path — one pair, numbers).
6.5.8 REPORT `tracker/loopmodel/LSP3-6.5-COMPLETION.md`: the context rules, the item sources and ranking, the
      payload measurement and the empty-prefix decision, the per-request timing, the scope-agreement property
      count, the staleness statement as written into docs/lsp.md, the diff summary, every gate number. Outcomes
      GREEN / PARTIAL. No silent weakening; STOP after the report — a reviewer re-runs the gates once.
