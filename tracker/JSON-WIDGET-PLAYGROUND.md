# JSON widget playground: edit a widget, see it rendered, inside VS Code

> **STATUS: WP-1, WP-2, WP-3, WP-4 AND WP-5 STAGE A ARE BUILT; EVERYTHING ELSE IS DESIGN
> ONLY.** No other ticket has been started. WP-5 is being built in three reviewed stages;
> stages B and C are not started. What each built ticket is, and the only files it changes --
> this document aside, which every ticket touches:
>
> - **WP-1**: `send` synchronised, `onRequestDeferred`, `$/cancelRequest` routed, the incoming
>   log line moved after the parse and redacted by method; the `TestLspRobustness` A group.
>   Files: `Rpc.scala`, `TestLspRobustness.scala`.
> - **WP-2**: `scrub` and `dependentsOf` lifted from `Resident` into `Session` with `builtins`
>   a parameter; `Resident` calls them at its four sites. Files: `Session.scala`,
>   `Resident.scala`.
> - **WP-3**: `SessionEnv._registerDecls`, default on and carried by `copy`; the registration in
>   `processTypeDefComponent` consults it; `Resident.withEnv` -- the one per-request copy site
>   -- takes a `copyNotRegistering` copy; the one `TestLspRobustness` D property. Files:
>   `SessionState.scala`, `Session.scala`, `Resident.scala`, `TestLspRobustness.scala`.
> - **WP-4**: `Runner` with `reports` keyed by `(module, binding)`,
>   `report`/`compile`/`render`/`renderText` per pair with `cfg.reportName` still the HTTP
>   route's default, `paramSchema(module, binding)`, `Runner.resultKind` public on the
>   companion, a `builtins` snapshot after the runner's own preamble, and
>   `invalidate(paths): Set[String]` under `evalLock` -- scrub the closure, evict `reports`, no
>   eager reload; `Backends.scannerFor(dialect, variant)`; `lsp/DelegatingRun.scala`; the four
>   `TestRunner` properties of §11's "Runner" row. Files: `json/Runner.scala`,
>   `backends/Backends.scala`, the new `lsp/DelegatingRun.scala`, `TestRunner.scala`, and --
>   for the review's layering item only -- `Session.scala` and `Resident.scala`, where
>   `normalize`, `moduleUnder` and `loadedByPath` move into `Session` beside
>   `dependentsOf`/`scrub` and `Resident` keeps forwarders, so that `json` does not import
>   `lsp`.
> - **WP-5 stage A**: the preview thread and the `Preview` object in `lsp/` -- one daemon
>   thread owning the render session, lazy boot of the `Runner` on the first `ermine/render`
>   with the roots of §2.4 and a local in-memory SQLite behind a `DelegatingRun`,
>   `ermine/render` answered through `onRequestDeferred` with §4's two shapes (`uri` ->
>   module, `inferredRoot`, absolute `roots`, the root-change discard, 404 / 400 / 503, no
>   JDBC URL in a message), the queue of §2.5 (one in flight, at most one queued render,
>   latest wins, `-32800` for the replaced one, jobs in queue order, `generation` echoed),
>   `$/cancelRequest` for a queued and for an in-flight render, the mtime scan at the head of
>   every render, the `stale` counter, and `invalidate` posted from `afterReload` with
>   `ermine/preview/invalidated`; the `TestLspRobustness` D render-session properties.
>   The preview thread cannot end abnormally (a pre-allocated last-resort answer in a
>   `finally`, every step of the crash handler guarded, a bounded outer catch-all, and a
>   render refused with an error rather than queued if the thread is gone), and every line
>   it logs is scrubbed of JDBC URLs by construction (rule A5 covers logs).
>   Files: the new `lsp/Preview.scala`, `Rpc.scala` (a deferred handler that is given the
>   request's id, and the `-32800` constant), `Documents.scala` (`pathFor` lifted to the
>   companion), `json/Runner.scala` (`invalidateStale`), `Main.scala` (the install and the
>   `afterReload` post), `TestLspRobustness.scala`.
>   NOT stage A, and named as seams in `Preview.scala`: the watchdog and the "stuck" state,
>   `ermine.preview.maxDocumentBytes`, `ermine/schema {binding}` on the queue,
>   `ermine/preview/reports`, work-done progress (stage B); the launcher's `-Xmx` and
>   `ermine.maxHeap`, the `lsp-client.py` smoke and the measured instruments (stage C);
>   profiles, `connect`, `disconnect` and the held connection (WP-13, WP-14).
>
> **Which suites were run, and what they said, is recorded in each ticket's commit message, not
> here**: a banner that names a suite goes stale the moment the next ticket runs a different
> set, and a claim about a suite THIS tree has not run is worse than no claim.
> The work lives on branch `widget-preview` in the worktree
> `ermine-scala-wt-widget-preview`, forked from `json-encode` at `a0830244`; this document is
> committed there. Every claim about this codebase is MINED from reading the source at that
> commit (2026-09-19) and carries a `file:line`; nothing was run or measured unless a row says
> MEASURED. Claims about third-party software (VS Code, vscode-languageclient, webpack, JDBC
> drivers, SQLite, SQL Server, the LSP specification) are tagged *external* and were not
> verified in this repository. Gates run against the worktree:
> `scripts/gate-tier0.sh -C widget-preview`, `scripts/corpus-sweep.sh -C widget-preview`, and
> the in-tree `scripts/gate.sh run commit|pr` from inside it.

## 0. What the preview is for

Two surfaces, one of which this document builds:

| Surface | What is edited | Rows come from | Oracle | In this document |
|---|---|---|---|---|
| **Widget and parameter work** | a widget module `Layout/Widgets/<Foo>.e`, its TypeScript renderer, the params a report is fed | inline literal relations (`Sales.e` imports `Relation` and defines `report : Query -> Node`, `core/src/test/resources/doc/Sales.e:107`; every relation in it is built from literal rows, `:111-117`, which the scanner emits as a `LiteralSqlTable`, `SqlScanner.scala:1034-1035`, through whatever connection is held) | SQLite in memory. The document *shape* -- widget names, props, layout -- does not depend on the dialect; cell values can differ only where §9.3 lists an engine difference | **yes, the whole loop** |
| **Relation / query authoring** | a relation that scans a real database | SQL Server | only SQL Server. SQLite is a best-effort stand-in, §9 | **only as a profile** (§7); the T-SQL diff view is optional and last (WP-19) |

The first row's honesty argument holds for literal relations. A report that reads `table`
declarations (`Session.scala:1695`) through `Layout.Fetch.scanRelation` (`Fetch.e:69`) needs
those tables to exist in the preview database: a file-backed SQLite the developer fills, or
an MSSQL profile (§7.1). The preview does not create tables and ships no seed-script
mechanism.

Scope: a developer edits (a) an Ermine widget module, (b) its renderer, (c) the parameters,
and sees the rendered document without restarting a JVM or running a build by hand. The
unit the preview shows is a **report**: a top-level binding of type `Node`, `Params -> Node`,
`Fetch Node` or `Params -> Fetch Node` (`Runner.scala:591-595`). Any such binding in any
module is previewable; nothing depends on what it is called (§3.2). Out of scope: deployment,
multi-tenant serving, class-constraint work (on hold), and the 2.11 back-port.

## 1. What exists, and what each edit costs today

| Surface | To see the result today | Why | Evidence |
|---|---|---|---|
| Ermine widget module | restart `bin/ermine-serve` (a JVM boot) and re-request | a module named by a request "is loaded on first use and stays loaded"; a working report "is cached forever; there is no `:reload`" | `json/Runner.scala:215-219`, `:296`, `:411-420`; `docs/JSON-GUIDE.md:1452-1453` |
| TypeScript renderer | `npm run build` (`tsc`), then nowhere to look: no host page, no bundle, no dev server | `client/` is CommonJS with `tsc` as its only build; nothing watches; the only `.html` in the repo is `docs/tutorial.html` | `client/tsconfig.json:5`; `client/package.json:11-18`, `:19-28`; `find` for `*.html` |
| zod for a new prop type | `npm run generate`: one `bin/ermine-schema --zod` per type, eleven JVM boots | the loop at `generate.sh:33-38` | `client/scripts/generate.sh:18-30`, `:33-38` |
| Parameters | hand-write JSON and `curl` it | `POST /report/<Module>` is the only way in, and it reaches one binding per module, `RunnerConfig.reportName`, default `"report"` | `json/Server.scala:16-18`, `:102-112`; `json/ServeMain.scala:13-26`; `Runner.scala:173`, `:445` |

`parseDocument` -> `render` has only ever run in jsdom under `node --test` with a stub
`htmlwriter` that records calls instead of drawing (`client/test/harness.ts:1-4`, `:31-42`);
the documented browser call is `client/src/index.ts:3-7`.

Assets the design stands on:

| Asset | Where | Used for |
|---|---|---|
| A resident session booted once (~13 s), interface-free, foreign-tolerant, watching `**/*.e` through the client and reloading changed modules plus dependents on the dispatch thread | `lsp/Resident.scala:14-18`, `:24`, `:118-121`, `:205-241`, `:251`; `lsp/Main.scala:199-208`, `:256-268` | the watcher event is the trigger of the loop (§3); the resident itself is **not** touched by the renderer (§2) |
| A per-document symbol tree built on the check path, each symbol carrying the check's inferred `Type`, rendered on demand | `lsp/Symbols.scala:120-122`, `:156-157`, `:287`, `:449-455`; `lsp/Definitions.scala:96-103`, `:1023-1026`; `Documents.scala:59` | listing a module's report-typed bindings for the picker (§3.2) |
| A custom request answered from that process, `ermine/schema` | `lsp/Definitions.scala:226-228`; `json/Schema.scala:800-815` | precedent for `ermine/render`; extended with a binding mode that the render session answers (§6) |
| `Runner`: boots its own `SessionEnv`, loads a module on demand, caches a working report, evaluates under a process-wide lock, scans outside it, inside ONE `cfg.run.run` | `json/Runner.scala:273`, `:287-288`, `:311-326`, `:411-420`, `:429-436`, `:495-496`, `:538-540`, `:624` | the render session **is** a `Runner` (§2) |
| `Runners.fromPersistentConnection(conn)`: a `Run[DB]` over one held connection | `backends/Backends.scala:49-51` | the preview's connection (§7) |
| `Scanners.MicrosoftSQLServer` / `...NoTransactions` | `backends/Backends.scala:26-27` | profile `scanner` knob (§7) |
| `Statement.setQueryTimeout(300)` on every prepared statement | `sql/SqlExecution.scala:47-50`; `backends/DB.scala:39-45` | the only bound a scan has today (§2.5) |
| `TestLspRobustness`: wire and dispatcher fuzz, a resident under mutation, reload properties | `scalacheck-binding/src/main/scala/TestLspRobustness.scala:168`, `:241`, `:455`, `:554`, `:583`, `:655` | where the render endpoint is property-tested (§11) |
| `tracker/tools/lsp-client.py`: `request()` and an `ermine/schema` section | `:57`, `:605-624` | the end-to-end smoke |
| Extension 0.1.4: LSP client over stdio, four commands, first-folder server path | `editor/vscode/src/extension.js:43-46`, `:49-55`, `:145-151`, `:179`, `:241-256`; `editor/vscode/package.json:5`, `:75-92` | grep for `createWebviewPanel`, `createFileSystemWatcher`, `secrets`, `isTrusted`, `untrustedWorkspaces`: 0 hits -- all new |

The LSP never touches a database today: no `Connection`, `Run[DB]` or `Scanner[` under
`core/src/main/scala/com/clarifi/reporting/ermine/lsp/` (grep, 0 files).

## 2. Decision: a second, render-only session in the LSP process, on its own thread

### 2.1 Where the render runs -- three options against the source

