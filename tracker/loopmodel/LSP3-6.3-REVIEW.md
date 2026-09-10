# LSP Stage 3, item 6.3 — independent review

Reviewer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.3-review.md`; implementer report
`tracker/loopmodel/LSP3-6.3-REFS.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.3 with
the STAGE-3 INVARIANTS and Decisions (c)/(d); gates `tracker/GATE-POLICY.md`.  Branch
`scala3-migration`, HEAD `1a22aef` plus the uncommitted 6.3 deliverables.  No commits, no edits
outside my scratch directory and this file; `tracker/lean/` and `tracker/LSP-ROADMAP.md`
untouched.  One JVM at a time; every `.ei` accounted for (0 outside `tracker/g1-*` before and
after every run).

**VERDICT: FIX-THEN-ADVANCE.**  The gates all reproduce, the batch path is genuinely inert, the
references set is right for every shape the brief names *except one*, and every refusal in
Decision (d)'s list fires when it should.  But I got two silent WRONG rename edits through the
refusal list, one of them on real stdlib files with every relevant buffer open, and I found a
third hole in the stale-index refusal.  All three violate Decision (d)'s "never a partial or a
wrong edit"; all three have cheap, refusal-shaped fixes.  Fix R1, R2, R3 (or turn each into an
explicit refusal) and this advances.

---

## 1. Findings

| id | severity | status | one line |
|---|---|---|---|
| **R1** | **HIGH** | CONFIRMED | A re-export splits the key: renaming a name in its defining module silently leaves every module that imports it *through* a re-exporter broken — reproduced on `Bool.e` / `Prelude` with both buffers open. |
| **R2** | **HIGH** | CONFIRMED | A backtick literal identifier (`` ``wide`` ``) gets a replace range 4 characters wide starting at the backtick; rename writes `narrowde`` = True` — an unparseable file. |
| **R3** | **MEDIUM** | CONFIRMED | The stale-index refusal only version-checks documents that already have a hit, so a sibling edited since its last check but not *yet* mentioning the name is neither refused nor edited. |
| **R4** | **LOW** | CONFIRMED | The report's §6 "Gaps, stated" list is incomplete: R1, R2 and R3 are not in it, and §Outcome's "Neither is a silent weakening" is false as written. |
| **R5** | INFO | REFUTED (as a risk) | The shared-file change is inert: `readModule` discards the `Read`, so nothing is retained per module in batch memory, and the editor's new retention is bounded per open document. |
| **R6** | INFO | CONFIRMED (as stated) | The operator import-list gap is exactly as the report describes, and rename does refuse operators both ways. |

### R1 — the re-export chain splits the key (HIGH, CONFIRMED)

`Definitions` keys a global occurrence on `Renamer.ToGlobal.origin`, and `Renamer.originOf`
chases `scope.termOrigins` — but `ModuleScope.importing` returns
`termOrigins = prior.termOrigins ++ localImportsToGlobals(canonicalTerms)` and drops
`sessionTermOrigins` from the *returned* scope (it only feeds `collapseNames`).  `prior` is
`Scope.empty` on the module path.  So `origin` is "the module I imported this name **from**",
which is the defining module for a direct import and is **not** for a re-exported one.  The
defining module's own binder, meanwhile, keys on `ownGlobal(spelling)` — its own module.  Two
keys, two disjoint sets, one name.

Synthetic (`ChainA` defines `gadget`; `ChainB` does `export ChainA using gadget`; `ChainC` does
`import ChainB using gadget` and uses it; all three open and clean):

* references from `ChainA`'s def-site → `{ChainA:5 sig, ChainA:6 eq, ChainB:3 export item}`;
* references from `ChainC`'s use → `{ChainC:3 import item, ChainC:5 use}` (+ the def-site
  Location via `outside`);
* `rename gadget → widget` from `ChainA` **SUCCEEDS**, editing `ChainA` (2) and `ChainB` (1) and
  leaving `ChainC` with `import ChainB using gadget` / `useGadget = gadget` — broken, no
  refusal.

Real stdlib, which is what makes this not a toy.  Open `core/src/main/resources/modules/Bool.e`
and a scratch `Pre.e` = `module Pre where / import Prelude / flipped = not True` (`Prelude.e`
does `export Bool`).  Both clean.

