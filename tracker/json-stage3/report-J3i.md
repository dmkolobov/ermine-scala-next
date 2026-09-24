# J3i: the crosstab, and the Fetch widget shape (branch `json-crosstab`, worktree `ermine-scala-wt-json-unify`)

Base `json-encode` 22b99671. Nothing committed; the tree is dirty for review.

`Layout.Widgets.Crosstab` is the widget a query cannot produce: a relation's row type is fixed at
compile time, so a table whose COLUMNS are the distinct values of a data column has to be built
from rows read while the report runs. `crosstabOf` scans, sorts both axes, sums the measure per
(row key, column key) pair and sends a MATRIX -- `cells : List (List (Maybe Double))`, where a pair
no row had is `Nothing` and goes on the wire as `null`. Both scanning widgets now have the same
shape: a wire props record, a server-side SOURCE record, and one function between them, so
`headlineOf` takes a `HeadlineSource` instead of four positional arguments (its wire props are
unchanged). Gates: `scripts/gate.sh run commit` 3/3 PASS, the five suites 117/117, `TestTolerantCheck`
57/57 after the 6.2c catalogue update, the client 62 passed / 3 skipped / 0 failed and
`check-generated` up to date.

## What was built

| File | What |
|---|---|
| `core/src/main/resources/modules/Layout/Widgets/Crosstab.e` (new) | `CrosstabProps` (title, the two axis headings, two sorted distinct label lists, `cells` row-major, `rowTotals`/`colTotals`/`grandTotal`, `crosstabFormat`), `crosstab : CrosstabProps -> Node`, `CrosstabSource h1 h2 h3 rel r`, and `crosstabOf : (Relational rel, r <- (h1, h2, h3, t)) => CrosstabSource h1 h2 h3 rel r -> Fetch Node`, plus the two helpers it needs (`keyOrd`, `sumsBy`). |
| `core/src/main/resources/modules/Layout/Widgets.e` | `export Layout.Widgets.Crosstab`; `"crosstab"` in `widgetNames`; a header paragraph on the TWO SHAPES (one record and a constructor, or two records and a `...Of` that scans) and on why a name two widget modules both want is prefixed. |
| `core/src/main/resources/modules/Layout/Widgets/Headline.e` | `HeadlineSource h rel r` added; `headlineOf` takes it. `HeadlineProps`, `headline` and the wire are untouched. Header comment rewritten around the two-record shape. |
| `core/src/test/resources/doc/FetchCrosstab.e` (new) | Regions x months over `FetchData.sales`: a month dimension joined in SQL, a parameter choosing `amount` or `units` as the measure, the crosstab and a `headlineOf` over the same relation in one `vflowF`. |
| `core/src/test/resources/doc/FetchHeadline.e`, `FetchFragments.e` | the one `headlineOf` call in each takes a `HeadlineSource`. |
| `client/src/widgets/crosstab.ts` (new), `src/props.ts`, `src/index.ts`, `scripts/generate.sh`, `src/generated/{crosstab.ts,index.ts}` | the three-edit recipe: the generate spec + the `WIDGET_PROP_SCHEMAS` line, the props interface, the component (a `<table>`: the column labels as the header row, the row labels as the first column, `rowHeader`/`colHeader` in the corner cell, every number through `crosstabFormat`, an em dash for a `null` cell, a totals column and a totals row), one `defaultRegistry()` line. |
| `client/test/{widgets,props}.test.ts` | `(w-crosstab)` renders a 2x3 matrix with one gap and checks the header row, the row labels, the formatted cells, the em dash and the totals; `(w-crosstab-empty)` the empty scan; `(p-crosstab)` pins the generated schema's keys and that a cell is a number OR null; `(p-registry)` now lists `crosstab`. |
| `scalacheck-binding/src/main/scala/TestRunner.scala` | `(fxc-1)` (30 generated crosstabs against a Scala oracle) and `(fx6)` (the example); `rgCat` added to the generated `RgFields`; `Layout.Widgets.Crosstab` in `fetchImports`; `(fxl-headline)` updated for `HeadlineSource`. |
| `scalacheck-binding/src/main/scala/TestWidgets.scala` | `crosstabSrc` in the widget pool, `Layout.Widgets.Crosstab` in `imps` and in the exported-schema map, `widget-crosstab` and the two crosstab shapes required by `(a-cov)`, and `(a-pin5)` for the wire spelling including a `null` cell. |
| `scalacheck-binding/src/main/scala/TestTolerantCheck.scala` | the 6.2c `knownHeadDisagreements` catalogue: `Headline.e:63:9` -> `78:9` and the eight `Crosstab.e:108-115:9` local heads (see Gates). |
| `tracker/JSON-API-DESIGN.md` | section 3.4c gains "The Fetch widget shape" (source record -> `...Of` -> props record, server-side by design) and the crosstab as the case a query cannot cover; the `a widget that scans` row now names `HeadlineSource`. |
| `tracker/JSON-STAGE3-PLAN.md` | the J3i row and a handoff-log entry. |
| `client/README.md` | crosstab in the files table and in the reserved names; three native widgets; "Adding a widget" gains the two-record shape and the field-name rule. |

