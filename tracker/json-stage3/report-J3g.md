# J3g: `Fetch Node` as the report type (branch `json-unify`, worktree `ermine-scala-wt-json-unify`)

Base `json-encode` 9fa3f89f. Nothing committed; the tree is dirty for review (15 files changed,
4 new; `git diff --stat`: 723 insertions, 151 deletions).

A scan no longer has to be hoisted above its layout. `modules/Layout/Fetch.e` gained the lifts and
the layout combinators over `Fetch Node`; `json/Runner.scala` has one render path, with
`Params -> Node` read as `done` of its value and the first evaluation step taken before any
connection is opened; `Layout.Widgets.Headline` is the widget whose smart constructor scans, end to
end (Ermine, generated zod, TypeScript component, registry). Gates: `scripts/gate.sh run commit`
3/3 PASS, the five suites 109/109, the client 59 passed / 3 skipped / 0 failed and
`check-generated` up to date.

## What was built

| File | What |
|---|---|
| `core/src/main/resources/modules/Layout/Fetch.e` | `map_Fetch`, `bind_Fetch`, `sequence_Fetch` (left to right), and the layout lifts `vflowF`, `hflowF`, `gridF`, `tabbedF`. It now imports `Layout.Doc` (`Doc` does not import `Fetch`). Header comment rewritten: the "a scan cannot sit inside a vflow: hoist it" paragraph is gone, replaced by what `Fetch Node` as the report type means and by an ORDER paragraph. |
| `core/src/main/scala/com/clarifi/reporting/ermine/json/Runner.scala` | One path. `Report.fetching` and `build` are gone; `render` decodes, takes the first `evalStep` under `evalLock` BEFORE `cfg.run.run`, and then either writes (the value is the document) or calls `renderFetch` (the value is a `Scan`). `renderFetch` now takes the first scan's `(order, ext, k)` and runs the interpreter plus the write in one `Run[DB].run`; `interpret` starts from that scan. `evalStep` reads a value that is neither `Done` nor `Scan` as the Node itself. Class doc comment and `renderFetch`'s doc comment rewritten. |
| `core/src/main/resources/modules/Layout/Widgets/Headline.e` (new) | `data HeadlineProps` + `headline : HeadlineProps -> Node` (pure) + `headlineOf : (Relational rel, r <- (h, t)) => String -> String -> Field h Double -> rel r -> Fetch Node`, which scans, counts, sums and takes the maximum (0.0 over no rows, as `sum'` is). |
| `core/src/main/resources/modules/Layout/Widgets.e` | `export Layout.Widgets.Headline`; `"headline"` added to `widgetNames`. |
| `core/src/test/resources/doc/FetchHeadline.e` | Rewritten around `headlineOf` and `vflowF`. The ad hoc `widget "headline"` and `widget "text"` are gone; the empty-scan arm now uses the PURE `headline` (nothing to scan), so the "layout depends on the data" story survives with registered widgets only. |
| `core/src/test/resources/doc/FetchFragments.e` (new) | One report from three fragments of type `... -> Fetch Node` (`regionHeadline`, `runningTable`, `topSlices`), composed with `sequence_Fetch` + `hflow`, `tabbedF` and `vflowF`. Five scans, one document. |
| `client/src/widgets/headline.ts` (new), `src/props.ts`, `src/index.ts`, `scripts/generate.sh`, `src/generated/{headline.ts,index.ts}` | The three-edit recipe of `client/README.md`: generate spec + `WIDGET_PROP_SCHEMAS` line, the props interface, the component (plain DOM: title, scope, three figures; `total` and `largest` through `headlineFormat` with `format.ts`, `rowCount` printed as it arrives), one `defaultRegistry()` line. |
| `client/test/{widgets,props}.test.ts` | `(w-headline)` renders it in jsdom and checks the count is raw while the two measurements are formatted (and that a plain `String()` of them is NOT what is rendered); `(p-headline)` pins the generated schema's keys; `(p-registry)` now lists `headline`. |
| `scalacheck-binding/src/main/scala/TestRunner.scala` | `RecordingScanner`, a third runner (`orderRunner`), and the properties `(fxl-order)`, `(fxl-laws)`, `(fxl-sugar)`, `(fxl-conn)`, `(fxl-headline)`, `(fx5)`; `(fx1)` updated for the new `FetchHeadline`. |
| `scalacheck-binding/src/main/scala/TestWidgets.scala` | `headlineSrc` in the widget pool, `Layout.Widgets.Headline` in `imps` and in the exported-schema map, `widget-headline` in `(a-cov)`'s required set. |
| `tracker/JSON-API-DESIGN.md` | New section 3.4c "Fetch as the report type" with the decisions table; section 3.4b's "Cost" line corrected (a failing fetching report no longer pays for a connection). |
| `tracker/JSON-STAGE3-PLAN.md` | J3g row in the stages table and a handoff-log entry. |
| `client/README.md` | Headline in the files table and in "Names Stage 3 reserves"; "Adding a widget" gained a sentence on a constructor that returns `Fetch Node`; the intro says two native widgets. |

