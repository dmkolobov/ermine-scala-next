# Review: LSP Stage 4, item 7.5 — ticket triage (E8 tab columns, E9 build-output paths, E10(5) synonyms, E7 half)

Independent review of `tracker/loopmodel/LSP4-7.5-TICKETS.md`.  Brief
`tracker/loopmodel/briefs/brief-LSP4-7.5-review.md`; implementer's brief
`tracker/loopmodel/briefs/brief-LSP4-7.5.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 4, 7.5;
`tracker/GATE-POLICY.md`.  Branch `scala3-migration`, HEAD `823cb1c` plus the uncommitted deliverables.
No commits; nothing edited but this file and
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-7.5/`.
`tracker/lean/` and `tracker/LSP-ROADMAP.md` untouched.  One JVM at a time throughout; no background JVMs
and no polling shells left behind.

**VERDICT: FIX-THEN-ADVANCE.**  The code is right and every gate reproduces — including the two numbers the
brief singled out (the sweep table and the extent histogram) to the digit.  I attacked E8 and E10(5) beyond
their pins with five live probe fixtures and both held.  What has to be fixed is **prose in the record**, and
two of the four items are statements I refuted by construction rather than by reading:

1. **R-3.** "no jar-only module is constructible here to test it against" (report §2a, ticket E9) is false.  I
   built one in under a minute and ran the server on it; the result is worth writing down, because in that
   configuration stdlib `definition` answers `null` and `workspace/symbol` answers `[]`.
2. **R-6.** "E5 rides with GATE G4" is the category error the brief suspected, and the roadmap's own
   disposition asked for a *commit*, not a gate.
3. **R-2.** the E9 write-back says "five pre-existing stdlib pins" and then lists eight.
4. **R-1.** `Lines.locate`'s scaladoc still states the mitigation this item removed.

R-4, R-5 and R-7 are recorded but need no action.  None of the seven is a code defect and none touches a
gate result, so this is a small text round, not a re-run.

---

## 1. Runs, in the order I made them

