# LSP Stage 4, item 7.5 — ticket triage: E8, E9, E10(5) closed; E7 split, half shipped and half deferred with the reason; E5, E6, E10(1)-(4) written back

Implementer report.  Brief `tracker/loopmodel/briefs/brief-LSP4-7.5.md`; item of record
`tracker/LSP-ROADMAP.md` § "Stage 4" item 7.5, whose DISPOSITIONS are the plan.  Branch
`scala3-migration`, from HEAD `775f1b4`.  No commits.  `tracker/lean/` and
`tracker/LSP-ROADMAP.md` untouched.  One JVM at a time throughout; no background JVMs left
behind.  Scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.5/`.

**OUTCOME: GREEN.**  E8, E9 and E10(5) are closed with pins and numbers; E7 is decided —
its TYPE half is shipped with a fixture and a control, its OPERATOR half is deferred with
three reasons written into the ticket.  Every gate is green.  lsp-smoke **510 -> 542**.

One arithmetic correction the brief asks about by name, stated up front rather than buried:
the brief's E10(5) target "OutOfScope 117 -> ≤ 84" is not reachable by E10(5) alone, and the
number it was derived from conflated NAME OCCURRENCES with REFUSALS.  What the fix can close
it closed completely: the own-synonym sub-class went **33 -> 0 name occurrences**, which
recovers **17 groups** and takes out-of-scope refusals **117 -> 100**.  §4 has the derivation.

---

## 1. E8 — the boundary conversion, parser column <-> LSP character.  FIXED

### 1a. What the two units are, and what the divergence actually is

`scalaparsers.Pos.bump` advances a TAB to the next tab stop — `column + (8 - column % 8)`,
so column 1 becomes column **8**, not 9 — and every other character by one.  An LSP position
counts UTF-16 code units from the start of the line.  Until this item the server converted
between them by `± 1` in BOTH directions and in EVERY feature, which is the 6.3 review's
finding S5 verbatim.

**THE UTF-16 RULE IS NOT A SECOND BUG IN THIS SERVER, and the brief asks for the answer
explicitly.**  `ParsingUtil.rawSatisfy` reads `si.charAt(so)` and hands that `Char` to
`Pos.bump`; `skipSatisfy` advances by `bumps`, which counts `String.length`.  Both are UTF-16
CODE UNITS.  So a non-BMP character is **two parser columns and two LSP characters** and the
two models already agree about it — there is nothing to convert.  (Ermine source can contain
one: string and character literals and comments take arbitrary text, and the lexer's
`isLetter` admits non-ASCII letters; the corpus has none.)  A `\r` is an ordinary character to
`bump` and sits past the last real character of a CRLF line, where nothing is measured.  **The
tab is the whole divergence, and converting it is converting everything.**

### 1b. The change — ONE helper, and every site routed through it

`Definitions.Lines` is the line model 6.3 wrote.  It is now KEPT on the `DocIndex` (field
`lines: Option[Lines]`) instead of discarded at the end of `Definitions.index`, and it gained
the bidirectional pair:

| | |
|---|---|
| `Lines.character(line, parserCol)` | parser column (1-based, tab-expanded) -> LSP character (0-based) |
| `Lines.column(line, chr)` | LSP character -> parser column |
| `Definitions.toCharacter(ls, line, col)` / `toColumn(ls, line, chr)` | the same, over `Option[Lines]`, falling back to the old `± 1` when no line model is to hand |
| `Definitions.LineSource(docs)` | the `Lines` of a file the server must convert a position IN but does not have open — index first, then the buffer, then the disk copy memoized on (path, mtime, size), cap 256 |
| `Lines.tabbedLine(line)` / `lineText(line)` | for the corpus properties |

An untabbed line is `col - 1` / `chr + 1` and stays O(1) — 252 of the 253 corpus files.  A
tabbed line walks, by the parser's own rule.  A column that lands INSIDE a tab's expansion
(nothing a token start can do; defensive) answers with the tab's own character; a column past
the end of the line keeps counting by ones, which is what an exclusive end column is.

**EVERY SITE, enumerated — the 6.3 review's list plus the two it did not name:**

| site | feature | before | after |
|---|---|---|---|
| `Diagnostics.fromDiag` | structured READ diagnostics | `sp.startCol - 1`, `sp.endCol - 1` | `toCharacter` on both ends, each against its own line |
| `Diagnostics.fromSpan` | span-bearing notes (the FFI ones) | same | same |
| `Diagnostics.fromReport` | caret notes, position recovered from the report's `file:line:col:` prefix | `c.toInt - 1` | `toCharacter` |
| `Diagnostics.check` | supplies the `Lines` | — | `idx.lines`, the one the index just built: **no second scan** |
| `Diagnostics`' `Death` catch | a header that will not parse | `column - 1`, no index exists | a `Lines` built from the buffer — the one place that pays a scan, at most once per failed check |
| `Definitions.location` | definition target, references' def-site, workspace/symbol | `p.column - 1` | `toCharacter` against the TARGET file's lines, via `LineSource` |
| `Definitions.occurrenceAt` | definition + hover hit-test | `chr + 1` | `toColumn(idx.lines, …)` |
| `References.siteAt` | references / highlight / prepareRename / rename hit-test | `chr + 1` | `toColumn(idx.lines, …)` |
| `References.rangeOf` | references, highlight, prepareRename, rename edits | `o.startCol - 1` | `toCharacter` against the document the occurrence is IN (it now takes the `Doc`: `occurrencesOf` spans the open buffers, so the home document's line model is the wrong one for a sibling's hit) |
| `Symbols.rangeJson` / `selJson` | documentSymbol + workspace/symbol | `r.sc - 1`, `s.col - 1` | `toCharacter`, `ls` threaded from the index |
| `Completion`'s scope lookup | `items(idx, line+1, wordStart+1)` | `+ 1` | `toColumn(idx.lines, …)` |
| `QuickFix` | edits | already character units by construction | unchanged — its scanner works on the buffer text, never on parser columns |

`grep -n "col - 1\|column - 1\|chr + 1\|startCol - 1\|endCol - 1\|\.sc - 1\|\.ec - 1"` over
`lsp/*.scala` now hits **only `Definitions.scala`**, inside `locate`, `character`, `column`
and the documented no-`Lines` fallback — plus one comment line in `Diagnostics.scala`.
`QuickFix.scala:308`'s `col + 1` is a CHARACTER index in the import scanner, which was never
in the wrong units.

**NOT the `Pos` fix.**  `scalaparsers.Locations.scala` is untouched; batch reports and REPL
goldens keep every column they had.

### 1c. The two mitigations E8 existed to make unnecessary, both removed

* **6.3's "never rename a name behind a tab"** (`Definitions.nameExtent` returned
  `exact = !sawTab`).  REMOVED: `exact` goes back to meaning what it says — the source at
  this position literally spells the name.  The refusal existed for one reason only, that an
  LSP range built from a parser column on a tabbed line was in the wrong units, and that is
  now converted.  The backtick-literal and parenthesised-operator refusals are UNCHANGED:
  those are about the source's written FORM, which no conversion touches.
* **`QuickFix.BehindTab`**, the add-signature refusal for a tab-indented equation.  REMOVED
  as redundant: the column comparison beside it (`expanded != g.eqCol`) is already in the
  parser's units, and the edit is a whole-line insertion at character 0 carrying the line's
  own leading whitespace, so it never had a units problem.  0 corpus groups were in the class,
  so the sweep table is unaffected.

### 1d. The extent histogram, re-run (the brief's number)

`TestRenamer` "6.3 corpus: a name's measured extent is the source's own", 253 files:

| | before (6.3) | after (7.5) |
|---|---|---|
| occurrences | 71248 | 71248 |
| **exact** | **70897** | **70903** |
| backticked | 39 | 39 |
| parenthesised | 306 | 306 |
| behind a tab | **6, and NOT exact** | **6, and EXACT** |
| unclassified (`other`) | 0 | 0 |

The class is still counted and still reported — it is the class the fix is about — but it is
counted among the exact ones, and the property now ALSO asserts that every tabbed occurrence
is exact and that there is at least one (anti-vacuity: without a tab-bearing file the whole
conversion would be trivially `col - 1`).

### 1e. The round-trip property (the brief's "corpus property")

Two new `TestRenamer` properties, 32 -> **34** in that suite:

```
7.5 corpus: parser column <-> LSP character round-trips
  occurrences 71248 | round-tripped 71248 | behind a tab 6

7.5 corpus: an LSP character round-trips through a parser column
  tabbed lines 3 | characters 132
```

The first is parser -> LSP -> parser over every occurrence's start column.  The second is the
other direction over the whole DOMAIN where the units disagree: every character index of every
tabbed line in the corpus (3 lines, 132 characters, all in `core/examples/GridExample.e`).
Both carry anti-vacuity clauses on the tabbed counts.

### 1f. PINS in lsp-smoke

**`tracker/lsp-tests/Tab.e`** (new; LF, real tabs).  `\tgo = True` inside a `where`, plus an
undefined name and an unknown operator behind a tab.  Pinned:

| | |
|---|---|
| a structured READ diagnostic on a tabbed line | `unknown operator <+>` at **character 6** (it was **13**), i.e. on the operator rather than six characters past it |
| a caret note on a tabbed line | `undefined term`, report prefix `Tab.e:20:8`, published at **character 1** (it was **8**) |
| definition from the use site | `tabbed = go where` at (10, 9) -> the binder at (11, 1)-(11, 4) |
| definition AND hover at the real character column | (11, 1) -> the binder; hover `go : Bool` |
| **the control, the 6.3 review's own observation inverted** | at (11, **8**) — the parser column, the position that USED to answer `go` — definition is null, and hover says `Builtin.True : Bool`, because character 8 of `\tgo = True` is inside `True` |
| the tab itself | not a name |
| `prepareRename` behind a tab | offers the name with range (11, 1)-(11, 3).  **6.3 answered null and `rename` answered -32803** |
| `rename` behind a tab | two edits: (10, 9)-(10, 11) and (11, 1)-(11, 3) |
| an untabbed symbol | selection still (10, 0) — the conversion moves nothing it should not |

**`core/examples/GridExample.e`**, opened as itself (the corpus instance: three tab-indented
lines, six `atomShown` occurrences, the 6 of 71,248).  Pinned: the file checks **clean**;
definition at (64, **2**) lands in `Layout/Report.e`; hover there is
`Layout.Report.atomShown : forall a (f: * -> *) z. Primitive a => a -> Report f z`; the `[`
at (64, 1) is not a name; and a references request from a tabbed occurrence finds **all six**
at their character columns — `(64,2) (64,26) (65,2) (65,27) (66,2) (66,32)`, each of which was
seven to the right before.

### 1g. Cost on the check path — MEASURED, as the brief asks

The brief's warning is right that this helper now sits on a much shorter check path (7.1b took
the read on `Layout/Report.e` to ~0.05 s).  What the item actually adds to a check is: the
`Lines` the index ALREADY BUILT is retained rather than dropped (two arrays — one `Int` and one
`Boolean` per line, ~9 KB on a 1757-line file — plus a reference to the buffer string
`Documents` already holds; **no text copy, no second scan**), and one O(1) arithmetic
conversion per published range.  `Layout/Report.e` publishes zero diagnostics, so the expected
delta is zero.  Measured, interleaved pair, `perf-bench.sh editor -k 15`, `Layout/Report.e`,
debounce pinned at 300 ms:

| | median | read | typecheck | debounce | residual | spread | reused | load before/after |
|---|---|---|---|---|---|---|---|---|
| BEFORE (tree stashed, recompiled) | 0.927 s | 0.055 s | 0.535 s | 0.300 s | 0.027 s | 0.884-1.052 | 97/154 | 1.13 / 2.28 |
| AFTER (this tree) | **0.908 s** | **0.055 s** | 0.525 s | 0.300 s | 0.027 s | 0.868-0.986 | 97/154 | 0.88 / 1.34 |

**Δ −19 ms, and the sign is favourable, which is exactly how a no-op reads on this harness.**
The READ is **0.055 s on both sides, identical**, and the residual is 0.027 s on both sides.
−19 ms is well inside the ~50 ms editor noise floor the roadmap records, and the BEFORE side
ran at the higher load of the two (1.13 -> 2.28 against 0.88 -> 1.34), so the difference is
the machine and not a win.  **The round trip did not move beyond the floor.**

---

## 2. E9 — stdlib locations point at the SOURCE tree.  FIXED

### 2a. The change

The resident session loads its 129 modules through `SourceFile.classloader("modules")`, which
resolves to `<classpath entry>/modules/<M>.e` — the byte-for-byte copy `copyResources` puts
under `core/target/<scala>/classes`.  So every stdlib `V.loc`/`Con.loc` names that copy and
the server reported it faithfully.  The rewrite is at the LSP boundary, in
**`Definitions.location` and nowhere else** — which is the one place all four answers are
built: `textDocument/definition`, the def-site `textDocument/references` adds when no open
buffer has it, `Symbols.sessionGlobals` (and therefore `workspace/symbol`), and the import
statement's own target.  `Definitions.SourceTree` does the work.

**Decision 5 is untouched**: the session still boots from the classpath, and no `Loc` is
rewritten anywhere inside the compiler.

**THE MAPPING IS DERIVED, as the brief requires — no Scala version appears anywhere.**  Ask
the class loader where `modules` actually is (that IS the copy the session read, whatever the
output layout); walk UP to the directory that owns the `target` tree; look for
`src/main/resources/modules` beside it.  That is one sbt convention
(`target/<x>/classes` is built from `src/main/resources`), and it is CHECKED before it is
used: `Files.isDirectory` on the source directory, and `Files.isRegularFile` on the particular
file.  The derived pair is logged once at install:
`positions: … stdlib source tree /…/core/target/scala-3.3.8/classes/modules -> /…/core/src/main/resources/modules`.

**The jar fallback.**  If the source directory is absent, or the specific module is not in it,
`rewrite` returns the argument UNCHANGED and navigation is exactly what it was.  It is
reasoned, not pinned: this build unpacks every module under `classes/modules`, so no jar-only
module is constructible here to test against, and a module that lives only in a jar reaches
`location` as a `Resource` whose `fileName` is not a file at all — `location` already answers
`None` for it, before the rewrite.  Stated rather than claimed.

**Reading the target file's line text.**  `location` must convert a column against the line it
names, in a file no buffer has open, so `LineSource` reads it.  That is bounded and it is the
boundary conversion reading the line it converts against, not analysis: `location` already
`stat`s the same file to decide whether the target exists, the read is memoized on (path,
mtime, size), and `workspace/symbol`'s ~2000 `Location`s are built ONCE
(`Symbols.sessionGlobals`) and share the memo — so the whole stdlib costs 129 reads, once.
`Symbols.install`, `Definitions.install` and `References.install` each hold one `LineSource`.

### 2b. PINS — tree-distinguishing, which is the point

The brief is right that the existing pins could not see the bug: every one was
`uri.endswith("/Bool.e")`-shaped and the build-output copy ends in `/Bool.e` too.  New pins,
all asserting the path is under `core/src/main/resources/modules`:

| assertion | pin |
|---|---|
| a stdlib DEFINITION target is in the source tree | `definition("Nav.e", 7, 12)` (`&&`) — uri starts with the `core/src/main/resources/modules` URI **and** contains no `/target/` |
| the def-site a REFERENCES request adds is in the source tree | the one hit outside the open buffers, `.../resources/modules/Bool.e` |
| a WORKSPACE SYMBOL's location is in the source tree | `workspace/symbol "not"`, the `Bool`/`not` row |
| **no** workspace-symbol location anywhere is in the build output | every row of that answer, `"/target/" not in uri` |
| the rewritten file really exists | `Path(...).is_file()` on the uri the server sent |
| hover target | hover publishes no `Location` at all, so there is nothing to assert; `definition` at the same position is the pin that covers it |

And the eight pre-existing stdlib pins were TIGHTENED from `/<name>.e` to
`/resources/modules/<name>.e`: `Bool.e`, `Either.e` (x3: constructor, type, import),
`Date.e`, `Relation.e`, `Relation/Sort.e`, `Layout/Report/SoftRelation.e`.

`docs/lsp.md`'s E9 caveat is replaced by the new behaviour (and says the mapping is derived
and what the fallback is).

---

## 3. E7 — DECIDED: the TYPE half shipped, the OPERATOR half deferred with the reason

### 3a. SHIPPED — "undefined type" is withheld while an import failed

6.1(b) withholds undefined-TERM notes (keyed on `Note.spelling`) and "unchecked" notes
(`dependsOnBroken`) while any import failed.  The type note could not be reached because it
carries no name — and it cannot: `Subst.assertTypeClosed` dies **once** with every free type
variable joined into one report, so there is no single spelling to put in `spelling`.

A FLAG is what there is.  `TolerantCheck.Note` gained `undefinedType: Boolean = false`, set
where the note is BUILT — the `catch` that replaced `guard(Error) { assertTypeClosed(bs) }` —
and never by matching rendered text (6.1's rule).  `Resident.checkFile`'s predicate is now
`n.spelling.isDefined || n.dependsOnBroken || n.undefinedType`.

**This needed no discriminator and opened no policy question**: it is 6.1(b)'s own wholesale
rule, unchanged, extended to a note that could not carry the flag it keys on.  The same
accepted cost applies verbatim and is already written down: a genuinely mistyped type name
goes quiet until the import is fixed.  **`Subst.scala` is untouched** — splitting that death
per name would be Tier 1 under the Stage-4 invariants, and the item would have had to stop.

PINS (two new fixtures, both LF):

| fixture | assertion |
|---|---|
| `tracker/lsp-tests/BadTy.e` — `import NoSuchTypeModule` + `paint : Shape -> Int` | exactly **ONE** diagnostic, `import NoSuchTypeModule failed: Module not found`, and **no** "undefined type" |
| `tracker/lsp-tests/UndefTy.e` — the same signature, every import healthy | **THE CONTROL**: "undefined type" is still reported, at the name, (7, 8).  Without this the change could be a filter that deletes the note outright |

### 3b. DEFERRED — the operator cascade, and three reasons it is not a Tier-0 change

Spent under a quarter of the item on this, as instructed, and the answer to the brief's
question ("is there a flag-based tag that distinguishes the two cases honestly?") is **no, not
for the operator half, and the half the brief hoped for does not exist either**.

1. **THE CARRIER IS NOT A NOTE.**  The three are `NewPipeline.Diag(phase, span, message)` —
   read-phase diagnostics with no structured payload at all, published from `checked.diags`,
   which the suppression filter never sees.  Tagging them means threading a new structured
   field out of `Reassoc`'s unknown-operator path and `Lower`'s error-node path, whose
   construction sites are shared with the STRICT read.  That is not the Tier-0 editor-path
   change the ticket assumed.
2. **THE DISCRIMINATOR THE BRIEF PROPOSES DOES NOT EXIST.**  "The operator's spelling appears
   in a failed module's known exports" needs that module's export list.  A module that FAILED
   to load contributes no names to the check's env copy — that is what failing means — and
   the resident session holds only its own 129 stdlib modules, so for the realistic case (a
   workspace sibling that will not load) nothing in the process knows what it would have
   exported.  The brief's "the resident session knows the module's origin names when the
   module EXISTS but failed to load" holds only when the module is ALSO already resident, i.e.
   a stdlib module, which is the case that essentially never fails.  And the one cheap way to
   name a module's top levels without loading it — `StatementExtents.scan(...).headWord` —
   **cannot name OPERATORS**, which is the documented limitation `TolerantCheck.keys` states
   in its own comment ("a spelling missing from `groups` — an operator, anything the extent
   scanner cannot name — is simply never cached").  Operators are exactly the half at issue.
3. **6.1's WHOLESALE RULE CANNOT BE COPIED ACROSS.**  6.1 keeps syntax diagnostics on purpose,
   and `ill-formed expression` / `error node` are `Lower`'s answer to ANY error node, not only
   an operator one.  Withholding them while an import failed would hide real structural
   breakage, not a cascade.

The route for a future item is written into the ticket: start at (1) — give the read's
diagnostics a structured kind, which is worth doing for other reasons — and (3) then becomes a
one-line predicate.

---

## 4. E10(5) — the quick fix sees through the file's own type synonyms.  FIXED

### 4a. The change, and why it is narrow

`QuickFix.inScope` tested the printer's spelling against `ModuleScope.canonicalTypes`, which
holds what the file's IMPORTS put in scope and nothing else.  `Layout/Scan.e` declares
`type Scan = Scan_S` over `import Relation.Scan as S`, so the only spelling in scope is
`Scan_S` while the printer writes `Scan` — and 29 of that file's groups were refused a
signature the file can perfectly well write.

`TolerantCheck.checkWith` now publishes `ownTypes: Map[String, Global]`, built right after the
type-def phase from `m.types` under the phase's own `maps` (an imported constructor is a `Con`
in that map, which is how `Scan_S` resolves to `Relation.Scan.Scan`).  It rides out on
`TolerantCheck.Result` -> `Resident.Checked` -> `Definitions.DocIndex`, and `inScope` resolves
the printed spelling through it before refusing — the **same identity test** (`chase` over the
origins) the import case makes, never a spelling one.

**Only `type X = C` with no kind or type parameters and a bare-`Con` body is published, and
that narrowness IS the soundness argument.**  `type X = C` says `X` and `C` are the same type
constructor, so a signature spelling `C` as `X` checks.  `type X = C Int` does NOT license
writing `C` as `X`; a parameterised synonym is not a type by itself at all.  Both fall out
here rather than being accepted and then failing to check — which is why PARSE-FAIL and
TYPE-FAIL did not move (§4b).  No `Supply` is drawn and no alias is expanded by
`expandAlias` (which would recurse through a mutually recursive synonym without a bound); the
substitution the type-def phase already made is enough.

### 4b. THE SWEEP TABLE, before and after

`sbt -batch -J-Xmx3g -Dermine.sweep.quickfix=true 'core/testOnly *TestTolerantCheck'`, 311 s,
47/47 properties.  BEFORE is `tracker/loopmodel/LSP3-6.6-QUICKFIX.md` §5a (same tree shape,
same corpus).

| | before | after |
|---|---|---|
| files | 253 (4 excluded: `Interp.e`, `Sample.e`, `Yahoo.e`, `guide/HelloWorld.e`) | 253 (the same 4) |
| unsigned top-level groups | 1334 | 1334 |
| insertions OFFERED | 1166 | **1183 (+17)** |
| **CLEAN** | 1164 (99.83 %) | **1181 (+17), 99.83 %** |
| **PARSE-FAIL** | **0** | **0** |
| **TYPE-FAIL** | **2** | **2** (the same two `Validation.e` alias unfolds, both re-checking with zero diagnostics) |
| SKIPPED | 168 | **151 (−17)** |
| — out of scope | **117** | **100 (−17)** |
| — nested `* ->` kind (item 1) | 10 | 10 |
| — free kind variable (item 2) | 36 | 36 |
| — `<:_Type.Cast` (item 3) | 2 | 2 |
| — field does not round-trip (item 4) | 3 | 3 |
| import-scanner disagreements | 0 | 0 |
| pairs equal only under the complete comparator | 5 | 6 (that counter is a lower bound: it only sees pairs the `forall` short-circuit reaches) |

Out-of-scope NAME OCCURRENCES, the sub-classification review R-1 introduced:

| sub-class | before | after |
|---|---|---|
| imported under an ALIAS (item (3)'s, `Report` 8, `Presentation` 8, `Map` 6, …) | 68 | **68** |
| not nameable here at all (`ErasedMagnitude` 31, …) | 49 | **49** |
| **the file's OWN synonym — the false negative** | **33** | **0** |
| total | 150 | **117** |

**SHIP BAR ≥ 95 % clean: 99.83 %, unchanged, with 17 more insertions.**

### 4c. 17 groups, not 31 — the brief's "≤ 84" corrected

The brief asks for `OutOfScope 117 -> ≤ 84`, i.e. 117 − 33.  That subtraction treats a NAME
OCCURRENCE as a REFUSAL, and the 6.6 report is explicit that they are not the same thing:
"117 refusals cite 150 type names between them".  A group is refused if ANY name in its
rendered type is out of scope, so a group citing an own-synonym name AND an alias-imported
name stays refused after E10(5) — correctly, because the alias-imported name still would not
parse.

The own-synonym class is CLOSED — **33 -> 0 name occurrences, every one recovered** — and 31
groups cited one.  **17 of those 31 cited own-synonym names ONLY**, and those 17 are the
recovery.  The other 14 also cite one of the 68 alias-imported or 49 not-nameable names and
are still correctly refused; they belong to E10(3) and to the private-`data` case, not here.
So `≤ 84` was not reachable by E10(5) alone, and 100 is the number this fix can produce.  No
test was loosened to reach it, and the invariant that matters — 0 PARSE-FAIL, 2 TYPE-FAIL —
held.

### 4d. PIN in lsp-smoke

`tracker/lsp-tests/SynSrc.e` (`data Widget = MkWidget`, `data Box a = MkBox a`) and
`tracker/lsp-tests/Syn.e` (`import SynSrc as W`; `type Widget = Widget_W`;
`type Boxed a = Box_W a`; `boxed = MkWidget_W`; `wrapped = MkBox_W MkWidget_W`), both clean:

| | |
|---|---|
| a synonym-typed unsigned binding is offered its signature | `add signature: boxed : Widget` |
| the edit | one insertion, `boxed : Widget\n` at (14, 0)-(14, 0) |
| **it re-checks clean** | applied through the client's own `apply_ws`, re-published diagnostics `[]` |
| **THE SOUNDNESS CONTROL** | `wrapped : Box Widget` is STILL refused — `type Boxed a = Box_W a` says how to write `Box x`, not how to write the bare constructor `Box`.  This is the half that must not be accepted |

`TestTolerantCheck`'s sweep passes `c0.ownTypes` as `sigEdit`'s ninth argument, so the sweep
and the server test the same function with the same inputs.

---

## 5. Write-back into `tracker/TICKET-stdlib-findings.md`

+123 / −4 lines, no other change to that file.  Every disposition names this item and this
report.

| ticket | disposition written back |
|---|---|
| **E5** (`loadModulesInSeries` vs `loadModules`) | **NOT THIS STAGE.**  Shipped loader behaviour: Tier 2 (`core/test` alone) plus Tier 1's `ei-diff.sh --batch` in series on both sides with `-Dermine.loadInSeries=true` and `g1-validate.sh`, and a one-line change is not worth a gate run of its own.  It waits for the FIRST TIER-2 CODE COMMIT that is due — not the G4 evidence run, which lands no code (review R-6 corrected the first wording): the first Stage-5 adoption item, or its own tiny item. |
| **E6** (lambda blame at the application) | **NOT THIS STAGE.**  A checking-mode `Lam` rule moves the POSITION and sometimes the wording of every such refusal: REPL goldens, two `TestStage1Pins` anchor pins and the corpus verdict TEXT all re-cut.  Tier 2 + goldens, its own item; frozen batch semantics forbid it here. |
| **E7** | **HALF FIXED, HALF DEFERRED WITH THE REASON.**  §3 above, written out in full in the ticket — the flag, the two pins, and the three reasons the operator half is not Tier 0. |
| **E8** | **FIXED in LSP Stage 4 item 7.5**, pins `tracker/lsp-tests/Tab.e` and `core/examples/GridExample.e`, with the new histogram, the round-trip properties, the UTF-16 answer, and the two removed mitigations. |
| **E9** | **FIXED in LSP Stage 4 item 7.5**, pins named (tree-distinguishing, plus the eight tightened ones), the derivation of the mapping, and the jar fallback stated as reasoned-not-pinned. |
| **E10(5)** | **FIXED in LSP Stage 4 item 7.5**, pin `tracker/lsp-tests/Syn.e` + `SynSrc.e`, the sweep table, and the 17-vs-31 correction. |
| **E10(1)-(3)** | **NOT THIS STAGE — Tier 1.**  The same printer writes interface bytes: the `ei-diff.sh --batch` interface sweep classified with `ei-classify.py`, `g1-validate.sh`, and a RE-CUT `tracker/g1-baseline` for the moved spellings.  Their own item, 48 groups, unchanged by 7.5. |
| **E10(4)** | **NOT THIS STAGE** and not the printer: a concrete row field's `Global` does not round-trip — in whatever mints a field's `Global`, or in unification's notion of field identity (3 groups).  Recorded in the same breath so the split is complete. |

---

## 6. Gates

Tier 0 on the FINAL tree unless a row says otherwise.  One JVM at a time; nothing in the
background.

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | **success**.  One `[E121]` pattern-match warning, `TolerantCheck.scala` `foreignTypes`' `case _ => None` — PRE-EXISTING, in code this item does not touch (the line number moved only because text was inserted above it) |
| `TestLoopTrace` | **720 solves / 720 segments / 720 agree**; `hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; 3/3 properties.  Controls still fire (id base +1: 46 of 720 disagree; `--flags=nongen`: 58 of 720) |
| `corpus-run.sh --batch` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**.  Byte-identical to a run of the same tree before the E7 delta except progress-bar timings |
| `repl-smoke.sh` | **8 groups PASS, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `tracker/repl-tests/` UNMODIFIED by `git status` |
| `lsp-smoke.sh` | **PASS, 542 checks** (510 before this item, **+32**) |
| boot | **129 modules**, asserted in lsp-smoke; 12.2-13.5 s observed |
| `.ei` droppings, by `find` | **0** under `tracker/lsp-tests` and `core/examples`.  The 14 `.ei` elsewhere are tracked fixtures in `tracker/g1-oracle-tests/`, unmodified, plus the `tracker/g1-baseline` golden set |
| targeted suites, one run: `*TestRenamer* *TestQuickFix *TestEditorBuffers *TestTolerantRead *TestTolerantCheck` | **122 / 122**, 257 s |
| `TestRenamer` alone (the histogram and round-trip numbers) | **34 / 34**, 34 s — 32 before, +2 |
| `TestTolerantCheck` with `-Dermine.sweep.quickfix=true` | **47 / 47**, 311 s; the sweep table is §4b |
| strict path untouched | `Session.scala`, `NewPipeline.readModule`, `scalaparsers/Locations.scala` (`Pos`), `Subst.scala`, `Type.scala` — **not in the diff** |
| `git diff --stat` vs `--stat -w` | **IDENTICAL**, 989 insertions / 137 deletions both ways, and identical per file for all 13 files |
| `git diff --stat` vs `--stat -w --histogram` | 989/137 vs 987/135.  **The delta is the `--histogram` ALGORITHM, not whitespace**: `--stat --histogram` alone gives the same 987/135, and per file the ONLY file that differs is `docs/lsp.md` (61/39 default and `-w`, 59/37 histogram), where histogram matches two blank lines that Myers re-creates inside a prose block this item rewrote.  Every `.scala` and `.py` file is identical under all three.  No reflow is hiding a change |
| line endings | preserved.  Every file edited was LF and stayed LF (`lsp/*.scala`, `TolerantCheck.scala`, `TestRenamer.scala`, `TestTolerantCheck.scala`, `docs/lsp.md`, `TICKET-stdlib-findings.md`, `lsp-client.py`); the three new fixtures are LF with real tabs, matching every other `tracker/lsp-tests` fixture.  No `.e` file in `core/` or `core/src/main/resources` is in the diff, so `GridExample.e`'s and `Bool.e`'s CRLF are untouched — lsp-smoke asserts the latter on disk |
| **Report.e round trip, one interleaved pair** | **BEFORE 0.927 s / AFTER 0.908 s, Δ −19 ms; read 0.055 s on BOTH sides; residual 0.027 s on both.**  Inside the ~50 ms noise floor, favourable sign, and the BEFORE side carried the higher load — the helper did not move the round trip.  §1g |

Batch semantics are frozen and were not touched: no `Pos` change, no `Session.load`/
`readModule`/`SurfaceParsers.module` change, REPL goldens byte-unchanged, corpus verdicts
unchanged.  No request-path work beyond the boundary conversion; the one file read it
introduces is `LineSource`'s, bounded and memoized, on the same file `location` already
`stat`s.

---

## 7. Files changed

| file | + / − | what |
|---|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Definitions.scala` | 261 / 10 | `Lines.character`/`column`/`tabbedLine`/`lineText`; `toCharacter`/`toColumn`; `LineSource`; `SourceTree` (E9); `DocIndex.lines` and `DocIndex.ownTypes`; `location` rewritten; `occurrenceAt` converted; `nameExtent`'s tab refusal removed |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Diagnostics.scala` | 28 / 13 | `fromDiag`/`fromSpan`/`fromReport` take the line model; `check` passes `idx.lines`; the `Death` path builds one from the buffer |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/References.scala` | 26 / 11 | `siteAt` converted; `rangeOf` takes the document it is in; the def-site `location` call; one `LineSource` |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Symbols.scala` | 37 / 23 | `rangeJson`/`selJson`/`documentSymbolJson` take the line model; `sessionGlobals` takes the `LineSource`; one per `install`; header comment corrected |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Completion.scala` | 12 / 6 | the `scopeAt` column converted |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/QuickFix.scala` | 25 / 8 | `inScope` takes `ownTypes` (E10(5)); `sigEdit` threads it; `BehindTab` removed (E8) |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Resident.scala` | 20 / 3 | `Checked.ownTypes`; the suppression predicate gains `undefinedType` (E7) |
| `core/src/main/scala/com/clarifi/reporting/ermine/session/TolerantCheck.scala` | 60 / 4 | `Note.undefinedType` and the tagged `assertTypeClosed` catch (E7); `ownTypes` built and published (E10(5)) |
| `scalacheck-binding/src/main/scala/TestRenamer.scala` | 83 / 7 | two round-trip corpus properties; the extent classification re-stated for the tab class |
| `scalacheck-binding/src/main/scala/TestTolerantCheck.scala` | 6 / 1 | the sweep passes `ownTypes` |
| `tracker/tools/lsp-client.py` | 247 / 8 | the 7.5 pin sections (E8, E9, E10(5), E7) and eight tightened stdlib pins |
| `tracker/lsp-tests/Tab.e` | new | E8's fixture |
| `tracker/lsp-tests/Syn.e`, `tracker/lsp-tests/SynSrc.e` | new | E10(5)'s fixture and its soundness control |
| `tracker/lsp-tests/BadTy.e`, `tracker/lsp-tests/UndefTy.e` | new | E7's fixture and its control |
| `docs/lsp.md` | 61 / 39 | the column note rewritten (E8, with the UTF-16 answer), the E9 caveat replaced, the import-failure rule and the signature refusals updated (E7, E10(5)) |
| `tracker/TICKET-stdlib-findings.md` | 123 / 4 | the seven write-backs (§5) |

No commits; nothing pushed.  STOP here, per the brief — a reviewer re-runs the gates once.


## Orchestrator's note at commit (review R-1..R-3, R-6)

R-3: the jar-only case IS constructible (the reviewer built it) and in it stdlib navigation vanishes for a pre-existing reason (`isFile` rejects a `jar:` fileName before the rewrite); the reachable fallback is a `modules` directory with no `target` ancestor. R-6: "rides with G4" was a category error — E5 waits for the first Tier-2 code commit. R-2: eight pre-existing pins, not five. R-1: `Lines.locate`'s scaladoc no longer asserts the removed mitigation; GridExample.e indents three lines, not four.
