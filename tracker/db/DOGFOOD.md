# DOGFOOD: a real SQL Server behind the preview panel, step by step

DB programme stage 2e (tracker/DB-PLAN.md §4 S2 and S5). This walkthrough is written in the order you
experience it: the database, the profile, the first password prompt, a DB-backed report drawn in
the panel, a tier change, an edit, the Trace view, then the failure paths and the tear-down.
Checklist group F (`tracker/WP-7-MANUAL-CHECKLIST.md`) holds the same steps as F1-F12 for ticking
off. Record results in `tracker/PLAYTEST-RESULTS.md`, group F.

**NOTHING HERE HAS BEEN RUN IN A REAL VS CODE.** Each quoted text is read from the source at the
cited `file:line`, and `tracker/db/dogfood-citecheck.py` checks that every cited line still
contains its quote. Where a number was MEASURED (by the server roles' live suites, the loader, or
`scripts/db.sh` itself), the step says who measured it and when. Everything else is INFERRED from
the code and is marked that way.

| What you need before step 0 | Where |
|---|---|
| The extension **0.1.18** installed (`code --list-extensions --show-versions` printed `clarifi.ermine-lang@0.1.18` at 08:24 on 2026-09-25; a VS Code window opened earlier runs the older one until Reload Window) | the orchestrator repackages `editor/vscode/ermine-lang-0.1.17.vsix` after review. The version is in `tracker/db/MORNING-2026-09-25.md`'s ORCHESTRATOR FILLS block |
| A server compiled from THIS tree (`sbt core/compile core/copyResources`, which the orchestrator's gates run) | `tracker/PLAYTEST-SETUP.md` §2. A server from before stage 2 answers `ermine/preview/connect` with "method not found" (step 4's fallback) |
| The client bundle rebuilt after the Trace view landed (`cd client && npm run bundle`) | `client/dist/browser/ermine-host.js` was rebuilt at 00:07 on 2026-09-25 by the panel role. Rebuild it again if `client/src/` changed since |
| The rest of `tracker/PLAYTEST-SETUP.md` §1-§6 (the writers checkout for the pie chart, `.vscode/settings.json` for the workspace settings) | as for groups A-E |

---

## 0. Is the database up?

**Do:** in a terminal in the worktree:

```sh
scripts/db.sh status
```

**What OK looks like** (MEASURED 2026-09-25 00:0x, the whole output):

```
container ermine-mssql state=running health=healthy image=mcr.microsoft.com/mssql/server:2022-latest volume=present
databases present=ErmineHR,ErmineSales,ErmineScience missing=none
login ermine ok via 127.0.0.1:1433 suser=ermine tls=TRUE
memory sqlservr-rss=1172M cap=MSSQL_MEMORY_LIMIT_MB=2048 host-avail=6.6G
status OK
```

The last line is `(( rc == 0 )) && echo "status OK" || echo "status DEGRADED"` (`scripts/db.sh:222`). The
login line comes from `echo "login $LOGIN ok via 127.0.0.1:1433 suser=$who tls=$enc"` (`scripts/db.sh:216`).
The exit status is 0.

**If not:** `status DEGRADED` or exit 1 with `state=exited` or no container: run `scripts/db.sh up`.
It is idempotent and takes 4-5 s on a restart, 7-8 s on a create (MEASURED by infra,
`tracker/db/CONTAINER.md`). Nothing starts on its own after a reboot (the restart policy is `no`).
Exit 3 with `login sa FAILED` means `~/.config/ermine/db.env` does not match the volume
(CONTAINER.md, known gap 1). Other exit codes are listed in `scripts/db.sh --help`.

## 1. Which tier is loaded, and how to change it

**Do:**

```sh
scripts/db.sh verify sales
```

**Expect:** one line per table, one per view, then fk, smoke and a verdict line. The verdict line is
`` verify ${c.domain} mssql tier=${stamp.tier} seed=${stamp.seed ?? "-"} loaded= `` (`data/src/load/mssql.ts:150`), i.e.
`verify sales mssql tier=s seed=42 loaded=2026-09-25T06:03:45.026Z OK` right now. The stamp was read
with `scripts/db.sh sql` at 00:1x: `{"domain":"sales","tier":"s","seed":42,...,"loadedAt":"2026-09-25T06:03:45.026Z"}`.

**Tier s is the walkthrough's tier.** It has 1,676 rows in all, 1,000 order lines, and **388 rows in
the `sales` view** across 8 regions. To change it:

```sh
scripts/db.sh load sales --tier xs|s|m|l      # seed 42 by default
```

MEASURED by the loader role (`tracker/db/LOADER.md` §2, seed 42, one run each):

| Tier | Order lines | `sales` view rows | Load | With verify |
|---|---|---|---|---|
| xs | 8 | 8 | 0.65 s | 1.15 s |
| s | 1,000 | 388 | 0.66 s | 1.23 s |
| m | 100,000 | 7,701 (INFERRED from the trace A/B: 7,716 rows read by DbFetchTopN = 7,701 + 12 targets + 3 pie rows) | 1.91 s | 3.03 s |
| l | 2,000,000 | not measured | 25.7 s | 27.5 s |

