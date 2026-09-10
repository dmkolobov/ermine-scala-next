# LSP Stage 3, item 6.5 — completion

Implementer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.5.md`; item of record
`tracker/LSP-ROADMAP.md` § Stage 3, item 6.5 with the STAGE-3 INVARIANTS and Decision (c); gates
`tracker/GATE-POLICY.md`.  Branch `scala3-migration`, from `46f88e1` (6.4 committed).  No commits of
my own; no change to `tracker/LSP-ROADMAP.md` or `tracker/lean/`.  **FIX ROUND** (this revision)
after the independent review `tracker/loopmodel/LSP3-6.5-REVIEW.md` (FIX-THEN-ADVANCE): **F-2, F-3,
F-5, F-6 and F-8 are all addressed** — F-2 by shipping the qualified `textEdit` and its import line
(§4a, a CODE change the coordinator ordered beyond the reviewer's "restate only"), F-3 by the reverse
corpus property (§8a), F-5 by running and tabling `*TestLower`, F-6 in `docs/lsp.md`, F-8 by a `do`
block in the fixtures with three end-to-end pins.  F-1, F-4, F-7, F-9 and F-10 need no action here
(F-7 is the orchestrator's note on Decision (c)).  **FINAL ROUND** after the reviewer's SECOND PASS
(same file, "Second pass", S-1..S-4): **S-2 is FIXED** (a type and a constructor of one spelling are
two qualified items, §4b), **S-1 is fixed and stated** (an aliased import inserts the affix form,
§4b), **S-3 is stated** (`Module.` lists ORIGIN names, not exports, §4c) and **S-4 is now PINNED**
(the `using`-list gap has a negative smoke check, §8b).  S-5..S-9 need no action.

**OUTCOME: GREEN.**  `textDocument/completion` ships in all four contexts, answered entirely from
the last check's tables and the current buffer text; every gate is green; the per-request server
time on `Layout/Report.e` is **2.5 ms** (median of ten) against a 50 ms bar; the scope-agreement
properties are **0 disagreements over 6643 local occurrences** and **0 false locals over 39 487**
in 252 files; lsp-smoke **344 → 407**.

The item found and fixed **two real bugs in the scope-at-position layer** — the thing 4.2 built,
deferred "to where a consumer exists", and never tested.  `scopeAt` folded its frames the wrong way,
so an OUTER binding shadowed an inner one (88 corpus occurrences disagreed with the renamer's own
resolution), and a `do` binder's frame covered only its own bind statement, so `scopeAt` reported it
nowhere it was usable (33 more).  Both are fixed in `rename/Renamer.scala` and both are now pinned
at 0 by a corpus property.  The 4.2 note that this layer "was subsumed by G1Resolution" was wrong:
the differential says every REFERENCE resolves as the fused pipeline resolved it and says nothing at
all about the frame stack.

---

## 1. What answers a completion, and what does not

`textDocument/completion` reads exactly two things:

1. **The last check's tables**, stored in `Definitions.DocIndex`: the renamer's `frames` (through
   `Renamer.Result.scopeAt`) and `binders`; 6.2's `locals` (def-site → type); 6.4's symbol tree (the
   module's own declarations, with their checked types); and the `ModuleScope.Scope` the check built
   (`canonicalTerms`/`canonicalTypes` — the exact set of names this file's imports put in scope —
   plus its `termNames`, for the V a name's type hangs off).
2. **The current buffer text**, read LEXICALLY and only on the request's own line: the word prefix at
   the cursor, and which of the four contexts applies.

No parse, no rename, no check and no inference is reachable from the handler.  The one thing on the
request path that touches the world outside the process is the module-name walk (§4), which is
filesystem IO — a `File.listFiles` recursion, cached — not an analysis; 6.4's workspace list is
2157 `File.isFile` stats in the same class.

Batch semantics are untouched: no file outside `lsp/` changed except `rename/Renamer.scala`, whose
change is confined to `Result.scopeAt` (a function with two callers, both in `lsp/`) and to the
FRAMES table (which nothing on the batch path reads — the renamer's own resolution uses its `env`
stack, not `frames`).  The evidence is the gates: corpus `--batch` 85/69/0 over 154, repl goldens
byte-identical, TestLoopTrace 720/720, `TestTolerantRead`'s 180-file agreement property green.

### 1a. What the check path pays

Nothing measurable.  `Definitions.DocIndex` gained four fields and a fifth for the module list, and
every one of them is a REFERENCE to a table the check already built — `c.locals`,
`c.scope.termNames`, `env.cons`, `c.root` (a String) and `env.loadedModules.keySet` (a view).  No
walk, no copy, no rendering was added to `index`.  `Resident.Checked` gained `root`, the module root
`checkFile` already computes for its loader.  Measured anyway, one pair, `Layout/Report.e`
(1757 lines), one cold check then two warm ones, twice on each side; BEFORE is this tree with the
five source edits stashed and `Completion.scala` moved out, rebuilt and re-run in the same shell
(the 6.4 protocol).  Load average 1.85 on both sides.

| | index build (cold / warm / warm) | check round trip |
|---|---|---|
| BEFORE, run 1 | 52.7 / 17.9 / 14.1 ms | 2.02 / 1.43 / 1.24 s |
| BEFORE, run 2 | 12.1 / 15.8 / 11.3 ms | 1.22 / 1.34 / 1.45 s |
| AFTER, run 1 | 60.3 / 18.4 / 15.5 ms | 2.06 / 1.31 / 1.29 s |
| AFTER, run 2 | 13.4 / 15.4 / 12.0 ms | 1.25 / 1.47 / 1.33 s |

Warm index 11.3–17.9 ms before, 12.0–18.4 ms after — one band, its own run-to-run spread.  Round
trip 1.22–1.45 s before, 1.25–1.47 s after.  **Unmoved**, as it must be for a change that stores five
references.  7980 occurrences and 511 symbols on both sides (the index itself did not move either).

## 2. The context rules (6.5.1)

One function, `Completion.contextAt(line, col)`, over ONE LINE of the buffer and a 0-based column.
It is public and free of every server type, so the property calls the shipped rule rather than
restating it.

| the text before the cursor | context | the prefix |
|---|---|---|
| a line whose first word is `import` or `export`, with only a dotted name after it | **module** | the whole dotted text (`import La` → `La`; `import Layout.` → `Layout.`) |
| an identifier prefix preceded by `.`, itself preceded by a dotted path of upper-initial segments | **qualified** | the identifier prefix; the path is the module |
| anything else | **name** | the identifier characters backwards from the cursor |
| inside a `--` comment, a `{- -}` opened on this line, or a `"…"` string | **dead** → `[]` | — |

* **The prefix is an IDENTIFIER** — `Lexer.isTailChar`s backwards from the cursor, the surface
  lexer's own character class.  **OPERATORS ARE NOT COMPLETED**: a cursor after `<+` has an empty
  prefix and completes names.  An operator's written form is not its spelling (`(<+>)` in a
  reference, `<+>` in a fixity line), so offering one means guessing which form to insert — the same
  reason 6.3's rename refuses operators outright.
* **The module rule stops at the first space**: `import Bool using no` is a NAME context, not a
  module one.  Completing inside an import LIST (offering the module's exports there) would be a
  fourth context; it is not built, and `import M using (` answers with the file's own scope, which is
  wrong-but-harmless rather than silent.  Stated, not fixed.
* **`Module.` requires every segment upper-initial** and the whole path preceded by a non-identifier
  character, so `x.y`, `rec.field` and `fooBar.baz` are NAME contexts.
* **The comment/string test is LINE-LOCAL, with a stated gap**: a `{- … -}` block comment opened on
  an EARLIER line, and a string that spans lines, are not detected — inside one of those, completion
  answers as if the cursor were in code.  The brief allows the line-local heuristic explicitly ("use
  the surface `Lexer`'s notion if cheap, else a line-local heuristic and say so"); this is the
  saying-so.  A whole-buffer prefix scan would close it for ~0.1 ms per request on a 60 KB file and
  is the obvious fix if anyone minds.
* **Positions are the server's own model**: LSP 0-based, `Span` 1-based, `line + 1` / `col + 1`,
  tab-expanded parser columns inherited (**ticket E8**) exactly as hover, definition, references and
  symbols have inherited them since 0.5.  No second conversion path was invented.  `scopeAt` is asked
  about the position the WORD STARTS at — the position the name being typed occupies, and the one the
  corpus property pins.

Sixteen cases of this table are pinned in `TestRenamer` ("6.5: the context rules over one line of
text"), including `import Bool using not` → `Names("no")`, `x = Layout.Report.so` →
`Qualified("Layout.Report", "so")`, `x = rec.fie` → `Names("fie")`, and `x = "s" ++ no` →
`Names("no")` (a closed string does not poison the rest of the line).

## 3. The items, their sources and their ranking (6.5.2)

Name context, in tier order.  **Prefix-filtered SERVER-SIDE**, case-sensitive first; a
case-insensitive prefix match is kept and ranked BELOW every exact-case match of its own tier
(`sortText` = tier, then `0`/`1` for exact/case-insensitive, then the lower-cased label).

| tier | source | CompletionItemKind | `detail` |
|---|---|---|---|
| 0 | **locals** visible at the position — `Renamer.Result.scopeAt`, filtered to binder kinds that are not `TopLevel`/`TyDef` | Variable 6 | 6.2's type for that def-site, rendered through `Pretty.prettyTypeIn` so an argument's letters agree with its binding's own hover |
| 1 | **this module's own declarations** — 6.4's symbol tree, flattened, containers (import, `foreign`, `private`, `database`) dropped | Function 3 / Variable 6 / Constructor 4 / Class 7 / Enum 13 / Field 5 / Interface 8 / Method 2 / Property 10 | the checked type (`Sym.ty`, printed like hover), else the symbol's own detail string |
| 1 | **top levels the renamer bound that the symbol tree has not** (a group whose statement did not parse still binds its head) | Function 3 | none |
| 2 | **imported terms** — the check's `ModuleScope` canonical term map | Constructor 4 if upper-initial, else Function 3 | the type on the `V` the scope carries |
| 2 | **imported types** — the canonical type map | Class 7 | the kind schema, printed by `Pretty.ppKindSchema` (the printer `:kind` uses) |
| 3 | **keywords** — `SurfaceParsers.keywords`, the grammar's own set | Keyword 14 | none |

**Arity decides Function vs Variable for an own top level** because 6.4's symbol tree already made
that decision from the surface tree ("a group with at least one equation that takes an argument" is
Function 12).  For an IMPORTED name a `V` records no arity, so Function 3 is used for everything
lower-initial and Variable is never claimed — the same rule 6.4's workspace list states.

**One item per LABEL** (`dedup`, first in ranking order wins): a local shadowing an import is offered
once, as the local, which is what the name MEANS at that position; a type and a constructor of one
spelling collapse likewise, since in a NAME context the text to insert is identical either way.  (In
a QUALIFIED context it is not — the import line differs by namespace — so that branch dedups on
(label, namespace) instead; §4b.)

**Type variables are not offered at all, and that is a fact about the tables, not a choice.**  The
brief asked "do you know you are in a type? if not, say so and offer them anyway or not,
consistently".  The answer: we do not know, and it does not arise — `TyParam`, `TyImplicit` and
`KindParam` binders are in NO frame, so `scopeAt` never sees one.  Measured, not assumed: 12339 of
the corpus's 18982 local occurrences are type-level and the scope layer reports none of them
(the property collects the figure).  The scope-at-position layer is a VALUE-scope layer.  What IS
offered in every context, type or term, is a NAMED type — own (`Colour`, `Pair`) and imported (`Int`,
`Nullable`) — because those come from the symbol tree and the canonical type map, which have no
position information to filter by.  So `data Colour = Re|` offers `Red` and `Relation` alike.

**`isIncomplete`.**  A prefix-filtered answer is COMPLETE (`false`): the client may narrow it itself
as more characters arrive.  Three answers say `true`: the empty prefix (§5), an answer the 300-item
cap truncated, and a document whose first check has not finished (a client that took an empty
COMPLETE list would cache it and never ask again).  This is the one place the brief's blanket
"`isIncomplete: false`" is not followed, and it is deliberate: 6.5.5 asks for a partial answer on an
empty prefix, and a partial answer marked complete is a list the client stops refreshing.

## 4. Module names (A) and qualified names (B) — 6.5.3

**Module context.**  The candidate set is the union of FOUR sources, prefix-matched on the whole
dotted path and kinded Module 9:

1. **what the last check of this file had loaded** (`env.loadedModules.keySet`) — its own imports and
   their closure;
2. the resident session's `loadedModules` (the 129);
3. the `.e` files under this file's module root (`Resident.checkFile`'s `root`, now carried on
   `Checked` and in the index), walked as a directory tree, upper-initial names only;
4. the open buffers' own module names (a module that exists only as an unsaved buffer).

Source 1 is not in the brief and had to be added: `Layout.Scan` is imported by this item's own
fixture, is a real module, and is in NONE of the other three (the resident session's Layout closure
does not reach it, and it is not under the fixtures' root).  The smoke pins it.

The directory walk is filesystem IO on a request path — not a parse, not a check — and is cached per
root for **5 seconds**, so a module the user creates while the editor is open appears within five
seconds rather than never (the alternative, 6.4's build-once, cannot see a new file at all).  Cost on
the largest root (the stdlib tree, ~180 files): **5.3 ms cold, 0.2–0.3 ms cached**.

**Qualified context.**  `Module.` answers with that module's exports: terms from the scope's
`termNames` filtered by `g.module`, with their types; types from the check env's `cons`, with their
kinds; plus the flattened symbol tree of an OPEN BUFFER of that module (a sibling the resident
session has never seen).  An unknown module answers `[]`.  Because the source is the check's own
session superset, `Bool.` answers whether or not this file imports `Bool`.

### 4a. A dotted reference does not parse in this fork — in ANY position (review F-2)

**The first round's claim that qualified completion "is correct and useful for a TYPE position and
for a qualified CONSTRUCTOR" was wrong, and the reviewer refuted it by measurement.**  On
`Complete.e`, where `zzD = not True` and `zzE : Bool` both check clean:

```
zzA = Bool.not True   ->  error: unknown operator .
zzB = Bool.True       ->  error: unknown operator .
zzC : Bool.Bool       ->  error: unknown type operator .
```

The reason is order, not grammar: `SurfaceParsers.varTerm` is
`identTok | literalIdentTok | moduleQualCon` and `tyName` is `identTok | moduleQualCon |
qualDottedName`, so the upper-initial first segment is consumed by `identTok` and the dotted
alternative never runs; the `.` is then read as composition.  The renamer has no dotted-name path
either — nothing in `Renamer.scala` splits a spelling on `.`, and the canonical maps are keyed by the
imported LOCAL name with `_M` affixes for aliases (`empty#_NM`, `lookup_M`, `at_V` in the stdlib).
**Qualified completion is a module BROWSER in this fork; the dotted text is not code.**

**SO THE ITEM DOES NOT INSERT IT** (the fix round, the coordinator's instruction over the reviewer's
"restate only").  A qualified item carries:

* a **`textEdit`** whose range runs from the first character of the dotted module path to the cursor
  and whose `newText` is the **bare name** — `Bool.no|` becomes `not`, which this grammar reads;
* a **`filterText`** of `Module.label` (`Bool.not`), because the client is matching against the
  dotted text the user typed; without it an editor filters `not` against `Bool.n` and shows nothing;
* an **`additionalTextEdits`** entry inserting `import M using <name>` (or `using type <name>`)
  after the last import line — after the `module … where` line when there are none — **when M is not
  already imported in this file**.  The check is a lexical scan of the CURRENT buffer for lines whose
  first word is `import`/`export` (`Completion.importLines`): no parse, and an import the user typed
  a second ago counts.  The inserted line matches the buffer's own line terminator (142 of the 161
  stdlib modules are CRLF).

