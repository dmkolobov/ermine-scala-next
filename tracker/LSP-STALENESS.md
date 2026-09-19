# LSP staleness: the server reads the stdlib from the source tree

State file of the staleness arc (started 2026-09-18 after J3i landed). Branch `lsp-roots`
off `json-encode`, worktree `ermine-scala-wt-lsp-roots`.

## The problem

| Observed | Cause |
|---|---|
| `import Layout.Widgets.Headline` squiggled "Module not found" in the editor right after the J3i landing, twice in one day | the resident session boots through `SessionEnv.loadFile`'s default, the classpath loader, i.e. `core/target/<scala>/classes/modules` = the `copyResources` copy; a module added under `core/src/main/resources/modules` is not there until the next `sbt core/copyResources`, and the loaded closure is kept for the server's life |
| a worktree's document imports the MAIN checkout's stdlib | the classpath is `tracker/repl-classpath.txt` / `target/ermine-classpath` of the checkout `bin/ermine-lsp` ran in; per check only the document's own directory and module root are prepended (`Resident.checkFile`) |

Workaround before this arc: `sbt core/compile core/copyResources` in the main checkout and
**Ermine: Restart Language Server** after every landing (memory `ermine-landing-rebuild-main`).

## Steps

| # | Step | Mechanism | Status |
|---|---|---|---|
| 1 | Source roots ahead of the classpath | `Resident.moduleRoots`, set by `Main` at `initialize` (`initializationOptions.moduleRoots`, then `Resident.rootsUnder` of every `workspaceFolders`/`rootUri` folder = `<folder>/core/src/main/resources/modules` when it exists), installed at boot as `SourceFile.inOrder(roots..., classpath)`; per check `Resident.checkoutRootOf(document)` (nearest ancestor with that directory) goes after the siblings and before the resident chain | DONE 2026-09-18 (evidence below) |
| 2 | Invalidate on change | after `initialized` the server registers a `**/*.e` watcher through `client/registerCapability` (when the client's `didChangeWatchedFiles.dynamicRegistration` says it may); on `workspace/didChangeWatchedFiles` the loaded modules read from the changed/deleted files plus their transitive dependents (import sets from `Session.depCache`, keyed by the resident's own `loadedFiles`) are scrubbed from the RESIDENT env (`Resident.scrub`, the per-check scrub generalised) and loaded back (`Session.loadModules`); a load that dies leaves them `pending`, retried on the next event; then `Symbols.forgetSession`, `Documents.dropCaches`, `Diagnostics.recheckAll`. Manual: `workspace/executeCommand ermine.reloadModules` = every loaded file whose mtime is not the one its load recorded (+ pending); extension 0.1.4 adds **Ermine: Reload Modules** | DONE 2026-09-19 (evidence below) |
| 3 | "Not built" diagnostic | `BuildStamp`: newest `.class` under the class loader's `core/target/<scala>/classes` (once) vs the `.scala` files under `core/src/main/scala` of the first root's checkout (else the classes' checkout), memoised 5 s and re-read on `ermine.reloadModules`; boot sends a type-2 logMessage naming the count, the newest source and both times; `Diagnostics.check` appends a one-line hint to every diagnostic the build could explain (`undefined term`, `does not export`, `Module not found`, `class/member/field/constructor missing`, `unloadable`) | DONE 2026-09-19 (evidence below) |

## Step 1: what changes for whom

| Client | Before | After |
|---|---|---|
| VS Code extension (sends `rootUri` + `workspaceFolders`; unchanged, 0.1.3) | classpath copy | `<workspace>/core/src/main/resources/modules` first, classpath last -- when a workspace folder IS a checkout; a folder that merely holds checkouts (`~/research/ermine`) implies no root, and only the per-check checkout root applies; several checkout folders give several roots, first folder wins |
| any client, `initializationOptions.moduleRoots: [dirs]` | n/a | those dirs first, in the order given, then the folder-derived ones, then the classpath |
| a client sending neither (the smoke's second server) | classpath copy | classpath copy, unchanged |
| a document in another checkout | that checkout's siblings only, then the booted stdlib | plus that checkout's stdlib root, for modules the boot did not load |

What step 1 alone did NOT do: a module the boot already loaded kept the text it was read
with until a restart. Step 2 closes that.

## Step 2: why not `Session.reloadChangedModules`

| Candidate | Verdict |
|---|---|
| `Session.reloadChangedModules(builtinEnv)` (what `:reload` uses) | not used: it takes its dirty set from the PROCESS-GLOBAL `depCache`, which every per-check copy also fills with the workspace siblings it loaded, so it would load those into the resident too; its mtime scan is reused in spirit by the manual command |
| re-boot the session on every event | not used: ~13 s per save; a leaf module and its dependents is two modules (`Byte` + `Prelude`, the smoke's case) |
| extension-side `synchronize.fileEvents` | not needed: `vscode-languageclient` turns the server's dynamic registration into a FileSystemWatcher; a client without dynamic registration can still send the notification, and has the command |

## Evidence

Gate runs on the worktree (`scripts/gate.sh`), 2026-09-18:

| Tree | compile | corpus | lsp | suites |
|---|---|---|---|---|
| 1bdf9cd7 (step 1) | PASS 36s | PASS 48s, 0 differ of 168 | PASS 49s, 587 checks (582 + 5) | PASS 881s, 1216/1216 |
| + review fixes (3ca335c8) | PASS 12s | PASS 48s, 0 differ of 168 | PASS 49s, 598 checks (587 + 11) | PASS 774s, 1216/1216 |
| step 2 (lsp-watch, 16e2f1d3) | PASS 5s | PASS 49s, 0 differ of 168 | PASS 52s, 622 checks (598 + 24) | PASS 749s, 1216/1216 |
| step 3 (branch lsp-stamp) | PASS 8s | PASS 42s, 0 differ of 168 | PASS 46s, 628 checks (622 + 6) | see below |

What the 16 new smoke checks pin (`tracker/tools/lsp-client.py`, `roots:` names). The first
server is initialised with `rootUri` + `workspaceFolders` = the checkout and
`moduleRoots = [tracker/lsp-tests/roots]`; the second with neither. Two modules exist only
for the run: `SmokeDerived` written into `core/src/main/resources/modules/` (never in
target) and a second `Shadow` written into `core/target/<scala>/classes/modules/` with
`which` on a different line than `tracker/lsp-tests/roots/Shadow.e`; both removed at exit.

| Pin | Server 1 (roots) | Server 2 (no roots) |
|---|---|---|
| boot log | names the option root, then `<checkout>/core/src/main/resources/modules` | "no module roots; the stdlib is read from the classpath" |
| `Roots.e` imports `RootOnly` (option root only) | clean; definition opens `roots/RootOnly.e` | one diagnostic, `Module not found: 'RootOnly'` |
| `Derived.e` imports `SmokeDerived` (source tree only) | clean; definition opens the source-tree file (derived boot root) | clean; same file (the document's own checkout root, per check) |
| `Shadowed.e` imports `Shadow` (option root AND classpath copy) | definition at the ROOT copy's line | definition at the CLASSPATH copy's line, path under `target/` (E9 has nothing to map it to) |
| `Nav.e` `&&` (stdlib) | 7.5 E9 pins, unchanged | definition mapped into the source tree (E9 under a classpath boot, which server 1 no longer exercises) |

Server log lines from the gate's run (`.gate-cache/<key>/lsp/lsp-server.log`):

```
module roots: <wt>/tracker/lsp-tests/roots, <wt>/core/src/main/resources/modules
session: module roots ahead of the classpath: <wt>/tracker/lsp-tests/roots, <wt>/core/src/main/resources/modules
```
and on the second server
```
module roots: none (no moduleRoots option, no workspace folder with a stdlib)
session: no module roots; the stdlib is read from the classpath
```

Review (Fable, read-only, 2026-09-18): no blocking issue; the eleven order/derived/E9
pins above, the malformed-`moduleRoots` guard in `Main`, and the prose in `Definitions`
are its findings, applied.

### Step 2 evidence (2026-09-19)

The smoke's first server (roots, dynamic registration advertised) edits `core/src/main/
resources/modules/Byte.e` ON DISK -- in the boot closure, one dependent (Prelude) -- and
`Watched.e` (imports Byte, uses the appended `smokeAdded`) is opened after each event.
The file is byte-for-byte restored at exit (also on a `timeout` kill: SIGTERM -> exit).

| Event | Server log | Watched.e |
|---|---|---|
| registration | `<< client/registerCapability ... "globPattern":"**/*.e"` before the boot; `watch: client registered the **/*.e watcher` 14 s later (reply queued behind the boot) | -- |
| append + changed | `watch: reloaded Byte, Prelude in 0.0s`; logMessage type 3 "reloaded 2 module(s): Byte, Prelude" | clean; definition of `smokeAdded` = the appended line of the source-tree file |
| revert + changed | reloaded Byte, Prelude | one `undefined term` |
| broken save + changed | `reloaded Byte, Prelude in 0.0s; FAILED: .../Byte.e:9:14: ...`; logMessage type 1 | one `import Byte failed` (the check copy tried the load) |
| good save + changed | reloaded (the pending pair) | clean |
| delete + deleted | reloaded: Byte read back from the chain's next link, the classpath copy | `undefined term` (the copy has no `smokeAdded`) |
| restore + created | reloaded, matched BY MODULE NAME under the root (the resident held Byte from the target path) | clean |
| revert + changed | reloaded | `undefined term` |
| append, no event, `ermine.reloadModules` | `reload command: reloaded Byte, Prelude`; response `{"reloaded":["Byte","Prelude"],"failure":null}` | clean |
| revert, no event, command | reloaded | `undefined term` |
| changed event for `Good.e` (never loaded by the resident) | `watch: no loaded module changed` | -- |
| unknown command | error response naming it | -- |
| second server (no dynamic registration) | no request from the server; "does not register file watchers dynamically" | -- |

Nine reloads, one FAILED, each 0.0-0.1 s (`Byte` + `Prelude`); every reload re-checked
the open fixtures (`diagnostics: reload <file>` lines) before its logMessage.

Review (Fable, read-only, 2026-09-19): server side sound; ONE blocker in extension 0.1.4 --
`vscode-languageclient`'s ExecuteCommandFeature registers every server-declared command as
a VS Code command itself (`lib/common/executeCommand.js:49`), so the extension's own
`registerCommand("ermine.reloadModules")` would throw inside `client.start()`; fixed by
dropping it (the status line moved to `middleware.executeCommand`). Also applied: a
sidecar backup makes the smoke's Byte.e cleanup SIGKILL-safe; a failed batch reload
re-scrubs and retries one module at a time so one broken file costs only its closure;
the QuickFix signature memo (keyed `(uri, version)`, which a reload does not bump) is
forgotten on reload; deletion wording in docs and Main.

### Step 3 evidence (2026-09-19)

The smoke moves the mtime of one Scala source (`core/src/main/scala/com/clarifi/reporting/
Attribute.scala`) to "now" before the first server boots and puts it back after the boot
warning (and again around the diagnostic pin); `ermine.reloadModules` re-reads the stamp.

| Pin | Result |
|---|---|
| boot with one source newer than the classes | log `stamp: NOT BUILT: 1 Scala source(s) under <wt>/core/src/main/scala newer than the classes (.../Attribute.scala at <t>; classes .../classes at <t'>)`; `window/logMessage` type 2 `Ermine: not built -- 1 Scala source(s) ... Attribute.scala ... sbt core/compile` |
| `Watched.e` (undefined term) while stale | message ends `not built: the compiled classes (<t'>) are older than 1 Scala source(s) under core/src/main/scala, newest Attribute.scala (<t>); if this name was added in Scala, run sbt core/compile and restart the server` |
| the same after the mtime is put back and the command re-reads the stamp | no hint |
| second server, fresh | `stamp: the compiled classes (<t'>) are newer than every Scala source under <wt>/core/src/main/scala` |
| the Scala file afterwards | original mtime, byte for byte untouched |

One stat walk of 178 `.scala` files per five seconds while checks run; the 2758 `.class`
files are walked once at boot.

Review (Fable, read-only, 2026-09-19): server sound; two smoke defects fixed (the temp-module
planting had slipped into `restore_stamp`, so the first server booted without `SmokeDerived`
and the roots pins passed only through per-check discovery; a killed run left the touched
mtime as the next run's "original" -- now a sidecar, as for Byte.e); scan I/O errors answer
"fresh" instead of costing a check its diagnostics; "Module not found" dropped from the
explained list; the mtime-vs-content-hash limitation documented (STALE-9).

## Decisions

| Decision | Why |
|---|---|
| Roots are ordered, classpath always last | the worst case is exactly the old behaviour; a missing root is logged and skipped, never a boot failure |
| One derivation convention, `core/src/main/resources/modules` under a folder | the same convention `Definitions.SourceTree` (E9) reads the other way; checked before use |
| The extension is not changed | `vscode-languageclient` already sends `rootUri` and `workspaceFolders`; a `moduleRoots` setting can be added when someone needs a root outside the workspace |
| No Scala unit test; the smoke is the test | nothing in core/test constructs `Resident`; the smoke boots a real server twice already |

## Tickets

- STALE-1: DONE (step 2).
- STALE-4: an open, UNSAVED buffer of a stdlib file is not what the resident holds (the reload reads disk on save); a check of that file itself uses the buffer, its importers see the saved text. Expected; documented.
- STALE-5: `Ready.builtins` is copied before the roots are installed, so `builtinEnv.loadFile` is the bare classpath loader; harmless while only `.contains` reads it.
- STALE-6: a reload publishes fresh diagnostics for every open document synchronously on the dispatch thread; with many open documents and a Prelude-level change this is one long turn (the boot's cost, once). Measured on the smoke: see evidence.
- STALE-7: `Resident.normalize` does not resolve symlinks or case, so a `moduleRoots` entry spelled through a symlink (or in another case than the folder VS Code watches) never matches an event's path; workspace-derived roots match by construction. `toRealPath` when the path exists, if it ever bites.
- STALE-8: 0.1.3 extension users get the watcher and the reloads with the new server (the client library handles both); only the palette entry **Ermine: Reload Modules** needs 0.1.4.
- STALE-2: DONE (step 3). Only `core` is compared; a name added in `parsers/` or `machines/` Scala is not covered.
- STALE-9: the stamp is mtime and zinc stamps sources by content hash, so a `.scala` whose mtime moved without a content change (branch switch leaving it identical, `cp` without `-p`, a killed smoke before the sidecar existed) reads as "newer" until some compile writes a class; `sbt core/compile` on such a tree does nothing. Accepted for a hint that says "if"; a content-hash stamp (zinc's `inc_compile_3.zip`?) is the fix if it ever bites.
- STALE-3: `Resident.checkoutRootOf` walks to the filesystem root on every check of a file outside any checkout (a handful of `stat`s); memoise per directory if it ever shows in the phase timers.
