# LSP Stage 3, item 6.3 — references, document highlight, rename

Implementer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.3.md`; item of record
`tracker/LSP-ROADMAP.md` § Stage 3, item 6.3 with the STAGE-3 INVARIANTS and Decisions (c)/(d);
gates `tracker/GATE-POLICY.md`.  Branch `scala3-migration`, from `2a9fde1` (6.2 committed).  No
commits of my own; no change to `tracker/LSP-ROADMAP.md` or `tracker/lean/`.  **FIX ROUND**
(this revision) after the independent review `tracker/loopmodel/LSP3-6.3-REVIEW.md`
(FIX-THEN-ADVANCE): R1, R2, R3 and R4 are all addressed — R1 in §11, R2 in §12, R3 in §13, R4 by
the rewritten §6 and this paragraph.

**OUTCOME: GREEN**, after the fix round.  All four requests ship, all of Decision (d)'s refusals
are implemented and pinned, the coverage warning of Decision (c) is sent on every global
request, and every gate is green.  The review found three ways to get a WRONG or PARTIAL edit
past the refusal list — a re-export splitting the key (R1), a backtick literal measured by its
spelling (R2), and a stale sibling with no hit escaping the version check (R3).  All three are
fixed, each with a live pin in lsp-smoke, and each is now either CORRECT or a REFUSAL WITH A
MESSAGE.  §6 lists what is left, including the classes rename declines to touch and the one
pre-existing position bug (tab-expanded columns) it now refuses rather than corrupts.

---

## 1. The index extension (6.3.1), and what it costs

`Definitions.Occ` grew three fields and `DocIndex` five.  Everything a request needs is now
STORED; nothing is re-derived from text and nothing re-runs an analysis.

```scala
sealed abstract class Key
final case class LocalKey(binderId: Int)                     extends Key
final case class GlobalKey(origin: Global, typeLevel: Boolean) extends Key

final case class Occ(line, startCol, len, target, hover, kind,
                     key: Option[Key], spelling: String, isDef: Boolean)

final case class DocIndex(occs, version: Long, moduleName: String,
                          renamed: Renamer.Result,
                          scopeTerms: Map[Local, List[Name]],
                          scopeTypes: Map[Local, List[Name]])