## Decisions the brief did not fix

| Decision | Choice and why |
|---|---|
| How `Params -> Node` stays accepted with no `fetching` flag | `evalStep` dispatches on the VALUE: `Data(DoneCon, ..)` is the document, `Data(ScanCon, ..)` is a scan, anything else IS the Node and goes to `Doc.fromRuntime`. `resultKind` still classifies the TYPE at compile time (so the (b3) refusal is unchanged), but nothing branches on it at request time. |
| Where the branch that remains lives | `render` branches on the first step's value, not on the report: `Done`/bare Node is written by `write` (which opens the one connection), a `Scan` goes to `renderFetch`. Both spellings of a report take exactly the same first step. |
| `headlineTitle`, not `title` | VERIFIED CLASH, not a guess: with the prop named `title`, a module that does `import Layout.Widgets` and applies `title` to a `ScorecardProps` fails with `failed to unify type (ScorecardProps !r) with type HeadlineProps` (probe module, `bin/ermine :load`). `Layout.Widgets` re-exports every widget module into one scope and `Layout.Widgets.Scorecard` owns `title`; `Layout.Widgets.Chart` already spells `chartTitle` for that reason and says so in a comment. The other five prop names (`scope`, `rowCount`, `total`, `largest`, `headlineFormat`) are free in the stdlib and in `Layout/Widgets/*.e`, and the module loads clean. |
| `headlineOf`'s format | `Default`. The brief's signature has no format argument; a caller who wants another builds `HeadlineProps` by hand and uses `headline`. |
| `FetchTopN`'s `widget "metTargets"` | KEPT as a pin that an unregistered name goes on the wire (the brief left the call to me). Changing it to a headline would have removed the only example of that case; `(fx4)` still asserts it. |
| Where the headline is property-tested | The scanning half is `TestRunner (fxl-headline)` -- it needs a runner to execute a scan, and `TestWidgets` has none -- and the props/schema half is in `TestWidgets` (the headline is now one of the widgets `(a)` and `(a-cov)` generate, mutate and validate). |
| `(fxl-order)`'s observation of scan order | A `RecordingScanner` wrapping the SQLite scanner, which notes the `rgName` of the first row of every literal relation it scans, in scan order. The leaves' continuations also put the marks THEY received into the document, so the property compares three things: the source order of the leaves, the scanner's order, and the document's. |
| Sample sizes | The (fxl) properties are fixed-sample `secure` properties (24 trees, 12 law cases, 20 sugar cases, 20 headline cases) driven by `TestDoc.samples`, not `forAll`: every case writes and loads one or two Ermine modules in the runner's session, so 100 ScalaCheck cases per property would have cost minutes per property. The samples are seeded and deterministic. |

## Departures from the brief

