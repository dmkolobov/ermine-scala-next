# Ermine for VS Code

Syntax highlighting plus a client for `bin/ermine-lsp`: diagnostics as you type,
go-to-definition, hover types, find references, rename, outlines, completion and
two quick fixes.

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
npx @vscode/vsce package          # -> ermine-lang-0.1.1.vsix
code --install-extension ermine-lang-0.1.1.vsix
```

Open the `ermine-scala` folder as your workspace. The extension finds
`bin/ermine-lsp` inside the first workspace folder; point `ermine.serverPath`
elsewhere if your layout differs.

## What you get

Everything below one line is served by `vscode-languageclient` straight from
the capabilities the server advertises at `initialize`. This extension adds no
provider of its own and filters none away — it exists for the syntax grammar,
the status bar, the settings and the sbt warm-up.

| | |
|---|---|
| Syntax highlighting | keywords, literals, comments, operators, constructors, declaration heads |
| Diagnostics | on open, on save, and ~300 ms after you stop typing — no save needed. Every failure, not the first; an import that will not load is squiggled on its own `import` line |
| Go to definition | equations, signatures, local binders, `field` and `table` declarations, data constructors, foreign declarations, type names, fixity mentions, and `import` module names — same file, workspace siblings, and the stdlib |
| Hover | the inferred or declared type of a top-level, imported or declared name; the **type of a local binder** — `let`, `where`, a binder with its own signature, and a plain-variable argument of an equation (when the binding's own type shows `arity` arrows and that argument's type is a monotype); the **kind** of a type name |
| Find references / highlight | every mention of a local in its file; every mention of a global across the buffers you have OPEN |
| Rename | one atomic `WorkspaceEdit` over that set, or a refusal with a reason — never a partial edit |
| Outline / breadcrumbs | `textDocument/documentSymbol`, one symbol per top-level group, constructors nested under their type |
| Go to symbol in workspace | your open buffers plus the whole stdlib, ranked, capped at 200 |
| Completion | locals, this module's own names, imported names, module names after `import`, and a module's names after `Module.` — from the last check, never a fresh one |
| Quick fixes | **add import** on an undefined term (it edits an existing `using` list, or writes a new `import` line), and **add type signature** on an unsigned top-level binding — plus "add all missing signatures" for the file |

`docs/lsp.md` is the full reference: what each of those covers, and what it
does not.

Names Scala installs rather than source declares (`Just`, `True`, `Int`,
`Maybe` — all of `Builtin`) have no file to open and no source position, so
go-to-definition answers nothing on them and they are not listed in the
workspace symbol picker.

## Three things that will surprise you

**A stdlib definition opens in `core/target/…/classes/modules`, not in
`core/src/main/resources/modules`.** The language server's resident session
loads its 129 modules from the classpath, where `sbt core/copyResources` puts a
COPY of the source tree, so that is where every stdlib position points — for
go-to-definition and for the workspace symbol picker alike. Browsing is fine;
**editing the file you land in is not** — the next `copyResources` overwrites
it. Ticket E9 in `tracker/TICKET-stdlib-findings.md`.

**On a TAB-indented line every range is in the wrong units.** The parser
expands a tab to the next eight-column stop and LSP counts characters, so a
diagnostic, a hover target or a highlight on such a line lands to the right of
the real text by seven columns per tab. Rename refuses outright on a name
behind a tab rather than corrupting the file. Ermine sources are
space-indented almost everywhere (one file in the 253-file corpus has tabs).
Ticket E8.

**A local binder inside a `case`, a `do` or a lambda still hovers empty.** Its
type exists only inside the checker's pattern inference and is never written
back where the editor can read it; hover answers nothing rather than guessing.
`let`, `where`, signed binders and an equation's plain-variable arguments DO
hover — the last of those by reconstruction from the binding's own type, so it
needs that type to show `arity` arrows and the argument's own type to be a
monotype; a strict (`!x`) or lazy (`~x`) argument answers nothing.

## Fast mode

`ermine.fastMode` (or **Ermine: Toggle Fast Mode**) skips type checking. On the
largest stdlib module a check splits roughly 0.94 s read + 0.60 s typecheck, so
this is about a third off the time to diagnostics.

**Kept:** syntax errors, shadowing refusals, unknown operators, interleaved
equations, every lowering diagnostic, import failures — and all navigation,
plus hover on *imported* names and on imported type names' kinds.

**Lost:** every type error, the "unchecked: depends on a broken definition"
notes, import-list export requirements, hover on this module's *own*
definitions, and hover on every local binder. Nothing but the type check
computes those. Navigation to this module's own fields and constructors
survives, since their positions come from the surface tree rather than from the
check.

The inference cache is carried forward while fast mode is on, so switching back
does not start cold.

## First run is slow, on purpose

Three costs, in the order you meet them:

1. **The classpath cache.** `bin/ermine-lsp` builds it with sbt on a cold
   checkout. The extension does this up front as a cancellable notification
   rather than letting it happen invisibly inside the server — that is what
   `ermine.warmClasspathOnStart` controls. Turning it off does not make it
   faster, only silent.
2. **Session boot, ~12–14 s.** The server loads the Prelude/Layout closure with
   type checking on and interface files off (a stale `.ei` would let type errors
   through, and definition targets would land in interface text rather than
   source). The status bar tracks it. Requests that arrive before the boot
   starts answer empty immediately instead of queueing behind it.
3. **Per-check cost.** ~1.7 s on the largest stdlib module (1757 lines) on a
   quiet machine, ~1.9 s on a busy one, and well under that on ordinary files. Unchanged binding groups are not re-inferred
   between keystrokes. Dispatch is single-threaded by design, so a hover or a
   completion that arrives WHILE a check is running waits for it — up to about
   1.5 s on that module, and imperceptible on a normal one.

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

There is no setting for the completion trigger character, the code-action
kinds or anything else the protocol negotiates: the server advertises them and
the client obeys.

## One highlighting rule that will surprise you

`--` starts a line comment **unconditionally**, so `-->` is a comment, not an
operator. That is this implementation's rule, not Haskell's — see
`ParsingUtil.scala:133`, which carries a standing TODO about it, and
`StatementExtents.scala`, which independently does the same. The grammar
matches the implementation. Block comments nest.

The grammar is also what renders a hover: the server sends its types in a
` ```ermine ` fenced block, and VS Code tokenizes that fence with the grammar
this extension contributes.

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
through `vscode-languageclient` into this extension's handler. It then checks
that the client registered a provider for every capability the server
advertises (nine of them), that the server's `.` completion trigger reached the
editor, and that its `quickfix`/`source` code-action kinds did. It skips itself
if `target/ermine-classpath` is missing, and takes ~15 s when it runs.

**`test/grammar-test.py`** is a small TextMate tokenizer (context stack,
begin/end, ordered patterns) run over the whole corpus (359 `.e` files —
it globs both source trees unfiltered rather than using the 253-file checked
corpus). It pins the rules that differ from Haskell intuition — `--` unconditional, `if` as a function,
`'` and `` ` `` as ordinary operators, `_Module` affixes as single tokens — and
checks that no regex can match empty, which would hang the real tokenizer.

Node was not previously a dependency of this repo. `npm test` needs it; nothing
else here does.
