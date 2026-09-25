# Playtest setup: getting the Ermine extension into VS Code

**Prerequisite for `tracker/WP-7-MANUAL-CHECKLIST.md`.** Follow it top to
bottom once; then open that file and start at step A1.

**AMENDED 2026-09-23 BY WP-10 STAGE 5 (at HEAD `56f608cd`, the stage itself
uncommitted):** the extension is now **0.1.14** and packaged as
`editor/vscode/ermine-lang-0.1.14.vsix` (§3); the panel needs the client bundle
and the writers checkout (§1); two settings are new (§6); §2's check was re-run
(§2); §13 says what the panel does and does not do yet. The checklist has a
Group E for the panel.

**What was verified while writing this, and what was not.** Everything with a
measured number below was run on this machine on 2026-09-23 against a real
`bin/ermine-lsp` from this worktree, with no editor in the loop. **Nothing in
VS Code was run at all** — no editor window was opened. Every claim about
what VS Code does is marked *(unobserved)*. **INSTALLED 2026-09-23 (evening), at
the user's request, by the orchestrator:** `code --install-extension …/ermine-lang-0.1.14.vsix --force`
printed "successfully installed"; `code --list-extensions --show-versions` went
from `clarifi.ermine-lang@0.1.4` to `clarifi.ermine-lang@0.1.14`; VS Code was not
running at the time, so the next window picks it up with no reload.

---

## 1. Prerequisites