* references on `not` from `Pre.e` → `[Pre.e:5, Bool.e:20]` (the second is the go-to-definition
  Target, not an indexed occurrence);
* references on `not` from `Bool.e` → `[Bool.e:19 sig, Bool.e:20, Bool.e:21]` — **`Pre.e`'s use
  is not in the set**;
* `rename not → nope` from `Bool.e`, with `Pre.e` open, **SUCCEEDS** with 3 edits in `Bool.e`
  and none in `Pre.e`.

The only message the user gets is the Decision (c) coverage warning, which says *unopened*
importers were not searched — actively misleading here, because the importer **was** open and
**was** searched and was missed.  The mirror-image symptom: renaming *from* `ChainC` (or from
`Pre.e`) is refused with "cannot rename a name defined in a file that is not open" even though
the defining file **is** open — same split key, seen from the other end.

`Prelude.e` re-exports fourteen modules and `Field.e` does `export Field.Type`, so this is the
normal shape of the corpus, not an edge.  Cheap conservative fix, in the spirit of refusal (v):
before building the edit, refuse when any open document's index holds an occurrence with the
old spelling under a *different* key.  Proper fix: canonicalise the key by chasing session
origins (the map `ModuleScope.importing` already computes as `termOrigins0` and then throws
away), so a re-exported name and its definition share one key.

### R2 — a literal identifier gets a wrong replace range (HIGH, CONFIRMED)

`SurfaceParsers.literalIdentTok` yields the middle of a `` ``…`` `` pair as the spelling, tagged
`Plain` — indistinguishable from a plain identifier — while the span starts at the first
backtick.  `Definitions.nameLen` measures a letter-initial spelling by its own length, so the
name's recorded extent is 4 short and 2 characters left of true.  `classify` sees `wide`, a
perfectly good lower identifier, and lets rename through.

Fixture `module Lit where / import Bool / ``wide`` = True / useWide = ``wide`` && False`, clean
on open.  `rename ``wide`` → narrow` returns two edits, ranges `4:0-4` and `6:10-14`, and the
buffer they produce is

```
narrowde`` = True

useWide = narrowde`` && False
```

— unparseable.  `documentHighlight` and `prepareRename` are wrong the same way (`prepareRename`
answers range `6:10-14`, placeholder `wide`).  The corpus's largest file, `Layout/Report.e` —
the one the item benchmarks — has 14 such definitions (`` ``1pixel`` ``, `` ``4cell`` `` …);
those are digit-initial, so `classify` refuses them by luck, not by design, and their highlight
ranges fall back to the too-long token span instead.  Any letter-initial one corrupts.

TestRenamer's new overlap property cannot catch this: it re-implements `nameLen`'s rule inline
rather than calling it, so it models the same understated extent and sees no overlap.  Fix:
either give the literal form its own `NameForm` so `nameLen` can add the four backticks (and/or
rename can refuse it), or pass the buffer text into `Definitions.index` and only trust the
spelling length when `text.substring(start, start + len) == spelling`.

### R3 — the stale-index refusal has a hole (MEDIUM, CONFIRMED)

`References.scala:273` computes `touched = docs.all.filter(d => hits.exists(_._1.uri == d.uri))`
and then version-checks only `touched`.  A document that has been edited since its last check
but whose *stale* index carries no hit for the key is in neither set: not refused, not edited.

Reproduced.  `Stale.e` defines `top`; `StaleSib.e` (`import Stale`) does not mention it.  Both
open and clean.  `didChange` `StaleSib.e` to add `useTop = top`, then `rename top → apex`
before the 300 ms debounce: **OK**, two edits in `Stale.e`, none in `StaleSib.e`, whose
just-typed `top` is now undefined.  The control — the same rename while `StaleSib.e` is stale
*and* has a hit — is correctly refused with "check pending; retry after diagnostics update".
Fix: version-check every open document (or every open document for a global key) before
building the edit, not just the ones with hits.

### R4 — the gaps section is incomplete (LOW, CONFIRMED)

§6 lists five items, all accurate.  R1, R2 and R3 are not among them, and the Outcome paragraph
("Neither is a silent weakening: both are refusals with a message, never a partial edit") is
false as written — R1 and R3 are partial edits with no message, R2 is a wrong edit with no
message.  §7's table-integrity claims and §1c's cost numbers are accurate (verified below).

