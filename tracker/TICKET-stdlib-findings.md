# TICKET: stdlib and language findings from the example-corpus programme (E1–E5, 2026-09-06/07)

Every item below was found while writing the new example groups under `core/examples/{Wide,Algebra,Time,
Present,Lang}/` and CONFIRMED by an independent reviewer with a minimal module (the reports and reviews are
under `tracker/loopmodel/E<n>-EXAMPLES.md` / `E<n>-REVIEW.md`; the section that holds the reproduction is
cited per item). Items are grouped by what they are — a runtime bug, a type-system hole, a wrong or misleading
API, a tooling defect — and ordered within a group by severity. "Fix" states the change the finding implies;
none of these fixes has been made unless a later line says so.

Later stages outside E1–E5 add items here when what they find is a stdlib or published-API defect rather than
a solver question; such items name their stage. **C12** (2026-09-08) is the first, from the loop-model
programme's stage R3 and its review.

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
    migration converted "only the ~20 sites the compiler rejected".) — stage F3.
    **FIXED in `775a20f`** (stage F3, 2026-09-08): the three `.toMap`s are in
    (`SqlScanner.scala:649` the pivot's bootstrap key, `:719-720` the hash join's two key
    functions, `relational/package.scala:72` the sort's chunk predicate), and five new
    `core/test` properties in `scalacheck-binding/src/main/scala/TestInMemoryScan.scala`
    DRIVE the in-memory pivot, the hash join and the sort and check what they emit.
    Four of the five fail on the pre-fix compiler, measured as a negative control with only
    the three `.toMap`s reverted: the pivot answered `xs -> -1` (the DEFAULT) for the row
    that opened every group, the hash join answered the EMPTY SET, and `sorting` gave the
    input order back; the fifth is an already-sorted stream, unchanged either way, and is a
    regression guard rather than a discriminator.  `pivot` and `hashJoin` became
    `private[relational]` so the test can drive them; nothing else about them changed.
    None of the three is reachable from an Ermine program — `Scanners.e` publishes only
    `dumpClosed`, so the REPL can dump a relation's SQL and can never execute a `Mem` — which
    is why the properties drive them directly rather than through a scan.  Every other
    `mapValues`/`filterKeys`/`.view` in `core/src/main/scala` (115 hits, 9 of them in the
    fully commented-out `Access.scala`) was checked one by one and is listed in the report.
    Details and every gate: `tracker/loopmodel/F3-FIXES.md`.

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
    **Fix:** one timezone (UTC) for both, or make it a parameter. (E3 §8 FiscalTree; E3-REVIEW.) — stage F3.
    **FIXED in `775a20f`** (stage F3, 2026-09-08), the first of the two: ONE timezone, UTC.
    `PrimExprs` gains `getYear`/`getMonth`/`getDate` reading a `GregorianCalendar` in
    `YMDTriple.ymdPivotTimeZone` — the zone `dateFormatterTLV` already pins every formatter
    to — and `Date.e` binds the three names to those instead of to `java.util.Date`'s
    deprecated methods.  The CONVENTIONS are unchanged (`getYear` is the year minus 1900,
    which `core/examples/Yahoo.e` relies on; `getMonth` is 0-based; `getDate` is the 1-based
    day), and `getTime` is epoch milliseconds and was never affected.  Measured on this
    machine (default zone America/Denver): `@2011/1/1` answered `getMonth 11, getDate 31,
    getYear 110` before and answers `0, 1, 111` now — the same as under `-Duser.timezone=UTC`
    and the same under `Pacific/Kiritimati` (UTC+14), `Asia/Tokyo` and `Pacific/Niue`
    (UTC−11): five zones, one answer.  **Published behaviour that changes on a non-UTC
    machine**: `Date.getYear/getMonth/getDate`, `Date.formatExcelDate`, `Date.quarter`,
    `Date.formatQuarter`, `DateRange.formatPeriod`, `DateRange.formatPeriodOr`,
    `DateRange.formatExcelPeriod`, and in the examples `Yahoo.e`'s URL builder (which was a
    day out) and `Time/FiscalTree.e`'s ten `periodLabel*`/`jan*Number`/`*QuarterLabel`
    bindings.  Nothing that goes through a formatter moves, and no SQL rendering moves.  A
    timezone PARAMETER is still not offered.
    **STILL OPEN IN THE SAME FAMILY, found in the F3 fix round and NOT fixed:** date
    ARITHMETIC is still in the default zone.  `Date.incrementDate` / `decrementDate` /
    `incrementTimestamp` go through `com.clarifi.reporting.TimeUnit.increment`
    (`Op.scala:291`, `:313`), which builds a `Calendar.getInstance` — the JVM's default zone —
    and adds there.  Adding whole days is offset-invariant EXCEPT across a daylight-saving
    transition, where the local day is 23 or 25 hours and the result lands on the wrong UTC
    day.  Measured: `incrementDate 1 days @2011/3/13` is `"3/14/11"` under
    `-Duser.timezone=UTC` and `"3/13/11"` under `America/Denver` (13 March 2011 is the US
    spring-forward); `@2011/11/6`, the autumn transition, does not move.  The fix is the same
    one line — `Calendar.getInstance(YMDTriple.ymdPivotTimeZone)` — but it CHANGES the answer
    of a shipped function on a non-UTC host, so it wants its own stage and its own gates
    rather than a footnote here.  `Date.e`'s header now scopes its "one timezone" claim to
    reading and formatting and names this.
    Details: `tracker/loopmodel/F3-FIXES.md`.