| | |
|---|---|
| The worktree | `/home/dmitry/research/ermine/ermine-scala-wt-widget-preview`, branch `widget-preview`, HEAD `56f608cd` (WP-11) plus WP-10 stage 5's uncommitted docs, one test and a one-line wording fix. (Written first at `2b67997b`.) |
| VS Code | 1.138.0 at `/snap/bin/code` (the extension needs ≥ 1.75) |
| A JDK 17+ | present: `~/.local/ermine-toolchain/jdk-21.0.12.1+1`. `bin/ermine-lsp` finds it by itself when `JAVA_HOME` is unset |
| sbt | **not needed.** `target/ermine-classpath` already exists here and is newer than `build.sbt`, so the launcher does not shell out to sbt |
| A compiled `core` | **already compiled, and it matches HEAD.** Checked: the newest class under `core/target/scala-3.3.8/classes` is 2026-09-21 03:10:38 and the last commit touching `core/src/main/scala` is 2026-09-21 02:44:40; `parsers`, `machines`, `scalaz-compat` and `f0` are all likewise newer than their last source commit; `core/src/main/resources` is byte-identical to the copied resources. **No `sbt core/compile` is needed and none was run** |
| Node and npm | node v24.20.0, npm 11.19.0. Needed only to package the `.vsix` |
| `editor/vscode/node_modules` | already there (3.4 MB, gitignored). If it goes missing, copy it from `/home/dmitry/research/ermine/ermine-scala/editor/vscode/node_modules` |
| **The client bundle** (for the panel, Group E) | `cd client && npm ci && npm run bundle` — **already done in this worktree**: MEASURED 2026-09-23 by `ls -l client/dist/browser`, `ermine-client.js` **327,103 B** and `ermine-host.js` **25,390 B** (plus their two `.map` files), both newer than the last change under `client/src`. **Rebuilt by S5's round 2 (13:49)** after one string in `client/src/host/page.ts` changed (the deferred-relation refusal, Q24): `ermine-host.js` is now **25,639 B**, `ermine-client.js` unchanged at 327,103 B (MEASURED, `ls -l`). **Rebuilt again by Q24 (d), 2026-09-23** (the `heading`/`text` renderers and `page.ts`'s U6 comment): `ermine-client.js` **333,377 B**, `ermine-host.js` **25,908 B** (MEASURED, `ls -l client/dist/browser`). **Rebuilt again by the F3 fix, 2026-09-23** (`client/src/host/page.ts`: the writers' `renderFunction` draw step, the white paper, the grid and table layout; `tracker/PLAYTEST-RESULTS.md` F3): `ermine-host.js` **31,240 B**, `ermine-client.js` unchanged at **334,820 B** (MEASURED, `ls -l client/dist/browser`). **After F3 you need only `cd client && npm run bundle`**: the open panel's bundle watcher reloads the page (0.1.13). Whether that watcher fired was NOT checked: it is the extension's, and the headless harness loads the page without it. **A `client/` change needs only this rebuild, not a new `.vsix`**: the `.vsix` carries `editor/vscode` and nothing of `client/`, and the panel loads the bundle from the checkout (an open panel reloads by itself, E7). It is gitignored and NOT in the `.vsix`: the panel loads it from the checkout that holds `bin/ermine-lsp`. **Without it the panel shows the static page *"The preview bundle is not built"*** with the folder it looked in and the two commands to run — the designed first experience, not a failure (checklist E8). `npm ci` needs the network once, or an npm cache |
| **The writers checkout** (for the panel's `table`, charts and `styleBox`) | `/home/dmitry/research/ermine/ermine-writers`, a sibling of this worktree. The panel's default for `ermine.preview.writersPath` (empty) is `<checkout>/../ermine-writers/writers/html/src/main/resources/web`, which from here resolves to `/home/dmitry/research/ermine/ermine-writers/writers/html/src/main/resources/web` and holds `htmlwriter.js` (MEASURED by the WP-11 review). **Without it** the panel still loads, the scorecard, headline and crosstab still draw, every legacy widget is an error box, and a banner (plus one channel line) says *"the legacy writers are not loaded: no htmlwriter.js in …"* — with the document dimmed under it (checklist E14). The folder is not watched: fix the path and run **Ermine: Preview Report...** again |

## 2. Verify the server, before any editor is involved

```sh
cd /home/dmitry/research/ermine/ermine-scala-wt-widget-preview
python3 tracker/playtest/check-server.py
```

It starts `bin/ermine-lsp` exactly the way the extension does — same command,
same cwd, same environment — waits for the boot line, shuts it down and exits
0. **A good run looks exactly like this** — the transcript below is a real
run of this script on 2026-09-23, and the boot took 11.8 / 11.8 / 11.9 / 12.0 s
over the four boots made while writing this guide:

```
worktree:  /home/dmitry/research/ermine/ermine-scala-wt-widget-preview
launcher:  /home/dmitry/research/ermine/ermine-scala-wt-widget-preview/bin/ermine-lsp
classpath: /home/dmitry/research/ermine/ermine-scala-wt-widget-preview/target/ermine-classpath, 2410 bytes
initialize answered in 0.26s
  [  0.27s] Ermine: loading the session (129 modules, ~13s)…
  [ 12.28s] Ermine session ready: 129 modules in 12.0s
shutdown clean, exit code 0
OK: Ermine session ready: 129 modules in 12.0s
```

**129 modules is the number.** A different count, or no `session ready` line at
all, means the classpath cache points somewhere stale — delete
`target/ermine-classpath` and run it again, which will shell out to sbt once.

**Re-run by WP-10 stage 5 on 2026-09-23 at 13:36 (-0600), HEAD `56f608cd`
plus the stage's uncommitted edits (none of them touches the server): exit code
0**, last lines:

```
initialize answered in 0.27s
  [  0.28s] Ermine: loading the session (129 modules, ~13s)…
  [ 13.76s] Ermine session ready: 129 modules in 13.5s
shutdown clean, exit code 0
OK: Ermine session ready: 129 modules in 13.5s
```

(`scripts/liveness.sh` read `sbt=0 … lsp=0 … ermine-jvm=0` before and after.)

If this fails, nothing in the checklist can work and there is no point opening
VS Code.

## 3. Package the extension

**Already done: `editor/vscode/ermine-lang-0.1.14.vsix`, 854,103 bytes, 334
files** (`ls -l`; `unzip -l` lists 334 entries, 3,091,342 bytes unpacked),
REPACKAGED 2026-09-23 19:37 from commit `f75b77f8` (Q25) after the earlier
852,896-byte build from WP-10 stage 5; its `src/preview-core.js` sha256
`eea5afd7…` equals the tree's. This is the file that is installed (§4). `unzip -p … extension/package.json` says `"version": "0.1.14"`, and its
`src/extension.js`, `src/preview-core.js`, `test/preview-core.test.js` and
readme are byte-identical to the working tree's (MEASURED with `sha256sum`).
**Use it as it is.** The old `ermine-lang-0.1.9.vsix` (739,081 bytes, 328
files, the first playtest prep) is still beside it; do not install that one.
To rebuild:

```sh
cd /home/dmitry/research/ermine/ermine-scala-wt-widget-preview/editor/vscode
npx @vscode/vsce package          # -> ermine-lang-<version in package.json>.vsix
```

It needed **no changes** to `package.json`, `.vscodeignore` or the README. It
prints three warnings, all harmless and all expected:

- `A 'repository' field is missing` — the repository has no remote yet.
- `../../LICENSE not found` — `package.json` says `SEE LICENSE IN
  ../../LICENSE`; the repository's licence files are `LICENSE.md` and
  `COPYING`. The `.vsix` therefore ships with no licence file in it.
- a bundling suggestion (at 0.1.14: *"This extension consists of 334 files,
  out of which 169 are JavaScript files"*) — the package ships `src/`,
  `syntaxes/`, the hand-listed `node_modules` subset from `.vscodeignore`, and
  `test/` (about 740 KB at 0.1.14, 447 KB at 0.1.9, which `.vscodeignore` does
  not exclude).

The 0.1.14 run printed exactly these three warnings again and exited 0
(WP-10 stage 5, 2026-09-23).

The package does **not** contain the repository's `client/` webview bundle, and
it should not: the extension is not self-contained and needs this checkout for
`bin/ermine-lsp`.

**Since 0.1.12 (WP-10 S2) the preview draws into a webview panel that LOADS that
bundle from the checkout**, `client/dist/browser/`, which is git-ignored and so
absent on a fresh checkout. Build it once before using the panel:

```sh
cd /home/dmitry/research/ermine/ermine-scala-wt-widget-preview/client && npm install && npm run bundle
```

Without it the panel shows *"The preview bundle is not built"* with the path
(that is the designed first experience, not a failure). **The checklist's
groups A, B and C are written against the JSON tab**, so
`tracker/playtest/settings.example.json` (§6) sets `ermine.preview.target` to
`json` (the 0.1.11 tab, unchanged). **Group E is the panel** and begins by
setting it back to `panel`.

**Since 0.1.13 (WP-10 S3) an open panel follows the bundle by itself**: building
it while the *not built* page is up should turn the panel into the page with no
command (UNVERIFIED in VS Code for a folder that did not exist yet -- if nothing
happens, run **Ermine: Preview Report...** again). To work on the client, leave
`npm run bundle:watch` running in `client/`: each save becomes a *"the client
bundle changed; reloading"* banner and then the redrawn panel, once per build.

**Since 0.1.14 (WP-11) the panel also loads the legacy writers** for `table`,
`drilldownTable`, the charts and `styleBox`: `htmlwriter.js` plus
`common.css`, `htmlwriter.css` and `htmlwriter_classic.css`, from the setting
`ermine.preview.writersPath`. **Leave it empty on this machine**: empty means
`<checkout>/../ermine-writers/writers/html/src/main/resources/web`, i.e.
`/home/dmitry/research/ermine/ermine-writers/writers/html/src/main/resources/web`
from this worktree (MEASURED: that folder holds `htmlwriter.js`). That default
is this machine's sibling layout, not a guarantee; on another machine set the
path. Without `htmlwriter.js` there, the panel still loads, the legacy widgets
show error boxes and a banner says where it looked (the document is dimmed
under it); the folder is not watched, so after fixing it run **Ermine: Preview
Report...** again. **Expected, not a failure**: in **Developer: Open Webview
Developer Tools**, a blocked image for
`/CIQDotNet/images/TopMenuBar/tmbllsprite.png?urwvid=1` (a root-relative
sprite in `common.css`); `/content/themes/base/images/mainSprite.png` belongs
to the dark sheet, which is not loaded, so it should not appear. A click in a
style box does nothing (its click-through posts to a server the CSP blocks),
and `treeMap` is always an error box. Whether `table` and a `pieChart`
actually draw is what E9/E10 record: **nobody has run this yet.**

## 4. Install it

**One line, and it is yours to run — this was not run for you:**

```sh
code --install-extension /home/dmitry/research/ermine/ermine-scala-wt-widget-preview/editor/vscode/ermine-lang-0.1.14.vsix
```

Then **reload the window**. Upgrading later is the same command with the new
file.

**The alternative, if you would rather not touch your installed extensions**:
skip this step and run an Extension Development Host instead —

```sh
code --extensionDevelopmentPath=/home/dmitry/research/ermine/ermine-scala-wt-widget-preview/editor/vscode \
     /home/dmitry/research/ermine/ermine-scala-wt-widget-preview
```

Both routes run the same code. The `.vsix` route is the one whose version
string you can check in the Extensions view, and it is what the checklist
assumes.

## 5. Open the right folder, and only that folder

```sh
code /home/dmitry/research/ermine/ermine-scala-wt-widget-preview
```

**Open the worktree root, as a single folder.** Two reasons, and both change
what the checklist sees:

1. **Params files land in the workspace folder that CONTAINS the report** —
   the innermost one, never the first in the window. `Sales.report` writes
   `<that folder>/.ermine/preview/Sales/report.params.json`. **A report that
   is inside no workspace folder writes nothing at all**, says so once in the
   channel, and renders with empty parameters. That is deliberate: the
   fallback for a *setting* is the first folder, and doing the same for a
   *file* would write into an unrelated repository.
2. **Keep the window single-root.** Three of the settings below are
   window-scoped (`preview.timeoutSeconds`,
   `preview.restartAfterStuckSeconds`, `maxHeap`). VS Code reads a
   window-scoped setting from a folder's `.vscode/settings.json` only while
   that folder *is* the workspace; **File > Add Folder to Workspace** makes
   the window multi-root and those three stop coming from this file
   *(unobserved — documented VS Code behaviour)*. The wedge fixtures now live
   inside this worktree precisely so that no step needs a second folder.

The one step that still needs a report **outside** every workspace folder is
the old §2.40. Make it a copy, and do not add its directory to the workspace:

```sh
mkdir -p /tmp/wp7 && cp tracker/playtest/fixtures/WpSpin.e /tmp/wp7/
```

Open `/tmp/wp7/WpSpin.e` as the active editor and run **Ermine: Preview
Report...**; it is offered first even though the workspace scan cannot see it.

## 6. The settings

```sh
mkdir -p .vscode
cp tracker/playtest/settings.example.json .vscode/settings.json
```

`tracker/playtest/settings.example.json` carries the reasoning inline. In
short:

| setting | value here | why |
|---|---|---|
| `ermine.serverPath` | absolute, to **this** worktree's `bin/ermine-lsp` | without it the extension takes `bin/ermine-lsp` from the first workspace folder. Setting it also fixes the repo root the server runs in and reads `target/ermine-classpath` from |
| `ermine.preview.roots` | `[]` | empty means the report's own directory plus the stdlib. Every report in this playtest is a single-segment module, so that is enough. The key is present so the steps that ask you to edit it have something to edit |
| `ermine.preview.timeoutSeconds` | `60` | the shipped default; the wedge steps tell you to set `5` and step C6 tells you to set it back |
| `ermine.preview.restartAfterStuckSeconds` | `0` | `0` = never, and it is the default. **Turning it on is a checklist step**, not part of the setup — the steps that observe the feature each tell you to set `20` |
| `ermine.maxHeap` | `""` | empty means the launcher's own `2g`. One step sets `256m` (to make `WpBlow` die of the heap) and one sets `16m` (to see the 64 MB floor refused). Changing it **restarts the server**, because `-Xmx` is fixed at process start |
| `ermine.preview.target` | **`json`** | the shipped default is `panel` (since 0.1.12), but Groups A–C are written against the JSON tab, which `json` keeps byte-for-byte as 0.1.11 had it. **Group E sets it to `panel`**; E13 tries `both` and a bad value. Window scope |
| `ermine.preview.writersPath` | not set (= `""`) | empty means the sibling writers checkout (§1), which exists here. Only E14 sets it, to an empty folder, and puts it back. Window scope |
| `ermine.preview.profiles` + `ermine.preview.profile` | **not here**: USER settings | the DB programme's profile for the local SQL Server (extension 0.1.17, WP-13). The extension reads both from user settings ONLY and ignores a workspace value (tracker §8.1 A2); the example file carries them only as a comment saying so |

**The database profile (DB programme, stage 2).** With the container up
(`scripts/db.sh status` says `status OK`) and a server that has
`ermine/preview/connect`, add these two keys to your **USER** settings
(`Preferences: Open User Settings (JSON)`), **not** to `.vscode/settings.json`:

```jsonc
"ermine.preview.profiles": [
  { "id": "sales-mssql", "dialect": "mssql",
    "url": "jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true",
    "user": "ermine" }
],
"ermine.preview.profile": "sales-mssql"
```

In workspace settings they are ignored, and the output channel and a status
bar item say *"profiles set in workspace settings are ignored (user settings
only)"*: a checked-in `.vscode/settings.json` could point a profile at another
host and have the password sent there (tracker §8.1 A2). When the server is up
the extension asks once for the password of `ermine @ 127.0.0.1` (it is
`ERMINE_DB_PASSWORD` in `~/.config/ermine/db.env`; type it, do not paste it
into any file). It is held in the window's memory only and forgotten on reload
or **Ermine: Disconnect Database**. The second status bar item then reads
`sales-mssql (mssql) @ 127.0.0.1`. Keep `ermine.trace.server` off or at
`messages`: at `verbose` the extension refuses to connect. There is no
password field in the profile and the URL may not carry one (it is refused).
To go back to the in-memory SQLite, set `ermine.preview.profile` to `""` in
user settings.

`.vscode/` is **not** gitignored in this repository, so `.vscode/settings.json`
shows up in `git status` as untracked. Delete it when you are done.

## 7. The output channel

**Ermine: Show Language Server Output** (`ermine.showOutput`) opens the output
channel named **Ermine**. Both halves go there: the extension's own lines
(`preview: …`, `restart: …`, `settings: …`, `client N: …`) and the server's
log. **Every line the checklist quotes appears in that one channel.** Open it
before step A1 and leave it open.

The status bar item is on the right and reads `Ermine: starting session…`,
then `Ermine`, then `$(json) Ermine: <Module>.<binding>` once a report is
picked.

## 8. Confirm you are testing what you think you are

**The extension is 0.1.14**: Extensions view > Ermine > the version under the
name, or

```sh
code --list-extensions --show-versions | grep ermine
```

**The server is this worktree's** — check it while the server is up, from
outside VS Code:

```sh
/home/dmitry/research/ermine/scripts/liveness.sh --procs
```

A live server prints one line (measured):

```
lsp pid=2541951 up=0h00m rss=754M wt=widget-preview
```

`wt=widget-preview` is the whole point: any other suffix, or `wt=main`, means
`ermine.serverPath` did not take. The long form shows the classpath itself:

```sh
pgrep -af 'com\.clarifi\.reporting\.ermine\.lsp\.Main'
```

which on a correct start begins
`…/jdk-21.0.12.1+1/bin/java -Xmx2g -XX:+ExitOnOutOfMemoryError
-XX:+DisplayVMOutputToStderr -cp /home/dmitry/…-wt-widget-preview/core/target/…`
(measured).

## 9. Where the results go

**`tracker/PLAYTEST-RESULTS.md`** — the checklist's own "Before you start"
table names it, one row per step id. Fill in PASS / FAIL / SKIP and one line
of what you saw; paste the Ermine channel's text under the table for any FAIL.

## 10. The fixtures

They live in `tracker/playtest/fixtures/`, are inside the workspace folder, and
are swept by nothing: the corpus gate globs `core/examples/**` explicitly and
the LSP gate reads `tracker/lsp-tests/` (both checked). Each file's header says
which steps use it.

| fixture | what it does | measured here, 2026-09-23 |
|---|---|---|
| `WpInt.e` | **renders.** `report : Int -> Node`, the control — if this does not render, the trouble is the server, not the step | `ok=true` in 2.18 s (including the 1.9 s render-session boot), document `{"version":1,"settings":{},"root":{"tag":"Widget","name":"int","props":0}}`. Its `ermine/schema` is 105 bytes, `$schema`/`$id`/`type`, so the written skeleton is the bare value `0` with no `$schema` key |
| `WpSpin.e` | **wedges** — a bare self-call | at `timeoutSeconds: 5` the render is answered **7.18 s** after the request with `status 500, stuck: true`; the `ermine/preview/stuck` notification (`seq: 1`) arrived **after** the answer; a second render was refused in **0.00 s** with its own generation echoed |
| `WpChain.e` | **wedges** — a fold over a cyclic list, the same wedge by a different mechanism | at `timeoutSeconds: 5` answered **6.70 s** after the request, same shape |
| `WpBlow.e` | **kills the JVM** — an unbounded allocation off a retained top-level list | at `ERMINE_LSP_XMX=256m` and `timeoutSeconds: 600` the server **died 6.85 s** after the render, **exit code 3**, with `Terminating due to java.lang.OutOfMemoryError: Java heap space` on **stderr** and nothing after the last complete frame on stdout (Q12's `-XX:+DisplayVMOutputToStderr` is working here) |
| `WpEmpty.e` | **refuses to encode on purpose** — `report : Int -> Node` returning a table over `relation []`, a header-less empty relation (TestRunner's (b7) `RgEmpty` shape; the engine gap is WP-29). Not a checklist step: it keeps the 500 that `Sales` used to answer reproducible for `editor/vscode/test/fixtures/panel-answers.json` | `ok=false, status 500`, *"WpEmpty.report produced a document that cannot be encoded: an empty relation built from no rows carries no columns; give it a header (mkRelationWithHeader#) or a static hint"*, path `$.props` (`scratch-widget-preview/q21-sales/captures.json`) |

**`Sales.e` is not in that directory and must not be moved there.** It stays at
`core/src/test/resources/doc/Sales.e`; other suites read it. Measured: its
`ermine/preview/reports` answers `report : Query -> Node`, and a render with
empty params answers `{"ok": false, "status": 400, "message": "the required key
\"fromDay\" is missing", "path": "$.params"}`.

**One surprise in the pick list.** `WpSpin.e` offers **two** report-typed
bindings — `spin : Int -> Node` as well as `report : Int -> Node` — because
`spin` has a report type too. **Pick `report`.** (Picking `spin` wedges just
the same.) The other three fixtures offer exactly one binding each.

The two hand-written params files the checklist asks for are in
`tracker/playtest/params/`, with a README saying where to copy each.

**What `git status` will show, and what is fine.** This setup's own files
(`tracker/PLAYTEST-SETUP.md`, `tracker/playtest/`) were committed in
`edb0b74c`. Both `.vsix` files are gitignored (`editor/vscode/.gitignore`,
`*.vsix`) and do not appear, and neither does `client/dist/`. So the
checklist's end-of-session rule reads: `git status --short` should show
`.ermine/` and `.vscode/` — and nothing else.

## 11. Resetting between scenarios

In this order:

```sh
rm -rf .ermine/preview/<Module>        # or rm -rf .ermine for a clean first-pick run
```

then **Ermine: Restart Language Server** (`ermine.restartServer`). A restart
clears a *stuck* preview, and normally re-sends the last pick.

**A restart does NOT clear a wedge mark, and neither does a window reload.**
Both the remembered pick and the wedge mark live in `workspaceState`, so they
survive a server restart, a window reload and a machine reboot. After a report
has wedged the preview, the restart leaves the status bar reading
`$(warning) Ermine preview: held` and asks **Render anyway / Not now** instead
of rendering. What clears the mark: saving any `.e` file, changing the
parameters the report is actually sent, a `preview.roots` change that really
moves the resolved list, or pressing **Render anyway**. Picking a different
report replaces the pick.

Between the heap steps, put `ermine.maxHeap` back to `""` and
`ermine.preview.timeoutSeconds` back to `60` before you go on.

## 12. If the server will not stop

A wedged server exits by itself about two minutes after the watchdog fires (it
reaches `-Xmx`), and `-XX:+ExitOnOutOfMemoryError` means an OOM is a clean exit
the client restarts. If you need to do it by hand, **find the pid and kill that
one** — do not `pkill java`, and do not kill anything you did not start:

```sh
pgrep -af 'com\.clarifi\.reporting\.ermine\.lsp\.Main'   # look at the -cp: it must name this worktree
kill <pid>                                               # kill -9 <pid> only if it does not go
/home/dmitry/research/ermine/scripts/liveness.sh          # lsp=0 when it is gone
```

The language client restarts the server by itself up to 5 times in 3 minutes
(`vscode-languageclient`'s own policy); past that, **Ermine: Restart Language
Server**.

At the end of a session `liveness.sh` should read `sbt=0 … lsp=0 … ermine-jvm=0`.

## 13. What is NOT expected to work yet

- **The webview panel exists (0.1.12-0.1.14) and has never been seen by
  anyone.** Built: one panel per window, beside the editor, opened only by the
  two commands; the whole state re-sent on `ready` and when it becomes visible;
  the static *not built* / *HALF-BUILT* page; the bundle watcher (one reload
  per build); the stuck / held / offline / error / re-rendering banners; the
  Restart button; the legacy writers and their missing-writers banner; the
  refused deferred relation. Group E is where each of those is first looked at.
- **Not built, so not a failure when you do not see it:** the **`unsaved`**
  hint (the kind exists in the page; nothing in the extension produces it);
  **`switching`** (no producer until profiles exist, WP-13/14); a **Render
  anyway** button in the panel (the held question stays a notification, by
  decision U4); **`treeMap`** (always an error box, by design).
- **Built, but with a known gap:** a **server restart does NOT re-check the
  writers** (only an explicit command on a page built without them, a bundle
  rebuild, or a new panel does); the **writers folder is not watched** at all;
  **deleting the bundle FOLDER** (as opposed to its files) is predicted by the
  typings NOT to be noticed until it is re-created, and nobody has observed
  either way (checklist E8); a **style-box click** does nothing, by design
  (the page may not open a connection), and **no report in this repository
  draws a style box**, so E11 has no fixture.
- **Deferred relations in the panel (WP-30, filed, NOT built).** The panel
  refuses every deferred relation by name (U6, kept by the user's Q24 decision,
  2026-09-23); fetching them through the extension is ticket WP-30.
  **`Sales.report` in the panel draws all five widgets, NO error box** (Q25,
  decided by the user 2026-09-23: typed widget schemas, "Rewrite it."): its
  body is typed now -- `Layout.Widgets.Heading`, `Layout.Widgets.Text` and three
  `tabular` tables, every props object validated by GENERATED zod -- and its
  items table is INLINE (a typed table cannot force deferral), so NO report in
  this repository shows the deferred-refusal box in the panel (MEASURED in
  jsdom, checklist E2's `Sales` sub-step). WP-10's done-when and checklist E2
  use `core/src/test/resources/modules/Doc/SalesReport.e` and, since Q25,
  `Sales`. The runner's untyped fixture, `core/src/test/resources/doc/SalesRaw.e`,
  is NOT a preview step: four of its five widgets are boxes by design. A
  `client/` change such as Q25's needs only `npm run bundle` in `client/`, **no
  new `.vsix`** (§3's bundle row).
- **The render tab is untitled and always dirty.** Closing it offers to save a
  throwaway render: **Don't Save**. There is no way round it for an untitled
  document.
- **The first pick of `Sales.report` renders an EMPTY table.** The skeleton
  is written with **today's** dates and `Sales`'s rows are all in
  2026-01..2026-03, so nothing matches: the heading says `matched: 0` and the
  `byDay` table has its four columns and no rows. It used to be a 500 ("an
  empty relation built from no rows carries no columns"); the user decided Q21
  on 2026-09-23 (fix the example, ticket the engine: WP-29), and `Sales.e`
  now gives that table a header. **Measured 2026-09-23 against a real
  server.** Edit the dates to `2026-01-05` / `2026-03-17` and the rows
  appear. A report of your own that builds an empty relation with plain
  `relation` still gets the 500 (WP-29).
- ~~**No database, no backends.**~~ **SUPERSEDED 2026-09-25 by DB stages 0-2:**
  the local SQL Server, the `mssql-jdbc` driver, profiles, the prompted password,
  the held connection and the render trace are built (uncommitted at writing,
  NEVER RUN in a VS Code). See §14.
- **Remote and virtual workspaces will not work.** The params file is addressed
  with `vscode.Uri.file(fsPath)`, which discards the scheme and the authority,
  so on a `vscode-remote:` or virtual workspace the read and the watcher both
  point at a local path that is not there. Use a local folder.
- **Windows is not supported.** Every launcher is bash; there is no
  `bin/ermine-lsp.cmd`.
- **The `.vsix` ships no licence file** (see §3), and there is no publisher
  registration or marketplace entry — it installs from the file only.


## 14. The database

The DB programme (tracker/DB-PLAN.md) gave the preview a real SQL Server: SQL Server 2022 in the
rootless podman container `ermine-mssql`, listening on `127.0.0.1:1433` only. It holds the databases
`ErmineSales`, `ErmineHR` and `ErmineScience`, and the login `ermine`. **The walkthrough is
[`tracker/db/DOGFOOD.md`](db/DOGFOOD.md)**, and checklist group F (F1-F12) is its tick list.

| | |
|---|---|
| The one script | `scripts/db.sh` (`--help` lists the exit codes). `status` says whether it is up. `up` / `down` / `down --all` manage the container. `load sales --tier xs\|s\|m\|l`, `verify sales` and `unload sales` manage the data. `sql DB "QUERY"` runs SQL as `ermine`. Details: `tracker/db/README.md`, `CONTAINER.md` and `LOADER.md` |
| The tier | the walkthrough uses tier **s** (seed 42, 388 rows in the `sales` view). The PR-tier `db` gate needs **xs**. `scripts/db.sh verify sales` prints which tier is loaded |
| **The profile lives in USER settings (tracker §8.1 A2)** | `ermine.preview.profiles` and `ermine.preview.profile` are read from user settings only (§6 has the JSON). A copy in `.vscode/settings.json` is ignored and named once, because a checked-in settings file could point the profile at another host and collect your password there |
| The password | `ERMINE_DB_PASSWORD` in `~/.config/ermine/db.env` (mode 600). VS Code asks for it once per window and holds it in memory only. It is not in any setting or file the extension writes, and never in the channel |
| Versions | extension **0.1.17**, a server compiled from the stage-2 tree, and the client bundle rebuilt (`npm run bundle` in `client/`) for the Trace view |
| Unverified | every VS Code behaviour in group F. The server half was measured over the wire (`tracker/db/SERVER.md` §6.3, `tracker/db/OBSERVABILITY.md` §4) |

---

**Unverified, and named as such:** every VS Code behaviour in this guide —
the install, the Extensions view version, the output channel, the status bar,
the quick picks, the params watcher, the multi-root settings rule. The server
half, the fixtures, the packaging, the gate scopes and the compiled-state
checks were all run on this machine and are quoted with their numbers.
