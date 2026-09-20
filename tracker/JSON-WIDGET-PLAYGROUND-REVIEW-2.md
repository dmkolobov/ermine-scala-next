# Second review of `tracker/JSON-WIDGET-PLAYGROUND.md` (adversarial, 2026-09-19)

Reviewed against branch `json-encode` at `a0830244`, the same commit the rewrite cites.
Every `file:line` below was opened in this review; nothing was built or run. The first
review (`JSON-WIDGET-PLAYGROUND-REVIEW.md`) is the historical record and is not edited; its
"checked and confirmed" list is not re-litigated here.

**Verdict: FIX-THEN-LAND.** The rewrite closes 13 of the 17 prior findings with mechanisms
rather than mentions, and option (C) — a second render-only session on its own thread — is
argued from the source and survives this review. What does not survive is the one premise
under §2.2's "no collapse" verdict: the two sessions do **not** write equal-content entries
into the `DataConDecl` registry, because the editor's tolerant check registers `data` shapes
from **unsaved buffers** on every debounced keystroke (`TolerantCheck.scala:862` →
`Session.scala:896,915`), and the `stale` flag cannot see that path. The fix is bounded (a
per-session constructor index; finding 1) and does not reopen the choice of (C), which is why
this is not REWORK; but it, the schema-routing error (finding 3), the trust-declaration
regression (finding 2) and the driver-message leak (finding 5) must be written into the
document and its tickets before WP-3 starts.

## Part 1 — are the prior findings closed?