```

* **`key`** is what two occurrences must agree on to be one name.  A `LocalKey` is a renamer
  binder id, meaningful only inside the document whose check minted it.  A `GlobalKey` is the
  canonical `Global` — `ToGlobal.origin`, never the `g` the reference was written through, so an
  alias-imported name and its canonical name find each other across buffers.  `typeLevel` keeps
  `data Color = Color Int`'s two meanings apart, the same reason `Occurrence.typeLevel` exists.
  Where each key comes from:

  | occurrence | key |
  |---|---|
  | `ToBinder` of a `TopLevel` binder | `GlobalKey(ownGlobal(spelling), false)` |
  | `ToBinder` of a `TyDef` binder | `GlobalKey(ownTyCon(spelling), true)` |
  | `ToBinder` of any other binder (Arg/Let/Where/Do/Case/TyParam/TyImplicit/KindParam) | `LocalKey(id)` |
  | `ToGlobal(g, _, origin)` | `GlobalKey(origin, typeLevel)` |
  | `Unresolved(spelling)` that a declaration head or the session answers | `GlobalKey(own(spelling), typeLevel)` |
  | declaration heads (`field`, `table`, constructor, foreign), type heads, fixity mentions, import-list items | the same own/canonical `GlobalKey` |
  | `Ambiguous` | none — it produces no `Occ` at all, as before |

* **`isDef`** is true when the occurrence sits exactly where the binder table says the name is
  introduced, and on the declaration-head entries.  It is the DocumentHighlight `Write`, the
  declaration `references` may include or drop, and the proof rename has a def-site it is
  allowed to touch.  ONE CAVEAT, stated: for a `sig` + several equations the renamer's def-site
  is the LAST equation, so an earlier equation head reads as a `Read`.  Every one of them is
  still in the references set and every one is still edited by a rename.

* **`spelling`** is the occurrence as written.  Rename compares them and refuses when they
  differ (§4, refusal v).

* **`version`** is stamped by `Documents.putIndex` from the buffer the check ran on (dispatch is
  single-threaded, so that IS the version).  It is what makes the stale-index refusal possible.

* **`renamed`** is the renamer's own tables — `frames` for the capture test, `moduleTerms` and
  `binders` for the top-level clash test, `occurrences` for the `Ambiguous` test.  It is a
  reference to a table the check already built.

* **`scopeTerms`/`scopeTypes`** are `ModuleScope.Scope`'s canonical import maps, held BY
  REFERENCE — no copy, no set is materialised, and a probe is one hash lookup.  Getting them
  there is the one change outside `lsp/`: `NewPipeline.Read` grew a `scope` field (defaulted,
  set at its single construction site) and `Resident.Checked` carries it through.  Nothing on
  the batch path reads it and `ModuleScope.importing` still runs exactly where it always ran.

### 1a. Def-site occurrences for every local binder

6.2 added def-site `Occ`s for pattern binders but kept only those a hover could answer
(`.filter(o => o.hover.isDefined)`).  That left highlight and rename unable to hit the very
position a reader clicks — where the name is introduced.  6.3 keeps them all, for every binder
kind except `TopLevel` (its head IS an occurrence) and `TyDef` (the type heads already have
theirs), type variables included.  An untyped one still hovers null — no `hover`, no `kind` —
so **no hover answer moved**; what it gains is a key.  The index grew from 7305 to 7980
occurrences on `Layout/Report.e` (+675, 9 %): those def-sites plus the import-list entries.

### 1b. The name's extent is not the span's extent (a bug this item had to fix)

`SurfaceParsers.spanned` brackets a `token`, and a token eats the whitespace after its lexeme.
So an occurrence's span runs to the START OF THE NEXT TOKEN: `mine` in `let mine = ...` spans
five characters, and a name at the end of a line spans onto the next one — where the old
`spanLen` gave up and answered 1.  Highlighting that is untidy; EDITING it would have deleted
the space after every renamed name, or replaced a single character at a line end.  New
`Definitions.nameLen(span, spelling)` measures a name by its own spelling wherever the spelling
is a plain word, and keeps the old measure for operator and parenthesised forms (whose spelling
is not what the source says: `(++)` is written with parens, spelled without) — which is exactly
the class rename refuses.  Every occurrence-derived `Occ` uses it; `selfTarget` (the go-to
definition target's own length) and the import module-name span are untouched.

`hit` is unchanged, and lsp-smoke's pre-6.3 checks — 237 of them, every one a position — all
still answer what they answered.

### 1c. Cost, on the check path

`Definitions.index` is now timed out loud in the log (`index: <file> <n> occurrences in <ms>`)
rather than argued about.  `Layout/Report.e`, 1757 lines, one cold check then two warm ones:

| run | occurrences | index build (cold / warm / warm) | check round trip |
|---|---|---|---|
| BEFORE (`2a9fde1` + the log line only) | 7305 | 21.7 / 8.5 / 5.0 ms | 2.0 / 1.3 / 1.2 s |
| AFTER round 1 | 7980 | 30.0 / 10.2 / 7.5 ms | 2.0 / 1.4 / 1.3 s |
| AFTER round 1, second run | 7980 | 37.7 / 15.2 / 7.3 ms | 2.0 / 1.4 / 1.2 s |
| **AFTER the FIX ROUND** (load 0.83) | 7980 | **46.8 / 16.2 / 12.4 ms** | 2.0 / 1.4 / 1.2 s |
| AFTER the fix round, two more (load ~2.5) | 7980 | 41.0 / 15.4 / 13.4 and 44.7 / 15.7 / 13.4 ms | 2.0 / 1.3 / 1.3 s |

**The index costs about +7 ms warm on the largest file in the corpus** (5–8.5 ms before 6.3,
12–16 ms after the fix round), and **the check round trip does not move at all** — 1.2–1.4 s
before and after, its own run-to-run spread, with the read half (0.81–0.96 s) dominating and
untouched by this item.  The fix round's share of that is the `Lines` build (one pass over
~60 KB) plus a `regionMatches` and a memoised origin lookup per occurrence; the tab-aware column
walk costs nothing on a file with no tabs, which is every file but one in the corpus.  The
~50 ms editor floor is more than three times the whole index build.  BEFORE is this tree with
the 6.3 changes absent and the timing line present, measured before any of them were made.

## 2. `textDocument/references` and `documentHighlight` — what "the set" is

Both hit-test with `Definitions.hit`, the one every other request uses, so "the name at this
position" has exactly one meaning in this server.

**Local key** (a `let`/`where` binding, an equation argument, a `case`/`do`/lambda binder, a
type variable).  The set is every `Occ` in THIS DOCUMENT whose key is that binder id.  The
def-site is one of them (§1a), so `context.includeDeclaration: false` is a filter on `isDef`
and nothing more.  No coverage warning — a local cannot leave its file.

**Global key** (this module's own top level, a `data`/`type`/`class` head, a constructor, a
`field`, a `table`, a foreign declaration, or any imported name).  The set is every `Occ` in
EVERY OPEN DOCUMENT whose key is that canonical origin: uses, the defining module's signature
and equation heads, its declaration head, its fixity line, and the `import M using (n)` entries
that name it.  Matching on ORIGIN and not on `g` is what makes an alias-imported mention and
its canonical name one name.  Plus the def-site: when some open buffer declares the name that
is the `isDef` occurrence in it; when none does — a stdlib name — it is the `Target` the
definition request answers, a real position in a file nobody has open, reported as a Location
all the same.  Results are ordered (uri, line, column).

**Highlight** is the same key, restricted to the requesting document, with kind 3 (`Write`) at
`isDef` and 2 (`Read`) elsewhere.  Per-document by definition, so no warning.

**Nothing runs.**  Every one of these is a filter over `DocIndex.occs`.  No parse, no rename
pass, no inference, no check is reachable from any of the four handlers — the Stage-3
invariant.  Dispatch stays single-threaded; nothing here touches it.

**BATCH SEMANTICS ARE UNTOUCHED, and I say so explicitly** because this item did edit a shared
file: `NewPipeline.Read` gained a `scope` field with a default, set at the one place `Read` is
built, read only by the editor path.  No traversal, no diagnostic, no refusal and no ordering
changed.  The evidence is the gates: corpus `--batch` 85/69/0 over 154 unchanged, repl-smoke's
goldens byte-identical (`git status tracker/repl-tests` clean), TestLoopTrace 720/720.

### 2a. The coverage warning (Decision c), verbatim

Sent ONCE per request, for a global key, on `references` and on `rename` (not on highlight, not
on a local):

```
window/showMessage  type 2 (Warning)
"Ermine: references searched in N open files; unopened importers are not searched"
"Ermine: rename searched in N open files; unopened importers are not searched"
```

N is `Documents.all.size`.  It is unconditional for globals, exactly as the brief requires: the
server cannot know whether an unopened module imports the name, so it never claims it does not.

## 3. `prepareRename`

Answers `{ range, placeholder }` for an `Occ` that has a key and whose spelling is a plain
identifier; `null` otherwise — off a name, on an operator, on an occurrence with no key.  The
range is the name's own extent (§1b), and the placeholder is the spelling the source uses.

## 4. `rename` — every refusal, and how it is detected

One `WorkspaceEdit` with `changes: { uri -> [TextEdit] }` over exactly the references set,
def-site included, only for OPEN documents.  Every check below runs BEFORE any edit is built, so
there is no path on which a refusal leaves a partial edit.  Codes: **InvalidParams (-32602)**
for what the request got wrong, **RequestFailed (-32803)** for what the workspace forbids.

| # | refusal | how it is detected | code |
|---|---|---|---|
| 0 | the session is still booting | `Resident.ready` | -32803 |
| 0b | no `newName`; no name at the position; the occurrence has no key | the request; `Definitions.hit`; `Occ.key` | -32602 |
| i | the new name is not a valid Ermine identifier | `classify` = None: not `letter` + `Lexer.isTailChar`\*, or a `parsing.keywords` word | -32602 |
| i | …or is of the OTHER case class | `classify(old) != classify(new)`, upper vs lower initial | -32602 |
| ii | the NEW spelling is an operator | `Lexer.op(s, 0)` lexes the whole string | -32602 |
| ii | the OLD spelling is an operator (or not a plain identifier at all) | the same `classify`, on `Occ.spelling` | -32602 |
| iii | CAPTURE: the new name is already bound where the old one is used | `renamed.scopeAt(line, col)` contains it, at EVERY occurrence in the set, per document | -32803 |
| iii | …or is already a top level of that module | `renamed.moduleTerms`, plus the `TyDef` binders for an upper-case rename | -32803 |
| iii | …or already resolves through that file's imports | `DocIndex.scopeTerms` / `scopeTypes` probed with `Local(newName, Idfix)` — the renamer's own canonical map | -32803 |
| iv | STALE INDEX | `doc.index.version != doc.version`, for EVERY document in the edit — "check pending; retry after diagnostics update" | -32803 |
| — | a mention of the name is `Ambiguous` | `renamed.occurrences` carries an `Ambiguous` with that spelling in a document being edited | -32803 |
| — | the def-site is in a file that is not open | no `isDef` occurrence anywhere among the open buffers | -32803 |
| v | the name is mentioned under more than one spelling | `hits.map(_.spelling).distinct.size > 1` — an alias import or a qualified use | -32803 |

\* the classification is the surface grammar's, not a regex: an operator is what `Lexer.op`
lexes whole (the lexer ported byte-for-byte from the fused parser, key operators, the `|]`
guard and the comment rule included), and an identifier is `letter` followed by
`Lexer.isTailChar`s — `ParsingUtil.identTail` — that is not in `parsing.keywords`.

Refusal **v** is mine, not the brief's, and it exists so that nothing else has to be: a
textual rename cannot follow `import M as N` or a qualified `M.foo`, and skipping such a
mention would be a partial edit.  It is the only place where 6.3 answers "no" to something that
is in principle renameable, and it is loud about it.

Note on how iii fires in practice: the renamer pushes a module-level `Frame` over the whole
file (`Renamer.scala:225`), so `scopeAt` already contains every top level — a clash with one is
caught by the frame test and reports "already bound where '<old>' is used".  The `moduleTerms`
test remains as the backstop for a file whose frames are shaped otherwise.

For a global rename the edit touches the def-site, every use in every open document, the
defining module's signature/fixity/declaration mentions, AND the `import M using (name)` entry
in each importing buffer — the last of these is new to the index in 6.3.1.  The coverage
warning is sent here too.

## 5. Capabilities (6.3.4)

`initialize` now advertises `referencesProvider: true`, `documentHighlightProvider: true` and
`renameProvider: { prepareProvider: true }`; `lsp-client.py` asserts all three, the last by
exact shape.

## 6. Gaps and declined cases, stated

Rewritten after the review (R4), which was right that the first version of this list omitted the
three findings and that "neither is a silent weakening" was too broad a claim.  The accurate
claim is narrower and is what the fix round now delivers: **every case below is either correct,
or a refusal the user can read.**  None of them is a silent partial or wrong edit — the three
that were (R1, R2, R3) are §§11–13.

WHAT RENAME DECLINES TO DO, each with a message:

1. **A `` ``literal`` `` name is not renamed** (§12), because re-wrapping is a grammar question
   this item cannot answer.  References and highlight ARE correct on it.
2. **A name behind a TAB is not renamed** (§12).  The server's `(line, column)` model is the
   parser's, whose columns are tab-expanded to eight-column stops, while LSP counts characters;
   the two disagree on a tabbed line.  That is a PRE-EXISTING bug of the whole position model
   (definition, hover and diagnostics have had it since 0.5) and fixing it is not this item; 6.3
   refuses rather than corrupts.  Six corpus occurrences, all in `core/examples/GridExample.e`.
3. **An operator is not renamed**, either way (Decision d).
4. **A parenthesised operator form `(++)` is not renamed** — the same `exact` flag as (1); it
   was already covered by (3).
5. **A name mentioned under two spellings is not renamed** — an alias import (`gadget_CA`) or a
   qualified use; a textual rename cannot follow them.  The reviewer confirmed this is doing
   real work: `Layout/Report.e`'s header alone has six `… as …` items.
6. **A name whose def-site is in a file that is not open is not renamed** (Decision d).
7. **A global rename is refused while ANY open buffer is stale** (§13) — the deliberate cost of
   closing R3.
8. **A global rename is refused when another open buffer holds that spelling under a different
   canonical global** (§11's belt).  This can refuse a legitimate rename — two open modules that
   genuinely define the same name — and it does so loudly, naming the other definition, rather
   than editing one and reading as the other.

WHAT IS INCOMPLETE, without a refusal:

9. **An OPERATOR import-list mention is not indexed.**  `SurfaceParsers.importItem` spells an
   operator item `(<+>)` — parens inside the spelling — and gives it `Idfix`, so the canonical
   `Global` (whose equality includes the fixity) is not recoverable there.  Rename refuses
   operators outright, so nothing rename does depends on it; a `references` request on an
   operator misses its import-list mentions.  Its fixity-declaration mentions ARE indexed.
   (Confirmed as stated by the review, R6.)
10. **The def-site of a multi-equation group is the LAST equation**, so highlight marks an
    earlier equation head `Read`.  Cosmetic; the references set and the rename edits are
    complete either way, which the reviewer verified.
11. **`Ambiguous` occurrences are not in the index** (they never were — `Definitions.index`
    answers `None` for them), so the ambiguity refusal reads `DocIndex.renamed.occurrences`
    directly rather than the `Occ` list.
12. **The workspace is the open buffers** (Decision c).  That is the design, not a gap, but it is
    what the coverage warning exists to say out loud — and note R1's lesson: before the fix that
    warning was actively misleading, because an importer that WAS open was being missed.  It is
    only about UNOPENED importers now, which is what it says.

## 11. FIX ROUND, review R1 — the re-export chain split the key

**The bug.**  `Renamer.ToGlobal.origin` is "the module I imported this name FROM", not the
module that DEFINES it: `ModuleScope.importing` computes `termOrigins0` *with* the session's
origins in it and then returns `localImportsToGlobals(canonicalTerms)` instead, dropping them.
`Prelude.e` does `export Bool`, so a use of `not` reached through `Prelude` arrived keyed on
`Prelude.not` while `Bool.e`'s own binder keyed on `ownGlobal("not")` = `Bool.not` — two keys,
two disjoint sets, one name.  The reviewer's reproduction: with `Bool.e` and a buffer doing
`import Prelude; flipped = not True` BOTH open and clean, `rename not → nope` from `Bool.e`
succeeded with three edits and left the importer broken; from the importer it was refused
"defined in a file that is not open", though it was open.  `Prelude.e` re-exports fourteen
modules, so this is the corpus's normal shape.

**The canonicalisation rule I implemented.**  At INDEX time — so the request path stays a
lookup, per the Stage-3 invariant — every `GlobalKey`'s origin is chased to a fixpoint through
the SESSION's own re-export maps, `env.termNameOrigins` for terms and `env.consOrigins` for
types (the maps `Session.scala:1076` fills from each load), by the same greatest-ancestor walk
`ModuleScope.collapseNames` uses:

> follow `origins(g)` while it answers a SINGLETON list naming something other than `g`; stop at
> an absent entry, at a self-entry, at a list with more than one ancestor (that is an ambiguity,
> not a chain), or after 32 hops.  Memoised per index build, so a repeated name costs one hash
> lookup.

It is applied to every global key without exception: `ToGlobal` origins, `ToBinder` TopLevel and
TyDef heads, `Unresolved` own-declaration mentions, declaration heads, type heads, fixity
mentions and import-list items.  The module's own definitions are unaffected because
`Resident.checkFile` scrubs the module being checked out of its env copy, so its own globals
have no origin entry and canonicalise to themselves — which is exactly what makes both ends meet
at `Bool.not`.

**The belt, as asked.**  Before building any GLOBAL rename edit, every open document's index is
scanned for an occurrence with the old spelling under a DIFFERENT global key; one is a refusal
(-32803) naming the file, the line and the other definition.  If two modules really do define
the name, a rename here would be read as a rename there; if the canonicalisation ever fails to
join a chain, this catches the residue instead of writing half an edit.  A LOCAL key is exempt
on purpose — a local shadowing a global of the same spelling is two names with two sets, and the
reviewer verified both rename correctly.

**Pinned both directions** in lsp-smoke with the reviewer's own stdlib case (`Bool.e` open plus
`tracker/lsp-tests/RefsPre.e` = `import Prelude` / `flipped = not True`): references from the
importer and from the defining module return the SAME four locations across both files; rename
from either end produces the SAME edit set touching both files; and the importer's rename is no
longer refused as "defined in a file that is not open".

## 12. FIX ROUND, review R2 — the backtick literal, and the tab

**The bug.**  `SurfaceParsers.literalIdentTok` yields the MIDDLE of a `` ``…`` `` pair as the
spelling, tagged `Plain` — indistinguishable from a plain identifier — while the span starts at
the first backtick.  Round 1 measured a letter-initial name by its spelling, so `` ``wide`` ``
got a four-character range two characters left of true and `rename ``wide`` → narrow` wrote
``narrowde`` `` — an unparseable file.  `Layout/Report.e` has fourteen such definitions.

**The fix: measure against the SOURCE.**  `Resident.Checked` now carries the `contents` the
check read (the same String the read already holds; `Checked` is transient, so nothing new is
retained — the reviewer's R5 analysis of what the editor keeps still holds), and
`Definitions.index` builds one `Lines` over it.  `Definitions.nameExtent(lines, span, spelling)`
returns **(length, exact)**:

* **exact** when the source at that position literally begins with the spelling — the ordinary
  case, measured by the spelling and NOT by the span, because a token swallows the whitespace
  *and the line comment* after it (`sa       -- ^ select the series identifier` is one span; the
  corpus has 121 of these);
* otherwise, not exact, and measured from the source: a `` ``literal`` `` runs through its
  closing pair (so an inner space or escape is inside the extent), anything else takes the run
  of non-space characters clipped to the span and the line.

**THE BACKTICK DECISION: references and highlight are CORRECT; rename REFUSES.**  The extent is
now the whole `` ``wide`` `` token, so highlight and find-references are right.  Rename refuses
(-32803, "the source writes it in a form that is not its spelling") rather than re-wrapping,
because whether the NEW name needs backticks is a grammar question this item cannot answer from
`classify` alone — `` ``1pixel`` `` is digit-initial and legal only inside them, `` ``a b`` ``
holds a space — and the literal form carries its own backslash escapes, which a plain
replacement would have to re-apply.  `prepareRename` answers null on such a name, so the refusal
arrives before the user types anything.  The same flag refuses a parenthesised operator form,
which rename declined anyway.

**A SECOND, PRE-EXISTING BUG the new property found: tab-expanded columns.**  A parser column is
not a character index — `scalaparsers.Pos.bump` advances a tab to the next multiple of eight
(`column + (8 - column % 8)`) — and `core/examples/GridExample.e` indents four lines with a tab.
`Lines.locate` now walks such a line by the parser's own rule (untabbed lines, which is
everything else, keep O(1) arithmetic through a per-line tab flag), so the extent is measured at
the right place; and because an LSP range built from a parser column on a tabbed line is in the
wrong units for the editor that receives it — the server's position model has been tab-blind
since 0.5, and fixing THAT is not this item — a name behind a tab is never `exact` and never
renamed.  Six corpus occurrences are in that class; §6 states it.

**The property now calls the index's own function.**  `TestRenamer`'s overlap property used to
re-implement `nameLen`'s rule inline and was therefore blind to exactly this; it calls
`Definitions.nameExtent` now.  A new sixth property classifies EVERY corpus occurrence by form
and requires the residue to be empty:

```
occurrences 71248 | exact 70897 | backticked 39 | parenthesised 306 | behind a tab 6 | other 0
```

— so a new form that this measurement does not understand shows up here rather than in a
corrupted rename.

## 13. FIX ROUND, review R3 — the stale-index hole

**The bug.**  The version check ran over `touched` — the documents that already had a HIT.  A
sibling edited since its last check whose STALE index carries no mention was in neither set:
not refused, not edited.  Reproduced by the reviewer inside the 300 ms debounce; the just-typed
mention was left dangling.

**The fix.**  For a GLOBAL key every open document is version-checked before the edit is built,
not only the ones with hits — a stale sibling may have just gained a mention its index cannot
know about.  A LOCAL key checks only its own document, because a local cannot leave its file, so
no other buffer can hold a mention of it.  A document with NO index at all has never been
checked and has produced no mention; it is in the same class as an unopened importer, which the
coverage warning already speaks for, and it does not block a rename.  Stated cost, deliberately
taken: while any open buffer is mid-debounce, every global rename answers "check pending; retry
after diagnostics update" and names the buffer.  That is the Decision (d) trade — a message
instead of a partial edit.

**Pinned** in lsp-smoke, with the local half pinned too: `onlyHere` (a new top level in `Refs.e`
that `RefsSib.e` never mentions) renames with one edit while everything is current; after a
`didChange` to `RefsSib.e` that adds an unrelated line, the same rename is refused and the
message names `RefsSib.e`; a LOCAL rename in the same instant still succeeds; and once the
pending check has run the global rename succeeds again.

## 7. Table integrity — the corpus properties (6.3.5)

Six new properties in `TestRenamer` (18 → **24**; five in round 1, the sixth added by the fix
round), over stdlib + `core/examples` — the standing 180-file rule, which today finds
**253 files**.  They need NO session: an empty import scope
leaves more names `Unresolved` but changes no binder, no def-site and no span, which is all
these properties look at, so the whole sweep runs in seconds.  `Prop.collect` prints the counts
on a PASS, so the numbers are reported and not merely asserted:

```
files 253 renamed 252 | occurrences 71248 (ToBinder 31438) | binders 16506
| moduleTerms 3441 | unparsed Sample.e
```

| property | result |
|---|---|
| the tables are there at all (anti-vacuity) | 252 of 253 files renamed; `core/examples/Sample.e` is the one the surface parser refuses outright, named rather than quietly dropped |
| every `ToBinder` occurrence's binder exists, and its def-site is inside this file (line in `1..lines`, column ≥ 1) | **0 bad of 31438** |
| no two occurrences overlap | **0 overlapping pairs of 71248** — by the NAME's extent (§1b), which is what the LSP edits; raw token spans abut the next token by construction |
| one binder per def-site position | **0 shared positions of 16506 binders** — the index keys a def-site `Occ` by (line, column) and `dedup` keeps one per position, so a shared def-site would silently lose a binder and a rename would then miss every use of it |
| every `moduleTerms` id is a `TopLevel` binder with the same spelling | **0 bad of 3441** |
| **(fix round)** every occurrence's measured extent is the SOURCE's own — and every non-exact one is a form we can name | 71248 occurrences: **70897 exact, 39 backticked, 306 parenthesised, 6 behind a tab, 0 unclassified** |

These are what references and rename stand on: an id with no binder, a def-site outside the
file, two binders at one position or two occurrences over one stretch of text would each make a
rename write nonsense.  The overlap property and the new extent property both call
`Definitions.nameExtent` — the function the index itself uses — rather than re-stating its rule
(review R2: the first version re-implemented it inline and was blind to the very case that was
wrong).

## 8. lsp-smoke

**237 → 306 checks (+69)**: 50 in round 1 and **19 more in the fix round**.  Fixtures
`tracker/lsp-tests/Refs.e` and `tracker/lsp-tests/RefsSib.e` (which does
`import Refs using shared`, so the explicit import list is exercised), plus the fix round's
`tracker/lsp-tests/Lit.e` (a `` ``literal`` `` name) and `tracker/lsp-tests/RefsPre.e`
(`import Prelude`, which re-exports `Bool`) opened alongside the real
`core/src/main/resources/modules/Bool.e`.  What is pinned:

* references on the local `mine` — def-site + 3 uses, **exact ranges**, from the def-site and
  from a use alike; without the declaration, 3; and **no** coverage warning for a local;
* highlight on the local: one `Write` at the def-site, three `Read`s, exact ranges;
* prepareRename on the local: its exact range and the placeholder `mine`;
* references on the top-level `shared` from the importing sibling — six locations across BOTH
  files (3 + 3), exact ranges, the import-list entry among them — and the same set from the
  defining file; without the declaration, five;
* the coverage warning arrives, ONCE, `type: 2`, with the wording asserted at both ends;
* highlight on the top level stays inside its own file (3 hits, `Write` at the equation head)
  and sends no warning;
* rename the local: one file, four edits at exactly the four sites and nowhere else, every
  `newText` the new name, no warning — then the client APPLIES the edits, `didChange`s the
  result, the file **re-checks clean**, and the renamed local **hovers with the same type**
  (`mine : Bool` → `flagged : Bool`);
* every refusal, by code and by message: a capturing name (-32803), a name that is already a top
  level (-32803), a wrong-case name (-32602), renaming TO an operator (-32602), renaming FROM an
  operator (-32602), a stdlib name whose file is not open (-32803);
* prepareRename on an operator → null, and off a name → null;
* rename the top level across two open buffers: both files edited, 3 + 3 edits at exact
  positions, the `import Refs using shared` mention among them, plus the coverage warning;
* the stale-index refusal: `didChange`, then rename BEFORE the debounce fires → -32803 "check
  pending", then the pending check runs and the very same rename succeeds with its four edits.

Three checks were also added to the `initialize` block for the new capabilities.

THE FIX ROUND's nineteen (§§11–13):

* R2 — `Lit.e` clean; references on `` ``wide`` `` cover the WHOLE eight-character token in both
  places; highlight the same, Write then Read; `prepareRename` → null; rename → refused -32803
  with "not its spelling";
* R1 — `Bool.e` and `RefsPre.e` both clean; references on `not` from the IMPORTER and from the
  DEFINING module return the same four locations across both files; rename from the defining
  module edits BOTH files; rename from the importer is not refused as "defined in a file that is
  not open"; both directions produce the identical edit set; and `Bool.e` on disk is untouched;
* R3 — `onlyHere` renames with one edit while every buffer is current; after a `didChange` to
  `RefsSib.e` (which never mentions it) the same rename is refused "check pending" and the
  message names `RefsSib.e`; a LOCAL rename in the same instant still succeeds; and the global
  rename succeeds again once the pending check has run.

## 9. Gates

ROUND 1 (all re-run and reproduced by the reviewer):

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | green (one pre-existing deprecation warning in `NewPipeline.scala:361`, untouched) |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, fuel 0; 3 properties passed |
| `tracker/tools/corpus-run.sh --batch <scratch>/corpus` | 154 outputs, **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** |

THE FIX ROUND (the tier the coordinator named; the fix round changed only `lsp/` sources and
`TestRenamer`, so nothing on the batch path moved — `TestReplDifferential` and repl-smoke's
goldens are the tripwires and both are green):

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | green |
| `sbt 'core/testOnly *TestRenamer* *TestTolerantCheck *TestEditorBuffers* *TestTolerantRead *TestReplDifferential'` | **68 / 68 passed, 0 failed, 0 errors** — TestRenamer **24** (18 before 6.3), TestTolerantCheck **26**, TestEditorBuffers **6**, TestTolerantRead **11**, TestReplDifferential **1** |
| TestRenamer collected data | `files 253 renamed 252 \| occurrences 71248 (ToBinder 31438) \| binders 16506 \| moduleTerms 3441 \| unparsed Sample.e` and `occurrences 71248 \| exact 70897 \| backticked 39 \| parenthesised 306 \| behind a tab 6 \| other 0` |
| `tracker/tools/repl-smoke.sh` | **8 groups / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); goldens unmodified (`git status tracker/repl-tests` clean) |
| `tracker/tools/lsp-smoke.sh` | **306 checks** (6.2's baseline 237; +50 in round 1, +19 in the fix round) |
| boot | `Loaded 129 modules (11.44 seconds)` |
| Report.e check time (the index is on the check path) | round trip 2.0 / 1.4 / 1.2 s at load 0.83 — unchanged from BEFORE's 2.0 / 1.3 / 1.2 s; the index itself 5.0–8.5 ms warm before 6.3, 12.4–16.2 ms after the fix round (§1c) |
| `.ei` | the `bin/ermine` boot wrote 129 into `core/target/.../modules`; **deleted**, 0 outside `tracker/g1-*`, re-verified after every JVM |
| line endings | `git diff --stat` and `git diff --stat -w` are IDENTICAL — no file was reformatted (every file this item touches was already LF) |

Not run, and why: **Tier 1** (no solver, no `Type.scala` constraint construction, no executable
Lean — `NewPipeline`'s added field is a carried value, not a phase); **Tier 2** (`core/test` in
full — this is not an adoption commit and no default flips).  No perf A/B: this item adds no
inference and no check, and its one check-path addition is the index build, measured above
against its own before.  `TestLoopTrace` and the corpus `--batch` verdicts were not re-run in the
fix round because the fix round touched no source outside `lsp/` and `TestRenamer`; both were
green in round 1 and both were re-run once by the reviewer.

## 10. Files changed

* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/References.scala` — **new**: references,
  documentHighlight, prepareRename, rename, the name classifier, the coverage warning; fix
  round: the `exact` refusal (R2), the different-key belt (R1), the every-open-document version
  check (R3).
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Definitions.scala` — `Key`, `Occ.key` /
  `spelling` / `isDef`, `DocIndex`'s five new fields, def-site `Occ`s for every local binder,
  import-list `Occ`s, `hit` and `location` made public; fix round: `Occ.exact`, `Lines`
  (tab-aware, with an O(1) fast path), `nameExtent` replacing `nameLen`, and the origin
  canonicalisation `gkey` applies to every global key.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Documents.scala` — `all`, and
  `putIndex` stamping the buffer version onto the index.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Diagnostics.scala` — the `index:` timing
  log line (the item's own budget line).
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Main.scala` — the three capabilities and
  `References.install`.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Rpc.scala` — `InvalidParams`,
  `RequestFailed`.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Resident.scala` — `Checked.scope`, and
  (fix round) `Checked.contents`, the text the check read.