`using` is the form this grammar has (`SurfaceParsers.importStatement` takes `using`/`hiding` over a
laid-out list; there is no parenthesised `import M (a, b)` form in this fork, whatever the roadmap's
6.6 sketch says).  Both halves are pinned END TO END in lsp-smoke: the edit's exact range and
`newText`, the `filterText`, the absence of an import edit for an already-imported module, its
presence for `Maybe.` — and, for both, the edits APPLIED by the client script and re-sent as a
`didChange`, after which **the file checks clean**.

WHAT IS STILL NOT DONE, deliberately: if M is already imported WITH a `using` list that does not name
the picked name, nothing is added and the bare name will not resolve until the list is extended.
Editing an existing import list is 6.6's add-import quick fix, by name; this item does not touch a
list it did not write.  Stated in `docs/lsp.md` too, and since the final round it is PINNED: the
smoke applies exactly that completion and asserts the ONE diagnostic it leaves (review S-4), so the
gap is a fact in the harness rather than a paragraph, and 6.6 closing it will show up here.

### 4b. Two things the edit has to know: the alias, and the namespace (review S-1, S-2)

**S-2, a spelling that is both a TYPE and a CONSTRUCTOR.**  `exportsOf` returns the terms and the
types of the module, and round two's `dedup` kept the first per label — so `Ring` the constructor
swallowed `Ring` the type, and since the import line is chosen by the item's kind
(`i.kind == KClass`), a TYPE position got `import Ring using Ring` and two diagnostics.  The reviewer
found it, and it also falsified the `dedup` comment ("the text to insert is identical either way"),
which was true before an `additionalTextEdits` rode on the kind.  FIXED: the qualified branch dedups
on **(label, namespace)** (`dedupQualified`), so `Ring.` offers two items —