### R5 — the shared file (INFO, risk REFUTED)

`rename/NewPipeline.scala` is the only non-`lsp/` source touched and the diff is 10 lines: a
doc comment, one defaulted `scope` field on `Read`, and passing `scope` at the single
construction site (`read`, line 175).  Everything in the brief's question checks out:

* the strict path *does* populate the field — `read` is shared — but `readModule` immediately
  destructures `(r.ps, r.module)` and drops `r`, so the `Read` (and the `scope` reference) is
  garbage before the loader ever sees it.  **Nothing is retained per module in batch memory**;
  the 129-module load carries no new live object.
* no new allocation either: `ModuleScope.importing` runs at line 143 exactly where it always
  did, and four of `Scope`'s five maps (`canonicalTerms`, `canonicalTypes`, `termOrigins`,
  `typeOrigins`) are *already* stored by identity in the `ErParseState` the strict path returns
  (lines 511–516).  The field adds a pointer to an object that was already reachable.
* per open document, `Resident.Checked` is transient (`Documents.Doc` stores text, version,
  `DocIndex`, cache — never `Checked`), and `DocIndex` keeps only `canonicalTerms` /
  `canonicalTypes`, **not** the session-wide `termNames` superset.  The genuinely new editor
  retention is `DocIndex.renamed` (a whole `Renamer.Result`) — bounded by file size, replaced
  wholesale on every `putIndex`, dropped on close.  No growth over an editing session.

Batch frozen, checked three ways: `git status tracker/repl-tests` empty after `repl-smoke.sh`;
`TestReplDifferential` green; corpus `--batch` verdicts identical (85/69/0 over 154).
`git diff --stat` and `git diff --stat -w` are byte-identical, so nothing was reformatted.

### R6 — the operator import-list gap (INFO, as stated)

Reproduced exactly.  `Ops.e` declares `infixl 5 <+>` and `(<+>) x y = …`; `OpsUse.e` does
`import Ops using (<+>)` and uses it.  References on `<+>` from any of the three positions →
`{Ops.e fixity line, Ops.e definition head, OpsUse.e use}`; the `import Ops using (<+>)` item is
absent, as §6.1 says.  Rename is refused from both the definition head and the fixity line with
the operator message (-32602), so the gap is references-completeness only, exactly as claimed.

## 2. What I checked that is RIGHT

Everything below was probed against a live server (scratch fixtures, `probe.py` …
`probe4.py`), not read off the source.

* **Multi-equation definitions are complete.**  `multi : Bool -> Bool` + two equations + a use:
  references returns all four heads from any of them; highlight marks the *last* equation
  `Write` (3) and the signature and first equation `Read` (2) — the stated cosmetic caveat, and
  nothing more; `rename multi → dual` edits all four.  The set is complete, so rename is
  complete.
* **A local shadowing a global of the same spelling: two keys, two sets, no bleed.**  `shadowed`
  as a top level and as a `let` binder inside another definition: the global set is
  `{sig, equation, the outer use}`, the local set is `{def-site, its use}`, and each renames
  independently and correctly.
* **`where` blocks and per-equation arguments.**  `x` in equation 1 and `x` in equation 2 are
  different binders with disjoint sets; a `where`-bound `helper` sees its use in the equation
  body and its own def-site, and nothing else.
* **Name extents are exact** for plain identifiers in every position the brief names —
  line-final (`9:2-9`), before `)` (`7:9-16`), before `,` (`10:9-16`), at a definition head.
  The `nameLen` fix does what it says (for non-literal names — see R2).
* **Alias imports are one set, and rename refuses them loudly.**  `import ChainA as CA` makes
  the mention `gadget_CA`; it lands in the *same* references set as `gadget` (origin-keyed, as
  designed), and `rename` is refused -32803 "mentioned under more than one spelling (gadget,
  gadget_CA)".  Refusal (v) is doing real work: `Layout/Report.e`'s header alone has six
  `… as …` import items.
