# WP-7 manual checklist: the preview loop in VS Code, with no panel

**NOTHING BELOW HAS BEEN RUN BY ANYONE.** Nothing in this repository runs VS
Code, and the agent that built WP-7 did not install, package or load the
extension into any editor. Every step here is written from the code and from
two instruments that drove a REAL `bin/ermine-lsp` over the wire without an
editor (`wp7-instrument.js`, `wp7-stuck.js` in the build session's
scratchpad); what those measured is quoted where it decides what you should
see. **`wp7-stuck-4.log` ends "8 ok, 1 failed" and the failure is the
INSTRUMENT'S OWN WRONG EXPECTATION, not the extension's behaviour**: it
asserted that a transition into `Running` asks for a re-render, having never
sent a `Stopped` edge before it; the extension re-renders on a restart
(Stopped then Running) and deliberately not on the first `Running` of a
session, which is what the unit test "the first Running of a session costs no
render" pins. The instrument was not re-run for it -- that would cost another
JVM for an assertion a pure test already covers. The VS Code half -- the quick picks, the untitled tab, the status bar,
the notification, the file watcher -- is unverified.

This checklist ticks §14's WP-7 done-when and the two behaviours the ticket
adds to it (stuck/recover, offline/online), and -- since 2026-09-20 --
**WP-22's wedge guard (§2.15-2.27), which is equally unrun**: it was built
after this file was written, its pure half is unit-tested, and not one of its
editor steps has been observed by anyone either.

## 0. Before you start