| Brief | What was done | Why |
|---|---|---|
| `HeadlineProps { title, .. }` | `headlineTitle` | The clash above, which the brief's own rule ("if a field selector name clashes, rename the prop") covers. Everything downstream (zod, `props.ts`, the component, the tests) uses `headlineTitle`. |
| `FetchHeadline.e`: "an empty scan yields ... instead of a table" | The empty arm is a `headline` of zeros built by the pure constructor, not a "text" widget | The brief removes `widget "text"` (not in the registry) and there is no other registered widget for a note. The layout still changes with the data: one widget, no table, and `(fx1)` asserts it. |
| `(fxl-order)` "a random tree ... over N leaf scans" | 24 seeded samples rather than ScalaCheck's 100 | Cost (above). The distribution is printed once per run and asserted, and the property was shown red under a mutation (below). |

## Anti-vacuity

- `(fxl-order)` prints its distribution once. Last green run: `24 trees, 95 leaf scans; leaves per
  tree 1x6 2x4 3x6 4x5 10x1 13x1 20x1; nodes bind_Fetch=14 gridF=3 hflowF=11 leaf=95
  sequence_Fetch=8 tabbedF=2 vflowF=12` (`tracker/json-stage3/logs/suites-4.log:411`). The property
  asserts that at least 18 of 24 trees have two or more leaves (a one-leaf tree cannot tell an
  order from its reverse), that all six combinators occurred, and that there were at least 40 leaf
  scans in all.
- MUTATION RUN. With `sequence_Fetch` changed to scan right to left
  (`bind_Fetch (sequence_Fetch ms) (as -> map_Fetch (a -> a :: as) m)`, which keeps the RESULT
  order and only reverses the scans), `(fxl-order)` is red: `14 of 24 failed: scan order
  List(Lf01, Lf00) for List(Lf00, Lf01)` on `(vflowF [leaf0, leaf1])` and on
  `(map_Fetch hflow (sequence_Fetch [leaf0, leaf1]))`; the run was `Failed: Total 29, Failed 1,
  Errors 0, Passed 28` (`tracker/json-stage3/logs/mutation-fxl-order.log:103-109`). The document
  order stayed correct under the mutant, which is the evidence that the property observes the SCAN
  order and not the tree.
- `(fxl-laws)` requires both request defaults (inline and deferred) to have occurred; `(fxl-sugar)`
  requires both delivery arms to have appeared in the compared documents; `(fxl-headline)` requires
  at least one empty relation and at least ten multi-row cases; `TestWidgets (a)` already mutates
  every props document and requires the schema to refuse the mutant, and the headline now goes
  through that.

## Error texts

Unchanged: the (b3) refusal (`<module>.report is not a report: a report returns Layout.Doc.Node or
Layout.Fetch.Fetch Layout.Doc.Node, not ...`), the fetch-scan 500 (`<module>.report: scan n
failed: ...`), the encode 500 (`... produced a document that cannot be encoded: ...`), the
evaluation 500 (`<module>.report failed: ...`).

REMOVED: `step n is neither Done nor Scan: <value>`. That branch is what now reads a bare `Node`,
so the message has no reachable case left (`resultKind` has already refused any other result type);
a value the walker cannot encode gets the unchanged "cannot be encoded" 500 instead.

## Gates

| Gate | Result | Log |
|---|---|---|
| `scripts/gate.sh run commit` (key `637f2b4a413f400707939a1fe46f89214946c870`) | `compile PASS 7s compiled`; `corpus PASS 60s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected`; `lsp PASS 60s PASS lsp (582 checks)` | `tracker/json-stage3/logs/gate-commit-2.log`; per-gate logs and `.result` files under `/home/dmitry/research/ermine/ermine-scala/.gate-cache/637f2b4a413f400707939a1fe46f89214946c870/` |
| the same gate on the previous content (key `8efb4f2eaebd900b538669a0859e2c4bd7095db9`, before `hflowF`/`gridF` were added to `(fxl-order)`) | compile PASS 6s, corpus PASS 53s (same counts), lsp PASS 57s (582 checks) | `tracker/json-stage3/logs/gate-commit.log` |
| `sbt -batch 'core/testOnly *TestRunner *TestWidgets *TestDoc *TestJson *TestSchema'` | `Passed: Total 109, Failed 0, Errors 0, Passed 109`, 89 s | `tracker/json-stage3/logs/suites-4.log:415` |
| `cd client && npm ci && npm test` | `tests 62, pass 59, fail 0, skipped 3` (the three skips are the corpus / end-to-end fixtures the Scala side writes; they skip on the base too) | `tracker/json-stage3/logs/client-1.log` (npm ci), `tracker/json-stage3/logs/client-2.log` |
| `cd client && npm run check-generated` | `check-generated: src/generated is up to date` | `tracker/json-stage3/logs/client-2.log` (tail) |
| mutation of `sequence_Fetch` (evidence, not a gate) | `Failed: Total 29, Failed 1, Errors 0, Passed 28` -- only `(fxl-order)` red | `tracker/json-stage3/logs/mutation-fxl-order.log` |

