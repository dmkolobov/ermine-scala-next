# Ermine language server

`bin/ermine-lsp` speaks LSP over stdio. On `initialize`/`initialized` it boots a
resident Ermine session — `Lib.preamble` plus the Prelude/Layout closure, type
checking on, interface files off, 129 modules in about 12–15 seconds, reported
through `window/logMessage` — and then answers requests.

Two rules shape everything below, and are worth reading before the feature list:

- **A request never starts work.** Hover, definition, references, highlight,
  rename, symbols, completion and code actions all answer from the tables the
  LAST CHECK left behind, plus (for completion and the import quick fix) the
  current buffer text read lexically. Nothing on a request path parses, infers
  or checks. The cost of that is *staleness*, which is stated where it bites
  rather than papered over.
- **Dispatch is single-threaded**, because a `SessionEnv` is not thread-safe.
  A request that arrives while a check is running waits for the check. On the
  largest module in the stdlib that wait is about 1.5 s; on an ordinary file it
  is imperceptible. A worker-thread check is a design fork that has not been
  taken.

The advertised capabilities are `textDocumentSync` (FULL), `definitionProvider`,
`hoverProvider`, `referencesProvider`, `documentHighlightProvider`,
`renameProvider` (with `prepareProvider`), `documentSymbolProvider`,
`workspaceSymbolProvider`, `completionProvider` (trigger character `.`, no
`resolve`) and `codeActionProvider` (kinds `quickfix` and `source`).
`tracker/lsp-tests/G3-demo.txt` is a scripted run over all of them, with the
protocol traffic and the timings.

## Diagnostics

Published on `didOpen`, on `didSave`, and ~300 ms after the last `didChange` —
no save required. Checking runs against the open BUFFER, for this file and its
workspace siblings alike, so a cross-file check sees unsaved edits. Every check
uses a fresh copy of the resident session, so a broken file poisons nothing.

A file gets **all** of its diagnostics, not just the first: every unparseable
statement, every shadowing refusal, every unknown operator, and every
independent type error. Syntax errors are blamed where the parser actually gave
up, including inside `where`/`let` blocks. The healthy definitions of a broken
file are still type checked; whatever depends on something broken is reported
"unchecked: depends on a broken definition" rather than inferred against
unconstrained metavariables.

**An import that will not load** — a module that does not exist, or one whose
file has a syntax error of its own — is reported ON ITS OWN `import` statement,
squiggling the module name, with the loader's own message (which names the
failing file and the position inside it) after an `import X failed:` prefix.
Each failing import gets its own diagnostic, so one broken import cannot hide
another, and the file is checked anyway: its other diagnostics, its navigation
and its hovers all still work. Fixing a broken sibling in ITS buffer clears the
importing file's diagnostic — but not until the importer is CHECKED again, and
the server does not re-check the dependents of an edited buffer. In practice
that means the next time you touch the importing file (or open or save it); no
save is needed anywhere, but a squiggle that is already fixed can sit there
until you go back to it.

While an import has failed, the editor withholds the notes that are merely
consequences of the names that never arrived: "undefined term" and "unchecked:
depends on a broken definition" are suppressed for that check — the import
failure is the error to act on, and a file's worth of undefined names on top of
it is noise. (The same rule already applies while a statement is too broken to
parse.) It is deliberately blunt: a genuine typo goes quiet until the import is
fixed.

**Two consequences of a missing import are NOT withheld.** An operator the
module would have supplied still draws "unknown operator", plus the two
lowering diagnostics that follow it — three per use. A type it would have
supplied still draws "undefined type". Neither is a note the suppression filter
can reach: the operator's three are read-phase DIAGNOSTICS rather than notes at
all, and the type one is a note that carries no name — the flag the rule keys
on. And the same three diagnostics are exactly right for a genuinely mistyped
operator in a file whose imports are all fine, so telling the two apart needs a
change the editor has not made.