* **Every Decision (d) refusal fires.**  Verified live, each with its own message: keyword
  (`f → let`, -32602); wrong case (`f → Color`, -32602); operator either way (-32602); a name
  already imported open from the stdlib (`f → not` with `import Bool`, -32803 "already in scope
  … (imported)"); a name already a top level (-32803); a name bound where the old one is used
  (-32803, with file:line); def-site not open (-32803); stale index (-32803, with the file
  name); `Ambiguous` (code path present, not reached by my fixtures).
* **Renames that SHOULD be allowed are allowed.**  A new name that occurs only inside a string
  and a comment (`f → zzz`) is renamed, and the string and comment are untouched.  A top level
  renamed to a name that is a local *elsewhere*, and a local renamed to a name a *nested*
  binder uses in a region where the old name does not occur, are both allowed and both
  semantically correct (I applied the edits and read the result).  `prepareRename` inside a
  string answers null.
* **Type and term namespaces stay apart.**  `data Color = Color Bool`: the type head and the
  constructor are two keys; renaming the type edits only `data Colour = Color Bool`, renaming
  the constructor only `data Color = Colr Bool`.
* **Coverage warning (Decision c).**  One `window/showMessage`, `type: 2`, per *request*, for a
  global references or rename request; wording names the count of open files searched
  ("references searched in 9 open files; unopened importers are not searched"); none for a
  local; none for highlight.  Confirmed live.  (Its wording is misleading in R1's situation —
  see R1.)
* **Table integrity (6.3.5) is real, not vacuous.**  Each of the five properties carries a
  floor assertion (`n >= 150`, `occs > 10000`, `bs > 3000`, `n > 5000`, `n > 1000`) that a
  planted vacuity would trip, and the failure messages name the offending file and position.
  The exclusions match `TestTolerantRead`'s exactly (`shouldfail`, `shouldfail-controls`,
  `incomplete`); `core/examples/Sample.e` is a long-standing known-bad file (explicit layout,
  `panic: trailing virtual semicolon` — `tracker/PERF-ROADMAP.md`, `tracker/LSP-ROADMAP.md`,
  `TestTolerantRead:182`) and it is *named* rather than dropped.  I independently counted the
  corpus: 161 stdlib + 92 examples = **253**, matching.  Caveat, already stated under R2: the
  overlap property re-implements `nameLen` inline instead of calling it, so it is blind to
  exactly the class of mis-measured extent that R2 is about.

## 3. Gates — re-run once