| # | run | wall | result |
|---|---|---|---|
| R1 | `sbt -batch -J-Xmx3g core/compile core/copyResources` | 5 s | up to date (the implementer's tree was already built) |
| R2 | `sbt -batch -J-Xmx3g core/clean core/compile core/copyResources` | 43 s | **success**, 478 warnings, 0 errors |
| R3 | `tracker/tools/lsp-smoke.sh` | ~35 s | **PASS, 542 checks** |
| P1 | reviewer probe 1 — mid-line tab, double tab, astral, synonym attacks (`probe.py`, 8 scratch fixtures) | ~25 s | 33 of 35 as predicted; the 2 misses were my expectation strings, not the server (§3, §5) |
| P2 | reviewer probe 2 — synonym chain vs. declaration order vs. higher-kinded nullary (`probe2.py`) | ~20 s | isolated R-4 |
| P3 | reviewer probe 3 — `Layout/Scan.e` opened as itself, all offered signatures applied and re-checked | ~20 s | **15 signatures, all naming `Scan`, re-check CLEAN** |
| R4 | `sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace*'` | ~60 s | **720 / 720 / 720**, 3/3 properties |
| R5 | `sbt -batch -J-Xmx3g 'core/testOnly *TestRenamer* *TestQuickFix *TestEditorBuffers *TestTolerantRead *TestTolerantCheck *TestSurfaceCache'` | 283 s | **127 / 127** |
| R6 | `sbt -batch -J-Xmx3g -Dermine.sweep.quickfix=true 'core/testOnly *TestTolerantCheck'` | ~310 s | **47 / 47**, sweep table §4 |
| R7 | `tracker/tools/corpus-run.sh --batch <scratch>` | 44 s | **85 / 69 / 0 over 154** |
| R8 | `tracker/tools/repl-smoke.sh` | 114 s | **8 groups, 66 checks**, goldens unmodified |
| P4a | E9 fallback A — a classpath `modules` dir with no `target` ancestor | ~20 s | mapping `None`, navigation unchanged and working |
| P4b | E9 fallback B — **modules in a JAR**, jar first on the classpath | ~20 s | boot 129, `definition` → `null`, `workspace/symbol` → `[]` |
| R9 | `tracker/tools/perf-bench.sh editor -k 15` (load 1.26 before) | 29 s | median **0.880 s**, read **0.050 s** |

Eleven JVM starts, all sequential, all exited.  `.ei` count 143 before and after, all tracked.

---

## 2. Findings

| id | severity | status | one line |
|---|---|---|---|
| R-1 | LOW | CONFIRMED | `Lines.locate`'s scaladoc still says a name behind a tab "is never treated as exact and never renamed" — the mitigation this item removed |
| R-2 | LOW | CONFIRMED | the E9 write-back says "five pre-existing stdlib pins" and lists eight |
| R-3 | MEDIUM | CONFIRMED | "no jar-only module is constructible here" is false; I built one, and in it stdlib navigation and workspace symbols vanish entirely |
| R-4 | LOW | CONFIRMED | E10(5) does not see through a synonym CHAIN, and the record does not say so (conservative refusal, not unsound) |
| R-5 | LOW | CONFIRMED | "pairs equal only under the COMPLETE comparator: 5 → 6" — my re-run of the same tree gives 5, not 6 |
| R-6 | MEDIUM | CONFIRMED | "E5 rides with GATE G4" is a category error: a gate is an evidence run, not a commit, and the roadmap asked the item to name a commit |
| R-7 | LOW | CONFIRMED | every tab in every pin and property is a single LEADING tab; mid-line and double tabs are unexercised by the suite (I exercised them live and they are correct) |
| R-8 | INFO | CONFIRMED | the UTF-16 argument is right, and now holds end to end against a real astral character |
| R-9 | INFO | CONFIRMED | the E7 catch swallows exactly what `guard(Error)` swallowed, no more |
| R-10 | LOW | CONFIRMED | `LineSource`'s comment gives the wrong *reason* for preferring the index's `Lines` on a stdlib target (the behaviour is right) |
| R-11 | INFO | — | batch and REPL cannot be reached by this diff, which is what stands in for my not re-running the byte-identical corpus A/B |

### R-1 — the scaladoc at the site of the change is now false (LOW, CONFIRMED)

`Definitions.scala:390-404`, `Lines.locate`, still ends:

> `sawTab` matters as well as the offset: an LSP range built from a parser column on such a line is in the
> wrong units for the editor that receives it (the server's position model has been tab-blind since 0.5, and
> fixing THAT is not this item), so a name behind a tab is never treated as exact and never renamed.

Every clause of that is now wrong: the units are converted, `nameExtent` reads `val (off, _) = ls.locate(...)`,
and `rename` behind a tab is pinned working in lsp-smoke and in my own probe.  `sawTab` survives as a return
value read by exactly one caller — `TestRenamer.scala:326`, the histogram — and by nothing in the server
(`grep` over `lsp/` and `scalacheck-binding/`).  The same comment also says `GridExample.e` "indents four
lines with a tab"; it indents **three** (`grep -nP "\t"` gives lines 65, 66, 67), which is what both new
properties report and what the report itself says.  Pre-existing for the line count, newly false for the
rest.  Fix: rewrite the paragraph, or delete `sawTab` from `locate` and let the property compute it from
`tabbedLine`.

### R-2 — "five" pre-existing stdlib pins, eight listed (LOW, CONFIRMED)

`tracker/TICKET-stdlib-findings.md:662`: "and the five pre-existing stdlib pins (`Bool.e`, `Either.e` x3,
`Date.e`, `Relation.e`, `Relation/Sort.e`, `Layout/Report/SoftRelation.e`) were tightened".  That list is
eight pins over six files, which is what report §2b says ("the eight pre-existing stdlib pins were
TIGHTENED") and what the diff does.  The ticket file is the artifact of record; make it agree.

### R-3 — a jar-only module IS constructible, and the result is worth recording (MEDIUM, CONFIRMED)

Report §2a and the E9 write-back both say: "this build unpacks every module under `classes/modules`, so no
jar-only module is constructible here to test it against."  It took one command:

```
cd <scratch>/fakecp && jar cf modules.jar modules      # 192 entries, modules/Bool.e etc.
java -cp modules.jar:<rest of the classpath> …lsp.Main  # the jar FIRST
```

That is an assembly/fat-jar deployment, which is a supported way to ship this server, and it is exactly the
shape the user's older Scala-2 fork would arrive in.  Measured (P4b):

* boot: **`Ermine session ready: 129 modules in 13.0s`** — the session loads fine from the jar;
* `textDocument/definition` on a stdlib operator: **`null`**;
* `workspace/symbol "not"`: **`[]`** — not an unrewritten path, *nothing at all*;
* the install log: `stdlib source tree (no source tree found beside the classpath modules)`.

The **reasoning** in the report is right and I verified the mechanism: `SourceFile.classloader`
(`Session.scala:367-375`) returns `Resource(module, url)` for a non-`file:` protocol, `Resource.toString` is
the `jar:…!/modules/Bool.e` URL, that string becomes `Pos.fileName`, and `Definitions.location`'s guard
`new java.io.File(p.fileName).isFile` rejects it *before* `SourceTree.rewrite` is reached.  So
`rewrite`'s jar branch is genuinely dead for stdlib modules, the disposition ("reasoned, not pinned") is
unchanged, and **E9 introduces no regression** — the `[]` and the `null` are pre-existing.  What is wrong is
the sentence, and what is missing is the note that in a jar deployment stdlib navigation and workspace
symbols are absent altogether (a `docs/lsp.md` sentence, and arguably a new ticket).

The fallback that *is* reachable — and that the report should cite instead — I also exercised (P4a): a
classpath `modules` directory with no `target` ancestor (an installed distribution with classes but no source
tree).  `baseOf` finds no `target`, `mapping` is `None`, the log says so, `rewrite` returns its argument, and
`definition` and `workspace/symbol` answer the classpath path and still work.  Clean degradation, confirmed
by experiment rather than by argument.

### R-4 — E10(5) does not see through a synonym CHAIN (LOW, CONFIRMED)

Isolated in P2 with three one-import fixtures over the same `SynSrcB.e` (`data Widget = MkWidget`,
`data Box a = MkBox a`):

| fixture | shape | `add signature: boxed : Widget` |
|---|---|---|
| `SynF.e` | `type Widget = Widget_W`, declared **after** the binding | **offered** |
| `SynE.e` | `type Widget = Mid` + `type Mid = Widget_W`, declared **before** | **not offered** |

So declaration order is *not* the variable (the brief's "a synonym defined AFTER its use" works), the chain
is.  The cause is in `Session.processTypeDefComponent:890`: a `TypeStatement` installs
`v -> Con(l, global(mn, v), TypeAliasDecl(...))` — the module's **own** alias `Con`, not the head it expands
to.  So `subTypeMaps(maps, body)` on `type Widget = Mid` yields `Con(Global("SynE","Mid"))` and `ownTypes`
publishes `"Widget" -> SynE.Mid`; `inScope`'s identity test then intersects `chase(origins, SynE.Mid)` (a
local global, absent from `consOrigins`, so `{SynE.Mid}`) with `chase(origins, SynSrcB.Widget)` and gets the
empty set, so the signature is refused.  **Conservative and sound** — the refusal is the safe direction, and
this is the same identity test doing its job — but the report's "nullary `type X = C` synonyms resolved
through the type-def phase's maps" and the ticket's "resolved to the `Con` that writing that spelling in this
file denotes" both read as if a chain resolves to its head.  One sentence: the substitution is a single pass
over `maps`, so a synonym of a synonym stops at the intermediate alias and is refused.

The same probe confirmed the two soundness halves the brief asked about, and one the report did not claim:

| fixture | shape | result |
|---|---|---|
| `SynD.e` | `type Box = Box_W Widget_W` — **applied body** | not published; `wrapped : Box Widget` **refused** (`the type names Box, which this file does not import`) |
| `SynB.e` | `type Box = Widget_W` — nullary but pointing at the **wrong** con (shadowing/mis-pointing) | published, and the identity test **still refuses** `wrapped` |
| `SynG.e` | `type Box = Box_W` — nullary synonym of a `* -> *` constructor | published, `wrapped : Box Widget` offered, applied, **re-checks CLEAN** |

`SynG.e` is the case the report's soundness argument covers but does not mention ("`type X = C` says `X` and
`C` are the same type constructor" holds at any kind), and it behaves correctly.

### R-5 — one sweep counter does not reproduce (LOW, CONFIRMED)

Report §4b's last row: "pairs equal only under the complete comparator | 5 | **6**".  My re-run of the same
tree prints `### pairs equal only under the COMPLETE comparator: 5`.  The report already flags the counter as
a lower bound that depends on which pairs the `forall` short-circuit reaches, so this is a known-unstable
figure rather than a disagreement about the fix — but as printed, the "after" column is not reproducible.
Either quote 5 with the caveat, or drop the row.  **Every other cell of the sweep table reproduced exactly.**

### R-6 — "E5 rides with G4" is a category error (MEDIUM, CONFIRMED)

The brief's suspicion is right, and the write-back half-concedes it in its own last clause.

* **G4 is an evidence gate, not a commit.**  Nothing lands "with" it.  Its GREEN line is a list of runs made
  *on the tree as it then stands*.
* **The sequencing is therefore undefined, and both readings are wrong.**  If E5 lands *before* G4, G4's runs
  cover it — but then G4 is measuring a tree that changed after the stage's items were reviewed, which is
  precisely what "frozen batch semantics" forbids inside the stage.  If E5 lands *after* G4, it gets no gate
  at all, and the disposition's whole justification ("the next scheduled occasion for exactly those runs")
  evaporates.
* **The roadmap asked for something else.**  Its E5 disposition reads: "It rides along with the next Tier-2
  commit that is due anyway; **the item notes which**."  The item was asked to name a commit and named a
  gate.  The write-back's own hedge — "If G4 lands no code commit, the next Stage-5 adoption item inherits
  it" — is an admission that no commit has been identified.

Fix, in the ticket and in report §5: say "the first Tier-2 code commit that is due — in the current plan the
first Stage-5 adoption item; it must NOT land between the last Stage-4 item and G4", or make E5 its own tiny
item and gate it on its own.  Either is fine; "rides with G4" is not.

On the rest of question 5: the ticket file **does** agree with the roadmap's dispositions for E6 (Tier 2 +
goldens, own item), E7 (flag-based tag or the reason written down — the reason is written down, at length),
E8 and E9 (TAKE, boundary conversion / `Definitions.location`, Tier 0), and E10 (SPLIT, (5) taken, (1)-(3)
Tier 1 with a re-cut `g1-baseline`).  E10(4) is written back too, which the roadmap did not ask for and which
completes the split honestly.  E5 is the only disagreement.

