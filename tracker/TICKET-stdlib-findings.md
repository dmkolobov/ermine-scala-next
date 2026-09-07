# TICKET: stdlib and language findings from the example-corpus programme (E1–E5, 2026-09-06/07)

Every item below was found while writing the new example groups under `core/examples/{Wide,Algebra,Time,
Present,Lang}/` and CONFIRMED by an independent reviewer with a minimal module (the reports and reviews are
under `tracker/loopmodel/E<n>-EXAMPLES.md` / `E<n>-REVIEW.md`; the section that holds the reproduction is
cited per item). Items are grouped by what they are — a runtime bug, a type-system hole, a wrong or misleading
API, a tooling defect — and ordered within a group by severity. "Fix" states the change the finding implies;
none of these fixes has been made unless a later line says so.

## A. Runtime bugs

A1. **`record#` returns a Scala 2.13 `MapView`; every consumer that pattern-matches `Map` panics when forced.**
    `Lib.scala:988` (`scalaRecord#`, `case Prim(t: Map[...])`), `:1007` (it would return a `MapView` itself),
    `:1012` (`scalaRecordIn#`, live at `Layout/Report.e:1594,1608`). Affected: `Relation.Pivot.pivot`,
    `Relation.Predicate.all`, `Record.header`, `Record.anyRecordOrd`, `Relation.Sort.partialRecordOrd`,
    `Relation.nonEmptyRelation`, `Layout.Chart.srecKeys`, `Layout.Presentation`, `Native.Record.header#`;
    `core/examples/PivotTest.e`'s `pivotData` has panicked for years. `Relation.relation` is NOT affected
    (`mkRelation#`), which is why relation renderings work. Nobody saw it because everything is lazy.
    **Fix:** three `.toMap` (988, 1007, 1012) plus a test that FORCES a pivot. (E1 §7.2, E1-REVIEW §MapView,
    E4 §4.6.) — stage F1. **FIXED in `254110b`** (stage F1, 2026-09-07): the three `.toMap`s are in
    (`Lib.scala:997`, `:1016`, `:1021` after the added comment), and eight new `core/test` properties in
    `scalacheck-binding/src/main/scala/TestRecordPrims.scala` FORCE a pivot, `Relation.Predicate.all`,
    `Record.header`, `header#`, `scalaRecord#` and `scalaRecordIn#` to values and check them; all eight
    fail on the pre-fix compiler (measured as a negative control). `PivotTest.pivotData`,
    `Wide/MediaSpend`'s two pivots, `Present/FulcrumPanel.bothHalves` and `Algebra/SoftSchema`'s two
    pivots now evaluate, and the six `q_pivot_*` probes in `sql-render.sh` get past the panic to the
    SAME pre-existing wall every other `Mem` probe hits (`Don't know how to dump a mem`,
    `Scanner.scala:35` — no `SqlScanner` override), so the panic is gone but a pivot still renders no
    SQL; the 15 renderings that did work are byte-identical. Details and every gate:
    `tracker/loopmodel/F1-FIXES.md`.

A1b. **Three more `MapView` sites survive where the compiler cannot reject a view: equality and hashing.**
    `SqlScanner.scala:644` — `kr == k` is always false against a view, so the IN-MEMORY pivot gives every column
    its default on the first row of each group; `SqlScanner.scala:708` — `Tee.hashJoin`'s key is a view, so the
    lookup never matches and the join emits nothing; `relational/package.scala:67` — the chunk predicate is always
    false, so `sorting` never groups. The correct spellings sit nearby (`SqlScanner.scala:629/630`, `:538`,
    `Optimizer.scala:277`). Pre-existing, out of F1's scope, unreachable from the corpus (every pivot stops at
    `dumpMem`), same family as A1 on the feature A1 unblocked. **Fix:** `.toMap` at the three sites plus a test
    that drives the in-memory pivot/join/sort path. (F1-REVIEW J-3; `tracker/03-core-progress.md` records the
    migration converted "only the ~20 sites the compiler rejected".)