| # | Prior finding (sev.) | Status | Evidence |
|---|---|---|---|
| 1 | Password written to the server log (CRITICAL) | **CLOSED** | §4 moves the `>>` line from `Wire.receive` (`Rpc.scala:318`) to `Server.handle` after `Json.parse` (`:442-452`) and redacts by method; A6/A7; §8.4 runs the gate at every trace level; WP-1 done-when checks a captured log. The open item in WP-1 is answerable now: the parser's error strings (`Rpc.scala:97-221`) echo input only as one character (`:121`) or a number token (`:144`) — never a string body. Remaining exposure is new material (finding 5) |
| 2 | Render thread contradicts the single-thread invariant (CRITICAL) | **PARTIALLY CLOSED** | The env race is genuinely gone: no `SessionEnv` is shared (§2.3; the preview thread owns a `Runner` env, `Runner.scala:287-288`). The registry argument that replaces it ("equal-content writes", §2.2 row 1) is false — finding 1 |
| 3 | Cancellation/timeout asserted (MAJOR) | **CLOSED** | §2.5 states what a timeout can and cannot do; `$/cancelRequest` routed and its semantics narrowed (WP-1); the reader/dispatcher change is named (`onRequestDeferred`, §4). The added claim "the resident keeps working" is attacked in finding 4 |
| 4 | Headline loop has no trigger or harness (MAJOR) | **CLOSED** | §3 steps 1-7 with `ermine/preview/invalidated`; §3.2 picked report remembered per workspace. Gap for the manual-reload path is minor (finding 7) |
| 5 | Report-cache eviction hole (MAJOR) | **CLOSED** | §3 step 4 keys eviction on the render session's own `loadedFiles` plus `dependentsOf`; `TestRunner` properties in §11 pin it |
| 6 | Auth vs connect failure (MAJOR) | **CLOSED** | §8.3 classifier (`28000` / `18456`; TLS → `connect`, secret kept), A8, fake-driver test in WP-11. Lockout/expiry codes are a minor gap (finding 10) |
| 7 | Secret keyed by a workspace-definable id (MAJOR) | **CLOSED** | A2 user scope only (`inspect().globalValue`), A3 `sha256(url + " " + user)`, §8.2 threat model names T1-T5. The `untrustedWorkspaces` declaration added alongside is a regression — finding 2 |
| 8 | Password after connect; recycling (MAJOR) | **CLOSED** | §7.2: server holds a `Connection`, extension owns reconnect, `RunUser` rejected with the reason. One honesty gap: the driver's `Connection` retains the credential (finding 11) |
| 9 | Overlapping renders on one connection (MAJOR) | **CLOSED** | §2.5 one in flight / one queued / latest wins; the held connection is used by one thread; `DB.transaction` toggling (`DB.scala:19-29`, `SqlScanner.scala:193-195`) is therefore never interleaved |
| 10 | Emitter gaps misattributed to SQLite (MAJOR) | **CLOSED** | §9.1 (emitter gap, mixin) / §9.2 (engine gap, refuse); WP-13 / WP-14 split |
| 11 | Purpose vs scope contradiction (MAJOR) | **CLOSED** | §0 two-surface table; WP-17 optional and last |
| 12 | "A constructor parameter" hides the `Runner` refactor (MAJOR) | **CLOSED** | §2.1 rejects (A) on `Runner.scala:311-326`; `Runner` unchanged, `delegatingRun` `@volatile` holder; foreign-tolerance consequence stated (§2.4). Verified: `Runners.liteDB` is a `def` (`Backends.scala:39`) and `DB.sqliteTestDB` a `lazy val` (`DB.scala:140`), so an explicit `run` really loads no driver |
| 13 | Schema only for a named `Params` type (MINOR) | **PARTIALLY CLOSED** | The binding mode via `reportSignature` is right; it is routed to the session that cannot find the report — finding 3 |
| 14 | Workspace trust declaration (MINOR) | **PARTIALLY CLOSED** | Acknowledged (§8.2 last paragraph), but WP-11's `supported: "limited"` makes the situation worse — finding 2 |
| 15 | Omissions: errors, initial state, lifetime, windows, testing, `data`, message hygiene (MINOR) | **CLOSED** | §5 rows, §11 layers, "no `data` field on this wire" (§4), A5. The A5 hole that remains is the driver's own message — finding 5 |
| 16 | Ticket order and hidden size (MINOR) | **CLOSED** | WP-10 precedes WP-11; WP-1 names the dispatcher change; WP-3 pins the lazy boot with `CountingRun` (`TestRunner.scala:77`) |
| 17 | Citation drift (NIT) | **CLOSED** | Of ~45 citations re-opened (list below) one is misattributed: §11 "`checkFile`, `:401`" under `TestLspRobustness` is `Resident.scala:401`; `TestLspRobustness.scala:401` is `val lines = text.split(...)` |

Counts: 13 CLOSED, 4 PARTIALLY CLOSED, 0 NOT CLOSED.

## Part 2 — the new material

### 1. The registry premise is false: the editor check writes `data` shapes from unsaved buffers — CRITICAL

**Claim under attack.** §2.2 row 1: "Both sessions read the **same files** (§2.4), so their
writes are equal-content … **no collapse.** One window: between the resident re-registering a
changed shape and the render session reloading it"; §2.5 `stale` closes that window.

**What is wrong.** The registry has a third writer the table does not list.
`TolerantCheck.scala:862` runs `Session.processTypeDefComponent(mod)` for every type
declaration of the file being checked; that function is `Session.scala:896`, and it calls
`DataConDecl.register` at `:915`. `Resident.checkFile` (`Resident.scala:401`) reads the file
from the **open buffer** (`:412-413`, `docs.byPath(...).source` = `Session.Buffer`,
`Documents.scala:46`) and resolves its unloaded imports through `docs.loaderFor(dir)`
(`:437-440`, `:485`), i.e. sibling modules also come from buffers. So on every debounced
`didChange` of a file that declares a `data` type, the process-wide registry takes the
**buffer's** shape, while the render session holds the **saved** shape. Every widget module
declares such types (`Layout/Widgets/Chart.e` 12, `Table.e` 5, `Format.e` 4, …; `Sales.e`
4), and three widgets build their props through `Json` (`Scorecard.e:13`, `PieChart.e:23`,
`StyleBox.e:28` import `Json using type Inline`), which is the `toJson#` primitive
(`Lib.scala:1478`) → `Encode.toErmine` → `Encode.userData` → `DataConDecl.forConstructor`
(`Encode.scala:400`), the one reader with no env in reach.

