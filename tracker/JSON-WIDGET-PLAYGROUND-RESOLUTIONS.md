# Resolutions for the open problems in `JSON-WIDGET-PLAYGROUND.md`

> **STATUS: PROPOSALS.** Nothing here has been built. Options and one recommendation per problem,
> for the user to adopt or reject. Every `file:line` was opened on branch `json-encode` at
> `a0830244` while writing this. Third-party facts are tagged *external* and were **not verified**
> against the tool's source; the bracketed tag on each recommendation names the prior art it copies
> or says `[first principles]`. Group A is the second review's unresolved findings
> (`JSON-WIDGET-PLAYGROUND-REVIEW-2.md`); Group B is what reading the design turned up. Settled
> decisions (the second session, the preview thread, webpack, SQL auth) are not reopened.

Legend for the "lands in" column: an existing WP ticket, or **NEW** with the proposed number.
Ordering changes are collected in §C at the end.

---

## Group A — carried over from the second review

### A1. The unsaved-buffer hole (CRITICAL)

**Problem.** The editor's tolerant check registers `data` shapes from open buffers on every debounced
keystroke (`TolerantCheck.scala:862` → `Session.processTypeDefComponent` → `DataConDecl.register`,
`Session.scala:915`); the render session holds the saved shape; `Encode.userData` (`Encode.scala:400`)
reads the process-wide registry, so a field-count mismatch encodes props silently wrong
(`Encode.scala:413` guard), and no invalidation fires.

| Option | Shape of the change | Cost | Consequence |
|---|---|---|---|
| (a) per-session constructor index | `SessionEnv` gains `var decls: Map[Global, DataConDecl]` (beside `cons`, `SessionState.scala:99`; carried by `copy` `:113` and `+=` `:149-158`); `processTypeDefComponent` writes it (`Session.scala:915`); `Lib.json` (`Lib.scala:1443`, has `s: SessionEnv` implicit) installs `toJson#` as `Fun(v => Encode.toErmine(v, s.decls))` (`:1478`); `Encode.encode`/`toArgonaut`/`toErmine`/`render` (`Encode.scala:134-186`) and `userData` (`:400`) take the index; the lifted scrub (WP-2) drops a module's entries | ~1 day: a parameter threaded through the encoder every JSON test pins (`TestJson`, `TestSchema`, `TestNamedFields`); the `evalLock` registry rationale (`Runner.scala:614-619`) shrinks to Supply + Thunk | the right long-term shape; the static registry becomes test-only |
| (b) no-register flag on check copies | `SessionEnv` gains `_registerDecls: Option[Boolean]` (default on), carried by `copy` (`SessionState.scala:113`); `Session.scala:915` becomes `if (se.registerDecls) DataConDecl.register(decl, names) else decl`; `Resident.withEnv` (`Resident.scala:143`, the one place every check copy is made) sets it off on the copy, which `SessionTask.fork` inherits (`SessionTask.scala:27` uses `s.copy`) | ~10 lines + one property | the check copy's own readers are unaffected: the `Con` carries its decl (`Session.scala:923`) and Schema/Decode read the `Con` first (`Schema.scala:240`, `:319`; `Decode.scala:232`, `:402`); checks never evaluate, so `toJson#` never runs on a copy. Remaining writers: the resident's boot/reload (disk, `Resident.scala:126-127`), the render session's boot/`compile` (disk, `Runner.scala:315`), and both preambles (`Lib.scala:45`, `:1472`) — all disk content, ids irrelevant (review-2 confirmed). The residual window is exactly §2.2's stated one, closed by `invalidate`/`stale` |
| (c) refuse to render while a loaded `.e` buffer is dirty | extension: `workspace.textDocuments.some(d => d.isDirty && d.languageId === "ermine")` (*external*); or server: mark on `didChange` (`Diagnostics.scala:180`), clear on `didSave` (`:197`) | ~20 lines | **does not close the hole**: a buffer closed without saving (`didClose`, `:205`) leaves the buffer's shape registered and nothing is dirty any more; a checked *sibling* buffer is registered too. How often it blocks: every render triggered from a non-`.e` file (params save, bundle rebuild, reconnect) while any `.e` in the closure is mid-edit — in the two-file loop (widget module + its renderer) that is a normal state, so it would block often and explain nothing |

**Prior art.** Save-driven reload is the norm and none of them refuses to reload because another
file is dirty: Vite HMR and Flutter hot reload fire on save (*external*); VS Code's Markdown preview
renders the buffer, the opposite choice, which is unavailable here because the render session reads
files (`Runner.scala:315`). No tool has an analogue of the registry itself.

