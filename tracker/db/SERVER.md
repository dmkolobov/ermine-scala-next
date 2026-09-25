# SERVER: the SQL Server driver (WP-12(a)) and the preview connection profile (WP-13 design)

Role `server` of the DB programme (`tracker/DB-PLAN.md` §3). Stage 1 builds the driver and
the smoke; stage 2 builds §2 below. **§2's server half is WIRED as of 2026-09-24 (stage 2a): see §6 for what was built and measured.** Line numbers are at the
worktree's `f899958b` plus this stage's uncommitted diff. MEASURED = run here; MINED = read
from the source at the cited line; *external* = documented behaviour, not run.

## 0. What stage 1 built

| Item | Where | Status |
|---|---|---|
| `"com.microsoft.sqlserver" % "mssql-jdbc" % "13.6.0.jre11"`, Compile scope of `core`, beside mysql/jTDS/sqlite | `build.sbt:111-116` | MEASURED: resolves; the exported `core/fullClasspath` gains exactly ONE jar and nothing else (diff of the classpath before/after: `+ .../mssql-jdbc-13.6.0.jre11.jar`) |
| The jar | `~/.cache/coursier/v1/https/repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/13.6.0.jre11/mssql-jdbc-13.6.0.jre11.jar` | MEASURED: 1 576 575 bytes; sha256 `4c566e4022c4dcf1489aeb639fe49a0f6ffae3d796fdc2f56b5b8882d4c3bf5a` |
| Its pom | same directory, `mssql-jdbc-13.6.0.jre11.pom` | MEASURED: 28 169 bytes; sha256 `06bd0a5c382cdc4af2fe9a9a97bc05eaa032c82dd60d3d4819c7f2e5e3bd792f`; no `<parent>`; 42 `<dependency>` entries, none of which reached the classpath (all optional/test/provided) |
| The launchers' classpath cache | `target/ermine-classpath` | deleted and rebuilt by `bin/ermine-schema` (`bin/ermine-schema:29-35`: rebuilds when the file is empty or `build.sbt` is newer; `bin/ermine`, `bin/ermine-lsp`, `bin/ermine-serve` share the same file and rule, `:13-15`, `:10-12`, `:21-23`). MEASURED: rebuilt, contains the jar, `bin/ermine-schema --widgets Layout.Widgets \| head -3` prints the generated header |
| JDBC smoke, two properties | `scalacheck-binding/src/main/scala/TestMsSqlSmoke.scala` | "driver resolves" (no server; always runs) and "live connect" (NOT registered without `ERMINE_DB_URL`/`_USER`/`_PASSWORD`: one "DB suites: not requested" line instead, since the `suites` gate fails on a SKIPPED property); MEASURED green in both modes, §3; gated by `db`, §5 |
| The runnable | `tracker/tools/db-smoke.sh [--skip]` | sources the password from `~/.config/ermine/db.env` into the sbt JVM's environment only; exit 0/1/2 (another sbt)/3 (no password) |

## 1. How a connection profile reaches the scanner today

There is **no profile** yet. Three code paths pick a backend, each from a dialect NAME; none
infers a dialect from a URL (grep for `"jdbc:` in `core/src/main`: three hits, all
`jdbc:sqlite::memory:` defaults, `ServeMain.scala:17,41`, `Preview.scala:2222`,
`DB.scala:140`).