Two earlier runs are kept for the record: `suites-1.log` (4 red: a generated `HeadlineProps` with a
NEGATIVE Double literal, `unknown operator -`, because a bare `-1.5` argument is parsed as the
operator; fixed by generating non-negative literals in `TestWidgets.headlineSrc`, where every other
generator is already non-negative -- the negative cases live in `(fxl-headline)`, where the numbers
sit inside a record literal and parse), and `suites-2.log` / `suites-3.log` (109/109 before the
`hflowF`/`gridF` coverage was added). The full `core/test` was NOT run (the brief forbids it).

`tracker/repl-classpath.txt` is untouched (`gate.sh` swaps and restores it).

## Open issues

- **The 2.11 port.** Nothing was ported. The Scala is in the shared dialect (no `given`, `Either`
  through `.right`, no JDK 9+ API), and the only new Scala outside tests is inside `Runner.scala`.
- **A widget that owns its scan reads the relation itself.** `FetchHeadline` therefore scans
  `picked q` twice on the non-empty arm (once for the shape, once inside `headlineOf`). The file
  says so; section 3.4c says so. A caller holding the numbers uses `headline` and scans once. There
  is no sharing of a scan between two `Fetch` values.
- **`gridF` scans row-major**; `tabbedF` scans in tab order even for tabs the client will not open
  (`FetchTabs` still defers the CONTENT, but a `tabbedF` whose tab bodies scan reads them all).
  That is the price of a layout whose children scan, not a bug, and `(fxl-order)` pins the order.
- **`Layout.Scan` (the old `Report f z` runner) and the legacy `Report`/`Writer` path are
  untouched**, as in J3f.
- **The client corpus fixtures were not regenerated**, so `client/test/corpus.test.ts` and
  `endtoend.test.ts` still skip. They now would include headline widgets (TestWidgets generates
  them); the dispatcher has the schema and the renderer, but that path is UNVERIFIED in this
  stage -- running `client/scripts/check-corpus.sh` would verify it.

## What J3h (one step interpreter) must know

1. **Where the one path is now.** `Runner.render` = `report` -> `decode` -> `evalStep(.., n = 1)`
   under `evalLock` -> either `write(Doc.document(doc, settings), ..)` or
   `renderFetch(rep, order, ext, k, out, wcfg)`. `renderFetch` builds ONE `DB` action
   (`interpret` then `Write.doc`) and runs it in one `cfg.run.run`. `build` and `Report.fetching`
   no longer exist; `write` is the pure path's only use of `cfg.run.run`.
2. **The ordering is a property, not an accident.** `(fxl-conn)` asserts that a report that fails
   to evaluate opens ZERO connections, pure and fetching, and that one that scans opens exactly
   one; `(fx-conn)` asserts one connection for a report with two scans and an inline relation. A
   step interpreter that starts the driver inside `cfg.run.run` before the first `Eval` will turn
   `(fxl-conn)` red. Keep the first `Eval` outside.
3. **Scan numbering.** `evalStep(rep, next, n)` is called with `n = 1` OUTSIDE the connection, and
   the scan it returns is scan 1; `interpret` then numbers the following steps 2, 3, ... So
   `ScanFailed(n)`'s `n` is "the scan asked for at step n", 1-based, and `$.fetch[n]` in J3h should
   keep that numbering if the messages are to stay comparable. `(fx-err)` asserts only that the
   500 names the report, so re-spelling the message is cheap; `(fxl-conn)` asserts statuses and
   connection counts, not text.