| Option | What it requires | What the source says | Verdict |
|---|---|---|---|
| **(A)** render on the dispatch thread, sharing the resident's env | `Runner` refactored over a foreign env | `Runner.booted` is not a constructor parameter: it rewrites `env.loadFile` (`Runner.scala:316`), re-runs `Lib.preamble` (`:318`), loads `Layout.Doc`/`Layout.Fetch` (`:319`) into an env built `_typeCheck=true, _useInterface=false` without tolerance (`:287-288`), whereas the resident is `_foreignTolerant = Some(true)` (`Resident.scala:118-120`). `Session.loadModules(List("Sales"))` (`Runner.scala:436`) would put workspace modules into the resident, which `tracker/LSP-STALENESS.md:40` rejects for `reloadChangedModules`. And the first preview would boot on the dispatch thread: `booted` is a constructor `val` (`:311`) | rejected: sound only after a refactor larger than the feature, and the workspace-module leak remains |
| **(B)** share the resident's env under a new lock ordered against `Runner.evalLock` | a lock taken by `reload`, `checkFile`, `ermine/schema` and the render | `SessionEnv.copy` reads eleven `var`s non-atomically (`session/SessionState.scala:95-113`); every `Runtime` in `env.env` is shared by copies and `Thunk.state` is a non-volatile `var` (`Runner.scala:257-260`); a runaway evaluation holding that lock would freeze diagnostics too | rejected: the lock would have to cover every check, so a slow render stalls typing anyway, and the copy-torn window stays |
| **(C)** a second session: the renderer keeps building its own `SessionEnv` exactly as `Runner` does today, booted lazily, invalidated by the same `**/*.e` events | proof that two sessions coexist in one JVM (§2.2) | `Runner` needs no constructor change: it already owns its env (`:287-288`). The resident is never read or written by the renderer | **adopted** |

### 2.2 Can two sessions coexist in one JVM? Every process-wide mutable object on the load/eval path

| State | Where | Written by | Two sessions | Verdict |
|---|---|---|---|---|
| `DataConDecl` registry: two `ConcurrentHashMap[Global, DataConDecl]` | `ermine/DataConDecl.scala:55-56`; `register` `:58-62` | four writers: the resident's boot and reloads (disk, `Resident.scala:126-127`, `:130`, `:214-215`); the render session's boot and `compile` (disk, `Runner.scala:315`, `:436`); both `Lib.preamble`s (`Lib.scala:45`, `:1472`); and **the editor's tolerant check**, which runs `Session.processTypeDefComponent` (`TolerantCheck.scala:862` -> `Session.scala:896`, `:915`) for every type declaration of the file being checked, reading the **open buffer** (`Resident.scala:412-413`; `Documents.scala:46`) on every debounced keystroke | Keyed by `Global(module, name)`; the file's own comment: entries are "facts about a declaration (module + name -> shape); reloading a module re-registers and overwrites ... Two sessions in one JVM defining the same module.name with different shapes (only the test fixture does this) see the last writer" (`:44-54`). Readers fall back to the registry only when the `Con` in hand carries no decl (`json/Schema.scala:240`, `:319`; `json/Decode.scala:232`, `:402`; `json/Encode.scala:631`) plus `Encode.userData`'s lookup for a runtime `Data` node, which has no env in reach (`Encode.scala:400`; `DataConDecl.scala:46-48`) -- the reader `toJson#` reaches (`Lib.scala:1478`), which three widgets use (`Scorecard.e:13`, `PieChart.e:23`, `StyleBox.e:28` import `Json`). The fourth writer is the problem: with `Chart.e` open and a field added to a props constructor but not saved, a render of the **saved** `Chart` meets the **buffer's** declaration; the guard `c.fields.length == args.length` (`Encode.scala:414`) fails, `named` is `None`, and the props encode as `{"tag", "args"}` (`:478-481`) instead of an object, which the renderer's zod refuses; a nullary constructor given a field in the buffer flips `isEnum` (`:401-404`) the same way. No invalidation fires for a `didChange`. **WP-3 silences that writer**: `SessionEnv` gains `_registerDecls` (default on; carried by `copy`, `SessionState.scala:113`, so `SessionTask.fork`'s copies inherit it, `SessionTask.scala:27`); `Session.scala:915` registers only when it is on; `Resident.withEnv` (`:143`, the one place every check copy is made) turns it off. A check copy's own readers are unaffected: the `Con` carries its decl (`Session.scala:923`) and Schema/Decode read the `Con` first; checks never evaluate, so `toJson#` never runs on a copy. After WP-3 every writer loads **disk content**, and entries from two sessions differ only in `Supply`-minted ids, which every reader is insensitive to (`Encode.scala:399-414` uses `isEnum`, `constructor(g)`, field names). The registry is already written from several threads inside one session's load: `loadMore` forks each module's make onto a cached pool (`Session.scala:639`, `:656`, `:672`; `session/SessionTask.scala:19-24`, `:26-37`), so a second session adds no new kind of write | **no collapse** once WP-3 lands. One window remains: between the resident re-registering a changed shape from disk and the render session reloading it, a render in flight can encode a `Data` node with the new field list. §2.5 makes that answer `stale` and the loop replaces it |
| `Supply` block allocator | `parsers/src/main/scala/scalaparsers/Supply.scala:7-10` (`synchronized`), `:18` | every `fresh` that exhausts a block | the resident has one supply (`Resident.scala:33`); `Runner` one per thread (`Runner.scala:280-283`); ids are globally unique by construction | fine |
| `Session.depCache` | `Session.scala:110`, "process-global" `:280` | every load, keyed by content-bearing `SourceFile` | already shared between the resident and every per-check copy; `Resident.reload` takes its dirty set from its own `loadedFiles`, not from the cache (`Resident.scala:160-166`, `:178-197`) | fine; the render session does the same (§3) |
| `SessionTask.pool`, a cached pool with no bound | `SessionTask.scala:19-24` | every parallel load | a render's module load and a check's import load compete for **cores**, not for threads; on a 4-core laptop a check slows while a render loads. `-Dermine.loadInSeries=true` (`Session.scala:682`) is the existing knob for a starved machine | stated; no code |
| `ForeignClasses.classMap` / `failureMap` | `parsing/ForeignClasses.scala:41`, `:52` | class lookups during load | a class missing for one session is missing for the other: same JVM | fine (mined, not run) |
| `Phases` | `session/Phases.scala:23-25`, `:42`, `:49` | inert unless `-Dermine.lsp.phases=true`; `record` is `synchronized` (`:43`) when on | a render in flight would add its load timings to the next check's phase line; nothing corrupts, and `perf-bench.sh` refuses to run while any ermine JVM is alive, the editor included (`docs/gate-policy.md:105`), so a preview cannot pollute a recorded figure | fine; stated |
| `Runner.evalLock` | `Runner.scala:624`, "PROCESS-WIDE" `:247`, `:298` | `Runner` only; the resident never takes it | stays that way: the resident is never blocked by a render | fine |
| `Lib` object-level values | `Lib.scala:165-192`: `Con`s and two constant `Data` nodes (`:168`, `:180`) | none after class init | already shared by the resident and its copies; no thunk among them | fine |
| `Type.Con.memoizedKindSchema`, a non-volatile `var` on `Con`s `Lib` shares | `ermine/Type.scala:231` | kind-schema memoisation on either thread | the write is idempotent | benign |
| `Runtime.Thunk.state` | `Runner.scala:257-260` | forcing | each session's `Lib.preamble` (`Lib.scala:1495`) installs its own primitives into its own env; no `Runtime` is shared across the two envs (mined: no object-level `Runtime` in `Lib` other than the two constants) | fine |
| JDBC `DriverManager` | `backends/DB.scala:107`, `:130` | `Class.forName` | process-global registry of drivers, read-only after load | fine |

The long-term shape is a per-session constructor index (a `decls` map on `SessionEnv` beside
`cons`, threaded into `Encode.encode`/`userData` through the primitive `Lib.json` installs
with the env in scope, `Lib.scala:1443`, `:1478`), which would make the static registry
test-only (`TestJson.scala:121`, `TestSchema.scala:754`, `TestNamedFields.scala:436` read it)
and shrink the `evalLock` rationale (`Runner.scala:614-619`) to `Supply` and `Thunk.state`.
It is about a day of threading a parameter through every JSON test and is **not** scheduled;
it becomes mandatory the day a second registry *reader* appears.

**Cost.** Two booted sessions in the editor's server process: the resident's 129 modules
(`Resident.scala:110`) plus a render session holding `Lib.preamble`, the `Layout.Doc`/
`Layout.Fetch` closure and the picked report's closure. `Layout.Fetch` imports `Native.*`,
`Control.Monad`, `Control.Monad.Cont`, `Function`, `List`, `Pair`, `Relation.Sort`,
`Relation.Scan` (`Fetch.e:45-55`), so a large fraction of the resident's modules is loaded
twice. **Unmeasured.** No launcher sets a heap cap today (`bin/ermine-lsp:18-31`; the
extension sets only `ERMINE_LSP_LOG`, `extension.js:145-146`), so the cap is the JDK default,
a quarter of RAM (*external*): 3984 MB on the 15.6 GB dev box (`tracker/PERF-ROADMAP.md:139`),
~2 GB on an 8 GB laptop, and §5's two-windows row makes that four sessions. WP-5 caps it:
`-Xmx${ERMINE_LSP_XMX:-2g}` and `-XX:+ExitOnOutOfMemoryError` in the launcher unless
`ERMINE_JAVA_OPTS` already names `-Xmx`; a setting `ermine.maxHeap` (default `"2g"`) the
extension exports as `ERMINE_LSP_XMX` beside `ERMINE_LSP_LOG`, restarting the server on a
change as `serverPath` does (`extension.js:275-280`). Two windows on an 8 GB laptop are then
4 GB of JVM heap by construction. WP-5's done-when records RSS and boot seconds before and
after the preview boot and writes the figures here.

### 2.3 Which thread

The render session runs on **one dedicated daemon thread** ("the preview thread": a
single-thread executor owned by the LSP, `setDaemon(true)` as `SessionTask.scala:22`, so a
looping render cannot keep a forked test JVM alive). The dispatch thread never touches the
render env; the preview thread never touches the resident. This is the resident's own
invariant (`Rpc.scala:364-368`; `Resident.scala:14-18`) applied to a second env on a second
thread.

Why not the dispatch thread:

| Fact | Evidence | Consequence on the dispatch thread |
|---|---|---|
| `Runner` boots in its constructor | `Runner.scala:311-326` | the first preview freezes every LSP request for the boot; the comparable resident boot is ~13 s (`Resident.scala:24`) -- unmeasured for the smaller session |
| a scan is bounded only by the 300 s statement timeout | `SqlExecution.scala:50`; `DB.scala:43` | a slow SQL Server query freezes diagnostics for up to five minutes |
| the reader and the dispatcher are one loop | `Rpc.scala:429-440` | `$/cancelRequest` cannot even be read while a render runs |

What the preview thread costs, and where it is paid:

| Change | Where | Ticket |
|---|---|---|
| `Wire.send` is unsynchronised (`Rpc.scala:340-346`); a second sending thread could interleave frames | make `send` `synchronized`. The monitor is then held for the write of a whole document; a multi-megabyte answer to a slow client delays the dispatch thread's next `publishDiagnostics` behind it. Bounded by the pipe and by the cap below | WP-1 |
| a document larger than the panel can survive | `ermine.preview.maxDocumentBytes` (default 16 MB): a rendered document over it is answered 500 "document too large for the panel" **before** `send` | WP-5 |
| a request handler answers synchronously (`Rpc.scala:471-481`) | add `onRequestDeferred(method)(params, answer: Either[(code, msg), Json] => Unit)`; the answer callback may run on any thread and answers exactly once | WP-1 |
| `$/` notifications are dropped (`Rpc.scala:488`) | route `$/cancelRequest` to a handler | WP-1 |
| `Server.ask` / `clientPending` are plain vars (`Rpc.scala:413-426`) | rule: the preview thread uses `notify` (through the synchronised `send`) and the deferred answer only, **never** `ask`; a server-to-client request the preview needs (the progress token, §2.5) is issued by the dispatch thread when it enqueues the job | WP-5 |

### 2.4 The render session, concretely