| Step | Path A: the preview (LSP) | Path B: `bin/ermine-serve` / `RunnerConfig.backend` | Path C: legacy |
|---|---|---|---|
| Where the dialect comes from | the constant `StageABackend = "sqlite"`, `Preview.scala:2221` | `--dialect NAME` (default `sqlite`), `ServeMain.scala:18,42,69` | none: hard-wired |
| Where the URL comes from | the constant `StageAUrl = "jdbc:sqlite::memory:"`, `Preview.scala:2222` | `--db URL`, `ServeMain.scala:17,41,68` | system property `db.dev.ds.url`, `Backends.scala:90-92` |
| Dialect -> scanner (emitter) | `Backends.scannerFor(dialect, variant)`, `Backends.scala:38-55`; `mssql`/`sqlserver` + `default` -> `Scanners.MicrosoftSQLServer` (`:42`, emitter `SqlEmitter.msSqlEmitter`, `:75`), + `noTransactions` -> `MicrosoftSQLServerNoTransactions` (`:43`, `:76`); dialect case-insensitive under `Locale.ROOT`, variant exact; unknown dialect / `noTransactions` on another dialect -> `Left` (`:47-54`). Called at `Preview.scala:1847` with `"default"` | `RunnerConfig.backend(dialect, url)`, `Runner.scala:188-200`: a closed match, `mssql`/`sqlserver` -> `(Runners.MicrosoftSQLServer(url), Scanners.MicrosoftSQLServer(sms))` (`:192`); no variant; its refusal string CARRIES THE URL (`:198`) | `Scanners.cloudScanner` = MSSQL (`Backends.scala:78`), used by `remote/BackendServer.scala:38` |
| Dialect -> driver class | not yet: the preview calls `Runners.SQLite(StageAUrl)` directly (`Preview.scala:1866`) | fixed per dialect in `Runners`, `Backends.scala:81-86`; SQL Server = `com.microsoft.sqlserver.jdbc.SQLServerDriver` (`:83`) -- the class this stage's jar provides | `net.sourceforge.jtds.jdbc.Driver` (`Backends.scala:92`): **the only jTDS user**; `Runners.cloudDB` has one caller, `BackendServer.scala:38` |
| Opening a connection | `DB.Run(driver)(url)`, `DB.scala:106-117`: `Class.forName` eagerly, then `DriverManager.getConnection(url)` **per run**, closed after it; no user, no password | same `DB.Run` | same |
| With a user and password | nothing calls it: `DB.RunUser` (`DB.scala:129-138`) reconnects per run and closes over the password; the tracker rejects it (§7.2) | not reachable: `--db` has no user flag | — |
| Held connection | `Runners.fromPersistentConnection(conn)` (`Backends.scala:98-100`) exists, zero callers | — | — |
| Where it is swapped | `DelegatingRun` (`lsp/DelegatingRun.scala:44-75`): `use(r)` answers the target it replaced, `clear()` the one it removed, `run` throws `NotConnected` when unset; the Runner is built ONCE around it with the scanner FIXED (`Preview.scala:1868`, `RunnerConfig.scanner` is an immutable field, `Runner.scala:175`) | the pair goes straight into `RunnerConfig` | — |
| What uses the pair | `Runner` runs every scan inside `cfg.run.run(... (cfg.scanner, ...))`, `Runner.scala:511` (delivery) and `:935` (the Fetch interpreter) | same | — |
| "Not connected" | `doRender` asks `delegating.connected` BEFORE rendering and answers 503 "not connected", `Preview.scala:1498-1499` (unreachable in stage A: nothing clears the delegate but `discardSession`, `:1909-1919`, which also drops the Runner) | — | — |
| Scrub | `Preview.scrubUrls` replaces any `jdbc:...` token with `<url>` (`Preview.scala:2583-2586`); `Rpc.Redacted = Set("ermine/preview/connect")` already redacts the connect body in the wire log (`Rpc.scala:276`, WP-1) | none: `:198` prints the URL | — |
| `database "X"` in a module | parsed and bound (`Session.processTableStatement`, `Session.scala:2050`) but never emitted: the CONNECTION decides the database (DB-PLAN D5) | same | same |
| Type decoding on read | `MsSqlEmitter.sqlPrimT` maps by type NAME: `"date"` -> `DateT`, `"datetime"`/`"datetime2"` -> `TimestampT`, else by `java.sql.Types` (`SqlEmitter.scala:881-885`); the comment "jtds gives x = varchar for dates" (`:882`) was written for jTDS. The live smoke reads a `date` column through it (§3) | same | same |

So the seam for WP-13 is exactly two lines of `Preview.ensureSession`: `:1847` (which
dialect) and `:1866` (which `Run[DB]`), plus the two constants at `:2221-2222`.

## 2. Design: the preview connection profile (stage 2, NOT wired)

The design is the playground tracker's §7 and §8 **as amended by the user on 2026-09-20**
(prompted password held for the window, no secret store); this section says how it lands on
the code in §1 and what the DB programme adds. Every "extension" claim is unobserved.

### 2.1 Setting shape

Two shapes are on the table; the tracker's §7.1 already specifies the first, DB-PLAN §2's one
line reads like the second.

