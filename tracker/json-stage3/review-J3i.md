# Review of J3i: the crosstab and the Fetch widget shape (branch `json-crosstab`, worktree `ermine-scala-wt-json-unify`)

Reviewed: the uncommitted diff against `json-encode` 3cae9678 plus the untracked files
(`Crosstab.e`, `FetchCrosstab.e`, `client/src/widgets/crosstab.ts`, `client/src/generated/crosstab.ts`).
Independent reviewer; nothing of the stage was edited except two mutations and one fix probe, each
reverted and verified byte-identical (`review-j3i-mutations.log`, `review-j3i-foldl-probe.log`:
`FINAL-IDENTICAL`; `core/copyResources` re-run, `target/` copy identical). Every log named below is
under `tracker/json-stage3/logs/`.

## Verdict in one paragraph

The stage is what the brief asked for and the tests it ships are real: my own mutations (a swap of
the two totals lists, a collision that keeps the last value instead of adding) each go red in exactly
`(fxc-1)` and `(fx6)` with the other 32 `TestRunner` properties green, the duplicate-key row
constraint is rejected at load, the wire pin and the zod agree, the docs are short and accurate, and
the 6.2c catalogue edit is exactly what the sweep reported. Two things the tests cannot see block a
plain LAND. (1) `sumsBy` is `foldMap`, which is `foldr` (List.e:46, not tail-recursive), so the
crosstab's stack depth grows with ROWS: through `bin/ermine-serve` a crosstab over 5,000 inline rows
is an HTTP 500 (`infinite loop detected`) where the headline over 100,000 rows of the same relation
is a 200; a one-line `foldl` renders 100,000. (2) `primOrd` on `String` is CASE-INSENSITIVE
(`PrimExpr.scala:641` lower-cases both sides), so `distinct primOrd` MERGES keys that differ only by
case into the first spelling seen and sums their rows into one cell, while Ermine's `==` and a SQL
`GROUP BY` keep them apart; the `(fxc-1)` oracle is Scala's case-sensitive `.distinct.sorted`, and
only the all-lowercase alphabet keeps it green. Both are small fixes.

## What I re-ran (mine) and what I cite (the implementer's)

| Check | Result | Log |
|---|---|---|
| `sbt -batch core/compile core/copyResources` | `[success]` x2 (already compiled, 1 s) | `review-j3i-compile.log` |
| `sbt -batch 'core/testOnly *TestRunner *TestWidgets *TestDoc *TestJson *TestSchema *TestNamedFields'` | `Passed: Total 133, Failed 0, Errors 0, Passed 133`, 107 s (the implementer's 117 + 16 `TestNamedFields`) | `review-j3i-suites.log:566` |
| `(fxc-1)` distribution in that run | `30 crosstabs; 3 empty, 16 with a gap, 21 with a collision; rows per case 0x3 1x5 2x1 3x2 4x3 5x3 6x4 7x2 8x4 9x3` (seeded, identical to `j3i-suites-1.log:455`) | `review-j3i-suites.log:51` |
| `(a-pin5)`, `(a-cov)` with the two crosstab shapes | OK | `review-j3i-suites.log:533,565` |
| `cd client && npm test && npm run check-generated` | `tests 65, pass 62, fail 0, skipped 3`; `check-generated: src/generated is up to date` | `review-j3i-client.log:76-81` and tail |
| Mutation M3: `rowTotals`/`colTotals` swapped (`Crosstab.e:119-120`) | `Failed: Total 34, Failed 2, Errors 0, Passed 32`; the two red are `(fx6)` and `(fxc-1)` | `review-j3i-mutation-M3-swap-totals.log:47,66,78` |
| Mutation M4: a collision keeps the last value (`valueMonoid_M o (x y -> y)`, `Crosstab.e:98`) | `Failed: Total 34, Failed 2, Errors 0, Passed 32`; `(fx6)` shows north/January as `1200.5` for `2040.5`; `(fxc-1)` red | `review-j3i-mutation-M4-last-value.log:52,55,70,83` |
| Row constraint with the SAME field as row and column key (`CrosstabSource .. k k m r`) | rejected at load: `Fields appear twice in row: XtDup.k` | REPL, scratch module `XtDup.e` (output in this session; not a log file) |
| Stack: `bin/ermine-serve --root <scratch>`, `XtBig.report n` = `crosstabOf` over `n` inline rows `{k="a", k2="b", m=1.0}` | n=100/300/500/1000/2000: `200`, `cells [[n.0]]`; n=5000 and 20000: `500 {"error":{"path":"$.props","message":"XtBig.report produced a document that cannot be encoded: ... cannot encode $.cells[0][0]: the value is an error: infinite loop detected"}}`; the same relation through `headlineOf` at n=5000/20000/100000: `200`, `total n.0` (6.8 s at 100k) | `review-j3i-stack-probe.log` |
| The fix probe (M5): `sumsBy` as a strict `foldl` over `unionWith_M (+)` (diff in the log), same server, same module | n=2000/5000/20000/100000: all `200`, `cells [[n.0]]` (100k in 31 s); reverted, `FINAL-IDENTICAL` | `review-j3i-foldl-probe.log` |
| Case: REPL over the stage's `target/` | `"B" < "b"` = `False`, `"b" < "B"` = `False`, `"a" < "B"` = `True`; `sort primOrd ["b","B","a","A","c"]` = `["a","A","b","B","c"]`; `distinct primOrd ["b","B","a"]` = `["b","a"]` | REPL, scratch module `XtCase.e` (this session) |

Cited from the implementer, not re-run (nothing in the diff touches them): `scripts/gate.sh run commit`
`compile PASS 7s`, `corpus PASS 52s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ`, `lsp PASS 51s
(582 checks)` (`j3i-gate-commit-2.log:1-3`); `TestTolerantCheck` before the catalogue edit `Failed:
Total 57, Failed 1` with the moved set (`j3i-tolerant-1.log:102-103`) and after `Passed: Total 57`
(`j3i-tolerant-2.log:102`); the implementer's M1/M2 mutations `Failed 2 of 34` (`j3i-mutation-M1.log:67`,
`j3i-mutation-M2.log:71`). The full `core/test` was not run.