A4. **`Date.formatQuarter` is wrong twice over:** `getMonth d / 4 + 1` divides by four, then indexes a 0-based
    list with a 1-based number — quarters are four months long and `"Q1"` is unreachable (January prints
    `"Q2"` under UTC). **Fix:** `/ 3`, 0-based index. (E3 §8.) — stage F3.
    **FIXED in `775a20f`** (stage F3, 2026-09-08): `quarter d = getMonth d / 3 + 1` and
    `formatQuarter d = orElse "Unknown" (at (quarter d - 1) quarterNames)`.  `quarter` keeps
    its 1-based meaning, which is the one its name and `quarterNames` have; the index is
    where the off-by-one is fixed.  The twelve month-firsts of 2011 now label
    `Q1 Q1 Q1 Q2 Q2 Q2 Q3 Q3 Q3 Q4 Q4 Q4` (they were `Q2 Q2 Q2 Q2 Q3 Q3 Q3 Q3 Q4 Q4 Q4 Q4`
    under UTC and `Q4 Q2 Q2 Q2 Q2 Q3 Q3 Q3 Q3 Q4 Q4 Q4` under this machine's MDT default
    zone, which is A3 on top of A4), and two `core/test` properties pin all twelve.
    Details: `tracker/loopmodel/F3-FIXES.md`.

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
    silently deferred to run time. **Fix:** the one-line signature. (E3 §finding; E3-REVIEW P-3.) — stage F3.
    **FIXED in `775a20f`** (stage F3, 2026-09-08): the wrapper now carries `dateAdd'`'s
    signature, one line above it in the same file —
    `dateDiff : (AsOp op1, AsOp op2, RUnion2 t r1 r2, PrimitiveTemporal d) => TimeUnit ->
    op1 r1 d -> op2 r2 d -> Op t Int` — so the result row is the union of the operands'.  The
    commented-out line it replaces would not have fixed anything: `r2` was free there too, and
    `AsOp op1 op2` is not a constraint the parser accepts.  The reproduction (a `combine_Op` of
    a date difference over a relation carrying NEITHER date) LOADED before and answered
    `<relation with Failure(NonEmpty[Operation refers to nonexistent column (startDate) in
    header., …])>` only when forced; it is now rejected statically with `Row partitions are
    unsatisfiable at field '…startDate': the whole contains it but no part does`, and it is in
    the corpus as `core/examples/Time/shouldfail/date01_datediff_free_row.e` — the one
    deliberate corpus change of this stage — plus two `core/test` properties, one positive and
    one negative.  The PRIMITIVE `dateDiff#` still publishes a free result row, as `dateAdd#`
    always has; the wrapper is what users call.  **`core/examples/Time/Helpers.e` still declares
    `dayCount : forall r r1 out. …`, and that signature is still ACCEPTED for that body, so a
    caller who goes through the example helper rather than through `dateDiff` still gets the
    deferred failure**; tightening it to `RUnion2 out r r1 => …` was measured in F3 to load the
    whole `Time/` group cleanly and is left as a one-line follow-up, with the helper's comment
    updated to say so.  **That follow-up is now ticket B1a below** (eight helpers, not seven — F3 review N-7/N-8), so it is not parked inside a FIXED entry.  Details: `tracker/loopmodel/F3-FIXES.md`.