| | (a) profile list (tracker §7.1) | (b) one object |
|---|---|---|
| Settings | `ermine.preview.profiles`: `[{id, dialect, driver?, url, user?, scanner?, settings?, deploy?}]` + `ermine.preview.profile`: the active `id` (default `local`) | `ermine.preview.database`: `{url, user?, dialect, scanner?}`; absent = in-memory SQLite |
| Switch MSSQL <-> SQLite twin | change one string (a status-bar picker is natural) | edit the object |
| `deploy` badge (WP-16) | has a place to live | needs a second setting |
| Built-in `local` | the implicit profile `{id: local, dialect: sqlite, url: jdbc:sqlite::memory:}` | the "absent" case |
| Scope | **user scope only** (A2: `inspect(...).globalValue`; a workspace value is ignored and named once) | same |
| Password field | none (A1): the `contributes.configuration` schema has no such property | same |

A named profile FROM A FILE (e.g. `~/.config/ermine/profiles.json`) was considered: it would
keep the work server's URL out of VS Code's settings (and Settings Sync), but it is a second
configuration channel the extension has to watch, and A1/A9 already keep secrets out of
settings. Listed as a question (Q-S1), not recommended.

Example for this programme (shape (a)):

```jsonc
"ermine.preview.profiles": [
  { "id": "sales-mssql",  "dialect": "mssql",
    "url": "jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true",
    "user": "ermine" },
  { "id": "sales-sqlite", "dialect": "sqlite", "url": "jdbc:sqlite:/abs/path/to/ErmineSales.db" }
],
"ermine.preview.profile": "sales-mssql"
```

### 2.2 Where the prompted password enters