| Item | Decision | Evidence |
|---|---|---|
| Construction | `new Runner(RunnerConfig(roots = ermine.moduleRoots ++ inferredRoot(uri) ++ roots, run = delegatingRun, scanner = scannerFor(profile)))` on the preview thread, on the first `ermine/render` (lazy: no profile read, no driver class, no connection before then) | `Runner.scala:171-179`; resident roots at `Main.scala:106-117`. Passing `run` explicitly avoids the default `Runners.liteDB`, which is a `def` (`Backends.scala:39`) forcing the `lazy val` `DB.sqliteTestDB` (`DB.scala:140`) and loading the SQLite driver (`Runner.scala:174`) |
| Roots | `moduleRoots` (the resident's own, so both sessions register equal shapes, §2.2), then the picked report's **inferred root** (the server derives it as `checkFile` does: parse the header, walk up one directory per extra segment of the module name, `Resident.scala:428-434`), then `ermine.preview.roots` -- `type: array of string`, `scope: "resource"` (*external*: per-folder), default `[]`, resolved by the extension against the workspace folder that owns the picked report (`getConfiguration("ermine", folderUri)`, *external*) and sent as **absolute** paths in every `ermine/render`, because a relative root would resolve against the server's cwd (`Main.scala:102-104`), which is `server.root` (`extension.js:151`). Distinct, then the classpath (`Runner.scala:313-316`). A single-segment module anywhere previews with **no setting**; empty means "the report's own tree and the stdlib". A change to the set **discards the `Runner`**: roots are immutable config (`:171`) | |
| Reads saved files, not buffers | `Runner` loads through `Session.SourceFile.filesystem` (`:315`); the resident's checks read open buffers (`Resident.scala:397-400`) but the resident env itself loads from disk too | the preview follows **saves**; the panel says so with an "unsaved: Chart.e" hint (§5) |
| Always typechecks | `Runner` is `_typeCheck = Some(true)` (`Runner.scala:288`) and must be: `Session.eval` infers the report's type (`Session.scala:830`) and `Decode.reportSignature` consumes it (`Runner.scala:464`). `ermine.fastMode` skips the typecheck in **checks** only (`Main.scala:65-70`), so in fast mode a type error has no squiggle and the preview shows a 500 "module does not load": the banner is the only diagnostic, and says so (§5) | |
| Foreign tolerance OFF | `Runner` leaves `_foreignTolerant` unset -> default off (`SessionState.scala:130`) | a module with an unresolved foreign binding is a warning plus a stub in the editor (`Session.scala:1405-1411`) and a load failure in the preview (500 banner, §5). That is `bin/ermine-serve`'s behaviour, i.e. the deploy shape; stated, not hidden |
| Report cache | keyed by `(module, binding)`; `compile(module, binding)` evaluates the bare binding name as today (`Runner.scala:445`, `:458`); `cfg.reportName` stays the default for `bin/ermine-serve`'s route | `:296`, `:411-420`, `:445`, `:458`, `:485`, `:541` read `cfg.reportName` today |
| `plans` | unused: every render is `Delivery.Inline`, `Strategy.Buffered`, no threshold, so no deferred token is minted | `Runner.scala:293-294`, `:72-80` |
| Profile switch, roots change, connect / disconnect / recycle | connect, disconnect and recycle inside one profile swap the target of `delegatingRun` (a `RunDB` whose `run` forwards to a `@volatile` current `Run[DB]`), no `Runner` change. A switch of profile, or of `ermine.preview.roots`, runs the sequence in §7.2: disconnect, **discard the `Runner`** (`RunnerConfig.run`/`scanner`/`settings`/`roots` are immutable case-class fields, `:171-179`), which evicts `reports` and the compiled closure with it, connect, re-render (a new boot, unmeasured seconds, with progress) | |

### 2.5 One render in flight, what a timeout can do, what cancel means

| Rule | Mechanism |
|---|---|
| **One in flight, at most one queued, latest wins** | the preview thread's queue holds jobs `boot`, `invalidate(paths)`, `render(id, uri, binding, params, roots, generation)`, `schema(id, module, binding)`, `connect`, `disconnect`, `discard`. A new `render` replaces a queued one, which is answered `-32800` (*external*: LSP `RequestCancelled`). The running one finishes. Ordering between jobs is queue order |
| Generation | every `render` carries the extension's `generation` counter and every answer echoes it; the extension discards an answer with an older generation than its current one (a render started on the previous profile finishes and is ignored, §7.2) |
| Fresh files, whoever saved them | at the head of every render the session runs `reloadStale`'s test (`Resident.scala:271-273`: `depCache(sf)._1 != sf.lastModified`) over its **own** `loadedFiles` -- one `stat` per loaded file, ~150 files, milliseconds -- and invalidates what moved, so edits from outside VS Code and clients without dynamic watchers (`Main.scala:214-217`) are seen without the watcher |
| The held connection is used by one thread only | so `DB.transaction`'s `setAutoCommit` toggling (`DB.scala:19-29`, called per scan from `SqlScanner.scala:193-195`) is never interleaved, and `fromPersistentConnection` handing every caller the same `Connection` (`Backends.scala:49-51`) is safe |
| A scan hang ends by itself | the existing 300 s `setQueryTimeout` (`SqlExecution.scala:50`) raises an `SQLException`; the render answers 500; the preview thread is free again |
| A non-terminating **evaluation** | pure Ermine loops run under `Runner.evalLock` (`Runner.scala:538-540`) and cannot be stopped from outside (*external*: `Thread.stop` throws on JDK 21). The honest promise: **a runaway evaluation blocks no LSP request until it exhausts the heap cap, then the server exits and the client restarts it**. A watchdog (`java.util.Timer`) answers the request after `ermine.preview.timeoutSeconds` (default 60) with "evaluation did not finish", in a notification carrying the **Ermine: Restart Language Server** button (`ermine.restartServer`, `extension.js:241`), marks the preview stuck, and every later `ermine/render` is answered the same way without queueing. An allocating loop (a fold over an infinite list; `swhnf` builds thunk chains as it goes, `Runtime.scala:215-238`) then hits `-Xmx` (§2.2) and `-XX:+ExitOnOutOfMemoryError` (*external*: since JDK 8u92) turns the OOM into a clean exit that `vscode-languageclient` restarts, up to 5 times in 3 minutes (*external*); the panel recovers as §7.2 describes. A CPU-bound loop pins one core for the process life until the user restarts. The resident keeps answering until then: it does not take `evalLock` and is on another thread. The watchdog exists so the user is told at 60 s rather than at OOM. WP-6 makes cancel real (next row) |
| Cooperative cancel (WP-6, gated on a perf A/B) | a `@volatile` cancel flag on a per-thread evaluation context, checked at the head of `Runtime.swhnf` (`Runtime.scala:215`): `if (cancelled) throw Cancelled`. The watchdog and an in-flight `$/cancelRequest` set it. The unwinding thunk writes `Bottom` back into the thunks on its chain (`:231`, `:238`), which poisons the render session's stdlib thunks, so a cancel **discards the `Runner`** (the next render boots a new one) and the runaway's chains become garbage; the resident is untouched. Cost: one volatile read per force on the evaluator's hot loop, hence a Tier-2 instrument run (`perf-bench.sh`, an interleaved A/B; it "has never moved", `docs/gate-policy.md:105`) before adoption. Unverified: that every Ermine loop passes through `swhnf` (a loop inside one primitive would not) |
| `$/cancelRequest` | queued: removed and answered `-32800`; in flight: marked, its eventual answer replaced by `-32800`, the work not interrupted until WP-6 (no hook into `SqlExecution` either way); during a boot: honoured when the boot ends (answer `-32800`, boot kept) |
| `stale` | a **hint**; `invalidated` is the mechanism. A `@volatile` generation counter is bumped by `invalidate`, snapshotted at render start and compared just before `send`; a mismatch sets `"stale": true`, and the `invalidated` notification that follows makes the extension re-render (§3). An `invalidate` that lands after the comparison is not lost, only its banner is late. **AS BUILT (WP-5 stage A), DIFFERS FROM THE LETTER ABOVE -- for the user to confirm**: the counter is bumped when an `invalidate` is **posted** (on the dispatch thread) and snapshotted when a render is **enqueued**, not when it starts. The literal reading cannot work on a single-threaded queue: an `invalidate` that ran as a job could never move the counter *during* a render, so `stale` would be dead code; and a snapshot taken at render *start* would call a render fresh that was enqueued before an invalidate still queued behind it. Bumping per post can flag a render whose invalidation turns out empty -- a false positive, which is what "a hint" permits. The WP-5 stage A review judged this strictly better than the literal reading |
| Boot progress | the first render, and every post-discard boot, reports "Ermine preview: booting the render session" through LSP work-done progress (`window/workDoneProgress/create`, then `$/progress` begin / end, `cancellable: false`, *external*: LSP 3.15+), guarded by the client's `window.workDoneProgress` capability. The `create` request is sent by the dispatch thread when it enqueues the job (§2.3); the `$/progress` notifications go from the preview thread through the synchronised `send` |

What a restart costs, stated once: a fresh process, the ~13 s boot (`Resident.scala:24`),
every per-document inference cache (cold first check ~2.5 s against ~0.9 s warm,
`editor/vscode/README.md:117-118`), the workspace-symbol table, the held connection and its
`##` tables (§7.2), and the compiled report. WP-5's done-when measures heap after a watchdog
fire for an allocating and a non-allocating loop and writes the figures here.

Dropped from earlier drafts, on this evidence: "never stalls diagnostics" is narrowed to
"never blocks the dispatch thread"; "cancellable" is narrowed to the rows above.

## 3. The loop: save -> reload -> invalidate -> re-render

| Step | Thread | What happens | Evidence |
|---|---|---|---|
| 1 | client | the `**/*.e` watcher the server registered fires for any `.e` in the workspace, stdlib or not | `Main.scala:199-208` |
| 2 | dispatch | `workspace/didChangeWatchedFiles` reloads the resident's own closure (unchanged) | `Main.scala:256-268`; `Resident.scala:251`, `:243-250` ("files the resident did not load ... are ignored here") |
| 3 | dispatch | `afterReload` (`Main.scala:179`), which both the watch handler (`:268`) and the `ermine.reloadModules` command (`:277`) call, posts `invalidate(changed ++ removed)` to the preview thread (a no-op before the preview has booted), so the manual reload path invalidates too | new |
| 4 | preview | `Runner.invalidate(paths)`, under `evalLock` (`TestRunner` runs properties concurrently over one runner, `TestRunner.scala:112`, `:806`): paths -> modules through the render session's **own** `loadedFiles` (`Session.Filesystem`, as `Resident.loadedByPath` does, `Resident.scala:178-183`) plus `Resident.moduleUnder(cfg.roots, p)` for a file restored after deletion (`:699-704`, `:262-265`); closure through `depCache` imports as `dependentsOf` does (`:186-197`); scrub the closure (§3.1); evict every `(module, binding)` key of those modules from `reports` (`Runner.scala:296`). **No eager reload**: the next render's `compile` loads on demand (`:432-436`) | new; because eviction is keyed on the render session's loaded set, a workspace report module (`Sales`) is covered -- the resident's reload set could never name it |
| 5 | preview | if the dirty set is non-empty: `ermine/preview/invalidated {modules}` | new |
| 6 | extension | if the picked report's module is in `modules` (the set includes dependents, so saving `Layout/Widgets/Foo.e` names every report that imports it), re-send `ermine/render` with the last params, and re-request the params schema (§6) | new |
| 7 | preview | render; answer; the panel repaints | §4 |

### 3.1 The scrub, shared

`Resident.scrub` (`Resident.scala:286-301`) removes a module set from an env down to its
builtin state, guarded by a post-preamble `builtins` copy (`:122`) so `Lib`-installed names
survive. `Runner.invalidate` needs the same ten lines and the same guard. WP-2 lifts `scrub`
and `dependentsOf` into `Session` (with the `builtins` env as a parameter) and makes `Runner`
take a `builtins` snapshot after its own `Lib.preamble` (`Runner.scala:318`); the resident
keeps calling the lifted versions at its four call sites (`scrub` at `Resident.scala:212`,
`:231`, `:461`; `dependentsOf` at `:208`), pinned by the existing C properties
(`TestLspRobustness.scala:554`, `:583`, `:655`).

### 3.2 Which report is rendered: selected by type, not by name

A widget module has no report of its own (`Layout/Widgets/*.e`, eleven modules today). The
panel renders **a report the developer picks**, and the unit of the pick is a
**(file, binding) pair**: any top-level binding whose type is a report type is previewable,
a module may declare several (`report`, `emptyReport`, `wideReport`, each with its own
params file, §6), and no binding name is privileged. Expecting a binding literally called
`report` is an artefact of the HTTP route `/report/<Module>` (`Server.scala:16`;
`Runner.scala:173`) and has no place in an editor.

**Ermine: Preview Report...** is two steps. First a file: `.e` files under the workspace
(`workspace.findFiles("**/*.e")`, *external*). Then a binding, from a new request
`ermine/preview/reports {uri}`, answered on the dispatch thread as a **lookup over the stored
document index**: the symbol tree `Definitions.index` builds on every check
(`Definitions.scala:1023-1026`, stored as `DocIndex.symbols`, `:103`) carries, per top-level
term group (`Symbols.termGroups`, `Symbols.scala:496-500`), the type the check inferred for
that spelling -- `TolerantCheck.types` first, the session's `termNames` for names a check
installs rather than binds (`Symbols.scala:156-157`, `:287`; `Sym.ty`, `:120`). The server
filters those symbols with the same test the runner applies to a compiled report:
`resultKind` (`Runner.scala:591-595`), made public, applied to the codomain after at most one
`->` (aliases expanded through the index's own `cons`, the check env's Con table,
`Definitions.scala:127`, `:1035`), and answers `{module, reports: [{binding, type}]}` with the
type rendered as hover renders it (`Pretty.prettyType`, `Symbols.scala:450`). The picker
shows `binding : type` and remembers the pair per workspace (`workspaceState`, *external*).
Two things this rests on, stated: a file with no index (never opened, never checked) is
checked once by the server for this request, from disk through `checkFile`
(`Resident.scala:401`, `:412-413`) and `Definitions.index` (`Definitions.scala:635`), a cold
check of ~2.5 s (`editor/vscode/README.md:117`) on the dispatch thread -- the one preview
request that analyses there, and it is a user command, not a navigation request; and the
filter is a candidate list, so the picker also accepts a typed binding name, and a binding
that is not a report is a 400 at render (`Runner.scala:466-470`). Neither
`workspace/symbol` (its `SymbolInformation` carries no type, `Symbols.scala:469-472`, and its
session globals exclude workspace modules, `:640-644`) nor a regex over the file's text
(`^report\s*:` finds one privileged name and misses a signature-less binding) is the
mechanism.

Saving a widget module re-renders the picked report through step 6 only if the report
imports the widget; if it does not, nothing changes and the status bar says "not used by
<Module>.<binding>". The harness for a new widget is therefore an ordinary report module
under a preview root -- `core/src/test/resources/doc/Sales.e` is one -- not a hidden
convention.

## 4. Wire

All new methods are `ermine/...`, beside `ermine/schema` (`Definitions.scala:226-228`).

| Method | Direction | Shape | Notes |
|---|---|---|---|
| `ermine/render` | request | `{uri, binding, params, roots, generation}` -> `{ok: true, document, generation, stale?}` or `{ok: false, status, message, path?, generation}` | `uri` -> module via `Resident.moduleUnder(cfg.roots, path)`; a file under no root is `404 "not under a module root"`; `roots` are the absolute `ermine.preview.roots` (§2.4). Delivery is always inline, buffered, no threshold (`Runner.scala:72-80`): **no `data` field on this wire**. `status`/`message`/`path` are `RunError`'s (`Runner.scala:25-65`: `BadRequest` 400 at `:47`, `NotFound` 404 at `:51`, `Failed` 500 at `:55`): 400 with a JSON path for a bad param or a binding that is not a report (`:466-470`, `:472-476`), 404 for module or binding (`:447`, with the request's binding in the text), 500 for load, eval, scan, write, and for a document over the size cap (§2.3). The message never carries a JDBC URL (§8, rule A5). Answered through `onRequestDeferred` from the preview thread |
| `ermine/preview/reports` | request | `{uri}` -> `{module, reports: [{binding, type}]}` or `{error}` | §3.2; dispatch thread; a lookup, or one cold check for an unopened file |
| `ermine/preview/invalidated` | notification, server -> client | `{modules}` | §3 step 5 |
| `ermine/schema` | request, extended | `{module, binding}` alongside `type`/`name` | **with a `binding` key the request is a preview-queue job** answered from the render session (§6); the `type`/`name` forms stay on the resident (`Schema.scala:807-816`) |
| `ermine/preview/connect` | request | `{profile: {id, dialect, driver, url, user?, scanner, settings}, password?}` -> `{ok: true, host}` or `{ok: false, class: "auth" \| "driver" \| "connect", kept, message}` | §8. The **body is never logged** (WP-1). Absent `user` means `DriverManager.getConnection(url)` (the local SQLite case) |
| `ermine/preview/disconnect` | request | `{}` -> `{ok: true}` | closes the held connection and discards the `Runner` (§7.2); the next render answers `{ok: false, status: 503, message: "not connected"}` until the extension connects again |
| `ermine/preview/disconnected` | notification, server -> client | `{reason}` | after a recycle or a failed scan that closed the connection; the extension reconnects (§7.2) |
| `$/cancelRequest` | notification | `{id}` | §2.5 |
| `window/workDoneProgress/create`, `$/progress` | request then notifications, server -> client | the LSP shapes (*external*) | §2.5 boot progress; the `create` from the dispatch thread through `ask`, the `$/progress` from the preview thread through `notify` |