**RECOMMEND.** Adopt **(b)** now, as **NEW WP-2b** between WP-2 and WP-3: `_registerDecls` on
`SessionEnv`, off on every `withEnv` copy; property in group D: check a buffer whose `data Heading`
gained a field, then `DataConDecl.forConstructor(Global("Sales","Heading"))` still has four fields.
Record (a) as the follow-up that becomes mandatory the day a second registry *reader* appears.
Drop (c). Add a non-blocking hint in the panel banner, "unsaved: Chart.e", from `isDirty` (5 lines,
WP-7), because "the preview follows saves" (§2.4) must be visible, not documented. Rewrite §2.2 row 1:
writers are the two sessions' disk loads plus `TolerantCheck.scala:862` (silenced by WP-2b); replace
"equal-content" with "disk-content". `[after save-driven HMR; the registry fix is first principles]`

### A2. `untrustedWorkspaces: "limited"` is a regression

**Problem.** Declaring `limited` activates the extension in Restricted Mode; the server path is derived
from the first workspace folder (`extension.js:52-54`) and spawned with `cwd: server.root` (`:148-151`),
so an untrusted repo's own `bin/ermine-lsp` would run. Today (no declaration, `package.json` has none)
the extension is not activated there at all.

| Option | Change | Consequence |
|---|---|---|
| (i) keep the declaration absent | delete the WP-11 item; a comment in `package.json` saying why | Restricted Mode: no activation, no server, no preview; the TextMate grammar is a static contribution and keeps working (*external*). Nothing the extension offers works without the server, so `limited` would buy nothing |
| (ii) `limited` + trust gate | `startClient` (`extension.js:126`) begins `if (!vscode.workspace.isTrusted) { setStatus("Ermine: restricted", ...); context.subscriptions.push(vscode.workspace.onDidGrantWorkspaceTrust(() => startClient(context))); return; }` (*external* API) | correct, but it re-implements what non-activation already gives, and `restrictedConfigurations` still cannot cover a folder-derived path |
| (iii) `limited` + honour only user-scope `ermine.serverPath` and never the folder fallback in Restricted Mode | as (ii) plus an `inspect().globalValue` read | most code for the least value |

**Prior art.** VS Code's guide: `restrictedConfigurations` makes VS Code ignore the *workspace value*
of a setting in Restricted Mode (*external*); ESLint's `eslint.nodePath`/`eslint.runtime` are handled
that way and the extension once demanded explicit confirmation before executing a workspace-local
eslint (*external*). Both patterns protect a *setting*; ours is a *path derived from the folder*,
which no declaration reaches.

**RECOMMEND.** **(i)**: no `untrustedWorkspaces` declaration; §8.2 T3 says "the extension is not
activated in Restricted Mode, so no server and no preview run; a trusted workspace is the user's trust
decision". Delete the declaration from WP-11's list and done-when. Add (ii)'s four-line guard only if
someone later declares `limited` for another reason. `[after VS Code's own guidance; reject ESLint's
restricted-setting pattern as inapplicable to a folder-derived path]`

### A3. The schema binding mode is routed to the session that cannot see the report

**Problem.** `LspSchema.answer` runs on a resident copy (`Schema.scala:807-810`, `withEnv` +
`Session.loadModules(List(m))`) whose loader chain is `moduleRoots` + classpath (`Resident.scala:126-127`);
preview roots exist only in the render session, so `Sales` is module-not-found and WP-9's acceptance
test fails as designed.

| Option | Change | Consequence |
|---|---|---|
| (i) answer from the render session | `Runner` gains `def paramSchema(module, binding): Either[RunError, Json]` = `report(module, binding)` (`Runner.scala:411-420`, cached, under `evalLock`) then `Schema.exportType(rep.paramTy, module)(env)` (`Schema.scala:184` takes the implicit `SessionEnv`; `Report.paramTy` is `:598`). The LSP routes `ermine/schema` **with a `binding` key** to the preview queue through WP-1's deferred answer; the `type`/`name` forms stay on the resident | the schema is exported from the *same* `paramTy` the decoder was compiled from (`:472-476`), so the params schema and the 400s can never disagree; it queues behind renders like every preview job |
| (ii) append `previewRoots` to the resident's chain | `Main.scala:117` + `Resident.scala:126` | workspace report modules enter the resident (what `LSP-STALENESS.md:40` rejects) and the binding is *evaluated* on the dispatch thread, which §2.3 exists to prevent |
| (iii) extension derives the schema from the picked file's text | — | no: the params type may be an alias from another module (§6) |

**RECOMMEND.** **(i)**. Lands in WP-3 (the `Runner` accessor, one property: `paramSchema("Sales",
"report")` equals `exportNamed("Sales","Query")` under the same env) and WP-4 (the routing rule
"`ermine/schema` with `binding` is a preview job"). WP-9's done-when is unchanged and now reachable.
`[first principles: answer from the session that compiled it; rust-analyzer likewise answers from the
analysis host that owns the data, *external*]`

### A4. No maximum heap; the restart is undersold

**Problem.** Nothing sets `-Xmx` (`bin/ermine-lsp:18-31`; the extension only sets `ERMINE_LSP_LOG`,
`extension.js:144-146`), so an allocating runaway evaluation on the preview thread takes the whole
process into GC storms or OOM; "the resident keeps working" holds for CPU only. Restart (`ermine.restartServer`,
`extension.js:241`) is a fresh process: the ~13 s boot (`Resident.scala:24`), every per-document inference
cache (cold first check ~2.5 s, `editor/vscode/README.md:117`), the symbol table, the held connection and
its `##` tables, the compiled report.

