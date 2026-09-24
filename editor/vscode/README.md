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
npx @vscode/vsce package          # -> ermine-lang-0.1.15.vsix
code --install-extension ermine-lang-0.1.15.vsix
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

## Preview

A **report** is a top-level binding whose type is `Params -> Node` or
`Params -> Fetch Node`. The binding picker also offers a zero-parameter
binding (`report : Node`), but the server refuses it at render with a 400,
*"… is not a report: a report must be a function Params -> Node, not Node"*
(playtest finding F2, see **0.1.15**). The preview renders one, on the
server, in a second session of its own, and re-renders it when a file it
depends on is saved — with no JVM restart and no build.

**Since 0.1.12 the answer is drawn in a webview panel** beside the editor
(`ermine.preview.target`, default `panel`; see **0.1.12** below). The JSON tab
described in the rest of this section is still there, unchanged, with
`ermine.preview.target` set to `json` (or `both`, for the two at once) — it is
the verbatim view of every `status`, `message`, `path` and `reason`.

**The panel needs the client bundle, which is not built by default** (it is
git-ignored). The first time you open it you will most likely see *"The
preview bundle is not built"* and the path it looked in. Build it once in the
checkout that holds `bin/ermine-lsp`:

```sh
cd client && npm install && npm run bundle
```

and the open panel loads the page by itself (since 0.1.13 it watches the bundle
folder; running **Ermine: Preview Report...** again also works). A
directory with only one of `ermine-client.js` / `ermine-host.js` in it is
reported as **HALF-BUILT** — delete `client/dist/browser` and bundle again.

**The legacy widgets need the writers** (`table`, `drilldownTable`, the
charts, `styleBox`; since 0.1.14). The panel loads the `ermine-writers`
bundle from `ermine.preview.writersPath`; empty means
`<checkout>/../ermine-writers/writers/html/src/main/resources/web`, the sibling
checkout — **that default is the layout of the machine this was built on, not
a guarantee**. Without `htmlwriter.js` there the panel still loads,
`scorecard`, `headline`, `crosstab`, `heading` and `text` still draw, each legacy widget shows an
error box, and a banner says where it looked (see **0.1.14**).

**Working on the client?** Run `npm run bundle:watch` in `client/` and leave
it running: every save of a `client/src` file rebuilds the bundle, and the open
panel reloads itself about a quarter of a second after the build's last write
— once per build, keeping the last document (see **0.1.13**).

Parameters come from a file you write
yourself — see **Params files** below; with no such file the render still sends
empty parameters, so a report with required ones shows the refusal that names
the first missing key rather than a document.

| Command | |
|---|---|
| **Ermine: Preview Report...** | picks a `.e` file (the active editor's first), then a binding from the list the server computes **by type** — `binding : type`, with a free-text fallback for a binding it did not list. The pick is remembered per workspace and renders immediately |
| **Ermine: Render Report to JSON** | renders the remembered pick again into the same panel or tab (and runs the picker if nothing is picked yet) |

With `ermine.preview.target` at `json` or `both`, one untitled JSON tab is
reused and updated in place. A successful render
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
throwaway render: choose **Don't Save**. (This is one of the reasons for the
panel, which has no such prompt.) The panel follows the same rule: **only the
two commands open or reveal it**, and an automatic re-render updates it in
place — including when it is hidden behind another tab.

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
name, not three — and the file is named after the binding. The file is
ordinary committed source: whoever clones the repository renders the same
first document.

**The first pick of a report that has none writes three files** (0.1.9), and
then opens the params file beside the render without taking the cursor out of
whatever you are typing:

| file | what it is | committed? |
|---|---|---|
| `.ermine/preview/<Module>/<binding>.params.json` | a skeleton from the report's parameter type: required keys only, today for a date, `Maybe` keys left out. **Yours. Edit it, commit it** | **yes** |
| `.ermine/preview/<Module>/<binding>.schema.json` | the JSON Schema the `"$schema"` line above points at, generated from the parameter type | no — ignored |
| `.ermine/preview/.gitignore` | generated once per workspace folder; ignores `*.schema.json` and `*.db` and says in the file itself that the `*.params.json` beside them are not ignored | yes, it is tiny |

