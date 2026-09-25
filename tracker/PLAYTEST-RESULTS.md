# Playtest results: the Ermine preview in VS Code (0.1.14)

## Findings

The first real playtest, 2026-09-23: the user, in a real VS Code, extension
0.1.14 installed, on this worktree.

| id | what | cause | status |
|---|---|---|---|
| **F1** | With `ermine.preview.target` = `panel`, the panel opens and shows, verbatim: *the preview page could not be built: buildPreviewHtml: cspSource "'self' https://*.vscode-cdn.net" contains a character that would change the policy* | `cspSourceProblem` (`editor/vscode/src/preview-core.js`, 0.1.14) refused any space, quote, `;`, `,`, `<`, `>`, `&` or `\`. VS Code's real `webview.cspSource` is `'self' https://*.vscode-cdn.net` (MEASURED by the user): a space-separated list of CSP source expressions, one of them a quoted keyword. Every test used a single bare token (`"vscode-src"`, `"s"`), so no test could see it | **FIXED in 0.1.15, commit pending** (uncommitted in the worktree): each space/tab-separated token must be exactly one CSP source expression (a quoted keyword, a scheme-source, or a host-source); anything else is refused naming the token. The page's CSP for the real value is pinned exactly by a test. Group E needs 0.1.15 |
| **F2** | **Ermine: Preview Report...** on `core/src/test/resources/modules/Doc/SalesReport.e` → `report` (`report : Node`) answers 400 *"Doc.SalesReport.report is not a report: a report must be a function Params -> Node, not Node"* | the runner requires `Params -> Result` (`json/Decode.scala:122-140`, `reportSignature`); the binding picker offers bare `Node` bindings knowingly (`lsp/Definitions.scala:393-397`). `editor/vscode/README.md` listed `Node` as a report type, which was false | **CLOSED 2026-09-24 BY WP-34 (Q27 DECIDED, option (i), the user: *"we should fix SalesReport.e also: currently cant preview it on account `report` binding signature issue"*): the runner treats a `Node`/`Fetch Node` binding as a report with no parameters; `SalesReport.e` unchanged and renders (MEASURED, `scratch-widget-preview/wp34/IMPL-REPORT.md`); not yet seen in VS Code (needs 0.1.16 + a rebuilt server).** HISTORY: **RECORDED, runner not changed.** README corrected (0.1.15). Checklist E1/E2/E9 and 30-minute rows 11 and *re-pick* now use the typed `core/src/test/resources/doc/Sales.e`; **E10 (pie/bar charts) has NO FIXTURE**. **The user's decision is pending (Q27 in `tracker/JSON-WIDGET-PLAYGROUND.md` §13):** (i) the runner treats `Node` as `{} -> Node`; (ii) `SalesReport` gains a parameter and the picker stops offering bare `Node` |
| **F3** | The panel (Group E, `Sales.e` → `report`) shows the tables with a header and one row of `.`, the text grey and small, and the Region table invisible. The user's words: *"I can't see shit in the widgets generated. Text is too light, and it doesn't look like it's populating properly."* | Three causes, measured in a headless Chromium with the real `buildPreviewHtml` and bundles (`scratch-widget-preview/panel-render/DIAGNOSIS.md`, `panel-fix/RESULTS.md`). **(1) Not drawn:** `runTabular` only queues a table, and the legacy page draws it with `ermine_htmlwriter_conf.renderFunction(ermine_htmlwriter)` after `renderPage` (`HTMLWriter.scala` `wrapHeader`). The panel never called it. **(2) Illegible:** the page's text was `--vscode-foreground` (`#9e9e9e` in the user's theme). Writers cells inherit it, so they were 2.2:1 on the `#E9E9E9` stripes, and `common.css` makes text 10px. **(3) Layout:** `Grid` had no CSS and stacked. The writers size each table to the WINDOW's width, so tables in grid cells were drawn over their neighbours. A one-column table (Region) is all row header: the writers gave its scroller the empty main part's 0px height, whatever the timing (after two animation frames, after 500 ms, or with the table alone, all measured 0px) | **FIXED in the client bundle, commit pending** (`client/src/host/page.ts`; the extension is unchanged, so no new `.vsix`). The page calls `renderFunction` once after each render: 8/4/8 rows, and 8/4/8 → 3/4/8 → 8/4/8 over three renders. The document draws on white paper with `#222` text: cells 13.1:1 or better, headers 6.49:1, table text 12px, in dark and light themes. The banner keeps the theme's editor colours. The grid is laid out side by side and wraps under 480px a cell. Each table pair is held inside its cell, and the one-column scroller gets its natural height. Pinned by `(pg-f3-*)` in `client/test/page.test.ts`. **You need only `npm run bundle` in `client/`**. The open panel should reload (the bundle watcher); otherwise re-run the command. **OBSERVED by the user, 2026-09-23** (VS Code 1.139.0, Vue Theme): after the bundle rebuild the panel drew `Sales` with its tables (*"It renders now, the tables show up"*), and it re-rendered on a params-file save and on a `Sales.e` save (*"yup, it updates"*). Whether that reload came from the bundle watcher or from re-running the command is NOT recorded. The review's M-1 is fixed: the page's own error box inside the paper is `#b00020` (7.33:1), not the theme's error red (2.46:1) |
| **F4** | NOT seen by the user: MEASURED headless while building WP-31 (2026-09-23). A `Sales` document rendered into a `display:none` panel logged 12 `TypeError: $(...).find(...).andSelf is not a function` from DataTables `fnDestroy`, and its tables stayed one-row skeletons | A latent WRITERS bug, not the panel's: the writers bundle ships **jQuery 3.4.1** with **DataTables 1.9.4** (and jQuery UI 1.11.4); DataTables 1.9.4's `fnDestroy` calls `$(...).find('*').andSelf()`, and `.andSelf` was deprecated in jQuery 1.8 and REMOVED in 3.0. Two more `.parents(...).andSelf()` calls sit in an edit-mode plugin in the same bundle (READ by the WP-31 review). Any path that reaches `fnDestroy` or those plugin methods throws, in the panel or in the writers' own host | **RECORDED, not fixed** (it belongs to the `ermine-writers` repo: jQuery < 3.0 or jquery-migrate would satisfy it). The panel no longer reaches it: WP-31 lays a hidden document out off-stage instead of `display:none` (`scratch-widget-preview/json-toggle/IMPL-REPORT.md`) |

