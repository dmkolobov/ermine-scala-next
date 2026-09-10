# LSP Stage 3, item 6.7 — editor wiring, docs, demo, and the G3 gate evidence

Implementer report, 2026-09-10 (Opus).  Brief `tracker/loopmodel/briefs/brief-LSP3-6.7.md`; item of record
`tracker/LSP-ROADMAP.md` § Stage 3, item **6.7** and **GATE G3**, with the STAGE-3 INVARIANTS and
Decisions (c)/(d); gates `tracker/GATE-POLICY.md`.  Branch `scala3-migration`, from HEAD `3cd5300`.
No commits.  `tracker/LSP-ROADMAP.md` and `tracker/lean/` untouched.  Scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.7/`.

**OUTCOME: GREEN.**  Every GATE G3 line is satisfied or its shortfall is stated (§6a): the whole tier is
green including Tier 2 at **988/988, 0 failed, 0 errors** on ONE run, the extension is wired and its own
tests pass (after a test-harness fix, §1b), `docs/lsp.md` is rewritten with a re-measured latency table, and
the demo transcript is `tracker/lsp-tests/G3-demo.txt`.  The two things G3 asks about that are NOT clean are
both PRE-EXISTING and both now DOCUMENTED rather than absorbed: **6.2 remains PARTIAL** (62.4 % of local
binders; the residual is the roadmap's own FORK) and tickets **E8**/**E9** are user-visible defects that this
item wrote into the docs instead of fixing.

**FIX ROUND (2026-09-10, after `tracker/loopmodel/LSP3-6.7-REVIEW.md`, verdict FIX-THEN-ADVANCE).**  All ten
items of the review's §7 are applied, plus R-19; every one is PROSE in `docs/lsp.md` and
`editor/vscode/README.md`, no JVM was started (the reviewer's `core/test` was running alone on the tree), and
`git diff -- core/src` is still empty.  The changes, in the review's numbering: **R-1** the completion row was
a client round trip labelled "server side" — it now gives ≈2.2 ms server (the log line, 6.5's 2.5 ms) beside
6.5–6.9 ms round trip, and `documentSymbol` and the idle hover carry "client round trip" too; **R-2** the
117 refusals now say they cite **150 type names**, so 68/49/33 reads as name occurrences, and the scope-test
class is **31 groups (33 name occurrences)** beside the printer's 48 groups; **R-3** a GLOBAL rename
version-checks every open document, a LOCAL rename only its own file (so a `let` rename still works while
another buffer is mid-debounce); **R-4** references and highlight are correct on all the refusal cases
**except a name behind a tab**; **R-5** the equation-argument hover class now carries its three conditions
(plain variable, `arity` arrows, monotype domain) in the doc and in the README, twice; **R-6** neither
surviving cascade is a note the suppression filter can reach — the operator's three are read-phase Diags, not
notes; **R-7** a fixed sibling clears the importer only when the importer is next CHECKED, and the server does
not re-check dependents; **R-8** the third `isIncomplete: true` case (a document whose first check has not
landed) is named; **R-9** the README's two "180-file corpus" labels become the 253-file corpus and "the whole
corpus (359 `.e` files)"; **R-10** the dropped source line is ANY statement outside the run, with the fixity
declaration named as a third producer; **R-19** the latency row gives the range with the quiet run's split.
The review's R-11 (the same unit confusion in `tracker/TICKET-stdlib-findings.md` and the roadmap) is NOT
mine to edit and is left for the orchestrator; R-12–R-18 were logged as nits and not requested.

No shipped Scala changed: `git diff --name-only -- core/src` is empty.  The four edited files are
`docs/lsp.md`, `editor/vscode/README.md`, `editor/vscode/package.json` and
`editor/vscode/test/load-test.js`; the new files are `tracker/tools/lsp-demo.py`,
`tracker/tools/lsp-demo.sh`, `tracker/lsp-tests/G3-demo.txt` and this report.  The rebuilt
`editor/vscode/ermine-lang-0.1.1.vsix` replaces `ermine-lang-0.1.0.vsix` on disk; both are gitignored
(`editor/vscode/.gitignore: *.vsix`), so neither shows in `git status`.

---

## 1. VS Code (6.7.1)

### 1a. Nothing filters the server's capabilities — verified, and now asserted

`editor/vscode/src/extension.js` was read end to end.  Its `clientOptions` are
`documentSelector`, `outputChannel`, `revealOutputChannelOn` and
`initializationOptions`.  There is **no `middleware`, no `capabilities` override and no feature
list**, so `vscode-languageclient` does what it does by default: it reads the server's
`initialize` result and registers one provider per advertised capability.  Nothing was added.

That claim is now MEASURED rather than asserted.  `test/load-test.js`'s `vscode` stub records every
`languages.register*` call, and step 6 checks the nine registrations the server's capabilities imply:

```
providers registered by the client: 9 (CompletionItem, Hover, Definition, Reference,
DocumentHighlight, DocumentSymbol, WorkspaceSymbol, CodeActions, Rename)
```

plus two things that travel through the client without any client-side configuration: the
completion **trigger character `.`** reaching `registerCompletionItemProvider`'s argument list, and
the **code-action kinds `quickfix,source`** reaching `providedCodeActionKinds`.  Both are the
server's, and `package.json` declares neither — which is the point.

### 1b. A REAL FAILURE the live test found, and the fix

`npm run test:load` was **RED on the tree as it stands** before this item touched it:

```
6. LIVE: the client handshakes with the real bin/ermine-lsp
Error: Stopping the server timed out
    at .../vscode-languageclient/lib/common/client.js:983:23