**One position is still wrong.** A refusal raised against a whole BINDING GROUP
— rather than against a term inside it — carries the module's own position and
publishes at line 1, column 1. Nothing in the 253-file corpus does this; the
examples are in `core/examples/shouldfail`. Every other editor-path diagnostic
is where the parser or the checker put it, which is pinned as a property over
289 files.

## Go to definition

For every name that has a source position: equations, signatures and local
binders; `field` and `table` declarations; data constructors; foreign
declarations; type names (`data`, `type`, `class`, `foreign data`) and their
aliases; the operator named in a fixity declaration; and the module named by an
`import`, which opens its file. Same file, workspace siblings, and the stdlib
alike. It works on the healthy statements of a broken file, and follows a
sibling's unsaved edits.

Names installed by Scala rather than declared in source — `Just`, `True`, `Int`,
`Maybe`, the `Relation` type and the rest of `Builtin` — answer null, because
there is no source to open.

**A stdlib target opens the BUILD OUTPUT, not the source tree.** The resident
session loads its 129 modules from the classpath, where `sbt core/copyResources`
puts a copy of `core/src/main/resources/modules`, so a stdlib definition (and a
stdlib workspace-symbol hit) is reported at
`core/target/scala-3.3.8/classes/modules/Bool.e:19` rather than at the file you
would edit. Reading is fine; **editing what you land in is not** — the next
`copyResources` overwrites it. Tracked as ticket E9 in
`tracker/TICKET-stdlib-findings.md`.

## Hover