B1a. **Eleven example helpers still publish a FREE result row, so B1's static guarantee stops at the
    stdlib boundary.**  Opened 2026-09-08 by the F3 review (finding N-8); B1 itself is fixed.
    `core/examples/Time/Helpers.e` declares **eight** helpers as `forall … out. … -> Op out …`
    with `out` constrained by nothing — `dayCount` :288, `yearFrac365` :293, `monthsBetween` :303,
    `monthsSince` :309, `daysSince` :313, `daysUntil` :319, `yearsOn` :324, `yearFrac360` :330 —
    and every one of those signatures is still ACCEPTED for its body after `Relation.Op.dateDiff`
    was tightened, so `combine_Op (dayCount_H f g) gap r` over a relation carrying NEITHER date
    still type-checks and still fails at header computation with `Operation refers to nonexistent
    column`.  That is exactly the defect B1 was raised for, one level up.
    `core/examples/Time/Signatures.e` mirrors it in `yearFrac365Full` (`out <- (out)`, the
    tautology), `yearFrac365Deduped` and `yearFrac365Simple` — the last labelled "What `Helpers.e`
    ships, specialised to `Date`" — while its `pctChange*` and `safeDiv*` families all constrain
    `out` properly, so the hole there is exactly those three.  The two PRIMITIVES `dateDiff#` and
    `dateAdd#` (`Relation/Op.e`) also still publish a free result row; that is deliberate — they
    are the raw foreign imports and the wrappers are what users call — but it is the reason the
    hole is one `unsafe` step away for anyone who reaches past a wrapper.
    **Fix:** `RUnion2 out r r1 => …` on the eight, and a decision on the three exhibits.  MEASURED
    in stage F3: tightening the eight loads the whole `Time/` group cleanly (all eleven modules
    import), so this is a one-line-per-helper change and not a design question.  It was left out of
    F3 because it is an example-level change the brief did not scope and it moves eight published
    signatures.  (F3 review N-8; `tracker/loopmodel/F3-FIXES.md` §5.)

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
    projections of one record, or raise the budget with a measured justification). **FIXED behind a flag in `c48f178`** (stage S4, 2026-09-07): `-Dermine.topNormalise`, DEFAULT OFF -- the written-partition normalisation (k >= 3 distinct pairwise-incomparable lone-abstract reads at one lhs, no concrete row, no self-read -> `v <- (c, F)` + `c_i <- (c, F \ F_i)` before every input reader); the ladder is one pre-loop draw at every N (measured 3/30/207/1,230/6,783 OFF for N = 2..6; ON: 3/0/0/0/0/0/0 for N = 2..8, ten reads compile in 0.04 s); `Present/WildChain.e` is the wild-code gate. **ADOPTED 2026-09-08 (default ON)** after stage S4c (`2747b47`, `a696d1c`) met both Lean prerequisites of `tracker/loopmodel/S4B-REVIEW.md` §5.2; `proj01_seven_reads.e` became `Present/SevenReads.e`, `Lang/ProjectionCliff.slow` a `.e`, and the `.ei` cache was cleared once. Rollback `-Dermine.topNormalise=false`.

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
    (`r <- (k, r1, r2)` is a partition, so `f` is the whole key). (E2 F2.) — stage F3.
    **FIXED in `775a20f`** (stage F3, 2026-09-08): the comment now says that it takes the join
    key EXPLICITLY and is exactly `joinBy {f}`, and spells out why — `r <- (k, r1, r2)` is a
    partition, so `r1` and `r2` are disjoint, and with `ra <- (k, r1)` and `rb <- (k, r2)` the
    intersection of the operands is exactly `k`.  Comment only: no signature and no `.ei` byte
    changed.
C3. **`lookupLatest`/`nearestDate` group by the DATE ALONE**: a multi-series history silently loses whichever
    series stopped reporting; `nearestDate` maps dates to dates and forces both relations to one column.
    (E3.) `asOfWithin` is a binary gate on the as-of answer, never a per-row staleness filter. (E3 §8.)
C4. **`weightedMean` forces value and weight to one type** (needs `annul`). (E3.)
C5. **`rename'` is misnamed** (its doc is right; it requires the destination column to already exist);
    **`Relation.Scan.sumBy'` carries a vacuous `r <- (h,t)`**; **`Layout.Scan` omits exactly `removeK`,
    `removeBy`, `multiply`**. (E2 F7–F9.) — stage F3.
    **FIXED in `775a20f`** (stage F3, 2026-09-08), all three as the brief scoped them.
    `Layout/Scan.e` re-exports `removeK`, `removeBy` and `multiply` (the last takes the runner,
    as `groupBy`/`sumBy`/`count` do); three `core/test` properties resolve them, and a module
    whose whole body is those three names failed to load before and loads now.
    `Relation/Scan.e`'s `sumBy'` loses `r <- (h,t)`, in which `h` and `t` occur nowhere else —
    the published interface printed them as FREE variables it did not bind, which is B3 as well
    as C5.  The other four signatures carrying the same tautology (`sumBy`, `avgBy'`, `count`,
    `count'`) keep it: deleting them one at a time is not the fix, C12 is.  `rename'` KEEPS its
    name, as the brief directs, and gains the doc line: it requires the destination column to be
    there already, because the `except {f2}` is what gives it its name, so it OVERWRITES rather
    than renaming into a fresh column.  Details: `tracker/loopmodel/F3-FIXES.md`.
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