### R-7 — every tab in the suite is a single LEADING tab (LOW, CONFIRMED)

`grep -rlP "\t" --include=*.e core/src/main/resources/modules core/examples` returns exactly one file:
`core/examples/GridExample.e`, three lines, one leading tab each.  `tracker/lsp-tests/Tab.e` is the same
shape.  So the domain of the second round-trip property ("tabbed lines 3 | characters 132") and of every new
pin is *single leading tab only*.  The two cases the brief asks about — a tab in the MIDDLE of a line, and
two tabs on one line — are pinned nowhere.

They are nonetheless correct.  I checked them live (P1) with `MidTab.e`:

```
line  6:  cc = aa<TAB>&& bb              aa@char5 col6 | &&@char8 col16 | bb@char11 col19
line  8:  <TAB><TAB>ee = aa<TAB>&& bb    ee@char2 col16 | aa@char7 col21 | bb@char13 col27
line 10:  ff = aa<TAB><+> bb             <+>@char8 col16
line 12:  gg = aa<TAB>&& nosuchname      nosuchname@char11 col19
```

Every one answered at the character column and refused the parser column: `definition` on `aa`/`bb` at chars
5/11 and 7/13; `definition` at char 19 and char 16 (the old parser columns) → `null`; `hover ee` at char 2;
`references` of `aa` → `(4,0) (6,5) (8,7) (10,5) (12,5)`, of `bb` → `(5,0) (6,11) (7,5) (8,13) (10,12)`;
the structured `unknown operator` diagnostic at **(10, 8)** and the caret `undefined term` note at
**(12, 11)** — both after a *mid-line* tab, both on the text; `prepareRename` behind two tabs offering
`(8,2)-(8,4)`; and the rename applied by the client producing exactly `\t\teee = aa\t&& bb`, with the
re-checked buffer reporting the same diagnostics.  The arithmetic is right by construction too — `character`
and `column` both walk with `c += 8 - (c % 8)`, which is `Pos.bump`'s rule verbatim at any starting column,
not only at column 1.