**The params file is NEVER overwritten by anything automatic.** Not on a
second pick, not on a restart, not when the parameter type changes: the
extension only ever *creates* it, through an editor operation that skips a
file which is already there, and then reads the file back to be sure of what
is on disk. If a `git checkout` or another window puts one there while the
schema is being worked out, yours is what stays. The **schema** file is the
generated one and is rewritten whenever the parameter type moves, and only
when its bytes really change — so saving a `.e` file does not churn it, or the
editor's cache of it.

**The one thing that replaces it is a command you run: `Ermine: Write Params
Skeleton`** (0.1.10). Use it when the report's parameter type has changed and
you would rather start from a fresh skeleton than patch the file by hand. It
asks first, in a modal that names the file and says the contents will be
replaced; **Escape, Cancel and anything but the `Replace` button leave the
file exactly as it is**, and nothing is asked of the language server until you
have answered. It then refreshes the generated schema file beside it, opens
the params file, and re-renders. If there is no params file it behaves like a
first pick — nothing to lose, so nothing to confirm. If you change the picked
report while the question is on screen, it writes nothing and says so. **If
the file itself changes after you were asked** — you, or `files.autoSave`,
save it while the question is on screen or while the schema is being worked
out — it writes nothing and says so by name: run the command again to replace
what is there now. An explicit command is consent, so it also runs for a
report that wedged the language server; the hold is cleared **only once the
file has been written** and the render is on its way. A command that writes
nothing — declined, refused, or failed — leaves the hold exactly as it was.

**A left-over params file is pointed out, never deleted.** Rename or remove a
report's binding (or make it `private`) and its params file stays behind
under the old name, still
committed, still looking current. When the preview next lists that file's
reports it compares them with the params files under
`.ermine/preview/<Module>/` and, once per left-over file per session, says so:
which file it is, that nothing reads it, that it is yours to delete, and a
**Write Params Skeleton** button that writes a fresh skeleton for the report
you have picked now. **Nothing is ever deleted for you.** If the server could
not list that file's reports — a parse error, a module that does not
compile — nothing is called stale.

**A renamed MODULE is not covered**, and that is a known gap rather than a
surprise: the whole `.ermine/preview/<OldModule>/` directory is then stale and
nothing looks inside it. Finding out would mean asking the server which module
every `.e` file in the workspace declares, and each of those answers compiles
a module. The directory is visible in `git status` like any other committed
file.

**The one exception, stated because it is your committed source:** if the
create leaves a file of **zero length** — which happens only if this VS Code
honours the create but drops the initial contents — the skeleton is written
into it. Nothing else is ever written over: not whitespace, not a newline,
not a file that merely looks empty. And nothing is written *through a
symbolic link*: if the params file, the schema file, the `.gitignore` or any
`.ermine` directory above them is a link, the preview refuses, says which
path stopped it, and renders with empty parameters — it cannot tell where a
link points, and a file written through one would land outside the folder you
opened.

This repository's own `.gitignore` carries the one line that matches the
generated schemas, `**/.ermine/preview/**/*.schema.json`. **The extension
does not edit your root `.gitignore`**: the file it writes is the
self-contained one beside the generated files, which works in every workspace
folder without touching anything you maintain.

**When nothing can be written** — a read-only workspace, a report outside
every workspace folder, a module name that is not known yet, a binding that
cannot be a filename, a parameter type with no finite smallest value — the
report still renders with empty parameters and the Ermine output channel says
why, once per report. A parameter type that is not a JSON object
(`report : Int -> Node`) gets its params file *without* a `$schema` line,
because a JSON number has nowhere to put one, and the notice says the editor
will not validate that file; the server still does.

**Since 0.1.10 that notice also says what the value IS**, because "not a JSON
object" leaves you opening the file to guess. Every shape the exporter can put
at the root was measured against a real server, and each renders:

| the report takes | the file holds | the notice says |
|---|---|---|
| `Int -> Node` | `0` | its parameters are a single whole number |
| an all-nullary `data` (`Spring \| Summer \| Autumn`) | `"Spring"` | one of `"Spring"`, `"Summer"`, `"Autumn"` |
| `Maybe String -> Node` | `null` | optional (a single string); `null` means there is none |
| `Json -> Node` | `null` | any JSON value at all |
| `() -> Node` | `[]` | the empty tuple `()`, and there is nothing in it to edit |

**Working out the parameter schema runs the report.** It compiles the module
and evaluates the binding on the same queue a render uses, so it is not a
free lookup: a report that wedged the language server is asked about with the
same **Render anyway** / **Not now** question a render gets, and while the
preview is stuck the request is refused outright.

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

### 0.1.15

The first two findings of the first real playtest (2026-09-23, VS Code with
0.1.14 installed).

**F1, fixed: the panel refused VS Code's own `cspSource`.** With
`ermine.preview.target` at `panel`, every render showed *"the preview page
could not be built: buildPreviewHtml: cspSource "'self'
https://*.vscode-cdn.net" contains a character that would change the policy"*.
VS Code's real `webview.cspSource` is a space-separated LIST of CSP source
expressions, one of them a quoted keyword (`'self' https://*.vscode-cdn.net`,
MEASURED in that playtest); the 0.1.14 guard refused every space and quote, and
every test had used a single bare token. The guard now splits the value on
spaces/tabs and accepts each token only if it is exactly one CSP source
expression: a quoted keyword (`'self'`), a scheme (`https:`), or a host with an
optional scheme, `*.` wildcard, port and path. Anything else (`;`, `,`, `"`,
`<`, `>`, `&`, `\`, a newline, an unquoted `self`) is still refused, naming the
token. The policy itself is unchanged: `cspSource` is substituted verbatim, so
for the real value the page's CSP is `default-src 'none'; script-src 'self'
https://*.vscode-cdn.net 'unsafe-eval'; style-src 'self'
https://*.vscode-cdn.net 'unsafe-inline'; img-src 'self'
https://*.vscode-cdn.net data:;` (pinned by a test).

**F2, recorded, not fixed: a zero-parameter report is refused.** Picking
`core/src/test/resources/modules/Doc/SalesReport.e` → `report` (`report :
Node`) answers 400 *"Doc.SalesReport.report is not a report: a report must be
a function Params -> Node, not Node"*. The picker offers bare `Node` bindings on
purpose, the runner refuses them; the **Preview** section above said `Node` was
a report type and now says what is true. Whether the runner should accept
`Node` or the picker should stop offering it is the user's decision (Q27 in
`tracker/JSON-WIDGET-PLAYGROUND.md`). Until then the panel's playtest steps use
the typed `core/src/test/resources/doc/Sales.e`.

### 0.1.14

**The legacy writers in the panel** (WP-11, stage 4 of the panel). The page
now loads the `ermine-writers` bundle first, then the client and host bundles,
plus three of the writers' style sheets.