C12. **[FIXED in `ed53fe7` 2026-09-09 (stage S5.1, uncommitted at the time of writing; `-Dermine.tautoDelete`
    DEFAULT ON).**  The theorem is `Rowpartition/Determined.lean`'s `tauto_delete` /
    `tauto_delete_two` (standard axioms; three necessity witnesses), and the deletion is
    `Subst.deleteTautologies`, at exactly the theorem's side condition, fired only from the
    generalisation that publishes a MODULE's signatures (`inferBindingGroupTypes`'s `publishing`
    parameter).  The adoption criterion — exactly these signatures shorten, every other interface
    byte-identical — IS met at that restriction: single-build flag A/B over 268 interfaces /
    3,481 bindings gives **identical 3,477, other 4**, and with the S5.2 interface key stripped
    exactly one file differs on exactly four lines.  Corpus verdicts AND messages are unchanged
    (85/69/0, zero differing lines), the `boot` and `Wide` row traces are byte-identical to the
    pre-change compiler, `core/test` green.
    TWO CORRECTIONS TO THIS TICKET.  (i) It is **four** signatures, not five: `sumBy'` was
    already fixed BY HAND in stage F3 (`Relation/Scan.e:113-117`), which C12's text predates.
    (ii) Fired at EVERY generalisation the deletion is sound but not confined -- it also moved
    `Layout.Report.Relation.cutoffGroupedFldsPosNegRel'` 40 -> 38 constraints and 13 bindings as
    alpha-variants -- and a `let`/`where` group counts as an intermediate generalisation, which
    is the distinction the fix turns on.  Full report: `tracker/loopmodel/S5-HYGIENE.md` §1 and
    "Follow-up: publishing-only deletion".]**

    **Five stdlib signatures publish a constraint that says nothing.**  `Layout/Scan.e`'s `sumBy` :44,
    `sumBy'` :43, `count` :47, `count'` :48 and `avgBy'` :45 each publish
    `(exists (t: rho) (h: rho). r <- (t, h)) => …` with `r` UNIVERSAL and both parts existential.  That
    qualification is a **tautology** — every row splits, `t := r`, `h := ∅` — so it constrains no caller,
    it cannot be discharged usefully, and it makes five signatures longer and harder to read than they are.
    It is also, measured, five of the **nine** genuinely row-ambiguous published signatures in the whole
    corpus (`tracker/loopmodel/R3-DETERMINED.md` §4.5, §4.7), so it is the single most common shape the
    row-ambiguity criterion of stage R3 finds.  **Fix:** delete it in `Subst.mkSimplified`, beside the
    tautology deletion S3 already does for `a <- (a)`.

    *What it needs first, and why R3 did not do it.*  A two-line theorem R3 does not have: R3 proves
    `dead_delete_of_pairwise` and `dead_delete_of_le_one_part`, and **both are about a dead existential on
    the LEFT**, whereas here the left-hand side is the universal (R3-REVIEW M-3).  The statement to prove is
    `REquiv ⟨ex ∪ {t,h}, insert (mk r {t,h} ∅) G⟩ ⟨ex, G⟩` when `t`, `h` occur nowhere else; the witness is
    `t := rho r`, `h := ∅`, of the same kind as the reviewer's `RevCheck.pairwise_not_necessary`
    (`/home/dmitry/.claude/jobs/880c725d/tmp/review-R3/Check1.lean`).  `Rowpartition/Determined.lean`'s
    `Residual` / `Holds` / `REquiv` are already the right vocabulary.

    *Acceptance criteria.*  (1) the theorem in `Determined.lean`, standard axioms; (2) the deletion in
    `mkSimplified`, behind no flag if the corpus is unchanged and behind one if it is not; (3)
    `tracker/tools/ei-diff.sh` over `core/examples` shows **exactly** the five signatures shortened and
    every other interface byte-identical — which is the question R3's splice measurement explicitly could
    not answer (`R3-DETERMINED.md` §7 item 6: how many published interfaces actually change); (4)
    `core/test` unchanged and the corpus verdicts unchanged.

    *And a warning is NOT part of this.*  R3 measured a row-ambiguity criterion and recommends against
    shipping one (`R3-DETERMINED.md` §5(ii)); if one is ever written it must be **signature-level and must
    never name variables** — `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` is flagged on 33 of its 34
    row existentials and only 16 are genuinely undetermined.  (R3, R3-REVIEW §6(iii).)

## E. The interface cache (`.ei`)

Opened 2026-09-09 by the S5 review (`tracker/loopmodel/S5-REVIEW.md`, findings Q-16 and Q-7).
Both are PRE-EXISTING and neither is stage S5's work; they are here because S5.2 made the
interface cache load-bearing (a mismatched key is now a full recheck) and both are exactly the
failure mode S5.2's own report warns about — a silent full recheck that no test sees.