A2. **`Console.other` loops forever on a piped line containing `case`, `let` or `where` as a substring.**
    `Console.scala:149`: `readLine` returns `null` at EOF, `null == ""` is false, so `blank` never flips; each
    iteration appends `"\n" + null` and re-runs `balanced()` and three `contains` over the growing string.
    Minimal input: `printf 'staircase\n' | bin/ermine` (an unbounded stream of `|>` prompts — the count in any
    report is a time-boxed iteration count, not a durable number); control `staircas` exits cleanly. This is the long-known "REPL pipe quirk". **Fix:** treat `null` as EOF; match
    the keywords as tokens, not substrings. (E4 §4.7, E4-REVIEW.) — stage F2, done early in F1.
    **FIXED in `254110b`** (stage F1, 2026-09-07): both halves. `Console.opensLayout` matches the three
    keywords as WORDS (a boundary that excludes `'` and `#`, so `case'` and `let#` stay names), which is
    what stops `staircase` / `"complete"` opening a continuation at all; and
    `blank = (last == null) || (last == "")` ends the continuation at EOF, which is what makes a line
    carrying a REAL keyword terminate (`printf 'f x = case x of\n' | bin/ermine`: 2,493 prompts and rc=124
    before, 1 prompt and rc=0 after). `tracker/repl-tests/pipedeof.in` pins both, plus that the multi-line
    `case`/`let` continuations still work, and `repl-smoke.sh` now runs every input under a timeout and
    fails on a non-zero exit so such a hang cannot come back silently.
    Details: `tracker/loopmodel/F1-FIXES.md`.

A3. **`Date`'s accessors read the instant in the JVM's default timezone; its formatters do not.** `@2011/1/1`
    is simultaneously `"1/1/11"` and `"Dec 31"`; `getMonth` is 11 under MDT and 0 under UTC;
    `formatPeriodOr "custom" (1 Jan, 31 Jan)` is `"Jan 2011"` on one machine and `"custom"` on another.
    **Every `DateRange` period label is machine-dependent.** Measured with and without `-Duser.timezone=UTC`.
    **Fix:** one timezone (UTC) for both, or make it a parameter. (E3 §8 FiscalTree; E3-REVIEW.)

A4. **`Date.formatQuarter` is wrong twice over:** `getMonth d / 4 + 1` divides by four, then indexes a 0-based
    list with a 1-based number — quarters are four months long and `"Q1"` is unreachable (January prints
    `"Q2"` under UTC). **Fix:** `/ 3`, 0-based index. (E3 §8.)

A5. **`SqlEmitter` flattens a non-left-deep join tree without parentheses** (`SqlEmitter.scala:262` emits both
    operands bare: `A JOIN B ON c1 JOIN C JOIN D ON c2 ON c3`). SQL-92/T-SQL/Postgres re-associate it; SQLite's
    flat join grammar rejects it (`near "on": syntax error`). A portability bug in the emitter. (E2-REVIEW,
    E1-REVIEW §N-10.)

A6. **Window functions emit real SQL only on the MS SQL emitter**; every other emitter writes
    `TODO I don't yet know how to play … over …` into the query. (E1 §7.3.)

A7. **A foreign exception becomes a `Bottom` VALUE, so nothing can catch it.** `Runtime.scala:51`'s `Prim.apply`
    converts the exception, so `IO.Unsafe.eval`'s try/catch (`Lib.scala:1311`) never fires, `Parse.numberFormat`'s
    `NumberFormatException` branch is dead, and `IO.catch` cannot catch a foreign exception either
    (`catch (readFile "/nope") …` → `<error: …>`). Consequence: `Parse.parseInt`/`parseDouble` are not total —
    `isJust (parseInt 10 "1O2")` is `True` (a `Just <error>`), and a hand-written "total" parser still bombs on
    overflow (`parseIntTotal "99999999999999"`). (E5 finding 2, E5-REVIEW L-*; ticketed with A2's family of
    runtime traps.)

A8. **`File.readFile` calls `traceShow` through `System.console()`**, which breaks an `IO.CSV` read from a piped
    or non-console session; the read itself works. (E5-REVIEW.)

## B. Type-system holes (things that type-check and should not, or vice versa)