## Decisions the brief did not fix

| Decision | Choice and why |
|---|---|
| the kind and row-constraint spelling of `CrosstabSource` | THE BRIEF'S SPELLING WORKS UNCHANGED. `data CrosstabSource h1 h2 h3 rel r = CrosstabSource { .., source : rel r }` kind-checks with no annotation: `bin/ermine :type crosstabOf` answers `forall (h1: rho) (h2: rho) (h3: rho) (rel: rho -> *) (r: rho). (r <- (h1, h2, h3, t), Relational rel) => CrosstabSource h1 h2 h3 rel r -> Fetch Node`, so a higher-kinded field is fine and the four-way `r <- (h1, h2, h3, t)` entails the three `getF`s (the same n-ary spelling `Relation.joinBy'` uses). No fallback to `[..r]` was needed. |
| how a `Maybe` inside a LIST goes on the wire | as `null`, in place, and the key is NOT dropped. The encoder's omit-the-key rule reads the DECLARED type of a named FIELD (`Encode.isMaybe`, `json/Encode.scala`); inside an array there is no key, and the walker's `Nothing` case is `Leaf(b.nul)`. Confirmed three ways: a real render (`{"cells":[[null,75.5,4100.0],..]}`, `bin/ermine-serve`), the exported zod (`cells: z.array(z.array(z.number().nullable()))`, `bin/ermine-schema --zod`), and `TestWidgets (a-pin5)`, which pins the whole document byte for byte. `(p-crosstab)` pins the client half: no key of `CrosstabProps` is optional. |
| `crosstabRowLabels` / `crosstabColLabels`, not `rowLabels` / `colLabels` | VERIFIED CLASH, not a guess: with the field named `rowLabels`, a probe module that does `import Layout.Widgets` and applies `rowLabels` to a `StyleBoxProps` fails with `failed to unify type CrosstabProps with type (StyleBoxProps r)` (`bin/ermine :load`). `Layout.Widgets.StyleBox` owns `rowLabels`. `colLabels` was free, but a pair whose halves are spelt differently reads worse than a pair that is both prefixed. `cells`, `rowHeader`, `colHeader`, `rowTotals`, `colTotals`, `grandTotal`, `crosstabTitle`, `crosstabFormat` are free and are spelt plainly. |
| the source records' field names | a field two widget modules both want is prefixed, the others are not. `CrosstabSource` and `HeadlineSource` both want a title, a measure and a relation, so those are `crosstabSourceTitle`/`crosstabMeasure`/`crosstabSource` and `headlineSourceTitle`/`headlineMeasure`/`headlineSource`; `rowKey`, `colKey`, `rowKeyHeader`, `colKeyHeader` and `sourceFormat` are only this module's and are plain. `HeadlineSource` could not reuse `scope` at all -- `HeadlineProps` owns it in the SAME module -- hence `headlineScope`. The rule is stated in both module headers, in `Layout/Widgets.e` and in `client/README.md`. |
| where the format lives | in the SOURCE (`sourceFormat : CellFormat`), so `crosstabOf` has no fixed `Default`. The brief left the call to me; the crosstab shows money and the example wants `Currency` for amounts and `IntegralRound` for units, and a source record makes the argument free. The headline keeps its `Default` (its brief fixed that, and its source record has no format field). |
| the totals | BUILT: `rowTotals`, `colTotals` (one `Double` per label) and `grandTotal`. They are `Maybe`-free because a label that exists has at least one row; they cost one more `sumsBy` per axis over rows already in hand, and the client renders them as a last column and a `<tfoot>` row. |
| how the sums are computed | one `Map` per axis plus one over the pairs, built with `foldMap` over `Map.valueMonoid` (`unionWith (+)`), and `Map.lookup` IS the `Maybe Double` a cell wants -- an absent key is exactly "no row had this pair". The obvious alternative (filter the rows once per cell) is O(rows x labels x labels). `keyOrd` is `mappend ordMonoid (contramap fst primOrd) (contramap snd primOrd)`. |
| keys are `String` | as the brief says, and the module comment says why it is not a limitation: the caller projects an `Int` or `Date` key first, and in doing so CHOOSES the spelling the axis sorts by. `FetchCrosstab.e` labels its months `"2026-01"` rather than `"Jan"` for exactly that reason, and says so. |
| how a test writes an EMPTY literal relation | `relationWithHeader {rgName, rgCat, rgAmount} []`. `relation []` (`mkRelation#` of no rows) has no header -- "an empty relation built from no rows carries no columns" -- so `(fxc-1)`'s empty case cannot use the shape every other generated relation uses. That is why the generated crosstab modules get two imports (`Relation`, `Relation.Row`) on top of `fetchImports` rather than changing `fetchImports` for every other (fxl) property. |
| `(fx6)` | ADDED, though the brief only asked for the example. `(fx1)`-`(fx5)` pin one example each; `FetchCrosstab` is the only example of the widget and its numbers are the whole point, so it gets the same treatment (both parameter arms, the gaps, the collision, the totals, and the headline beside it). |
| the client's empty case | when either axis is empty the component still emits the table (headers and the totals row) and adds a `p.ermine-crosstab-no-rows` saying "no rows", the way `scorecard.ts` does. `(w-crosstab-empty)` pins it. |