| item | kind | import line | applied to `type QQ = Ring.Ring Int` |
|---|---|---|---|
| `Ring` the type | Class 7 | `import Ring using type Ring` | **0 diagnostics** |
| `Ring` the constructor | Constructor 4 | `import Ring using Ring` | 1 diagnostic |

— and the editor tells them apart by kind and detail (a kind schema vs a type).  We cannot tell a
type position from a term one lexically, so both are offered; both rows above are pinned in the
smoke, including the negative one, which is what says the split earns its keep.

**S-1, an ALIASED import.**  `import Bool as B` puts the module's names in scope ONLY in the affix
form — `ModuleScope.local` calls `Global.localized(as, …)`, which is `name + "_" + alias` — so a bare
`not` does not resolve there, and no import edit can save it because the module IS imported.  Round
two inserted the bare name and left the file broken.  FIXED: `importLines` now reads `import M as A`
too (`importOf` answers "not imported" / "plainly" / "as A"), and under an alias the item inserts
**`not_B`**.  Pinned end to end on the new fixture `CompleteAlias.e`: the item's `newText` is
`not_B`, it carries no import edit, and the applied buffer **checks clean**.

STILL NOT HANDLED, stated: the ALIAS ITSELF as a qualifier.  `B.n|` is recognised as a qualified
context (`B` is upper-initial) and `exportsOf` filters on `g.module == "B"`, which no Global matches,
so it answers `[]`.  Benign — nothing wrong is offered — and mapping an alias back to its module is
a lookup this item does not have; `docs/lsp.md` says so.

