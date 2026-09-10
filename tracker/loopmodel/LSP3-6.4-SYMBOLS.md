# LSP Stage 3, item 6.4 — document symbols and workspace symbols

Implementer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.4.md`; item of record
`tracker/LSP-ROADMAP.md` § Stage 3, item 6.4 with the STAGE-3 INVARIANTS and Decision (c); gates
`tracker/GATE-POLICY.md`.  Branch `scala3-migration`, from `498dbbc` (6.3 committed).  No commits
of my own; no change to `tracker/LSP-ROADMAP.md` or `tracker/lean/`.  **FIX ROUND** (this revision)
after the independent review `tracker/loopmodel/LSP3-6.4-REVIEW.md` (FIX-THEN-ADVANCE): F1, F2, F3,
F4 and F8 are all addressed — F1 and F2 by the new range rule in §2c, F3 by the new corpus property
in §5, F4 in §3, F8 in §7c(8) and `docs/lsp.md`; F5 is inherited and gets the ticket paragraph the
coordinator asked for, in §7d, and is NOT fixed here.

**OUTCOME: GREEN**, after the fix round.  Both requests ship, answered entirely from what the last
check stored; every gate is green; the corpus cross-check that says the groups merge correctly is
EXACT (3441 term groups, 3441 `moduleTerms`, over 252 files); and **sibling ranges no longer
straddle: 171 → 0**, now asserted by a property rather than claimed in prose.  The review was right
that the first round's §2c asserted the opposite of what shipped; it is rewritten below and the
claim is now a measurement.  Two things in the brief turned out not to be true of this codebase and
are called out rather than quietly worked around: `Relation` the TYPE is a Scala-installed builtin
with no source (§7a), and a `foreign` declaration is a Function to an editor but is not a term
group, so the moduleTerms cross-check counts groups and not Function-kinded symbols (§7b).

---

## 1. Where the symbols live, and what they cost (the Stage-3 invariant)

`Definitions.DocIndex` grew ONE field:

```scala
final case class DocIndex(occs, version, moduleName, renamed, scopeTerms, scopeTypes,
                          symbols: List[Symbols.Sym] = Nil)