E1. **[FIXED in `78adf6d` (stage F4, 2026-09-09; committed; originally written while uncommitted in the
    working tree at the time of writing).  The narrowing below is WRONG and F4 corrected it: it
    is not the partition SHAPE, it is the LABEL.  Any concrete row carrying a label whose last
    segment starts LOWER case fails to read back, in any position -- as a part of a partition,
    as an argument to `Relation`, as an argument to `Record` -- because
    `Pretty.qualifiedGlobal` publishes `(|Mod.label|)` under `FullyQualified` and
    `TypeParsers.rho` read it with `dottedName`, which requires EVERY segment to start upper
    case.  Re-measured scope: **70 of 241** corpus interfaces, not 18 -- the 18 counted only the
    interfaces publishing the partition shape.  The label census is 7,448 dotted-lower / 53
    dotted-upper / 34 empty, and the set of files holding a dotted-lower label is EXACTLY the
    set rewritten on every load.  The stdlib escaped because the only row label a REPL boot
    publishes is `Field.Count`; `Currency.ei` does NOT warm-read either, contrary to the note
    below -- it is simply not one of the 129 modules a plain boot loads.  Fix: a new
    `TypeParsers.dottedFieldName` used by `rho` (the module path in upper-case segments, then
    one ordinary identifier of any case); `dottedName` is untouched for `interfaceCon`.  On the
    PARSER, so NO published byte moves: the post-fix compiler read the 241 interfaces the
    pre-fix compiler had written and rewrote 0.  Three new properties in
    `scalacheck-binding/src/main/scala/TestInterfaceConcreteRow.scala`, all three measured RED on
    the pre-fix compiler.  Two printer forms remain unreadable and are recorded here rather than
    fixed, because neither is reachable from Ermine source: an abnormal (back-quotable) label,
    which `qualifiedGlobal` publishes WITHOUT its back-quotes under `FullyQualified`, and a label
    with operator fixity.  The two have DIFFERENT mechanisms and F4's first draft gave only one
    of them (F4-REVIEW R-6a): the operator label is blocked by `SurfaceParsers.fieldStatementP`,
    which takes `identTok`, so a declared field label is always `Idfix`, and by `typeName`'s
    `paren(opName(canonicalTypes))`, which refuses anything not already a registered type
    operator; the ABNORMAL label is blocked by the SOURCE row grammar itself, which does not
    admit a literal ident there -- `(| ``a b`` |)`, `(| ``ab`` |)` and `type R = (| ``a b`` |)`
    are all syntax errors, and `field ``a b`` : Int` is refused by `identTok` -- even though
    `TypeNameParsers.ident` is `super.ident | literalIdent`, which on a reading of the
    INTERFACE grammar alone would look admissible.  Cross-reference for
    the header-strip trap of `S5-HYGIENE.md` 2.3: every reader of an `.ei` goes through
    `Session.splitInterfaceKey`, and the new properties do too.  Report and every gate:
    `tracker/loopmodel/F4-ROUNDTRIP.md`.]**

    **An `.ei` publishing a partition with a CONCRETE part never warm-reads: 18 of 268 corpus
    interfaces are fully rechecked and rewritten on EVERY load, silently.**

    *Reproduction* (the reviewer's, `review-S5/probe/ConcProbe.e`).  A module whose published
    signature carries `X <- (…, (|lbl|))`:

    ```
    module ConcProbe where
    import Prelude
    cSig : r <- (h, (|foo|)) => Relation r -> Relation r
    cSig x = x
    c = cSig
    ```

    Load it twice with interfaces on.  The observable is the `.ei`'s mtime, because
    `writeInterface` runs on every `CheckMethod.Full` and on no `CheckMethod.Interface`: the
    file is rewritten on the second load too, and on the third, and does not converge.  A
    control module with classes, `exists` binders and several bindings but NO concrete part
    (`TautoProbe2.e`) warm-reads on the second load.  The key matches and the mtime is newer,
    so the only remaining `None` in `Session.dep`'s `preCk` is the PARSE: the printed form of
    a concrete part is not read back by `InterfaceParsers.interfaceSigs`.

    *Not concrete rows as such.*  129 of 129 stdlib interfaces warm-read, `Currency.ei`'s
    `Relation (|Currency.currencyName, …|)` included.  The cause is narrowed to the
    `X <- (…, (|lbl|))` form — a concrete row as a PART of a partition.

    *Scope, measured.*  **18 of 268** corpus interfaces publish that shape,
    `Layout/Report/Relation.ei` among them.  The cost is silent: those modules pay their full
    inference time on every load of a tree that is otherwise warm, and nothing fails.

    *Acceptance criteria.*  (1) A round-trip property in `TestInterfaceRoundTrip`'s style —
    its own temp workspace, `Session.depCache.clear()` under `ErmineFixture.literalLock`,
    modules owning every interface they depend on (`TestInterfaceKey` is the pattern) — that
    writes a module publishing `r <- (h, (|foo|))` and asserts the second load is
    `CheckMethod.Interface`; it must FAIL before the fix.  (2) The 18 corpus interfaces
    warm-read: two consecutive `bin/ermine` runs over the corpus rewrite 0 `.ei`.  (3) The
    printer and the parser agree on the whole published grammar, not just this shape — the
    cheapest form of that is a property that round-trips every `.ei` the corpus produces
    through `InterfaceParsers.interfaceSigs`.  (4) No published byte changes if the fix is on
    the READER; if it is on the PRINTER, the `.ei` sweep says exactly which interfaces move.

E2. **The WRITE side of the interface cache is frozen into the cached `Dep`, while the READ
    side is gated at call time.**  `Session.dep` builds `writeInterfaceString` as
    `if (s.useInterface) file.interfaceWriteback else (_ => ())` (`Session.scala:513`) and
    caches the `Dep` process-globally, but `preCk` — the read side — is deliberately always
    the real closure, with a comment saying why ("a dep cached by a useInterface=false suite
    must not poison a =true one").  The asymmetry means a dep first built by a
    `useInterface=false` session never writes an interface again, in any session, for the
    life of the process.

    *Why it matters more since S5.2.*  A key mismatch is now a full recheck; a dep carrying
    the no-op writeback is fully rechecked AND never re-keys the file, so it never converges.

    *Evidence.*  This is the mechanism behind both of stage S5's `core/test` failures
    (`S5-HYGIENE.md`, the fix-round and follow-up sections): a sibling suite building the
    `Primitive` dep in a `useInterface=false` session made `TestInterfaceKey`'s warm load
    answer `Full`.  The tests were made to own their own interfaces instead, which is right
    for the tests and does not fix this.

    *Acceptance criteria.*  Gate the write side at call time the way `preCk` is (pass the
    live `SessionEnv` into the writeback, or make `Dep.writeInterfaceString` take it), then:
    (1) the existing interface properties still pass, run alone and in the full suite; (2) a
    new property that loads a module in a `useInterface=false` session and then, in a
    `useInterface=true` session over the SAME `depCache`, gets `CheckMethod.Full` followed by
    a written `.ei` and a warm `CheckMethod.Interface` — failing before the fix; (3) the
    `.ei` sweep unchanged.

E3. **A published `.ei`'s BYTES depend on the load HISTORY of the session that wrote it: a
    cold-written tree and a warm-written tree differ in 16 of 241 interfaces.**

    Opened 2026-09-09 by the F4 review (`tracker/loopmodel/F4-REVIEW.md`, finding R-2).
    PRE-EXISTING and not stage F4's: the reviewer measured it with the PRE-FIX compiler on
    BOTH sides, so nothing about the F4 parser change is involved.

    *The measurement.*  Build the corpus tree cold (no `.ei` present, every module
    `CheckMethod.Full`); build it again in a session that read some interfaces warm; diff
    the bytes.  **16 of 241 interfaces differ** — 15 examples and
    `Layout/Report/Relation.ei` — in three ways: the QUANTIFIER SHAPE
    (`forall a b (k: rho)…` against `forall {a b} (a1: a) (b1: b) (k: rho)…`), an
    existential binder's KIND (`(Has: rho -> a)` against `(Has: a)`), and CONSTRAINT ORDER.
    All three are alpha-variants; none is a different type.

    *Why it matters.*  Every future `.ei` byte comparison has to control for it, the Tier 1
    interface sweep (`ei-diff.sh`) included: two sides that loaded in a different ORDER can
    differ without either compiler having changed.  It is also part of what a canonicaliser
    (`ROSE-COMPARISON.md` §3 rank 3) would have to absorb, and it compounds **B3** — the
    printer publishes a free row variable it does not bind, and `qtyp` re-binds it on read,
    which is one of the two places the quantifier shape can move.

    *What it does NOT overturn.*  F4's claim that its fix moves no published byte survives,
    because the strong form was measured directly rather than inferred: the post-fix compiler
    read all 241 interfaces the pre-fix compiler had written, rewrote 0 and moved 0 bytes.
    F4's report §6 has been corrected where it said the two sides' bytes are identical
    without qualifying the regime.

    *Acceptance criteria.*  (1) Say where the load-order dependence enters — the candidates
    are the `Supply` draw order reaching published existential names, `generalize`'s
    quantifier construction, and the kind-defaulting of an unannotated binder; (2) a property
    that writes one module's interface from a cold session and from a warm one and compares;
    (3) either make the bytes load-order-independent or state in `ei-diff.sh`'s header that
    both sides must be built in the same regime.

E4. **`sbt core/test` was INTERMITTENT — `TestInterfaceKey` flipped `ermine.loadInSeries` process-wide
    for ~16 ms and the series loader asks for the sourceless `Test`.**  FIXED 2026-09-09 (LSP Stage 3
    item 6.0; `tracker/loopmodel/LSP3-6.0-HYGIENE.md`, review `LSP3-6.0-REVIEW.md`).  The title and
    "Mechanism" paragraph below are the ORIGINAL, WRONG hypothesis, kept for the record: no dep-cache
    interaction is involved and no `loadedModules` key is ever removed.  Real mechanism: one property
    set `ermine.loadInSeries=true` with `System.setProperty` for 14-28 ms; `Session.loadModules`
    re-reads the flag per call; `loadModulesInSeries` does not subtract `s.loadedModules`; every
    fixture import map names `Test`, seeded as loaded with no source file — so whichever concurrent
    property was loading died with `Module not found: 'Test'` (deterministic under the flag: TestLower
    28/28; rate ~0.43 deaths per full run, matching one failure in two).  Fix, test-side only: the
    property calls `Session.loadModulesInSeries` directly (same assertion); `withProps` refuses any
    property not read once at class init.  Three full `core/test` runs 943/943 (1,533 s / 1,463 s /
    1,673 s), pinning recipe 132/132 x4 post-fix.  Acceptance criterion (1) below was therefore the
    wrong fix and was NOT done; (2) was met with three runs, not ten; (3) see GATE-POLICY.  Follow-up
    on the loader itself: E5.

    Opened 2026-09-09 by the F4 review (R-1).  Two full runs of the SAME tree: run 1 was
    `Total 943, Failed 0, Errors 1, Passed 942` (1,453 s), the error being
    `TestLower :: "3.4a.negation applies primNeg to the whole chain" — scalaparsers.Death:
    Module not found: 'Test'`; run 2 was `943 / 943, 0 failed, 0 errors` (1,356 s).  It does
    not reproduce in isolation (`TestLower` alone 2× = 28/28; `TestLower` with
    `TestInterfaceConcreteRow` 2× = 31/31), and it is not the F4 parser change — `TestLower`
    exercises the lowering pipeline, not the interface grammar.

    *Mechanism.*  `TestNewPipeline`, `TestLower`, `TestTolerantCheck`, `TestTolerantRead`,
    `TestStage1Pins` and `TestEditorBuffers` use `Session.depCache` / `Session.loadModules`
    WITHOUT taking `ErmineFixture.literalLock`, while the interface suites clear the
    process-global dep cache under it.  `ErmineFixture.baseEnv`'s dynamic `Test` module is
    what goes missing.  This is stage S5's hazard (`S5-HYGIENE.md`), not F4's: F4's suite is
    on the correct side of the discipline (it holds the lock across staging, both loads and
    every `depCache.clear()`), but it holds it ~85 s per run and clears the cache five times,
    which LENGTHENS the window rather than opening it.  Locking harder in the compliant
    suites cannot close it — the six offenders never take the lock at all.

    *Why it matters.*  A gate that is red one run in two is a gate nobody can use, and the
    Tier 2 line "`sbt core/test` in full" presumes determinism.

    *Acceptance criteria.*  (1) Make the six suites take `ErmineFixture.literalLock` around
    anything that touches `depCache`/`loadModules`, or give each its own dep cache; (2) ten
    consecutive full `core/test` runs green; (3) the quarantine list in
    `tracker/GATE-POLICY.md` updated to say the suite was intermittent and is not any more.

E5. **`Session.loadModulesInSeries` and `Session.loadModules` disagree on already-loaded modules.**
    Filed 2026-09-09 from E4.  The parallel schedule subtracts `s.loadedModules` before asking the
    loader (`moduleNames.toSet &~ loaded`); the series schedule asks for every name it is given.  For a
    module that is in `loadedModules` with no source file — `Builtin`, seeded by shipped code
    (`SessionState.scala:104`), and the test fixtures' `Test` — the series schedule dies with
    `Module not found`.  Not a live bug today: no non-test caller passes a sourceless loaded module
    (`bin/ermine`, the REPL, `ei-diff.sh --batch`, `corpus-run.sh`, `perf-bench.sh` name real files;
    `Session.load` short-circuits on `loadedFiles`), but the two schedules should agree.
    *Fix.* `for (m <- moduleNames if !s.loadedModules.contains(m)) load(...)` in `loadModulesInSeries`.
    *Tier* (LSP3-6.0 review R-7): shipped loader behaviour, so Tier 2 (`core/test` alone) plus Tier 1's
    `ei-diff.sh --batch` sweep with `-Dermine.loadInSeries=true` on BOTH sides and `g1-validate.sh`
    (the G1 oracle runs in series).  Not scheduled; a one-line change when a Tier-2 commit is due anyway.

E6. **Type errors inside an unannotated lambda are blamed at the APPLICATION, not the offending subterm.**
    Filed 2026-09-10 from LSP Stage 3 item 6.1(a), the do-anchor blame gap (report
    `tracker/loopmodel/LSP3-6.1-DIAGNOSTICS.md` §(a), review `LSP3-6.1-REVIEW.md` §2 — refutation attempted,
    ACCEPTED confirmed).  `Subst` is purely bottom-up: `inferType`'s `App` case (~:914) infers the argument and
    `subsumeType`s it against the function's domain (~:527); `typeCheck` is infer + subsume too, so no expected
    type is ever pushed into a `Lam`.  The do-anchor gap (`TestStage1Pins` "a type error inside a do block
    anchors on the bind's rhs", line 1 not line 2) is one instance; `g (w -> w && True)` is the general one; an
    INTRINSIC inner clash is blamed inside already (fixture `DoInner.e` 8:27).  *Fix.* A checking-mode rule for
    `Lam` (bind the pattern at the expected domain, check the body against the expected codomain), used by `App`
    when the argument is a syntactic lambda.  *Scope.* Moves the position and sometimes the wording of every such
    refusal: `tracker/repl-tests` goldens, the two `TestStage1Pins` anchor pins and the corpus batch verdict TEXT
    must be re-cut — Tier 2 + goldens, its own item, NOT a diagnostics-debt item under frozen batch semantics.
    An editor-only re-blame was judged (review) implementable without touching `Subst` but is the same rule
    written a second time, 1-2 days, and was declined.  Not scheduled.

E7. **The editor's import-failure suppression rule covers term names only (operators and type names still
    cascade).**  Filed 2026-09-10 from LSP Stage 3 item 6.1(b) (review R2/R3).  While an import has failed to
    load, `Resident.checkFile` withholds undefined-term and "unchecked" NOTES — but a missing module also costs
    (i) three READ diagnostics per use of an operator it would have supplied (`unknown operator` from `Reassoc`,
    then `ill-formed expression` and `error node` from `Lower`) and (ii) one `undefined type` note per type name
    (that note carries no `spelling`, the flag the rule keys on).  Evidence: `OpCascade.e`, `TypeCascade.e`,
    `BigCascade.e` in the 6.1 review's scratch directory (recreate from the review report if gone).  *Candidate
    shape.* Tag the read diagnostics whose head is an unresolved operator and the type-phase notes for unresolved
    type names with a flag (never by matching rendered text) and withhold them the same way while an import
    failed.  *The hard part is policy, not plumbing:* the same three diagnostics are exactly right for a mistyped
    operator in a file whose imports are all fine, so the tag must distinguish "unknown because a module did not
    load" from "unknown".  Also recorded: narrowing by an explicit `import X using {...}` list was available and
    DECLINED in 6.1 (an open import has no list; a rule that narrows only sometimes is harder to state and predict).
    Editor path only; Tier 0.  Not scheduled — a Stage 3/4 item if a real session shows the cascade hurts.

E8. **Parser columns are tab-expanded to 8-column stops, so every editor range on a tab-indented line is in
    the wrong units.**  Filed 2026-09-10 from LSP Stage 3 item 6.3 (report `tracker/loopmodel/LSP3-6.3-REFS.md`
    §12; found by the new corpus property classifying every occurrence's source extent).  `Pos.bump` advances the
    column to the next multiple of 8 on a tab; LSP positions count UTF-16 code units, so a diagnostic, a definition
    target, a hover hit-test, a highlight or a rename range on a line with leading tabs lands right of the real
    text by 7 per tab (`core/examples/GridExample.e` is the corpus instance; 6 of 71,248 occurrences).  6.3 made
    rename REFUSE a name behind a tab (`Definitions.nameExtent` non-exact) and `Lines.locate` walk by the parser's
    rule so the classification is right; nothing else was corrected.  *Fix.* Either convert at the LSP boundary
    (the server knows the line text: map parser columns back to character offsets in `Diagnostics`/`Definitions`
    once, in one helper every range goes through) or stop expanding tabs in `Pos` — the latter changes every
    batch report's column on tab-indented lines (REPL goldens, corpus verdict text) and is Tier 2 + goldens.
    Recommended: the boundary conversion, editor path only, Tier 0.  Not scheduled; small.

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

D3. **`TestConstraints.disjunction sound` never checks anything: generator starvation.** `disjunctionGen` draws
    seven field sets and seven variable valuations independently, so the three partitions' parts overlap and the
    `satisfies` guard discards every sample ("gave up after 0 passed tests, 501 discarded" in every recorded run;
    `tracker/06-tests.md`). The rule under test, `Constraints.disjunction`, ships OFF (`GenRules.disjRule`).
    QUARANTINED 2026-09-08 behind `-Dermine.test.disjunction=true` (gate policy) so the suite's green means green.
    **Fix:** draw one pool of fields and partition it among A/B/C/D/E/F/G, and valuations disjoint from the fields
    and each other; acceptance = the property PASSES 100 samples with the guard discarding < 50 %.