4. **`Params -> Node` reaches the interpreter as a value, not as a type.** `evalStep`'s last case
   walks a value that is neither `Done` nor `Scan` into a `Doc`. If J3h's `Eval` step keeps only
   the two `Fetch` constructors, every pure report becomes a 500.
5. **Stats today.** `WriteStats.relations` holds wire relations only; nothing in `TestRunner`
   asserts its contents for a fetch scan (the assertions are on `(e)` / `(fx-conn)` connection
   counts and on the document). Adding `$.fetch[n]` entries in execution order breaks no existing
   assertion in these five suites.
6. **`Layout.Fetch` is loaded at boot** (`FetchModule` in `Runner.booted`) and `Layout.Fetch` now
   imports `Layout.Doc`; `Layout.Doc` must NOT import `Layout.Fetch` (the lifts live in `Fetch`).
7. **Byte-identical output.** `(fxl-sugar)` compares a pure report and the same body under `done`
   byte for byte (tokens and expiry masked) over 20 generated documents including deferred
   relations; it is the cheapest regression net J3h has for "the step interpreter writes the same
   bytes".

## R1 applied (review fix, 2026-09-18)

`headlineOf`'s `largest` was folded from `0.0`, so a relation whose values are all negative
reported `largest = 0.0`, a number that is in no row.

| Change | File |
|---|---|
| `biggest : List Double -> Double` (`[] -> 0.0`; `(y :: ys) -> foldl (a b -> if (b > a) b a) y ys`), used by `headlineOf`; `empty_Bracket`/`cons_Bracket` added to the `List` import for the patterns; the doc comments now say the maximum is negative when the rows are | `core/src/main/resources/modules/Layout/Widgets/Headline.e` |
| The oracle is `if (xs.isEmpty) 0.0 else xs.max` (it used to restate the bug) | `scalacheck-binding/src/main/scala/TestRunner.scala`, `(fxl-headline)` |
| `headlineCase` gained an explicit ALL-NEGATIVE arm (`Gen.frequency((3, mixed), (1, allNeg))`, `allNeg` = 1..4 values from `Gen.choose(-9999, -1) / 8.0`) and the property gained the conjunct `cases.exists(c => c._1.nonEmpty && c._1.forall(_ < 0))` | same file |

Evidence, in order:

| Run | Result | Log |
|---|---|---|
| the new oracle + generator against the OLD `Headline.e` (red before the fix) | `Failed: Total 35, Failed 1, Errors 0, Passed 34`; `(fxl-headline)` falsified, `7 of 20 wrong`, e.g. `largest ... "largest":0.0 ... for List(-534.0, -74.25, -516.5, -490.5)` | `tracker/json-stage3/logs/suites-r1-red.log:92-96,106` |
| `bin/ermine`: `:load` of `Layout/Widgets/Headline.e`, `FetchHeadline.e`, `FetchFragments.e` | all three imported, no error | -- |
| `sbt -batch 'core/testOnly *TestRunner *TestWidgets'` after the fix | `Passed: Total 35, Failed 0, Errors 0, Passed 35`, 41 s | `tracker/json-stage3/logs/suites-r1.log:69` |
| `scripts/gate.sh run commit` on the post-R1 content (key `be2560a7f75843ffd51a45826fa2181828c6faff`) | `compile PASS 5s compiled`; `corpus PASS 53s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected`; `lsp PASS 52s PASS lsp (582 checks)` | `tracker/json-stage3/logs/gate-commit-r1.log`; `.result` files under `/home/dmitry/research/ermine/ermine-scala/.gate-cache/be2560a7f75843ffd51a45826fa2181828c6faff/` |

`TestDoc`, `TestJson` and `TestSchema` were not re-run (nothing they cover changed; their green is
`tracker/json-stage3/logs/suites-4.log`). The client was not re-run: `largest` is a number the
server computes, and no client file changed. Still not committed.