No `invalidate` is posted for a `didChange`, so the `stale` peek (§2.5 last row) never fires.

**Failure scenario.** `Chart.e` is open and dirty with a field added to a props constructor.
The developer saves `Sales.params.json` (or `Sales.e`, or the bundle rebuilds and they hit
re-render). The render evaluates the saved `Chart` (4 arguments) against the buffer's
declaration (5 fields): the guard `c.fields.length == args.length` (`Encode.scala:413`) fails,
`named` is `None`, and the props encode as `{"tag": …, "args": [...]}` (`:478-481`) instead of
an object. The renderer's zod schema rejects it; the panel shows the dispatcher's error box;
nothing says why; the next keystroke re-registers the same shape. The dual case — a nullary
constructor given a field in the buffer — flips `isEnum` (`:401-404`) and a saved enum value
encodes as `{"tag": "Name", "args": []}` instead of `"Name"`.

**Why it is CRITICAL.** It is the premise of the §2.2 verdict that option (C) rests on, the
condition ("any dirty buffer that declares a `data` type, until it is saved") is the widget
loop's steady state, and no mechanism in the design detects it. The `DataConDecl.scala:44-54`
comment the design quotes says "only the test fixture does this" because until now nothing but
`Runner` *read* the registry from a second session.

**Correction** (one of three, decided before WP-3):

- (a) *Preferred.* Make the runtime lookup per session. `toJson#`/`renderJson#` are installed
  per env by `Lib.json` with the `SessionEnv` in scope (`Lib.scala:1478-1487`), so the
  primitive can close over that session's constructor index; `processTypeDefComponent` adds
  `constructor Global -> decl` to a new `SessionEnv` map beside `cons` (carried by `copy`,
  `SessionState.scala:112`; `+=`; and the scrub, `Resident.scala:289-301`). The static registry
  then serves only the tests that read it (`TestJson.scala:121`, `TestSchema.scala:754`,
  `TestNamedFields.scala:436`), and the registry rationale for `Runner.evalLock`
  (`Runner.scala:614-619`) falls away with it. New ticket between WP-2 and WP-3.
- (b) A `SessionEnv` flag under which `DataConDecl.register` is a no-op, set by `checkFile` on
  its copy. Cheaper, but leaves the process-wide map as the source of truth for a second
  session, which is the thing this design is the first to rely on.
- (c) Accept and state the true window, and have the extension refuse to render while any
  `.e` buffer is dirty (`TextDocument.isDirty`, *external*), for every trigger (params save,
  reconnect, bundle reload), not only step 6.

Either way §2.2 row 1 must list `TolerantCheck.scala:862` as a writer and drop "equal-content".

### 2. WP-11's `untrustedWorkspaces: limited` is a regression, not a mitigation — MAJOR

