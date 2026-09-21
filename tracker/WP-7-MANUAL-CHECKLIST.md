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
editor steps has been observed by anyone either. **Since 2026-09-21 it also
carries WP-22(c)'s automatic restart (**§2.28-2.32c, TEN steps**), which is
OFF by default (`ermine.preview.restartAfterStuckSeconds` = 0) precisely
because none of these steps has ever been run -- §2.28 is the step that
checks the default changes nothing, and the other nine are the only things
that can observe the feature at all.**

## 0. Before you start

| | |
|---|---|
| The extension | `editor/vscode` in this worktree, version **0.1.7** (0.1.6 plus WP-22(c)'s automatic restart, §2.28-2.32c, which is OFF by default) |
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
(`npm run test:preview`, 96 tests as of 0.1.7); the ARRIVAL of every editor
event below is unobserved, and these steps are the only thing that can
observe it.**

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

### The automatic restart (WP-22(c), 0.1.7) -- NEVER RUN BY ANYONE

**WHAT THESE STEPS ARE FOR.** A wedged render used to end only when the JVM
hit `-Xmx` -- MEASURED at about two minutes after the watchdog fires, with the
heap thrashing meanwhile -- and a wedge that allocates nothing, or a preview
thread that is BLOCKED, never ended at all. The extension can now end it
itself: `ermine.preview.restartAfterStuckSeconds` seconds after the preview
goes stuck it stops and restarts its own language client, through the same
`restart(context)` the **Restart Language Server** button uses. **THE DEFAULT
IS 0 = NEVER**, and it is 0 *because this checklist has never been run*: the
design review advised default OFF until a human has seen it work, the user
confirmed the feature and has NOT been asked about the default, and the
orchestrator will ask once §2.28-2.32c have been ticked. Nothing here is a
server change; `bin/ermine-serve` and every non-VS-Code client still get
nothing (§13's Q18).

| # | Step | What you should see |
|---|---|---|
| 2.28 | **THE DEFAULT CHANGES NOTHING.** Leave `ermine.preview.restartAfterStuckSeconds` unset (or 0), set `"ermine.preview.timeoutSeconds": 5`, and wedge `WpSpin.report` as in §2.7 | exactly §2.7-2.12's behaviour and not one line more: the stuck notification's text is the SAME sentence as 2.7 with **nothing** appended about a restart, the status bar tooltip likewise, and the channel logs no `preview: the language server will be restarted in …` line. The server still dies by itself at `-Xmx` about two minutes later. **If anything restarts here, the default is not what this document says it is** |
| 2.29 | **THE FEATURE.** Set `"ermine.preview.restartAfterStuckSeconds": 20` with `"ermine.preview.timeoutSeconds": 5` still in place, and wedge `WpSpin.report` again | at ~5 s the stuck notification reads, IN FULL AND WITH NO WORDS ELIDED (quote it here so this step can catch a run-on -- review N1 -- the server's own message ends `(ermine.restartServer)` with no full stop and ours is joined onto it): `Ermine: evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that evaluation ever finishes; if it does not, restart the language server -- run "Ermine: Restart Language Server" (ermine.restartServer). You do not need to do that by hand: the language server will be restarted automatically in 20 s unless the render comes back. Set ermine.preview.restartAfterStuckSeconds to 0 to stop that.` -- **one full stop before "You do not need"**, and the last two sentences also on the status bar tooltip's own line; the channel logs `preview: the language server will be restarted in 20s unless the preview recovers (…)`. At ~25 s the channel logs `preview: RESTARTING the language server — the preview has been stuck for 20 s (ermine.preview.restartAfterStuckSeconds = 20; WpSpin.report is held)`, the status bar goes through `Ermine: preview offline` and comes back reading `$(warning) Ermine preview: held` -- **the tab does NOT re-render** and the §2.16 question appears instead, exactly as it does after a hand-pressed restart. **The whole incident is ~25 s instead of ~2 minutes at `-Xmx`** |
| 2.30 | **A SLOW RENDER IS NOT KILLED.** Keep the grace at 20 and `timeoutSeconds` at 5, and render something that takes ~10 s but FINISHES (a large fold, not a loop -- §2.27's fixture shape) | the watchdog marks it stuck at 5 s and the notification says a restart is coming, and then the job returns: the channel logs `preview: no longer stuck`, `preview: the automatic restart is disarmed (the wedged render came back (ermine/preview/stuck {stuck:false}))` and an automatic re-render with reason `the preview recovered`. **NO restart happens.** This is why there is a grace at all -- without the disarm a 300 s scan under a 60 s watchdog would be killed for being slow (§13's Q10) |
| 2.31 | **TURNING IT OFF MID-GRACE DISARMS.** Wedge `WpSpin.report` with the grace at 20, and within those 20 seconds set `ermine.preview.restartAfterStuckSeconds` back to `0` | the channel logs `preview: the automatic restart is disarmed (ermine.preview.restartAfterStuckSeconds was set to 0)` and **nothing restarts** -- the status bar stays `stuck` and the server dies by itself at `-Xmx` as before. Editing the setting to a different NON-ZERO value instead re-arms it at the new value, counted from that moment (the channel says so) |
| 2.31b | **TURNING IT ON WHILE ALREADY WEDGED ARMS (review D1).** With the setting at its default `0`, wedge `WpSpin.report` and leave it wedged; then set `ermine.preview.restartAfterStuckSeconds` to `20` | the channel logs `preview: the language server will be restarted in 20s unless the preview recovers (ermine.preview.restartAfterStuckSeconds was turned on while the preview was stuck)` and the restart happens ~20 s later, exactly as in 2.29. **This is the likeliest moment anyone touches this setting** -- they reach for it because the preview is wedged -- and the first build did nothing at all here, because it waited for a rising edge that was already in the past |
| 2.31c | **THE FLOOR DEFERS, IT DOES NOT CANCEL, AND SAYS SO (review D2, and the delta review's M1).** Set `"ermine.preview.timeoutSeconds": 5` and the grace to `5`, wedge it, let the restart happen, press **Render anyway**, and let it wedge a second time | the second notification does NOT say 5 s: it says something like `…restarted automatically in 27 s unless the render comes back. It is not before 27 s, because the language server was restarted less than 30 s ago and restarts are limited to one every 30 s (you asked for 5 s).` -- the number is 30 minus however long the second wedge took to arrive -- and the channel's arm line carries the same reason. The restart then happens at that number. **Nothing is stranded**: the first build refused the second restart and disarmed, leaving the preview stuck for the rest of the session with a notification promising a restart in 5 s. **AND THE NUMBER IS THE THING TO WATCH**: the delta review found that the stretch, though written, never ran in the shipped extension, because the three events that arm were sent without a clock -- the outcome was right and only the sentence was wrong, which is exactly the kind of defect this step exists to catch. If you see `5 s` here, that regression is back |
| 2.32a | **THE STATE LOG, and the one UNVERIFIED thing a human can settle in a second.** Watch the Ermine output channel through any restart | every transition the language client reports is logged as `client N: state <from> -> <to>`, with `(DROPPED: a newer client is current)` on the ones the epoch guard ignores. **WHETHER A FRESH `LanguageClient` EMITS AN INITIAL `Stopped -> Starting` AT ALL IS UNVERIFIED** -- the library's source is unread and nobody has run this extension -- and this line is what settles it: note what the FIRST client of a session logs before it reaches `Running`, and write it into this row |
| 2.32 | **NO DOUBLE RESTART.** Wedge it with the grace at 20 and press **Restart Language Server** after ~10 s, before the grace expires | ONE restart: the edge out of `Running` disarms the grace, so the channel logs `preview: the automatic restart is disarmed (…)` -- **either `(the language server stopped)` or `(the language client left Running)`, and both are correct** (review N5: which one you get depends on whether the library reports `Starting` first, which nobody here has observed) -- and there is no later `preview: RESTARTING the language server` line. If the two ever do collide, the AUTOMATIC one is refused (`restart: refused (a restart is already under way)`) and you should see exactly one `restarting…` line and one new server process, never two. **THE OPPOSITE ORDER IS THE ONE THAT MATTERS (review F1): press the button WHILE an automatic restart is under way and the button must still work** -- the channel logs `restart: the user asked while an automatic restart was under way, so it takes over` and then `restart: superseded by a newer one — not starting a second client` from the older one. **The user's restart is never the one that is refused**; if you ever see it refused, that is a regression of the command the whole feature leans on |
| 2.32b | **THE STOP THAT DOES NOT COME BACK (review F1), and the two glue paths no test can reach (review N4).** There is no way to make this happen on purpose from the UI; watch for it whenever a restart takes more than five seconds | the channel logs `stop: the language server did not stop within 5s — carrying on anyway. THE OLD SERVER PROCESS MAY STILL BE ALIVE: check with ps -ef \| grep lsp.Main, and kill the older pid by hand if there are two.` and a NEW server starts regardless. Run the `ps` check it names. **AND THE REST OF THE RESTART MUST STILL HAPPEN (final re-check must-fix): the held question IS asked.** On this path the old client's real `Stopped` arrives after a newer client is current and is dropped as stale -- you will see it in the channel as `client N: state Running -> Stopped (DROPPED: a newer client is current)` -- so `restart` reports the edge itself, logged as `preview: the language server stopped (the stop returned "timed-out")`. What follows must look exactly like §2.29: `Ermine: preview offline`, then the `held` status bar and ONE question. If the tab re-renders by itself, or nothing is asked at all, that is the defect this step exists for. **Two other pieces of glue have no test and can only be seen here**: that a render coalesced in the 150 ms before an automatic restart is dropped rather than sent to the fresh server (you would see a `preview: render …` line just after `preview: RESTARTING …` -- there should be none), and the restart guard above. The review's own mutation run removed each of them from the source and the whole unit suite stayed green |

| 2.32c | **RESTART DURING THE FIRST-RUN CLASSPATH WARM-UP (delta review M2).** With no `target/ermine-classpath` (delete it, or use a fresh checkout), open a `.e` file so the extension activates, and while the **"Ermine: building the classpath cache (first run, sbt)"** progress notification is on screen run **Ermine: Restart Language Server** -- twice, if you are quick | **EXACTLY ONE `lsp.Main` PROCESS AFTERWARDS** (`ps -ef \| grep lsp.Main`), and the channel logs `start: superseded during the classpath warm-up — not starting this client` for each superseded attempt. The warm-up can run for MINUTES, and before this fix a restart arriving inside it found the client already cleared, skipped the stop, and raced into its own start: two clients, two JVMs, one referenced by nothing and never stopped, with its handlers still wired to the extension's state. Nothing in the unit suite can see this; an async model of the same control flow can, and does (`restartModel` in `test/preview-core.test.js`), but only this step sees the real thing |

**WHAT THESE TEN STEPS CANNOT TELL YOU, and it matters**: whether
`client.stop()` really kills a wedged server process, or only stops talking
to it. The server should answer `shutdown`/`exit` promptly even while the
preview is wedged (READ: `Preview.shutdown()` drains and returns without
joining the preview thread; the preview thread is a daemon; MEASURED: the
dispatch thread answered a hover in 0.00 s while wedged) -- but the library's
own behaviour is *external* and UNVERIFIED here. **So while you run §2.29 and
§2.32, watch the process list**: `ps -ef | grep lsp.Main` should show exactly
ONE server after each restart. Two would mean the old JVM outlived the stop,
and a non-allocating wedge would then never go away.

**THE HOLES TO KNOW WHILE TICKING THESE**, each of them a design decision
rather than a bug: a second VS Code window on the same folder keeps its own
mark (per extension host; cross-window `Memento` visibility is *external* and
unverified), `bin/ermine-serve` and every non-VS-Code client are unprotected
(§13's Q18), and "it didn't change" is a PROXY -- the two signals used are the
server's own `invalidated` and any `.e` save, and both err towards asking
less. **IF THE AUTOMATIC RESTART EVER DOES NOT HAPPEN** -- nothing is picked, or a restart is already under way -- you get a warning notification and the stuck tooltip says `The automatic restart did not happen: …`; it is not only an output-channel line (review D3). **WP-22(c) IS BUILT AS OF 0.1.7 BUT IS OFF BY DEFAULT** (§2.28-2.32):
with `ermine.preview.restartAfterStuckSeconds` at its default of 0 nothing
kills the server on your behalf and the wedged process still dies by itself at
`-Xmx` (or when you press Restart). The setting is spelled
`restartAfterStuckSeconds`, not `killAfterStuckSeconds` as the design review
called it.

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
