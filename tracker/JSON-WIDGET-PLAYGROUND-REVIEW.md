# Review of `tracker/JSON-WIDGET-PLAYGROUND.md` (adversarial, 2026-09-19)

Reviewed against branch `json-encode` at `a0830244`. Every `file:line` below was opened in
this review; nothing was built or run. Where a claim rests on third-party behaviour it is
marked *external*, as the document does.

**Verdict: REWORK.** The load-bearing decision (render inside the LSP resident) is asserted,
not designed: the document's §8 requires a render thread while every piece of code it builds
on (`Rpc.scala:365-367`, `Resident.scala:16-18`) makes single-threaded access to `SessionEnv`
the invariant, and the two questions that decide whether the design is safe (Q2, Q3) are
listed as open. Separately, the authentication section fails its own acceptance test against
code that already exists: the wire logger at `Rpc.scala:318` writes every incoming request
body, password included, to `ERMINE_LSP_LOG`, and no ticket touches it.

## Findings, most severe first

### 1. The password is written to the server log by existing code — CRITICAL

**Claim under attack.** §6 A3–A5 and WP-7's done-when: "a password never appears in
`settings.json`, the JDBC URL, `ERMINE_LSP_LOG` or the status bar (grep of a captured log)".
A5 redacts only the URL.

**What is wrong.** `Rpc.scala:318` logs `">> " + clip(body)` for every message the server
reads, and `Rpc.scala:345` logs `"<< " + clip(...)` for every message it sends; `clip` keeps
the first 2000 characters (`Rpc.scala:359-360`), which is more than a connect request.
`bin/ermine-lsp:19` turns `ERMINE_LSP_LOG` into `-Dermine.lsp.log`, and the extension sets it
from `ermine.logFile` (`extension.js:145-146`). So with logging on, the proposed
`ermine/preview/connect {profileId, user, password}` lands in a plaintext file verbatim. The
document greps `lsp/` for database references (§1) but not for what the wire logger does with
request bodies. No ticket in §12 changes `Rpc.scala`.

**Second leak on the client side.** `editor/vscode/package.json:63-71` declares
`ermine.trace.server` with a `verbose` level. *External:* `vscode-languageclient` at `verbose`
logs each request's params to the output channel. The document never mentions the setting.

**Failure scenario.** A developer turns on `ermine.logFile` to debug a slow render, connects,
and the SQL password is now in a file under the checkout, which `git add -A` will pick up
unless it is gitignored.

**Correction.** Add a ticket: the wire logger redacts by method (`ermine/preview/connect`
bodies never logged; the extension sends the request with trace suppressed, or the password
travels in a separate notification the client logs at `messages` only). Make the WP-7 gate
run with `ermine.logFile` set AND `ermine.trace.server: verbose`, and grep both files.

### 2. "Render on its own thread" contradicts the resident's single-thread invariant; the race is real and undesigned — CRITICAL

**Claim under attack.** §8 row 1: `ermine/render` "runs on its own thread with a hard
timeout"; §2 P1 (i): `Runner` accepts the resident's `SessionEnv`; Q2/Q3 defer the lock
question to WP-1.

**What is wrong.**
- `Rpc.scala:365-367`: "JSON-RPC dispatch, strictly one message at a time: SessionEnv is
  not thread-safe ... there is exactly one loop and handlers run on it". `Resident.scala:16-18`
  repeats it. A render thread is a second thread touching the env.
- `Runner.evalLock` (`Runner.scala:624`) is taken by `Runner` only. `Resident.reloadModules`
  (`Resident.scala:205-241`) and `checkFile` (`:401`) never take it. So the design's own
  argument for a process-wide lock — `Runner.scala:250-256`: module loading "mutates the
  `SessionEnv`'s eight maps field by field and the process-global `DataConDecl` registry -- two
  STATIC maps" — applies to the resident as a second, unlocked writer.
- Copies do not save it. `SessionEnv.copy` (`SessionState.scala:112-113`) reads eleven `var`
  fields non-atomically; a `checkFile` copy taken while a render thread's
  `Session.loadModules(List(module))` (`Runner.scala:436`) is half-way through its field-by-
  field writes sees a torn env. And a copy shares every `Runtime` value in `env.env`, whose
  `Thunk.state` is a non-volatile `var` (`Runner.scala:257-260`): evaluation on the render
  thread and a scrub-and-reload on the dispatch thread now touch the same objects with no
  happens-before.