The inferred or declared type of a top-level, imported or declared name
(`Nav.twice : forall a. a -> a`, `GroupBy.value : Field (|value|) Double`),
including at the declaration itself. The type is sent as a ` ```ermine ` fenced
markdown block, so an editor with an Ermine grammar highlights it.

A **type name** hovers with its KIND — `Builtin.Bool : *`,
`Locals.Boxed : * -> *` — imported and own alike, at a mention and at the
declaration head. Builtin type atoms (`->`, `*`, rho) have no constructor and
answer null.

A **local binder** hovers with the type the last check gave it, at its def-site
and at every use, with no `forall` and with still-free metas rendered as type
variables (`idy : a -> a`). What that covers:

- **a `let` or `where` binding** — its solved monotype, or its declaration when
  it carries an explicit signature (shown AS DECLARED);
- **an ARGUMENT of an equation**, top-level or in a `where`, at any depth —
  under three conditions, because the type is RECONSTRUCTED from the binding's
  own type rather than read off the binder: the argument must be a plain
  variable (`f !x` and `f ~x` answer null, and so does a variable inside a
  constructor or tuple pattern); the binding's type must unfold to exactly
  `arity` arrows, or NOTHING is recorded for that binding; and the argument's
  own type must be a monotype (a rank-N argument is skipped, because a `forall`
  on a local is what the rendering rule forbids);
- **a pattern binder that carries a signature.**

Over the 253-file corpus that is 3156 of 5056 local binders — 62.4 %, with the
three classes above complete (0 misses). What it does NOT cover is the other
1900: **a lambda's argument, a `case` alternative's binder, a `do` binder, and a
variable nested inside a constructor or tuple pattern.** Their types exist only
inside `Subst.inferPatternType`, which mints a fresh variable per pattern into a
copy of the body and writes nothing back, so the editor answers null rather than
guessing. Recovering them is a change to the shared type checker and has not
been made (`tracker/loopmodel/LSP3-6.2-LOCALS.md`).

An equation's arguments are read off the binding's own type by its arity, so
their type variables are the SAME ones the binding's hover shows:
`konst : forall a b. a -> b -> a` gives `k : a` and `j : b`, never `a` and `a`.
One caveat worth knowing: that agreement holds WITHIN a binding. A local's type
variables are named independently of the ENCLOSING binding's, so the same letter
in two hovers need not be the same variable — a `where` helper may hover
`h : a -> a` inside a binding whose own hover calls that variable `b`.

In fast mode no local answers at all — nothing computes them.

## Find references, document highlight

From the same index. What the set is depends on the name:

A **local** — a `let` or `where` binding, an equation argument, a `case`, `do`
or lambda binder, a type variable — is a renamer binder id, so the set is every
mention of it in THAT FILE, plus the def-site itself when
`context.includeDeclaration` asks for it. Highlight marks the def-site Write and
the uses Read.

A **global** — this module's own top level, a `data`/`type`/`class` head, a
constructor, a `field`, a `table`, a foreign declaration, or a name imported
from anywhere — is a canonical name, chased through any re-export chain to the
module that DEFINES it (`Prelude` re-exports `Bool`, and a use of `not` reached
through `Prelude` is the same name as `Bool.e`'s own), so the set is every
mention in every OPEN BUFFER: uses, the defining module's signature and equation
heads, its declaration head, its fixity line, and the `import M using n` entries
that name it. An ALIAS-imported mention counts: the key is the canonical origin,
not the spelling. The def-site is in the set even when its file is not open.
Document highlight is always per-document.

**COVERAGE: the workspace is the OPEN BUFFERS.** A module that imports the name
but is not open is not searched, and the server cannot know whether one exists —
so every global references or rename request sends one `window/showMessage`
warning saying how many open files were searched. There is no persistent
workspace index.

Two things are incomplete without a refusal, both harmless: an OPERATOR's
mentions inside an `import M using (<+>)` list are not indexed (its fixity
cannot be recovered from that spelling), so a references request on an operator
misses them — and a multi-equation definition's def-site is its LAST equation,
so highlight marks an earlier equation head Read rather than Write. The
reference set and the rename edits are complete either way.

## Rename

`prepareRename` answers the name's range and its spelling; `rename` writes ONE
`WorkspaceEdit` over exactly the references set. **It never produces a partial
edit**: every refusal is checked before any edit is built, so on the paths below
the answer is a `ResponseError` with a message and no edit at all.

It refuses when:

- the name is defined in a file that is not open (a stdlib name);
- the new name is not a valid Ermine identifier, or is one of the other case —
  a constructor or type name stays upper-case, a term lower-case;
- either name is an operator (an operator's spelling carries its fixity);
- the new name is already bound where the old one is used, is already a top
  level of the module, or already resolves through the file's imports;
- a mention is written under another spelling — an alias import or a qualified
  use — which a textual rename cannot follow;
- another open buffer holds that spelling under a DIFFERENT definition (this
  can refuse a legitimate rename of two genuinely distinct names, and says so);
- a mention of the name is ambiguous;
- the source writes the name in a form that is not its spelling: a
  `` `literal` `` name, whose backticks and escapes a textual rename cannot
  rebuild, or a name behind a TAB (see the note on columns below);
- a document the edit would touch has been edited since its last check — "check
  pending; retry after diagnostics update", which is the honest answer while a
  debounced check is owed: a buffer that has just gained a mention cannot be
  edited from an index that predates it. A GLOBAL rename version-checks EVERY
  open document, because the name can be mentioned in any of them; a LOCAL
  rename checks only its own file, since a local cannot leave it — so renaming
  a `let` binder still works while another buffer is mid-debounce.

References and highlight are correct on all of those EXCEPT a name behind a tab,
`` `literal` `` names included: their extent is the whole backticked token. The
tab case is a column-model defect, not a rename one, and it is the next
paragraph.

**A note on columns.** The parser expands a tab to the next eight-column stop
and LSP counts UTF-16 code units, so on a line with leading tabs every range
this server produces — a diagnostic, a definition target, a hover hit-test, a
highlight, a symbol — sits seven columns to the right per tab. Rename is the
one request that refuses rather than risking a wrong edit. Ermine sources are
space-indented almost everywhere: 6 of 71,248 corpus occurrences are in that
class, all in `core/examples/GridExample.e`. Ticket E8.

## Document symbols

`textDocument/documentSymbol`, hierarchical, one symbol per top-level GROUP
rather than per statement: a spelling's signature and its equations are one
thing to a reader, so they merge into one symbol whose selection is the
equation's head. `detail` is the type the last check inferred, printed the way
hover prints it, with the operator's fixity folded in.

Its `range` is the CONTIGUOUS RUN of that group's own statements around the
selection — normally the signature and the equations right below it. ANY
statement outside that run is left OUT of the range, and **that source line then
belongs to no symbol**. A signature separated from its equations is the usual
cause (a block of signatures followed by a block of equations, or a multi-name
signature whose equations are on separate lines), and a fixity declaration
sitting between a signature and its equation does it too. The alternative would
be a breadcrumb that names the wrong definition, because a client maps a cursor
to a symbol by taking the first sibling range that contains it. No two sibling ranges overlap unless they are identical, which
is what one statement declaring several names (`field fa, fb : Int`) produces. A
group whose equations live inside a `private` block is a child of that block.

Bindings inside a definition — `where`, `let` and `do` binders — are NOT
symbols. The outline lists a module's declarations; a local binder is reached by
hover, go-to-definition and find-references instead. The kinds:

| statement | SymbolKind |
|---|---|
| a term group with an argument, or a bare signature | Function (12) |
| a term group whose equations take no arguments | Variable (13) |
| a member of a `class` body | Method (6) |
| `data` with a constructor that carries a field | Struct (23) |
| `data` whose constructors are all nullary | Enum (10) |
| a data constructor (a child of its type) | Constructor (9) |
| `type` alias, `foreign data` | Class (5) |
| `class` | Interface (11) |
| `field` (one per name) | Field (8) |
| `table` (one per name) | Object (19) |
| `import`, and the `foreign` block itself | Module (2) |
| `private` and `database` blocks | Namespace (3) |
| `foreign function` / `method` / `subtype` | Function (12) |
| `foreign value` | Property (7) |
| `foreign constructor` | Constructor (9) |
| a fixity declaration | none — it is a `detail` on the operator's symbol |
| a statement that would not parse | none — its diagnostic is the answer |

A broken file lists its healthy statements. Before the first check of a file the
answer is `[]`.

## Workspace symbols

`workspace/symbol`, a case-insensitive substring over (a) every open document's
own declarations and (b) the resident session's globals that have a real source
`Loc` — the stdlib, in its `.e` files, because the session is interface-free. A
Scala-installed builtin (`Just`, the `Relation` type) has no source and is not
listed, and neither is a CONTAINER: an import, a `foreign` block, a `private` or
`database` block declares no name of its own. Results are ranked exact match,
then prefix, then substring, and capped at 200; an empty query answers with the
open documents only.

The session's name list is built ONCE, inside the first query that arrives after
boot (2157 names), which is what makes that query cost tens of milliseconds and
every one after it a fraction of one. Stdlib hits carry the build-output path
described under go-to-definition.

## Completion

`textDocument/completion`, trigger character `.`, no `completionItem/resolve` —
every item arrives with its `detail` already on it. Every item comes from the
LAST CHECK's tables and the CURRENT buffer text; never a check, a parse or an
inference. The buffer is read lexically, on the request's own line, for two
things: the word prefix at the cursor (an identifier; **operators are not
completed**) and which of four contexts applies.

| context | what is offered |
|---|---|
| the line's first word is `import` / `export` | module names (Module 9) from four sources: the modules THIS file's check loaded, the resident session's, the `.e` files under the file's module root, and the open buffers' own modules — prefix-matched on the whole dotted path, so `import La` offers `Layout` and `Layout.*` |
| the cursor follows `Module.` (every segment upper-initial) | the names whose ORIGIN is that module: terms with their types, constructors, and types with their kinds — see the note below on what such an item INSERTS |
| the cursor is inside a `--` comment, a `{- -}` opened on this line, or a `"…"` string | nothing: the answer is an empty list |
| otherwise | names, ranked: **locals** visible at the position (Variable 6, with the type hover gives the binder) < **this module's own** declarations (from the document-symbol tree, with their checked types) < **imported** names in this file's scope (with the type the check's `ModuleScope` carries) < **keywords** (Keyword 14) |

The comment/string test reads the CURRENT LINE only, so a cursor inside a
`{- -}` block comment opened on an EARLIER line, or inside a string that spans
lines, is not recognised and completion answers as if it were code. An import
LIST (`import M using (`) is treated as a name context, so it offers the file's
own scope rather than M's exports.

**A qualified item inserts the BARE name, not the dotted one.** A dotted
reference does not parse in this dialect — `Bool.not`, `Bool.True` and
`: Bool.Bool` all fail with `unknown operator .`, because an upper-initial
segment is read as a plain identifier and the `.` as composition. So completing
`Bool.no|` replaces the whole `Bool.no` span with `not`, and, when the module is
not already imported in this file, adds an `import M using <name>` line after
the last import. `Module.` completion is therefore a way to BROWSE another
module and pull one name in; the dotted text you typed never survives into the
file. Under `import M as A` the module's names are in scope only in the affix
form, so the item inserts `not_A` rather than `not` (and no import is added —
the module is already imported). A spelling that is both a type and a
constructor is offered TWICE, once per namespace, because their import lines
differ (`using type Ring` and `using Ring`) and nothing in the buffer says which
position you are in.

Three limits of `Module.`, stated: it lists the names whose ORIGIN is that
module, so a name the module RE-EXPORTS is not offered under it (`Maybe.` offers
`Maybe.e`'s own functions, not `Maybe`/`Just`/`Nothing`, which originate in
`Native.Maybe`); a module referred to by its ALIAS (`A.n`) is not recognised as a
module at all and answers nothing; and if the module is already imported with a
`using` list that does not name what you picked, the insertion will not resolve
until that list is extended — the add-import quick fix below is what edits
existing lists, and it does.

Ranking is carried in `sortText` (tier, then case, then the name); a
case-insensitive prefix match is offered BELOW every exact-case match of its own
tier. A name is offered once: a local shadowing an import is the local, which is
what that name means at that position. Filtering is server-side and
case-sensitive-first.

With a NON-EMPTY prefix the answer is complete (`isIncomplete: false`) and the
editor may filter it as you keep typing. With an EMPTY prefix — the cursor after
a space, or the `.` trigger — the answer is the file's own names only (locals
and the module's declarations) and says `isIncomplete: true`, so the editor asks
again the moment a character is typed and gets the imports too. That decision
was measured: on the largest module in the corpus the unfiltered set is 1332
names and 176 KB of JSON, which is not an answer to "show me everything".
Answers are capped at 300 items (with `isIncomplete: true` when the cap bites),
and a document whose FIRST check has not landed yet answers the empty list with
`isIncomplete: true` as well — so a client that asks during the ~13 s boot is
told to ask again rather than caching nothing forever.

TYPE VARIABLES ARE NOT OFFERED. A `forall` variable, a data argument and a kind
brace bind through the annotation rather than through a scope frame, and the
scope-at-position layer carries value scopes only.

**Staleness is accepted and stated.** Completion answers from the tables the
last DEBOUNCED CHECK left behind, so a binder you have just typed is not offered
until that check lands (~300 ms after you stop typing, plus the check itself).
The word prefix and the context are read from the buffer as it is NOW, so the
filtering is always current; only the set of names is as old as the last check.
The alternative — checking on a completion request — would put a whole check on
every keystroke, which is the one thing this server does not do. A request that
arrives during the session boot answers with an empty list, never null.

## Quick fixes

`textDocument/codeAction`, in two kinds: `quickfix` and `source`.

### Add import

On an "undefined term" diagnostic. The candidate modules are the loaded modules
that export that spelling — mapped through the session's re-export origins, so a
name and its re-exporters are ONE candidate and the one offered is the module
that DEFINES it — plus any open sibling buffer whose own declarations include
it. One action per candidate (at most eight, alphabetically), each carrying the
diagnostic it fixes; when there is exactly one it is `isPreferred`, and when
there are two the server does not choose for you. The edit depends on how the
file already imports that module:

| how M is imported | the fix |
|---|---|
| not at all | `import M using name` on its own line after the LAST import (after the `module … where` line when there are none) |
| openly (`import M`) | none — every name M exports is already in scope, so this one did not come from M |
| with an alias (`import M as A`) | none: an aliased import puts `name_A` in scope and never `name`, and a second import of one module is a hard error |
| `using` a list that lacks the name | `; name` appended to the list — inside the braces when it has them |
| `using` a list that has it | none |
| `hiding` a list that names it | the name is REMOVED from the hiding list; if it was the only one, the whole `hiding` clause goes |

Every inserted line carries the buffer's OWN terminator (142 of the 161 stdlib
modules are CRLF). The import statements are read lexically from the current
buffer with comments blanked out, so an import you typed a second ago counts and
one inside a `{- -}` block does not.

Three things it does not do. **A type name gets no action** — the "undefined
type" note carries no spelling, and giving it one is a checker change.
**Operators are unreachable** — an unknown operator is a read diagnostic, not an
undefined-term note. And **a re-exporter you already import is never offered**:
with `import Prelude using isJust` in the header and an undefined `not`, the menu
is `import Bool using not` and `import Relation.Predicate using not` — the two
ORIGINS — and not "add `not` to the Prelude list", which is the smaller edit a
reader of that file would make. Both offered edits apply and re-check clean.

### Add type signature

On a top-level binding group with no signature (inside a `private` or `database`
block too): `f : <type>` on the line above the group's first equation, at that
equation's own indentation, with the type rendered by the same printer hover
uses. An operator group takes the `(<+>) : …` form. There is also a `source`
action, "add all missing signatures (N)", carrying one insertion per group,
sorted by line descending so that a client applying them in sequence cannot
drift. Class bodies are out of scope.

THE SIGNATURE IS NOT RE-CHECKED BEFORE IT IS OFFERED — a code action fires on
every cursor move, and a check costs a second. Its correctness was measured once
instead, over the 253-file corpus: of 1334 unsigned groups, **1166 signatures
were offered, inserted and re-checked, and 1164 came back clean — 99.83 %,
against a shipping bar of 95 %.** The two that did not are correct signatures
whose type merely re-prints with a `type` alias unfolded; both re-check with no
diagnostics, so the honest reading is 1166 of 1166 usable. (Equivalence there is
alpha-equivalence up to kinds, not text: a rendered-text comparison first
reported 81 %, and 145 of its "failures" were kind-binder and row-constraint
ORDER.)

The action REFUSES rather than offering a line that would not parse. 168 of the
1334 groups are refused, and the reasons are the PRINTER's limits and the scope
test's, not yours:

- **117** — the type is not in scope under the spelling the printer writes.
  Those 117 refusals cite **150 type names** between them, so the split below is
  in NAME OCCURRENCES, not in groups: **68** are types the file DOES import,
  under an ALIAS (`import Native.Map as NM`), so only `Map_NM` resolves while
  the printer writes `Map`; **49** name types nothing can bring into that file
  (31 of them one `private data`); and **33 are a false negative** — the file
  can write the name through a `type` synonym of its own, which the scope test
  cannot see through. That last class is **31 groups (33 name occurrences)**,
  and it is the one place a signature that would have worked is withheld.
- **36** — the printer emits a kind variable that nothing quantifies.
- **10** — the printer drops the parentheses a nested `* ->` kind needs.
- **3** — a record row whose field names do not round-trip.
- **2** — an infix constructor the printer writes as `<:_Type.Cast`, which is
  not one name to the lexer.

None of them can produce a wrong edit, only a missing one; each refusal is
silent (the reason goes to the log). Fixing the printer would return **48
groups** and the scope test **31 groups (33 name occurrences)** — ticket E10 in
`tracker/TICKET-stdlib-findings.md`.

A signature is also refused on a tab-indented equation, for the column reason
above. No corpus group is in that class today.

### Staleness is REFUSED here, not accepted

Every other request in this server answers from a possibly-stale index, because
a stale ANSWER is harmless. A code action is an EDIT: a signature inserted at a
line the buffer no longer has is corruption. So while the index is older than
the buffer — between a keystroke and the check ~300 ms later — the answer is an
empty list. A request during the boot answers `[]` as well.

`context.only` is honoured. The server always answers with `CodeAction` objects,
never the legacy `Command` form, and there is no `codeAction/resolve`.

## Logging

Logging goes to the file named by `ERMINE_LSP_LOG` (or `-Dermine.lsp.log`);
stdout is reserved for the protocol.

## Fast mode

`initializationOptions: { fastMode: true }`, or a
`workspace/didChangeConfiguration` carrying
`{ settings: { ermine: { fastMode: true } } }`, skips type checking. On a
1757-line module a check splits roughly 0.86 s read + 0.50 s typecheck on a
quiet machine (0.94 + 0.60 on a busy one), so this takes about a third off the
latency either way.

Kept: every syntax, shadowing, unknown-operator and lowering diagnostic; import
failures; go-to-definition, including to this module's own fields and
constructors, whose positions come from the surface tree rather than from the
check; hover on imported names, and on imported TYPE names' kinds. Lost: all
type errors, the "unchecked" notes, import-list export requirements, hover on
the module's own definitions, and hover on every local binder.

## Latency

Re-measured 2026-09-10 on this machine (JDK 21, one-minute load average under
1.5 at the start of every run) against
`core/src/main/resources/modules/Layout/Report.e`, 1757 lines and the largest
module in the stdlib. Small modules are far below all of it. Where a row gives
a range, the two ends are a quiet machine and a busy one; nothing else about
the measurement differs.

| | | how |
|---|---|---|
| session boot | 12–15 s, once (129 modules) | six runs: 11.9 / 12.2 / 13.4 / 14.0 / 14.8 / 14.9 s |
| keystroke to diagnostics | **≈1.7 s quiet, ≈1.9 s busy** — 0.86 read + 0.50 typecheck + 0.30 debounce on the quiet run | `perf-bench.sh editor -k 15`, median of rounds 2–15, 97 of 154 binding groups reused. 1.690–1.697 s at load ≈1.0; 1.859 s (spread 1.80–2.12) at load 1.3–2.2. The gap is the machine, not the build: an interleaved pair against a build of the Stage-3 opening commit (`78d860f`), on the same machine, measured 1.759 s before / 1.694 s after |
| first check of a freshly opened file | 2.40 s | the same run's cold open |
| **worst-case wait for a request sent DURING a check** | **1.47 s** | a hover sent 350 ms after the keystroke — just after the debounce fires — median of 3 (1.45 / 1.48 / 1.47); the answer lands 1.82 s after the keystroke. This is the number a worker-thread check would have to beat |
| a hover on an idle server | 0.6 ms, client round trip | median of 10 |
| a completion | **≈2.2 ms** server side, **6.5–6.9 ms** client round trip | prefix `f` at line 1504, 97 items of the module's scope. The server figure is its own log line (median of the same ten requests; 6.5 measured 2.5 ms); the round trip adds JSON encoding and the wire, and is the median of 10 measured by the client |
| `workspace/symbol` | 61 ms first, then **1.6 ms** | the first query builds the 2157-name session list; warm figure is the median of 10 |
| `documentSymbol` | 32 ms, client round trip | median of 10; 398 top-level symbols, 511 in all. This is the JSON round trip for the whole tree, not the build — the tree itself is built on the check path |
| the index the requests read | 66 ms cold, **13–23 ms** warm | rebuilt on every check; 7980 occurrences + 511 symbols, from the server's own `index:` log line |
| a code action | 52 ms on the first request after a check, then 0.7–1.1 ms | the edits are memoised per document version |

Dispatch is single-threaded by design (a `SessionEnv` is not thread-safe), so
requests are served one at a time — which is what the worst-case row measures.
Requests that arrive before the boot begins answer empty immediately rather than
queueing behind it; a request sent after `initialized` queues behind the module
load like anything else.

## VS Code

An extension lives in `editor/vscode` — syntax highlighting plus a client for
this server. See its README for install and settings. VS Code has no built-in
generic LSP client, so an extension is the only route.

The extension registers no provider of its own: `vscode-languageclient` builds
one per capability the server advertises, including the completion trigger
character and the code-action kinds. Nothing in the extension filters them.

## Emacs (eglot)

```elisp
(define-derived-mode ermine-mode prog-mode "Ermine"
  "Bare major mode for Ermine `.e' files.")
(add-to-list 'auto-mode-alist '("\\.e\\'" . ermine-mode))
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(ermine-mode . ("/path/to/ermine-scala/bin/ermine-lsp"))))
;; M-x eglot in an .e buffer.
```

That snippet is all the configuration there is, and it has not changed since
Stage 0. Eglot reads the server's advertised capabilities and binds them itself:
`M-.` definition, `eldoc`/`K` hover, `xref-find-references`,
`eglot-rename`, `imenu` document symbols, `xref-find-apropos` workspace
symbols, `completion-at-point` (trigger characters are the server's, not the
client's), and `eglot-code-actions`. For fast mode, add
`:initializationOptions (:fastMode t)` to the server entry.

## Regression harness

- `tracker/tools/lsp-smoke.sh` runs the scripted client
  (`tracker/tools/lsp-client.py`) against the fixtures in `tracker/lsp-tests/` —
  **480 checks** over everything above, including didChange without save, the
  sibling-buffer path, the import-failure diagnostics, local and kind hovers,
  references/highlight/rename with every refusal, the pinned symbol trees of
  `Decls.e`, `Syms.e`, `Scope.e` and the broken `Broken.e`, the workspace
  queries, completion in every context (`Complete.e` and its siblings, including
  the staleness pin), the quick fixes (`Fix.e`, `FixSib.e`, `FixTy.e` and the
  CRLF `FixCrlf.e` — every import-edit case applied by the client and
  re-checked, the signature actions, the `only` filter and the stale-index
  refusal), the FFI-tolerance fixtures, fast mode, the phase-timer property gate
  in both directions (7.0), and `Anchor.e`'s ANCHORED-POSITION pins (7.2): every
  reply that carries a position — hover on a local, definition, references,
  highlight, a rename edit, documentSymbol, a code-action edit — asked once on
  the pristine buffer and again after a `didChange` that inserts three blank
  lines at the top with NO save, and required to have moved by exactly three.
- `tracker/tools/repl-smoke.sh` — **8 groups, 66 checks** against the byte-exact
  REPL goldens in `tracker/repl-tests/`. The editor path must never move them.
- `tracker/tools/corpus-run.sh --batch <outdir>` — the batch verdicts over the
  154-file corpus: **85 LOADED / 69 REJECTED / 0 UNKNOWN**.
- `tracker/tools/lsp-demo.sh > tracker/lsp-tests/G3-demo.txt` regenerates the
  capability-by-capability transcript. It is evidence, not a test.

Run the first three with `sbt core/test` before committing server changes
(`tracker/LSP-ROADMAP.md`, Baselines).