```

and node died with an uncaught exception, **leaving the `bin/ermine-lsp` JVM running** (observed:
one 470 %-CPU `com.clarifi.reporting.ermine.lsp.Main`, killed by hand).  The cause, from an
instrumented re-run that traced who called `stop()`:

```
### BaseLanguageClient.stop() from LanguageClient.doInitialize (client.js:917)
channel tail: ["language client failed to start: TypeError: result.append is not a function
    at asCodeActionKind (protocolConverter.js:661)
    at asCodeActionKinds (protocolConverter.js:669)
    at CodeActionFeature.registerLanguageProvider (codeAction.js:95)
    at CodeActionFeature.initialize ... at LanguageClient.doInitialize (client.js:890)"]
```

**It is the TEST HARNESS, not the extension and not the server.**  `protocolConverter` builds a Map
from the LSP kind strings to `vscode.CodeActionKind` OBJECTS at module load and calls
`.append()` on `CodeActionKind.Empty` for any string the map misses.  The stub's generic-class
fallback answers `0` for every capitalised static, so every lookup missed and `0.append` threw.
Registering the **6.6** `codeActionProvider.codeActionKinds` is the first thing in this server's
history to take that path, which is why the test was green when it was written and red now.

FIX (`editor/vscode/test/load-test.js`, test-side only): a real `CodeActionKind` class in the stub
— `value`, `append`, `contains`, `intersects`, and the eleven named instances VS Code exposes.
With it, the whole chain runs:

```
6. LIVE: the client handshakes with the real bin/ermine-lsp
   status bar now reads: "$(symbol-namespace) Ermine"
   tooltip (the server's own words): "Ermine session ready: 129 modules in 11.9s"
   providers registered by the client: 9 (...)
...
PASS — the extension loads, activates and registers correctly
```

Recorded as a finding rather than buried: **a client-side registration failure of a NEW server
capability is invisible to `lsp-smoke.sh`** (which never runs the client library) and was visible
only here.  The added registration assertions are what make the next one fail loudly.

### 1c. The hover fence still renders

`Definitions.scala:193` sends hover as `{"kind":"markdown","value":"```ermine\n<text>\n```"}`.
`package.json` contributes language id `ermine` with grammar `source.ermine`
(`syntaxes/ermine.tmLanguage.json`), so the fence resolves to that grammar.  Checked with the
extension's own tokenizer over fourteen real hover BODIES (a scheme, a local's monotype, a kind, a
constrained type, a backticked literal name, an operator group, a record row): all fourteen
tokenize, none stalls, and none leaves the tokenizer inside a comment or string context — which is
the failure that would bleed into the rest of the popup.  Probe: `<scratch>/fence-probe.py`.

### 1d. Test results and the vsix

| what | result |
| --- | --- |
| `npm run test:grammar` | **PASS** — 36 regexes, 9 groups of rules, 359 files / 36,800 lines tokenized without stalling |
| `npm run test:load` (before the harness fix) | **FAIL** — client failed to start, `result.append is not a function`; node died and leaked the server JVM |
| `npm run test:load` (after) | **PASS** — activate in 7 ms, 9 providers registered, `session ready: 129 modules in 11.9s`, no leaked JVM |
| `npx @vscode/vsce package` | **`ermine-lang-0.1.1.vsix`**, 324 files, 479 KB — `ermine-lang-0.1.0.vsix` deleted (`*.vsix` is gitignored, so neither is tracked) |

`package.json`: `version` **0.1.0 → 0.1.1**; `description` widened from "syntax highlighting,
diagnostics, go-to-definition and hover" to the shipped set; `ermine.fastMode`'s
`markdownDescription` re-cut (it claimed "roughly halves" on stale 0.80/0.45 s figures — the
re-measured split is 0.94 read + 0.60 typecheck, so it says "about a third", and its Lost list now
names local hovers).  `configuration` and `commands` are otherwise unchanged, and no new setting was
added: everything this item touches is negotiated over the protocol.

`editor/vscode/README.md` rewritten: the feature table is the shipped set (references/highlight,
rename, outline, workspace symbols, completion, both quick fixes), with one line saying the client
serves them from the server's capabilities and this extension adds and filters nothing.  A new
"Three things that will surprise you" section carries **E9** (a stdlib target opens
`core/target/.../classes/modules`, and editing it loses the edit at the next `copyResources`),
**E8** (tab-expanded columns; rename refuses rather than corrupts) and the 6.2 residual (a `case`,
`do` or lambda binder still hovers empty).  First-run costs re-cut to the measured 12–15 s boot and
~1.9 s check, with the ~1.5 s worst-case wait during a check stated.

## 2. Eglot (6.7.2) — no change needed, and why

Verified over the scripted transcript, not over Emacs.  The snippet in `docs/lsp.md` is a
`define-derived-mode`, an `auto-mode-alist` entry and an `eglot-server-programs` entry, and **none
of the six capabilities added in Stage 3 needs a line of client-side configuration**:

- completion trigger characters are read from `completionProvider.triggerCharacters` — the demo
  transcript shows the server advertising `["."]` — and eglot installs its
  `completion-at-point-function` from the capability;
- `referencesProvider`, `documentHighlightProvider`, `renameProvider`, `documentSymbolProvider`,
  `workspaceSymbolProvider` and `codeActionProvider` are all bound by eglot itself
  (`xref-find-references`, `eglot-rename`, `imenu`, `xref-find-apropos`, `eglot-code-actions`);
- the server answers `CodeAction` literals, which eglot handles, and never the legacy `Command`
  form;
- `prepareRename` is advertised and optional either way.

The only initialization option this server has is `fastMode`, which the snippet already documents.
The docs' eglot section now says all of the above explicitly instead of leaving it implied.

## 3. `docs/lsp.md`, rewritten (6.7.3)

Rewritten whole, not appended — 405 lines → 540.  Sections, in order:

1. **Header** — the boot line, and the two rules that shape everything: *a request never starts
   work* (the Stage-3 invariant, with staleness stated where it bites) and *dispatch is
   single-threaded* (Decision 3, with the measured worst-case wait). The advertised capability list,
   and a pointer to `tracker/lsp-tests/G3-demo.txt`.
2. **Diagnostics** — all of them, not the first; 6.1(b)'s import-failure rule (each failing import
   squiggled on its own module-name span, the loader's report kept verbatim, the check continues);
   the suppression rule AND what it does not cover (E7: three read diagnostics per use of an
   operator the missing module would have supplied, and `undefined type`); the one surviving 0:0
   position (a group-level refusal; no corpus file, `shouldfail` only).
3. **Go to definition** — every declaration kind; builtins answer null; **E9 stated plainly**, with
   the path shape and the "editing what you land in loses the edit" consequence.
4. **Hover** — top level, imported, kinds on type names; then 6.2 exactly as it shipped: the three
   COMPLETE classes (`let`/`where` heads, every equation argument, signed pattern binders),
   **3156 of 5056 = 62.4 %**, and the named residual (lambda argument, `case`, `do`, a var nested in
   a constructor/tuple pattern) with the mechanism and why it answers null rather than guessing. The
   letter-agreement note in both directions: arguments share the binding's supply; a `where` helper's
   letters are independent of its enclosing binding's.
5. **Find references, document highlight** — the local key and the global key, re-export
   canonicalisation, the `import M using n` entries, alias mentions; **Decision (c)'s coverage
   warning** in its own paragraph ("the workspace is the OPEN BUFFERS … no persistent workspace
   index"); the two incomplete-without-refusal cases (operator import-list items, multi-equation
   def-site).
6. **Rename** — the "never a partial edit" guarantee, then **Decision (d)'s nine refusals as a
   list**, each with the reason a user needs; then the tab-column note (E8) once, as a property of
   every range this server produces, with rename singled out as the one request that refuses.
7. **Document symbols** — the group unit, the RANGE RULE and what a separated signature loses
   (that source line belongs to no symbol, and why the alternative is worse), the sibling-overlap
   rule, locals are not symbols, the full kind table.
8. **Workspace symbols** — the two sources, builtins and containers excluded, ranking, the 200 cap,
   the once-only session list, and the E9 path again.
9. **Completion** — the four contexts as a table (including the four module-name sources, Decision
   (c) as amended), the line-local comment/string test, the import-list gap; what a qualified item
   INSERTS and why (a dotted reference does not parse in ANY position), the alias affix form, the
   type/constructor double offer, the three `Module.` limits; ranking; **the empty-prefix decision
   with the measurement that drove it** (1332 names / 177 KB) and `isIncomplete`; type variables are
   not offered; **the staleness statement**.
10. **Quick fixes** — add import with the six-case table and the three things it does not do
    (type names, operators, a re-exporter already imported); add signature; **the sweep**: 1334
    unsigned groups, 1166 offered and re-checked, **1164 clean = 99.83 % against a 95 % bar**, the
    two "failures" being alias-unfolded but clean, the alpha-equivalence caveat (a text comparison
    first said 81 %), and the 168 refusals broken down 117/36/10/3/2 with the 33-group false
    negative named; then **staleness is REFUSED here, not accepted**, with the reason.
11. **Logging**, **Fast mode** (kept/lost, re-cut), **Latency** (below), **VS Code**, **Emacs
    (eglot)**, **Regression harness**.

Every stale number is gone: the file said 82 checks in its harness paragraph as recently as 6.1 and
now says 454; the latency table is entirely re-measured (the old `~13s` / `~1.57s` / `2 ms` rows are
replaced); `2157 names, ~40 ms` is replaced by the measured 61 ms first query.

### 3a. THE LATENCY TABLE, and how each number was taken

All on `core/src/main/resources/modules/Layout/Report.e` (1757 lines, the largest stdlib module),
JDK 21, one-minute load average **under 1.5 at the start of every run** (the machine's load comes
from the user's browser, so runs were queued behind an `until` guard).  Raw logs:
`<scratch>/m1-perf-editor.log`, `<scratch>/m2-latency.log`, `<scratch>/latency-lsp.log`.

| row | figure | how it was measured |
| --- | --- | --- |
| session boot | **12–15 s**, once, 129 modules | six independent boots this session: 11.9 / 12.2 / 13.4 / 14.0 / 14.8 / 14.9 s (the load test, the demo, the perf bench, the latency probe, `bin/ermine-lsp`) |
| keystroke → diagnostics | **≈1.7 s quiet / ≈1.9 s busy** — my run 1.859 s = 0.935 read + 0.600 typecheck + 0.300 debounce + 0.028 residual; the reviewer's quiet run **1.690–1.697 s** = 0.86 read + 0.50 typecheck + 0.30 debounce | `tracker/tools/perf-bench.sh editor -k 15`, median of rounds 2–15 (round 1 discarded as JIT warm-up), reused 97 of 154 components. Mine: spread 1.796–2.118 s, `load_before=1.34` rising to 2.22. Reviewer's: load ≈1.0. Settled by the reviewer's INTERLEAVED pair against `78d860f` — **1.759 s before / 1.694 s after** — so the gap is machine drift, not the build (R-19) |
| first check of a freshly opened file | **2.404 s** | the same run's `cold_open_s` |
| **worst-case request wait DURING a check** | **1468 ms** median (1450 / 1477 / 1468) | `<scratch>/latency.py`: a `didChange` on Report.e, then a hover sent at **+352 ms** — just past the 300 ms debounce, so the check is already on the dispatch thread — timed from send to response. The server's own log confirms it: the `>>` line for the hover is written 1.98 s after the `didChange`, i.e. the server does not even READ the request until the check is done. The answer lands **1.82 s** after the keystroke. n=3, load_before=1.20 |
| a hover on an IDLE server (the control) | **0.61 ms** median of 10 | same run — the same request costs 2,400× less when nothing is checking, which is the whole content of the parked worker-thread fork |
| completion | **≈2.2 ms server side**, **6.5–6.9 ms client round trip** | prefix `f` at line 1504, 97 items, `isIncomplete=false`. My 6.5 ms (spread 5.3–26.8, first is JIT) is the CLIENT round trip; the server's own log line for the same requests reads ≈2.2 ms warm, and 6.5 measured 2.5 ms. R-1: my first table labelled the round trip "server side", which is the one row whose label changes what a reader concludes — corrected in `docs/lsp.md` and here |
| `workspace/symbol` | **60.7 ms** first query, **1.58 ms** warm median of 10 | the first query builds the 2157-name session list (Decision 5's interface-free session, 2157 `File.isFile` stats) |
| `documentSymbol` | **32.4 ms** median of 10, CLIENT ROUND TRIP | 398 top-level symbols, 511 in all, spread 22.4–53.3 ms — the JSON round trip for the whole tree, not the build (the tree is built on the check path); the label is now in the docs table too |
| index build | **65.5 ms** cold, **13.4–23.3 ms** warm (median ≈ 16 ms) | the server's own `index: Report.e 7980 occurrences, 511 symbols in X ms` log line, eight warm samples |
| code action | **51.9 ms** first request after a check, **0.68–1.09 ms** after | memoised per document version |

Two honest notes.  (1) The keystroke→diagnostics median, 1.86 s, is above the 1.62 s the 6.2 gate
recorded — the READ half moved (0.935 s here against 0.855 s then) and this item changed nothing on
that path.  It is machine drift, which is exactly why GATE-POLICY says perf claims are interleaved
A/B pairs and never single-side figures; this row is a user-facing "what does it feel like" number,
not a regression verdict.  THE REVIEW SETTLED IT (R-19): an interleaved pair against `78d860f`
measured **1.759 s before / 1.694 s after**, and the reviewer's own single-side run at load ≈1.0 was
1.690–1.697 s.  Both docs and this table now give the honest RANGE — ≈1.7 s quiet, ≈1.9 s busy —
with the split from the quiet run.  (2) The worst-case row is the
number the PARKED worker-thread fork will be judged against, and it is **not** simply "one check":
it is one check minus the 352 ms already elapsed, which is why 1.47 s sits below the 1.86 s round
trip.

## 4. The G3 demo transcript (6.7.4)

`tracker/lsp-tests/G3-demo.txt`, 249 lines, produced by two new files:
`tracker/tools/lsp-demo.py` (the scripted client) and `tracker/tools/lsp-demo.sh` (the same server
command line `lsp-smoke.sh` builds).  Regenerate with
`tracker/tools/lsp-demo.sh > tracker/lsp-tests/G3-demo.txt`.  It is EVIDENCE, not a test —
`lsp-smoke.sh` remains the harness, and the demo asserts nothing.

Twelve steps, in order, each request echoed with its params (uris shortened to repo-relative) and
each response trimmed to what a reader needs, with the client-side timing:

1. `initialize` — the ten advertised capabilities printed one per line; then `initialized` and
   `Ermine session ready: 129 modules in 14.8s`.
2. `didOpen` the broken `Broken.e` → **2 diagnostics** on its two unparseable statements.
3. `didChange` the fix in → **0 diagnostics**, and the fixture on disk is untouched (asserted in
   the transcript).
4. `definition` on an imported name → `Good.e 2:0-2:6`; on an `import` → the module's file.
5. `hover` — `konst`'s scheme, both of its arguments (same letter supply: `k : a`, `j : b`), a
   `let` binder at its def-site and at a use, a polymorphic `where` helper (`idy : a -> a`), a type
   name's kind (`Builtin.Bool : *`), and a `case` binder answering **null** — the 6.2 residual,
   shown rather than hidden.
6. `references` on a local (4 locations, this file, no warning) and on a global (6 locations across
   two open buffers) **with Decision (c)'s `window/showMessage`** reproduced verbatim:
   `Ermine: references searched in 4 open files; unopened importers are not searched`. Then
   `documentHighlight` with its Write/Read kinds.
7. `prepareRename`, `rename` (4 edits), the edits APPLIED by the client and re-sent as a
   `didChange` → **re-checks clean**, and the renamed local hovers with the same type. Then two
   refusals for contrast — a capture and an operator — each a `ResponseError` with its message.
8. `documentSymbol` on `Decls.e` — the whole tree with ranges, selection ranges, details, and the
   constructors nested under `Shape`.
9. `workspace/symbol` ×3 — an open buffer's top level, a stdlib type in its source `.e`, and a
   builtin that is NOT listed. **The transcript states E9 in place**, because the hits it prints
   are `core/target/scala-3.3.8/classes/modules/...` paths.
10. `completion` ×5 — a local argument with its type, a prefix where the let binder outranks the
    imported `not`, module context after `import`, an empty list inside a string, and a QUALIFIED
    completion after `Maybe.` showing the whole mechanism: `filterText Maybe.isJust`, a `textEdit`
    replacing the dotted span `26:7-16` with `'isJust'`, and an `additionalTextEdit` inserting
    `import Maybe using isJust`.
11. `codeAction` — an appended `undef = not True` produces one undefined-term diagnostic, the
    request returns **two add-import candidates** (`Bool`, `Relation.Predicate`, neither preferred)
    plus the file's `source` action; the `Bool` edit is applied by the client and re-sent →
    **the diagnostic clears**. Then the other action: `add signature: answer : Int`, applied →
    **re-checks clean**.
12. `shutdown` / `exit`, exit code 0.  Total wall clock 19.1 s, of which 14.8 s is the boot.

## 5. GATES (6.7.5)

Run in the brief's order, one JVM at a time, nothing else on the machine but the user's browser.
Logs are in the scratch directory under the names given.

| gate | result | log |
| --- | --- | --- |
| `sbt -batch -J-Xmx3g core/compile core/copyResources` | **green** (no-op; the tree was already built at `3cd5300`) | `g0-compile.log` |
| `sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**, skipped 0, hashdiff 0, eqdiff 0; 3 properties, 0 failed, 0 errors. Controls fired (46 and 58 of 720 disagree under injected divergence) | `g1-looptrace.log` |
| `tracker/tools/corpus-run.sh --batch <scratch>/corpus-out` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** | `g2-corpus.log` |
| `tracker/tools/repl-smoke.sh` | **8 groups / 66 checks**, all PASS (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5). `git status tracker/repl-tests` **clean** — goldens byte-identical | `g3-repl.log` |
| `tracker/tools/lsp-smoke.sh` | **PASS, 454 checks** (the 6.6 count, unmoved) | `g4-lsp.log` |
| `tracker/tools/g1-validate.sh` | **9/9 PASS** — 7 comparator fixtures, double-run self-agreement (129 modules, 1447 signatures, EQUIVALENT), and **no drift from `tracker/g1-baseline`**. First run since the stage opened; **not red** | `g5-g1validate.log` |
| `bin/ermine-lsp` boot | **`Ermine session ready: 129 modules in 14.0s`**, clean `shutdown`/`exit`, code 0 | `g6-boot.log` |
| **Tier 2** `sbt -batch -J-Xmx3g core/test`, ALONE on the tree | **Passed: Total 988, Failed 0, Errors 0** in **25m56s** (11:13:36 → 11:39:32, `load=0.58` at the start). ONE run — it was green, so the brief's "if red, run it once more" did not apply | `g7-coretest.log` |

### 5aa. Tier 2, in detail

**`Passed: Total 988, Failed 0, Errors 0, Passed 988`**, 25 minutes 56 seconds, alone on the tree, nothing
else running.  The `[info] !`/`[info] x` count is 0.  988 against the 943 that 6.0 recorded is the Stage-3
growth: `Quick fix` 18 (new in 6.6), `Renamer 3.2a` 32 (18 at the start of the stage), `Tolerant check` 27
(14), `Tolerant read` 11, `Editor buffers` 6, and the F-stage properties.  The quarantined
`TestConstraints."disjunction sound"` is registered only under its system property and did not run, which is
the documented state.  No `/tmp/ermine-*` tree survived the run (6.0's leak fix holds).

### 5a. `.ei` hygiene

`find core/target -name '*.ei'` was **129 after `g1-validate.sh`** (its two full-inference boots are
what write them — `g1-diff.sh` publishes interfaces by design) and **0** after a scoped delete.
Every later gate was checked: the LSP boot writes **none**, because Decision 5 keeps the resident
session interface-free — the brief's expectation that "the LSP boot writes 129 into the target
module tree" does not hold on this tree, and the count after the boot gate is 0.  Final count at the
end of this item: **0**, and `tracker/lsp-tests` has no `.ei` at any point.  The delete was scoped to
`core/target` throughout; the 143 tracked `tracker/g1-*` files were never in reach (`git status
tracker/g1-baseline` clean at the end).  Tier 2 itself left **7** (`Bool`, `Function`, `Ord`, `Primitive`,
`Function/Endo`, `Control/Monoid`, `Control/Category` — the interface suites' own fixtures); those were
deleted after it, and the final count in both `core/target` and `tracker/lsp-tests` is **0**.

### 5b. Whitespace and line endings

`git diff --name-only -- core/src` is **empty**: no Scala, and no `.e`, changed.  Of the seven files
this item touches, all seven are LF at HEAD and LF now — per-file `grep -c $'\r'` is 0 before and 0
after for each, so no line ending moved.

`git diff --stat` and `git diff --stat -w` are **not equal** (645/401 against 575/331), and that is
expected here rather than a failure of the check: the three prose files were REWRITTEN, so
paragraphs are rewrapped and `-w` collapses the reflow-only hunks.  The check exists to catch a
CRLF/whitespace flip in a source file; the per-file audit above is the direct evidence that none
happened, and on the files the rule is really about — `core/src` — both forms of the diff are empty.

## 6. GATE G3 — every line, where it is checked, and the number

| GATE G3 asks for | where it is checked | number |
| --- | --- | --- |
| lsp-smoke green with the new fixtures (Locals, Refs, Decls symbols, Complete, Fix, BadImport) | `tracker/tools/lsp-smoke.sh`; the fixtures are `Locals.e`/`LocalsBroken.e`, `Refs.e`/`RefsSib.e`/`RefsPre.e`, `Decls.e`/`Syms.e`/`Scope.e`, `Complete.e`/`CompleteSib.e`/`CompleteAlias.e`, `Fix.e`/`FixSib.e`/`FixTy.e`/`FixCrlf.e`, `BadImport.e`/`BadSib.e`/`BadHeader.e`/`BadReq.e` | **PASS, 454 checks** |
| Tier 0 green | compile+copyResources / TestLoopTrace / corpus / repl-smoke / lsp-smoke, §5 | **green: 720/720, 85-69-0 of 154, 8 groups 66 checks, 454 checks** |
| Tier 2 = full `core/test` ALONE on the tree, green | `g7-coretest.log`, §5 | **988 passed, 0 failed, 0 errors**, 25m56s |
| — and deterministic after 6.0 (its three runs recorded) | 6.0's acceptance: three full runs **943/943** (1,533 / 1,463 / 1,673 s), in `tracker/loopmodel/LSP3-6.0-HYGIENE.md`. This item's run is the FOURTH on this tree and the first since 6.1–6.6 landed | **988/988 green first time**, no flake, no `Module not found: 'Test'`; the 6.0 determinism claim holds |
| REPL goldens and TestReplDifferential BYTE-UNCHANGED | `repl-smoke.sh` + `git status tracker/repl-tests` (clean); `TestReplDifferential` inside `core/test` | **goldens byte-identical** (0 files modified); `REPL eval goldens` property **green** inside the 988 |
| TestTolerantRead's 180-file agreement property green | inside `core/test` | **green** — `Tolerant read.strict and tolerant agree, and the tolerant read is silent, over the corpus`, 11 of the 988 |
| the 6.2 perf line recorded (interleaved A/B, within budget, or the item parked with its number) | recorded by 6.2 and its review, not re-run here (GATE-POLICY: perf is an interleaved A/B on adoption, never a single-side re-run) | implementer pooled **−13.5 ms** (1.621/1.679/1.706/1.621); reviewer **1.615 → 1.606**; fix round **1.631 → 1.610** — every pair inside the 5 % / 80 ms budget and below the noise floor; **locals ship ON** |
| the 6.6 sweep numbers recorded | `docs/lsp.md` § Quick fixes, and §3 above | **253 files, 1334 unsigned groups, 1166 offered, 1164 CLEAN = 99.83 %** against a 95 % bar; PARSE-FAIL 0, TYPE-FAIL 2 (both alias-unfolded and clean on re-check), SKIPPED 168 by named reason (117 / 36 / 10 / 3 / 2) |
| boot 129 | `bin/ermine-lsp` boot gate, and independently in the demo transcript, the load test and the latency probe | **129 modules**, six boots |
| no `.ei` droppings in tracker/lsp-tests | §5a | **0**, at every point |
| STOP the loop and summarize for sign-off before any Stage 4 planning | this report ends the item; the reviewer re-runs the gates once | — |

### 6a. What G3 asks for that is NOT satisfied

- **6.2 is PARTIAL, by its own letter, and stays so.**  62.4 % of the corpus's local binders (3156
  of 5056) hover with a type; the residual 1900 — lambda arguments, `case` and `do` binders, and
  variables nested inside constructor/tuple patterns — are unreachable without a four-site change on
  `Subst.scala`'s hot path, which the Stage-3 invariant stopped for the user.  It is the FORK in
  the roadmap's Blocked/Awaiting.  `docs/lsp.md` states the coverage and the residual by name, so
  the shortfall is documented rather than absorbed.
- **No shortfall in 6.6's ship bar**: 99.83 % against 95 %, GREEN, both actions, no syntactic
  filter.
- **Two tickets are visible to a user and remain open**: **E9** (stdlib navigation and workspace
  symbols land in the build output — a user who edits what they land in loses the edit) and **E8**
  (tab-expanded columns put every range on a tab-indented line seven columns per tab to the right;
  rename refuses, everything else is silently off).  Both are now stated in `docs/lsp.md` and in
  the extension README, and E9 is stated inside the demo transcript at the point where it shows.
- **E7** (the import-failure suppression rule covers term names only) and the group-level 0:0
  refusal are documented in the Diagnostics section as residuals.
- **`npm run test:load` was red on arrival** for a test-harness reason (§1b), and is green after a
  test-side fix.  No shipped code was involved either way, but it means the extension's live check
  had been failing since 6.6 landed and nothing noticed.
