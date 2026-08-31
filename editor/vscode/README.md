# Ermine for VS Code

Syntax highlighting plus a client for `bin/ermine-lsp`: diagnostics as you type,
go-to-definition, and hover types.

## Install

```sh
cd editor/vscode
npm install
```

Then either **run it from source** —

```sh
code --extensionDevelopmentPath="$PWD" /path/to/ermine-scala
```

— or **package and install it**:

```sh
npx @vscode/vsce package          # -> ermine-lang-0.1.0.vsix
code --install-extension ermine-lang-0.1.0.vsix
```

Open the `ermine-scala` folder as your workspace. The extension finds
`bin/ermine-lsp` inside the first workspace folder; point `ermine.serverPath`
elsewhere if your layout differs.

## What you get

| | |
|---|---|
| Syntax highlighting | keywords, literals, comments, operators, constructors, declaration heads |
| Diagnostics | on open, on save, and ~300ms after you stop typing — no save needed |
| Go to definition | same file, workspace siblings, and the stdlib |
| Hover | inferred types for top-level and imported names |

Local binders hover empty on purpose — that is gated on
`tracker/TICKET-perf-type-inference.md`, not on this extension.

## Fast mode

`ermine.fastMode` (or **Ermine: Toggle Fast Mode**) skips type checking. On a
1757-line module the check splits roughly 0.80s read + 0.45s typecheck, so this
is about half the time to diagnostics.

**Kept:** syntax errors, shadowing refusals, unknown operators, interleaved
equations, every lowering diagnostic — and all navigation, plus hover on
*imported* names.

**Lost:** every type error, the "unchecked: depends on a broken definition"
notes, import-list export requirements, and hover on this module's *own*
top-level names. Nothing but the type check computes those.

The inference cache is carried forward while fast mode is on, so switching back
does not start cold.

## First run is slow, on purpose

Three costs, in the order you meet them:

1. **The classpath cache.** `bin/ermine-lsp` builds it with sbt on a cold
   checkout. The extension does this up front as a cancellable notification
   rather than letting it happen invisibly inside the server — that is what
   `ermine.warmClasspathOnStart` controls. Turning it off does not make it
   faster, only silent.
2. **Session boot, ~13s.** The server loads the Prelude/Layout closure with
   type checking on and interface files off (a stale `.ei` would let type
   errors through, and definition targets would land in interface text rather
   than source). The status bar tracks it. Navigation requests during boot
   answer empty immediately instead of queueing behind it.
3. **Per-check cost.** Roughly 1.6s on the largest stdlib module, well under
   that on ordinary files. Unchanged binding groups are not re-inferred between
   keystrokes.

## Settings

| Setting | Default | |
|---|---|---|
| `ermine.serverPath` | *(workspace)* | Path to `bin/ermine-lsp` |
| `ermine.fastMode` | `false` | Skip type checking |
| `ermine.logFile` | *(off)* | Sets `ERMINE_LSP_LOG` |
| `ermine.warmClasspathOnStart` | `true` | Build the sbt cache visibly, before starting |
| `ermine.trace.server` | `off` | Trace LSP traffic to the output channel |

Commands: **Ermine: Restart Language Server**, **Ermine: Toggle Fast Mode**,
**Ermine: Show Language Server Output**.

## One highlighting rule that will surprise you

`--` starts a line comment **unconditionally**, so `-->` is a comment, not an
operator. That is this implementation's rule, not Haskell's — see
`ParsingUtil.scala:133`, which carries a standing TODO about it, and
`StatementExtents.scala`, which independently does the same. The grammar
matches the implementation. Block comments nest.

## Development

The grammar is derived from the lexer, not from Haskell intuition; the reasoning
is in the `_readme` key at the top of `syntaxes/ermine.tmLanguage.json`.

Server-side changes are covered by `tracker/tools/lsp-smoke.sh`, which includes
fast-mode checks. Run it with `core/test` and `repl-smoke.sh` before committing.

## Tests

```sh
npm test           # both of the below
npm run test:load  # loads and activates the extension, then talks to the server
npm run test:grammar
```

Neither needs VS Code.

**`test/load-test.js`** stubs the `vscode` module in the loader and calls
`activate()` exactly as the editor would, then checks that every command
package.json contributes is registered, that activation returns without
waiting on the server, and that `deactivate()` is safe after a failed start.

Its last step is live: it waits for the status bar to carry the server's own
`session ready: 129 modules in …s`, which only `Main.scala` can produce. That
one assertion covers the whole chain — the client spawned `bin/ermine-lsp`,
the handshake completed, the session booted, and `window/logMessage` came back
through `vscode-languageclient` into this extension's handler. It skips itself
if `target/ermine-classpath` is missing, and takes ~15s when it runs.

**`test/grammar-test.py`** is a small TextMate tokenizer (context stack,
begin/end, ordered patterns) run over the 180-file corpus. It pins the rules
that differ from Haskell intuition — `--` unconditional, `if` as a function,
`'` and `` ` `` as ordinary operators, `_Module` affixes as single tokens — and
checks that no regex can match empty, which would hang the real tokenizer.

Node was not previously a dependency of this repo. `npm test` needs it; nothing
else here does.