## Departures from the brief

| Brief | What was done | Why |
|---|---|---|
| `CrosstabProps { .., rowLabels, colLabels, .. }` | `crosstabRowLabels`, `crosstabColLabels` | the verified clash above, which the brief's own rule ("`columns`, `rows`, `title`, `count`, `descending`, `format` are known to be taken; rename rather than fight") covers. Everything downstream (zod, `props.ts`, the component, the tests) follows. |
| `HeadlineSource { sourceTitle, scope, measure, source }` | `headlineSourceTitle`, `headlineScope`, `headlineMeasure`, `headlineSource` | `scope` is `HeadlineProps`' own field in the same module, and the other three would have clashed with `CrosstabSource`'s. |
| "Add the crosstab as a fourth fragment of `FetchFragments.e` if it fits in a line or two" | NOT added | it does not fit: `sales.day` is a `Date`, so a crosstab over it needs the month dimension and the join that `FetchCrosstab.e` spends six lines on. `FetchFragments` keeps its three fragments. |
| "a parameter choosing `amount` or `units` as the measure" | the parameter chooses a RELATION whose measure column is named `measure`, not a `Field` | two `Field`s of different columns have different row types, so they cannot be the two arms of one `if`. `measured q` renames `amount` to `measure`, or combines `fromNumericOp (col units)` into it (`units` is an `Int`; the cast happens in SQL, and the units arm of `(fx6)` is the evidence it works there). |