Recommendation, not a requirement: add one mid-line tab and one double tab to `Tab.e` (two lines) so the
class is pinned rather than reviewed.

### R-8 — the UTF-16 argument, verified at both ends (INFO, CONFIRMED)

Source side: `parsers/src/main/scala/scalaparsers/Locations.scala:55-62` — `def bump(c: Char, …)`, with
`else if (c == '\t') … column + (8 - column % 8)` and `else … column + 1`; and `bumps` (`:64`) advances by
`pre.length`, a `String.length`.  `ParsingUtil.rawSatisfy:52-65` reads `si.charAt(so)` and advances
`offset = so + 1`.  So a surrogate pair is **two** `bump`s → two parser columns, and it is two UTF-16 code
units → two LSP characters.  Confirmed: `column 1` becomes `column 8` on a tab, **not 9**, and
`Lines.character` matches (`c=1` → `c += 8 - 1` → `8`).

Behaviour side, which is what the brief asked for — `Astral.e`, `n = second "𝔸𝔹" flag`, two astral
characters in a string literal.  `flag` is at code-point index 16 and **UTF-16 index 18**:

* `definition` at `(8, 18)` → the binder at `(6, 0)`; `hover` at `(8, 18)` → `Astral.flag : Bool`;
* `definition` at `(8, 16)` → `null` (that is the closing quote);
* `references` of `flag` → `(6, 0)-(6, 4)` and `(8, 18)-(8, 22)`.

A code-point-counting server would have answered at 16.  The two models agree, and nothing needed converting.
(The report's aside is also right that an astral character cannot be an *identifier* character —
`Character.isLetter(Char)` is false for a lone surrogate, so `rawLetter`/`rawTailChar` reject it; it can only
reach the text through a literal or a comment, which is what my fixture does.)

### R-9 — the E7 catch swallows exactly what it replaced (INFO, CONFIRMED)

`guard` (`TolerantCheck.scala:476-482`) catches `Death(e, _)` and
`com.clarifi.reporting.ermine.parsing.Recoverable(e)`.  The replacement catches those two and nothing else;
the only difference is `undefinedType = true`.  And `Subst.assertTypeClosed:1741-1744` has exactly one exit —
`die(vsep(ftvs.map(v => v.report("error: undefined type"))))` — so the flag cannot land on a different note.
The one theoretical over-reach is that a `Recoverable` raised *inside* `assertTypeClosed` would also be
tagged; `assertTypeClosed` computes `typeVars(t) -- ex` and dies, and raises none.  The flag is set by
construction and never by matching text, as 6.1's rule requires, and `Resident.checkFile`'s predicate is the
6.1(b) predicate with one more disjunct.  `Subst.scala` is not in the diff.

