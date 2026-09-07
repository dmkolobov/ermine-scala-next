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
    E4 §4.6.) — stage F1.

A2. **`Console.other` loops forever on a piped line containing `case`, `let` or `where` as a substring.**
    `Console.scala:149`: `readLine` returns `null` at EOF, `null == ""` is false, so `blank` never flips; each
    iteration appends `"\n" + null` and re-runs `balanced()` and three `contains` over the growing string.
    Minimal input: `printf 'staircase\n' | bin/ermine` (thousands of `|>` prompts, never exits); control
    `staircas` exits cleanly. This is the long-known "REPL pipe quirk". **Fix:** treat `null` as EOF; match
    the keywords as tokens, not substrings. (E4 §4.7, E4-REVIEW.) — stage F2.

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
    cannot read back. (E3, E4 §4.3.)

B5. **The projection fan-out cliff.** N projections of ONE open-row record parameter cost 3 / 30 / 212 / 1,232
    / 6,804 fresh row variables for N = 2..6 (every draw a `Resolution`, no split); N = 7 exhausts the adopted
    20,000-draw budget and a VALID program is rejected with the resource diagnostic. The same reads under one
    written partition cost 0. `Present/ProjectionCost.e` + `shouldfail/proj01_seven_reads.e` pin it; the
    model reproduces the budget stop at the same count. **This is the one known shape on which the adopted
    budget rejects a valid program.** (E4-REVIEW M-*, E4 §4.) — stage S4 candidate (guard the repeated
    projections of one record, or raise the budget with a measured justification).

B6. **Refutation blame wording is a propagation reason, not a description, and it varies with load order**:
    the same module prints a different clause of the same refutation per file vs in a batch, and on
    `shouldfail/inf02` the blamed FIELD moves; the clause follows the id base (a census must state its file
    order). (E1 §7.5, E2 F4, E3 P-*, E4.)

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
    over a row). (E1, E3, E4.)

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