### 4c. `Module.` lists ORIGIN names, not exports (review S-3)

`exportsOf` filters both tables on `g.module == mod`, and a re-exported name keeps the `Global` of
the module that DEFINED it.  So `Maybe.` answers with the sixteen functions `Maybe.e` itself defines
(`catMaybes`, `getJust`, `isJust`, `maybe`, …) and NOT with `Maybe`, `Just` or `Nothing`, which
originate in `Native.Maybe` and are re-exported.  Nothing wrong is emitted — every name offered is
real and its import edit checks — but the most obvious thing a user types `Maybe.` for is the one
thing it does not offer.  §4's wording is corrected here and in `docs/lsp.md` ("the names whose
ORIGIN is that module"), and the fix is a chase through `termOrigins`/`consOrigins` — the very walk
`Definitions.index` already does for its keys — which is a 6.6/6.7-sized change, not a 6.5 one.

## 5. The unfiltered payload, and what an empty prefix answers (6.5.5)

Measured ONCE, on `Layout/Report.e` (1757 lines, the Prelude/Layout closure in scope), with a
temporary build whose empty-prefix branch returns everything, reverted immediately after:

| empty prefix on Report.e | items | JSON bytes | server-side | client round trip (median of 10) |
|---|---|---|---|---|
| **UNFILTERED** (locals + own + imported + keywords) | **1332** | **180 752** | 2.1 ms | **33.7 ms** |
| **SHIPPED**: locals + own, capped at 300, `isIncomplete: true` | 300 | 52 490 | 1.8 ms | 14.9 ms |