**Claim under attack.** §8.2 T3: "WP-11 declares `capabilities.untrustedWorkspaces:
{supported: "limited", restrictedConfigurations: ["ermine.serverPath",
"ermine.preview.profiles"]}` (*external*), which helps only in Restricted Mode."

**What is wrong.** Today the extension declares nothing and is therefore not activated in
Restricted Mode at all (§8.2 last paragraph, correct). Declaring `limited` **activates** it
there (*external*), with only the two named settings blanked. But the server path is not
only a setting: `resolveServer` (`extension.js:49-55`) falls back to
`path.join(root, "bin", "ermine-lsp")` where `root` is the **first workspace folder**
(`:43-46`), and `activate` spawns it with `cwd: server.root` (`:148-151`). So in Restricted
Mode the extension would execute the untrusted repository's own `bin/ermine-lsp`, which today
it does not. `restrictedConfigurations` cannot reach a path derived from the folder.

**Failure scenario.** A developer opens a colleague's repo, declines trust, and the extension
runs `<repo>/bin/ermine-lsp` — a shell script in the untrusted checkout — as the language
server.

**Correction.** Either keep the declaration absent (the status quo §8.2 already accepts:
"the preview is off in an untrusted workspace"), or declare `limited` **and** gate the spawn
on `vscode.workspace.isTrusted`, resuming on `onDidGrantWorkspaceTrust` (*external*). Rewrite
the T3 row: the declaration is not the mitigation; the trust gate is.

### 3. `ermine/schema {module, binding}` is routed to the session that cannot see the report — MAJOR

**Claim under attack.** §6: "`ermine/schema {module, binding: "report"}` (new mode): load the
module, `Session.eval` the bare binding as `Runner.compile` does … `Schema.exportType`";
WP-9 done-when: "`lsp-client.py` pins the binding mode on `Sales` (domain is `Query`)".

**What is wrong.** `LspSchema.answer` runs on the dispatch thread against a copy of the
**resident** (`Schema.scala:807-811`: `ermine.withEnv`, `Session.loadModules(List(m))`),
whose loader chain is `moduleRoots` then the classpath (`Resident.scala:126-127`). The
preview roots (`ermine.preview.roots`, §2.4) are added to the **render session's** `cfg.roots`
only. `Sales` lives under `core/src/test/resources/doc`, a preview root, so
`Session.loadModules(List("Sales"))` in the resident copy dies with module-not-found and the
WP-9 done-when fails as designed. Secondarily, the binding mode *evaluates* a workspace
module's top-level on the dispatch thread — the thing §2.3 exists to keep off it.

**Correction.** Make the binding mode a preview-queue job: the render session already holds
`Report.paramTy` for a compiled report (`Runner.scala:476`), so the answer is
`Schema.exportType(rep.paramTy, module)` under the render env, and it serialises behind
renders like everything else. If the resident must answer it, say that `previewRoots` are
appended to the resident's chain too, and what that does to `reload`'s `moduleUnder` check
(`Resident.scala:262`).

### 4. "The resident keeps working" after a runaway evaluation holds for CPU, not for the heap; the restart cost is undersold — MAJOR

**Claim under attack.** §2.5 row 4: the watchdog answers, "marks the preview stuck … The
resident keeps working: it does not take `evalLock` and is on another thread"; §2.1 (B) is
rejected because "a runaway evaluation holding that lock would freeze diagnostics too".

**What is wrong.** The two threads share the JVM heap and the GC. No launcher sets `-Xmx`
(`bin/ermine-lsp:18-31`; `extension.js` sets only `ERMINE_LSP_LOG`), so the cap is the JDK
default, a quarter of RAM (*external*; `tracker/PERF-ROADMAP.md:139` records "default max
heap" on the 15.6 GB dev box). A non-terminating Ermine evaluation that allocates — a fold
over an infinite list, the usual shape of the bug — fills that heap in seconds to minutes;
`swhnf` builds thunk chains as it goes (`Runtime.scala:215-230`). After that every thread,
the dispatch thread included, is in GC storms or sees `OutOfMemoryError`; "keeps working" is
then false and the restart the watchdog message recommends is the only outcome. A purely
CPU-bound loop pins one core for the process life, which the document also does not say.

The restart is priced as a menu item. It is a fresh process: the ~13 s boot
(`Resident.scala:24`), every per-document inference cache (`editor/vscode/README.md:118-124`:
warm 0.9 s → cold; 1.6 MB heap per open document rebuilt), the workspace-symbol table, the
held connection and its `##` tables, and the picked report's compiled closure.