| Option | Change | Cost | Consequence |
|---|---|---|---|
| (i) cap the heap and make OOM a crash | `bin/ermine-lsp:18-20`: `opts+=( -Xmx"${ERMINE_LSP_XMX:-2g}" -XX:+ExitOnOutOfMemoryError )` unless `ERMINE_JAVA_OPTS` already names `-Xmx`; a setting `ermine.maxHeap` (default `"2g"`) the extension exports as `ERMINE_LSP_XMX` beside `ERMINE_LSP_LOG` (`extension.js:145-146`); a change restarts the server like `serverPath` does (`:275-280`) | 6 lines | an OOM becomes a clean exit; `vscode-languageclient` restarts a crashed server automatically, up to 5 times in 3 minutes (*external*, the well-known cpptools message); the panel recovers per B12. `-XX:+ExitOnOutOfMemoryError` exists since JDK 8u92 (*external*). Today's zombie-under-OOM becomes a crash-and-restart for the resident too — a behaviour change to state |
| (ii) cooperative cancellation in the evaluator | a `@volatile var cancel: Boolean` on a per-thread `Eval` context checked at the head of `Runtime.swhnf` (`Runtime.scala:215`): `if (cancelled) throw Cancelled`. The watchdog sets it instead of only answering; `$/cancelRequest` on the in-flight render sets it too. The unwinding thunk writes `Bottom` back into the thunks on its chain (`:231`, `:238` writeback), which poisons the render session's stdlib thunks — so a cancel **discards the `Runner`** (next render boots a new one, unmeasured seconds) and the runaway's thunk chains become garbage. The resident is untouched | the evaluator's hot loop gains one volatile read per force: a Tier-2 instrument run (`perf-bench.sh`, an interleaved A/B, which "has never moved", `docs/gate-policy.md:105`) before adoption; **unverified** that every Ermine loop passes through `swhnf` (a loop inside one primitive would not) | the watchdog and cancel become real for CPU *and* heap; restart of the whole server becomes rare |
| (iii) a separate render process | — | reopens the settled "second session in one process" decision | not argued here |

**Prior art.** Jupyter: *interrupt* (SIGINT → `KeyboardInterrupt` at the next bytecode boundary, state
kept) is distinct from *restart* (state lost), and the UI marks a dead or busy kernel (*external*).
(ii) is that split: cancel = interrupt of the preview "kernel" (its session is discarded, the editor's
resident survives); Restart Language Server = restart. rust-analyzer's queries unwind on a `Cancelled`
check inside the analysis loop, the same cooperative shape (*external*).

**RECOMMEND.** **(i) now** in WP-4 (the launcher and the `ermine.maxHeap` setting; **the figure is the
user's call**, advice `2g`: the resident plus one render session, on an 8 GB laptop with two windows =
4 GB). **(ii) as NEW WP-4b**, after WP-4, gated on the perf instrument; until it lands, §2.5's promise
reads "a runaway evaluation blocks no LSP request until it exhausts the heap cap, then the server exits
and the client restarts it; the watchdog tells the user at 60 s rather than at OOM", the watchdog
notification carries the **Restart Language Server** button, and §2.5 states the restart cost from the
list above. WP-4's done-when gains: heap after a watchdog fire MEASURED for an allocating and a
non-allocating loop. `[after Jupyter interrupt-vs-restart; (i) is first principles]`

### A5. The URL can still reach a log or a client

**Problem.** `DriverManager.getConnection` throws "No suitable driver found for <url>" (*external*,
JDK) which classifies `connect`, is answered, and is logged by `Wire.send` (`Rpc.scala:345`); a
`LinkageError` from a handler falls through `Server.request` (`:478-480`) into the log and the answer;
nothing forbids `password=`/`pwd=` inside the URL string.

| Option | Change | Consequence |
|---|---|---|
| (i) scrub at the source | the connect handler catches `Throwable` (not `NonFatal`), never rethrows, and builds every message as `e.getClass.getSimpleName + ": " + scrub(msg)` where `scrub` replaces the profile's `url`, `user`, and the URL's host with `<url>`/`<user>`/`<host>`; classification uses `getSQLState`/`getErrorCode` only (the shape `SqlScanner.scala:190` already renders) | `Server.request`'s crash path is unreachable for `connect`; `<<` logging (`Rpc.scala:345`) needs no redaction because nothing secret is ever in the answer |
| (ii) refuse credentials inside the URL | extension: before `connect`, `/(^|[;?&])\s*(password|pwd|user|userName|integratedSecurity|authentication)\s*=/i` (*external*: mssql-jdbc property names) refuses with "credentials belong in `user` and the prompt" | closes the Settings-Sync leak (T2) at the only place the URL enters |
| (iii) redact the `<<` line for connect answers | track request id → method in `Server` | unnecessary once (i) holds; adds state to `Rpc.scala` |

