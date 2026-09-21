# Ermine for VS Code

Syntax highlighting plus a client for `bin/ermine-lsp`: diagnostics as you type,
go-to-definition, hover types, find references, rename, outlines, completion and
two quick fixes.

The extension and the server live on the `scala3-migration` branch only. The
`backport-2.11` branch builds the language on Scala 2.11 and has neither; see
the top-level `README.md` for what each branch is for.

## Building and installing

### What you need

| | |
|---|---|
| VS Code | 1.75 or newer (`engines.vscode` in `package.json`) |
| Node.js and npm | for `npm install`, packaging and the tests. Nothing else in the repository needs Node |
| A JDK, 17 or newer | runs the server. `bin/ermine-lsp` uses `$JAVA_HOME/bin/java` if `JAVA_HOME` is set and `java` from `PATH` otherwise |
| sbt 1.x | builds the server's classpath once, on first run |
| A checkout of `ermine-scala` on `scala3-migration` | the server is `bin/ermine-lsp` inside it; the extension is not self-contained |

### 1. Build the server

The server is the `core` module of the sbt build. Compile it once so the first
editor session does not start with a cold sbt compile:

```sh
cd /path/to/ermine-scala
sbt compile
```

`bin/ermine-lsp` then builds its classpath with sbt on first run and caches it
in `target/ermine-classpath`. Delete that file after changing dependencies. You
can check the server starts on its own before involving the editor:

```sh
tracker/tools/lsp-smoke.sh        # needs tracker/repl-classpath.txt, see the top-level README
```

### 2. Build the extension

```sh
cd editor/vscode
npm install
```

### 3. Run it from source, or package and install it

**From source**, in an Extension Development Host window:

```sh
code --extensionDevelopmentPath="$PWD" /path/to/ermine-scala
```

**Packaged**, as a `.vsix` you can install into any VS Code (the file is
gitignored, so build it yourself):

```sh
npx @vscode/vsce package          # -> ermine-lang-0.1.8.vsix
code --install-extension ermine-lang-0.1.8.vsix
```

`npm run package` does the same. Upgrading is the same command with the new
file; VS Code replaces the installed version.

### 4. Open the workspace

Open the `ermine-scala` folder as your workspace. The extension finds
`bin/ermine-lsp` inside the first workspace folder and starts it when the
first `.e` file is opened. If the checkout is somewhere else, or you opened a
different folder, set `ermine.serverPath` to the absolute path of that
`bin/ermine-lsp`.

The first start builds the classpath cache (visibly, as a cancellable
notification) and then boots the session, about 12–14 s; the status bar tracks
both. See "First run is slow, on purpose" below.

### Checking the installation

`npm test` in `editor/vscode` loads the extension the way the editor would and,
if `target/ermine-classpath` exists, starts the real server and waits for its
`session ready` line — see "Tests" at the end. In the editor itself, **Ermine:
Show Language Server Output** shows the server's log, and `ermine.logFile`
writes it to a file.

## What you get

Everything below one line is served by `vscode-languageclient` straight from
the capabilities the server advertises at `initialize`. This extension adds no
provider of its own and filters none away — it exists for the syntax grammar,
the status bar, the settings and the sbt warm-up.

| | |
|---|---|
| Syntax highlighting | keywords, literals, comments, operators, constructors, declaration heads |
| Diagnostics | on open, on save, and after you stop typing — no save needed. The quiet window is adaptive: `clamp(150 ms, the document's own median check time, 300 ms)`, so a small file answers in 150 ms and only the biggest modules wait the full 300. Every failure, not the first; an import that will not load is squiggled on its own `import` line |
| Go to definition | equations, signatures, local binders, `field` and `table` declarations, data constructors, foreign declarations, type names, fixity mentions, and `import` module names — same file, workspace siblings, and the stdlib |
| Hover | the inferred or declared type of a top-level, imported or declared name; the **type of every local binder** — `let` and `where` heads (with their full published scheme, constraints included), a binder with its own signature, a plain-variable argument of an equation, a lambda's argument, a `case` or `do` binder, and a variable nested inside a constructor or tuple pattern; the **kind** of a type name. Over the corpus that is 5054 of 5083 value-local binders; the 29 that stay silent are variables bound to a rank-N constructor field |
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

