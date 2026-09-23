# Playtest guide: the Ermine preview in VS Code (extension 0.1.10)

**NOTHING IN THIS FILE HAS EVER BEEN RUN BY ANYONE.** Not one step. Nothing in
this repository runs VS Code; every expectation below is READ from
`editor/vscode/src/extension.js` and `editor/vscode/src/preview-core.js`, from
the server's own source, or MEASURED over the wire against a real
`bin/ermine-lsp` with no editor in the loop. Where a line was measured it says
so; where it was only read, that is what "NEVER RUN" on the step means. **Every
step is marked NEVER RUN, and none of the marks is a formality.**

**THIS FILE WAS REWRITTEN IN PLACE, 2026-09-23, as a runnable guide.** The old
checklist's step numbers are kept as aliases in square brackets after each new
id — `B12 [2.38]` — so every reference elsewhere in the tracker (`§2.35`,
`§2.41b`, `§2.45`, `§2.52b`, …) still resolves by searching this file. The old
"deviations" section survives as Appendix 1 and the old "what these steps
cannot tell you" paragraphs as Group D. Nothing was dropped.

## Before you start

| | |
|---|---|
| Setup | **`tracker/PLAYTEST-SETUP.md` is the prerequisite and is written separately. Do all of it before step A1.** It produced: the packaged extension `editor/vscode/ermine-lang-0.1.9.vsix` (gitignored) — **which is 0.1.9 and does NOT contain WP-8 S4 (B22-B27): package 0.1.10 yourself (`cd editor/vscode && npx @vscode/vsce package`) or run from source, because the S4 stage was run with no `npm install`**; eight fixtures, `tracker/playtest/fixtures/WpSpin.e`, `WpChain.e`, `WpBlow.e`, `WpInt.e`, and S4's `WpEnum.e`, `WpMaybe.e`, `WpJson.e`, `WpUnit.e`; two ready-made params files, `tracker/playtest/params/Sales.report.params.json` and `WpSpin.report.params.json`, with `tracker/playtest/params/README.md` saying where to copy each; `tracker/playtest/settings.example.json`; and a server verifier, `tracker/playtest/check-server.py` |
| `Sales` is NOT a fixture | **`Sales.report` is the repository's own `core/src/test/resources/doc/Sales.e`** and stays there — other suites read it. Any step that edits it says how to undo it (`git checkout -- core/src/test/resources/doc/Sales.e`) |
| ONE workspace folder, and keep it that way | **No step needs a second folder.** All four fixtures live inside this worktree. **Do NOT use File > Add Folder to Workspace:** a second folder makes the window MULTI-ROOT, and VS Code then stops reading the three WINDOW-scoped settings — `ermine.preview.timeoutSeconds`, `ermine.preview.restartAfterStuckSeconds` and `ermine.maxHeap` — from `.vscode/settings.json` (documented; unobserved here). Every "add `/tmp/wp7` to the workspace" instruction in the old checklist is obsolete and has been removed. The one step that still wants a report outside every folder (**B18**) copies a fixture to `/tmp/wp7` and deliberately does NOT add it |
| Where you record | **`tracker/PLAYTEST-RESULTS.md`**, in this directory. One row per step id, pre-filled in the order below. Fill in PASS / FAIL / SKIP, one line of what you saw, and anything else in the notes column. **For any FAIL, paste the Ermine output channel's text into a fenced block under the table.** The orchestrator reads that file and acts on it |
| The channel | **Ermine: Show Language Server Output** opens the output channel named **Ermine**. Both the extension's own lines (`preview: …`, `restart: …`, `settings: …`, `client N: …`) and the server's log go to that one channel. Every quoted line below appears there |
| The render tab is UNTITLED and DIRTY | every update is a `WorkspaceEdit`, so the tab always has unsaved changes and closing it offers to save a throwaway render: **Don't Save**. There is no way round it for an untitled document, and it is one of the motivations for WP-10's panel (*external*, not exercised here) |
| 0.1.9 WRITES TO YOUR DISK | it is the first version that does. On the first pick of a report with no params file it creates three files under `.ermine/preview/`. Group B is where you look at them |
| 0.1.10 CAN REPLACE ONE | and **only** through the command **Ermine: Write Params Skeleton**, and **only** after a modal you answer. Nothing automatic overwrites a params file, and nothing in the extension ever deletes one. B22-B26 are those steps |
| Undo | any step that edits a checked-in file says so and says how to undo it. **At the end (A14) `git status --short` should show `.ermine/`, `.vscode/`, `tracker/PLAYTEST-SETUP.md` and `tracker/playtest/` and nothing else** — `.vscode/` is not gitignored here, and the setup agent's files are untracked until the orchestrator commits them. `core/src/test/resources/doc/Sales.e` must be clean |