Add the generator's time when `data/out/sales/<tier>/` is missing: 0.04 s at s, 0.79 s at m, 11.8 s at l.
All four exist right now. The load line is
`` load ${c.domain} mssql tier=${p.manifest.tier} seed= `` (`data/src/load/mssql.ts:95`).

**Careful:** the PR-tier `db` gate needs ErmineSales at **xs** (`tracker/db/SERVER.md` §5). Whoever
runs it loads xs first and reloads s afterwards. Loading a tier while a gate runs changes what the
gate sees.

## 2. The profile, in USER settings

**Do:** **Preferences: Open User Settings (JSON)** and add these two keys. They go in your USER
settings, **not** in `.vscode/settings.json`:

```jsonc
"ermine.preview.profiles": [
  { "id": "sales-mssql", "dialect": "mssql",
    "url": "jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true",
    "user": "ermine" }
],
"ermine.preview.profile": "sales-mssql"
```

There is no password field. A profile with a `password` key is refused, and so is a URL that carries
`password=`, `user=` and so on (`editor/vscode/README.md`, "Database profiles"). Keep
`ermine.trace.server` at `off` or `messages`.

**If you put them in workspace settings by mistake:** they are ignored. The channel says
`const SCOPE_NOTICE = "profiles set in workspace settings are ignored (user settings only)";`
(`editor/vscode/src/preview-core.js:6808`) once, prefixed `settings: `, and the second status bar item reads
`text: "$(database) workspace profiles ignored"` (`editor/vscode/src/preview-core.js:7272`).
Both settings are declared `"scope": "application"` in `editor/vscode/package.json`.

## 3. Open the worktree, and the output channel

**Do:**

```sh
code /home/dmitry/research/ermine/ermine-scala-wt-widget-preview
```

Open it as ONE folder (`tracker/PLAYTEST-SETUP.md` §5). Then run **Ermine: Show Language Server
Output**: the channel is named **Ermine**. Every `db:` and `preview:` line below appears there,
the server's own log lines too. For this walkthrough set `"ermine.preview.target": "both"` in
`.vscode/settings.json`, so each render fills the panel AND the JSON tab (step 5 uses both). Set it
back to `panel` at the end.

**If not:** no Ermine channel means the extension did not activate: open any `.e` file (checklist A1).

## 4. The first activation: one password prompt

**Do:** nothing. When the language client is running, the extension connects the active profile.
**Expect**, in order:

1. The second status bar item shows `text: "$(key) " + id + ": password?"` (`editor/vscode/src/preview-core.js:7264`),
   i.e. **`sales-mssql: password?`** with a key icon, and the channel logs
   `line: "db: asking for the password of " + labelText(label) + " (" + cause + ")",` (`editor/vscode/src/preview-core.js:7133`):
   **`db: asking for the password of sales-mssql (mssql) @ 127.0.0.1 (running)`**. The label is
   `return label.id + " (" + label.dialect + ")" + (label.host ? " @ " + label.host : "");` (`editor/vscode/src/preview-core.js:7033`).
2. A password box titled `title: "Ermine: database password",` (`editor/vscode/src/preview-core.js:6899`)
   with the prompt `prompt: "Password for " + who + " (profile " + (profile ? profile.id : "?") +` (`editor/vscode/src/preview-core.js:6900`)
   `"). It is held in this window's memory only, until the window closes or you disconnect.",` (`editor/vscode/src/preview-core.js:6901`):
   **`Password for ermine @ 127.0.0.1 (profile sales-mssql). It is held in this window's memory only, until the window closes or you disconnect.`**
   It stays open if you click elsewhere (`ignoreFocusOut`).
3. Type `ERMINE_DB_PASSWORD` from `~/.config/ermine/db.env` (read it with an editor. Do not paste it
   into any file or terminal command) and press Enter. The item turns to
   `text: "$(sync~spin) " + id + ": connecting"` (`editor/vscode/src/preview-core.js:7267`) and the channel logs
   `line: "db: connecting " + labelText(s.label) + " (password entered)",` (`editor/vscode/src/preview-core.js:7146`).