```

`Definitions.index` — already on the check path, already timed — now also calls
`Symbols.build(c.module, lines, termTy)`.  That is a walk over STATEMENTS only: no expression is
visited, no pattern, no type.  The `Lines` it measures names with is the one 6.3 already built for
the occurrence extents, so the symbol tree costs one extra pass over the statement list and nothing
else.

**What is stored and what is rendered.**  A `Sym` keeps the `Type`, not its rendering, for exactly
the reason hover does (`Definitions.Occ`'s scaladoc: an index rebuilt on every keystroke must not
pay for a printer nobody asked for).  `Pretty.prettyType` runs in the REQUEST, on the symbols the
request actually returns — printing is not a check, a parse or an inference, and it is the same
thing hover has done since 6.2.  Positions are converted in the request too.

**Nothing runs on a request path.**  `textDocument/documentSymbol` is `docs index uri` followed by
a JSON render of the stored tree.  `workspace/symbol` is a substring scan over that tree plus a
list built ONCE (§4).  No parse, no rename, no check, no inference is reachable from either
handler; dispatch stays single-threaded and nothing here touches it.  Batch semantics are untouched
— no file outside `lsp/` changed at all this item.

### 1a. Cost on the check path, measured against its own before

`Layout/Report.e`, 1757 lines, the largest file in the corpus: one cold check then two warm ones,
twice on each side.  BEFORE is this tree with the four `lsp/` edits reverted and `Symbols.scala`
removed, rebuilt and re-run in the same session.

| | occurrences | symbols | index build (cold / warm / warm) | check round trip |
|---|---|---|---|---|
| BEFORE, run 1 | 7980 | — | 42.0 / 15.3 / 13.9 ms | 2.03 / 1.37 / 1.24 s |
| BEFORE, run 2 | 7980 | — | 42.2 / 15.8 / 13.5 ms | 2.08 / 1.37 / 1.30 s |
| AFTER, run 1 | 7980 | 511 | 53.8 / 22.8 / 13.8 ms | 2.09 / 1.41 / 1.30 s |
| AFTER, run 2 | 7980 | 511 | 51.3 / 18.3 / 14.0 ms | 1.99 / 1.34 / 1.26 s |

**The check round trip does not move**: 1.24–1.30 s warm before, 1.26–1.30 s after, its own
run-to-run spread, with the read half dominating and untouched.  The index build pays about +10 ms
on its FIRST run (the new code path is cold), +3–7 ms on the second, and **nothing by the third**
(13.5–13.9 ms before, 13.8–14.0 ms after) — the symbol walk is JIT-warm by then and it is a walk
over 1757 statements' heads.  The ~50 ms editor floor (PERF-ROADMAP) is more than three times the
whole index build, symbols included.  The occurrence count is unchanged, which is the check that
6.4 did not disturb 6.3's index.

The log line now carries both, so this is a standing measurement and not a one-off:

```
index: Report.e 7980 occurrences, 511 symbols in 14.0ms
```

## 2. `textDocument/documentSymbol` — the mapping (6.4.1)

HIERARCHICAL (`DocumentSymbol[]`), sorted by position at every level, children included.

### 2a. Term GROUPS, not statements

The unit is the group, not the statement: **all of a spelling's signatures and equations in one
binding scope merge into ONE symbol**, whose `selectionRange` is the head `SName` of the FIRST
EQUATION — the signature's own head when the group has no equation — and whose `range` is the
contiguous run of its own statements around that selection (§2c).  Grouping is by spelling across
the whole scope (not only adjacent statements) for one reason: that is what
`Renamer.collectHeads` does, and §5's cross-check compares the two counts.

| | SymbolKind |
|---|---|
| a group with at least one equation that takes an argument | **Function 12** |
| a group with at least one equation, none of which takes an argument | **Variable 13** |
| a group that is only a SIGNATURE (a class member; a sig whose definition is missing) | **Function 12** |
| a group in a `class` BODY, whatever its arity | **Method 6** |

The Method rule is not decoration: a class body is its own binding scope
(`Renamer.statement` calls `topLevelHeads` on it separately), so its members are not module terms,
and giving them their own kind is what keeps §5 exact as well as what an outline wants.

`detail` = the type the check knows for that spelling — `TolerantCheck.types` for the module's own
top levels, the session's `termNames` for the names a check INSTALLS rather than binds — printed by
`Pretty.prettyType`, the printer hover uses, with the operator's fixity appended when there is one.

### 2b. Every other statement

| statement | SymbolKind | notes |
|---|---|---|
| `data` with a constructor carrying a field | **Struct 23** | constructors are CHILDREN |
| `data` whose constructors are all nullary | **Enum 10** | the distinction an outline icon is for |
| a data constructor | **Constructor 9** | `detail` = its type from the env |
| `type` alias | **Class 5** | a name for a type; `TypeParameter 26` would collide visually with real type parameters |
| `class` | **Interface 11** | body statements are children, by the same rules |
| `field` | **Field 8** | one per name in the statement |
| `table` | **Object 19** | one per name in the statement |
| `import` | **Module 2** | name = the module; `detail` = `export` for a re-export |
| `foreign` block | **Module 2** | named `foreign`; declarations are children |
| `foreign data` | **Class 5** | same as an alias: a name for a type; `detail` = the Java class |
| `foreign function` | **Function 12** | `detail` = `class.member` |
| `foreign method` | **Function 12** | `detail` = the member name |
| `foreign value` | **Property 7** | `detail` = `class.member` |
| `foreign constructor` | **Constructor 9** | |
| `foreign subtype` | **Function 12** | |
| `foreign private` | **Namespace 3** | named `private`, inside the foreign block |
| `private` block | **Namespace 3** | statements are children, recursively |
| `database "d"` block | **Namespace 3** | named `d`, `detail` = `database` |
| a fixity declaration | **none** | it is a property of the operator's symbol: it is that symbol's `detail` |
| `SErrorStatement` | **none** | its diagnostic is the answer; its healthy neighbours still list |

The `SStatement` match is exhaustive with no wildcard, deliberately: a NEW statement kind fails to
compile here rather than vanishing silently from the outline.

### 2c. Ranges

`Span` is 1-based half-open, LSP 0-based; the conversion is `line - 1`, `column - 1`, and a name's
length from `Definitions.nameExtent` over `Definitions.Lines` — **the path every other range in
this server already uses**, per the brief and ticket E8.  No second position model was invented,
and the tab-expanded-column limit (E8) is inherited as it stands: a range on a tab-indented line is
in the parser's units, not the editor's, exactly as hover, definition and diagnostics have been
since 0.5.

A symbol's `range` is made to CONTAIN its `selectionRange`, and a parent's to contain its
children's, **by construction** (`Symbols.build`'s `sym` unions the statement span with the
selection and with every child) rather than by hoping the parser's spans line up.  §5 asserts it
anyway, over 8159 real symbols, through `Symbols.containsRng` — the builder's own rule, not a
restatement of it (the 6.3 review's R2 lesson).

### THE RANGE RULE (fix round, review F1 and F2)

**A group's `range` is the maximal CONTIGUOUS RUN of its own statements, in the statement list of
the container its SELECTION stands in, containing that selection.**  Normally that is exactly what
it sounds like: a signature and the equations directly under it, which is every pin in this item
and the overwhelming majority of the corpus.

The first round took the union of ALL of a group's statement spans, and claimed in this section
that "half-open, so siblings abut and do not overlap".  **That was false, 171 times in 21 corpus
files**, and the reviewer found it.  Grouping is by spelling across the whole scope, so any other
group's statement standing between a group's first and last statement made the two ranges nest.
Two ordinary Ermine idioms do exactly that:

* **a block of signatures followed by a block of equations** — `Layout/Column.e` 25–32 is a
  four-deep staircase (`unsafeCol` 25–29, `unsafeFCol` 26–30, `unsafePhantomCol` 27–31,
  `unsafePhantomColK` 28–32);
* **a multi-name signature whose equations are on separate lines** — `Function.e`'s
  `($), ($!) : (a -> b) -> a -> b`, `Layout/Format.e`'s `round, roundParens`, and this item's own
  fixture `Syms.e`'s `symBoth`/`symAlsoBoth`, which §2c used to cite as the example of siblings
  that abut.

Nothing spec-illegal followed — the spec requires only containment, which held — and the outline
LIST was right, because a client builds it from `children` and not from ranges.  What misrendered
is every feature that maps a CURSOR to a symbol: breadcrumbs, sticky scroll and outline
follow-cursor all walk a level in order and take the first range containing the position, so a
cursor on `unsafeFCol`'s own signature line reported `unsafeCol`.

**What the run rule gives up, deliberately.**  A signature separated from its equations by another
group is not in the symbol's range, so that source line belongs to NO symbol.  A breadcrumb there
says nothing, which is honest; before, it said the wrong name.  The symbol is still found by name,
still selects its equation head, and still merges — only the range is narrower.  Live, on the new
fixture `Scope.e`:

```
stairA : Int          <- belongs to no symbol
stairB : Int          <- belongs to no symbol
stairA = 1            stairA  Variable  range = this line
stairB = 2            stairB  Variable  range = this line
```

**F2 falls out of the same rule.**  A group is emitted in the container of its SELECTION, not of
its first statement.  Before, a signature at top level whose equations sat inside a `private` block
produced an EMPTY `private` namespace beside a top-level symbol whose `selectionRange` pointed
inside it, and the mirror cases stretched a namespace past its own block over a second one.  Now
the group lives where its equations do, the stray signature is outside the run, and a container's
range is its own block.  Pinned live on `Scope.e` (which checks CLEAN — this is legal Ermine):

```
hidden : Int          <- outside the run; belongs to no symbol
                      private   Namespace  (11,0)-(14,0)