**Setup fact, not a defect:** the first render showed only the JSON tab because
the copied settings file (`tracker/playtest/settings.example.json` →
`.vscode/settings.json`, `tracker/PLAYTEST-SETUP.md` §6) sets
`ermine.preview.target` to `json` on purpose for Groups A–D. Group E sets it to
`panel`; that is when F1 appeared.

**Who fills this in:** you, while you run `tracker/WP-7-MANUAL-CHECKLIST.md`.
**Who reads it:** the orchestrator. I read this file and act on it — every
FAIL becomes a ticket or a fix, every SKIP becomes a decision about whether
we still need that step, and the open questions at the top of the guide (the
restart default, the U7 `.gitignore` reading, the command's title, the panel's
U1-U7) get asked again with your answers in hand. Q21 is DECIDED (the user,
2026-09-23: fix `Sales.e`, ticket WP-29), and so are Q24 (the user, 2026-09-23:
"Do (a) and (d) now, file (c).") and Q25 (the user, 2026-09-23: typed widget
schemas, "Rewrite it."); their rows below record the answers.

**Date run:** ______  **Extension:** 0.1.14 —
`editor/vscode/ermine-lang-0.1.14.vsix`, repackaged 2026-09-23 from commit `f75b77f8` and INSTALLED (replacing 0.1.4)
(size and file count in `tracker/PLAYTEST-SETUP.md` §3). **Not the
`ermine-lang-0.1.9.vsix` beside it**, which has no params command, no panel and
no writers. Or run from source (`code --extensionDevelopmentPath=editor/vscode`).
**VS Code:** ______  **OS:** ______  **Window:** single-root (if you ever added a
second folder, say so — three settings stop working and several Group C rows
become meaningless)