Also: "No suitable driver found" means the URL prefix matched no registered driver — a configuration
error, not a network one; classify it **`driver`**, secret kept, no prompt.

**RECOMMEND.** **(i) + (ii)**, both in WP-11; the fake-driver test gains "a message containing the
URL is answered with `<url>` and the log has 0 hits for the URL and the host"; §8.4 gains that row.
vscode-mssql shows driver messages verbatim, which is fine when the profile is in settings anyway;
copy its secret-store split, not its message handling. `[partly after vscode-mssql; the scrub is first
principles]`

### A6. The second review's minor findings

| # | Finding | Options | RECOMMEND | Lands in |
|---|---|---|---|---|
| 6a | `SessionTask.pool` unbounded and shared (`SessionTask.scala:19-24`) | bound it; or state it | **state it** in §2.2: a render's load and a check's import load compete for cores; `-Dermine.loadInSeries=true` (`Session.scala:682`) is the existing knob for a starved laptop. No code | §2.2 text |
| 6b | `Phases` pollution | preview thread records nothing; or perf runs with preview off | **both are already true or free**: `Phases.record` is `synchronized` (`Phases.scala:43`) so nothing corrupts; `perf-bench.sh` refuses to run while any ermine JVM is alive, the editor included (`docs/gate-policy.md:105`), so a preview cannot pollute a recorded figure. State it; no code | §2.2 row |
| 6c | `Wire.send` monitor held by a large document | accept; or cap | **cap**: a rendered document over `ermine.preview.maxDocumentBytes` (default 16 MB) is answered 500 "document too large for the panel" before `send`; the webview would not survive it either. State the monitor in §2.3 | WP-4 |
| 6d | `Con.memoizedKindSchema` (`Type.scala:231`) | add to the table | **add as benign** (idempotent write) | §2.2 row |
| 6e | `Server.ask`/`clientPending` plain vars (`Rpc.scala:413-426`) | rule | **rule in §2.3**: the preview thread uses `notify` and the deferred answer only, never `ask` | WP-4 |
| 6f | manual reload never invalidates the preview | post from `afterReload`; mtime scan per render | **both**: `afterReload` (`Main.scala:179`, called by the watch handler `:268` *and* the command `:277`) posts `invalidate(paths of x.modules)`; and the render session runs the `reloadStale` test (`Resident.scala:271-273`, `depCache(sf)._1 != sf.lastModified`) over its own `loadedFiles` at the head of every render — one `stat` per loaded file, ~150 files, milliseconds — so edits from outside VS Code and watcher-less clients are seen | WP-4 |
| 6g | 503 window after a recycle; A7 on the automatic reconnect | — | the extension **re-sends the last render after every successful `connect`**; the trace-`verbose` refusal lives in the extension's one `connect()` function, so the recycle path cannot bypass it; while refused the status bar reads "disconnected: trace is verbose" | WP-12 |
| 6h | 18486 / 18487 / 18488 classified `connect` and replayed (locked, expired, must-change; *external* but corroborated by MS docs and an Azure Data Studio issue on 18487) | new class; or `auth` with a flag | **`auth` gains `kept: Boolean`**: 18456/`28000` → `auth, kept:false` (delete the secret); 18486/18487/18488 → `auth, kept:true` (secret kept, "prompt next time", **never** an unattended retry, message names the reason). Pinned with the fake driver | WP-11 |
| 6i | the driver's `Connection` retains the password (*external*) | — | **state it** in §7.2 and change WP-12's done-when to "no password *field* in `lsp/Preview.scala`; the driver's `Connection` is acknowledged to hold it until close" | §7.2, WP-12 |
| 6j | `invalidate` under `evalLock` | — | yes: `Runner.invalidate` is `evalLock.synchronized` (`Runner.scala:301`); `TestRunner` runs properties concurrently over one runner (`:112`) | WP-3 |
| 6k | preview thread a daemon | — | yes, `setDaemon(true)` as `SessionTask.scala:22` | WP-4 |
| 6l | WP-2 "two call sites" | — | four: `scrub` at `Resident.scala:212`, `:231`, `:461`; `dependentsOf` at `:208`; done-when says so | WP-2 |
| 6m | `previewRoots` resolution | — | see B8 | WP-5 |

---

## Group B — underspecified in the design

### B7. The first render has no parameters

**Problem.** Pick `Sales` (four required fields, `Sales.e:58-63`) and the render is a 400 at
`$.params.fromDay` (`Runner.scala:473`) until a params file exists; the picker is WP-5, the file WP-9.