**Correction.** Narrow the promise to what is true: "a runaway evaluation blocks no LSP
request until it exhausts the heap, after which the whole server must be restarted; the
watchdog exists so the user is told at 60 s rather than at OOM". Have the extension offer
**Restart Language Server** in the watchdog notification itself. Add to WP-4's done-when: heap
after a watchdog fire is MEASURED for an allocating loop and a non-allocating one, and the
figure is written into §2.5. State the restart cost in §2.5.

### 5. The driver's own exception text can carry the URL; A5 and the §8.4 grep fail on a predictable path — MAJOR

**Claim under attack.** A5: "The server never puts a URL or a password in anything a client
or a log sees … `connect` answers `host` only"; §8.3 `connect` class: "shows the message";
§8.4 row 2: grep for the JDBC URL, 0 hits.

**What is wrong.**
- `DriverManager.getConnection` with a driver that does not accept the URL throws
  `SQLException("No suitable driver found for <url>")` (*external*, JDK) — the full URL. This
  is the `connect` class, not the `driver` class (`Class.forName` succeeded), and it is the
  first-connect failure a typo in `jdbc:sqlserver://` produces. The message is answered to
  the client, logged by `Wire.send` at `Rpc.scala:345` (`<<` logs every outgoing body, which
  §4 leaves unchanged on the stated ground that "no server-sent message carries a secret"),
  and shown by the extension.
- Nothing forbids credentials **inside** the URL string. A1 removes a *field*; a user-scope
  profile with `url: "jdbc:sqlserver://h;user=u;password=p"` passes the schema, is synced by
  Settings Sync (T2), and its password lands in the `<<` log through the path above.
- If the connect handler throws rather than classifies — `ExceptionInInitializerError` from a
  driver's static initialiser is a `LinkageError`, outside `NonFatal` — `Server.request`
  (`Rpc.scala:478-480`) logs the stack trace and answers `method + " failed: " + e`.
- mssql-jdbc's messages name host, port and user ("Login failed for user 'x'") (*external*).
  Not secrets, but §8.4's "grep for the JDBC URL" would count the host.

**Correction.** (i) The classifier catches `Throwable`, and every answered/logged message has
the profile's `url` string (and the `user`) replaced before it leaves the preview thread.
(ii) The extension validates `url` and refuses one containing `password=`, `pwd=`, `user=`
or `integratedSecurity` (*external*: mssql-jdbc property names). (iii) §8.4 gains a row:
connect with a driver that rejects the URL; grep the log and the output channel for the URL
and the host: 0 hits.

### 6. What the preview thread and the dispatch thread still share — MINOR

"Never blocks the dispatch thread" is true up to the following, none of which the document
lists:

| Shared | Where | Effect |
|---|---|---|
| `SessionTask.pool`, a cached pool with no bound | `SessionTask.scala:19-24` | a render's module load and a check's import load compete for cores, not for threads; on a 4-core laptop a check slows while a render loads |
| `Phases` | `Phases.scala:31-49`; reset by `Resident.boot` `:138`, `reloadModules` `:238` and `Diagnostics.run` | with `-Dermine.lsp.phases=true` (what `perf-bench.sh` uses) a render in flight adds its `Session.loadModules` timings to the next check's phase line; perf figures taken with a preview open are polluted. Say the preview thread records nothing, or that perf-bench runs with the preview off |
| `Wire.send` under the new monitor | `Rpc.scala:340-346` | a multi-megabyte document written to a slow client holds the monitor; the dispatch thread's next `publishDiagnostics` waits behind it. Bounded by the pipe and a client that reads continuously; state it |
| `Type.Con.memoizedKindSchema`, a non-volatile `var` on `Con`s that `Lib` shares | `Type.scala:231`; `Lib.scala:165-192` | both threads may memoise the same `Con`'s kind schema; the write is idempotent, so benign — but it belongs in the §2.2 table, which claims to be "every process-wide mutable object" |
| `Server.ask` / `clientPending` | `Rpc.scala:413-426`, plain vars | dispatch-thread only; the design should say the preview thread never calls `ask` (it uses `notify` and the deferred answer only) |

