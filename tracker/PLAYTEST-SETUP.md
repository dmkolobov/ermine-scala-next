# Playtest setup: getting the Ermine extension into VS Code

**Prerequisite for `tracker/WP-7-MANUAL-CHECKLIST.md`.** Follow it top to
bottom once; then open that file and start at step A1.

**What was verified while writing this, and what was not.** Everything with a
measured number below was run on this machine on 2026-09-23 against a real
`bin/ermine-lsp` from this worktree, with no editor in the loop. **Nothing in
VS Code was run at all** — the extension was packaged but deliberately not
installed, and no editor window was opened. Every claim about what VS Code
does is marked *(unobserved)*.

---

## 1. Prerequisites

| | |
|---|---|
| The worktree | `/home/dmitry/research/ermine/ermine-scala-wt-widget-preview`, branch `widget-preview`, HEAD `606d99b0` |
| VS Code | 1.138.0 at `/snap/bin/code` (the extension needs ≥ 1.75) |
| A JDK 17+ | present: `~/.local/ermine-toolchain/jdk-21.0.12.1+1`. `bin/ermine-lsp` finds it by itself when `JAVA_HOME` is unset |
| sbt | **not needed.** `target/ermine-classpath` already exists here and is newer than `build.sbt`, so the launcher does not shell out to sbt |
| A compiled `core` | **already compiled, and it matches HEAD.** Checked: the newest class under `core/target/scala-3.3.8/classes` is 2026-09-21 03:10:38 and the last commit touching `core/src/main/scala` is 2026-09-21 02:44:40; `parsers`, `machines`, `scalaz-compat` and `f0` are all likewise newer than their last source commit; `core/src/main/resources` is byte-identical to the copied resources. **No `sbt core/compile` is needed and none was run** |
| Node and npm | node v24.20.0, npm 11.19.0. Needed only to package the `.vsix` |
| `editor/vscode/node_modules` | already there (3.4 MB, gitignored). If it goes missing, copy it from `/home/dmitry/research/ermine/ermine-scala/editor/vscode/node_modules` |

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

If this fails, nothing in the checklist can work and there is no point opening
VS Code.

## 3. Package the extension

**Already done: `editor/vscode/ermine-lang-0.1.9.vsix`, 739,081 bytes, 328
files** (built 2026-09-23 from this HEAD). Use it as it is. To rebuild:

```sh
cd /home/dmitry/research/ermine/ermine-scala-wt-widget-preview/editor/vscode
npx @vscode/vsce package          # -> ermine-lang-0.1.9.vsix
```

It needed **no changes** to `package.json`, `.vscodeignore` or the README. It
prints three warnings, all harmless and all expected:

- `A 'repository' field is missing` — the repository has no remote yet.
- `../../LICENSE not found` — `package.json` says `SEE LICENSE IN
  ../../LICENSE`; the repository's licence files are `LICENSE.md` and
  `COPYING`. The `.vsix` therefore ships with no licence file in it.
- a bundling suggestion — the package ships `src/`, `syntaxes/`, the
  hand-listed `node_modules` subset from `.vscodeignore`, and `test/` (447 KB
  of unit tests, which `.vscodeignore` does not exclude).

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
groups A and B are written against the JSON tab**: set `ermine.preview.target`
to `json` (the 0.1.11 tab, unchanged) or `both` before running them as written.
There is no panel group in the checklist yet (WP-10 S5).

**Since 0.1.13 (WP-10 S3) an open panel follows the bundle by itself**: building
it while the *not built* page is up should turn the panel into the page with no
command (UNVERIFIED in VS Code for a folder that did not exist yet -- if nothing
happens, run **Ermine: Preview Report...** again). To work on the client, leave
`npm run bundle:watch` running in `client/`: each save becomes a *"the client
bundle changed; reloading"* banner and then the redrawn panel, once per build.

## 4. Install it

**One line, and it is yours to run — this was not run for you:**

```sh
code --install-extension /home/dmitry/research/ermine/ermine-scala-wt-widget-preview/editor/vscode/ermine-lang-0.1.9.vsix
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

**The extension is 0.1.9**: Extensions view > Ermine > the version under the
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

**What `git status` will show, and what is fine.** This setup adds
`tracker/PLAYTEST-SETUP.md` and `tracker/playtest/` as untracked, and nothing
here has been committed. `editor/vscode/ermine-lang-0.1.9.vsix` is gitignored
(`editor/vscode/.gitignore`) and does not appear. So the checklist's
end-of-session rule reads: `git status --short` should show `.ermine/`,
`.vscode/`, `tracker/PLAYTEST-SETUP.md` and `tracker/playtest/` — and nothing
else.

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

- **There is no webview panel.** One untitled JSON tab and one status bar item
  is the whole preview. The panel is WP-10.
- **The render tab is untitled and always dirty.** Closing it offers to save a
  throwaway render: **Don't Save**. There is no way round it for an untitled
  document.
- **The first pick of `Sales.report` answers a 500, not a document.** The
  skeleton is written with **today's** dates and `Sales`'s rows are all in
  2026-01..2026-03, so nothing matches and an empty relation carries no
  columns. **Measured twice against a real server.** That is open question Q21
  and it is yours; edit the dates to `2026-01-05` / `2026-03-17` and it renders
  `ok=true`.
- **No database, no backends.** Profiles, the held connection, the driver and
  everything in §7 of `tracker/JSON-WIDGET-PLAYGROUND.md` are not built. The
  `mssql-jdbc` driver is not even in `build.sbt`.
- **Remote and virtual workspaces will not work.** The params file is addressed
  with `vscode.Uri.file(fsPath)`, which discards the scheme and the authority,
  so on a `vscode-remote:` or virtual workspace the read and the watcher both
  point at a local path that is not there. Use a local folder.
- **Windows is not supported.** Every launcher is bash; there is no
  `bin/ermine-lsp.cmd`.
- **The `.vsix` ships no licence file** (see §3), and there is no publisher
  registration or marketplace entry — it installs from the file only.

---

**Unverified, and named as such:** every VS Code behaviour in this guide —
the install, the Extensions view version, the output channel, the status bar,
the quick picks, the params watcher, the multi-root settings rule. The server
half, the fixtures, the packaging, the gate scopes and the compiled-state
checks were all run on this machine and are quoted with their numbers.