| Option | Change | Consequence |
|---|---|---|
| (i) skeleton from the JSON schema | extension, ~40 lines, no dependency: walk the exported schema; required properties get `""` / `0` / `false` / first `enum` value / today for `format: date` / `{}` recursively; optional (`Maybe`) keys are omitted; written as the initial `<Module>.params.json` with `$schema` | every report renders on first pick; wrong-but-typed values are a 400 with a path, which the file's squiggles already explain |
| (ii) Storybook `args`: a sibling binding `reportArgs : Query` in the module | render session evaluates the bare name and encodes it with `Encode.toArgonaut` (`Encode.scala:171`); used as the initial file when present | Ermine-native defaults the module author controls; needs the render session, a naming convention, and an encode path for an arbitrary value (already exists) |
| (iii) leave the 400 | — | a real report is unusable until the user hand-writes JSON from the schema |

**Prior art.** Storybook: `args` on the default export are the component's defaults and every story
overrides them; controls are generated from `argTypes` (*external*). JSON-Schema tooling generates
instances from `required` + `default` (json-schema-faker and kin, *external*).

**RECOMMEND.** **(i)** in WP-9, and **move WP-9 to directly after WP-5** (before the bundle work), since
a report with parameters is unusable without it. (ii) is adopted as part of B9's shape: when the module
has `<binding>Args` of the params type, it seeds the file instead of the skeleton. WP-5's done-when
changes to "`Sales` shows a 400 naming `$.params.fromDay` in the tab; WP-9 turns it into a document".
`[after Storybook args + JSON-Schema instance generation]`

### B8. `ermine.preview.roots` is a passing mention

**Problem.** No scope, no resolution rule, no default, no behaviour when empty; relative `moduleRoots`
resolve against the server's cwd (`Main.scala:102-104`), which is `server.root` (`extension.js:151`).

| Option | Consequence |
|---|---|
| (i) infer the root from the picked report | the server derives it as `checkFile` does (`Resident.scala:428-434`: parse the header, walk up one directory per extra segment of the module name); a single-segment module anywhere previews with **no setting** |
| (ii) `ermine.preview.roots` only | every user configures it before the first render; the WP-5 done-when already assumes that |
| (iii) both | inferred root first, then the configured extras (a widget library beside the report) |

