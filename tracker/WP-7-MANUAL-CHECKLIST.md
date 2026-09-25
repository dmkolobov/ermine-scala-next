# Playtest guide: the Ermine preview in VS Code (extension 0.1.14)

**NOTHING IN THIS FILE HAS EVER BEEN RUN BY ANYONE.** Not one step. Nothing in
this repository runs VS Code; every expectation below is READ from
`editor/vscode/src/extension.js` and `editor/vscode/src/preview-core.js` (and,
for Group E, from `client/src/`), from the server's own source, or MEASURED over the wire against a real
`bin/ermine-lsp` with no editor in the loop. Where a line was measured it says
so; where it was only read, that is what "NEVER RUN" on the step means. **Every
step is marked NEVER RUN, and none of the marks is a formality.**

**AMENDED 2026-09-23 BY WP-10 STAGE 5: Group E (the webview panel, E1–E14) is new, and
Groups A–D are now run with `ermine.preview.target` set to `json`** (the panel is the
default since 0.1.12; the setup's settings file sets `json` for A–D and Group E sets it
back). **THIS FILE WAS REWRITTEN IN PLACE, 2026-09-23, as a runnable guide.** The old
checklist's step numbers are kept as aliases in square brackets after each new
id — `B12 [2.38]` — so every reference elsewhere in the tracker (`§2.35`,
`§2.41b`, `§2.45`, `§2.52b`, …) still resolves by searching this file. The old
"deviations" section survives as Appendix 1 and the old "what these steps
cannot tell you" paragraphs as Group D. Nothing was dropped.