**The fixtures, one line each.** `WpSpin.e` diverges — it is the wedge, and
**it offers TWO report-typed bindings in the picker, `spin : Int -> Node` AND
`report : Int -> Node` (MEASURED)**, so every step that says "pick `report`"
expects two entries and you pick the second. **`WpChain.e` is a SECOND WEDGE of
a different shape** — a fold over a cyclic list, not an import chain — usable
anywhere a step says `WpSpin`. `WpBlow.e` allocates without bound. `WpInt.e`
renders a small document from an `Int` parameter and is the control: **if
`WpInt` does not render, the trouble is the server or the roots, not the
fixture.** **The other three fixtures offer exactly one binding each.**

The six commands, exactly as `editor/vscode/package.json` spells them:
**Ermine: Preview Report...** (`ermine.previewReport`), **Ermine: Render Report
to JSON** (`ermine.renderReport`), **Ermine: Restart Language Server**
(`ermine.restartServer`), **Ermine: Show Language Server Output**
(`ermine.showOutput`), **Ermine: Reload Modules** (`ermine.reloadModules`),
**Ermine: Toggle Fast Mode** (`ermine.toggleFastMode`).

The settings this guide touches, with their defaults:
`ermine.preview.timeoutSeconds` = `60`,
`ermine.preview.restartAfterStuckSeconds` = `0`,
`ermine.preview.roots` = `[]`,
`ermine.preview.maxDocumentBytes` = `16777216`,
`ermine.maxHeap` = `""`, `ermine.serverPath` = `""`.
`tracker/playtest/settings.example.json` has each of them written out.

### Three open decisions that change what you should see

