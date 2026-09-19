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
| 2 | Invalidate on change | `workspace/didChangeWatchedFiles` on `**/*.e` (+ a manual reload command): scrub the module and its dependents from the resident env with `Session.reloadChangedModules(builtinEnv, ...)` (what `:reload` uses; `Resident.builtinEnv` exists for it) | open |
| 3 | "Not built" diagnostic | when a source module resolves but the classes on the classpath predate it (new Scala natives), say so instead of a unification error | open |

## Step 1: what changes for whom

| Client | Before | After |
|---|---|---|
| VS Code extension (sends `rootUri` + `workspaceFolders`; unchanged, 0.1.3) | classpath copy | `<workspace>/core/src/main/resources/modules` first, classpath last -- when a workspace folder IS a checkout; a folder that merely holds checkouts (`~/research/ermine`) implies no root, and only the per-check checkout root applies; several checkout folders give several roots, first folder wins |
| any client, `initializationOptions.moduleRoots: [dirs]` | n/a | those dirs first, in the order given, then the folder-derived ones, then the classpath |
| a client sending neither (the smoke's second server) | classpath copy | classpath copy, unchanged |
| a document in another checkout | that checkout's siblings only, then the booted stdlib | plus that checkout's stdlib root, for modules the boot did not load |

What step 1 does NOT do: a module the boot already loaded keeps the text it was read with
until a restart (step 2). Nothing is watched.

## Evidence

Gate runs on the worktree (`scripts/gate.sh`), 2026-09-18:

| Tree | compile | corpus | lsp | suites |
|---|---|---|---|---|
| 1bdf9cd7 (step 1) | PASS 36s | PASS 48s, 0 differ of 168 | PASS 49s, 587 checks (582 + 5) | PASS 881s, 1216/1216 |
| + review fixes | PASS 12s | PASS 48s, 0 differ of 168 | PASS 49s, 598 checks (587 + 11) | see handoff |

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

## Decisions

| Decision | Why |
|---|---|
| Roots are ordered, classpath always last | the worst case is exactly the old behaviour; a missing root is logged and skipped, never a boot failure |
| One derivation convention, `core/src/main/resources/modules` under a folder | the same convention `Definitions.SourceTree` (E9) reads the other way; checked before use |
| The extension is not changed | `vscode-languageclient` already sends `rootUri` and `workspaceFolders`; a `moduleRoots` setting can be added when someone needs a root outside the workspace |
| No Scala unit test; the smoke is the test | nothing in core/test constructs `Resident`; the smoke boots a real server twice already |

## Tickets

- STALE-1: step 2 (watch + `reloadChangedModules`; reload command).
- STALE-2: step 3 ("not built" diagnostic).
- STALE-3: `Resident.checkoutRootOf` walks to the filesystem root on every check of a file outside any checkout (a handful of `stat`s); memoise per directory if it ever shows in the phase timers.