## How to fill it in

- **Result:** `PASS`, `FAIL`, or `SKIP`. Leave it blank if you did not reach the step.
- **What you saw:** ONE line. If it matched the guide exactly, `as written` is enough.
- **Notes:** anything else — a number you were asked to write down (C28), a
  decision you want to register (B16's U7 reading), a step that was awkward.
- **For every FAIL: paste the Ermine output channel's text** into a fenced block
  under the table, headed with the step id. The channel is **Ermine: Show
  Language Server Output**; select all of it and paste. Without that text a FAIL
  is usually not actionable.
- Steps marked OPTIONAL in the guide are fine to `SKIP`; say why in the notes.

---

## Group A — the core loop

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **A1** | [§0] | Activate; the session boots (`Ermine session ready: …`) |  |  |  |
| **A2** | [1.1] | The file quick pick |  |  |  |
| **A3** | [1.2] | The binding quick pick, populated by type |  |  |  |
| **A4** | [1.3, 1.4] | The render: status bar, untitled tab, the answer (Q21: an EMPTY table, `matched: 0`; a 500 is a FAIL) |  |  |  |
| **A5** | [1.5] | Edit the report's file and save -> generation 2, in place |  |  |  |
| **A6** | [new] | Invalidation of an IMPORTING module (stdlib `Json.e`) |  |  |  |
| **A7** | [1.8] | Render Report to JSON re-renders into the same tab |  |  |  |
| **A8** | [1.7] | Under `target: json`: the JSON tab and NO panel |  |  |  |
| **A9** | [2.1] | Closing the tab does not resurrect it |  |  |  |
| **A10** | [2.2] | The pick is remembered per workspace |  |  |  |
| **A11** | [new] | The status bar's states and tooltips |  |  |  |
| **A12** | [1.9-1.12] | The Q11 placement-404 watcher: away, render, back |  |  |  |
| **A13** | [1.13] | A binding that does not exist: 404 with no `reason` |  |  |  |
| **A14** | [1.6] | Put the fixtures back |  |  |  |
| **A15** | [2.3] | OPTIONAL `ermine.preview.roots` validation |  |  |  |
| **A16** | [2.4] | OPTIONAL `ermine.maxHeap` floor and restart |  |  |  |
| **A17** | [2.5] | OPTIONAL `timeoutSeconds` type check |  |  |  |
| **A18** | [2.6] | OPTIONAL a file with no report-typed binding |  |  |  |

## Group B — params files

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **B1** | [2.43, 2.33] | The first pick writes three files (Q21: the tab shows an empty table; a 500 is a FAIL) |  |  |  |
| **B2** | [2.44] | …and opens the params file without stealing focus |  |  |  |
| **B3** | [2.45, 2.45b] | One render per coalescing window; the second is not a question |  |  |  |
| **B4** | [2.49a] | Edit the dates -> a document with rows (Q21) |  |  |  |
| **B5** | [2.47] | `$schema` not squiggled; a wrong key is (D1 go/no-go) |  |  |  |
| **B6** | [2.48] | Completion offers the keys and the enum values (D3 go/no-go) |  |  |  |
| **B7** | [2.50] | Editing the params TYPE updates the schema file (G17) |  |  |  |
| **B8** | [2.34] | Save the params file: ONE render, in place |  |  |  |
| **B9** | [2.35] | A change from OUTSIDE the editor (the surviving mutant) |  |  |  |
| **B10** | [new] | A reordered file renders the same document |  |  |  |
| **B11** | [2.36] | Invalid JSON refuses in the tab, renders nothing |  |  |  |
| **B12** | [2.37] | An empty file is not `{}` |  |  |  |
| **B13** | [2.38] | Delete the file: a 400 naming the key, said once |  |  |  |
| **B14** | [2.39] | A wrong key earns the server's own 400; no wedge |  |  |  |
| **B15** | [2.49] | A second pick never rewrites the params file |  |  |  |
| **B16** | [2.46] | `git status` shows the params file and NOT the schema (U7) |  |  |  |
| **B17** | [2.42] | A credential-looking key warns once, never blocks |  |  |  |
| **B18** | [2.40] | A report outside every workspace folder |  |  |  |
| **B19** | [2.52b] | OPTIONAL a symlink anywhere on the way refuses |  |  |  |
| **B20** | [2.51] | OPTIONAL a read-only workspace falls back to `{}` |  |  |  |
| **B21** | [new] | OPTIONAL WpInt: a params type that is NOT a JSON object (its sentence CHANGED in 0.1.10) |  |  |  |
| **B22** | [new] | `Ermine: Write Params Skeleton` asks in a MODAL; declining leaves the file |  |  |  |
| **B23** | [new] | …accepting replaces it, refreshes the schema, opens it, re-renders |  |  |  |
| **B24** | [new] | The command with NO params file: no dialog, a create |  |  |  |
| **B25** | [new] | The ORPHAN notice after renaming a binding, once per session |  |  |  |
| **B26** | [new] | The orphan notice's button writes for the CURRENT pick |  |  |  |
| **B27** | [new] | OPTIONAL WpEnum/WpMaybe/WpJson/WpUnit: each non-object root's sentence |  |  |  |

## Group C — the wedge guard and the restart

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **C1** | [2.7-2.9] | Wedge it: banner, orange bar, watchdog answer |  |  |  |
| **C2** | [2.10] | A second render is refused immediately |  |  |  |
| **C3** | [2.13, 2.14] | The server dies and comes back, UNWEDGED pick |  |  |  |
| **C4** | [2.22] | A wedged server that dies by itself does NOT re-render (Q17) |  |  |  |
| **C5** | [2.15] | The Restart button: still no re-render, `held` |  |  |  |
| **C6** | [2.16] | The question, and exactly what it says |  |  |  |
| **C7** | [2.17] | Dismissal is never consent |  |  |  |
| **C8** | [2.19] | Render anyway renders, and wedges again |  |  |  |
| **C9** | [2.18] | Once per restart, never stacked |  |  |  |
| **C10** | [2.20] | Any `.e` save clears the hold; `.md` clears nothing |  |  |  |
| **C11** | [2.21] | With the mark cleared, a restart DOES re-render |  |  |  |
| **C12** | [2.41] | Changing what is SENT clears the hold |  |  |  |
| **C13** | [2.41b] | A re-format while held ASKS instead of rendering |  |  |  |
| **C14** | [2.41c] | Asked ONCE, not once per save |  |  |  |
| **C15** | [2.41d] | A roots change that changes nothing also asks |  |  |  |
| **C16** | [2.52] | A wedged report is never handed a schema request |  |  |  |
| **C17** | [2.23] | The mark survives a window reload, and says restored |  |  |  |
| **C18** | [2.24] | The mark is the CURRENT pick's only |  |  |  |
| **C19** | [2.26] | OPTIONAL `died-mid-render` (WpBlow, maxHeap 256m) — M1 |  |  |  |
| **C20** | [2.27] | OPTIONAL the `{stuck:false}` recovery clear (Q10) |  |  |  |
| **C21** | [2.28] | THE DEFAULT CHANGES NOTHING |  |  |  |
| **C22** | [2.29] | The feature: the automatic restart at the grace |  |  |  |
| **C23** | [2.30] | OPTIONAL a slow render is NOT killed |  |  |  |
| **C24** | [2.31] | Turning it off mid-grace disarms |  |  |  |
| **C25** | [2.31b] | Turning it ON while already wedged ARMS |  |  |  |
| **C26** | [2.31c] | OPTIONAL the floor defers and says so |  |  |  |
| **C27** | [2.32] | No double restart; the user's is never refused |  |  |  |
| **C28** | [2.32a] | The state log; what the FIRST client logs (write it down) |  |  |  |
| **C29** | [2.32b] | The stop that does not come back; two untested glue paths |  |  |  |
| **C30** | [new] | Exactly ONE `lsp.Main` after every restart |  |  |  |
| **C31** | [2.32c] | OPTIONAL restart during the first-run classpath warm-up |  |  |  |
| **C32** | [2.12, 2.25] | Put the settings back |  |  |  |

## Group E — the panel (set `ermine.preview.target` to `panel` first)

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **E1** | [new] | The panel opens BESIDE on `Sales.e` → `report` (F2: not `SalesReport`); the cursor stays in your editor; no JSON tab |  |  |  |
| **E2** | [new] | The typed `Sales` draws: heading, text, three tables, no error box (F2: was `Doc.SalesReport`'s scorecard); no banner, no `preview panel: widget` line. **F3:** on white paper, dark text; every table shows its rows (8, 4 and 8 in the harness's `sales-range` capture), two per grid row |  | **OBSERVED by the user, 2026-09-23** (VS Code 1.139.0, Vue Theme): after the bundle rebuild the panel drew `Sales` with its tables (*"It renders now, the tables show up"*), and it re-rendered on a params-file save and on a `Sales.e` save (*"yup, it updates"*). Whether that reload came from the bundle watcher or from re-running the command is NOT recorded. |  |
| **E3** | [new] | Console: no CSP refusal except at most `tmbllsprite.png`; list any other URL verbatim |  |  |  |
| **E4** | [new] | `400: the key "fromDy" is not allowed here ($.params.fromDy)`; document dimmed |  |  |  |
| **E5** | [new] | Hidden panel + wedge -> shown: the stuck banner. **F1: (a) posts reach a hidden webview / (b) they do not / (c) not determined** |  |  |  |
| **E6** | [new] | The panel's Restart button: restart, then HELD, no re-render; `WpInt.e` put back |  |  |  |
| **E7** | [new] | `bundle:watch` + a `scorecard.ts` edit: ONE reload line, the title changes, no restart |  |  |  |
| **E8** | [new] | Files deleted -> *not built* page; rebuilt -> back. **Folder deleted: (i) page flipped? (ii) rebuild noticed?** |  |  |  |
| **E9** | [new] | `Sales`'s items table draws through the writers' `runTabular`, eight rows, no error box (F2: was `SalesReport`'s three-row table) |  |  |  |
| **E10** | [new] | `Doc/SalesReport.e` → `report`: the bar chart and the pie `Share of sales` draw (fixture restored by WP-34; was NO FIXTURE under F2). Needs 0.1.16 + a rebuilt server |  |  |  |
| **E11** | [new] | OPTIONAL, NO FIXTURE: a style-box click is inert (SKIP unless you wrote a report) |  |  |  |
| **E12** | [new] | Two commands, one panel; close it and re-run: a new one, never two |  |  |  |
| **E13** | [new] | `target: json` = tab only; `both` = tab then panel; `"tab"` refused once by name |  |  |  |
| **E14** | [new] | `writersPath` -> an empty folder: the writers banner, dimmed, legacy error boxes; `""` and a command put it right |  |  |  |
| **E15** | [new, WP-31] | the panel's **JSON** button: under `target: both` its text equals the JSON tab's; no re-render on a click; a save while on JSON re-renders the hidden document once; **Document** shows the tables at once; the choice survives a bundle reload; a window reload's new panel starts in Document |  |  |  |

## Group F — the database (extension 0.1.17; the profile in USER settings; target `both`; walkthrough `tracker/db/DOGFOOD.md`)

**Never paste the password here**, and check any pasted channel text for it first.

| Step | Was | What it checks | Result | What you saw | Notes |
|---|---|---|---|---|---|
| **F1** | [new] | `scripts/db.sh status` → `status OK`, `tls=TRUE`; `db.sh verify sales` → `tier=s seed=42 ... OK` |  |  |  |
| **F2** | [new] | the profile in USER settings; a workspace copy is ignored and named once (`profiles set in workspace settings are ignored (user settings only)`) |  |  |  |
| **F3** | [new] | one folder, the Ermine channel open, target `both` |  |  |  |
| **F4** | [new] | ONE prompt `Password for ermine @ 127.0.0.1 (profile sales-mssql) ...`; `sales-mssql: connecting` → `sales-mssql (mssql) @ 127.0.0.1`; `db: connected sales-mssql (mssql) @ 127.0.0.1 / ErmineSales`; a restart does not prompt, a window reload does |  |  |  |
| **F5** | [new] | `DbFetchTopN` → `report`: keep 0 = one `Other` slice (1,051,094.22); keep 2 = china 225,449.88, us-south 172,784.89, Other 652,859.45; `metTargets` an error box by design, 1 in the JSON tab |  |  |  |
| **F6** | [new] | `db.sh load sales --tier m` then save: new numbers, only after the save; tier xs: north 4,350.75, east 4,175.50, Other 4,155.75, met 2 (= in-memory `FetchTopN`); back to s |  |  |  |
| **F7** | [new] | `keep` 2 → 3: ONE re-render; france 154,111.45 appears, Other 498,748.00 |  |  |  |
| **F8** | [new] | **Trace**: headline `render N ms: db M ms (P%), 3 queries, 19 rows (399 read)`; connection `sales-mssql (mssql) @ 127.0.0.1 / ErmineSales`; `$.fetch[1]` scanned 388, rows 8, "Ermine reduced them to 8"; Copy + `db.sh sql` = 388 rows; status bar `· N ms`; one channel line, no SQL in it |  |  |  |
| **F9** | [new] | Disconnect: `sales-mssql: not connected`; the re-render's banner `503: not connected (... is not connected) -- run "Ermine: Connect Database", ...`; reconnect prompts again and re-sends the render |  |  |  |
| **F10** | [new] | wrong password: `FAILED auth (connect-auth, password forgotten)`; the notification with Retry / Disconnect; `sales-mssql: auth`; Retry prompts. Note whether `<user> @ <host>` in the message bothers you |  |  |  |
| **F11** | [new] | `db.sh down`: 503, `the server closed the connection ... reconnecting`, then the NEW-2 retry chain: `sales-mssql: reconnecting (2/3)` / `(3/3)` at 5 s and 15 s, three attempts, then `unreachable`, no Retry; `up` inside the chain reconnects by itself; after the chain, a save connects once (`connecting once before showing it`) and draws; never a prompt |  |  |  |
| **F12** | [new] | Disconnect, `ermine.preview.profile` = `""`: the database item goes, renders are in-memory again; ErmineSales left at tier ___ |  |  |  |

## Group D — not observable by any step (record as SKIP)

These are here so that nobody later mistakes silence for evidence. `SKIP` is
the right answer for all of them; the notes column is for anything you
happened to notice that bears on one.

| # | What cannot be told | Result | Notes |
|---|---|---|---|
| **D1** | `client.stop()` really killing a wedged server process | SKIP |  |
| **D2** | whether a fresh `LanguageClient` emits an initial `Stopped -> Starting` | SKIP |  |
| **D3** | whether `createFile(..., contents)` is an ATOMIC create | SKIP |  |
| **D4** | whether VS Code's `contents` option is honoured at all | SKIP |  |
| **D5** | whether `workspace.fs.createDirectory` really is recursive | SKIP |  |
| **D6** | whether the params file's creation fires `onDidCreate` | SKIP |  |
| **D7** | whether a new `.gitignore` reaches the SCM view without a refresh | SKIP |  |
| **D8** | that `workspace.fs.readFile` answers `FileNotFound` with that `code` | SKIP |  |
| **D9** | that `stat` answers a size, and the 1 MiB cap is checked before the read | SKIP |  |
| **D10** | that a params-file read can HANG (the 5-second bound) | SKIP |  |
| **D11** | cross-window `Memento` visibility of the wedge mark | SKIP |  |
| **D12** | whether VS Code re-reads a relative `$schema` file changed on disk (G17) | SKIP |  |
| **D13** | remote and virtual workspaces (out of scope, will not work) | SKIP |  |
| **D14** | a file outside the workspace changing; `workspace.fs` reports no links there | SKIP |  |
| **D15** | the surviving mutants, other than through B9 and C29 | SKIP |  |
| **D16** | `bin/ermine-serve` and non-VS-Code clients (Q18) | SKIP |  |
| **D17** | whether a MULTI-ROOT window really stops reading window-scoped settings | SKIP |  |
| **D18** | the `.vsix` ships no licence file (`package.json` points at a missing `../../LICENSE`) | SKIP |  |

---

## Output channel text for every FAIL

One block per failing step, headed with the step id. Delete the example.

### (example — delete)

```
preview: render 1 (generation 1; the report was picked; empty parameters)
Ermine session ready: 129 modules in 11.8s
```

---

## The five open questions, with room for your answer

| | Question | Your answer |
|---|---|---|
| **Q21** | The first pick of `Sales.report` answers a 500 with today's dates (A4, B1, B4). Options recorded neutrally in §13 of `tracker/JSON-WIDGET-PLAYGROUND.md`: **(a)** keep today's dates and accept the 500 until you edit them; **(b)** give `Sales.e`'s relations a header hint so an empty result encodes — which raises the wider question of whether ANY report returning no rows hitting this 500 is an engine limitation deserving its own ticket; **(c)** change the date rule itself | **DECIDED by the user 2026-09-23: "Let's fix Sales.e now, and file a ticket for zero-rows."** `Sales.e` builds `byDay` with `relationWithHeader`, so the first pick renders an empty four-column table (MEASURED, `scratch-widget-preview/q21-sales/`); the engine gap is ticket WP-29 (§14), not scheduled. |
| **Restart default** | `ermine.preview.restartAfterStuckSeconds` ships at `0` = never, only because this file had never been run. After C21–C28, should the default move, and to what? |  |
| **U7 `.gitignore`** | S3 writes only the self-contained `.ermine/preview/.gitignore` and this repository carries `**/.ermine/preview/**/*.schema.json` in its own root `.gitignore` (B16). The alternative — the extension OFFERING to add the line to YOUR root `.gitignore` — is named and not built. Which do you want? |  |
| **Q22 the command's title** | **Ermine: Render Report to JSON** renders into the PANEL under the default target (E12, E13). Keep the title, or rename it (e.g. **Ermine: Render Report**)? A rename changes the palette entry every checklist step names, so it was not done (the WP-10 S2 review's N4) |  |
| **Q23 the panel's U1-U7** | Seven design choices for the panel were TAKEN BY THE ORCHESTRATOR on the WP-10 design review's recommendations; **you were not asked any of them**: U1 a `target` setting, default `panel`, tab kept; U2 `retainContextWhenHidden` on plus a resync; U3 the bundle from the checkout, the writers from a setting with a sibling default; U4 Restart as the panel's only button; U5 no `blob:`; U6 deferred relations refused, not fetched (**taken on a premise that proved FALSE: see Q24**); U7 the extension's tests gate every commit. Which, if any, do you want changed? (E5 and E8 are the steps whose results bear most on U2 and U3) |  |
| **Q24 deferred relations and WP-10's done-when fixture** | U6 (refuse deferred relations, no fetch) was taken on the design review's F2, "the preview never mints a deferred token". **That is false**: `core/src/test/resources/doc/Sales.e:129 (was :116 before the Q21 fix moved it)` asks for `Deferred` itself, and the S1 capture of its render holds a token, so in the panel that table is an error box (E2). WP-10's done-when says "`Sales` renders inline", which Sales as written cannot meet. Options: **(a)** keep the refusal and make an inline fixture the done-when (`Doc/SalesReport.e`, E2/E9/E10); **(b)** a preview-side override that forces inline delivery, so Sales's deferred table arrives inline; **(c)** build the fetch message pair U6 deferred (the panel asks the extension, the extension asks the server); **(d)**, with any of these, register `heading`/`text` renderers so Sales's other two boxes draw. Which? | **DECIDED by the user 2026-09-23: "Do (a) and (d) now, file (c)."** (a) the panel keeps refusing deferred relations and WP-10's done-when is the inline fixture `Doc/SalesReport.e` (E2/E9/E10); (d) `heading` and `text` renderers are built in the client, so `Sales`'s heading and text draw (E2's Sales sub-step); (c) the fetch message pair is ticket WP-30 (§14), not built; (b) not chosen. MEASURED while building: `Sales`'s three tables are all boxes (a bare relation is not `TableProps`), so the items table's box says `its props are invalid`, not the refusal. |
| **Q25 which report carries a typed deferred table** | Found by the Q24 review, MEASURED: `Sales.e`'s three tables are all error boxes in the panel, because it hands `table` a bare relation, which the client's `TableProps` schema refuses before any fetch. That is DELIBERATE (`docs/JSON-GUIDE.md:1090-1093` (at b7faef3a): `Sales` exercises the runner, not the client; `Doc/SalesReport.e` is the typed report), and `Sales` is the only fixture using `Deferred`, so WP-30 (the fetch pair) has nothing it could make draw. Options (§13 of `tracker/JSON-WIDGET-PLAYGROUND.md` has the costs): **(A)** rewrite `Sales.e`'s tables typed; **(B)** a new typed fixture with a deferred `TableProps.rows`; **(C)** the client's `table` also accepts a bare relation; **(D)** leave it until WP-30 is scheduled. Which? | **DECIDED by the user 2026-09-23: "I'm pretty sure I want typed widget schemas in the typescript rather than matching runtime ermine values fallibly", then "Rewrite it."** Option (A), plus the principle that the client's widget vocabulary is the TYPED one, its zod GENERATED from `Layout.Widgets.*`; the client never accepts bare runtime values. BUILT: `Sales.e`'s body is typed (new `Layout.Widgets.Heading` and `Layout.Widgets.Text`, three `tabular` tables), the hand-written `heading`/`text` schemas are gone, and `Sales` draws in the panel with NO error box (E2's Sales sub-step, rewritten). Its items table is INLINE -- a typed table cannot force deferral -- so WP-30 still needs a fixture (Q26, below). The runner's untyped shape is `core/src/test/resources/doc/SalesRaw.e` |
| **Q26 how a typed deferred table should exist (WP-30's fixture)** | Found by the Q25 review, MEASURED: a typed `table`'s `rows` cannot be `Deferred`, and the preview's request asks inline, so no typed report shows a deferred table in the panel. Options: (a) change the Table widget's contract so a report can force deferral; (b) let the preview's request ask for deferred delivery for a chosen report (the opposite of Q24 (b), which forced inline and was not chosen); (c) a test-only untyped fixture shaped like `TableProps`; (d) no manual fixture until WP-30 is scheduled. Details: §13 of `tracker/JSON-WIDGET-PLAYGROUND.md` |  |

## Anything else

Free text. What surprised you, what was tedious, what you would want the
preview to do that it does not.