| | |
|---|---|
| **where** | `ermine.preview.writersPath` (new, window scope): the writers' `web/` folder. A relative path is resolved against the first workspace folder, exactly as `ermine.preview.roots` is. **Empty = `<checkout>/../ermine-writers/writers/html/src/main/resources/web`**, `<checkout>` being the checkout that holds `bin/ermine-lsp` (the parent of its `bin/`) — the sibling layout of the machine this was built on, **not a guarantee** |
| **what loads** | `htmlwriter.js` (5.2 MB; jQuery and Highcharts are bundled inside it, so there is no other script), then `ermine-client.js`, then `ermine-host.js` — plain `<script src>`, in that order, because the writers assign `window.ermine_htmlwriter` in a `DOMContentLoaded` listener that must be registered before the page's own. Style sheets: `common.css`, `htmlwriter.css`, `htmlwriter_classic.css`. **Not** `htmlwriter_dark.css` (it re-adds DataTables' sort arrows through a sprite image the webview cannot load, so every arrow would be an empty box) and **not** `javafxwriter.css` (JavaFX). The writers folder becomes the page's second `localResourceRoots` entry; the CSP is unchanged from 0.1.11 (`'unsafe-eval'` is there for this bundle, a webpack-4 `eval` build) |
| **writers missing** | no `htmlwriter.js` in that folder (or no folder): the page loads **without** the writers, `scorecard` / `headline` / `crosstab` / `heading` / `text` draw, each legacy widget draws its own error box naming what it needed (the tables `window.ermine_htmlwriter`, the charts the writers' missing `run…` function), and the panel's banner says *"the legacy writers are not loaded: no htmlwriter.js in …"* with the path and the setting to fix — plus **one** line in the Ermine output channel per page built. The banner is the panel's ordinary error banner, so **the document below it is dimmed** while the writers are missing. A failed render keeps its own error banner and the writers sentence is appended to it. **The same banner also hides *re-rendering***: an error outranks it, so while the writers are missing (or half there) a render in flight shows nothing until its answer lands, and in the **half** state below the whole document is dimmed too, although its widgets draw |
| **half** | `htmlwriter.js` present but a style sheet missing: the script and the sheets that exist load, and the banner names what is missing (the widgets draw unstyled) |
| **fixing it** | the writers folder is **not watched**. After setting the path (or checking the writers out), run **Ermine: Preview Report...** again: a panel built without the whole writers re-checks on an explicit command and reloads only if the answer changed (a machine without the writers is not reloaded on every command). A bundle rebuild (`bundle:watch`) re-checks too, and so does a new panel. Restarting the language server does not |
| **expected console noise** | in the webview's developer tools (**Developer: Open Webview Developer Tools**): `common.css` references `url("/CIQDotNet/images/TopMenuBar/tmbllsprite.png?urwvid=1")` (on `.headerlabel`), a root-relative sprite that is neither under the webview's resource root nor allowed by `img-src`, so the webview refuses it — a blocked-image line is **expected, not a broken panel**. The other sprite the design review named, `url("/content/themes/base/images/mainSprite.png")`, is in `htmlwriter_dark.css`, which the panel does not load, so it should not appear |
| **by design, not a failure** | a click in a **style box** does nothing: the writers' click-through always posts to a server, and the page's CSP (`default-src 'none'`, no `connect-src`) blocks it; the legacy code reports it through its own error callback and nothing throws. **`treeMap`** stays unregistered, so it is always the error box naming it |

**None of this has run in VS Code or a browser.** Whether the writers bundle
loads under the CSP, whether `table` draws through `runTabular`, whether a
`pieChart` draws and what the console shows are the playtest's (E3, E9-E11).
What the tests hold is what the extension decides: the page it builds, the
roots it grants, the banner it sends and when it re-checks.

**Amended by WP-10 stage 5 (still 0.1.14):** a `writersPath` that is an array
now reads *"is a directory path, not an array"* (it said *"not a array"*), and
the six `ermine.preview.roots` refusal texts are pinned word for word by a test;
`ermine.preview.target` refuses an array as *"not an array"* too; and the panel's
refusal of a deferred relation no longer claims every relation is inline (see
**0.1.12**'s *deferred relations* row). That last one is a `client/` change, so
it takes effect after `npm run bundle` in `client/`; the `.vsix` does not carry
the bundle.
The playtest steps for all of the above are Group E of
`tracker/WP-7-MANUAL-CHECKLIST.md`.

### 0.1.13

**The panel follows the bundle** (WP-10 stage 3). While a panel is open the
extension watches the bundle folder — `<checkout>/client/dist/browser`, the
same folder the page loads from (`<checkout>` is the checkout that holds `bin/ermine-lsp`:
the parent of `ermine.serverPath`'s `bin/`, or the first workspace folder) — for `*.js` files, so
the `.js.map` files never fire it.

| | |
|---|---|
| **one build, one reload** | one webpack build writes four files. Every create, change or delete pushes ONE shared deadline 250 ms out; only a quiet 250 ms reloads the page, once. Two builds more than 250 ms apart are two reloads |
| **what you see** | the first write of a build puts *"the client bundle changed; reloading"* over the page; when the build is quiet the page is replaced (a fresh `?v=` stamp on both scripts, so the new code loads) and the new page is sent the whole state again, so the last document comes back without a render. Scroll and drilldown are lost |
| **the bundle vanishes** | deleting the bundle FILES (`rm client/dist/browser/*.js`) turns the panel into the static *not built* page; one entry without the other is the *HALF-BUILT* page; a build that brings both back turns it into the page again — no command needed. **Deleting the FOLDER (`rm -rf client/dist/browser`) probably does NOT flip it**: the typings say a watched path that is deleted makes the watcher *"suspend and not report any events until the path is created again"*, and that a folder delete may be folded into one event for the folder, which `*.js` does not match. The page then stays up (its scripts are already loaded) until the next build, or the next **Ermine: Preview Report...**, which re-checks. Each change writes one reload line in the Ermine output channel, and a not-whole bundle a second, naming what is missing |
| **a render in flight** | an answer that arrives while the page is being replaced is not lost: the new page's `ready` carries it |
| **only with a panel** | no panel, no watcher: it is created with the panel and disposed with it (and when the window closes) |
| **deferred relations** | still refused by name: the page's `fetchData` rejects with *"this preview does not fetch deferred relations, and the report asked for deferred delivery of "…" (the panel has no network access: its CSP has no connect-src)"* (reworded by WP-10 stage 5: the 0.1.13 text claimed every relation is delivered inline, which is false for `Sales.e`), which the widget's own error box shows, and nothing is fetched. The page's CSP has no `connect-src`, and a test pins that it never will |

**`npm run bundle:watch`** in `client/` runs `tsc --watch` and `webpack --watch`
together; with it running, a save of `client/src/widgets/scorecard.ts` becomes a
banner, then the redrawn panel, with no restart. What the vendored typings
say, and nobody has observed ((`editor/vscode/node_modules/@types/vscode/index.d.ts:13977-13979` and `:13996-14001`)): "paths that do not exist in the file system will be monitored with a delay until created and then watched depending on the parameters provided. If a watched path is deleted, the watcher will suspend and not report any events until the path is created again." and "file events from deleting a folder may not include events for the contained files. [...] performance optimizations are in place to fold multiple events that all belong to the same parent operation (e.g. delete folder) into one event for that parent." So the not-built first
run should recover when the folder is created (after a delay), and deleting the
folder should be silent until it is created again. Whenever the watcher stays
silent, the next **Ermine: Preview Report...** re-checks, as in 0.1.12; playtest
step E8 records which of these actually happens. **None of this has run in VS
Code yet.**

### 0.1.12

**The preview panel** (WP-10 stage 2). The two preview commands now show the
report in a webview panel beside the editor, created on the first explicit
render and revealed (without taking focus) by every later one. There is ONE
panel per window; closing it is fine — the next command makes a new one.

| | |
|---|---|
| **`ermine.preview.target`** | `panel` (default), `json` or `both`. `json` is the 0.1.11 tab, **byte for byte** — the tab code did not change. An unknown value is refused once in the output channel and the default used |
| **what the panel shows** | the last good document, with a banner above it: *stuck* (with the one button, **Restart Language Server**, which runs the same command as the palette), *held*, *offline* (the document kept, dimmed), an *error* (`status: message (path)`, the last good document dimmed below it; in fast mode it adds that type errors are not shown in Problems), *re-rendering*, or *Pick a report* when nothing has rendered yet. Picking another report withdraws the old document at once |
| **the bundle** | loaded from `<checkout>/client/dist/browser/` — `<checkout>` is the checkout that holds `bin/ermine-lsp` (the parent of `ermine.serverPath`'s `bin/`, or the first workspace folder). **Not built** and **HALF-BUILT** are a static page that says so, with the path, plus one line in the Ermine output channel. There is no watcher yet (stage 3, **0.1.13**): after building, run the command again |
| **the page's own log** | anything the page wants to say — a widget that failed, a document it could not read — arrives in the Ermine output channel as `preview panel: ...` |
| **deferred relations** | the preview never produces one (every relation is inline), so the page's `fetchData` refuses by name; a widget that asked would show its own error box. **Amended by WP-10 stage 5: that first clause is FALSE** for a report that asks for `Deferred` itself (`core/src/test/resources/doc/Sales.e` does; its render holds a token), and such a table IS the error box. The refusal now reads *"this preview does not fetch deferred relations, and the report asked for deferred delivery of "…""*; what to do about it is an open question (Q24 in the tracker) |
| **not yet** | the `unsaved` hint (no producer), the bundle watcher, the writers' legacy renderers (`table`, charts: WP-11), a Render anyway button in the panel (the held question stays a notification) |

**The protocol, extension -> panel, is ONE message:**

```js
{ kind: "snapshot", seq: 12, messages: [ /* panelMessagesFor(view): render?, error?, stale, stuck, held, offline, switching, unsaved, reloadBundle? */ ] }
```

— the whole state every time, never a loose message, because a hidden webview
may drop any post and one flag (`reloading`) has no falling edge of its own.
The page folds `messages` from a fresh state, ignores an envelope whose `seq`
is not above the last one it applied, and re-draws the document only when its
generation or payload changed (so a *re-rendering* toggle keeps scroll and
drilldown). Nothing is posted until the page says `ready`; the extension
re-sends the snapshot on `ready` and whenever the panel becomes visible again.
**Panel -> extension** is `{type: "ready"}`, `{type: "intent", kind:
"restartServer"}` and `{type: "log", message}`; anything else is logged and
ignored. The new exports behind this are `panelSnapshot`, `panelInbound`,
`presentRoute`, `previewBundleDir` / `previewBundleCheck` /
`previewResourceRoots` and `buildPanelNoticeHtml`.

**None of this has run in VS Code yet.** It is tested in node (models of the
glue, a JSDOM page) and nothing else; the playtest's panel group is stage 5.

### 0.1.11

**Nothing you can see changed.** 0.1.11 is the pure half of the webview panel
(WP-10 stage 1): functions in `src/preview-core.js` that decide what the panel
will be told and what page it will load. `src/extension.js` does not call any
of them yet — no panel is created, nothing is posted, no setting was added.

| Export | What it is |
|---|---|
| `panelMessagesFor(view)` | the whole extension -> panel protocol: the ordered messages of `client/src/host/index.ts`'s nine kinds (`render`, `error`, `stale`, `stuck`, `held`, `offline`, `switching`, `unsaved`, `reloadBundle`) for one view. It is a **snapshot**, not a delta: every latch is sent on both edges, so a panel that missed posts while hidden is put right by the next list |
| `panelView(parts)` | the one builder of that view, from the extension's own state: `answers`, `stuckState` (the arbitrated wedge and the offline flag), the wedge `mark` + `pick` + `restartedByUs` (through `heldMessage`), `pending`, `unsaved`, `fastMode`, `switching` (no producer yet), `reloading` |
| `panelAnswerStep(answers, outcome, current)`, `initialPanelAnswers()` | folds one render outcome — `{answer}` or `{rejection, generation}` — into the last answer and the last good one: a displaced render (`-32800`) and an answer behind the current generation change nothing |
| `unsavedNames(documents)` | the dirty Ermine documents by base name, for the `unsaved` hint |
| `panelTarget(raw)`, `PANEL_TARGETS` | the contract of the coming `ermine.preview.target` setting: `panel` (default), `json` or `both` |
| `buildPreviewHtml(uris, opts)`, `previewCsp(cspSource)`, `PREVIEW_ROOT_ID` | the host page: one CSP line, the writers' CSS links (optional), a root element and three classic `<script src>` tags in the order writers -> client -> host, with **no inline script at all** |
| `FAST_MODE_SUFFIX`, `PANEL_MESSAGE_KINDS` | the fast-mode sentence an `error` gains, and the nine kinds |

**The panel's Content-Security-Policy**, exactly, on one line:

```
default-src 'none'; script-src ${cspSource} 'unsafe-eval'; style-src ${cspSource} 'unsafe-inline'; img-src ${cspSource} data:;
```

`'unsafe-eval'` is there for the committed `ermine-writers` bundle (a webpack-4
`eval` build) and in this webview only; the client's own bundles contain no
`eval`. There is no nonce because there is no inline script, no `blob:` and no
`font-src` because the writers bundle uses neither, and no `connect-src`
(`default-src 'none'`), so the panel can make no network request.

### 0.1.10

**`Ermine: Write Params Skeleton`**, a command you run, is the only thing in
this extension that replaces a params file — and it asks first, in a modal
that names the file and says the contents will be replaced. Escape, Cancel and
every answer but the `Replace` button leave the file alone, and nothing is
asked of the language server until you have answered. It then refreshes the
generated schema file, opens the params file and re-renders. With no params
file it behaves like a first pick: nothing to lose, so nothing to confirm.
Change the picked report while the question is on screen and it writes nothing
and says so; so does a params file that changes after you were asked. The
wedge hold is cleared only once the file is written.

**A left-over params file is pointed out.** Rename or remove a report's
binding and its params file stays behind under the old name. The preview now
compares the bindings the server offers for a file with the params files under
`.ermine/preview/<Module>/` and says, once per left-over file per session,
which file it is, that nothing reads it, and that it is yours to delete —
with a **Write Params Skeleton** button for the report you have picked now.
**It never deletes anything.** A server that could not list the file's reports
calls nothing stale, and a renamed *module* is not covered (see **Params
files**).

**A params file whose root is not a JSON object now says what it holds.** All
five shapes the exporter can produce there were measured against a real server
and all five render: `Int` (`0`), an all-nullary `data` (`"Spring"`),
`Maybe X` (`null`), `Json` (`null`) and `()` (`[]`).

**Nothing else moved.** No server change, no wire change, and the automatic
paths still cannot overwrite a params file: the permission to replace one is
an argument the command passes and nothing else does.

### 0.1.9

**The first pick of a report that has no params file writes one.** Picking
`Sales.report` in a workspace with nothing under `.ermine/preview/` now asks
the language server for the report's parameter schema, writes three files and
opens the params file beside the render:

```
.ermine/preview/.gitignore                  (generated; ignores *.schema.json and *.db)
.ermine/preview/Sales/report.schema.json    (generated from the parameter type)
.ermine/preview/Sales/report.params.json    (a skeleton, for you to edit and commit)
```

The skeleton is the smallest value the parameter type accepts: required keys
only, `""` / `0` / `false` / the first `enum` member / **today** for a date,
and `Maybe` keys left out entirely. It carries a relative
`"$schema": "./report.schema.json"` line, so the editor completes the keys and
the enum values and squiggles a wrong one; the line itself is stripped before
the parameters are sent. `git status` then shows the params file and NOT the
schema file, which is the point of the generated `.gitignore`.

**When nothing is written**, the report still renders with empty parameters
`{}` and the Ermine output channel says why, once per report: a read-only
workspace, a report outside every workspace folder, a report whose module name
is not known yet, a binding that cannot be a filename, or a parameter type
with no finite smallest value. A parameter type that is not a JSON object
(`report : Int -> Node`) gets its params file without a `$schema` line, and
the notice says the editor will not validate it — the server still does.

**A report that wedged the language server is not asked for a schema
either.** Working out the parameter schema compiles and *evaluates* the report
on the same queue a render runs on, so it is guarded by the same **Render
anyway** / **Not now** question as a render is, and refused while the preview
is stuck.

**The params file is never overwritten** — not on a second pick, not on a
restart, not when the parameter type changes. The one exception, and what
happens with symbolic links, are in **Params files** above.

**Known, and not this version's to decide:** with today's dates the skeleton
for the example `Sales.report` selects no rows, and the first render is a
`500` — *"an empty relation built from no rows carries no columns"*. Edit
`fromDay`/`toDay` into 2026-01-05..2026-03-17 and it renders. See Q21 in
`tracker/JSON-WIDGET-PLAYGROUND.md`. **Since 2026-09-23** (Q21 decided by the
user) `Sales.e` gives that table a header with `relationWithHeader`, so the
first render is a document with an empty table; a report that builds an empty
relation with plain `relation` still gets the `500` (ticket WP-29).

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
status bar item and four new settings — see "Preview" above.
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
| `ermine.preview.target` | `panel` | Where a render is shown: the webview `panel`, the `json` tab (0.1.11's, unchanged), or `both` |
| `ermine.preview.writersPath` | *(sibling `ermine-writers`)* | The legacy writers' `web/` folder the panel loads `htmlwriter.js` and its CSS from; empty = `<checkout>/../ermine-writers/writers/html/src/main/resources/web`, this machine's layout, not a guarantee |
| `ermine.trace.server` | `off` | Trace LSP traffic to the output channel |

| Command | |
|---|---|
| **Ermine: Restart Language Server** | Stops the server and starts a fresh one |
| **Ermine: Toggle Fast Mode** | Flips `ermine.fastMode` for this workspace |
| **Ermine: Show Language Server Output** | Opens the Ermine output channel |
| **Ermine: Reload Modules** | Declared by the *server* and registered by the language client; the extension only adds the status-bar line |
| **Ermine: Preview Report...** | Picks a file and a binding, and renders it |
| **Ermine: Render Report to JSON** | Re-renders the picked report into the same panel or tab |
| **Ermine: Write Params Skeleton** | Replaces the picked report's params file with a fresh skeleton, **after a modal you answer** — see **Params files**. The only thing in this extension that overwrites a params file |

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
the window is torn down) is driven by hand there. **Since 0.1.9** it covers
the first pick that writes: which of the schema and the render goes first,
when the generated schema file is worth re-asking for, what each way an
`ermine/schema` answer can fail turns into, which bytes go to which path in
which order, and a third async model — the whole first-pick sequence over a
model disk, with the same interleavings plus a params file appearing during
the schema request, a read-only workspace, and an editor that creates the
file without its contents. What is NOT there is the glue that needs an editor
to observe: when a document is created or revealed, the watcher's
registration, the coalescing timer, and whether `WorkspaceEdit.createFile`
really is an atomic create. **Since 0.1.11** it covers the panel's pure half:
the CSP character for character, the script order and the absence of any
inline script, each of the nine message kinds, and `panelMessagesFor` over
real answers captured from `bin/ermine-lsp` (`test/fixtures/panel-answers.json`,
whose `_note` says how). **Since 0.1.12** it covers the panel's glue: the
envelope, the inbound messages, the target routes, the fail-closed bundle
check and its static page; a fourth async model — the panel glue statement for
statement over a fake panel that drops posts while hidden and throws after
dispose — driven through `ready` before and after the first answer, a hidden
panel, a close and a teardown mid-render, two overlapping commands and a
random interleaving explorer; and source pins that `extension.js` keeps that
shape (one `createWebviewPanel`, one guarded `postMessage`, the latch consumed
once, `showAnswer` byte-identical). **Since 0.1.13** it covers the bundle
watcher: the coalescer over a fake clock (one reload per four-file build, two
for two builds apart), the notice page on a vanished or half-built bundle and
the page again on its return, a reload in the middle of a render, the watcher's
lifetime, a random explorer, source pins for the one watcher and its three
arms, the CSP's absent `connect-src`, and `gate_client`'s three verdicts over a
stub `npm`. **Since 0.1.14** it covers the writers: the page's script order and
three style sheets, their escaping and the exact CSP; `writersState` over
listings (fail-closed on `htmlwriter.js`); `ermine.preview.writersPath`
through the roots' absolutiser and its sibling default; the second
`localResourceRoots` entry; the banner as the `error` kind; the re-check on an
explicit command and on a bundle rebuild, in the panel model; source pins for
the one roots list, the setting and the output line; and a test that the
model's view passes exactly the glue's fields. It runs under `node --test` with no
`node_modules` at all, and it is the `extension` gate of `scripts/gate.sh`
(commit tier).

**`test/load-test.js`** stubs the `vscode` module in the loader and calls
`activate()` exactly as the editor would, then checks that every command
package.json contributes is registered, that `ermine.preview.target` is
contributed with the values and default `preview-core.js` decides with, that
`ermine.preview.writersPath` is a window-scoped string whose empty default
resolves to the sibling writers folder (it prints whether that folder is
there), that
activation creates no webview panel, that activation returns without
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
