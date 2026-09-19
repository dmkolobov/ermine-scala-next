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
`tracker/lsp-tests/G4-demo.txt` is a scripted run over all of them, with the
protocol traffic and the timings; its last section is Stage 4's — the check's own
log line on a keystroke, a top-of-file insertion, a coalesced burst, a tab-indented
hover and a stdlib definition. (`G3-demo.txt` is kept as the Stage-3 artifact.)

## Diagnostics

Published on `didOpen`, on `didSave`, and 150-300 ms after the last `didChange`
— no save required; the exact wait is derived from what checking that file has
been measured to cost (see **The debounce** under Latency). Checking runs against
the open BUFFER, for this file and its workspace siblings alike, so a cross-file
check sees unsaved edits. Every check uses a fresh copy of the resident session,
so a broken file poisons nothing.

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
consequences of the names that never arrived: "undefined term", "undefined type"
and "unchecked: depends on a broken definition" are suppressed for that check —
the import failure is the error to act on, and a file's worth of undefined names
on top of it is noise. (The same rule already applies while a statement is too
broken to parse.) It is deliberately blunt: a genuine typo goes quiet until the
import is fixed. Every one of the three is recognised by a FLAG set where the
note is built, never by matching its rendered text.

**One consequence of a missing import is NOT withheld.** An operator the module
would have supplied still draws "unknown operator", plus the two lowering
diagnostics that follow it — three per use. Those three are read-phase
DIAGNOSTICS rather than notes, so the filter cannot reach them at all; and they
are exactly right for a genuinely mistyped operator in a file whose imports are
all fine, so telling the two cases apart would need a tag that says "unknown
because a module did not load" — which nothing here can supply, since a module
that failed to load contributes no export list to compare against. Ticket E7
carries the argument.

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

**The stdlib is read from the source tree.** At `initialize` the server takes
the workspace folders the editor opened (`workspaceFolders`, or `rootUri`) and,
for each that has `core/src/main/resources/modules` beneath it, puts that
directory AHEAD of the classpath in the module loader; `initializationOptions.
moduleRoots`, a list of directories (absolute, or relative to the server's
working directory), adds roots explicitly and they go first. A folder that is
not a checkout, such as a directory that merely holds several checkouts,
implies no root; the modules the boot did not load still resolve per check
against the checkout each document is in.
The session's modules then come from the source tree, so a module added under
`modules/` is importable without `sbt core/copyResources` or a restart, and a
document in another checkout (a worktree opened beside the workspace) resolves
the modules its own tree has, and the boot did not load, against that tree. A
client that sends neither boots from the classpath copy as before. What does
NOT refresh yet: a module the boot already loaded keeps the text it was read
with until **Ermine: Restart Language Server**; invalidation on change is the
next step of tracker/LSP-STALENESS.md.

**A stdlib target opens the SOURCE tree.** When the stdlib was read from the
classpath copy (no folder, no roots) a stdlib name's recorded position is in
that copy, and the server maps it back to
`core/src/main/resources/modules/Bool.e` before it sends a `Location`. You land
in the file you would edit, for definition, for references' def-site and for
workspace symbols alike. The mapping is derived from where the class loader
actually found `modules` (no Scala version is spelled anywhere); if the source
tree is not there, or the particular module is not in it, the build-output path
is sent unchanged. With source roots the position is in the source tree already
and the mapping has nothing to do.

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
and at every use. A `let`/`where` HEAD shows the SCHEME the checker published
for it — quantifier and constraints, exactly as a top-level hover shows one
(`idy : forall a. a -> a`, `go : forall a. Num a => List a -> a -> a`). Every
other local binder shows a monotype, with no `forall` and with still-free metas
rendered as type variables (`acc : a`, `h : Int`). The head is the amendment to
Stage-3 Decision (a) made for interstage item 6.2c: its old reading, a local's
solved monotype read off the binder's own meta, is one frame BEHIND what the
checker published — the constraints are moved into the scheme at generalisation
and nothing binds the meta again, so `go` hovered `List a -> a -> a` where the
checker held `forall a. Num a => List a -> a -> a` (ticket E14). What the local
rule covers:

- **a `let` or `where` binding** — its published scheme (constraints included),
  or its declaration when it carries an explicit signature (shown AS DECLARED,
  unchanged by the amendment). One display rule applies to the scheme, and only
  to it: a constraint is shown when every type variable in it is one the scheme
  quantifies or one its body shows, and is otherwise DROPPED. What that drops is
  the ambiguous row residual a local's inferred constraint set drags along — a
  constraint over variables that appear nowhere in the type being hovered, which
  no edit to that binding can discharge and which two checks of one unedited
  file do not even agree about (the checker's published row-constraint set is
  id-ordered and varies between runs). What it keeps is every constraint the
  head's own variables carry: `Num a`, `AsOp opl`, `a <- (r2, (|cutoff|))`. The
  `.ei` a batch build publishes makes a DIFFERENT choice — it keeps the
  existential row constraints and deletes provable tautologies instead — so the
  two are not the same predicate and should not be read as one;
- **an ARGUMENT of an equation**, top-level or in a `where`, at any depth —
  under three conditions, because the type is RECONSTRUCTED from the binding's
  own type rather than read off the binder: the argument must be a plain
  variable (`f !x` and `f ~x` answer null, and so does a variable inside a
  constructor or tuple pattern); the binding's type must unfold to exactly
  `arity` arrows, or NOTHING is recorded for that binding; and the argument's
  own type must be a monotype — the reconstruction divides an arrow chain and
  has no scheme to hand out, so a rank-N argument is skipped rather than
  guessed;
- **a pattern binder that carries a signature;**
- **every OTHER pattern binder** — a lambda's argument, a `case` alternative's
  binder, a `do` binder, and a variable nested inside a constructor, tuple or
  `as` pattern. These have no arity to divide and their type exists only inside
  `Subst.inferPatternType`, so since 6.2b the checker records it where it mints
  it (`SubstEnv.binderTypes`, kept substituted as inference proceeds) behind a
  flag the editor path alone sets. Batch never sets it and never reads it.

Over the corpus that is every value-local binder of every cleanly checked module
— 5054 of 5083 over 253 modules, with `Arg` 4650/4678, `CaseBound` 116/117,
`DoBound` 31/31, `LetBound` 165/165, `WhereBound` 92/92. The 29 that stay silent
are ONE class and they are a limit of the two MECHANISMS, not of the rendering:
both of them record MONOTYPES — the arity split divides the head's arrow chain
(`d.mono`) and the hook records the meta `inferPatternType` minted (`t.mono`) —
and a variable bound to a RANK-N constructor field (`data Alt f = Alt (forall
a. f a) …`) has a polymorphic type that neither can express. (Until 6.2c this
was justified by "no `forall` on a local"; that rule no longer holds for heads,
and it was never the actual reason here.  `tracker/loopmodel/LSP-6.2b-HOOK.md`.)

An equation's arguments are read off the binding's own type by its arity, so
their type variables are the SAME ones the binding's hover shows:
`konst : forall a b. a -> b -> a` gives `k : a` and `j : b`, never `a` and `a`.
A binder the checker recorded shares its letters with the enclosing TOP-LEVEL
binding's hover for the same reason. One caveat worth knowing: a `let`/`where`
HEAD's own type is read from a different place and its variables are named
independently, so the same letter in two hovers need not be the same variable —
a `where` helper may hover `h : a -> a` inside a binding whose own hover calls
that variable `b`, and a lambda argument inside that helper is named against the
top-level binding rather than against `h`.

**Two frames in one `let`.** A head and the ARGUMENTS of its equations are in
the SCHEME's frame: the arguments are divided out of the head's own type, so

```
let go []       acc = acc
    go (h :: t) acc = go t (h * acc)
in go xs 1
```

hovers `go : forall a. Num a => List a -> a -> a` and `acc : a` — `acc` has the
binding's quantified variable, which is what it has for every use of `go`. A
PATTERN binder inside the body is in the INSTANCE frame instead: `h : Int` and
`t : List Int` there, because the hook records the meta the checker minted and
that record is carried along to the first instantiation the body takes of the
scheme (`go xs 1`, hence `Int`). The two answers are consistent here — this
`let` has exactly one use — and where a local is used at two types the hook
shows the FIRST instantiation, which is ticket E15 and is not fixed: a binder
of a polymorphic local can therefore read more specific than the binding is.

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

References and highlight are correct on all of those, `` `literal` `` names
included: their extent is the whole backticked token.