## Checklist

1. **`Crosstab.e` / `crosstabOf`.** Sums per pair, both axes `sort primOrd (distinct primOrd ..)`,
   `lookup_M` is the `Maybe` (absent pair = `Nothing`, verified by M1 and by my M4 that the sum is a
   real sum), totals from the same rows (`rowTotals`/`colTotals` via `sumsBy`, `grandTotal` via
   `sum'`; consistent up to floating-point association, which `(fxc-1)`'s 1e-9 `near` and the
   eighth-step generator make exact), the empty relation gives `[] [] []` `[] []` `0.0` (`(fxc-1)`
   `empties >= 1`). `r <- (h1, h2, h3, t)` is sound: the same field twice fails to load (above).
   `keyOrd` via `ordMonoid` (`Ord.e:14`) compares first then second. Two findings: R1 (foldr) and
   R2 (case) below. `sumsBy` and `keyOrd` are exported into `Layout.Widgets`' scope; no stdlib or
   corpus name clashes (`grep -rnw` over `modules/` and `core/examples/`: none; the corpus gate is
   green), so O2 only.
2. **`Headline.e`.** `HeadlineProps`, `headline` and the wire untouched (diff); `HeadlineSource` with
   the four prefixed fields; `headlineOf` body equivalent to J3g's; `FetchHeadline.e`,
   `FetchFragments.e`, `(fxl-headline)` updated in place; `(fx1)`..`(fx5)` green in my run.
3. **The wire.** `Maybe Double` inside a list is a `null` element: `(a-pin5)` pins the whole
   document (`"cells":[[1.5,null],[null,2.0]]`), the generated zod says
   `z.array(z.array(z.number().nullable()))`, `(p-crosstab)` pins no optional key and rejects a string
   cell, a flat matrix and a `null` total. `crosstab.ts` handles `null` (em dash + `.ermine-crosstab-empty`),
   short rows (`?? null`), empty axes (`no rows`, `(w-crosstab-empty)`), totals column/row.
   `check-generated` up to date; `(w-crosstab)` asserts header row, row labels, formatted cells,
   the dash, totals.
4. **Properties.** `(fxc-1)` is random over rows and values (seeded), the oracle is independent
   Scala, the anti-vacuity is asserted (`>= 1` empty, `>= 5` gaps, `>= 5` collisions) and printed;
   `(fx6)` pins both parameter arms; `(a-cov)` requires `crosstab-gap` and `crosstab-full`. The
   implementer's M1/M2 and my M3/M4 each isolate to `(fxc-1)`+`(fx6)`. What the properties cannot
   see: depth (max 9 rows) and case (lowercase alphabets) -- R1, R2.
5. **6.2c catalogue.** The nine entries in `TestTolerantCheck.scala` (`Headline.e:78:9`,
   `Crosstab.e:108:9`..`115:9`) are exactly the `new`/`gone` set in `j3i-tolerant-1.log:102-103`
   (`gone Headline.e:63:9`), and the lines are the eight `let` heads of `crosstabOf` and the one of
   `headlineOf` (checked with `grep -n`). The comment is accurate.
6. **Dialect and scope.** Only test Scala changed; grep for `given|using|extension|derives|LazyList|
   CollectionConverters|isBlank|readString|List.of|?=>|as-import|*-import` over the diff: none;
   `Either` untouched; `.corresponds`, `Gen.zip`(3), `lift` all 2.11. `git diff --stat`: the 16
   listed files + 5 untracked, nothing under `core/examples/`, `tracker/repl-classpath.txt` clean, no
   CRLF introduced (`grep -c $'\r'` over the diff: 0). Docs (3.4c "The Fetch widget shape", the
   `a widget that scans` row, README files table / reserved names / "Adding a widget", the plan row
   and handoff entry, the `Widgets.e` header) are accurate and short.

## REQUIRED fixes