## Preview (no panel yet)

A **report** is any top-level binding whose type is `Node`, `Params -> Node`,
`Fetch Node` or `Params -> Fetch Node`. The preview renders one, on the
server, in a second session of its own, and re-renders it when a file it
depends on is saved — with no JVM restart and no build.

At 0.1.8 there is **no webview panel** (that is a later ticket): the answer is
shown as JSON in an ordinary editor tab. Parameters come from a file you write
yourself — see **Params files** below; with no such file the render still sends
empty parameters, so a report with required ones shows the refusal that names
the first missing key rather than a document.

| Command | |
|---|---|
| **Ermine: Preview Report...** | picks a `.e` file (the active editor's first), then a binding from the list the server computes **by type** — `binding : type`, with a free-text fallback for a binding it did not list. The pick is remembered per workspace and renders immediately |
| **Ermine: Render Report to JSON** | renders the remembered pick again into the same tab (and runs the picker if nothing is picked yet) |

One untitled JSON tab is reused and updated in place. A successful render
shows the document; a refusal shows the whole `{ok:false, status, message,
path}` answer, because `message` and `path` together are the diagnostic. A
report with required parameters and no parameters yet reads

```json
{
  "ok": false,
  "status": 400,
  "message": "the required key \"fromDay\" is missing",
  "path": "$.params",
  "generation": 1
}
```

— the missing key is named in the message, at the path of the object that
should have held it; a key that is present but of the wrong type is reported
at its own path, `"$.params.fromDay"`.

The loop after that is automatic: saving a file the report depends on makes
the server send `ermine/preview/invalidated`, and the tab re-renders. Every
render carries a generation counter and an answer behind the current one is
discarded, so a save during a render never shows a stale document. A report
whose file the server cannot even read — picked before it existed, or moved
away and back — is watched at its own path and re-renders when it reappears.

An automatic re-render **updates the tab where it is and never pulls it in
front of what you are editing**; only the two commands reveal it. The tab is
untitled and the updates leave it dirty, so closing it offers to save a
throwaway render: choose **Don't Save**. (A real panel is a later ticket; this
is one of the reasons for it.)