The deferral is honest about what a user still sees: `docs/lsp.md` now reads "**One consequence of a missing
import is NOT withheld** … three per use", names the two reasons a filter cannot reach them, and points at
ticket E7.  The three reasons in §3b hold up — I checked (1) by reading `checked.diags` (they are
`NewPipeline.Diag`, published from a list the suppression filter never sees) and (3) by reading 6.1's own
rule; (2) is the one I cannot fully re-derive without building the counterfactual, but the
`TolerantCheck.keys` comment it cites ("an operator, anything the extent scanner cannot name — is simply
never cached") is there and says what it is said to say.

### R-10 — `LineSource`'s comment gives the wrong reason (LOW, CONFIRMED)

`Definitions.scala:521-525`: the index's `Lines` is preferred "over the buffer even when the buffer has moved
on" because it is "the text the CHECK read, which is the text every position this converts was measured in".
For a *stdlib* target — the case `LineSource` exists for — that is not so: the position was measured by the
resident **session** reading the build-output copy, while the index is the **editor's** check of the source
copy the user happens to have open.  The behaviour is right anyway, because `copyResources` makes the two
copies byte-identical (which the report says elsewhere, §2a), but the justification as written does not cover
the case it is written for.  Cosmetic.

### R-11 — why I did not re-run the byte-identical corpus A/B

The implementer's byte-identity claim would need the BEFORE tree built, i.e. stashing an uncommitted diff I
am not allowed to touch.  Instead: the only file in the diff outside `lsp/` is `TolerantCheck.scala`, and
`grep -rn TolerantCheck --include=*.scala core/src/main scalacheck-binding/src/main` reaches it from
`lsp/*.scala` and the test suites only — `Session.scala`'s single hit is a comment.  Batch and REPL run
`Session.load`, not `TolerantCheck`, so neither can observe this diff.  That plus 85/69/0 and byte-unchanged
REPL goldens is the evidence.  Corroboration from the run itself: the batch verdicts still name
`…/core/target/scala-3.3.8/classes/modules/Field.e` in two `shouldfail` refutations — E9's rewrite really is
LSP-boundary-only and no `Loc` moved inside the compiler.

---

## 3. E8 — the conversion, checked against the brief's list

* **Grep for a surviving `± 1` on a column.**  `grep -n "col - 1\|column - 1\|chr + 1\|startCol - 1\|endCol -
  1\|\.sc - 1\|\.ec - 1\|col + 1"` over `lsp/*.scala` hits `Definitions.scala` only — `locate`'s untabbed
  fast path (`:408`), `character`/`column`'s own untabbed fast paths (`:453`, `:454`, `:473`, `:474`) and the
  documented no-`Lines` fallback (`:509`, `:512`) — plus one comment in `Diagnostics.scala:337`.
  `QuickFix.scala:308`'s `col + 1` is a character index in the import scanner and was never in parser units.
  Confirmed as reported.
* **A `Span`/`Pos` column reaching JSON without the helper.**  I walked every `"character" -> Json.num(...)`
  in `lsp/`: `Diagnostics:435-436` and `QuickFix:51-52` take already-converted values from `range(...)`;
  `References:136-138` and `Symbols:409-417` take `toCharacter` results; `Completion:465-466,490-491` are
  computed on the LINE TEXT in character units and need no conversion; `Definitions:268-269` is the converted
  `chr`.  **Nothing reaches JSON unconverted.**  `codeAction` edits are built from the buffer scanner in
  character units (unchanged), and `tracker/tools/lsp-demo.py` is a pure consumer — it only formats
  `range.start.character` values the server sent, never constructs one.  So the demo tool needed no change
  and got none, correctly.
* **`Pos.bump` and the tab stop.**  `column + (8 - column % 8)`; column 1 → **8**, not 9; `Lines.character`
  and `Lines.column` both use `c += 8 - (c % 8)`.  Matches.
* **UTF-16.**  R-8: verified in the parser and end to end with an astral probe.
* **Both mitigations removed.**  `nameExtent` no longer reads `sawTab` (`val (off, _) = …`);
  `QuickFix.BehindTab` is gone from the source entirely (the only surviving occurrence of the word is the
  comment that explains its removal).  Rename behind a tab works end to end: lsp-smoke pins `Tab.e`
  `(11,1)-(11,3)` + `(10,9)-(10,11)`, and my probe applied a rename behind **two** tabs through the client
  and got `\t\teee = aa\t&& bb` back.
* **`GridExample.e`'s six occurrences.**  lsp-smoke pins `(64,2) (64,26) (65,2) (65,27) (66,2) (66,32)` and
  the file checking clean; 542 PASS.
* **Both round-trip directions.**  Yes, genuinely both.  Property 1 (`TestRenamer.scala`) computes
  `chr = ls.character(ln, col)` then `back = ls.column(ln, chr)` over every occurrence — parser → LSP →
  parser, 71,248 of 71,248.  Property 2 computes `col = ls.column(ln, chr)` then `back = ls.character(ln,
  col)` over `0 to text.length` of every tabbed line — LSP → parser → LSP, 132 characters over 3 lines.  Both
  carry anti-vacuity clauses (`tabbed > 0`, `n > 50000`, `lines > 0`).  The claim is accurate.
* **Mid-line and double tabs.**  R-7: not covered by any pin; correct in fact, checked live.
* **The extent histogram**, re-run: `occurrences 71248 | exact 70903 | backticked 39 | parenthesised 306 |
  behind a tab 6 | other 0`.  Exactly the report's table.  The property is also strictly *stronger* than 6.3's
  — `other` no longer excludes `x._2 == x._3`, so a tabbed occurrence that came back inexact would fail the
  property instead of being reclassified — plus two new clauses (`tabbed > 0`, and every tabbed occurrence
  exact).  No silent weakening.

## 4. E10(5) — the sweep, mine beside theirs

`sbt -batch -J-Xmx3g -Dermine.sweep.quickfix=true 'core/testOnly *TestTolerantCheck'`, 47/47 properties.

| | 6.6 (before) | implementer (after) | **this review (after)** |
|---|---|---|---|
| files | 253 (4 excluded) | 253 (same 4) | **253 (Interp.e, Sample.e, Yahoo.e, HelloWorld.e)** |
| unsigned top-level groups | 1334 | 1334 | **1334** |
| insertions OFFERED | 1166 | 1183 | **1183** |
| **CLEAN** | 1164 (99.83 %) | 1181 | **1181 (99.83 %)** |
| **PARSE-FAIL** | 0 | 0 | **0** |
| **TYPE-FAIL** | 2 | 2 | **2** (concrete row 1, row constraint 1 — the two `Validation.e` alias unfolds) |
| SKIPPED | 168 | 151 | **151** |
| — out of scope | 117 | 100 | **100** |
| — nested `* ->` kind | 10 | 10 | **10** |
| — free kind variable | 36 | 36 | **36** |
| — `<:_Type.Cast` | 2 | 2 | **2** |
| — field does not round-trip | 3 | 3 | **3** |
| import-scanner disagreements | 0 | 0 | **0** |
| pairs equal only under the complete comparator | 5 | 6 | **5** ← R-5 |
| OOS occurrences: imported under an ALIAS | 68 | 68 | **68** |
| OOS occurrences: not nameable here | 49 | 49 | **49** |
| **OOS occurrences: the file's OWN synonym** | **33** | **0** | **0** |
| OOS occurrences, total | 150 | 117 | **117** |

Every cell reproduces except the one flagged in R-5.  Ship bar ≥ 95 % clean: **99.83 %**, with 17 more
insertions and 0 PARSE-FAIL.

**The 17-vs-31 correction is right.**  The 6.6 report does say "117 refusals cite 150 type names between
them", a group is refused if ANY cited name is out of scope, and the sub-class totals above are arithmetic
proof: the own-synonym class went 33 → 0 *occurrences* while refusals went 117 → 100, i.e. 17 groups.  The
brief's "≤ 84" did conflate occurrences with refusals.  The implementer was right to correct it up front
rather than bury it, and no test was loosened to reach 100.

**Three newly offered signatures, spot-checked by hand (P3).**  I opened
`core/src/main/resources/modules/Layout/Scan.e` — the file the ticket is about, CRLF — as itself through the
client.  It checks clean and offers **15** signatures, every one of which names `Scan`, the own-synonym:

```
line 21  scanList : forall a z. List a -> Scan z a
line 24  map_Scan : forall a b z. (a -> b) -> Scan z a -> Scan z b
line 25  filterK  : forall k z v. (k -> Bool) -> Scan z (k, v) -> Scan z (k, v)
…
line 55  count'   : forall (r2: rho) n z k (r: rho). PrimitiveNum n =>
                    Field r2 n -> Scan z (k, Relation r) -> Scan z (k, Relation r2)
```

I applied **all fifteen** through the client (CRLF preserved; the server's `newText` ends `\r\n`, so it reads
the file's own EOL) and re-checked: **`diagnostics: []`**.  That is the recovery, verified by hand on the
real file rather than inferred from the CLEAN column — far more than the three the brief asked for.

**The soundness attacks** are in R-4: applied body refused, wrong-con synonym refused, higher-kinded nullary
synonym accepted *and* re-checking clean, chain refused (conservatively).  `inScope`'s new branch is an
identity test on `chase`d origins, never a spelling comparison, and a local alias `Global` can never
intersect a session origin set, which is why the wrong-con case cannot slip through.

## 5. E9 — the path assertions

| assertion | how I checked it | result |
|---|---|---|
| definition target under the source tree | lsp-smoke `definition("Nav.e", 7, 12)`, `startswith(<repo>/core/src/main/resources/modules)` and no `/target/` | PASS |
| references' def-site under the source tree | lsp-smoke, the one hit outside the open buffers | PASS |
| workspace/symbol under the source tree | lsp-smoke, and my own probe: `…/core/src/main/resources/modules/Bool.e` | PASS |
| **no** workspace-symbol location anywhere in the build output | lsp-smoke over every row, re-checked independently in P1 | PASS |
| the rewritten file exists | `Path(...).is_file()` on the uri the server sent | PASS |
| hover target | hover publishes no `Location`; `definition` at the same position is the cover | correct, and stated |
| a module in `core/examples` (not on the classpath) unaffected | `GridExample.e` opened as itself; its `definition` targets are its own uri and `Layout/Report.e` | PASS |
| a workspace sibling unaffected | `Nav.e` → `Good.e`, still the fixture's own uri; `rewrite` guards on `p.startsWith(out)` | PASS |
| **computed once** | `SourceTree.mapping` is a `lazy val`; the smoke log contains exactly **one** `positions: …` line | PASS |
| **survives Decision 5** | the session still boots from the classpath; no `Loc` is rewritten in the compiler — corroborated by the batch run still printing `core/target/…/modules/Field.e` in two verdicts | PASS |
| jar-only module constructible? | **YES — R-3.** I built one and ran it | claim REFUTED, disposition unaffected |

The derived mapping logged once at install:
`stdlib source tree /…/core/target/scala-3.3.8/classes/modules -> /…/core/src/main/resources/modules`.
No Scala version appears in the source; `baseOf` walks to the `target` owner and `Files.isDirectory` /
`Files.isRegularFile` check before use.  Cost: `workspace symbols: 2157 session globals with source, built in
108 ms`, once, including the 129 memoized `LineSource` reads; the pinned per-query budget (`< 50 ms`, best of
five) still passes.

## 6. Gates

Tier 0 on the final tree, one run each, one JVM at a time.

| gate | implementer | **this review** |
|---|---|---|
| `sbt core/clean core/compile core/copyResources` | success; one pre-existing `[E121]` | **success, 0 errors**; 478 warnings; the `[E121]` is `TolerantCheck.scala:740` `foreignTypes`' `case _ => None` — **byte-identical at HEAD** (`git show HEAD:…` confirms), so pre-existing, in code this item does not touch |
| `TestLoopTrace` | 720/720/720, 3/3 | **720 solves / 720 segments / 720 agree**; `hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; **3/3**; controls fire (id base +1: **46** of 720; `--flags=nongen`: **58**) |
| targeted suites | 122/122 (+ SurfaceCache) | **127 / 127**, 283 s (the six suites together) |
| — extent histogram | 71248 / 70903 exact / 6 tabbed exact / other 0 | **identical** |
| — round trips | 71248 round-tripped; 3 lines / 132 chars | **identical** |
| 6.6 sweep | 47/47, table §4b | **47 / 47**, §4 above — every cell but R-5 |
| `corpus-run.sh --batch` | 85/69/0, byte-identical | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**; byte-identity argued, not re-run (R-11) |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups PASS, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` **empty** |
| `lsp-smoke.sh` | PASS 542 (+32) | **PASS, 542 checks**; 510 at 7.4 (roadmap:3295) + **32** counted from the diff — Tab.e **12**, GridExample.e **5**, E9 **5**, Syn.e/SynSrc.e **7**, BadTy.e/UndefTy.e **3** |
| boot | 129 modules | **129 modules**, 12.5–14.0 s over five independent server starts |
| `.ei` droppings | 0 | **0** under `tracker/lsp-tests`, `core/examples`, `core/src/main/resources`; 143 repo-wide, all tracked (`g1-baseline` 129 + `g1-oracle-tests` 14), unchanged before and after |
| strict path untouched | not in the diff | **confirmed**: `git diff --name-only` contains no `Session.scala`, `NewPipeline*`, `scalaparsers/Locations.scala`, `Subst.scala`, `Type.scala` |
| `--stat` vs `--stat -w` | identical 989/137 | **identical, 989 insertions / 137 deletions both ways, per file for all 13 files** |
| `--stat` vs `--stat -w --histogram` | 989/137 vs 987/135, `docs/lsp.md` only | **confirmed**: 987/135 under `--histogram`, and the ONLY file that differs is `docs/lsp.md` (100 vs 96); every `.scala` and `.py` identical under all three |
| line endings | LF preserved | **confirmed**: `file` reports no CRLF on any of the 13 edited files or the 5 new fixtures; no `.e` under `core/` is in the diff, so `GridExample.e`'s and `Bool.e`'s CRLF are untouched |
| Report.e round trip | 0.927 → 0.908, read 0.055 both | **median 0.880 s** = read **0.050** + typecheck **0.510** + debounce **0.300** + residual **0.029**; spread 0.849–0.992; reused **97/154**; cold open 2.321 s; load 1.26 → 1.77; `.ei` 0 before and after |

**On the perf pair.**  I ran the AFTER side only.  A true interleaved A/B needs the BEFORE tree built, which
means stashing an uncommitted diff I am not permitted to touch; and this item makes no performance claim, so
the question the gate asks is only "did the helper move the round trip beyond the floor".  It did not: my
0.880 s and read 0.050 s sit on top of 7.1b's recorded 0.90 s / 0.05 s (roadmap:3296) and 28 ms *below* the
implementer's own AFTER, which is the ~50 ms editor noise floor talking.  The read segment — the one the
retained `Lines` could have touched — is 0.050 s against 0.055 s and 0.05 s.  No movement.

**Is this an adoption item?  No, and I agree with the implementer.**  GATE-POLICY defines Tier 2 as "adoption
commits only (a default flips or shipped behaviour changes)".  7.5 flips no default, adds no flag, and adds
no option that was previously off; it corrects wrong output on the editor path.  "Shipped behaviour" in this
tracker's usage is the compiler/loader/batch behaviour — it is the phrase the E5 disposition uses for a
loader change — and this diff provably cannot reach it (R-11).  The roadmap's own G4 NUMBERS line enumerates
the stage's adoption items as "7.1b, 7.2, 7.4" and requires an interleaved A/B for each; 7.5 is not among
them and makes no claim that would need one.  The roadmap item itself specifies Tier 0 for every ticket it
takes.  I did not run Tier 2, and **G4 will run a full `core/test` ALONE on the tree regardless**, which is
where the residual risk is covered — one more reason E5 must not be waved in that direction (R-6).

## 7. Acceptance, against the roadmap's own line

> ACCEPTANCE: each taken ticket closed with its own lsp-smoke fixture (count grows); each deferred one has
> its disposition and tier written back into `tracker/TICKET-stdlib-findings.md` in the same commit.

| ticket | fixture | met? |
|---|---|---|
| E8 | `tracker/lsp-tests/Tab.e` (new) + `core/examples/GridExample.e` opened as itself | **yes**, 17 checks |
| E9 | no new fixture — 5 tree-distinguishing checks over `Nav.e`/`Bool.e`/`workspace/symbol`, plus 8 tightened pins | **in substance**; E9 is about stdlib paths, so it cannot have a fixture of its own, and the pins are tree-distinguishing, which is what the roadmap actually demanded |
| E10(5) | `Syn.e` + `SynSrc.e` (new), including the parameterised-synonym soundness control | **yes**, 7 checks |
| E7 (half) | `BadTy.e` + `UndefTy.e` (new) — the rule and the control | **yes**, 3 checks |
| count grows | 510 → **542** | **yes** |
| E5, E6, E10(1)-(3), E10(4) written back with disposition and tier | +123/−4 in the ticket file, no other change to it | **yes for six of seven**; E5's names a gate, not a commit — R-6 |

Report §§1-7 are accurate against my numbers with the exceptions listed in §2 (R-3 §2a, R-5 §4b, R-2's
count).  Nothing is overclaimed: the report volunteers its own arithmetic correction (17 not 31) before
anyone asks, states the jar branch as reasoned-not-pinned rather than tested (it is simply wrong about *why*
it could not be tested), reads its own −19 ms as machine noise rather than a win, and names the E121 warning
as pre-existing — which it is.

---

## 8. Fix list (all text; no code, no re-run)

1. **R-3** — replace "no jar-only module is constructible here to test it against" (report §2a and ticket E9)
   with what is true: a jar deployment *is* constructible, `Resource`'s `fileName` is a `jar:` URL, so
   `location`'s `isFile` guard answers `None` before `rewrite` is reached and stdlib navigation and
   `workspace/symbol` are absent altogether in that configuration (pre-existing, not E9's doing).  Cite the
   fallback that IS reachable — a classpath `modules` with no `target` ancestor — which degrades cleanly.
   Consider one sentence in `docs/lsp.md` and/or a new ticket for the jar case.
2. **R-6** — reword E5's disposition to name a COMMIT ("the first Tier-2 code commit that is due — the first
   Stage-5 adoption item in the current plan; it must not land between the last Stage-4 item and G4"), or
   make E5 its own tiny item.  A gate is not a commit.
3. **R-2** — "five pre-existing stdlib pins" → **eight**.
4. **R-1** — rewrite `Lines.locate`'s scaladoc: the `sawTab` paragraph describes a mitigation this item
   removed, and "four lines" is three.
5. *(optional, recommended)* **R-4** — one sentence saying a synonym CHAIN stops at the intermediate alias
   and is conservatively refused.  **R-5** — quote 5, or drop the comparator row.  **R-7** — two lines in
   `Tab.e` (one mid-line tab, one double tab) to pin the class I had to check by hand.

None of these changes a gate number, a sweep cell or a line of shipped code.  **FIX-THEN-ADVANCE.**