4. The server logs `log("preview: connected " + p.id + " (" + p.dialect + ") @ " + host + " / " + db + " in " + ms +` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2127`),
   which shows as `preview: connected sales-mssql (mssql) @ <host> / ErmineSales in 13 ms, seq 1`. The
   host is written `<host>` because the server scrubs the profile's host and user from its log. 13 ms
   was MEASURED by `TestPreviewDbLive` in a warm JVM (SERVER.md §6.3). A cold JVM is not measured (P1).
5. The extension logs `line: "db: connected " + labelText(label) + (database ? " / " + database : "") +` (`editor/vscode/src/preview-core.js:7162`):
   **`db: connected sales-mssql (mssql) @ 127.0.0.1 / ErmineSales`**. The status bar item reads
   `return { hidden: false, text: "$(database) " + labelText(s.label), severity: "none",` (`editor/vscode/src/preview-core.js:7260`):
   **`sales-mssql (mssql) @ 127.0.0.1`** with a database icon. Hover over it:
   `tooltip: "connected: " + labelText(s.label) + (s.database ? "\ndatabase: " + s.database : "") +` (`editor/vscode/src/preview-core.js:7261`),
   so `connected: sales-mssql (mssql) @ 127.0.0.1`, `database: ErmineSales`, `server: 16.00.4295`
   (the version string was MEASURED in the connect answer, SERVER.md §6.3).

**If not:**
- no prompt and the item reads `sales-mssql: trace is verbose`: `ermine.trace.server` is `verbose`, and
  the channel says so with `line: "db: NOT connecting " + labelText(label) + ": ermine.trace.server is \"verbose\" and would log the " +` (`editor/vscode/src/preview-core.js:7108`).
  Set it to `off`.
- you pressed Escape: `line: "db: no password given for " + labelText(s.label) + "; not connected",` (`editor/vscode/src/preview-core.js:7141`).
  Nothing asks again on its own. Run **Ermine: Connect Database** or click the status bar item.
- `sales-mssql: profile` with the message *this language server has no ermine/preview/connect (it is
  older than the extension)*: the server was not rebuilt from this tree (see "What you need").
- `sales-mssql: unreachable`: the container is down. Go back to step 0.
- no database item at all: the profile is not in user settings, or `ermine.preview.profile` is empty.
  Look for `settings:` lines in the channel.

## 5. Preview Report on the DB-backed twin: `DbFetchTopN`

**Why this report.** `core/src/test/resources/doc/DbFetchTopN.e` is `FetchTopN.e` line for line, except
that it imports `DbFetchData`, whose `sales` and `targets` are `table` statements, not `VALUES`
literals. So its rows come from the connected database (`tracker/db/REPORTS.md` §1). At tier xs its
document equals the in-memory original's, apart from row order (MEASURED, `TestDbReports` and
`TestPreviewDbLive`). It is a `Fetch` report with two scans in one `do` block: an aggregate
`groupBy {region} (sumBy amount) sales` read largest first, and `targets`.

**Do:** **Ermine: Preview Report...** → type `DbFetchTopN` → `core/src/test/resources/doc/DbFetchTopN.e` →
`report` (`report : Query -> Fetch Node`, where `Query` is `{ keep : Int }`).

**Expect:**
1. The first pick writes `.ermine/preview/DbFetchTopN/report.params.json` and opens it (as B1 does for
   `Sales`). The skeleton's `keep` is 0: the skeleton's number starts at `let value = 0;` (`editor/vscode/src/preview-core.js:3272`)
   (INFERRED: the schema is not captured).
2. The channel logs the usual `preview: render DbFetchTopN.report (generation 1; the report was picked; ...)`
   (checklist A4). The first render after a connect rebuilds the preview session, because the scanner
   is part of the session. MEASURED: 2.2 s in `TestPreviewDbLive` (SERVER.md §6.3), about 1.6-1.7 s of
   `boot` in the trace (OBSERVABILITY.md §9). Later renders took 22 ms in that test.
3. The panel draws two widgets. (a) A pie **`Sales by region`**, from the `pieChart (PieChartProps "Sales by region" "Sales" "region" "amount"` line
   (`core/src/test/resources/doc/DbFetchTopN.e:58`), drawn by the legacy writers. With `keep` 0 it has
   ONE slice, `Other`, the whole of tier s: **1,051,094.22**. (b) An error box, and that is expected:
   `, rawWidget "metTargets" met ])))` (`core/src/test/resources/doc/DbFetchTopN.e:63`) has no renderer,
   so the box says `` title.textContent = `widget "${widget}" could not be rendered`; `` (`client/src/dispatcher.ts:88`)
   with the reason `` : fail(`no renderer is registered under that name`); `` (`client/src/dispatcher.ts:253`).
   Its value (1 at tier s) is in the JSON tab.
4. **Set `keep` to 2** in the params file and save. You get ONE re-render (checklist B8). The pie has
   three slices. At tier **s** (read with `scripts/db.sh sql` at 00:1x on 2026-09-25):
   **china 225,449.88, us-south 172,784.89, Other 652,859.45**, and `metTargets` 1 (germany: 148,127.96
   against a target of 144,500). The trace example in OBSERVABILITY.md §4 carries the same three
   amounts in its SQL literal: `(225449.87999999998, 'china'), (172784.89, 'us-south'), (652859.45, 'Other')`.
   Summing Doubles gives the `...87999999998`, and the JSON tab may print it that way.
5. **The JSON tab** (target `both`: `return Object.freeze({ tab: t === "json" || t === "both", panel: t === "panel" || t === "both" });`,
   `editor/vscode/src/preview-core.js:6178`) has the same document. The pie's rows are inline under
   `$.children[0].props.pieRows`, and `metTargets` is under `$.children[1]`.

**Tier xs versus tier s (the S2 done-when).** At tier **xs** the same `{"keep": 2}` gives **north 4,350.75,
east 4,175.50, Other 4,155.75** (south 2,605.75 + west 1,550.00), and `metTargets` **2**, exactly as the
in-memory `core/src/test/resources/doc/FetchTopN.e` gives it. MEASURED on SQL Server and on the
SQLite twin by `TestDbReports` (REPORTS.md §5) and by `TestPreviewDbLive` (SERVER.md §6.3). Step 6 shows
how to see it in the panel.

**If not:**
- a 503 `not connected (...)` banner: step 4 did not finish. See step 9 for the banner's wording.
- a 500 naming `sales` (on SQL Server, "Invalid object name"): ErmineSales has no tables. Run `scripts/db.sh load sales --tier s`.
- the pie is an error box that says `env.htmlwriter ...`: the writers are missing (checklist E14).
- no database item in the status bar, and a 500 from SQLite about a missing table `sales`:
  nothing is connected, so the render used the in-memory SQLite, which has no `sales` table. The exact
  text of that 500 is not captured.

**Optional, a second report with no error box:** **Ermine: Preview Report...** →
`core/src/test/resources/modules/Doc/DbSalesReport.e` → `report` (`report : Node`, no parameters, so
no params file). It is `SalesReport.e`'s twin over `table sales_report`: a scorecard, a table, a bar
chart and a pie (checklist E2's `SalesReport` sub-step and E10). At tier s the three rows are
AMER 59.12 / -0.481, APAC 101.55 / 0.772, EMEA 86.9 / -0.185 (read with `scripts/db.sh sql`).

## 6. Change the tier under the panel

**Do:** in a terminal, `scripts/db.sh load sales --tier m`. Then re-render: save the params file, or
run **Ermine: Render Report to JSON**, which re-renders the current pick.

**Expect:**
- The load prints `load sales mssql tier=m seed=42 rows=106106 ... verify=OK` after about 3 s
  (MEASURED 3.03 s with verify, LOADER.md §2). **Nothing re-renders by itself**: the extension cannot
  know that the data changed.
- After the re-render the pie shows tier m's top two regions and `Other`. At m, 12 regions and 7,701
  `sales` rows. The Trace view (step 8) shows `$.fetch[1]` reading about 7,701 rows and handing the
  report 12. **Tier m's amounts were not read by anyone**, so check them against
  `scripts/db.sh sql ErmineSales "SELECT region, SUM(amount) FROM sales GROUP BY region ORDER BY 2 DESC"`.
- Render time: MEASURED median 103.8 ms for a warm `DbFetchTopN` at m with no trace, and 105.3 ms with
  the trace (OBSERVABILITY.md §7, 5 rounds).

**To see the S2 done-when:** `scripts/db.sh load sales --tier xs` (1.15 s), re-render, and compare with
§5's xs numbers. Then `scripts/db.sh load sales --tier s` (1.23 s) to go back.

**If not:**
- `db.sh load` seems to hang at the DDL step. That would mean the held connection is inside a
  transaction that holds a lock on `sales` (INFERRED possible, not observed: renders commit when they
  finish). Run **Ermine: Disconnect Database**, and the load continues.
- the numbers did not change: you did not re-render. Nothing tells the preview that the data moved.

## 7. Edit the report's parameters: `keep` 2 → 3

**Do:** in `.ermine/preview/DbFetchTopN/report.params.json` change `"keep": 2` to `"keep": 3` and
save. (Or edit `DbFetchTopN.e` itself, e.g. the pie's title, and save: the module is invalidated and
re-rendered, as in checklist A5. Put it back with `git checkout -- core/src/test/resources/doc/DbFetchTopN.e`.)

**Expect:** ONE re-render in place. The panel is not brought to the front (checklist B8). At tier s:
**china 225,449.88, us-south 172,784.89, france 154,111.45, Other 498,748.00**, and `metTargets`
still 1. The channel gets one `preview: render ...` line and one trace line (step 8). No SQL changes
between keep 2 and keep 3: `keep` is applied in Ermine, after the scan (`take (keep q) ranked`).

**If not:** two renders for one save, or none: checklist B3/B8's failure lines apply.

## 8. The Trace view: what the database did for this render

**Do:** in the panel's toolbar click **Trace**. The button is `showTrace = control("Trace", "trace");` (`client/src/host/page.ts:668`),
beside Document and JSON.

**Expect** (the numbers are from server-trace's MEASURED `DbFetchTopN {"keep":2}` at tier s,
OBSERVABILITY.md §4, n=1. Yours will differ):
1. **The headline**, built from `` `render ${formatMs(wall)}` `` (`client/src/host/page.ts:330`):
   `render 51 ms: db 11 ms (22%), 3 queries, 19 rows (399 read) · generation <G>` (panel role, board 00:08).
2. **The connection line**: `c.profile ?? "profile"` (`client/src/host/page.ts:344`) and the rest of that
   line: **`sales-mssql (mssql) @ 127.0.0.1 / ErmineSales`**. The host comes from the extension's held
   connection (extension role, board 00:10), and the database from the server's trace.
3. **The phase bar**: the blue `db` segment first, then the other phases (`session`, `eval`, `scan`,
   ...). A segment gets a text label only when it is at least 12% wide: `sg.pct >= 12 ?` (`client/src/host/page.ts:814`).
   The legend below it lists every segment. At tier s most of the 40 ms outside the database is `scan`
   (30.7 ms): Ermine grouping 388 rows into 8 regions, because `groupBy ... (sumBy ...)` is a `Mem`
   and is not pushed into the SQL (OBSERVABILITY.md §9, finding 1).
4. **The table.** Its headers come from `for (const [h, cls] of [["#", "num"], ["relation", ""], ["delivery", "opt"], ["rows", "num"], ["scanned", "num"],` (`client/src/host/page.ts:833`),
   so: `#, relation, delivery, rows, scanned, db, total, dialect, share`. The rows are `$.fetch[1]`
   (fetched, rows 8, scanned **388**), `$.fetch[2]` (fetched, 8 and 8) and `$.children[0].props.pieRows`
   (inline, 3 and 3). Under `$.fetch[1]` a note says `rows; Ermine reduced them to ${formatCount(q.rows)}` (`client/src/host/page.ts:871`),
   i.e. `the database returned 388 rows; Ermine reduced them to 8`.
5. **The SQL.** Click `SQL · ${formatCount(bytes)} bytes` (`client/src/host/page.ts:881`) under `$.fetch[1]`
   (`SQL · 182 bytes` in the example). The SQL appears in a grey box with a
   `const copy = el("button", "ermine-trace-copy", "Copy");` (`client/src/host/page.ts:769`) button. Click
   **Copy**. The button reads `clip.writeText(text).then(() => { button.textContent = "Copied"; },` (`client/src/host/page.ts:750`),
   or, when the webview has no clipboard, `button.textContent = "Selected: press Ctrl+C";` (`client/src/host/page.ts:744`).
   Paste it into `scripts/db.sh sql ErmineSales "<paste>"`: it prints `(388 rows affected)` at tier s,
   the `scanned` cell. The example's SQL is
   `select ([t1030144].[amount]) [amount], ... from [sales] [t1030144] order by [t1030144].[region] asc`.
   The alias numbers change on each render.
6. **The status bar's preview item** reads `return { hidden: false, text: "$(json) Ermine: " + label + suffix, tooltip: tooltip + traceLine, severity: "none" };`
   (`editor/vscode/src/preview-core.js:2163`) with the suffix `return wall === null ? "" : " · " + traceMs(wall);` (`editor/vscode/src/preview-core.js:5644`):
   **`Ermine: DbFetchTopN.report · 51 ms`**. Its tooltip ends with
   `return "render " + traceMs(tt.wallMs || 0) + ": db " + traceMs(tt.dbMs || 0) + ", " +` (`editor/vscode/src/preview-core.js:5652`):
   `render 51 ms: db 11 ms, 3 queries, 19 rows (sales-mssql / ErmineSales)`.
7. **The channel** gets ONE line per render:
   `return head + "ok " + traceMs(rt === null ? wall : rt) + " (" + (rt === null ? "" : "server " + traceMs(wall) + ": ") +` (`editor/vscode/src/preview-core.js:5700`),
   e.g. `preview: render <G> ok <RT> ms (server 51 ms: db 11 ms, 3 queries, 19 rows; scan 31 ms, session 4.5 ms, other 4.8 ms) sales-mssql / ErmineSales`
   (panel role, board 00:08). The connection part is
   `return (c.profile || "profile") + (c.host ? " @ " + c.host : "") + (c.database ? " / " + c.database : "");` (`editor/vscode/src/preview-core.js:5637`).
   **The channel never contains SQL.**

**If not:** `no trace: this answer carried none (a server from before DB stage 2 sends none)`: the
server was not rebuilt. The Trace button missing: the client bundle is older than the Trace view,
so run `npm run bundle` in `client/`.

## 9. Disconnect: the 503 banner, and reconnecting

**Do:** **Ermine: Disconnect Database**. Then save the params file (a re-render).

**Expect:**
- The channel: `line: "db: disconnected " + labelText(s.label) + " by the user; the password is forgotten",` (`editor/vscode/src/preview-core.js:7223`),
  then `() => log("db: the server let the connection go"),` (`editor/vscode/src/extension.js:3603`).
  The status bar item reads `text: "$(database) " + id + ": not connected"` (`editor/vscode/src/preview-core.js:7286`).
  The panel keeps its last document until something re-renders.
- The re-render is answered with the server's 503 (`private[lsp] val NotConnectedMessage = "not connected"`,
  `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2752`, reason
  `val NotConnected       = "not-connected"`, `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:3060`).
  The extension rewords it:
  `: s.label ? labelText(s.label) + " is " + (s.phase === "connecting" || s.phase === "prompting" ? "still connecting" : "not connected")` (`editor/vscode/src/preview-core.js:7349`)
  and `" (" + why + ') -- run "' + CONNECT_COMMAND_TITLE + '", or click the database item in the status bar',` (`editor/vscode/src/preview-core.js:7354`).
  The banner is `e.status === 0 ? e.message :` (`client/src/host/index.ts:335`) plus the status, i.e.
  **`503: not connected (sales-mssql (mssql) @ 127.0.0.1 is not connected) -- run "Ermine: Connect Database", or click the database item in the status bar`**.
  The document below is dimmed (checklist E4). MEASURED on the wire by `TestPreviewDbLive`:
  `{"ok":false,"status":503,"message":"not connected","reason":"not-connected",...}`.
- **Reconnect:** click the status bar item (or run **Ermine: Connect Database**). The password is
  forgotten, so the box asks again (step 4). After `db: connected ...` the last render is re-sent
  once, and the line ends `(trigger ? "; re-sending the last render (" + trigger + ")" : ""),` (`editor/vscode/src/preview-core.js:7163`),
  i.e. `; re-sending the last render (reconnected)`. The banner goes.

**If not:** the render after Disconnect draws a document instead of a 503: the disconnect did not
reach the server. Look for `db: the disconnect request failed (...)` in the channel.

## 10. A wrong password, on purpose

**Do:** **Ermine: Disconnect Database** (so no password is held), then **Ermine: Connect Database**
and type something wrong.

**Expect:**
- The channel: `line: "db: connect " + labelText(s.label) + " FAILED " + cls + " (" + reason + (forget ? ", password forgotten" : ", password kept") +` (`editor/vscode/src/preview-core.js:7201`),
  i.e. `db: connect sales-mssql (mssql) @ 127.0.0.1 FAILED auth (connect-auth, password forgotten; attempt 1/3): login failed for <user> @ <host>: SQLServerException: Login failed for user '<user>'. ClientConnectionId:...`.
  The server builds the message from `"login failed for " + p.user.getOrElse("(no user)") + " @ " + hostAndDatabase(p.dialect, p.url)._1 +` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2111`)
  and then scrubs the user and host out of it. That is why you read `<user> @ <host>`, while the prompt
  said `ermine @ 127.0.0.1` (MEASURED by `TestPreviewDbLive`: answered in 36 ms, class `auth`, `kept:false`).
- An error notification, `return "Ermine: " + labelText(s.label) + ": " + (s.cls || "connect") + ": " + (s.message || "the connect failed");` (`editor/vscode/src/preview-core.js:7294`),
  with two buttons, `const CONNECT_RETRY = "Retry";` (`editor/vscode/src/preview-core.js:6659`) and
  `const CONNECT_DISCONNECT = "Disconnect";` (`editor/vscode/src/preview-core.js:6660`), shown by
  `vscode.window.showErrorMessage(text, core.CONNECT_RETRY, core.CONNECT_DISCONNECT).then((choice) => {` (`editor/vscode/src/extension.js:3629`).
- The status bar item: `return { hidden: false, text: "$(database) " + id + ": " + (s.cls === "trace" ? "trace is verbose" : s.cls),` (`editor/vscode/src/preview-core.js:7275`),
  i.e. **`sales-mssql: auth`**, with a warning colour.
- With a report picked, the panel gets a banner:
  `message: connectFailureText(s).replace(/^Ermine: /, "") + ' -- run "' + CONNECT_COMMAND_TITLE + '" to try again',` (`editor/vscode/src/preview-core.js:7308`),
  i.e. `503: sales-mssql (mssql) @ 127.0.0.1: auth: login failed for <user> @ <host>: ... -- run "Ermine: Connect Database" to try again`.
- **Retry** opens the password box again. Type the right one: step 4's `db: connected ...`, and the
  last render is re-sent. An `auth` failure is never retried automatically, since the password was forgotten (NEW-2 retries only
  `unreachable`/`driver` with a held password).

**If not:** a Retry that connects without asking would mean a rejected password was kept. That is a
FAIL (A8).

## 11. Stop the database while connected

**Do:** with step 10's connection up, run `scripts/db.sh down` in a terminal (about 1 s: `SHUTDOWN` as
sa, then `podman wait`, CONTAINER.md). Then save the params file.

**Expect** (INFERRED order: the server's notice and the render's answer race):
- The server finds the held connection dead before the render (`isValid(2)`, SERVER.md §6.2) and logs
  `log("preview: the held connection " + (if (a != null) a.profile.id else "") + " is gone (" + reason + ")")` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2170`),
  i.e. `preview: the held connection sales-mssql is gone (connection-lost)`, and answers the render with
  step 9's 503.
- The extension gets `ermine/preview/disconnected` and logs
  `line: "db: the server closed the connection of " + labelText(s.label) + " (" + (event.reason || "no reason") + "); reconnecting",` (`editor/vscode/src/preview-core.js:7213`).
  It tries ONE reconnect with the held password (no prompt):
  `line: "db: connecting " + labelText(label) + " (" + cause + (needsPassword ? ", password held" : ", no user") + ")",` (`editor/vscode/src/preview-core.js:7116`),
  i.e. `db: connecting sales-mssql (mssql) @ 127.0.0.1 (disconnected, password held)`.
- With the server down, that connect fails with class `unreachable`, and the password is KEPT. **Since
  NEW-2 (extension, 2026-09-25 00:22) the extension then retries by itself, never prompting**: after
  `const RECONNECT_DELAYS_MS = Object.freeze([5000, 15000]);` (`editor/vscode/src/preview-core.js:6955`),
  that is 5 s and then 15 s later, three attempts in all. Each failure logs the step 10 line, which now ends
  `"; attempt " + attempt + "/" + RECONNECT_ATTEMPTS +` (`editor/vscode/src/preview-core.js:7202`), e.g.
  `db: connect sales-mssql (mssql) @ 127.0.0.1 FAILED unreachable (connect-unreachable, password kept; attempt 1/3, retrying in 5 s): ...`.
  While a retry is armed, the status bar item reads
  `return { hidden: false, text: "$(sync) " + id + ": reconnecting (" + s.retry.attempt + "/" + RECONNECT_ATTEMPTS + ")",` (`editor/vscode/src/preview-core.js:7278`),
  i.e. **`sales-mssql: reconnecting (2/3)`** and then `(3/3)`. Its tooltip says `retrying automatically, 3 attempts in all`.
  An error notification (with NO Retry button) appears for the first failure and again for the last one,
  not for the one in the middle. A 503 banner shown while a retry is armed says
  `: s.label && s.phase === "retrying" ? labelText(s.label) + " is reconnecting (attempt " + s.retry.attempt + "/" + RECONNECT_ATTEMPTS + " is armed)"` (`editor/vscode/src/preview-core.js:7348`).
  If all three attempts fail, the item settles on **`sales-mssql: unreachable`** and the panel banner is
  `503: sales-mssql (mssql) @ 127.0.0.1: unreachable: ... -- run "Ermine: Connect Database" to try again`.
  The driver's own message text is not captured.
- **Bring it back:** `scripts/db.sh up` (4-5 s on a restart). **If you run it within about 20 s of the
  failure**, the retry chain picks it up: `db: connected ...`, and the last render is re-sent, with no
  click and no prompt. **If the chain is already over**, save the params file. That render gets the 503,
  and because a password is held the extension first connects ONCE, logging
  `` `preview: render ${mine} answered 503 not connected; connecting once before showing it` `` (`editor/vscode/src/extension.js:2407`).
  It shows the banner only if that connect fails. When it succeeds, the render is re-sent and draws.
  Clicking the status bar item works too (`(command, password held)`, no prompt). **Nothing here ever
  prompts.** Disconnect, a server stop, a profile change or closing the window cancels a pending retry.

**If not:** the render hangs for up to `ermine.preview.timeoutSeconds` instead of answering 503: then
`isValid` did not return quickly on a dead socket. Record how long it took. The login timeout is
clamped to 1-15 s (SERVER.md §6.2).

## 12. Tear-down

| Command | What it removes | What it keeps |
|---|---|---|
| **Ermine: Disconnect Database** (do this first) | the held connection and the password | the profile in settings |
| `ermine.preview.profile` set to `""` in user settings | the active profile: renders use the in-memory SQLite again, and the database item disappears | the profiles list |
| `scripts/db.sh unload sales` | the Sales tables, views and load stamp, and `/load/sales/`. It prints `` other-objects=${left[3]} stage-dir=removed `` (`data/src/load/mssql.ts:193`) | the database `ErmineSales`, the `ermine` user and its grants, the grown data files (LOADER.md §5) |
| `scripts/db.sh down` | nothing: it stops the server | everything, in the volume |
| `scripts/db.sh down --all` | the container and the volume `ermine-mssql-data`: every database | the image, `/load`, `~/.config/ermine/db.env`, `data/out/` |

To start again after `down --all`: `scripts/db.sh up` (7-8 s, which creates the three empty databases
and the login), then `scripts/db.sh load sales --tier s` (1.23 s). **Leave ErmineSales at tier s** (or
at xs, if the next thing to run is the `db` gate) and say which one on the board.

Put back what the walkthrough changed: `"ermine.preview.target"` back to `panel`,
`git checkout -- core/src/test/resources/doc/DbFetchTopN.e` if you edited it, and delete
`.ermine/preview/DbFetchTopN/` if you do not want the params file.

---

## 13. Preview the trace as an Ermine report

(DB programme S2f, extension 0.1.18. It needs no database: run it before §12's tear-down to see a
`DbFetchTopN` trace from the profile, or after it on the in-memory SQLite. `Layout.Trace` must be in
the server you run, so rebuild it first: `sbt core/compile core/copyResources`.)

**Do:** with `DbFetchTopN` → `report` rendered in the panel (step 5), run **Ermine: Preview Render Trace**
(`"ermine.previewRenderTrace"`, `editor/vscode/src/preview-core.js:5732`).

**Expect:**
1. **The save.** With no file yet there is no question. The channel says
   `"replaced " : "wrote "` (`editor/vscode/src/preview-core.js:5952`), i.e. `preview: wrote
   <workspace>/.ermine/preview/Doc.TraceReport/report.params.json with the trace of render <G>
   (Doc.TraceReport.report reads it as its parameters)`. The directory is the dotted module name, as
   for every params file. The file holds the trace's keys in the server's order and nothing else. It
   is written by `traceParamsText` from `traceParamsOf`, which copies only the keys `Layout.Trace`
   declares, so a url or a user can never get in.
2. **The pick.** The panel switches to `Doc.TraceReport.report` through the picker's own tail,
   `core.TRACE_REPORT_BINDING, listed.module` (`editor/vscode/src/extension.js:3937`). It renders
   like any report: the queue, the wedge guard and the params watcher all apply.
3. **The document** (headless, from the captured tier-s trace: `scratch-widget-preview/db/s2f/trace-report-dark.png`):
   a headline titled `"Render trace, generation "` (`core/src/test/resources/modules/Doc/TraceReport.e:70`) with
   `Rows 3, Total 51.0, Largest 36.7` under a scope that names them (`Rows = relations, Total = render
   wall ms, Largest = slowest relation ms`: the wall time includes work outside every relation, so it
   is more than the relations' 42.4 ms), the caption `db 11.0 ms of 51.0 ms, 3 queries.`, two scorecards
   `"Time (ms)"` (`core/src/test/resources/modules/Doc/TraceReport.e:76`) (1 wall 51.0, 2 db 11.0, 3 other 40.0,
   4 queue 0.0; the number keeps the order, since a relation has none) and Rows (1 rows read 399,
   2 rows used 19, 3 queries 3), a bar chart
   `"Time by phase (ms)"` (`core/src/test/resources/modules/Doc/TraceReport.e:79`) with the bars `01 session` ...
   `13 other`, the relations table sorted by Total ms (`$.fetch[1]` 388 read, 8 rows, 36.7 ms, 72%), a pie
   `"Time by relation"` (`core/src/test/resources/modules/Doc/TraceReport.e:96`) and the SQL table.
   Both charts are coloured and 320 px tall. (Finding S2f-1, FIXED 2026-09-25: the writers draw
   Highcharts in styled mode, and the panel now links `javafxwriter.css`, which holds those rules.
   Before that every chart was a black box: `scratch-widget-preview/db/s2f/old/`.) A black box now
   means an older extension or a writers folder without `javafxwriter.css`.
4. **The recursion.** Run **Ermine: Save Render Trace** now (the trace report is picked). Its params
   file exists, so a modal asks: `now in that file are REPLACED` (`editor/vscode/src/preview-core.js:5892`).
   **Replace** writes the trace of the trace report's OWN last render (three or more `inline` VALUES
   relations, no fetch) and the watcher re-renders it. **Cancel** leaves the file byte for byte. If a
   render answers while the modal is open, nothing is written and the warning starts
   `a newer render answered (generation ` (`editor/vscode/src/preview-core.js:5882`).
5. With the trace report not picked, **Save Render Trace** on its own shows the status bar message
   `" saved for "` (`editor/vscode/src/extension.js:3939`) for 5 s and picks nothing.

**If not:** `the trace report is not in this workspace` means the window has no
`core/src/test/resources/modules/Doc/TraceReport.e`; `this answer carries no trace` (`editor/vscode/src/preview-core.js:5803`)
means the answer came from a server from before DB stage 2 (or was built by the extension); a 404
naming `Layout.Trace` means the server was not rebuilt.

---

## What this walkthrough does not show

| | Why |
|---|---|
| A cold-JVM connect time | not measured (SERVER.md §6.4 P1) |
| The Trace view's stuck case (`stuck: partial trace, ...`) | needs a query that hangs. Only the in-memory test (t4) and a hand-made screenshot show it (OBSERVABILITY.md §5, `scratch-widget-preview/db/panel-trace/panel-trace-stuck-*.png`) |
| `##` temp tables building up on a long-held connection | WP-14's one-hour count, not run (P2) |
| The SQLite twin as a second profile | optional: `cd data && npm run load:sqlite -- --domain sales --tier s` writes `data/out/sales/s/sales.sqlite` (0.19 s). Add `{ "id": "sales-sqlite", "dialect": "sqlite", "url": "jdbc:sqlite:/home/dmitry/research/ermine/ermine-scala-wt-widget-preview/data/out/sales/s/sales.sqlite" }` and switch `ermine.preview.profile` to it. There is no password, and the last render is re-sent. Right now only `data/out/sales/l/sales.sqlite` exists |