private                 hidden  Variable   (12,2)-(12,12)   <- a CHILD, selecting its equation
  hidden = 3            helper  Variable   (13,2)-(13,12)
  helper = 4
```

**What stays true, and is now asserted rather than claimed** (§5, and in lsp-smoke for all four
pinned fixtures): **no two sibling ranges overlap unless they are IDENTICAL** — 0 straddling pairs
over 8411 sibling levels in 252 files, down from 171.  Identical ranges are the separate,
legitimate class the reviewer counted apart: one statement can declare several names
(`field fa, fb : Int`, and a multi-name signature's own group when its equation is adjacent), and
each gets its own symbol over the same statement, told apart by its `selectionRange`.  A cursor
there is genuinely inside both.  1824 such pairs in the corpus.

A statement's span runs to the start of the next token (`SurfaceParsers.spanned` brackets a
`token`, which eats the whitespace after the lexeme), so a group's range typically ends at column 0
of the next statement's line and the next sibling begins there.  Half-open, so that is an abuttal
and not an overlap — `Symbols.overlaps` compares those endpoints STRICTLY, which is the difference
between the two, and is the function the property and the smoke both use.

## 3. `workspace/symbol` — source, ranking, cost (6.4.2)

`SymbolInformation[]`, case-insensitive SUBSTRING of the query.

**(a) Every open document's own declarations** — `Symbols.flatten` over the stored tree of each open
buffer, `containerName` = the module name the check recorded, `location` = the buffer's uri and the
symbol's SELECTION range (the name, which is where an editor should land).  **CONTAINERS are
excluded** (fix round, review F4): `workspace/symbol` is a search for declarations, and an import,
a `foreign` block, a `private` block and a `database` block each declare no name of their own —
kinds Module 2 and Namespace 3.  The first round dropped only Module 2, so a `private` container
leaked into every result set; `Syms.e` alone contributes two of them.  A `class` (Interface) and a
`data` type (Struct/Enum) DO declare their names and stay, as does every declaration INSIDE a
`private` block (`Scope.e`'s `hidden` is listed, its `private` container is not).

**(b) The resident session's globals that have a real file `Loc`** — `env.termNames` (through
`V.loc`) and `env.cons` (through `Con.loc`), the tables `textDocument/definition` already answers
from.  Kinds:

| source | kind | how it is told |
|---|---|---|
| `termNames`, upper-case initial | Constructor 9 | the grammar's own rule for a constructor |
| `termNames`, otherwise | Function 12 | a `V` says nothing about arity, so Variable is not claimed |
| `cons`, in `env.classes` | Interface 11 | the same kind a `class` gets in the document tree |
| `cons`, otherwise | Struct 23 | data, alias, foreign data |

A **Scala-installed builtin carries `Loc.builtin`**, which is not a `Pos` at all, so it never
produces a location and is never listed.  That is the whole of the "no builtins" rule — no name
list, no special case.

`containerName` for a session global is **the module the FILE defines** (`env.loadedFiles`
inverted), not the `Global`'s own module: a re-exported name arrives under whichever re-exporter's
`Global` the env kept (`Prelude` for half of `Syntax/Relation.e`), and the container a user wants
is where the definition lives.  The same rule dedupes re-exports: one entry per (definition site,
spelling), preferring the Global whose module matches the file — without it, a popular name would
fill the 200-result cap with copies of itself.

**Dedupe (a) over (b)** by `(containerName, name)`: a module that is both open and loaded is listed
once, from its BUFFER.  Pinned: with `core/src/main/resources/modules/Bool.e` open, `not` in
container `Bool` appears once, at the buffer's uri.  (`Relation.Predicate` defines a `not` of its
own — two modules, two names, two entries; the key is the pair, not the name.)

**Ranking**, stated: **exact match (case-insensitive), then prefix, then substring**; inside a tier
by lower-cased name, then container.  Total and pinnable: `"relation"` answers `relation` first,
and `relationWithHeader` (prefix) before `fromRelation` (substring).  **Capped at 200.**

**An EMPTY query answers with the open documents only** — 2000 stdlib names are not an answer to
"show me everything".

### 3a. Cost — the list is built ONCE, and the brief's escape hatch was needed

Walking `env.termNames` and `env.cons` per query would mean thousands of `File.isFile` stats per
keystroke (that is how `Definitions.location` drops a builtin), so the list is built the FIRST time
a query arrives after boot and kept.  It cannot go stale: the resident session is interface-free,
loads its 129 modules once and never again (Decision 5), and every check runs against a `withEnv`
COPY, so nothing a check does reaches it.  From the smoke log:

```
workspace symbols: 2157 session globals with source, built in 36 ms
workspace/symbol "twice":    1 of 1    in 37.8 ms      <- the build is inside this one
workspace/symbol "Relation": 15 of 15  in 0.66 ms
workspace/symbol "a":        200 of 1094 in 1.27 ms
workspace/symbol "relation": 15 of 15  in 0.21-0.49 ms  (five consecutive)
```

**Even the first query, build included, is 38 ms; every query after it is under 1.3 ms** — well
under the 50 ms bar, by more than an order of magnitude in the steady state.  The smoke asserts it
live (best of five, so a scheduling hiccup cannot fail a bound that is about the algorithm).

## 4. Capabilities and the boot path (6.4.3)

`initialize` advertises `documentSymbolProvider: true` and `workspaceSymbolProvider: true`;
`lsp-client.py` asserts both.

Requests that arrive **before the session exists** answer at once and never wait: `documentSymbol`
answers from the stored tree if there is one and `[]` when there is not (there is not, before the
first check of a file), and `workspaceSymbol` answers `[]` (`Resident.loadedEnv` is `None` while
booting).  Never null.  Both are pinned by sending them BEFORE the `initialized` notification, so
the resident session has not even begun to boot — dispatch is single-threaded, so a request sent
after `initialized` would queue behind the boot instead and would prove nothing.

## 5. The corpus properties (6.4.4) — totals

Four new properties in `TestRenamer` (24 → **28**; three in round one, the fourth added by the fix
round), over stdlib + `core/examples` — the standing
180-file rule, which today finds 253 files, 252 of which parse (`core/examples/Sample.e` is the one
the surface parser refuses outright, named rather than dropped).  No session: `Symbols.build` takes
"the type of this spelling" as a FUNCTION, and `_ => None` is a legitimate argument, so the whole
sweep runs in seconds.  The corpus is now parsed ONCE and both the renamer tables and the symbol
trees come off that parse.

| property | result |
|---|---|
| a symbol tree is built for every file, every symbol is named, every `range` contains its `selectionRange`, every child is inside its parent | **0 malformed of 8159 symbols over 252 files** |
| **(fix round, F1/F3)** every level of every tree is SORTED by position, and no two siblings STRADDLE (overlap without being identical) | **0 unsorted-or-straddling over 8411 sibling levels**; 1824 identical-range pairs, counted and allowed |
| term groups are exactly the renamer's `moduleTerms`, file by file | **3441 groups, 3441 moduleTerms, 0 files disagree** |
| every statement kind maps to a SymbolKind (a parser-only pin for `class`, `field` with two names, `database` + `table`) | proved |

`Prop.collect` prints on a PASS, so the distribution is reported and not merely asserted:

```
files 252 | symbols 8159 | Class 225, Constructor 161, Enum 6, Field 1431, Function 1841,
Module 2050, Namespace 181, Property 166, Struct 103, Variable 1995
files 252 | sibling levels 8411 | identical-range pairs 1824 | straddling pairs 0
files 252 | term groups 3441 | moduleTerms 3441
```

The straddle property is the one the first round should have had: the review asked whether
sortedness and sibling non-overlap were asserted, and neither was — sortedness held silently, and
non-overlap did not hold at all.  Both are asserted now, through `Symbols.beforeSym` and
`Symbols.overlaps` on the builder rather than a rule restated in the test, and the identical-range
class is COUNTED rather than failed so that it cannot quietly become the excuse for a real
straddle.  Note the file sets differ from the reviewer's census (they measured 358 files — stdlib +
examples + fixtures — and found 171 straddles / 2018 identical; this property measures the standing
253-file corpus rule).  The number that matters is the same either way: **0**.

The group cross-check is the one that says the MERGE is right: a signature that failed to join its
equations, or two equations of one name that split, would show up as a count one too many.  It
compares `Symbols.termGroups` — the builder's own answer to "which symbols came from a term group"
— against `Renamer.Result.moduleTerms`, rather than restating a rule in the test.

## 6. lsp-smoke (6.4.4)

**306 → 344 checks (+38)**: 32 in round one and **6 more in the fix round**.  Two new fixtures,
`tracker/lsp-tests/Syms.e` and (fix round) `tracker/lsp-tests/Scope.e`, both of which **check
clean**, carrying the statement kinds and the range shapes the existing fixtures do not reach.
What is pinned:

* **`Decls.e`'s FULL symbol tree**, as an exact expected structure — every name, kind, `range` and
  `selectionRange`, and the nesting — so a change in any of them is one diff.  It covers imports,
  an operator merged with its fixity declaration, two `field` names sharing their statement's
  range, a `data` statement with its constructors as children, a `type` alias, nullary groups
  (Variable), and `useAlias`/`useEither`, whose ranges span their signature AND their equation
  while selecting the equation's head.
* **`Decls.e`'s details**: `<+>` → `forall a. Num a => a -> a -> a  infixl 6` (the checked type
  plus the fixity), `Circle` → `forall a. a -> Shape a` (a constructor's type from the env),
  `fa` → `Field (|fa|) Int`.
* **`Syms.e`'s FULL tree**: an Enum (`SymColor`, all constructors nullary) beside a Struct
  (`SymBox`), a `type` alias and a `foreign data` both Class, a `private` Namespace whose group is
  its child, a `foreign` Module with a Class, a Constructor and a Function inside it, and a
  `private foreign` pair; plus `symBoth` (18,0)–(19,11) and `symAlsoBoth` **(20,0)–(20,15)**, which
  the fix round separated — the multi-name signature is in the range of the group whose equation is
  adjacent to it, and the two no longer straddle.
* **(fix round) `Scope.e`'s FULL tree**: `stairA`/`stairB`, a block of two signatures followed by a
  block of two equations, each symbol's range its own equation line; and `hidden`, whose signature
  is at top level and whose equation is inside a `private` block, appearing as a CHILD of that
  block with the signature outside its range.  Both are the shapes F1 and F2 named.
* **(fix round) no sibling range straddles another**, computed over the whole returned tree of
  `Scope.e`, `Syms.e` and `Decls.e` in the client — the live counterpart of the corpus property.
* **`Broken.e`**: its two diagnostics still arrive, its four healthy symbols list, and there is NO
  symbol for either broken statement.
* **`workspace/symbol "twice"`** finds `Nav.twice`, kind Function, container `Nav`, at its exact
  Location in the open buffer.
* **`"Relation"`** finds a stdlib TYPE in its SOURCE `.e` — `SoftRelation`, kind Struct, uri ending
  `/modules/Layout/Report/SoftRelation.e`, container `Layout.Report.SoftRelation` — and the stdlib
  TERM `relation` at `/modules/Relation.e`; and asserts that nothing named exactly `Relation` is
  listed (§7a).
* **`"sortorder"`**, a lower-case query, finds the upper-case stdlib type `SortOrder` at
  `/modules/Relation/Sort.e`.
* **`"just"`** lists exactly `getJust` and `isJust` and NOT the builtin `Just`.
* **dedupe**: with the real `Bool.e` open, `not` in container `Bool` appears once, from the buffer.
* **the empty query** returns only open-buffer symbols (no uri under `/modules/`) and, since the
  fix round, **no CONTAINER symbols at all** — neither Module 2 (imports, `foreign`) nor
  Namespace 3 (`private`, `database`) — while a declaration INSIDE a `private` block (`Scope.e`'s
  `hidden`) is still listed.
* **the cap**: `"a"` returns exactly 200 of 1094.
* **ranking**: exact first, prefix before substring.
* **cost**: a query is under 50 ms, asserted live (best of five; observed 0.21–0.49 ms).
* **before boot**: `workspace/symbol` → `[]` and `documentSymbol` → `[]`, both sent before
  `initialized`.
* the two new capabilities in the `initialize` block.

## 7. Findings, gaps and declined cases — stated

### 7a. `Relation` the TYPE is a Scala-installed builtin, so the brief's example cannot hold

The brief asks that `workspace/symbol "Relation"` find "the stdlib TYPE in its SOURCE `.e` file
(Decision 5 makes this true)".  It is not true of this codebase, and not because of anything 6.4
does: `Relation` is `Type.scala:615`'s `relationT = mkCon[AnyRef](Global("Builtin", "Relation"),
rho ->: star)` — installed by Scala, carrying `Loc.builtin`, with no `.e` declaration anywhere in
the 129 modules.  It is in exactly the same class as `Just`, which the brief's very next clause
asks be ABSENT.  Listing it would require inventing a source position it does not have.

So the query is pinned on what it does find: the stdlib TYPE `SoftRelation` (Struct) in
`modules/Layout/Report/SoftRelation.e`, the stdlib TERM `relation` in `modules/Relation.e`, and a
positive assertion that no result is named `Relation`.  A second query, `"sortorder"`, pins the
same property on a cleaner example (`SortOrder`, Struct, `modules/Relation/Sort.e`) and doubles as
the case-insensitivity check.  Decision 5 IS what makes those two answer their source files rather
than `.ei` text; the premise holds, the example did not.

### 7b. A `foreign` declaration is a Function, but it is not a term group

The brief asks the corpus property to check "the count of Function/Variable symbols equals the
number of distinct top-level term groups the renamer's `moduleTerms` knows".  Taken literally that
is false, and the first run of the property said so: 3836 Function/Variable symbols against 3441
`moduleTerms`, 60 files disagreeing, `Float.e` with ten Function symbols and zero module terms.
The reason is not a merge bug — it is that a `foreign function` prints as a Function to an editor
(that is what it is to a caller) while `Renamer.collectHeads` walks signatures and equations only
and never binds one.  Class members are in the same class of thing, which is why they are Methods.

The property therefore compares `Symbols.termGroups` — a function ON THE BUILDER that says which
symbols came from a term group, skipping `Module` subtrees (an import, a `foreign` block) and
`Interface` subtrees (a class body is its own binding scope) and recursing through `private` and
`database` namespaces (which `collectHeads` walks into) — against `moduleTerms`.  That is the
check the brief wanted, stated in terms the codebase actually has, and it is EXACT: 3441 = 3441,
zero files disagreeing.  It is a refinement of the brief's sentence, not a weakening of it: the
original sentence would have had to be satisfied by mis-kinding foreign declarations.

### 7c. What is inherited, incomplete or deliberately plain

1. **Tab-expanded columns (ticket E8) are inherited, not fixed.**  Symbol ranges use the same
   `(line, column)` model as every other range in this server, and on a tab-indented line that
   model is in the parser's units.  Six corpus occurrences are in that class
   (`core/examples/GridExample.e`).  The brief forbids inventing a second conversion path and this
   item does not.
2. **`class`, `table` and `database` are pinned by a parser-only property, not by a live fixture.**
   They are essentially unused in the corpus — `Eq.e`'s class is inside a block comment,
   `Syntax/Procedure.e`'s `database` is in a doc comment — and Stage-3 Decision (f) parks the bare-
   `class` divergence explicitly.  Rather than write a fixture whose cleanliness would depend on
   that parked behaviour, the mapping for all three is pinned on the surface parser alone
   (`TestRenamer`, "6.4: every statement kind maps to a SymbolKind"), which needs no session and
   asserts the kinds, the containment and that class members stay out of `moduleTerms`.
3. **`private foreign` shows as a `private` Namespace containing a `foreign` Module with the same
   range.**  That is the tree `SurfaceParsers.foreignBlockP` builds
   (`SPrivateBlock(span, List(SForeignBlock(span, …)))`), reported faithfully rather than flattened
   — flattening would mean the outline disagreed with the tree every other request reads.
4. **A workspace hit's `location` is the NAME's range, not the declaration's.**  `SymbolInformation`
   has one range and an editor jumps to it; the name is where a reader wants the cursor.  The
   document tree carries both.
5. **Kind for a session global is the best a `V` supports.**  Upper-case initial → Constructor,
   otherwise Function; a `V` records no arity, so Variable is never claimed for a session name even
   though the same name in an open buffer would get it.  Stated rather than guessed at.
6. **The session name list is process-global and never invalidated.**  It is built once and the
   resident session never reloads (Decision 5); a restart is a new process.  If a later item ever
   makes the session reload, this memo is a thing it must clear.
7. **A `type` alias and a `foreign data` are both Class 5.**  `TypeParameter 26` was the other
   option the brief offered and was rejected: an editor draws it as a generic-parameter icon, which
   would read as a type variable sitting next to real ones.  Class 5 is free — `class` takes
   Interface 11 — and both statements name a type with no constructors of its own.
8. **(fix round, review F8) `where`, `let` and `do` binders are NOT symbols**, deliberately: the
   brief asked for one symbol per TOP-LEVEL group, an outline lists a module's declarations, and a
   local binder is reached by hover, go-to-definition, find-references and highlight instead —
   all of which have answered on locals since 6.2/6.3.  `whereTop x = helper x where helper y = y`
   is one symbol.  Now said out loud here and in `docs/lsp.md`; a hierarchical outline is exactly
   where a reader would look for them, so silence was the wrong answer.
9. **(fix round, review F6) "a query during boot never waits" is narrower than it sounds.**  It is
   true before `initialized`, which is what the pin exercises and what a client that connects and
   queries immediately will see; a request sent AFTER `initialized` queues behind the ~12 s module
   load, because dispatch is single-threaded (Decision 3) and a worker-thread check is a parked
   Stage-4 fork.  §4 already described the mechanism; this states the limit of the claim.
10. **(fix round, review F7) the once-only session-list build sits inside the first query.**  It is
   2157 `File.isFile` stats — filesystem IO, not a parse or an inference, and so not a breach of
   the Stage-3 invariant — and it makes the FIRST query 37.8 ms end to end against 0.2–1.3 ms for
   every one after it.  Under the 50 ms bar as it stands; the smoke's best-of-five cost check is
   taken after the build, so the first-query cost is logged rather than gated.

### 7d. TICKET (review F5, inherited — NOT fixed in this item)

**Stdlib navigation and workspace symbols land in the build output, not the source tree.**  With no
buffer open, `workspace/symbol "not"` answers
`file:///…/core/target/scala-3.3.8/classes/modules/Bool.e:19`, and `textDocument/definition` has
answered that same path since 6.1.  CAUSE: the resident session loads its 129 modules from the
CLASSPATH, and `core/copyResources` puts a copy of `core/src/main/resources/modules` under
`core/target/scala-3.3.8/classes/modules`; `V.loc`/`Con.loc` therefore carry positions in the copy,
and `Definitions.location` faithfully reports them.  IMPACT: 6.4 is what makes it matter — browsing
the stdlib is the point of workspace symbols, and a user who follows a hit and EDITS the file they
land in loses the edit at the next `copyResources`.  It is invisible to both suites: every existing
pin is of the shape `uri.endswith("/Bool.e")` or `endswith("/modules/Relation.e")`, which cannot
tell the copy from the original, and 6.4's own new pins are the same shape.  FIX (two options,
neither taken here): map the target module tree back to `core/src/main/resources/modules` at the
LSP boundary — a path rewrite in `Definitions.location`, one place, but it has to know the mapping;
or boot the resident session from the source tree, which is a `Resident.boot` change and would make
the LSP's module set differ from `bin/ermine`'s.  SCOPE: editor path only; batch and the REPL are
untouched either way.  GATE: Tier 0, plus a pin that distinguishes the two trees (the current
`endswith` pins must become absolute or `resources`-anchored, or the fix cannot be observed).  NOT
a 6.4 regression and not fixed in 6.4, per the coordinator.