The rest of the sweep found nothing the table missed that breaks (C): `Session.depCache` is a
`ConcurrentHashMap` (`Session.scala:110`), `ForeignClasses` maps are concurrent (`:41`, `:52`),
`Supply.getBlock` is `synchronized` (`Supply.scala:7-10`), `PrimExpr._dateFormatTemplate`
(`:512`) is cloned per thread by `dateFormatterTLV` (`:501-504`), `Run.lazyRefGenOverride`
(`Run.scala:95`) has no writer in `core`, `Main.logSink` is a `PrintWriter` whose `println`
is synchronised (`Main.scala:13-20`), and no object-level `Thunk` exists (grep).

### 7. The manual reload path and a client without dynamic watchers never invalidate the preview — MINOR

§3 step 3 posts `invalidate` from the `didChangeWatchedFiles` handler only
(`Main.scala:256-269`). `ermine.reloadModules` (`:271-280` → `reloadStale`) reloads the
resident and does not; a client that cannot register watchers (`:214-217`) has only that
command. The render session then serves a stale report indefinitely. **Correction.** Post
from `afterReload` (`:179`) for both callers, and — cheaper and watcher-independent — have the
render session run `reloadStale`'s mtime scan (`Resident.scala:271-273`:
`Session.depCache.get(sf).map(_._1) != sf.lastModified`) over its own `loadedFiles` at the
head of every render. That also makes edits from outside VS Code visible.

### 8. The connect/recycle protocol has a 503 gap, and A7 must cover the automatic reconnect — MINOR

After `ermine/preview/disconnected` (§7.2) the extension sends a fresh `connect`; an
`invalidated`-driven render that lands between the two is answered `503 not connected` (§4)
and the panel shows a banner until the next save. **Correction.** The extension re-sends the
last render after every successful `connect`. Separately, A7's "refuses to connect while the
trace is `verbose`" is written for the user-initiated connect; the recycle-driven reconnect
runs unattended and must apply the same refusal (and say so in the status bar), or a trace
level flipped to `verbose` after the first connect leaks the password on the next recycle.

### 9. Classifier: locked, expired and must-change accounts are `connect`, so the secret is replayed on every recycle — MINOR

§8.3 names `18456` only. SQL Server reports a locked account as `18486`, an expired password
as `18487`, and must-change as `18488` (*external*). All three fall into `connect`, keep the
secret, and are retried unattended on each recycle (§7.2), which keeps a locked account
locked. Add them to `auth` (or to "prompt next time" without deleting), and pin them with the
fake driver.

### 10. "Referenced by nothing after the call" describes the server's code, not the process — MINOR

§7.2 row 1. The JDBC driver's `Connection` retains its connection properties, password
included, for reconnect/failover (*external*, mssql-jdbc). The claim is true of
`lsp/Preview.scala` and false of the heap, and the heap-dump concession beside it should say
so, since WP-12's done-when is a code review of exactly that claim.

### 11. Memory and boot cost: "unmeasured" is honest but can be bounded now — MINOR

No `-Xmx` anywhere (`bin/ermine-lsp`, `extension.js`), so the cap is a quarter of RAM
(*external*): ~4 GB on the 15.6 GB dev box (`PERF-ROADMAP.md:139`), ~2 GB on an 8 GB laptop,
and §5's "two windows" row makes that four sessions. No RSS figure for the resident exists in
the tracker (grep for `RSS`/`resident set`/`heap`: only `README.md:121`'s 1.6 MB per open
document). The render session's closure is not small: `Layout.Fetch` imports `Native.*`,
`Control.Monad`, `Control.Monad.Cont`, `Function`, `List`, `Pair`, `Relation.Sort`,
`Relation.Scan` (`Fetch.e:45-55`) and `Sales` imports `Relation`, so a large fraction of the
resident's 129 modules is loaded twice. WP-4 should record boot seconds as well as RSS, and
§2.2 should state the default-heap arithmetic so the work-laptop case is a number, not a
shrug.

