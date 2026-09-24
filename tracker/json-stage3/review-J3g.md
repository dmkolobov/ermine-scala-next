# Review of J3g (`json-unify`, uncommitted diff against json-encode 9fa3f89f)

Reviewer: independent (did not write the stage). Scope: `git diff 9fa3f89f` (15 files, 723
insertions, 151 deletions) plus the untracked `Layout/Widgets/Headline.e`, `FetchFragments.e`,
`client/src/{widgets,generated}/headline.ts`. Every number below names its log; the logs I
produced are `tracker/json-stage3/logs/review-*.log`.

## Verdict in one paragraph

The design is right and the runner change is correct: one render path, the first evaluation
step under `evalLock` and outside `cfg.run.run` for both spellings of a report, no lock held
across a scan, the same error texts. The lifts are correct and scan left to right. One
correctness bug: `headlineOf`'s `largest` is not the maximum -- the fold is seeded with `0.0`,
so over rows whose field values are all negative it reports `0.0` -- and the property that was
meant to catch it computes the same seeded fold in Scala and its 20 seeded samples contain no
all-negative relation, so it could not catch it even with the right oracle. That is a small,
local fix; everything else is LAND-quality.

## What I re-ran

| Check | Result | Log |
|---|---|---|
| `sbt -batch core/compile core/copyResources` | `[success]` (nothing to recompile; the implementer's build was current) | `logs/review-compile.log` |
| `sbt -batch 'core/testOnly *TestRunner *TestWidgets *TestDoc *TestJson *TestSchema *TestNamedFields'` | `Passed: Total 125, Failed 0, Errors 0, Passed 125`, 94 s | `logs/review-suites.log:413-414` |
| (fxl-order) distribution in that run | `24 trees, 95 leaf scans; leaves per tree 1x6 2x4 3x6 4x5 10x1 13x1 20x1; nodes bind_Fetch=14 gridF=3 hflowF=11 leaf=95 sequence_Fetch=8 tabbedF=2 vflowF=12` (identical to `logs/suites-4.log:411`) | `logs/review-suites.log` |
| `cd client && npm test && npm run check-generated` | `tests 62, pass 59, fail 0, skipped 3`; `check-generated: src/generated is up to date` | `logs/review-client.log` |
| `bin/ermine`: `foldl (a b -> if (b > a) b a) 0.0 [-1.5, -2.0]` | `res0 : Double = 0.0` (the bug, in one line); `... [1.5, 2.0, -7.0]` gives `2.0` | REPL, transcript in this review only |

Cited, not re-run (the diff gives no reason to doubt them): `scripts/gate.sh run commit` --
`compile PASS 7s`, `corpus PASS 60s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from
expected`, `lsp PASS 60s PASS lsp (582 checks)` (`logs/gate-commit-2.log`). The implementer's
own mutation (`sequence_Fetch` right to left): `Failed: Total 29, Failed 1` with only
(fxl-order) red, `14 of 24 failed` (`logs/mutation-fxl-order.log:103-109`) -- read and consistent
with the distribution (the one-leaf trees cannot fail).

## My mutations (both reverted; `git diff 9fa3f89f --stat` is back to 15 files / 723 / 151, and
`core/copyResources` was re-run so `target/` holds the stage's `Fetch.e` again)

Two mutations in one `core/testOnly *TestRunner` run, attributable per property because
`headlineOf` uses `scanRelation` directly and never `bind_Fetch`:

- **A** (`Fetch.e`): `bind_Fetch (Done a) f = dropScans_M (f a)` where `dropScans_M` replaces
  every `Scan` in the continuation by its `k []` -- "the continuation's scans are dropped". A
  first attempt put the helper between the two `bind_Fetch` equations and the module refused to
  load (`interleaved equations for bind_Fetch`, every property 500 -- `logs/review-mutation-AB.log`,
  void); the corrected run is `logs/review-mutation-AB2.log`.
- **B** (`TestRunner.scala` (fxl-headline) oracle): `wantLargest = if (xs.isEmpty) 0.0 else xs.max`,
  plus a `println` whenever a sample is non-empty and all-negative.

Result: `Failed: Total 29, Failed 3, Errors 0, Passed 26` (`logs/review-mutation-AB2.log:68`).

| Property | Under A+B | Reading |
|---|---|---|
| (fxl-order) | RED, `18 of 24 failed: scan order List(Lf00) for List(Lf00, Lf01, ...)` (`:57-64`) | exactly the 18 multi-leaf trees; the property observes the scans, not the tree |
| (fx5) | RED, 500 `an empty relation built from no rows carries no columns` at `$.children[1].tabs[0].content.props.rows` (`:17-19`) | `runningTable`'s continuation got `[]` |
| (fxl-conn) | RED, `FetchFragments status 500` (`:38-41`) | same cause; the connection-count arms were not reached |
| (fxl-laws) | GREEN | laws (2) and (3) never put a scan inside the continuation of a `bind_Fetch` whose left side is `done`, so this mutation is invisible to them (optional S2 below) |
| (fxl-headline) | GREEN, and the all-negative `println` never fired (`grep all-negative` over the log: no line) | the 20 samples of seed 31337 contain NO non-empty all-negative relation; with the TRUE-max oracle the property still passes, so as seeded it cannot detect the `largest` bug |

## Checklist

1. **Runner.scala, one path.** `render` (Runner.scala:364-373): `report` -> `decode` ->
   `evalStep(rep, () => Runtime.swhnf(rep.fn).apply1(v), 1)` -> `Left(doc)` goes to `write`
   (the pure path's only `cfg.run.run`), `Right((order, ext, k))` goes to `renderFetch`, whose
   single `cfg.run.run` wraps `interpret` + `Write.doc`. The first step is therefore outside any
   connection for both spellings; a report that throws (pure or fetching) never reaches
   `cfg.run.run` -- (fxl-conn) asserts 0/0/1 connections and is green. `evalLock` is taken only
   inside `evalStep`; `scanning` runs `cfg.scanner.scanExt` in the `DB` action between steps, so
   the lock is never held across a scan. `evalStep`'s "anything else is the Node" case: the
   value has passed `resultKind` at `report()` time, so a non-`Fetch` value can only be a `Node`
   or a bottom; a bottom is `Death`/`NonFatal` -> `<module>.report failed: ...`, an unwritable
   Node is the unchanged "cannot be encoded" 500 with its path. I see no way to reach that case
   with a value of another type without defeating the type checker. Error texts: compared old
   `build` and new `evalStep` -- `failed(..)` spells `<module>.<report> failed: <why>` exactly as
   before; the only removed text is the one the report lists.
2. **Fetch.e.** `map_Fetch`, `bind_Fetch` are the obvious structural definitions;
   `sequence_Fetch (m :: ms) = bind_Fetch m (a -> map_Fetch (a ::) (sequence_Fetch ms))` scans `m`
   before `ms` and keeps result order; `gridF` is row-major, `tabbedF` zips labels back in
   order. Header comment accurate (the "hoist it" paragraph is gone; the ORDER paragraph matches
   the code and (fxl-order)). `Layout.Doc` does not import `Layout.Fetch` (checked).
3. **Headline widget.** Ermine props/`headline`/`headlineOf` load; zod
   (`client/src/generated/headline.ts`) matches the Ermine record field for field
   (`rowCount: z.number().int()`, two `z.number()`, `headlineFormat` lazy `CellFormat`),
   `props.ts` matches, the component reads the six props and formats `total`/`largest` through
   `format.ts`, `defaultRegistry()` has the line, `check-generated` is current. Empty relation:
   `0 / 0.0 / 0.0`, documented, pinned by (fx1) and (fxl-headline). **Negative numbers: WRONG
   `largest`** (required fix R1). The max over non-negative data is right ((fx1): 2310.25 and
   4100.0).
4. **Properties.** None can pass vacuously: every (fxl) case counts a non-200 status as a
   failure, (fxl-order) asserts >= 18 multi-leaf trees (exactly 18 in the seeded run -- at the
   threshold, but the seed is fixed), all six combinators, >= 40 scans; (fxl-laws) requires both
   request defaults; (fxl-sugar) requires both delivery arms; (fxl-headline) requires >= 1 empty
   and >= 10 multi-row cases. Seeded samples via `TestDoc.samples(gen, n, seed)` (`Gen.apply`
   with `Seed(seed + i)`) are deterministic; the cost argument for 24/12/20/20 instead of 100 is
   reasonable (each case writes and loads one or two modules). What the seeds do NOT reach: an
   all-negative relation in (fxl-headline) (R1). `RecordingScanner` and `CountingRun` are both
   per-thread and `render` is in-process on the calling thread, so the marks and the counts are
   the request's own.
5. **Dialect and scope.** Grep over the added Scala: no `given`/`using`/`enum`/`extension`/
   `export`/`derives`/`LazyList`/`CollectionConverters`/JDK 9+ API/top-level defs/`*` imports;
   `Either` is used only through `.right.flatMap`/`.left.map`; `Gen.sequence[C, T]` and
   `Gen.zip` 3-ary already occur in `TestDoc.scala`/`TestNamedFields.scala` on the base.
   `abstract class Scanner[G[_]](implicit G: Monad[G])` takes the `()(under.M)` call. Line
   endings preserved (all touched files LF). Nothing under `core/examples/`;
   `tracker/repl-classpath.txt` untouched. Untracked and NOT part of the stage:
   `tracker/json-stage3/brief-J3h-interp.md` (the orchestrator's next brief -- it says "on top
   of J3g (committed)") and `tracker/json-stage3/logs/` (earlier stages did not track logs
   either). The orchestrator should decide whether the J3h brief is committed with J3g.
6. **Docs.** Section 3.4c and the corrected 3.4b "Cost" line are accurate and short; the J3g
   plan row and handoff entry are accurate. `client/README.md` is right (two native widgets,
   the headline row, the one sentence on a `Fetch Node` constructor).

## REQUIRED fixes

**R1. `headlineOf`'s `largest` is not the maximum over negative data.**
- `core/src/main/resources/modules/Layout/Widgets/Headline.e:57`:
  `(foldl (a b -> if (b > a) b a) 0.0 xs)`. Failure: a relation whose `f` values are all
  negative (a loss column, a delta) reports `largest = 0.0`, a number that is in no row; REPL:
  `foldl (a b -> if (b > a) b a) 0.0 [-1.5, -2.0]` = `0.0`. The brief says "takes the max of the
  field"; the comment at `:48-49` only promises `0.0` over NO rows. Fix: fold from the first
  element, e.g. `case xs of { [] -> 0.0 ; (y :: ys) -> foldl (a b -> if (b > a) b a) y ys }`
  (or `maximum`-style over `Double` if the stdlib has one), keeping `0.0` for the empty case;
  then `bin/ermine :load core/src/test/resources/doc/FetchHeadline.e`.
- `scalacheck-binding/src/main/scala/TestRunner.scala:1385`: the oracle
  `xs.foldLeft(0.0)((a, b) => if (b > a) b else a)` restates the bug. Fix:
  `if (xs.isEmpty) 0.0 else xs.max`.
- `scalacheck-binding/src/main/scala/TestRunner.scala:1364-1366` and `:1395`: the generator
  (`Gen.choose(-9999, 99999) / 8.0`, ~9 % negative per value) never yields a non-empty
  all-negative relation in the 20 samples of seed 31337 (my mutation B run,
  `logs/review-mutation-AB2.log`: the oracle with the true max still passed and the
  all-negative `println` never fired). Fix: give the generator an explicit all-negative arm
  (e.g. `Gen.frequency((3, mixed), (1, allNegative))` with `Gen.choose(-9999, -1) / 8.0`) and
  add the anti-vacuity conjunct
  `(cases.exists(c => c._1.nonEmpty && c._1.forall(_ < 0))) :| "no all-negative relation"`,
  so the property is red on the current `Headline.e` and green after the fix. Re-run
  `core/testOnly *TestRunner *TestWidgets` once (the headline is also generated by
  `TestWidgets (a)`, but with non-negative literals, so that suite should stay green).
- `tracker/JSON-API-DESIGN.md:529` says "takes the maximum" -- true after the fix; no change.

That is the whole required list: one widget line, one oracle line, one generator arm.

## Optional suggestions (not required for landing)

- **S1** (fxl-order): `multi >= 18` is met exactly (18 of 24); with a different seed it could
  flip. Either lower the bound to 16 or raise `orderCase`'s minimum depth to 2. Deterministic
  today, so not required.
- **S2** (fxl-laws): under mutation A (continuation scans dropped) the three laws stayed green
  because law (2)'s continuation and law (3)'s `done` never scan. Making (2)'s `k` scan (the
  same one-row literal law (3) uses) would make the laws see `bind_Fetch`'s second equation;
  (fxl-order)'s `bind_Fetch` nodes already cover it, so this is depth, not a gap.
- **S3** `client/src/widgets/headline.ts:37` duplicates `text()` from `scorecard.ts:31`; a
  shared helper in `format.ts` would remove the copy.
- **S4** `tracker/JSON-STAGE3-PLAN.md:207-208`: the J3g row sits above the J3f row, and the
  J3g handoff entry (`:383`) sits above the J3f LANDED entry (`:401`); chronological order would
  read better.
- **S5** `resultKind` still returns `Option[Boolean]` whose `Boolean` nobody reads
  (`Runner.scala:471 case Some(_)`); an `Option[Unit]` or a `Boolean` would say so. Cosmetic.
- **S6** Seen under mutation A, pre-existing and not J3g's: `relation (withRunning [])` over an
  empty scan is the "empty relation built from no rows carries no columns" 500
  (`FetchFragments.runningTable`, `FetchRunning`). With the fixture data it cannot happen; a
  `mkRelationWithHeader#` there would make the fragments total on empty input. J3h's call.

FIX-THEN-LAND