B1. **`Relation.Op.dateDiff`'s wrapper has no signature** (`Relation/Op.e:150` commented out), so it infers
    `Op r2 Int` with `r2` FREE: `combine_Op (dateDiff …) gap t` type-checks over a relation carrying neither
    date and fails only at header computation (`Operation refers to nonexistent column`). A static guarantee
    silently deferred to run time. **Fix:** the one-line signature. (E3 §finding; E3-REVIEW P-3.)

B2. **A row variable written in the `[f1, f2]` relation-type syntax is read as a LABEL.**
    `mk : Field c String -> [aid, c]` checks, and `:type mk` is `forall (c: rho). … Relation (|aid, c|)` — the
    mistake surfaces at a later call site. (E2 F3, E2-REVIEW Q-*.)

B3. **The `.ei` printer publishes a free row variable it does not bind** (general: a two-line module
    reproduces it; it round-trips, so it is a printing defect). (E4 §4.2, E4-REVIEW.)

B4. **An `AsOp`-polymorphic helper's inferred signature cannot be written down**: it contains an existentially
    quantified CLASS, `(exists (AsOp: b). AsOp op, …)`. Three of five affected helpers in `Present/`, and
    `Time.bucketBy` (four `AsOp` existentials + `forall {a}`) — the compiler prints a type its own parser
    cannot read back; the minimal case is `atAnyKind` (E5-REVIEW). (E3, E4 §4.3.)

B5. **The projection fan-out cliff.** N projections of ONE open-row record parameter cost 3 / 30 / 212 / 1,232
    / 6,804 fresh row variables for N = 2..6, and (model replay without the budget) 35,923 at N = 7 and 185,848
    at N = 8 -- about 5.3-6x per extra read, every draw a `Resolution`, no split; N = 7 exhausts the adopted
    20,000-draw budget and a VALID program is rejected with the resource diagnostic. The same reads under one
    written partition cost 0, and the remedy is the annotation and only the annotation: reordering the helper's
    arguments changes nothing (1,230 → 1,233 draws), annotating the lambda takes it to 1 (E5-REVIEW).
    `Present/ProjectionCost.e` + `shouldfail/proj01_seven_reads.e` pin it; the
    model reproduces the budget stop at the same count. **This is the one known shape on which the adopted
    budget rejects a valid program.** (E4-REVIEW M-*, E4 §4.) — stage S4 candidate (guard the repeated
    projections of one record, or raise the budget with a measured justification).

B6. **Refutation blame wording is a propagation reason, not a description, and it varies with load order**:
    the same module prints a different clause of the same refutation per file vs in a batch, and on
    `shouldfail/inf02` the blamed FIELD moves; the clause follows the id base (a census must state its file
    order). (E1 §7.5, E2 F4, E3 P-*, E4.)

B7. **The `.ei` interface is neither a subset nor a superset of the module**: it lists `private` names importers
    cannot see and omits `foreign` names they can (proved both ways by importing). (E5 finding 7, E5-REVIEW.)

B8. **A rank-2 function argument cannot be applied at all**: `oneWay nat a = nat a` fails with
    `failed to unify type (forall x. f x -> m x) with type (a -> b)` — which explains the shape of every
    `Control.*` dictionary and why `Data.Free` has no `foldFree` (a generic one loads only through a `Nat`
    data-field wrapper). (E5-REVIEW.)

## C. Wrong, misleading or missing API

C1. **`Relation.UnifyFields.unify1` cannot unify differently-named schemas** — the one thing it is named for:
    its constraints force the operands to agree on every column but one each, and `f1` appears in no
    constraint; only same-header self-joins load. (E2 F1.)
C2. **`Relation.join1` is `joinBy {f}`**, not "the intersection is nonempty" as its doc comment says
    (`r <- (k, r1, r2)` is a partition, so `f` is the whole key). (E2 F2.)
C3. **`lookupLatest`/`nearestDate` group by the DATE ALONE**: a multi-series history silently loses whichever
    series stopped reporting; `nearestDate` maps dates to dates and forces both relations to one column.
    (E3.) `asOfWithin` is a binary gate on the as-of answer, never a per-row staleness filter. (E3 §8.)