## Anti-vacuity

`(fxc-1)` prints its distribution once and asserts it. Last green run: `30 crosstabs; 3 empty, 16
with a gap, 21 with a collision; rows per case 0x3 1x5 2x1 3x2 4x3 5x3 6x4 7x2 8x4 9x3`
(`tracker/json-stage3/logs/j3i-suites-1.log:455`). The property requires at least one empty
relation, at least 5 cases with a pair no row has (or the `null` cell would never be produced) and
at least 5 with two rows on one pair (or the summing would never be exercised). The keys are drawn
from a three-letter and a two-letter alphabet over up to nine rows, which is what makes both
common. `TestWidgets (a-cov)` requires both `crosstab-gap` and `crosstab-full` over its 200 fixed
cases, so the generated documents cover the `null` arm as well.

TWO MUTATION RUNS, both on `Layout/Widgets/Crosstab.e`, both reverted (`diff` against the saved
original is empty and `core/copyResources` was re-run, so `target/` holds the stage's module again):

| Mutation | Result | Log |
|---|---|---|
| M1: an absent pair reads 0.0 -- `Just (lookupOr_M 0.0 (rl, cl) cellSums)` for `lookup_M (rl, cl) cellSums` | `Failed: Total 34, Failed 2, Errors 0, Passed 32`; only `(fxc-1)` (`16 of 30 wrong`, e.g. `cells [[7205.25,5471.75],[1153.875,5141.375],[0.0,12238.875]] for List(.., List(None, Some(12238.875)))`) and `(fx6)` (`Expected .. List(None, Some(75.5), Some(4100.0)) .. but got .. Some(0.0)`) | `tracker/json-stage3/logs/j3i-mutation-M1.log:15,54,67` |
| M2: the axes keep first-appearance order -- `distinct primOrd ..` without `sort primOrd` | `Failed: Total 34, Failed 2, Errors 0, Passed 32`; only `(fxc-1)` (`20 of 30 wrong`, `row labels List(cy, bob, ann) for List(ann, bob, cy)`) and `(fx6)` | `tracker/json-stage3/logs/j3i-mutation-M2.log:57,60,71` |

Both mutations leave the other 32 properties of `TestRunner` green, which is the evidence that
`(fxc-1)` and `(fx6)` are what sees them.

## Gates

| Gate | Result | Log |
|---|---|---|
| `scripts/gate.sh run commit` (key `f453608a580054cff68f3203ba89ff6cc4b71920`, the final content) | `compile PASS 7s compiled`; `corpus PASS 52s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected`; `lsp PASS 51s PASS lsp (582 checks)` | `tracker/json-stage3/logs/j3i-gate-commit-2.log`; `.result` files under `/home/dmitry/research/ermine/ermine-scala/.gate-cache/f453608a580054cff68f3203ba89ff6cc4b71920/` |
| the same gate on the earlier content (key `4fb30ef57c1a8c5e9889603bcdf065087751db4e`, before the 6.2c catalogue entry and the docs) | `compile PASS 6s`; `corpus PASS 63s` (same counts); `lsp PASS 68s` (582 checks) | `tracker/json-stage3/logs/j3i-gate-commit.log` |
| `sbt -batch 'core/testOnly *TestRunner *TestWidgets *TestDoc *TestJson *TestSchema'` | `Passed: Total 117, Failed 0, Errors 0, Passed 117`, 78 s (J3h's final was 114; the three new ones are `(fxc-1)`, `(fx6)`, `(a-pin5)`) | `tracker/json-stage3/logs/j3i-suites-1.log:489` |
| `sbt -batch 'core/testOnly *TestTolerantCheck'`, BEFORE the catalogue update | `Failed: Total 57, Failed 1, Errors 0, Passed 56`; `head disagreement set moved: new Crosstab.e:108:9 .. Crosstab.e:115:9, Headline.e:78:9; gone Headline.e:63:9` | `tracker/json-stage3/logs/j3i-tolerant-1.log:102-103` |
| `sbt -batch 'core/testOnly *TestTolerantCheck'`, after | `Passed: Total 57, Failed 0, Errors 0, Passed 57`, 422 s | `tracker/json-stage3/logs/j3i-tolerant-2.log:102` |
| `cd client && npm test` | `tests 65, pass 62, fail 0, skipped 3` (the three skips are the corpus / end-to-end fixtures the Scala side writes; they skip on the base too) | `tracker/json-stage3/logs/j3i-client-2.log:76-81` (and `j3i-client-1.log`, the same counts before the README edit) |
| `cd client && npm run check-generated` | `check-generated: src/generated is up to date` | `tracker/json-stage3/logs/j3i-client-2.log` (tail) |
| `sbt -batch core/compile core/copyResources`, `core/Test/compile` | `[success]` both | `tracker/json-stage3/logs/j3i-compile-1.log`, `j3i-testcompile-1.log` |

The full `core/test` was NOT run (the brief forbids it). `tracker/repl-classpath.txt` is untouched
(`gate.sh` swaps and restores it). The gate key is the tree SHA including untracked files, so the
final run's key names the tree as it stood before this report file was given its last two rows;
nothing else changed after it.

## The 6.2c catalogue (as commit b1226e9c did)

The pr-tier sweep pins the SET of local binding heads whose hover changes in content, and a new
stdlib module with a `let` under a row constraint moves it. Nine entries moved: the eight `let`
bindings of `crosstabOf` (`Crosstab.e:108:9` .. `115:9` -- `rk`, `ck`, `mv`, `rls`, `cls`,
`cellSums`, `rowSums`, `colSums`, every one under `r <- (h1, h2, h3, t)`) are new, and
`Headline.e:63:9` became `78:9` because `HeadlineSource`'s declaration sits above the `let`. None of
them is in `knownHeadShown`, so no hover the user sees changed. The comment in
`TestTolerantCheck.scala` says all of that.

## Open issues

- **The 2.11 port.** Nothing was ported. The only Scala touched is test code, and it is in the
  shared dialect (no `given`, no `Either#map`, no JDK 9+ API, `.right`/`.left` where either is
  used). `Map.valueMonoid`, `List.foldMap`, `List.Util.sort`/`distinct` and `Ord.ordMonoid` are all
  pre-existing stdlib, so the Ermine side should port by copy.
- **A crosstab scans its own relation.** `FetchCrosstab.e` reads `measured q` twice -- once in the
  crosstab, once in the headline beside it -- which is the documented cost of a widget that owns its
  scan (design note 3.4c). Nothing shares a scan between two `Fetch` values.
- **Nothing caps the matrix.** A crosstab over a high-cardinality key builds
  `rowLabels x colLabels` cells in the JVM and puts them all in the response. That is the same
  open ticket as J3h's "a cap on fetched rows", one level up: the fix needs a way for the report to
  say what to do when it hits a cap, not just a number.
- **A cell is a `Double`.** A count, a string or a date in a cell would need another props type or a
  sum type on the wire; `crosstabOf` sums, so its measure is numeric by construction. A caller who
  wants counts projects a 1.0 column.
- **`Layout.Widgets` now re-exports `sumsBy`, `keyOrd` and the two source types.** They are ordinary
  global names once a module imports `Layout.Widgets`; nothing in the stdlib or the corpus clashes
  today (the corpus gate is green), but a widget module's helpers are part of that namespace and
  should be named as if they were.
- **The client corpus fixtures were not regenerated**, so `client/test/corpus.test.ts` and
  `endtoend.test.ts` still skip (3 of 65). They would now include crosstabs, and the dispatcher has
  the schema and the renderer, but that path is UNVERIFIED in this stage;
  `client/scripts/check-corpus.sh` would verify it.

## Fixes 1 and 2 applied (review R1 and R2, 2026-09-18)

Both required fixes are in. Nothing else changed: no client file, no Ermine example, no wire.

### Fix 1 (R1): `sumsBy` folds strictly

| Change | File |
|---|---|
| `sumsBy o key val xs = foldl (acc x -> unionWith_M (+) acc (fromAssocList_M o [(key x, val x)])) (empty_M o) xs` -- the reviewer's verified one-liner -- and `foldl` for `foldMap` in the `List` import (now unused) | `core/src/main/resources/modules/Layout/Widgets/Crosstab.e` |
| the `sumsBy` doc comment says why: `foldMap` is `foldr`, whose stack grows with the ROWS | same |
| `(fxc-2)`: one `crosstabOf` over a 20,000-row relation built in Ermine (`map_List .. (take 20000 (from 0))`), asserting `cells == [[20000.0]]` and `grandTotal == 20000.0` | `scalacheck-binding/src/main/scala/TestRunner.scala` |

Evidence that `(fxc-2)` is not vacuous -- it is RED on the pre-fix fold IN THE TEST HARNESS, not
only through the server: mutation M6 put `sumsBy` back to `foldMap` (the two lines above, nothing
else) and ran `core/testOnly *TestRunner`: `Failed: Total 35, Failed 1, Errors 0, Passed 34`, the
one red being `(fxc-2)` with `status 500 over 20000 rows: {"error":{"path":"$.props","message":
"RgXtBig43.report produced a document that cannot be encoded: ... cannot encode $.cells[0][0]: the
value is an error: infinite loop detected"}}`
(`tracker/json-stage3/logs/j3i-r-mutation-foldr.log:54-56,83`). M6 was reverted (`diff` against the
saved copy empty), `core/copyResources` re-run, and `target/`'s copy diffed against the source: identical.

### Fix 2 (R2): the case-insensitive merge, documented and tested

| Change | File |
|---|---|
| a CASE paragraph in the header: `primOrd` compares strings lower-cased while Ermine's `==` and a SQL `GROUP BY` do not, so `"North"` and `"north"` are ONE label whose cells and totals add both rows, both axes sort case-insensitively, and the surviving SPELLING is the one the scan met first -- a relation is a SET of rows, so it is not the report's to choose; fold the case in the projection to be rid of the question | `core/src/main/resources/modules/Layout/Widgets/Crosstab.e` |
| `(fxc-1)`'s alphabets hold a pair differing only by case (`"ann"`/`"Ann"`, `"x"`/`"X"`); the oracle groups rows, cells and totals by LOWER CASE; a new anti-vacuity conjunct requires >= 5 cases with two spellings of one key, and the printed distribution counts them | `scalacheck-binding/src/main/scala/TestRunner.scala` |

Evidence, in order:

| Run | Result | Log |
|---|---|---|
| the mixed-case alphabets against the OLD case-sensitive oracle (`.distinct.sorted`) -- the property must be red before the oracle is changed | `Failed: Total 35, Failed 1, Errors 0, Passed 34`; `(fxc-1)` `19 of 30 wrong`, e.g. `row labels List(ann, bob, cy) for List(Ann, ann, bob, cy)` -- Ermine returned one label where the case-sensitive oracle wanted two. `(fxc-2)` green in the same run | `tracker/json-stage3/logs/j3i-r-case-red.log:131-134,142` (and `:100`) |
| the review's exact wording for the new oracle -- "the label is the FIRST SPELLING IN ROW ORDER" -- tried and FALSIFIED | `Failed: Total 35, Failed 1, Errors 0, Passed 34`; `13 of 30 wrong`, e.g. `row labels List(ann, bob, cy) for keys List(ann, bob, cy) of List(bob, bob, Ann, ann, ann, cy)` and, the other way, `List(Ann, bob, cy) ... of List(ann, Ann, cy, bob, cy, cy, Ann, bob)`. The spelling that survives is the one the SCAN met first, and a relation is a set of rows, so the generator's row order does not decide it | `tracker/json-stage3/logs/j3i-r-oracle-firstspelling-red.log:114-117,126` (variant reverted, `diff` empty) |
| the oracle as it now stands: the labels' LOWER-CASED forms are the sorted distinct keys, each label is a spelling the data had, and every cell, row total and column total is the sum of the rows matched case-insensitively | green (below) | -- |

That is the one DEPARTURE from the review's wording for Fix 2, and the run above is why: pinning
which spelling wins would pin an order the algebra does not promise. The module comment says the
same thing, so the documented semantics and the property agree.

### 6.2c catalogue: the let heads DID move

The CASE paragraph is eleven lines of module header above `crosstabOf`, so the eight local heads
moved from `Crosstab.e:108:9`..`115:9` to `119:9`..`126:9` (`Headline.e:78:9` did not move --
`Headline.e` is untouched by these fixes). `knownHeadDisagreements` was updated to the new lines with
a one-line note, and `TestTolerantCheck` was re-run once for that reason: `Passed: Total 57, Failed 0,
Errors 0, Passed 57` (`tracker/json-stage3/logs/j3i-tolerant-r.log:102`), the printed 6.2c set naming
`Crosstab.e:119:9 .. 126:9` (`:98`).

### Gates after the fixes

| Gate | Result | Log |
|---|---|---|
| `bin/ermine :load core/src/main/resources/modules/Layout/Widgets/Crosstab.e` + `:type crosstabOf` | imported, and the type is unchanged: `forall (h1: rho) (h2: rho) (h3: rho) (rel: rho -> *) (r: rho). (r <- (h1, h2, h3, t), Relational rel) => CrosstabSource h1 h2 h3 rel r -> Fetch Node` | REPL (quoted here) |
| `sbt -batch 'core/testOnly *TestRunner *TestWidgets'` | `Passed: Total 42, Failed 0, Errors 0, Passed 42`; `(fxc-2)` at `:92`, `(fxc-1)` at `:124`, its distribution `30 crosstabs; 3 empty, 16 with a gap, 20 with a collision, 19 with two spellings of one key` at `:123` | `tracker/json-stage3/logs/j3i-suites-r.log:131` |
| `sbt -batch 'core/testOnly *TestTolerantCheck'` | `Passed: Total 57, Failed 0, Errors 0, Passed 57` | `tracker/json-stage3/logs/j3i-tolerant-r.log:102` |
| `scripts/gate.sh run commit` (key `ae59a68c86ac237db47d9e22ec7b9ab9fca74958`) | `compile PASS 6s compiled`; `corpus PASS 49s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected`; `lsp PASS 52s PASS lsp (582 checks)` | `tracker/json-stage3/logs/j3i-gate-r.log` |
| `sbt -batch core/Test/compile` after reverting the oracle variant | `[success]`, 12 s | `tracker/json-stage3/logs/j3i-r-testcompile.log` |

The client was NOT re-run: no client file changed in either fix (its green is
`tracker/json-stage3/logs/j3i-client-2.log`, 65 tests / 62 pass / 3 skipped, `check-generated` up to
date). `TestDoc`, `TestJson` and `TestSchema` were not re-run either -- nothing they cover changed
(their green is `j3i-suites-1.log`). The gate key is the tree SHA including untracked files, so it
moves with every log file written after the run; the CODE at that key is the code as it stands.

### New open ticket

**A case-sensitive `Ord String`** (review R2, recorded in the plan's J3i entry): `primOrd` compares
strings lower-cased (`PrimExpr.scala:641` through `primLt#`), so every stdlib `distinct`/`sort` over
String keys -- the crosstab's axes included -- merges keys that differ only by case, while Ermine's
`==` and a SQL `GROUP BY` keep them apart. The stdlib has no case-sensitive `Ord String`, adding one
is a `Lib.scala` change shared with the 2.11 branch, and whether `primOrd` should ignore case at all
is a language question for the user. The crosstab documents and tests the behaviour it has.