`Rpc.scala` changes (WP-1), all in one file:

| Line (at a04f179c) | Change |
|---|---|
| `Wire.receive` logs the raw body before the method is known (`:318`) | the incoming log line moves to `Server.handle` after `Json.parse` (`:442-452`) and is `">> <method> [redacted]"` for methods in `Rpc.Redacted = Set("ermine/preview/connect")`; the unparseable branch (`:449`) keeps logging the parser's error only. That error never carries body text: the parser echoes at most one character (`Rpc.scala:121`) or a number token (`:144`), never a string. **Corrected at WP-1:** that was false as mined -- at a04f179c two escape errors (`Rpc.scala:166`, `:169`) quoted up to four characters from INSIDE a string literal (`bad \u escape 'ZZZZ'`, `bad escape '\q'`). WP-1 removed both echoes, leaving the offset, and pins the claim with a property (`TestLspRobustness`, A group): every quoted fragment is at most one character or a number token, and no two-character UPPER-CASE window of the input appears anywhere in the error. The second half is a marker check, not a check over every substring: every fixed word in a parser message is lower-case, so an upper-case pair can only have been echoed, while searching for arbitrary two-character substrings would falsify a sound parser on a collision with its own English ("of" inside "offset").  The property's own comment carries the alphabet argument |
| `Wire.send` (`:340-346`) | `synchronized`; the `<<` line (`:345`) is unchanged: no server-sent message carries a secret, and after §8's scrub none carries a URL or a host either |
| `Server.request` answers synchronously (`:471-481`) | `onRequestDeferred`; the property "A: the dispatcher answers every message in order, once, with the right shape, and runs to EOF" (`TestLspRobustness.scala:371`, and `:352-370` for what "in order" means once an answer is deferred) is extended to a deferred handler answering from another thread |
| `$/` dropped (`:488`) | `onNotification("$/cancelRequest")` is consulted first |
| nothing sends from a second thread | `notify` from the preview thread is legal once `send` is synchronised; `ask` stays dispatch-only (§2.3) |

The dispatch loop has **one** idle slot (`Rpc.scala:394-397`), taken by the diagnostics
debounce; the render watchdog therefore uses a `Timer` thread and the synchronised `send`,
not the idle slot.

## 5. The panel and the bundle

Decision (the user's): **webpack, watch-to-disk**; no `webpack-dev-server` (a webview cannot
load from it under its CSP, *external*).