| gate | implementer | mine |
|---|---|---|
| `sbt core/compile core/copyResources` | green | green (tree already up to date; no recompile) |
| `sbt 'core/testOnly *TestLoopTrace'` | 720/720/720, hashdiff 0 eqdiff 0 nonpart 0 fuel 0 | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, rejected 36, fuel 0; 3 properties |
| `sbt 'core/testOnly *TestRenamer* *TestTolerantCheck *TestEditorBuffers* *TestTolerantRead *TestReplDifferential'` | 55/55 for the first three | **67 passed, 0 failed, 0 errors** — TestRenamer 23 + TestTolerantCheck 26 + TestEditorBuffers 6 = **55**, plus TestTolerantRead 11 and TestReplDifferential 1 |
| TestRenamer collected data | files 253 renamed 252 \| occurrences 71248 (ToBinder 31438) \| binders 16506 \| moduleTerms 3441 \| unparsed Sample.e | **identical, string for string** |
| `corpus-run.sh --batch` | 85 LOADED / 69 REJECTED / 0 UNKNOWN over 154 | **85 / 69 / 0 over 154** |
| `repl-smoke.sh` | 8 groups / 66 checks; goldens clean | **8 groups / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` **empty** |
| `lsp-smoke.sh` | 287 checks (237 + 50) | **287 checks, PASS** |
| the 50 new checks, by fixture | — | 3 in the `initialize` block; 47 over `tracker/lsp-tests/Refs.e` + `RefsSib.e` (references local ×4, highlight local, prepareRename local, references global ×5, highlight global ×2, coverage warning ×2, rename local end-to-end ×8 incl. re-check-clean and hover-unchanged, six refusals ×7, prepareRename null ×2, rename global across two buffers ×5, stale index ×3, two fixture-clean checks) |
| boot | `Loaded 129 modules (11.25 s)` | **129 modules in 11.7 s** |
| `Layout/Report.e` index build | 7980 occurrences; 30.0 / 10.2 / 7.5 ms | **7980 occurrences; 30.2 / 9.1 / 7.1 ms**; round trip 1.64 / 1.53 s warm |
| `.ei` | 0 outside `tracker/g1-*` | **0**, verified before the first run and after every one (143 remain under `tracker/g1-baseline/ei`, pre-existing) |
| line endings | `git diff --stat` == `git diff --stat -w` | **identical** |

On the cost pair: I reproduced the AFTER half only — the BEFORE half needs a second tree with
the timing line but without the 6.3 index, which I may not build.  What matters for the budget
is reproducible and reproduced: **7980 occurrences, 7–9 ms warm on the largest file in the
corpus**, an order of magnitude under the ~50 ms editor floor, with the check round trip at
1.5–1.6 s — inside its own run-to-run spread and dominated by the read half this item does not
touch.  The claimed +2…+7 ms delta is consistent with these absolutes and I have no reason to
doubt it.

Tiers not run, and I agree with the reasons: Tier 1 (no solver, no `Type.scala` constraint
construction, no executable Lean — the added `Read` field is a carried value); Tier 2 (`core/test`
in full — not an adoption commit, no default flips); no perf A/B (no inference and no check
added; the one check-path addition is measured above).  Per `tracker/GATE-POLICY.md` no gate was
triple-run.

## 4. What must change before this ticks

1. **R1** — canonicalise the global key across re-export hops, or refuse when an open document
   holds the old spelling under a different key.  Until then a rename of any name a
   `Prelude`-style module re-exports silently breaks its importers.
2. **R2** — make the literal-identifier form recoverable at index time (its own `NameForm`, or
   verify the spelling against the buffer text), and either measure it correctly or refuse it.
3. **R3** — version-check every open document before building the edit, not only the ones that
   already have a hit.
4. **R4** — bring §6 and the Outcome paragraph in line with whatever 1–3 settle on.

Everything else in the item — the index extension and its cost, the `nameLen` fix for ordinary
names, the set semantics for locals, globals, aliases, multi-equation groups, `where` blocks and
shadowing, the capture and case and operator and stale and ambiguity and unopened-def-site
refusals, the coverage warning, the corpus table-integrity properties, and the batch-inertness of
the one shared file — is sound and reproduced.

STOP after this report.

---

## Second pass — the fix round

Re-review of the R1–R4 fixes only, per the coordinator's brief.  Read: the rewritten §6 and the
new §§11–13 of `tracker/loopmodel/LSP3-6.3-REFS.md`; `lsp/References.scala`,
`lsp/Definitions.scala`, `lsp/Resident.scala`, `scalacheck-binding/.../TestRenamer.scala`,
`tracker/tools/lsp-client.py`; new fixtures `tracker/lsp-tests/Lit.e`, `RefsPre.e`.  Same rules
observed: nothing edited but my scratch dir and this file, one JVM at a time, no commits, `.ei`
0 outside `tracker/g1-*` at the end.

**VERDICT: ADVANCE.**  R1, R2 and R3 are closed — I re-ran all three of my own reproductions and
none reproduces — and I could not break any of the four ways the coordinator asked me to try to
break R1.  Two new items are worth recording, neither a blocker: a refusal-wording defect (S4,
LOW) and the tab/position-model bug the fix round surfaced, which I agree deserves its own
ticket rather than being 6.3's to fix (S5).

### Second-pass findings

| id | severity | status | one line |
|---|---|---|---|
| **S1** | — | **R1 CLOSED** | Keys canonicalise correctly through one hop, two hops, a type re-export and a multi-ancestor entry; my stdlib reproduction now answers one set from both ends and renames both files from either end. |
| **S2** | — | **R2 CLOSED** | A backticked, tab-located or parenthesised name cannot reach an edit — `prepareRename` null, `rename` -32803 — and references/highlight now measure the backticked token exactly; the 39/6/306 classification cross-checks against the source. |
| **S3** | — | **R3 CLOSED** | My debounce reproduction now refuses and names the stale sibling; after the check the same rename succeeds and edits the sibling's newly typed mention. |
| **S4** | LOW | NEW | Two refusal messages mislead: the belt says "rename it from there" when renaming from there is refused symmetrically, and an unjoined key is refused "defined in a file that is not open" when the defining file IS open. Cosmetic — no wrong edit either way. |
| **S5** | INFO | NEW — own ticket | Tab-expanded parser columns are wrong LSP units in BOTH directions for the whole position model — diagnostics, definition, hover, references, highlight and the hit-test — pre-existing since 0.5, and the same conversion point as LSP's UTF-16 counting. |
| **S6** | INFO | ACCEPTED | The belt over-refuses by design: two open modules that both define a spelling refuse each other's rename in both directions. Loud, actionable, and stated in §6.8. |

#### S1 — R1, re-broken four ways and it held

* **The original stdlib reproduction, both directions.**  `core/.../Bool.e` plus a buffer doing
  `import Prelude` / `flipped = not True`, both open and clean.  References from the importer
  and from `Bool.e` now return **the same four locations** (`Bool.e:19,20,21` + the importer's
  use).  `rename not → nope` from **either** end returns **the same edit set** — 3 edits in
  `Bool.e`, 1 in the importer.  The "defined in a file that is not open" refusal from the
  importer is gone.  Round 1's silent breakage does not reproduce.
* **Two hops.**  `ChainA` defines `gadget`; `ChainB` re-exports it; `ChainD` re-exports
  `ChainB`'s; `ChainE` imports `ChainD`'s and uses it.  All four open.  One key at every level:
  references from `ChainA`'s def-site and from `ChainE`'s use return **the same six locations**
  (both equation/sig heads, both `export … using` items, `ChainE`'s import item and its use),
  and rename from either end edits **all four files**.  The fixpoint chase does what it says.
* **A type re-export through `consOrigins`.**  `TyA` declares `data Widget = W Bool`; `TyB` does
  `export TyA using type Widget; W`; `TyC` imports and uses both.  `Widget` is one key across
  three files (5 locations, both re-export items included) and renames all of them; the
  constructor `W` is its own key and renames its own four sites.  The term and type namespaces
  stay apart while both canonicalise.
* **A multi-ancestor origin entry** — the branch the canon deliberately stops at.  Built it:
  `ChainA` and `ChainA2` both define `gadget`, `MultiQ` re-exports both, `MultiUse` imports
  `MultiQ`'s.  As designed the three sets do **not** join, and the failure mode is a **refusal,
  not an edit**: from `ChainA` the belt refuses, naming `ChainA2.gadget`; from `MultiUse` the
  def-site check refuses.  This is the case the belt exists for and it earns its keep.
* **The belt on a genuine same-spelling clash.**  A module with `import Bool hiding not` and its
  own `not`, open beside `Bool.e`: renaming either `not` is refused, each naming the other
  definition.  Correct in the sense that matters — no silent cross-edit — at the cost recorded
  as S6.

#### S2 — R2, and what the classification says

`Definitions.nameExtent` measures against the source and returns `(length, exact)`; `exact`
additionally requires that no tab lies to the left of the position on that line.  Verified live:

* `` ``wide`` `` — references and highlight now cover the **whole eight-character token**
  (`4:0-8`, `6:10-18`), which is right and is an improvement on round 1 *and* on 6.2;
  `prepareRename` → **null**; `rename` → **-32803** "the source writes it in a form that is not
  its spelling".  Round 1's `narrowde``` corruption cannot be produced.
* a name behind a **tab** (`\tgo = True`) — `prepareRename` → null, `rename` → -32803.  Cannot
  reach an edit.
* a **parenthesised** operator head `(<+>)` — `prepareRename` → null (rename already refused
  operators).
* the ordinary case — every plain identifier probe from the first pass still measures exactly,
  including line-final, before `)` and before `,`.

The corpus classification `71248 = 70897 exact + 39 backticked + 306 parenthesised + 6 behind a
tab + 0 other` reproduces verbatim, and I cross-checked two of the classes against the source
independently: `grep -ro '``[^`]*``'` over the corpus returns **exactly 39**, and the only
tab-bearing file is `core/examples/GridExample.e` with three tab-indented (CRLF) lines carrying
six name occurrences.  The "0 other" residue is the part that matters going forward — a new
surface form shows up there rather than in a corrupted rename.  The overlap property now calls
`nameExtent` instead of restating it, which was round 1's specific criticism.

#### S4 — two refusal messages mislead (LOW, NEW)

The belt's message ends "— rename it from there, or close that buffer", but the refusal is
**symmetric**: renaming from the other buffer is refused too, naming this one.  The user is sent
somewhere that will refuse them the same way; the only advice that works is the second half
(close the buffer).  Separately, when a key joins nothing — the multi-ancestor case — rename is
refused "cannot rename a name defined in a file that is not open" although the defining file *is*
open, and the references answer for that very position includes the definition's location.  Both
are wording, not behaviour: no wrong edit is produced either way.  Worth a sentence each.

#### S5 — the tab finding: scope, and yes it deserves its own ticket (INFO, NEW)

The fix round is right that this is not 6.3's bug, and it is bigger than the report states.  A
parser column is tab-expanded to eight-column stops (`scalaparsers.Pos.bump`); the LSP counts
characters.  The server converts between them by `± 1` and nothing else, in **both** directions
and in **every** feature:

* `Diagnostics` builds ranges as `0 max (sp.startCol - 1)` — so a **squiggle on a tab-indented
  line lands in the wrong place**;
* `Definitions.location` builds go-to-definition targets the same way;
* `Definitions.hit` and `References.siteAt` convert the *editor's* character column back with
  `chr + 1` — so on a tabbed line **clicking the name misses it**.  I saw exactly this: on
  `\tgo = True`, a request at the real character column (1) answered nothing, and one at the
  parser column (8) answered the name — with a range pointing at characters 7–9 of a 10-character
  line.

So on any tab-indented line, hover, go-to-definition, references, highlight and diagnostics are
all silently off, and 6.3's contribution is to be the first feature that **refuses** rather than
mis-edits.  Exposure in the corpus is tiny (1 file, 6 occurrences, and the standing gates never
noticed); exposure in a user's tab-indented file is every request on that line.

Ticket-worthy, small, and it should be scoped as **one bidirectional conversion** — parser column
↔ LSP character index — built over `Definitions.Lines`, which the fix round has now written and
which already knows which lines are tabbed.  It should be taken together with the LSP's
UTF-16-code-unit rule, which is the same conversion point and the same class of bug for any
non-BMP character.  Until it lands, 6.3's "never rename a name behind a tab" is the right local
mitigation and should stay.

### Second-pass gates

| gate | implementer | mine |
|---|---|---|
| `sbt core/compile core/copyResources` | green | green (tree already built) |
| the five suites | 68/68 | **68 passed, 0 failed, 0 errors** (TestRenamer **24**, TestTolerantCheck 26, TestEditorBuffers 6, TestTolerantRead 11, TestReplDifferential 1) |
| TestRenamer collected data | 253/252, 71248 occs, 31438 ToBinder, 16506 binders, 3441 moduleTerms, unparsed Sample.e | **identical** |
| extent classification | 70897 / 39 / 306 / 6 / 0 | **71248 = 70897 exact + 39 backticked + 306 parenthesised + 6 behind a tab + 0 other**, and 39 / 6 cross-checked against the source by grep |
| `lsp-smoke.sh` | 306 | **306 checks, PASS** — R1 pinned both directions, R2 pinned (whole-token references, null prepare, refused rename), R3 pinned incl. "a local rename is not blocked by a stale sibling" |
| `repl-smoke.sh` | goldens clean | **8 groups / 66 checks**; `git status tracker/repl-tests` **empty** |
| `TestLoopTrace` (not re-run by the implementer; run to be safe) | — | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, fuel 0 |
| corpus `--batch` | not re-run (lsp/ + TestRenamer only) | skipped per the coordinator; `NewPipeline.scala` is unchanged since the first pass, where it was 85/69/0 over 154 |
| boot | 129 | **129 modules in 11.9 s** |
| `.ei` | 0 | **0** outside `tracker/g1-*` after every run |

### What I would still record, but not hold the item for

1. **S4** — reword the two refusals (one sentence each).
2. **S5** — open a position-model ticket (tab expansion + UTF-16), and keep 6.3's tab refusal
   until it lands.
3. **S6** — the belt's over-refusal is a real usability cost that will be felt the moment two
   open buffers share a top-level spelling; if it bites, the narrower rule is "refuse only when
   the other key's occurrences are in a buffer this edit would touch".

Everything the first pass flagged as sound remains sound and re-ran green.  6.3 ADVANCES.

STOP after this report.