### 12. Ticket hygiene — MINOR

- WP-3: `Runner.invalidate` must take `evalLock`; the LSP calls it from one thread, but
  `TestRunner` runs properties concurrently over one runner (`:806`) and the §11 `invalidate`
  properties will race a render otherwise.
- WP-4: the preview thread must be a daemon thread; the "render whose evaluation loops"
  property leaves it spinning, and a non-daemon thread keeps the forked test JVM alive.
- WP-2 done-when "deletions plus two call sites": `scrub` is called at `Resident.scala:212`,
  `:231`, `:461` and `dependentsOf` at `:208`; four call sites plus the `builtins` threading.
- §2.2 row 1's "written by" column must add `TolerantCheck.scala:862` (finding 1).
- `previewRoots` "workspace-relative": relative `moduleRoots` resolve against the server's
  cwd (`Main.scala:102-104`), which is `server.root` (`extension.js:151`), not the report's
  folder; say the extension absolutises them as it should for `moduleRoots`.

## New claims checked and confirmed

- `DataConDecl.scala:44-54` comment, `:55-56` two `ConcurrentHashMap`s, `:58-62` `register`;
  writers at `Lib.scala:45`, `:1472` and `Session.scala:915` (inside `processTypeDefComponent`,
  `:896`). Entries from two sessions differ in `Supply`-minted `TypeVar` ids (`typeArgs`,
  `existentials`, field `VarT`s) but every reader is id-insensitive (`Encode.userData`
  `:399-413` uses `isEnum`, `constructor(g)`, field names; the Schema/Decode fallbacks at
  `Schema.scala:240`, `:319`, `Decode.scala:232`, `:402` substitute `d.typeArgs` internally),
  so **ids** are not the problem — buffers are (finding 1).
- `SessionTask.fork` copies the env and `join` merges it back (`SessionTask.scala:26-37`,
  `:41-45`); `loadMore` forks each make (`Session.scala:639`, `:656`, `:672`), so the registry
  is indeed already written from pool threads inside one load.