**RECOMMEND.** **(iii)**, specified as: `ermine.preview.roots`, `type: array of string`, `scope: "resource"`
(*external*: per-folder setting), default `[]`; the extension resolves each entry against the workspace
folder that owns the picked report (`getConfiguration("ermine", folderUri)`, *external*) and sends
**absolute** paths in every `ermine/render` as `roots`; the server's roots are `moduleRoots ++
inferredRoot(uri) ++ roots`, distinct; a change to the set discards the `Runner` (roots are immutable
config, `Runner.scala:171`). Empty means "the report's own tree and the stdlib". Lands in WP-4 (server:
`inferredRoot`, the discard rule) and WP-5 (setting, resolution). `[after Storybook's explicit `stories`
glob with an inferred default; the header walk is this repo's own rule]`

### B9. Only the binding named `report` is reachable

**Problem.** `ermine/render` is `{uri, params}`; `RunnerConfig.reportName` defaults to `"report"`
(`Runner.scala:173`) and `compile` uses it at `:445`, `:458`; `reports` is keyed by module (`:296`).

| Option | Change | Consequence |
|---|---|---|
| (i) a binding per request | `ermine/render {uri, binding?: "report", params}`; `Runner.report/compile(module, binding)` with `reports` keyed `module + "." + binding` (`:296`, `:411-420`, `:445`, `:458`, `:485`, `:541` all read `cfg.reportName` today; it stays the default for `bin/ermine-serve`); the picker's unit becomes (file, binding), listing bindings whose signature line ends in `Node` or `Fetch Node` (`^(\w+)\s*:.*\b(Node|Fetch Node)\s*$`, approximate; the server 400s anything that is not a report, `:466-470`) | one module can hold `report`, `emptyReport`, `wideReport`, each with its own params file `<Module>.<binding>.params.json` (`<Module>.params.json` stays for `report`) |
| (ii) a `Story` record type in the stdlib | — | new surface; nothing else needs it |
| (iii) one report per module | — | the widget harness multiplies files for every variant |

**Prior art.** Storybook CSF: the default export is the component's meta, **every named export is a
story** with its own `args` (*external*). (i) is that shape: a story is a named report-typed binding.

**RECOMMEND.** **(i)**; copy the named-export idea, reject a stdlib `Story` type. Lands in WP-3 (`Runner`
keyed by binding; property: two bindings in one module render two documents), WP-4 (wire), WP-5
(picker unit), WP-9 (file naming, `<binding>Args` seeding per B7). No ordering change.
`[after Storybook CSF named exports]`

### B10. How a scanning report gets data locally

**Problem.** §0's honesty argument rests on inline relations; real reports scan tables. Checked:
`Sales.e` builds every relation from literal rows (`relation (map_List …)`, `Sales.e:111-117`;
`relation = mkRelation# …`, `Relation.e:23-24`), which the scanner emits as a `LiteralSqlTable`
(`SqlScanner.scala:1034-1035`) — so it is scanned through the SQLite connection and needs no table.
A real report reads `table` declarations (`Session.scala:1695`) through `Layout.Fetch.scanRelation`
(`Fetch.e:69`), and those tables must exist in the preview database. **§0's claim holds for the widget
surface and for `Sales`; it does not hold for a scanning report, and the design does not say so.**

| Option | Change | Consequence |
|---|---|---|
| (i) file-backed SQLite | the `local` profile documents `url: "jdbc:sqlite:<folder>/.ermine/preview/local.db"` as the alternative to `:memory:`; the developer fills it with `sqlite3`, DB Browser, a script | zero server code; the data outlives a restart; `.ermine/` is gitignored by WP-9 |
| (ii) `seed` in the profile | `seed: [paths]` of `.sql` files run on every `connect` (once per held connection) as `Statement.execute` per `;`-terminated line; a failing statement answers `connect` class naming the file and index; refused for a `deploy: true` profile | reproducible fixtures beside the report; naive `;` splitting (Flyway/Liquibase split the same way with a configurable delimiter, *external*) |
| (iii) Ermine-side fixtures | — | Ermine relations cannot create tables; the emitter's temp tables are the scanner's, not the author's |

**Prior art.** Storybook fakes data at the boundary (MSW, loaders/decorators) rather than running a
database (*external*) — unavailable here, the scanner is the boundary. Seed files are the norm where a
local database is real (Rails `db/seeds.rb`, Django fixtures, *external*).

**RECOMMEND.** **(i) now** (one documented URL; §0 rewritten: "faithful in shape for literal relations;
a scanning report needs its tables in the preview database — file-backed SQLite, seeded by you, or an
MSSQL profile") and **(ii) in WP-12**, where the connect lifecycle it hangs on exists. Whether `seed`
belongs in the tool at all is the user's call (product scope). `[after seed-script convention; reject
Storybook's mock-at-the-boundary as inapplicable]`

### B11. Profile switching is a sentence, not a sequence

**Problem.** §2.4 says a switch is "a new `Runner`"; the order of disconnect, discard, boot, reconnect,
eviction, the panel's document and an in-flight render is unstated; a settings/profile change does not
evict the report cache.

**Prior art.** vscode-mssql: explicit Connect/Disconnect commands, the status bar names the connection,
"change connection" disconnects first (*external*).

**RECOMMEND** the sequence below as the text of §2.4 and WP-12's spec; every step is a preview-queue job,
so ordering is queue order and the in-flight render simply finishes first:

| Step | Who | What |
|---|---|---|
| 1 | extension | bump a `generation` counter; every later `ermine/render` carries it and every answer echoes it; an answer with an older generation is discarded (the in-flight render on the old profile finishes and is ignored) |
| 2 | extension | status bar "switching to `<id>`"; the panel keeps the last document dimmed under a "switching" banner |
| 3 | extension → server | `ermine/preview/disconnect` |
| 4 | server | close the connection; **discard the `Runner`** (`RunnerConfig.run`/`scanner`/`settings`/`roots` are immutable, `Runner.scala:171-179`), which evicts `reports` and the compiled closure with it |
| 5 | extension → server | `ermine/preview/connect {profile, password?}` after the A3 prompt if the secret is missing; the A7 refusal applies here as everywhere (A6g) |
| 6 | extension → server | on `ok`, re-send the last render (the new `Runner` boots lazily inside it, with B15's progress) |

The same sequence runs when any field of the **active** profile, or `ermine.preview.roots`, changes
(`onDidChangeConfiguration`, `extension.js:262`); a change to an inactive profile does nothing. Lands
in WP-12, with the generation field in WP-4's wire shape. `[after vscode-mssql connect/disconnect;
ordering is first principles]`

### B12. Crash and restart recovery

**Problem.** If the server dies or is restarted — the designed recovery for a runaway — the panel holds a
stale document and the extension has no stated behaviour.

**Prior art.** `vscode-languageclient` restarts a crashed server, up to 5 times in 3 minutes, and
exposes `onDidChangeState` (Stopped / Starting / Running) (*external*). Jupyter marks outputs as from a
dead kernel and re-runs nothing on its own; Flutter's hot *restart* drops state where hot *reload*
keeps it (*external*).

**RECOMMEND.** By construction every input the loop needs lives in the extension — picked (file, binding),
params path, active profile id, last document, `generation` — and the server holds nothing across a
restart except the database. Then: on `Stopped`, banner "server stopped — last document kept", status
"Ermine: preview offline", the document stays dimmed; on `Running`, the extension runs the connect flow
of B11 steps 5-6 (prompting only if the secret is gone) and re-sends the last render; scroll and
drilldown are lost, exactly as §5 already accepts for a bundle change (a hot restart, not a hot reload).
The watchdog notification (A4) carries **Restart Language Server** (`ermine.restartServer`,
`extension.js:241`). Lands in WP-7 (banner states) and WP-12 (reconnect on `Running`).
`[after vscode-languageclient restart + Jupyter dead-kernel marking]`

### B13. Nothing tests the panel or the bundle

**Problem.** §11 covers wire, render session, runner, emitters, classifier and a smoke; the webview
layer has none.

| Layer | Worth testing? | How |
|---|---|---|
| host-page message protocol (extension ↔ webview: `render`, `error`, `stale`, `reloadBundle`, `unsaved`) | **yes**: it is the only new logic | pull the host script's state transition into a pure `applyMessage(state, msg)` in `client/src/host/`, built by the same webpack config, run under `node --test` beside `client/test/harness.ts` (`client/package.json:16`) |
| the bundle loads under the CSP; the writers global (Q1) | **yes, once per bundle-config change, by hand**: jsdom cannot answer it | a checklist in WP-6/7's done-when: no console error, `window.ErmineClient.parseDocument` present, `table` renders through the writers global |
| DOM output of `parseDocument → render` | no: already covered in jsdom (`client/test/harness.ts:1-4`, `:31-42`) | — |
| scroll, `retainContextWhenHidden`, panel lifetime | no: VS Code's behaviour, not ours | — |
| `@vscode/test-electron` integration | no: downloads VS Code, impossible offline (§10) | — |

**Prior art.** VS Code's Markdown preview is tested by integration tests in the vscode repo; Storybook's
test-runner drives a real browser (*external*). Copy "one real-browser check", reject a browser
automation dependency in a closed environment.

**RECOMMEND.** The two "yes" rows, in WP-6 (bundle checklist) and WP-7 (host reducer + its `node --test`).
`[after Storybook's one-real-browser-check; the reducer test is first principles]`

### B14. The new tests are not placed in the gate tiers

**Problem.** `tracker/GATE-POLICY.md` is superseded (`:1-3`) by `docs/gate-policy.md`: tiers `commit`
(compile, corpus, lsp; ~2.5 min, budget 3 min), `pr` (+suites = full `core/test`, lean; 20 min),
`nightly`; "a new gate enters at `nightly` and moves up on evidence" (`docs/gate-policy.md:52-56`,
`:87-92`); environment-dependent checks are instruments, not gates (`:28-29`, `:98-101`).

**RECOMMEND** this placement, written into each WP done-when as a "tier / cost" cell:

| New tests | Where they run | Tier | Cost per run |
|---|---|---|---|
| `TestLspRobustness` A + D groups, `TestRunner` invalidate/binding properties, `TestSqlEmitters` strings, the classifier with the fake driver | `sbt core/test` (`scalacheck-binding/src/main/scala` is in core's test sources, `build.sbt:88-90`) | `suites` (**pr**), automatically | group D boots a render session: seconds each, MEASURED in WP-4 and kept under 60 s total or the suite is split |
| `lsp-client.py` render / invalidated / schema-binding section | `tracker/tools/lsp-smoke.sh` (`scripts/gates.sh:115-120`) | `lsp` (**commit**) | adds one preview boot to a 44 s gate; if the gate passes ~90 s it moves to `pr` per the 3-min budget |
| `client` `npm test` (existing harness + the B13 reducer) | new `gate_client` in `scripts/gates.sh` | enters at **nightly** per policy; promotion after one recorded catch | seconds |
| credential gate (§8.4), `##` count, RSS/boot seconds, heap after watchdog | instruments; results written into the design | none | human / machine-dependent |

No gate exceeds 20 min, so nothing needs the user's approval under `:91`. `[after this repo's own policy]`

### B15. Two small races

**(a) `stale` peek before send.** The peek is advisory: whatever `invalidate` arrives after it, the
`invalidated` notification that follows (§3 step 5) makes the extension re-render, so nothing is lost —
only the banner is late. **RECOMMEND** stating that in §2.5 ("`stale` is a hint; `invalidated` is the
mechanism") and implementing the hint as a `@volatile` generation counter bumped by `invalidate`,
snapshotted at render start and compared just before `send`, no queue peek. WP-4.
`[after rust-analyzer's `ContentModified`: the client re-asks, *external*]`

**(b) the lazy boot.** LSP 3.15+ has server-initiated work-done progress
(`window/workDoneProgress/create` then `$/progress` begin / report / end; `cancellable` is a field)
(*external*); rust-analyzer reports "Loading / Indexing" that way so a long operation never looks like
a hang (*external*). **RECOMMEND**: the first render (and every post-discard boot) reports progress
"Ermine preview: booting the render session" with `cancellable: false`, guarded by the client's
`window.workDoneProgress` capability; a `$/cancelRequest` during the boot is honoured when the boot
ends (answer `-32800`, boot kept), the §2.5 rule unchanged; boot seconds MEASURED in WP-4. WP-4 plus
WP-1's `$/progress` send from the preview thread (through the synchronised `send`).
`[after LSP work-done progress as rust-analyzer uses it]`

### B16. Fast mode is unaddressed

**Problem.** `ermine.fastMode` skips the typecheck in *checks* (`Main.scala:65-70`); the render session
is `_typeCheck = Some(true)` (`Runner.scala:288`) and must be: `Session.eval` infers the report's type
(`Session.scala:830`) and `Decode.reportSignature` consumes it. So in fast mode a type error has no
squiggle but the preview shows a 500 "module does not load" — the banner is the only diagnostic.

**RECOMMEND.** Say it, cheaply: the preview status item carries the same "(fast)" suffix
(`extension.js:69-71`), and a load-failure banner adds "fast mode is on: type errors are not shown in
Problems" when `config().get("fastMode")` is true; §2.4 gains the row "the preview always typechecks".
Three lines, WP-7. `[first principles]`

---

## Housekeeping — the 2.11 back-port is out of scope

| Where | Today | Change |
|---|---|---|
| §0 scope | "the 2.11 back-port beyond the driver-classifier note in §7" | delete the clause |
| §7.3 row 4 | "the classifier differs per branch" | "`mssql-jdbc` with the `jre11` classifier (JDK 21, `bin/ermine-lsp:25`; *external*: jre11 runs on 11+)" |
| §10 driver row | "the right classifier per branch" | "`jre11`" |
| WP-10 | "with the per-branch classifier" | "`jre11`" |

---

## §C. Effect on the tickets

| Ticket | Change | Ordering |
|---|---|---|
| WP-1 | `$/progress` sendable from the preview thread | — |
| WP-2 | done-when: four call sites, not two | — |
| **WP-2b NEW** | `_registerDecls` flag on `SessionEnv`, off on `withEnv` copies; group-D property | **between WP-2 and WP-3** |
| WP-3 | `Runner` keyed by (module, binding); `paramSchema`; `invalidate` under `evalLock`; `CountingRun` pin unchanged | — |
| WP-4 | daemon thread; generation counter for `stale`; mtime scan per render; `-Xmx` + `ExitOnOutOfMemoryError` in the launcher and `ermine.maxHeap`; document-size cap; `inferredRoot`; `ermine/schema {binding}` routing; work-done progress; `generation` in the wire shape; heap/boot MEASURED | — |
| **WP-4b NEW** | cooperative cancel in `swhnf`; render session discarded on cancel; perf instrument before adoption | after WP-4, optional |
| WP-5 | picker unit (file, binding); `ermine.preview.roots` resource-scoped and absolutised; done-when accepts the 400 | — |
| **WP-9** | skeleton from schema; `<binding>Args` seeding; `<Module>.<binding>.params.json` | **moves to directly after WP-5** |
| WP-6 / WP-7 | bundle CSP checklist; host reducer + `node --test`; banner states (unsaved, switching, server stopped, fast mode) | — |
| WP-11 | no `untrustedWorkspaces`; `Throwable` catch + scrub; URL credential refusal; `driver` for "No suitable driver"; `auth.kept` for 18486/7/8 | — |
| WP-12 | B11 sequence; re-render after every connect; A7 in the one `connect()`; `seed` files; reconnect on `Running`; done-when wording on the driver's `Connection` | — |
| §11 | tier / cost cell per done-when; `gate_client` at nightly | — |

## Decisions that are the user's, beyond the three already on their plate

| Decision | Advice |
|---|---|
| A4 (ii): a cancel check inside the evaluator's hot loop (`Runtime.swhnf`), with a perf A/B before adoption | yes, as WP-4b; it is what makes the watchdog honest |
| A4 (i): `-XX:+ExitOnOutOfMemoryError` for the whole server (today's OOM zombie becomes crash-and-restart) | yes |
| B9: the picker's unit is (file, binding) — a naming-free convention, any report-typed binding is previewable | yes; it is Storybook's shape and costs a key change |
| B10: whether `seed` SQL files belong in the tool, or a file-backed SQLite the developer fills is enough | file DB now; `seed` only if a scanning report is actually authored in the panel |
| B14: `npm test` as a registered (nightly) gate | yes; it is seconds |

## Not verified

- Every *external* claim above: VS Code Restricted Mode activation and `restrictedConfigurations`
  semantics; ESLint's `nodePath` handling; `vscode-languageclient`'s 5-in-3-minutes restart and
  `onDidChangeState`; `scope: "resource"` and per-folder `getConfiguration`; `isDirty`,
  `onDidGrantWorkspaceTrust`; LSP work-done progress and `-32800`; mssql-jdbc property names and the
  wording of "No suitable driver found"; SQL Server 18486/18487/18488 meanings (corroborated by web
  sources, not by a driver run); `-XX:+ExitOnOutOfMemoryError`; SQLite `:memory:` persistence per
  connection; Storybook CSF/args; Jupyter interrupt semantics; rust-analyzer's progress and
  cancellation; Flyway's delimiter handling.
- Whether every Ermine loop passes through `Runtime.swhnf` (A4 (ii) depends on it; a loop inside one
  primitive would not be cancellable).
- The cost of a render-session boot and of group D in `core/test` (both MEASURED in WP-4 by design).
- That the TextMate grammar keeps working for a non-activated extension in Restricted Mode (*external*).