* `core/src/main/scala/com/clarifi/reporting/ermine/rename/NewPipeline.scala` — `Read.scope`
  (defaulted, additive; the ONLY non-`lsp/` source touched, and §2 says why it is batch-inert).
* `scalacheck-binding/src/main/scala/TestRenamer.scala` — six corpus table-integrity properties
  and the corpus walker; the overlap property and the new extent property both call
  `Definitions.nameExtent`.
* `tracker/tools/lsp-client.py` — the 6.3 block (+50) and the fix-round block (+19), plus the
  capability assertions.
* `tracker/lsp-tests/Refs.e` (which gained `onlyHere` for R3), `tracker/lsp-tests/RefsSib.e`,
  and the fix round's `tracker/lsp-tests/Lit.e` and `tracker/lsp-tests/RefsPre.e` — new fixtures.
* `docs/lsp.md` — the references/highlight/rename section, and the harness count 237 → 306.
* `tracker/loopmodel/LSP3-6.3-REFS.md` — this report.

No `Subst.scala`, `Type.scala`, `Lower.scala`, `Renamer.scala` or `TolerantCheck.scala` change.
No `tracker/LSP-ROADMAP.md` or `tracker/lean/` change.  No commits.  The three untracked briefs
`brief-LSP3-6.4/6.5/6.6.md` were already in the tree when I started and are not mine.

STOP after this report, per the brief; a reviewer re-runs the gates once.