**A note on columns.** The parser expands a tab to the next eight-column stop
(`Pos.bump`) and LSP counts UTF-16 code units from the start of the line, so a
parser column and an LSP character are DIFFERENT UNITS on any line with a tab in
it — seven apart per tab. The server converts between them at its boundary and
nowhere else: one helper over the line model the last check built
(`Definitions.Lines.character` / `.column`), with every published range and
every incoming position routed through it — diagnostics, definition targets,
hover and reference hit-tests, highlight, rename edits, document and workspace
symbols, and completion's scope lookup. A corpus property round-trips all 71,248
occurrence columns, and every character of every tabbed line, through both
directions. A name behind a tab is therefore renameable like any other.

The UTF-16 rule is NOT a second bug here: the scanner feeds `Pos.bump` one
`Char` at a time, so a non-BMP character is two parser columns and two LSP
characters and the two models already agree about it. The tab is the whole
difference. Ermine sources are space-indented almost everywhere — 6 of 71,248
corpus occurrences are behind a tab, all in `core/examples/GridExample.e` — so
the conversion is `col - 1` and O(1) on 252 of 253 corpus files. Ticket E8,
fixed in Stage 4 item 7.5.

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
until that check lands (150-300 ms after you stop typing, plus the check itself).
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
groups** — ticket E10(1)-(3) in `tracker/TICKET-stdlib-findings.md`.

A tab-indented equation is no longer refused either: the insertion is a whole
line at character 0 carrying the line's own leading whitespace, so it never had
a units problem (ticket E8).

The scope test used to refuse a type the file reaches only through a SYNONYM OF
ITS OWN (`Layout/Scan.e` declares `type Scan = Scan_S` over `import
Relation.Scan as S`), which cost 33 name occurrences over the corpus. Since
Stage 4 item 7.5 the check carries the file's own nullary synonyms resolved to
the constructor each one names, and the scope test resolves the printer's
spelling through them — an identity test, never a spelling one, and only for
`type X = C` with no parameters, which is the shape where writing `X` and
writing `C` mean the same type. Ticket E10(5).

### Staleness is REFUSED here, not accepted

Every other request in this server answers from a possibly-stale index, because
a stale ANSWER is harmless. A code action is an EDIT: a signature inserted at a
line the buffer no longer has is corruption. So while the index is older than
the buffer — between a keystroke and the check 150-300 ms later — the answer is
an empty list. A request during the boot answers `[]` as well.

`context.only` is honoured. The server always answers with `CodeAction` objects,
never the legacy `Command` form, and there is no `codeAction/resolve`.

## Logging

Logging goes to the file named by `ERMINE_LSP_LOG` (or `-Dermine.lsp.log`);
stdout is reserved for the protocol.

## Fast mode and the pinned debounce

`initializationOptions: { debounce: 300 }` pins the quiet window before a debounced
check to a fixed number of milliseconds (1–10000; anything outside that range is
refused and logged, never silently clamped) instead of deriving it from the measured
check time. It exists for reproducibility, not for tuning — a measurement of record
cannot have one of its own terms move underneath it, so `tracker/tools/perf-bench.sh`
pins 300, the constant every editor figure in the roadmap was taken with. The
derivation it switches off is described under **The debounce** in Latency.

`initializationOptions: { fastMode: true }`, or a
`workspace/didChangeConfiguration` carrying
`{ settings: { ermine: { fastMode: true } } }`, skips type checking. On a
1757-line module a WARM check now splits **0.05 s read + 0.53 s typecheck of a
0.61 s check** on a quiet machine, so skipping the check is most of what is left,
where before the surface cache (Stage 4 item 7.1b) the read was 0.84 s of it and
fast mode took off about a third. It also shortens the WAIT, since item 7.4's
window tracks the measured check time. A file opened for the FIRST time still
pays its whole parse, so on a cold open fast mode drops the ~1.3 s first check
and keeps the ~1.0 s read.

Kept: every syntax, shadowing, unknown-operator and lowering diagnostic; import
failures; go-to-definition, including to this module's own fields and
constructors, whose positions come from the surface tree rather than from the
check; hover on imported names, and on imported TYPE names' kinds. Lost: all
type errors, the "unchecked" notes, import-list export requirements, hover on
the module's own definitions, and hover on every local binder.

## Latency