1. **`Crosstab.e:98` -- `sumsBy` must not be `foldMap`.** `foldMap m f = foldr (mappend m . f)
   (mempty m)` (List.e:67) and `foldr f z (x :: xs) = f x (foldr f z xs)` (List.e:46) is not
   tail-recursive, and `unionWith#` is strict in both maps, so the JVM stack grows with the row
   count -- three times over, once per `sumsBy`. Failure scenario: `bin/ermine-serve` (its pool
   threads have the JVM default stack, `Server.scala:48`) renders a crosstab over 2,000 rows and
   returns `500 ... $.cells[0][0]: the value is an error: infinite loop detected` at 5,000
   (`review-j3i-stack-probe.log`); the REPL dies at 500 (`foldr` over `replicate () 500`:
   `runtime error: null`, a `StackOverflowError`'s message). J3h's `(ip-stack)` comment promises the
   opposite ("the depth grows with RELATIONS and not with rows"), and `headlineOf` keeps that promise
   (100,000 rows, `200`). Fix (verified, `review-j3i-foldl-probe.log`, diff at its head): import
   `foldl` and write
   `sumsBy o key val xs = foldl (acc x -> unionWith_M (+) acc (fromAssocList_M o [(key x, val x)])) (empty_M o) xs`
   -- `foldl f !z` (List.e:50) is strict in the accumulator; 2,000 / 5,000 / 20,000 / 100,000 rows
   all render. It is one line and the import list, so `Crosstab.e:108-115` do not move and the
   6.2c catalogue stays as it is. Add a pin that would have caught it: a `TestRunner` `(fxc-2)`
   that renders `crosstabOf` over a relation of >= 20,000 generated rows built in Ermine
   (`mkRelation# (toList# (map_List (i -> { rgName = "a", rgCat = "b", rgAmount = 1.0 }) (take n (from 0))))`
   is the shape my probe used; `Native.List`, `Native.Relation`, `Function` are already in
   `fetchImports`) and asserts `cells == [[n.0]]` and `grandTotal == n.0`; 20,000 is above both
   ceilings measured (500 REPL, between 2,000 and 5,000 server), so it is red on `foldr` on any
   thread and green on `foldl`.
2. **`Crosstab.e:111-115` and `TestRunner.scala` `(fxc-1)` -- say what `primOrd` does to case, and
   test it.** `primLt#` (`Lib.scala:387`) compares through `PrimExprOrder`, and for strings that is
   `v1.toLowerCase ?|? v2.toLowerCase` (`PrimExpr.scala:641`), so `primOrd "B" "b"` is `EQ` while
   `==` (`Lib.scala:234`, Scala `==` on the extracted values) says they differ. Failure scenario: a
   `region` column holding both `"North"` and `"north"` (or a `Date` projected two ways) gives ONE row
   label -- whichever spelling `distinct` met first, so it changes with row order -- whose cells and
   `rowTotals` sum both, silently; a SQL `GROUP BY` on the same column (SQLite's default `BINARY`
   collation) and Ermine's own `==` keep two. The module header says "sorted, distinct" and the
   `(fxc-1)` oracle is Scala's case-sensitive `.distinct.sorted`, which would go red on such input;
   the property never sees it because both alphabets are lowercase. Minimum fix (small, no design
   change): (a) one sentence in the `KEYS ARE STRINGS` paragraph of `Crosstab.e` -- keys are compared
   by `primOrd`, which ignores case, so labels differing only by case merge under the first spelling
   seen and the axes sort case-insensitively; (b) put a mixed-case letter in `(fxc-1)`'s alphabets
   (e.g. `"Ann"` beside `"ann"`) and make the oracle key on `toLowerCase` for both the labels and the
   sums, with the label expected to be the first spelling in row order -- so the property states the
   real semantics and would catch a change to them. The better product answer is a case-sensitive
   key order, but the stdlib has no case-sensitive `Ord String` (`String.e` has none; `Lib.scala`
   only `primLt#`), adding one is a `Lib.scala` change shared with the 2.11 branch, and whether
   `primOrd` should ignore case at all is a language question -- the user's call, not this stage's.
   Record it as an open ticket if (a)+(b) is what lands.

## Optional suggestions

- O1. With R1 applied the 100,000-row render takes 31 s (`review-j3i-foldl-probe.log`) against the
  headline's 6.8 s: three passes, each a `unionWith#` of a singleton map per row. A `Map.insertWith`
  (there is `insert`, Map.e:89, but no `insertWith`) or one pass that builds all three maps would cut
  it; or derive `rowTotals`/`colTotals` from `cellSums` (`|rows| x |cols|` lookups) rather than two
  more scans of the rows. Not needed for correctness.
- O2. `sumsBy` and `keyOrd` are generic names now exported through `Layout.Widgets`. A `private`
  section (as `List.e:291` does) would keep them out of every importer's scope; it moves the
  `Crosstab.e:108-115` lines, so it costs one 6.2c catalogue edit and one `TestTolerantCheck` run.
- O3. The implementer's open issues stand: the 2.11 port is untouched; the client corpus fixtures are
  not regenerated (3 skips); a crosstab beside a headline scans twice; no cap on the matrix.

## Verdict

FIX-THEN-LAND