| | |
|---|---|
| The extension | `editor/vscode` in this worktree, version **0.1.6** (0.1.5 plus WP-22's wedge guard, §2.15-2.27) |
| `node_modules` | **Already there.** The build session copied it from `/home/dmitry/research/ermine/ermine-scala/editor/vscode/node_modules` (there is no network here, and it is gitignored, so it is in neither `git status` nor the commit). If it goes missing, copy it again the same way |
| The server | `target/ermine-classpath` already exists here, so the first start does **not** shell out to sbt |
| Do NOT package or install | this is an Extension Development Host session; nothing touches your installed 0.1.4 |
| The render tab is UNTITLED and DIRTY | every update is a `WorkspaceEdit`, so the tab always has unsaved changes and closing it offers to save a throwaway render: **Don't Save**. There is no way round it for an untitled document, and it is one of the motivations for WP-10's panel (*external*, not exercised here) |

Load it from the worktree, without publishing anything:

```sh
code --extensionDevelopmentPath=/home/dmitry/research/ermine/ermine-scala-wt-widget-preview/editor/vscode \
     /home/dmitry/research/ermine/ermine-scala-wt-widget-preview
```

Open any `.e` file to activate the extension (the two preview commands also
activate it on their own). Then open **Ermine: Show Language Server Output** --
the **Ermine** output channel is where every line quoted below appears -- and
wait for the status bar to read `Ermine` (about 13 s: the session boot).

## 1. The done-when

| # | Step | What you should see |
|---|---|---|
| 1.1 | Run **Ermine: Preview Report...** | a file quick pick; the active editor's `.e` file is first, the rest are the workspace's `**/*.e` sorted by name, with the workspace-relative path as the description |
| 1.2 | Type `Sales` and pick `core/src/test/resources/doc/Sales.e` | a second quick pick listing **`report`** with the description **`Query -> Node`**, and nothing else above the last entry. MEASURED over the wire: `ermine/preview/reports` answers `module = "Sales"`, `reports = ["report : Query -> Node"]` |
| 1.3 | Pick `report` | the status bar (right) reads `Ermine: Sales.report`; a render starts (`$(sync~spin)`) and an **untitled JSON tab** opens beside your editor |
| 1.4 | Read the tab | MEASURED, this exact answer: `{"ok": false, "status": 400, "message": "the required key \"fromDay\" is missing", "path": "$.params", "generation": 1}` -- and no `reason` key, because this is the decoder's refusal and not a placement one. **READ THE DEVIATION IN §3 BELOW**: the done-when's literal `$.params.fromDay` is not what the server sends for a MISSING key -- it names `fromDay` in the message and `$.params` in the path |
| 1.5 | Edit `core/src/test/resources/doc/Sales.e` -- add a comment line -- and SAVE | the same tab updates **in place**: no second tab, no restart, and it is NOT pulled in front of the file you are editing (only the two commands reveal it). The Ermine channel shows one line, `preview: render Sales.report (generation 2; invalidated: Sales)`. MEASURED over the wire: the save produces `ermine/preview/invalidated {"modules":["Sales"]}` |
| 1.6 | Undo the edit | `git checkout -- core/src/test/resources/doc/Sales.e` when you are done; it is a test resource other suites read |
| 1.7 | Look for a panel | there is **no webview**: one editor tab and one status bar item, nothing else. That is WP-10 |
| 1.8 | Run **Ermine: Render Report to JSON** | the SAME tab is updated again; the channel logs `preview: render Sales.report (generation 3; Ermine: Render Report to JSON)` |
| 1.9 | **The Q11 watcher.** With `Sales.report` picked and rendered, move the file away: `mv core/src/test/resources/doc/Sales.e /tmp/Sales.e.away` | nothing happens yet -- the extension re-renders on a save, not on a delete |
| 1.10 | Run **Ermine: Render Report to JSON** | the tab shows the placement 404: `{"ok": false, "status": 404, "message": "cannot read Sales.e", "reason": "unreadable", "generation": N}`. The `reason` key is the point: it is what says the PREVIEW refused the file, not the runner. The channel logs `preview: the pick cannot be placed (unreadable); watching <path> for it to come back` |
| 1.11 | Move it back: `mv /tmp/Sales.e.away core/src/test/resources/doc/Sales.e` | **the tab re-renders BY ITSELF within a second or two**, back to the 400 of step 1.4, with no command and no restart. The channel logs `preview: render Sales.report (generation N+1; the picked report's own file appeared or changed after a placement 404)` |
| 1.12 | What failure looks like | the tab stays on the 404 and the channel logs no new render. Two causes worth separating: the server is older than Q15 and sends no `reason` (the answer in 1.10 has no `reason` key -- the extension then deliberately never triggers), or VS Code's watcher did not report the creation, which happens for a file outside every workspace folder (§10, *external*, not exercised here). A **Ermine: Render Report to JSON** always recovers it by hand |
| 1.13 | A binding that does not exist: pick `Sales.e` again and type `reprot` | the tab shows a 404 with **no `reason` key** (it is the runner's: the module loaded fine). Moving the file away and back does NOT re-render here -- `invalidated` owns this case, and one save must not render twice |

## 2. The rest of the ticket

| # | Step | What you should see |
|---|---|---|
| 2.1 | Close the JSON tab, then **Ermine: Render Report to JSON** | a new tab opens; the old one is not resurrected |
| 2.2 | Close and reopen the window, then **Ermine: Render Report to JSON** without picking | it renders `Sales.report` straight away: the pick is remembered per workspace (`workspaceState`) |
| 2.3 | Set `"ermine.preview.roots": ["not/a/place"]` in the workspace settings | the channel logs nothing wrong (a relative root is resolved against the workspace folder), and the next render still works -- the report's own tree is inferred. Set `["   "]` instead and a warning notification names the empty entry and the root is NOT sent |
| 2.4 | Set `"ermine.maxHeap": "16m"` | a warning names the 64m floor and the server keeps its own 2g. Set `"2g"` and the server RESTARTS (the setting is `-Xmx`, fixed at process start) |
| 2.5 | Set `"ermine.preview.timeoutSeconds": "60"` (a string) | the channel logs `settings: ermine.preview.timeoutSeconds is a whole number of seconds, not a string` and the value is not sent |
| 2.6 | **Ermine: Preview Report...** on a file with no report-typed binding | the binding pick offers only `$(edit) Type a binding name…`; typing `report` picks it anyway and the render answers a 404 or a 400, which the tab shows |

### Stuck, and recovery

The watchdog fires on an evaluation that does not finish. To make one:

1. write this module into a directory of your own (NOT into the checkout),
   say `/tmp/wp7/WpSpin.e`. **It is exactly the fixture the instrument wedged
   a real server with**, so it loads and it diverges; the obvious
   `spin n = spin (n + 1)` does NOT work with these imports (`unknown
   operator +`, measured):

   ```
   module WpSpin where

   import Builtin
   import Int
   import Layout.Doc

   spin : Int -> Node
   spin n = spin n

   report : Int -> Node
   report n = spin n
   ```

2. set `"ermine.preview.timeoutSeconds": 5`;
3. add `/tmp/wp7` to the workspace (**File > Add Folder to Workspace**) so the
   file picker can see it, or open the file and use it as the active editor;
4. **Ermine: Preview Report...** -> `WpSpin.e` -> `report`.

| # | What you should see |
|---|---|
| 2.7 | after ~5 s: an ERROR notification, `Ermine: evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that evaluation ever finishes; if it does not, restart the language server -- run "Ermine: Restart Language Server" (ermine.restartServer)`, with a **Restart Language Server** button |
| 2.8 | the status bar turns orange and reads `Ermine preview: stuck` |
| 2.9 | the tab shows the watchdog's own answer. MEASURED over the wire, both edges: the answer is `{"ok":false,"status":500,"message":"evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that evaluation ever finishes; if it does not, restart the language server -- run \"Ermine: Restart Language Server\" (ermine.restartServer)","generation":1,"stuck":true}` and the notification is `ermine/preview/stuck {"stuck":true,"message":<the same text>,"seq":1}`. The ANSWER arrived first in every run, which is why the extension does not derive the state from the order |
| 2.10 | run the render again: it is refused immediately (not queued), with `"stuck": true` and its own generation echoed. MEASURED: the second render came back `"generation":2, "stuck":true` with the same text |
| 2.11 | press **Restart Language Server**: the client stops and starts, the status bar goes through `Ermine: preview offline` and back, and the preview is no longer stuck. The `seq` high-water mark is reset on the way, so the fresh server's `seq: 1` is not ignored -- the failure this prevents is a restarted server whose stuck banner never appears again |
| 2.12 | set `timeoutSeconds` back to `60` and re-pick `Sales.report` |

**A wedged server exits by itself about two minutes after the fire** (the
loop reaches `-Xmx`), so if you wait instead of restarting you will see the
client restart it on its own -- also a valid way to see 2.11's transition.

### Offline

| # | Step | What you should see |
|---|---|---|
| 2.13 | with `Sales.report` picked and rendered, kill the server process (`pkill` is not the way -- find the `java ... lsp.Main` child of the extension host and kill that pid) | the status bar reads `Ermine: preview offline` and the tab keeps its last document |
| 2.14 | the client restarts it (up to 5 times in 3 minutes, `vscode-languageclient`'s own policy) | the channel logs `preview: the language server is running again` and then a render of the last pick, without you touching anything |

### The wedge guard (WP-22) -- NEVER RUN BY ANYONE, like everything above

**WHAT THESE STEPS ARE FOR.** Before WP-22, a report that wedged the server
was re-rendered *by the restart that the wedge caused* -- and the **Restart
Language Server** button in our own stuck notification took the same path, so
the one remedy offered during a wedge was itself a loop trigger (§13's Q17,
READ from the code and unobserved). The extension now keeps ONE mark for the
current pick and asks before re-rendering it. **The decision is unit-tested
(`npm run test:preview`, 67 tests); the ARRIVAL of every editor event below
is unobserved, and these steps are the only thing that can observe it.**

Use the same `WpSpin` fixture and `"ermine.preview.timeoutSeconds": 5` as
§2.7-2.12 above, and start from a wedged preview. §2.26 and §2.27 need a
different setup and say so in the step.

| # | Step | What you should see |
|---|---|---|
| 2.15 | With `WpSpin.report` wedged (the ERROR notification of 2.7 is on screen), press its **Restart Language Server** button | the client stops and starts as in 2.11 -- and then **NOTHING RENDERS**. The status bar reads `$(warning) Ermine preview: held` (orange), and its tooltip names the report and the reason. The Ermine channel logs `preview: remembering that WpSpin.report wedged the preview (watchdog)` when the mark is set, then `preview: HELD — Ermine: WpSpin.report wedged the preview: …` and **no** `preview: render …` line |
| 2.16 | Read the notification that appears with it | ONE non-modal WARNING (not an error, not a modal): `Ermine: WpSpin.report wedged the preview: the watchdog fired and the server did not come back. Nothing has changed since, so it was NOT re-rendered automatically.` with two buttons, **Render anyway** and **Not now** |
| 2.17 | Press **Not now**, or dismiss it with Escape, or ignore it until it times out | the channel logs `preview: still held (Not now)` or `preview: still held (the question was dismissed)`. The status bar STAYS `held`; the mark is not cleared. **Dismissal is never consent** |
| 2.18 | Restart a second time from the palette (**Ermine: Restart Language Server**) -- NOT by clicking the preview status bar item, which runs the picker and would clear the mark | you are asked again -- once per restart -- and still nothing renders by itself. If the first question is still on screen the channel logs `preview: the question is already on screen; not asking again` instead of stacking a second one |
| 2.19 | Now press **Render anyway** | the channel logs `preview: the wedge mark is cleared (the user asked for this render)` and then `preview: render WpSpin.report (generation N; Render anyway)`, the tab is revealed, and after ~5 s **it wedges again** -- the report has not been fixed. That is the point: the guard asks, it does not decide |
| 2.20 | Edit `/tmp/wp7/WpSpin.e` (add a comment line) and SAVE, while the status bar reads `held` | the channel logs `preview: the wedge mark is cleared (an Ermine source file was saved)` and the status bar leaves `held`. **Any `.e` save clears it**, deliberately: while the server is dead nothing sends `didChangeWatchedFiles`, so no `invalidated` can cover the window in which you fix the loop. A save of a `.md` or a `.json` clears nothing |
| 2.21 | With the mark cleared, restart the server again | the last render IS re-sent, exactly as §2.11 and §2.14 describe. The channel logs `preview: render WpSpin.report (generation N; the language server restarted)` |
| 2.22 | **The automatic path, no button.** Wedge it again and then WAIT instead of restarting (about two minutes at the default heap, §2.5) | the server exits at `-Xmx`, `vscode-languageclient` restarts it, and the tab does **NOT** re-render: the same `held` status bar and the same one question. This is the loop Q17 named, and this step is the only thing that can show it was closed |
| 2.23 | **The mark survives a window reload.** While `held`, run **Developer: Reload Window** | after activation the channel logs `preview: remembered WpSpin.report` AND `preview: a wedge mark was restored from the last session (watchdog)` -- a RESTORE line, deliberately not the line a fresh wedge prints -- and the status bar reads `held` again: the mark is mirrored in `workspaceState` beside the pick. Nothing renders (activation never renders), so you are not asked until the next restart |
| 2.24 | **The mark is the CURRENT pick's only.** While `held`, run **Ermine: Preview Report...** and pick `Sales.report` | the channel logs `preview: the wedge mark is cleared (the pick changed)`; `Sales.report` renders immediately (picking IS consent) and a later restart re-renders it without a question |
| 2.25 | Set `"ermine.preview.timeoutSeconds"` back to `60` | |
| 2.26 | **THE `died-mid-render` CASE, AND THE ONLY STEP THAT CAN OBSERVE M1.** Every step above runs at `timeoutSeconds: 5`, so the watchdog always wins and the mark is always set by the stuck edge. To get the OTHER reason, starve the heap instead: set `"ermine.maxHeap": "256m"` (the server restarts), set `"ermine.preview.timeoutSeconds": 600` so the watchdog CANNOT fire first, and render a report that allocates without bound -- §2.5's `WpBlow` shape, MEASURED there as exit code 3 at 8.6 s with no watchdog fire | the JVM dies mid-render: **no** stuck notification and **no** `Ermine preview: stuck`, but the channel logs `preview: render N was lost with the connection (...)` and/or the `Stopped` edge, then `preview: remembering that WpBlow.report wedged the preview (died-mid-render)`. After the restart the tab does **NOT** re-render, the status bar reads `held`, and the question names *…was still rendering when the language server stopped*. **This is the case the guard would lose if the mark depended on which of the two the library delivers first** (WP-22 review M1): the extension now marks from BOTH, and `guardReduce`'s SET is idempotent, so you should see exactly one mark however the race falls. Put `ermine.maxHeap` back to `""` afterwards |
| 2.27 | **THE `{stuck:false}` RECOVERY CLEAR, which is the load-bearing one.** Wedge a report that is SLOW rather than infinite: set `"ermine.preview.timeoutSeconds": 5` and render something that takes ~30 s (a large fold, not a loop). The watchdog fires at 5 s and the preview is marked stuck; then the job FINISHES | the channel logs `preview: no longer stuck`, the toast `Ermine: the preview recovered`, `preview: the wedge mark is cleared (the preview recovered: the wedged job returned)`, and an automatic re-render with reason `the preview recovered`. **Without this clear a slow report would be held for ever** -- a 300 s scan under a 60 s watchdog is the real case (§13's Q10) -- and the status bar must leave both `stuck` and `held`. A restart after it re-renders without a question |

**THE HOLES TO KNOW WHILE TICKING THESE**, each of them a design decision
rather than a bug: a second VS Code window on the same folder keeps its own
mark (per extension host; cross-window `Memento` visibility is *external* and
unverified), `bin/ermine-serve` and every non-VS-Code client are unprotected
(§13's Q18), and "it didn't change" is a PROXY -- the two signals used are the
server's own `invalidated` and any `.e` save, and both err towards asking
less. **WP-22(c) IS NOT BUILT**: nothing here kills the server on your behalf,
so the wedged process still dies by itself at `-Xmx` (or when you press
Restart), and there is no `ermine.preview.killAfterStuckSeconds` setting to
find.

## 3. Deviations to read before ticking anything

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
   -- the tab names `fromDay` -- and not to the letter, and the letter needs a
   server change (a per-key path for a missing key), which this ticket did not
   make.

2. **WP-7 sends `params: {}`, not `null`**, for the reason in that table: it
   is the shape that names the first missing key, and it is also the shape
   under which a report whose parameters are all optional RENDERS instead of
   being refused.

3. **The Q11 trigger is EXACT, and the server changed to make it so.** §3
   step 6 wants a re-render when the picked file is created or changed while
   its last answer was a PLACEMENT 404, and NOT on a `Runner` 404. The wire
   used to give both the same `{ok:false, status:404, message}`, and WP-7's
   first cut approximated the test with "the server never named this file's
   module" -- which its review falsified: the module name is a cache the
   pick carries, so Q11's own case (picked, deleted, restored) never fired.
   **That claim has been removed everywhere and is not true of what ships.**
   The user then decided Q15: `lsp/Preview.scala` now carries a
   machine-readable `reason` on the preview's own placement failures
   (`unreadable`, `no-module-header`, `not-ermine-source`,
   `header-deeper-than-path`, `not-placed`, plus `shadowed` on the 409 and
   `not-a-file-uri` on that 400), and a `Runner` 404 carries none. The
   extension tests `status === 404 && typeof reason === "string"`. Steps
   1.9-1.13 above are how you see both halves.