| Step | Where | What |
|---|---|---|
| 1 | extension, its ONE `connect()` function | refuse if `ermine.trace.server` is `verbose` (A7); refuse a `url` matching the A9 credential regex; if the active profile has a `user` and no password is held for `(id, url, user)`, `showInputBox({password: true, ignoreFocusOut: true})` naming `user @ host (id)` |
| 2 | extension host memory | a `Map` keyed by `id + "\0" + url + "\0" + user` (a changed URL or user is a new key and prompts again -- A3's replay protection without a store). Never written to disk, `globalState`, a webview message or a log |
| 3 | wire | `ermine/preview/connect {profile, password?}` over stdio (A4); the body is already redacted in the server's wire log (`Rpc.scala:276`, WP-1 DONE) |
| 4 | server, preview queue | a `Connect` job (a queue job, so it orders after an in-flight render): `DriverManager.getConnection(url, user, password)` with the password passed as a `Properties` entry; the `password` string is referenced by nothing after the call. The driver's `Connection` retains it until closed (*external*; tracker §7.2 says so) |
| 5 | forgetting | window close/reload (memory is gone); **Ermine: Disconnect Database** (clears the map entry, sends `disconnect`); an `auth, kept: false` answer (A8) |
| 6 | reconnect | after `disconnected {reason}` or a server restart (`Running`), the extension re-sends `connect` with the HELD password -- automatic, per the user's decision -- and re-sends the last render on `ok` |

### 2.3 "Profile or in-memory": what replaces `Preview.scala:2219-2222`

| Piece | Today | Stage 2 |
|---|---|---|
| State | `delegating`, `runner`, `rootsInUse` (preview thread only, `Preview.scala:29`, `:417`) | + `active: Option[ActiveProfile(id, dialect, scanner, host, conn)]`, preview thread only |
| `ensureSession` dialect (`:1847`) | `StageABackend` | `active.map(_.dialect).getOrElse("sqlite")`, variant `active.map(_.scanner).getOrElse("default")` |
| `ensureSession` target (`:1866`) | `del.use(Runners.SQLite(StageAUrl))` | `active` present: `del.use(Runners.fromPersistentConnection(conn))`; absent: today's line unchanged (the implicit `local`: per-run in-memory SQLite, every existing test and the Doc fixtures keep their behaviour) |
| `Connect` job | — | validate (§2.5) -> `Backends.scannerFor` (a `Left` answers class `profile` before any socket) -> `Class.forName(driver or Runners' default)` -> `getConnection` with a login timeout (below) -> close the previous `active.conn` -> `discardSession("profile changed")` because the scanner is baked into the `Runner` (§7.2 step 4) -> set `active` -> answer `{ok: true, host}` |
| `Disconnect` job | — | `discardSession`, close `active.conn`, `active = None` **and** leave the delegate unset so renders answer the existing 503 (`:1498`) -- see Q-S2 for whether a disconnected preview should instead fall back to `local` |
| Close must not block | `discardSession` closes nothing (`:1910-1914`) | the close of a held connection gets a bounded wait or runs off the preview thread (WP-14's S3 note, tracker §14) |
| Login timeout | — | the preview thread must not sit in `getConnection` on an unreachable host: pass `loginTimeout` (mssql-jdbc property, seconds, *external*) or `DriverManager.setLoginTimeout`, below `ermine.preview.timeoutSeconds` (default 60, `Preview.scala:2226`) |
| Scrub | `scrubUrls` (`:2583`) | A10: also the profile's `url`, `user` and host (`<url>`/`<user>`/`<host>`), applied to every connect answer and to render 500s while a profile is active |

### 2.4 Failure answers and how the panel shows them

The wire already fixes the connect answer: `{ok: false, class: "auth" | "driver" | "connect",
kept, message}` (tracker §4 row `ermine/preview/connect`; classification §8.3). This design
adds one class for what fails before any socket opens:

| Class | Trigger | `kept` | Message (scrubbed) |
|---|---|---|---|
| `auth` | SQLState `28000` / vendor `18456` | false | "login failed for `<user>` @ `<host>`" + driver text |
| `auth` | `18486`/`18487`/`18488` (locked / expired / must change) | true | names the reason; never retried unattended |
| `driver` | `ClassNotFoundException`, "No suitable driver" | true | "driver `<class>` not on the classpath" / "no driver accepts this URL" |
| `connect` | everything else: refused, DNS, timeout, TLS | true | driver text; a TLS failure is NOT an auth failure (Q3's first connect) |
| **`profile`** (NEW, Q-S3) | unknown dialect, `noTransactions` on non-MSSQL (`Backends.scala:47-54`), a URL whose subprotocol disagrees with `dialect` (`jdbc:sqlserver:` with `dialect: sqlite`), a `jdbc:sqlite:` file that does not exist (sqlite-jdbc would create an empty one, *external*) | true | the `scannerFor` `Left` text, or "dialect sqlite does not match a jdbc:sqlserver URL" |

The panel already has the kind: `{kind: "error", status, message, path, reason}`
(`client/src/host/index.ts:44-46`, built by `panelErrorMessage`, `editor/vscode/src/preview-core.js:5351-5360`).
A failed connect is not a render answer, so the extension builds that message itself:
`status: 503`, `message: "<id> (<dialect>) @ <host>: <class>: <message>"`, `path: null`,
`reason`: see Q-S4. The status bar reads `id (dialect) @ host` connected, `id: <class>` failed.
The render that triggered the connect is answered by the existing 503 "not connected".

### 2.5 The SQLite twin (D13) as a profile

A twin is an ordinary profile `{id: "<domain>-sqlite", dialect: "sqlite", url: "jdbc:sqlite:<abs path>.db"}`
with no `user`, so no prompt (`getConnection(url)`, tracker §4). What the DB programme adds:

| Point | Consequence |
|---|---|
| The loader (DB-PLAN §2, `load-sqlite.ts`) writes the file | the profile names its absolute path; a relative path would resolve against the server's cwd (the checkout root, `bin/ermine-lsp`), so the extension should resolve it against the first workspace folder the way `ermine.preview.roots` is resolved, or refuse it (Q-S5) |
| Held connection on a file | the file is open while connected; `db down`/a reload of the twin while the panel is connected must disconnect first, or the loader writes under an open reader (SQLite allows it; what the held connection then sees is *external*, unverified) |
| Same rows, two dialects | switching `sales-mssql` <-> `sales-sqlite` is the §9.3 divergence observed with identical data -- the reason D13 exists |

### 2.6 Open questions for the user (neutral)

| # | Question | Options |
|---|---|---|
| Q-S1 | Setting shape | (a) `ermine.preview.profiles` list + active id (tracker §7.1); (b) one `ermine.preview.database` object; (c) profiles in a file outside settings |
| Q-S2 | What a render does while disconnected | (a) 503 "not connected" until the extension reconnects (tracker §4 as written); (b) fall back to in-memory SQLite, with the dialect badge saying so |
| Q-S3 | Refusals before any socket | (a) a fourth class `profile` on the connect answer; (b) fold them into `driver` (no wire change) |
| Q-S4 | The panel's `reason` for a connect failure | (a) extend `Preview.Reason`'s closed vocabulary with `connect-auth`, `connect-driver`, `connect-unreachable`, `connect-profile` (a wire change, Q15's contract); (b) `reason: null`, the class is in the message only |
| Q-S5 | Relative `jdbc:sqlite:` paths in a profile | (a) resolve against the first workspace folder; (b) refuse, absolute only |

## 3. The smoke, recorded

`tracker/tools/db-smoke.sh --skip` (no credentials), MEASURED 2026-09-24 (before §5 removed the skip-named property; the current no-env output is in §5):

```
[info] + SQL Server driver smoke (WP-12a).live connect SKIPPED: ERMINE_DB_URL / ERMINE_DB_USER / ERMINE_DB_PASSWORD unset: OK, passed 100 tests.
[info] + SQL Server driver smoke (WP-12a).driver resolves: mssql-jdbc on the classpath, both dialect paths answer mssql: OK, proved property.
[info] Passed: Total 2, Failed 0, Errors 0, Passed 2
```

Live run, `tracker/tools/db-smoke.sh` (defaults: `jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true`
as `ermine`, password from `db.env`), MEASURED 2026-09-24 22:15 against infra's container
(2022 CU27). Password grep over the full sbt log: 0 hits.

```
[mssql-smoke] connected in 231 ms via com.microsoft.sqlserver.jdbc.SQLServerDriver 13.6.0.0
[info] + SQL Server driver smoke (WP-12a).driver resolves: mssql-jdbc on the classpath, both dialect paths answer mssql: OK, proved property.
[mssql-smoke] SELECT 1 -> 1
[mssql-smoke] SELECT @@VERSION -> Microsoft SQL Server 2022 (RTM-CU27) (KB5104824) - 16.0.4295.3 (X64)
[mssql-smoke] DB_NAME() -> ErmineSales
[mssql-smoke] encrypt_option -> null
[mssql-smoke] dialect for this URL -> Some(mssql); scannerFor -> Some(SqlScanner)
[mssql-smoke] ## temp table ##wp12_smoke_2...: created; date column reads as java.sql.Types 91 "date" -> sqlPrimT Some(DateT(false)); value 2026-09-24
[mssql-smoke] ## temp table dropped
[info] + SQL Server driver smoke (WP-12a).live connect: SELECT 1, @@VERSION, dialect, date column, ## temp table: OK, proved property.
[info] Passed: Total 2, Failed 0, Errors 0, Passed 2
```

| Finding | Status |
|---|---|
| The `"date"` mapping: mssql-jdbc reports a `date` column as `java.sql.Types.DATE` (91) with type name `"date"`, and `MsSqlEmitter.sqlPrimT` maps it to `DateT` -- the name match at `SqlEmitter.scala:882` fires; the jTDS comment is obsolete but harmless (`defaultDecodeType(91)` would presumably also be a date; not run) | MEASURED |
| `##` temp tables: create, insert, select, drop as `ermine` in ErmineSales | MEASURED (infra also found no grant is needed for `##`, board 22:14) |
| First run FAILED on the smoke's own probe, not the driver: `SELECT encrypt_option FROM sys.dm_exec_connections` needs VIEW SERVER PERFORMANCE STATE (`S0001`/300), which `ermine` lacks, correctly for D3. Replaced by `CONNECTIONPROPERTY('encrypt_option')`, which answers `NULL` for this login | MEASURED; whether the JDBC session is encrypted is therefore NOT shown by this smoke (unverified from JDBC; infra's `db.sh status` reports `tls=TRUE` for a go-sqlcmd session with `-N`) |
| Login to connected: 231 ms (one sample, JVM warm from the other property) | MEASURED, n=1 |

## 4. Closed network (tracker §10, WP-17)

| Need | Detail |
|---|---|
| Artifacts to vendor | `com/microsoft/sqlserver/mssql-jdbc/13.6.0.jre11/` -- the `.jar` and the `.pom` (sha256s in §0); coursier also wants the `.sha1`/`.md5` siblings when checksums are verified. No transitive jar is needed: the pom's dependencies are all optional/test/provided, so the classpath gained exactly one entry |
| Where | the internal Maven registry, or a copy of the coursier cache directory above (`~/.cache/coursier/v1/https/repo1.maven.org/maven2/...`, the path sbt 1.10 resolves from) |
| When | before the first `sbt` on the work machine after this `build.sbt` lands: the launchers rebuild `target/ermine-classpath` the first time they see `build.sbt` newer than it, and that rebuild runs sbt, which resolves |
| JDK | `jre11` runs on 11+; the server runs on JDK 21 |
| Not answered here | Q3 (the work server's CA vs `cacerts`/`Windows-ROOT`) -- WP-12(b), work network only |

## 5. The `db` gate (PR tier) and the end of SKIPPED names

The `suites` gate fails on the word SKIPPED anywhere in its log (`scripts/gates.sh`, `gate_suites`),
and the stage-1 suites registered skip-NAMED properties without `ERMINE_DB_*`, so the stage-1 pr gate
went red on names alone (REVIEW-S1 M1). Now:

| Piece | What |
|---|---|
| `TestMsSqlSmoke`, `TestDbReports` without `ERMINE_DB_*` | register NOTHING for the live sets; print `DB suites: not requested (no ERMINE_DB_* in the environment); the `db` gate runs them` (the SQLite set: `sqlite twin not requested (no file at ...)`) |
| `tracker/tools/db-smoke.sh --skip` | passes only if that line is printed AND the log has no SKIPPED |
| `scripts/gates.sh` `gate_db`, tier pr, timeout 900 | UNAVAILABLE (3), never a pass, when: `scripts/db.sh status` fails (remedy `scripts/db.sh up`); ErmineSales's load stamp is not tier xs (remedy `scripts/db.sh load sales --tier xs`); `data/node_modules` absent; another sbt running. Then it BUILDS the SQLite twin itself (`npm run load:sqlite -- --domain sales --tier xs --seed 42 --db $GATE_OUT/sales-xs.sqlite`), reads the password from `db.env` into sbt's environment only, runs `core/testOnly *TestMsSqlSmoke* *TestDbReports*`, and FAILS on any failed property, on a "not requested" line (the env did not reach sbt), or if the password appears in its log |
| Key | content + `GATE_KEYFN[db]=db_key_extra`: ErmineSales's stamp (tier, seed, manifest sha256), read with `db.sh sql` from the `ermine.load.sales` extended property, because `db.sh status` does not print the tier. `scripts/gate.sh` gained the generic hook (`extra_key`) |

MEASURED 2026-09-24, once each:

```
$ env -u ERMINE_DB_* sbt -batch 'core/testOnly *TestMsSqlSmoke*'
[mssql-smoke] DB suites: not requested (no ERMINE_DB_* in the environment); the `db` gate runs them
[info] + SQL Server driver smoke (WP-12a).driver resolves: ...: OK, proved property.
[info] Passed: Total 1, Failed 0, Errors 0, Passed 1          (SKIPPED in the log: 0)

$ gate_db (body run directly, container up; ErmineSales loaded at xs for it, then reloaded s seed 42, verify OK)
first try at tier s: SUMMARY ErmineSales holds tier s, the twins pin tier xs (run scripts/db.sh load sales --tier xs)   rc 3
at xs, twin built by the gate:
load sales sqlite tier=xs seed=- rows=39 load=0.36s ... verify=OK
[info] Passed: Total 18, Failed 0, Errors 0, Passed 18
SUMMARY db 18 properties, 18 passed, twins equal, totals pinned (ErmineSales tier xs)            rc 0, SKIPPED 0
```

**Design nit for stage 2 (the orchestrator's):** a gate must not depend on which tier the user has
loaded. The `db` gate should load tier xs into its OWN database (e.g. `ErmineGate`, created by
`db.sh up`, with the loader's `load` gaining `--db`); the key-on-load-stamp and the tier-xs
UNAVAILABLE are workarounds for that, and they make the gate unrunnable whenever ErmineSales is at s.

### 5.1 Round 2 fixes (REVIEW-S1 R2-1, R2-2)

| Fix | What | MEASURED |
|---|---|---|
| R2-1 | `scripts/gate.sh` `extra_key`: a gate WITH a key function whose function fails or prints nothing gets an `uncached/<key>-<time>-<pid>-<random>` key and exit 1; `run` then prints why and does not write the result (`gwrite=0`); `status` shows `-`. Never a silent content-only key | on a COPY of gate.sh/gates.sh with `db_key_extra` forced to fail and a stub body: two consecutive `run db` both RAN (`gate db PASS`, no CACHED-PASS), each printed "key function db_key_extra failed or printed nothing; this run is uncacheable ...", 0 `.result` files written (the two empty `uncached/` dirs removed afterwards) |
| R2-2 | the leak check reads the password from a file descriptor, `grep -qFf <(printf '%s\n' "$pw")`, not from grep's argv | the body run below |
| nit | `docs/gate-policy.md` now says the key does NOT hash the SQLite twin (the gate builds it from tier xs, which content covers) | — |

Body run once after the fixes, ErmineSales at tier xs (not changed): `SUMMARY db 18 properties, 18 passed, twins equal, totals pinned (ErmineSales tier xs)`, rc 0, SKIPPED 0.

## 6. WP-13 server half, as built (stage 2a, 2026-09-24/25)

Role `server-profile`. Uncommitted at writing. Everything in `lsp/Preview.scala` sits inside
`// ===== WP-13 profile (server-profile) =====` fences; stage 2b (`// ===== S2b trace =====`)
shares the file and reads `activeConnection` / `active.database` for the trace's connection line.

### 6.1 The wire

| Method | Shape as built |
|---|---|
| `ermine/preview/connect` | `{profile: {id, dialect, url, user?, driver?, scanner?}, password?}` -> `{ok: true, id, dialect, host, database, server, seq}` or `{ok: false, class, message, kept, reason}`; class `auth` \| `driver` \| `unreachable` \| `profile`, reason `connect-<class>`; a connect refused while STUCK adds `"stuck": true` (class `unreachable`, kept) |
| `ermine/preview/disconnect` | `{}` -> `{ok: true}` (idempotent) |
| `ermine/preview/disconnected` | notification `{reason: "connection-lost"}` |
| render while disconnected | `{ok: false, status: 503, message: "not connected", reason: "not-connected", generation, trace}` (the `trace` key is stage 2b's) |

### 6.2 How §2 landed

| §2 item | As built |
|---|---|
| 2.1 setting shape (Q-S1 a) | the server takes ONE profile per connect; `ermine.preview.profiles` + `ermine.preview.profile` are read by the extension (stage 2c) |
| 2.2 password | a `Properties` entry `password` next to `user`, only when the profile has a `user` (a password without one is a `profile` refusal); nothing in `Preview.scala` references it after `getConnection`; `ConnectRequest`/`Profile` `toString` print neither password nor url |
| 2.3 profile or in-memory | fields `active` / `disconnected` / `connectSeq` (preview thread only). `ensureSession`: dialect+variant from `active` else `sqlite/default`; target `Runners.fromPersistentConnection(active.conn)`, else stage A's `Runners.SQLite(StageAUrl)` unchanged, else (disconnected) the delegate stays unset |
| queue | `Connect` / `Disconnect` are `Answering` jobs (watchdog, cancel, shutdown drain, crash answer all apply); not "latest wins" |
| close | owned by `active`, never by `discardSession` (which stays non-blocking on Q10's unwatched recovery path); `closeOffThread` = daemon thread + 2 s bounded join; also on thread exit |
| login timeout | mssql-jdbc `loginTimeout` property = half `timeoutSeconds`, clamped 1..15 s (15 when the watchdog is off); never `DriverManager.setLoginTimeout` (process-wide); other dialects rely on the watchdog |
| liveness | `isValid(2)` before each render on a held connection; dead -> discard, close, disconnected, `disconnected {connection-lost}`, the render answers 503 |
| 2.4 failures (Q-S3 a, Q-S4 a) | validation on the DISPATCH thread before any socket or queue, class `profile`: missing/ill-typed keys, `Backends.scannerFor` refusal, url not `jdbc:`, A9 keys (any case) or `//user:pass@`, subprotocol vs dialect, relative `jdbc:sqlite:` (Q-S5 b), missing sqlite file. Classifier on SQLState / vendor code over the cause chain: `18456`/`28000` auth kept:false; `18486-18488` auth kept:true; `ClassNotFoundException`/`LinkageError`/"No suitable driver" driver; else `unreachable` (incl. TLS, `4060` unknown database) |
| scrub (A10) | the profile's url (literal), host and user (as tokens: not inside `ermine.preview.*` or `ermine/render`; terms under 3 chars skipped) are scrubbed from every log line and from the top-level `message`/`error` of every answer; documents and traces are never scrubbed |
| `host`/`database` | parsed from the URL (`databaseName`/`database`/`serverName` for SQL Server, `//host/db` otherwise, `local` + file name for SQLite); `getCatalog` only if the URL names no database. `server` = `getDatabaseProductVersion` |

### 6.3 Tests, run once each

`TestPreviewProfile` (core/test, no env), MEASURED 2026-09-24 23:4x: `Passed: Total 9, Failed 0` — validation
refusals (17 cases + 100 generated A9 URLs, none echoing password/host/url), well-formed profiles, host/database
parsing, the classifier on constructed exceptions (incl. a wrapped 18456 and a TLS cause), answer key order,
the scrub, the login timeout, and a wire bench: refused connect, `driver` failure, disconnect -> 503
`not-connected` with 0 boots, a held `:memory:` SQLite profile that renders.

`TestPreviewDbLive` (env-gated, added to the `db` gate's testOnly list), MEASURED 2026-09-25 00:04 with
ErmineSales loaded at xs for the run and reloaded at s (seed 42, verify OK) afterwards. Output (the password
never appears; 0 hits of a `grep -f` over the full log):

```
[preview-db] ErmineSales holds tier xs
[preview-db] in-memory FetchTopN: ok=Some(true) in 5061 ms
[preview-db] connect answered in 24 ms (request to answer, over the wire): {"jsonrpc":"2.0","id":2,"result":{"ok":true,"id":"sales-mssql","dialect":"mssql","host":"127.0.0.1","database":"ErmineSales","server":"16.00.4295","seq":1}}
[preview-db] DbFetchTopN on ErmineSales: ok=Some(true) in 2211 ms (includes the re-boot)
[preview-db] DbFetchTopN again (session warm): ok=Some(true) in 22 ms
[preview-db] document vs the in-memory twin: bytes differ, modulo row order EQUAL
[preview-db] disconnect: {"ok":true}; render after it: {"ok":false,"status":503,"message":"not connected","reason":"not-connected","generation":4,"trace":{...}}
[preview-db] wrong password answered in 36 ms: {"ok":false,"class":"auth","message":"login failed for <user> @ <host>: SQLServerException: Login failed for user '<user>'. ClientConnectionId:...","kept":false,"reason":"connect-auth"}
[preview-db] log: preview: connected sales-mssql (mssql) @ <host> / ErmineSales in 13 ms, seq 1
[preview-db] log: preview: connect sales-mssql (mssql) failed in 33 ms: auth (the password is not kept): SQLServerException: Login failed for user '<user>'. ...
[info] + ... live: connect ErmineSales, render DbFetchTopN == FetchTopN (row order aside), disconnect -> 503, wrong password -> auth kept:false: OK, proved property.
[info] Passed: Total 1, Failed 0, Errors 0, Passed 1
```

| Measure | Value (n=1) |
|---|---|
| connect, `getConnection` inside the job | 13 ms (the driver class was already loaded by the suite's own stamp query, so this is a warm-JVM login) |
| connect, request to answer over the wire | 24 ms |
| first render after connect (session re-boot, the scanner changed) | 2.2 s; the next render 22 ms |
| wrong password to `auth` answer | 36 ms |

### 6.4 Open

| # | Item |
|---|---|
| P1 | A cold-JVM connect (driver class not yet loaded) is not measured. |
| P2 | `##` temp tables accumulate on the held connection until disconnect (WP-14's 1-hour count is not run). |
| P3 | the classifier is pinned on constructed exceptions, not on a registered fake `java.sql.Driver` (tracker §8.3's test shape); the live wrong-password case is the real driver. |
| P4 | the `db` gate still needs ErmineSales at xs (§5's nit); the new suite inherits that. |