A status bar item on the right says which report is picked, and turns into a
warning when the preview is **stuck** (a render that never finished — the
server's watchdog) with an error notification offering **Restart Language
Server**, or **offline** when the server has stopped — which wins over
"stuck", because a wedged server exits about two minutes after the watchdog
fires. When it comes back the last render is re-sent — **unless it is the
render that wedged the server and nothing has changed since**, and then you
are asked first (0.1.6, below).

A stuck preview can also be ended by the extension itself, by restarting the
language server after a grace — `ermine.preview.restartAfterStuckSeconds`,
**off by default** (0.1.7, below).

Settings: `ermine.preview.roots` (per folder), `ermine.preview.timeoutSeconds`
(`0` turns the watchdog off, which is rarely what you want — see its
description), `ermine.preview.maxDocumentBytes` and
`ermine.preview.restartAfterStuckSeconds` (client-side only; nothing about it
is sent to the server). The first three reach a running server at once, with
no restart; `ermine.maxHeap` is the one that needs a fresh process, and
changing it restarts the server.

## Params files

A report that takes parameters reads them from an ordinary file in your
workspace:

```
<workspace folder>/.ermine/preview/<Module>/<binding>.params.json
```

so `Sales.report` reads `.ermine/preview/Sales/report.params.json`. The
directory is one entry per module — `Layout.Widgets.Foo` is one directory
name, not three — and the file is named after the binding. **You write it
yourself at 0.1.8**; the extension does not create one, does not write a JSON
schema beside it and does not add a `.gitignore` (those are the next ticket).
The file is ordinary committed source: whoever clones the repository renders
the same first document.

**Local workspaces only.** The params file is addressed by its path on your
own machine, so a `vscode-remote:` or virtual workspace is not supported by
this feature — the file is neither read nor watched there. (Everything else
about the preview is local too: the language server is a process on the same
machine.)

**It is read from DISK at the moment a render is sent, not from the editor
buffer.** The preview follows saves, like every other part of the loop, so an
unsaved edit changes nothing until you save it. Saving it re-renders the
report in place, and so does a change from outside the editor — a `git
checkout`, a script, another program. One save costs one render, whichever of
the two notices it first.

A `"$schema"` key at the TOP level of the file is stripped before the
parameters are sent, so you can point your editor at a JSON schema without the
server refusing the request: every request key is closed, and MEASURED against
a real server, a `$schema` that reaches it answers `400 the key "$schema" is
not allowed here`. Nested `$schema` keys are NOT stripped — only the top-level
one — and would be refused the same way.

**It is preview-only.** `bin/ermine-serve` never reads these files: the HTTP
runner takes its parameters from the request body and nothing else. A
committed preview default must not quietly become a production one.

**Never put a credential in one.** It is committed to the repository AND its
value is written into the render body that reaches the language server's log
(`ermine.logFile`). The extension warns once per file when a top-level key
looks like one — it matches `pass`, `pwd`, `secret`, `token` and `apiKey` —
and never blocks, because a report may legitimately take a `token` parameter.
That check is on the KEY NAME only: it says nothing about a key called
`connectionString`, `dsn`, `jwt`, `auth`, `bearer`, `privateKey` or
`credential`.

What happens when the file is not usable, and each is said in the Ermine
output channel once per report rather than once per render:

| | |
|---|---|
| there is no file | the report renders with empty parameters `{}` — exactly what it did before 0.1.8 |
| the report is not inside any workspace folder | the same, and the reason is named once. Nothing is read or written outside the folders you opened |
| the file is not valid JSON | **the report is NOT rendered.** The tab shows the parse error and the file's path; rendering yesterday's parameters under today's file would look like it worked |
| the file is empty | the same refusal, with its own sentence: an empty file is not `{}`, it is a truncated write or an interrupted checkout |
| the file is over 1 MiB | the same refusal, naming the size |
| the file exists but cannot be read | the same refusal. A file that is there and unreadable is not a file that is absent |
| the file is bigger than 1 MiB | the same refusal, **without reading it**: the size is checked first, so a huge file cannot be pulled into the editor before the cap looks at it |
| the read does not finish within 5 seconds | the same refusal, named. A read that hangs is not a read that failed, and the render must not wait for ever |
| the file was deleted | the next render sends `{}` and says so |
| a value has the wrong type, or a key does not belong | the server answers `400` and the tab shows it, with the key named in `message` and, for a present-but-wrong value, the path in `path` |

A refusal is not a wedge: nothing is marked, nothing is restarted, and the
next save tries again.

**If the report wedged the language server, saving its params file without
changing them asks before re-rendering.** Re-formatting the file, running
format-on-save or moving its `$schema` line does not change what is sent, so
the preview treats it the way it treats a restart: the **Render anyway** /
**Not now** question of 0.1.6, and the status bar stays `Ermine preview:
held`. Changing an actual value clears the hold and renders.

**It asks once.** If you answer **Not now**, further saves that still change
nothing do not ask again — they say so in the output channel and the status
bar keeps reading `held`. Editing a real value, restarting the language
server, or rendering it yourself all make it ask (or render) again. The same
holds for the other things that are not evidence of change: learning a
report's module name, and an `ermine.preview.roots` edit that resolves to the
same list.

## Two things that will surprise you

**The FIRST check of a file you just opened costs about 2.5 s; every keystroke
after it costs about 0.9 s.** A fresh buffer has nothing to reuse, so the whole
file is parsed and every binding group inferred; from the second check on, one
statement re-parses and the inference cache keeps what the edit did not touch.
The cache is the reason, and it is not free: about **1.6 MB of heap per open
document** the size of the 1757-line `Layout/Report.e` (mostly the surface tree
itself), released when you close the document, plus **30–70 ms** on that first
check for building the statement index.

**Some edits check cold anyway.** The per-document inference cache is keyed on
the file's SCOPE — its imports, its type/data/class/instance/field/foreign
declarations, its fixity declarations, and its `private` and `database` blocks.
Edit inside one of those, or inside a definition whose name is not a plain word
(an operator, a backtick name, a spelling with `_` or `'` in it), and the whole
cache drops and the file is re-inferred from scratch: about 1.6 s instead of
0.9 s on that module. This is deliberate — those are the edits that can change
what every other name in the file MEANS — and it is the one place where a
keystroke is slower than the average.

### Fixed in 0.1.3 (server-side; the client did not change)

**A local binder inside a `case`, a `do` or a lambda now hovers.** Its type
used to exist only inside the checker's pattern inference and was never
written back where the editor could read it. The checker now records it where
it mints it, behind a flag only the editor path sets, so batch checking pays
one boolean test and observes nothing. Coverage over the corpus went from 3079
to 5054 of 5083 local binders; the 29 that remain are variables bound to a
rank-N constructor field (`data Alt f = Alt (forall a. f a)`), whose
polymorphic type neither mechanism can express. Two limits stay: a strict
(`!x`) or lazy (`~x`) argument answers nothing, and a binder of a local that
is used at two types shows its FIRST instantiation (ticket E15). `docs/lsp.md`
has the exact rules.

**A `let` or `where` head hovers its published scheme.** It used to show the
type one frame early and without its constraints (`go : List a -> a -> a` for
a `go` held at `forall a. Num a => List a -> a -> a`); it now renders the
scheme the checker generalised, like a top-level hover does. Pattern binders
and equation arguments stay monotypes.

### 0.1.8

**A report's parameters come from a file you write.**
`.ermine/preview/<Module>/<binding>.params.json` in the workspace folder that
holds the report is read from disk when a render is sent, and its contents are
sent as the report's parameters; saving it, or changing it from outside the
editor, re-renders the report in place. A top-level `"$schema"` key is
stripped before sending. There is still no skeleton, no generated schema file
and no `.gitignore` — you write the file, the extension reads it. See **Params
files** above for where it lives, what is refused and what must never go in
one.

Nothing is written to disk by this version, and nothing about it reaches
`bin/ermine-serve`: the HTTP runner does not read these files and never will.

**A params save while a report is *held* asks first if nothing changed.** A
report that wedged the server is not re-rendered automatically (0.1.6); since
0.1.8 that also covers everything that is not evidence that something
changed — a params file saved without changing what it sends (a re-format,
format-on-save, a moved `$schema` line), an `ermine.preview.roots` edit that
resolves to the same list, and learning a report's module name. You get the
same **Render anyway** / **Not now** question, asked once rather than once per
save. Editing a real value clears the hold and renders straight away.

Two smaller things that come with it. A params file whose whole content is
`null` is now sent as `null` rather than as `{}` — which is what a report
whose parameter type is a `Maybe` wants, and what the older coercion would
have turned into an unexplainable 400. And changing the parameters a report
was rendered with now counts as "something changed" for the wedge question of
0.1.6: if the report that wedged the server is one whose parameters you have
since edited, the restart re-renders it instead of asking. Re-formatting the
file, or pointing its `$schema` line somewhere else, is not a change — the
comparison is of what is actually sent.

### 0.1.7

**The extension can restart a wedged language server itself, and by default
does not.** A render that never finishes leaves the preview stuck until the
JVM runs out of heap — about two minutes after the watchdog fires — and a
wedge that allocates nothing never ends at all. With
`ermine.preview.restartAfterStuckSeconds` set to a number of seconds, the
extension starts a grace when the preview goes stuck and, if nothing has come
back when it expires, stops and restarts its own language client. The grace is
cancelled if the render returns (a slow report is not a wedged one), if the
server stops or is restarted for any other reason, or if you set the number
back to 0. **The default is 0 = never**, because nobody has yet run this
extension in a real editor: the steps that would check it are in
`tracker/WP-7-MANUAL-CHECKLIST.md` and none of them has been run.

The report that wedged is remembered before the restart happens, so the fresh
server does **not** re-render it: the same **Render anyway** / **Not now**
question from 0.1.6 is what you get, and the status bar reads
`Ermine preview: held`. While the grace runs, the stuck notification and the
status bar tooltip say when the restart will happen and which setting stops
it — and if you set the number while the preview is *already* stuck, that
incident is restarted too.

Two restarts are never closer together than 30 seconds, whatever the setting
says; a grace that would land inside those 30 seconds waits for them, and
tells you the longer number *and why it is longer* rather than one it cannot
keep. **Your own "Ermine: Restart Language Server" is never refused or
delayed by any of this** — if an automatic restart is already running, or is
stuck waiting for a server that will not stop, yours takes over, and the
extension is left talking to exactly one language server. That is not quite
the same as only one *process*: if a stop times out, the extension says so
in its output channel, tells you the old server may still be alive, and
names the check (`ps -ef | grep lsp.Main`) so you can end it yourself. If a
restart cannot happen (nothing is picked, so nothing would hold the
re-render afterwards), you are told, in a notification and in the status bar
tooltip, not only in the output channel.

One thing to know if you ever go back to **0.1.6**: a report that wedged
under 0.1.7 may be remembered in a form 0.1.6 does not recognise, and 0.1.6
will then re-render it once after a restart instead of asking. Save the file
or pick another report first, or just let the one prompt happen.

### 0.1.6

**A report that wedged the server is not re-rendered automatically.** A
render that never finishes ends with the server out of heap, and the client
restarts it — which used to re-send the same render, wedging it again; so
did the **Restart Language Server** button in the stuck notification. The
extension now remembers that the picked report wedged, and after a restart
asks **Render anyway** / **Not now** instead of rendering, with the status bar
reading `Ermine preview: held`. The memory is forgotten as soon as anything
could have changed the answer: the server says the report's module was
invalidated, any `.e` file is saved, the pick or the preview roots change, the
wedged evaluation comes back by itself, or you render it on purpose. Nothing
else is suppressed — a save still re-renders at once.

### 0.1.5

**The preview loop, with no panel.** Two commands, one untitled JSON tab, a
status bar item and four new settings — see "Preview (no panel yet)" above.
The webview panel and parameter files are separate tickets; nothing here
renders a document into a view.

### 0.1.4

**Stdlib edits are live.** The server reads the stdlib from
`core/src/main/resources/modules` under the workspace (not the build output),
registers a watcher on every `.e` file, and when a file it has loaded changes
on disk it reloads that module and the modules that import it, then re-checks
the open documents. A save that the watcher did not report (or a change made
outside the editor) is picked up by **Ermine: Reload Modules**, which reloads
every loaded file whose modification time moved. No `sbt core/copyResources`,
no restart. If a reloaded file does not load (saved broken, or deleted), the
server says so and the session lacks those modules until a later save
succeeds.

### Fixed in 0.1.2

**Stdlib navigation lands in the source tree.** A stdlib definition, reference
or workspace symbol used to open `core/target/…/classes/modules` — the copy the
resident session actually loads — where an edit was lost at the next
`copyResources`. The server now maps that back to
`core/src/main/resources/modules`, deriving the pair from the class loader
rather than hard-coding a Scala version, and falling back to the old behaviour
when no source tree is there (ticket E9).

**Tab-indented lines are in the right units.** A tab is one character to LSP and
eight columns to the parser; every range on such a line used to land seven
characters per tab to the right of the text it named, and rename refused
outright behind a tab. The conversion now happens at the boundary in both
directions, so diagnostics, hover, highlight and rename all land on the text
(ticket E8).

## Fast mode

`ermine.fastMode` (or **Ermine: Toggle Fast Mode**) skips type checking. On the
largest stdlib module a warm check now splits 0.05 s read + 0.53 s typecheck of
a 0.61 s check — the read used to be 0.85 s of it — so fast mode takes most of
the remaining time off, and, because the quiet window tracks the measured check
time, it shortens the wait before the check as well.

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
3. **Per-check cost.** ~0.9 s on the largest stdlib module (1757 lines,
   `Layout/Report.e`) on a quiet machine — it was ~1.7 s before Stage 4 — and
   0.17–0.42 s on ordinary files. One statement re-parses per keystroke and
   unchanged binding groups are not re-inferred, so almost all of what is left
   is the type check. Dispatch is single-threaded by design, so a hover or a
   completion that arrives WHILE a check is running waits for it — about 0.54 s
   on that module (it was 1.45 s), and imperceptible on a normal one.

## Settings

| Setting | Default | |
|---|---|---|
| `ermine.serverPath` | *(workspace)* | Path to `bin/ermine-lsp` |
| `ermine.fastMode` | `false` | Skip type checking |
| `ermine.logFile` | *(off)* | Sets `ERMINE_LSP_LOG` |
| `ermine.warmClasspathOnStart` | `true` | Build the sbt cache visibly, before starting |
| `ermine.maxHeap` | *(launcher's `2g`)* | `-Xmx` for the server, as `ERMINE_LSP_XMX`; changing it restarts the server |
| `ermine.preview.roots` | `[]` | Extra module roots for the preview, per workspace folder, sent absolute |
| `ermine.preview.timeoutSeconds` | `60` | The preview's evaluation watchdog; `0` turns it off (no restart needed) |
| `ermine.preview.restartAfterStuckSeconds` | `0` *(never)* | How long the preview may stay stuck before the extension restarts the language server itself; client-side only, never sent to the server |
| `ermine.preview.maxDocumentBytes` | `16777216` | Largest rendered document the server will send |
| `ermine.trace.server` | `off` | Trace LSP traffic to the output channel |

Commands: **Ermine: Restart Language Server**, **Ermine: Toggle Fast Mode**,
**Ermine: Show Language Server Output**, **Ermine: Reload Modules** (declared
by the server and registered by the language client; the extension only adds
the status-bar line), **Ermine: Preview Report...** and **Ermine: Render
Report to JSON**.

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
npm test              # all three of the below
npm run test:preview  # the preview loop's decisions, pure functions, no server
npm run test:load     # loads and activates the extension, then talks to the server
npm run test:grammar
```

None of them needs VS Code.

**`test/preview-core.test.js`** covers `src/preview-core.js`, which holds the
preview loop's decisions and imports no editor API: root absolutisation, the
generation discard, the stuck state machine (the highest `seq` wins, the mark
resets on a restart, an answer's marker is per-request, an accepted clear
always re-renders), the two re-render rules, the three request builders —
including that a render and a schema for one pick carry the SAME roots — both
quick-pick lists, the status bar's text and precedence (now including
`held`), the wedge guard's whole lifecycle and its one consultation, the
restart timer's whole lifecycle — its arm, its disarms, the stale-timer rule
and the 30-second floor — an async model of the restart itself, which is
where the interleavings live (a restart during the first-run classpath
warm-up, during a stop, one taking over another), the two settings payloads and the `ermine.maxHeap`
spelling. Since 0.1.8 it also covers the params file: where one lives, which
workspace folder owns the report, what its text becomes, what each refusal
says, and which render triggers must ask before re-rendering a report that
wedged — and a second async model, of the render's own send path, because
reading the file puts an `await` between deciding to render and sending, and
every way the world can move in that gap (the pick changes, the roots change
*in place*, a newer render starts, the server is restarted or merely stops,
the window is torn down) is driven by hand there. What
is NOT there is the glue that needs an editor to observe: when a document is
created or revealed, the watcher's registration, the coalescing timer. It runs
under `node --test` with no `node_modules` at all.

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