| Item | Decision | Note |
|---|---|---|
| Node build | `tsc -p tsconfig.json` and `npm test` untouched (`client/package.json:12`, `:16`) | webpack is additive |
| Bundle | `entry: src/index.ts`, `ts-loader`, `target: 'web'`, `library: {name: 'ErmineClient', type: 'window'}`, output `client/dist/browser/ermine-client.js`, under the already-ignored `client/dist/` (`.gitignore:11`) | the host script reads `window.ErmineClient.parseDocument` etc. |
| `devtool` | `'source-map'` explicitly | *external*: `mode: 'development'` defaults to `eval`, which a webview CSP without `unsafe-eval` blocks silently |
| Host page CSP | `default-src 'none'; script-src ${cspSource}; style-src ${cspSource} 'unsafe-inline'; img-src ${cspSource} data:` | the legacy renderers inject styles |
| Legacy renderers | a second `<script>` from a second `localResourceRoots` entry at the `ermine-writers` checkout's built bundle; the host passes the global into `render`'s env, read as `ctx.env.htmlwriter` (`client/src/legacy.ts:327-333`) | without it `scorecard`/`headline`/`crosstab` render and `table`/`drilldownTable`/charts show the dispatcher's error box, the designed "unsupported" behaviour (`JSON-GUIDE.md:1648-1652`) |
| **The writers global** | **open (Q1)**: `client/src/index.ts:5` documents `window.htmlwriter`; the writers entry assigns `window.ermine_htmlwriter` (`../ermine-writers/writers/js/htmlwriter.js:11`) and the object `legacy.ts` types is `const htmlwriter = {}` (`ermine-htmlwriter.js:45`). Never observed in a real browser here | WP-11 |
| Host-page logic | the extension <-> webview message protocol (`render`, `error`, `stale`, `reloadBundle`, `unsaved`, `switching`, `offline`) is the only new logic on the client side; its state transition is a pure `applyMessage(state, msg)` in `client/src/host/`, built by the same webpack config and run under `node --test` beside `client/test/harness.ts` (`client/package.json:16`) | the DOM output of `parseDocument -> render` is already covered in jsdom; scroll, `retainContextWhenHidden` and panel lifetime are VS Code's behaviour, not ours; `@vscode/test-electron` downloads VS Code and is impossible offline (§10) |
| Initial state | before the first render: "Pick a report: **Ermine: Preview Report...**"; while a render runs: a thin progress bar, the last document kept | |
| Errors | `{ok: false}` -> a banner with `status`, `message`, `path`; the last good document stays below, dimmed. A load failure shows there **and**, for the same file, in Problems through the resident's own diagnostics (`Main.scala:188`) -- unless fast mode is on, when the banner adds "fast mode is on: type errors are not shown in Problems" (`config().get("fastMode")`, the same read as `extension.js:69-71`) and the preview status item carries the "(fast)" suffix | |
| Unsaved | a non-blocking hint "unsaved: Chart.e" in the banner area whenever a `.e` document in the workspace is dirty (`workspace.textDocuments.some(d => d.isDirty && d.languageId === "ermine")`, *external*): the preview follows saves (§2.4) and that must be visible, not documented. Rendering is never refused for it: a buffer closed without saving would leave nothing dirty and the hole open, and the two-file loop (widget module + renderer) is mid-edit as a normal state | |
| Stale | `stale: true` -> the banner "re-rendering" until the next answer | §2.5 |
| Switching | during a profile or roots switch (§7.2): the last document dimmed under "switching to `<id>`" | |
| Server stopped | on the client's `Stopped` state (`onDidChangeState`, *external*): banner "server stopped -- last document kept", status "Ermine: preview offline", the document dimmed. On `Running`: the reconnect flow of §7.2 and a re-send of the last render. Scroll and drilldown are lost, as for a bundle change (a hot restart, not a hot reload). By construction every input the loop needs -- picked (file, binding), params path, active profile id, last document, `generation` -- lives in the extension; the server holds nothing across a restart except the database | |
| Lifetime | `retainContextWhenHidden: true` (*external*; costs memory, keeps drilldown state); a bundle change re-sets `webview.html` and **loses** scroll and drilldown state -- accepted | |
| Bundle reload | `createFileSystemWatcher` on `client/dist/browser/ermine-client.js`, debounced ~200 ms (unverified atomicity of webpack's write), cache-busting query on the script URI, re-send the last document | |
| Bundle checklist | once per bundle-config change, by hand (jsdom cannot answer it): no console error under the CSP, `window.ErmineClient.parseDocument` present, `table` renders through the writers global | WP-9 / WP-10 done-when |
| Two windows | each window spawns its own `bin/ermine-lsp` (`extension.js:179`), hence its own preview session and its own held connection: two boots' memory (capped, §2.2) and two sets of `##` tables (§7) | stated, not solved |
| Multi-root | the server reads every folder's stdlib (`Main.scala:106-117`); the extension uses `folders[0]` for the server path only (`extension.js:43-46`). Profiles are user-scope (§8), so no folder question arises there; `ermine.preview.roots` and the params directory are per the picked report's workspace folder (§2.4, §6) | |

## 6. Parameters as files, with a schema, under the report's module

| Item | Decision | Evidence |
|---|---|---|
| Layout | `<workspace folder of the picked report>/.ermine/preview/<Module>/<binding>.params.json`, with `<binding>.schema.json` beside it: **a directory per module, a file per binding**. `<Module>` is the dotted module name from the file's header (`module Sales where`, `Sales.e:1`; the index's `moduleName`, `Definitions.scala:98`, which `ermine/preview/reports` also answers), used as one directory name, not split into a path, so `ls .ermine/preview` lists modules and `Layout.Widgets.Foo` is one entry | |
| Rejected layouts | a flat `<Module>.<binding>.params.json` is unreadable because module names contain dots (`Layout.Widgets.Foo.report.params.json` does not say where the module ends); one file per module keyed by binding is a merge-conflict surface, every report's params in one JSON object | |
| The committed file is the default | the params file is ordinary committed source: whoever clones renders the same first document. There is **no** defaults binding in the module (a `<binding>Args` convention would be another privileged name, rejected for the reason §3.2 gives) and no computed defaults: a rolling date range has to be literal JSON, and the honest place for that logic is the report itself -- for example a `Maybe Date` the report interprets as "today" when absent | `Sales.e:58-63` has four required fields |
| First pick | when no params file exists the extension writes a **skeleton from the schema**, ~40 lines, no dependency: walk the exported schema; required properties get `""` / `0` / `false` / the first `enum` value / today for `format: date` / `{}` recursively; optional (`Maybe`) keys are omitted. Wrong-but-typed values are a 400 with a path (`Runner.scala:473`, `:488`), which the file's squiggles already explain. The skeleton is written to disk for the developer to edit and commit | |
| Rename | renaming the binding orphans its file: the panel says "no params for `<binding>`" and offers the skeleton; the orphan is visible in `git status` and is the developer's to move or delete. Nothing fails silently | |
| Git | one `.gitignore` line, `**/.ermine/preview/**/*.schema.json`: only the generated schema is ignored; the params file is not | today's `.gitignore` has no `.ermine` entry |
| Saving re-renders | a watcher on the params file (`createFileSystemWatcher`, *external*) re-sends the last render with the new params | |
| Schema source | `ermine/schema {module, binding}` is a **preview-queue job** answered from the render session: `Runner.paramSchema(module, binding)` = `report(module, binding)` (`Runner.scala:411-420`, cached, under `evalLock`) then `Schema.exportType(rep.paramTy, module)` (`Schema.scala:184`; `Report.paramTy`, `Runner.scala:598`) under the render env. The schema is therefore exported from the **same** `paramTy` the decoder was compiled from (`:472-476`), so the params schema and the 400s can never disagree, and it queues behind renders like every preview job | the resident cannot answer it: `LspSchema.answer` runs on a resident copy whose loader chain is `moduleRoots` + classpath (`Schema.scala:807-810`; `Resident.scala:126-127`), preview roots exist only in the render session, so `Sales` would be module-not-found; and the binding mode *evaluates* a workspace module's top level, which §2.3 keeps off the dispatch thread. The existing `name` mode looks a **type** name up in `s.cons` (`Schema.scala:206-210`); a report's params type may be an alias from another module or an anonymous record, so a binding mode is needed. `Sales.e:107` happens to name it (`Query`) |
| Why it fits | params are required monomorphic and closed-row (`JSON-GUIDE.md:1218-1221`; `Decode.scala:99`, `:128`) | the describable fragment |
| Registration | the extension writes `<binding>.schema.json` beside the params file and puts `"$schema": "./<binding>.schema.json"` in the params file (*external*: VS Code's JSON language service honours a relative `$schema`). No write into the user's `json.schemas` setting | the extension strips `$schema` before sending, since every request key is closed (`Runner.scala:101-103`) |
| Refresh | the schema is regenerated on every `invalidated` that names the report's module | |

## 7. Backends: profiles and one held connection

### 7.1 Profiles

`RunnerConfig.backend(dialect, url)` (`Runner.scala:183-199`) is a closed five-way match that
pairs one `Run[DB]` with one `Scanner[DB]`, fixes the driver class per dialect
(`Backends.scala:33-37`), and puts the URL into its refusal string (`:198`). The preview does
not call it. A **profile** is the unit of configuration, under `ermine.preview.profiles` in
**user** settings only (§8):

| Knob | Values | Meaning |
|---|---|---|
| `id` | string | label for the status bar and the picker |
| `dialect` | `sqlite` / `mssql` / `mysql` / `postgres` / `vertica` (`Runner.scala:183`) | chooses the **emitter**: new `Backends.scannerFor(dialect, scanner)` returning `Scanner[DB]` only |
| `driver` | JDBC class name | default per dialect as `Backends.scala:33-37`; overridable |
| `url` | JDBC URL **without credentials** (rule A9) | |
| `user` | optional | present: `DriverManager.getConnection(url, user, password)`; absent: `getConnection(url)` |
| `scanner` | `default` / `noTransactions` | `Scanners.MicrosoftSQLServer` vs `MicrosoftSQLServerNoTransactions` (`Backends.scala:26-27`), unreachable from any command line today |
| `settings` | JSON object | the document's `settings` object |
| `deploy` | boolean | marks the profile whose dialect the badge compares against (§9.4) |

A built-in profile `local` = `{dialect: sqlite, url: "jdbc:sqlite::memory:"}` is the default
and needs no configuration. Because the connection is **held**, the in-memory database
persists across renders (a `create table` once is possible), unlike `bin/ermine-serve`,
whose `Run[DB]` opens and closes per request and starts empty every time
(`DB.scala:106-116`; `JSON-GUIDE.md:1577-1583`). For a scanning report (§0) the documented
alternative is a **file-backed SQLite**, a user profile with `url: "jdbc:sqlite:<path>.db"`,
filled by the developer with `sqlite3`, DB Browser or a script of their own: zero server
code, and the data outlives a restart and a recycle. There is **no seed-script mechanism**
(no `seed: [paths]` run on connect): whether such a fixture is committed, and where the file
lives, is the developer's choice, not the tool's.

### 7.2 Connection lifecycle -- who owns reconnection

| Rule | Mechanism |
|---|---|
| The server holds a `Connection`, never a password field | `connect` runs `Class.forName(driver)` then `DriverManager.getConnection(...)` on the preview thread, wraps the result in `Runners.fromPersistentConnection` (`Backends.scala:49-51`) and swaps it into `delegatingRun`. `lsp/Preview.scala` references the `password` string by nothing after the call. Stated, not mitigated: Java strings cannot be zeroed, and the driver's `Connection` retains its connection properties, password included, for reconnect and failover (*external*, mssql-jdbc) until it is closed -- the claim is true of the server's code and false of the heap |
| `DB.RunUser` is **not** the tool | it is a per-run reconnecting closure over the password (`DB.scala:129-138`, zero callers): it would hold the secret for the process's life and open a connection per render |
| Recycling is the **extension's** reconnect | after N renders or T idle minutes (defaults in WP-14, Q2), on **Ermine: Disconnect Database**, or after a scan closes the connection, the server closes it and sends `ermine/preview/disconnected {reason}`; the extension, which has `SecretStorage`, sends a fresh `connect`. The server never reconnects on its own |
| Every successful `connect` re-sends the last render | so a render that lands between `disconnected` and the new `connect` (answered `503 not connected`) is replaced without waiting for the next save. The trace-`verbose` refusal (rule A7) lives in the extension's **one** `connect()` function, so the unattended recycle path cannot bypass it; while refused, the status bar reads "disconnected: trace is verbose" |
| Temp tables | MSSQL temp tables are `##global` (`SqlEmitter.scala:621`); neither the SQLite nor the MSSQL emitter drops them (`EmitNoDropTempTable`, `:431-433`, mixed into both `:676-683`, `:834-849`; `cleanTempTables` is a no-op, `SqlScanner.scala:240-248`). With a per-request connection the server reclaims them at session end; with a held one they accumulate in `tempdb` until a recycle. Names are GUID-fresh (`SqlScanner.scala:305`), so the measure is a **count**, never a collision |
| Cursor leaks on a failing scan | closed at J3c: `withDriver` tears down in a `finally` (`relational/package.scala:136-142`) |

A **profile switch** is a sequence, not a sentence; every step is a preview-queue job, so
ordering is queue order and the in-flight render simply finishes first:

| Step | Who | What |
|---|---|---|
| 1 | extension | bump `generation`; an answer with an older generation is discarded (§2.5) |
| 2 | extension | status bar "switching to `<id>`"; the panel keeps the last document dimmed under a "switching" banner (§5) |
| 3 | extension -> server | `ermine/preview/disconnect` |
| 4 | server | close the connection; **discard the `Runner`** (§2.4), which evicts `reports` and the compiled closure |
| 5 | extension -> server | `ermine/preview/connect {profile, password?}` after the rule-A3 prompt if the secret is missing; the A7 refusal applies here as everywhere |
| 6 | extension -> server | on `ok`, re-send the last render (the new `Runner` boots lazily inside it, with §2.5's progress) |

The same sequence runs when any field of the **active** profile, or `ermine.preview.roots`,
changes (`onDidChangeConfiguration`, `extension.js:262`); a change to an inactive profile
does nothing. Steps 5-6 are also the recovery after a server crash or restart (§5, "server
stopped"): on `Running` the extension prompts only if the secret is gone, reconnects and
re-renders.

### 7.3 Driver

| Fact | Status | Evidence |
|---|---|---|
| `Runners.MicrosoftSQLServer` loads `com.microsoft.sqlserver.jdbc.SQLServerDriver` | MINED | `Backends.scala:34` |
| `build.sbt` ships mysql-connector-j, jTDS and sqlite-jdbc only, so `--dialect mssql` fails at `Class.forName` today | MINED, not run | `build.sbt:111-113`; `DB.scala:107`; `JSON-GUIDE.md:1587-1589` |
| jTDS is used only by `Runners.cloudDB` | MINED | `Backends.scala:41-43` |
| `mssql-jdbc` with the `jre11` classifier: one artifact | *external* (jre11 runs on 11+) | the server runs on JDK 21 (`build.sbt:1`; `bin/ermine-lsp:25`); the 2.11 back-port is out of scope |
| mssql-jdbc defaults `encrypt=true`; an internal CA fails the first connect; `-Djavax.net.ssl.trustStoreType=Windows-ROOT` via `ERMINE_JAVA_OPTS` (`bin/ermine-lsp:20`) is the usual bridge | *external*, **to verify in WP-12** (Q3) | this is why the auth failure classifier (§8.3) must not treat a TLS failure as a wrong password |
| `MsSqlEmitter.sqlPrimT` maps `"date"` by type name with the comment "jtds gives x = varchar for dates" | MINED | `SqlEmitter.scala:881-882`; written against a driver this design does not use; one real check in WP-12 |

## 8. Authentication (standalone; read this if you read nothing else)

Settled constraints: the work SQL Server does **not** accept AD authentication; integrated
auth / Kerberos are unavailable there and not proposed. **SQL auth (user + password) is the
path.** Local runs use SQLite with no credential. Work machines are Windows, and the
extension host runs on Windows (§10).

### 8.1 Rules

| # | Rule | Mechanism | Status |
|---|---|---|---|
| A1 | No password field anywhere in settings | the `contributes.configuration` schema for `ermine.preview.profiles` declares `{id, dialect, driver, url, user, scanner, settings, deploy}` and nothing else | design |
| A2 | Profiles are read from **user scope only** | `getConfiguration("ermine").inspect("preview.profiles").globalValue` (*external*); a workspace- or folder-scope value is ignored and named once in the output channel | design; see the threat model |
| A3 | The password lives in `SecretStorage`, keyed by `sha256(url + "\0" + user)` | `context.secrets.get/store/delete` (*external*, since VS Code 1.53; the extension already requires `^1.75.0`, `package.json:8-9`, `:98`). Prompt with `showInputBox({password: true})` naming the **host** and user; store only after `connect` answers `ok`. A changed URL or user is a new key and prompts again, so a stored secret can never be replayed against a host it was not typed for. Command **Ermine: Forget Database Password** deletes the key of the active profile. On Windows the store behind it is the OS credential store (*external*) | design |
| A4 | The secret travels over the existing stdio JSON-RPC channel, in `ermine/preview/connect` | `extension.js:145-151`, `:179` already spawn the server on stdio. Never a command-line argument: `bin/ermine-serve:32-33` forwards `"$@"`, which `ps` shows | design |
| A5 | The server never puts a URL, a host or a password in anything a client or a log sees | the URL is not logged and not answered: `connect` answers `host` only; `RunError` messages come from `Runner`, which never sees the URL under this design (the preview does not use `RunnerConfig.backend`, whose refusal string carries it, `Runner.scala:198`); the status bar shows `id (dialect) @ host`. The driver's own text is covered by A10 | design |
| A6 | The wire log never records the connect body | `Rpc.scala:318` logs every incoming body to `ERMINE_LSP_LOG` (`bin/ermine-lsp:4`, `:19`; set from `ermine.logFile`, `extension.js:145-146`; clipped at 2000 chars, `:360`, which is more than a connect). WP-1 redacts by method (§4). Redaction keys on the method, so the three shapes that have none are settled explicitly: a message that is not an object, and an object whose `method` is not a string, log **no body** (either could hide a connect, e.g. `[{"method":"ermine/preview/connect",...}]`); a message with no `method` at all is a REPLY to one of our own `ask`s and **is logged in full**, by design. That is safe only while no reply can carry a secret: today the tree has exactly one `ask`, `client/registerCapability` (`Main.scala:203`, LSP-STALENESS step 2), and its reply carries a registration outcome the handler reads as `error` present or absent (`Main.scala:209-212`, the match; the continuation opens at `:208` and closes at `:213`) -- nothing a client would not already know. **Any future `ask` whose reply could carry one must extend the redaction**, which then needs the request-id-to-method map that resolution A5(iii) judged unnecessary | **DONE (WP-1)**; the rule binds WP-13 |
| A7 | The client trace never records it either | `ermine.trace.server` (`package.json:63-72`) at `verbose` logs request params to the output channel (*external*, vscode-languageclient). The extension **refuses to connect while the trace is `verbose`** and says why, in its one `connect()` function so the recycle path is covered (§7.2); `messages` and `off` log method names only (*external*) | design |
| A8 | After one authentication failure, no stored password is retried without a new prompt | §8.3 | design |
| A9 | No credentials inside the URL | before `connect` the extension refuses a `url` matching `/(^\|[;?&])\s*(password\|pwd\|user\|userName\|integratedSecurity\|authentication)\s*=/i` (*external*: mssql-jdbc property names) with "credentials belong in `user` and the prompt". This closes the Settings-Sync path (T2) at the only place the URL enters | design |
| A10 | Every driver message is scrubbed at the source | the connect handler catches `Throwable` (not `NonFatal`: an `ExceptionInInitializerError` from a driver's static initialiser is a `LinkageError`), never rethrows, and builds every answered message as `e.getClass.getSimpleName + ": " + scrub(msg)` where `scrub` replaces the profile's `url`, `user` and the URL's host with `<url>`/`<user>`/`<host>`; classification reads `getSQLState`/`getErrorCode` only (the shape `SqlScanner.scala:190` already renders). `Server.request`'s crash path (`Rpc.scala:478-480`, which logs the stack trace and answers `method + " failed: " + e`) is unreachable for `connect`, and the `<<` log line needs no redaction because nothing secret is ever in the answer. The predicted case: `DriverManager.getConnection` with no driver accepting the URL throws "No suitable driver found for <url>" (*external*, JDK), the full URL, on the first typo in `jdbc:sqlserver://` | design |

Precedent, cited not measured: Microsoft's `vscode-mssql` keeps connection profiles in
settings without the password, the secret in the OS store, and hands it to a separate
tools-service process over JSON-RPC stdio (*external*). It shows driver messages verbatim,
which is fine when the profile is in settings anyway; this design copies its secret-store
split, not its message handling.

### 8.2 Threat model

| Adversary | What they can reach | What stops them | What does not |
|---|---|---|---|
| T1 another account or process on the same machine | files under the checkout; the process list | A1 (settings carry no password); A4 (no argv); A6/A7/A10 (no log); `git add -A` after A6 finds nothing to leak | a heap dump or a debugger attached to the JVM (not addressed) |
| T2 synced settings | whatever Settings Sync carries | A1: the synced profile is url + user only, and A9 keeps a password out of the url. Whether `SecretStorage` is synced is *external* and **unverified**; the design assumes it is machine-local and WP-13's done-when records the answer here | |
| T3 an authored workspace (a colleague's repo with a committed `.vscode/settings.json`), trusted or not | any workspace-scope setting | A2: workspace profiles are ignored. A3: even a user-scope profile edited to another host has no secret under the new key; the prompt names the host. **The extension is not activated in Restricted Mode**, so no server and no preview run there (next paragraph) | `ermine.serverPath` (`package.json:43-47`; `extension.js:49-51`) already lets a workspace choose the executable the extension spawns -- a larger, pre-existing hazard; in a trusted workspace it is the user's trust decision, and this document says so rather than pretending the JDBC URL is the risk |
| T4 other extensions in the host | | `SecretStorage` is per-extension (*external*) | |
| T5 the log files | `ERMINE_LSP_LOG`, the output channel | A6, A7, A10, verified by the gate in 8.4 | |

Today the extension declares no `capabilities.untrustedWorkspaces` (grep, 0 hits), so it is
not activated in Restricted Mode at all (*external*); "the preview is off in an untrusted
workspace" is therefore already true and **stays true: the declaration stays absent.**
Declaring `supported: "limited"` would *activate* the extension there with only the named
settings blanked, and the server path is not only a setting: `resolveServer` falls back to
`<first workspace folder>/bin/ermine-lsp` (`extension.js:52-54`), spawned with
`cwd: server.root` (`:148-151`), so Restricted Mode would execute the untrusted repository's
own shell script as the language server -- a regression `restrictedConfigurations` cannot
reach, because it protects a *setting*, not a path derived from the folder. Nothing the
extension offers works without the server, so `limited` would buy nothing; the TextMate
grammar is a static contribution and keeps working (*external*, unverified). Should someone
later declare `limited` for another reason, `startClient` (`extension.js:126`) must first gate
on `vscode.workspace.isTrusted` and resume on `onDidGrantWorkspaceTrust` (*external*).

### 8.3 Failure classification

`connect` classifies on the driver's exception and answers a `class` and a `kept` flag;
`SqlScanner` already renders `getErrorCode`/`getSQLState` (`SqlScanner.scala:189-190`), so
both are available.

| Class | Signal | Extension does | Secret |
|---|---|---|---|
| `auth`, `kept: false` | `SQLException` with SQLState `28000`, or vendor error `18456` for SQL Server (*external*, mssql-jdbc's login failure) | shows the scrubbed message once; **deletes** the secret; marks the profile "prompt next time"; does not retry until the user renders again | deleted |
| `auth`, `kept: true` | vendor errors `18486` (account locked), `18487` (password expired), `18488` (must change) (*external*: corroborated by Microsoft's documentation and an Azure Data Studio issue, not by a driver run) | shows the message naming the reason; marks "prompt next time"; **never** an unattended retry, so a recycle cannot keep a locked account locked | kept |
| `driver` | `ClassNotFoundException` from `Class.forName`, or "No suitable driver" (the URL prefix matched no registered driver: a configuration error, not a network one) | shows "driver <class> not on the classpath (WP-12)" or "no driver accepts this URL" | kept |
| `connect` | every other exception: TLS (`encrypt=true` against an internal CA, §7.3 -- the failure this design predicts on the **first** connect), DNS, refused, timeout | shows the scrubbed message; no re-prompt; the stored password is kept because it was never rejected | kept |

Pinned with a fake `java.sql.Driver` registered in the test JVM (*external*:
`DriverManager.registerDriver`) that throws an `SQLException` with SQLState `28000` for one
URL, vendor code `18487` for a second, a plain `SQLException` whose message contains the URL
for a third, and accepts nothing for a fourth: the classifier answers `auth/false`,
`auth/true`, `connect` and `driver` respectively, never `auth` for the third, and the third's
message is answered with `<url>` while the log has 0 hits for the URL and the host (WP-13).

### 8.4 The credential gate

Run once, with `ermine.logFile` set **and** `ermine.trace.server` at each level:

| Setting | Expected |
|---|---|
| `verbose` | the extension refuses to connect; grep of the output channel for `preview/connect` finds the refusal line only, no request |
| `messages` + log file | connect succeeds; grep of `ERMINE_LSP_LOG` and of the output channel for the password: 0 hits; grep for the JDBC URL and for the host: 0 hits; `settings.json` has no password |
| wrong password | class `auth`, `kept: false`; the secret is gone from `SecretStorage` (`secrets.get` is `undefined`); the next render prompts |
| a URL no driver accepts | class `driver`; grep of the log and the output channel for the URL and the host: 0 hits; the secret is still stored |
| a URL carrying `password=` | refused by the extension before any request; nothing in the log |
| TLS failure (WP-12's first connect, if it happens) | class `connect`; the secret is still stored |

## 9. Dialect fidelity

No test in this repository executes the same relation against two dialects:
`core/src/test/scala/com/clarifi/reporting/sql/TestSqlEmitters.scala` compares emitted SQL
**strings** (grep for `scanRel`, `Run[DB]`, `DriverManager`, `getConnection`: 0 hits);
`Profiler.scala:281-295` names MySQL, SQL Server and Vertica but is a hand-run `object`
(`:37`). Every row below is MINED from `sql/SqlEmitter.scala` and `relational/SqlScanner.scala`.

`SqliteEmitter` mixes in 7 traits (`SqlEmitter.scala:676-683`), `MsSqlEmitter` 15
(`:834-849`); 5 are shared. Production is MSSQL.

### 9.1 Emitter gaps: SQLite could run these, the SQLite emitter does not emit them -- fixable

| Feature | SQLite emitter today | MSSQL emitter | Fix | Why it is an emitter gap |
|---|---|---|---|---|
| window functions (`Relation/Windowed.e:31`) | base `emitOver` splices `"TODO I don't yet know how to play %s over %s"` **into the SQL** (`:269-271`); `LOOP-MODEL-PLAN.md:249` (iii) calls it a silent wrong answer | `EmitOver_UsingOver` (`:538-558`), mixed in at `:843` only | `class SqliteEmitter ... with EmitOver_UsingOver` | `tracker/tools/tsql2sqlite.py:10-12`: SQLite "supports OVER(...) since 3.25" and E1 ran windowed reports on SQLite that way (*external* fact, recorded in-repo; sqlite-jdbc `3.51.1.0`, `build.sbt:113`, bundles a newer engine, *external*) |
| column names needing quoting | `emitColumnName(s) = s` (`:38`) | `[s]` (`:616-617`) | a bracket-name trait for the SQLite emitter (not `EmitName_MsSql`, which also renames temp tables to `##`, `:615-629`) | `tsql2sqlite.py:10`: "SQLite accepts [bracket] identifiers" |
| non-left-deep joins | `emitJoinOn` emits both operands bare (`:253-263`) | accepted | parenthesise the right operand | `LOOP-MODEL-PLAN.md:249` (iv): SQLite's flat join grammar rejects it |

`TestSqlEmitters` compares strings, so each mixin is pinned for free (WP-15).

### 9.2 Engine gaps: SQLite lacks the function -- refuse, do not splice

| Feature | SQLite path today | MSSQL | Failure mode today |
|---|---|---|---|
| `dateAdd` (`Relation/Op.e:144`) | `sys.error("todo - sqlite dateadd function")` (`:699-701`) | `dateadd` (`:877-879`) | a Scala exception, loud |
| `dateDiff` (`Op.e:160`) | `FunSqlExpr("datediff", ...)` for every dialect (`SqlScanner.scala:110`) | same text | SQLite has no `datediff` (*external*): SQL error at scan |
| `stddev` / `variance` (`Relation/Aggregate.e:29-30`) | `STDDEV_POP`/`STDDEV_SAMP`/`VAR_POP`/`VAR_SAMP` (`:328-348`) | `STDEVP`/`STDEV`/`VARP`/`VAR` (`:606-612`) | SQLite has none built in (*external*): SQL error |
| `tryCast` null-on-fail (`Op.e:65`) | `emitTryCast(true)` splices `"TODO I don't yet know how to write try_cast"` (`:276-278`) | `TRY_CAST(` (`:597-599`) | **silent wrong answer** |
| stored-procedure relations | `" exec "` (`:191`) | same | no procedures in SQLite (*external*) |

Mitigation: a typed `UnsupportedOnDialect(feature, dialect)` thrown by the base `emitOver`
(after 9.1 makes SQLite inherit `OVER`), `emitTryCast(true)`, the SQLite `emitDateAddName`,
and the `datediff`/stddev sites on emitters that lack them; `ermine/render` answers it as a
500 whose message names the feature and the dialect, and the panel shows it as a banner.
No emitter output ever contains `TODO` afterwards (WP-16).

### 9.3 Same query, different rows, no error either side (best-effort; stated in the badge)

| Construct | SQLite | MSSQL | Consequence |
|---|---|---|---|
| concatenation with NULL | `a \|\| b` (`:321`) | `Concat(a, b)` (`:573-575`) | `NULL` vs `''` (*external* engine semantics) |
| integer division of negatives | bare `/` (`:356`) | `floor(floor(a) / floor(b))` (`:631-635`) | truncation vs floor (*external*) |
| `GROUP BY` / `DISTINCT` on strings | engine default collation | server collation, commonly case-insensitive (*external*) | group counts differ; nothing in the emitter controls collation |
| `Date` literal | epoch milliseconds, `d.getTime.toString` (`:696`), column type `integer` (`:724`) | `'yyyy-MM-dd'` (`:199-201`, `:211`) | time-of-day survives on SQLite only |
| `Timestamp` | formatted string into an `integer` column (`:203-205`, `:725`) | `CAST('...' AS DATETIME2)` (`:860-862`) | unverified how SQLite stores it |
| nullability, string length | never `not null`; `text` without length (`:716-727`, `:717`) | `nn` appends ` not null` (`:864`); `nvarchar(<l>)`, `1000` when unspecified (`:866-867`) | the preview accepts what production rejects |

### 9.4 What this decides

For the widget/parameter surface the rows are inline and the preview is faithful in shape;
values differ only where 9.3 applies. For relation authoring the honest tool is an MSSQL
profile (§7). The status bar shows a **"preview dialect != deploy dialect"** badge whenever
the active profile's emitter differs from the `deploy: true` profile's (WP-16). The dual-emit
diff (render answering the SQL it ran via `dumpRel`, `SqlScanner.scala:281`, beside what the
deploy emitter would run via `dumpClosed`, `relational/Scanner.scala:44-45`) is
query-authoring tooling, not part of the loop: **optional, last** (WP-19).

## 10. Closed-environment constraints

| Constraint | Consequence |
|---|---|
| No internet in the loop | no CDN script in the webview; `client/node_modules/` is gitignored (`.gitignore:9`) and absent here, so `webpack`, `ts-loader` and their closure need a vendored copy or an internal registry |
| Driver artifact | `mssql-jdbc`, classifier `jre11` (§7.3), in the offline Ivy/Coursier cache before `sbt` resolves; `bin/ermine-lsp` rebuilds its classpath cache when `build.sbt` is newer (`bin/ermine-lsp:12-16`, same as `bin/ermine-serve:21-27`) |
| Every launcher is bash | `bin/ermine`, `bin/ermine-lsp`, `bin/ermine-schema`, `bin/ermine-serve`; the default server path is `bin/ermine-lsp` under the first folder (`package.json:43-47`; `extension.js:49-55`). **Windows gets native `.cmd`/PowerShell wrappers** (`bin/ermine-lsp.cmd` at least, doing what `bin/ermine-lsp:12-31` does: the classpath cache, `-Dermine.lsp.log`, the heap cap of §2.2, `ERMINE_JAVA_OPTS`); `resolveServer` picks the wrapper when `process.platform === "win32"` (*external*). No WSL |
| Consequences of a Windows host | the extension host stays on Windows, so `SecretStorage` is backed by the OS credential store (*external*) and the JVM truststore is the Windows JDK's (`Windows-ROOT`, Q3, §7.3). Portability note, not a live question: on a Linux host `SecretStorage` is backed by the keyring (*external*) and the truststore by that JDK's `cacerts` |

## 11. Testing

`tracker/GATE-POLICY.md` is superseded (`:1-3`) by `docs/gate-policy.md`: tiers `commit`
(compile, corpus, lsp; ~2.5 min, budget 3 min), `pr` (+ `suites` = full `core/test`, lean;
20 min), `nightly`; "a new gate enters at `nightly` and moves up on evidence"
(`docs/gate-policy.md:52-56`, `:87-92`); environment-dependent checks are instruments, not
gates (`:28-29`, `:98-101`). No gate below exceeds 20 min, so nothing needs the user's
approval under `:91`. Each WP done-when in §14 names its tier.

| Layer | Where | Properties (each is a WP done-when) | Tier | Cost per run |
|---|---|---|---|---|
| Wire / dispatcher | `TestLspRobustness` A-group | a deferred handler answering from another thread still yields "every message answered in order, once" -- the synchronous answers keep their positions and every deferred one is answered exactly once, in any order; two threads calling `send` concurrently produce frames a `Wire` reads back intact; a body for a redacted method never appears in the captured log, an unredacted one does, and neither a JSON array nor a non-string `method` logs a body either; a parse error quotes at most one character of the input or a number token, and no two-character upper-case window of the input appears in it (the marker check of §4), with the same claim re-checked through `Server.handle` on an unparseable frame carrying a secret; `$/cancelRequest` reaches a registered handler while other `$/` notifications are dropped with no answer and no `ignoring notification` line (they do get the ordinary `">>"` line, like every other incoming message) | `suites` (**pr**): `scalacheck-binding/src/main/scala` is in core's test sources (`build.sbt:88-90`) | seconds |
| Registration flag | group D in `TestLspRobustness` | check a buffer whose `data Heading` gained a field; `DataConDecl.forConstructor(Global("Sales", "Heading"))` still has four fields | **pr** | seconds |
| Render session | group D, under `residentLock` as B/C are (`:34`, `:307`) | render `Sales.report`; mutate the report file; `invalidate`; render again: the document differs. Mutate a **widget** module the report imports: the report is in the invalidated set. Render a module whose evaluation throws: the resident still answers a check (`Resident.checkFile`, `Resident.scala:401`) and the next render works. A `$/cancelRequest` for a queued render answers `-32800` and the queue is empty. `ermine/schema {module: "Sales", binding: "report"}` from the queue equals `exportNamed("Sales", "Query")` under the render env. `ermine/preview/reports` on `Sales.e` lists `report : Query -> Node` and nothing else | **pr**; group D boots a render session, seconds each, MEASURED in WP-5 and kept under 60 s total or the suite is split | seconds to a minute |
| Runner | `TestRunner` (`:112`, `:806` already runs properties concurrently over one runner) | `invalidate` of an unloaded path is a no-op; `invalidate` then `render` reloads the module (loaded-set delta); two report-typed bindings in one module render two documents; `new Runner(cfg)` with an explicit `run` loads no JDBC driver (`CountingRun`, `TestRunner.scala:77`) | **pr** | seconds |
| Emitters | `TestSqlEmitters` | the SQLite string for a windowed relation contains `over (`; no emitter output contains `TODO`; `UnsupportedOnDialect` for `tryCast` on SQLite | **pr** | seconds |
| Classifier | new, with a fake driver | §8.3 | **pr** | seconds |
| End to end | `tracker/tools/lsp-client.py`, run by `tracker/tools/lsp-smoke.sh` (`scripts/gates.sh:115-120`) | `reports`, render, edit, `invalidated`, render: differs; the schema binding mode on `Sales` (domain is `Query`) | `lsp` (**commit**): adds one preview boot to a 44 s gate; if the gate passes ~90 s it moves to `pr` under the 3-minute budget | ~1 min |
| Host page | `client` `npm test` (the existing harness plus the `applyMessage` reducer, §5) | every message sequence the extension can send leaves a consistent state (no document and a banner, or a document and its dimming flag) | new `gate_client` in `scripts/gates.sh`, entering at **nightly** per policy; promotion after one recorded catch | seconds |
| Instruments | results written into this document, never gate evidence | the credential gate (§8.4); the `##` count (`tempdb.sys.tables`) after an hour and after Disconnect; RSS and boot seconds before/after preview boot (§2.2); heap after a watchdog fire (§2.5); the bundle checklist (§5); the `perf-bench.sh` A/B for WP-6 | none | human / machine-dependent |

## 12. Alternatives rejected

| Alternative | Why |
|---|---|
| Drive the loop off `bin/ermine-serve` | a JVM boot per `.e` edit (`Runner.scala:411-420`; `JSON-GUIDE.md:1452-1453`); no host page, no CORS (`JSON-GUIDE.md:1593-1603`); a credential would be an argument (`bin/ermine-serve:32-33`) |
| A dev server (static route + CORS + `webpack-dev-server`) | a second process, a second cache to invalidate, a webview that cannot load from it (*external*) |
| Options (A) and (B) of §2.1 | see the table |
| A separate render process | reopens the settled second-session decision; the heap cap and the restart path cover what it would buy |
| Reuse `Session.reloadChangedModules` for invalidation | its dirty set is the process-global `depCache` (`LSP-STALENESS.md:36-40`) |
| Refuse to render while any `.e` buffer is dirty | does not close the registry hole (a buffer closed unsaved leaves its shape registered and nothing dirty) and would block the two-file loop's normal state (§5, "unsaved") |
| A per-session constructor index now | the right long-term shape, a day of work through every JSON test; the registration flag closes the hole in ten lines (§2.2) |
| `ermine/schema {binding}` answered by the resident with the preview roots appended to its chain | workspace report modules would enter the resident (`LSP-STALENESS.md:40`) and the binding would be evaluated on the dispatch thread (§6) |
| A privileged binding name (`report`), found by a `^report\s*:` regex | one report per module, one spelling, a signature-less binding missed; the picker lists by type (§3.2) |
| A defaults binding (`<binding>Args`) seeding the params file | another privileged name; the committed params file is the default (§6) |
| A stdlib record type for previews | new surface; a report-typed binding already is the unit |
| Flat `<Module>.<binding>.params.json`; one params file per module | §6 |
| Seed SQL files run on connect | no seed mechanism; a file-backed SQLite the developer fills is enough (§7.1) |
| `capabilities.untrustedWorkspaces: limited` | activates the extension in Restricted Mode and spawns the untrusted checkout's `bin/ermine-lsp` (§8.2) |
| Redact the `<<` log line per request id | unnecessary once every answered message is scrubbed at the source (A10); adds state to `Rpc.scala` |
| WSL for Windows machines | native wrappers keep the extension host, the secret store and the truststore on Windows (§10) |
| `DB.RunUser` for credentials | holds the password for the process's life and reconnects per run (§7.2) |
| A password field in the profile; integrated auth | §8 |

## 13. Open questions (none blocks WP-1..WP-6)

| # | Question | Blocks |
|---|---|---|
| Q1 | which global the writers bundle puts on `window` (`htmlwriter` vs `ermine_htmlwriter`) | WP-11 |
| Q2 | recycling defaults (renders / idle minutes) for a held MSSQL connection | WP-14 |
| Q3 | is `Windows-ROOT` needed, or is the internal CA in the JDK's `cacerts` | WP-12 |
| Q4 | how a module whose LOAD FAILED is invalidated once it is fixed | WP-7 |
| Q5 | §2.4 and §4 disagree: the 404 "not under a module root" is unreachable for a readable file | nothing; decide before WP-7 |
| Q6 | a roots change discards the `Runner`, and the inferred root is part of the roots, so previewing two reports in two directories re-boots the render session each time | nothing; decide before WP-7 |

**Q4, in full** (found by the WP-4 review, 2026-09-20). A module that failed to load is in
neither `loadedFiles` nor `loadedModules`, and `Runner.invalidate` derives its module set from
exactly those two (`json/Runner.scala`, step 1 of its doc comment: `Session.loadedByPath`, then
`Session.moduleUnder(cfg.roots, p)` filtered by `loadedModules`). So after a render answers 500
"module does not load", saving the fix invalidates NOTHING: `invalidate` answers the empty set,
no `ermine/preview/invalidated` goes out (§3 step 5 sends nothing for an empty set), the
extension never re-renders (§3 step 6), and the panel keeps the 500 banner until the user picks
the report again. The same is true of a file the broken module imports. The resident meets the
same shape and compensates with a `pendingReload` set -- the modules a reload scrubbed and could
not load back, retried by the next reload (`lsp/Resident.scala:179`, `:182`, `:197`, `:219`);
`Runner` has no equivalent, because until WP-4 it never scrubbed. Options, none built:
(i) a `pendingLoad` set in `Runner`, named by every `compile` that fails, returned by any
`invalidate` whose paths name a module under a root whether or not it is loaded -- the resident's
answer, in the runner; a `Runner` change, so a **follow-up to WP-4**;
(ii) the extension re-renders on ANY `.e` save while its last answer was a load failure -- no
server change, one wasted render per save in the broken state; lands in **WP-7**, the extension;
(iii) the server sends `invalidated` for every watched change while the last render failed to
load -- the same rule, moved to the server, where it knows what "the last render" was; lands in
**WP-5**, the `Preview` object that owns the queue and the notification.
Whichever is chosen, the loop only closes in the extension, which is why the table says WP-7.
It does not block WP-4 or WP-5: `Runner.invalidate` is exactly as specified in §3 step 4 and
§11's Runner row ("`invalidate` of an unloaded path is a no-op") stays true whichever option
wins -- (i) would make a *failed* module no longer count as unloaded, which is a change to what
is loaded, not to the rule.

**Q5, in full** (found while building WP-5 stage A, 2026-09-20). §2.4 puts the picked
report's **own inferred root** in the render session's root set, and §4 promises
`404 "not under a module root"` for a file under none of them. Together these cannot both
bite: any readable file whose header parses is, by construction, under the root its own
module name implies, so the 404 is unreachable for it. **As built**: both, literally. The
404 therefore fires exactly when no root can be **inferred** -- an unreadable, non-existent
or unparseable file (a report the developer deleted while the panel still points at it), or
a path that is not a `.e` file at all. That is a real case and the group-D property pins it,
but it is not what §4's sentence sounds like. Options, none built: (i) reword §4 to say what
the 404 means (no root could be inferred and none was configured); (ii) drop `inferredRoot`
from §2.4 and require `ermine.preview.roots` for anything outside `moduleRoots`, which makes
the 404 mean what it says and costs every single-segment module a setting -- the thing §2.4
added `inferredRoot` to avoid. It blocks nothing: WP-7 is where the picker decides what to
send, so the answer is wanted before that.

**Q6, in full** (same origin). §2.4 makes the root set immutable config and says a change to
it **discards the `Runner`**; `inferredRoot` puts the picked report's own directory in that
set. So previewing report A in one directory and report B in another discards and re-boots
the render session on every switch, in both directions, for ever. **MEASURED**: 2.3-7.3 s per
boot for the group-D fixture (`TestLspRobustness`, the render-session group's own `collect`
label across four runs), which loads `Lib.preamble`, `Layout.Doc` and `Layout.Fetch` over the
stdlib source root. A real workspace's report is **unmeasured** and will be slower. Options,
none built: (i) accept -- a developer works on one report at a time, and the panel shows
progress (stage B); (ii) keep a small map of `Runner`s keyed by root set, evicting the
least-recently-used, which multiplies the memory of §2.2 by however many are kept;
(iii) drop `inferredRoot` from the **discard key** while keeping it in the roots -- unsound
as stated, because the runner's loader chain really is different, so it would mean rebuilding
only the loader, which `RunnerConfig` does not allow today.

## 14. Tickets, in dependency order

Every ticket lands on `widget-preview` in `ermine-scala-wt-widget-preview`. Costs are
estimates from the shape of the change, not measurements; tiers are `docs/gate-policy.md`'s.

**This table is authoritative for ticket numbers.** `JSON-WIDGET-PLAYGROUND-RESOLUTIONS.md`
numbers them differently, and the offset is not constant: its own table
(`RESOLUTIONS:380-392`) INSERTS two tickets, `WP-2b NEW` (`:384`, `_registerDecls`) and
`WP-4b NEW` (`:387`, cooperative cancel), which this table numbers WP-3 and WP-6. So its
"WP-3" (`:385`, and `:84`, `:155` in the prose) and its "WP-4" (`:386`, and `:151`) are ONE
behind -- they are this table's WP-4 and WP-5 -- and everything after its inserted `WP-4b` is
further behind still: its "WP-5" (`:388`, the picker and `ermine.preview.roots`) is this
table's **WP-7**, and its "WP-6 / WP-7" (`:390`, the bundle and the host reducer) are this
table's WP-9 and WP-10. Read the ticket here.

| # | Ticket | Done when | Tier / cost |
|---|---|---|---|
| WP-1 | `Rpc.scala`: `send` synchronised; `onRequestDeferred`; `$/cancelRequest` routed; incoming log line moved after parse and redacted by method (`Rpc.Redacted`); `notify` legal from a second thread | the four A-group properties in §11 pass; a captured log of an `ermine/preview/connect` round trip contains `[redacted]` and not the body | pr / ~half a day |
| WP-2 | lift `scrub` and `dependentsOf` from `Resident` into `Session` with `builtins` as a parameter; `Resident` calls them | C properties `:554`, `:583`, `:655` pass unchanged; `git diff --stat` of `Resident.scala` is deletions plus the four call sites (`:208`, `:212`, `:231`, `:461`) and the `builtins` threading | pr / ~2 h |
| WP-3 | `_registerDecls` on `SessionEnv` (default on, carried by `copy`), consulted at `Session.scala:915`, off on every `Resident.withEnv` copy | the group-D registration property in §11; `TestJson`, `TestSchema`, `TestNamedFields` unchanged | pr / ~2 h |
| WP-4 | `Runner`: `reports` keyed by `(module, binding)`, `report`/`compile(module, binding)`, `cfg.reportName` the default for the HTTP route; `paramSchema(module, binding)`; `resultKind` public; `builtins` snapshot after its preamble; `invalidate(paths: Set[Path]): Set[String]` under `evalLock` (scrub the closure, evict `reports`, no eager reload); `Backends.scannerFor(dialect, variant)`; a `delegatingRun: RunDB` in `lsp/` | the four `TestRunner` properties in §11; `bin/ermine-serve` behaviour unchanged (`TestRunner` green) | pr / ~1 day |
| WP-5 | the preview thread and `Preview` object in `lsp/`: lazy boot on first `ermine/render`, daemon thread, `uri` -> module, `inferredRoot`, absolute `roots`, queue with one in flight / one queued / latest wins, `generation` echo, mtime scan per render, `stale` generation counter, watchdog with the restart button, document-size cap, `invalidate` posted from `afterReload`, `ermine/preview/invalidated`, `ermine/schema {binding}` routed to the queue, `ermine/preview/reports` on the dispatch thread, work-done progress; launcher `-Xmx${ERMINE_LSP_XMX:-2g}` + `-XX:+ExitOnOutOfMemoryError` and the `ermine.maxHeap` setting | group D properties; `lsp-client.py` smoke; RSS, boot seconds and heap after a watchdog fire (allocating and non-allocating loop) MEASURED and written into §2.2/§2.5; a render whose evaluation loops is answered by the watchdog and the resident still answers a hover; an allocating loop ends in a clean exit the client restarts | pr + commit + instruments / ~3 days |
| WP-6 | cooperative cancel: the flag checked at the head of `Runtime.swhnf`, set by the watchdog and by an in-flight `$/cancelRequest`; the `Runner` discarded on cancel | a looping render is cancelled within a second and the next render boots a new session; the resident's tables are unchanged; **adopted only if** the `perf-bench.sh` interleaved A/B shows no movement (instrument, written here) | pr + instrument / ~1 day; gated |
| WP-7 | extension: **Ermine: Preview Report...** as a (file, binding) picker over `ermine/preview/reports` with per-workspace memory and free-text fallback, **Ermine: Render Report to JSON** into an untitled editor tab, `ermine.preview.roots` (resource scope, absolutised), re-render on `invalidated`, the `ermine.maxHeap` export | on `core/src/test/resources/doc/Sales.e` with no setting the picker offers `report : Query -> Node`; the tab shows a 400 naming `$.params.fromDay` (WP-8 turns it into a document); saving `Sales.e` updates the tab with no restart; no webview | manual + commit smoke / ~1 day |
| WP-8 | params: `.ermine/preview/<Module>/<binding>.params.json`, the skeleton from the schema on first pick, `<binding>.schema.json` beside it with a relative `$schema`, `$schema` stripped before sending, re-render on save, the orphan message, the one `.gitignore` line | `Sales` renders a document on first pick with no hand-written JSON; completion and a red squiggle for a wrong key in `Sales/report.params.json`; saving it re-renders; renaming the binding shows "no params for"; `git status` shows the params file and not the schema | commit smoke + manual / ~1 day |
| WP-9 | webpack browser bundle: config, `npm run bundle` / `bundle:watch`, `devtool: 'source-map'`, output under `client/dist/browser/` | `npm test` unchanged; the bundle checklist of §5 passes under a CSP without `unsafe-eval` | nightly (`npm test`) + checklist / ~half a day |
| WP-10 | webview panel: host page, CSP, `localResourceRoots`, the `applyMessage` reducer and its `node --test`, banner states (initial, error, stale, unsaved, switching, offline, fast mode), `retainContextWhenHidden`, bundle watcher -> reload; `gate_client` registered at nightly | `Sales` renders inline; editing `client/src/widgets/scorecard.ts` updates the panel without a restart; a 400 from a bad param shows `path` in the banner; the reducer property passes; `scripts/gate.sh run nightly` runs `gate_client` | nightly + manual / ~2 days |
| WP-11 | Q1 and the legacy renderers in the panel | `table` renders through `runTabular`; the global's name is written into `client/src/index.ts` and `legacy.ts` | checklist / ~half a day |
| WP-12 | `mssql-jdbc` `jre11` in `build.sbt`; one real connect to the work server from the preview; `sqlPrimT`'s `"date"` mapping checked; Q3 answered | a connect succeeds (MEASURED, with the truststore answer written into §7.3); the first-connect TLS behaviour is recorded as observed | instrument / ~half a day plus the wait for the server |
| WP-13 | profiles (user scope only) + `ermine/preview/connect` + the four-way classifier with `kept` + `Throwable` catch and scrub + URL credential refusal + `SecretStorage` keyed by `sha256(url + "\0" + user)` + trace-`verbose` refusal in the one `connect()` + **Forget Database Password**; no `untrustedWorkspaces` declaration; the Settings-Sync answer written into §8.2 | the credential gate (§8.4) passes in full; the fake-driver classifier test passes; a workspace-scope profile is ignored and named once | pr + instrument / ~2 days |
| WP-14 | held connection lifecycle: the §7.2 switch sequence, Disconnect command, `disconnected` notification, extension-driven reconnect, re-render after every connect, recycling defaults (Q2), reconnect on `Running`, status-bar item `id (dialect) @ host`, the file-backed SQLite profile documented | a 1-hour session against MSSQL leaves no `##` tables after Disconnect (count in `tempdb.sys.tables`, MEASURED); a profile switch mid-render discards the old answer; killing the server and letting the client restart it ends in a rendered document; no password *field* in `lsp/Preview.scala` (code review), the driver's `Connection` acknowledged to hold it until close | instrument + manual / ~1.5 days |
| WP-15 | SQLite emitter gaps: `EmitOver_UsingOver` mixin, bracket names, parenthesised joins | `TestSqlEmitters` pins each string; a windowed report previews on SQLite with rows | pr / ~half a day |
| WP-16 | engine gaps: `UnsupportedOnDialect` at the §9.2 sites, 500 banner, deploy-dialect badge | no emitter output contains `TODO`; `tryCast` on SQLite shows the banner naming `tryCast` and `sqlite` | pr / ~1 day |
| WP-17 | closed-environment packaging: vendored `client/node_modules` or internal registry, driver jar offline, `bin/ermine-lsp.cmd` (and a PowerShell twin) with `resolveServer` choosing it on Windows | a fresh clone on a work machine runs WP-7 and WP-10 with no network and no WSL; the credential gate passes on Windows | manual / ~1 day |
| WP-18 | docs: `docs/JSON-GUIDE.md` §9/§10/§12 (the guide's `Runner.scala:259-280` reference at `:1571` has drifted to `:287-288`), `client/README.md` "Adding a widget" (`ermine/schema` from the render session replaces eleven boots), `editor/vscode/README.md` | the three documents describe the loop as built; MEASURED figures replace the mined ones here | none / ~half a day |
| WP-19 | **optional, out of the loop**: dual-emit T-SQL diff in the panel via `dumpRel` / `dumpClosed` | only if relation authoring in the panel is asked for | -- |
