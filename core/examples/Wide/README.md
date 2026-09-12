# `core/examples/Wide` — generic helpers over wide tables

Ten self-contained Ermine reports over **wide** fact tables — twenty to
thirty-six columns each — plus one shared library, `Helpers.e`, a module of
machine-checked signature equivalences, `Signatures.e`, and three negative
examples in `shouldfail/`.  (`Corrected.e`, the tenth, is narrow on purpose: it
is a signature control, not a wide report.)

`core/examples/Ai` is about **trees**: drilldowns, hierarchies, date-range
calendars. This directory is about **width**. Its subject is the three report
steps a wide table needs and a narrow one does not:

* **window functions** — rank, dense rank, row number, n-tile, running total,
  moving average, share of a partition total;
* **pivots** — turning the values of a key column into columns;
* **unpivots ("melt")** — the same move backwards.

Between them these are the *existential-generating* corner of the standard
library: helpers whose signatures **mint row variables the caller never writes
down**. `pivot`'s identity row `i` and `window`'s row `w` are the two clearest
cases, and before this directory existed neither appeared in any example that
did real work (`Relation.Pivot` had one toy, `PivotTest.e`; `Relation.Windowed`
had none at all).

Every file here type-checks. Load the library first — the examples import it:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    bin/ermine core/examples/Wide/Helpers.e $(ls core/examples/Wide/*.e | grep -v 'Helpers\.e')

or, one at a time,

    bin/ermine core/examples/Wide/Helpers.e core/examples/Wide/Leaderboard.e

## The examples

Check time is the module's own, excluding the ~13 s standard-library boot; two independent
per-file sweeps on 2026-09-07, one JVM per file, `-XX:ActiveProcessorCount=2`, at the adopted
row-solver defaults, on a machine that was also building two sibling example corpora — so both
figures are upper bounds and the spread between them is the contention.

| file | subject | fact columns | joined row | what it exercises | check |
|---|---|---|---|---|---|
| `Helpers.e` | the library | — | — | 24 row-polymorphic helpers, all with explicit signatures | 0.33 / 0.42 s |
| `Leaderboard.e` | esports season | 30 | 38 | five window solves — rank, dense, row-number, n-tile, top-N — over one wide row; a two-column sort | 0.64 / 1.10 s |
| `SalesLedger.e` | order lines | 27 | 35 | **two pivots**, by period and by product line; a four-deep `Fulcrum`; legends pinning pivoted column order | 1.17 / 1.18 s |
| `TrialBalance.e` | general ledger | 21 | 27 | **framed windows** — running balance and a three-posting trailing mean; `melt2` on the full 27-column row | 0.49 / 0.47 / 0.48 s |
| `RevenueShare.e` | subscriptions | 21 | 26 | share of total at **two levels**, written both as one `share` call and as `windowTotal` + a division | 0.53 / 0.56 s |
| `SurveyPanel.e` | survey waves | 20 | — (never joined) | the **round trip**: `melt4` to key/value, aggregate, `pivotBy` back to wide, with four profile columns kept in the identity so the analysis can group by country | 0.47 / 0.29 / 0.34 s |
| `WardRoster.e` | hospital shifts | 24 | 30 | **four helper calls chained**, each on the row the last one minted; `withDerived2`/`withDerived3` | 2.13 / 2.25 s |
| `BranchDeposits.e` | bank deposits | 22 | 27 | `lookupLatest` against **two calendars** that share no dates; moving average; latest-per-key | 0.70 / 0.57 s |
| `MediaSpend.e` | marketing spend | 23 | 26 | the **concise** pivot spelling (`pivotOnRow`), and the same pivot **with defaults** so the row can be summed | 0.60 / 0.52 s |
| `ClaimsExperience.e` | insurance claims | **36** | **43** | the widest row in the corpus: three ratios in one call, three windows, a defaulted three-way pivot, and the tree's widest `melt3` | 2.60 / 2.83 / 2.23 s |
| `Corrected.e` | the corrected `melt` signatures, called | 4 / 5 | — | the POSITIVE control for stage S3b: `melt2` and `melt3Simple` at a key column that is NOT one of the melted columns, which is what the constraint the two signatures gained (`r | key`) asks for.  Both evaluate to a `Success` whose header is the declared row; `melt2 fa vf fa fb r`, which the old signature accepted, is the negative | 0.4 s |
| `Signatures.e` | the helpers' own types | — | — | four equivalence proofs: `RUnion2` **is** its three-constraint lattice (both directions); `rankWithin`'s five published ≡ the four written (both directions); `melt3`'s 22 inferred ≡ 20 after dedup, and 3 when written by hand (a SPECIALISATION, not an equivalent -- and three since stage S3b, the third being the `r | key` the hand-written pair forgot); `withDerived2`'s eight ⊨ four | 0.18 s |

`shouldfail/` holds three modules that must NOT compile, with their diagnostics
recorded verbatim in `shouldfail/RESULTS.md`: a pivot whose key column is also
its value column, a window partitioned by a column the relation has not got, and
a running total ordered by the column it accumulates. Each is rejected in 0.05 s.

## `Helpers.e` — what is in it

| group | helpers |
|---|---|
| sorts | `asc`, `desc`, `thenBy` |
| ranking windows | `rankWithin`, `denseWithin`, `rowNumberWithin`, `nTileWithin`, `topNWithin` |
| framed windows | `runningTotal`, `movingAverage` |
| partition totals | `windowTotal`, `share` |
| derived columns | `withDerived2`, `withDerived3` |
| pivots | `startPivot`, `pivotColumn`, `pivotBy`, `pivotOnRow`, `pivotOnRowWithDefault`, `pivotByWithDefault` |
| unpivots | `melt2`, `melt3`, `melt4` |
| key lookup | `latestPerKey` |

Every one carries an explicit signature and a doc comment saying which row
constraint it adds and why. The signatures are the documentation: `rankWithin`'s
`w <- (k, s)` is the sentence "the window's columns are the partition columns
together with the sort columns", and `pivotBy`'s `s <- (i, p)` is "the wide row
is the identity columns together with the produced ones".

## Seeing the numbers

`render` does not exist in this repository (see below), so the way to see what one of these
reports actually computes is to compile its relation to SQL and run it:

```
tracker/tools/sql-render.sh tracker/tools/wide-render-probe.e /tmp/wide-render
cat /tmp/wide-render/out/q_leader_rank.txt
```

That dumps every report relation through the shipped scanners, rewrites the MS SQL dialect to
SQLite where a window function forces it, and executes each query against an in-memory SQLite
database. Fifteen of the twenty-seven relations probed come back as real tables; the rest hit
the three limits in the next section. Section 6 of `tracker/loopmodel/E1-EXAMPLES.md` prints
them.

## Three things worth knowing before you extend this directory

### 1. The row-constraint cliff has moved

`Ai/README.md` records a measurement that shaped `Ai/Common.e`: a helper whose
signature bundled a `RUnion3` (from `if`) with a `RUnion2` (from `combine`)
**did not finish**. That was measured before the row-solver defaults adopted on
2026-09-05 (`-Dermine.rowSound`, `dequeuePolicy=smallcanon`, `solveBudget=20000`).

Re-measured on 2026-09-07 on the same module, at the new defaults, the bundled
form **finishes**, in 1.30–1.51 s against the inline form's own 1.05–1.46 s —
see section 5 of `tracker/loopmodel/E1-EXAMPLES.md` for the numbers and the
reproduction.

The advice survives the measurement, but with a much smaller multiplier than a
first reading of the group's check times suggests. The **controlled** comparison
is the one above, where bundling is the only thing that changes, and it says
**1.2×** (1.28 s against 1.06 s); on a nine-column module it is about 2×. The
two modules here that use `withDerived2`/`withDerived3` are indeed the two
slowest, but they also carry the widest row, the most window helpers and the
longest helper chain, so that comparison measures four things at once and should
not be read as the cost of bundling. Bundling is no longer *fatal* and is not
expensive; it is still the thing to reach for last, because the signature it
publishes is the one a reader has to understand.

### 2. Two runtime limits you will hit before the type system stops you

Everything in this directory type-checks. Two things cannot be **run** in this
repository, and both are recorded in full in section 7 of
`tracker/loopmodel/E1-EXAMPLES.md`:

* **`Relation.Pivot.pivot` panics when the relation is forced**, with
  `Panic: unexpected runtime value in Native.Record.scalaRecord# - MapView(<not computed>)`.
  It is a Scala 2.13 collection regression (`mapValues` now returns a lazy
  `MapView`, and the pattern that consumes it expects a `Map`), not anything
  about the row types. `Relation.Predicate.all` goes the same way, for the same
  reason. Every pivot in this directory is written the way the library intends;
  none of them work around it.
* **Window functions compile to real SQL only through the MS SQL emitter.**
  Every other emitter — SQLite, MySQL, Postgres, Vertica — inherits
  `SqlEmitter.emitOver`'s placeholder and emits
  `TODO I don't yet know how to play … over …` where the `OVER` clause should be.

Neither affects type-checking, which is what these examples are for; both affect
what you can demonstrate.

### 3. Three binding names are defined twice in this directory

The README above tells you to load all ten modules at once, and if you do,
`ledger` (`SalesLedger` and `TrialBalance`), `accountDim` (`RevenueShare` and
`TrialBalance`) and `productDim` (`BranchDeposits` and `SalesLedger`) each name
two different relations. Nothing breaks — the batch load is clean and none of
the `>>` recipes in the module headers touches an ambiguous name — but typing
`:type ledger` in such a session answers `undefined term` rather than reporting
an ambiguity, which is confusing. Load one module at a time, or qualify.

### 4. `single` and `empty` are ambiguous — use `asc` / `desc`

`Relation.Row` and `Relation.Sort` both export `single` and `empty`, and
`Prelude` re-exports both modules. `Helpers.e` therefore defines `asc`, `desc`
and `thenBy`, which name the sort side unambiguously, and every example uses
them. Rows are still written with the brace syntax, `{teamName, division}`.