1. **Q21 (§13 of `tracker/JSON-WIDGET-PLAYGROUND.md`) is OPEN and it is YOURS.**
   The first pick of `Sales.report` writes a skeleton with **today's** dates,
   and `Sales`'s rows all fall in 2026-01..2026-03, so that first render
   answers `ok=false, status=500` — *"an empty relation built from no rows
   carries no columns; give it a header (mkRelationWithHeader#) or a static
   hint"*. **MEASURED twice against a real server.** It is not a defect of the
   step that shows it. Steps **A4**, **B1** and **B4** all point here.
2. **The automatic restart's DEFAULT is the orchestrator's, and you have not
   been asked.** `ermine.preview.restartAfterStuckSeconds` ships at `0` = never,
   *because this file had never been run*. **C22 [2.28]** checks that the
   default changes nothing; **C23–C28** are the only things that can observe the
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

---

## If you only have 30 minutes

Ten steps, in this order. They are the cheapest ten that between them say
whether the loop works at all, whether the disk-writing half works, and
whether the wedge guard closes the loop it was built for. Everything else is
detail on top of these.

| | Step | Why it is in the ten |
|---|---|---|
| 1 | **A1** | the extension activates and the session boots at all |
| 2 | **A3** | the server answers `ermine/preview/reports` and the binding pick is populated **by type** |
| 3 | **A4** | a render reaches a tab — the whole point of WP-7 |
| 4 | **A5** | save → re-render in place, generation 2: the loop is a loop |
| 5 | **B1** | the disk-writing half: three files written, params file opened |
| 6 | **B4** | edit the dates → a **document**. This is the first minute Q21 is about |
| 7 | **B5** | the `$schema` line is not squiggled and a wrong key is (D1 go/no-go) |
| 8 | **B11** | invalid JSON refuses in the tab instead of rendering yesterday's parameters |
| 9 | **C1** | the watchdog fires, the banner appears, the status bar turns orange |
| 10 | **C5** + **C6** | after a restart the wedged report is **held** and you are asked — Q17's loop, closed or not |

If any of 1–4 fails, stop and report: nothing after it means anything.

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
- **Expect, in the tab — AND THIS IS Q21:** on a clean workspace the skeleton written by this very pick carries **today's** dates, and the answer is `ok=false, status=500`, message *"Sales.report produced a document that cannot be encoded: an empty relation built from no rows carries no columns; give it a header (mkRelationWithHeader#) or a static hint"*, path `$.children[1].cells[0][0].props`. **That is expected, it is MEASURED, and it is not this step's defect — it is Q21, which is yours.** If instead no params file could be written you get the WP-7 answer, MEASURED exactly: `{"ok": false, "status": 400, "message": "the required key \"fromDay\" is missing", "path": "$.params", "generation": 1}` — and no `reason` key, because this is the decoder's refusal and not a placement one (read Appendix 1.1 before calling that wrong).
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

- **Setup:** `Sales.report` picked and rendered (A4). **There is no fixture for this** — `WpChain.e` is a second wedge by a different mechanism (a fold over a cyclic list), NOT an import chain, and it imports only stdlib modules. So this step uses a module `Sales.e` really does import: `core/src/main/resources/modules/Json.e` (`Sales.e:34`). Its siblings `Date`, `Layout/Doc`, `List`, `Relation` would do as well.
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

### A8 [1.7] — There is no panel — **NEVER RUN**

- **Do:** look for a webview.
- **Expect:** one editor tab and one status bar item, nothing else. **That is WP-10, and it is not built.**
- **Failure:** anything webview-shaped exists.
- **Bears on:** WP-10 (not built).

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
- **Expect:** **`.ermine/`, `.vscode/`, `tracker/PLAYTEST-SETUP.md` and `tracker/playtest/` and nothing else** — `.vscode/` is NOT gitignored in this worktree, and the setup agent's own files are untracked until the orchestrator commits the prep. **`core/src/test/resources/doc/Sales.e` must be clean:** other suites read it.
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
- **Expect, in the tab:** **the Q21 500.** `ok=false, status=500`, *"an empty relation built from no rows carries no columns; give it a header (mkRelationWithHeader#) or a static hint"* at `$.children[1].cells[0][0].props`. **MEASURED twice. This step PASSES with that 500 in the tab.** B4 is where you fix it.
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

### B4 [2.49 first half; Q21] — Edit the dates, get a document — **NEVER RUN**

- **Setup:** B1 done; the params file open (B2 opened it for you).
- **Do:** change `"fromDay"` to `"2026-01-05"` and `"toDay"` to `"2026-03-17"`, and **save**.
- **Expect:** the SAME tab updates in place and now holds a **document** — `{"kind": "doc", …}`. **MEASURED against a real server: `ok=true`, a 1407-byte document.** The channel logs ONE render line whose reason is `the params file was saved` and whose tail is `params from <…>/report.params.json`.
- **Failure:** still a 500 (then the dates did not reach the server — check the render line's tail says `params from`, not `empty parameters`); or two render lines for one save (the editor's save event and the file watcher both fire and the 150 ms window should collapse them).
- **Bears on:** WP-8 S2/S3; **Q21 — this is the step that shows what option (a) costs the first minute**.

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
- **Expect, renders:** **ONE**, or two identical ones — the file watcher sees our write too, and `scheduleRender` merges the two inside its 150 ms window; outside it you get a second identical render, which is harmless (same session, no boot). **ZERO renders is the defect.** The tab shows the Q21 500 again, because the dates are today's again.
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
   wants (`docs/JSON-GUIDE.md:1295-1297`). MEASURED 2026-09-21 against a real
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
`lsp.Main` after every restart).

**Obsolete instructions from the old checklist, deliberately not carried over:**
every "write this module into `/tmp/wp7`" (the fixtures are checked in under
`tracker/playtest/fixtures/`), every **File > Add Folder to Workspace** and
**Remove Folder from Workspace** (a second folder makes the window multi-root
and VS Code then ignores the window-scoped settings this guide sets), and the
old §0 claim that `node_modules` is already in place (the extension is now
installed from a `.vsix` YOU PACKAGE at 0.1.10 (the checked-in one is 0.1.9); `tracker/PLAYTEST-SETUP.md`
owns that).