- `Session.depCache` is a `ConcurrentHashMap` (`Session.scala:110`, "was HashMap with
  SynchronizedMap"); `Session.cache` writes it only for sources with a `lastModified`
  (`:405`); `Buffer` is content-keyed with the version as its mtime (`:274-290`).
- `Runners` has only `def`s (`Backends.scala:32-55`); `liteDB` is a `def` (`:39`),
  `sqliteTestDB` a `lazy val` (`DB.scala:140`): WP-3's "loads no JDBC driver" is achievable.
- `fromPersistentConnection` (`Backends.scala:49-51`) hands one `Connection` to every caller;
  `SqlScanner.transaction` (`:193-195`) wraps each scan in `DB.transaction` (`:19-29`) when the
  emitter is transactional; temp tables are `guidName` = UUID (`SqlScanner.scala:305`,
  `:892`, `:919-922`, `:940`; `package.scala:19`), so the two-windows case cannot collide.
- `Runner.evalLock` rationale (`Runner.scala:246-260`, `:614-624`) names the registry,
  `Supply` and `Thunk.state`; `Runner` supplies are per thread (`:280-283`); `Resident` has
  one supply (`:33`); `Supply.getBlock` is synchronised (`Supply.scala:7-10`).
- `Runner.compile` (`:429-482`) loads on demand, evaluates the bare binding (`:458`),
  `reportSignature` (`:464`), caches only success (`:411-420`); `reports` is a
  `ConcurrentHashMap` (`:296`).
- `Rpc.scala`: `Wire.send` unsynchronised (`:340-346`); `handle` (`:442-469`) with the
  unparseable branch at `:448-450`; `request` synchronous (`:471-482`); `$/` dropped (`:488`);
  one idle slot (`:394-398`); reader and dispatcher one loop (`:429-440`).
- `Resident.scala`: single-thread comment `:13-18`, `~13s` `:24`, boot `:103-140` with
  `_foreignTolerant = Some(true)` `:118-120`, `builtins` `:122`, roots chain `:125-129`,
  `loadedByPath` `:178-181`, `dependentsOf` `:186-198`, `reloadModules` `:205-241`, `reload`
  `:251-265`, `reloadStale` `:270-275`, `scrub` `:286-302`, `checkFile` `:401`, buffer read
  `:412-413`, sibling loaders `:435-440`, `moduleUnder` `:699-704`.
- `Main.scala`: roots `:106-120`, watcher registration `:202-213`, no-dynamic fallback
  `:214-217`, `afterReload` `:179-194` with `recheckAll` `:188`, `didChangeWatchedFiles`
  `:256-269`, `executeCommand` `:271-284`; `log` is a `PrintWriter` (`:13-20`).
- `TolerantCheck.scala:862` (the third registry writer); `SessionState.scala:95-113` copy,
  `:130-131` `foreignTolerant` default; `Session.scala:1405-1412` `foreignStub`.
- `Lib.scala:165-192` object-level `Con`s and the two `Data` constants (`:168`, `:180`);
  `preamble` at `:1495`; `toJson#` installed per env at `:1478`.
- `Phases.scala:25` `enabled`, `:31-33` maps, `:42`, `:46`, `:49` synchronised.
- `ForeignClasses.scala:41`, `:52` concurrent maps. `SqlExecution.scala:47-50` and
  `DB.scala:39-45` `setQueryTimeout(300)`. `DB.scala:106-116` `Run`, `:129-138` `RunUser`.
- `relational/package.scala:136-142` `withDriver` `finally`.
- `Schema.scala:184` `exportType`, `:206-210` `exportNamed`, `:800-816` `LspSchema.answer`
  (`withEnv`, `loadModules(List(m))`); `Decode.scala:122` `reportSignature`.
- `TestLspRobustness.scala:34`, `:82`, `:86`, `:94`, `:168`, `:241`, `:307`, `:455`, `:554`,
  `:583`, `:655`; `TestRunner.scala:77`, `:112`, `:806`. `Definitions.scala:226-228`.
- `extension.js:43-46`, `:49-55`, `:145-151`, `:179`, `:241-256`; `package.json:5`, `:8-9`,
  `:43-47`, `:63-72`, `:75-92`, `:98`. `bin/ermine-lsp:4`, `:12-16`, `:19`, `:20`, `:25`;
  `bin/ermine-serve:32-33`. `LSP-STALENESS.md:40`; `JSON-GUIDE.md:1452-1453`, `:1571`,
  `:1577-1583`; `build.sbt:1`, `:111-113`; `Sales.e:107`; `lsp-client.py:57`, `:605-608`;
  `SqlEmitter.scala` `:38`, `:269`, `:276`, `:431`, `:538`, `:597`, `:615`, `:621`, `:676`,
  `:699`, `:843`, `:864`, `:866`, `:877`, `:881`; `Fetch.e:45-55`, `Doc.e:29-30`.

## Questions that must be answered before implementation

1. Which of (a)/(b)/(c) in finding 1 is adopted, and does `evalLock`'s registry rationale
   (`Runner.scala:614-619`) survive it? (Finding 1.)
2. Is the `untrustedWorkspaces` declaration dropped, or is the spawn gated on
   `workspace.isTrusted`? (Finding 2.)
3. Does the binding mode of `ermine/schema` run on the preview thread against the render
   session, or does the resident's loader chain gain the preview roots? (Finding 3.)
4. What does the user see, and what is measured, when a runaway evaluation allocates?
   (Finding 4.)
5. Is `url` validated for embedded credentials, and is every driver message scrubbed of the
   URL and host before it is answered or logged? (Finding 5.)