**Re-measured whole at GATE G4** (2026-09-11, the final Stage-4 tree) on this
machine: JDK 21, ONE JVM, the one-minute load average waited for and recorded
**under 1.3 at the start of every run** (it sat at 1.18–1.29 all window).
Unless a row says otherwise the file is
`core/src/main/resources/modules/Layout/Report.e`, 1757 lines and the largest
module in the stdlib; small modules are far below all of it. The driver is
`tracker/tools/perf-client.py`, the client `perf-bench.sh editor` uses, and a row
that says *unpinned* let the adaptive window be whatever the policy chose and
harvested it from the server's own `debounce:` line.

Calibration, so the deltas below can be read honestly: `checkWith` — the phase
Stage 4 never touched — measured 492 ms before the stage and 529 ms at G4, i.e.
**+7 %, which is this machine's between-JVM drift** (item 7.0 measured that band
at 8 %). Read-side changes below are −90 % and larger, far outside it; nothing
smaller than ~80 ms in this table should be read as a verdict.

| | | how |
|---|---|---|
| session boot | **13–14 s**, once (129 modules) | seven boots in the G4 window: 12.8 / 13.5 / 13.5 / 13.6 / 13.7 / 14.1 / 16.4 s |
| **keystroke to diagnostics, the LARGEST module** | **0.93 s** — 0.05 read + 0.54 typecheck + **0.30 debounce** + 0.02 | `perf-client.py --rounds 70` UNPINNED, median of rounds 2–70, 97 of 154 binding groups and 528 of 529 statements reused every round, load 1.29. The policy asked for **300 ms every round** — the CEILING, because this file's median check (0.59–0.60 s) is over it. Pinned at 300 for the roadmap-comparable figure, `perf-bench.sh editor -k 15` gives **0.95 s** at load 1.24: on this file the pin changes nothing, which is the point of quoting both. It was **≈1.7 s** at GATE G3 |
| keystroke to diagnostics, a SMALL module | **0.17 s** — 0.15 debounce + 0.02 check | `Control/Monad/Reader.e`, 44 lines, `perf-client.py --rounds 70` unpinned, median of rounds 2–70, load 1.27; the harvested window was the **150 ms FLOOR** every round (the server's own line reads `median 13–16ms of 5 checks`). It was **0.32 s** before item **7.4** made the window adaptive, of which 0.30 s was the fixed wait: 94 % of the round trip was the wait for a 20 ms check. 7.4's interleaved A/B moved it **0.3204 → 0.1719 s** (−149 ms, −46.4 %) with the read and typecheck segments unmoved as the control |
| keystroke to diagnostics, a MID-SIZED module | **0.42 s** — 0.02 read + 0.08 typecheck + **0.22 debounce** + 0.09 | `Layout/Report/Keyed/Options.e`, 438 lines, 15 rounds unpinned, load 1.19. This file is the one that lands INSIDE the 150–300 ms band, so the window TRACKS the check rather than clamping, and you can watch it settle: 300 → 258 → 235 → 212 → 192 → … → **173 ms**. 7.4's own A/B pairs: this file **0.4703 → 0.3596 s** (−111 ms), `List.e` (341 lines, 7 of 13 groups reused) **0.3583 → 0.2124 s** (−146 ms, −40.7 %) |
| keystroke to diagnostics, **WORST site** | **1.58 s** — 0.17 read + 1.07 typecheck + 0.30 debounce | one keystroke inside the 10.7 KB `private` block at the end of `Report.e`, 15 rounds unpinned, load 1.28. It is worst on BOTH axes: the slowest statement in the stdlib to re-parse (`parse` 154 ms against 37 ms at the ordinary site) **and** `reused 0 of 154` — `private` is one of the SCOPE words, so the block's text is part of the per-document inference key and an edit inside it drops the whole cache on purpose. Same family as the operator / backtick / `_` / `'` definitions below. It was ≈2.2 s before 7.1b |
| first check of a freshly opened file | **2.47 s** | the cold open of the same runs, median of five (2.37 / 2.38 / 2.47 / 2.57 / 3.00). A first open has no cache to reuse, so it parses the whole file — the server's own line reads `read 0.9–1.4 s, surface 0 of 529` — and 7.1b makes it **30–70 ms SLOWER** (the extent scan, the line index and one cache entry per statement, all running interpreted), ~2 % of the open and the price of every keystroke after it |
| **worst-case wait for a request sent DURING a check** | **0.54 s** | a hover sent 352 ms after the keystroke — just past the window, so the check is already running — timed send → answer, median of five (0.51 / 0.53 / 0.54 / 0.56 / 0.62), load 1.18; the answer lands **0.90 s** after the keystroke. It was **1.45 s** at GATE G3, and the whole of the difference is the read falling out of the check the request is queued behind. This is the number a worker-thread check would have to beat, and it is now only just above the 500 ms that fork sets as its trigger |
| a hover on an idle server | **0.31 ms**, client round trip | median of 10 — the same request costs ~1750x less when nothing is checking, which is the entire content of the parked worker-thread fork |
| a completion | **≈1.7 ms** server side, **6.1 ms** client round trip | prefix `f` at line 1504, 97 items of the 1332 in scope. The server figure is its own log line, warm (11.0 → 4.1 → 2.8 → … → 1.6 ms over ten requests); the round trip adds JSON encoding and the wire, median of 10 |
| `workspace/symbol` | **106 ms** first, then **1.3 ms** | the first query builds the 2157-name session list. That first figure is the noisiest row here — 61 ms at G3, 106 and 161 ms in two G4 runs — because it is a `File.isFile` sweep of the module tree and moves with the OS page cache; the warm figure is the median of 10 |
| `documentSymbol` | **22 ms**, client round trip | median of 10; 398 top-level symbols, 511 in all. This is the JSON round trip for the whole tree, not the build — the tree itself is built on the check path |
| the index the requests read | **59 ms** cold, **9.6–15.4 ms** warm (median 10.6) | rebuilt on every check; 7980 occurrences + 511 symbols, from the server's own `index:` log line, 26 samples |
| a code action | **41 ms** on the first request after a check, then **0.7 ms** | the edits are memoised per document version |

**Where a warm check actually goes, after Stage 4.** The same run with
`-Dermine.lsp.phases=true` (see **Logging**) splits the 0.61 s check as: parse
**37 ms**, the rest of the read **15 ms** (header 8.8, rename 4.5, lower 5.0,
scrub 2.1, …), `read.total` **52 ms = 8.5 %**; the extent scan and its line index
**2.3 ms**; the inference-key map **3.3 ms**; the typecheck **529 ms = 87 %**;
`Definitions.index` **11 ms**. Before the stage the same file read **845 ms** of a
**1363 ms** check, and the parse alone was **61 %** of it. The read is no longer
where an editor keystroke goes; inference is.

**One observation, not a claim.** In one G4 probe run, ten hover requests issued
between checks were followed by checks that got steadily slower (0.59 → 0.95 s)
while an otherwise identical 70-round run stayed flat (0.50–0.56 s over 70
checks). It reproduced once and was not chased; whether it is hover-induced
allocation or machine noise is open. It is recorded here because it is the only
thing in the G4 window that looked like a pattern and is not explained.

**The debounce is derived from the measured check time** (item 7.4). A `didChange`
does not check; it queues, and the check runs once the input stream has been quiet
for D milliseconds. D is no longer a constant:

    D = clamp(150 ms, C, 300 ms)

where **C is the median of the last five measured check times of that document**.
With no samples at all D is 300 ms, but that case is defensive rather than ordinary:
`didOpen` and `didSave` check synchronously and pay no window, so the first DEBOUNCED
check of a file already has the open's measurement to go on — on the 44-line module
below the very first keystroke waited 150 ms off a single 144 ms sample.

The floor is 150 ms because a window shorter than the gap between keystrokes
coalesces nothing: it catches any burst faster than ~150 ms per character (a fast
typist is ~120 ms, within-word digraphs 60–80 ms). It deliberately does NOT catch
slower steady typing — at 40–60 wpm, ~200–300 ms per character, a file whose check is
at or below the floor gets a check per character. That is accepted, because on such a
file the check is cheaper than the window: a 20 ms check per 150 ms of quiet is at
most a ~43 % duty cycle, a request waits at most one 20 ms check, and the squiggles
are fresher for it. A check per character on an EXPENSIVE file is what must not
happen, and the clamp prevents it — a file whose check exceeds 150 ms raises its own
window to match.

The ceiling stays 300 ms because that is the staleness a squiggle may carry, and
because checks cannot pile up behind it: the queue holds one entry per document and a
superseded check is dropped before it starts. Between the two, the window tracks the
check time one-for-one, so at most half the dispatch thread goes to checking while
you type. The effect, measured: a small file stopped waiting 300 ms for a 20 ms check
(0.32 → 0.17 s), and the largest module did not move, because its check is 0.61 s and
the policy asks for the ceiling.

What bounds the feedback — a longer window coalesces more keystrokes, which can make
the next check cost more, which lengthens the window — is the CLAMP, not the median.
The median smooths; it does not bound. A document whose check cost alternates between
100 ms and 400 ms will alternate its window between 150 and 300 ms, which is harmless
precisely because those are the clamp values: the worst the feedback can do is the
constant this server used before.

The server logs the decision on every debounced check — `debounce: Report.e waited
300ms (median 592ms of 5 checks, policy 300ms)` — so the window is auditable rather
than assumed. It can also be pinned to a fixed value (see **Fast mode and the pinned
debounce**); `tracker/tools/perf-bench.sh` pins 300 so its editor numbers stay
comparable with every figure it recorded while the window was a constant.

**Why a keystroke is now 0.05 s of parsing.** The server keeps the parsed
statements of each open document and re-parses only those whose own text, or
whose lookahead region — the bytes the parser actually examined, which reach
into the next statement — the edit touched; everything else is carried over with
its positions shifted by the lines the edit added or removed. One keystroke in a
body therefore re-parses ONE of `Report.e`'s 529 top-level statements. The cost
is memory: one parsed tree per OPEN document, about 1.6 MB for the largest
stdlib file (~20x its source) and ~3.6 MB for the ten largest open at once,
replaced wholesale on every check and dropped on `didClose`.

**Which edits check COLD, and why.** The inference half of that reuse is keyed
per document in two parts. Each top-level binding GROUP has its own key — its
statements' text, each tagged with its offset from the group's own first line
(item 7.2: the ABSOLUTE line is deliberately not in it, so a line shift costs
nothing) — and everything that can change what the other names MEAN goes into a
single SCOPE key shared by the whole document: the import list, every
`type`/`data`/`class`/`instance`/`field`/`table`/`foreign`/`database`/`abstract`
declaration, every fixity declaration, and every `private` block. Touch anything
in the scope key and the whole per-document cache drops and the file is
re-inferred from scratch — `reused 0 of 154` on `Report.e`, the WORST-site row in
the table above.

Two consequences worth knowing before they surprise you. An edit inside a
`private` (or `database`) block always checks cold, because the block is one
scope statement and its text is the key. And a top-level definition whose name
is not a plain word — an operator, a backtick name, or a spelling containing `_`
or `'` — has its text in the SCOPE key too, because the extent scanner's head
word does not match the spelling the readers look the group up by; that
conservative choice is item 7.2's, and the alternative it replaced was worse (a
dependent silently holding a stale type). Everything else — ordinary equations,
signatures, comments, whitespace, line shifts — reuses.

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
  **542 checks** over everything above, including didChange without save, the
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
  Since 7.4 it also drives the real server loop through two keystroke BURSTS on
  `Burst.e` and one on `Layout/Report.e`, asserting one check per burst and the
  window the policy chose (the floor, the ceiling, the pin and the per-line
  audit); and since 7.5 the tab-column pins on `Tab.e` and the stdlib-position
  pins that require a definition, a reference def-site and every workspace
  symbol to name `core/src/main/resources/modules` and no `/target/` path.
- `tracker/tools/repl-smoke.sh` — **8 groups, 66 checks** against the byte-exact
  REPL goldens in `tracker/repl-tests/`. The editor path must never move them.
- `tracker/tools/corpus-run.sh --batch <outdir>` — the batch verdicts over the
  154-file corpus: **85 LOADED / 69 REJECTED / 0 UNKNOWN**.
- `tracker/tools/lsp-demo.sh > tracker/lsp-tests/G4-demo.txt` regenerates the
  capability-by-capability transcript, thirteen sections ending in Stage 4's.
  It is evidence, not a test, and it is reproducible modulo timings.

Run the first three with `sbt core/test` before committing server changes
(`tracker/LSP-ROADMAP.md`, Baselines).