**AMENDED 2026-09-23 BY THE FIRST PLAYTEST (findings F1, F2 in
`tracker/PLAYTEST-RESULTS.md`).** F1: under 0.1.14 the panel could not build its
page at all in a real VS Code (the CSP guard refused `'self'
https://*.vscode-cdn.net`); fixed in 0.1.15, so Group E needs 0.1.15. F2:
`Doc/SalesReport.e`'s `report : Node` is REFUSED at render (400, *"a report must
be a function Params -> Node, not Node"*), so E1, E2 and E9 and the 30-minute
path now use the typed `core/src/test/resources/doc/Sales.e`, and **E10 has NO
FIXTURE** until the runner accepts a zero-parameter report or `SalesReport`
gains a parameter (the user's call, Q27).

**AMENDED 2026-09-24 BY WP-34 (Q27 DECIDED, option (i)): the runner accepts a
zero-parameter report, so `Doc/SalesReport.e` renders again and E10 has its
fixture back.** Needs extension **0.1.16** and a server rebuilt from the WP-34
tree (`sbt core/compile core/copyResources`, then restart the language server).
E2 gains a `SalesReport` sub-step; E1, E2's main step and E9 stay on `Sales`.

**AMENDED 2026-09-25 BY DB STAGE 2e: Group F (the database, F1–F12) is new; S2f added F13.** It runs the preview
against the local SQL Server (`ermine-mssql`, `ErmineSales`) through a profile in USER settings and a
prompted password, and reads the panel's new **Trace** view. It needs extension **0.1.17**, a server
compiled from the stage-2 tree and a rebuilt client bundle. Its narrative twin, with timings and
fallbacks, is `tracker/db/DOGFOOD.md`. Its quotes are checked against their lines by
`tracker/db/dogfood-citecheck.py`.

## Before you start

| | |
|---|---|
| Setup | **`tracker/PLAYTEST-SETUP.md` is the prerequisite and is written separately. Do all of it before step A1.** It produced: the packaged extension **`editor/vscode/ermine-lang-0.1.14.vsix`** (gitignored; the old `ermine-lang-0.1.9.vsix` is still beside it — do NOT install that one: it has no params command, no panel and no writers); the client bundle in `client/dist/browser/` (the panel loads it from the checkout, it is not in the `.vsix`); the writers checkout beside this worktree (the panel's legacy widgets); eight fixtures, `tracker/playtest/fixtures/WpSpin.e`, `WpChain.e`, `WpBlow.e`, `WpInt.e`, and S4's `WpEnum.e`, `WpMaybe.e`, `WpJson.e`, `WpUnit.e`; two ready-made params files, `tracker/playtest/params/Sales.report.params.json` and `WpSpin.report.params.json`, with `tracker/playtest/params/README.md` saying where to copy each; `tracker/playtest/settings.example.json`; and a server verifier, `tracker/playtest/check-server.py` |
| THE PANEL IS THE DEFAULT, BUT NOT FOR A–D | since 0.1.12 `ermine.preview.target` defaults to `panel`, and **Groups A, B and C are written against the JSON tab**. `tracker/playtest/settings.example.json` therefore sets `"ermine.preview.target": "json"` (the tab path is byte-for-byte 0.1.11's). **Group E is the panel, and its first line of setup sets `panel` back.** If you skip straight to Group E, set `panel` first |
| `Sales` is NOT a fixture | **`Sales.report` is the repository's own `core/src/test/resources/doc/Sales.e`** and stays there — other suites read it. Any step that edits it says how to undo it (`git checkout -- core/src/test/resources/doc/Sales.e`) |
| ONE workspace folder, and keep it that way | **No step needs a second folder.** All four fixtures live inside this worktree. **Do NOT use File > Add Folder to Workspace:** a second folder makes the window MULTI-ROOT, and VS Code then stops reading the three WINDOW-scoped settings — `ermine.preview.timeoutSeconds`, `ermine.preview.restartAfterStuckSeconds` and `ermine.maxHeap` — from `.vscode/settings.json` (documented; unobserved here). Every "add `/tmp/wp7` to the workspace" instruction in the old checklist is obsolete and has been removed. The one step that still wants a report outside every folder (**B18**) copies a fixture to `/tmp/wp7` and deliberately does NOT add it |
| Where you record | **`tracker/PLAYTEST-RESULTS.md`**, in this directory. One row per step id, pre-filled in the order below. Fill in PASS / FAIL / SKIP, one line of what you saw, and anything else in the notes column. **For any FAIL, paste the Ermine output channel's text into a fenced block under the table.** The orchestrator reads that file and acts on it |
| The channel | **Ermine: Show Language Server Output** opens the output channel named **Ermine**. Both the extension's own lines (`preview: …`, `restart: …`, `settings: …`, `client N: …`) and the server's log go to that one channel. Every quoted line below appears there |
| The render tab is UNTITLED and DIRTY | every update is a `WorkspaceEdit`, so the tab always has unsaved changes and closing it offers to save a throwaway render: **Don't Save**. There is no way round it for an untitled document, and it is one of the motivations for WP-10's panel, which Group E exercises (under `target: json`, the setting Groups A–C run with, the tab is what you get) |
| 0.1.9 WRITES TO YOUR DISK | it is the first version that does. On the first pick of a report with no params file it creates three files under `.ermine/preview/`. Group B is where you look at them |
| 0.1.10 CAN REPLACE ONE | and **only** through the command **Ermine: Write Params Skeleton**, and **only** after a modal you answer. Nothing automatic overwrites a params file, and nothing in the extension ever deletes one. B22-B26 are those steps |
| Undo | any step that edits a checked-in file says so and says how to undo it. **At the end (A14) `git status --short` should show `.ermine/` and `.vscode/` and nothing else** — `.vscode/` is not gitignored here; the setup's own files (`tracker/PLAYTEST-SETUP.md`, `tracker/playtest/`) have been committed since (`edb0b74c`). `core/src/test/resources/doc/Sales.e` must be clean, and so must every file Group E edits (`tracker/playtest/fixtures/WpInt.e`, `client/src/widgets/scorecard.ts`) |

**The fixtures, one line each.** `WpSpin.e` diverges — it is the wedge, and
**it offers TWO report-typed bindings in the picker, `spin : Int -> Node` AND
`report : Int -> Node` (MEASURED)**, so every step that says "pick `report`"
expects two entries and you pick the second. **`WpChain.e` is a SECOND WEDGE of
a different shape** — a fold over a cyclic list, not an import chain — usable
anywhere a step says `WpSpin`. `WpBlow.e` allocates without bound. `WpInt.e`
renders a small document from an `Int` parameter and is the control: **if
`WpInt` does not render, the trouble is the server or the roots, not the
fixture.** **The other three fixtures offer exactly one binding each.**

The seven commands, exactly as `editor/vscode/package.json` spells them:
**Ermine: Preview Report...** (`ermine.previewReport`), **Ermine: Render Report
to JSON** (`ermine.renderReport` — under the default `panel` target it renders
into the PANEL, not JSON; the title is open decision 4), **Ermine: Restart
Language Server** (`ermine.restartServer`), **Ermine: Show Language Server
Output** (`ermine.showOutput`), **Ermine: Reload Modules**
(`ermine.reloadModules`), **Ermine: Toggle Fast Mode** (`ermine.toggleFastMode`),
**Ermine: Write Params Skeleton** (`ermine.writeParamsSkeleton`, B22–B26).

The settings this guide touches, with their defaults:
`ermine.preview.timeoutSeconds` = `60`,
`ermine.preview.restartAfterStuckSeconds` = `0`,
`ermine.preview.roots` = `[]`,
`ermine.preview.maxDocumentBytes` = `16777216`,
`ermine.maxHeap` = `""`, `ermine.serverPath` = `""`,
`ermine.preview.target` = `panel` (**the settings file sets `json` for A–D**),
`ermine.preview.writersPath` = `""` (the sibling `ermine-writers` checkout).
`tracker/playtest/settings.example.json` has each of them written out.

### Open decisions that change what you should see

Five. **Q21 was DECIDED by you on 2026-09-23; none of the other four has
been put to you yet.** The first three are the ones this file has always
carried; 4 and 5 are new with the panel (WP-10).
`tracker/PLAYTEST-RESULTS.md` has a row for each, for your answer.

1. **Q21 (§13 of `tracker/JSON-WIDGET-PLAYGROUND.md`) is DECIDED (you,
   2026-09-23): fix the example, ticket the engine.** The first pick of
   `Sales.report` writes a skeleton with **today's** dates, and `Sales`'s rows
   all fall in 2026-01..2026-03, so that first render selects no rows. It USED
   to answer a 500 (*"an empty relation built from no rows carries no
   columns"*); `Sales.e` now builds that table with `relationWithHeader`, so it
   renders **`ok=true`: a heading with `matched: 0`, and a `byDay` table with
   its four columns and zero rows** (MEASURED against a real server,
   `scratch-widget-preview/q21-sales/`). The engine gap — any report that
   builds an empty relation with plain `relation` still gets that 500 — is
   ticket **WP-29**. Steps **A4**, **B1** and **B4** all point here.
2. **The automatic restart's DEFAULT is the orchestrator's, and you have not
   been asked.** `ermine.preview.restartAfterStuckSeconds` ships at `0` = never,
   *because this file had never been run*. **C21 [2.28]** checks that the
   default changes nothing; **C22–C28** are the only things that can observe the
   feature at all. After you have run them you will be asked whether the default
   should move.
3. **The U7 `.gitignore` reading is flagged for you.** U7 asked for the
   generated `.ermine/preview/.gitignore` "PLUS the repo line", which was
   ambiguous. S3 took the reading *the extension writes only the self-contained
   generated file, and this repository's own `.gitignore` carries the line* —
   `**/.ermine/preview/**/*.schema.json`, line 21 of the root `.gitignore`. The
   alternative (a notification offering to edit YOUR root `.gitignore`) was
   named and not built. **B16 [2.46]** is where you see the consequence and can
   say whether you want the other reading.
4. **The command title "Ermine: Render Report to JSON" is now misleading, and
   was deliberately NOT renamed** (the WP-10 S2 review's N4; Q22 in §13 of the
   tracker). Under the default `panel` target it renders into the panel. A
   rename (e.g. "Ermine: Render Report") would change the palette entry every
   step in this file names, so it waits for you. **E12** and **E13** are where
   you use it both ways.
5. **The panel's seven design choices (the WP-10 design review's U1–U7) were
   TAKEN BY THE ORCHESTRATOR on the review's recommendations. You have NOT been
   asked any of them** (Q23 in §13 of the tracker). In what you will see: U1 the
   `ermine.preview.target` setting with `panel` as the default and the JSON tab
   kept (**E13**); U2 `retainContextWhenHidden` on AND a resync on visibility
   (**E5**); U3 the bundle found from the checkout and the writers from a new
   setting with a sibling default (**E8**, **E14**); U4 a Restart button and no
   other button in the panel (**E6**); U5 no `blob:` in the page's policy
   (**E3**); U6 deferred relations refused rather than fetched (**E2**'s
   `Sales` sub-step — **U6 was taken on the design review's F2, "the preview never
   mints a deferred token", which `Sales.e` disproves; Q24 is DECIDED (you,
   2026-09-23: "Do (a) and (d) now, file (c)."): the refusal stays, the
   done-when is an inline fixture (since playtest F2 only the typed `Sales.e`
   can meet it: `Doc/SalesReport.e` is refused at render, Q27), `heading`/`text` now draw, the fetch pair
   is WP-30**); U7 the extension's unit tests gate every commit (no step).
   Any of them is yours to overturn.

---

## If you only have 30 minutes

Fourteen steps, in this order (seventeen with the database's three, 15–17, added 2026-09-25). The first ten are the cheapest ten that
between them say whether the loop works at all, whether the disk-writing half
works, and whether the wedge guard closes the loop it was built for; the last
four are the panel steps that settle the most (whether a document draws at
all, the F1 contradiction in the typings, the folder-delete question, and the
legacy writers). Everything else is detail on top of these. **Steps 1–10 run
with `ermine.preview.target` at `json` (the settings file's value); set it to
`panel` before step 11.**

| | Step | Why it is in the fourteen |
|---|---|---|
| 1 | **A1** | the extension activates and the session boots at all |
| 2 | **A3** | the server answers `ermine/preview/reports` and the binding pick is populated **by type** |
| 3 | **A4** | a render reaches a tab — the whole point of WP-7 |
| 4 | **A5** | save → re-render in place, generation 2: the loop is a loop |
| 5 | **B1** | the disk-writing half: three files written, params file opened |
| 6 | **B4** | edit the dates → a document with rows (the first pick already renders an empty one, Q21) |
| 7 | **B5** | the `$schema` line is not squiggled and a wrong key is (D1 go/no-go) |
| 8 | **B11** | invalid JSON refuses in the tab instead of rendering yesterday's parameters |
| 9 | **C1** | the watchdog fires, the banner appears, the status bar turns orange |
| 10 | **C5** + **C6** | after a restart the wedged report is **held** and you are asked — Q17's loop, closed or not |
| 11 | **E1** + **E2** | E1 opens the panel on `core/src/test/resources/doc/Sales.e` → `report` (E2's setup; was `Doc/SalesReport.e`, refused at render by F2); E2: a document draws in the panel at all — the bundle loads in a real webview (nobody has seen it) |
| 12 | **E5** + **E6** | the stuck banner survives a hidden panel — and, instrumented, which of the two contradicting `@types/vscode` sentences is true (F1). **E6 is not optional here**: E5 leaves the server wedged, `WpInt.e` edited and the timeout at 5 s, and E6's Undo puts all three back |
| — | *re-pick* | **Ermine: Preview Report...** → `core/src/test/resources/doc/Sales.e` → `report` again, and check the `Sales` heading and three tables are back: E8 and E9 both need E2's document (was `Doc/SalesReport.e`: F2) |
| 13 | **E8** | deleting the bundle files flips the page; deleting the folder is the open question the typings predict |
| 14 | **E9** | `table` through the writers' `runTabular` — WP-11's done-when, human since WP-9 |
| 15 | **F4** | the database: ONE password prompt naming `ermine @ 127.0.0.1`, then the status bar reads `sales-mssql (mssql) @ 127.0.0.1` (needs 0.1.17, `scripts/db.sh status` OK, the profile in USER settings: F1–F3's setup) |
| 16 | **F5** | `DbFetchTopN` draws from `ErmineSales` at tier s: china, us-south, Other in the pie — DB-PLAN S2's done-when |
| 17 | **F8** | the Trace view: the SQL, `scanned` 388 against `rows` 8, db time against the rest, and the one channel line |

Steps 15–17 were added by DB stage 2e (2026-09-25) and are the database's cheapest three. If F4
fails, F5 and F8 mean nothing.

If any of 1–4 fails, stop and report: nothing after it means anything. If
**E1** or **E2** fails, E5, E6, E8 and E9 mean nothing either.

---

## Group A — the core loop

**Must work or nothing else matters.** A1–A5 are the spine; A6–A14 fill in the
rest of WP-7's done-when. A15–A18 are an optional settings-validation tail.

### A1 [§0] — Activate, and watch the session boot — **NEVER RUN**

- **Setup:** the window `tracker/PLAYTEST-SETUP.md` tells you to open. No settings.
- **Do:** open any `.e` file. Then run **Ermine: Show Language Server Output** and watch.
- **Expect:** the left-hand status bar item goes `$(symbol-namespace) Ermine: preparing…` → `$(symbol-namespace) Ermine: starting session…` → `$(symbol-namespace) Ermine`. The Ermine channel carries `Ermine: loading the session (129 modules, ~13s)…` and then the server's own boot line, **MEASURED over four boots by the setup agent: `Ermine session ready: 129 modules in 11.8s`, and 11.8–12.0 s every time.** The extension's own first line is `language client started`.
- **A cheap pre-flight:** `tracker/playtest/check-server.py` starts the same server without an editor and prints the same boot line. If A1 fails, run it — it says whether the problem is the server or the extension.
- **Failure:** the status bar sticks on `Ermine: starting session…` for more than ~60 s; or reads `Ermine: server not found` (then `ermine.serverPath` is wrong), `Ermine: no workspace`, or `Ermine: server failed` (the tooltip holds the error). **`Ermine: building the classpath cache (first run, sbt)`** as a progress notification is not a failure — it means `target/ermine-classpath` was missing and sbt is building it; it can run for minutes.
- **Bears on:** WP-7 done-when; everything below.

### A2 [1.1] — The file quick pick — **NEVER RUN**

- **Setup:** A1 passed.
- **Do:** run **Ermine: Preview Report...**.
- **Expect:** a quick pick whose placeholder is `Ermine: which file holds the report?`. The active editor's `.e` file is FIRST; the rest are the workspace's `**/*.e` sorted by name, each with its workspace-relative path as the description.
- **Failure:** `Ermine: no .e file found in the workspace.` (a warning notification) when there plainly are some; or the active file missing from the list; or `Ermine: the language server is not running.` (an error notification) — then A1 did not really pass.
- **Bears on:** WP-7 done-when.

### A3 [1.2] — The binding quick pick, populated by TYPE — **NEVER RUN**

- **Setup:** A2's pick open.
- **Do:** type `Sales`, pick `core/src/test/resources/doc/Sales.e`.
- **Expect:** a second quick pick, placeholder `Ermine: which binding in Sales.e?`, listing **`report`** with the description **`Query -> Node`**, and one last entry `$(edit) Type a binding name…` described as `any top-level binding, report-typed or not`. Nothing else. **MEASURED over the wire:** `ermine/preview/reports` answers `module = "Sales"`, `reports = ["report : Query -> Node"]`.
- **Failure:** only the `$(edit) Type a binding name…` entry, described as `no report-typed binding was found in this file` (the server listed nothing) or `the server could not list this file: <error>` (it failed). The channel then carries `preview: ermine/preview/reports: <error>`.
- **Bears on:** WP-7 done-when.

### A4 [1.3, 1.4] — The render: status bar, untitled tab, the answer — **NEVER RUN**

- **Setup:** A3's pick open. **This is also the first pick of `Sales.report`, so it WRITES THREE FILES** — that is Group B's subject; here you only need the tab.
- **Do:** pick `report`.
- **Expect:** the right-hand status bar item shows `$(sync~spin) Ermine: Sales.report` while the render runs and settles to `$(json) Ermine: Sales.report` (tooltip: the file path, `binding: report`, `roots: …`). An **untitled JSON tab** opens beside your editor. The channel logs `preview: render Sales.report (generation 1; the report was picked; …)`.
- **Expect, in the tab — AND THIS IS Q21:** on a clean workspace the skeleton written by this very pick carries **today's** dates, which select no sale, and the answer is a **document** — `ok=true`, the heading's props `{"title": "Sales", "sortColumn": "day", "matched": 0, "total": 0}`, and the first table (`byDay`) with its four columns (`amount`, `day`, `region`, `units`), `"rows": []`, `"rowCount": 0`. **MEASURED 2026-09-23** (`scratch-widget-preview/q21-sales/`). Before your Q21 decision this was a 500 (*"an empty relation built from no rows carries no columns"*, path `$.children[1].cells[0][0].props`); **that 500 in the tab is now a FAILURE** (it means `Sales.e` is not the fixed one). If instead no params file could be written you get the WP-7 answer, MEASURED exactly: `{"ok": false, "status": 400, "message": "the required key \"fromDay\" is missing", "path": "$.params", "generation": 1}` — and no `reason` key, because this is the decoder's refusal and not a placement one (read Appendix 1.1 before calling that wrong).
- **Failure:** no tab; or the status bar stays on `$(sync~spin)` for ever; or the tab holds something that is neither a document nor an `{ok:false, …}` object.
- **Bears on:** WP-7 done-when; **Q21**; Group B.

### A5 [1.5] — Edit the report's own file and save — **NEVER RUN**

- **Setup:** A4 done, tab open. You are about to edit a fixture.
- **Do:** add a comment line to `core/src/test/resources/doc/Sales.e` and **save**. (Undo it in A14 with `git checkout --`.)
- **Expect:** the SAME tab updates **in place** — no second tab, no restart — and **it is NOT pulled in front of the file you are editing** (only the two commands reveal it). The channel logs ONE line: `preview: render Sales.report (generation 2; invalidated: Sales; params from <…>/.ermine/preview/Sales/report.params.json)`. **MEASURED over the wire:** the save produces `ermine/preview/invalidated {"modules":["Sales"]}`.
- **Failure:** two render lines for one save; a second tab; the tab jumping in front of you; or no render at all.
- **Note:** the old §1.5 quoted this line without its trailing clause. **Since 0.1.8 every render line ends with either `params from <path>` or `empty parameters`** (`extension.js:2157`) — the clause is not optional.
- **Bears on:** WP-7 done-when.

### A6 [new] — Invalidation of an IMPORTING module — **NEVER RUN**

- **Setup:** `Sales.report` picked and rendered (A4). **There is no fixture for this** — `WpChain.e` is a second wedge by a different mechanism (a fold over a cyclic list), NOT an import chain, and it imports only stdlib modules. So this step uses a module `Sales.e` really does import: `core/src/main/resources/modules/Json.e` (`Sales.e:39`). Its siblings `Date`, `Layout/Doc`, `List`, `Relation` would do as well.
- **Do:** add a comment line to `core/src/main/resources/modules/Json.e` and **save**. Do NOT touch `Sales.e`.
- **Expect:** the tab re-renders although you edited a different file, and the channel's render line names the IMPORTER, not the file you edited: `preview: render Sales.report (generation N; invalidated: Sales; …)`. **The server names the modules IT invalidated, and `Sales` is in that set because it imports `Json`.**
- **Failure:** no render line at all — the server's dependency edges did not reach the importer, which is Q4's territory.
- **Undo:** `git checkout -- core/src/main/resources/modules/Json.e`. **Do this before anything else** — it is a stdlib module every suite loads.
- **If you would rather not touch the stdlib, SKIP this step** and say so; A5 already shows the same mechanism for the report's own file.
- **Bears on:** WP-7 done-when ("re-renders when a file it depends on is saved"); Q4.

### A7 [1.8] — The render command re-renders into the same tab — **NEVER RUN**

- **Setup:** A5 done.
- **Do:** run **Ermine: Render Report to JSON**.
- **Expect:** the SAME tab is updated again and IS revealed this time. The channel logs `preview: render Sales.report (generation 3; Ermine: Render Report to JSON; …)`.
- **Failure:** a new tab each time; or no reveal.
- **Bears on:** WP-7 done-when.

### A8 [1.7] — Under `target: json`, the JSON tab and NO panel — **NEVER RUN**

- **Setup:** `"ermine.preview.target": "json"`, as the setup's settings file has it. **Under the DEFAULT (`panel`) there IS a panel since 0.1.12** — that is Group E, not this step.
- **Do:** look for a webview after A4–A7's renders.
- **Expect:** one untitled JSON editor tab and one status bar item, and **no `Ermine preview` webview tab**: `json` routes to the tab alone (`editor/vscode/src/preview-core.js:5523`). The tab path is the 0.1.11 code, unchanged.
- **Failure:** a webview tab titled `Ermine preview` under `json` (then the setting did not take: check `.vscode/settings.json`, and that the window is single-root).
- **Bears on:** U1; E13 checks the same routing from the panel's side.

### A9 [2.1] — Closing the tab does not resurrect it — **NEVER RUN**

- **Do:** close the JSON tab (**Don't Save**), then run **Ermine: Render Report to JSON**.
- **Expect:** a NEW tab opens; the old one is not resurrected.
- **Failure:** two tabs, or none.
- **Bears on:** WP-7 done-when.

### A10 [2.2] — The pick is remembered per workspace — **NEVER RUN**

- **Do:** close and reopen the window (or **Developer: Reload Window**), wait for the boot, then run **Ermine: Render Report to JSON** WITHOUT picking anything.
- **Expect:** it renders `Sales.report` straight away. The channel logs `preview: remembered Sales.report` during activation. The pick lives in `workspaceState`.
- **Failure:** the file picker opens instead — the pick was not persisted.
- **Bears on:** WP-7 done-when.

### A11 [new] — The status bar's states and tooltips — **NEVER RUN**

- **Setup:** a pick in place.
- **Do:** read the right-hand status bar item during and after a render, and hover it.
- **Expect, verbatim** (`preview-core.js:2087-2135`): idle `$(json) Ermine: Sales.report`, tooltip = the file path, then `binding: report`, then `roots: <the list>` or `roots: (none configured)`, and — only when the module name is unknown — `the module name is unknown, so \`invalidated\` cannot match it`. While rendering: `$(sync~spin) Ermine: Sales.report`, tooltip `rendering`. The other three states (`$(warning) Ermine preview: stuck`, `$(warning) Ermine preview: held`, `$(debug-disconnect) Ermine: preview offline`) belong to Group C. **The item is hidden entirely when nothing is picked, nothing is stuck, nothing is held and the client is running.**
- **Failure:** wrong text, a missing tooltip, or an item that stays visible with nothing picked.
- **Bears on:** WP-7 done-when.

### A12 [1.9, 1.10, 1.11, 1.12] — The Q11 placement-404 watcher — **NEVER RUN**

- **Setup:** `Sales.report` picked and rendered.
- **Do, in order:** (1) `mv core/src/test/resources/doc/Sales.e /tmp/Sales.e.away`; (2) run **Ermine: Render Report to JSON**; (3) `mv /tmp/Sales.e.away core/src/test/resources/doc/Sales.e`.
- **Expect:** after (1) **nothing happens** — the extension re-renders on a save, not on a delete. After (2) the tab shows the placement 404: `{"ok": false, "status": 404, "message": "cannot read Sales.e", "reason": "unreadable", "generation": N}` and the channel logs `preview: the pick cannot be placed (unreadable); watching <path> for it to come back`. **The `reason` key is the whole point:** it says the PREVIEW refused the file, not the runner. After (3) **the tab re-renders BY ITSELF within a second or two**, with no command and no restart, and the channel logs `preview: render Sales.report (generation N+1; the picked report's own file appeared or changed after a placement 404; …)`.
- **Failure:** the tab stays on the 404 and the channel logs no new render. Two causes worth separating: the server is older than Q15 and sends no `reason` (the answer in step 2 then has no `reason` key, and the extension deliberately never triggers); or VS Code's watcher did not report the creation, which happens for a file outside every workspace folder (*external*, not exercised here). **Ermine: Render Report to JSON** always recovers it by hand.
- **Bears on:** **Q11**, **Q15**.

### A13 [1.13] — A binding that does not exist — **NEVER RUN**

- **Do:** **Ermine: Preview Report...** → `core/src/test/resources/doc/Sales.e` → `$(edit) Type a binding name…` → type `reprot`.
- **Expect:** the tab shows a 404 with **no `reason` key** — it is the runner's, because the module loaded fine. Moving the file away and back does NOT re-render here: `invalidated` owns this case, and one save must not render twice.
- **Failure:** a `reason` key on this answer (the server would then be conflating runner and placement failures, and A12's watcher would fire on the wrong thing).
- **Bears on:** **Q11**, **Q15**.

### A14 [1.6] — Put the files back — **NEVER RUN**

- **Do:** `git checkout -- core/src/test/resources/doc/Sales.e` and, if you ran A6, `git checkout -- core/src/main/resources/modules/Json.e`. Then `git status --short`.
- **Expect:** **`.ermine/` and `.vscode/` and nothing else** — `.vscode/` is NOT gitignored in this worktree; the setup's own files were committed in `edb0b74c`. **`core/src/test/resources/doc/Sales.e` must be clean:** other suites read it.
- **Bears on:** hygiene.

### A15 [2.3] — `ermine.preview.roots` validation (OPTIONAL) — **NEVER RUN**

- **Do:** set `"ermine.preview.roots": ["not/a/place"]` in the workspace settings; render. Then set `["   "]`; render.
- **Expect:** a RELATIVE root is resolved against the workspace folder, so the first is silent and the next render still works — the report's own tree is inferred. The second produces ONE warning notification `Ermine: ermine.preview.roots has an empty entry; each root is a directory path` and the same line in the channel prefixed `preview: `, and that root is NOT sent. **Each distinct problem warns once per base directory.**
- **Failure:** a notification storm, or a bad root reaching the server.
- **Bears on:** §2.4 of the ticket.

### A16 [2.4] — `ermine.maxHeap` floor and restart (OPTIONAL) — **NEVER RUN**

- **Do:** set `"ermine.maxHeap": "16m"`. Then set `"2g"`. Then clear it.
- **Expect:** `16m` earns ONE warning notification, verbatim: `Ermine: ermine.maxHeap "16m" is below the launcher's 64m floor (the resident session cannot boot in a heap that small); the server uses its own default of 2g` — and the server keeps its own 2g. Setting `2g` RESTARTS the server (the setting is `-Xmx`, fixed at process start).
- **Failure:** the server booting with 16m, or not restarting on a real change.
- **Bears on:** §2.4; C20 needs this setting.

### A17 [2.5] — `ermine.preview.timeoutSeconds` type check (OPTIONAL) — **NEVER RUN**

- **Do:** set `"ermine.preview.timeoutSeconds": "60"` — a STRING.
- **Expect:** the channel logs `settings: ermine.preview.timeoutSeconds is a whole number of seconds, not a string` and the value is not sent. (Out of range instead: `settings: ermine.preview.timeoutSeconds of 5000 is outside 0..3600 and was not sent`.)
- **Failure:** the string reaching the server.
- **Bears on:** §2.4.

### A18 [2.6] — A file with no report-typed binding (OPTIONAL) — **NEVER RUN**

- **Do:** **Ermine: Preview Report...** on a `.e` file with no report-typed binding.
- **Expect:** the binding pick offers ONLY `$(edit) Type a binding name…`, described `no report-typed binding was found in this file`. Typing `report` picks it anyway and the render answers a 404 or a 400, which the tab shows.
- **Failure:** an empty quick pick with no fallback entry, or a crash.
- **Bears on:** WP-7 done-when.

---

## Group B — params files

**The newest code, and the most likely to surprise.** Group A must have passed.
A report's parameters come from
`<workspace folder>/.ermine/preview/<Module>/<binding>.params.json`, read from
DISK at the moment a render is sent. The pure half is unit-tested (`npm run
test:preview`, 313 tests at 0.1.10 after the S4 fix round, round 2); the send half, the three writes and the
five non-object params roots were MEASURED against a real `bin/ermine-lsp`
with no editor. **Everything about VS Code's own behaviour below is unobserved
by anyone.**

**START CLEAN:** `rm -rf .ermine` in the worktree root, and `git status --short`
must show nothing under it before B1. If you did Group A you already have a
written `Sales` params file — delete it, or B1 tests the wrong branch.

**REMOTE AND VIRTUAL WORKSPACES ARE OUT OF SCOPE AND WILL NOT WORK** (S2 review
M7): the params file is addressed with `vscode.Uri.file(fsPath)`, which discards
the scheme and the authority, so on a `vscode-remote:` or a virtual workspace
the read and the watcher both point at a local path that is not there.
Everything here assumes a local folder.

### B1 [2.43] — The first pick writes three files — **NEVER RUN**

- **Setup:** no `.ermine` directory at all. `ermine.preview.timeoutSeconds` at its default `60`.
- **Do:** **Ermine: Preview Report...** → `core/src/test/resources/doc/Sales.e` → `report`.
- **Shortcut for later steps:** `tracker/playtest/params/Sales.report.params.json` is a ready-made params file with dates that RENDER; its `README` says where to copy it. **Do not copy it before this step** — B1 is about the file the extension writes for itself.
- **Expect, on disk:** three files — `.ermine/preview/.gitignore`, `.ermine/preview/Sales/report.schema.json`, `.ermine/preview/Sales/report.params.json`. The params file holds exactly `{"$schema": "./report.schema.json", "fromDay": "<today>", "toDay": "<today>", "orderBy": "ByDay"}`, pretty-printed. **`onlyRegion` is ABSENT** — a `Maybe` key is omitted, not nulled. **The dates are TODAY's in YOUR timezone**, not UTC's.
- **Expect, in the channel** (`preview-core.js:3934-3941`, said ONCE per report): `preview: wrote <…>/report.params.json from the report's parameter type, with <…>/report.schema.json beside it (generated, and gitignored by <…>/.ermine/preview/.gitignore). It is ordinary committed source: edit it, save it, and the preview re-renders.`
- **Expect, in the tab:** **a document with an EMPTY table** (Q21, decided 2026-09-23): `ok=true`, the heading at `matched: 0`, the `byDay` table with its four columns and zero rows. **MEASURED 2026-09-23.** The old 500 (*"an empty relation built from no rows carries no columns"*) in the tab is a FAILURE now. B4 is where the rows appear.
- **Failure:** fewer than three files; a params file with `onlyRegion` in it or with `null` values; UTC dates when your timezone differs; or the channel line missing (it is `once per report`, so a second pick will not repeat it).
- **Bears on:** WP-8 S3; **Q21 (yours)**; U2.

### B2 [2.44] — …and opens the params file without stealing focus — **NEVER RUN**

- **Setup:** `rm -rf .ermine` again so the first-pick branch runs afresh.
- **Do:** start typing in some other editor. WITHOUT stopping, run B1's pick.
- **Expect:** the params document opens **beside** the render tab and **the cursor stays where you were typing**. The render tab is revealed too — the pick asked for it.
- **Failure:** the cursor jumps into the params file (U2's whole point is that it does not), or the params file does not open at all.
- **Bears on:** WP-8 S3, **U2**.

### B3 [2.45, 2.45b] — At most one render per coalescing window, and the second is not a question — **NEVER RUN**

- **Setup:** watch the Ermine channel through B1/B2.
- **Expect:** first `preview: render N is yielding to the parameter schema (<why>)` — **that render is NOT sent** — then either **ONE** `preview: render M (… ; the params skeleton was written; params from …/report.params.json)` line if the params watcher's own event lands inside the 150 ms coalescing window, or **TWO IDENTICAL ones** if it lands outside it. **Two identical renders are expected and harmless**: same session, no boot, same parameters, the wedge mark untouched.
- **Failure:** **ZERO** renders, or two renders that DIFFER. And [2.45b]: on a report that previously wedged the preview and whose params type has NO required fields (so the skeleton sends `{}`), **a Render anyway / Not now question INSTEAD OF a document is the defect** (review N-3): the scheduled render carries the trigger of the render that wrote the file — `explicit` for a pick — so consent stays consent. **One residue, and it is small (N-d):** if the watcher's event lands OUTSIDE the window it is a SECOND render still carrying `params-file`, so on that same empty-params report it can ASK — but the document has already arrived from the first one, so what you see is a question BESIDE a rendered tab. Answer it either way; **a question with NO document is the defect.**
- **Bears on:** WP-8 S3 review M-4, N-3, N-d.

### B4 [2.49 first half; Q21] — Edit the dates, get a document with rows — **NEVER RUN**

- **Setup:** B1 done; the params file open (B2 opened it for you).
- **Do:** change `"fromDay"` to `"2026-01-05"` and `"toDay"` to `"2026-03-17"`, and **save**.
- **Expect:** the SAME tab updates in place and now holds a **document with rows** — `{"kind": "doc", …}`, heading `matched: 8`. **MEASURED against a real server: `ok=true`, a 1407-byte document** (re-measured 2026-09-23 on the fixed `Sales.e`: 1407 bytes, and the same document as before the fix, deferred token and expiry aside). The channel logs ONE render line whose reason is `the params file was saved` and whose tail is `params from <…>/report.params.json`.
- **Failure:** still the empty table or a 500 (then the dates did not reach the server — check the render line's tail says `params from`, not `empty parameters`); or two render lines for one save (the editor's save event and the file watcher both fire and the 150 ms window should collapse them).
- **Bears on:** WP-8 S2/S3; **Q21** (decided: the first pick renders an empty table; this step fills it).

### B5 [2.47] — The `$schema` line is not squiggled; a wrong key is — **NEVER RUN**

- **Setup:** the params file open, `report.schema.json` beside it.
- **Do:** look at the `"$schema"` line. Then type `"nope": 1` into the object.
- **Expect:** **no squiggle on the `"$schema"` line** — that is D1, and it is why `schemaFileFor` injects a `$schema` property into the object the root `$ref` names. `"nope"` **does** squiggle (`additionalProperties: false`).
- **Failure:** **if the `$schema` line itself squiggles, D1's fix does not work in this editor and the whole scheme needs rethinking.** If `"nope"` does NOT squiggle, VS Code is not loading the relative schema at all.
- **Bears on:** **D1**, and it is a go/no-go.

### B6 [2.48] — Completion offers the keys and the enum values — **NEVER RUN**

- **Do:** delete the `orderBy` line and press Ctrl+Space inside the object. Then type `"orderBy": ` and press Ctrl+Space again.
- **Expect:** the first offers `fromDay`, `toDay`, `onlyRegion`, `orderBy`. The second offers `ByDay`, `ByAmount`, `ByUnits`.
- **Failure:** **the second is the `$ref` → `$defs` hop**, which is what U1's `$id` drop was for. If the enum values do not appear, VS Code's JSON language service is not resolving a fragment `$ref` in a file loaded by relative path, and **D3 is answered NO**.
- **Bears on:** **D3**, and it is a go/no-go.

### B7 [2.50] — Editing the params TYPE updates the schema file, and the editor notices — **NEVER RUN**

- **Setup:** the params file open.
- **Do:** in `core/src/test/resources/doc/Sales.e`, rename `data Query`'s `onlyRegion` field to `onlyReg` and save. Afterwards `git checkout --` it, then save it once more with NO change to the type.
- **Expect:** the render re-runs; `report.schema.json` is rewritten (`stat` it, or watch `git status`) and the channel logs `preview: rewrote <…>/report.schema.json (<why>)`; and **the params file's completion and squiggles follow WITHOUT a window reload** — `onlyRegion` now squiggles as an unknown key, Ctrl+Space offers `onlyReg`. On the final no-op save, **`report.schema.json`'s mtime must NOT move** (D8's write-if-different) and there must be no `preview: rewrote` line.
- **Failure:** **whether VS Code re-reads a relative `$schema` file that changed on disk is UNVERIFIED.** If it does not, G17 needs its own ticket — record exactly what you saw. A moving mtime on a no-op save is a D8 regression.
- **Bears on:** **G17** (open), **D8**.

### B8 [2.34] — Save the params file: ONE render, in place — **NEVER RUN**

- **Do:** change `"toDay"` to `"2026-01-20"` and save.
- **Expect:** the SAME tab updates in place, ONE render line with reason `the params file was saved`, and the document has fewer rows.
- **Failure:** **two `preview: render` lines for one save** — the editor's save event and the watcher both fire and the 150 ms coalescing window must collapse them. That is the defect this step exists for.
- **Bears on:** WP-8 S2.

### B9 [2.35] — A change from OUTSIDE the editor — **NEVER RUN**

- **Do:** `sed -i s/2026-01-20/2026-03-17/ .ermine/preview/Sales/report.params.json`
- **Expect:** the tab re-renders by itself within a second or two, reason `the params file was changed outside the editor`. The channel also carries, from when the pick was made, `preview: watching <…>/report.params.json for parameter changes`.
- **Failure:** nothing happens. **This is the ONLY step that can observe the one source mutant of twenty-seven that survives the whole unit suite** — `installParamsWatcher` returning before it registers anything, and equally a `RelativePattern` rooted at the wrong place. `onDidSaveTextDocument` cannot see this path; the watcher is the only thing that can. A `git checkout` of the params file does the same thing.
- **Bears on:** WP-8 S2; the surviving mutant.

### B10 [new] — A reordered file renders the same document — **NEVER RUN**

- **Do:** re-order the keys in the params file (put `orderBy` first, `$schema` last) without changing a single value, and save.
- **Expect:** a render goes, and the document in the tab is **the same document** as before the re-order. (With `Sales.report` NOT held, a re-format always renders; C13 is what happens when it IS held.)
- **Failure:** a different document — parameter order would then be reaching the report, which it must not.
- **Bears on:** WP-8 S2; it is the control for C13.

### B11 [2.36] — Invalid JSON refuses in the tab, and renders nothing — **NEVER RUN**

- **Do:** delete the comma after `"fromDay": "2026-01-05"` and save.
- **Expect:** **NOTHING IS RENDERED.** The tab shows the refusal: `{"ok": false, "status": null, "message": "The params file is not valid JSON, so the report was not rendered: <the parser's own words> Nothing was sent to the language server.", "path": "<the params file>", "paramsProblem": "invalid-json", "generation": N}`. The channel logs `preview: render N REFUSED (invalid-json): …`. The status bar leaves the spinner and goes back to `$(json) Ermine: Sales.report`. **`status` is null on purpose:** no server was asked. Fix the comma and save; it renders again.
- **Failure:** a render happening anyway (yesterday's parameters under today's file would look like it worked); or `status: 400`, which would mean a server was asked.
- **Note:** the old §2.36 quoted this message without its final sentence. **The message ends `Nothing was sent to the language server.`** (`preview-core.js:2814-2816`) — always.
- **Bears on:** WP-8 S2, G7.

### B12 [2.37] — An empty file is not `{}` — **NEVER RUN**

- **Do:** `: > .ermine/preview/Sales/report.params.json`
- **Expect:** the same shape with `"paramsProblem": "empty"` and its own sentence: `The params file is empty. An empty file is not JSON; write \`{}\` in it for a report whose parameters are all optional, or fill in the keys the schema beside it names. Nothing was sent to the language server.`
- **Failure:** the report rendering with `{}` — an empty file is a truncated write or an interrupted checkout, not a decision.
- **Bears on:** WP-8 S2.

### B13 [2.38] — Delete the file: a 400 that names the key, said once — **NEVER RUN**

- **Do:** `rm .ermine/preview/Sales/report.params.json`. Then run **Ermine: Render Report to JSON** a second time.
- **Expect:** the tab re-renders with EMPTY parameters, which for `Sales` is A4's 400 — `the required key "fromDay" is missing` at `$.params`. The channel says, ONCE: `preview: no params file at <path> -- rendering with empty parameters. Write one there (it is ordinary committed source) to give this report its parameters.` **The second render does NOT repeat it:** one line per report, not one per render.
- **Failure:** the sentence repeating per render; or no render at all.
- **Bears on:** WP-8 S2.

### B14 [2.39] — A wrong key earns the server's own 400 — **NEVER RUN**

- **Setup:** put the params file back (B4's dates).
- **Do:** add `"fromDy": "2026-01-05"` beside the right key and save.
- **Expect:** the server's own 400: `{"ok": false, "status": 400, "message": "the key \"fromDy\" is not allowed here", …}`. **MEASURED without an editor, that exact message.** The status bar must NOT turn orange, nothing is marked as having wedged, and the next save tries again.
- **Failure:** an orange status bar or a wedge mark. **A refusal is not a wedge.**
- **Bears on:** WP-8 S2.

### B15 [2.49] — A second pick never rewrites the params file — **NEVER RUN**

- **Do:** with the params file edited to B4's dates and saved, pick another report, then pick `Sales.report` again. Then **Developer: Reload Window** and pick it again.
- **Expect:** **your edit survives, every time.** Nothing in this version ever overwrites a params file. Check with `git diff` or by looking. The channel says nothing about writing it again.
- **Failure:** the skeleton coming back — that is destroyed committed source, and it is the single most serious thing this group can find.
- **Bears on:** WP-8 S3; review M-2.

### B16 [2.46] — `git status` shows the params file and NOT the schema — **NEVER RUN**

- **Do:** `git status --short`; then `git check-ignore -v .ermine/preview/Sales/report.schema.json`; then `git check-ignore -v .ermine/preview/Sales/report.params.json`.
- **Expect:** `?? .ermine/` covering the params file and the generated `.gitignore`, and **NOT** `report.schema.json`. The first `check-ignore` names **this repository's own** `.gitignore`, line 21: `**/.ermine/preview/**/*.schema.json`. The second names **nothing** (exit 1).
- **Failure:** the schema file showing up as untracked, or the params file being ignored.
- **Bears on:** **U7 — and this is the step where the OPEN reading is visible.** S3 took the reading "the extension writes only the generated file; the repo carries the line". If you would rather the extension OFFERED to add a line to your own root `.gitignore`, say so in the notes: that alternative is named and not built.

### B17 [2.42] — A credential-looking key warns once and never blocks — **NEVER RUN**

- **Do:** add `"apiToken": "hunter2"` to the params file and save. Then save it again.
- **Expect:** ONE warning notification, verbatim: `Ermine: The key "apiToken" looks like a credential. A params file is committed to the repository and its value is written to the language server's log, so a password or an API token in one is a secret in both. Nothing is blocked: if the report really takes it as a parameter, ignore this. This is a check on the KEY NAME only -- it looks for pass, pwd, secret, token and apiKey, so it says nothing about a key called connectionString, dsn, jwt, auth, bearer, privateKey or credential.` **The render still happens** (U5: warn, never block) and the server answers a 400 because `apiToken` is not a `Query` field. **The second save does NOT warn again** — once per file per session.
- **Failure:** a blocked render, or a warning per save.
- **Bears on:** WP-8 S2, **U5**.

### B18 [2.40] — A report outside every workspace folder — **NEVER RUN**

- **Setup:** `mkdir -p /tmp/wp7 && cp tracker/playtest/fixtures/WpSpin.e /tmp/wp7/`. **Do NOT add `/tmp/wp7` to the workspace** — the point of the step is that it is outside every folder, and a second folder would make the window multi-root and stop VS Code reading the window-scoped settings the rest of this guide sets.
- **Do:** open `/tmp/wp7/WpSpin.e` so it is the active editor, then **Ermine: Preview Report...** (it is offered first even though the workspace scan cannot see it) → `report` (**the second of the two report-typed entries — `spin` is the first**).
- **Expect:** the channel says, ONCE: `preview: The report "<path>" is not inside the workspace folder "<folder>", so the preview will not create a params file for it; it renders with empty parameters instead.` and the report renders with empty parameters. **No `.ermine` directory appears anywhere** — in particular NOT in the first workspace folder, which is what `ermine.preview.roots` falls back to and what a params file must never do (review G1). Check with `ls -a <that directory>` (nothing) and `git status` in the worktree (nothing new).
- **Failure:** an `.ermine` directory anywhere it should not be.
- **Cleanup:** `rm -rf /tmp/wp7`.
- **Bears on:** WP-8 S2 review G1.

### B19 [2.52b] — A symlink anywhere on the way refuses (OPTIONAL, ADVANCED) — **NEVER RUN**

- **Setup:** no `.ermine` yet. `mkdir -p /tmp/outside && echo PRECIOUS > /tmp/outside/p.json && mkdir -p .ermine/preview/Sales && ln -s /tmp/outside/p.json .ermine/preview/Sales/report.params.json`
- **Do:** pick `Sales.report`. Then repeat for `report.schema.json`, for `.ermine/preview/.gitignore`, and for the directory itself (`rm -rf .ermine/preview && ln -s /tmp/outside .ermine/preview`).
- **Expect, each time:** ONE channel line naming THAT path — `preview: The preview will not write through the symbolic link "<path>": it cannot tell where it points, and a params or schema file written through one would land outside the workspace folder. Nothing was written; the report renders with empty parameters.` — **nothing under `/tmp/outside` is touched** (`cat /tmp/outside/p.json` still says `PRECIOUS`), and the report renders with empty parameters.
- **Failure:** `PRECIOUS` gone. **MEASURED on a real disk without VS Code for all four**, so what this step really observes is that VS Code's `workspace.fs.stat` reports the `SymbolicLink` bit the way the API documents it. If it does not, the refusal you should see instead is `preview: The preview could not tell what "<path>" is (<why>), so it will not write there: it cannot rule out a symbolic link pointing outside the workspace folder. Nothing was written; the report renders with empty parameters.` — which is also a pass.
- **Bears on:** WP-8 S3 review M-3.

### B20 [2.51] — A read-only workspace falls back to `{}` and does not retry (OPTIONAL) — **NEVER RUN**

- **Setup:** `rm` the params file so the first-pick branch runs again, then `chmod -R a-w .ermine`.
- **Do:** pick `Sales.report`. Then save an `.e` file a few times.
- **Expect:** ONE channel line, `preview: the preview could not write under "<dir>" (<the error>), so the report renders with empty parameters.`, **no notification storm**, and the report renders with empty parameters — which for `Sales` is `400 the required key "fromDay" is missing`. **The important half: it is NOT retried.** The line appears ONCE and no further `ermine/schema` request goes out.
- **Cleanup:** `chmod -R u+w .ermine`.
- **Failure:** a line per render, or a schema request per render (each one compiles and evaluates the report).
- **Bears on:** WP-8 S3.

### B21 [new] — A params type that is NOT a JSON object (OPTIONAL) — **NEVER RUN**

- **Setup:** no `.ermine/preview/WpInt/` yet. `tracker/playtest/fixtures/WpInt.e` takes an `Int`.
- **Do:** pick `WpInt`'s `report`.
- **Expect:** a params file holding just `0`, **WITHOUT a `$schema` line** — a JSON number has nowhere to put one — and the channel's write notice ends, verbatim (**the sentence CHANGED in 0.1.10**): `Its parameters are a single whole number, so the file holds just that number. The file therefore carries no "$schema" line and the editor will not validate it; the server still checks it and answers a 400 with a path.` The schema file is still written (**MEASURED: 105 bytes**). **MEASURED, the document this fixture renders with the parameter `0`:** `{"version":1,"settings":{},"root":{"tag":"Widget","name":"int","props":0}}`
- **Failure:** a `$schema` line in the params file (VS Code would squiggle a bare number against an object schema); no notice about validation; or 0.1.9's sentence (`Its parameters are not a JSON object, …`), which means the shape never reached the notice.
- **Bears on:** WP-8 S3 and S4 item 3; it is also the cheapest report in the set to re-render.

### B22 [new] — `Ermine: Write Params Skeleton` asks first, and DECLINING leaves the file — **NEVER RUN**

- **Setup:** B1 and B4 done, so `.ermine/preview/Sales/report.params.json` exists and holds the dates you EDITED (2026-01-05..2026-03-17). Note its exact contents — `cat` it, or keep it open.
- **Do:** run **Ermine: Write Params Skeleton** from the command palette. When the dialog appears, press **Escape**. Run it again and press **Cancel**. Run it a third time and click anything that is not **Replace**, if your dialog offers one.
- **Expect:** a **MODAL** dialog (the window dims; you cannot carry on typing behind it) whose text begins, verbatim: `Replace <…>/.ermine/preview/Sales/report.params.json with a fresh skeleton?` and continues `Everything in that file now -- every value you have edited, and anything you have not committed -- is REPLACED by the defaults derived from the report's parameter type. This cannot be undone from here; git can. The generated schema file beside it is refreshed too.` The buttons are **Replace** and the dialog's own Cancel. After each dismissal: **the params file is byte-for-byte what it was**, `git diff` on it is empty, **no render happens** (no new `preview: render N` line), and the channel says `preview: Write Params Skeleton was declined for <…>/report.params.json; it is untouched`.
- **Failure:** a non-modal toast instead of a dialog; the file changing; a render; or **anything at all in the Ermine channel about `ermine/schema`** — nothing may be asked of the language server before you answer.
- **Bears on:** WP-8 S4, **U3**.

### B23 [new] — …and ACCEPTING replaces it, refreshes the schema and re-renders — **NEVER RUN**

- **Setup:** as B22 — the params file still holds your edited dates. Have the Ermine channel visible.
- **Do:** run **Ermine: Write Params Skeleton** and click **Replace**.
- **Expect, on disk:** `report.params.json` now holds the SAME skeleton B1 wrote — `{"$schema": "./report.schema.json", "fromDay": "<today>", "toDay": "<today>", "orderBy": "ByDay"}`, pretty-printed, `onlyRegion` absent. **Your edited dates are gone**, which is what you confirmed.
- **Expect, in the channel:** `preview: replaced <…>/report.params.json with a fresh skeleton from the report's parameter type, and refreshed <…>/report.schema.json beside it. Edit it, save it, and the preview re-renders.`
- **Expect, in the editor:** the params document is opened (and opened AGAIN on a second run of the command, unlike the first pick's once-per-session open), and the render tab is revealed.
- **Expect, renders:** **ONE**, or two identical ones — the file watcher sees our write too, and `scheduleRender` merges the two inside its 150 ms window; outside it you get a second identical render, which is harmless (same session, no boot). **ZERO renders is the defect.** The tab shows the empty `byDay` table again (heading `matched: 0`), because the dates are today's again.
- **Failure:** the file unchanged; the schema file not rewritten when the type had moved; no render; or a **Render anyway / Not now** question — an explicit command is consent and must never be held.
- **Also (added by the S4 fix round, 2026-09-23):** run the command again, and while the modal is on screen switch to the params document, change a date and **save** (Ctrl+S; the modal may need to be moved or the save done from a second window), then click **Replace**. **Expect:** nothing is written, no render, and a warning plus the channel line `preview: the params file "<…>/report.params.json" changed after you were asked (while the question was on screen or while the schema was being worked out), so nothing was written; run the command again`. **Your saved edit is still in the file.** If VS Code will not let you save behind a modal, record SKIP — the case is covered by the unit model and by the fake-vscode probe over a real disk (`scratch-widget-preview/wp8s4-fix/probe/overwrite.log`, cases 4 and 4b).
- **Bears on:** WP-8 S4, **U3**; Q21.

### B24 [new] — The command with NO params file behaves like a first pick — **NEVER RUN**

- **Setup:** `rm .ermine/preview/Sales/report.params.json` (leave the schema file and the `.gitignore`).
- **Do:** run **Ermine: Write Params Skeleton**.
- **Expect:** **NO dialog at all** — there is nothing to lose, so nothing is confirmed — the file is created, the channel line begins `preview: wrote <…>/report.params.json from the report's parameter type` (`wrote`, not `replaced`), and the report renders.
- **Failure:** a dialog; or the file created through an overwrite rather than a create (you cannot see that from here — it is unit-tested; what you CAN see is that a file which appears under you, e.g. from a `git checkout` while the schema is being worked out, is left alone and the channel says `a params file appeared at …`).
- **Bears on:** WP-8 S4, U3.

### B25 [new] — The ORPHAN notice after a binding is renamed — **NEVER RUN**

- **Setup:** B1 done, so `.ermine/preview/Sales/report.params.json` exists. Reload the window first (the notice is once per left-over file per SESSION, so a session that has already said it will not say it again).
- **Do:** in `core/src/test/resources/doc/Sales.e`, rename the binding `report` to `report2` — **both the signature and the equation** — and save. Then run **Ermine: Preview Report…** → `Sales.e` → `report2`.
- **Expect:** a warning notification, and the same text in the channel, verbatim in shape: `Ermine: <…>/.ermine/preview/Sales/report.params.json is left over: Sales no longer offers a report called "report" (it was renamed or removed, or the module has made it private), so nothing reads that file. It is committed source, so the preview will not delete it -- delete it yourself once you are sure. "Write Params Skeleton" writes a fresh skeleton for Sales.report2, the report picked now.` The notification carries ONE button, **Write Params Skeleton**. **The old file is still on disk** — check it.
- **Expect, again:** pick `report2` a second time. **No second notification** (once per module+binding per session).
- **Failure:** the old file deleted or changed — **that is a serious failure, report it with the channel text**; no notice at all; or a notice on every pick.
- **Cleanup:** put `Sales.e` back (`git checkout core/src/test/resources/doc/Sales.e`) and delete the left-over file.
- **Bears on:** WP-8 S4, **D6**.

### B26 [new] — The orphan notice's button runs the command for the CURRENT pick — **NEVER RUN**

- **Setup:** as B25, with the notification on screen and `report2` picked. `report2` now has its own params file (the pick wrote one) — note its contents.
- **Do:** click **Write Params Skeleton** on the notification.
- **Expect:** the B22 modal, naming **`report2.params.json`** — the report picked NOW, not the stale `report.params.json` the notice is about. Answer **Replace** and B23's outcome follows for `report2`. **The stale `report.params.json` is never touched, whatever you answer.**
- **Failure:** the modal naming the stale file; the stale file changing; or the button doing nothing.
- **Bears on:** WP-8 S4, D6, U3.

### B27 [new] — Every non-object params root says what its value MEANS (OPTIONAL) — **NEVER RUN**

- **Setup:** copy the four fixtures beside `WpInt.e` into the worktree root (they are `tracker/playtest/fixtures/WpEnum.e`, `WpMaybe.e`, `WpJson.e`, `WpUnit.e`), and make sure there is no `.ermine/preview/<Module>/` for any of them.
- **Do:** pick each one's `report` in turn. B21 already covers `WpInt`.
- **Expect** — each writes a params file with **no `$schema` line**, each renders `ok=true`, and each channel notice carries its own sentence, verbatim (**all four MEASURED against a real server, 2026-09-23**):

| module | the file holds | the notice says | the document |
|---|---|---|---|
| `WpEnum` | `"Spring"` | `Its parameters are one of "Spring", "Summer", "Autumn", so the file holds just that value.` | `{"version":1,"settings":{},"root":{"tag":"Widget","name":"season","props":"Spring"}}` |
| `WpMaybe` | `null` | ``Its parameters are optional (a single string), so the file holds just that value, and `null` means there is none.`` | `{"version":1,"settings":{},"root":{"tag":"Widget","name":"maybe","props":null}}` |
| `WpJson` | `null` | ``Its parameters are any JSON value at all (the report takes a `Json`), so the file holds just that value; `null` is the smallest one that decodes.`` | `{"version":1,"settings":{},"root":{"tag":"Widget","name":"json","props":null}}` |
| `WpUnit` | `[]` | ``Its parameters are the empty tuple `()`, so the file holds just the empty array `[]` and there is nothing in it to edit.`` | `{"version":1,"settings":{},"root":{"tag":"Widget","name":"unit","props":[]}}` |

- **Failure:** a `$schema` line in any of the four files; a render that is not `ok=true`; the generic sentence (`Its parameters are not a JSON object…`) for any of them, which means the shape was not recognised; or `WpMaybe`'s file holding `""` rather than `null` (that would be "match the empty string", not "no filter").
- **Cleanup:** delete the four copied `.e` files and their `.ermine/preview/` directories.
- **Bears on:** WP-8 S4 item 3; G5.

---

## Group C — the wedge guard and the restart

**What this group is for.** Before WP-22, a report that wedged the server was
re-rendered *by the restart that the wedge caused* — and the **Restart Language
Server** button in our own stuck notification took the same path, so the one
remedy offered during a wedge was itself a loop trigger (Q17, read from the
code and unobserved). The extension now keeps ONE mark for the current pick and
asks before re-rendering it. **The decision is unit-tested; the ARRIVAL of
every editor event below is unobserved, and these steps are the only thing that
can observe it.** WP-22(c) then added an automatic restart, **OFF by default**
(open decision 2 above).

**Standing setup for C1–C20:** `"ermine.preview.timeoutSeconds": 5` and
`"ermine.preview.restartAfterStuckSeconds"` unset (or `0`), both in
`.vscode/settings.json` — `tracker/playtest/settings.example.json` has them
written out. **DO NOT add a folder to the workspace for any of this**: the
fixtures are inside the worktree and the picker already sees them, and a second
folder would make the window multi-root, at which point VS Code stops reading
those two settings (and `ermine.maxHeap`) from `.vscode/settings.json` at all.

`tracker/playtest/fixtures/WpSpin.e` is the wedge: it loads and it diverges.
**It offers TWO report-typed bindings, `spin : Int -> Node` and
`report : Int -> Node` — pick `report`** (MEASURED; the other three fixtures
offer one each). **MEASURED at `timeoutSeconds: 5`: the watchdog fires 7.18 s
after the request** for `WpSpin` and 6.70 s for `WpChain` (the alternative
wedge, usable in place of `WpSpin` in any step here) — the extra ~2 s is the
render-session boot, which the watchdog's clock does not cover, so **do not
call a fire at 7 s a failure of a 5 s timeout.** A wedged server **exits by
itself about two minutes after the fire**, when the loop reaches `-Xmx`, so if
a step tells you to wait, that is how long.

**Watch the process list throughout.** `pgrep -af lsp.Main` should show exactly
**ONE** server after every restart in this group. Two would mean the old JVM
outlived the stop, and a non-allocating wedge would then never go away. C30 is
the step that records it.

### C1 [2.7, 2.8, 2.9] — Wedge it: the banner, the orange bar, the watchdog's answer — **NEVER RUN**

- **Setup:** as above. `timeoutSeconds` = 5.
- **Do:** **Ermine: Preview Report...** → `tracker/playtest/fixtures/WpSpin.e` → **`report`, the SECOND of the two report-typed entries** (`spin : Int -> Node` is listed too). Wait ~7 s (MEASURED: 7.18 s from the request).
- **Expect, the notification** (an ERROR, with a **Restart Language Server** button), verbatim — the server's own words, `lsp/Preview.scala:2177-2179`: `Ermine: evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that evaluation ever finishes; if it does not, restart the language server -- run "Ermine: Restart Language Server" (ermine.restartServer)`
- **Expect, the status bar:** orange, reading `$(warning) Ermine preview: stuck`, tooltip = that same message.
- **Expect, the tab:** the watchdog's own answer. **MEASURED over the wire, both edges:** `{"ok":false,"status":500,"message":"evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that evaluation ever finishes; if it does not, restart the language server -- run \"Ermine: Restart Language Server\" (ermine.restartServer)","generation":1,"stuck":true}`, and the notification on the wire is `ermine/preview/stuck {"stuck":true,"message":<the same text>,"seq":1}`. **The ANSWER arrived first in every measured run, and the setup agent measured it again: the `ermine/preview/stuck` notification with `seq: 1` arrives AFTER the answer** — which is why the extension does not derive the state from the order. The channel logs `preview: STUCK — <that message>`.
- **Failure:** no notification; a status bar that stays `$(json)`; or a modal.
- **Bears on:** WP-7's stuck/recover behaviour; Q8.

### C2 [2.10] — A second render is refused immediately, not queued — **NEVER RUN**

- **Do:** with the preview stuck, run **Ermine: Render Report to JSON**.
- **Expect:** refused at once, with `"stuck": true` and its own generation echoed. **MEASURED twice, most recently by the setup agent: the refusal comes back in 0.00 s** — `"generation":2, "stuck":true` with the same text.
- **Failure:** it hangs (queued behind the wedge).
- **Bears on:** Q8.

### C3 [2.13, 2.14] — The server dies and comes back, on an UNWEDGED pick — **NEVER RUN**

- **Setup:** restart the server (button), set `timeoutSeconds` back to `60`, pick `Sales.report` and let it render. **Nothing is held.**
- **Do:** find the `java … lsp.Main` child of the extension host — `pgrep -af lsp.Main` — and kill that pid. (`pkill` by name is not the way; you may hit another session's server.)
- **Expect:** the status bar reads `$(debug-disconnect) Ermine: preview offline`, tooltip `the language server stopped; the last document is kept`, and the tab KEEPS its last document. The channel logs `preview: the language server stopped — preview offline`. Then `vscode-languageclient` restarts it on its own policy (up to 5 times in 3 minutes), the channel logs `preview: the language server is running again`, and **the last pick is re-rendered without you touching anything** — `preview: render Sales.report (generation N; the language server restarted; …)`.
- **Failure:** no re-render on an UNWEDGED pick (that would be the guard over-reaching), or a lost document.
- **Bears on:** WP-7's offline/online behaviour.

### C4 [2.22] — The automatic path: a wedged server that dies by itself does NOT re-render — **NEVER RUN**

- **Setup:** `timeoutSeconds` back to `5`; wedge `WpSpin.report` again (C1). Then **WAIT** instead of restarting — about two minutes at the default heap.
- **Expect:** the server exits at `-Xmx`, `vscode-languageclient` restarts it, and the tab does **NOT** re-render: the `$(warning) Ermine preview: held` status bar and ONE question (C6). The channel logs `preview: remembering that WpSpin.report wedged the preview (watchdog)`, then `preview: not re-rendering — nothing about WpSpin.report has changed since it wedged the preview`, then `preview: HELD — …`, and **no `preview: render …` line**.
- **Failure:** a re-render. **This is the loop Q17 named, and this step is the only thing that can show it was closed.**
- **Bears on:** **Q17**, WP-22.

### C5 [2.15] — The Restart button takes the same path and still does not re-render — **NEVER RUN**

- **Setup:** wedge it again; the C1 ERROR notification on screen.
- **Do:** press its **Restart Language Server** button.
- **Expect:** the client stops and starts (status bar through `$(debug-disconnect) Ermine: preview offline` and back) — **and then NOTHING RENDERS.** The status bar reads `$(warning) Ermine preview: held` (orange); its tooltip is `WpSpin.report wedged the preview: the watchdog fired and the server did not come back.` then `Nothing has changed since, so the restart did not re-render it.` then `Render it anyway with "Ermine: Render Report to JSON", or save the file you fixed.` The channel: `preview: not re-rendering — nothing about WpSpin.report has changed since it wedged the preview`, then `preview: HELD — …`, and **no `preview: render …` line**.
- **Failure:** a render. That is Q17's loop, open.
- **Bears on:** **Q17**, WP-22.

### C6 [2.16] — The question, and exactly what it says — **NEVER RUN**

- **Expect:** ONE non-modal **WARNING** (not an error, not a modal), verbatim (`preview-core.js:1041-1059`): `Ermine: WpSpin.report wedged the preview: the watchdog fired and the server did not come back. Nothing has changed since, so it was NOT re-rendered automatically.` with two buttons, **Render anyway** and **Not now**.
- **Note:** if the extension itself restarted the server (C22 onwards), the middle clause becomes `wedged the preview, and the language server was restarted to clear it` — deliberately, because "the server did not come back" would be false when we brought it back (review N2). The `died-mid-render` wording is `was still rendering when the language server stopped` (C19).
- **Failure:** an error notification, a modal, two questions, or no buttons.
- **Bears on:** WP-22.

### C7 [2.17] — Dismissal is never consent — **NEVER RUN**

- **Do:** press **Not now**. Then wedge/restart again and instead dismiss with Escape, or ignore it until it times out.
- **Expect:** the channel logs `preview: still held (Not now)` for the button and `preview: still held (the question was dismissed)` for the dismissal. The status bar STAYS `held`; the mark is NOT cleared.
- **Failure:** a render after a dismissal.
- **Bears on:** WP-22.

### C8 [2.19] — Render anyway renders, and wedges again — **NEVER RUN**

- **Do:** press **Render anyway**.
- **Expect:** the channel logs `preview: the wedge mark is cleared (the user asked for this render)` and then `preview: render WpSpin.report (generation N; Render anyway; …)`, the tab is revealed, and after ~5 s **it wedges again** — the report has not been fixed. **That is the point: the guard asks, it does not decide.**
- **Failure:** nothing renders.
- **Bears on:** WP-22.

### C9 [2.18] — Once per restart, and never stacked — **NEVER RUN**

- **Do:** from the wedged-and-held state, restart a second time from the palette (**Ermine: Restart Language Server**) — **NOT** by clicking the preview status bar item, which runs the picker and would clear the mark.
- **Expect:** you are asked again — once per restart — and still nothing renders by itself. **If the first question is still on screen**, the channel logs `preview: the question is already on screen; not asking again` instead of stacking a second one.
- **Failure:** two notifications on screen at once, or no question on the second restart.
- **Bears on:** WP-22.

### C10 [2.20] — Any `.e` save clears the hold — **NEVER RUN**

- **Do:** with the status bar reading `held`, add a comment line to the `WpSpin` fixture and save. Then save a `.md` or a `.json` and watch that nothing happens.
- **Expect:** the channel logs `preview: the wedge mark is cleared (an Ermine source file was saved)` and the status bar leaves `held`. **Any `.e` save clears it, deliberately:** while the server is dead nothing sends `didChangeWatchedFiles`, so no `invalidated` can cover the window in which you fix the loop. **A save of a `.md` or a `.json` clears nothing.**
- **Failure:** the mark surviving an `.e` save, or a `.md` save clearing it.
- **Bears on:** WP-22.

### C11 [2.21] — With the mark cleared, a restart DOES re-render — **NEVER RUN**

- **Do:** with the mark cleared (C10), restart the server again.
- **Expect:** the last render IS re-sent, exactly as C3 describes: `preview: render WpSpin.report (generation N; the language server restarted; …)`.
- **Failure:** still held — then the clear did not stick.
- **Bears on:** WP-22.

### C12 [2.41] — Changing what is actually SENT clears the hold — **NEVER RUN**

- **Setup:** `WpSpin.report` needs a params file. **`tracker/playtest/params/WpSpin.report.params.json` is that file** — copy it to `.ermine/preview/WpSpin/report.params.json` (`tracker/playtest/params/README.md` says so); it holds `5`, and the report takes an `Int`. Pick `WpSpin.report` and let it wedge until the status bar reads `held`.
- **Do:** edit the params file to `7` and save.
- **Expect:** the channel logs `preview: the wedge mark is cleared (the parameters changed)`, the status bar leaves `held`, and the render goes. **Changing what is SENT is evidence of change, exactly like an `.e` save.**
- **Failure:** the hold surviving a real parameter change.
- **Bears on:** WP-8 S2, WP-22.

### C13 [2.41b] — A re-format while held ASKS instead of rendering — **NEVER RUN**

- **Do:** wedge it again, and while the status bar reads `held` save the params file with the SAME value but different bytes: `7` → `  7  ` (or add a `$schema` line, or run format-on-save).
- **Expect:** **NOTHING RENDERS.** The channel logs `preview: render N is HELD (params-file: nothing about WpSpin.report has changed since it wedged the preview)` and the **Render anyway / Not now** question of C6 appears — the same question, the same `held` status bar. Press **Render anyway** and it renders (and wedges again).
- **Failure:** **if the report re-renders with no question, that is the loop this ticket exists to close** — the first cut of S2 did exactly that, and recorded it as expected behaviour.
- **Bears on:** WP-8 S2 review M6 (the user's own sentence), WP-22.

### C14 [2.41c] — The question is asked ONCE, not once per save — **NEVER RUN**

- **Do:** press **Not now** on C13's question, then save the same unchanged params file twice more — or turn format-on-save on and type in it.
- **Expect:** **NO second and third notification.** Each further save logs `preview: not asking again — this question was already answered "Not now" for these parameters; the preview stays held until they change or you render it yourself`, and the status bar keeps reading `$(warning) Ermine preview: held`. **Then, each of these makes it ask or render again:** change a value and save → it renders immediately (the mark clears); restart the language server → you are asked AGAIN, because a restart is a new event and is never remembered; run **Ermine: Render Report to JSON** → it renders, and the next unchanged save asks once more. **AND A WINDOW RELOAD ASKS AGAIN:** the refusal is in-process only and is deliberately NOT mirrored into `workspaceState` the way the mark is, so **Developer: Reload Window** while held leaves the report held (C17) and the next unchanged save asks once more.
- **Failure:** **a notification per keystroke-and-save.**
- **Bears on:** WP-8 S2 delta re-review D3.

### C15 [2.41d] — A roots change that changes nothing also asks — **NEVER RUN**

- **Do:** while `held`, edit `ermine.preview.roots` to a value that RESOLVES to the same list (add a trailing slash — anything that makes VS Code fire the change without moving the resolved absolute paths). Then edit it to a value that really moves the list.
- **Expect:** the first: **NOTHING RENDERS**, and the question appears as in C13, with `(roots: …)` in the channel's `preview: render N is HELD (…)` line. The second: the mark is cleared and it renders without asking.
- **Note:** this family was MEASURED as 1,218 of 5,097 violating sequences in an exhaustive exploration of the reducers over a 13-event alphabet (579,194 sequences); the reviewer's wider 15-event alphabet counts 1,851 for the same family. **Nobody has seen either half in an editor.**
- **Failure:** a silent re-render on the no-op roots edit.
- **Bears on:** WP-8 S2 delta re-review D1.

### C16 [2.52] — A report that wedged is never handed a SCHEMA request — **NEVER RUN**

- **Setup:** `rm -rf .ermine/preview/WpSpin` so `WpSpin.report` has NO params file. Wedge it until the status bar reads `held`.
- **Do:** trigger a render whose trigger carries no evidence of change — edit `ermine.preview.roots` to a value that resolves to the SAME list, exactly as C15 does.
- **Expect:** **NO `ermine/schema` request goes out** and **no file is written**: the channel shows the render `HELD` and the **Render anyway / Not now** question, and **no `.ermine/preview/WpSpin/` directory appears**. **Working out the schema COMPILES AND EVALUATES the report on the preview queue** (`json/Runner.scala:849-852`; `lsp/Preview.scala:596-598` says so in the server's own words), so handing one to a server this report has just wedged is the same mistake as re-rendering it. Press **Render anyway**: the files are written and the report renders (and wedges again).
- **Failure:** an `.ermine` directory appearing while held.
- **Bears on:** WP-8 S3.

### C17 [2.23] — The mark survives a window reload, and says it was restored — **NEVER RUN**

- **Do:** while `held`, run **Developer: Reload Window**.
- **Expect:** after activation the channel logs `preview: remembered WpSpin.report` AND `preview: a wedge mark was restored from the last session (watchdog)` — **a RESTORE line, deliberately not the line a fresh wedge prints** — and the status bar reads `held` again: the mark is mirrored in `workspaceState` beside the pick. **Nothing renders** (activation never renders), so you are not asked until the next restart.
- **Failure:** the fresh-wedge line (`preview: remembering that …`) instead of the restore line, or a render on activation.
- **Bears on:** WP-22 review N4.

### C18 [2.24] — The mark is the CURRENT pick's only — **NEVER RUN**

- **Do:** while `held`, run **Ermine: Preview Report...** and pick `Sales.report`.
- **Expect:** the channel logs `preview: the wedge mark is cleared (the pick changed)`; `Sales.report` renders immediately (**picking IS consent**) and a later restart re-renders it without a question.
- **Failure:** `Sales.report` being held because `WpSpin.report` wedged.
- **Bears on:** WP-22.

### C19 [2.26] — The `died-mid-render` case, and the ONLY step that can observe M1 — **NEVER RUN**

- **Setup:** every step above runs at `timeoutSeconds: 5`, so the watchdog always wins and the mark is always set by the stuck edge. To get the OTHER reason, starve the heap: set `"ermine.maxHeap": "256m"` (the server restarts — this is one of the three WINDOW-scoped settings, so the window must still be single-root), set `"ermine.preview.timeoutSeconds": 600` so the watchdog CANNOT fire first, and render `tracker/playtest/fixtures/WpBlow.e`. **MEASURED twice: the JVM dies 6.85 s after the render with exit code 3 and `Terminating due to java.lang.OutOfMemoryError: Java heap space` on stderr, and no watchdog fire** (the setup agent measured it with `ERMINE_LSP_XMX=256m` outside the editor; `ermine.maxHeap` is how the extension spells the same thing).
- **Expect:** the JVM dies mid-render: **no** stuck notification and **no** `$(warning) Ermine preview: stuck`, but the channel logs `preview: render N was lost with the connection (<the error>)` and/or the `Stopped` edge, then `preview: remembering that WpBlow.report wedged the preview (died-mid-render)`. After the restart the tab does **NOT** re-render, the status bar reads `held`, and the question names *…was still rendering when the language server stopped*.
- **Failure:** **two marks, or none.** This is the case the guard would lose if the mark depended on which of the two the library delivers first (WP-22 review M1): the extension marks from BOTH, and `guardReduce`'s SET is idempotent, so you should see **exactly one mark however the race falls**.
- **Cleanup:** put `ermine.maxHeap` back to `""`.
- **Bears on:** WP-22 review **M1**.

### C20 [2.27] — The `{stuck:false}` recovery clear, which is the load-bearing one — **NEVER RUN**

- **Setup:** `"ermine.preview.timeoutSeconds": 5`, and a report that is SLOW rather than infinite — one that takes ~30 s and FINISHES (a large fold, not a loop). `tracker/PLAYTEST-SETUP.md` says which fixture that is, or how to make one.
- **Expect:** the watchdog fires at 5 s and the preview is marked stuck; then the job FINISHES and the channel logs `preview: no longer stuck`, a transient **status bar message** (not a notification) `Ermine: the preview recovered`, `preview: the wedge mark is cleared (the preview recovered: the wedged job returned)`, and an automatic re-render with reason `the preview recovered`. The status bar must leave **both** `stuck` and `held`. A restart after it re-renders without a question.
- **Failure:** **without this clear a slow report would be held for ever** — a 300 s scan under a 60 s watchdog is the real case (Q10).
- **Note:** the old §2.27 called `Ermine: the preview recovered` a toast. It is `setStatusBarMessage(…, 4000)` (`extension.js:1604`) — a status bar message that disappears after four seconds, not a notification. Watch for it.
- **Bears on:** **Q10**, WP-22.

### C21 [2.28] — THE DEFAULT CHANGES NOTHING — **NEVER RUN**

- **Setup:** leave `ermine.preview.restartAfterStuckSeconds` unset (or `0`); `"ermine.preview.timeoutSeconds": 5`.
- **Do:** wedge `WpSpin.report` as in C1.
- **Expect:** exactly C1–C2's behaviour and **not one line more**. The stuck notification's text is the SAME sentence as C1 with **nothing** appended about a restart; the status bar tooltip likewise; and the channel logs no `preview: the language server will be restarted in …` line. The server still dies by itself at `-Xmx` about two minutes later.
- **Failure:** **if anything restarts here, the default is not what this document says it is.**
- **Bears on:** **WP-22(c), and open decision 2 — the default is the orchestrator's and you have not been asked.**

### C22 [2.29] — The feature: the automatic restart — **NEVER RUN**

- **Setup:** `"ermine.preview.restartAfterStuckSeconds": 20` with `"ermine.preview.timeoutSeconds": 5`.
- **Do:** wedge `WpSpin.report` again.
- **Expect at ~5 s**, the stuck notification **IN FULL AND WITH NO WORDS ELIDED** — quote it here so this step catches a run-on (review N1: the server's own message ends `(ermine.restartServer)` with no full stop, and ours is joined onto it): `Ermine: evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that evaluation ever finishes; if it does not, restart the language server -- run "Ermine: Restart Language Server" (ermine.restartServer). You do not need to do that by hand: the language server will be restarted automatically in 20 s unless the render comes back. Set ermine.preview.restartAfterStuckSeconds to 0 to stop that.` — **one full stop before "You do not need"**, and the last two sentences also on the status bar tooltip's own line. The channel logs `preview: the language server will be restarted in 20s unless the preview recovers (<why>)`.
- **Expect at ~25 s:** `preview: RESTARTING the language server — the preview has been stuck for 20 s (ermine.preview.restartAfterStuckSeconds = 20; WpSpin.report is held)`, the status bar through `$(debug-disconnect) Ermine: preview offline` and back to `$(warning) Ermine preview: held` — **the tab does NOT re-render** and C6's question appears instead, exactly as after a hand-pressed restart (its middle clause now reads `wedged the preview, and the language server was restarted to clear it`). **The whole incident is ~25 s instead of ~2 minutes at `-Xmx`.**
- **Failure:** a run-on sentence; a re-render; no restart; two servers (C30).
- **Bears on:** **WP-22(c)**, review N1, N2.

### C23 [2.30] — A slow render is NOT killed — **NEVER RUN**

- **Setup:** grace still `20`, `timeoutSeconds` still `5`. Use C20's slow-but-finishing report (~10 s).
- **Expect:** the watchdog marks it stuck at 5 s and the notification says a restart is coming; then the job returns and the channel logs `preview: no longer stuck`, `preview: the automatic restart is disarmed (the wedged render came back (ermine/preview/stuck {stuck:false}))`, and an automatic re-render with reason `the preview recovered`. **NO restart happens.**
- **Failure:** a restart. **This is why there is a grace at all** — without the disarm a 300 s scan under a 60 s watchdog would be killed for being slow (Q10).
- **Bears on:** **WP-22(c)**, **Q10**.

### C24 [2.31] — Turning it off mid-grace disarms — **NEVER RUN**

- **Do:** wedge `WpSpin.report` with the grace at 20, and within those 20 seconds set `ermine.preview.restartAfterStuckSeconds` back to `0`.
- **Expect:** `preview: the automatic restart is disarmed (ermine.preview.restartAfterStuckSeconds was set to 0)` and **nothing restarts** — the status bar stays `stuck` and the server dies by itself at `-Xmx` as before. Editing the setting to a different NON-ZERO value instead re-arms it at the new value, counted from that moment: `preview: the language server will be restarted in Ns unless the preview recovers (ermine.preview.restartAfterStuckSeconds changed to N s)`.
- **Failure:** a restart after the setting was turned off.
- **Bears on:** **WP-22(c)**.

### C25 [2.31b] — Turning it ON while already wedged ARMS — **NEVER RUN**

- **Do:** with the setting at its default `0`, wedge `WpSpin.report` and leave it wedged; then set `ermine.preview.restartAfterStuckSeconds` to `20`.
- **Expect:** `preview: the language server will be restarted in 20s unless the preview recovers (ermine.preview.restartAfterStuckSeconds was turned on while the preview was stuck)` and the restart happens ~20 s later, exactly as in C22.
- **Failure:** nothing happening at all. **This is the likeliest moment anyone touches this setting** — they reach for it *because* the preview is wedged — and the first build did nothing here, because it waited for a rising edge that was already in the past.
- **Bears on:** **WP-22(c)** review D1.

### C26 [2.31c] — The floor DEFERS, it does not cancel, and says so — **NEVER RUN**

- **Do:** `"ermine.preview.timeoutSeconds": 5` and the grace at `5`. Wedge it, let the restart happen, press **Render anyway**, and let it wedge a second time.
- **Expect:** the second notification does **NOT** say 5 s. It says, with the number being 30 minus however long the second wedge took to arrive: `…restarted automatically in 27 s unless the render comes back. It is not before 27 s, because the language server was restarted less than 30 s ago and restarts are limited to one every 30 s (you asked for 5 s). Set ermine.preview.restartAfterStuckSeconds to 0 to stop that.` The channel's arm line carries the same reason, and the restart then happens at that number.
- **Failure:** **if you see `5 s` here, a known regression is back.** The delta review found that the stretch, though written, never ran in the shipped extension, because the three events that arm were sent without a clock — the outcome was right and only the sentence was wrong, which is exactly the kind of defect this step exists to catch. **And nothing must be stranded:** the first build refused the second restart and disarmed, leaving the preview stuck for the rest of the session with a notification promising a restart in 5 s.
- **Bears on:** **WP-22(c)** review D2 and the delta review's M1.

### C27 [2.32] — No double restart, and the USER's restart is never the one refused — **NEVER RUN**

- **Do:** wedge it with the grace at 20 and press **Restart Language Server** after ~10 s, before the grace expires. Then, separately, try the OPPOSITE ORDER: press the button WHILE an automatic restart is under way.
- **Expect, first order:** ONE restart. The edge out of `Running` disarms the grace, so the channel logs `preview: the automatic restart is disarmed (…)` — **either `(the language server stopped)` or `(the language client left Running)`, and both are correct** (review N5: which one you get depends on whether the library reports `Starting` first, which nobody here has observed) — and there is no later `preview: RESTARTING the language server` line. If the two ever do collide, the AUTOMATIC one is refused: `restart: refused (a restart is already under way)`, and you should see exactly one `restart: restarting…` line and one new server process, never two.
- **Expect, opposite order — THE ONE THAT MATTERS (review F1):** the button must still work. The channel logs `restart: the user asked while an automatic restart was under way, so it takes over` and then, from the older one, `restart: superseded by a newer one — not starting a second client`.
- **Failure:** **the user's restart being refused.** That is a regression of the command the whole feature leans on.
- **Bears on:** **WP-22(c)** review F1, N5.

### C28 [2.32a] — The state log, and the one UNVERIFIED thing you can settle in a second — **NEVER RUN**

- **Do:** watch the Ermine output channel through any restart, and through the FIRST client of a session.
- **Expect:** every transition the language client reports is logged as `client N: state <from> -> <to>`, with ` (DROPPED: a newer client is current)` on the ones the epoch guard ignores.
- **What to record:** **whether a fresh `LanguageClient` emits an initial `Stopped -> Starting` at all is UNVERIFIED** — the library's source is unread (project rule) and nobody has run this extension. **Note exactly what the FIRST client of a session logs before it reaches `Running`, and write it into the notes column.** That one line settles it.
- **Bears on:** WP-22(c) review N5; C27's two acceptable disarm reasons.

### C29 [2.32b] — The stop that does not come back, and the two glue paths no test can reach — **NEVER RUN**

- **Do:** there is no way to make this happen on purpose from the UI. Watch for it whenever a restart takes more than five seconds.
- **Expect:** `stop: the language server did not stop within 5s — carrying on anyway. THE OLD SERVER PROCESS MAY STILL BE ALIVE: check with \`ps -ef | grep lsp.Main\`, and kill the older pid by hand if there are two.` and a NEW server starts regardless. **Run that check.** On this path the old client's real `Stopped` arrives after a newer client is current and is dropped as stale — you will see `client N: state Running -> Stopped (DROPPED: a newer client is current)` — so `restart` reports the edge itself, logged as `preview: the language server stopped (the stop returned "timed-out")`. **AND THE REST OF THE RESTART MUST STILL HAPPEN:** what follows must look exactly like C22 — `$(debug-disconnect) Ermine: preview offline`, then the `held` status bar and ONE question.
- **Failure:** the tab re-rendering by itself, or nothing being asked at all.
- **Also observable only here (review N4), two pieces of glue with no test:** that a render coalesced in the 150 ms before an automatic restart is DROPPED rather than sent to the fresh server (you would see a `preview: render …` line just after `preview: RESTARTING …` — **there should be none**), and the restart guard above. The review's own mutation run removed each of them from the source and the whole unit suite stayed green.
- **Bears on:** WP-22(c) review F1, N4.

### C30 [new] — Exactly ONE `lsp.Main` after every restart — **NEVER RUN**

- **Do:** run `pgrep -af lsp.Main` after each restart in C5, C22, C27 and C31.
- **Expect:** exactly ONE server process belonging to this Extension Development Host each time.
- **Failure:** two. **That would mean the old JVM outlived the stop** — and a non-allocating wedge would then never go away. **This is the thing these steps CANNOT otherwise tell you:** whether `client.stop()` really kills a wedged server process, or only stops talking to it. The server should answer `shutdown`/`exit` promptly even while the preview is wedged (READ: `Preview.shutdown()` drains and returns without joining the preview thread; the preview thread is a daemon; MEASURED: the dispatch thread answered a hover in 0.00 s while wedged) — but the library's own behaviour is *external* and UNVERIFIED here.
- **Bears on:** WP-22(c); the *external* gap.

### C31 [2.32c] — Restart during the first-run classpath warm-up — **NEVER RUN**

- **Setup:** no `target/ermine-classpath` (delete it, or use a fresh checkout). **This costs an sbt run and several minutes — skip it if you would rather not.**
- **Do:** open a `.e` file so the extension activates, and while the **`Ermine: building the classpath cache (first run, sbt)`** progress notification is on screen run **Ermine: Restart Language Server** — twice, if you are quick.
- **Expect:** **EXACTLY ONE `lsp.Main` PROCESS AFTERWARDS** (`pgrep -af lsp.Main`), and the channel logs `start: superseded during the classpath warm-up — not starting this client` for each superseded attempt.
- **Failure:** two clients, two JVMs — one referenced by nothing and never stopped, with its handlers still wired to the extension's state. Before this fix a restart arriving inside the warm-up found the client already cleared, skipped the stop, and raced into its own start. **Nothing in the unit suite can see this;** an async model of the same control flow can (`restartModel` in `test/preview-core.test.js`), but only this step sees the real thing.
- **Bears on:** WP-22(c) delta review M2.

### C32 [2.12, 2.25] — Put the settings back — **NEVER RUN**

- **Do:** `"ermine.preview.timeoutSeconds": 60`, `"ermine.preview.restartAfterStuckSeconds": 0`, `"ermine.maxHeap": ""`, `"ermine.preview.roots": []`. Re-pick `Sales.report`.
- **Expect:** a normal render.
- **Bears on:** leaving the workspace as you found it.

### The holes to know while ticking Group C

Each of these is a design decision rather than a bug, and none of them is a
step:

- **A second VS Code window on the same folder keeps its own mark** (per extension host; cross-window `Memento` visibility is *external* and unverified).
- **`bin/ermine-serve` and every non-VS-Code client are unprotected** — nothing about the wedge guard or the automatic restart is a server change (**Q18**).
- **"It didn't change" is a PROXY.** The two signals used are the server's own `invalidated` and any `.e` save, and both err towards asking *less*.
- **If the automatic restart ever does NOT happen** — nothing is picked, or a restart is already under way — you get a warning notification, `Ermine: the preview is stuck and the automatic restart did not happen — <why>. Run "Ermine: Restart Language Server" when you are ready.`, and the stuck tooltip says `The automatic restart did not happen: <why>.` **It is not only an output-channel line** (review D3).
- **The setting is spelled `restartAfterStuckSeconds`**, not `killAfterStuckSeconds` as the design review called it.

---

## Group E — the panel

**What this group is for.** Since 0.1.12 the default `ermine.preview.target`
is `panel`: the two preview commands draw the report in a webview beside the
editor instead of the JSON tab, and since 0.1.14 that page also loads the
legacy writers for `table`, the charts and `styleBox`. **Everything in this
group is READ from the code and tested in node and JSDOM only. No browser and
no VS Code webview has shown any of it to anyone.** E3, E5, E8, E9, E10 and
E11 are the only way anyone will learn the answers they record.

**Standing setup for E1–E15** (it differs from Groups A–D):

- **`"ermine.preview.target": "panel"`** in `.vscode/settings.json` — change
  the `json` line the setup file wrote for Groups A–D, or delete it (`panel`
  is the default). E13 is the one step that sets it to something else.
- **The client bundle is built**: `client/dist/browser/ermine-client.js` and
  `ermine-host.js` exist (`tracker/PLAYTEST-SETUP.md` §1; MEASURED present in
  this worktree on 2026-09-23). Without them every step here shows the
  not-built page instead, which is E8's subject and nothing else's.
- **The writers are at the default**: `ermine.preview.writersPath` unset or
  `""`, which from this worktree resolves to
  `/home/dmitry/research/ermine/ermine-writers/writers/html/src/main/resources/web`
  (MEASURED by the WP-11 review). E14 is the one step that changes it.
- `ermine.preview.timeoutSeconds` at `60`, except in E5–E6, which set `5`.
- **The report for E1–E3 and E9 is `core/src/test/resources/doc/Sales.e`**,
  binding `report` (`report : Query -> Node`), typed since `f75b77f8`: a
  heading, a text and three tables (E2's `Sales` paragraph has the detail).
  **AMENDED BY PLAYTEST F2 (2026-09-23):** this line used to name
  `core/src/test/resources/modules/Doc/SalesReport.e` (`report : Node`), and
  the first real playtest MEASURED that the server refuses it at render: 400
  *"Doc.SalesReport.report is not a report: a report must be a function
  Params -> Node, not Node"* (`json/Decode.scala:137`; the picker offers bare
  `Node` bindings knowingly, `lsp/Definitions.scala:393-397`). **E10 (the pie
  and bar charts) has NO FIXTURE** until the runner accepts a zero-parameter
  report or `SalesReport` gains a parameter (the user's call, Q27).
  **WP-34 (2026-09-24) fixed that: `SalesReport` renders, see E2's
  `SalesReport` sub-step and E10.** Run the
  panel steps after A4/B1, so `Sales`'s params file already exists (a first
  pick writes it and opens it, which is B1's behaviour, INFERRED to move focus).
- **Open the webview's developer tools once** for E3 and keep them for E5:
  **Developer: Open Webview Developer Tools** while the panel is focused.

**What the panel is NOT, so you do not mark it down for it:** it has no
*Render anyway* button (the held question stays the notification C6
describes), no *unsaved* hint (nothing produces one yet), and never shows
*switching …* (profiles do not exist). `treeMap` is always an error box.

### E1 [new] — The panel opens BESIDE, and the cursor stays where it was — **NEVER RUN**

- **Setup:** the standing setup; no panel open; an `.e` file open in the only editor group.
- **Do:** click into that editor and start typing. WITHOUT stopping, run **Ermine: Preview Report...** → `core/src/test/resources/doc/Sales.e` → `report` (was `Doc/SalesReport.e`: refused at render, F2).
- **Expect:** a webview tab titled **`Ermine preview`** (`editor/vscode/src/preview-core.js:5466`, `const PANEL_TITLE = "Ermine preview";`) opens in a NEW column beside yours, and **the cursor stays in your editor**: the panel is created with `{ viewColumn: vscode.ViewColumn.Beside, preserveFocus: true }` (`editor/vscode/src/extension.js:2588`). **No untitled JSON tab opens**: under `panel` the tab path is skipped (`if (route.tab) await showAnswer(answer, reveal);`, `editor/vscode/src/extension.js:2414`). The channel logs the usual `preview: render Sales.report (generation N; the report was picked; …)` and, once per panel, ``preview: watching ${dir} for bundle rebuilds`` (`editor/vscode/src/extension.js:2658`) with `dir` = this worktree's `client/dist/browser`. **No `preview: the legacy writers …` line**: a present writers folder is silent (`writersLine` answers null, `editor/vscode/src/preview-core.js:5778`).
- **Failure:** the cursor lands in the panel; a JSON tab opens as well; the panel opens in your own column, replacing the file. **Paste into `tracker/PLAYTEST-RESULTS.md`:** the Ermine channel from the command on, and the value of `ermine.preview.target` you had.
- **Bears on:** WP-10 S2 (the reveal latch, `preserveFocus`); U1.

### E2 [new] — A document renders in the panel — **NEVER RUN**

- **Setup:** E1's panel.
- **Do:** look at it.
- **Expect (AMENDED BY PLAYTEST F2, 2026-09-23):** the typed `Sales` document exactly as the `Sales` paragraph below describes: **five widgets, no error box**. (This step used to expect `Doc/SalesReport.e`'s scorecard `Sales by region`; that report is refused at render, F2, so no fixture draws a scorecard today.) **No banner at all**: the banner is hidden whenever there is nothing to say (`banner.hidden = p.banner === null;`, `client/src/host/page.ts:343`), and the document is not dimmed. The heading and the text need no writers, so they are the part of this step that does not depend on WP-11. **The channel carries no `preview panel: widget …` line**: the page logs one per widget that failed (`client/src/host/page.ts:390`).
- **E2, the `Sales` sub-step (Q24 (d), added 2026-09-23; REWRITTEN BY Q25 the same day: `Sales` is TYPED now).** **Do:** nothing more: E1 already picked it (before F2 this was a second pick after `Doc/SalesReport.e`). **Expect** (MEASURED in jsdom from the captured answer, `scratch-widget-preview/q25/captures.json` `ok-sales` = `editor/vscode/test/fixtures/panel-answers.json` `ok-sales`, by `client/test/widgets.test.ts` `(w-sales-panel)`; every widget validated against the GENERATED zod by `scratch-widget-preview/q25/validate.mjs`; NOT yet seen in VS Code): **FIVE widgets, NO error box.** (1) **the heading DRAWS** (`Layout.Widgets.Heading`, `core/src/test/resources/doc/Sales.e:154`): a title `Sales` (`client/src/widgets/heading.ts:43`, `title.textContent = props.title;`) and one line ``${props.matched} matched``, ``total ${props.total}``, ``sorted by ${props.sortColumn}`` joined by `, ` (`heading.ts:54-58`) -- with the capture's params (`2026-01-05`..`2026-02-20`, `north`, `ByAmount`) that reads **`3 matched, total 4350.75, sorted by amount`**; with the skeleton's today's dates it reads `0 matched, total 0, sorted by day` (Q21; MEASURED `ok=true`, `sales-today` in the same capture); (2) **the text DRAWS** (`Layout.Widgets.Text`): a paragraph **`every line item, whatever the date range`** (`client/src/widgets/text.ts:22`, `p.textContent = props.body;`; the string is `Sales.e:165`); (3) **THREE TABLES DRAW through the writers' `runTabular`**, as E9's does: `$.root.children[1].cells[0][0]` with the headers `Region`, `Day`, `Amount`, `Units` and three north rows, sorted by `Amount` descending (INFERRED, as E9's sort is, from the `ColumnSort 2 True` that `sortOf ByAmount` gives, `Sales.e:122`); `[0][1]` with one header, `Region`, and four rows; `[1][0]` with `Item`, `Amount`, `Units` and all eight line items. **The items table is INLINE**: a typed table cannot force deferral (`TableProps.rows` is a bare relation) and the preview asks inline, so nothing in this document reaches the page's refusal (`this preview does not fetch deferred relations, …`) -- that box is WP-30's, and no fixture shows it today. The Ermine channel carries **no** `preview panel: widget …` line (`client/src/host/page.ts:390`). **Failure:** any error box; markup in the heading shown as markup rather than text; a table with no rows; fewer or more than five widgets. (The step's history: Q24 (d) drew `heading`/`text` with hand-written schemas and left all three tables as boxes, since the old `Sales.e` handed `table` a bare relation; the user decided Q25 on 2026-09-23, *"I'm pretty sure I want typed widget schemas in the typescript rather than matching runtime ermine values fallibly"* and *"Rewrite it."* The untyped shape lives on in `core/src/test/resources/doc/SalesRaw.e`, the runner's fixture, which is NOT a preview step: four of its five widgets are boxes by design.)
- **E2, the `SalesReport` sub-step (WP-34, added 2026-09-24; needs 0.1.16).** **Do:** delete `.ermine/preview/Doc.SalesReport/` if an older extension left a `report.params.json` there, then **Ermine: Preview Report...** → `core/src/test/resources/modules/Doc/SalesReport.e` → `report` (`report : Node`, a report with NO parameters). **Expect** (MEASURED through one `bin/ermine-lsp` boot, `scratch-widget-preview/wp34/captures.json`; NOT yet seen in VS Code): (a) **no file is written and no params document opens**: nothing appears under `.ermine/preview/Doc.SalesReport/` (the server's `ermine/schema` answers `{"parameters": false}`); (b) the Ermine channel says once `preview: Doc.SalesReport.report takes no parameters, so no params file is written and it renders with none.` and **no** `no params file at ... Write one there` line; (c) the panel draws **four widgets, no error box**: a scorecard `Sales by region` (three cards, EMEA/APAC/AMER), a table (`Region`, `Sales`, `Change`, three rows), a bar chart `Sales by region` and a pie `Share of sales` (the last two are E10's). **Failure:** a `report.params.json` or `report.schema.json` appears; a 400 *"... is not a report"* (the server was not rebuilt) or *"... takes no parameters"* (a params file was left behind, step (a)); any error box. **Paste:** the channel and `ls -la .ermine/preview/`.
- **Expect, the look (AMENDED BY PLAYTEST F3, 2026-09-23; MEASURED in a headless Chromium with the real page builder and bundles, `scratch-widget-preview/panel-fix/panel-dark-fixed.png`, NOT yet seen in VS Code):** the banner area keeps your theme; **the document is a white sheet with near-black (`#222`) text** in a dark theme too. The `Sales` heading is at the top, then the `Grid`: **two tables side by side** in its first row (`Region`/`Day`/`Amount`/`Units`, and `Region` alone) and the items table beside the text in its second, while the panel is wide enough for two cells of 480px (about 1000px); narrower, the four stack. **Every table shows its rows** (the harness drew 8, 4 and 8 from the `sales-range` capture, `scratch-widget-preview/q25/captures.json`, 2026-01-05..2026-03-17 by day, not from your params file; your counts follow your params), the one-column `Region` table included, and no table is drawn over another. Table text is 12px. **F3 failure:** a table that is a header and one row of `.` (the draw step did not run. If the channel has `window.ermine_htmlwriter_conf.renderFunction is not there, ...`, the writers lack the draw step. If there is no line at all, the bundle is the old one without F3: run `npm run bundle` in `client/` again); grey text on grey; two tables overlapping. F3 needs only `npm run bundle` in `client/`, not a new `.vsix`: the panel should reload by itself, and if it does not, run the command again. **OBSERVED by the user, 2026-09-23** (VS Code 1.139.0, Vue Theme): after the bundle rebuild the panel drew `Sales` with its tables (*"It renders now, the tables show up"*), and it re-rendered on a params-file save and on a `Sales.e` save (*"yup, it updates"*). Whether that reload came from the bundle watcher or from re-running the command is NOT recorded.
- **Failure:** a blank panel; the `Pick a report: Ermine: Preview Report...` banner (`client/src/host/index.ts:299`) after the render line has appeared; or a red box saying `the client bundle (window.ErmineClient) is not loaded, so the document cannot be drawn` (`client/src/host/page.ts:372`). **Paste:** the Ermine channel, and the developer tools' console (E3's window) as text.
- **Bears on:** WP-10's done-when, **AMENDED BY Q24 AND Q25 (2026-09-23): an inline fixture renders in the panel -- the typed `Sales`, this step's document** (and E9). **Before playtest F2 this also named `Doc/SalesReport.e`, which is refused at render (Q27).** Also WP-9's bundle in a real webview, and Q25's typed `heading`/`text` widgets. WP-30's deferred box is NOT reachable from this step (no fixture carries a typed deferred table).

### E3 [new] — The console shows no CSP violation but the one named sprite — **NEVER RUN**

- **Setup:** E2's document on screen; the webview developer tools open on the **Console** tab. If the console has a context drop-down, the panel's page is the inner frame, not `top` (*external*, unverified).
- **Do:** reload nothing. Read the console from the top.
- **Expect:** **no line that says a resource or script was refused by the Content Security Policy**, with at most ONE exception: a blocked image for `/CIQDotNet/images/TopMenuBar/tmbllsprite.png?urwvid=1`, which is `url("/CIQDotNet/images/TopMenuBar/tmbllsprite.png?urwvid=1")` at `ermine-writers/writers/html/src/main/resources/web/common.css:125` (MEASURED by the WP-11 review: the only `url()` in the three style sheets the page loads). A browser fetches a CSS background image only for an element the rule matches (`.headerlabel`), so **zero lines is also a PASS** (INFERRED). The policy the page carries, from `editor/vscode/src/preview-core.js:5368` and `:5369`: `default-src 'none'; script-src <cspSource> 'unsafe-eval'; style-src <cspSource> 'unsafe-inline'; img-src <cspSource> data:;`. **`mainSprite.png` must NOT appear**: it is in `htmlwriter_dark.css`, which is not in the list the page links (`editor/vscode/src/preview-core.js:5680`).
- **UNKNOWN, AND SAID SO:** the 5.2 MB `htmlwriter.js` may inject styles or images at run time. Nobody has read it for that (the design review measured `url(` only in the CSS files). **Any OTHER blocked resource: copy its URL verbatim into the notes.** It is a finding, not automatically a FAIL; the orchestrator decides.
- **Failure:** a refused SCRIPT (then the writers or the client did not load — look for the `eval` wording, which would mean `'unsafe-eval'` is not honoured); a refused style sheet; any `connect-src` refusal before you have clicked anything (E11's click is the one expected source of one). **Paste:** every console line that mentions `Content Security Policy` or `Refused`, verbatim.
- **Bears on:** WP-11 done-when; W7; Q19 (`'unsafe-eval'`); U5 (`blob:` absent).

### E4 [new] — An error banner: status, message, path, and the document dimmed below — **NEVER RUN**

- **Setup:** `Sales.report` picked in the panel with a params file that renders: `mkdir -p .ermine/preview/Sales && cp tracker/playtest/params/Sales.report.params.json .ermine/preview/Sales/report.params.json`, then **Ermine: Preview Report...** → `core/src/test/resources/doc/Sales.e` → `report`. Its document is E2's broken-looking one; that is fine, this step judges the banner.
- **Do:** open `.ermine/preview/Sales/report.params.json`, add the line `"fromDy": "2026-01-05",` and **save**.
- **Expect:** the SAME panel, not revealed (a save never reveals), gains a banner reading exactly **`400: the key "fromDy" is not allowed here ($.params.fromDy)`**. The answer is MEASURED (`scratch-widget-preview/wp10-s1/captures.json` `error-400-sales-key`: `status 400`, that `message`, `path "$.params.fromDy"`) and the banner text is the reducer's ``const head = e.status === 0 ? e.message : `${e.status}: ${e.message}`;`` then ``return e.path === null ? head : `${head} (${e.path})`;`` (`client/src/host/index.ts:305` and `:306`). **The last document stays, DIMMED** — faded to `.ermine-document.ermine-dimmed{opacity:.45}` (`client/src/host/page.ts:265`) because an error is on the list of states that dim (`(state.offline || state.switching !== null || state.error !== null || state.held !== null)`, `client/src/host/index.ts:277`). With **Ermine: Toggle Fast Mode** on, the message also ends ` -- fast mode is on: type errors are not shown in Problems` (`editor/vscode/src/preview-core.js:5168`).
- **Then:** remove the line and save. The banner goes and the document is no longer dimmed.
- **Failure:** no banner; a banner without the `($.params.fromDy)` part; the document gone instead of dimmed; or the panel jumping in front of your editor. **Paste:** the Ermine channel and the banner text as you see it.
- **Bears on:** WP-10 done-when ("a 400 from a bad param shows `path` in the banner"); §5's Errors row; W5.

### E5 [new] — Hide the panel, wedge the server, show it: the stuck banner is there — **NEVER RUN**

**This is the design review's F1 experiment.** The vendored `@types/vscode`
(1.134.0) says both of these, and they contradict each other:
`editor/vscode/node_modules/@types/vscode/index.d.ts:10018` and `:10019` —
*"Messages can only be posted to live webviews (i.e. either visible webviews
or hidden webviews that set `retainContextWhenHidden`)."* — and
`editor/vscode/node_modules/@types/vscode/index.d.ts:10076` and `:10077` —
*"You cannot send messages to a hidden webview, even with
`retainContextWhenHidden` enabled."* The panel sets `retainContextWhenHidden:
true` (`editor/vscode/src/extension.js:2594`) AND re-sends the whole state when
it becomes visible (`if (previewPanel === panel && panel.visible)
postSnapshot("visible");`, `editor/vscode/src/extension.js:2615`), so **the
banner should be there whichever sentence is true**. The optional
instrumentation below is what tells the two apart.

- **Setup:** `"ermine.preview.timeoutSeconds": 5`. Pick **`tracker/playtest/fixtures/WpInt.e`** → `report` (the control) so the panel shows its document — an `int` box, since no renderer is registered under `int`; that is fine. **Drag the panel into the same editor group as `WpInt.e`**, so that clicking the file's tab hides it. *Optional, and the only way to settle F1:* in the webview developer tools' console, in the panel's frame, run `addEventListener("message", e => console.log("ermine snapshot", e.data && e.data.seq, new Date().toISOString()))` (whether a listener added from the console survives while the webview is hidden is itself unverified).
- **Do:** (1) click `WpInt.e`'s tab so the panel is hidden, and note the time. (2) In `WpInt.e` change `report n = rawWidget "int" n` to `report n = report n` and **save** — a save re-renders WITHOUT revealing, and that report now never finishes. (3) Wait until the stuck ERROR notification appears (5–7 s at a 5 s timeout; MEASURED 7.18 s for `WpSpin` including a session boot, which this re-render does not pay; C1 quotes the text), then ten seconds more. (4) Click the panel's tab.
- **Expect:** the panel shows **the stuck banner**: the server's own sentence, `evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that evaluation ever finishes; if it does not, restart the language server -- run "Ermine: Restart Language Server" (ermine.restartServer)` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2177` to `:2179`), with a **`Restart Language Server`** button beside it (`client/src/host/page.ts:332`; shown only for this banner, `client/src/host/page.ts:346`). `stuck` outranks the watchdog's own 500 answer (`"offline", "stuck", "held", "reloading", "switching", "error", "stale", "initial",`, `client/src/host/index.ts:225`), and that 500 is why the document below is DIMMED.
- **Record F1 in the notes, one of three:** (a) the console has an `ermine snapshot` line timestamped BEFORE step 4 → posts DO reach a hidden retained webview, `index.d.ts:10018-10019` is the true sentence; (b) the only new lines arrive at step 4 → `index.d.ts:10076-10077` is; (c) you did not instrument, or saw nothing either way → **not determined** (still a PASS on the banner).
- **Leave it wedged for E6.** Do not undo the edit yet.
- **Failure:** the panel still shows the WpInt document with no banner, or with an older banner, after step 4 — then the visible resync did not happen. **Paste:** the Ermine channel from the save on, and every `ermine snapshot` console line.
- **Bears on:** F1, U2 (`retainContextWhenHidden`), H7 (a hidden panel drops posts), W1.

### E6 [new] — The panel's Restart button restarts and does NOT re-render the held pick — **NEVER RUN**

- **Setup:** E5's end state: the stuck banner with its button, `WpInt.e` still edited to diverge.
- **Do:** press **Restart Language Server** in the PANEL (not in the notification).
- **Expect:** the channel logs `preview: the panel asked for a restart` (`editor/vscode/src/extension.js:2729`) and the extension runs the same command the palette runs (`vscode.commands.executeCommand("ermine.restartServer");`, `editor/vscode/src/extension.js:2730`). The banner may flash `server stopped -- last document kept` (`client/src/host/index.ts:285`) while the client is down, and then settles on **the held banner**, the document dimmed: `Ermine: WpInt.report wedged the preview: the watchdog fired and the server did not come back. Nothing has changed since, so it was NOT re-rendered automatically.` (`editor/vscode/src/preview-core.js:1049` for the middle, `:1061` for the end). **No `preview: render …` line follows the restart**; the channel has `preview: not re-rendering — …` (`editor/vscode/src/extension.js:1729`) and `preview: HELD — …` (`editor/vscode/src/extension.js:1750`), and the **Render anyway / Not now** notification appears (`editor/vscode/src/extension.js:1789`, C6). Answer **Not now**.
- **Undo:** in the EDITOR, put `report n = rawWidget "int" n` back and **save**. An `.e` save clears the hold (C10), so the report renders again and the banner goes. `git diff --stat tracker/playtest/fixtures/WpInt.e` must print nothing. `ermine.preview.timeoutSeconds` back to `60`.
- **Failure:** a render right after the restart (Q17's loop, through the panel's door); or the button doing nothing (no `the panel asked for a restart` line). **Paste:** the Ermine channel from the button press to the held banner.
- **Bears on:** U4 (Restart only); WP-22; Q17.

### E7 [new] — `npm run bundle:watch`: edit a widget, the panel updates ONCE, no restart — **NEVER RUN**

- **Setup (NOTE, playtest F2: no fixture draws a scorecard today, so this step's scorecard edit has nothing to show; edit `client/src/widgets/heading.ts` instead and look for the `Sales` heading, or SKIP it):** E2's `Doc.SalesReport` document in the panel. In a terminal: `cd client && npm run bundle:watch`, and wait until it has built once and gone quiet. **Its own first build rewrites the bundle, so the panel reloads once here** — that is the watcher working, not this step's event.
- **Do:** in `client/src/widgets/scorecard.ts` change `title.textContent = props.title;` to `title.textContent = "E7 " + props.title;` and **save**.
- **Expect:** within a few seconds the banner **`the client bundle changed; reloading`** (`client/src/host/index.ts:291`) appears, then the page is replaced and the scorecard's title reads **`E7 Sales by region`** — with no render line in the channel and no server restart: the new page is sent the last document again. The channel logs **exactly ONE** reload line for the build, `"preview: " + why + "; reloading the panel"` (`editor/vscode/src/preview-core.js:5931`), where `why` is `the client bundle changed (N file events)` (`editor/vscode/src/preview-core.js:5927`). One build writes four files; only the `*.js` two are watched (`editor/vscode/src/preview-core.js:5852`) and every event pushes one shared 250 ms deadline (`editor/vscode/src/preview-core.js:5857`), so one build is one reload. Scroll position is lost; that is accepted.
- **Undo:** `git checkout -- client/src/widgets/scorecard.ts`. That is a second build, so a second reload line is expected. Then stop `bundle:watch` (Ctrl-C).
- **Failure:** TWO reload lines for one save (the coalescer lost the race — write down the gap you think there was); the title unchanged after the banner went (the stamp did not bust the cache); or the banner staying up. **Paste:** the Ermine channel from the save on, and the terminal's last twenty lines.
- **Bears on:** WP-10 done-when ("editing `client/src/widgets/scorecard.ts` updates the panel without a restart"); W4; H4.

### E8 [new] — Delete the bundle FILES, then the FOLDER: which one flips the page? — **NEVER RUN**

**What the typings predict, verbatim** (`editor/vscode/node_modules/@types/vscode/index.d.ts:13977` to `:13979`): *"paths that do not exist in the file system will be monitored with a delay until created and then watched depending on the parameters provided. If a watched path is deleted, the watcher will suspend and not report any events until the path is created again."* And (`editor/vscode/node_modules/@types/vscode/index.d.ts:13996` to `:14001`): *"file events from deleting a folder may not include events for the contained files. […] performance optimizations are in place to fold multiple events that all belong to the same parent operation (e.g. delete folder) into one event for that parent."* The watcher's glob is `*.js` (`editor/vscode/src/preview-core.js:5852`), which a folder event does not match.

- **Setup:** E2's document in the panel; `bundle:watch` NOT running.
- **Do, part 1 (the files):** `rm client/dist/browser/ermine-client.js client/dist/browser/ermine-host.js` (one command). Wait two seconds.
- **Expect, part 1:** the panel turns into the static page **`The preview bundle is not built`** (`editor/vscode/src/preview-core.js:5581`), its message starting `no ermine-client.js or ermine-host.js in <that folder>. Run \`npm install\` once and then \`npm run bundle\` in <client>` (`editor/vscode/src/preview-core.js:5582`) and ending `, then run Ermine: Preview Report... again` (`editor/vscode/src/preview-core.js:5583`). Two channel lines: `"preview: " + why + " and the bundle is not whole (" + (a.state || "problem") + "); showing the notice page"` (`editor/vscode/src/preview-core.js:5934`, state `absent`), then ``preview: ${bundle.title} -- ${bundle.message}`` (`editor/vscode/src/extension.js:2537`). **If the two deletions land more than 250 ms apart** you may see **`The preview bundle is HALF-BUILT`** (`editor/vscode/src/preview-core.js:5588`) for a moment first — not a failure.
- **Then:** `cd client && npm run bundle`. **Expect** the page back without a command, and ONE line `"preview: " + why + " and the bundle is whole again; loading the panel page"` (`editor/vscode/src/preview-core.js:5932`).
- **Do, part 2 (the folder):** `rm -rf client/dist/browser`. Wait five seconds. Then `cd client && npm run bundle` again. Wait five seconds.
- **Record, one line each, in the notes:** (i) after the `rm -rf`: did the page flip to *not built*, or stay as it was? (**The typings predict it STAYS**: the page's scripts are already loaded and the folder event does not match `*.js`.) (ii) after the rebuild: did a reload line appear by itself (the watcher resumed when the folder was re-created, as the first quote says it may "with a delay"), or nothing?
- **Either answer to (i) and (ii) is a PASS as long as the next Ermine: Preview Report... puts the page right** — an existing panel on the notice page re-checks on every explicit command (`openPanel`, `editor/vscode/src/extension.js:2569` onwards). **FAIL only if** part 1 does not flip, or the command does not recover the page after part 2.
- **Failure paste:** the Ermine channel from the `rm` on, and `ls -l client/dist/browser` at the moment you judged.
- **Bears on:** W10 (the not-built page is the default first experience); H4; the S3 review's docs must-fix M1 (it was about exactly this folder delete).

### E9 [new] — `table` renders THROUGH `runTabular` — **NEVER RUN**

- **Setup:** E2's `Sales` document; writers at the default. (AMENDED BY PLAYTEST F2: this step used `Doc/SalesReport.e`'s table, which is refused at render.)
- **Do:** look at the items table, `$.root.children[1].cells[1][0]` (the last one, under the text).
- **Expect:** a real table drawn by the legacy writers, with the headers `Item`, `Amount` and `Units` and all **eight** line items, whatever the date range (E2's `Sales` paragraph; MEASURED in jsdom, NOT yet in VS Code). The `byDay` table at `cells[0][0]` has rows only for dates that select sales (with the skeleton's today's dates it is an empty four-column table, Q21), so it is not this step's witness. **No error box** for it, and **no** `preview panel: widget "table" …` line in the channel (`client/src/host/page.ts:390`). The error it would show without the writers is `env.htmlwriter with a runTabular function is required by this widget` (`client/src/legacy.ts:338`), and seeing THAT means the writers did not load.
- **Failure:** an error box; a table with no rows; an unstyled table (then `common.css` did not load — look in E3's console). **Paste:** the channel, the console, and one sentence describing what is drawn.
- **Also:** the other two `Sales` tables draw through the same `runTabular`.
- **Bears on:** WP-11 done-when (the one row that has been HUMAN since WP-9); §5's Bundle checklist third row.

### E10 [new] — A `pieChart` draws — **NEVER RUN (fixture restored by WP-34)**

**FIXTURE RESTORED 2026-09-24 BY WP-34 (Q27 option (i)): `Doc/SalesReport.e` (`report : Node`) renders as a report with no parameters.** It is the only report with a `pieChart` and an `axisChart`; `Sales` has no chart. (Between playtest F2 and WP-34 this step was SKIP: the server refused the report at render.) Needs 0.1.16 and the rebuilt server.

- **Setup:** E2's `SalesReport` sub-step's document.
- **Do:** scroll to the last item, `$.children[3]`, and the bar chart above it, `$.children[2]`.
- **Expect:** a pie titled **`Share of sales`** (`core/src/test/resources/modules/Doc/SalesReport.e:59`) with three slices and a legend table to its right (INFERRED from `LegendRightTable` in the same props); above it a bar chart, also titled `Sales by region` (`core/src/test/resources/modules/Doc/SalesReport.e:52`), with three bars, each chart 320 px tall and as wide as the paper, coloured (not black: **AMENDED 2026-09-25 BY S2f-1**, the page now links the writers' `javafxwriter.css`, which holds Highcharts' styled-mode rules; before that every chart drew as a black box, MEASURED headlessly: `scratch-widget-preview/db/s2f/salesreport-dark.png`, `-light.png`, and `old/` for the before). Both are Highcharts, which is bundled inside `htmlwriter.js` (MEASURED by the design review: 11 webpack modules), so no other script loads. **No error box, no `preview panel: widget` line.** Without the writers the box would read `env.htmlwriter with a runPiechart function is required by this widget` (`client/src/charts.ts:451`, with `runPiechart` for the name).
- **Failure:** an empty box where the chart should be; a chart with no slices; an error box. **Paste:** the channel and the console.
- **Bears on:** WP-11 done-when.

### E11 [new] — A style-box click does nothing, and that is by design (OPTIONAL, NEEDS A FIXTURE) — **NEVER RUN**

- **Setup:** **THERE IS NO REPORT TO RUN THIS ON.** MEASURED by `grep`: no report-typed binding in this repository draws a `styleBox`. The only `.e` files that use it are `core/examples/Present/*.e`, and none of them has a binding of a report type. **Record SKIP — "no fixture"** unless you write a small report yourself (`Layout.Widgets.StyleBox`; `styleBox` is the `rawWidget` name).
- **If you have one:** click a cell of the 3×3 grid.
- **Expect:** nothing visible happens in the panel, nothing throws, and the channel gets NO new line. The writers' click-through always POSTs for the popup's rows; the page's CSP has no `connect-src` (`default-src 'none'`), so the POST is refused, and the legacy code reports it through its own error callback: *"`relation` and `legend` are sent as `null`, the POST fails, and stylebox.js logs through its own `callbackError`. No exception reaches the page."* (`client/src/charts.ts:21`). **The console is where "logs" happens**: a `connect-src` refusal and whatever `callbackError` prints (unread). That refusal is the expected exception to E3.
- **Failure:** the page blanks, an exception surfaces, or a popup opens with rows (then something is reachable that the CSP should have refused). **Paste:** the console lines from the click.
- **Bears on:** WP-11 (W9: the click-through cannot work under `default-src 'none'`).

### E12 [new] — Close the panel, re-run the command: ONE panel — **NEVER RUN**

- **Setup:** a panel open with any document.
- **Do:** (1) run **Ermine: Render Report to JSON** twice more with the panel open. (2) Close the panel's tab. (3) Run **Ermine: Render Report to JSON** again.
- **Expect:** after (1), still exactly one `Ermine preview` tab — the second command reveals the panel that exists (`previewPanel.reveal(undefined, true);`, `editor/vscode/src/extension.js:2569`). After (2), nothing in the channel beyond what a render writes; the panel's state is dropped (`previewPanel = undefined;`, `editor/vscode/src/extension.js:2606`). After (3), a NEW `Ermine preview` tab with the current document, and a fresh ``preview: watching ${dir} for bundle rebuilds`` line (`editor/vscode/src/extension.js:2658`). **Never two panels.**
- **Failure:** two `Ermine preview` tabs at once; or no panel after (3). **Paste:** the Ermine channel from (1) to the end.
- **Bears on:** H9 (two commands, one panel); the dispose path.

### E13 [new] — `ermine.preview.target`: `json` is the old tab, `both` is both — **NEVER RUN**

- **Setup:** close the panel first. The code shows that an ALREADY OPEN panel keeps being sent the state whatever the target (`setPreviewStatus` posts a snapshot for every state change, `postSnapshot("status");` at `editor/vscode/src/extension.js:712`, and every render folds its answer into the panel's state before `present` routes it, `editor/vscode/src/extension.js:2305` — INFERRED from those two lines, not observed), so an open panel would muddy this step.
- **Do:** (1) set `"ermine.preview.target": "json"`, run **Ermine: Render Report to JSON**. (2) Set it to `"both"`, run it again. (3) Set it to `"tab"`, run it again. (4) Set it back to `"panel"`.
- **Expect:** (1) the untitled JSON tab exactly as in A7 and A9 — **the tab path is byte-for-byte 0.1.11's** — and no panel: `json` routes to the tab only (`return Object.freeze({ tab: t === "json" || t === "both", panel: t === "panel" || t === "both" });`, `editor/vscode/src/preview-core.js:5523`). (2) the tab updated first, then a panel (`editor/vscode/src/extension.js:2414`, then `:2416`, `if (reveal) openPanel();`). (3) ONE channel line, `ermine.preview.target is one of "panel", "json" or "both", not "tab"; the preview uses "panel"` prefixed `preview: ` (`editor/vscode/src/preview-core.js:5156` to `:5158`, logged by `editor/vscode/src/extension.js:2427`), and the panel is used; running it again does NOT repeat the line.
- **Failure:** a panel under `json`; no tab under `both`; the `tab` line repeated per command. **Paste:** the channel.
- **Bears on:** U1 (taken by the orchestrator, not asked of you: see the open decisions).

### E14 [new] — The writers-missing banner — **NEVER RUN**

- **Setup:** `mkdir -p /tmp/wp-empty`. **Close the panel**: a page built WITH the whole writers is not re-checked by a command (only a page built without them is), so changing the setting under an open, healthy panel does nothing until a new panel or a bundle rebuild.
- **Do:** set `"ermine.preview.writersPath": "/tmp/wp-empty"`, then **Ermine: Preview Report...** → `core/src/test/resources/doc/Sales.e` → `report` (was `Doc/SalesReport.e`: refused at render, F2).
- **Expect, the banner** (status 0, so no `NNN:` prefix and no path): `the legacy writers are not loaded: no htmlwriter.js in /tmp/wp-empty. table, drilldownTable, the charts and styleBox show an error box instead; set ermine.preview.writersPath to the writers' web/ folder and run Ermine: Preview Report... again` — built at `editor/vscode/src/preview-core.js:5758` and `:5759`, with the `why` of `:5757` and the fix of `:5754`, sent as an `error` with `status: 0` (`editor/vscode/src/preview-core.js:5333`). **The document is DIMMED** under it, the heading and text drawn (AMENDED BY F2: `Sales` has no scorecard and no chart), and its three tables are error boxes, each saying `env.htmlwriter with a runTabular function is required by this widget` (`client/src/legacy.ts:338`). **The channel** has the same sentence once, prefixed `preview: ` (`editor/vscode/src/preview-core.js:5778`), and one `preview panel: widget "…" at $.children[N]: it threw while rendering: …` line per legacy widget (`client/src/host/page.ts:390`, `client/src/dispatcher.ts:247`). While this banner is up a re-render in flight shows NO *re-rendering* banner (an error outranks `stale`, `client/src/host/index.ts:225`) — expected, and in the README since this stage.
- **Then:** set `writersPath` back to `""` and run **Ermine: Preview Report...** again, the same pick. **Expect** the page to reload WITH the writers (a page built without them IS re-checked on a command) and the banner to go.
- **Failure:** no banner; a banner that begins `0:`; widgets drawn although the folder is empty; or the fix in "Then" needing a window reload. **Paste:** the channel.
- **Bears on:** WP-11's second done-when half; the Bundle checklist row's third state; N2.

### E15 [new, WP-31] — The Document / JSON toggle — **NEVER RUN**

- **Setup:** the standing setup, the client bundle rebuilt AFTER WP-31 (`npm run bundle` in `client/`; no new `.vsix`, the extension did not change). Close the panel, then set `"ermine.preview.target": "both"` so ONE render fills the tab AND the panel (`panel: t === "panel" || t === "both"`, `editor/vscode/src/preview-core.js:5560`).
- **Do:** (1) **Ermine: Preview Report...** → `core/src/test/resources/doc/Sales.e` → `report`. (2) In the panel, click **JSON**. (3) Select all the text in the panel's JSON and in the untitled JSON tab and compare them (a diff tool, or paste both into two scratch files and run **Compare Selected**). (4) Save the params file once (a re-render) while JSON is showing. (5) Click **Document**. (6) Click **JSON** again, then run `npm run bundle` in `client/` (the bundle watcher re-sets the page). (7) Tab from the editor into the panel and press Space on each button. (8) **Developer: Reload Window**, then **Ermine: Preview Report...** again. (9) Set the target back to `"panel"`.
- **Expect:** (1) a toolbar between the banner and the white paper with two buttons, `Document` and `JSON` (`control("Document", "document")`, `control("JSON", "json")`, `client/src/host/page.ts:431`–`:432`), **Document** drawn in the theme's button colours (pressed, `aria-pressed="true"`). (2) the paper shows monospace JSON; the tables are gone from view; **no re-render**: no new render line in the channel, and the status bar does not move. (3) **the two texts are identical**: the panel's is `JSON.stringify(value, null, 2)` (`client/src/host/page.ts:191`) of the document, the tab's is `stringify(answer.document)` (`editor/vscode/src/preview-core.js:1971`), the same call. (4) the JSON updates to the new answer; the view stays on JSON. (5) the document is back AT ONCE, the tables with their rows (the same rows as the new answer in the tab): it was re-rendered once behind the JSON in (4), laid out off-stage (`area.classList.toggle("ermine-offstage", p.showDocument && view === "json");`, `client/src/host/page.ts:474`). (6) after the page reloads, **JSON is still the view** (read back by `try { view = restoredView(api.getState?.()); }`, `client/src/host/page.ts:401`; written by `api.setState?.({ ...base, view });`, `:450`). (7) each button is reachable with Tab and Space presses it. (8) after the window reload there is NO panel until the command runs (the extension registers no `WebviewPanelSerializer`), and the new panel opens in **Document**: the stored choice belongs to the panel that was closed.
- **Optional, the error case:** with E4's failing params in place, click **JSON**: the text is the four fields `status`, `message`, `path`, `reason` of the banner, NOT the tab's whole `{ "ok": false, ... }` answer (no `ok`, no `generation`): that gap is stated, and Q28 in `tracker/JSON-WIDGET-PLAYGROUND.md` asks whether to close it.
- **Failure:** the two texts in (3) differ; the tables redraw (a flash, or a channel render line) on a click; after (5) the tables are one-row skeletons (the writers drew a hidden document: the off-stage rule failed in the webview); (6) comes back as Document; the view is sent to the extension (a channel line on a click); a writers popup or tooltip drawn offset by the banner-plus-toolbar height (the root is now `position:relative`, WP-31 review N3). **Paste:** the channel, and the first 20 lines of each text in (3) if they differ.
- **Bears on:** WP-31's done-when; whether `setState` survives a `webview.html` re-set in the real webview (UNVERIFIED: read from the `@types/vscode` docs only, never observed).

---

## Group F — the database

**What this group is for.** DB programme stage 2 (tracker/DB-PLAN.md §4 S2, S5): the preview renders
against a real SQL Server 2022 (`ermine-mssql`, rootless podman, `ErmineSales`) through a **profile**
in USER settings and a **prompted password**. The render answer carries a **trace** that the panel's
**Trace** view draws. The narrative version, with timings and fallbacks, is
**`tracker/db/DOGFOOD.md`**: F1-F12 are its steps 0-12, in its order. **Every step below is NEVER RUN
in a VS Code.** The server half was MEASURED over the wire by `TestPreviewDbLive` and
`TestRenderTraceLive` (tracker/db/SERVER.md §6.3, tracker/db/OBSERVABILITY.md §4 and §8). The
extension and panel halves are tested in node and JSDOM only. The quotes are checked against
their lines by `tracker/db/dogfood-citecheck.py`.

**Standing setup for F1-F12** (it differs from A-E):

- **Extension 0.1.17** (profiles, the password prompt, the Trace view's glue) and a server compiled
  from this tree. The client bundle must be rebuilt after the Trace view (`npm run bundle` in `client/`).
- **`"ermine.preview.target": "both"`** in `.vscode/settings.json`, so one render fills the panel and
  the JSON tab. F12 sets it back to `panel`.
- **The profile in USER settings**, never in `.vscode/settings.json` (F2).
- **ErmineSales at tier s** (seed 42). `scripts/db.sh verify sales` says which tier is loaded.
  F6 changes it and puts it back.
- The password is `ERMINE_DB_PASSWORD` in `~/.config/ermine/db.env`. Type it into the box; do not
  paste it into a file, a terminal or `tracker/PLAYTEST-RESULTS.md`.

### F1 [new] — The database is up, and holds tier s — **NEVER RUN**

- **Setup:** a terminal in the worktree.
- **Do:** `scripts/db.sh status`, then `scripts/db.sh verify sales`.
- **Expect:** five lines ending `(( rc == 0 )) && echo "status OK" || echo "status DEGRADED"` (`scripts/db.sh:222`), i.e. `status OK`, exit 0, including `echo "login $LOGIN ok via 127.0.0.1:1433 suser=$who tls=$enc"` (`scripts/db.sh:216`) with `tls=TRUE` (MEASURED 2026-09-25 00:0x). `verify` ends with `` verify ${c.domain} mssql tier=${stamp.tier} seed=${stamp.seed ?? "-"} loaded= `` (`data/src/load/mssql.ts:150`), i.e. `verify sales mssql tier=s seed=42 loaded=... OK`.
- **Failure:** `status DEGRADED` or a nonzero exit: run `scripts/db.sh up` (4-5 s) and record that you had to. `tier=xs` or `tier=m`: run `scripts/db.sh load sales --tier s` (1.23 s with verify) and record it. **Paste:** both outputs (they contain no password).
- **Bears on:** DB-PLAN S0/S1; every step below.

### F2 [new] — The profile goes in USER settings, and a workspace copy is ignored — **NEVER RUN**

- **Setup:** F1 passed; the window from `tracker/PLAYTEST-SETUP.md` §5 closed or not yet opened.
- **Do:** **Preferences: Open User Settings (JSON)**, add `ermine.preview.profiles` (one profile, `sales-mssql`, dialect `mssql`, the URL `jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true`, user `ermine`) and `"ermine.preview.profile": "sales-mssql"`. The exact JSON is in `tracker/db/DOGFOOD.md` §2 and `tracker/PLAYTEST-SETUP.md` §6. *Optional:* copy the same two keys into `.vscode/settings.json` too, for one window, to see that they are refused.
- **Expect:** with the keys in user settings only, nothing is said. With a workspace copy as well, the channel says once `const SCOPE_NOTICE = "profiles set in workspace settings are ignored (user settings only)";` (`editor/vscode/src/preview-core.js:6808`), prefixed `settings: `, and the user value is used. With the keys ONLY in workspace settings, the status bar item reads `text: "$(database) workspace profiles ignored"` (`editor/vscode/src/preview-core.js:7272`) and nothing connects.
- **Failure:** a workspace-only profile that connects, or prompts for a password. That is the A2 hole this rule closes. **Paste:** the channel's `settings:` and `db:` lines.
- **Bears on:** tracker §8.1 A2; WP-13.

### F3 [new] — Open the worktree and the Ermine channel — **NEVER RUN**

- **Setup:** F2's user settings; `"ermine.preview.target": "both"` in `.vscode/settings.json`.
- **Do:** `code /home/dmitry/research/ermine/ermine-scala-wt-widget-preview` (ONE folder). Open any `.e` file. Run **Ermine: Show Language Server Output**.
- **Expect:** A1's activation. The channel **Ermine** is where every `db:` line (the extension's) and `preview:` line (the extension's and the server's) of F4-F11 appears.
- **Failure:** as A1.
- **Bears on:** F4-F11.

### F4 [new] — The first activation asks for the password ONCE, and connects — **NEVER RUN**

- **Setup:** F3; no password entered yet in this window.
- **Do:** wait for the password box. Type the password and press Enter.
- **Expect:** (1) before you type: a second status bar item, `text: "$(key) " + id + ": password?"` (`editor/vscode/src/preview-core.js:7264`), i.e. `sales-mssql: password?`, and the channel line `line: "db: asking for the password of " + labelText(label) + " (" + cause + ")",` (`editor/vscode/src/preview-core.js:7133`), i.e. `db: asking for the password of sales-mssql (mssql) @ 127.0.0.1 (running)`. (2) The box is titled `title: "Ermine: database password",` (`editor/vscode/src/preview-core.js:6899`), and its prompt is `prompt: "Password for " + who + " (profile " + (profile ? profile.id : "?") +` (`editor/vscode/src/preview-core.js:6900`) followed by `"). It is held in this window's memory only, until the window closes or you disconnect.",` (`editor/vscode/src/preview-core.js:6901`), i.e. **`Password for ermine @ 127.0.0.1 (profile sales-mssql). It is held in this window's memory only, until the window closes or you disconnect.`** The typed characters are masked. (3) After Enter: `text: "$(sync~spin) " + id + ": connecting"` (`editor/vscode/src/preview-core.js:7267`) and `line: "db: connecting " + labelText(s.label) + " (password entered)",` (`editor/vscode/src/preview-core.js:7146`). Then the server's `log("preview: connected " + p.id + " (" + p.dialect + ") @ " + host + " / " + db + " in " + ms +` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2127`), which reads `preview: connected sales-mssql (mssql) @ <host> / ErmineSales in <ms> ms, seq 1` (the server scrubs the host from its log; 13 ms MEASURED warm, SERVER.md §6.3). Then `line: "db: connected " + labelText(label) + (database ? " / " + database : "") +` (`editor/vscode/src/preview-core.js:7162`), i.e. `db: connected sales-mssql (mssql) @ 127.0.0.1 / ErmineSales`. (4) The item settles on `return { hidden: false, text: "$(database) " + labelText(s.label), severity: "none",` (`editor/vscode/src/preview-core.js:7260`), i.e. **`sales-mssql (mssql) @ 127.0.0.1`**. Its tooltip is `tooltip: "connected: " + labelText(s.label) + (s.database ? "\ndatabase: " + s.database : "") +` (`editor/vscode/src/preview-core.js:7261`), with `database: ErmineSales` and `server: 16.00.4295`. (5) **Restart Language Server** afterwards: NO prompt (the password is held), a reconnect, `(running, password held)`. **Developer: Reload Window**: the prompt comes back.
- **Failure:** two prompts; no prompt; the password visible in the channel; `sales-mssql: trace is verbose` (then `ermine.trace.server` is `verbose`: `line: "db: NOT connecting " + labelText(label) + ": ermine.trace.server is \"verbose\" and would log the " +`, `editor/vscode/src/preview-core.js:7108`); `sales-mssql: profile` saying the server has no `ermine/preview/connect` (the server was not rebuilt). **Paste:** every `db:` and `preview: connect` line. Check first that the password is not in them.
- **Bears on:** WP-13 done-when (the prompted password end to end, moved there from WP-12(a): DECISIONS Q-V3); A1, A3, A7.

### F5 [new] — `DbFetchTopN` draws from ErmineSales, and the JSON tab agrees — **NEVER RUN**

- **Setup:** F4 connected.
- **Do:** **Ermine: Preview Report...** → `core/src/test/resources/doc/DbFetchTopN.e` → `report` (`Query -> Fetch Node`). The first pick writes and opens `.ermine/preview/DbFetchTopN/report.params.json`. Set `"keep": 2` in it and **save**.
- **Expect:** (1) the first render (skeleton `keep` 0, from `let value = 0;`, `editor/vscode/src/preview-core.js:3272`, INFERRED) draws a pie built from the `pieChart (PieChartProps "Sales by region" "Sales" "region" "amount"` line (`core/src/test/resources/doc/DbFetchTopN.e:58`) with ONE slice, `Other`, worth 1,051,094.22. The first render after a connect rebuilds the session: MEASURED 2.2 s in `TestPreviewDbLive`. (2) After the save: ONE re-render, and the pie has **china 225,449.88, us-south 172,784.89, Other 652,859.45** (tier s, read with `scripts/db.sh sql` on 2026-09-25; the same three values are in OBSERVABILITY.md §4's MEASURED trace). (3) The second widget, `, rawWidget "metTargets" met ])))` (`core/src/test/resources/doc/DbFetchTopN.e:63`), is an error box, **by design**: `` title.textContent = `widget "${widget}" could not be rendered`; `` (`client/src/dispatcher.ts:88`) with the reason `` : fail(`no renderer is registered under that name`); `` (`client/src/dispatcher.ts:253`). (4) The JSON tab (`both`: `return Object.freeze({ tab: t === "json" || t === "both", panel: t === "panel" || t === "both" });`, `editor/vscode/src/preview-core.js:6178`) shows the pie's rows under `$.children[0].props.pieRows` and `metTargets` = 1. An amount may print as `225449.87999999998` (a Double sum).
- **Failure:** a 503 `not connected` (F4 did not finish); a 500 naming `sales` (ErmineSales is empty: `scripts/db.sh load sales --tier s`); the pie as an error box saying `env.htmlwriter ...` (the writers are missing, E14); numbers from tier xs (`north`, `east`) while F1 said tier s. **Paste:** the channel from the command on, and the JSON tab's `pieRows`.
- **Bears on:** DB-PLAN S2 done-when ("the panel renders `DbFetchTopN` from `ErmineSales` at tier `s`"); WP-13.

### F6 [new] — Change the tier under the panel; tier xs equals the in-memory original — **NEVER RUN**

- **Setup:** F5's panel, with `keep` 2.
- **Do:** (1) `scripts/db.sh load sales --tier m` (about 3 s), then save the params file (a re-render). (2) `scripts/db.sh load sales --tier xs` (about 1.2 s), save again. (3) `scripts/db.sh load sales --tier s`, save again.
- **Expect:** each load prints `` load ${c.domain} mssql tier=${p.manifest.tier} seed= `` (`data/src/load/mssql.ts:95`) with `verify=OK` (MEASURED 3.03 s at m and 1.15 s at xs with verify, LOADER.md §2). **Nothing re-renders until you save.** (1) At m the pie shows m's top two of 12 regions. Nobody has read those amounts: check them with `scripts/db.sh sql ErmineSales "SELECT region, SUM(amount) FROM sales GROUP BY region ORDER BY 2 DESC"`. (2) At xs: **north 4,350.75, east 4,175.50, Other 4,155.75** and `metTargets` **2**, the same as the in-memory `core/src/test/resources/doc/FetchTopN.e` (MEASURED equal modulo row order by `TestDbReports` and `TestPreviewDbLive`). (3) Back to F5's numbers.
- **Failure:** the numbers do not change after a save; `db.sh load` hangs at the DDL while the preview is connected (then run **Ermine: Disconnect Database**, and record it: INFERRED possible, never observed). **Paste:** the load lines and the channel's `preview: render` lines.
- **Bears on:** DB-PLAN S2's second done-when half ("the JSON tab shows the same totals SQLite shows for tier `xs`"); D11 tiers.

### F7 [new] — Edit the parameters: `keep` 2 → 3 — **NEVER RUN**

- **Setup:** F6 left the database at tier s.
- **Do:** change `"keep": 2` to `"keep": 3` in the params file and **save**.
- **Expect:** ONE re-render in place, not revealed (B8). The pie has **china 225,449.88, us-south 172,784.89, france 154,111.45, Other 498,748.00**. The Trace view's SQL for `$.fetch[1]` is the same as at `keep` 2: `take (keep q)` runs in Ermine.
- **Failure:** B8's.
- **Bears on:** WP-8 on a DB-backed report.

### F8 [new] — The Trace view: the SQL, rows scanned, db time versus the rest — **NEVER RUN**

- **Setup:** F7's panel (or F5's).
- **Do:** click **Trace** in the panel's toolbar. Open `SQL · ... bytes` under `$.fetch[1]`, click **Copy**, and run the SQL with `scripts/db.sh sql ErmineSales "<paste>"`. Hover over the preview's status bar item. Read the channel's last line.
- **Expect** (the numbers are server-trace's MEASURED `DbFetchTopN {"keep":2}` at tier s, n=1, OBSERVABILITY.md §4; yours will differ): (1) the button, `showTrace = control("Trace", "trace");` (`client/src/host/page.ts:668`), is pressed. (2) The headline, from `` `render ${formatMs(wall)}` `` (`client/src/host/page.ts:330`): `render 51 ms: db 11 ms (22%), 3 queries, 19 rows (399 read) · generation <G>`. (3) The connection line, starting at `c.profile ?? "profile"` (`client/src/host/page.ts:344`): **`sales-mssql (mssql) @ 127.0.0.1 / ErmineSales`**. (4) The phase bar: `db` in blue, then `session`, `eval`, `scan`, and the rest. A segment carries its label only when `sg.pct >= 12 ?` (`client/src/host/page.ts:814`) holds. The legend lists them all; `scan` (~31 ms) is Ermine grouping 388 rows into 8. (5) The table's headers come from `for (const [h, cls] of [["#", "num"], ["relation", ""], ["delivery", "opt"], ["rows", "num"], ["scanned", "num"],` (`client/src/host/page.ts:833`), so `#, relation, delivery, rows, scanned, db, total, dialect, share`. Its rows are `$.fetch[1]` fetched 8 / **388**, `$.fetch[2]` fetched 8 / 8, and `$.children[0].props.pieRows` inline 3 / 3. Under `$.fetch[1]` a note ends `rows; Ermine reduced them to ${formatCount(q.rows)}` (`client/src/host/page.ts:871`), i.e. `the database returned 388 rows; Ermine reduced them to 8`. (6) `SQL · ${formatCount(bytes)} bytes` (`client/src/host/page.ts:881`) opens a grey box with `const copy = el("button", "ermine-trace-copy", "Copy");` (`client/src/host/page.ts:769`). The button then reads `clip.writeText(text).then(() => { button.textContent = "Copied"; },` (`client/src/host/page.ts:750`), or else `button.textContent = "Selected: press Ctrl+C";` (`client/src/host/page.ts:744`). The pasted SQL prints `(388 rows affected)`, equal to the `scanned` cell. (7) The status bar: `return { hidden: false, text: "$(json) Ermine: " + label + suffix, tooltip: tooltip + traceLine, severity: "none" };` (`editor/vscode/src/preview-core.js:2163`) with `return wall === null ? "" : " · " + traceMs(wall);` (`editor/vscode/src/preview-core.js:5644`), i.e. `Ermine: DbFetchTopN.report · 51 ms`. The tooltip's last line is `return "render " + traceMs(tt.wallMs || 0) + ": db " + traceMs(tt.dbMs || 0) + ", " +` (`editor/vscode/src/preview-core.js:5652`), i.e. `render 51 ms: db 11 ms, 3 queries, 19 rows (sales-mssql / ErmineSales)`. (8) The channel has ONE line for the render, `return head + "ok " + traceMs(rt === null ? wall : rt) + " (" + (rt === null ? "" : "server " + traceMs(wall) + ": ") +` (`editor/vscode/src/preview-core.js:5700`), e.g. `preview: render <G> ok <RT> ms (server 51 ms: db 11 ms, 3 queries, 19 rows; scan 31 ms, session 4.5 ms, other 4.8 ms) sales-mssql / ErmineSales`. It contains NO SQL.
- **Failure:** no Trace button (the bundle is stale: `npm run bundle` in `client/`); `no trace: this answer carried none (a server from before DB stage 2 sends none)` (the server is stale); a `scanned` cell that differs from the pasted SQL's row count; any SQL in the channel; the phase bar wider than the panel. **Paste:** the headline, the table as text, and the channel line.
- **Bears on:** the user's observability brief (*"the queries generated, the results scanned, time spent in db vs elsewhere"*); Q-O1..Q-O6 (DECISIONS.md, taken by the orchestrator, NOT by you: say here if you disagree).

### F9 [new] — Disconnect: the 503 banner names the fix; reconnect asks again — **NEVER RUN**

- **Setup:** F8.
- **Do:** **Ermine: Disconnect Database**. Save the params file. Then click the database status bar item and type the password.
- **Expect:** (1) `line: "db: disconnected " + labelText(s.label) + " by the user; the password is forgotten",` (`editor/vscode/src/preview-core.js:7223`), then `() => log("db: the server let the connection go"),` (`editor/vscode/src/extension.js:3603`). The item reads `text: "$(database) " + id + ": not connected"` (`editor/vscode/src/preview-core.js:7286`). (2) The re-render is answered with the server's `private[lsp] val NotConnectedMessage = "not connected"` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2752`), status 503, and the reason `val NotConnected       = "not-connected"` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:3060`) (MEASURED on the wire). The panel's banner, built by `: s.label ? labelText(s.label) + " is " + (s.phase === "connecting" || s.phase === "prompting" ? "still connecting" : "not connected")` (`editor/vscode/src/preview-core.js:7349`), `" (" + why + ') -- run "' + CONNECT_COMMAND_TITLE + '", or click the database item in the status bar',` (`editor/vscode/src/preview-core.js:7354`) and `e.status === 0 ? e.message :` (`client/src/host/index.ts:335`), reads **`503: not connected (sales-mssql (mssql) @ 127.0.0.1 is not connected) -- run "Ermine: Connect Database", or click the database item in the status bar`**, and the document is dimmed. (3) The click asks for the password again (F4's box). After `db: connected ...` the line ends `(trigger ? "; re-sending the last render (" + trigger + ")" : ""),` (`editor/vscode/src/preview-core.js:7163`), i.e. `; re-sending the last render (reconnected)`, and the banner goes.
- **Failure:** a document instead of the 503 after Disconnect; a reconnect with no prompt (the password was not forgotten); no re-render after the reconnect. **Paste:** the `db:` lines and the banner text.
- **Bears on:** Q-S2 (a); A8's "forgotten on Disconnect".

### F10 [new] — A wrong password: auth, forgotten, Retry — **NEVER RUN**

- **Setup:** F9 connected.
- **Do:** **Ermine: Disconnect Database**, then **Ermine: Connect Database**, and type a wrong password. Then click **Retry** and type the right one.
- **Expect:** (1) `line: "db: connect " + labelText(s.label) + " FAILED " + cls + " (" + reason + (forget ? ", password forgotten" : ", password kept") +` (`editor/vscode/src/preview-core.js:7201`), i.e. `db: connect sales-mssql (mssql) @ 127.0.0.1 FAILED auth (connect-auth, password forgotten; attempt 1/3): login failed for <user> @ <host>: SQLServerException: Login failed for user '<user>'. ...`. The message is built by `"login failed for " + p.user.getOrElse("(no user)") + " @ " + hostAndDatabase(p.dialect, p.url)._1 +` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2111`), and the server then scrubs the user and host out of it (MEASURED: `auth`, `kept:false`, 36 ms). (2) An error notification, `return "Ermine: " + labelText(s.label) + ": " + (s.cls || "connect") + ": " + (s.message || "the connect failed");` (`editor/vscode/src/preview-core.js:7294`), with the buttons `const CONNECT_RETRY = "Retry";` (`editor/vscode/src/preview-core.js:6659`) and `const CONNECT_DISCONNECT = "Disconnect";` (`editor/vscode/src/preview-core.js:6660`), shown by `vscode.window.showErrorMessage(text, core.CONNECT_RETRY, core.CONNECT_DISCONNECT).then((choice) => {` (`editor/vscode/src/extension.js:3629`). (3) The item reads `return { hidden: false, text: "$(database) " + id + ": " + (s.cls === "trace" ? "trace is verbose" : s.cls),` (`editor/vscode/src/preview-core.js:7275`), i.e. `sales-mssql: auth`. (4) The panel's banner is `message: connectFailureText(s).replace(/^Ermine: /, "") + ' -- run "' + CONNECT_COMMAND_TITLE + '" to try again',` (`editor/vscode/src/preview-core.js:7308`). (5) **Retry** asks again. The right password connects and re-sends the last render. An `auth` failure is never retried automatically (NEW-2 retries only `unreachable`/`driver` with a held password).
- **Failure:** Retry connects without asking (a rejected password was kept: A8); the password in any line; no Retry button. **Record in the notes** whether `<user> @ <host>` in the notification reads as a defect to you. The prompt names `ermine @ 127.0.0.1`, while the failure scrubs both.
- **Bears on:** A8; Q-S3/Q-S4 (the `auth` class and `connect-auth` reason).

### F11 [new] — Stop the database while connected; the bounded retry brings it back — **NEVER RUN**

- **Setup:** F10 connected. **Rewritten for NEW-2** (extension, 2026-09-25 00:22): a failed `unreachable`/`driver` connect with a held password is retried unattended, and a render's 503 connects once first.
- **Do:** (a) `scripts/db.sh down`, save the params file, and watch the status bar for about 25 s WITHOUT running `up`. (b) Save again (a render), then `scripts/db.sh up` at once, and wait about 20 s. (c) Once (b) has settled, repeat `down`, let the chain run out (about 25 s), run `up`, and save the params file.
- **Expect** (the order of the first two is a race, INFERRED): (1) the server logs `log("preview: the held connection " + (if (a != null) a.profile.id else "") + " is gone (" + reason + ")")` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:2170`), i.e. `... sales-mssql is gone (connection-lost)`, and answers the render 503. (2) The extension logs `line: "db: the server closed the connection of " + labelText(s.label) + " (" + (event.reason || "no reason") + "); reconnecting",` (`editor/vscode/src/preview-core.js:7213`) and connects with the held password: `line: "db: connecting " + labelText(label) + " (" + cause + (needsPassword ? ", password held" : ", no user") + ")",` (`editor/vscode/src/preview-core.js:7116`), i.e. `(disconnected, password held)`. (3) That fails with `unreachable`, password kept, and is retried after `const RECONNECT_DELAYS_MS = Object.freeze([5000, 15000]);` (`editor/vscode/src/preview-core.js:6955`), three attempts in all. Each failure line ends with `"; attempt " + attempt + "/" + RECONNECT_ATTEMPTS +` (`editor/vscode/src/preview-core.js:7202`), e.g. `(connect-unreachable, password kept; attempt 1/3, retrying in 5 s)`. While a retry is armed the item reads `return { hidden: false, text: "$(sync) " + id + ": reconnecting (" + s.retry.attempt + "/" + RECONNECT_ATTEMPTS + ")",` (`editor/vscode/src/preview-core.js:7278`), i.e. **`sales-mssql: reconnecting (2/3)`** and then `(3/3)`. An error notification (NO Retry button) appears for the first failure and for the last one only. After the third failure the item reads `sales-mssql: unreachable` and the panel banner ends `-- run "Ermine: Connect Database" to try again`. (4) In (b) the chain's next attempt finds the server up: `db: connected ...`, and the last render is re-sent, with no click and no prompt. (5) In (c) the chain is over, but the save's 503 first logs `` `preview: render ${mine} answered 503 not connected; connecting once before showing it` `` (`editor/vscode/src/extension.js:2407`), connects without a prompt, and the render draws, with no banner. **Nothing in F11 ever prompts.**
- **Failure:** the render waits the whole `ermine.preview.timeoutSeconds` instead of answering 503 (record the time); any prompt; more than three attempts in one chain, or retries continuing after **Ermine: Disconnect Database**; a banner in (c) although `up` had finished. **Paste:** the channel from `down` on.
- **Bears on:** SERVER.md §6.2 liveness (`isValid` before each render); tracker §7.2's automatic reconnect; NEW-2 (FIXED 00:22, extension; to be recorded as a decision in DECISIONS-S2).

### F12 [new] — Tear-down, and put things back — **NEVER RUN**

- **Setup:** anything above.
- **Do:** **Ermine: Disconnect Database**. In user settings set `"ermine.preview.profile": ""`. *Optional:* `scripts/db.sh unload sales` and then `scripts/db.sh load sales --tier s`. Set `"ermine.preview.target"` back to `panel`.
- **Expect:** with the profile empty, the database item disappears and renders use the in-memory SQLite again. `DbFetchTopN` then fails (there is no `sales` table in memory; the text is not captured), and `FetchTopN.e` renders. `unload` prints `` other-objects=${left[3]} stage-dir=removed `` (`data/src/load/mssql.ts:193`) with `tables=0 views=0 stamp=0`. `scripts/db.sh down --all` would remove the container and the volume, keeping the image, `/load`, `db.env` and `data/out/` (DOGFOOD.md §12).
- **Failure:** the database item stays after the profile is emptied; a render still reaches SQL Server. **Leave ErmineSales at tier s** (or xs, if the `db` gate runs next) and say which one in the notes.
- **Bears on:** D12 (kept until torn down).

### F13 [new, S2f] — Preview the trace as an Ermine report — **NEVER RUN**

- **Setup:** before F12 (for a profile trace) or after it (in-memory). A server rebuilt with `Layout.Trace` (`sbt core/compile core/copyResources`), extension 0.1.18. DOGFOOD.md §13.
- **Do:** with `DbFetchTopN` → `report` rendered, run **Ermine: Preview Render Trace**. Then, with `Doc.TraceReport` picked, run **Ermine: Save Render Trace** twice: answer **Cancel**, then **Replace**.
- **Expect:** (1) no question the first time; the channel line starts `"replaced " : "wrote "` (`editor/vscode/src/preview-core.js:5952`), i.e. `preview: wrote <workspace>/.ermine/preview/Doc.TraceReport/report.params.json with the trace of render <G> ...`. (2) The panel picks `Doc.TraceReport.report` and draws a headline `"Render trace, generation "` (`core/src/test/resources/modules/Doc/TraceReport.e:70`), the caption, two scorecards, the relations table sorted by Total ms, the SQL table, and two coloured charts 320 px tall (S2f-1, fixed 2026-09-25: the page links `javafxwriter.css`; headless `scratch-widget-preview/db/s2f/trace-report-{dark,light}.png`). **Record it if a chart is a black box** (an older extension, or a writers folder without `javafxwriter.css`: the banner then says the style sheets are incomplete). (3) The Save asks `now in that file are REPLACED` (`editor/vscode/src/preview-core.js:5892`); Cancel leaves the file byte for byte; Replace writes the trace of the trace report's OWN render and the panel re-renders from it.
- **Failure:** a write without the question over an existing file; the file carrying any key `Layout.Trace` does not declare (a url, a user, a host); a 400 `cannot decode $.params...` on the render; the panel re-rendering in a loop after Replace.
- **Bears on:** design §3.6 (Q-O4 a), DB programme S2f; WP-11 D6 (the panel's CSS, amended by S2f-1).

---

## Group D — the honest leftovers

**Nothing in this group is a step you run.** D1–D18 are the things a human at a
keyboard **cannot** find out, kept as a list so that nobody later mistakes
silence for evidence. D19 lists the steps above that cost a fixture or a
setting you may not want to bother with. Record D1–D18 in
`tracker/PLAYTEST-RESULTS.md` as **SKIP — not observable**, not as PASS.

**Not observable by any step in this file:**

| # | What cannot be told | Where it would bite |
|---|---|---|
| D1 | Whether `client.stop()` really KILLS a wedged server process or only stops talking to it. The library's behaviour is *external* and its source is unread (project rule) | C30 shows the SYMPTOM (two processes) but not the mechanism; a non-allocating wedge would never go away |
| D2 | Whether a fresh `LanguageClient` emits an initial `Stopped -> Starting` at all | C28 settles it EMPIRICALLY for this VS Code version only — write down what you see |
| D3 | Whether `WorkspaceEdit.createFile({overwrite: false, ignoreIfExists: true, contents})` is an ATOMIC create at the filesystem level. The API is documented; its implementation is not read | the one race that could destroy committed source. The code reads the file back rather than trusting it |
| D4 | Whether VS Code's `contents` option is honoured at all on this version | if it is not, the read-back sees an empty file and writes the text separately — B1 would show the right content either way |
| D5 | Whether `workspace.fs.createDirectory` really is recursive | a first pick in a deep module path |
| D6 | Whether the params file's creation fires `onDidCreate` on the S2 watcher | if it does not, B3 shows ONE render, not two, and the report renders on the next trigger. The extension schedules its own render precisely so this cannot end in nothing |
| D7 | Whether a `.gitignore` written while VS Code is open takes effect in its SCM view without a refresh | B16 reads `git` on the command line instead, which is why it does |
| D8 | That `workspace.fs.readFile` answers `FileNotFound` with that `code` | B13's "no params file" branch |
| D9 | That `stat` answers a size at all, and that a params file over 1 MiB is refused BEFORE it is read | the review MEASURED both sides of the cap over the wire, but the `stat` that now precedes the read is VS Code's |
| D10 | That a params-file read can HANG, which is what the 5-second bound is for | a network filesystem |
| D11 | Cross-window `Memento` visibility: a second VS Code window on the same folder keeps its own wedge mark | two windows, one worktree |
| D12 | Whether VS Code re-reads a relative `$schema` file that CHANGED on disk | **B7 is the closest anyone can get. If it does not, G17 needs its own ticket** |
| D13 | Remote and virtual workspaces: `vscode.Uri.file(fsPath)` discards the scheme and the authority, so the params read and its watcher both point at a local path that is not there | **out of scope, will not work, and nobody has run it either way** (S2 review M7) |
| D14 | A file outside the workspace that changes: `workspace.fs` does not report links there | B19's symlink refusal has no reach outside the folders you opened |
| D15 | The ONE source mutant of twenty-seven that survives the whole unit suite — `installParamsWatcher` returning before it registers anything, and equally a `RelativePattern` rooted at the wrong place | **B9 is the only thing in the world that can observe it.** The other two survivors are 0.1.7's and unchanged: the coalescer clear before an automatic restart, and the restart guard — **C29** is the only thing that can observe those |
| D16 | Whether `bin/ermine-serve` or any non-VS-Code client is affected by any of this | it is not, by construction (**Q18**); nothing here is a server change |
| D17 | Whether VS Code really stops reading WINDOW-scoped settings from `.vscode/settings.json` in a MULTI-ROOT window. Documented and unobserved here — which is exactly why this guide never adds a second folder | if it is true, adding a folder silently disables `ermine.preview.timeoutSeconds`, `ermine.preview.restartAfterStuckSeconds` and `ermine.maxHeap`, and half of Group C would "fail" for a reason that is not the extension's |
| D18 | Whether anyone downstream minds that **the `.vsix` ships NO licence file**: `editor/vscode/package.json` points at `../../LICENSE`, which does not exist — this repository has `LICENSE.md` and `COPYING`. **Not a step, and not a blocker for a private playtest**; it is a packaging ticket for whenever the extension is published | publishing, not playtesting |

**D19 — steps that cost a fixture or a setting you may not want to bother
with.** All are marked OPTIONAL above; SKIP is a fine answer for any of them,
and the notes column is where to say why:

| Step | What it costs |
|---|---|
| **A15–A18** | four settings edits and a window of noise; they only check validation messages |
| **B19** | four symlink setups and a `/tmp/outside` directory |
| **B20** | `chmod -R a-w` on a directory inside your worktree |
| **C19** | an `ermine.maxHeap` change (restarts the server) plus the `WpBlow` fixture |
| **C20**, **C23** | a report that is SLOW but FINISHES — a fixture `tracker/PLAYTEST-SETUP.md` has to provide |
| **C26** | one more wedge cycle, purely to read a number in a sentence |
| **C31** | deleting `target/ermine-classpath` and paying for a full sbt classpath build |
| **B21** | almost nothing — the cheapest optional step here, and one of the five that see a non-object params root |
| **B22-B24** | nothing, except that B23 REPLACES a params file you may have edited. That is what the modal is for; `git checkout` puts it back |
| **B25-B26** | they edit `core/src/test/resources/doc/Sales.e` and leave a stale params file behind. Both are `git checkout`-able, and the step says so |
| **B27** | it copies four `.e` files into the worktree root and writes four `.ermine/preview/` directories. Delete them afterwards |

---

## Appendix 1 — Deviations to read before ticking anything

1. **`$.params.fromDay` is not what a MISSING key answers.** §14's done-when
   says "the tab shows a 400 naming `$.params.fromDay`". MEASURED against a
   real server on a copy of `Sales.e`:

   | what the extension sends | what comes back |
   |---|---|
   | `params: {}` (what WP-7 sends) | `{"status":400,"message":"the required key \"fromDay\" is missing","path":"$.params"}` |
   | `params: null` | `{"status":400,"message":"expected an object (Query), found null","path":"$.params"}` |
   | `params: {"fromDay": 5, ...}` (WP-8's case) | `{"status":400,"message":"expected a date string yyyy-MM-dd, found the number 5","path":"$.params.fromDay"}` |

   The literal `$.params.fromDay` is the path of a key that is PRESENT and
   ill-typed; a missing key is reported at its object's path with the key in
   the message (`Decode.scala:723-725`). So the done-when is met in substance
   — the tab names `fromDay` — and not to the letter, and the letter needs a
   server change (a per-key path for a missing key), which this ticket did not
   make.

2. **WP-7 sends `params: {}`, not `null`**, for the reason in that table: it
   is the shape that names the first missing key, and it is also the shape
   under which a report whose parameters are all optional RENDERS instead of
   being refused.

3. **WP-8 S2 MOVED ONE MEASURED SHAPE, AND IT IS THE `null` ROW OF THE TABLE
   ABOVE.** WP-7 sent `params: null` for "no parameters" and the builder
   turned it into `{}`; at 0.1.8 "no parameters" is spelled `undefined` and
   still becomes `{}`, while a params FILE whose whole content is `null` is
   sent as `null` — which is what a report whose parameter type is a `Maybe`
   wants (`docs/JSON-GUIDE.md:1329-1331`). MEASURED 2026-09-21 against a real
   server: such a file on disk answers `400 "expected an object (Query), found
   null"` for `Sales`, which is the row above, reached now by a file rather
   than by a builder. Nothing about the no-file case changed.

4. **The Q11 trigger is EXACT, and the server changed to make it so.** §3
   step 6 wants a re-render when the picked file is created or changed while
   its last answer was a PLACEMENT 404, and NOT on a `Runner` 404. The wire
   used to give both the same `{ok:false, status:404, message}`, and WP-7's
   first cut approximated the test with "the server never named this file's
   module" — which its review falsified: the module name is a cache the
   pick carries, so Q11's own case (picked, deleted, restored) never fired.
   **That claim has been removed everywhere and is not true of what ships.**
   The user then decided Q15: `lsp/Preview.scala` now carries a
   machine-readable `reason` on the preview's own placement failures
   (`unreadable`, `no-module-header`, `not-ermine-source`,
   `header-deeper-than-path`, `not-placed`, plus `shadowed` on the 409 and
   `not-a-file-uri` on that 400), and a `Runner` 404 carries none. The
   extension tests `status === 404 && typeof reason === "string"`. **A12** and
   **A13** are how you see both halves.

5. **Every render line ends with a params clause, and the old checklist's
   quotes predate it.** Since 0.1.8 `extension.js:2157` writes
   `preview: render <label> (generation N; <reason>; params from <path>)` or
   `… ; empty parameters)`. Wherever the old text quoted a render line without
   that clause (old §1.5, §1.8, §1.11, §2.15, §2.19, §2.21), the clause is
   there in what ships.

6. **Three other quotes were corrected against 0.1.9's source** and the
   corrections are in the steps: the params-refusal `message` ends
   `Nothing was sent to the language server.` (**B11**, **B12**); the recovery
   line `Ermine: the preview recovered` is a four-second **status bar message**
   and not a toast (**C20**); and the offline status bar text carries an icon,
   `$(debug-disconnect) Ermine: preview offline` (**A11**, **C3**).

---

## Appendix 2 — Step map, old id → new id

| Old | New | Old | New | Old | New |
|---|---|---|---|---|---|
| §0 | A1 | 2.15 | C5 | 2.35 | B9 |
| 1.1 | A2 | 2.16 | C6 | 2.36 | B11 |
| 1.2 | A3 | 2.17 | C7 | 2.37 | B12 |
| 1.3 | A4 | 2.18 | C9 | 2.38 | B13 |
| 1.4 | A4 | 2.19 | C8 | 2.39 | B14 |
| 1.5 | A5 | 2.20 | C10 | 2.40 | B18 |
| 1.6 | A14 | 2.21 | C11 | 2.41 | C12 |
| 1.7 | A8 | 2.22 | C4 | 2.41b | C13 |
| 1.8 | A7 | 2.23 | C17 | 2.41c | C14 |
| 1.9 | A12 | 2.24 | C18 | 2.41d | C15 |
| 1.10 | A12 | 2.25 | C32 | 2.42 | B17 |
| 1.11 | A12 | 2.26 | C19 | 2.43 | B1 |
| 1.12 | A12 | 2.27 | C20 | 2.44 | B2 |
| 1.13 | A13 | 2.28 | C21 | 2.45 | B3 |
| 2.1 | A9 | 2.29 | C22 | 2.45b | B3 |
| 2.2 | A10 | 2.30 | C23 | 2.46 | B16 |
| 2.3 | A15 | 2.31 | C24 | 2.47 | B5 |
| 2.4 | A16 | 2.31b | C25 | 2.48 | B6 |
| 2.5 | A17 | 2.31c | C26 | 2.49 | B4, B15 |
| 2.6 | A18 | 2.32 | C27 | 2.50 | B7 |
| 2.7 | C1 | 2.32a | C28 | 2.51 | B20 |
| 2.8 | C1 | 2.32b | C29 | 2.52 | C16 |
| 2.9 | C1 | 2.32c | C31 | 2.52b | B19 |
| 2.10 | C2 | 2.33 | B1 | §3 | Appendix 1 |
| 2.12 | C32 | 2.34 | B8 | "cannot tell you" | Group D |
| 2.13 | C3 | | | | |
| 2.14 | C3 | | | | |

**New steps with no old id:** A6 (invalidation of an importing module), A11
(the status bar's states and tooltips), B10 (a reordered file renders the same
document), B21 (a params type that is not a JSON object), C30 (exactly one
`lsp.Main` after every restart), and all of Group E, E1–E14 (the webview panel,
WP-10 and WP-11; added by WP-10 stage 5). The old §1.7, "there is no panel", is
A8, now scoped to `target: json`.

**Obsolete instructions from the old checklist, deliberately not carried over:**
every "write this module into `/tmp/wp7`" (the fixtures are checked in under
`tracker/playtest/fixtures/`), every **File > Add Folder to Workspace** and
**Remove Folder from Workspace** (a second folder makes the window multi-root
and VS Code then ignores the window-scoped settings this guide sets), and the
old §0 claim that `node_modules` is already in place (the extension is now
installed from `editor/vscode/ermine-lang-0.1.14.vsix`, packaged by WP-10 stage 5; `tracker/PLAYTEST-SETUP.md`
owns that).