## 8. Gates

Tier 0 plus the targeted suites the brief named.  Load average was under 2 at the start of the
timed runs; nothing else was running on the tree, one JVM at a time throughout.  Every number below
was produced on the FINAL tree — every gate below was re-run after the FIX ROUND's last source
edit, not inherited from round one.

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | **green** (the one pre-existing deprecation warning in `NewPipeline.scala:361`, untouched) |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, fuel 0; 3 properties passed |
| `sbt 'core/testOnly *TestRenamer* *TestTolerantRead *TestTolerantCheck *TestEditorBuffers *TestReplDifferential'` | **72 / 72 passed, 0 failed, 0 errors** — TestRenamer **28** (24 after 6.3; 27 after round one, +1 in the fix round), TestTolerantCheck 26, TestTolerantRead 11, TestEditorBuffers 6, TestReplDifferential 1 |
| TestRenamer collected data | `files 252 \| symbols 8159 \| Class 225, …, Variable 1995`; **`files 252 \| sibling levels 8411 \| identical-range pairs 1824 \| straddling pairs 0`**; `files 252 \| term groups 3441 \| moduleTerms 3441`; 6.3's two lines unchanged (`occurrences 71248 \| exact 70897 \| backticked 39 \| parenthesised 306 \| behind a tab 6 \| other 0`) |
| `tracker/tools/corpus-run.sh --batch <scratch>/corpus` | 154 outputs, **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** |
| `tracker/tools/repl-smoke.sh` | **8 groups / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); goldens unmodified (`git status tracker/repl-tests` clean) |
| `tracker/tools/lsp-smoke.sh` | **344 checks** (6.3's baseline 306; +32 in round one, +6 in the fix round) |
| boot | `ready — 129 modules in 11.9s` |
| Report.e check time before/after | round trip 1.24–1.30 s warm BEFORE, 1.26–1.30 s AFTER — unchanged; the index 13.5–13.9 ms warm before, 13.8–14.7 ms after (§1a).  Re-measured after the fix round: 511 symbols, 58.7 / 18.4 / **14.7** ms, round trip 2.04 / 1.35 / **1.26** s — the new range rule moves neither |
| workspace-symbol cost | list built once, **36 ms / 2157 globals**; queries **0.21–1.27 ms**, first query 37.8 ms including the build (§3a) |
| `.ei` | **0** outside `tracker/g1-*`, re-verified after every JVM (the LSP runs `useInterface=false`; nothing wrote any) |
| line endings | `git diff --stat` and `git diff --stat -w` are **IDENTICAL** — no file reformatted (every file this item touches was already LF) |

Not run, and why: **Tier 1** (no solver, no `Type.scala` constraint construction, no executable
Lean — this item touched no file outside `lsp/` at all); **Tier 2** (`core/test` in full — not an
adoption commit, no default flips); no perf A/B (no inference, no check added; the one check-path
addition is measured against its own before in §1a).

## 9. Files changed

* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Symbols.scala` — **new**: the `Sym` model,
  `build` (the statement → SymbolKind mapping and the group merge), `containsRng`, `overlaps`,
  `beforeSym` and `termGroups` (the rules the corpus properties call), the JSON rendering, the
  session's global name list, and both request handlers.  Fix round: the `Hit`/contiguous-run range
  rule and selection-based container (F1, F2), `overlaps`/`beforeSym` (F3), and the Namespace
  filter in `workspace/symbol` (F4).
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Definitions.scala` — `DocIndex.symbols`,
  and the `Symbols.build` call inside `index`.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Diagnostics.scala` — the symbol count in
  the `index:` timing line (the item's budget line).
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Resident.scala` — `loadedEnv`, the resident
  env without a boot and without a copy.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Main.scala` — the two capabilities and
  `Symbols.install`.
* `scalacheck-binding/src/main/scala/TestRenamer.scala` — the corpus is parsed once
  (`corpusTrees`), and four 6.4 properties (the fourth is the fix round's sortedness/straddle one).
* `tracker/tools/lsp-client.py` — the 6.4 block (+32 checks), the two capability assertions, the
  before-boot pair, and the fix round's block (+6: the `Scope.e` tree, the live straddle census
  over three fixtures, the container-leak assertions).
* `tracker/lsp-tests/Syms.e`, `tracker/lsp-tests/Scope.e` — **new** fixtures (the second from the
  fix round).
* `docs/lsp.md` — the document-symbol kind table, the range rule and what it leaves out, the
  `where`/`let` sentence, the workspace-symbol section, and the harness count 306 → 344.
* `tracker/loopmodel/LSP3-6.4-SYMBOLS.md` — this report.

No file outside `core/src/main/scala/…/lsp/` changed in `core/src/main`.  No `Subst.scala`,
`Type.scala`, `Lower.scala`, `Renamer.scala`, `TolerantCheck.scala` or `NewPipeline.scala` change.
No `tracker/LSP-ROADMAP.md` or `tracker/lean/` change.  No commits.  The two untracked briefs
`brief-LSP3-6.5/6.6.md` were already in the tree when I started and are not mine.

STOP after this report, per the brief; a reviewer re-runs the gates once.


## Orchestrator's note at commit (second review pass, S1-S4)

S1: the identical-range example `symBoth, symAlsoBoth : Int` cited above is stale after the F1 fix (their pin now
reads (18,0)-(19,11) vs (20,0)-(20,15), disjoint); every one of the 2018 identical sibling pairs in the reviewer's
358-file census is a multi-name `field` statement, and the only Function construction that still yields identical
ranges is a multi-name signature with no equations (zero in the corpus).  Identical sibling ranges are fine for
clients.  S2: the range rule drops ANY statement outside the anchor's contiguous run, not only "a separated sig";
in legal code only signatures are ever dropped (16 of 6146 group heads over 358 files, all signatures — an equation
outside the run is an interleaved-equations refusal).  S3: the mirror of F2 (equation top-level, sig inside
`private`) leaves an empty `private` namespace, correctly, because the symbol is emitted where its selection is.
S4: a fixity line between a sig and its equation breaks the run and drops the sig (legal, absent from the corpus).