C4. **`weightedMean` forces value and weight to one type** (needs `annul`). (E3.)
C5. **`rename'` is misnamed** (its doc is right; it requires the destination column to already exist);
    **`Relation.Scan.sumBy'` carries a vacuous `r <- (h,t)`**; **`Layout.Scan` omits exactly `removeK`,
    `removeBy`, `multiply`**. (E2 F7–F9.)
C6. **`Relation` and `Mem` have no conversion back**: `filterEq`/`firstBy`/`lastBy`/`leafRows`/`lookupLatest*`/
    `unionAll` are `Relation`-only, `groupBy`/`accumulate`/`medianBy` return `Mem`, `join`/`union`/`difference`
    insist both operands be the same `rel`, and `asMem` goes one way — so a report that groups and then
    filters must push `asMem` outward through the whole expression (eight of ten Algebra modules carry an
    `asMem` for that reason alone). (E2 §7.)
C7. **`Layout.Magnitude` is box sizes, not number scaling**; **`Double.e` is an empty module**; there is no
    `year`/`month`/`quarter` op; `Math`/`Vector` cannot be lifted into an `Op` (no rolling median/percentile
    as a column). (E3, E4.)
C8. **`render` is not a defined term anywhere** (every `Ai/*.e` header's recipe is not executable);
    `Layout.harness` needs a `Scanner` + `Runner`, and the writers live in the sibling `ermine-writers`
    project (HTML/JavaFX/JSON/CSV/PDF, one Ermine-facing type `Scanner f -> Runner f -> Writer f z`; 4 of 6
    use the `harness'` entry). The obstacle to rendering from `bin/ermine` is a writer jar on the classpath,
    not a database (`Runners.sqlite` takes a JDBC URL). `tracker/tools/sql-render.sh` executes relations as
    SQL meanwhile; it cannot dump a `Mem`. (E1 §7.1, E3, E4 §4.1.)
C9. **`Random` draws from one shared generator per stream through `unsafePerformIO`** — reproducibility is a
    property of evaluation order. (E3.)
C10. Small language facts worth a guide chapter: fields may not shadow globals; `map` needs `Syntax.List`; `Op`
    arithmetic is homogeneous (`fromNumericOp`); `'` is `infixl 0`; duplicate `field` declarations across
    modules do not clash (keyed by name and type) but duplicate top-level TERM names do (`undefined term` in a
    multi-module session); variadic melt / relation-level dynamic pivot are inexpressible (no type-level fold
    over a row); the character-literal rule is positional (`'/'` fails after `==`, `'-'` works as an argument);
    there are no operator sections; a suffixed bracket/brace literal cannot be a non-final argument, a pattern, or
    precede `where`; `Prelude`'s `length`/`++` are `List`'s and `||` is `Layout.Report`'s. (E1, E3, E4, E5.)

C11. **`String.Markdown.link`'s type is `(String -> String) -> String -> String`** — it CAN make a link
    (`link ((++) "SUP-77/A") loc`), but the shape is a trap; E5's claim that it cannot was refuted. (E5-REVIEW.)

## D. Claims in older documents that do not reproduce

D1. `core/examples/Ai/README.md`'s RUnion table ("a helper bundling `RUnion3` and `RUnion2` does not finish")
    does not reproduce at either the adopted or the old configuration (bundled form 1.2–1.5× the inline, on
    the very module it measured; and the README never names its module). Three E-stages reconstructed it
    three ways. Soften the claim. (E1, E2-REVIEW, E3.)
D2. `TICKET-row-constraint-decision.md` states Rémy-style row unification is polynomial; no primary source
    supports it (Pottier & Rémy, ATTAPL §10.8: "the complexity of row unification remains unexplored").
    (`tracker/ROSE-COMPARISON.md` §2.)

## Fixed in this programme

- `Subst.mkSimplified`: permuted duplicate residual constraints survived `List.distinct` because `NormalPart`
  overrode `equals` but not `hashCode`; the `a <- (a)` tautology was never dropped. — stage S3 (see
  `tracker/loopmodel/S3-SIMPLIFY.md` when it lands).
- `TestSurfaceParsers.scala` asserted an exact corpus size (`files ?= 271`); now derived with a floor.