- `Runner.scala:250-256` is cited by Q3 as "Evaluation mutates the env"; the passage says
  *module loading* mutates the env and *evaluation* races on thunks. Both are true and both
  need a lock the resident does not have.

**Failure scenario.** Save `Layout/Widgets/Foo.e` while a render is evaluating: the dispatch
thread scrubs `Foo` out of the resident (`Resident.scala:289-301`) while the render thread's
`Session.eval` reads `env.termNames` — a `NoSuchElementException` in the render at best, a
corrupt `DataConDecl` registry seen by the next `ermine/schema` at worst.

**Correction.** Q2/Q3 are not open questions, they are the design. Either (a) the render runs
on the dispatch thread (then §8 row 1 is false, there is no cancellation, and a 30 s render
stalls diagnostics for 30 s — say so), or (b) `Resident` gains a lock that `reload`,
`checkFile`, `ermine/schema` and the render all take, and the document states the lock order
against `Runner.evalLock`. Pick one before WP-1.

### 3. Cancellation and timeout are asserted; nothing in the dispatcher can deliver them — MAJOR

**Claim under attack.** §8 row 1 ("`$/cancelRequest`; on timeout the connection is closed
and recycled") and WP-2's done-when ("render timeout and `$/cancelRequest` pinned").

**What is wrong.**
- `grep cancel lsp/*.scala` hits only a comment in `Diagnostics.scala:67`. `Rpc.scala:488`
  silently ignores every `$/` notification. There is no cancel support to extend.
- The reader and the dispatcher are one thread (`Rpc.scala:365-367`, `:384`). While a render
  runs on it, `$/cancelRequest` sits unread in the pipe. Cancellation therefore needs a reader
  that keeps reading while a handler runs — a change to the one-loop architecture, not a
  handler.
- The evidence column cites `JSON-GUIDE.md:1602-1603`: "an Ermine infinite loop hangs the
  runner". That hang is in *evaluation*, under `evalLock` (`Runner.scala:540`), before any
  connection is opened (`:359-360`). Closing the connection does not end it, and a JVM thread
  in a pure loop cannot be stopped. After the timeout fires the runaway thread still holds the
  process-wide `evalLock`, so every later render blocks forever.

**Failure scenario.** A widget module with a non-terminating fold is saved; the first render
never returns; the timeout "recycles the connection"; the second render queues on `evalLock`
behind the first; the only way out is **Ermine: Restart Language Server**.

**Correction.** State what a timeout can and cannot do: it can abandon the *scan* (close the
statement) and answer the client; it cannot stop evaluation. The honest done-when is "a
render whose evaluation does not terminate is answered with a timeout error and the server
tells the user a restart is needed", and WP-2 must name the reader/dispatcher change.

### 4. The headline loop — save the widget module, see the panel change — has no trigger and no harness — MAJOR

**Claim under attack.** §1 surface A and §2: "the module cache already reloads on save", so
the restart cost per `.e` edit is "none".

**What is wrong.** Reload is invalidation, not re-render. §3 says the panel re-renders when
the *bundle* changes; P3 says it re-renders when the *params file* is saved. Nothing says what
re-renders the panel after the resident reloads a module: no server-to-client notification
after `afterReload` (`Main.scala:179-194`), no extension-side `.e` watcher. Second, a widget
module `Layout.Widgets.Foo` has no `report` binding; rendering it needs a harness report that
uses it, and the document never says where that harness lives or how the panel knows which
report to render when the active editor is `Foo.e`.

**Failure scenario.** The developer saves `Foo.e`, the log says "reloaded Layout.Widgets.Foo",
the panel shows the old widget until they touch the params file.

**Correction.** Add to P1: `afterReload` sends `ermine/preview/invalidated {modules}`; the
extension re-sends the last render request when the current report or a dependency is in the
set. Add to P2/P3: a per-report "harness" convention (`.ermine/preview/<Module>.params.json`
already keys on the *report* module; say that the widget loop is driven from a report the
developer picks, and remember it per workspace).

### 5. Report-cache eviction has a hole whichever answer Q3 gets — MAJOR

**Claim under attack.** §2 P1 (iii) and §8 last row: eviction "keyed by `Resident.reload`'s
changed+dependents set" so "nothing [is] cached across a module edit".

**What is wrong.** `Resident.reload` only knows modules the *resident* loaded: "Files the
resident did not load -- workspace siblings ... are not its business and are ignored here"
(`Resident.scala:243-250`). `ermine/schema`, the precedent, works on a *copy* (`Schema.scala:807`
`ermine.withEnv`) and loads the module into that copy.
- If the render also uses a copy (Q3 option 2), the report module (`Sales`, a workspace file)
  is never in the resident, `reload` returns nothing for it, and the `reports` map
  (`Runner.scala:296`) serves the stale report forever — exactly the bug (iii) exists to fix.
- If the render shares the resident env (Q3 option 1), `Session.loadModules(List("Sales"))`
  puts a workspace module into the resident, which `tracker/LSP-STALENESS.md:40` gives as the
  reason `Session.reloadChangedModules` was rejected ("would load THOSE into the resident
  too"); every later `checkFile` on `Sales.e` scrubs it from its copy, and every
  `workspace/symbol` walk (`Resident.scala:148-155`) now lists workspace names.

**Correction.** Decide, and add a second eviction key: the render request's own `module` plus
anything the render loaded (`env.loadedModules` delta), watched by the extension's existing
file events. Pin it: edit the *report* module (not a stdlib widget), render again, the answer
differs.

### 6. Auth failure is not distinguishable from connect failure, and §5 predicts a connect failure — MAJOR

**Claim under attack.** §6 A2/A6: "`delete` on an authentication failure so the next attempt
re-prompts".

**What is wrong.** Nothing says how the server classifies a failure. `RunnerConfig.backend`
(`Runner.scala:197-198`) folds every `NonFatal` into one string, "cannot open <dialect> at
<url>: <message>". §5 row 4 predicts the *first* connect to the work server fails on TLS
("an internal CA fails the first connect"). Under A6 as written that failure deletes the
correct password the user just typed, and the next render prompts again, forever, with a
message about certificates. Nor is lockout mentioned: a stored password that has been changed
server-side is retried on every render until the account locks.

**Correction.** Classify on the driver's error: *external* — mssql-jdbc reports login failure
as SQLState `28000` / error 18456. Delete the secret only on that class; keep it and show the
driver message on every other class; after one auth failure, do not retry without a new
prompt. State the classification in A6 and pin it with a fake driver in a test.

### 7. The secret is keyed by a profile id that a workspace can define — MAJOR

**Claim under attack.** §6 A1/A2 and §8 "Workspace trust": the hazard is an *untrusted*
workspace.

**What is wrong.** Profiles live in `settings.json`, which VS Code reads from user AND
workspace scope; the secret is keyed by `id` alone. A *trusted* workspace — a colleague's
repo with a committed `.vscode/settings.json` — can define `{id: "work", url:
"jdbc:sqlserver://their-host", user: "..."}`. The extension finds a stored secret for `work`,
sends it to the server, the server hands it to `DriverManager.getConnection` against
`their-host`. Workspace trust does not help: the user trusted the repo to edit it. The
document has no threat-model statement, so this adversary is never named.

**Correction.** Key the secret by a hash of `(id, url, user)` so a URL change re-prompts;
or read profiles from user scope only; or declare `ermine.preview.profiles` in
`capabilities.untrustedWorkspaces.restrictedConfigurations` *and* prompt with the host name
whenever a stored secret is about to be used against a URL it has not been used with before.
Write the threat model down: co-worker on the box (log files, process list), synced settings,
authored workspace.

### 8. Where the password lives after connect is undecided, and recycling forces the wrong answer — MAJOR

**Claim under attack.** §6 A4 (`DB.RunUser`) with §4 "recycling after N renders or T idle
minutes".

**What is wrong.** `DB.RunUser` (`DB.scala:129-138`) returns a closure over `password` that
opens a new connection on every `run`; the design instead holds one connection
(`fromPersistentConnection`, `Backends.scala:49-51`), for which the password is needed once.
But "automatic recycling" and "recycle on profile switch" mean the *server* reconnects on its
own, so the server must keep the password for the process's life. The document says nothing
about clearing it, about a changed password, or about which side owns reconnection.

**Correction.** Decide: the server holds the password for the duration of one `getConnection`
call and nothing else; a recycle is the server closing the connection and the *extension*
sending a fresh `ermine/preview/connect` (it has `SecretStorage`). Then `DB.RunUser` is the
wrong tool (it is a per-run reconnecting runner) and WP-7 should say what is built instead.

### 9. Overlapping renders share one JDBC connection; the design must serialise them and does not say so — MAJOR

**Claim under attack.** §8 row 1 (a render thread per request) with §4 (one held connection).

**What is wrong.** `Runner`'s concurrency argument (`Runner.scala:264-267`) is that "`Run[DB]`
hands each thread its own connection (`Run.ThreadLocalDC`)". `fromPersistentConnection`
(`Backends.scala:49-51`) hands every thread the same `Connection`, and `drive`
(`Runner.scala:495-496`) runs scans *outside* `evalLock`. Two renders in flight — a params save
during a slow render — run statements concurrently on one connection. `DB.transaction`
(`DB.scala:19-29`) also toggles `setAutoCommit` on that shared connection per scan
(`SqlScanner.scala:194`), so an interleaved second scan can be committed or rolled back by the
first. *External:* sqlite-jdbc does not support concurrent use of one connection.

**Correction.** One render in flight per server; a new request while one is running either
queues or supersedes it (the panel wants "latest wins"). State it, and pin it.

### 10. §7 misattributes emitter gaps to SQLite, so M1 is the wrong mitigation for the most important row — MAJOR

**Claim under attack.** §7.1 title "Cannot be previewed on SQLite at all", first row (window
functions), and M1 "refuse up front".

**What is wrong.** The base `emitOver` splices prose (`SqlEmitter.scala:269-271`) and only
`MsSqlEmitter` mixes in `EmitOver_UsingOver` (`:843`, the only use) — confirmed. But that is
a property of the *emitter*, not of SQLite: the repo's own `tracker/tools/tsql2sqlite.py:10-12`
says "SQLite accepts [bracket] identifiers and supports OVER(...) since 3.25, so everything
else -- the window clauses this whole exercise is about -- passes through untouched", and E1
ran windowed reports on SQLite that way (`LOOP-MODEL-PLAN.md:249`). The same holds for the
"column names needing quoting" row: SQLite accepts `[s]`. So the cheapest, most faithful fix
for `windowed` is one mixin line (`class SqliteEmitter ... with EmitOver_UsingOver`), after
which the preview *runs* the window query; M1's typed refusal is what to do only for the rows
where the engine really lacks the function (`dateadd`, `datediff`, `STDEV`, `TRY_CAST`,
procedures). `tryCast` with null-on-fail is correctly a refusal.

**Correction.** Split §7.1 into "emitter gap, fixable" (window functions, bracket names,
possibly non-left-deep joins by parenthesising `emitJoinOn`) and "engine gap, refuse". WP-11
becomes two tickets. `TestSqlEmitters` already compares strings, so the mixin is pinned for
free.

### 11. §7's answer to "what is the preview for" is buried, and the scope it implies contradicts §0 — MAJOR

**Claim under attack.** The scope statement (widget module, renderer, params) versus WP-11,
WP-12 (dual-emit diff, deploy-dialect badge).

**What is wrong.** Surfaces A and B are exercised by inline literal relations
(`core/src/test/resources/doc/Sales.e`, which imports `Relation` and defines
`report : Query -> Node` at `:107`); for those the dialect is irrelevant and SQLite is a
perfectly good oracle for *widget rendering*. Dialect fidelity matters for a fourth surface —
authoring the relation — which §0 does not list. M4 concedes that "an MSSQL-backed profile for
preview is the only honest answer", i.e. for that surface the right tool is the profile
mechanism §4 already builds. WP-12 (a side-by-side T-SQL diff in the panel) is therefore a
query-authoring feature dressed as widget-loop hygiene.

**Correction.** Say plainly: for A/B the preview is authoritative because the rows are inline;
for relation authoring use the MSSQL profile, and SQLite previews of scanned relations are
best-effort. Keep M3 (the badge) and the split WP-11; move WP-12 out of this document or mark
it optional.

### 12. WP-1 is not "a constructor parameter"; `Runner`'s boot is the refactor — MAJOR

**Claim under attack.** §2 P1 (i) and WP-1's done-when: "`new Runner(cfg)(env)` compiles,
`TestRunner` passes unchanged with the default env".

**What is wrong.** `Runner.booted` (`Runner.scala:311-326`) is a constructor-time `val` that
(a) *mutates* `env.loadFile` when `cfg.roots` is non-empty, (b) runs `Lib.preamble` again,
(c) loads `Layout.Doc`/`Layout.Fetch`/preload, (d) builds a `_typeCheck=true,
_useInterface=false` env with `_foreignTolerant` unset, whereas the resident is
`_foreignTolerant = Some(true)` (`Resident.scala:118-120`). Handing it the resident's env
means re-running the preamble on a booted env from a render thread (see finding 2), and a
module with an unresolved foreign binding now *loads* and fails at force time with
`Bottom(throw Death(...))` (`Session.scala:1405-1411`), i.e. at render rather than at load —
a difference from `ermine-serve` the document does not mention. `RunnerConfig.run` is an
immutable case-class field (`Runner.scala:174`), so "recycle on profile switch" (WP-9) needs
either a new `Runner` per profile (new report cache, another boot) or a mutable `Run[DB]`
holder — neither is in the ticket. Callers today: three in `TestRunner.scala:112,124,1124`,
one in `ServeMain.scala:97`; that part is small.

**Correction.** WP-1 becomes: a `Runner` constructor over a *pre-booted* env that skips
`booted`, takes no ownership of `loadFile`, and takes a `Run[DB]` *provider* (mutable holder)
rather than a `Run[DB]`; state the foreign-tolerance consequence.

### 13. P3's schema claim is only true for a named `Params` type declared in the report module — MINOR

**Claim under attack.** §1 asset table: `ermine/schema` "already exports the `Params` type
surface P3 needs"; P3: "a JSON Schema for the `Params` type, produced by `ermine/schema`".

**What is wrong.** `LspSchema.answer` takes a `type` expression or a `name`
(`Schema.scala:800-815`); `exportNamed` looks the name up in `s.cons` (`Schema.scala:206-210`),
i.e. it is a *type* name. The Params type of a report is the domain of the `report` binding's
inferred type (`Decode.reportSignature`, used at `Runner.scala:464`), which may be an alias
from another module or an anonymous record. `Sales.e:107` happens to name it (`Query`), so the
smoke would pass and the general case would not.

**Correction.** Give `ermine/schema` (or `ermine/render`) a `binding` mode that runs
`reportSignature` and exports the domain; say `json.schemas` is a *user* setting and the
mechanism is a `contributes.jsonValidation` `fileMatch` plus a content provider, not a write
into the user's settings.

### 14. Workspace trust: the extension declares nothing today, and the bigger hazard is already there — MINOR

**Claim under attack.** §8 row 3 and WP-13 ("in an untrusted workspace the commands are absent").

**What is wrong.** `editor/vscode/package.json` has no `capabilities.untrustedWorkspaces`
(grep, 0 hits). *External:* an extension that declares nothing is treated as not supporting
Restricted Mode and is disabled entirely there — so today the whole language server is off in
an untrusted workspace, and "the commands are absent" is trivially true; the ordering question
(connect before or after trust) is moot for the untrusted case and does not arise for the
trusted case that finding 7 describes. Note also that `ermine.serverPath`
(`package.json:43-46`, `extension.js:50-51`) already lets a workspace choose the executable
the extension spawns — a larger pre-existing hazard than a JDBC URL, and the natural
`restrictedConfigurations` entry alongside the profiles.

### 15. Omissions a design of this kind must settle — MINOR (one finding, several items)

- **Error surfacing.** How a `Failed`/`BadRequest`/`NotFound` from `ermine/render` shows in
  the panel (banner? the `RunError` JSON verbatim?) and whether a module that fails to load
  shows there or only in Problems. §7.4 covers only `UnsupportedOnDialect`.
- **Initial state.** What the panel shows before the first render and while a render runs.
- **Panel lifetime.** A hidden webview is destroyed unless `retainContextWhenHidden` is set
  (*external*); re-setting `webview.html` on bundle change loses scroll and drilldown state.
- **Two windows / multi-root.** Each window spawns its own `bin/ermine-lsp` (`extension.js:179`)
  with its own held connection; the server reads *every* workspace folder's stdlib
  (`Main.scala:114`) while the extension uses `folders[0]` (`extension.js:43-46`); which
  folder's `.ermine/preview/` and which scope's profiles apply is unsaid.
- **Testing.** `scalacheck-binding/src/main/scala/TestLspRobustness.scala` already has the
  shape (a `Resident` under mutation, `:455`; reload properties, `:554-655`). A render property
  — render, mutate the module, render; render under a concurrent reload; a render that throws
  poisons nothing — belongs there. The document proposes only the `lsp-client.py` smoke.
- **`data` in the request.** P1 says the request takes `{module, binding, params, data?}` but
  §2 also says the preview "always sends `{"data":{"default":"inline"}}`"; pick one.
- **Error-message hygiene.** `Runner.scala:198` puts the JDBC URL into the refusal string that
  reaches the client; A5 covers logs but not answers.

### 16. Ticket order and hidden size — MINOR

- WP-7's done-when ("auth failure re-prompts") cannot be exercised without a driver that
  authenticates; SQLite has no credential. WP-8 must precede or accompany WP-7.
- WP-2 hides the dispatcher change (finding 3) and the lock design (finding 2).
- WP-13 "lazy" depends on `Runner` not booting at construction (finding 12); as written,
  constructing a `Runner` with the default config forces `DB.sqliteTestDB`
  (`Runner.scala:174`, `DB.scala:140`) and loads the SQLite driver.
- WP-9's done-when measures `tempdb.sys.tables`; fine, but note `##` names are GUID-fresh
  (`SqlScanner.scala:305`, `:891`) so the test is about count, never collision.

### 17. Citation drift and small misstatements — NIT

| Cited | Actual | Note |
|---|---|---|
| `bin/ermine-serve:36-37` (`"$@"`) | `:32-33`; the file is 33 lines | §2 row 1, §6 A3 |
| `bin/ermine-serve:20-25` (classpath rebuild) | `:21-27` | §9 |
| `Main.scala:268` (`afterReload`) | def at `:179`, the watch call at `:274`; 268 is inside the `paths` helper | §2 P1 (iii), WP-2 |
| `SqlEmitter.scala:722` (Date column `integer`) | `:724`; `:723` (Timestamp) is `:725`; `:715` (`text`) is `:717`; `:714-726` is `:716-727` | §7.2, §7.3 |
| "`STDEV`/`VAR` (`:606-612`)" | `STDEVP`, `STDEV`, `VARP`, `VAR` | §7.1 |
| Q3: "Evaluation mutates the env (`Runner.scala:250-256`)" | the passage is about *module loading*; evaluation races on `Thunk.state` (`:257-260`) | Q3 |
| `Definitions.scala:221-228` | comment `:221-225`, handler `:226-228` | fine, noted |

## Checked and confirmed (do not re-litigate)

- `Runner.scala`: `:215-219` boot comment, `:287-288` own env, `:296` `reports` map,
  `:411-420` cache-once, `:495-496` one `cfg.run.run`, `:246-248`/`:624` process-wide lock,
  `:171-179` config, `:183` dialects, `:188-198` five-way `backend` match.
- `Resident.scala:24` (~13 s), `:251` `reload`, `:286` `scrub`; `Main.scala:196-211` watcher
  registration, `:258-274` `didChangeWatchedFiles` → `reload`.
- `Backends.scala:26-27` (`MicrosoftSQLServerNoTransactions` unreachable from `backend`),
  `:33-37` drivers, `:34` mssql driver class, `:42-43` jTDS in `cloudDB` only, `:49-51`
  `fromPersistentConnection`; `backends.scala:6` `type DB[+A] = Connection => A`.
- `DB.scala:106-116` `Run` (eager `Class.forName` at `:107`, connect+close per run),
  `:129-138` `RunUser`, zero callers outside its definition.
- `build.sbt:111-113`: mysql-connector-j, jTDS, sqlite-jdbc only; `build.sbt:1` Scala 3.3.8.
- Emitter overlap: `SqliteEmitter` 7 mixins (`:676-683`), `MsSqlEmitter` 15 (`:834-848`),
  5 shared, as listed. `emitOver` `:269-271`, `emitTryCast` `:276-278`, `emitJoinOn` `:253-263`,
  `emitColumnName` `:38`, `[s]` `:616-617`, `##` `:621`, `EmitNoDropTempTable` `:431-433`,
  `dateadd` `:699-701`/`:877-879`, `datediff` `SqlScanner.scala:109-110`, `cleanTempTables`
  `:239-248`, `dumpRel` `:281`, `Scanner.scala:29-31`/`:44-45`, concat `:318-322`/`:573-575`,
  int div `:356`/`:631-635`, stddev `:328-348`, `sqlPrimT` `:881-882` with the jtds comment,
  `nn` `:864-868`, `nvarchar(1000)` `:867`, `DATETIME2` `:860-862`, `emitDate` base `:199-201`
  (`yyyy-MM-dd`, `:211-215`) and SQLite `:696` (`getTime`).
- `relational/package.scala:122-140` `withDriver` `finally`; `Write.scala:352-361`.
- `Decode.scala:99`, `:128` monomorphic / closed-row; `Schema.scala` is JSON Schema 2020-12
  (`:10`, `:126`).
- `TestSqlEmitters.scala` has no `scanRel`/`Run[DB]`/`DriverManager`/`getConnection` (0 hits);
  `Profiler.scala:37` is an `object`, `:281-295` names the three backends.
- `lsp/*.scala` has no `Connection`/`Run[DB]`/`Scanner[` reference (0 files).
- `Definitions.scala:226-228` routes `ermine/schema` to `LspSchema.answer` (`Schema.scala:800`).
- `extension.js` 292 lines; `:43-46` first folder, `:50-54` server path, `:145-150` env and
  stdio spawn, `:179` `LanguageClient`, `:240-257` four commands; `package.json:5` 0.1.4, `:8-9`
  `^1.75.0`, `:43-46` `serverPath`, `:63-71` `ermine.trace.server`, `:98` `@types/vscode`; no
  `createWebviewPanel`/`createFileSystemWatcher`/`secrets`/`isTrusted` (0 hits).
- `client/`: `tsconfig.json:5` CommonJS; `package.json:11-18` scripts, `:20-28` deps (no
  bundler); `generate.sh:18-30` eleven types, `:33-38` one `bin/ermine-schema` per type;
  `harness.ts:1-3`, `:31-40` stub; `index.ts:3-7`, `:37-50`; `document.ts:58`;
  `dispatcher.ts:90-95`; `legacy.ts:327-333` (`table`/`drilldownTable` need it; `scorecard`,
  `headline`, `crosstab` are under `widgets/`); `.gitignore:9`; `client/node_modules` absent;
  `docs/tutorial.html` is the only `.html`.
- `ermine-writers/writers/js/htmlwriter.js:11` assigns `ermine_htmlwriter` on `window`;
  `ermine-htmlwriter.js:45` `const htmlwriter = {}`; that package has its own webpack config.
- `JSON-GUIDE.md:1218-1221`, `:1452-1453`, `:1568-1573`, `:1577-1583`, `:1587-1589`,
  `:1593-1603`, `:1648-1652`, `:1953-1954` all say what the document says.
- `Server.scala:16-18`, `:104-110`; `ServeMain.scala:15-25` no credential flag;
  `bin/ermine-lsp:4`, `:19`, `:20`; `LOOP-MODEL-PLAN.md:249` findings (iii), (iv);
  `tsql2sqlite.py:1-12`; `LSP-STALENESS.md:36-40` "why not".
- `Windowed.e:31`, `Op.e:65`/`:144`/`:160`, `Aggregate.e:29-30`, `Scanners.e:15`.
- `tracker/tools/lsp-client.py` has `request()` (`:57`) and an `ermine/schema` section
  (`:605-624`), so the P1 smoke is buildable as described.

## Questions the document must answer before anyone implements from it

1. Does `ermine/render` run on the dispatch thread or not? If not, what lock do `reload`,
   `checkFile`, `ermine/schema` and the render share, and in what order with
   `Runner.evalLock`? (Findings 2, 3, 9.)
2. Per-render env copy or the resident env? With the answer, how is a *workspace* report
   module evicted from the report cache when it changes? (Finding 5.)
3. What sends the re-render after a `.e` save, and which report renders when the active file
   is a widget module? (Finding 4.)
4. Who owns reconnection — server or extension — and does the server hold the password past
   `getConnection`? (Finding 8.)
5. By what driver signal is "authentication failure" recognised, and what happens to the
   stored secret on every other failure class, including the TLS failure §5 predicts?
   (Finding 6.)
6. What is the threat model, and what stops a trusted workspace's `settings.json` from
   redirecting a stored secret to another host? (Finding 7.)
7. Which lines of `Rpc.scala` change so that `ermine/preview/connect` is never logged, and is
   the WP-7 gate run with `ermine.logFile` and `ermine.trace.server: verbose` both on?
   (Finding 1.)
8. For which of §7.1's rows is the fix a SQLite emitter mixin rather than a refusal, and is
   WP-12 in scope at all? (Findings 10, 11.)
9. Is one render in flight at a time, and does a new request supersede or queue? (Finding 9.)
10. How is the render endpoint property-tested, given `TestLspRobustness` exists? (Finding 15.)