(The logged server-side figure is the time to BUILD the answer; the client figure additionally
contains JSON encoding and the write of 176 KB, which is where the difference lives.  Both are quoted
so neither flatters the other.)

**THE DECISION: option (i) — locals + own only — with `isIncomplete: true`.**  Why not (ii),
everything capped: 1332 names is not an answer to "what can I write here", and 176 KB on a keystroke
is thirty times the answer a prefix produces.  Why the flag matters: with `isIncomplete: false` a
conforming client caches the list and filters it itself, so the imported names would never appear —
the partial answer would become a permanent one.  With `true`, the moment the user types a character
the client asks again and gets the full prefix-filtered set (imports and keywords included), which is
the case that actually matters and costs 11 KB.  The 300 cap is the same bargain for a pathological
prefix and it too sets the flag.

Note that "empty prefix" is not an idle case: the `.` trigger character produces one, and so does a
cursor after a space.  On `Report.e` the shipped answer is that file's own 511 declarations plus the
locals in scope, capped — an outline of the module you are typing in, which is a reasonable thing to
show and a defensible 52 KB.

## 6. Per-request timing (the 50 ms bar)

`Layout/Report.e`, line 1504 (deep in the file, inside `(fieldName parentId)`), server-side, from the
log line the handler prints on every completion; median of ten, JIT warm-up included in the sample:

| position | items | candidates in scope | median | min–max |
|---|---|---|---|---|
| prefix `f` | 97 | 1332 | **2.5 ms** | 1.9–11.5 (first call) |
| prefix `fie` | 4 | 1332 | 1.6 ms | 1.5–2.3 |
| empty prefix | 300 (capped) | 1332 | 1.8 ms | 1.4–2.3 |

Client round trips for the same three: 6.5 / 2.0 / 14.9 ms.  **The bar is 50 ms and the answer is
2.5.**  What keeps it there is that `detail` is a THUNK: the candidate list is every name in scope
(1332 on this file), and a type is rendered only for the items that survive the prefix filter and the
cap — at most 300 `Pretty` runs, normally a handful.  The first version rendered every candidate's
type before filtering; it is the one thing in this item that would have missed the bar.

The log line is standing (`completion: Report.e name prefix='f' 97 items of 1332 in scope in 2.5 ms`),
so this is a measurement anyone can repeat, not a one-off.

## 7. Two bugs in the scope-at-position layer, found by the property

### 7a. `scopeAt` folded the wrong way — the OUTERMOST binding won

`Renamer.Result.scopeAt` sorted the frames containing a position by extent (outermost first) and then
`foldRight`ed them with `acc ++ f.bindings`, which applies the HEAD last and so let the outermost
frame overwrite every inner one.  Against the renamer's own resolution — which takes the first hit in
an innermost-first `env` — that is backwards, and on the corpus **88 of 6643 local occurrences
disagreed**: `Ap.e:35 ap` resolves to the equation's argument and `scopeAt` answered the top-level
`ap` it shadows; `Report.e:182 h` resolved to an argument and `scopeAt` answered a top level 67 lines
away; `Column.e:123 ss` answered an outer argument instead of the inner one.

Fixed by folding LEFT (the frames are nested, so ordering by extent orders them outermost first and
the inner scope must be applied last).  A completion is what makes it visible — offering the wrong
binder's TYPE — but the same table is what 6.3's rename asks "would this new name be captured here",
so the fix is not cosmetic.

### 7b. A `do` binder's frame covered only its own bind statement

`Renamer.term`'s `SDo` case pushed `Frame(loc.span, b)` where `loc` is the SDoBind's own span.  A do
binder is visible to every LATER statement of the block (which is what the renamer's `cur = b :: cur`
does) and not to its own rhs, so the frame said neither: every use of a do binder in `Monad.e` — 33
occurrences — resolved to a binder `scopeAt` reported as "not visible at all".  Fixed: the frame runs
from the END of the bind statement (spans run to the start of the next token, so that is the next
statement's start) to the end of the do block.  Completion now offers a do binder where it is usable.

Both fixes are in `Renamer.scala` and both are pinned at 0 by the property below.  Neither can reach
the batch path: `frames` is consumed only by `scopeAt`, whose callers are this item and 6.3's capture
refusal.

## 8. Tests

### 8a. The corpus properties — `TestRenamer` 28 → 32

Over stdlib + `core/examples`, the standing 180-file rule (253 files found, 252 parse).

| property | result |
|---|---|
| **6.5: scopeAt agrees with resolution at every local occurrence** — for every `ToBinder` occurrence of a value-level local binder, `scopeAt(occurrence start)` maps its spelling to its own id | **0 disagreements of 6643, over 252 files** (88 before the 7a fix, 33 before 7b) |
| **6.5: scopeAt claims no local where the renamer used none** (the fix round, review F-3) — for every occurrence that resolved to a TOP LEVEL, an import or nothing, `scopeAt` must not offer a local of that spelling | **0 false locals of 39 487** |
| 6.5: an inner binding wins over an outer one of the same name (anti-vacuity for the two above) | 55 occurrences stand where more than one containing frame binds their spelling — the cases where "innermost wins" is the only thing that can make the two agree |
| **6.5: the context rules over one line of text** — 16 cases through `Completion.contextAt` | proved |

The REVERSE property is the fix round's answer to the reviewer's F-3: the forward property filters to
occurrences that resolved to a value-local binder, so a frame that reaches ONE STATEMENT TOO FAR —
precisely the failure mode the do-binder fix could have introduced — is outside it.  The reviewer ran
that direction in their own scratch tree (0 of 35 920, a slightly different denominator: they
excluded type-level occurrences by a wider rule, 28 663 of them, where this property excludes
12 339 and keeps `Unresolved`/`Ambiguous` occurrences in the denominator).  It is in the tree now, so
a later item cannot over-trust the forward one.

Collected data, printed on a pass:

```
files 252 | value-local occurrences 6643 | scopeAt disagreements 0 | type-level occurrences 12339 (no frames: not offered)
top-level/free value occurrences 39487 | false-local 0
shadowed value-local occurrences 55
```

The type-level figure is in the collect line on purpose: it is the measurement behind §3's "type
variables are not offered", and if a later item ever gives type binders frames, this number is where
it will show up.

### 8b. lsp-smoke — 344 → 407 (+63; +42 in round one, +10 in the fix round, +11 in the final round)

Three new fixtures — `tracker/lsp-tests/Complete.e`, `tracker/lsp-tests/CompleteSib.e` (a sibling it
imports, which also imports `Layout.Scan` for the module-name pins and, since the fix round, carries
a `do` block) and `tracker/lsp-tests/CompleteAlias.e` (the final round: `import Bool as B` and
`import Maybe using isJust`, the two shapes S-1 and S-4 are about) — all three check CLEAN.  What is
pinned, live, end to end:

* **an argument** offered inside its equation, kind Variable, `detail` `Bool` — and its absence from
  every other equation (the empty-prefix answers in the `where` body and the `let` body);
* **a where-bound** (`helper : Bool -> Bool`) in its own block, and the where body seeing `helper`,
  its argument `h` and the equation's `b`, but not `arg` and not `inner`;
* **a let-bound** (`inner : Bool`) in the `in`, plus the equation's argument `c`, and neither
  escaping into another equation;
* **a keyword**: prefix `in` offers `inner` FIRST and the keyword `in` after it, with the tiers
  visible in `sortText` (`0…` vs `3…`);
* **an own top level** with its checked type (`topFn : Bool -> Bool`, kind Function);
* **an own constructor** (`Red : Colour`, kind Constructor) ranked above the imported `Relation`;
* **an imported name** with its type (`not : Bool -> Bool`) ranked below a local `n1`, and a
  case-insensitive match (`Nil`) ranked below every exact-case one, with `sortText` `21…`;
* **a sibling buffer's export** (`sibValue : Bool`);
* **`import La`** offering `Layout` and `Layout.Scan` and nothing that is not a module; **`import
  Layout.`** offering only `Layout.*`; an empty module prefix offering the root's own files
  (`Complete`, `CompleteSib`), the session's (`Prelude`) and the check's (`Layout.Scan`);
* **`Bool.`** offering `not` with its type and nothing from another module; **`Nope.`** → `[]`;
* **(fix round, F-2) the qualified EDITS**: `Bool.no|`'s item replaces exactly `(26,4)-(26,11)` with
  `not`, filters on `Bool.not`, and adds NO import (Bool is already imported); `Maybe.isJust|`'s adds
  `import Maybe using isJust` at line 4; the client script APPLIES each item's `textEdit` and
  `additionalTextEdits`, re-sends the buffer, and **both applied results check clean** — while the
  dotted text itself is pinned as a parse failure (`unknown operator .`);
* **(final round, S-2) `Ring.`** offering TWO items for one spelling, kind 4 with
  `import Ring using Ring` and kind 7 with `import Ring using type Ring`, the type one applied to
  `type QQ = Ring.Ring Int` checking CLEAN and the constructor one applied there leaving exactly one
  diagnostic — the negative half is what says the split is needed;
* **(final round, S-1) an aliased import**: on `CompleteAlias.e`, `Bool.no|` inserts `not_B`, carries
  no import edit, and the applied buffer checks clean;
* **(final round, S-4) the `using`-list GAP as a negative pin**: `Maybe.isNothing|` under
  `import Maybe using isJust` gets no import edit and the applied buffer leaves exactly one
  `undefined term` diagnostic;
* **(fix round, F-8) a `do` binder**: not in scope in its own rhs (`dy <- |fb` offers `dx` and not
  `dy`), both in scope after their statements (`unit (f d|x dy)`), and neither in the FIRST rhs —
  the end-to-end counterpart of the frame rule §7b fixed;
* **a cursor inside a string** → `[]` with `isIncomplete: false`;
* **a broken file** (`LocalsBroken.e`) completing from its healthy statement;
* **a request during boot** → `[]` (sent before `initialized`, so the session has not begun to load);
* the **capability** block, exactly `{"triggerCharacters": ["."], "resolveProvider": false}`;
* **cost** under 50 ms, asserted live (best of five);
* **THE STALENESS PIN**: a didChange adds `zzz = True`; the completion request goes out immediately
  after it and `zzz` is NOT offered; after the diagnostics for that check arrive, the same request
  offers `zzz : Bool`.  Deterministic because the debounce is ~300 ms and dispatch is
  single-threaded, so the request cannot be behind the check.

## 9. The staleness statement, as written into `docs/lsp.md`

> **Staleness is accepted and stated.** Completion answers from the tables the last DEBOUNCED CHECK
> left behind, so a binder you have just typed is not offered until that check lands (~300 ms after
> you stop typing, plus the check itself). The word prefix and the context are read from the buffer
> as it is NOW, so the filtering is always current; only the set of names is as old as the last
> check. The alternative — checking on a completion request — would put a whole check on every
> keystroke, which is the one thing this server does not do. A request that arrives during the ~13 s
> session boot answers with an empty list, never null.

`docs/lsp.md` also gained the full completion section (the four contexts as a table — the fix round
added the comment/string row and the sentence saying the detection is LINE-LOCAL, review F-6 — the
ranking, the `isIncomplete` rule with the 1332-name measurement behind it, the "type variables are
not offered" paragraph, and what a qualified item inserts, and the final round's three limits of `Module.`) and its harness count
moved 344 → 407.
6.7 will fold it in.

## 10. Gates

Tier 0 plus the targeted suites.  Load average under 2 at the start of every timed run; one JVM at a
time throughout; every number below was produced on the FINAL tree.

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | **green** (the one pre-existing deprecation warning in `NewPipeline.scala:361`, untouched) |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, fuel 0; 3 properties passed |
| `sbt 'core/testOnly *TestRenamer* *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestReplDifferential *TestLower'` (the fix round adds the last two; **`*TestLower` is required by the Stage-3 invariant for a `Renamer` change and both briefs omitted it** — review F-5.  The final round touched no property; `*TestRenamer*` was re-run alone to confirm — **32/32**) | **104 / 104 passed, 0 failed, 0 errors** — TestRenamer **32** (28 after 6.4; 31 in round one, +1 for the reverse property), TestTolerantCheck 26, TestTolerantRead 11, TestEditorBuffers 6, TestReplDifferential 1, **TestLower 28**, TestNewPipeline 2, TestLoopTrace 3, plus the suites the wildcards pull in |
| TestRenamer collected data | `files 252 \| value-local occurrences 6643 \| scopeAt disagreements 0 \| type-level occurrences 12339`; `top-level/free value occurrences 39487 \| false-local 0`; `shadowed value-local occurrences 55`; 6.3's and 6.4's lines unchanged (`occurrences 71248 \| exact 70897 \| … \| behind a tab 6`; `symbols 8159`; `sibling levels 8411 \| straddling pairs 0`; `term groups 3441 \| moduleTerms 3441`) |
| `tracker/tools/corpus-run.sh --batch <scratch>/corpus` | 154 outputs, **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** (round one; the fix round changed no file the batch path reads — `Completion.scala`, a test, two fixtures and two docs — and the reviewer re-ran it green independently) |
| `tracker/tools/repl-smoke.sh` | **8 groups / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); goldens unmodified (`git status tracker/repl-tests` clean) |
| `tracker/tools/lsp-smoke.sh` | **407 checks** (6.4's baseline 344; +42 round one, +10 fix round, **+11 final round**) |
| boot | `Ermine session ready: 129 modules in 12.0s` in the fix round (11.9s in round one; BEFORE side 12.0s) |
| Report.e check time before/after | index warm 11.3–17.9 ms before, 12.0–18.4 ms after; round trip 1.22–1.45 s before, 1.25–1.47 s after — **unmoved** (§1a) |
| completion cost | **2.5 ms** median of ten on Report.e (97 items of 1332 in scope); 1.6 ms for a three-character prefix; 5.3 ms for a module context with a cold directory walk, 0.2 ms cached |
| `.ei` | **0** outside `tracker/g1-*` after every JVM (the LSP runs `useInterface=false`; nothing wrote any) |
| line endings | `git diff --stat` and `git diff --stat -w` are **IDENTICAL** — no file reformatted (every file this item touches was already LF) |

Not run, and why: **Tier 1** (no solver, no `Type.scala` constraint construction, no executable Lean;
the `Renamer.scala` change is confined to the frames table and `scopeAt`, which no batch path reads);
**Tier 2** (`core/test` in full — not an adoption commit, no default flips); no perf A/B (nothing is
added to inference or to the check; the check-path pair in §1a is the measurement this item owes).

## 11. What is inherited, incomplete or deliberately plain

1. **Ticket E8 (tab-expanded parser columns) is inherited, not fixed.**  A completion on a
   tab-indented line converts its column the way every other request in this server has since 0.5.
   Six corpus occurrences are in that class.
2. **The comment/string test is line-local** (§2): a multi-line `{- -}` block or a multi-line string
   is not detected, and completion inside one answers as if it were code.
3. **A dotted reference does not parse in this fork in ANY position** (§4a, review F-2) — a finding
   about the fork, not a defect of the item.  Since the fix round the item does not INSERT one: a
   qualified completion replaces the dotted span with the bare name (the `_A` affix form under an
   aliased import, §4b) and adds the import when it is needed.  What remains, all stated and two of
   them pinned: an existing `using` list is never extended (6.6's job, pinned as a negative check);
   the ALIAS itself as a qualifier (`B.n`) answers `[]`; and `Module.` lists ORIGIN names, so a
   re-exported name is not offered under the module that re-exports it (§4c).
4. **An import LIST is a name context**, so `import M using (` offers the file's own scope rather
   than M's exports.  A fourth context would fix it; it is not built.
5. **Operators are not completed** (§2), by the same rule 6.3's rename refuses them.
6. **Type variables are not offered** (§3), because the scope layer has no type frames.  Giving them
   frames is a `Renamer` change of its own and would need a type-context test the buffer scan cannot
   do today.
7. **The module-name walk is filesystem IO on a request path**, cached 5 s (§4).  It is in the same
   class as 6.4's once-only `File.isFile` sweep and is stated for the same reason.
8. **The forward scope property is one-directional** (review F-3) — which is why the fix round added
   the reverse one (§8a).  Neither covers TYPE-level scopes, because there are none to cover.
9. **No `completionItem/resolve`**: every item carries its `detail` already, which is why the thunk
   in §6 matters.  A `documentation` field (a doc comment) would be the reason to add resolve later;
   nothing reads doc comments today.
10. **A completion does not know about the edit that is in flight.**  §9's staleness statement is the
   whole of it; the smoke pins both sides of the line.
11. **The 300-item cap and the 5 s directory TTL are constants in `Completion.scala`** (`Cap`,
    `fsTtlMs`), named and commented rather than tunable — there is no configuration surface in this
    server and this item did not open one.

## 12. Files changed

* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Completion.scala` — **new**: the
  context rules (`contextAt`, `dead`, `lineText`), the item model with its lazy `detail`, the four
  sources and the ranking (`items`, `matching`, `dedup`), the module-name walk (`modulesUnder`), the
  qualified exports (`exportsOf`), the JSON rendering and the request handler.  Fix round: the
  qualified `textEdit`/`filterText`/`additionalTextEdits` (`importLines`, `importEdit`,
  `qualifiedExtras`) and the module-path start column on `Qualified` (§4a).  Final round: the
  namespace-aware `dedupQualified` (S-2) and the alias-aware `importOf` with the affix insertion
  (S-1), both in §4b.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Definitions.scala` — `DocIndex` gained
  `locals`, `importTypes`, `cons`, `root` and `modules`, all references to tables `index` already
  holds; nothing else in the file changed.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Resident.scala` — `Checked.root`, set from
  the module root `checkFile` already computes.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Main.scala` — the `completionProvider`
  capability and `Completion.install`.
* `core/src/main/scala/com/clarifi/reporting/ermine/rename/Renamer.scala` — **the two scope fixes**
  (§7): `scopeAt` folds left (innermost wins), and a `do` binder's frame is the rest of its block.
* `scalacheck-binding/src/main/scala/TestRenamer.scala` — four 6.5 properties (§8a; the reverse one
  is the fix round's) and the `Completion` import.
* `tracker/tools/lsp-client.py` — the 6.5 block (+42 checks), the capability assertion and the
  before-boot pin; the fix round's +10 (the qualified edits applied and re-checked, the `do` pins).
* `tracker/lsp-tests/Complete.e`, `tracker/lsp-tests/CompleteSib.e`,
  `tracker/lsp-tests/CompleteAlias.e` — **new** fixtures; the sibling grew `import Syntax.Do` and a
  `do` block in the fix round (F-8), and the alias fixture is the final round's (S-1, S-4).
* `docs/lsp.md` — the completion section, the staleness paragraph (§9), the latency row, 344 → 407;
  the fix round added the comment/string row, the line-local sentence (F-6) and the paragraph on what
  a qualified item inserts (F-2); the final round the ORIGIN wording and the three limits of
  `Module.` (S-1, S-3).
* `tracker/loopmodel/LSP3-6.5-COMPLETION.md` — this report.

No `Subst.scala`, `Type.scala`, `Lower.scala`, `TolerantCheck.scala` or `NewPipeline.scala` change.
No `tracker/LSP-ROADMAP.md` or `tracker/lean/` change.  No commits.  The untracked briefs
`brief-LSP3-6.6.md` and `brief-LSP3-6.7.md` were in the tree when I started and are not mine.

STOP after this report, per the brief; a reviewer re-runs the gates once.
